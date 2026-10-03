// 91porna + 蜜桃/黑料 + ms + 小说 —— **这几站的专属实现** ✓
//
// ⚠️ 用户 2026-10-03 决策：取消全站共享，站点相关的一切改成站点独立专属 ✓；底座保持公用 ✓。
// 从 `api.dart` 的 `Api` 里**原样搬**过来（**不重写逻辑** ✓ 行为不变 ✓）。
// ⚠️ **为什么 5 个站放一个文件**：它们**共用同一套子系统** ✗ ——
//   `list()` 一个分发器按路径分流到 4 种卡片解析（`heiliaoCards`/`msCards`/`novelCards`/`melonCards`/`cards`）；
//   换源机器 `playUrlFromScript`/`unpackJs`/`pornaDuration` 也是共享的 ✓。
//   硬拆成 5 个文件必然跨文件调不到 ✗ → **先整体搬** ✓，后续要细分得先把共用件抽出来（待办 ✓）。
// 入口已公开：`list` / `detail`（91porna ✓）· `melonCards`/`melonDetail` · `heiliaoCards`/`heiliaoDetail` · `novelCards`/`novelDetail` ✓
// （`msCards` 只在本文件内用 → 保持私有 ✓）

import 'dart:convert';

import 'package:flutter/material.dart';
import '../sites.dart';
import '../base/site_ui.dart';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as hp;

import '../base/fetch.dart';
import '../base/fmt.dart';
import '../models.dart';

/// 上述几站的专属实现（取数走公用底座 [SiteFetcher] ✓）
class PornaSite extends SiteUi {
  PornaSite(this._f);

  final SiteFetcher _f;

  /// 详情入口：**按路径分流**到四种详情解析器（原 `Api.detail` 的 case body 原样搬来 ✓）
  /// 四种详情页：短视频 / 黑料图文 / 小说 / 普通视频 ✓
  Future<ArticleDetail> detailOf(String url) {
    if (url.startsWith('/melonshort/video/')) return melonDetail(url);
    if (url.startsWith('/heiliao-chigua/')) return heiliaoDetail(url);
    if (url.startsWith('/novels/')) return novelDetail(url);
    return detail(url);
  }

  /// 搜索（原 `Api.search` 的 case body 原样搬来 ✓）
  Future<List<Article>> search(String keyword,
      {int page = 1, List<MapEntry<String, String>>? extra}) =>
      list('search:$keyword', page: page);

  /// 标签列表页（原 `Api.tag` 的 case body 原样搬来 ✓）
  /// 这站的"标签"分两种：以 / 开头的是站内分类页（黑料吃瓜的标签）✓，
  /// 其余是搜索关键词（视频页的 keywords ✓）
  Future<List<Article>> tag(String slug, {required int page}) =>
      list(slug.startsWith('/') ? slug : 'search:$slug', page: page);

  /// 首页 = 第一个分类（原 `Api.home` 的 case body 原样搬来 ✓）
  Future<List<Article>> home({required int page, String first = ''}) => list(first, page: page);

  /// 「分类」tab 的列表（本站专属 ✓ —— 原 `Api.category` 里的 case body 原样搬来 ✓）
  /// key 可能是站内路径（/section 之类）也可能是分类 slug，站点内部自己分流 ✓
  Future<List<Article>> category(String key,
          {required int page,
          String? k,
          String? theme,
          String? duration,
          String? sort,
          List<MapEntry<String, String>>? extra,
          Future<List<Article>> Function({int page})? home}) =>
      list(key, page: page);
  // 91porna

  /// 列表：按路径分三种页面类型（都是服务端渲染，取到就能用）：
  /// - `/melonshort*`            → 91短视频：`article.video-card`（封面右下角有时长角标）
  /// - `/heiliao-chigua*`、`/黑料吃瓜/*` → 黑料吃瓜：`a[href^=/heiliao-chigua/]` 图文卡
  /// - 其余（/comic/index/*、/comic/av/*、搜索） → `div.video-item`
  /// [key]：站内路径或 "search:关键词"。
  Future<List<Article>> list(String key, {int page = 1}) async {
    // 关键词里的空格站点用 + 分隔（encodeQueryComponent 正好把空格编成 +）
    final path = key.startsWith('search:')
        ? '/comic/index/search?keyword=${Uri.encodeQueryComponent(key.substring(7))}'
        : key;
    final url = page <= 1
        ? path
        : '$path${path.contains('?') ? '&' : '?'}page=$page';
    final html = await _f.text(url);
    final doc = hp.parse(html);
    if (path.startsWith('/melonshort')) return melonCards(doc);
    // ⚠️ 只看路径部分：搜索关键词里也可能出现"黑料"（%E9%BB%91%E6%96%99），
    // 用整个 path 判断会把搜索结果页错认成黑料页（而且要用完整的"黑料吃瓜"编码）
    final p0 = path.split('?').first;
    // 精选合集：/moviesets、/moviesets/{rank|category|people|brand} 是"合集卡"页面；
    // 再深一层（/moviesets/xxx/yyy）才是该合集的视频列表（走下面的 video-item）
    if (p0.startsWith('/moviesets')) {
      final segs = p0.split('/').where((x) => x.isNotEmpty).toList();
      if (segs.length <= 2) return _msCards(doc);
    }
    // 色情小说列表（/novels、/novels/{分类}/new）
    if (p0 == '/novels' || p0.startsWith('/novels/')) return novelCards(doc);
    if (p0.contains('heiliao') || p0.contains('%E9%BB%91%E6%96%99%E5%90%83%E7%93%9C')) {
      return heiliaoCards(doc);
    }
    return _pornaCards(doc);
  }

