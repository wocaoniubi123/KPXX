// 野果短剧（yeguodj.com）—— **本站专属**的一切 ✅
//
// 站点：`yeguodj.com`（`www.` 会 301 回 apex ✅）。**竖版封面**短剧站（3:4 ✅）⇒ 档案里 `portraitCovers: true` ✅。
//
// ⚠️ 本站是**第二个"自管整页"的站点** ✅（第一个 = xhamsterlive ✅ —— 引 material 的写法照它 ✅）：
//   三主 tab（推荐 / 探索 / 排行榜）+ 分区行（每区 4 条 + 「查看更多 ›」）+ 5 组筛选胶囊 —— 全是站点专有版式 ✅
//   ⇒ 走 `SiteUi.sitePage()` ✅（底座里**唯一**使用点 = `home_page.dart:580` ✅ 那一句判断**不认站名** ✅ 一字不动 ☑️）。
//   ⚠️ 本站**不引 html/dom** ☑️（列表/详情都不在 DOM 里 —— 数据在 `__NUXT_DATA__` 那个 devalue **扁平数组**里 ✅
//      ⇒ 只用 `dart:convert` + 字符串定位 ✅），所以**不会**和 material 的 `Text`/`Key`/`Element` 撞名 ✅。
//
// ---- 口径（2026-10-08 本机复核 ✅ 真站实测，见每条后面括注）----
//  · 三 tab：推荐 / 探索 / 排行榜 ✅
//  · 推荐 = 6 个分区行（`rec-sweet-romance` 等 ✅；每行 4 条 + 「查看更多 ›」⇒ `/drama/<code>/` ✅）
//  · 探索 = 5 组筛选 ⇒ **路径式** `/explore/drama/<主题>-<设定>-<背景>-<时间>-<推荐>/`
//    （段序固定 ✅、`0` = 该组不选 ✅、全不选 = `/explore/drama/` ✅）
//  · 排行榜 = 周榜 `/rank/drama/` · 月榜 `/rank/drama/month/` ✅
//    （⚠️ `?type=month` 那条是坑 ☑️ 别用）；名次**照站上顺序** ✅（站上给 `rank_score` ✅ 不按播放量重排 ☑️）
//  · 详情 = **接口优先** `POST https://www.yeguodj.com/api.php/api/playlet/detail`（form 编码 ✅
//    AES-128-CBC/Pkcs7 响应 ⇒ 明文里再取 `.data` ✅）；失败**回落 SSR**（`<script id="__NUXT_DATA__">` ✅）
//    并**打错误日志** ✅（☑️ 不许静默）
//  · 播放 = `GET /drama/video/<video_id>/` ✅ —— **实测（2026-10-08）：这一页就带全集地址** ✅
//    （`episodeAll[]` 每项都有 `id/sort/video_url` ✅；同一部剧的第 1/2 集地址都在这一页里 ✅）
//    ⚠️ 而"按单集寻址"**不存在** ☑️（复核过：`/drama/video/<单集行id>/` 落通用页 ☑️、
//      `/drama/video/<剧id>/<集号>/` = 404 ☑️、`?episode_id=` / `?episode_sort=` / `?sort=` / `?ep=` 一律**照旧出第 1 集** ☑️）
//      ⇒ 所以本站的"每集现取"在 App 侧落成：**详情打开时抓一次播放页** ✅ ⇒ 按 `id`（回退 `sort`）把
//        `episodeAll[]` 的地址映射到**每一集** ✅（这正是站上的真实形态 ✅ —— 站方自己也是从这一页拿全集 ✅）；
//        第 1 集另有 `lazyUrl` 现取兜底 ✅（该页顶层 `video_url` **就是第 1 集** ✅ 实测吻合 ✅）。
//  · 封面是**加密图** ⇒ 直接用底座 `fetched_image.dart` ✅（key/iv 与本文件无关、两边**同一份** ✅ 零成本复用 ✅）
//
// ---- 日志（照 DEVLOG 顶部第七节 ✅）----
//  每个分支都有日志（成功也打 ✅）；**不打带 `auth_key` 的完整 URL** ☠（只打条数/命中的集号/耗时 ✅）。

import 'dart:convert';

// ⚠️ 本站要**自己画整页**（三 tab / 分区行 / 胶囊 / 榜单行）⇒ 必须 import material ✅
//   （只 import material、不 import html/dom ⇒ 不会撞名 ✅，同 xhamsterlive.dart 的注释 ✅）
import 'package:flutter/material.dart';
import 'package:encrypt/encrypt.dart' as enc;

import '../app_background.dart';
import '../app_bg.dart';
import '../base/fetch.dart';
import '../base/site_ui.dart';
import '../config.dart' show Site;
import '../detail_page.dart';
import '../fetched_image.dart';
import '../models.dart';
import '../settings.dart'; // ★ 诊断开关（`AppSettings.i.logConsole` ✅）；`debugPrint` 由 material 带入 ✅
import '../site_error_log.dart'; // ★ 列表请求非 200 时写公共错误日志 ✅（`SiteErrorLog.log` ✅）
import '../sites.dart'; // 本站档案 `kSite15` + `SiteTemplate.yeguodj` ✅（循环 import 本项目允许 ✅）

/// 野果短剧本站专属实现（取数走底座 [SiteFetcher] ✅）
class YeguoSite extends SiteUi {
  YeguoSite(this._f);

  final SiteFetcher _f;

  /// 详情接口固定走 `www.` 这个子域 ✅（站点数据里 `apiBaseURL = https://www.yeguodj.com/api.php` ✅）
  static const String _kApiHost = 'www.yeguodj.com';

  /// 详情接口路径（前端 JS 里那串 ✅ 照抄 ☑️ 不改）
  static const String _kApiPath = '/api.php/api/playlet/detail';

  /// 接口响应的 AES 参数（recon 从站点前端抠出的 ✅；**勿改** ☑️）
  static const String _kApiKey = '2acf7e91e9864673';
  static const String _kApiIv = '1c29882d3ddfcfd6';

  /// 详情接口那串固定表单体（除 `video_id` 外全部照抄站点前端 ✅）
  static const String _kOauthId = '7d05538c4b8a5e74e82f93c0dab0163c';

  static final enc.Encrypter _aes =
      enc.Encrypter(enc.AES(enc.Key.fromUtf8(_kApiKey), mode: enc.AESMode.cbc));
  static final enc.IV _iv = enc.IV.fromUtf8(_kApiIv);

  /// 详情「相关推荐」那块：**标题用真站叫法** ✅（真站就叫「猜你喜欢」✅）——
  /// 走底座槽位 `SiteUi.relatedTitle` ✅（默认空串 = 底座用「相关推荐」⇒ 其它站零变化 ✅）。
  @override
  String get relatedTitle => '猜你喜欢';

