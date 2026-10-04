import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as hp;

import 'base/fetch.dart';
import 'base/site_ui.dart';
import 'base/source_cache.dart';
import 'models.dart';
import 'sites/pornhub.dart';
import 'sites/pektino.dart';
import 'sites/hanime1.dart';
import 'sites/xvideos.dart';
import 'sites/porna.dart';
import 'sites/huangguo.dart';
import 'sites/kmsvip.dart';
import 'sites/madou.dart';
import 'sites/wordpress.dart';
import 'sites/xhamster.dart';
import 'sites.dart';

/// 站点抓取层。按 [SiteEntry.template] 分派到各站模板的解析规则：
///
/// - `SiteTemplate.wordpress`（51吃瓜/每日大赛/91吃瓜/911爆料网/51fans）：
///   列表 `article[itemscope]` 或 51fans 的 `div.xqbj-list-rows`；
///   分页 `/category/{slug}/{n}/`；搜索 `/search/{kw}/`；详情 `.dplayer[data-config]`。
///   51fans1 的搜索页是 JS/接口驱动，抓不到结果（已知限制）。
/// - `SiteTemplate.huangguo`（黄果短剧）：列表走 JSON 接口
///   `/api/videos/category/{slug}?sort=..&page=..&size=..`；
///   详情页内嵌 `<script id="videoInitialData">`，里面有全部剧集的 m3u8。
/// - `SiteTemplate.porna`（91porna）：列表 `div.video-item`；
///   详情页播放地址要再请求 `/index/detail_play?img=..&u=..&t=..` 换回 m3u8（带时效签名）。
/// - `SiteTemplate.madou`（麻豆社 madou.club）：列表 `article.excerpt`（无 itemscope）；
///   分页 `/page/N`、`/category/{slug}/page/N`、`/tag/{slug}/page/N`、`/?paged=N&s=kw`；
///   详情正文是玩家 iframe → dash.madou.club 分享页给 token + m3u8（见 _mdDetail）。
class Api {
  /// site：站点清单里的那条（域名、模板、分类都从这来）
  Api({required this.site});

  final SiteEntry site;

  /// ⚠️ 取数底座已搬到 `lib/base/fetch.dart`（与站点无关 ✓，用户 2026-10-03 决策）：
  /// 域名轮换 / 8 秒超时 / 5xx 重试 / Referer+UA / UTF-8 解码 / NSURLSession 客户端。
  /// 这里只**委托** ✓ —— 下面 46 个 `_fetchText(...)` 调用点**一个字都不用改** ✓。
  late final SiteFetcher _f = SiteFetcher(site);

  String get _host => _f.host;

  String get base => 'https://$_host';

  /// 一块 dplayer 的播放源（h264 主源在前，h265 兜底）；配置坏就返回空
  List<String> _dplayerSources(Element dp) {
    final sources = <String>[];
    try {
      final cfg = jsonDecode(dp.attributes['data-config']!) as Map<String, dynamic>;
      final video = cfg['video'];
      final h265 = cfg['video_h265'];
      if (video is Map<String, dynamic>) {
        final u = (video['url'] as String?) ?? '';
        if (u.isNotEmpty) sources.add(u);
      }
      if (h265 is Map<String, dynamic>) {
        final u = (h265['url'] as String?) ?? '';
        if (u.isNotEmpty) sources.add(u);
      }
    } catch (_) {
      // 配置坏：视为无源
    }
    return sources;

  }

  /// 本站的 UI 事实（2026-10-03 站点独立改造）✓
  ///
  /// ✅ **全项目唯一一处"哪个模板对应哪个站点类"的选择** ✓ ——
  /// 站点专属的判断/UI 全在各 lib/sites/<站>.dart 里 ✓，这里只做接线 ✓；
  /// 没实现 SiteUi 的站点返回 null ✓ → 调用处 `?? 默认值` ✓ = 改造前行为 ✓。
  /// 便捷：当前站点的 UI 事实（可能就是 null ✓）
  SiteUi? get _ui => ui;

  SiteUi? get ui => switch (site.template) {
        SiteTemplate.wordpress => _wpSite,
        SiteTemplate.huangguo => _hgSite,
        SiteTemplate.porna => _pornaSite,
        SiteTemplate.pektino => _pkSite,
        SiteTemplate.hanime1 => _hnSite,
        SiteTemplate.xvideos => _xvSite,
        SiteTemplate.kmsvip => _kmSite,
        SiteTemplate.madou => _mdSite,
        SiteTemplate.pornhub => _phSite,
        SiteTemplate.xhamster => _xhSite,
        // 直播站 xHamsterLive：**没有** SiteUi 事实 ✓ —— 它的列表/房间页全在
        // `lib/sites/xhamsterlive.dart` 里自己实现 ✓（界面上也不会有人把它交给 HomePage：
        // 它 `group: SiteGroup.live` ✓，只从底栏「直播」进 ✓）
        SiteTemplate.xhamsterlive => null,
      };

