// 柚子短剧（youzidj.com）—— **本站专属**的一切 ✅
//
// 站点：`youzidj.com`（**SSR HTML** ✅ 非 Nuxt/Next；Cloudflare 但**不挡人** ✅；**无特殊头** ⇒ 全局 UA 够用 ✅）。
// **竖版海报 9:16** ✅ ⇒ 档案里 `portraitCovers: true` ✅ + 每条卡自带 `coverAspect: 9/16` ✅。
//
// ⚠️ 本站是**第三个"自管整页"的站点** ✅（前两个 = xhamsterlive / 野果短剧 ✅）：
//   主 tab = **首页 / 剧库**，两页版式都是站点专有（5 个分区行 / 8 分类 + 2 排序 + 分页）✅
//   ⇒ 走 `SiteUi.sitePage()` ✅（底座里**唯一**使用点 = `home_page.dart:580` ✅ 那句**不认站名** ✅ 一字不动 ☑️）。
//   详情**仍走通用详情页** ✅（本站只提供解析 + 取流凭证 ✅）。
//   卡片直接复用**全站共用**的 `ArticleCard` ✅（`home_page.dart:1096` ✅ —— 点它 = 进通用详情页 ✅
//   并自动带 `listCover` ✅），不自造一套 ✅。
//
// ---- 形态（2026-10-11 本机 curl + 实站 HTML **逐条核对** ✅，每条后面括注取数方式）----
//  · 首页 `/` = SSR：5 个 `section.home-section`（`.catalogue-section-heading` 里 h2 + 「更多」✅）
//    柚惑热播 → `/dramas/?sort=popular` · 柚追连载 → `/dramas/` · 柚遇都市 → `/dramas/category/urban/`
//    · 柚燃上头 → `/tags/ni-xi/` · 柚密心事 → `/tags/romance/` ✅（都是站上真链接 ✅ 实测）
//    每区实测 8~12 张卡（竖版海报 ✅）
//  · 剧库 `/dramas/`：数据走**片段接口**（比整页小 79% ✅ —— 这是"打开快"的关键 ✅）
//    `GET /api/catalogue/browse?sort=<updated|popular>&category=<slug|留空>&page=<n>&navigation=1`
//    ⇒ `text/html` 片段：根 `<div data-browse-response="true" data-browse-metadata="{…}">`
//      + **24 张 `article.drama-card`** + 自带翻页状态 **`data-page` / `data-pages` / `data-total`** ✅
//    · 分类 slug（照 `/dramas/` 的 `.catalogue-category-track` 逐条抄 ✅）：
//      `全部`=空 · `cultivation` · `wealthy-family` · `urban` · `costume` · `family-ethics` ·
//      `martial-arts` · `campus` ✅；排序 `updated`=最新 / `popular`=最热 ✅
//    ⚠️ **页码越界回 404**（实测：`sort=popular&category=cultivation&page=2` ⇒ 404 `{"error":"资源不存在"}` ✅
//      —— slug 没错，是该组合没第 2 页）⇒ **第 2 页起遇 404 当"没有更多了"** ✅；
//      **第 1 页遇 404 仍照错抛** ☑️（免得把"slug 打错"当成"空列表" ✅）
//  · 卡片选择器（都取自实站标记 ✅）：`article.drama-card` → `p.drama-card-title a[title]`（标题）、
//    `a.drama-card-cover[href]`（详情路径）、**`img[data-image-src]`**（封面；⚠️ `src` 是 1×1 占位 svg ☑️
//    别用 ✅）、`span.drama-card-status`（`预热`/`连载中` ✅）、`span.drama-poster-episodes`（`6集可看` ✅）、
//    `.drama-card-meta span[title]`（`482热度` ✅）
//  · 详情 `/dramas/<slug>/`：`script[type="application/ld+json"]` 的 **TVSeries**
//    （`name`/`description`/`image`/`numberOfEpisodes` ✅ —— 实测 `numberOfEpisodes:14` ✅）
//    ⚠️ **`/dramas/<slug>/season-1/`（搜索结果给的去向）实测 `@type` = `TVSeason`** ✅
//      ⇒ 判据**放宽成 `TVSeries` 或 `TVSeason`**（2026-10-12 用户批准 ✅ —— 详见 `detail()` 里的注释 ✅）
//    + 集清单 `a.series-episode-link`（`data-analytics-video` = **该集 videoId** ✅、`title`/`aria-label`、
//      `data-paid` ✅；实测一部剧 14 条、**去重后正好 14** ✅）
//    + 标签 `a[href*="/tags/"]`（名字在 `<span>` 里 ✅）+ 相关推荐 `.series-recommendations article.drama-card` ✅
//  · 标签页 `/tags/<slug>/`：SSR 单页（实测 8 条、**没有翻页** ✅）
//
//  · ⭐ **播放 = 三步，缺一步 403**（全部本机实测 ✅）：
//    ① `POST /api/account/bootstrap`（头 `Origin: https://youzidj.com` + `Content-Type: application/json`，
//       体 `{}`）⇒ 200 + `Set-Cookie: eden_account=…`（1 年 ✅）
//       ⚠️ `Origin` **必须带**：缺它 ⇒ **403 `请求来源无效，请刷新页面后重试`**（2026-10-11 本机实锤 ✅）
//    ② `POST /api/playback/<videoId>?mode=mse`（**必带** `Cookie: eden_account=…` + `Referer`＝该集页面 ✅，
//       体 `{}`）⇒ 200 JSON **`{url, expires_at}`**（实测**只有这两个键** ✅ —— `mse` 也没有 `startup` ✅）+
//         `Set-Cookie: eden_play_<videoId>=…; Max-Age=900; Path=/media/<videoId>/` ✅
//       （实测：② 只带 `eden_account` 就 200 ✅ ⇒ ② 不需要播放 cookie ✅）
//       ⚠️ 站方 2026-10-11 收紧过：`Referer` 补成**该集页面** ✅（本机三组实测都 200：无 Referer ✅ /
//         季节页 ✅ / 该集页 ✅ —— 此刻它不是**硬性**的 ☑️，但站方出现过 `404 作品尚未上线` / `401` 的
//         收紧行为，且站方自己的播放器也只带 `referer` ⇒ **按浏览器同款补上** ✅；`Origin` 照样留着 ✅）
//    ③ 取流 `https://youzidj.com/media/…/master.m3u8`（**HLS 分片** ✅ 同域、无独立媒体域名 ✅）
//       ⚠️ **必须 `Cookie: eden_account=…; eden_play_<videoId>=…` 两个一起**（本机实测 ✅）：
//          两个都带 ⇒ **200** + `#EXTM3U` ✅；只带 `eden_account` ⇒ **403** ✅；一个都不带 ⇒ **403** ✅（负控 ✅）
//          ⇒ 给播放器的头 = **这两个** ✅
//       `Origin`/`Referer` 取流时**不需要**（实测 ✅）
//    ★ **为什么"只走分片"（2026-10-12 用户拍板 ✅ —— 原话："柚子只走分片。就这样"）**：
//      · 依据：**分片路径实测比整段快 1.5~5 倍且更稳**（同集同窗口：分片 1329~3649 KB/s
//        vs 单文件 98~1723 KB/s ✅）；**新库下 fMP4 HLS 能跳**（4.1~7.0s 恢复、1× ✅）
//      · **代价（如实记）**：**旧库（iOS 现状）下 fMP4 HLS 远跳会坏** ☑️ —— 用户已拍板接受 ✅
//      · ⇒ 代码里**不再**取 native 票、**不再**做 2 字节 MP4 探测、**不再**按"真 MP4 + 大小 ≤500MB"选路
//        （2026-10-11 那套 `_probeMp4` / `_kNativeMaxBytes` / `_mb` **已整段删除** ✅ 不留死代码 ☑️；
//          当时那套是为绕开"整段 665MB 卡 00:00" ✅ 现按用户口径整段弃用 ☑️）
//      · ⇒ **请求数下降**：每集 **1 次 POST**（原来 2~3 次：native 票 + 探测 + 可能的 mse 票 ✅），
//        且**每集少 1 次 2 字节探测** ✅
//    ⚠️ **页面里那个 `master.m3u8` 直接拿来播必失败**（403）☠ ⇒ **不许**把它当源 ✅
//       —— 源一律用 ② 现取的地址 ✅
//    ⚠️ 凭证 **15 分钟**（`expires_at` = 请求时刻 +900s ✅）⇒ **详情页每次加载都重跑 ②** ✅
//       （口径与野果那次一致：地址进 `detail()` 的 `ArticleVideo.sources` ✅ ⇒ 播放器"刷新源"
//        （= 重抓详情 ✅ `detail_page.dart:465 _refreshSources` ✅）对**每一集**都有效 ✅）
//  · ⚠️ **状态码/未解锁口径（2026-10-11 修 S3 ✅ —— 原实现有"整会话停手"缺陷 ☠）**：
//    · **未解锁**：集链接上 `data-paid`（站上**唯一**的这种标记 ✅ 实测 4 部剧 57 条**全 `false`** ✅、
//      `true` **无样本** ❓）为真 ⇒ **该集不发 ②**、直接无源 ⇒ 日志 `跳过(未解锁) 集=…` ✅；
//      只认 `true`/`1`/`yes`，认不出的值当"可播"（fail-open ☑️ 不误杀 ✅）。
//      ⚠️ 另实测：站上"N集可看" == 详情里**唯一 videoId 数** == `numberOfEpisodes` ✅
//        ⇒ **未解锁的集似乎压根不列出来** ✅（所以这条分支平时走不到 ☑️ 但必须留着 ✅）。
//    · **403** ⇒ **只当"这一集取不到票"** ✅（该集无源）⇒ **继续处理其余集** ✅，日志 `403(该集无票)` ✅
//      （旧实现是"整会话停手"☠ —— 一触发**后面所有剧都没源** ✗ 已删 ✅）
//    · **429** ⇒ **冷却 30 秒**（`_coolUntil` ✅）：窗口内不再发 ② ✅、**到点自动恢复** ✅（不必重启 App ✅），
//      日志 `429(冷却 30s)` / 窗口内被调到 `跳过(429冷却 Ns)` ✅
//      ⚠️ 冷却与 `eden_account` 都挂在本类**实例**上，而 `Api` 是**每页一份**
//        （`api.dart:42` + `late final YouziSite _yzSite` ✅；`detail_page.dart:49` 每页 new ✅）
//        ⇒ **跨详情页不保持**：新开一页 = 新实例 = 冷却清零 + 账号 cookie 重取 ✅
//        （这正好满足"冷却过后自动恢复、不必重启 App" ✅）。
//  · ★ **2026-10-11（用户批准"甲/不预取" ✅）：只取"要看的那一集"的票** ——
//    `detail()` 只给**第 1 集**取票（1 次 POST ✅；改前是"每集都取、3 路并发" ⇒ 42 集要等十几秒 ☠），
//    其余集 `sources` 空 + `lazyUrl` = **伪地址** `/yz/play/<videoId>/<nonce>/`
//    ⇒ **切到那一集时才 POST 现取**（播放器亮"正在取视频…" ✅ `player_widget.dart:1332-1375` ✅）。
//    ⚠️ 伪地址的 `nonce` 是**必须的**（不是装饰）：`SourceCache` 键 = URL 字符串、**无 TTL**、
//      命中还**续命**（`source_cache.dart:25/37/39` ✅）⇒ 固定地址会把 15 分钟前的**过期票**再喂给播放器 ☠。
//      带 nonce ⇒ 每次都是新键 ⇒ **次次真发 POST** ✅（宁可多一次请求，也要新票 ✅ —— 用户口径 ✅）。
//    ⚠️ 刷新兜底（**超出"甲"口径的一处小加法**，已在汇报里点明 ✅）：`detail()` 被
//      "播放失败 ⇒ 刷新源"重跑时（`detail_page.dart:465` ✅），**额外补一张"用户正在看的那一集"**的票
//      （靠 `_lastVid` ✅ —— 由 [fetchSources] 记下）⇒ 同一集连续播超过 15 分钟、票过期后
//      `_recover` 也能拿到**新鲜地址**、原地续播 ✅；**不加**这一条 ⇒ 刷新拿空 ⇒ `_recover` 退回旧源
//      ⇒ 会话内救不回来 ☠（见回报"已知限制" ✅）。每次 `detail()` 的 POST 数 = 1 + (0~1) ✅。
//
// ---- 日志 ----
//  可以打：videoId / 状态码 / 字节数 / 条数 / 耗时 ✅；
//  ⚠️ **绝不打 cookie 值、也绝不打带凭证的地址** ☠（本项目既有口径 ✅）。