  /// 「猜你喜欢」版式 = **3 列 + 封面右下角角标** ✅（用户点名保留 ✅）——
  /// 走底座槽位 `SiteUi.relatedAsGrid` ✅；角标数据侧已给足（`Article.badge` = `9.4W播放` ✅）。
  @override
  bool get relatedAsGrid => true;

  // ===== 一、devalue 扁平数组（`__NUXT_DATA__`）=====
  //
  // ⚠️ 站点是 Nuxt SSR：页面里 `<script id="__NUXT_DATA__">` 放的是一段
  //   **devalue 扁平数组** —— 数字 = 下标引用 ✅，对象成员的值也是下标 ✅
  //   ⇒ 照 sim 那份实现（`sim/index.html` 的 `ygResolver` ✅）解析 ✅。

  /// 取出扁平数组；页面里没有就返回 null
  List<dynamic>? _nuxt(String html) {
    final k = html.indexOf('id="__NUXT_DATA__"');
    if (k < 0) return null;
    final s = html.indexOf('>', k);
    if (s < 0) return null;
    final e = html.indexOf('</script>', s);
    if (e < 0) return null;
    try {
      final j = jsonDecode(html.substring(s + 1, e));
      return j is List ? j : null;
    } catch (_) {
      return null;
    }
  }

  /// 下标解引用（递归；数字成员 = 下标 ✅；深度保护照 sim 的 14 层 ✅）
  Object? _deref(List<dynamic> a, Object? v, [int depth = 0]) {
    if (depth > 14 || v is! num) return v;
    final i = v.toInt();
    if (i < 0 || i >= a.length) return null;
    final t = a[i];
    if (t is List) return [for (final x in t) _deref(a, x, depth + 1)];
    if (t is Map) {
      return {
        for (final e in t.entries) '${e.key}': _deref(a, e.value, depth + 1),
      };
    }
    return t;
  }

  /// 找第一个"同时带这几个 key"的对象（本站各页的 payload 都靠这个定位 ✅ 同 sim 的 `ygFindIdx`）
  int _findObj(List<dynamic> a, List<String> keys) {
    for (var i = 0; i < a.length; i++) {
      final t = a[i];
      if (t is! Map) continue;
      if (keys.every((k) => t[k] != null)) return i;
    }
    return -1;
  }

  /// 定位对象并解引用成普通 Map
  Map<String, dynamic>? _obj(List<dynamic> a, List<String> keys) {
    final i = _findObj(a, keys);
    if (i < 0) return null;
    final o = _deref(a, i);
    return o is Map ? Map<String, dynamic>.from(o) : null;
  }

  // ===== 二、列表项（列表 / 分区 / 榜单 / 猜你喜欢 **同一套** ✅）=====

  /// 播放量角标（**列表口径** ✅）：≥1 万用站上 `play_count_text`（如 `38W` ✅），否则用原始数 ✅
  String _pct(int pc, String pct) {
    if (pc >= 10000 && pct.isNotEmpty) return pct;
    if (pc > 0) return '$pc';
    return pct;
  }

  /// 猜你喜欢角标（**另一套口径** ✅）：站上文本 + 「播放」后缀（如 `9.4W播放` ✅）
  String _likePct(int pc, String pct) {
    if (RegExp(r'^[\d.]+W$').hasMatch(pct)) return '$pct播放';
    final w = pc > 0 ? pc / 10000 : 0.0;
    return w > 0 ? '${w.toStringAsFixed(1)}W播放' : '';
  }

  /// 一条播放条目 → 卡片（站上字段：video_id / title / cover / play_count / play_count_text ✅）
  Article? _item(Map<String, dynamic> o, {bool like = false}) {
    final id = (o['video_id'] as num?)?.toInt() ?? 0;
    final title = '${o['title'] ?? ''}'.trim();
    if (id <= 0 || title.isEmpty) return null;
    final pc = (o['play_count'] as num?)?.toInt() ?? 0;
    final pct = '${o['play_count_text'] ?? ''}'.trim();
    return Article(
      title: title,
      url: '/drama/detail/$id/',
      cover: '${o['cover'] ?? ''}',
      meta: '', // 本站卡片**不显示时间** ✅（右下角只放播放量 ✅）
      badge: like ? _likePct(pc, pct) : _pct(pc, pct),
    );
  }

  /// 「列表对象」：payload 里同时带这几个 key 的那个对象 + 它的 `list` ✅
  ///
  /// 返回 (items, total)；找不到返回 null（调用方当失败 ✅ 不静默 ☑️）
  ({List<Article> items, int total})? _listObj(
      String html, List<String> keys, {bool like = false}) {
    final a = _nuxt(html);
    if (a == null) return null;
    final o = _obj(a, [...keys, 'list']);
    if (o == null) return null;
    final list = o['list'];
    if (list is! List) return null;
    final out = <Article>[];
    for (final it in list) {
      if (it is Map) {
        final one = _item(Map<String, dynamic>.from(it), like: like);
        if (one != null) out.add(one);
      }
    }
    return (items: out, total: (o['total'] as num?)?.toInt() ?? out.length);
  }

  // ===== 三、推荐页（6 个分区行）=====