  /// wordpress 本站专属实现（2026-10-03 站点独立改造）✓
  late final WpSite _wpSite = WpSite(_f);

  /// madou 本站专属实现（2026-10-03 站点独立改造）✓
  late final MadouSite _mdSite = MadouSite(_f);

  /// kmsvip 本站专属实现（2026-10-03 站点独立改造）✓
  late final KmSite _kmSite = KmSite(_f);

  /// 黄果短剧本站专属实现（2026-10-03 站点独立改造）✓
  late final HuangguoSite _hgSite = HuangguoSite(_f);

  /// 91porna/蜜桃/黑料/ms/小说（共用子系统）专属实现（2026-10-03 ✓）
  late final PornaSite _pornaSite = PornaSite(_f);

  /// XVideos 本站专属实现（2026-10-03 站点独立改造）✓
  late final XvSite _xvSite = XvSite(_f);

  /// Hanime1 本站专属实现（2026-10-03 站点独立改造）✓
  late final HanimeSite _hnSite = HanimeSite(_f);

  /// 「內容標籤」（原公开方法随段搬去 HanimeSite ✓，这里转发给 home_page 用 ✓）

  /// Pektino 本站专属实现（2026-10-03 站点独立改造）✓
  late final PektinoSite _pkSite = PektinoSite(_f);

  /// Pornhub **本站专属实现**（2026-10-03 站点独立改造）✓ —— 同一份取数底座 `_f` ✓
  late final PhSite _phSite = PhSite(_f);

  /// xHamster **本站专属实现**（2026-10-03 站点独立改造 Step B）✓ —— 用同一份取数底座 `_f` ✓
  late final XhSite _xhSite = XhSite(_f);

  /// 切回「短片」tab 时让下一次取数重新随机（`home_page` 会调 ✓；原方法随段搬去了 XhSite ✗）

  /// 顺序尝试域名取文本 —— **实现搬到了 `lib/base/fetch.dart` 的 `SiteFetcher.text`** ✓
  /// （底座公用 ✓；这里只是委托，调用点不用改 ✓）
  Future<String> _fetchText(String path,
          {Map<String, String>? extraHeaders}) =>
      _f.text(path, extraHeaders: extraHeaders);

  // ---------------------------------------------------------------------------
  // 列表

  /// 分类/频道列表。page 从 1 开始。
  /// [sub]/[sub2] 是两级子分类 key（有子分类的站点才用）。
  /// 路径型模板（wordpress/porna）取**最深的那个 key** 当站内路径；
  /// 黄果（huangguo）只有一层排序（latest/hot/original/random）。
  Future<List<Article>> category(String key,
      {int page = 1,
      String? sub,
      String? sub2,
      String? theme,
      String? duration,
      String? sort,
      List<MapEntry<String, String>>? extra}) async {
    final l1 = (sub == null || sub.isEmpty) ? null : sub;
    final l2 = (sub2 == null || sub2.isEmpty) ? null : sub2;
    final k = l2 ?? l1 ?? key;
    // ✅ 原来这里是 10 个 case 的 switch（每个 case 一行委托）。
    // 现在改成**问站点自己** ✓：各站的解析/URL 拼接早已在 lib/sites/*.dart 里 ✓。
    return _ui!.category(key,
        page: page,
        k: k,
        theme: theme,
        duration: duration,
        sort: sort,
        extra: extra,
        home: home);
  }

  /// 首页最新列表（无分类 tab 的站点用；有 tab 的都直接进分类页）
  Future<List<Article>> home({int page = 1}) async {
    // 只算好「第一个分类」（3 个站要用），其余交给站点自己 ✓
    final first = site.categories.isEmpty ? '' : site.categories.first.key;
    return _ui!.home(page: page, first: first);
  }

  /// 标签列表页。page 从 1 开始。
  Future<List<Article>> tag(String slug, {int page = 1}) async {
    return _ui!.tag(slug, page: page);
  }

  /// 搜索（关键词需原始文本，内部编码）。
  /// WordPress 系 5 站的搜索**有分页**：`/search/{kw}/{页码}/`
  /// （页面上的「下一页」链接就是这个形态；实测第 2 页有内容、与第 1 页不重复。
  ///  2026-09-30 修正：之前误判成「站点无搜索分页」，只取了第 1 页）。
  /// 黄果搜索单页（页面上没有分页入口）；91porna 用 `&page=`。
  Future<List<Article>> search(String keyword,
      {int page = 1, List<MapEntry<String, String>>? extra}) async {
    return _ui!.search(keyword, page: page, extra: extra);
  }

