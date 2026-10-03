// wordpress —— **本站专属**的一切 ✓
//
// ⚠️ 用户 2026-10-03 决策：取消全站共享，站点相关的一切改成站点独立专属 ✓；底座保持公用 ✓。
// 由 `tools/mover3.js` 从 `api.dart` 的 `Api` 里**原样搬**出（**不重写逻辑** ✓ 行为不变 ✓），
// 仅做等价替换：`_fetchText(`→`_f.text(`、`_secClock(`→`secClock(` 等 ✓；入口方法改名为公开 ✓。
// ⚠️ import 由脚本按**代码里实际用到的符号**推导 ✓（不是手写的 ✓）。

import 'package:html/dom.dart';
import '../base/site_ui.dart';
import 'package:html/parser.dart' as hp;
import '../base/fetch.dart';
import '../base/fmt.dart';
import '../models.dart';

/// wordpress 本站专属实现（取数走公用底座 [SiteFetcher] ✓）
class WpSite extends SiteUi {
  WpSite(this._f);

  final SiteFetcher _f;

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

  /// 站内相对路径（把 `https://host/xxx` 剥成 `/xxx`；本来就是相对路径的原样返回）✓
  /// ⚠️ 2026-10-03 从 `api.dart` 上移：**麻豆社与 wordpress 系都要用** ✗，
  /// 而各站已拆成独立文件 → 跨文件调不到 ✗，所以上移并公开 ✓。
  /// 把绝对地址归一化成站内相对路径（详情页只认 /archives/xxx/ 这种）
  String _toRelPath(String href) {
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

  /// 搜索（原 `Api.search` 的 case body 原样搬来 ✓）
  Future<List<Article>> search(String keyword,
      {int page = 1, List<MapEntry<String, String>>? extra}) async {
    final kw = Uri.encodeComponent(keyword);
    final path = page <= 1 ? '/search/$kw/' : '/search/$kw/$page/';
    return parseArticles(await _f.text(path));
  }

  /// 标签列表页（原 `Api.tag` 的 case body 原样搬来 ✓）
  Future<List<Article>> tag(String slug, {required int page}) async {
    final path = page <= 1 ? '/tag/$slug/' : '/tag/$slug/page/$page/';
    return parseArticles(await _f.text(path));
  }

  /// 首页最新列表（原 `Api.home` 的 case body 原样搬来 ✓）
  Future<List<Article>> home({required int page, String first = ''}) async {
    final path = page <= 1 ? '/' : '/page/$page/';
    return parseArticles(await _f.text(path));
  }

  /// 「分类」tab 的列表（原 `Api.category` 的 case body 原样搬来 ✓）
  /// k 以 `/` 开头 = 站内路径型（如 51fans1 的 `/order/hot/` ✓）；否则是分类 slug ✓
  Future<List<Article>> category(String key,
          {required int page,
          String? k,
          String? theme,
          String? duration,
          String? sort,
          List<MapEntry<String, String>>? extra,
          Future<List<Article>> Function({int page})? home}) async {
    // 并集里 kk 是可空具名参数 ✗ → 绑定回原语义 ✓（原位置参数 = 子分类 key）
    final kk = k ?? key;
    final path = kk.startsWith('/')
        // 51fans1 的 /order/hot/ 这类：页 2 = /order/hot/2/
        ? (page <= 1 ? kk : '$k$page/')
        : (page <= 1 ? '/category/$k/' : '/category/$k/$page/');
    return parseArticles(await _f.text(path));
  }
  /// 列表页 / 搜索页通用的文章卡片解析。
  /// 先按 WordPress 模板（article[itemscope]）找，找不到再按 51fans1（.xqbj-list-rows）。
  List<Article> parseArticles(String html) {
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
  Future<ArticleDetail> detail(String url) async {
    final html = await _f.text(url);
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
      final sources = _dplayerSources(dp);
      // 就近往上找最多两条短文本（空行跳过，长正文不算）
      final texts = <String>[];
      for (var e = dp.previousElementSibling;
          e != null && texts.length < 2;
          e = e.previousElementSibling) {
        final t = e.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (t.isEmpty || t.length > 60) continue;
        texts.add(t);
      }
      final parsed = texts.map(videoOrdinal).firstWhere((v) => v > 0, orElse: () => 0);
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
            label: cleanSubTitle(e.value),
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
    for (final el in _f.site.showRelated
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
}
