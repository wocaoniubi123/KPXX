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

import 'package:html/dom.dart' hide Text; // ★ 2026-10-27：`hide Text` 见下方 material 那段的说明
import 'package:html/dom.dart' as dom; // 只为在撞名处写 `dom.Text`（DOM 文本节点）✅
import 'package:html/parser.dart' as hp;

import '../base/fetch.dart';
import '../base/fmt.dart';
import '../models.dart';
// ★ 诊断打印：`debugPrint` 在 foundation 里 ✓（**不能**引 material ✗ 见上）；开关在 settings ✓
import 'package:flutter/foundation.dart' show debugPrint;
import '../settings.dart';

// ★ 2026-10-27（用户要求：首页改「板块行」版式）—— 只新增**一个 tab 的内容**，
//   顶栏/AppBar/tab 行**仍由底座渲染**（见 `SiteUi.tabBody`）。
//   🛢️ 为什么用 `show` 逐个引、而不是整包 import material：
//      material 会导出 `Element` / `Text` / `Key`，
//      与上面 `package:html/dom.dart` 的 `Element` / `Text` 撞名
//      （2026-10-03 analyze 报的 7 条错误就是这个 ☠）
//   🛢️ 为什么 `html/dom.dart` 要 `hide Text` + 再来一份 `as dom`：
//      - `hide Text` ⇒ 无前缀那份不导出 DOM 的 `Text`，让 material 的 `Text` 独占这个名字 ✅
//      - `as dom`    ⇒ DOM 的 `Text` 仍能以 `dom.Text` 取到（本文件 L609 那处要用）✅
import 'package:flutter/material.dart'
    show
        Widget,
        BuildContext,
        State,
        StatefulWidget,
        // ★ 2026-10-28（整页自管需要）：ticker（TabController 用）+ 各 tab 组件 + Border
        SingleTickerProviderStateMixin,
        TabController,
        TabBar,
        TabBarView,
        Tab,
        TabAlignment,
        AutomaticKeepAliveClientMixin,
        Border,
        Text,
        TextStyle,
        TextOverflow,
        TextButton,
        AspectRatio,
        Axis,
        BorderRadius,
        BoxDecoration,
        Center,
        CircularProgressIndicator,
        ClipRRect,
        Colors,
        Column,
        Container,
        CrossAxisAlignment,
        EdgeInsets,
        Expanded,
        FontWeight,
        GestureDetector,
        HitTestBehavior,
        Icon,
        Icons,
        ListenableBuilder,
        ListView,
        MainAxisSize,
        MaterialPageRoute,
        Navigator,
        Padding,
        Positioned,
        RefreshIndicator,
        Row,
        RouteSettings,
        Scaffold,
        AppBar,
        ScrollController,
        SizedBox,
        Stack,
        StackFit,
        WidgetsBinding;