  /// 精选合集的"合集卡"（a.ms-card → /moviesets/{type}/{slug}）
  List<Article> _msCards(Document doc) {
    final out = <Article>[];
    for (final a in doc.querySelectorAll('a.ms-card')) {
      final href = a.attributes['href'] ?? '';
      final title = (a.querySelector('.ms-card__title')?.text ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (href.isEmpty || title.isEmpty) continue;
      final img = a.querySelector('img[data-src]') ?? a.querySelector('img');
      final meta = (a.querySelector('.ms-card__meta')?.text ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      out.add(Article(
        title: title,
        url: href,
        cover: img?.attributes['data-src'] ?? '',
        meta: meta, // 形如"视频数量：53"
      ));
    }
    final seen = <String>{};
    return [
      for (final a in out)
        if (seen.add(a.url)) a
    ];
  }

  /// 色情小说的文字卡（没有封面，标题在 .dx-title，时间/作者在卡片文字里）
  List<Article> novelCards(Document doc) {
    final out = <Article>[];
    for (final a in doc.querySelectorAll('a[href^="/novels/"]')) {
      final href = a.attributes['href'] ?? '';
      if (!RegExp(r'^/novels/\d+$').hasMatch(href)) continue; // 跳过分类链接
      final title = (a.querySelector('h2.dx-title')?.text ?? a.querySelector('.dx-title')?.text ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (title.isEmpty) continue;
      out.add(Article(
        title: title,
        url: href,
        cover: '',
        meta: metaDate(a.text),
      ));
    }
    final seen = <String>{};
    return [
      for (final a in out)
        if (seen.add(a.url)) a
    ];
  }

  /// 91短视频的卡片
  List<Article> melonCards(Document doc) {
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
        badge: RegExp(r'\d{1,2}:\d{2}(?::\d{2})?').firstMatch(dur)?.group(0) ?? '',
      ));
    }
    final seen = <String>{};
    return [
      for (final a in out)
        if (seen.add(a.url)) a
    ];
  }

  /// 黑料吃瓜的图文卡（标题/封面/时间都在卡片里）
  List<Article> heiliaoCards(Document doc) {
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
        meta: metaDate(desc),
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
        badge: duration,
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
  Future<ArticleDetail> melonDetail(String url) async {
    final html = await _f.text(url);
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
        badge: secClock('${v['video_duration'] ?? ''}'),
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
      seriesPrefix: seriesPrefix(title),
      duration: secClock('${cur?['video_duration'] ?? ''}'),
    );
  }

  /// 色情小说详情：标题（og:title 去掉站点后缀）+ 正文（article.markdown-body 全文）+ 插图
  Future<ArticleDetail> novelDetail(String url) async {
    final html = await _f.text(url);
    final doc = hp.parse(html);
    var title =
        (doc.querySelector('meta[property="og:title"]')?.attributes['content'] ?? '')
            .trim();
    title = title.replaceAll(RegExp(r'\s*-\s*91博客色情小说\s*$'), '');
    if (title.isEmpty) title = url;
    final body = (doc.querySelector('article.markdown-body')?.text ?? '').trim();
    final desc =
        (doc.querySelector('meta[name="description"]')?.attributes['content'] ?? '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    final images = <String>[];
    for (final img in doc.querySelectorAll('article.markdown-body img[data-src]')) {
      final src = img.attributes['data-src'] ?? '';
      if (src.startsWith('http') && !images.contains(src)) images.add(src);
    }
    return ArticleDetail(
      title: title,
      time: metaDate(doc.querySelector('.markdown-body')?.text ?? ''),
      categories: const [],
      images: images,
      // 有正文就用正文（小说就是来看字的），没有退回摘要
      intro: body.isNotEmpty ? body : desc,
      videos: const [], // 小说没有视频
      tags: const [],
      related: const [],
      seriesPrefix: seriesPrefix(title),
    );
  }

  /// 黑料吃瓜详情：图文帖 + **正文里的视频**。
  /// 视频不是 `<video>`/dplayer，而是正文里一块 `ql-video-mse`，地址由
  /// `/index/melon_detail_play.js?img=&u=<页面内嵌 token>&t=<时间戳/2100>` 换回来，
  /// 且响应是**打包过的 JS**（把 m3u8 拆成字典碎片），所以要解包后再抠地址。
  /// 标签是元信息行里指向 `/黑料吃瓜/xxx` 的分类链接。
  Future<ArticleDetail> heiliaoDetail(String url) async {
    final html = await _f.text(url);
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
      time = metaDate(doc.querySelector('.dx-text')?.text ?? '');
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
      related: heiliaoCards(doc).where((a) => a.url != url).take(12).toList(),
      seriesPrefix: seriesPrefix(title),
    );
  }

