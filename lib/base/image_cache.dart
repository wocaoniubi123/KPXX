import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// **图片的磁盘缓存**（`FetchedImage` 用 ✓）—— 与 `video_cache` 同一套写法 ✓：
/// `.part` 写完再改名 ✓、LRU 按"最后修改时间"清 ✓、**全程静默** ✗（失败=照旧走网络 ✓）。
///
/// ⚠️ 为什么需要它（实测依据 ✓）：`fetched_image.dart` 原来**只有内存缓存** ✓
/// （`_cache` 静态 Map + `_maxCache=400` ✓）→ 进程一结束全没了 ✗ → 冷启动进首页/详情/短片
/// 都要**重新下载 + 重新解密** ✗；而站点图是 AES-CBC 密文，解密还**丢到后台 isolate** ✓
/// （`fetched_image.dart:147-150` ✓）→ 单页几十张图就是几十次"下载 + isolate 解密" ✗。
///
/// ⚠️ **存的是解密后的明文** ✓（不是密文 ✗）—— 理由：
///   ① 密文要在**每次命中**时再解一次（`compute` isolate ✓）→ 省下的正是最贵的那步 ✗；
///   ② AES-CBC 是一比一 padding ✓ 明文/密文**体积几乎相同** ✓ → 存密文并不省空间 ✓；
///   ③ 目录是 App **私有**目录 ✓，与 `video_cache` 存明文视频同一性质 ✓。
///
/// ⚠️ **key 就是 url 本身** ✓（哈希成文件名 ✓）—— 依据：`fetched_image.dart:124-137` ✓
/// 请求头**只由 url 推导** ✓（UA 写死 ✓、`Referer` = url 自己的域名 ✓、`Accept` 写死 ✓）
/// → 同一个 url 在任何站点/任何页面拿到的字节都一样 ✓ → **不需要**把站名混进 key ✓。
class ImageDiskCache {
  ImageDiskCache._();

  /// 单例（全局一个目录/一份清理 ✓）
  static final ImageDiskCache i = ImageDiskCache._();

  /// 保留的图片个数上限（与内存缓存上限保持一致 ✓，见 `fetched_image.dart:64` ✓）
  static const int maxFiles = 400;
  /// 目录总量上限（图片都很小，60MB 兜底 ✓）
  static const int maxTotalBytes = 60 * 1024 * 1024;
  /// 半截 `.part` 的最长存活时间（App 被杀留下的残渣 ✓）
  static const Duration partTtl = Duration(hours: 1);

  Directory? _dir;

  /// 建目录 + 清一次 LRU ✓（**幂等** ✓：目录已建就立刻返回 ✓）
  Future<void> init() async {
    if (_dir != null) return;
    try {
      final base = await getTemporaryDirectory();
      final d = Directory('${base.path}/kpxx_img_cache');
      if (!await d.exists()) await d.create(recursive: true);
      _dir = d;
      await _prune();
    } catch (_) {
      _dir = null; // 拿不到目录 → 整块缓存静默失效 ✓（照旧走网络 ✓）
    }
  }

  /// **同步**取一张（命中返回明文 ✓，没有返回 null ✓）。
  /// ⚠️ 同步读盘：只在"这一张不在内存缓存里"时走一次 ✓，文件都很小（几十~几百 KB ✓）
  /// → 亚毫秒级 ✓（换来的是首帧不必多等一个 async 往返 ✓）。
  /// ⚠️ 调用前应先 `await init()` ✓（没 init 过就直接返回 null ✓，不会抛 ✗）
  Uint8List? take(String url) {
    final dir = _dir;
    if (dir == null) return null;
    try {
      final f = File('${dir.path}/${_keyOf(url)}.img');
      if (!f.existsSync()) return null;
      final b = f.readAsBytesSync();
      return b.isEmpty ? null : b;
    } catch (_) {
      return null; // 静默 ✓
    }
  }

  /// 落盘（**fire-and-forget** ✓：调用方不用 await ✓、失败静默 ✓）
  void put(String url, Uint8List bytes) {
    if (bytes.isEmpty) return;
    Future(() async {
      try {
        await init();
        final dir = _dir;
        if (dir == null) return;
        final part = File('${dir.path}/${_keyOf(url)}.part');
        final done = File('${dir.path}/${_keyOf(url)}.img');
        await part.writeAsBytes(bytes, flush: true);
        await part.rename(done.path); // 整份写完才"变成"可读文件 ✓（原子 ✓）
        await _prune();
      } catch (_) {
        // 静默 ✓：没缓存上就是下次再下 ✓
      }
    });
  }

  /// LRU：清过期 `.part` + 按"最后修改时间"新→旧留，超条数/超总量就删尾 ✓
  ///（与 `video_cache._prune` 同一套口径 ✓：谁先撞线听谁的 ✓）
  /// B4（2026-10-05）：全扫目录很贵（每次 put / 下完一条都会调）⇒ 入口加两道闸 ✓
  ///   ① 已在跑 ⇒ 直接跳过（不排队、不叠加 ✓）；② 5 秒内跑过 ⇒ 跳过（节流 ✓）。
  ///   调用点与 _pruneNow 的函数体都**一字未动** ✓。
  bool _pruning = false;
  DateTime? _pruneAt;
  Future<void> _prune() async {
    if (_pruning) return;
    final now = DateTime.now();
    if (_pruneAt != null && now.difference(_pruneAt!) < const Duration(seconds: 5)) return;
    _pruning = true;
    _pruneAt = now;
    try {
      await _pruneNow();
    } finally {
      _pruning = false;
    }
  }

  Future<void> _pruneNow() async {
    final dir = _dir;
    if (dir == null) return;
    try {
      final entries = <MapEntry<File, DateTime>>[];
      final now = DateTime.now();
      for (final e in await dir.list().toList()) {
        if (e is! File) continue;
        DateTime m;
        try {
          m = await e.lastModified();
        } catch (_) {
          continue;
        }
        if (e.path.endsWith('.part')) {
          if (now.difference(m) > partTtl) {
            try {
              await e.delete();
            } catch (_) {}
          }
          continue;
        }
        entries.add(MapEntry<File, DateTime>(e, m));
      }
      entries.sort((a, b) => b.value.compareTo(a.value)); // 新 → 旧 ✓
      var total = 0;
      for (var n = 0; n < entries.length; n++) {
        final f = entries[n].key;
        var len = 0;
        try {
          len = await f.length();
        } catch (_) {}
        total += len;
        if (n >= maxFiles || total > maxTotalBytes) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// url → 稳定文件名（FNV-1a ✓，与 `video_cache._keyOf` 同款 ✓ —— 不依赖
  /// `String.hashCode` 的进程内实现 ✓，无需额外依赖 ✓）
  static String _keyOf(String url) {
    var h = 0x811c9dc5;
    for (final c in utf8.encode(url)) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}
