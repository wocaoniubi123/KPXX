// ★ 2026-10-27（用户要求）：**PandaTV 直播站** —— 独立站点文件 ✅
//
// 数据源 = 用户提供的 `E:\desk-ai\panda直播.js`（Rex 模块），照它的协议重写：
//   · `GET <host>/player/list.json` ⇒ `{ list: [ {userId, userNick, title, thumbUrl,
//       isAdult, isPw, type, user, totalScoreCnt, bookmarkCnt, liveType, onAirType,
//       startTime, …}, … ] }`
//   · `GET <host>/player/list.m3u`  ⇒ 简易映射表：`#EXTINF:-1 ,<userId>,<昵称>` + 下一行 = 流地址
//   · 两表按 `userId` 合并；**不在 m3u 里的房间 = 无流**（脚本注释原文：「该主播不在 list.m3u 中（无流」）
//
// 🛢️ 实测事实（2026-10-27 本机真请求核对，**不是推断**）：
//   · 中转域名 `5721004.xyz` 走 Cloudflare；官方站 `pandalive.co.kr` 是真身（韩国 더블미디어 运营）
//   · 流是 **AWS IVS**（`playlist.live-video.net` + `cloudfront.hls.live-video.net`），不是 FLV
//   · 播放清单里有 `#EXT-X-MEDIA-SEQUENCE` 且**随时间滚动**、**无 `#EXT-X-ENDLIST`**
//     ⇒ 真·实时直播（实测延迟 3 秒）
//   · 🛢️ **`liveType` 有两种值**：`live`（实时）/ **`rec`（回放）** —— 实测 326 个房间里
//     `live` 300 个、`rec` 26 个 ⇒ 用户"感觉像录播"最可能就是点到了 `rec` 房间 ✅
//   · 🛢️ **请求头是硬要求**：清单只带 Referer 也 **403**，必须
//     `Referer + Origin` 同时带；**分片**不带 Origin 会返回
//     `403 origin required`（15 字节响应体，实测原文）
//
// ⚠️ 本文件只管数据；UI 在 `lib/panda_live_page.dart`（独立文件 ✅）。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../base/fetch.dart';
import '../config.dart';
import '../settings.dart';
import '../site_error_log.dart';

/// 直连域名（脚本 `PANDA_HOST`）
const String kPandaHost = 'https://5721004.xyz';

/// ★ 2026-10-27（用户要求：**主域名 + 备用域名都要**）：备用走脚本里那组代理的前缀拼法
///
/// 🛢️ 实测（2026-10-27，每个连测 3 次）：
/// ```
/// hubu.515355.xyz/proxy/?<url>   ⇒ 200 / 200 / 200   ✅ 唯一可用
/// flank / uae2 / pol / f00       ⇒ 400 / 400 / 400   ☠ 响应体 "Invalid target URL"
/// ce2                            ⇒ 500 / 500 / 500   ☠
/// ```
/// ⇒ **只上 hubu**：其余 4 个 400 + 1 个 500 是**固定失败**（不是偶发），
///   写进兜底链只会让每次失败多等 4 轮超时 ☠
///
/// 🛢️ 代理的**两个实测特性**（决定了代码怎么写）：
///   ① 拼法 = `https://<代理>/proxy/?<完整原始URL>`（`?` 后直接跟、**不能 URL 编码**：
///      编码后 hubu 返回 500/7 字节；`/proxy/<url>` 无 `?` 那种是错格式，hubu 返回 HTML 页）
///   ② 代理返回的 `list.m3u` 里，**流地址也已被改写成代理地址**
///      （`https://hubu.515355.xyz/proxy/?https://…cloudfront…`）⇒ 拿到什么就播什么
///   ③ 走代理的流 **不需要 Referer/Origin**（实测清单 + 分片全是 200，带不带都一样）
///      ⇒ 但代码照旧统一带，直连那条必须带，统一带不亏 ✅
const List<String> kPandaProxyHosts = <String>[
  'https://hubu.515355.xyz/proxy/?',
];

/// 所有可用入口（**直连恒为第一**，与脚本 `loadResource` 的同款口径 ✅）
List<String> get kPandaEntries => <String>[
      kPandaHost,
      for (final p in kPandaProxyHosts) '$p$kPandaHost',
    ];

/// 请求头（🛢️ **硬要求**，实测缺一个就 403）
const Map<String, String> kPandaHeaders = <String, String>{
  'Referer': 'https://www.pandalive.co.kr/',
  'Origin': 'https://www.pandalive.co.kr',
};

/// 桌面 Chrome UA（照脚本原口径）
///
/// ⚠️ 为什么不用全站 `Site.ua`（iPhone Safari）：脚本原作者用桌面 UA 测通，
///   换 UA 是否会触发站点拦截**未验证** ⇒ 照抄已验证的那一份 ✅
const String kPandaUA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

