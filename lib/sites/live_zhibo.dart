// ★ 2026-10-24（用户要求）：**直播聚合站**（api.hclyz.com）—— 独立站点文件 ✅
//
// 数据来源（用户桌面 `yuncaidan.txt` = 同一批数据的 GBK 纯文本版；这里用 JSON 版）：
//   · 目录：`<base>json.txt`
//       { "pingtai": [ {address, xinimg, Number, title}, … ] }
//       address = 明细文件名（如 `jsonkawayi.txt`）· xinimg = 平台封面 · Number = 主播数（**实时变动**）
//   · 明细：`<base><address>`
//       { "zhubo": [ {address, img, title}, … ] }
//       address = **FLV 直链（已带 wsSecret/wsTime 签名，无需自己算）**
//
// 🛢️ 实测事实（2026-10-24，全部亲自请求核对过）：
//   · 平台共 **136 个**
//   · **3 个坏平台**：`土豪`/`九尾狐` 明细 404、`龙珠` 明细 0 字节 ⇒ **用户要求直接隐藏**
//   · `Number`（目录数）与实际主播数**经常差 10~26 个**（花蝴蝶 108 vs 实际 82 / 盘他 101 vs 87）
//     ⇒ 但用户明确"按当前目录数分组"，所以分组用它 ✅
//   · 主域名 `api.hclyz.com:81`、备用 `api.maiyoux.com:81` —— 两个实测都 HTTP 200、都是 136 个平台
//   · 作者给的"查新域名"渠道（eBay 那个页面）**已失效**（页面返回 "this user was not found"）
//     ⇒ 域名必须做成可配、失败要能兜底，不能写死当永久 ✅
//
// ⚠️ 本文件**只管数据与分组**，UI 在 `live_zhibo_page.dart`（独立文件、互不污染 ✅）。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../base/fetch.dart';
import '../config.dart';
import '../settings.dart';
import '../site_error_log.dart';

/// 直播数据接口的两个域名（主 → 备，用户拍板：**主域名首选、备用域名兜底** ✅）
const List<String> kZhiboApiHosts = <String>[
  'api.hclyz.com:81',
  'api.maiyoux.com:81',
];

/// 一个直播平台（目录里的一条）
class ZhiboPlatform {
  /// 平台名（`title`）
  final String name;

  /// 明细文件名（`address`，如 `jsonkawayi.txt`）
  final String file;

  /// 平台封面（`xinimg`）
  final String cover;

  /// 目录里的主播数（`Number`）—— ⚠️ **实时变动**，只用于**分组**，不用于"实时显示人数"
  final int number;

  const ZhiboPlatform({
    required this.name,
    required this.file,
    required this.cover,
    required this.number,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'n': name,
        'f': file,
        'c': cover,
        'd': number,
      };

  /// ★ 从**接口原始 JSON** 解析（字段名是接口的口径，不是本地短名 ☠）
  ///
  /// 🛢️ 实测接口原文（`json.txt`）：
  /// ```json
  /// { "pingtai": [ { "address":"jsonweishizhibo.txt",
  ///                  "xinimg":"http://cdn.gcufbd.top/img/weishi.jpg",
  ///                  "Number":"36", "title":"卫视直播" }, … ] }
  /// ```
  /// ⇒ `title`=平台名 · `address`=明细文件名 · `xinimg`=封面 · `Number`=主播数（**字符串形态**）
  static ZhiboPlatform? fromApi(Map<dynamic, dynamic> j) {
    final n = '${j['title'] ?? ''}'.trim();
    final f = '${j['address'] ?? ''}'.trim();
    if (n.isEmpty || f.isEmpty) return null;
    return ZhiboPlatform(
      name: n,
      file: f,
      cover: '${j['xinimg'] ?? ''}'.trim(),
      number: int.tryParse('${j['Number'] ?? ''}') ?? 0,
    );
  }

  static ZhiboPlatform? fromJson(Map<String, dynamic> j) {
    final n = '${j['n'] ?? ''}'.trim();
    final f = '${j['f'] ?? ''}'.trim();
    if (n.isEmpty || f.isEmpty) return null;
    return ZhiboPlatform(
      name: n,
      file: f,
      cover: '${j['c'] ?? ''}'.trim(),
      number: j['d'] is int ? j['d'] as int : int.tryParse('${j['d'] ?? ''}') ?? 0,
    );
  }
}

/// 一个主播（明细里的一条）
class ZhiboRoom {
  /// 主播名（`title`）
  final String name;

  /// **FLV 直链**（`address`，已带 `wsSecret`/`wsTime` 签名，直接用 ✅）
  final String url;

  /// 封面（`img`）
  final String cover;

  const ZhiboRoom({required this.name, required this.url, required this.cover});
}

/// 直播数据层：目录 / 明细 / 分组
///
/// ⚠️ **不走** `SiteFetcher`：那个底座是"`https://<站域名><path>`"的拼法（`base/fetch.dart:62`），
///   而这里的接口是 `http://<ip>:81/mf/xxx.txt`（**非 https、带端口、路径带前缀**）⇒ 自己发请求 ✅
class ZhiboApi {
  ZhiboApi({SiteFetcher? fetcher}) : _f = fetcher;

  /// 只用来拿共享 `http.Client`（iOS = NSURLSession）和 UA；为空也能工作
  final SiteFetcher? _f;