  /// 首页推荐：6 个分区（`{code,title,item_total,items[]}` ✅）
  ///
  /// 看：解析出几个分区、每个分区几条 —— 0 个就是首页 SSR 结构变了（`code/items/item_total` 那套 ✅）。
  Future<List<YgSection>> homeSections() async {
    final sw = Stopwatch()..start();
    final html = await _f.text('/');
    final a = _nuxt(html);
    final out = <YgSection>[];
    if (a != null) {
      for (var i = 0; i < a.length; i++) {
        final t = a[i];
        if (t is! Map) continue;
        if (t['title'] == null ||
            t['code'] == null ||
            t['items'] == null ||
            t['item_total'] == null) {
          continue;
        }
        final o = _deref(a, i);
        if (o is! Map) continue;
        final code = '${o['code'] ?? ''}';
        final items = o['items'];
        if (!RegExp(r'^[a-z][a-z0-9-]{2,40}$').hasMatch(code) || items is! List) {
          continue;
        }
        final list = <Article>[];
        for (final it in items) {
          if (it is Map) {
            final one = _item(Map<String, dynamic>.from(it));
            if (one != null) list.add(one);
          }
        }
        out.add(YgSection(
          code: code,
          title: '${o['title'] ?? ''}',
          total: (o['item_total'] as num?)?.toInt() ?? list.length,
          items: list,
        ));
      }
    }
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 入口=推荐 分区=${out.length} '
          '每条=${out.isEmpty ? 0 : out.first.items.length} ms=${sw.elapsedMilliseconds}');
    }
    return out;
  }

  // ===== 四、分区页 / 探索 / 排行榜 =====

  /// **列表类 SSR 页**（分区页 / 探索 / 榜单 / 标签页）取 HTML：**本站单独放宽到 15 秒** ✅
  ///
  /// 依据（2026-10-08 ✅）：本站列表页全是 SSR HTML，而**底座超时是 8 秒**
  /// （`lib/base/fetch.dart:70` ✅）—— 同一页实测在 **2~8 秒**之间浮动
  /// （`/explore/drama/` 一次 7.93 秒 ☑️、复测 3 次都 200 · 1.8~2.2 秒 ✅；
  /// `/rank/drama/` 到过 10.7 秒 ☑️）⇒ **卡在超时线上**，稍一抖动就整批失败
  /// （真机表现 = `Exception: 所有域名均无法访问` ✅）⇒ 本站列表请求单独放宽到 **15 秒** ✅。
  ///   ⚠️ 域名照档案写死 `yeguodj.com` ✅（`kSite15.hosts` **只有这一个** ✅ ⇒ 与底座的域名轮换等价 ✅；
  ///      `www.` 会 301 回 apex ✅）。⚠️ **未加 `Referer`** ☑️ —— 照 `online_album_common.dart:568` 的先例 ✅。
  ///   ⚠️ 只覆盖**列表类** ☑️：详情接口（[_detailApi] ✅）与播放页**保持底座原样** ✅（它们不慢 ✅）。
  ///   ⚠️ 非 200 ⇒ **抛异常 + 写错误日志** ✅（☑️ 不静默、不假装空列表）；任何失败都**原样上抛** ✅
  ///      （只多两条日志 ✅ 不吞异常 ☑️）。
  ///
  /// 取证日志（2026-10-08 要求 ✅；两条都受 `AppSettings.i.logConsole` 守卫 ✅ ⇒ 关着时零开销 ✅，
  ///   打开时经 `main.dart` 的 `debugPrint` 接管进错误日志页 ✅）：
  ///   ① 请求**发出前**打**最终 URL** + 入口（含 `seg` ✅）⇒ 一眼看出是不是我们**拼错了** ☑️
  ///      （例：`seg` 没算成空 ☑️）；⚠️ 这几条列表 URL **不带 `auth_key`** ✅ ⇒ 与本站
  ///      "不打带 key 的完整 URL" 那条口径不冲突 ✅；
  ///   ② 失败时打**异常类名 + 原文 + URL** ✅ ⇒ 分辨 DNS / 连接被拒 / TLS / 超时
  ///      （此前只有包装过的"所有域名均无法访问" ☑️ 看不出是哪一种 ☑️）。
  Future<String> _listHtml(String path, String entry) async {
    final url = 'https://yeguodj.com$path';
    if (AppSettings.i.logConsole) {
      debugPrint('[SRC] ${_f.site.name} 入口=$entry url=$url'); // ① 请求前：最终 URL ✅
    }
    try {
      final r = await Site.httpClient
          .get(Uri.parse(url), headers: {'User-Agent': Site.ua})
          .timeout(const Duration(seconds: 15)); // ★ 本站列表 15 秒 ✅（底座 8 秒 ☑️）
      if (r.statusCode != 200) {
        // ☑️ 非 200 不静默：写错误日志 + 抛（调用方照旧显示失败态 + 可重试 ✅）
        final e = Exception('HTTP ${r.statusCode}');
        await SiteErrorLog.log(_f.site.name, '$entry ${e.toString()} url=$url');
        throw e;
      }
      return utf8.decode(r.bodyBytes);
    } catch (e) {
      if (AppSettings.i.logConsole) {
        debugPrint('[SRC] ${_f.site.name} 入口=$entry 失败 类型=${e.runtimeType} '
            '原文=$e url=$url'); // ② 失败：类名 + 原文 + URL ✅
      }
      rethrow; // ☑️ 行为原样：照旧抛给调用方（☑️ 不吞）
    }
  }

  /// 分区页 `/drama/<code>/`（站上**只有第 1 页** ☑️ 别承诺翻页 ☑️）
  ///
  /// 看：标题 + 条数 —— 0 条就是该分区当前没有内容，或 `title/module/list` 那套对象没找到。
  Future<({String title, List<Article> items, int total})> section(String code) async {
    final sw = Stopwatch()..start();
    final html = await _listHtml(
        '/drama/${Uri.encodeComponent(code)}/', '分区 code=$code');
    final a = _nuxt(html);
    var title = '';
    final out = <Article>[];
    var total = 0;
    if (a != null) {
      final o = _obj(a, ['title', 'module', 'list']);
      if (o != null) {
        title = '${o['title'] ?? ''}';
        total = (o['total'] as num?)?.toInt() ?? 0;
        final list = o['list'];
        if (list is List) {
          for (final it in list) {
            if (it is Map) {
              final one = _item(Map<String, dynamic>.from(it));
              if (one != null) out.add(one);
            }
          }
        }
      }
    }
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 入口=分区 code=$code 条=${out.length}/$total '
          'ms=${sw.elapsedMilliseconds}');
    }
    return (title: title, items: out, total: total);
  }

  /// 探索页：**路径式** `/explore/drama/<5 段>/` ✅（`0` = 不选 ✅；全 0 ⇒ 末尾不带那五段 ✅）
  ///
  /// [seg] 由 `ygExploreSeg` 拼好传进来 ✅ —— 站点真实参数值在 `kYgExplore` 里 ✅。
  ///
  /// 看：哪一段组合、回来几条 —— 0 条就是"这个组合下没有结果"（站上也是这么显示的 ✅）。
  Future<({List<Article> items, int total})> explore(String seg) async {
    final sw = Stopwatch()..start();
    final path = seg.isEmpty ? '/explore/drama/' : '/explore/drama/$seg/';
    // ★【取证】入口里带上 `seg` ✅ —— 一眼看出"是不是没算成空" ☑️（见 [_listHtml] ✅）
    final html = await _listHtml(
        path, '探索 seg=${seg.isEmpty ? '(空)' : seg}');
    final r = _listObj(html, ['total', 'page', 'limit']);
    final out = r?.items ?? const <Article>[];
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 入口=探索 seg=$seg 条=${out.length} '
          'total=${r?.total ?? 0} ms=${sw.elapsedMilliseconds}');
    }
    return (items: out, total: r?.total ?? 0);
  }

  /// 排行榜：`month = true` ⇒ 月榜 `/rank/drama/month/` ✅（周榜 = `/rank/drama/` ✅）
  ///
  /// ⚠️ 名次**照站上顺序** ✅（站上带 `rank_score` ✅ 别按播放量重排 ☑️）。
  ///
  /// 看：周/月、条数 —— 空就是该榜单当前没数据。
  Future<({List<Article> items, int total})> rank({bool month = false}) async {
    final sw = Stopwatch()..start();
    final html = await _listHtml(month ? '/rank/drama/month/' : '/rank/drama/',
        '排行榜 ${month ? '月榜' : '周榜'}');
    final r = _listObj(html, ['total', 'page', 'limit']);
    final out = r?.items ?? const <Article>[];
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 入口=排行榜 ${month ? '月榜' : '周榜'} '
          '条=${out.length} total=${r?.total ?? 0} ms=${sw.elapsedMilliseconds}');
    }
    return (items: out, total: r?.total ?? 0);
  }

  // ===== 五、详情（接口优先 ⇒ 失败回落 SSR + 打错误日志 ✅）=====

  /// 详情接口（form + AES-128-CBC/Pkcs7 ✅）：成功返回解析后的对象，失败返回 null
  /// （**调用方负责回落 SSR + 打日志** ✅ —— 这里只打接口这一层 ✅）
  Future<Map<String, dynamic>?> _detailApi(int id) async {
    final sw = Stopwatch()..start();
    try {
      final r = await _f.client
          .post(
            Uri.parse('https://$_kApiHost$_kApiPath'),
            headers: {
              'User-Agent': Site.ua,
              'Referer': 'https://$_kApiHost/',
              'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            },
            body: {
              'bundleId': 'com.pwa.mater',
              'version': '1.3.2',
              'oauth_type': 'web',
              'language': 'zh',
              'via': 'pwa',
              'oauth_id': _kOauthId,
              'token': '',
              'trace_id': _kOauthId,
              'video_id': '$id',
              'episode_id': '0',
              'related_list': '1',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (AppSettings.i.logConsole) {
        debugPrint('[DETAIL] ${_f.site.name} 接口 id=$id code=${r.statusCode} '
            'len=${r.bodyBytes.length} ms=${sw.elapsedMilliseconds}');
      }
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map || (j['errcode'] as num?)?.toInt() != 0) {
        if (AppSettings.i.logConsole) {
          debugPrint('[DETAIL] ${_f.site.name} 接口 id=$id errcode=${j is Map ? j['errcode'] : '?'} ⇒ 回落');
        }
        return null;
      }
      final b64 = j['data'];
      if (b64 is! String) return null;
      final plain = _aes.decrypt64(b64, iv: _iv); // AES-128-CBC / Pkcs7 ✅
      final o = jsonDecode(plain);
      final inner = (o is Map && o['data'] is Map) ? o['data'] : o;
      if (inner is! Map) return null;
      if (AppSettings.i.logConsole) {
        debugPrint('[DETAIL] ${_f.site.name} 接口 id=$id 解密命中 '
            'ms=${sw.elapsedMilliseconds}');
      }
      return Map<String, dynamic>.from(inner);
    } catch (e) {
      // ⚠️ 这里**必须打**（回落的原因要看得见 ✅ ☑️ 不许静默）
      if (AppSettings.i.logConsole) {
        debugPrint('[DETAIL] ${_f.site.name} 接口 id=$id 失败：$e ⇒ 回落 SSR');
      }
      return null;
    }
  }

  /// 详情 SSR 回落：`/drama/detail/<id>/` 里的扁平数组（找 `episodes/description/video_id` 那个对象 ✅）
  Future<Map<String, dynamic>?> _detailSsr(int id) async {
    final html = await _f.text('/drama/detail/$id/');
    final a = _nuxt(html);
    if (a == null) return null;
    return _obj(a, ['episodes', 'description', 'video_id']);
  }

  /// 播放页：`/drama/video/<id>/` ⇒ **全集地址**（`episodeAll[]` ✅ 每项 `id/sort/video_url` ✅）
  ///
  /// 返回「集行 id → 地址」和「集号 → 地址」两张表（都为空 = 这页没给地址 ✅ 调用方记日志 ✅）
  Future<({Map<int, String> byId, Map<int, String> bySort, String top})> _playPage(
      int id) async {
    final sw = Stopwatch()..start();
    try {
      final html = await _f.text('/drama/video/$id/');
      final a = _nuxt(html);
      final byId = <int, String>{};
      final bySort = <int, String>{};
      var top = '';
      if (a != null) {
        final o = _obj(a, ['video_url', 'episodeAll']);
        if (o != null) {
          top = '${o['video_url'] ?? ''}';
          final all = o['episodeAll'];
          if (all is List) {
            for (final e in all) {
              if (e is! Map) continue;
              final u = '${e['video_url'] ?? ''}';
              if (u.isEmpty) continue;
              final eid = (e['id'] as num?)?.toInt() ?? 0;
              final es = (e['sort'] as num?)?.toInt() ?? 0;
              if (eid > 0) byId[eid] = u;
              if (es > 0) bySort[es] = u;
            }
          }
        }
      }
      if (AppSettings.i.logConsole) {
        debugPrint('[SRC] ${_f.site.name} 播放页 id=$id 集址=${byId.length} '
            '顶层=${top.isEmpty ? '无' : '有'} ms=${sw.elapsedMilliseconds}');
      }
      return (byId: byId, bySort: bySort, top: top);
    } catch (e) {
      if (AppSettings.i.logConsole) {
        debugPrint('[SRC] ${_f.site.name} 播放页 id=$id 失败：$e（各集将没有源）');
      }
      return (byId: const <int, String>{}, bySort: const <int, String>{}, top: '');
    }
  }

  /// 详情入口（`Api.detail` → 本方法 ✅）
  ///
  /// 看：走了接口还是 SSR、几集、几集拿到地址、猜你喜欢几条、耗时 —— 详情页空白时先看这行。
  @override
  Future<ArticleDetail> detail(String url) async {
    final sw = Stopwatch()..start();
    final id = int.tryParse(
            RegExp(r'/drama/detail/(\d+)').firstMatch(url)?.group(1) ?? '') ??
        0;
    final path = url.length <= 80 ? url : url.substring(0, 80);
    if (id <= 0) {
      if (AppSettings.i.logConsole) {
        debugPrint('[DETAIL] ${_f.site.name} path=$path ⇒ 没有 video_id，解析不了');
      }
      throw Exception('野果短剧：详情路径里没有 video_id（$path）');
    }
    // ★ 播放页与详情**同时发**（别串行等 ☑️）—— 站上这一页就是全集地址 ✅
    final playF = _playPage(id);
    var j = await _detailApi(id);
    var via = '接口';
    if (j == null) {
      j = await _detailSsr(id);
      via = 'SSR回落';
    }
    if (j == null) {
      if (AppSettings.i.logConsole) {
        debugPrint('[DETAIL] ${_f.site.name} id=$id 接口与 SSR 都没解析出来 ☑️');
      }
      throw Exception('野果短剧：详情解析失败（id=$id）');
    }
    final play = await playF;

    // ---- 选集（站上字段：id / sort / title / resolution / duration / access.can_play ✅）----
    final eps = j['episodes'];
    final videos = <ArticleVideo>[];
    if (eps is List) {
      for (final e in eps) {
        if (e is! Map) continue;
        final eid = (e['id'] as num?)?.toInt() ?? 0;
        final sort = (e['sort'] as num?)?.toInt() ?? 0;
        final n = sort > 0 ? sort : videos.length + 1;
        final u = play.byId[eid] ?? play.bySort[sort] ?? '';
        videos.add(ArticleVideo(
          label: '第 $n 集',
          ordinal: n,
          sources: u.isEmpty ? const <String>[] : <String>[u],
          // 第 1 集兜底现取：播放页顶层 `video_url` **就是第 1 集** ✅（实测吻合 ✅）
          lazyUrl: (n == 1 && u.isEmpty) ? '/drama/video/$id/' : null,
        ));
      }
    }
    if (videos.isEmpty && play.top.isNotEmpty) {
      // 详情里没有集清单、但播放页有地址 ⇒ 兜住第 1 集（不静默：上面已打日志 ✅）
      videos.add(ArticleVideo(
          label: '第 1 集', ordinal: 1, sources: <String>[play.top]));
    }

    // ---- 元信息行（塞进通用槽位 `ArticleDetail.metaLine` ✅ 详情页 `detail_page.dart:513` 渲染 ✅）----
    // 口径：`连载中 · 播放 38W · 追剧 36931` ✅；`chase_count` 为 0 ⇒ **那一段不显示** ✅（不留空尾巴 ☑️）
    final parts = <String>[];
    final st = '${j['serialize_status_text'] ?? ''}'.trim();
    if (st.isNotEmpty) parts.add(st);
    final pc = (j['play_count'] as num?)?.toInt() ?? 0;
    final pct = '${j['play_count_text'] ?? ''}'.trim();
    if (pct.isNotEmpty) {
      parts.add('播放 $pct');
    } else if (pc > 0) {
      parts.add('播放 $pc');
    }
    final chase = (j['chase_count'] as num?)?.toInt() ?? 0;
    if (chase != 0) parts.add('追剧 $chase');

    // ---- 猜你喜欢（站上口径：`related_list` ✅ **10 条** ✅ 角标 `9.4W播放` ✅ 标题 = 真站叫法「猜你喜欢」）----
    final related = <Article>[];
    final rel = j['related_list'];
    if (rel is List) {
      for (final it in rel) {
        if (it is Map) {
          final one = _item(Map<String, dynamic>.from(it), like: true);
          if (one != null) related.add(one);
        }
      }
    }

    // ---- 标签（站上是**名字** ✅ ⇒ `/tag/<名字>/` ✅ 点进去走本站 [tag] ✅）----
    final tags = <MapEntry<String, String>>[];
    final tg = j['tags'];
    if (tg is List) {
      for (final t in tg) {
        final name = '$t'.trim();
        if (name.isEmpty) continue;
        tags.add(MapEntry(name, name));
      }
    }

    if (AppSettings.i.logConsole) {
      debugPrint('[DETAIL] ${_f.site.name} id=$id via=$via 集=${videos.length} '
          '有源=${videos.where((v) => v.sources.isNotEmpty).length} '
          '相关=${related.length} 标签=${tags.length} '
          'ms=${sw.elapsedMilliseconds}');
    }
    return ArticleDetail(
      title: '${j['title'] ?? ''}'.trim(),
      time: '', // 站上详情**没有发布时间字段** ✅（只有每集的 published_at ☑️ 不塞这里 ☑️）
      categories: const [],
      images: const [], // 这站没有剧照 ✅（封面就是剧封面 ✅）
      intro: '${j['description'] ?? ''}'.trim(),
      videos: videos,
      tags: tags,
      related: related,
      seriesPrefix: '',
      metaLine: parts.join(' · '),
    );
  }

  /// 标签列表页 `/tag/<名字>/`（站上**单页** ☑️ 别承诺翻页 ☑️ —— 第 2 页起返回空 ✅ 不静默 ☑️）
  @override
  Future<List<Article>> tag(String slug, {required int page}) async {
    final sw = Stopwatch()..start();
    if (page > 1) {
      if (AppSettings.i.logConsole) {
        debugPrint('[LIST] ${_f.site.name} 入口=标签 slug=$slug 页=$page ⇒ 本站标签页无翻页，返回 0 条');
      }
      return [];
    }
    final html = await _listHtml(
        '/tag/${Uri.encodeComponent(slug)}/', '标签 slug=$slug');
    final r = _listObj(html, ['total', 'page', 'limit']);
    final out = r?.items ?? const <Article>[];
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 入口=标签 slug=$slug 条=${out.length} '
          'total=${r?.total ?? 0} ms=${sw.elapsedMilliseconds}');
    }
    return out;
  }

  /// 搜索：**没做** ☑️（真站有没有搜索页未核实 ❓）⇒ 返回空 + 日志 ✅（不静默 ☑️、也不假装有 ☑️）
  @override
  Future<List<Article>> search(String keyword,
      {int page = 1, List<MapEntry<String, String>>? extra}) async {
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 入口=搜索 页=$page ⇒ 本站搜索还没做，返回 0 条');
    }
    return [];
  }

  /// 取源（通用槽位 ✅）：**播放页**里那一个 `video_url`（本站的地址全在播放页/详情那一页 ✅）
  ///
  /// ⚠️ 正常路径**走不到这里** ✅ —— 详情打开时已把 `episodeAll[]` 映射到每一集（见 [detail] ✅），
  ///   只有"第 1 集没拿到地址"那条兜底会用它（`lazyUrl = /drama/video/<id>/` ✅）。
  ///
  /// 看：解析出几条源 —— 0 条就是这一页没给 `video_url`（顶层那个字段 ✅）。
  @override
  List<String>? sourcesFromHtml(String html) {
    final out = <String>[];
    final a = _nuxt(html);
    if (a != null) {
      final o = _obj(a, ['video_url', 'episodeAll']);
      if (o != null) {
        for (final k in const ['video_url', 'video_url_h265']) {
          final u = '${o[k] ?? ''}'.trim();
          if (u.isNotEmpty && !out.contains(u)) out.add(u);
        }
      }
    }
    // ★【常驻诊断】本站自有取源结果：条数（⚠️ **不打 URL** ☠ —— 带 auth_key ✅）
    if (AppSettings.i.logConsole) {
      debugPrint('[SRC] ${_f.site.name} 分支=站点自有(播放页) n=${out.length}');
    }
    return out;
  }

  /// 自管整页（底座唯一使用点 = `home_page.dart:580` ✅）
  @override
  Widget? sitePage(BuildContext context, SiteEntry site) =>
      YgHomePage(site: site, ui: this);
}

