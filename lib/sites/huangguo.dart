// 黄果短剧（huangguoai.com）—— **本站专属**的一切 ✓
//
// ⚠️ 用户 2026-10-03 决策：取消全站共享，站点相关的一切改成站点独立专属 ✓；底座保持公用 ✓。
// 从 `api.dart` 的 `Api` 里**原样搬**过来（**不重写逻辑** ✓ 行为不变 ✓）。
// 入口公开 ✓：`list` / `pageList` / `detail` / `postDetail` / `initialData` ✓；
// 卡片解析（`_hgTopicCards`/`_hgPostCards`/`_hgRankCards`/`_hgArticle`）本站内部用 → 保持私有 ✓。
// ⚠️ `initialData` 必须公开 ✗：**共享的 `_fetchSourcesAt`** 里有一处黄果分支 ✗
//   （"站点逻辑散在公共函数里"的典型 ✓），本次改成调本类公开方法 ✓；彻底下放列为**待办** ✓。

import 'dart:convert';

// ⚠️ 本站只用 `Color`（SiteEntry.color ✓），**不要** import flutter/material ✗
// —— material 会同时导出 `Element`/`Text`/`Key`，与 html/dom、encrypt 撞名 ✗（2026-10-03 analyze 报的 7 条错误就是这个 ✓）
// `Color` 本来就定义在 dart:ui ✓ Flutter 只是转发 ✓
import 'dart:ui' show Color;
import '../sites.dart';
import '../base/site_ui.dart';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as hp;

import '../base/fetch.dart';
import '../base/fmt.dart';
import '../models.dart';
// ★ 诊断打印：`debugPrint` 在 foundation 里 ✓（**不能**引 material ✗ 见上）；开关在 settings ✓
import 'package:flutter/foundation.dart' show debugPrint;
import '../settings.dart';

/// 黄果短剧本站专属实现（取数走公用底座 [SiteFetcher] ✓）
class HuangguoSite extends SiteUi {
  HuangguoSite(this._f);

  final SiteFetcher _f;

  /// ★ 2026-10-08（用户要求 ✅）：相关推荐也改成**卡片网格**（= 野果那套 ✓ 一行三列 ✓）
  ///   走底座槽位 `SiteUi.relatedAsGrid`（默认 false ⇒ 其它站零变化 ✅）；
  ///   数据侧的条数本站本来就够（详情解析里 `take(12)` ✅ ⇒ 3 列 = 4 行 ✓）。
  ///   ⚠️ "点卡片跳转前先停本页播放器"**不靠这条** ✅ —— 由 `detail_page` 的 RouteAware 统一负责（任何 push 都覆盖 ✓）。
  @override
  bool get relatedAsGrid => true;

  /// 黄果的某一集：源在 videoInitialData.epPlaySrcs[本集号]（页面自报 ep ✓）。
  /// ⚠️ 原在共享 `_fetchSourcesAt` 里按模板分叉 ✗，现下放本站 ✓（body 原样搬来 ✓）。
  @override
  List<String>? sourcesFromHtml(String html) {
    final out = <String>[];
    final data = HuangguoSite.initialData(hp.parse(html));
    final ep = int.tryParse('${data?['ep'] ?? ''}') ?? 0;
    final eps = data?['epPlaySrcs'];
    if (eps is Map) {
      final v = '${eps['$ep'] ?? ''}';
      if (v.isNotEmpty) out.add(v);
    }
    // ★【常驻诊断】本站自有取源结果：集号 ep + 条数 —— 0 条就是页面没给 epPlaySrcs[ep] ✓
    // （⚠️ 本方法是纯函数、拿不到 `_f.site.name`，站名写字面量 ✓）
    if (AppSettings.i.logConsole) debugPrint('[SRC] 黄果短剧 ep=$ep 解析出 ${out.length} 条源');
    return out;
  }