  /// 拉一个接口地址（主域名 → 备用域名 → 全部失败抛异常）
  ///
  /// [path] 形如 `json.txt` / `jsonkawayi.txt`（**不带前导斜杠**）
  Future<String> _get(String path) async {
    final client = _f?.client ?? Site.httpClient;
    final errs = <String>[];
    for (final h in kZhiboApiHosts) {
      final url = 'http://$h/mf/$path';
      try {
        final sw = Stopwatch()..start();
        final r = await client.get(
          Uri.parse(url),
          headers: {
            'User-Agent': Site.ua,
            'Referer': 'http://$h/',
            'Accept': 'application/json,text/plain,*/*;q=0.8',
          },
        ).timeout(const Duration(seconds: 12));
        // ⚠️ 空响应（0 字节）当失败：`龙珠` 就是这种（实测 HTTP 200 但文件 0 字节）
        if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
          if (AppSettings.i.logConsole) {
            debugPrint('[ZHIBO] 站请求 ${r.statusCode} len=${r.bodyBytes.length} '
                'ms=${sw.elapsedMilliseconds} host=$h file=$path');
          }
          return utf8.decode(r.bodyBytes, allowMalformed: true);
        }
        errs.add('$h:${r.statusCode}/${r.bodyBytes.length}B');
      } catch (e) {
        errs.add('$h:${e.runtimeType}');
      }
    }
    // 全部失败：写错误日志（与全站同一套记录器 ⇒ 错误日志页可见 ✅）
    final msg = '直播接口全部失败（主+备域名）：$path ⇒ ${errs.join(' | ')}';
    unawaited(SiteErrorLog.log('直播聚合', msg));
    throw Exception(msg);
  }

  /// 拉目录 → 平台列表（按 `Number` **降序**稳定排序，同数保持接口原顺序 ✅）
  Future<List<ZhiboPlatform>> catalog() async {
    final txt = await _get('json.txt');
    final j = jsonDecode(txt);
    final raw = (j is Map && j['pingtai'] is List) ? j['pingtai'] as List : const <dynamic>[];
    final out = <ZhiboPlatform>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final p = ZhiboPlatform.fromApi(e); // ★ 接口字段口径（title/address/xinimg/Number）
      if (p != null) out.add(p);
    }
    // 降序 + 稳定（同 Number 保持接口原顺序：Dart 的 List.sort **不保证稳定** ⇒ 自己带原始下标）
    final idx = <ZhiboPlatform, int>{};
    for (var i = 0; i < out.length; i++) {
      idx[out[i]] = i;
    }
    out.sort((a, b) {
      final c = b.number.compareTo(a.number);
      if (c != 0) return c;
      return (idx[a] ?? 0).compareTo(idx[b] ?? 0);
    });
    return out;
  }

  /// 拉某个平台的主播列表
  Future<List<ZhiboRoom>> rooms(ZhiboPlatform p) async {
    final txt = await _get(p.file);
    final j = jsonDecode(txt);
    final raw = (j is Map && j['zhubo'] is List) ? j['zhubo'] as List : const <dynamic>[];
    final out = <ZhiboRoom>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final url = '${e['address'] ?? ''}'.trim();
      final name = '${e['title'] ?? ''}'.trim();
      if (url.isEmpty) continue;
      out.add(ZhiboRoom(
        name: name.isEmpty ? '未命名' : name,
        url: url,
        cover: '${e['img'] ?? ''}'.trim(),
      ));
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// 分组（用户 2026-10-24 拍板）
// ---------------------------------------------------------------------------

/// 每个分类 tab 放多少个平台（用户：**四个 tab、每组 34 个** ✅）
const int kZhiboTabSize = 34;

/// 分类 tab 的名字（用户确认：就叫「直播平台1~4」✅）
const List<String> kZhiboTabNames = <String>[
  '直播平台1',
  '直播平台2',
  '直播平台3',
  '直播平台4',
];

/// **必须隐藏的平台**（用户拍板：直接隐藏 ✅）
///
/// 🛢️ 实测依据（2026-10-24 逐个请求核过）：
///   · `土豪`   ⇒ 明细 404
///   · `九尾狐` ⇒ 明细 404
///   · `龙珠`   ⇒ 明细 HTTP 200 但 **0 字节**（空文件）
/// 这三个点进去必然白屏 ⇒ 用户要求**不进列表** ✅
const Set<String> kZhiboHiddenNames = <String>{
  '土豪',
  '九尾狐',
  '龙珠',
};

/// 按用户口径把 136 个平台分 4 组：**先剔除隐藏项，再按降序每 34 个一组** ✅
///
/// ⚠️ 分组基于**整份目录**（136 个）先切 34/34/34/34，然后各组内**再去掉隐藏项** ✅
///   ⇒ 一旦有平台被隐藏，那一组的显示数量会少于 34（这是用户确认过的口径 ✅）
List<List<ZhiboPlatform>> groupZhibo(List<ZhiboPlatform> all) {
  final groups = <List<ZhiboPlatform>>[];
  for (var g = 0; g < kZhiboTabNames.length; g++) {
    final from = g * kZhiboTabSize;
    final to = (from + kZhiboTabSize).clamp(0, all.length);
    final slice = from >= all.length ? <ZhiboPlatform>[] : all.sublist(from, to);
    groups.add(slice.where((p) => !kZhiboHiddenNames.contains(p.name)).toList());
  }
  return groups;
}

/// 默认打开的平台名（用户拍板：**星宝贝** ✅）
///
/// ⚠️ 不用写死下标：目录按 Number 降序，`星宝贝` 实测是最高（109）⇒ 落在第 1 组第 1 个；
///   但接口数据会变 ⇒ 这里按**名字**找，找到就用、找不到退回"第一组第一个非空平台" ✅
const String kZhiboDefaultPlatform = '星宝贝';

/// 从分组里挑默认平台
ZhiboPlatform? pickDefaultZhibo(List<List<ZhiboPlatform>> groups) {
  for (final g in groups) {
    for (final p in g) {
      if (p.name == kZhiboDefaultPlatform) return p;
    }
  }
  for (final g in groups) {
    if (g.isNotEmpty) return g.first;
  }
  return null;
}