import 'dart:convert';
// ★ 2026-10-12（**iOS 修** ✅）：回退用的**站点内自建** `dart:io HttpClient`（只给 bootstrap/取票两条用 ✅，
//   公共 fetch/config **不动** ☑️ —— iOS 仍走 NSURLSession 读系统代理/VPN ✅）。用前缀防与 material 撞名 ✅
import 'dart:io' as io;

// ⚠️ 本站要**自己画整页**（两主 tab / 分区行 / 分类胶囊 / 分页）⇒ 必须 import material ✅
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom; // ⚠️ 必须带前缀：html 的 `Text`/`Element` 会和 material 撞名 ☠
import 'package:html/parser.dart' as hp;

import '../app_background.dart';
import '../app_bg.dart';
import '../base/fetch.dart';
import '../base/site_ui.dart';
import '../config.dart' show Site;
import '../home_page.dart' show ArticleCard, SearchPage; // ★ 复用全站共用卡片 + 底座通用搜索页 ✅
import '../models.dart';
import '../settings.dart'; // ★ 诊断开关（`AppSettings.i.logConsole` ✅）
import '../site_error_log.dart'; // ★ 列表请求非 200 时写公共错误日志 ✅
import '../sites.dart'; // 本站档案 `kSite16` + `SiteTemplate.youzidj` ✅（循环 import 本项目允许 ✅）

/// 柚子短剧本站专属实现（取数走底座 [SiteFetcher] ✅）
class YouziSite extends SiteUi {
  YouziSite(this._f);

  final SiteFetcher _f;

  static const String _kHost = 'youzidj.com';
  static const String _kBase = 'https://$_kHost';

  /// 接口超时：与本项目其它接口口径一致（10 秒 ✅；列表类页面另给 15 秒 ✅ —— 见 [browse]）
  static const Duration _kApiTimeout = Duration(seconds: 10);

  /// 剧库的 8 个分类 chip（**站上真 slug + 真名字** ✅ 逐条照 `/dramas/` 的 `.catalogue-category-track` ✅）
  static const List<MapEntry<String, String>> kYzCats = [
    MapEntry('', '全部'),
    MapEntry('cultivation', '修仙'),
    MapEntry('wealthy-family', '豪门'),
    MapEntry('urban', '都市'),
    MapEntry('costume', '古装'),
    MapEntry('family-ethics', '家庭伦理'),
    MapEntry('martial-arts', '武侠'),
    MapEntry('campus', '校园'),
  ];

  /// 剧库的 2 个排序 chip（站上 `data-browse-sort` 的两个值 ✅：`updated`=最新 / `popular`=最热 ✅）
  static const List<MapEntry<String, String>> kYzSorts = [
    MapEntry('updated', '最新'),
    MapEntry('popular', '最热'),
  ];

  /// ★ 2026-10-12（**用户口径**，原话：**"相关推荐怎么是列表，改为卡片；卡片内文字不要被截断"** ✅）：
  ///   详情页「相关推荐」**改成卡片版式** ⇒ 走底座现成槽位 `SiteUi.relatedAsGrid` ✅
  ///   —— **3 列竖版卡片**（= 野果 / 黄果 同款那套 ✅），**本文件只加这一行**、公共区 0 改动 ✅。
  ///
  /// ⚠️ **为什么这样就不会"文字被截断"**（用户特别点名的那条 ✅）：
  ///   · 底座网格版式用的是 **`IntrinsicHeight` + `Row(stretch)`**（`detail_page.dart:1144-1183` ✅）：
  ///     行高 = 该行**最高**卡、行内等高、**卡片高度随内容自适应** ✅（不是写死高度 ✅）。
  ///   · **野果当年的毛病**正是写死高度：原来是 `GridView.count(childAspectRatio: 0.62)`
  ///     ⇒ 卡片高度固定 ⇒ **两行标题溢出、下半截被卡片底边遮住** ✗（代码里留了根因注释 ✅）；
  ///     改成"高度随内容"之后就好了 ✅ —— 现在这条路径**不会**再犯 ☑️。
  ///   · 公用 `ArticleCard`（`home_page.dart:1096` ✅）本身也安全：标题 **`maxLines: 2` + 省略号** ✅、
  ///     文字块内边距 **`fromLTRB(8, 6, 8, 8)` ⇒ 底部 8px 余量** ✅、卡片**没有写死高度** ✅
  ///     （封面是固定纵横比、文字区按内容高度 ✅）。
  ///
  /// ✅ **影响面**：只有柚子短剧 ✅（未覆写的 13 站照旧走列表版式 ⇒ 行为逐字不变 ✅）。
  @override
  bool get relatedAsGrid => true;

  // ===== 一、cookie（**全在本文件里自管** ✅，不动公共区 ✅）=====

  /// `eden_account`（1 年有效 ✅）—— 进程内只取一次 ✅
  String? _acc;

  /// ★ 2026-10-11（修 S3 ✅）：**429 冷却窗口的终点**（`null` / 已过去 = 不在冷却 ✅）。
  ///   ⚠️ **只对 429 生效** ☑️ —— 403 一律**不停手**（只当这一集没票 ✅，见 [_playback] ✅）。
  ///   ⚠️ 到点**自动恢复** ✅（时间到了判据自然为假 ⇒ 不必重启 App、也不必手动复位 ✅）。
  DateTime? _coolUntil;

  /// 429 冷却时长（30 秒 ✅，用户口径）
  static const Duration _kCool = Duration(seconds: 30);

  /// 冷却剩余秒数（0 = 不在冷却 ✅）
  int _coolLeft() {
    final u = _coolUntil;
    if (u == null) return 0;
    final d = u.difference(DateTime.now()).inSeconds;
    return d > 0 ? d : 0;
  }

  /// ★ 2026-10-11（用户批准"甲/不预取" ✅）：**用户最近真正要看的那一集**（videoId）——
  ///   由 [fetchSources] 每次按集取源时记下 ✅。作用：`detail()` 被"播放失败 ⇒ 刷新源"重跑时
  ///   （`detail_page.dart:465 _refreshSources` ✅）**只补这一集的票** ⇒ `_recover` 才拿得到新鲜地址 ✅
  ///   （否则它刷新拿空 ⇒ 退回**旧源**重开 ⇒ 那种情况就救不回来 ☠ 见本文件顶部"已知限制" ✅）。
  String? _lastVid;

  /// ★ 2026-10-11（站方新要求 ✅）：**videoId → 该集页面的绝对地址** —— 取票时当 `Referer` 发 ✅。
  ///   由 `detail()` 从页面上的 `a.series-episode-link[href]` **抄下来**（**不自己拼** ☑️ —— 多季
  ///   `season-N` 也能对 ✅）；查不到就退站点根（见 [_ticket] ✅）。
  final Map<String, String> _epUrl = <String, String>{};

  /// 伪地址里的**唯一化序号**（单调自增 ✅；配合微秒时间戳 ⇒ 同一 videoId 每次都是**新**缓存键 ✅）
  static int _nonce = 0;

  /// 每集的**额外请求头**（videoId → `{'Cookie': …}`）——
  /// ★ **同一个 videoId 永远用同一个 Map 实例**（原地更新 ☑️），原因见 [headersOf] ✅
  final Map<String, Map<String, String>> _hdr = <String, Map<String, String>>{};

  /// 取某一集的头 Map（**实例稳定** ✅ —— 只往里写，不换实例 ✅）
  ///
  /// ⚠️ 为什么必须"实例稳定"（这是"刷新源带新凭证"能立刻生效的关键 ✅）：
  ///   详情页刷新源时 `setState` 到**父级重建**之间隔着**一帧** ☑️，而播放器
  ///   "本轮源全失败 ⇒ 刷新源 ⇒ 立刻再试一轮"是在**同一个微任务**里继续跑的
  ///   （`player_widget.dart:1440-1455` ✅）⇒ 那一刻播放器手里的还是**旧 widget**
  ///   （= 旧 Map ✅）。**原地更新**这个 Map ⇒ 旧 widget 也能**立刻**看到新 cookie ✅
  ///   （否则要多等一轮自动重试才生效 ☑️）。
  Map<String, String> headersOf(String videoId) =>
      _hdr.putIfAbsent(videoId, () => <String, String>{});