  /// 详情入口：**按路径分流**到不同的解析器（原 `Api.detail` 的 case body 原样搬来 ✓）
  /// 吃瓜社区的帖子是图文帖（/archives/N/ ✓），跟视频详情不是一套 ✓
  /// ⚠️ 2026-10-05：原来是**死代码** ✗（`Api.detail` 直接调 `detail` ✗）→ 吃瓜帖子取不到视频 ✗；
  ///    现在 `Api.detail` 改调 `detailOf` ✓，这条分流才真正生效 ✓（见 `site_ui.dart` 的 `detailOf` ✓）
// 看：详情入口按路径分给了哪套解析器 —— 吃瓜帖子被当视频解析时一眼可见。
@override
  Future<ArticleDetail> detailOf(String url) {
    if (url.startsWith('/archives/')) {
      if (AppSettings.i.logConsole) debugPrint('[DETAIL] ${_f.site.name} path=${url.length <= 80 ? url : url.substring(0, 80)} 分流⇒图文帖子解析器');
      return postDetail(url);
    }
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] ${_f.site.name} path=${url.length <= 80 ? url : url.substring(0, 80)} 分流⇒视频解析器');
    return detail(url);
  }

  /// 搜索（**单页**：页面上没有分页入口 ✓；原 `Api.search` 的 case body 原样搬来 ✓）
// 看：搜索解析出几条 —— 0 条就是 /search/?keyword= 的卡片选择器变了（本站搜索只有单页）。
@override
  Future<List<Article>> search(String keyword,
      {int page = 1, List<MapEntry<String, String>>? extra}) async {
    final sw = Stopwatch()..start();
    if (page > 1) {
      if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} 入口=search 页=$page ⇒ 本站搜索无翻页，返回 0 条');
      return [];
    }
    final kw = Uri.encodeComponent(keyword);
    final html = await _f.text('/search/?keyword=$kw');
    final res = parseCards(hp.parse(html));
    if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} 入口=search 页=$page kwLen=${keyword.length} 解析出 ${res.length} 条 ms=${sw.elapsedMilliseconds}');
    return res;
  }

  /// 标签列表页（原 `Api.tag` 的 case body 原样搬来 ✓）
  /// 专题等路径型（点"专题"卡片进来）走页面列表 ✓；标签页是普通列表页（没有分页 ✓）
// 看：标签页解析出几条 —— 0 条就是该标签没内容或卡片选择器变了（路径型走 pageList、其余是单页）。
@override
  Future<List<Article>> tag(String slug, {required int page}) async {
    final sw = Stopwatch()..start();
    if (slug.startsWith('/')) {
      final res = await pageList(slug, page: page);
      if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} 入口=tag slug=$slug 页=$page 解析出 ${res.length} 条 ms=${sw.elapsedMilliseconds}');
      return res;
    }
    if (page > 1) {
      if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} 入口=tag slug=$slug 页=$page ⇒ 标签页无翻页，返回 0 条');
      return [];
    }
    final res = parseCards(hp.parse(await _f.text('/tag/$slug/')));
    if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} 入口=tag slug=$slug 页=$page 解析出 ${res.length} 条 ms=${sw.elapsedMilliseconds}');
    return res;
  }

  /// 首页 = 第一个频道的「最新」（原 `Api.home` 的 case body 原样搬来 ✓）
// 看：首页（第一个频道的最新）解析出几条 —— 0 条就是 /api/videos/category 的 items 空了。
@override
  Future<List<Article>> home({required int page, String first = ''}) async {
    final sw = Stopwatch()..start();
    final res = await list(first, sort: 'latest', page: page);
    if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} 入口=home 页=$page 解析出 ${res.length} 条 ms=${sw.elapsedMilliseconds}');
    return res;
  }

  /// 「分类」tab 的列表（原 `Api.category` 的 case body 原样搬来 ✓）