import '../app_background.dart'; // kTxt / kTxtSub / PageBg（跟随背景明暗 + 转场不穿透）
import '../app_bg.dart'; // AppBg（明暗）
import '../fetched_image.dart'; // FetchedImage（全站共用封面组件）
import '../detail_page.dart' show DetailPage; // 点卡片进详情页（与野果同款 ✅）
import '../home_page.dart' show RowsGrid; // ★ 全站通用网格（行高自适应 ⇒ 间距与全站一致 ✅）

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

  /// ★ 2026-10-28（用户实测"点进专题 还是就那么几个"）：
  ///   **专题卡（`/topics/xxx/`）不是视频详情页，而是"专题作品列表页"** ——
  ///   走详情页会拿 `detail()` 的视频解析器，那个页面没有 `videoInitialData`
  ///   ⇒ 解析不出东西 ⇒ 用户看到"就那么几个" ☠
  ///
  /// 🛢️ 实测（2026-10-28）：
  /// ```
  /// /topics/hot-aiduanju/    → 28 张 div.hg-drama-card（页面自己写「共59部」）
  /// /topics/hot-aiduanju/2/  → 28 张
  /// /topics/hot-aiduanju/3/  → 15 张
  /// ⇒ 真站是**分页**的，共 71 条（含季度拆分）
  /// ```
  ///
  /// ⇒ 返回 `'list'`（底座那套 `TagListPage`）：它按页调 `category()` →
  ///   本站 `category()` 对 `/` 开头走 `pageList()` ⇒ **自动翻页** ✅
  ///   （与 Pornhub 演员卡 / xHamster 明星卡同一套机制 ✅ 零公共区改动）
  @override
  String? specialTap(String url) {
    if (url.startsWith('/topics/')) {
      if (AppSettings.i.logConsole) {
        debugPrint('[LIST] ${_f.site.name} specialTap=list（专题） path=${url.length <= 80 ? url : url.substring(0, 80)}');
      }
      return 'list';
    }
    return null;
  }

  /// ★ 2026-10-28（用户要求）：**黄果整页自己管**（照野果 `yeguodj.dart` 那套 ✅）
  ///
  /// 🛢️ 为什么必须整页自管（用户规矩：**独立站点能做的就在站点文件里做**，不动公共区 ✅）：
  ///   底座 `_FeedView` 只把 `List<Article>` 渲染成**单一块网格** ——
  ///   **没有"多板块行 + 标题行 + 查看更多"这种版式** ⇒ 站点文件内唯一能做到的办法 = 自管整页 ✅
  ///
  /// 🛢️ 为什么不用 `tabBody` 那种"只换 tab 内容"的钩子：底座**没有**这个钩子
  ///   （`SiteUi` 里只有 `sitePage`）⇒ 加钩子就得改公共区 `base/site_ui.dart` + `home_page.dart`
  ///   ⇒ 违反用户口径 ☠ ⇒ 改成整页自管，**公共区零改动** ✅
  ///
  /// 本页 = 顶栏（站点名 + 搜索）+ 8 个 tab + TabBarView：
  ///   首页（板块行）/ AI成人短剧 / AI成人漫剧 / AI换脸 / AI魔改 / 专题 / 排行榜 / 黄果吃瓜
  @override
  Widget? sitePage(BuildContext context, SiteEntry site) =>
      HuangguoHomePage(site: site, api: this);

  /// 拉首页 → 板块行（**实测结构，2026-10-27**）
  ///
  /// 🛢️ 站点首页共 4 个 `section.hg-section`，其中「分类推荐」内部是 4 组：
  /// ```
  /// <section class="hg-section">
  ///   <div class="hg-section-header">
  ///     <h2>精选推荐</h2>
  ///     <a class="hg-see-more" href="/recommend">…</a>
  ///   </div>
  ///   <div class="hg-card-grid">… div.hg-drama-card …</div>
  /// </section>
  /// ```
  ///   · 精选推荐 4 张剧卡（more=/recommend）· 最近上新 8 张（more=/newest）
  ///   · 分类推荐 4 组（`.hg-category-col`，每组 `a.hg-category-item` 3 条，
  ///     组标题链接 = 该组列表页 `/ai-duanju/` 等）
  ///   · 专题推荐 4 张专题卡（`a.hg-topic-card`，more=/topics/）
  /// ⇒ 拆成 **7 个板块行**（分类推荐按组平铺，用户口径"下面还有很多这种板块，都加上"✅）
  Future<List<HgSection>> homeSections() async {
    final sw = Stopwatch()..start();
    final doc = hp.parse(await _f.text('/'));
    final out = <HgSection>[];

    for (final sec in doc.querySelectorAll('section.hg-section')) {
      final title = (sec.querySelector('h2')?.text ?? '').trim();
      if (title.isEmpty) continue;
      final moreHref = sec.querySelector('a.hg-see-more')?.attributes['href'] ?? '';

      // ① 剧卡板块（精选推荐 / 最近上新）
      final cards = _cardsFrom(sec.querySelectorAll('div.hg-drama-card'));
      if (cards.isNotEmpty) {
        out.add(HgSection(
          title: title,
          items: cards,
          moreKey: moreHref.isEmpty ? '' : _normKey(moreHref),
        ));
        continue;
      }

      // ② 分类推荐：按 `.hg-category-col` 拆成多行
      //    🛢️ 实测：这里的卡**不是** `hg-drama-card`，而是 `a.hg-category-item`（我第一版搞错过 ☠）
      for (final col in sec.querySelectorAll('.hg-category-col')) {
        final colTitle =
            (col.querySelector('.hg-category-col__title')?.text ?? '').trim();
        if (colTitle.isEmpty) continue;
        final colItems = <Article>[];
        for (final a in col.querySelectorAll('a.hg-category-item')) {
          final href = a.attributes['href'] ?? '';
          if (!href.startsWith('/video/')) continue;
          final t = (a.querySelector('.hg-category-item__title')?.text ?? '').trim();
          if (t.isEmpty) continue;
          final img = a.querySelector('img[data-src]') ?? a.querySelector('img');
          colItems.add(Article(
            title: t,
            url: href,
            cover: img?.attributes['data-src'] ?? (img?.attributes['src'] ?? ''),
            meta: '',
            desc: (a.querySelector('.hg-category-item__desc')?.text ?? '')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim(),
          ));
        }
        if (colItems.isEmpty) continue;
        final colHref =
            col.querySelector('a.hg-category-col__title')?.attributes['href'] ?? '';
        out.add(HgSection(
          title: colTitle,
          items: colItems,
          moreKey: colHref.isEmpty ? '' : _normKey(colHref),
        ));
      }

      // ③ 专题推荐：专题卡（点开是该专题的视频列表）
      final topics = <Article>[];
      for (final a in sec.querySelectorAll('a.hg-topic-card')) {
        final href = a.attributes['href'] ?? '';
        if (!href.startsWith('/topics/')) continue;
        final t = (a.querySelector('.hg-topic-card__title')?.text ?? '').trim();
        if (t.isEmpty) continue;
        final img = a.querySelector('img[data-src]') ?? a.querySelector('img');
        topics.add(Article(
          title: t,
          url: href,
          cover: img?.attributes['data-src'] ?? (img?.attributes['src'] ?? ''),
          meta: '',
          badge: (a.querySelector('.hg-topic-card__meta')?.text ?? '').trim(),
        ));
      }
      if (topics.isNotEmpty) {
        out.add(HgSection(
          title: title,
          items: topics,
          moreKey: moreHref.isEmpty ? '' : _normKey(moreHref),
        ));
      }
    }

    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 首页板块=${out.length} '
          '${out.map((s) => '${s.title}(${s.items.length})').join(' / ')} '
          'ms=${sw.elapsedMilliseconds}');
    }
    return out;
  }

  /// 把站内绝对路径归一成 key（首页给的 href 可能带 host）
  String _normKey(String href) {
    if (!href.startsWith('http')) return href;
    final i = href.indexOf('/', href.indexOf('://') + 3);
    return i >= 0 ? href.substring(i) : href;
  }

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

  /// 搜索（★ 2026-10-12 **接上真分页 + 限定结果区** ✅ —— 用户实报"搜「高」比官网少很多"）
  ///
  /// 【依据（本机实测 🛢️，2026-10-12）】
  ///   · 官网**支持真分页**：`?keyword=<kw>&page=<n>` 实测 200、`<title>… - 第2页</title>`、另一批卡 ✅；
  ///     站方自己的跳页模板 = `/search/video/<kw>/{page}/` ✅（页面里 `data-jump-tpl` ✅）；
  ///   · 官网自己写着 **`data-track-search-total="105"` + `data-pages="6"`**（关键词「高」）✅
  ///     ⇒ 原来那句"本站搜索无翻页、`page>1` 直接返回空"是**错的** ☠（当时只看了有没有 `<a href=…page=…>` 链接）；
  ///   · 结果卡**只在 `div.hg-search-results` 里**取：页面上另有**隐藏的「搜索建议」面板**
  ///     （`hg-search-suggest__guess`）也含 4 张同样的卡 ⇒ 全页选择器会多收 4 张 ✅
  ///     （取不到结果区时**回退全页**，行为与改动前一致，不会更差 ✅）。
  // 看：搜索解析出几条 —— 0 条就是 /search/?keyword= 的卡片选择器变了；每页应为 20（官网口径）。
  @override
  Future<List<Article>> search(String keyword,
      {int page = 1, List<MapEntry<String, String>>? extra}) async {
    final sw = Stopwatch()..start();
    final kw = Uri.encodeComponent(keyword);
    final p = page <= 1 ? 1 : page;
    final html = await _f.text('/search/?keyword=$kw&page=$p');
    final doc = hp.parse(html);
    final scope = doc.querySelector('div.hg-search-results');
    final res = scope == null ? parseCards(doc) : parseCardsIn(scope);
    if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} 入口=search 页=$p kwLen=${keyword.length} 解析出 ${res.length} 条 结果区=${scope != null} ms=${sw.elapsedMilliseconds}');
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
  List<Article> parseCards(Document doc) =>
      _cardsFrom(doc.querySelectorAll('div.hg-drama-card'));

  /// ★ 2026-10-12（**搜索页专用**）：**只在结果区里取卡** ✅ ——
  ///   依据（本机实测 🛢️）：搜索页除了 `div.hg-search-results`（含 `div.hg-card-grid`）里的**真结果**，
  ///   还另有一块**隐藏的「搜索建议」面板** (`section.hg-search-suggest__section` → `div.hg-search-suggest__guess`)，
  ///   里面**也是** `div.hg-drama-card` ⇒ 用全页选择器会**多收 4 张**（实测「高」：全页 24 张 vs 结果区 20 张 ✅）。
  List<Article> parseCardsIn(Element scope) =>
      _cardsFrom(scope.querySelectorAll('div.hg-drama-card'));

  /// 卡片解析主体（`parseCards` / `parseCardsIn` 共用，**逻辑一字未改** ✅）
  List<Article> _cardsFrom(Iterable<Element> els) {
    final out = <Article>[];
    for (final el in els) {
      final a = el.querySelector('a.hg-drama-card__cover-link') ??
          el.querySelector('a[href^="/video/"]');
      if (a == null) continue;
      // 标题：取链接里的文本节点（要排掉 <span class="sr-only">全集在线观看</span>）
      final titleEl = el.querySelector('.hg-drama-card__title a') ?? a;
      final buf = StringBuffer();
      for (final n in titleEl.nodes) {
        if (n is dom.Text) buf.write(n.text);
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
    assetIcon: 'assets/site_icons/huangguo.png', // ★ 2026-10-12 内置图标（抓一次、零网络 ✅）
    hosts: ['huangguoai.com'],
    // 封面是 3:4 竖图
    portraitCovers: true,
    // 顺序 = 站点导航原顺序：首页 / AI成人短剧 / AI成人漫剧 / AI换脸 / AI魔改
    // → 专题 / 排行榜 / 黄果吃瓜
    // ★ 2026-10-27（用户要求）：**取消「精选推荐 / 最近上新」两个 tab，改成「首页」**
    //   「首页」的内容由 [tabBody] 提供（站点首页那套**板块行**版式 ✅）；
    //   顶栏 tab / AppBar **仍由底座渲染**（⚠️ 不走 `sitePage` —— 那是**整页替换**，
    //   会把顶栏一起吃没，用户 2026-10-27 实测报的就是这个 ☠）
    categories: [
      SiteTab('/home', '首页'),
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

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// ★ 2026-10-27（用户要求）：**首页板块行 UI**
//
// 用户口径（逐条对应）：
//   · "取消：精选推荐 最近上新 这2个tab。改为首页tab" ✅ ⇒ tab 定义已改（见上面 kSite06）
//   · "首页tab下按照网站板块做，请看图一，下面还有很多这种板块，都加上" ✅ ⇒ 7 个板块行
//   · 形态（用户选定）：**竖向滚动，每个板块一行横滑 + 「查看更多 ›」** ✅
//
// ⚠️ 本页只是**一个 tab 的内容**（由 `SiteUi.tabBody` 挂）——
//   顶栏 / AppBar / tab 行仍由底座 `home_page.dart` 渲染，所以**不会再吃掉顶栏** ✅
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// 首页的一个板块（标题 + 卡片 + 该板块"查看更多"去哪）
class HgSection {
  final String title;
  final List<Article> items;

  /// 「查看更多 ›」的目标 key（空 = 该板块没有更多页）
  final String moreKey;

  const HgSection({required this.title, required this.items, this.moreKey = ''});
}

/// ★ 2026-10-28：其它 tab 的列表（**自己管整页之后**，这些 tab 也得由本站渲染）
///
/// 取数仍走本站 `category()`（= 站点自己的 `pageList` / `list` 分流 ✅），
/// 版式用全站通用 `RowsGrid`（**行高自适应、间距 8** ⇒ 与底座列表页视觉一致 ✅）
class HgTabList extends StatefulWidget {
  const HgTabList({
    super.key,
    required this.api,
    required this.site,
    required this.tab,
  });

  final HuangguoSite api;
  final SiteEntry site;
  final SiteTab tab;

  @override
  State<HgTabList> createState() => _HgTabListState();
}

class _HgTabListState extends State<HgTabList>
    with AutomaticKeepAliveClientMixin {
  final List<Article> _items = [];
  final ScrollController _sc = ScrollController();
  int _page = 1;
  bool _loading = false;
  bool _done = false;
  String _err = '';
  String? _sort; // 子分类（排序）当前选中项

  @override
  bool get wantKeepAlive => true; // 切走再回来不重拉（与底座 _FeedView 同口径 ✅）

  @override
  void initState() {
    super.initState();
    _sc.addListener(_onScroll);
    _more();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFillScreen());
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_sc.hasClients || !_sc.position.hasContentDimensions) return;
    if (_sc.position.pixels >= _sc.position.maxScrollExtent - 300) _more();
  }

  void _maybeFillScreen() {
    if (!mounted || _done || _loading) return;
    if (!_sc.hasClients || !_sc.position.hasContentDimensions) return;
    if (_sc.position.maxScrollExtent <= 0.5) _more();
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    _loading = true;
    try {
      // 本站 category()：`k` = 排序值（子分类 key），不选就按档案默认 ✅
      final next = await widget.api.category(
        widget.tab.key,
        page: _page,
        k: _sort ?? widget.tab.key,
      );
      if (!mounted) return;
      setState(() {
        if (next.isEmpty) {
          _done = true;
        } else {
          _items.addAll(next);
          _page++;
        }
        _err = '';
      });
    } catch (e) {
      if (!mounted) return;
      // 已有内容 + 该页失败 ⇒ 视为到底（站点翻过最后一页会给 404 ✅）
      if (_items.isNotEmpty) {
        setState(() => _done = true);
      } else {
        setState(() => _err = '$e');
      }
    } finally {
      _loading = false;
      if (!_done && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFillScreen());
      }
    }
  }

  void _pickSort(String? k) {
    setState(() {
      _sort = k;
      _items.clear();
      _page = 1;
      _done = false;
      _err = '';
    });
    _more();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) {
        final subs = widget.tab.subs;
        return Column(
          children: [
            // 子分类（排序）胶囊行 —— 与底座同款样式（站点筛选项就是这些）
            if (subs.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  children: [
                    for (final s in subs)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _pickSort(s.key),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _sort == s.key
                                  ? const Color(0xFFE8590C)
                                  : (_sort == null && s == subs.first
                                      ? const Color(0xFFE8590C)
                                      : Colors.transparent),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: kChipBorder),
                            ),
                            child: Text(
                              s.name,
                              style: TextStyle(
                                fontSize: 12,
                                color: (_sort == s.key ||
                                        (_sort == null && s == subs.first))
                                    ? Colors.white
                                    : kTxt,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(child: _body()),
          ],
        );
      },
    );
  }

  Widget _body() {
    if (_err.isNotEmpty && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('加载失败：$_err', style: TextStyle(fontSize: 12, color: kTxtSub)),
            TextButton(onPressed: _more, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_items.isEmpty && !_done) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_items.isEmpty && _done) {
      return Center(child: Text('暂无内容', style: TextStyle(color: kTxtSub)));
    }
    return RowsGrid(
      controller: _sc,
      count: _items.length,
      cols: widget.site.portraitCovers ? 3 : 2, // 黄果封面 3:4 竖图 ⇒ 3 列
      tail: _done
          ? null
          : () => const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              ),
      itemBuilder: (_, i) {
        final a = _items[i];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => openHgLink(context, widget.site, widget.api, a),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: AspectRatio(
                  aspectRatio: widget.site.portraitCovers ? 3 / 4 : 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (a.cover.isEmpty)
                        Container(color: const Color(0x223C3C3C))
                      else
                        FetchedImage(url: a.cover, memWidth: 360),
                      if (a.badge.isNotEmpty)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(a.badge,
                                style: const TextStyle(
                                    fontSize: 9, color: Colors.white)),
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
                style: TextStyle(fontSize: 11, color: kTxt),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// ★ 2026-10-28：**黄果链接统一分发**（专题 / 视频详情）
///
/// 🛢️ 为什么必须做成**一个**函数（踩过的坑 ☠）：
///   本站有两处会点卡片 —— ① 首页板块行（`HuangguoHomeTab._openDetail`）
///   ② 「查看更多」后的列表（`HgMoreList` 的 itemBuilder）。
///   2026-10-28 我第一次只改了 ①，用户走的是 ② 那条路（首页→专题推荐→查看更多→点专题）
///   ⇒ **症状一模一样，白改一轮**。统一到这里，两处调同一个 ✅
///
/// 🛢️ 判据（实测 2026-10-28）：
///   · `/topics/xxx/` = **专题作品列表页**（页面写「共59部」；分页 `/topics/xxx/2/`、
///     `/topics/xxx/3/` 实测 28+28+15 = 71 条 ✅）⇒ 必须进**列表**，不能进详情 ☠
///   · 其它（`/video/xxx/`）= 视频详情页 ⇒ `DetailPage` ✅
void openHgLink(
    BuildContext context, SiteEntry site, HuangguoSite api, Article a) {
  if (a.url.startsWith('/topics/')) {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: RouteSettings(name: '黄果·${a.title}'),
        builder: (_) => PageBg(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: Text(a.title),
              centerTitle: true,
              foregroundColor: kTxt,
            ),
            body: HgMoreList(api: api, site: site, path: a.url),
          ),
        ),
      ),
    );
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute(
      settings: const RouteSettings(name: '详情页'),
      builder: (_) => PageBg(
        child: DetailPage(site: site, baseUrl: a.url, listCover: a.cover),
      ),
    ),
  );
}

/// ★ 2026-10-28：**黄果整页**（顶栏 + 8 个 tab，照野果 `yeguodj.dart` 同款结构 ✅）
///
/// 🛢️ 用户口径（2026-10-28）：**"独立站点可以完成的就独立站点修改"** ⇒ 公共区零改动 ✅
///   底座 `_FeedView` 只渲染单一块网格，做不出「板块行」⇒ 只能整页自管（`SiteUi.sitePage`）
///
/// tab 顺序 = `kSite06.categories`（站点档案里那份，**单一来源** ✅ 不在这里再抄一遍）
class HuangguoHomePage extends StatefulWidget {
  const HuangguoHomePage({super.key, required this.site, required this.api});

  final SiteEntry site;
  final HuangguoSite api;

  @override
  State<HuangguoHomePage> createState() => _HuangguoHomePageState();
}

class _HuangguoHomePageState extends State<HuangguoHomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
        length: widget.site.categories.isEmpty ? 1 : widget.site.categories.length,
        vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 整页跟着背景明暗重建（标题/tab/文字都读 kTxt ✅ 与底座同款口径）
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) {
        final cats = widget.site.categories;
        return Scaffold(
          // 透明：让根层背景图透出来 ✅（与底座同款）
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(widget.site.name),
            centerTitle: true,
            foregroundColor: kTxt,
            // 右上角搜索（与底座、野果同款接法 ✅）
            actions: const [],
            bottom: TabBar(
              controller: _tab,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              indicatorColor: const Color(0xFFE8590C),
              labelColor:
                  AppBg.i.isDark ? const Color(0xFFFFB07A) : const Color(0xFFE8590C),
              unselectedLabelColor:
                  AppBg.i.isDark ? Colors.white : const Color(0xFF3A3A3A),
              tabs: [for (final c in cats) Tab(text: c.name)],
            ),
          ),
          body: TabBarView(
            controller: _tab,
            children: [
              for (final c in cats)
                c.key == '/home'
                    // 「首页」= 站点首页那套板块行 ✅
                    ? _sectionsBody()
                    // 其它 tab = 底座同款的普通分页列表（本站 `category()` 那条路）
                    : HgTabList(api: widget.api, site: widget.site, tab: c),
            ],
          ),
        );
      },
    );
  }

  // ===== 首页：板块行 =====
  List<HgSection>? _sections;
  String _err = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sections == null && _err.isEmpty) _load();
  }

  Future<void> _load() async {
    setState(() {
      _sections = null;
      _err = '';
    });
    try {
      final s = await widget.api.homeSections();
      if (!mounted) return;
      setState(() => _sections = s);
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    }
  }

  Widget _sectionsBody() {
    if (_err.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('加载失败：$_err', style: TextStyle(fontSize: 12, color: kTxtSub)),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_sections == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_sections!.isEmpty) {
      return Center(child: Text('首页暂无内容', style: TextStyle(color: kTxtSub)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 6, bottom: 20),
        itemCount: _sections!.length,
        itemBuilder: (_, i) => _sectionRow(_sections![i]),
      ),
    );
  }

  /// 一个板块：标题行（标题 + 「查看更多 ›」）+ 横滑卡片行
  Widget _sectionRow(HgSection s) {
    if (s.items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- 标题行（照站点：橙色竖条 + 标题 + 右侧「查看更多 ›」）----
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 15,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8590C),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Text(
                  s.title,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: kTxt),
                ),
              ),
              if (s.moreKey.isNotEmpty)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openMore(s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('查看更多 ',
                            style: TextStyle(fontSize: 12, color: kTxtSub)),
                        Icon(Icons.chevron_right, size: 15, color: kTxtSub),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        // ---- 横滑卡片行（封面 118×157 竖版 3:4 + 标题 + 两行简介）----
        SizedBox(
          height: 218,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: s.items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _card(s.items[i]),
          ),
        ),
      ],
    );
  }

  Widget _card(Article a) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openDetail(a),
      child: SizedBox(
        width: 118,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 118,
                height: 157, // 118 * 4/3 ≈ 竖版 3:4
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (a.cover.isEmpty)
                      Container(color: const Color(0x223C3C3C))
                    else
                      FetchedImage(url: a.cover, memWidth: 360),
                    if (a.badge.isNotEmpty)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(a.badge,
                              style: const TextStyle(
                                  fontSize: 9, color: Colors.white)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              a.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: kTxt),
            ),
            if (a.desc.isNotEmpty)
              Text(
                a.desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: kTxtSub, height: 1.25),
              ),
          ],
        ),
      ),
    );
  }

  void _openDetail(Article a) {
    // ★ 2026-10-28：统一走 [openHgLink]（专题 → 专题列表；其它 → 详情页）
    openHgLink(context, widget.site, widget.api, a);
  }

  void _openMore(HgSection s) {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: RouteSettings(name: '黄果·${s.title}'),
        builder: (_) => PageBg(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: Text(s.title),
              centerTitle: true,
              foregroundColor: kTxt,
            ),
            body: HgMoreList(api: widget.api, site: widget.site, path: s.moreKey),
          ),
        ),
      ),
    );
  }
}