// ⚠️ 2026-10-27：三站共用的等待文案 `kLiveLoadingText` **不在这里** ✅
//   它已挪到 `lib/app_background.dart`（共享 UI 常量区）——
//   否则站点 A 要 import 站点 B（panda_live.dart），违反"站点独立文件管理"规矩 ☠

/// 一个直播间（list.json + list.m3u 合并后的一条）
class PandaRoom {
  final String userId;
  final String nick;
  final String title;
  final String cover;

  /// 流地址（`list.m3u` 里查到的那条；空 = 无流，不会出现在列表里）
  final String url;

  final bool isAdult;
  final bool isPw;

  /// ★ **回放**（`liveType == 'rec'`）—— 不是实时直播 ✅
  final bool isRec;

  /// 粉丝房（`type == 'fan'`）
  final bool isFan;

  final int userCnt;
  final int score;
  final int bookmark;

  const PandaRoom({
    required this.userId,
    required this.nick,
    required this.title,
    required this.cover,
    required this.url,
    required this.isAdult,
    required this.isPw,
    required this.isRec,
    required this.isFan,
    required this.userCnt,
    required this.score,
    required this.bookmark,
  });
}

/// 列表的一次完整抓取结果
class PandaCatalog {
  /// **只含有流的房间**（无流的点进去必然失败 ⇒ 不列出来 ✅）
  final List<PandaRoom> rooms;

  /// `list.json` 的原始条数 / 有流的条数（日志与空态说明用）
  final int total;
  final int playable;

  const PandaCatalog({
    required this.rooms,
    required this.total,
    required this.playable,
  });
}

class PandaApi {
  PandaApi({SiteFetcher? fetcher}) : _f = fetcher;

  /// 只为复用共享 `http.Client`（iOS = NSURLSession）
  final SiteFetcher? _f;