// 看：分类页解析出几条 —— 0 条就是 JSON 接口的 items 空了，或路径型列表的卡片选择器变了。
@override
  Future<List<Article>> category(String key,
          {required int page,
          String? k,
          String? theme,
          String? duration,
          String? sort,
          List<MapEntry<String, String>>? extra,
          Future<List<Article>> Function({int page})? home}) async {
    final sw = Stopwatch()..start();
    // 并集里 kk 是可空具名参数 ✗ → 绑定回原语义 ✓
    final kk = k ?? key;
    // 以 / 开头 = 站内路径型列表（精选推荐/最近上新/专题/排行榜/吃瓜黑料）
    // 否则是频道 slug；只有一层排序：子分类 key 就是 sort 值，没选就按最新
    final res = kk.startsWith('/')
        ? await pageList(kk, page: page)
        : await list(key, sort: kk == key ? 'latest' : kk, page: page);
    // ★【常驻诊断】列表解析结果：站名 + key + 页 + 条数 + 耗时 ✓
    if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} k=$key 页=$page 解析出 ${res.length} 条 ms=${sw.elapsedMilliseconds}');
    return res;
  }
  // 黄果短剧（huangguoai）

  /// 黄果的"路径型"列表页（不是 JSON 接口那套）：
  /// - `/recommend`、`/newest`、`/topics/xxx/` → `hg-drama-card` 网格，翻页 `/xxx/2/`
  /// - `/ranks/hot/`                          → `hg-rank-item`（TOP20，无翻页）
  /// - `/chigua/`（及其子分类 remen/yuanchuang） → `hg-post-card` 帖子卡
  ///   （横版大图、列表 2 列）；翻页两形态：全部 → `/chigua/page/2/`、
  ///   子分类 → `/chigua/remen/2/`（都按页面实际链接，别猜）
  Future<List<Article>> pageList(String path, {int page = 1}) async {
    final sw = Stopwatch()..start(); // ★【常驻诊断】只计时 ✓ 不动分流/取数路径 ☠
    final p = path.endsWith('/') ? path : '$path/';
    // ⚠️ 精选推荐 / 最近上新 要走 **JSON 接口**：页面 HTML 里那份是站点没更新的静态版
    // （抓 HTML 会拿到另一个顺序，跟用户在站点上看到的对不上）。
    // /api/videos 默认排序 = 站点"热门视频推荐"那份；sort=new = 最新上传。
    if (p == '/recommend/' || p == '/newest/') {
      final sort = p == '/newest/' ? 'sort=new&' : '';
      final body = await _f.text('/api/videos?${sort}page=$page&size=20');
      final j = jsonDecode(body);
      final items = j is Map<String, dynamic>
          ? ((j['data'] is Map<String, dynamic>)
              ? (j['data']['items'] ?? const [])
              : const [])
          : const [];
      final res = [
        for (final it in items)
          if (it is Map<String, dynamic>) _hgArticle(it),
      ];
      // 看：路径型列表（精选推荐/最近上新走 JSON 接口）解析出几条 —— 0 条就是 data.items 空了。
      if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} pageList path=$p 页=$page 源码=json 解析出 ${res.length} 条 ms=${sw.elapsedMilliseconds}');
      return res;
    }
    // 翻页形态按站点实际链接来（不猜）：
    //   "全部"（/chigua/）→ /chigua/page/2/；子分类（/chigua/remen/ 等）→ /chigua/remen/2/；
    //   其余路径型（/topics/xxx/ 等）→ /xxx/2/
    final url = page <= 1
        ? p
        : ((p == '/chigua/' || p == '/chigua')
            ? '${p}page/$page/'
            : '$p$page/');
    final doc = hp.parse(await _f.text(url));
    final List<Article> res;
    if (p.startsWith('/chigua')) {
      res = _hgPostCards(doc);
    } else if (p.startsWith('/ranks')) {
      res = _hgRankCards(doc);
    } else if (p == '/topics/') {
      // 专题列表页（/topics/）上是"专题卡"，专题自己的页面（/topics/xxx/）才是视频网格
      res = _hgTopicCards(doc);
    } else {
      res = parseCards(doc);
    }
    // 看：路径型列表（HTML 那套）解析出几条 —— 0 条就是该路径的卡片选择器变了。
    if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} pageList path=$p 页=$page 源码=html 解析出 ${res.length} 条 ms=${sw.elapsedMilliseconds}');
    return res;
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
        meta: metaDate(date),
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

  /// 吃瓜社区的帖子详情：图文帖（正文在 .hg-post-detail__body，图片走 data-src）
  /// + **可选的多个视频**：正文里嵌 `div.post-video-player`，`data-src` 就是
  /// 现成的 m3u8（站点 xgplayer 播的就是它）；每个视频上面一般有个 `<h2>`
  /// 小标题，拿来当作选集 label。
  /// ⚠️ 2026-09-30 修正：之前写死"吃瓜帖是图文、无视频"是**探测不到位**
  /// （只扫了几篇就下结论）——实测 606/605/604/602 都有视频，612/611/610 是纯图文。
  Future<ArticleDetail> postDetail(String url) async {
    final sw = Stopwatch()..start(); // ★【常驻诊断】只计时 ✓ 不动解析路径 ☠
    final doc = hp.parse(await _f.text(url));
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
    // 正文里的视频（可以多个）：取 data-src；label 用视频前面最近的 <h2> 小标题
    final videos = <ArticleVideo>[];
    final body = doc.querySelector('.hg-post-detail__body');
    var ordinal = 0;
    for (final p
        in body?.querySelectorAll('div.post-video-player') ?? const <Element>[]) {
      final src = p.attributes['data-src'] ?? '';
      if (!src.startsWith('http')) continue;
      ordinal++;
      var label = '';
      var prev = p.previousElementSibling;
      while (prev != null) {
        if (prev.localName == 'h2') {
          label = prev.text.trim();
          break;
        }
        prev = prev.previousElementSibling;
      }
      videos.add(ArticleVideo(
        label: label.isEmpty ? '视频 $ordinal' : label,
        ordinal: ordinal,
        sources: [src],
      ));
    }
    final time = metaDate(doc.querySelector('.hg-post-detail')?.text ?? '');
    final tags = <MapEntry<String, String>>[];
    for (final a in doc.querySelectorAll('.hg-post-detail a[href*="/tag/"]')) {
      final href = a.attributes['href'] ?? '';
      final t = a.text.trim();
      if (href.isEmpty || t.isEmpty || t.length > 20) continue;
      final slug = href.split('/tag/').last.replaceAll('/', '');
      if (slug.isEmpty) continue;
      if (!tags.any((e) => e.key == slug)) tags.add(MapEntry(slug, t));
    }
    final det = ArticleDetail(
      title: title.isEmpty ? url : title,
      time: time,
      categories: const [],
      images: images,
      intro: intro,
      videos: videos, // ← 之前是 const []（"吃瓜帖是图文"探测不到位）
      tags: tags,
      related: parseCards(doc).where((x) => x.url != url).take(12).toList(),
      seriesPrefix: seriesPrefix(title),
    );
    // 看：吃瓜帖子（图文）解析出几条 —— 视频/图 全 0 就是帖子正文结构变了。
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] ${_f.site.name} 子解析=吃瓜帖子 path=${url.length <= 80 ? url : url.substring(0, 80)} 视频=${det.videos.length} 图=${det.images.length} 相关=${det.related.length} ms=${sw.elapsedMilliseconds}');
    return det;
  }

  // ---------------------------------------------------------------------------

  /// 列表：JSON 接口 `/api/videos/category/{channel}?sort=..&page=..&size=..`
  /// [sort]：latest / hot / original / random（对应页面上的 4 个子 tab）
  Future<List<Article>> list(String channel,
      {required String sort, int page = 1}) async {
    final sw = Stopwatch()..start(); // ★【常驻诊断】只计时 ✓ 不动取数/解析路径 ☠
    final sortParam = switch (sort) {
      'hot' => 'hot_window',
      'original' => 'hot_window&is_original=1',
      _ => sort,
    };
    final path =
        '/api/videos/category/$channel?sort=$sortParam&page=$page&size=20';
    final body = await _f.text(path);
    final data = jsonDecode(body);
    if (data is! Map<String, dynamic>) {
      // 看：频道列表 JSON 顶层不是对象（接口报错/换了壳）—— 0 条。
      if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} 频道=$channel sort=$sort 页=$page JSON 顶层非对象 解析出 0 条 ms=${sw.elapsedMilliseconds}');
      return [];
    }
    final d = data['data'];
    final items = (d is Map<String, dynamic> ? d['items'] : null) ?? const [];
    final res = [
      for (final it in items)
        if (it is Map<String, dynamic>) _hgArticle(it),
    ];
    // 看：频道列表（JSON 接口）解析出几条 —— 0 条就是 data.items 空了。
    if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} 频道=$channel sort=$sort 页=$page 解析出 ${res.length} 条 ms=${sw.elapsedMilliseconds}');
    return res;
  }

  Article _hgArticle(Map<String, dynamic> v) {
    final ep = int.tryParse('${v['episode_count'] ?? ''}') ?? 0;
    final total = int.tryParse('${v['total_episodes'] ?? ''}') ?? 0;
    final finished = v['is_finished'] == true;
    // 黄果的卡片：封面右下角显示**集数**（站点自己就是这么显示的），
    // 标题下面依次是 小字简介 + 分类标签
    final epText = finished && total > 0
        ? '全集$total集'
        : (ep > 0 ? '更新至$ep集' : '');
    return Article(
      title: '${v['title'] ?? ''}'.trim(),
      url: '/video/${v['id']}/',
      cover: '${v['cover'] ?? ''}',
      meta: '',
      badge: epText,
      desc: '${v['description'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim(),
      // 卡片不显示标签（用户要求：黄果卡片只留 封面(集数角标)+标题+小字简介）
    );
  }



  /// 详情页里的卡片（相关推荐 / 标签页 / 搜索结果都是这套结构）
  List<Article> parseCards(Document doc) {
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
      final desc = (el.querySelector('.hg-drama-card__desc')?.text ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      out.add(Article(
        title: title,
        url: a.attributes['href'] ?? '',
        cover: img?.attributes['data-src'] ?? '',
        meta: '',
        badge: RegExp(r'(更新至\s*\d+\s*集|全\s*\d+\s*集|完结)')
                .firstMatch(epRaw)
                ?.group(0) ??
            '',
        desc: desc,
        // 卡片不显示标签（用户要求）
      ));
      if (out.length >= 60) break;
    }
    final seen = <String>{};
    return [
      for (final a in out)
        if (seen.add(a.url)) a
    ];
  }

  /// 黄果详情页内嵌的 `<script id="videoInitialData" type="application/json">`
  /// （标题/简介/时间/标签 + epPlaySrcs 都在里面）
  static Map<String, dynamic>? initialData(Document doc) {
    final raw = doc.querySelector('script#videoInitialData')?.text ?? '';
    if (raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) return j;
    } catch (_) {
      // 坏 JSON 当没有
    }
    return null;
  }

  /// 详情：页面内嵌 `<script id="videoInitialData" type="application/json">`，
  /// 里面有 title/description/time/coverSrc/tagLinks 以及
  /// epPlaySrcs = {"1": m3u8, "2": m3u8, ...}（整部剧所有集，一次拿全，不用逐集抓）。