// ===== 六、本站清单（清单/参数表只写在本文件里 ✅ 不给别站用 ✅）=====

/// 推荐页一个分区行（标题 + 计数 + 该行 4 条 ✅）
class YgSection {
  YgSection({
    required this.code,
    required this.title,
    required this.total,
    required this.items,
  });

  final String code;
  final String title;
  final int total;
  final List<Article> items;
}

/// 探索页 5 组筛选（**站点真实参数值** ✅ 逐条照真站 ✅）—— 顺序 ≈ 路径里五段的顺序 ✅
const List<YgGroup> kYgExplore = [
  YgGroup('theme', '主题', [
    MapEntry('7', '野果原创'),
    MapEntry('8', '真人短剧'),
    MapEntry('9', '魔改漫剧'),
    MapEntry('10', '网红改编'),
    MapEntry('11', 'PMV裸舞'),
  ]),
  YgGroup('setting', '设定', [
    MapEntry('23', '禁忌伦理'),
    MapEntry('24', '职场反差'),
    MapEntry('25', '改造调教'),
    MapEntry('26', '出轨绿帽'),
    MapEntry('27', '高H剧情'),
    MapEntry('28', '后宫多人'),
    MapEntry('29', '逆袭系统'),
  ]),
  YgGroup('background', '背景', [
    MapEntry('39', '校园'),
    MapEntry('40', '都市'),
    MapEntry('41', '年代'),
    MapEntry('43', '古代'),
    MapEntry('44', '玄幻'),
    MapEntry('45', '末世'),
    MapEntry('46', '灵异'),
  ]),
  YgGroup('time', '时间', [
    MapEntry('1', '7天内'),
    MapEntry('2', '14天内'),
    MapEntry('3', '30天内'),
    MapEntry('4', '90天内'),
  ]),
  YgGroup('recommend', '推荐', [
    MapEntry('1', '最新'),
    MapEntry('2', '最热'),
  ]),
];