  /// 从 `Set-Cookie` 里抠一个 cookie 值（⚠️ **不能按 `,` 拆**：`Expires=Wed, 21 Oct …` 里就有逗号 ☠；
  ///   只认 `;`/`,`/空白 之前的那段值 ✅；cookie 值本身不含这些字符 ✅）
  static String? _cookieValue(String setCookie, String name) {
    if (setCookie.isEmpty) return null;
    final m = RegExp('${RegExp.escape(name)}=([^;,\\s]+)').firstMatch(setCookie);
    final v = m?.group(1)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  /// 日志用：videoId 只留前 8 字（uuid 太长 ☑️；**只是给日志看**，不参与任何判断 ✅）
  static String _vid8(String vid) => vid.length <= 8 ? vid : vid.substring(0, 8);

  /// ★ 2026-10-12（**iOS 修 ①** ✅）：把响应头里的 `set-cookie` **大小写不敏感 + 多值合并**地取出来 ✅
  ///
  /// 【依据 🛢️（真机日志 1.3.2，只有手机端犯）】`①bootstrap code=200 len=119 cookie=无` ⇒ 取票失败 ⇒
  ///   **0 条源** ⇒ 播放器"重试 5 次" ☠；PC（走 `dart:io`）同一请求**正常拿到** ⇒ 矛头指向 iOS 的
  ///   `cupertino_http`（NSURLSession）那一侧读头的方式 ✅。
  ///
  /// 【NSURLSession 侧两种可能，都堵掉 ✅】
  ///   ① 头名回的是 `Set-Cookie`（大写 S/C），而原来按 `r.headers['set-cookie']` 取 ⇒ **大小写敏感取不到** ☠；
  ///   ② 多个 `Set-Cookie` 需要**拼接**才看得全（原写法只看得见一个/看不见 ☠）。
  ///   ⇒ 这里**先把所有 key `toLowerCase()` 再比对**，命中的值用 `", "` **拼起来**，再交给 [_cookieValue] ✅
  ///     （⚠️ 拼接只是"多值合并"；**真正的取值仍按 [_cookieValue] 的 `;`/`,` 规则**，所以不会把
  ///      `Expires=Wed, 21 Oct …` 里那个逗号误当分隔 ☠ —— 见那个方法的注释 ✅）
  static String _setCookieOf(Map<String, String> headers) {
    final vals = <String>[];
    headers.forEach((k, v) {
      if (k.toLowerCase() == 'set-cookie' && v.isNotEmpty) vals.add(v);
    });
    return vals.join(', ');
  }

  /// ★ 2026-10-12（**iOS 修 ②：兜底** ✅）：用**站点内自建**的 `dart:io HttpClient` **重发一次**同一请求 ✅
  ///
  /// 【为什么要它】真机上"大小写不敏感"那招**也可能无效**（NSURLSession 就是不给这个头 ☠）⇒
  ///   `dart:io` 的 `HttpClient` 一定回 `Set-Cookie` ✅ ⇒ 用它兜。
  ///
  /// 【为什么只回退 **bootstrap / 按集取票** 这两条】整个站点里**只有这两条要从 `Set-Cookie` 读值** ✅；
  ///   其它请求（列表 / 详情 / 分片）**一条都不动** ☑️ —— 公共 `fetch.dart`/`config.dart` 也不动 ✅，
  ///   因为 iOS 走 NSURLSession 是**为了读系统代理/VPN** ✅（这条要保留 ☑️）。
  ///
  /// 【触发条件】**只在"站点客户端已经回话、但没抠到 cookie"时才走** ✅ ⇒
  ///   **Windows 正常路径永不触发**（它的 `dart:io` 客户端本来就能拿到 cookie ✅）⇒ 已验证的 PC 行为不变 ✅。
  ///
  /// 【口径】头/体由调用方传入（与主路径**共用同一份 Map** ⇒ 逐字一致 ✅）；用完 **`close(force: true)`** ✅；
  ///   返回 `(code, setCookie, body)`，异常 ⇒ null（调用方照原"失败"路径走 ✅）。**日志不打地址、不打 cookie** ☠
  Future<({int code, String setCookie, List<int> body})?> _postViaIo(
      String path, Map<String, String> headers, String body) async {
    final c = io.HttpClient();
    try {
      final req = await c.postUrl(Uri.parse('$_kBase$path'));
      headers.forEach((k, v) => req.headers.set(k, v));
      req.add(utf8.encode(body));
      final res = await req.close().timeout(_kApiTimeout);
      // ⚠️ 体必须读完（否则连接不回收 ☑️）
      final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      // `dart:io` 的 `HttpHeaders` 本身大小写不敏感（MultiMap）⇒ 直接 join ✅
      final sc = res.headers['set-cookie']?.join(', ') ?? '';
      return (code: res.statusCode, setCookie: sc, body: bytes);
    } catch (e) {
      if (AppSettings.i.logConsole) {
        debugPrint('[SRC] ${_f.site.name} 回落 dart:io 请求异常（当失败 ✅）：$e');
      }
      return null;
    } finally {
      c.close(force: true); // ★ 用完即关（不留连接/不泄漏 ☠）
    }
  }

  /// ① 账号 cookie（`eden_account`）：拿不到 ⇒ null（调用方记日志 ✅ 不静默 ☑️）
  Future<String?> _ensureAccount() async {
    final cur = _acc;
    if (cur != null && cur.isNotEmpty) return cur;
    final sw = Stopwatch()..start();
    // ★ 2026-10-12（iOS 修 ✅）：两条请求**共用同一份头** ⇒ 主路径与 dart:io 回退**逐字一致** ✅
    final hdrs = <String, String>{
      'User-Agent': Site.ua,
      'Origin': _kBase,
      'Content-Type': 'application/json',
    };
    try {
      final r = await _f.client
          .post(
            Uri.parse('$_kBase/api/account/bootstrap'),
            headers: hdrs,
            body: '{}',
          )
          .timeout(_kApiTimeout);
      var code = r.statusCode;
      var len = r.bodyBytes.length;
      // ★ iOS 修 ①：**大小写不敏感 + 多值合并**（见 [_setCookieOf]）
      var v = _cookieValue(_setCookieOf(r.headers), 'eden_account');
      var src = '头(不敏感)';
      if (v == null) {
        // ★ iOS 修 ②：兜底重发（只在这一条"客户端已回话但没 cookie"时 ✅ —— Windows 不进这里 ✅）
        final fb = await _postViaIo('/api/account/bootstrap', hdrs, '{}');
        if (fb != null) {
          code = fb.code;
          len = fb.body.length;
          v = _cookieValue(fb.setCookie, 'eden_account');
          src = v == null ? '回落dart:io(仍无)' : '回落dart:io';
          if (AppSettings.i.logConsole) {
            debugPrint('[SRC] ${_f.site.name} 回退 bootstrap code=${fb.code} '
                '有cookie=${v != null}');
          }
        } else {
          src = '回落dart:io(失败)';
        }
      }
      if (AppSettings.i.logConsole) {
        // ⚠️ 只打"有没有 + 长度 + 来源"，**不打值** ☠
        debugPrint('[SRC] ${_f.site.name} ①bootstrap code=$code '
            'len=$len cookie=${v == null ? '无' : '有(len=${v.length})'} '
            '来源=$src ms=${sw.elapsedMilliseconds}');
      }
      if (code != 200 || v == null) return null;
      _acc = v;
      return v;
    } catch (e) {
      if (AppSettings.i.logConsole) {
        debugPrint('[SRC] ${_f.site.name} ①bootstrap 失败：$e');
      }
      return null;
    }
  }

  /// ② 某一集的播放凭证：返回 `{url, cookie}`（失败/异常 ⇒ null ✅ 调用方记日志 ✅）
  ///
  /// 成功时**顺手**把这一集的 [headersOf] 原地更新成新 cookie ✅（见那个方法的说明 ✅）。
  ///
  /// ⚠️ 状态码口径（**2026-10-11 修 S3** ✅ —— 原来 403/429 一律"整会话停手"，一触发后面全没源 ☠）：
  ///   · **403 ⇒ 只当"这一集取不到票"** ✅（该集无源）⇒ **继续处理其余集** ✅，日志 `403(该集无票)` ✅
  ///   · **429 ⇒ 冷却 [_kCool] 秒**（窗口内不再发 ② ✅、到点自动恢复 ✅），日志 `429(冷却 30s)` ✅
  ///   · 冷却期内被调到 ⇒ 直接跳过 + 日志 `跳过(429冷却 Ns)` ✅
  ///
  /// ★ 2026-10-12（**用户拍板"只走分片"** ✅ —— 一句话口径：**"柚子只走分片。就这样"**）：
  ///   · **一律 `mode=mse`**（拿 `master.m3u8` 当源）✅
  ///   · 依据：**分片实测比整段快 1.5~5 倍且更稳**（同集同窗口：分片 1329~3649 KB/s
  ///     vs 单文件 98~1723 KB/s ✅）；**新库下 fMP4 HLS 能跳**（4.1~7.0s 恢复、1× ✅）
  ///   · **代价（如实记）**：**旧库（iOS 现状）下 fMP4 HLS 远跳会坏** ☑️ —— 用户已拍板接受 ✅
  ///   · 因此**删掉**了 2026-10-11 那套"native 票 + 2 字节探测 + 按大小选路"（`_probeMp4` /
  ///     `_kNativeMaxBytes` / `_mb` 均已删除 ✅ 不留死代码 ☑️）；那套当时是为绕开"整段太大卡 00:00" ✅
  ///   · ⇒ **请求数下降**：每集 **1 次 POST**（原来 2~3 次：native 票 + 探测 + 可能的 mse 票 ✅），
  ///     而且**不再额外探测**（每集少 1 次 2 字节请求 ✅）
  Future<({String url, String cookie})?> _playback(String videoId) async {
    final cool = _coolLeft();
    if (cool > 0) {
      if (AppSettings.i.logConsole) {
        debugPrint('[SRC] ${_f.site.name} 跳过(429冷却 ${cool}s) vid=${_vid8(videoId)}');
      }
      return null;
    }
    final acc = await _ensureAccount();
    if (acc == null) return null;
    // 只走 mse ✅（2026-10-12 用户拍板）
    final t = await _ticket(videoId, acc);
    if (t == null) return null;
    // 票写进 headersOf（**原地更新** ✅ —— 见那个方法的说明 ✅）
    headersOf(videoId)['Cookie'] = 'eden_account=$acc; eden_play_$videoId=${t.cookie}';
    return (url: t.url, cookie: t.cookie);
  }

  /// ② 的**单次取票**（**2026-10-12 起固定 `mode=mse`** ✅ —— 用户拍板"只走分片"）：成功 ⇒ `{url, cookie}` ✅
  ///
  /// ⚠️ 403/429 口径与日志跟原来**同一套** ✅（403 不停手 ✅、429 记冷却 ✅）。
  ///
  /// ★ 2026-10-11（**按站方新要求补 `Referer`** ✅ —— 站点当天收紧过，依据 probe19 + 本机 curl）：
  ///   · 现在发：`Origin` + `Cookie: eden_account=…` + **`Referer` = 该集页面** ✅
  ///     （本机实测三组都 200：**无 Referer** ✅ · 季节页 ✅ · **该集页** ✅ —— 也就是说此刻 Referer
  ///      还不是**硬性**的 ☑️；但站方已出现过 `404 作品尚未上线` / `401 请刷新页面以恢复账户` 的收紧行为
  ///      （probe19 ✅），**无头浏览器里站方自己的播放器也只带 `referer` + `content-type`（不带 Origin）** ✅
  ///      ⇒ 补上 Referer 是"与浏览器一致 + 防再次收紧"的低风险动作 ✅，同时也**不删** `Origin`
  ///      （本机实测带 Origin 三组都 200 ✅ ⇒ 它**不会**导致失败 ✅ 就不动它 ☑️）。
  ///   · Referer 取 `_epUrl[videoId]`（**该集页面的真实绝对地址** ✅ —— 由 `detail()` 从页面上
  ///     `a.series-episode-link[href]` 抄下来 ✅，不自己拼 ☑️）；查不到才退 `$_kBase/`（兜底 ❓**未实测** ☑️）。
  ///   · ⚠️ `bootstrap` 那一步**不加 Referer** ✅：本机实测"只带 Origin"就 200 ✅；缺 Origin ⇒ **403
  ///     `请求来源无效，请刷新页面后重试`** ✅（实锤 ⇒ `Origin` 必须留 ✅）。
  Future<({String url, String cookie})?> _ticket(String videoId, String acc) async {
    final sw = Stopwatch()..start();
    // ★ 2026-10-12（iOS 修 ✅）：主路径与 dart:io 回退**共用同一份头** ⇒ 逐字一致 ✅
    //   （⚠️ 这里**保持 `mode=mse` 不变** ✅ —— 平台选路已回滚，仍是"只走分片" ✅）
    final hdrs = <String, String>{
      'User-Agent': Site.ua,
      'Origin': _kBase,
      'Content-Type': 'application/json',
      // ★ 站方新要求（2026-10-11 ✅）：Referer = **该集页面**（浏览器同款 ✅）
      'Referer': _epUrl[videoId] ?? '$_kBase/',
      // ⚠️ ② 只需要账号 cookie（实测 ✅）；播放 cookie 是这一步**发下来**的 ✅
      'Cookie': 'eden_account=$acc',
    };
    try {
      final r = await _f.client
          .post(
            // ★ 2026-10-12（用户拍板 ✅）：**固定 `mode=mse`**（分片，快 1.5~5 倍且更稳 ✅）；
            //   `mode=native`（整段 MP4）那条已按用户口径弃用 ☑️（代价：旧库 iOS 下远跳会坏 ✅）。
            //   ⚠️ 响应只有 `url` + `expires_at`（实测 ✅ —— `mse` 也没有 `startup` ✅）⇒ 只读 `url` ✅。
            Uri.parse('$_kBase/api/playback/$videoId?mode=mse'),
            headers: hdrs,
            body: '{}',
          )
          .timeout(_kApiTimeout);
      var code = r.statusCode;
      List<int> bodyBytes = r.bodyBytes;
      // ★ iOS 修 ①：**大小写不敏感 + 多值合并**（见 [_setCookieOf]）
      var pc = _cookieValue(_setCookieOf(r.headers), 'eden_play_$videoId');
      var src = '头(不敏感)';
      if (pc == null) {
        // ★ iOS 修 ②：兜底重发（只在"客户端已回话但没 cookie"时 ✅ —— Windows 不进这里 ✅）
        final fb = await _postViaIo(
            '/api/playback/$videoId?mode=mse', hdrs, '{}');
        if (fb != null) {
          code = fb.code;
          bodyBytes = fb.body;
          pc = _cookieValue(fb.setCookie, 'eden_play_$videoId');
          src = pc == null ? '回落dart:io(仍无)' : '回落dart:io';
          if (AppSettings.i.logConsole) {
            debugPrint('[SRC] ${_f.site.name} 回退 取票 code=${fb.code} '
                '有cookie=${pc != null} vid=${_vid8(videoId)}');
          }
        } else {
          src = '回落dart:io(失败)';
        }
      }
      // ★ 修 S3：403 **不再**停手（只为"这一集没票" ✅）；429 记冷却窗口（到点自动恢复 ✅）
      final is403 = code == 403;
      final is429 = code == 429;
      if (is429) _coolUntil = DateTime.now().add(_kCool);
      // ★ 2026-10-11：**把站方那句错因打出来** ✅（`404 作品尚未上线` / `401 请刷新页面以恢复账户`
      //   这类误报要能一眼看见 ☑️）—— 只取响应体里的 `error` 字段（**不含 cookie/地址** ✅，
      //   截 40 字防刷屏 ✅）；**不做判断分支**：仍走现有"该集无源"路径 ✅
      var srvErr = '';
      if (code != 200) {
        try {
          final b = jsonDecode(utf8.decode(bodyBytes));
          srvErr = (b is Map) ? '${b['error'] ?? ''}'.trim() : '';
        } catch (_) {
          // 体不是 JSON（或为空）⇒ 没话可说 ✅ 不静默：上面 code= 那行已经打了 ✅
        }
        if (srvErr.length > 40) srvErr = srvErr.substring(0, 40);
      }
      if (AppSettings.i.logConsole) {
        // ⚠️ 只打 vid 前 8 字 / mode / 来源 / 码 / 字节 / ms / 站方错因 —— **不打 cookie、不打地址** ☠
        debugPrint('[SRC] ${_f.site.name} 取流 vid=${_vid8(videoId)} mode=mse（本站只走分片）'
            '来源=$src '
            'code=$code len=${bodyBytes.length} '
            'play=${pc == null ? '无' : '有(len=${pc.length})'} ms=${sw.elapsedMilliseconds}'
            '${srvErr.isEmpty ? '' : ' 站方说=「$srvErr」'}'
            '${is429 ? ' ⇒ 429(冷却 ${_kCool.inSeconds}s)' : (is403 ? ' ⇒ 403(该集无票)' : '')}');
      }
      if (code != 200 || pc == null) return null;
      final j = jsonDecode(utf8.decode(bodyBytes));
      final u = (j is Map) ? '${j['url'] ?? ''}'.trim() : '';
      if (u.isEmpty) return null;
      return (url: _abs(u), cookie: pc);
    } catch (e) {
      if (AppSettings.i.logConsole) {
        debugPrint('[SRC] ${_f.site.name} 取流 失败：$e');
      }
      return null;
    }
  }

  /// 有界并发（3 路 ✅）批量取凭证：`videoId → 视频地址（分片 `master.m3u8` ✅）`（拿不到的就不进表 ✅ 不静默：日志在上面 ✅）
  ///
  /// ⚠️ 修 S3 ✅：**403 不再中断**（`_playback` 自己返回 null，循环照旧往下走 ✅）；
  ///   只有 **429 的冷却窗口**会让本次提前收手（且**到点自动恢复** ✅，不留永久开关 ☑️）。
  Future<void> _fillPlayback(List<String> vids, Map<String, String> out) async {
    for (var i = 0; i < vids.length;) {
      final cool = _coolLeft();
      if (cool > 0) {
        if (AppSettings.i.logConsole) {
          debugPrint('[SRC] ${_f.site.name} 跳过(429冷却 ${cool}s) ⇒ 剩余 ${vids.length - i} 集本次不再取票');
        }
        break;
      }
      final end = (i + 3) > vids.length ? vids.length : (i + 3);
      final batch = vids.sublist(i, end);
      i = end;
      final rs = await Future.wait([for (final v in batch) _playback(v)]);
      for (var k = 0; k < batch.length; k++) {
        final r = rs[k];
        if (r != null && r.url.isNotEmpty) out[batch[k]] = r.url;
      }
    }
  }

  // ===== 二、公共小工具 =====

  /// ★ 伪地址（**本站专属形态** ✅）：`/yz/play/<videoId>/<nonce>/`
  ///
  /// 用途：填 `ArticleVideo.lazyUrl` ✅ —— 切到那一集时播放器把它**原样**交给 [fetchSources] ✅。
  ///
  /// ⚠️ 为什么必须带 `nonce`（依据 `base/source_cache.dart` ✅ 逐行看过）：
  ///   · 缓存键 = **URL 字符串**（`_map` `:25` / `:37` ✅）⇒ 站点前缀只能防"**跨站**撞键" ✅；
  ///   · 该缓存**没有 TTL**、**命中还会续命**（LRU：`remove`+`set` `:39` ✅）⇒ 伪地址若固定，
  ///     20 分钟后切回同一集，拿到的还是**过期那把票**（票只 15 分钟 ☠）；
  ///   · 带 `nonce` ⇒ 每次 `detail()` 生成的伪地址都是**新键** ⇒ [fetchSources] **每次都真发 POST** ✅
  ///     （宁可多一次请求，也要新票 ✅ —— 用户口径 ✅）。
  ///   ⚠️ `nonce` = **微秒时间戳 + 静态自增序号** ⇒ 跨实例也唯一 ✅。
  ///   ⚠️ 它**不是**站上真实路径 ☑️（本站没有 `/yz/…` 路由）—— 不该被 GET ✅
  ///     （真被 GET 了 = 404 ⇒ 当"没取到源" ✅ 不会假装成功 ✅）。
  static String _playLazyUrl(String videoId) =>
      '/yz/play/$videoId/${DateTime.now().microsecondsSinceEpoch}-${_nonce++}/';

  /// ★ **站点自有"按地址取源"**（走公共钩子 `SiteUi.fetchSources` ✅）：伪地址 ⇒ videoId ⇒
  ///   [_playback]（内部已含 ① bootstrap / `403(该集无票)` / `429(冷却)` 口径 ✅）⇒
  ///   票写进 [headersOf]（**原地更新** ✅）⇒ 返回**这一集**的媒体地址 ✅。
  ///
  /// ⚠️ 返回 `null` = **不是本站伪地址** ⇒ 交回底座老路 ✅（其它形态零影响 ✅）；
  ///   取不到票 ⇒ 返回**空列表**（"这一集已失效" ✅ 不静默 ☑️；详情路 `SourceCache` **空结果不缓存** ✅
  ///   ⇒ 再点一次还会重试 ✅）。
  @override
  Future<List<String>?> fetchSources(String url) async {
    final m = RegExp(r'^/yz/play/([0-9a-fA-F\-]{8,64})/').firstMatch(url);
    if (m == null) return null;
    final vid = m.group(1)!;
    _lastVid = vid; // ★ 记住"用户正在看的那一集"（刷新兜底靠它 ✅）
    final t = await _playback(vid);
    if (t == null) {
      if (AppSettings.i.logConsole) {
        debugPrint('[SRC] ${_f.site.name} 按集取 没票 vid=${_vid8(vid)} ⇒ 0 条');
      }
      return const <String>[];
    }
    if (AppSettings.i.logConsole) {
      debugPrint('[SRC] ${_f.site.name} 按集取 拿到票 vid=${_vid8(vid)} ⇒ 1 条');
    }
    return <String>[t.url];
  }

  /// 绝对地址（本站的卡片/封面都是相对路径 ✅）
  String _abs(String u) {
    final s = u.trim();
    if (s.isEmpty) return '';
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    return s.startsWith('/') ? '$_kBase$s' : '$_kBase/$s';
  }

  /// 站内**路径**（去掉域名 + 保留 query ✅ —— 本项目的 `Article.url` 一律是站内路径 ✅）
  String _path(String u) {
    final s = u.trim();
    if (s.isEmpty) return '';
    if (!s.startsWith('http')) return s;
    final x = Uri.tryParse(s);
    if (x == null) return s;
    return x.query.isEmpty ? x.path : '${x.path}?${x.query}';
  }

  /// 一张 `article.drama-card` → [Article]（找不到标题/路径 ⇒ null ✅）
  Article? _card(dom.Element el) {
    final tEl = el.querySelector('.drama-card-title a');
    final title = (tEl?.attributes['title'] ?? tEl?.text ?? '').trim();
    final href = _path(el.querySelector('a.drama-card-cover')?.attributes['href'] ??
        tEl?.attributes['href'] ??
        '');
    if (title.isEmpty || href.isEmpty) return null;
    // ⚠️ 封面来源有**两种写法**（2026-10-11 实测 ✅，用户报的"第一行 3 张没封面"就是这个 ☠）：
    //   ① **懒加载卡**（片段第 4 张起 ✅）：`<picture data-deferred-image>` 且 `src` 是
    //      **1×1 占位 svg**（`data:image/svg+xml,…`）☠ ⇒ 真图只在 **`data-image-src`** ✅
    //   ② **首屏直出卡**（片段**第 1 行那 3 张** ✅ 实测下标 0/1/2 ✅）：**没有** `data-image-src`，
    //      真图直接在 `<img src="/catalogue-art/…-960.webp" loading="eager" fetchpriority="high">` ✅
    //   ⇒ 只认 `data-image-src` 会把这 3 张解析成**空封面** ✗（已修 ✅）
    //   ③ 优先级：`data-image-src` ⇒ `data-image-srcset` 首项 ⇒ **`src`（但必须是真图**：
    //      空串与 `data:` 开头的占位 svg **一律丢掉** ✅ 别把占位当封面 ☠）
    //   ⚠️ 首页那 56 张卡**全都有** `data-image-src`（实测 ✅）⇒ 首页分区不受影响 ✅
    final img = el.querySelector('img[data-image-src]') ??
        el.querySelector('img[data-image-srcset]') ??
        el.querySelector('img');
    var cover = (img?.attributes['data-image-src'] ?? '').trim();
    if (cover.isEmpty) {
      final set = (img?.attributes['data-image-srcset'] ?? '').trim();
      if (set.isNotEmpty) {
        cover = set.split(',').first.trim().split(' ').first.trim();
      }
    }
    if (cover.isEmpty) {
      final raw = (img?.attributes['src'] ?? '').trim();
      if (raw.isNotEmpty && !raw.startsWith('data:')) cover = raw;
    }
    final status = (el.querySelector('span.drama-card-status')?.text ?? '').trim();
    final eps = (el.querySelector('span.drama-poster-episodes')?.text ?? '').trim();
    final heat = (el.querySelector('.drama-card-meta span[title]')?.text ?? '').trim();
    final meta = [status, heat].where((s) => s.isNotEmpty).join(' · ');
    return Article(
      title: title,
      url: href,
      cover: _abs(cover),
      meta: meta,
      badge: eps,
      coverAspect: 9 / 16, // 站上海报 9:16 ✅（实测）
    );
  }

  /// 一个范围内所有卡片（顺序照站上 ✅）
  ///
  /// ⚠️ `package:html` 里 `Document` 与 `Element` 都**不是**对方（共同的父类型是私有的 ☠）
  ///   ⇒ 分两个入口（整页 / 局部 ✅）—— 本项目别站也是这么分开写的 ✅。
  List<Article> _cards(dom.Document doc) =>
      _fromEls(doc.querySelectorAll('article.drama-card'));

  /// 局部范围（`section.home-section` / `.series-recommendations` ✅）
  List<Article> _cardsIn(dom.Element scope) =>
      _fromEls(scope.querySelectorAll('article.drama-card'));

  List<Article> _fromEls(List<dom.Element> els) {
    final out = <Article>[];
    for (final el in els) {
      final a = _card(el);
      if (a != null) out.add(a);
    }
    return out;
  }

  // ===== 三、首页（5 个分区，每区带「更多」）=====

  /// 首页 5 个分区（标题 + 「更多」目标 + 该区卡片 ✅）
  ///
  /// 看：解析出几个分区、每区几条 —— 0 个就是首页 SSR 结构变了（`section.home-section` 那套 ✅）。
  Future<List<YzSection>> homeSections() async {
    final sw = Stopwatch()..start();
    final html = await _f.text('/');
    final doc = hp.parse(html);
    final out = <YzSection>[];
    for (final sec in doc.querySelectorAll('section.home-section')) {
      final h2a = sec.querySelector('.catalogue-section-heading h2 a');
      final title = (h2a?.text ?? '').trim();
      final moreA = sec.querySelector('a.catalogue-section-more');
      final more = _path(moreA?.attributes['href'] ?? h2a?.attributes['href'] ?? '');
      final items = _cardsIn(sec);
      if (title.isEmpty || items.isEmpty) continue;
      out.add(YzSection(title: title, more: more, items: items));
    }
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 入口=首页 分区=${out.length} '
          '每条=${out.isEmpty ? 0 : out.first.items.length} ms=${sw.elapsedMilliseconds}');
    }
    return out;
  }

  // ===== 四、剧库（片段接口 + 分类/排序/分页）=====

  /// 剧库列表（走**片段接口** ✅）：`sort` = updated/popular ✅、`category` = slug 或空 ✅、`page` 从 1 起 ✅
  ///
  /// 看：分类/排序/页码 + 条数 + `data-total/data-pages` —— 0 条就是"这个组合没有内容"（或 slug 变了 ✅）。
  Future<({List<Article> items, int total, int pages, int page})> browse({
    String sort = 'updated',
    String category = '',
    int page = 1,
  }) async {
    final sw = Stopwatch()..start();
    final url = '$_kBase/api/catalogue/browse'
        '?sort=$sort&category=$category&page=$page&navigation=1';
    try {
      final r = await Site.httpClient
          .get(Uri.parse(url), headers: {
            'User-Agent': Site.ua,
            'Accept': 'text/html',
          })
          .timeout(const Duration(seconds: 15)); // 片段 49KB ⇒ 给宽一点（同本站列表口径 ✅）
      if (r.statusCode != 200) {
        // ⚠️ 页码越界时站上就回 **404**（实测 ✅）⇒ 第 2 页起当"没有更多了" ✅；
        //   第 1 页仍**照错抛** ☑️（免得把 slug 打错当成空列表 ✅）
        if (page > 1 && r.statusCode == 404) {
          if (AppSettings.i.logConsole) {
            debugPrint('[LIST] ${_f.site.name} 入口=剧库 分类=$category 排序=$sort '
                '页=$page ⇒ 404（越界）当没有更多');
          }
          return (items: const <Article>[], total: 0, pages: page - 1, page: page);
        }
        final e = Exception('HTTP ${r.statusCode}');
        await SiteErrorLog.log(_f.site.name,
            '剧库 分类=$category 排序=$sort 页=$page ${e.toString()}');
        throw e;
      }
      final doc = hp.parse(utf8.decode(r.bodyBytes));
      final rootEl = doc.querySelector('[data-browse-response]');
      final items = rootEl == null ? _cards(doc) : _cardsIn(rootEl);
      final pagesRaw = (rootEl ?? doc).attributes['data-pages'] ?? '';
      final totalRaw = (rootEl ?? doc).attributes['data-total'] ?? '';
      final pages = int.tryParse(pagesRaw) ?? (items.isEmpty ? page : page + 1);
      final total = int.tryParse(totalRaw) ?? items.length;
      if (AppSettings.i.logConsole) {
        debugPrint('[LIST] ${_f.site.name} 入口=剧库 分类=${category.isEmpty ? '(全部)' : category} '
            '排序=$sort 页=$page/$pages 条=${items.length} 共=$total ms=${sw.elapsedMilliseconds}');
      }
      return (items: items, total: total, pages: pages, page: page);
    } catch (e) {
      if (AppSettings.i.logConsole) {
        debugPrint('[SRC] ${_f.site.name} 剧库 分类=$category 排序=$sort 页=$page 失败：$e');
      }
      rethrow; // ☑️ 照旧抛给调用方（不吞）
    }
  }

  /// 「更多」页取数 —— **两种形态**（站上就是这样 ✅）：
  ///  · `/tags/<slug>/` ⇒ SSR 整页（实测 8 条、**没有翻页** ✅ ⇒ 只认第 1 页 ✅）
  ///  · `/dramas/…`（含 `?sort=` 与 `/dramas/category/<slug>/`）⇒ 走 [browse] 片段接口（可分页 ✅）
  Future<({List<Article> items, int total, int pages, int page, String title})>
      listPage(String path, int page) async {
    final p = _path(path);
    if (p.startsWith('/tags/')) {
      final sw = Stopwatch()..start();
      final html = await _f.text(p);
      final doc = hp.parse(html);
      final items = _cards(doc);
      final title = (doc.querySelector('h1')?.text ?? '').trim();
      if (AppSettings.i.logConsole) {
        debugPrint('[LIST] ${_f.site.name} 入口=标签页 $p 条=${items.length} '
            'ms=${sw.elapsedMilliseconds}（本站标签页无翻页 ⇒ 只第 1 页有数据）');
      }
      return (
        items: page > 1 ? const <Article>[] : items,
        total: items.length,
        pages: 1,
        page: page,
        title: title,
      );
    }
    final uri = Uri.tryParse(p);
    final sort = uri?.queryParameters['sort'] ?? 'updated';
    final cat = RegExp(r'^/dramas/category/([^/]+)/?')
            .firstMatch(uri?.path ?? '')
            ?.group(1) ??
        '';
    final r = await browse(sort: sort, category: cat, page: page);
    return (
      items: r.items,
      total: r.total,
      pages: r.pages,
      page: r.page,
      title: '',
    );
  }

  /// 标签列表页 `/tags/<slug>/`（站上**单页** ☑️ 别承诺翻页 ☑️ —— 第 2 页起返回空 ✅ 不静默 ☑️）
  @override
  Future<List<Article>> tag(String slug, {required int page}) async {
    if (page > 1) {
      if (AppSettings.i.logConsole) {
        debugPrint('[LIST] ${_f.site.name} 入口=标签 slug=$slug 页=$page ⇒ 本站标签页无翻页，返回 0 条');
      }
      return [];
    }
    final html = await _f.text('/tags/${Uri.encodeComponent(slug)}/');
    final out = _cards(hp.parse(html));
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 入口=标签 slug=$slug 条=${out.length}');
    }
    return out;
  }

  /// 搜索（★ 2026-10-12 **新增** ✅ —— 用户口径："柚子的搜索功能被你吃了？右上角搜索你没做"）：
  ///   `GET /search/?q=<关键词>` —— **单页** ✅（本机实测：**200** / 30124 字节 / **3 张 `article.drama-card`** /
  ///   页面**没有任何分页链接** ⇒ 单页，口径同黄果 ✅）⇒ **复用本站 [_cards] 解析** ✅
  ///   （结果卡与首页/剧库**同一套标记** ✅：`article.drama-card` → 标题 / 封面 / 状态 / 集数 / 热度 ✅）。
  ///
  /// ⚠️ 两条**限制（实测，不猜）**：
  ///   1. 站上 `h1` = 「搜索短剧、专题和工作室」⇒ **还搜专题 / 工作室**，但那些卡**不是**
  ///      `article.drama-card` 标记 ⇒ **本站只收短剧卡** ☑️（专题 / 工作室结果看不到 ✅ 如实记）。
  ///   2. 搜索结果的去向是 **`/dramas/<slug>/season-1/`（season 页）**；实测该页 **`ld+json` 的 `@type`
  ///      是 `TVSeason`（不是 `TVSeries`）** ⇒ 原先 `detail()` 只认 `TVSeries`
  ///      ⇒ 那儿的**简介与「共 N 集」会为空** ☑️；**2026-10-12 用户批准放宽判据后已修好** ✅
  ///      （`detail()` 现在 `TVSeries` / `TVSeason` 都收 ✅ —— 详见那边注释 ✅）。
  ///
  /// 看：解析出几条 —— 0 条就是"没搜到"（或卡片选择器变了 ✅）。
  @override
  Future<List<Article>> search(String keyword,
      {int page = 1, List<MapEntry<String, String>>? extra}) async {
    final sw = Stopwatch()..start();
    if (page > 1) {
      // 单页口径（同黄果 ✅）—— 站点没有第 2 页 ✅ 不静默 ☑️
      if (AppSettings.i.logConsole) {
        debugPrint('[LIST] ${_f.site.name} 入口=搜索 页=$page ⇒ 本站搜索无翻页，返回 0 条');
      }
      return [];
    }
    final html = await _f.text('/search/?q=${Uri.encodeComponent(keyword)}');
    final out = _cards(hp.parse(html));
    if (AppSettings.i.logConsole) {
      // ⚠️ 关键词**只打长度**（不打全文 ☠ —— 沿用既有口径 ✅）
      debugPrint('[LIST] ${_f.site.name} 入口=搜索 页=$page kwLen=${keyword.length} '
          '条=${out.length} ms=${sw.elapsedMilliseconds}');
    }
    return out;
  }

  // ===== 五、详情（SSR 解析 + 每集现取凭证 ✅）=====

  /// 详情入口（`Api.detail` → 本方法 ✅）
  ///
  /// 看：几集、**几集拿到凭证**、标签/相关各几条、耗时 —— 详情页空白或"取不到源"时先看这几行。
  ///   ★ 口径：**每次加载都重跑 ②**（凭证 15 分钟 ✅）⇒ 地址进 `sources` ⇒ 播放器"刷新源"
  ///     （= 重抓详情 ✅）对**每一集**都有效 ✅（与野果那次同一口径 ✅）。
  @override
  Future<ArticleDetail> detail(String url) async {
    final sw = Stopwatch()..start();
    final path = _path(url);
    if (!path.startsWith('/dramas/')) {
      throw Exception('柚子短剧：详情路径不对（$path）');
    }
    final html = await _f.text(path);
    final doc = hp.parse(html);

    // ---- ld+json（**`TVSeries` 或 `TVSeason`** ✅ —— 2026-10-12 用户批准放宽，见下）----
    var title = '';
    var intro = '';
    var cover = '';
    var total = 0;
    for (final s in doc.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        final j = jsonDecode(s.text);
        // ★ 2026-10-12（**用户批准 ✅**）：判据从"只认 `TVSeries`"**放宽成 `TVSeries` 或 `TVSeason`** ——
        //   · **首页 / 剧库**进的详情 = `/dramas/<slug>/` ⇒ 实测 `@type` = **`TVSeries`** ✅
        //   · **搜索结果**进的详情 = `/dramas/<slug>/season-1/` ⇒ 实测 `@type` = **`TVSeason`**
        //     （`numberOfEpisodes=10`、`description` 85 字**都在** ✅ —— 数据没少，是判据太窄 ☑️）
        //   ⇒ 放宽后"从搜索进去的详情"也能拿到**简介 + 「共 N 集」** ✅
        //     （标题靠 `h1` 兜底、选集 10 条、每集 videoId、`data-paid` **本来就正常** ✅）
        final t = (j is Map) ? '${j['@type']}' : '';
        if (j is Map && (t == 'TVSeries' || t == 'TVSeason')) {
          title = '${j['name'] ?? ''}'.trim();
          intro = '${j['description'] ?? ''}'.trim();
          cover = _abs('${j['image'] ?? ''}');
          total = (j['numberOfEpisodes'] as num?)?.toInt() ?? 0;
          break;
        }
      } catch (_) {
        // 解析不了就跳过（不静默：下面 title 为空会记日志 ✅）
      }
    }
    if (title.isEmpty) title = (doc.querySelector('h1')?.text ?? '').trim();

    // ---- 集清单（⚠️ 按 `data-analytics-video` **去重** ✅ —— 实测同一集会重复出现 ✅）----
    //   集号优先取站上 `aria-label` 里的「第 N 集」（实测形态：`第 1 集 初见岳母，准女婿当场被查底` ✅），
    //   拿不到才用出现顺序兜底 ✅（站上链接文字就是 `01`/`02`… ✅，顺序与集号一致 ✅）
    //   ★ 修 S3 ✅：顺手读集链接上的 **`data-paid`**（站上**唯一**的"这把要不要票"标记 ✅）——
    //     实测 4 部剧 57 条链接**全是 `false`** ✅（且站上"N集可看" == 详情里唯一 videoId 数 ==
    //     `numberOfEpisodes` ✅ ⇒ **未解锁的集压根不列出来** ✅）；`true` 样本**一个都没见到** ❓
    //     ⇒ 只认 `true`/`1`/`yes` 三个真值，**认不出的值一律当"可播"**（fail-open ☑️ 不许误杀 ✅）。
    final vids = <String>[];
    final ords = <int>[];
    final locks = <bool>[]; // 与 vids/ords 一一对应 ✅
    final seen = <String>{};
    for (final a in doc.querySelectorAll('a.series-episode-link')) {
      final vid = (a.attributes['data-analytics-video'] ?? '').trim();
      if (vid.isEmpty || !seen.add(vid)) continue;
      final aria = (a.attributes['aria-label'] ?? '').trim();
      final n = int.tryParse(
              RegExp(r'第\s*(\d+)\s*集').firstMatch(aria)?.group(1) ?? '') ??
          0;
      final paid = (a.attributes['data-paid'] ?? '').trim().toLowerCase();
      // ★ 站方新要求（2026-10-11 ✅）：把**该集页面的真实地址**记下来 ⇒ 取票时当 `Referer` ✅
      final epHref = (a.attributes['href'] ?? '').trim();
      if (epHref.isNotEmpty) _epUrl[vid] = _abs(epHref);
      vids.add(vid);
      ords.add(n > 0 ? n : vids.length);
      locks.add(paid == 'true' || paid == '1' || paid == 'yes');
    }

    // ---- 修 S3 ✅：**未解锁的集先跳过**（压根**不发** ② ✅）----
    final skipOrds = <int>[];
    for (var i = 0; i < vids.length; i++) {
      if (locks[i]) skipOrds.add(ords[i]);
    }
    if (skipOrds.isNotEmpty && AppSettings.i.logConsole) {
      debugPrint('[SRC] ${_f.site.name} 跳过(未解锁) 集=${skipOrds.join(',')} '
          '共${skipOrds.length}集（未发 ② 请求）');
    }

    // ---- ★ 2026-10-11（用户批准"甲/不预取" ✅）：**只给第 1 集取票**（1 次 POST ✅）----
    //   其余集**不预取、不后台补** ✅ —— `sources` 空 + `lazyUrl` = 伪地址（[_playLazyUrl] ✅）
    //   ⇒ **切到那一集时才取**（播放器会亮"正在取视频…" ✅：`player_widget.dart:1332-1375` ✅）。
    //   为什么改（事实依据 ✅）：老写法对**每一集**都发 POST（3 路并发）⇒ 42 集 ≈ 14 波 ⇒ 详情页等十几秒 ☠。
    //   ⚠️ 例外一条（**刷新兜底** ✅）：`detail()` 被"播放失败 ⇒ 刷新源"重跑时（`detail_page.dart:465` ✅），
    //     若用户在别的集上（`_lastVid` ✅ 由 [fetchSources] 记下），就**只多补那一集**的票 ⇒
    //     `_refreshSources` 能返回**新鲜地址** ⇒ `_recover` 才救得回来 ✅（否则它拿空 ⇒ 退回旧源 ☠）。
    //   ⇒ 每次 `detail()` 的 POST 数 = **1（第 1 集）+ 0~1（正在看的那一集）** ✅ 仍是"秒开" ✅。
    final need = <String>[]; // 现在就要票的（≤2 条 ✅）
    if (vids.isNotEmpty && !locks[0]) need.add(vids[0]);
    final lastVid = _lastVid;
    if (lastVid != null && vids.contains(lastVid)) {
      final li = vids.indexOf(lastVid);
      if (!locks[li] && !need.contains(lastVid)) need.add(lastVid);
    }
    final urls = <String, String>{}; // videoId → 视频地址（分片 master.m3u8 ✅）
    await _fillPlayback(need, urls);

    final videos = <ArticleVideo>[];
    for (var i = 0; i < vids.length; i++) {
      final vid = vids[i];
      final u = urls[vid] ?? '';
      // 没票的集（第 2 集起 ✅）⇒ **伪地址**（切到那一集时 [fetchSources] 现取 ✅）；
      // 未解锁的**不给伪地址** ☑️（取也白取 ⇒ 保持"点不动"的形态 ✅）
      final lazy = (u.isEmpty && !locks[i]) ? _playLazyUrl(vid) : null;
      videos.add(ArticleVideo(
        label: '第 ${ords[i]} 集',
        ordinal: ords[i],
        sources: u.isEmpty ? const <String>[] : <String>[u],
        lazyUrl: lazy,
        // ★ 这一集的额外头（**实例稳定** ✅ —— [fetchSources] 取到票后**原地更新**这个 Map
        //   ⇒ 播放器 `open` 那一刻读到的是**新** cookie ✅）
        //   ⚠️ 未解锁的集**没取票** ⇒ 不给头 ☑️（`null` = 等于不带 ✅）
        headers: locks[i] ? null : headersOf(vid),
      ));
    }

    // ---- 标签（站上是**名字** ✅ ⇒ `/tags/<slug>/`，自带 [tag] 实现 ✅）----
    final tags = <MapEntry<String, String>>[];
    final seenTag = <String>{};
    for (final a in doc.querySelectorAll('a[href*="/tags/"]')) {
      final slug = RegExp(r'^/tags/([^/]+)/?')
          .firstMatch(_path(a.attributes['href'] ?? ''))
          ?.group(1);
      if (slug == null || slug.isEmpty || !seenTag.add(slug)) continue;
      final name = a.text.trim();
      tags.add(MapEntry(slug, name.isEmpty ? slug : name));
    }

    // ---- 相关推荐（`.series-recommendations` 里的卡片 ✅）----
    final related = <Article>[];
    final relScope = doc.querySelector('.series-recommendations');
    if (relScope != null) related.addAll(_cardsIn(relScope));

    if (AppSettings.i.logConsole) {
      debugPrint('[DETAIL] ${_f.site.name} path=$path 集=${videos.length} '
          '未解锁=${skipOrds.length} 取票=${need.length}（其余按需） '
          '有源=${videos.where((v) => v.sources.isNotEmpty).length} '
          '相关=${related.length} 标签=${tags.length} 封面=${cover.isEmpty ? '无' : '有'} '
          'ms=${sw.elapsedMilliseconds}');
    }
    return ArticleDetail(
      title: title,
      time: '', // 站上 ld+json 里**没有**发布时间（实测键里没有 ✅）⇒ 不塞 ☑️
      categories: const [],
      images: const [], // 站上没有剧照 ✅（海报就是封面 ✅）
      intro: intro,
      videos: videos,
      tags: tags,
      related: related,
      seriesPrefix: '',
      // 元信息行：集数是站上 ld+json 的真字段 ✅（拿不到就留空 ⇒ 那一行不显示 ✅）
      metaLine: total > 0 ? '共 $total 集' : '',
    );
  }

  /// 自管整页（底座唯一使用点 = `home_page.dart:580` ✅）
  @override
  Widget? sitePage(BuildContext context, SiteEntry site) =>
      YzHomePage(site: site, ui: this);
}