@override
  Future<ArticleDetail> detail(String url) async {
    final sw = Stopwatch()..start();
    final html = await _f.text(url);
    final doc = hp.parse(html);

    final data = initialData(doc);

    final videos = <ArticleVideo>[];
    String title = '';
    String intro = '';
    String time = '';
    final id = '${data?['id'] ?? ''}';
    if (data != null) {
      title = '${data['title'] ?? ''}'.trim();
      intro = '${data['description'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
      time = '${data['time'] ?? ''}'.trim();
    }
    // 选集：页面上有**完整**的选集链接（/video/{id}/、/video/{id}/ep-{n}/），
    // 而 epPlaySrcs 只是"当前集附近的 2~3 集"窗口（第1集页给 {1,2}、第21集页给 {20,21}）
    // → 选集按链接列全（21 集就是 21 条），窗口里有源的直接能播，
    //   其余的 lazyUrl 留成那一集的地址，用户点到才去取（点哪集抓哪集）。
    final epUrls = <int, String>{};
    if (id.isNotEmpty) {
      final re = RegExp(r'^/video/' + RegExp.escape(id) + r'(?:/ep-(\d+))?/$');
      for (final a in doc.querySelectorAll('a[href^="/video/"]')) {
        final href = a.attributes['href'] ?? '';
        final m = re.matchAsPrefix(href);
        if (m == null) continue;
        final n = int.tryParse(m.group(1) ?? '1') ?? 1;
        epUrls.putIfAbsent(n, () => href);
      }
    }
    final eps = data?['epPlaySrcs'];
    if (epUrls.isEmpty) {
      // 页面没有选集链接（单集/结构变了）：退回旧逻辑，只用窗口里的源
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
    } else {
      final ns = epUrls.keys.toList()..sort();
      for (final n in ns) {
        final src = eps is Map ? '${eps['$n'] ?? ''}' : '';
        videos.add(ArticleVideo(
          label: '第 $n 集',
          ordinal: n,
          sources: src.isEmpty ? const [] : [src],
          lazyUrl: src.isEmpty ? epUrls[n] : null,
        ));
      }
    }

    // 相关推荐：详情页「猜你喜欢」区（排除广告 aside.hg-ssp-slot）
    final related = parseCards(doc);

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

    final det = ArticleDetail(
      title: title,
      time: time,
      categories: const [],
      images: const [], // 这站没有剧照（封面就是视频封面）
      intro: intro,
      videos: videos,
      tags: tags,
      related: related.where((a) => a.url != url).take(12).toList(),
      seriesPrefix: seriesPrefix(title),
    );
    // ★【常驻诊断】详情解析结果：站名 + path(截 80) + 视频/图/相关条数 + 耗时 ✓（**不打完整 URL** ☠）
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] ${_f.site.name} path=${url.length <= 80 ? url : url.substring(0, 80)} 视频=${det.videos.length} 图=${det.images.length} 相关=${det.related.length} ms=${sw.elapsedMilliseconds}');
    return det;
  }
}