  /// 拉一个接口（**直连 → 备用代理**，全失败才抛异常）
  ///
  /// [path] 形如 `player/list.json`（不带前导斜杠）
  ///
  /// ⚠️ 入口由 [kPandaEntries] 给（直连恒为第一），返回**实际成功的那个入口**
  ///   —— 因为走代理时，`list.m3u` 里的流地址已经变成代理地址，
  ///   两个文件必须**从同一个入口拿**，否则会出现"列表来自代理、流来自直连"的混搭 ☠
  Future<({String body, String entry})> _get(String path) async {
    final client = _f?.client ?? Site.httpClient;
    final errs = <String>[];
    for (final entry in kPandaEntries) {
      final url = '$entry/$path';
      try {
        final sw = Stopwatch()..start();
        final r = await client.get(
          Uri.parse(url),
          headers: <String, String>{'User-Agent': kPandaUA, ...kPandaHeaders},
        ).timeout(const Duration(seconds: 15));
        if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
          if (AppSettings.i.logConsole) {
            debugPrint('[PANDA] 站请求 ${r.statusCode} len=${r.bodyBytes.length} '
                'ms=${sw.elapsedMilliseconds} ${entry == kPandaHost ? '直连' : '备域'} path=$path');
          }
          return (
            body: utf8.decode(r.bodyBytes, allowMalformed: true),
            entry: entry,
          );
        }
        errs.add('${_entryTag(entry)}:${r.statusCode}/${r.bodyBytes.length}B');
      } catch (e) {
        errs.add('${_entryTag(entry)}:${e.runtimeType}');
      }
    }
    final msg = 'PandaTV 接口全部失败（直连+备域）：$path ⇒ ${errs.join(' | ')}';
    unawaited(SiteErrorLog.log('PandaTV', msg));
    throw Exception(msg);
  }

  /// 日志用短名（不打完整代理 URL）
  static String _entryTag(String entry) =>
      entry == kPandaHost ? '直连' : '备域';

  /// `list.m3u` → `{userId: 流地址}`
  ///
  /// 格式（实测原文）：
  /// ```
  /// #列表说明,本站长期使用域名5721004.xyz | 主播列表手动更新时间：2026-10-27 00:30:24
  /// #主播数量：36
  /// #EXTM3U
  /// #EXTINF:-1 ,mscrew33,mscrew33(小团播-周二/六)
  /// https://ffdced10e5f6.usw24.playlist.live-video.net/v1/playlist/…
  /// ```
  /// ⇒ `#EXTINF` 里**第 2 段 = userId**，下一行 = 地址（与脚本 `_parseStreamMap` 同规则）
  static Map<String, String> parseStreamMap(String text) {
    final lines = text.split('\n');
    final map = <String, String>{};
    final re = RegExp(r'#EXTINF:[^,]*,([^,]+),');
    for (var i = 0; i + 1 < lines.length; i++) {
      final m = re.firstMatch(lines[i]);
      if (m == null) continue;
      final uid = m.group(1)!.trim();
      final url = lines[i + 1].trim();
      if (uid.isNotEmpty && url.startsWith('http')) map[uid] = url;
    }
    return map;
  }

  /// 拉一次完整目录（两份数据合并成房间列表）
  ///
  /// 🛢️ 关键约束：两个文件必须**同源**（要么都直连、要么都走代理）——
  ///   走代理时 `list.m3u` 里的流地址**已经被改写成代理地址**，
  ///   若是"json 走代理、m3u 走直连"混搭，列表和流会用两套基准，容易对不上 ☠
  ///   ⇒ 所以**先取 json 定入口，再按同一入口取 m3u**（顺序取，两次 RTT；简单且不会混搭 ✅）
  Future<PandaCatalog> fetch() async {
    final jr = await _get('player/list.json');
    final mr = await _getFrom(jr.entry, 'player/list.m3u');

    final j = jsonDecode(jr.body);
    final raw = (j is Map && j['list'] is List) ? j['list'] as List : const <dynamic>[];
    final streams = parseStreamMap(mr.body);

    final out = <PandaRoom>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final uid = '${e['userId'] ?? ''}'.trim();
      if (uid.isEmpty) continue;
      final url = streams[uid] ?? '';
      if (url.isEmpty) continue; // 无流 ⇒ 不列（点进去必然失败）
      final lt = '${e['liveType'] ?? ''}'.trim();
      final tp = '${e['type'] ?? ''}'.trim();
      out.add(PandaRoom(
        userId: uid,
        nick: '${e['userNick'] ?? ''}'.trim().isEmpty
            ? '未命名'
            : '${e['userNick'] ?? ''}'.trim(),
        title: '${e['title'] ?? ''}'.trim(),
        cover: '${e['thumbUrl'] ?? ''}'.trim(),
        url: url,
        isAdult: e['isAdult'] == true,
        isPw: e['isPw'] == true,
        isRec: lt == 'rec',
        isFan: tp == 'fan',
        userCnt: (e['user'] is num) ? (e['user'] as num).toInt() : 0,
        score: (e['totalScoreCnt'] is num) ? (e['totalScoreCnt'] as num).toInt() : 0,
        bookmark: (e['bookmarkCnt'] is num) ? (e['bookmarkCnt'] as num).toInt() : 0,
      ));
    }
    if (AppSettings.i.logConsole) {
      debugPrint('[PANDA] 目录入口=${_entryTag(jr.entry)} json=${raw.length} '
          '流=${streams.length} 可播=${out.length}');
    }
    return PandaCatalog(rooms: out, total: raw.length, playable: streams.length);
  }

  /// 从**指定入口**取（配对用 —— 保证两个文件同源）
  ///
  /// ⚠️ 失败**不再换入口**：既然 `list.json` 已经定了入口，m3u 也只能从这里取
  ///   （换入口会混搭）；抛出去由 `_load()` 显示重试 ✅
  Future<({String body, String entry})> _getFrom(String entry, String path) async {
    final client = _f?.client ?? Site.httpClient;
    final r = await client.get(
      Uri.parse('$entry/$path'),
      headers: <String, String>{'User-Agent': kPandaUA, ...kPandaHeaders},
    ).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
      final msg = 'PandaTV 接口失败（同源取）：$path ⇒ '
          '${_entryTag(entry)}:${r.statusCode}/${r.bodyBytes.length}B';
      unawaited(SiteErrorLog.log('PandaTV', msg));
      throw Exception(msg);
    }
    return (body: utf8.decode(r.bodyBytes, allowMalformed: true), entry: entry);
  }
}

// ---------------------------------------------------------------------------
// 排序（照脚本 `_applyFilterSort` 的 sort 档；★ 2026-10-27 用户要求：**取消分类 tab**，
// 只显示全部房间 ⇒ 脚本里的 type/adult/pw/fan 四个筛选已删 ✅）
// ---------------------------------------------------------------------------

/// 排序档：key 名照脚本 `sort` 的值
class PandaSort {
  final String label;
  final int Function(PandaRoom) value;
  const PandaSort(this.label, this.value);
}

const List<PandaSort> kPandaSorts = <PandaSort>[
  PandaSort('观众量', _pandaByUser),
  PandaSort('实时热度', _pandaByScore),
  PandaSort('关注量', _pandaByBookmark),
];

int _pandaByUser(PandaRoom r) => r.userCnt;
int _pandaByScore(PandaRoom r) => r.score;
int _pandaByBookmark(PandaRoom r) => r.bookmark;