// ===== 六、本站清单（只写在本文件里 ✅ 不给别站用 ✅）=====

/// 首页一个分区行（标题 + 「更多」目标 + 该区卡片 ✅）
class YzSection {
  YzSection({required this.title, required this.more, required this.items});

  final String title;

  /// 「更多」的目标 = **站内路径**（如 `/dramas/?sort=popular` ✅），空串 = 不显示「更多」☑️
  final String more;
  final List<Article> items;
}

// ===== 七、界面（**自管整页** ✅：两主 tab = 首页 / 剧库 ✅）=====

/// 本站主色（选中态那点橙 ✅ —— 与全 App 的选中色一致 ✅）
const Color _kAccent = Color(0xFFE8590C);

/// 胶囊底（未选中，压在背景图上 ✅）
const Color _kChipBg = Color(0xFFF0F0F2);

/// 柚子短剧站点页（**自管整页** ✅ —— 首页 / 剧库 照真站 ✅）
///
/// 底座里**唯一**的使用点：`home_page.dart:580` 那句 `_api.ui?.sitePage(...)` ✅
/// （那里**只判断"要不要用"** ☑️ 不认站名 ✅ ⇒ 本页不影响任何别的站点 ✅）。
class YzHomePage extends StatefulWidget {
  const YzHomePage({super.key, required this.site, required this.ui});