// ===== 本站专属清单（2026-10-03 从 lib/sites.dart 下放 ✓；循环 import 允许 ✓）=====

const List<SiteTab> hgSorts = [
  SiteTab('latest', '最新更新'),
  SiteTab('hot', '当前热播'),
  SiteTab('original', '独家原创'),
  SiteTab('random', '随机推荐'),
];

// ===== 本站档案（2026-10-03 从 lib/sites.dart 的 kSites 下放 ✓）=====

/// 本站档案：黄果短剧
const SiteEntry kSite06 = SiteEntry(
    name: '黄果短剧',
    template: SiteTemplate.huangguo,
    iconUrl: '/favicon.ico',
    hosts: ['huangguoai.com'],
    // 封面是 3:4 竖图
    portraitCovers: true,
    // 顺序 = 站点导航原顺序：精选推荐 / 最近上新（首页两个板块，路径型）
    // → AI成人短剧 / AI成人漫剧 / AI换脸 / AI魔改（各带 4 个排序）
    // → 专题 / 排行榜 / 黄果吃瓜（顶部导航里 AI魔改 后面那三个）
    categories: [
      SiteTab('/recommend', '精选推荐'),
      SiteTab('/newest', '最近上新'),
      SiteTab('ai-duanju', 'AI成人短剧', hgSorts),
      SiteTab('ai-manju', 'AI成人漫剧', hgSorts),
      SiteTab('ai-huanlian', 'AI换脸', hgSorts),
      SiteTab('ai-mogai', 'AI魔改', hgSorts),
      SiteTab('/topics/', '专题'),
      SiteTab('/ranks/hot/', '排行榜'),
      // 吃瓜社区：站名就叫「黄果吃瓜」（不是"吃瓜黑料"——之前起错了），
      // 且下面带 3 个子分类，照站点导航原样。帖子卡是**横版大图**
      // （站点桌面就是 2 列网格）→ 列表页按 key 前缀走 2 列横版
      SiteTab('/chigua/', '黄果吃瓜', [
        SiteTab('/chigua/', '全部'),
        SiteTab('/chigua/remen/', '热门吃瓜'),
        SiteTab('/chigua/yuanchuang/', 'AI原创'),
      ]),
    ],
    color: Color(0xFFFFB300),
  );
