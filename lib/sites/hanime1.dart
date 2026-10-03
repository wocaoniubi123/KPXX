// Hanime1.me（H動漫/裏番）—— **本站专属**的一切 ✓
//
// ⚠️ 用户 2026-10-03 决策：取消全站共享，站点相关的一切改成站点独立专属 ✓；底座保持公用 ✓。
// 从 `api.dart` 的 `Api` 里**原样搬**过来（**不重写逻辑** ✓ 行为不变 ✓）。
// ⚠️ 入口方法**直接改名为公开**（`list`/`search`/`searchAt`/`detail` ✓）而不是包一层 ✓
// —— 因为各调用点的参数表不同（有的带 `extra` 有的不带 ✗），包一层极易写错签名 ✗。
// `hanimeTags()` 本来就是公开的 ✓（`home_page` 会用 ✓，`Api` 里留了转发 ✓）。

import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as hp;

import '../base/fetch.dart';
import '../base/site_ui.dart';
import '../models.dart';

/// Hanime1 本站专属实现（取数走公用底座 [SiteFetcher] ✓）
class HanimeSite extends SiteUi {
  HanimeSite(this._f);

  final SiteFetcher _f;

  /// 标签列表页（原 `Api.tag` 的 case body 原样搬来 ✓）
  /// 详情页标签：站内 /search? 路径直接请求（?query= / ?tags[]= 两种链接 ✓）；其余当搜索词 ✓
  Future<List<Article>> tag(String slug, {required int page}) async {
    if (slug.startsWith('/search')) return searchAt(slug, page: page);
    return search(slug, page: page);
  }

  /// 首页 = 第一个分类（原 `Api.home` 的 case body 原样搬来 ✓）
  Future<List<Article>> home(String first, {required int page}) => list(first, page: page);

  /// 「分类」tab 的列表（本站专属 ✓ —— 原 `Api.category` 里的 case body 原样搬来 ✓）
  /// 分类 tab = 站点的 genre（裏番/泡麵番/…）；列表走 /search?genre= ✓；
  /// extra = 筛选行（sort/date/duration/tags[]）✓
  Future<List<Article>> category(String key,
      {required int page, List<MapEntry<String, String>>? extra}) =>
      list(key, page: page, extra: extra);

  /// 列表页挂本站筛选行（照站点的下拉 ✓）
  @override
  bool get hasFilterRow => true;
  // Hanime1.me（H動漫）：分类列表=网格卡（/search?genre=）、搜索=横排卡（/search?query=）、
  // 详情页 watch?v= 内嵌多档直链 mp4（vdownload.hembed.com，secure 签名约 12 小时有效；
  // 过期时播放器失败 → 详情页的刷新机制会重新调 detail 拿新签名）。
  // 相关推荐走 AJAX POST（/video/load-playlist-chunk + _token），v1 未接（showRelated=false）。

  /// 绝对链接 → 站内路径（hanime1 的链接都是绝对地址，/watch?v=N 还带查询串）
  static String _hnRel(String href) {
    if (!href.startsWith('http')) return href;
    final u = Uri.tryParse(href);
    if (u == null) return href;
    return '${u.path}${u.hasQuery ? '?${u.query}' : ''}';
  }

  /// 拼查询串：页码 + Hanime1 筛选参数（空值跳过；tags[] 可重复出现）
  static String _hnQuery(
      String base, int page, List<MapEntry<String, String>>? extra) {
    final parts = <String>[
      if (page > 1) 'page=$page',
      for (final e in extra ?? const <MapEntry<String, String>>[])
        if (e.value.isNotEmpty)
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
    ];
    if (parts.isEmpty) return base;
    return '$base${base.contains('?') ? '&' : '?'}${parts.join('&')}';
  }

  /// 网格卡（`div.video-card-inner`）：裏番 / 泡麵番 / 新番預告 这几个分类页用这套模板
  static List<Article> _hnGridCards(Document doc) {
    final out = <Article>[];
    for (final a in doc.querySelectorAll('a[href*="/watch?v="]')) {
      final inner = a.querySelector('div.video-card-inner');
      if (inner == null) continue; // 广告卡
      final img = inner.querySelector('img');
      final t = inner.querySelector('div.home-rows-videos-title')?.text ?? '';
      final src = img?.attributes['src'] ?? '';
      // 只认真卡片：有标题 + 封面是站内 cover 图（广告卡是 image/icon/）
      if (t.trim().isEmpty || !src.contains('/image/cover/')) continue;
      out.add(Article(
        title: t.trim(),
        url: _hnRel(a.attributes['href'] ?? ''),
        cover: src,
        meta: '',
      ));
    }
    return out;
  }

  /// 横排卡（`div.video-item-container`）：搜索页、站内标签页，
  /// **以及另外 7 个分类页**（Motion Anime / 3DCG / 2.5D / 2D動畫 / AI生成 / MMD / Cosplay）
  ///
  /// ⚠️ `meta` **一律留空**（用户 2026-10-01 拍板）：站点的 `div.subtitle` 是
  /// 「上传者 • 上传时间」，而卡片那行只该放单一信息（§8.2.1-2）—— 用户决定**两个都不显示**，
  /// **分类页和搜索页都取消**。时长角标（`div.duration`）照 §8-4 保留。
  static List<Article> _hnRowCards(Document doc) {
    final out = <Article>[];
    for (final el in doc.querySelectorAll('div.video-item-container')) {
      final a = el.querySelector('a.video-link');
      final href = a?.attributes['href'] ?? '';
      if (!href.contains('/watch?v=')) continue; // 广告卡（外链）
      final t = (el.querySelector('div.title')?.text ??
              el.attributes['title'] ??
              '')
          .trim();
      if (t.isEmpty) continue;
      out.add(Article(
        title: t,
        url: _hnRel(href),
        cover: el.querySelector('img.main-thumb')?.attributes['src'] ?? '',
        meta: '',
        badge: el.querySelector('div.duration')?.text.trim() ?? '',
      ));
    }
    return out;
  }