  // ---------------------------------------------------------------------------
  // 详情

  /// 文章详情（相对路径或站内路径）。
  /// 视频 URL 带时效签名，过期时重新调用本方法即可拿到新地址。
  /// ⚠️ 2026-10-05 修：原来直接调 `_ui!.detail(url)` ✗ —— 那是**视频**详情解析器，
  ///    黄果的 `/archives/` 帖子 / 91porna 的小说·黑料图文会被它解析成"没有视频" ✗。
  ///    改调 [SiteUi.detailOf]（**详情入口** ✓，默认实现 = 原样转发给 `detail` ✓
  ///    → 未覆写的站行为一个字不变 ✓；覆写的两家见 `huangguo.dart` / `porna.dart` ✓）。
  Future<ArticleDetail> detail(String url) async {
    return _ui!.detailOf(url);
  }

  // ---------------------------------------------------------------------------
  // WordPress 系（含 51fans1 的兼容分支）






  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // 公共小工具

  /// 合集里某一集的视频源 —— **按需取**：播放器切到那一集才调这里。
  /// ⚠️ #9：去重+缓存**只留底座**（`SourceCache.i` ✓，LRU 80 ✓）——原来的 `_lazyCache`/`_lazyInflight` 已删 ✓。
  /// 两条契约照旧 ✓：**出错要抛**（`rethrowOnError: true` ✓，`player_widget.dart:789` 的重试依赖它 ✗）、
  /// **空结果不缓存** ✓；key 带命名空间 `d|` ✓（短片那条是 `s|` ✓ —— 取名策略不同，不能共用 ✗）。
  Future<List<String>> videoSourcesAt(String url) => SourceCache.i.get(
        'd|$url',
        () => _fetchSourcesAt(url),
        rethrowOnError: true,
      );

  /// 真去抓某一集的源（去重与缓存入口见 [videoSourcesAt]）
  Future<List<String>> _fetchSourcesAt(String url) async {
    final html = await _fetchText(url);
    final out = <String>[];
    // ⚠️ 站点专属的解析已**下放各站** ✓（见 SiteUi.sourcesFromHtml ✓）——
    // 本站返回非 null 就用自己的（黄果 ✓），返回 null 才走通用做法（.dplayer 配置 ✓）。
    final own = _ui?.sourcesFromHtml(html);
    if (own != null) {
      out.addAll(own);
    } else {
      final doc = hp.parse(html);
      for (final dp in doc.querySelectorAll('.dplayer[data-config]')) {
        out.addAll(_dplayerSources(dp));
      }
    }
    // ⚠️ #9：缓存已统一交给 `SourceCache`（在 `videoSourcesAt` 里 ✓）—— 这里**只管抓** ✓
    return out;
  }

  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // 快猫（kmsvip.xyz）：加密 API（AES-128-CBC 大写 HEX + md5 签名，协议照站点
  // 前端 JS 原样搬；key/iv 就硬编码在站点的前端里）


  /// 详情：标题 / 时长 / 标签 / 播放源（mp4 High→Low→HLS，去重）/ 相关推荐

  // ---------------------------------------------------------------------------
  // 麻豆社（madou.club）—— WordPress + 自研主题 showcase
  //
  // 列表：`article.excerpt`（**没有 itemscope**，和上面 5 个 wordpress 站不是一套）
  //   - 详情链接 a.thumbnail[href]、封面 a.thumbnail img[data-src] 都是绝对地址
  //     （用 _toRelPath 剥成站内路径）；封面是懒加载占位 thumb.png/空 → 整卡跳过
  //   - meta = ".post-view" 里的**数字**（站点原文 "观看(59.26K)"，只留 "59.26K"；
  //     用户要求去掉"观看"这截标签；站点**没有发布时间**）
  //   - 卡片分类名 = footer 里第一个 rel="category tag" 的锚文本（挂 Article.tags，
  //     key = 该分类的站内路径，点进去是该分类的列表）
  // 详情：`.article-title` / `.item-3 a`（分类）/ `.article-tags a`（标签）/
  //   `.postitems li a`（相关推荐）；播放源在正文 iframe 指向的分享页里。


  /// 合集按需取源的缓存（url -> 播放源）与"进行中"的请求（同一集去重）
  // ⚠️ #9：原来这里有两张静态表（`_lazyCache` / `_lazyInflight`）—— 已随"只留一份缓存"删掉 ✗
  //    统一走 `lib/base/source_cache.dart` ✓（LRU 80 ✓、在途共享 ✓、出错语义按调用方传 ✓）









  // ---------------------------------------------------------------------------
}