/// 探索页一组筛选
class YgGroup {
  const YgGroup(this.key, this.title, this.opts);

  final String key;
  final String title;
  final List<MapEntry<String, String>> opts;
}

/// 探索页一组选中的值 ⇒ 真站路径里的**那一段** ✅ —— **只此一处定义** ✅：
///   `''`（本页「全部」在 `_sel` 里存的就是它 ✅）与 `'0'`（站上的"不选" ✅）**都表示「全部」**
///   ⇒ 一律写成 `'0'` ✅。⚠️ 2026-10-08 实锤根因就在这一层映射上（见 [ygExploreSeg] ✅）。
String _ygSegOf(String v) => (v.isEmpty || v == '0') ? '0' : v;

/// 选中的 5 组 ⇒ 真站的**路径式**段串 ✅（`0` = 该组不选 ✅；全不选 = 空串 ⇒ `/explore/drama/` ✅）
///
/// ⚠️ 2026-10-08 **实锤根因**（用户 curl 真站 ✅）：本页「全部」在 `_sel` 里存的是 **`''`**
/// （`_YgExploreTabState._sel` 的初始化 / `_pick` 写入 / 胶囊高亮判据用的都是 `''` ✅），
/// 而老实现**只认 `'0'`** ✗ ⇒ `''` 被当成有效段 ⇒ 五组全「全部」时拼出 **`'----'`** ⇒ 真站 **404** ✗
/// （底座 `lib/base/fetch.dart:86-93` 把 4xx 和"连不上"混成同一句"所有域名均无法访问" ✗
/// ⇒ 真机上看着像网络/超时 ✗ —— 别去 `lib/base/**` 里找 ✗）。
/// 真站实测：`/explore/drama/----/` 404 ✗ · `/explore/drama/` 200 ✅ · 主题=7 ⇒ `7-0-0-0-0` ✅ ·
/// 设定=23 ⇒ `0-23-0-0-0` ✅ · 五组都选 ⇒ `7-23-39-1-1` ✅（三个都 200 ✅）·
/// **全 `0`（`0-0-0-0-0`）也 404** ✗ ⇒ **全不选必须"不带段"** ✅。
/// ⇒ 现在：映射收口在 [_ygSegOf] 一处 ✅（`''` 与 `'0'` 都当"不选" ✅）；`_sel` 的表示 / 写入 /
/// 高亮判据**一字未动** ✅ ⇒ 高亮与拼串仍一致 ✅。
String ygExploreSeg(Map<String, String> sel) {
  final seg = [for (final g in kYgExplore) _ygSegOf(sel[g.key] ?? '')];
  return seg.every((x) => x == '0') ? '' : seg.join('-');
}