  /// 分类列表：/search?genre={genre}&page=N&筛选（**两套模板都认**）
  ///
  /// ⚠️ 站点对分类页用了两套卡片模板（2026-10-01 用户实报"泡麵番后面的分类都没数据"）：
  /// 裏番 / 泡麵番 / 新番預告 = 网格卡；Motion Anime / 3DCG / 2.5D / 2D動畫 / AI生成 /
  /// MMD / Cosplay = 横排卡。实测这 10 个分类页的布局是**互斥**的（同一页不会混），
  /// 所以网格卡非空就直接返回。
  Future<List<Article>> list(String genre,
      {int page = 1, List<MapEntry<String, String>>? extra}) async {
    final path =
        _hnQuery('/search?genre=${Uri.encodeComponent(genre)}', page, extra);
    final doc = hp.parse(await _f.text(path));
    final grid = _hnGridCards(doc);
    return grid.isNotEmpty ? grid : _hnRowCards(doc);
  }

  /// 搜索 / 站内标签（?query= 与 ?tags[]= 两种路径）共用的横排卡解析
  Future<List<Article>> searchAt(String basePath,
      {int page = 1, List<MapEntry<String, String>>? extra}) async {
    final path = _hnQuery(basePath, page, extra);
    return _hnRowCards(hp.parse(await _f.text(path)));
  }

  /// 搜索：关键词走 /search?query=
  Future<List<Article>> search(String keyword,
          {int page = 1, List<MapEntry<String, String>>? extra}) =>
      searchAt('/search?query=${Uri.encodeComponent(keyword)}',
          page: page, extra: extra);

  /// Hanime1 的「內容標籤」（240 个，tags[] 多选用）——打开标签弹窗时从 /search
  /// 动态抓一次、内存缓存（不常变，没必要硬编码 240 条）
  static List<String>? _hnTagCache;
  Future<List<String>> hanimeTags() async {
    final cached = _hnTagCache;
    if (cached != null) return cached;
    final doc = hp.parse(await _f.text('/search'));
    final out = <String>[];
    for (final el in doc.querySelectorAll('input[name="tags[]"]')) {
      final v = el.attributes['value'] ?? '';
      if (v.isNotEmpty && !out.contains(v)) out.add(v);
    }
    _hnTagCache = out;
    return out;
  }

  /// 详情：watch?v=N → 标题 / 观看数+日期 / 标签 / 多档直链 mp4（清晰度从高到低）
  Future<ArticleDetail> detail(String url) async {
    final html = await _f.text(url);
    final doc = hp.parse(html);
    final title = doc.querySelector('h3#shareBtn-title')?.text.trim() ?? url;
    // 信息行：觀看次數：1.8萬次  2026-09-02
    // ⚠️ 页面有简/繁两种变体（不同抓取环境可能拿到不同版本）：两种都认
    var intro = '';
    for (final d in doc.querySelectorAll('div.video-details-wrapper')) {
      final t = d.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.contains('觀看次數') || t.contains('观看次数')) {
        intro = t;
        break;
      }
    }
    final poster =
        doc.querySelector('meta[property="og:image"]')?.attributes['content'] ??
            '';
    // 时长：<meta property="og:video:duration" content="1188">（秒）→ 19:48，显示在详情页
    // 标题下那行（§8.2-4）。⚠️ 站点页面 UI 上并不显示时长，只有这个 meta ——
    // 有就填、没有留空（§8 三原则①），走公共的 _secClock（和黄果/91短视频同一条路径）
    final duration = secClock(doc
            .querySelector('meta[property="og:video:duration"]')
            ?.attributes['content'] ??
        '');
    // 播放源：<source src="…-480p/720p/1080p.mp4?secure=…" size="…">，按清晰度降序
    final pairs = <MapEntry<int, String>>[];
    for (final s in doc.querySelectorAll('video source')) {
      final u = s.attributes['src'] ?? '';
      if (u.isEmpty) continue;
      pairs.add(MapEntry(int.tryParse(s.attributes['size'] ?? '') ?? 0, u));
    }
    pairs.sort((a, b) => b.key.compareTo(a.key));
    final videos = <ArticleVideo>[];
    if (pairs.isNotEmpty) {
      videos.add(ArticleVideo(
        label: '视频',
        ordinal: 1,
        sources: pairs.map((e) => e.value).toList(),
      ));
    }
    // 标签：正文下方 #xx / tags[] 两类链接（去掉计数后缀与 # 号；+/- 登录按钮除外）
    final tags = <MapEntry<String, String>>[];
    for (final a
        in doc.querySelectorAll('.video-tags-wrapper .single-video-tag a')) {
      final href = a.attributes['href'] ?? '';
      if (!href.contains('/search?')) continue;
      final t = a.text
          .replaceAll(RegExp(r'[\s\u00A0]+'), ' ')
          .replaceAll(RegExp(r'\s*\(\d+\)\s*$'), '')
          .replaceAll('#', '')
          .trim();
      if (t.isEmpty) continue;
      tags.add(MapEntry(_hnRel(href), t));
    }
    return ArticleDetail(
      title: title.isEmpty ? url : title,
      time: '',
      categories: const [],
      images: poster.isEmpty ? const [] : [poster],
      intro: intro,
      videos: videos,
      tags: tags,
      related: const [], // 相关推荐是 AJAX POST，v1 未接
      seriesPrefix: '',
      duration: duration,
    );
  }
}