  final SiteEntry site;
  final YouziSite ui;

  @override
  State<YzHomePage> createState() => _YzHomePageState();
}

class _YzHomePageState extends State<YzHomePage> {
  @override
  Widget build(BuildContext context) {
    // 整页跟着背景明暗重建（标题/tab/胶囊/空态文字都读 kTxt ✅ —— 同 home_page 那套 ✅）
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: Colors.transparent, // 透明：让根层背景图透出来 ✅
          appBar: AppBar(
            systemOverlayStyle: kStatusOverlay,
            title: Text(widget.site.name),
            centerTitle: true,
            foregroundColor: kTxt,
            // ★ 2026-10-12（用户口径："右上角搜索你没做" ✅）：右上角搜索图标 ——
            //   点它 push **底座的通用搜索页** `SearchPage`（`home_page.dart:1351` ✅ public、只吃 site ✅）
            //   ⇒ 输入框 / 空态「无结果」/ 竖屏站 3 列 `ArticleCard` / 上拉到底提示 **全部白拿** ✅，
            //   而**零公共区改动** ✅（它内部只调 `Api.search` ⇒ 落到本站 [search] ✅）。
            actions: [
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: '搜索',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    settings: const RouteSettings(name: '搜索页'),
                    builder: (_) => PageBg(child: SearchPage(site: widget.site)),
                  ),
                ),
              ),
            ],
            bottom: TabBar(
              indicatorColor: _kAccent,
              dividerColor: Colors.transparent,
              labelColor: AppBg.i.isDark ? const Color(0xFFFFB07A) : _kAccent,
              unselectedLabelColor:
                  AppBg.i.isDark ? Colors.white : const Color(0xFF3A3A3A),
              tabs: const [
                Tab(text: '首页'),
                Tab(text: '剧库'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _YzHomeTab(site: widget.site, ui: widget.ui),
              _YzLibTab(site: widget.site, ui: widget.ui),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- 首页 tab：5 个分区行（每行横滑 + 「更多 ›」✅）----

class _YzHomeTab extends StatefulWidget {
  const _YzHomeTab({required this.site, required this.ui});

  final SiteEntry site;
  final YouziSite ui;

  @override
  State<_YzHomeTab> createState() => _YzHomeTabState();
}

class _YzHomeTabState extends State<_YzHomeTab> {
  late Future<List<YzSection>> _f = _load();

  Future<List<YzSection>> _load() async {
    try {
      return await widget.ui.homeSections();
    } catch (e) {
      // ☑️ 不许静默：失败原因写在页面上（[_YzFail] ✅），日志里也留一行 ✅
      if (AppSettings.i.logConsole) {
        debugPrint('[UI] ${widget.site.name} 首页 tab 取数失败：$e');
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<YzSection>>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _YzHint('加载中…');
        }
        if (snap.hasError) {
          return _YzFail('${snap.error}',
              onRetry: () => setState(() => _f = _load()));
        }
        final secs = snap.data ?? const <YzSection>[];
        if (secs.isEmpty) return const _YzHint('暂时没有内容');
        return ListView(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 22),
          children: [for (final s in secs) _section(s)],
        );
      },
    );
  }

  Widget _section(YzSection s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 8, 2, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: kTxt),
                ),
              ),
              if (s.more.isNotEmpty)
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      settings: const RouteSettings(name: '柚子更多页'),
                      builder: (_) => PageBg(
                        child: _YzListPage(
                          site: widget.site,
                          ui: widget.ui,
                          path: s.more,
                          title: s.title,
                        ),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text('更多 ›',
                        style: TextStyle(fontSize: 13, color: kTxtSub)),
                  ),
                ),
            ],
          ),
        ),
        // 每行横滑（照真站的 rail ✅）
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final a in s.items)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 124,
                    child: ArticleCard(article: a, site: widget.site),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---- 剧库 tab：8 个分类 chip + 2 个排序 chip（**不互斥** ✅）+ 分页 ✅ ----