// ===== 七、界面（**自管整页** ✅：三主 tab = 推荐 / 探索 / 排行榜 ✅）=====

/// 本站主色（选中态那点橙 ✅ —— 与全 App 的选中色一致 ✅）
const Color _kAccent = Color(0xFFE8590C);

/// 卡片/胶囊底（未选中，压在背景图上 ✅ 同站点弹窗那套 ✅）
const Color _kChipBg = Color(0xFFF0F0F2);

/// 点卡片 ⇒ 通用详情页（本站详情由 [YeguoSite.detail] 解析 ✅；`listCover` 让播放记录零额外请求 ✅）
void _openDetail(BuildContext context, SiteEntry site, Article a) {
  Navigator.of(context).push(
    MaterialPageRoute(
      settings: const RouteSettings(name: '详情页'),
      builder: (_) => PageBg(
        child: DetailPage(site: site, baseUrl: a.url, listCover: a.cover),
      ),
    ),
  );
}

/// 野果短剧站点页（**自管整页** ✅ —— 三主 tab 照真站 ✅）
///
/// 底座里**唯一**的使用点：`home_page.dart:580` 那句 `_api.ui?.sitePage(...)` ✅
/// （那里**只判断"要不要用"** ☑️ 不认站名 ✅ ⇒ 本页的存在不影响任何别的站点 ✅）。
class YgHomePage extends StatefulWidget {
  const YgHomePage({super.key, required this.site, required this.ui});

  final SiteEntry site;
  final YeguoSite ui;

  @override
  State<YgHomePage> createState() => _YgHomePageState();
}