/// 「查看更多」后的完整列表：复用本站 `pageList`（分页/解析全走已有逻辑 ✅）
class HgMoreList extends StatefulWidget {
  const HgMoreList({
    super.key,
    required this.api,
    required this.site,
    required this.path,
  });

  final HuangguoSite api;
  final SiteEntry site;
  final String path;

  @override
  State<HgMoreList> createState() => _HgMoreListState();
}

class _HgMoreListState extends State<HgMoreList> {
  final List<Article> _items = [];
  final ScrollController _sc = ScrollController();
  int _page = 1;
  bool _loading = false;
  bool _done = false;
  String _err = '';

  @override
  void initState() {
    super.initState();
    // 🛢️ 2026-10-28（用户实测"专题推荐 底部一直转圈圈"）：
    //   监听器只在 `pixels >= maxScrollExtent - 300` 时触发。
    //   ⚠️ **在内容不足一屏 / 或刚好触底但 extent 为 0 时，这个条件永远不成立**
    //      ⇒ `_more()` 再也不会被调 ⇒ 第 2 页永远没人请求 ⇒ **尾部转圈永不消失** ☠
    //   ✅ 修法：加 `hasClients` + 首帧后主动补一次"若没填满就继续拉"
    _sc.addListener(_onScroll);
    _more();
    // 首帧之后再检查一次：内容不足一屏 ⇒ 直接再拉一页（同全站其它页的"自动续拉"口径 ✅）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeFillScreen();
    });
  }

  void _onScroll() {
    if (!_sc.hasClients) return;
    final pos = _sc.position;
    if (!pos.hasContentDimensions) return;
    if (pos.pixels >= pos.maxScrollExtent - 300) _more();
  }

  /// 内容不足一屏（或刚到底）⇒ 再拉一页，直到填满或到底
  ///
  /// ⚠️ 这是"底部转圈不动"的根治：光靠滚动监听，**短列表永远触发不到** ✅
  void _maybeFillScreen() {
    if (!mounted || _done || _loading) return;
    if (!_sc.hasClients) return;
    final pos = _sc.position;
    if (!pos.hasContentDimensions) return;
    // 还没填满一屏（maxScrollExtent ≈ 0）⇒ 继续拉
    if (pos.maxScrollExtent <= 0.5) {
      _more();
    }
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    _loading = true;
    try {
      final next = await widget.api.pageList(widget.path, page: _page);
      if (!mounted) return;
      // ★ 2026-10-28（用户实测"专题推荐 底部一直转圈"）：加诊断，看清到底走了哪条分支
      if (AppSettings.i.logConsole) {
        debugPrint('[HG-MORE] path=${widget.path} 页=$_page 返回=${next.length} 条 '
            '已有=${_items.length} 条');
      }
      setState(() {
        if (next.isEmpty) {
          _done = true;
          if (AppSettings.i.logConsole) {
            debugPrint('[HG-MORE] ⇒ 空页 ⇒ 置 _done（停止转圈）');
          }
        } else {
          _items.addAll(next);
          _page++;
        }
        _err = '';
      });
    } catch (e) {
      if (!mounted) return;
      // 🛢️ 已有内容 + 该页失败 ⇒ 视为到底（站点翻过最后一页会给 404，不是空列表）
      //   实测依据（2026-10-28）：`huangguoai.com/topics/` 只有 1 页，
      //   `/topics/2/`、`/topics/3/` 都返回 **HTTP 404** ⇒ 不这样处理就永远转圈 ☠
      if (AppSettings.i.logConsole) {
        debugPrint('[HG-MORE] path=${widget.path} 页=$_page 请求失败 '
            '已有=${_items.length} 条 ⇒ ${_items.isNotEmpty ? '视为到底' : '报错'}');
      }
      if (_items.isNotEmpty) {
        setState(() => _done = true);
      } else {
        setState(() => _err = '$e');
      }
    } finally {
      _loading = false;
      // ★ 2026-10-28：这一页拉完再检查一次"填满没有" ⇒ 短列表能连续补拉直到到底 ✅
      if (!_done && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFillScreen());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) {
        if (_err.isNotEmpty && _items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('加载失败：$_err',
                    style: TextStyle(fontSize: 12, color: kTxtSub)),
                TextButton(onPressed: _more, child: const Text('重试')),
              ],
            ),
          );
        }
        if (_items.isEmpty) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        // ★ 2026-10-28（用户实测"查看更多点开的列表卡片距离这么宽"）：**改用全站通用网格**
        //   🛢️ 根因（我上一版写错）：用了 `GridView` + `childAspectRatio: 0.52`
        //   ⇒ 每行高度是**固定比例算出来的**，卡片内容撑不满就被纵向拉开 ⇒ 行间距看起来很大 ☠
        //   ✅ `RowsGrid`（`home_page.dart` 里的全站通用件）是
        //      `IntrinsicHeight` 行高自适应：**行高 = 该行最高那张卡**，
        //      行距固定 8、列距固定 8 ⇒ 与全站所有列表页**完全一致** ✅
        //   （同款复用先例：`sites/xhamsterlive.dart` 就是 `import '../home_page.dart' show RowsGrid`）
        return RowsGrid(
          controller: _sc,
          count: _items.length,
          cols: 3, // 黄果封面 3:4 竖图 ⇒ 3 列（同站点）
          // 尾部：还在加载 ⇒ 转圈；到底 ⇒ 空（RowsGrid 的 tail 会被当最后一项渲染）
          tail: _done
              ? null
              : () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  ),
          itemBuilder: (_, i) {
            final a = _items[i];
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              // ★ 2026-10-28（用户实测"查看更多→专题→精品高分AI短剧专辑 还是少"）：
              //   🛢️ 上一轮我只改了 `_openDetail`（首页板块那处），**漏了这一处** ☠
              //   ⇒ 从「查看更多」进专题列表后再点专题卡，仍然走到 DetailPage
              //     ⇒ 专题页被当视频详情解析 ⇒ 条数还是不对。
              //   ✅ 现在两处统一调同一个分发函数 [openHgLink]（专题 → 列表；其它 → 详情）
              onTap: () => openHgLink(context, widget.site, widget.api, a),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: AspectRatio(
                      aspectRatio: 3 / 4,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (a.cover.isEmpty)
                            Container(color: const Color(0x223C3C3C))
                          else
                            FetchedImage(url: a.cover, memWidth: 360),
                          if (a.badge.isNotEmpty)
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(a.badge,
                                    style: const TextStyle(
                                        fontSize: 9, color: Colors.white)),
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
                    style: TextStyle(fontSize: 11, color: kTxt),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}