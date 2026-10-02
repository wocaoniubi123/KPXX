import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:http/http.dart' as http;
import 'package:html/dom.dart';
import 'package:html/parser.dart' as hp;

import 'base/fetch.dart';
import 'config.dart';
import 'models.dart';
import 'sites/pornhub.dart';
import 'sites/pektino.dart';
import 'sites/hanime1.dart';
import 'sites/xvideos.dart';
import 'sites/porna.dart';
import 'sites/huangguo.dart';
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
        return _parseArticles(await _fetchText(path));
      case SiteTemplate.huangguo:
        // 以 / 开头 = 站内路径型列表（精选推荐/最近上新/专题/排行榜/吃瓜黑料）
        if (k.startsWith('/')) return _hgSite.pageList(k, page: page);
        // 否则是频道 slug；只有一层排序：子分类 key 就是 sort 值，没选就按最新
        return _hgSite.list(key, sort: k == key ? 'latest' : k, page: page);
      case SiteTemplate.porna:
        return _pornaSite.list(k, page: page);
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
        // 分类 tab = 站点的 genre（裏番/泡麵番/…）；列表走 /search?genre=
        // extra = 筛选行（sort/date/duration/tags[]）
        return _hnSite.list(key, page: page, extra: extra);
      case SiteTemplate.xvideos:
        // 「分类」tab 的子分类 key（/c/xxx、/tags/xxx、/trans、/lang/…）优先；
        // 主分类 key = /best、/new、/channels-index、/pornstars-index（见 _xvList）
        return _xvSite.list(k, page: page);
      case SiteTemplate.kmsvip:
        // key = 站点 type：'0' 热门视频（listHot）/ '1' 视频广场（listAll）
        return _kmList(
            key == '1' ? '/api/videos/listAll' : '/api/videos/listHot',
            page: page);
      case SiteTemplate.madou:
        // key 平时是分类 slug（已编码，如 hongkongdoll）；以 / 开头 = 站内路径
        // （/likes /week /month 三个榜单 + /tags 标签云）
        // 空 key = 「首页」tab（站点导航第一项）→ 走首页那条路
        if (k.isEmpty) return home(page: page);
        if (k == '/tags') return _mdTags(await _fetchText('/tags'));
        if (k.startsWith('/')) {
          // 榜单**没有翻页**：第 2 页起直接给空，否则会把同一页重复追加
          // （同 huangguo 标签页的做法）
          return page > 1 ? const [] : _mdCards(await _fetchText(k));
        }
        // 详情页的分类 chip 传的是分类**名**（中文，没编码）→ 自己编码再拼路径
        // （站点对未编码的中文路径实测 400，编码后 200）
        final md = RegExp(r'[^\x00-\x7F]').hasMatch(k) ? Uri.encodeComponent(k) : k;
        return _mdCards(await _fetchText(
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
        return _parseArticles(await _fetchText(path));
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
        return _kmList('/api/videos/listHot', page: page);
      case SiteTemplate.madou:
        // 首页第 N 页 = /page/N（没有 /page/1）
        return _mdCards(await _fetchText(page <= 1 ? '/' : '/page/$page'));
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
        return _parseArticles(await _fetchText(path));
      case SiteTemplate.huangguo:
        // 专题等路径型（点"专题"卡片进来）走页面列表；标签页是普通列表页（没有分页）
        if (slug.startsWith('/')) return _hgSite.pageList(slug, page: page);
        if (page > 1) return [];
        return _parseHuangguoCards(hp.parse(await _fetchText('/tag/$slug/')));
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
          return _mdCards(
              await _fetchText(page <= 1 ? slug : '$slug/page/$page'));
        }
        return _mdCards(await _fetchText(
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
        return _parseArticles(await _fetchText(path));
      case SiteTemplate.huangguo:
        if (page > 1) return []; // 黄果搜索单页（页面上没有分页入口）
        final kw = Uri.encodeComponent(keyword);
        final html = await _fetchText('/search/?keyword=$kw');
        return _parseHuangguoCards(hp.parse(html));
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
        return _mdCards(await _fetchText(
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
        return _wpDetail(url);
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
        return _kmDetail(url);
      case SiteTemplate.madou:
        return _mdDetail(url);
      case SiteTemplate.xhamster:
        return _xhSite.detail(url);
    }
  }

  // ---------------------------------------------------------------------------
  // WordPress 系（含 51fans1 的兼容分支）



  /// 把绝对地址归一化成站内相对路径（详情页只认 /archives/xxx/ 这种）
  static String _toRelPath(String href) {
    if (!href.startsWith('http')) return href;
    final i = href.indexOf('/archives/');
    if (i >= 0) return href.substring(i);
    // 其它形态的绝对地址（如麻豆社的 https://host/xxx.html）：剥掉 scheme+host
    // 只留路径——_fetchText 会自己拼 "https://$host$path"，不剥就会拼出
    // "https://hosthttps://host/xxx.html" 这种废地址。
    final u = Uri.tryParse(href);
    if (u != null && u.path.isNotEmpty) {
      return u.query.isEmpty ? u.path : '${u.path}?${u.query}';
    }
    return href;
  }

  /// 列表页 / 搜索页通用的文章卡片解析。
  /// 先按 WordPress 模板（article[itemscope]）找，找不到再按 51fans1（.xqbj-list-rows）。
  List<Article> _parseArticles(String html) {
    final doc = hp.parse(html);
    final out = <Article>[];

    for (final el in doc.querySelectorAll('article[itemscope]')) {
      final cls = el.className ?? '';
      // 广告卡与站外推广卡
      // 注意：分类页的链接是相对路径（/archives/xxx/），但**搜索页是绝对地址**
      // （https://host/archives/xxx/）——只认相对路径会把搜索结果全丢掉。
      final a = el.querySelector('a[href*="/archives/"]');
      if (a == null || cls.contains('ad-item')) continue;
      final titleEl = el.querySelector('.post-card-title');
      final title = titleEl?.text.trim() ?? '';
      if (title.isEmpty) continue;
      // 封面：post-card 内的 loadBannerDirect('url', ...
      String cover = '';
      for (final s in el.querySelectorAll('script')) {
        final m = RegExp("loadBannerDirect\\('([^']+)'").firstMatch(s.text);
        if (m != null) {
          cover = m.group(1)!;
          break;
        }
      }
      if (cover.isEmpty) {
        final img = el.querySelector('img[data-src]');
        cover = img?.attributes['data-src'] ?? '';
      }
      final info = el.querySelector('.post-card-info');
      out.add(Article(
        title: title,
        url: _toRelPath(a.attributes['href'] ?? ''),
        cover: cover,
        // 卡片标题下面只显示时间：这行原来是"作者 • 日期 • 分类"，作者和分类都不要
        meta: metaDate(info?.text ?? ''),
      ));
    }

    // 51fans1：div.xqbj-list-rows（封面地址在 z-image-loader-url，值偶尔带一个反引号）
    if (out.isEmpty) {
      for (final el in doc.querySelectorAll('div.xqbj-list-rows')) {
        final a = el.querySelector('a[href*="/archives/"]');
        if (a == null) continue;
        final title = (el.querySelector('.xqbj-list-rows-image-title')?.text ?? '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (title.isEmpty) continue;
        final img = el.querySelector('img[z-image-loader-url]');
        final cover = (img?.attributes['z-image-loader-url'] ?? '')
            .replaceAll('`', '')
            .trim();
        // 时间：移动端文案更全（"9月29日"），桌面端只有时刻（"19:00"）→ 优先移动端
        var meta = (el
                    .querySelector('.xqbj-list-rows-bottom-tags-text.is-mobile')
                    ?.text ??
                '')
            .trim();
        if (meta.isEmpty || metaDate(meta).isEmpty) {
          final desk = (el
                      .querySelector('.xqbj-list-rows-bottom-tags-text.is-desktop')
                      ?.text ??
                  '')
              .trim();
          if (desk.isNotEmpty) meta = desk;
        }
        out.add(Article(
          title: title,
          url: _toRelPath(a.attributes['href'] ?? ''),
          cover: cover,
          meta: metaDate(meta),
        ));
      }
    }

    // 去重（同页重复卡片）
    final seen = <String>{};
    return [
      for (final a in out)
        if (seen.add(a.url)) a
    ];
  }

  /// WordPress 系详情页
  Future<ArticleDetail> _wpDetail(String url) async {
    final html = await _fetchText(url);
    final doc = hp.parse(html);

    // 标题：WP 模板是 .post-title，51fans1 是 .novel-title h1
    var title = doc.querySelector('.post-title')?.text.trim() ?? '';
    if (title.isEmpty) {
      title = doc.querySelector('.novel-title h1')?.text.trim() ?? '';
    }

    // 简介：文章页 meta description（实测就是本篇的剧情摘要）
    final intro =
        (doc.querySelector('meta[name="description"]')?.attributes['content'] ?? '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

    String time = '';
    final timeMeta = doc.querySelector('meta[itemprop="datePublished"]');
    if (timeMeta != null) {
      time = timeMeta.attributes['content'] ?? '';
    }
    if (time.isEmpty) {
      // 51fans1：.novel-info 里"2026-08-08 11:39:00发布"
      time = metaDate(doc.querySelector('.novel-info')?.text ?? '');
    }

    final categories = <String>[];
    for (final a in doc.querySelectorAll('a[href^="/category/"]')) {
      final href = a.attributes['href'] ?? '';
      final segs = Uri.parse('https://x$href').pathSegments;
      // pathSegments: ['category', 'wpcz', '']
      for (final s in segs) {
        if (s.isNotEmpty && s != 'category') {
          if (!categories.contains(s)) categories.add(s);
          break;
        }
      }
    }

    // 正文剧照：
    // - WP 系只认 data-xkrkllgl（推广图/主题图都不在这里）
    // - 51fans1 是 .defaultimg 里 img[data-image-preview][z-image-loader-url]
    final images = <String>[];
    for (final img in doc.querySelectorAll('.post-content img')) {
      final src = img.attributes['data-xkrkllgl'] ?? '';
      if (src.startsWith('http') && !images.contains(src)) images.add(src);
    }
    if (images.isEmpty) {
      for (final img in doc.querySelectorAll('img[data-image-preview]')) {
        final src =
            (img.attributes['z-image-loader-url'] ?? '').replaceAll('`', '').trim();
        if (src.startsWith('http') && !images.contains(src)) images.add(src);
      }
    }
    // 结构变化兜底：整篇都没有上面的标记时才退回 data-src/src（排除推广图）
    if (images.isEmpty) {
      for (final img in doc.querySelectorAll('.post-content img')) {
        final src = img.attributes['data-src'] ?? (img.attributes['src'] ?? '');
        if (!src.startsWith('http') || src.contains('/hc237/')) continue;
        if (!images.contains(src)) images.add(src);
      }
    }

    // 视频：正文里可能有多块 div.dplayer[data-config]（合集类文章一篇挂多个视频），
    // 全部收下来，按集数排序。每块前面通常先是一行 "视频一："、再是标题（blockquote），
    // 就近往上取最多两条短文本，用它们做序号和展示名。
    // 注意：video_h265 可能是对象（有 H265 源）也可能是空数组（无），必须类型容错。
    final videos = <ArticleVideo>[];
    var order = 0;
    for (final dp in doc.querySelectorAll('.dplayer[data-config]')) {
      order++;
      final sources = dplayerSources(dp);
      // 就近往上找最多两条短文本（空行跳过，长正文不算）
      final texts = <String>[];
      for (var e = dp.previousElementSibling;
          e != null && texts.length < 2;
          e = e.previousElementSibling) {
        final t = e.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (t.isEmpty || t.length > 60) continue;
        texts.add(t);
      }
      final parsed = texts.map(_videoOrdinal).firstWhere((v) => v > 0, orElse: () => 0);
      final ordinal = parsed > 0 ? parsed : order;
      // 只有确实出现了"视频X："编号，才把邻近文字当标题，
      // 否则（普通单视频文章）附近的短段落会被误当标题
      final label = parsed > 0 && texts.isNotEmpty ? texts.first : '';
      videos.add(ArticleVideo(
        label: label.isEmpty ? '视频 $ordinal' : label,
        ordinal: ordinal,
        sources: sources,
      ));
    }
    // 合集文章（如 51吃瓜 /archives/277245/）：正文里没有播放器，只有一串
    // "👉点我查看详情帖"链接，真正的视频在那些子文章里 → 逐个抓回来取源，
    // 拼成本篇的"篇内视频"，选集里就能切。并发抓，不然 5 篇串行要十几秒。
    if (videos.isEmpty) {
      final subs = <MapEntry<String, String>>[]; // url -> 链接文字
      // 结构规律（不看链接文字，2026-09-30 拿 4 篇样本对齐出来的）：
      // 正文里真·子文章链接的**直接父元素是 <p>**；
      // 而"吃瓜爆料"推广在 th、上一篇/下一篇在 span.prev/span.next、
      // "相关文章"在 div.link-list（hot-news 侧栏）、版权那行是 p.content-copyright
      // （href 就是本页，被 "href == url" 排除）→ 一条父级判断就够，不用认字。
      final contentEl = doc.querySelector('.post-content');
      for (final a in contentEl?.querySelectorAll('a[href*="/archives/"]') ??
          const <Element>[]) {
        // 两道结构判定：直接父级是 <p>，且这个 <p> 是 .post-content 的直接子元素。
        // （只判第一道会把"内容标签页部件"里那个 <p><a> 也收进来，实测踩过）
        final parent = a.parent;
        if (parent == null || parent.localName != 'p') continue;
        if (parent.parent != contentEl) continue;
        final href = _toRelPath(a.attributes['href'] ?? '');
        final t = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (href.isEmpty || t.isEmpty || href == url) continue;
        if (subs.any((e) => e.key == href)) continue;
        subs.add(MapEntry(href, t));
        if (subs.length >= 20) break;
      }
      // ⚠️ 这里**不预抓**子文章：只把「标题 + 地址」放进选集，用户点到哪一集
      // 才去抓那一篇的源（`videoSourcesAt`）——详情页首屏就只有 1 个请求，
      // 跟普通文章一样快；顺带好处是播放地址永远是新鲜的（auth_key 不会放旧）。
      if (subs.isNotEmpty) {
        var o = 0;
        for (final e in subs) {
          o++;
          videos.add(ArticleVideo(
            label: _cleanSubTitle(e.value),
            ordinal: o,
            sources: const [],
            lazyUrl: e.key,
          ));
        }
      }
    }

    videos.sort((a, b) => a.ordinal.compareTo(b.ordinal));

    // 标签：正文/侧栏里指向 /tag/xxx/ 的链接（名称取链接文字）
    final tags = <MapEntry<String, String>>[];
    for (final a in doc.querySelectorAll('a[href*="/tag/"]')) {
      final href = a.attributes['href'] ?? '';
      final t = a.text.trim();
      if (href.isEmpty || t.isEmpty || t.length > 20) continue;
      final slug = href.split('/tag/').last.replaceAll('/', '');
      if (slug.isEmpty) continue;
      if (!tags.any((e) => e.key == slug)) tags.add(MapEntry(slug, t));
      if (tags.length >= 30) break;
    }

    // 相关推荐：尾部「热门新闻」区（显示在剧照下方）。
    // 站点可以关掉（51吃瓜 用户要求不显示）。
    // class 实际是 hot-news-section / hot-news-box / hot-news-content——并没有单独的
    // .hot-news 元素，原来的 .hot-news 选择器一条都匹配不到（区块不显示）。
    // 每条 = 一句话标题（p）+「相关文章」链接（无封面图）。
    final related = <Article>[];
    for (final el in site.showRelated
        ? doc.querySelectorAll('.hot-news-content')
        : const <Element>[]) {
      final a = el.querySelector('a[href*="/archives/"]');
      if (a == null) continue;
      final href = a.attributes['href'] ?? '';
      final t = (el.querySelector('p')?.text ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (href.isEmpty || t.isEmpty || href == url) continue;
      if (related.any((x) => x.url == _toRelPath(href))) continue;
      related.add(Article(
        title: t,
        url: _toRelPath(href),
        cover: '',
        meta: '',
      ));
      if (related.length >= 12) break;
    }

    return ArticleDetail(
      title: title,
      time: time,
      categories: categories,
      images: images,
      intro: intro,
      videos: videos,
      tags: tags,
      related: related,
      seriesPrefix: seriesPrefix(title),
    );
  }

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

  static final _kmAes =
      Encrypter(AES(Key(utf8.encode('625202f9149maomi')), mode: AESMode.cbc));
  static final _kmIv = IV(utf8.encode('5efd3f6060emaomi'));

  String _kmHex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();

  /// hex → 字节。encrypt 包的 Encrypted 要 Uint8List（不是 List<int>）
  Uint8List _kmBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i + 1 < hex.length; i += 2) {
      out[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return out;
  }

  /// 快猫的加密 API：请求体 JSON → AES-128-CBC（Pkcs7）→ 大写 HEX；form 编码
  /// POST `data=<hex>&sig=<md5('data=<hex>maomi_pass_xyz')>`；响应同密钥密文 →
  /// 解密成 JSON。站点有访客态接口（不用登录），md5 用 crypto 包。
  Future<Map<String, dynamic>> _kmPost(
      String path, Map<String, dynamic> body) async {
    final hex = _kmHex(
        _kmAes.encryptBytes(utf8.encode(jsonEncode(body)), iv: _kmIv).bytes);
    final sig =
        md5.convert(utf8.encode('data=$hex' 'maomi_pass_xyz')).toString();
    final order = [
      if (hosts.contains(_host)) _host,
      ...hosts.where((h) => h != _host),
    ];
    for (final h in order) {
      try {
        final r = await _client
            .post(
              Uri.parse('https://$h$path'),
              headers: {
                'User-Agent': Site.ua,
                'Referer': 'https://$h/',
                'Origin': 'https://$h',
                'Accept-Language': 'zh-CN,zh;q=0.9',
                'Content-Type':
                    'application/x-www-form-urlencoded; charset=UTF-8',
              },
              body: 'data=$hex&sig=$sig',
            )
            .timeout(const Duration(seconds: 10));
        if (r.statusCode != 200) continue;
        _host = h;
        final plain = _kmAes.decryptBytes(
            Encrypted(_kmBytes(utf8.decode(r.bodyBytes).trim())),
            iv: _kmIv);
        return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      } catch (_) {
        // 换下一个域名
      }
    }
    throw Exception('请求失败');
  }

  /// 快猫列表：listHot（热门视频）/ listAll（视频广场），19 条/页、页码从 1 起。
  /// 卡片：竖版封面、标题、发布时间（用户要求不显示作者名），角标 = 点赞数（♡N）；
  /// is_cat_ads=1 是广告位（站点本会跳外链），跳过。
  Future<List<Article>> _kmList(String api, {int page = 1}) async {
    final j = await _kmPost(api, {'perPage': 19, 'page': page});
    if (j['code'] != 0) return const [];
    final data = j['data'];
    final list =
        (data is Map ? (data['list'] ?? const []) : const []) as List;
    final out = <Article>[];
    for (final v in list) {
      if (v is! Map) continue;
      if ((v['is_cat_ads'] ?? 0) == 1) continue;
      final id = (v['mv_id'] ?? '').toString();
      if (id.isEmpty) continue;
      final created = (v['mv_created'] ?? '').toString();
      out.add(Article(
        title: (v['mv_title'] ?? '').toString(),
        url: id,
        cover: (v['mv_img_url'] ?? '').toString(),
        // 用户要求：不显示作者名，只留发布时间（"09-29 18:12"）
        meta: created.length >= 16 ? created.substring(5, 16) : created,
        badge: '♡${v['mv_like'] ?? 0}',
      ));
    }
    return out;
  }

  /// 快猫详情：/api/videos/detail（必须带 uId——站点访客默认 60364099，不带会报
  /// "用户未登录"）。播放地址取详情里的 **https 直链**（列表中那份是 http://IP/…
  /// 形式，iOS ATS 不允许 http，且从开发机实测不可达）。
  Future<ArticleDetail> _kmDetail(String url) async {
    final j =
        await _kmPost('/api/videos/detail', {'mvId': url, 'uId': '60364099'});
    final data = j['data'];
    final d = data is Map ? data : const <dynamic, dynamic>{};
    final play = (d['mv_play_url'] ?? '').toString();
    final cover = (d['mv_img_url'] ?? '').toString();
    return ArticleDetail(
      title: (d['mv_title'] ?? '').toString(),
      time: (d['mv_created'] ?? '').toString(),
      categories: const [],
      images: cover.isEmpty ? const [] : [cover],
      intro: '',
      videos: [
        if (play.isNotEmpty)
          ArticleVideo(label: '视频', ordinal: 1, sources: [play]),
      ],
      tags: const [],
      related: const [],
      seriesPrefix: '',
    );
  }

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

  /// 卡片解析（首页/分类/搜索/标签/榜单共用）
  List<Article> _mdCards(String html) {
    final doc = hp.parse(html);
    final out = <Article>[];
    for (final el in doc.querySelectorAll('article.excerpt')) {
      final href =
          _toRelPath(el.querySelector('a.thumbnail')?.attributes['href'] ?? '');
      if (href.isEmpty) continue;
      final title = (el.querySelector('h2 a')?.text ?? '').trim();
      if (title.isEmpty) continue;
      // 封面必须是真图：img[src] 是懒加载占位（thumb.png），真封面在 data-src 上
      final cover =
          (el.querySelector('a.thumbnail img')?.attributes['data-src'] ?? '')
              .trim();
      if (cover.isEmpty || cover.endsWith('/showcase/img/thumb.png')) continue;
      // 观看数：站点原文「观看(59.26K)」**原样**显示（用户先要求只留数字、
      // 随后又说"观看数加回去"，以最终要求为准；见 DEVLOG 第 55/57 条）
      out.add(Article(
        title: title,
        url: href,
        cover: cover,
        meta: (el.querySelector('.post-view')?.text ?? '').trim(),
        // ⚠️ 卡片上的分类名**不取**：footer 里那个 `rel="category tag"`（如"麻豆传媒"）
        // 用户明确要求去掉（2026-10-01，见 DEVLOG 第 56 条）——挂 Article.tags 会在
        // 卡片上渲染成可点胶囊。详情页的分类/标签不受影响（走 _mdDetail 的 .item-3/.article-tags）。
      ));
    }
    final seen = <String>{};
    return [
      for (final a in out)
        if (seen.add(a.url)) a
    ];
  }

  /// 详情：标题/分类/标签/相关推荐/播放源（站点没有时长、系列、简介、发布时间）
  Future<ArticleDetail> _mdDetail(String url) async {
    final doc = hp.parse(await _fetchText(url));
    final title = (doc.querySelector('.article-title')?.text ?? '').trim();
    final catName = (doc.querySelector('.item-3 a')?.text ?? '').trim();
    // 标签：slug = URL 最后一段（原始编码值，不解码——与其它站点做法一致）
    final tags = <MapEntry<String, String>>[];
    for (final a in doc.querySelectorAll('.article-tags a')) {
      final name = a.text.trim();
      final slug = _mdLastSeg(a.attributes['href'] ?? '');
      if (name.isEmpty || slug.isEmpty) continue;
      if (tags.any((e) => e.key == slug)) continue;
      tags.add(MapEntry(slug, name));
    }
    // 相关推荐：标题取锚的文本（<a> 里只有一个缩进的 span>img，没有别的文本节点）
    final related = <Article>[];
    for (final a in doc.querySelectorAll('.postitems li a')) {
      final href = _toRelPath(a.attributes['href'] ?? '');
      final t = a.text.trim();
      if (href.isEmpty || t.isEmpty || href == url) continue;
      if (related.any((x) => x.url == href)) continue;
      related.add(Article(
        title: t,
        url: href,
        cover:
            (a.querySelector('img[data-src]')?.attributes['data-src'] ?? '')
                .trim(),
        meta: '',
      ));
      if (related.length >= 12) break;
    }
    final play = await _mdPlayUrl(doc);
    return ArticleDetail(
      title: title.isEmpty ? url : title,
      time: '',
      categories: [if (catName.isNotEmpty) catName],
      images: const [],
      intro: '',
      videos: [
        if (play.isNotEmpty)
          ArticleVideo(label: title, ordinal: 1, sources: [play]),
      ],
      tags: tags,
      related: related,
      seriesPrefix: '',
    );
  }

  /// URL 最后一段（标签 slug 用；空链接返回空串）
  static String _mdLastSeg(String href) {
    final segs = href.split('/').where((s) => s.isNotEmpty).toList();
    return segs.isEmpty ? '' : segs.last;
  }

  /// 麻豆社「热门标签」标签云页（/tags）——**不是文章卡片**，别用 _mdCards 解：
  /// `.tagslist li` 里 `a.name`=标签名（href 是 /tag/{slug}）、`<small>`=文章数
  /// （HTML 实体由 dom 包解出来，形如 ×2577）、`a.tit` 是"该标签下的一篇示例文章"
  /// （**忽略**）。没有封面 → 卡片变纯文字卡。站点**没有分页**（实测无 .pagination）。
  List<Article> _mdTags(String html) {
    final doc = hp.parse(html);
    final out = <Article>[];
    for (final li in doc.querySelectorAll('.tagslist li')) {
      final a = li.querySelector('a.name');
      if (a == null) continue;
      final title = a.text.trim();
      final slug = _mdLastSeg(a.attributes['href'] ?? '');
      if (title.isEmpty || slug.isEmpty) continue;
      if (out.any((x) => x.url == '/tag/$slug')) continue;
      out.add(Article(
        title: title,
        url: '/tag/$slug',
        cover: '',
        // 站点显示 "×N"（=该标签下的文章数），原样保留
        meta: (li.querySelector('small')?.text ?? '').trim(),
      ));
    }
    return out;
  }

  /// 播放源：正文第一个 iframe → dash.madou.club 分享页 → 页面里两行 JS
  /// （token 是双引号、m3u8 是单引号）→ `https://dash.madou.club{m3u8}?token=`。
  /// 任何一步拿不到就返回空串（videos 留空，不抛异常、不编假地址）；
  /// token 只有 100 秒时效，过期靠上层「起播失败 → 重新抓详情页」兜底。
  Future<String> _mdPlayUrl(Document doc) async {
    final share = (doc.querySelector('.article-content iframe')
                ?.attributes['src'] ??
            '')
        .trim();
    if (share.isEmpty) return '';
    final html = await _fetchAbs(share);
    if (html.isEmpty) return '';
    final tok =
        RegExp(r'var\s+token\s*=\s*"([^"]*)"').firstMatch(html)?.group(1) ?? '';
    final path =
        RegExp(r"var\s+m3u8\s*=\s*'([^']*)'").firstMatch(html)?.group(1) ?? '';
    if (tok.isEmpty || path.isEmpty) return '';
    final abs = path.startsWith('http') ? path : 'https://dash.madou.club$path';
    return '$abs?token=$tok';
  }

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

  /// 合集的"详情帖"链接文字 → 当选集标题：
  /// "👉点我查看详情帖 越南爆乳福利姬 xxx 【第5弹】" → "越南爆乳福利姬 xxx 【第5弹】"
  static String _cleanSubTitle(String raw) {
    var t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t.replaceAll('点我查看详情帖', ' ');
    t = t.replaceAll(RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.isEmpty ? '视频' : t;
  }

  /// "视频一：" → 1；"视频12：" → 12；没有编号返回 0
  static int _videoOrdinal(String s) {
    final m = RegExp(r'视频\s*([0-9一二三四五六七八九十百]+)').firstMatch(s);
    if (m == null) return 0;
    final t = m.group(1)!;
    if (RegExp(r'^[0-9]+$').hasMatch(t)) return int.parse(t);
    const cn = {
      '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
      '六': 6, '七': 7, '八': 8, '九': 9,
    };
    if (t == '十') return 10;
    if (t.startsWith('十')) return 10 + (cn[t.substring(1)] ?? 0);
    if (t.contains('十')) {
      final parts = t.split('十');
      return (cn[parts[0]] ?? 0) * 10 +
          (parts.length > 1 ? (cn[parts[1]] ?? 0) : 0);
    }
    return cn[t] ?? 0;
  }



  // ---------------------------------------------------------------------------
}