class _YgHomePageState extends State<YgHomePage> {
  @override
  Widget build(BuildContext context) {
    // 整页跟着背景明暗重建（标题/tab/胶囊/空态文字都读 kTxt ✅ —— 同 home_page 那套 ✅）
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => DefaultTabController(
        length: 3,
        child: Scaffold(
          // 透明：让根层背景图透出来 ✅
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            systemOverlayStyle: kStatusOverlay,
            title: Text(widget.site.name),
            centerTitle: true,
            foregroundColor: kTxt,
            bottom: TabBar(
              indicatorColor: _kAccent,
              dividerColor: Colors.transparent,
              labelColor: AppBg.i.isDark ? const Color(0xFFFFB07A) : _kAccent,
              unselectedLabelColor:
                  AppBg.i.isDark ? Colors.white : const Color(0xFF3A3A3A),
              tabs: const [
                Tab(text: '推荐'),
                Tab(text: '探索'),
                Tab(text: '排行榜'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _YgRecTab(site: widget.site, ui: widget.ui),
              _YgExploreTab(site: widget.site, ui: widget.ui),
              _YgRankTab(site: widget.site, ui: widget.ui),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- 推荐 tab：6 个分区行（每行 4 条 + 「查看更多 ›」✅）----

class _YgRecTab extends StatefulWidget {
  const _YgRecTab({required this.site, required this.ui});

  final SiteEntry site;
  final YeguoSite ui;

  @override
  State<_YgRecTab> createState() => _YgRecTabState();
}

class _YgRecTabState extends State<_YgRecTab> {
  late Future<List<YgSection>> _f = _load();

  Future<List<YgSection>> _load() async {
    try {
      return await widget.ui.homeSections();
    } catch (e) {
      // ☑️ 不许静默：失败原因写在页面上（下面 _YgFail ✅），也在日志里留一行 ✅
      if (AppSettings.i.logConsole) {
        debugPrint('[UI] ${widget.site.name} 推荐 tab 取数失败：$e');
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<YgSection>>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _YgHint('加载中…');
        }
        if (snap.hasError) {
          return _YgFail(
            '${snap.error}',
            onRetry: () => setState(() => _f = _load()),
          );
        }
        final secs = snap.data ?? const <YgSection>[];
        if (secs.isEmpty) return const _YgHint('暂时没有内容');
        return ListView(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 22),
          children: [for (final s in secs) _section(s)],
        );
      },
    );
  }

  Widget _section(YgSection s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 8, 2, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${s.title}(${s.total})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: kTxt),
                ),
              ),
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    settings: const RouteSettings(name: '野果分区页'),
                    builder: (_) => PageBg(
                      child: _YgSectionPage(
                          site: widget.site,
                          ui: widget.ui,
                          code: s.code,
                          title: s.title),
                    ),
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text('查看更多 ›',
                      style: TextStyle(fontSize: 13, color: kTxtSub)),
                ),
              ),
            ],
          ),
        ),
        // 每行 4 条、可横滑（照真站 ✅）
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final a in s.items)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 108,
                    child: _YgCard(site: widget.site, a: a),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---- 探索 tab：5 组筛选（**路径式** URL ✅）+ 结果 ---- 

class _YgExploreTab extends StatefulWidget {
  const _YgExploreTab({required this.site, required this.ui});

  final SiteEntry site;
  final YeguoSite ui;

  @override
  State<_YgExploreTab> createState() => _YgExploreTabState();
}

class _YgExploreTabState extends State<_YgExploreTab> {
  /// 每组选中的值（`''` = 「全部」= 该段写 `0` ✅ 同真站 ✅）
  final Map<String, String> _sel = {
    for (final g in kYgExplore) g.key: '',
  };

  late Future<({List<Article> items, int total})> _f = _load();

  Future<({List<Article> items, int total})> _load() async {
    try {
      return await widget.ui.explore(ygExploreSeg(_sel));
    } catch (e) {
      if (AppSettings.i.logConsole) {
        debugPrint('[UI] ${widget.site.name} 探索 tab 取数失败：$e');
      }
      rethrow;
    }
  }

  /// 点一个标签：**点的就是已经选中的那个 ⇒ 直接不重拉** ✅（白拉一次没意义 ☑️）。
  /// ⚙️ 比的是 [_ygSegOf] **归一化后**的值 ✅ —— `''`（「全部」✅）与 `'0'` 是同一个意思 ✅
  ///    ⇒ "重复点全部"不会被误判成"变了" ✅；真变了（如 `'7'` → 全部）才重取 ✅。
  void _pick(String key, String value) {
    if (_ygSegOf(_sel[key] ?? '') == _ygSegOf(value)) return; // 没变化 ⇒ 不重拉 ✅
    setState(() {
      _sel[key] = value;
      _f = _load(); // 换一个组合 ⇒ **真的重筛重画** ✅（不是只切本地选中态 ☑️）
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({List<Article> items, int total})>(
      future: _f,
      builder: (context, snap) {
        final rows = <Widget>[
          const SizedBox(height: 4),
          for (final g in kYgExplore) _group(g),
          const Divider(height: 18, thickness: 0.6),
        ];
        if (snap.connectionState != ConnectionState.done) {
          rows.add(const _YgHint('加载中…'));
        } else if (snap.hasError) {
          rows.add(_YgFail('${snap.error}',
              onRetry: () => setState(() => _f = _load())));
        } else {
          final r = snap.data;
          final items = r?.items ?? const <Article>[];
          rows.add(Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
            child: Text('共 ${r?.total ?? 0} 条',
                style: TextStyle(fontSize: 13, color: kTxtSub)),
          ));
          if (items.isEmpty) {
            rows.add(const _YgHint('这个组合下没有结果'));
          } else {
            rows.add(_grid(items, site: widget.site));
          }
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 22),
          children: rows,
        );
      },
    );
  }

  /// 一组：组名 + 「全部」+ 该组选项（**横滑** ✅）
  Widget _group(YgGroup g) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 34,
            child: Text(g.title,
                style: TextStyle(fontSize: 13, color: kTxtSub)),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _YgChip(
                    label: '全部',
                    on: _sel[g.key] == '',
                    onTap: () => _pick(g.key, ''),
                  ),
                  for (final o in g.opts)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _YgChip(
                        label: o.value,
                        on: _sel[g.key] == o.key,
                        onTap: () => _pick(g.key, o.key),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- 排行榜 tab：周榜 / 月榜（站上两个路径 ✅）----

class _YgRankTab extends StatefulWidget {
  const _YgRankTab({required this.site, required this.ui});

  final SiteEntry site;
  final YeguoSite ui;

  @override
  State<_YgRankTab> createState() => _YgRankTabState();
}

class _YgRankTabState extends State<_YgRankTab> {
  bool _month = false; // 默认周榜 ✅
  late Future<({List<Article> items, int total})> _f = _load();

  Future<({List<Article> items, int total})> _load() async {
    try {
      return await widget.ui.rank(month: _month);
    } catch (e) {
      if (AppSettings.i.logConsole) {
        debugPrint('[UI] ${widget.site.name} 排行榜 tab 取数失败：$e');
      }
      rethrow;
    }
  }

  void _pick(bool month) {
    setState(() {
      _month = month;
      _f = _load(); // 周/月 = 站上两个路径 ✅ ⇒ 真的重取 ✅
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({List<Article> items, int total})>(
      future: _f,
      builder: (context, snap) {
        final rows = <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: Row(
              children: [
                Expanded(
                    child: _YgSeg(
                        label: '周榜', on: !_month, onTap: () => _pick(false))),
                const SizedBox(width: 8),
                Expanded(
                    child: _YgSeg(
                        label: '月榜', on: _month, onTap: () => _pick(true))),
              ],
            ),
          ),
        ];
        if (snap.connectionState != ConnectionState.done) {
          rows.add(const _YgHint('加载中…'));
        } else if (snap.hasError) {
          rows.add(_YgFail('${snap.error}',
              onRetry: () => setState(() => _f = _load())));
        } else {
          final r = snap.data;
          final items = r?.items ?? const <Article>[];
          rows.add(Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Text(
                '${_month ? '月榜' : '周榜'} · 本页 ${items.length} 条 / 共 ${r?.total ?? 0}',
                style: TextStyle(fontSize: 13, color: kTxtSub)),
          ));
          if (items.isEmpty) {
            rows.add(const _YgHint('这个榜单当前没有内容'));
          } else {
            rows.addAll([
              for (var i = 0; i < items.length; i++)
                _YgRankRow(site: widget.site, a: items[i], rank: i + 1),
            ]);
          }
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 22),
          children: rows,
        );
      },
    );
  }
}

