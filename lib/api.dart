import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:http/http.dart' as http;
import 'package:html/dom.dart';
import 'package:html/parser.dart' as hp;

import 'base/fetch.dart';
import 'base/site_ui.dart';
import 'config.dart';
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

  List<String> get hosts => _f.hosts;
  String get _host => _f.host;
  set _host(String h) => _f.host = h;
  http.Client get _client => _f.client;

  String get base => 'https://$_host';

  /// 本站的 UI 事实（2026-10-03 站点独立改造）✓
  ///
  /// ✅ **全项目唯一一处"哪个模板对应哪个站点类"的选择** ✓ ——
  /// 站点专属的判断/UI 全在各 lib/sites/<站>.dart 里 ✓，这里只做接线 ✓；
  /// 没实现 SiteUi 的站点返回 null ✓ → 调用处 `?? 默认值` ✓ = 改造前行为 ✓。
  SiteUi? get ui => switch (site.template) {
        SiteTemplate.xhamster => _xhSite,
        SiteTemplate.pornhub => _phSite,
        SiteTemplate.pektino => _pkSite,
        SiteTemplate.hanime1 => _hnSite,
        _ => null,
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
  Future<List<String>> hanimeTags() => _hnSite.hanimeTags();

  /// Pektino 本站专属实现（2026-10-03 站点独立改造）✓
  late final PektinoSite _pkSite = PektinoSite(_f);

  /// Pornhub **本站专属实现**（2026-10-03 站点独立改造）✓ —— 同一份取数底座 `_f` ✓
  late final PhSite _phSite = PhSite(_f);

  /// xHamster **本站专属实现**（2026-10-03 站点独立改造 Step B）✓ —— 用同一份取数底座 `_f` ✓
  late final XhSite _xhSite = XhSite(_f);

  /// 切回「短片」tab 时让下一次取数重新随机（`home_page` 会调 ✓；原方法随段搬去了 XhSite ✗）
  void resetShortsRandom() => _xhSite.resetShortsRandom();

  /// 顺序尝试域名取文本 —— **实现搬到了 `lib/base/fetch.dart` 的 `SiteFetcher.text`** ✓
  /// （底座公用 ✓；这里只是委托，调用点不用改 ✓）
  Future<String> _fetchText(String path,
          {Map<String, String>? extraHeaders}) =>
      _f.text(path, extraHeaders: extraHeaders);

  /// 绝对地址请求（跨域）—— **实现搬到了 `SiteFetcher.abs`** ✓（底座公用 ✓）
  Future<String> _fetchAbs(String url) => _f.abs(url);

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
    switch (site.template) {
      case SiteTemplate.wordpress:
        final path = k.startsWith('/')
            // 51fans1 的 /order/hot/ 这类：页 2 = /order/hot/2/
            ? (page <= 1 ? k : '$k$page/')
            : (page <= 1 ? '/category/$k/' : '/category/$k/$page/');
        return _wpSite.parseArticles(await _fetchText(path));
      case SiteTemplate.huangguo:
        // 以 / 开头 = 站内路径型列表（精选推荐/最近上新/专题/排行榜/吃瓜黑料）
        if (k.startsWith('/')) return _hgSite.pageList(k, page: page);
        // 否则是频道 slug；只有一层排序：子分类 key 就是 sort 值，没选就按最新
        return _hgSite.list(key, sort: k == key ? 'latest' : k, page: page);
      case SiteTemplate.porna:
        // 列表逻辑已下放本站 ✓（见 lib/sites/porna.dart 的 category ✓）
        return _pornaSite.category(k, page: page);
      case SiteTemplate.pektino:
        // 主分类 4 个都是路径型（/zh-CN/、/zh-CN/weekly…）→ 从路径解出 range；
        // 主题/时长/排序是主分类页面里的筛选器（多级分类），由列表页传入
        final r = key.endsWith('/weekly')
            ? 'weekly'
            : key.endsWith('/monthly')
                ? 'monthly'
                : key.endsWith('/all')
                    ? 'all'
                    : 'timely';
        return _pkSite.list(r, theme ?? '',
            page: page, duration: duration, sort: sort);
      case SiteTemplate.hanime1:
        // 列表逻辑已下放本站 ✓（见 lib/sites/hanime1.dart 的 category ✓）
        return _hnSite.category(key, page: page, extra: extra);
      case SiteTemplate.xvideos:
        // 「分类」tab 的子分类 key（/c/xxx、/tags/xxx、/trans、/lang/…）优先；
        // 主分类 key = /best、/new、/channels-index、/pornstars-index（见 _xvList）
        return _xvSite.list(k, page: page);
      case SiteTemplate.kmsvip:
        // 列表逻辑已下放本站 ✓（见 lib/sites/kmsvip.dart 的 category ✓）
        return _kmSite.category(key, page: page);
      case SiteTemplate.madou:
        // key 平时是分类 slug（已编码，如 hongkongdoll）；以 / 开头 = 站内路径
        // （/likes /week /month 三个榜单 + /tags 标签云）
        // 空 key = 「首页」tab（站点导航第一项）→ 走首页那条路
        if (k.isEmpty) return home(page: page);
        if (k == '/tags') return _mdSite.tags(await _fetchText('/tags'));
        if (k.startsWith('/')) {
          // 榜单**没有翻页**：第 2 页起直接给空，否则会把同一页重复追加
          // （同 huangguo 标签页的做法）
          return page > 1 ? const [] : _mdSite.cards(await _fetchText(k));
        }
        // 详情页的分类 chip 传的是分类**名**（中文，没编码）→ 自己编码再拼路径
        // （站点对未编码的中文路径实测 400，编码后 200）
        final md = RegExp(r'[^\x00-\x7F]').hasMatch(k) ? Uri.encodeComponent(k) : k;
        return _mdSite.cards(await _fetchText(
            page <= 1 ? '/category/$md' : '/category/$md/page/$page'));
      case SiteTemplate.pornhub:
        // 列表 key 本身就是站内路径；「分类」tab 选中的分类是 theme（/video?c=27，见 _phCats）。
        // 「色情明星」tab 的筛选走 extra（o / performerType / t / 更多筛选各组的 key）。
        var php = theme ?? k;
        if (extra != null && extra.isNotEmpty) {
          php += '${php.contains('?') ? '&' : '?'}'
              '${extra.map((e) => '${e.key}=${e.value}').join('&')}';
        }
        return _phSite.list(php, page: page);
      case SiteTemplate.xhamster:
        // key / theme 都是**站内路径**（「色情明星」tab 自己的选择器也走 theme）：
        //   · 「影片」tab：'/'、'/hd'、'/4k'、'/vr'
        //   · 「分类」tab：默认 '/categories/18-year-old'；选中标签后 theme = '/categories/<slug>'
        //   · 「色情明星」tab：默认 '/pornstars'；选中后 theme = '/pornstars/top/us'、
        //     '/pornstars/all/countries'、'/pornstars/all/categories/<slug>'
        //   · 「短片」tab：'/shorts' → 内部走 JSON 接口（与路径无关）
        // 走哪套解析由 _xhList 内部按路径判断。
        return _xhSite.list(theme ?? k, page: page);
    }
  }

  /// 首页最新列表（无分类 tab 的站点用；有 tab 的都直接进分类页）
  Future<List<Article>> home({int page = 1}) async {
    switch (site.template) {
      case SiteTemplate.wordpress:
        final path = page <= 1 ? '/' : '/page/$page/';
        return _wpSite.parseArticles(await _fetchText(path));
      case SiteTemplate.huangguo:
        final first = site.categories.isEmpty ? '' : site.categories.first.key;
        return _hgSite.list(first, sort: 'latest', page: page);
      case SiteTemplate.porna:
        final first = site.categories.isEmpty ? '' : site.categories.first.key;
        return _pornaSite.list(first, page: page);
      case SiteTemplate.pektino:
        // 首页 = 每日榜（和站点首页一致）
        return _pkSite.list('timely', '', page: page);
      case SiteTemplate.hanime1:
        final first = site.categories.isEmpty ? '' : site.categories.first.key;
        return _hnSite.list(first, page: page);
      case SiteTemplate.xvideos:
        // 首页 = Newest 列表
        return _xvSite.list('/new', page: page);
      case SiteTemplate.kmsvip:
        return _kmSite.list('/api/videos/listHot', page: page);
      case SiteTemplate.madou:
        // 首页第 N 页 = /page/N（没有 /page/1）
        return _mdSite.cards(await _fetchText(page <= 1 ? '/' : '/page/$page'));
      case SiteTemplate.pornhub:
        return _phSite.list('/', page: page);
      case SiteTemplate.xhamster:
        return _xhSite.list('/', page: page);
    }
  }

  /// 标签列表页。page 从 1 开始。
  Future<List<Article>> tag(String slug, {int page = 1}) async {
    switch (site.template) {
      case SiteTemplate.wordpress:
        final path = page <= 1 ? '/tag/$slug/' : '/tag/$slug/page/$page/';
        return _wpSite.parseArticles(await _fetchText(path));
      case SiteTemplate.huangguo:
        // 专题等路径型（点"专题"卡片进来）走页面列表；标签页是普通列表页（没有分页）
        if (slug.startsWith('/')) return _hgSite.pageList(slug, page: page);
        if (page > 1) return [];
        return _hgSite.parseCards(hp.parse(await _fetchText('/tag/$slug/')));
      case SiteTemplate.porna:
        // 这站的"标签"分两种：以 / 开头的是站内分类页（黑料吃瓜的标签），
        // 其余是搜索关键词（视频页的 keywords）
        return _pornaSite.list(slug.startsWith('/') ? slug : 'search:$slug',
            page: page);
      case SiteTemplate.pektino:
        // "标签" = 主题筛选（走同一个接口，全时段）
        return _pkSite.list('all', slug, page: page);
      case SiteTemplate.hanime1:
        // 详情页标签：站内 /search? 路径直接请求（?query= / ?tags[]= 两种链接）；
        // 其余当搜索词
        if (slug.startsWith('/search')) return _hnSite.searchAt(slug, page: page);
        return _hnSite.search(slug, page: page);
      case SiteTemplate.xvideos:
        // 详情页标签 = /tags/{slug}（翻页规则同分类页）
        return _xvSite.list('/tags/$slug', page: page);
      case SiteTemplate.kmsvip:
        return const []; // 站点没有标签功能
      case SiteTemplate.madou:
        // 详情页的标签是裸 slug（/tag/{slug}）；以 / 开头的是卡片上的分类路径
        if (slug.startsWith('/')) {
          return _mdSite.cards(
              await _fetchText(page <= 1 ? slug : '$slug/page/$page'));
        }
        return _mdSite.cards(await _fetchText(
            page <= 1 ? '/tag/$slug' : '/tag/$slug/page/$page'));
      case SiteTemplate.xhamster:
        // 演员卡传过来的是 '/pornstars/<slug>'（本人页 → 视频列表）；详情页标签也走这里。
        // 全是站内路径，交给 _xhList 分流（它会避开"把演员页当演员列表解析"的坑）。
        return _xhSite.list(slug, page: page);
      case SiteTemplate.pornhub:
        // 详情页的标签是 `/video/search?search=<编码词>`；演员卡传来的是 `/pornstar/xxx`。
        // 两者对本站都只是"一个站内路径"→ 直接当列表抓（演员路径回来的是视频卡）。
        return _phSite.list(slug, page: page);
    }
  }

  /// 搜索（关键词需原始文本，内部编码）。
  /// WordPress 系 5 站的搜索**有分页**：`/search/{kw}/{页码}/`
  /// （页面上的「下一页」链接就是这个形态；实测第 2 页有内容、与第 1 页不重复。
  ///  2026-09-30 修正：之前误判成「站点无搜索分页」，只取了第 1 页）。
  /// 黄果搜索单页（页面上没有分页入口）；91porna 用 `&page=`。
  Future<List<Article>> search(String keyword,
      {int page = 1, List<MapEntry<String, String>>? extra}) async {
    switch (site.template) {
      case SiteTemplate.wordpress:
        final kw = Uri.encodeComponent(keyword);
        final path = page <= 1 ? '/search/$kw/' : '/search/$kw/$page/';
        return _wpSite.parseArticles(await _fetchText(path));
      case SiteTemplate.huangguo:
        if (page > 1) return []; // 黄果搜索单页（页面上没有分页入口）
        final kw = Uri.encodeComponent(keyword);
        final html = await _fetchText('/search/?keyword=$kw');
        return _hgSite.parseCards(hp.parse(html));
      case SiteTemplate.porna:
        return _pornaSite.list('search:$keyword', page: page);
      case SiteTemplate.pektino:
        // 站点搜索 = 把输入当分类名传同一个接口（实测：搜 anime 出 50 条）
        return _pkSite.list('all', keyword, page: page);
      case SiteTemplate.hanime1:
        return _hnSite.search(keyword, page: page, extra: extra);
      case SiteTemplate.xvideos:
        return _xvSite.search(keyword, page: page);
      case SiteTemplate.kmsvip:
        throw Exception('该站点没有搜索功能');
      case SiteTemplate.madou:
        // 搜索 = /?s={kw}；翻页参数是 **paged**（不是 page），照站点原样
        final kw = Uri.encodeComponent(keyword);
        return _mdSite.cards(await _fetchText(
            page <= 1 ? '/?s=$kw' : '/?paged=$page&s=$kw'));
      case SiteTemplate.pornhub:
        // 搜索 = /video/search?search=<kw>（站点自己的搜索页形态；kw 是原始文本，自己编码）
        return _phSite.list('/video/search?search=${Uri.encodeComponent(keyword)}',
            page: page);
      case SiteTemplate.xhamster:
        // ⚠️ 站点有搜索（'搜尋所有女優' 那个框），但**路径没实测过** → 先明确抛错，
        // 不猜一个地址糊上去（猜错了会静默变成空列表，更难查）。
        throw Exception('xHamster 搜索暂未接通（路径未实测）');
    }
  }

  // ---------------------------------------------------------------------------
  // 详情

  /// 文章详情（相对路径或站内路径）。
  /// 视频 URL 带时效签名，过期时重新调用本方法即可拿到新地址。
  Future<ArticleDetail> detail(String url) async {
    switch (site.template) {
      case SiteTemplate.wordpress:
        return _wpSite.detail(url);
      case SiteTemplate.huangguo:
        // 吃瓜社区的帖子是图文帖（/archives/N/），跟视频详情不是一套
        if (url.startsWith('/archives/')) return _hgSite.postDetail(url);
        return _hgSite.detail(url);
      case SiteTemplate.porna:
        // 四种详情页：短视频 / 黑料图文 / 小说 / 普通视频
        if (url.startsWith('/melonshort/video/')) return _pornaSite.melonDetail(url);
        if (url.startsWith('/heiliao-chigua/')) return _pornaSite.heiliaoDetail(url);
        if (url.startsWith('/novels/')) return _pornaSite.novelDetail(url);
        return _pornaSite.detail(url);
      case SiteTemplate.pektino:
        return _pkSite.detail(url);
      case SiteTemplate.hanime1:
        return _hnSite.detail(url);
      case SiteTemplate.xvideos:
        return _xvSite.detail(url);
      case SiteTemplate.pornhub:
        return _phSite.detail(url);
      case SiteTemplate.kmsvip:
        return _kmSite.detail(url);
      case SiteTemplate.madou:
        return _mdSite.detail(url);
      case SiteTemplate.xhamster:
        return _xhSite.detail(url);
    }
  }

  // ---------------------------------------------------------------------------
  // WordPress 系（含 51fans1 的兼容分支）






  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // 公共小工具

  /// 合集里某一集的视频源 —— **按需取**：播放器切到那一集才调这里。
  /// 取过的记住（同一集来回切不重复抓），最多缓存 60 篇。
  /// 同一个地址被"同时"要（详情页点击预取 + 播放器换片各调一次）时
  /// **共享同一个请求**，不重复抓。
  Future<List<String>> videoSourcesAt(String url) {
    final hit = _lazyCache[url];
    if (hit != null) return Future.value(hit);
    final pending = _lazyInflight[url];
    if (pending != null) return pending;
    final task = _fetchSourcesAt(url);
    _lazyInflight[url] = task;
    return task.whenComplete(() => _lazyInflight.remove(url));
  }

  /// 真去抓某一集的源（去重与缓存入口见 [videoSourcesAt]）
  Future<List<String>> _fetchSourcesAt(String url) async {
    final html = await _fetchText(url);
    final out = <String>[];
    if (site.template == SiteTemplate.huangguo) {
      // 黄果的某一集：源在 videoInitialData.epPlaySrcs[本集号]（页面自报 ep）
      final data = _hgSite.initialData(hp.parse(html));
      final ep = int.tryParse('${data?['ep'] ?? ''}') ?? 0;
      final eps = data?['epPlaySrcs'];
      if (eps is Map) {
        final v = '${eps['$ep'] ?? ''}';
        if (v.isNotEmpty) out.add(v);
      }
    } else {
      final doc = hp.parse(html);
      for (final dp in doc.querySelectorAll('.dplayer[data-config]')) {
        out.addAll(dplayerSources(dp));
      }
    }
    if (out.isNotEmpty) {
      if (_lazyCache.length >= 60) _lazyCache.remove(_lazyCache.keys.first);
      _lazyCache[url] = out;
    }
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
  static final Map<String, List<String>> _lazyCache = {};
  static final Map<String, Future<List<String>>> _lazyInflight = {};

  /// 一块 dplayer 的播放源（h264 主源在前，h265 兜底）；配置坏就返回空
  static List<String> dplayerSources(Element dp) {
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







  // ---------------------------------------------------------------------------
}