class _YzLibTab extends StatefulWidget {
  const _YzLibTab({required this.site, required this.ui});

  final SiteEntry site;
  final YouziSite ui;

  @override
  State<_YzLibTab> createState() => _YzLibTabState();
}

class _YzLibTabState extends State<_YzLibTab> {
  String _cat = ''; // 分类 slug（'' = 全部 ✅）
  String _sort = 'updated'; // 排序（updated=最新 ✅）

  // ★ 2026-10-11（用户要求）：**滚到底自动加载下一页并追加** ✅（原来的「上一页/下一页」按钮**已删** ✅）
  final List<Article> _items = <Article>[];
  final Set<String> _seen = <String>{}; // 去重键 = 详情路径 ✅（同一部剧重复出现只留一条 ✅）
  int _page = 0; // 已加载到的页号（0 = 还没开始 ✅）
  int _pages = 1; // 站上 `data-pages` ✅
  int _total = 0; // 站上 `data-total` ✅
  bool _loading = true; // 显示用：首次也算"装"（⇒ 首帧不会先闪一下"没有内容" ✅）
  bool _busy = false; // 重入锁（**不参与显示** ✅ —— 与 `_loading` 分开，免得"首帧 true"把第一次装载挡掉 ☠）
  bool _done = false; // 到底（最后一页 / 空页 / 越界 404 都算 ✅）
  String? _err; // 追加失败（**不清已有列表** ✅ 底部给"重试" ✅）
  final ScrollController _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    _sc.addListener(_onScroll);
    // ⚠️ 排进**微任务**再装（别在 `initState` 里直接 setState ✅ —— 照 `home_page.dart` 的 `Future.microtask` 先例 ✅）
    Future.microtask(_next); // 第 1 页
  }

  @override
  void dispose() {
    _sc.removeListener(_onScroll);
    _sc.dispose();
    super.dispose();
  }

  /// 触底判定：距底部 320px 就开始预取 ✅
  /// ⚠️ **追加不打断滚动位置**：只往同一个 `ListView` 尾部加 child ✅（不重建列表、不 jump ✅）
  void _onScroll() {
    if (!_sc.hasClients) return;
    final p = _sc.position;
    if (p.pixels >= p.maxScrollExtent - 320) _next();
  }

  /// 换分类/排序 ⇒ 清空重来（分类与排序**不互斥** ⇒ 任意组合 ✅）
  void _pick({String? cat, String? sort}) {
    if (cat != null && cat == _cat) return;
    if (sort != null && sort == _sort) return;
    setState(() {
      if (cat != null) _cat = cat;
      if (sort != null) _sort = sort;
      _items.clear();
      _seen.clear();
      _page = 0;
      _pages = 1;
      _total = 0;
      _done = false;
      _err = null;
      _busy = false; // 重新开始 ⇒ 锁放开 ✅
      _loading = true;
    });
    if (_sc.hasClients) _sc.jumpTo(0); // 换筛选 ⇒ 回顶部 ✅
    _next();
  }

  /// 取下一页（第 1 页 / 追加页同一套 ✅）：**去重后追加** ✅
  Future<void> _next() async {
    if (_busy || _done) return; // 重入锁 + 到底 ⇒ 直接不取 ✅（滚动事件很密，靠它挡住请求风暴 ✅）
    _busy = true;
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      // ⚠️ 一次调用里最多连取 3 页 ✅ —— 万一某页**全是重复项**，也不至于"停在底部不动" ✅
      for (var guard = 0; guard < 3; guard++) {
        final r =
            await widget.ui.browse(category: _cat, sort: _sort, page: _page + 1);
        if (!mounted) return;
        var added = 0;
        for (final a in r.items) {
          if (_seen.add(a.url)) {
            _items.add(a);
            added++;
          }
        }
        _page = r.page;
        _pages = r.pages < 1 ? 1 : r.pages;
        if (r.total > 0) _total = r.total;
        // 到底判据（口径不变 ✅）：空页（含第 2 页起越界 404 ⇒ 已在上层当"空 ✅"）或已到 `data-pages` ✅
        final last = r.items.isEmpty || _page >= _pages;
        if (added > 0 || last) {
          _busy = false;
          setState(() {
            _loading = false;
            _done = last;
          });
          return;
        }
      }
      _busy = false;
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (AppSettings.i.logConsole) {
        debugPrint('[UI] ${widget.site.name} 剧库 tab 第 ${_page + 1} 页取数失败：$e');
      }
      _busy = false;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _err = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: _sc,
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 22),
      children: [
        const SizedBox(height: 6),
        _chipRow([
          for (final c in YouziSite.kYzCats)
            _YzChip(
              label: c.value,
              on: _cat == c.key,
              onTap: () => _pick(cat: c.key),
            ),
        ]),
        const SizedBox(height: 6),
        _chipRow([
          for (final s in YouziSite.kYzSorts)
            _YzChip(
              label: s.value,
              on: _sort == s.key,
              onTap: () => _pick(sort: s.key),
            ),
        ]),
        const Divider(height: 16, thickness: 0.6),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
          child: Text(
              '${_catLabel(_cat)} · ${_sortLabel(_sort)} · '
              '已加载 ${_items.length}/共 $_total 条 · 第 $_page/$_pages 页',
              style: TextStyle(fontSize: 13, color: kTxtSub)),
        ),
        if (_items.isEmpty && _loading)
          const _YzHint('加载中…')
        else if (_items.isEmpty && _err != null)
          _YzFail(_err!, onRetry: _next)
        else if (_items.isEmpty)
          const _YzHint('这个组合下没有内容')
        else
          _grid(_items, site: widget.site),
        // ★ 底部状态行：加载中… / 没有更多了 / 加载失败+重试 ✅（列表已有内容时**只画这一行** ✅）
        _YzFooter(
          loading: _loading,
          done: _done,
          err: _err,
          onRetry: _next,
          empty: _items.isEmpty,
        ),
      ],
    );
  }

  String _catLabel(String slug) {
    for (final c in YouziSite.kYzCats) {
      if (c.key == slug) return c.value;
    }
    return slug;
  }

  String _sortLabel(String key) {
    for (final s in YouziSite.kYzSorts) {
      if (s.key == key) return s.value;
    }
    return key;
  }

  /// 一行 chip（★ 2026-10-12 **用户口径：前缀文案"分类"/"排序"碍眼 ⇒ 去掉** ✅）
  ///
  /// ⚠️ **只删文案，行为一行未动** ☑️：chip 集合（分类 8 + 排序 2）/ 选中态 / 横向滚动 /
  ///   点击逻辑（`_pick`）/ **不互斥** 全部照旧 ✅。
  /// 布局补法：原来那一列"前缀固定宽度 34px"（`SizedBox(width: 34)`）**整列删掉**，
  ///   也**不再需要外层 `Row`** ⇒ 直接让 chip 行**自己占满宽度、左对齐** ✅；
  ///   chip 之间的 `6px` 间距、以及两行之间的 `SizedBox(height: 6)` **照旧** ✅
  ///   （⇒ 不会留大洞、也不会挤在一起 ✅）；**触控区不变**（高度由 [_YzChip] 自己的
  ///   `padding: 10×5` 决定 ⇒ 与改前完全一样 ✅）。
  Widget _chipRow(List<Widget> chips) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            chips[i],
          ],
        ],
      ),
    );
  }

  Widget _grid(List<Article> items, {required SiteEntry site}) {
    return LayoutBuilder(
      builder: (context, c) {
        const pad = 10.0, gap = 8.0;
        final w = (c.maxWidth - pad * 2 - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: 12,
          children: [
            for (final a in items)
              SizedBox(width: w, child: ArticleCard(article: a, site: site)),
          ],
        );
      },
    );
  }
}