// ---- 分区页（「查看更多 ›」⇒ `/drama/<code>/` ✅ 站上**只有第 1 页** ☑️）----

class _YgSectionPage extends StatefulWidget {
  const _YgSectionPage({
    required this.site,
    required this.ui,
    required this.code,
    required this.title,
  });

  final SiteEntry site;
  final YeguoSite ui;
  final String code;

  /// 分区名（从推荐页那一行带过来 ✅ = 站点自己的分区标题 ✅ 标题照真站 ✅）
  final String title;

  @override
  State<_YgSectionPage> createState() => _YgSectionPageState();
}

class _YgSectionPageState extends State<_YgSectionPage> {
  late Future<({String title, List<Article> items, int total})> _f = _load();

  Future<({String title, List<Article> items, int total})> _load() async {
    try {
      return await widget.ui.section(widget.code);
    } catch (e) {
      if (AppSettings.i.logConsole) {
        debugPrint('[UI] ${widget.site.name} 分区页 ${widget.code} 取数失败：$e');
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          systemOverlayStyle: kStatusOverlay,
          title: Text(widget.title.isEmpty ? widget.code : widget.title),
          centerTitle: true,
          foregroundColor: kTxt,
        ),
        body: FutureBuilder<({String title, List<Article> items, int total})>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const _YgHint('加载中…');
            }
            if (snap.hasError) {
              return _YgFail('${snap.error}',
                  onRetry: () => setState(() => _f = _load()));
            }
            final r = snap.data;
            final items = r?.items ?? const <Article>[];
            if (items.isEmpty) return const _YgHint('这个分区当前没有内容');
            return ListView(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 22),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
                  child: Text(
                      '${r?.title ?? ''} · 本页 ${items.length} 条 / 共 ${r?.total ?? 0} 条',
                      style: TextStyle(fontSize: 13, color: kTxtSub)),
                ),
                _grid(items, site: widget.site),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---- 小件：卡片 / 胶囊 / 榜单行 / 状态 ----

/// 三列卡片网格（**竖版站 3 列** ✅ 规范「竖版站 3 列」✅）
Widget _grid(List<Article> items, {required SiteEntry site}) {
  return LayoutBuilder(
    builder: (context, c) {
      const pad = 10.0, gap = 8.0;
      final w = (c.maxWidth - pad * 2 - gap * 2) / 3;
      return Wrap(
        spacing: gap,
        runSpacing: 12,
        children: [
          for (final a in items) SizedBox(width: w, child: _YgCard(site: site, a: a)),
        ],
      );
    },
  );
}

/// 卡片：**封面（3:4）+ 标题 + 右下角角标** ✅（本站角标口径 = 播放量 ✅ 不显示集数/时长 ☑️）
class _YgCard extends StatelessWidget {
  const _YgCard({required this.site, required this.a});

  final SiteEntry site;
  final Article a;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openDetail(context, site, a),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4, // 站上封面是竖图 ✅
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (a.cover.isEmpty)
                    const ColoredBox(color: Color(0xFFEEEEEE))
                  else
                    // ⚠️ 本站封面是**加密图** ⇒ `FetchedImage` 自己会解密 ✅（key/iv 两边同一份 ✅）
                    FetchedImage(url: a.cover, memWidth: 320),
                  if (a.badge.isNotEmpty)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(a.badge,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            a.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, height: 1.25, color: kTxt),
          ),
        ],
      ),
    );
  }
}

/// 筛选胶囊（未选中浅底 / 选中橙底 ✅ 同全 App 那套 ✅）
class _YgChip extends StatelessWidget {
  const _YgChip({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? _kAccent : _kChipBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12, color: on ? Colors.white : const Color(0xFF444444)),
        ),
      ),
    );
  }
}

/// 周榜/月榜切换按钮（选中橙底 ✅）
class _YgSeg extends StatelessWidget {
  const _YgSeg({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: on ? _kAccent : _kChipBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 13,
              fontWeight: on ? FontWeight.bold : FontWeight.normal,
              color: on ? Colors.white : const Color(0xFF444444)),
        ),
      ),
    );
  }
}

/// 榜单行：名次 + 小封面 + 标题 + 播放量 ✅（名次**照站上顺序** ✅ 前 3 名用橙色 ✅）
class _YgRankRow extends StatelessWidget {
  const _YgRankRow({required this.site, required this.a, required this.rank});

  final SiteEntry site;
  final Article a;
  final int rank;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openDetail(context, site, a),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: rank <= 3 ? _kAccent : kTxtSub,
                ),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 64,
                height: 86,
                child: a.cover.isEmpty
                    ? const ColoredBox(color: Color(0xFFEEEEEE))
                    : FetchedImage(url: a.cover, memWidth: 200),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: kTxt),
                  ),
                  const SizedBox(height: 6),
                  Text('播放 ${a.badge}',
                      style: TextStyle(fontSize: 13, color: kTxtSub)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 加载中 / 空态提示
class _YgHint extends StatelessWidget {
  const _YgHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 24, 10, 0),
        child: Center(
            child: Text(text, style: TextStyle(fontSize: 14, color: kTxtSub))),
      );
}

/// 失败态：**写原因** + 可重试 ✅（☑️ 不静默、也不假装空）
class _YgFail extends StatelessWidget {
  const _YgFail(this.msg, {required this.onRetry});

  final String msg;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 24, 10, 0),
        child: Column(
          children: [
            Text('加载失败：',
                style: TextStyle(fontSize: 14, color: kTxt)),
            const SizedBox(height: 4),
            Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: kTxtSub)),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: kChipBorder),
              ),
              child: Text('重试',
                  style: TextStyle(fontSize: 13, color: kTxt)),
            ),
          ],
        ),
      );
}

// ===== 八、本站档案（2026-10-08 ✅；在 `lib/sites.dart` 的 `kSites` 里按用户指定顺序出现 ✅）=====

/// 本站档案：野果短剧
///
/// ⚠️ `categories` 留空 ✅ —— 本站是**自管整页**（三主 tab 在 [YgHomePage] 里 ✅），
///   底座那套「分类 tab + 分页列表」对它**用不到** ☑️（`home_page.dart:580` 直接返回本页 ✅）。
const SiteEntry kSite15 = SiteEntry(
  name: '野果短剧',
  template: SiteTemplate.yeguodj,
  iconUrl: '/favicon.ico',
  hosts: ['yeguodj.com'],
  portraitCovers: true, // 封面 3:4 竖图 ✅
  // 仅"首字色块"兜底用（有 iconUrl 时用不到 ✅）
  color: Color(0xFFE23B3B),
);
