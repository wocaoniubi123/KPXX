// 收藏 / 播放记录的「封面本地副本」（★ 2026-11-22 用户拍板 ✅）
//
// 为什么需要：这两个列表里存的是"加入那一刻的封面 URL"快照。站点换域名、换路径、
//   甚至那部片下架 ⇒ 旧 URL 永久失效 ⇒ 列表只剩灰块（用户实测过多次）。
//
// 做法（与封面 URL **解耦**）：
//   · 以**这条内容**为 key（`pin://站点|详情路径`），把封面明文字节存进已有的
//     `ImageDiskCache`（复用它的 FNV-1a 文件名、容量上限、落盘/读取实现，零新依赖）
//   · 列表显示时先读本地副本（同步、亚毫秒）⇒ 命中就直接画，不再依赖网络/站点是否还在
//   · 没命中就照旧用远程 `FetchedImage` 显示，并**顺手**把这次拿到的字节存一份（[pin]）
//   ⇒ 只要这张图**曾经显示成功过一次**，以后站点怎么变都不会再空白
//
// ⚠️ 不改 FavoriteItem / PlayRecord 的 JSON 结构，不加字段 ⇒ 老数据零兼容成本 ✅
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

import 'fetched_image.dart';
import 'favorites.dart'; // dropIfUnused：判断"收藏里还在不在用"
import 'settings.dart'; // PlayHistory（判断"播放记录里还在不在用"）

class CoverPin {
  CoverPin._();

  /// 持久目录（**与应用其它"数据"同一 base**：下载页用 `Documents/downloads`、
  /// 背景图用 `Documents`、这里用 `Documents/kpxx_covers`）
  /// ⚠️ 手机端对应 iOS `Documents/`、Android `…/app_flutter/` —— 都是**持久**目录，
  ///   不会被系统当临时文件清掉（对照：`ImageDiskCache` 用的是 `getTemporaryDirectory()`，
  ///   那是"缓存"，会被磁盘清理和 LRU 淘汰，**不能**用来存收藏封面）。
  static Directory? _dir;

  /// 启动时 awat 一次（两个入口各一行）⇒ [local] 之后可以同步读
  static Future<void> init() async {
    if (_dir != null) return;
    try {
      final base = await getApplicationDocumentsDirectory();
      final d = Directory('${base.path}/kpxx_covers');
      if (!await d.exists()) await d.create(recursive: true);
      _dir = d;
      if (AppSettings.i.logConsole) {
        debugPrint('[COVER] 本地封面目录 = ${d.path}');
      }
    } catch (_) {
      _dir = null; // 拿不到目录 ⇒ 整块静默失效（照旧走远程 URL）
    }
  }

  /// url → 稳定文件名（FNV-1a，与 `ImageDiskCache._keyOf` 同一算法，不依赖 hashCode）
  static String _keyOf(String s) {
    var h = 0x811c9dc5;
    for (final c in utf8.encode(s)) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// 本地副本的 key（**按内容身份**，不是按封面 URL —— 这是关键）
  static String keyOf(String site, String url) => '$site|$url';

  static File? _fileOf(String site, String url) {
    final d = _dir;
    if (d == null || site.isEmpty || url.isEmpty) return null;
    return File('${d.path}/${_keyOf(keyOf(site, url))}.img');
  }

  /// 同步取本地副本（列表 build 里用；没 init 过 / 没存过 ⇒ null，不抛）
  static Uint8List? local(String site, String url) {
    final f = _fileOf(site, url);
    if (f == null || !f.existsSync()) return null;
    try {
      final b = f.readAsBytesSync();
      return b.isEmpty ? null : b;
    } catch (_) {
      return null;
    }
  }

  /// 正在存的 key（防同一行被 build 多次时并发重复抓同一张图）
  static final Set<String> _inflight = <String>{};

  /// 删副本 —— **但前提是这条内容已经不被任何一边引用了**。
  ///
  /// ★ 2026-11-22 用户要求：收藏/播放记录点 X、或点清空时，本地副本要一起清掉。
  ///   收藏与播放记录**共用同一份副本**（key 都是 `站点|详情路径`）⇒ 只要还有一边在用就不能删，
  ///   否则会出现"删了收藏，播放记录那条也变空白"。
  static void dropIfUnused(String site, String url) {
    if (Favorites.i.find(site, url) != null) return; // 收藏还在用
    if (PlayHistory.i.find(site, url) != null) return; // 播放记录还在用
    drop(site, url);
  }

  /// 删掉这条内容的本地封面副本（不判断别的引用；一般用 [dropIfUnused]）
  static void drop(String site, String url) {
    final f = _fileOf(site, url);
    if (f == null) return;
    try {
      if (f.existsSync()) {
        f.deleteSync();
        debugPrint('[COVER] 已删副本 $site $url');
      }
    } catch (_) {
      // 静默：删不掉也不算错误（下次同名会覆盖）
    }
  }

  /// 把当前封面存成本地副本（fire-and-forget；已有副本就直接返回）
  /// ⚠️ 走 [FetchedImage.fetchDecoded]：下载 → 按站点规则解密 → 拿到**明文**再落盘
  ///   （直接存密文的话 Flutter 解码会失败，见 `download_manager.dart:297` 那条实测）
  static void pin(String site, String url, String coverUrl) {
    if (site.isEmpty || url.isEmpty || coverUrl.isEmpty) return;
    if (local(site, url) != null) return; // 已有副本，什么都不做
    final k = keyOf(site, url);
    if (!_inflight.add(k)) return; // 已在存，别重复抓
    unawaited(() async {
      try {
        await init(); // 幂等：万一入口没 await 过
        final f = _fileOf(site, url);
        if (f == null) return;
        final bytes = await FetchedImage.fetchDecoded(coverUrl);
        if (bytes == null || bytes.isEmpty) return;
        await f.writeAsBytes(bytes, flush: false);
        if (AppSettings.i.logConsole) {
          debugPrint('[COVER] 已存副本 $site $url ${bytes.length}字节');
        }
      } catch (_) {
        // 静默：存副本失败不影响显示（这次仍走远程 URL）
      } finally {
        _inflight.remove(k);
      }
    }());
  }
}