// ---- 「更多」页（分区的目标页 ✅：`/dramas/…` 走片段接口、`/tags/…` 走整页 ✅）----

class _YzListPage extends StatefulWidget {
  const _YzListPage({
    required this.site,
    required this.ui,
    required this.path,
    required this.title,
  });

  final SiteEntry site;
  final YouziSite ui;

  /// 「更多」目标 = 站内路径（含 query ✅）
  final String path;
  final String title;

  @override
  State<_YzListPage> createState() => _YzListPageState();
}

class _YzListPageState extends State<_YzListPage> {
  // ★ 2026-10-11（用户要求）：**滚到底自动加载下一页并追加** ✅（按钮**已删** ✅）
  final List<Article> _items = <Article>[];
  final Set<String> _seen = <String>{}; // 去重键 = 详情路径 ✅
  int _page = 0;
  int _pages = 1;
  int _total = 0;
  bool _loading = true; // 显示用：首次也算"装" ✅
  bool _busy = false; // 重入锁（不参与显示 ✅）
  bool _done = false;
  String? _err;
  String _stationTitle = ''; // 站上 h1（标签页有 ✅；分区页为空 ⇒ 用传进来的标题 ✅）
  final ScrollController _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    _sc.addListener(_onScroll);
    Future.microtask(_next); // 排微任务 ✅（别在 initState 里直接 setState ✅）
  }

  @override
  void dispose() {
    _sc.removeListener(_onScroll);
    _sc.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_sc.hasClients) return;
    final p = _sc.position;
    if (p.pixels >= p.maxScrollExtent - 320) _next();
  }

  Future<void> _next() async {
    if (_busy || _done) return;
    _busy = true;
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      for (var guard = 0; guard < 3; guard++) {
        final r = await widget.ui.listPage(widget.path, _page + 1);
        if (!mounted) return;
        var added = 0;
        for (final a in r.items) {
          if (_seen.add(a.url)) {
            _items.add(a);
            added++;
          }
        }
        _page = r.page;
        _pages = r.pages < 1 ? 1 : r.pages;
        if (r.total > 0) _total = r.total;
        if (r.title.isNotEmpty && _stationTitle.isEmpty) {
          _stationTitle = r.title;
        }
        // 口径不变 ✅：空页（第 2 页起越界 404 已在上层当"空" ✅）或已到 `data-pages` ⇒ 到底
        final last = r.items.isEmpty || _page >= _pages;
        if (added > 0 || last) {
          _busy = false;
          setState(() {
            _loading = false;
            _done = last;
          });
          return;
        }
      }
      _busy = false;
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (AppSettings.i.logConsole) {
        debugPrint('[UI] ${widget.site.name} 更多页 ${widget.path} 第 ${_page + 1} 页失败：$e');
      }
      _busy = false;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _err = '$e';
      });
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
          title: Text(widget.title.isNotEmpty
              ? widget.title
              : (_stationTitle.isNotEmpty ? _stationTitle : widget.site.name)),
          centerTitle: true,
          foregroundColor: kTxt,
        ),
        body: ListView(
          controller: _sc,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 22),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
              child: Text(
                  '已加载 ${_items.length}/共 $_total 条 · 第 $_page/$_pages 页',
                  style: TextStyle(fontSize: 13, color: kTxtSub)),
            ),
            if (_items.isEmpty && _loading)
              const _YzHint('加载中…')
            else if (_items.isEmpty && _err != null)
              _YzFail(_err!, onRetry: _next)
            else if (_items.isEmpty)
              const _YzHint('这里暂时没有内容')
            else
              _grid(_items),
            _YzFooter(
              loading: _loading,
              done: _done,
              err: _err,
              onRetry: _next,
              empty: _items.isEmpty,
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(List<Article> items) {
    return LayoutBuilder(
      builder: (context, c) {
        const pad = 10.0, gap = 8.0;
        final w = (c.maxWidth - pad * 2 - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: 12,
          children: [
            for (final a in items)
              SizedBox(width: w, child: ArticleCard(article: a, site: widget.site)),
          ],
        );
      },
    );
  }
}