  /// 详情：
  /// - 标题/简介/时长/时间/标签 来自页面内嵌的 LD+JSON（VideoObject）
  /// - 播放地址要再请求 `/index/detail_play`：参数 img=封面路径、u=页面里内嵌的
  ///   160 位 hex token、t=时间戳/2100（照抄前端 JS 的算法），响应里就是 m3u8。
  Future<ArticleDetail> detail(String url) async {
    final html = await _f.text(url);
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
      seriesPrefix: seriesPrefix(title),
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
      js = await _f.text(path);
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
}

// ===== 本站档案（2026-10-03 从 lib/sites.dart 的 kSites 下放 ✓）=====

/// 本站档案：91porna
const SiteEntry kSite07 = SiteEntry(
    name: '91porna',
    template: SiteTemplate.porna,
    iconUrl: '/favicon.ico',
    hosts: ['91porna.com'],
    // 顺序 = 站点导航原顺序（首页、91视频、91短视频、黑料吃瓜、AI成人、日本AV、
    // 91动漫、精选合集、色情小说、91品牌），已接入的排前面、按站点相对顺序；
    // 尚未接入的：精选合集（列表 JS 渲染）、色情小说（纯文字）、91品牌（外链导航）
    categories: [
      SiteTab('/comic/index/video?category=play', '91视频', [
        // 一级子分类 = 站点下拉菜单里的入口（顺序照站点原样：热门排行榜、国产原创、吃瓜爆料…三级片）
        // 「热门排行榜」自己还带二级子分类 —— 那 12 个排序（正在播放…收藏最多）
        SiteTab('/comic/index/video?category=now_month_hot', '热门排行榜', [
          SiteTab('/comic/index/video?category=play', '正在播放'),
          SiteTab('/comic/index/video?category=now_hot', '当前最热'),
          SiteTab('/comic/index/video?category=new_update', '最近更新'),
          SiteTab('/comic/index/video?category=original', '91原创'),
          SiteTab('/comic/index/video?category=now_month_hot', '本月最热'),
          SiteTab('/comic/index/video?category=ten_minutes', '10分钟以上'),
          SiteTab('/comic/index/video?category=twenty_minutes', '20分钟以上'),
          SiteTab('/comic/index/video?category=now_month_collect', '本月收藏'),
          SiteTab('/comic/index/video?category=hd', '高清'),
          SiteTab('/comic/index/video?category=month_hot', '每月最热'),
          SiteTab('/comic/index/video?category=now_month_comment', '本月讨论'),
          SiteTab('/comic/index/video?category=max_collect', '收藏最多'),
        ]),
        SiteTab('/comic/index/video?category=original', '国产原创'),
        SiteTab('search:吃瓜 黑料 爆料', '吃瓜爆料'),
        SiteTab('search:熟女', '熟女做爱'),
        SiteTab('search:萝莉', '可爱萝莉'),
        SiteTab('search:动漫', '成人动漫'),
        SiteTab('search:黑人', '大屌黑人'),
        SiteTab('search:巨乳', '童颜巨乳'),
        SiteTab('search:换妻', '少妇换妻'),
        SiteTab('search:内射', '内射中出'),
        SiteTab('search:按摩', '会所按摩'),
        SiteTab('search:探花', '91探花'),
        SiteTab('search:家庭乱伦', '家庭乱伦'),
        SiteTab('search:三级片', '三级片'),
      ]),
      SiteTab('/melonshort', '91短视频', [
        SiteTab('/melonshort', '全部'),
        SiteTab('/melonshort/amateur', '素人自拍'),
        SiteTab('/melonshort/hunjian', '高燃混剪'),
        SiteTab('/melonshort/fancha', '反差系列'),
        SiteTab('/melonshort/wanghong', '网红达人'),
        SiteTab('/melonshort/mingxing', '明星大瓜'),
        SiteTab('/melonshort/zipai', '原创自拍'),
      ]),
      SiteTab('/%E9%BB%91%E6%96%99%E5%90%83%E7%93%9C/%E6%8E%A8%E8%8D%90', '黑料吃瓜', [
        SiteTab('/%E9%BB%91%E6%96%99%E5%90%83%E7%93%9C/%E6%8E%A8%E8%8D%90', '全部'),
        SiteTab('/%E9%BB%91%E6%96%99%E5%90%83%E7%93%9C/%E4%BB%8A%E6%97%A5%E5%90%83%E7%93%9C/%E6%9C%80%E6%96%B0', '今日吃瓜'),
        SiteTab('/%E9%BB%91%E6%96%99%E5%90%83%E7%93%9C/%E5%AD%A6%E7%94%9F%E6%A0%A1%E5%9B%AD/%E6%8E%A8%E8%8D%90', '学生校园'),
        SiteTab('/%E9%BB%91%E6%96%99%E5%90%83%E7%93%9C/%E6%98%8E%E6%98%9F%E9%BB%91%E6%96%99/%E6%8E%A8%E8%8D%90', '明星黑料'),
        SiteTab('/%E9%BB%91%E6%96%99%E5%90%83%E7%93%9C/%E7%BD%91%E7%BA%A2%E9%BB%91%E6%96%99/%E6%8E%A8%E8%8D%90', '网红黑料'),
        SiteTab('/%E9%BB%91%E6%96%99%E5%90%83%E7%93%9C/%E6%AF%8F%E6%97%A5%E5%A4%A7%E8%B5%9B/%E6%8E%A8%E8%8D%90', '每日大赛'),
        SiteTab('/%E9%BB%91%E6%96%99%E5%90%83%E7%93%9C/%E5%90%8D%E4%BA%BA%E5%90%88%E9%9B%86/%E6%8E%A8%E8%8D%90', '名人合集'),
      ]),
      SiteTab('search:ai成人', 'AI成人', [
        SiteTab('search:ai成人', '全部'),
        SiteTab('search:ai短剧', 'AI成人短剧'),
        SiteTab('search:ai漫剧', 'AI漫剧'),
        SiteTab('search:ai美女', 'AI美女'),
        SiteTab('search:+ai换脸', 'AI换脸'),
      ]),
      SiteTab('/comic/index/av', '日本AV', [
        SiteTab('/comic/index/av', '最新更新'),
        SiteTab('/comic/av/relvideo?model=1&type=theme&order=week', '多P群交'),
        SiteTab('/comic/av/relvideo?model=12&type=theme&order=week', '无码解放'),
        SiteTab('/comic/av/relvideo?model=5&type=theme&order=week', '中文字幕'),
        SiteTab('/comic/av/relvideo?model=6&type=theme&order=week', '制服诱惑'),
        SiteTab('/comic/av/relvideo?model=107&type=tag&order=week', '黑人专区'),
        SiteTab('/comic/av/relvideo?model=7&type=theme&order=week', 'SM调教'),
      ]),
      SiteTab('search:h动漫', '91动漫', [
        SiteTab('search:h动漫', '全部'),
        SiteTab('search:成人动漫', '成人动漫'),
        SiteTab('search:日本动漫', '日本动漫'),
        SiteTab('search:国产动漫', '国产动漫'),
        SiteTab('search:3d动漫', '3d动漫'),
        SiteTab('search:同人动漫', '同人动漫'),
      ]),
      // 精选合集：列表页是"合集卡"（点开进该合集的视频列表）
      SiteTab('/moviesets', '精选合集', [
        SiteTab('/moviesets', '最新合集'),
        SiteTab('/moviesets/rank', '排行榜合集'),
        SiteTab('/moviesets/category', '分类合集'),
        SiteTab('/moviesets/people', '人物合集'),
        SiteTab('/moviesets/brand', '品牌合集'),
      ]),
      // 色情小说：列表是文字卡（无封面），详情是小说正文（article.markdown-body）
      SiteTab('/novels', '色情小说', [
        SiteTab('/novels', '全部'),
        SiteTab('/novels/dushi-jiqing/new', '都市激情'),
        SiteTab('/novels/xiaoyuan-zhilian/new', '校园之恋'),
        SiteTab('/novels/renqi-shunv/new', '人妻熟女'),
        SiteTab('/novels/jiating-luanlun/new', '家庭乱伦'),
      ]),
    ],
    color: Color(0xFF3B5998),
  );
