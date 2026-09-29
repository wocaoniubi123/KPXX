import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:html/dom.dart';
import 'package:html/parser.dart' as hp;

import 'config.dart';
import 'models.dart';
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
class Api {
  /// site：站点清单里的那条（域名、模板、分类都从这来）
  Api({required this.site})
      : hosts = site.hosts,
        _host = site.hosts.isNotEmpty ? site.hosts.first : '';

  final SiteEntry site;
  final List<String> hosts;
  String _host;

  /// 共享连接池：多处 Api 实例复用同一条 client
  static final http.Client _client = http.Client();

  String get base => 'https://$_host';

  /// 顺序尝试域名，返回第一个成功的文本。
  /// 上次跑通的域名排最前：站点常有一两个域名挂掉，若每次从列表头开始试，
  /// 每个请求都要先白等一次超时（列表/详情/视频启动全被拖慢）。
  Future<String> _fetchText(String path) async {
    final order = [
      if (hosts.contains(_host)) _host,
      ...hosts.where((h) => h != _host),
    ];
    for (final h in order) {
      // 5xx 是站点偶发（51fans1 实测会间歇性 500），同一个域名再试一次
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final r = await _client.get(
            Uri.parse('https://$h$path'),
            headers: {
              'User-Agent': Site.ua,
              'Referer': 'https://$h/',
              'Accept':
                  'text/html,application/xhtml+xml;application/json;q=0.9,*/*;q=0.8',
            },
          ).timeout(const Duration(seconds: 8));
          if (r.statusCode == 200) {
            _host = h;
            return utf8.decode(r.bodyBytes);
          }
          if (r.statusCode < 500) break; // 4xx 重试没用，直接换域名
        } catch (_) {
          // 超时/连接失败：不再重试同域名，换下一个
          break;
        }
      }
    }
    throw Exception('所有域名均无法访问');
  }

  // ---------------------------------------------------------------------------
  // 列表

  /// 分类/频道列表。page 从 1 开始。
  /// [sub]/[sub2] 是两级子分类 key（有子分类的站点才用）。
  /// 路径型模板（wordpress/porna）取**最深的那个 key** 当站内路径；
  /// 黄果（huangguo）只有一层排序（latest/hot/original/random）。
  Future<List<Article>> category(String key,
      {int page = 1, String? sub, String? sub2}) async {
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
        if (k.startsWith('/')) return _hgPageList(k, page: page);
        // 否则是频道 slug；只有一层排序：子分类 key 就是 sort 值，没选就按最新
        return _huangguoList(key, sort: k == key ? 'latest' : k, page: page);
      case SiteTemplate.porna:
        return _pornaList(k, page: page);
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
        return _huangguoList(first, sort: 'latest', page: page);
      case SiteTemplate.porna:
        final first = site.categories.isEmpty ? '' : site.categories.first.key;
        return _pornaList(first, page: page);
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
        if (slug.startsWith('/')) return _hgPageList(slug, page: page);
        if (page > 1) return [];
        return _parseHuangguoCards(hp.parse(await _fetchText('/tag/$slug/')));
      case SiteTemplate.porna:
        // 这站的"标签"分两种：以 / 开头的是站内分类页（黑料吃瓜的标签），
        // 其余是搜索关键词（视频页的 keywords）
        return _pornaList(slug.startsWith('/') ? slug : 'search:$slug',
            page: page);
    }
  }

  /// 搜索（关键词需原始文本，内部编码）。
  Future<List<Article>> search(String keyword, {int page = 1}) async {
    switch (site.template) {
      case SiteTemplate.wordpress:
        if (page > 1) return []; // 站点无搜索分页
        final path = '/search/${Uri.encodeComponent(keyword)}/';
        return _parseArticles(await _fetchText(path));
      case SiteTemplate.huangguo:
        if (page > 1) return []; // 只支持第一页
        final kw = Uri.encodeComponent(keyword);
        final html = await _fetchText('/search/?keyword=$kw');
        return _parseHuangguoCards(hp.parse(html));
      case SiteTemplate.porna:
        return _pornaList('search:$keyword', page: page);
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
        if (url.startsWith('/archives/')) return _hgPostDetail(url);
        return _huangguoDetail(url);
      case SiteTemplate.porna:
        // 三种详情页：短视频 / 黑料图文 / 普通视频
        if (url.startsWith('/melonshort/video/')) return _melonDetail(url);
        if (url.startsWith('/heiliao-chigua/')) return _heiliaoDetail(url);
        return _pornaDetail(url);
    }
  }

  // ---------------------------------------------------------------------------
  // WordPress 系（含 51fans1 的兼容分支）

  /// 卡片时间：站点带时分秒就一起显示；只有月-日（51fans1 列表）也照原样显示。
  static String _metaDate(String raw) {
    final t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return '';
    final cn = RegExp(r'\d{4}\s*年\s*\d{1,2}\s*月\s*\d{1,2}\s*日(?:\s*\d{1,2}:\d{2}(?::\d{2})?)?')
        .firstMatch(t);
    if (cn != null) return cn.group(0)!;
    // 51fans1 的列表卡片只有"9月29日"（没有年）
    final cnMd = RegExp(r'\d{1,2}\s*月\s*\d{1,2}\s*日').firstMatch(t);
    if (cnMd != null) return cnMd.group(0)!;
    final iso = RegExp(r'\d{4}[-/.]\d{1,2}[-/.]\d{1,2}(?:\s*\d{1,2}:\d{2}(?::\d{2})?)?')
        .firstMatch(t);
    if (iso != null) return iso.group(0)!;
    final md = RegExp(r'^\d{1,2}-\d{1,2}$').firstMatch(t);
    if (md != null) return md.group(0)!;
    final rel = RegExp(r'\d{1,2}\s*(?:分钟|小时|天)前').firstMatch(t);
    if (rel != null) return rel.group(0)!;
    return '';
  }

  /// 把绝对地址归一化成站内相对路径（详情页只认 /archives/xxx/ 这种）
  static String _toRelPath(String href) {
    if (!href.startsWith('http')) return href;
    final i = href.indexOf('/archives/');
    return i >= 0 ? href.substring(i) : href;
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
        meta: _metaDate(info?.text ?? ''),
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
        if (meta.isEmpty || _metaDate(meta).isEmpty) {
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
          meta: _metaDate(meta),
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
      time = _metaDate(doc.querySelector('.novel-info')?.text ?? '');
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
        // 这一个视频配置坏，视为无源，继续后面的
      }
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
    // class 实际是 hot-news-section / hot-news-box / hot-news-content——并没有单独的
    // .hot-news 元素，原来的 .hot-news 选择器一条都匹配不到（区块不显示）。
    // 每条 = 一句话标题（p）+「相关文章」链接（无封面图）。
    final related = <Article>[];
    for (final el in doc.querySelectorAll('.hot-news-content')) {
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
      seriesPrefix: _seriesPrefix(title),
    );
  }

  // ---------------------------------------------------------------------------
  // 黄果短剧（huangguoai）

  /// 黄果的"路径型"列表页（不是 JSON 接口那套）：
  /// - `/recommend`、`/newest`、`/topics/xxx/` → `hg-drama-card` 网格，翻页 `/xxx/2/`
  /// - `/ranks/hot/`                          → `hg-rank-item`（TOP20，无翻页）
  /// - `/chigua/`                             → `hg-post-card` 图文卡，翻页 `/chigua/page/2/`
  Future<List<Article>> _hgPageList(String path, {int page = 1}) async {
    final p = path.endsWith('/') ? path : '$path/';
    final url = page <= 1
        ? p
        : (p.startsWith('/chigua') ? '${p}page/$page/' : '$p$page/');
    final doc = hp.parse(await _fetchText(url));
    if (p.startsWith('/chigua')) return _hgPostCards(doc);
    if (p.startsWith('/ranks')) return _hgRankCards(doc);
    // 专题列表页（/topics/）上是"专题卡"，专题自己的页面（/topics/xxx/）才是视频网格
    if (p == '/topics/') return _hgTopicCards(doc);
    return _parseHuangguoCards(doc);
  }

  /// 专题卡（a.hg-topic-card → /topics/xxx/）：点开是该专题下的视频列表
  List<Article> _hgTopicCards(Document doc) {
    final out = <Article>[];
    for (final a in doc.querySelectorAll('a.hg-topic-card')) {
      final href = a.attributes['href'] ?? '';
      final title = (a.querySelector('.hg-topic-card__title')?.text ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (href.isEmpty || title.isEmpty) continue;
      final img = a.querySelector('img[data-src]') ?? a.querySelector('img');
      final meta = (a.querySelector('.hg-topic-card__meta')?.text ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      out.add(Article(
        title: title,
        url: href,
        cover: img?.attributes['data-src'] ?? '',
        meta: meta,
      ));
    }
    final seen = <String>{};
    return [
      for (final a in out)
        if (seen.add(a.url)) a
    ];
  }

  /// 吃瓜社区的图文卡（a.hg-post-card → /archives/N/）
  List<Article> _hgPostCards(Document doc) {
    final out = <Article>[];
    for (final a in doc.querySelectorAll('a.hg-post-card')) {
      final href = a.attributes['href'] ?? '';
      final title = (a.querySelector('.hg-post-card__body h3')?.text ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (href.isEmpty || title.isEmpty) continue;
      final img = a.querySelector('img[data-src]') ?? a.querySelector('img');
      final date = (a.querySelector('.hg-post-card__date')?.text ?? '').trim();
      out.add(Article(
        title: title,
        url: href,
        cover: img?.attributes['data-src'] ?? '',
        meta: _metaDate(date),
      ));
    }
    final seen = <String>{};
    return [
      for (final a in out)
        if (seen.add(a.url)) a
    ];
  }

  /// 排行榜（TOP20）：每项一个视频，封面右下角用它自己的名次当角标
  List<Article> _hgRankCards(Document doc) {
    final out = <Article>[];
    for (final el in doc.querySelectorAll('div.hg-rank-item')) {
      final a = el.querySelector('a[href^="/video/"]');
      if (a == null) continue;
      final title = ((el.querySelector('.hg-rank-item__title')?.text ?? a.text))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (title.isEmpty) continue;
      final img = el.querySelector('img[data-src]') ?? el.querySelector('img');
      final num = (el.querySelector('.hg-rank-num')?.text ?? '').trim();
      out.add(Article(
        title: title,
        url: a.attributes['href'] ?? '',
        cover: img?.attributes['data-src'] ?? '',
        meta: num.isEmpty ? '' : '第 $num 名',
      ));
    }
    final seen = <String>{};
    return [
      for (final a in out)
        if (seen.add(a.url)) a
    ];
  }

  /// 吃瓜社区的帖子详情：图文帖（正文在 .hg-post-detail__body，图片走 data-src），没有视频
  Future<ArticleDetail> _hgPostDetail(String url) async {
    final doc = hp.parse(await _fetchText(url));
    final title = (doc.querySelector('h1')?.text ?? '').trim();
    final intro =
        (doc.querySelector('meta[name="description"]')?.attributes['content'] ?? '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    final images = <String>[];
    for (final img in doc.querySelectorAll('.hg-post-detail__body img[data-src]')) {
      final src = img.attributes['data-src'] ?? '';
      if (src.startsWith('http') && !images.contains(src)) images.add(src);
    }
    final time = _metaDate(doc.querySelector('.hg-post-detail')?.text ?? '');
    final tags = <MapEntry<String, String>>[];
    for (final a in doc.querySelectorAll('.hg-post-detail a[href*="/tag/"]')) {
      final href = a.attributes['href'] ?? '';
      final t = a.text.trim();
      if (href.isEmpty || t.isEmpty || t.length > 20) continue;
      final slug = href.split('/tag/').last.replaceAll('/', '');
      if (slug.isEmpty) continue;
      if (!tags.any((e) => e.key == slug)) tags.add(MapEntry(slug, t));
    }
    return ArticleDetail(
      title: title.isEmpty ? url : title,
      time: time,
      categories: const [],
      images: images,
      intro: intro,
      videos: const [], // 吃瓜帖是图文
      tags: tags,
      related: _parseHuangguoCards(doc).where((x) => x.url != url).take(12).toList(),
      seriesPrefix: _seriesPrefix(title),
    );
  }

  /// 列表：JSON 接口 `/api/videos/category/{channel}?sort=..&page=..&size=..`
  /// [sort]：latest / hot / original / random（对应页面上的 4 个子 tab）
  Future<List<Article>> _huangguoList(String channel,
      {required String sort, int page = 1}) async {
    final sortParam = switch (sort) {
      'hot' => 'hot_window',
      'original' => 'hot_window&is_original=1',
      _ => sort,
    };
    final path =
        '/api/videos/category/$channel?sort=$sortParam&page=$page&size=20';
    final body = await _fetchText(path);
    final data = jsonDecode(body);
    if (data is! Map<String, dynamic>) return [];
    final d = data['data'];
    final items = (d is Map<String, dynamic> ? d['items'] : null) ?? const [];
    return [
      for (final it in items)
        if (it is Map<String, dynamic>) _hgArticle(it),
    ];
  }

  Article _hgArticle(Map<String, dynamic> v) {
    final ep = int.tryParse('${v['episode_count'] ?? ''}') ?? 0;
    final total = int.tryParse('${v['total_episodes'] ?? ''}') ?? 0;
    final finished = v['is_finished'] == true;
    final epText = finished && total > 0
        ? '全集$total集'
        : (ep > 0 ? '更新至$ep集' : '');
    return Article(
      title: '${v['title'] ?? ''}'.trim(),
      url: '/video/${v['id']}/',
      cover: '${v['cover'] ?? ''}',
      meta: epText,
      duration: _secClock('${v['duration'] ?? ''}'),
    );
  }

  /// 接口里的时长是秒（字符串或数字）：207 → 3:27
  static String _secClock(String raw) {
    final sec = int.tryParse(raw.trim());
    if (sec == null || sec <= 0) return '';
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// 详情页里的卡片（相关推荐 / 标签页 / 搜索结果都是这套结构）
  List<Article> _parseHuangguoCards(Document doc) {
    final out = <Article>[];
    for (final el in doc.querySelectorAll('div.hg-drama-card')) {
      final a = el.querySelector('a.hg-drama-card__cover-link') ??
          el.querySelector('a[href^="/video/"]');
      if (a == null) continue;
      // 标题：取链接里的文本节点（要排掉 <span class="sr-only">全集在线观看</span>）
      final titleEl = el.querySelector('.hg-drama-card__title a') ?? a;
      final buf = StringBuffer();
      for (final n in titleEl.nodes) {
        if (n is Text) buf.write(n.text);
      }
      var title = buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (title.isEmpty) {
        title = (titleEl.text).replaceAll('全集在线观看', '').trim();
      }
      if (title.isEmpty) continue;
      final img = el.querySelector('img[data-src]') ?? el.querySelector('img');
      // 集数角标：文字形如"更新至5集"/"全集5集"（前面可能有时刻，如"1小时前更新至5集"）
      final epRaw = (el.querySelector('.hg-drama-card__episode')?.text ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      out.add(Article(
        title: title,
        url: a.attributes['href'] ?? '',
        cover: img?.attributes['data-src'] ?? '',
        meta: RegExp(r'(更新至\s*\d+\s*集|全\s*\d+\s*集|完结)').firstMatch(epRaw)?.group(0) ??
            '',
      ));
      if (out.length >= 60) break;
    }
    final seen = <String>{};
    return [
      for (final a in out)
        if (seen.add(a.url)) a
    ];
  }

  /// 详情：页面内嵌 `<script id="videoInitialData" type="application/json">`，
  /// 里面有 title/description/time/coverSrc/tagLinks 以及
  /// epPlaySrcs = {"1": m3u8, "2": m3u8, ...}（整部剧所有集，一次拿全，不用逐集抓）。
  Future<ArticleDetail> _huangguoDetail(String url) async {
    final html = await _fetchText(url);
    final doc = hp.parse(html);

    Map<String, dynamic>? data;
    final raw = doc.querySelector('script#videoInitialData')?.text ?? '';
    if (raw.isNotEmpty) {
      try {
        final j = jsonDecode(raw);
        if (j is Map<String, dynamic>) data = j;
      } catch (_) {
        // 解析不了就退回 DOM 解析
      }
    }

    final videos = <ArticleVideo>[];
    String title = '';
    String intro = '';
    String time = '';
    if (data != null) {
      title = '${data['title'] ?? ''}'.trim();
      intro = '${data['description'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
      time = '${data['time'] ?? ''}'.trim();
      final eps = data['epPlaySrcs'];
      if (eps is Map) {
        final keys = eps.keys.map((k) => int.tryParse('$k') ?? 0).toList()..sort();
        for (final k in keys) {
          final src = '${eps['$k'] ?? ''}';
          if (src.isEmpty) continue;
          videos.add(ArticleVideo(
            label: '第 $k 集',
            ordinal: k <= 0 ? videos.length + 1 : k,
            sources: [src],
          ));
        }
      }
    }

    // 相关推荐：详情页「猜你喜欢」区（排除广告 aside.hg-ssp-slot）
    final related = _parseHuangguoCards(doc);

    // 标签：内嵌 JSON 的 tagLinks（[{name, url}]）
    final tags = <MapEntry<String, String>>[];
    final tagLinks = data?['tagLinks'];
    if (tagLinks is List) {
      for (final t in tagLinks) {
        if (t is Map) {
          final name = '${t['name'] ?? ''}'.trim();
          final u = '${t['url'] ?? ''}';
          final slug = u.split('/tag/').last.replaceAll('/', '');
          if (name.isNotEmpty && slug.isNotEmpty) {
            tags.add(MapEntry(slug, name));
          }
        }
      }
    }
    if (title.isEmpty) {
      title = (doc.querySelector('h1')?.text ?? '').trim();
    }

    return ArticleDetail(
      title: title,
      time: time,
      categories: const [],
      images: const [], // 这站没有剧照（封面就是视频封面）
      intro: intro,
      videos: videos,
      tags: tags,
      related: related.where((a) => a.url != url).take(12).toList(),
      seriesPrefix: _seriesPrefix(title),
    );
  }

  // ---------------------------------------------------------------------------
  // 91porna

  /// 列表：按路径分三种页面类型（都是服务端渲染，取到就能用）：
  /// - `/melonshort*`            → 91短视频：`article.video-card`（封面右下角有时长角标）
  /// - `/heiliao-chigua*`、`/黑料吃瓜/*` → 黑料吃瓜：`a[href^=/heiliao-chigua/]` 图文卡
  /// - 其余（/comic/index/*、/comic/av/*、搜索） → `div.video-item`
  /// [key]：站内路径或 "search:关键词"。
  Future<List<Article>> _pornaList(String key, {int page = 1}) async {
    // 关键词里的空格站点用 + 分隔（encodeQueryComponent 正好把空格编成 +）
    final path = key.startsWith('search:')
        ? '/comic/index/search?keyword=${Uri.encodeQueryComponent(key.substring(7))}'
        : key;
    final url = page <= 1
        ? path
        : '$path${path.contains('?') ? '&' : '?'}page=$page';
    final html = await _fetchText(url);
    final doc = hp.parse(html);
    if (path.startsWith('/melonshort')) return _melonCards(doc);
    // ⚠️ 只看路径部分：搜索关键词里也可能出现"黑料"（%E9%BB%91%E6%96%99），
    // 用整个 path 判断会把搜索结果页错认成黑料页（而且要用完整的"黑料吃瓜"编码）
    final p0 = path.split('?').first;
    if (p0.contains('heiliao') || p0.contains('%E9%BB%91%E6%96%99%E5%90%83%E7%93%9C')) {
      return _heiliaoCards(doc);
    }
    return _pornaCards(doc);
  }

  /// 91短视频的卡片
  List<Article> _melonCards(Document doc) {
    final out = <Article>[];
    for (final el in doc.querySelectorAll('article.video-card')) {
      final a = el.querySelector('a.video-card-link') ?? el.querySelector('a');
      if (a == null) continue;
      final title = (el.querySelector('h3.title')?.text ?? '').trim();
      if (title.isEmpty) continue;
      final img = el.querySelector('img[data-src]') ?? el.querySelector('img');
      final dur = (el.querySelector('span.badge-duration')?.text ?? '').trim();
      out.add(Article(
        title: title,
        url: a.attributes['href'] ?? '',
        cover: img?.attributes['data-src'] ?? '',
        meta: '',
        duration: RegExp(r'\d{1,2}:\d{2}(?::\d{2})?').firstMatch(dur)?.group(0) ?? '',
      ));
    }
    final seen = <String>{};
    return [
      for (final a in out)
        if (seen.add(a.url)) a
    ];
  }

  /// 黑料吃瓜的图文卡（标题/封面/时间都在卡片里）
  List<Article> _heiliaoCards(Document doc) {
    final out = <Article>[];
    for (final a in doc.querySelectorAll('a[href^="/heiliao-chigua/"]')) {
      final title = (a.querySelector('.post-item-title')?.text ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (title.isEmpty) continue;
      final poster = a.querySelector('.post-item-poster');
      final desc = a.querySelector('.post-item-desc')?.text ?? '';
      out.add(Article(
        title: title,
        url: a.attributes['href'] ?? '',
        cover: poster?.attributes['data-src'] ?? '',
        // desc 形如"今日爆料 • 2026-09-29 • 分类1,分类2" → 只留时间
        meta: _metaDate(desc),
      ));
    }
    final seen = <String>{};
    return [
      for (final a in out)
        if (seen.add(a.url)) a
    ];
  }

  List<Article> _pornaCards(Document doc) {
    final out = <Article>[];
    for (final el in doc.querySelectorAll('div.video-item')) {
      // 普通视频是 /comic/index/detail?video_key=xxx，日本AV 是 /comic/index/avdetail?video_key=xxx
      final a = el.querySelector('a[href*="/comic/index/detail"]') ??
          el.querySelector('a[href*="/comic/index/avdetail"]');
      if (a == null) continue;
      final href = a.attributes['href'] ?? '';
      final img = el.querySelector('img[data-src]') ?? el.querySelector('img');
      String title = '';
      for (final d in el.querySelectorAll('div')) {
        if ((d.className ?? '').contains('line-clamp-2')) {
          title = d.text.replaceAll(RegExp(r'\s+'), ' ').trim();
          break;
        }
      }
      if (title.isEmpty) title = (img?.attributes['alt'] ?? '').trim();
      if (title.isEmpty) continue;
      // 时长角标：右下角那个黑底 div（形如 1:00:39 / 12:34）
      var duration = '';
      for (final d in el.querySelectorAll('div')) {
        final t = d.text.trim();
        if (RegExp(r'^\d{1,2}:\d{2}(?::\d{2})?$').hasMatch(t)) {
          duration = t;
          break;
        }
      }
      out.add(Article(
        title: title,
        url: href,
        cover: img?.attributes['data-src'] ?? '',
        meta: '',
        duration: duration,
      ));
    }
    final seen = <String>{};
    return [
      for (final a in out)
        if (seen.add(a.url)) a
    ];
  }

  /// 91短视频详情：页面里 `<script id="ms-bootstrap">` 的 `first_screen.list`
  /// 带全部字段（signed `video_url`、cover、video_duration 秒、publish_time），
  /// 当前视频按 URL 里的 id 找；同一数组里其余的就是"相关推荐"。
  Future<ArticleDetail> _melonDetail(String url) async {
    final html = await _fetchText(url);
    final doc = hp.parse(html);
    Map<String, dynamic>? boot;
    final raw = doc.querySelector('script#ms-bootstrap')?.text ?? '';
    if (raw.isNotEmpty) {
      try {
        final j = jsonDecode(raw);
        if (j is Map<String, dynamic>) boot = j;
      } catch (_) {
        // 解析不了当无数据
      }
    }
    final items = <Map<String, dynamic>>[];
    final fs = boot?['first_screen'];
    if (fs is Map && fs['list'] is List) {
      for (final v in fs['list'] as List) {
        if (v is Map<String, dynamic>) items.add(v);
      }
    }
    final id = int.tryParse(
        RegExp(r'/melonshort/video/(\d+)').firstMatch(url)?.group(1) ?? '');
    Map<String, dynamic>? cur;
    for (final v in items) {
      if (int.tryParse('${v['id']}') == id) {
        cur = v;
        break;
      }
    }
    cur ??= items.isNotEmpty ? items.first : null;

    final videos = <ArticleVideo>[];
    final src = '${cur?['video_url'] ?? ''}';
    if (src.isNotEmpty) {
      videos.add(ArticleVideo(label: '视频 1', ordinal: 1, sources: [src]));
    }
    final related = <Article>[];
    for (final v in items) {
      if (identical(v, cur)) continue;
      final t = '${v['title'] ?? ''}'.trim();
      if (t.isEmpty) continue;
      related.add(Article(
        title: t,
        url: '/melonshort/video/${v['id']}',
        cover: '${v['cover'] ?? ''}',
        meta: '',
        duration: _secClock('${v['video_duration'] ?? ''}'),
      ));
      if (related.length >= 12) break;
    }
    final title = '${cur?['title'] ?? ''}'.trim();
    return ArticleDetail(
      title: title.isEmpty ? url : title,
      time: '${cur?['publish_time'] ?? ''}'.trim(),
      categories: const [],
      images: const [],
      intro: '${cur?['desc'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim(),
      videos: videos,
      tags: const [],
      related: related,
      seriesPrefix: _seriesPrefix(title),
      duration: _secClock('${cur?['video_duration'] ?? ''}'),
    );
  }

  /// 黑料吃瓜详情：图文帖 + **正文里的视频**。
  /// 视频不是 `<video>`/dplayer，而是正文里一块 `ql-video-mse`，地址由
  /// `/index/melon_detail_play.js?img=&u=<页面内嵌 token>&t=<时间戳/2100>` 换回来，
  /// 且响应是**打包过的 JS**（把 m3u8 拆成字典碎片），所以要解包后再抠地址。
  /// 标签是元信息行里指向 `/黑料吃瓜/xxx` 的分类链接。
  Future<ArticleDetail> _heiliaoDetail(String url) async {
    final html = await _fetchText(url);
    final doc = hp.parse(html);
    final title = (doc.querySelector('h1')?.text ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final intro =
        (doc.querySelector('meta[name="description"]')?.attributes['content'] ?? '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    var time = doc.querySelector('time')?.attributes['datetime'] ?? '';
    if (time.isEmpty) {
      time = _metaDate(doc.querySelector('.dx-text')?.text ?? '');
    }
    final images = <String>[];
    for (final img in doc.querySelectorAll('article.ql-editor img[data-src]')) {
      final src = img.attributes['data-src'] ?? '';
      if (src.startsWith('http') && !images.contains(src)) images.add(src);
    }
    // 正文里的视频（一篇可能有多个）
    final videos = <ArticleVideo>[];
    var order = 0;
    for (final m in RegExp(r'parseInt\|([0-9a-f]{60,400})\|').allMatches(html)) {
      order++;
      final src = await _pornaPlayUrlByToken(m.group(1)!, 'melon_detail_play');
      if (src.isEmpty) continue;
      videos.add(ArticleVideo(
        label: '视频 $order',
        ordinal: order,
        sources: [src],
      ));
    }
    // 标签：`/黑料吃瓜/xxx` 分类链接（点进去是该分类的图文列表）
    final tags = <MapEntry<String, String>>[];
    for (final a in doc.querySelectorAll('a.border-link')) {
      final href = a.attributes['href'] ?? '';
      final name = a.text.trim();
      if (href.isEmpty || name.isEmpty || name.length > 20) continue;
      if (!href.contains('%E9%BB%91%E6%96%99%E5%90%83%E7%93%9C')) continue;
      if (!tags.any((e) => e.key == href)) tags.add(MapEntry(href, name));
    }
    return ArticleDetail(
      title: title.isEmpty ? url : title,
      time: time,
      categories: const [],
      images: images,
      intro: intro,
      videos: videos,
      tags: tags,
      related: _heiliaoCards(doc).where((a) => a.url != url).take(12).toList(),
      seriesPrefix: _seriesPrefix(title),
    );
  }

  /// 详情：
  /// - 标题/简介/时长/时间/标签 来自页面内嵌的 LD+JSON（VideoObject）
  /// - 播放地址要再请求 `/index/detail_play`：参数 img=封面路径、u=页面里内嵌的
  ///   160 位 hex token、t=时间戳/2100（照抄前端 JS 的算法），响应里就是 m3u8。
  Future<ArticleDetail> _pornaDetail(String url) async {
    final html = await _fetchText(url);
    final doc = hp.parse(html);

    // LD+JSON
    Map<String, dynamic>? videoObj;
    for (final s in doc.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        final j = jsonDecode(s.text);
        final graph = (j is Map<String, dynamic>) ? j['@graph'] : null;
        if (graph is List) {
          for (final n in graph) {
            if (n is Map<String, dynamic> && n['@type'] == 'VideoObject') {
              videoObj = n;
            }
          }
        }
      } catch (_) {
        // 忽略坏 JSON
      }
    }

    final title = ('${videoObj?['name'] ?? ''}').trim().isNotEmpty
        ? '${videoObj!['name']}'.trim()
        : ((doc.querySelector('meta[property="og:title"]')?.attributes['content'] ??
                '')
            .trim());
    final intro = '${videoObj?['description'] ?? ''}'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final duration = _pornaDuration('${videoObj?['duration'] ?? ''}');
    final time = '${videoObj?['uploadDate'] ?? videoObj?['datePublished'] ?? ''}';

    // 封面：og:image（LD+JSON 里也有）
    var cover = doc
            .querySelector('meta[property="og:image"]')
            ?.attributes['content'] ??
        '';
    final thumbs = videoObj?['thumbnailUrl'];
    if (cover.isEmpty && thumbs is List && thumbs.isNotEmpty) {
      cover = '${thumbs.first}';
    }

    // 标签：LD+JSON keywords（点击 → 关键词搜索）
    final tags = <MapEntry<String, String>>[];
    final kws = videoObj?['keywords'];
    if (kws is List) {
      for (final k in kws) {
        final t = '$k'.trim();
        if (t.isNotEmpty) tags.add(MapEntry(t, t));
      }
    }

    // 播放地址：/index/detail_play
    final videos = <ArticleVideo>[];
    final src = await _pornaPlayUrl(html, cover);
    if (src.isNotEmpty) {
      videos.add(ArticleVideo(label: '视频 1', ordinal: 1, sources: [src]));
    }

    return ArticleDetail(
      title: title.isEmpty ? url : title,
      time: time,
      categories: const [],
      images: const [], // 这站没有剧照（封面就是视频封面）
      intro: intro,
      videos: videos,
      tags: tags,
      related: _pornaCards(doc).where((a) => a.url != url).take(12).toList(),
      seriesPrefix: _seriesPrefix(title),
      duration: duration,
    );
  }

  /// 拿 91porna 的播放地址：请求 `/index/detail_play`（黑料帖是 `/index/melon_detail_play.js`），
  /// 响应是打包过的 JS，从中解出 m3u8。
  Future<String> _pornaPlayUrl(String html, String cover) async {
    // img 参数 = 封面路径（去掉域名和查询串）
    var img = '';
    if (cover.isNotEmpty) {
      final u = Uri.tryParse(cover);
      img = u?.path ?? '';
    }
    if (img.isEmpty) {
      // 视频详情是 upload_01/…，日本AV 是 md-204/dcc-file/…
      final m = RegExp(r'(?:upload_01|md-\d+)/[^"\s]+\.(?:jpe?g|png|webp)')
          .firstMatch(html);
      img = m == null ? '' : '/${m.group(0)}';
    }
    if (img.isEmpty) return '';
    // u 参数 = 页面里内嵌的 hex token。长度不固定（视频页 160 位、日本AV 页 352 位），
    // 而且不一定紧跟在 parseInt| 后面，所以按"候选列表逐个试"：
    // 拿到第一个能换出 m3u8 的就用。
    final tokens = <String>{
      for (final m in RegExp(r'parseInt\|([0-9a-f]{60,400})\|').allMatches(html))
        m.group(1)!,
      for (final m in RegExp(r'\|([0-9a-f]{120,400})\|').allMatches(html))
        m.group(1)!,
      for (final m in RegExp(r'\b([0-9a-f]{120,400})\b').allMatches(html))
        m.group(1)!,
    }.take(6);
    for (final token in tokens) {
      final t = DateTime.now().millisecondsSinceEpoch ~/ 1000 ~/ 2100;
      final path =
          '/index/detail_play?img=${Uri.encodeComponent(img)}&ads=&u=$token&h=&t=$t';
      final src = await _playUrlFromScript(path);
      if (src.isNotEmpty) return src;
    }
    return '';
  }

  /// 请求换源脚本并抠出 m3u8。
  /// 响应有两种形态：明文（k 数组里就是完整地址）和打包（地址被拆成字典碎片）——
  /// 后者要先 `_unpackJs` 解包（黑料帖的 melon_detail_play 就是这种）。
  Future<String> _playUrlFromScript(String path) async {
    String js;
    try {
      js = await _fetchText(path);
    } catch (_) {
      return '';
    }
    final m = RegExp(r'https?://[^"\s\\]+\.m3u8[^"\s\\]*').firstMatch(js);
    if (m != null) return m.group(0)!;
    final plain = _unpackJs(js);
    if (plain == null) return '';
    final m2 = RegExp(r'https?://[^"\s\\]+\.m3u8[^"\s\\]*').firstMatch(plain);
    return m2?.group(0) ?? '';
  }

  /// 黑料帖正文里的视频（`melon_detail_play` 换源，参数只有 token）
  Future<String> _pornaPlayUrlByToken(String token, String script) {
    final t = DateTime.now().millisecondsSinceEpoch ~/ 1000 ~/ 2100;
    return _playUrlFromScript('/index/$script?img=&u=$token&t=$t');
  }

  /// 解开站点前端用的 JS 打包格式（Dean Edwards packer）：
  /// `eval(function(p,a,c,k,e,d){…}('p文本',a,c,'k1|k2|…'.split('|'),0,{}))`
  /// 站点用它把播放地址拆碎藏起来（melon/detail_play 的响应就是这种）。
  /// 解不出来返回 null。
  static String? _unpackJs(String src) {
    final head = RegExp(
            r"eval\(function\(p,a,c,k,e,[rd]\)\{[\s\S]*?\}\('([\s\S]*?)',(\d+),(\d+),'([\s\S]*?)'\.split\('\|'\)")
        .firstMatch(src);
    if (head == null) return null;
    final a = int.tryParse(head.group(2)!);
    final c = int.tryParse(head.group(3)!);
    if (a == null || c == null) return null;
    // p 是 JS 字符串字面量：把转义还原
    var p = head.group(1)!;
    final buf = StringBuffer();
    for (var i = 0; i < p.length; i++) {
      final ch = p[i];
      if (ch == '\\' && i + 1 < p.length) {
        final n = p[i + 1];
        // JS 字符串字面量里的常见转义（打包后的 p 文本靠它还原）
        const map = {
          'n': '\n',
          't': '\t',
          'r': '\r',
          "'": "'",
          '\\': '\\',
          '"': '"',
        };
        if (map.containsKey(n)) {
          buf.write(map[n]);
          i++;
          continue;
        }
      }
      buf.write(ch);
    }
    p = buf.toString();
    final dict = head.group(4)!.split('|');

    // 生成 token：base-a 编码（数字>35 用大写字母，10..35 用小写字母）
    String enc(int n) {
      final first = n < a ? '' : enc(n ~/ a);
      final d = n % a;
      final second = d > 35
          ? String.fromCharCode(d + 29)
          : (d < 10 ? '$d' : String.fromCharCode('a'.codeUnitAt(0) + d - 10));
      return '$first$second';
    }

    // 从高位到低位依次替换（跟 packer 自己的顺序一致）
    for (var i = c - 1; i >= 0; i--) {
      if (i >= dict.length || dict[i].isEmpty) continue;
      final tok = enc(i);
      p = p.replaceAll(RegExp('\\b$tok\\b'), dict[i]);
    }
    return p;
  }

  /// PT1H39S → 1:00:39；PT3M27S → 3:27
  static String _pornaDuration(String iso) {
    final m = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?').firstMatch(iso);
    if (m == null) return '';
    final h = int.tryParse(m.group(1) ?? '') ?? 0;
    final mi = int.tryParse(m.group(2) ?? '') ?? 0;
    final s = int.tryParse(m.group(3) ?? '') ?? 0;
    if (h == 0 && mi == 0 && s == 0) return '';
    final mm = mi.toString().padLeft(h > 0 ? 2 : 1, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  // ---------------------------------------------------------------------------
  // 公共小工具

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

  /// 标题中含"第 N 集"则提取系列前缀，否则空串。
  static String _seriesPrefix(String title) {
    final m = RegExp(r'第\s*\d+\s*集').firstMatch(title);
    if (m == null) return '';
    return title.substring(0, m.start).trim();
  }
}