// ---- 小件：胶囊 / 状态 ----

class _YzChip extends StatelessWidget {
  const _YzChip({required this.label, required this.on, required this.onTap});

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
              fontSize: 12,
              color: on ? Colors.white : const Color(0xFF444444)),
        ),
      ),
    );
  }
}

/// ★ 2026-10-11（用户要求自动翻页 ✅）：列表**底部状态行** ——
///   `加载中…`（正在追加）/ `没有更多了`（到底 ✅）/ `加载失败 + 重试`（只影响追加，**不清列表** ✅）。
/// ⚠️ `empty` = 列表还是空的 ⇒ 这一行**不画**（页面主体已经有"加载中…"了，别画两遍 ✅）。
class _YzFooter extends StatelessWidget {
  const _YzFooter({
    required this.loading,
    required this.done,
    required this.err,
    required this.onRetry,
    this.empty = false,
  });

  final bool loading;
  final bool done;
  final String? err;
  final VoidCallback onRetry;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    if (loading && !empty) {
      return Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Center(
          child: Text('加载中…', style: TextStyle(fontSize: 13, color: kTxtSub)),
        ),
      );
    }
    final e = err;
    if (e != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Column(
          children: [
            Text('加载失败：$e',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: kTxtSub)),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: kChipBorder),
              ),
              child: Text('重试', style: TextStyle(fontSize: 13, color: kTxt)),
            ),
          ],
        ),
      );
    }
    if (done) {
      return Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Center(
          child: Text('没有更多了', style: TextStyle(fontSize: 13, color: kTxtSub)),
        ),
      );
    }
    return const SizedBox(height: 18);
  }
}

class _YzHint extends StatelessWidget {
  const _YzHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 24, 10, 0),
        child: Center(
          child: Text(text, style: TextStyle(fontSize: 14, color: kTxtSub)),
        ),
      );
}

class _YzFail extends StatelessWidget {
  const _YzFail(this.msg, {required this.onRetry});

  final String msg;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 24, 10, 0),
        child: Column(
          children: [
            Text('加载失败：', style: TextStyle(fontSize: 14, color: kTxt)),
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
              child: Text('重试', style: TextStyle(fontSize: 13, color: kTxt)),
            ),
          ],
        ),
      );
}

// ===== 八、本站档案（2026-10-11 ✅；在 `lib/sites.dart` 的 `kSites` 里**排在黄果短剧之后** ✅）=====

/// 本站档案：柚子短剧
///
/// ⚠️ `categories` 留空 ✅ —— 本站是**自管整页**（两主 tab 在 [YzHomePage] 里 ✅），
///   底座那套「分类 tab + 分页列表」对它**用不到** ☑️（`home_page.dart:580` 直接返回本页 ✅）。
const SiteEntry kSite16 = SiteEntry(
  name: '柚子短剧',
  template: SiteTemplate.youzidj,
  iconUrl: '/favicon.ico',
  // ★ 2026-10-12：**内置图标**（当天恢复本站时补：抓 `youzidj.com/favicon.ico` 48x48 三帧
  //   ⇒ 取最大帧转 128x128 PNG ✅）—— 站点图标一律只走内置资源、不联网取 ✅
  assetIcon: 'assets/site_icons/youzidj.png',
  hosts: ['youzidj.com'],
  portraitCovers: true, // 海报 9:16 竖图 ✅（每条卡另带 coverAspect ✅）
  color: Color(0xFFF2A33C),
);
