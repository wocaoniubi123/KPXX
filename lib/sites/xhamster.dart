// xHamster（tw.xhamster.com）—— **本站专属**的一切 ✓
//
// ⚠️ 用户 2026-10-03 决策：取消全站共享，站点相关的一切改成**站点独立专属** ✓
//（分类/子分类/多级分类/选择器/重置/选中状态/取数解析）；**底座保持公用** ✓。
//
// 本文件是从 `api.dart` 的 `Api` 类里**原样搬**过来的（**不重写逻辑** ✓，行为不变 ✓），
// 仅两处**等价替换**：`_fetchText(` → `_f.text(`、`_fetchAbs(` → `_f.abs(` ✓，
// 并补上原本在 `Api` 里的 `_rand`（短片随机起始页 / 每批打乱用 ✓）。
//
// ⚠️ **Step A**：先复制成立（`api.dart` 暂不动 ✓）。**Step B** 才把原段从 `Api` 删掉、
// 并把 `Api.category/detail/search` 里 `case SiteTemplate.xhamster:` 改成委托本类 ✓。

import 'dart:convert';

// ⚠️ 本站只用 `Color`（SiteEntry.color ✓），**不要** import flutter/material ✗
// —— material 会同时导出 `Element`/`Text`/`Key`，与 html/dom、encrypt 撞名 ✗（2026-10-03 analyze 报的 7 条错误就是这个 ✓）
// `Color` 本来就定义在 dart:ui ✓ Flutter 只是转发 ✓
import 'dart:ui' show Color;
import '../sites.dart';
import 'dart:math';

import 'package:html/parser.dart' as hp;

import '../base/fetch.dart';
import '../base/site_ui.dart';
import '../models.dart';

/// xHamster 本站专属实现（取数走公用底座 [SiteFetcher] ✓）
class XhSite extends SiteUi {
  XhSite(this._f);

  final SiteFetcher _f;

  /// ⚠️ 站点**有**搜索（'搜尋所有女優' 那个框 ✓），但**路径没实测过** ✗ →
  /// **明确抛错**，不猜一个地址糊上去 ✓（猜错了会静默变成空列表，更难查 ✓）。
@override
  Future<List<Article>> search(String keyword,
      {int page = 1, List<MapEntry<String, String>>? extra}) async =>
      throw Exception('xHamster 搜索暂未接通（路径未实测）');

  /// 标签列表页（原 `Api.tag` 的 case body 原样搬来 ✓）
  /// 演员卡传过来的是 '/pornstars/<slug>'（本人页 → 视频列表 ✓）；详情页标签也走这里 ✓。
  /// 全是站内路径，交给 list 分流（它会避开"把演员页当演员列表解析"的坑 ✓）
@override
  Future<List<Article>> tag(String slug, {required int page}) => list(slug, page: page);

  /// 首页 = '/'（原 `Api.home` 的 case body 原样搬来 ✓）
@override
  Future<List<Article>> home({required int page, String first = ''}) => list('/', page: page);

  /// 「分类」tab 的列表（原 `Api.category` 的 case body 原样搬来 ✓）
  /// key / theme 都是**站内路径** ✓（「色情明星」tab 自己的选择器也走 theme ✓）：
  ///   · 「影片」tab：'/'、'/hd'、'/4k'、'/vr'
  ///   · 「分类」tab：默认 '/categories/18-year-old'；选中标签后 theme = '/categories/<slug>'
  ///   · 「色情明星」tab：默认 '/pornstars'；选中后 '/pornstars/top/us' 等
  ///   · 「短片」tab：'/shorts' → 内部走 JSON 接口（与路径无关 ✓）
@override
  Future<List<Article>> category(String key,
          {required int page,
          String? k,
          String? theme,
          String? duration,
          String? sort,
          List<MapEntry<String, String>>? extra,
          Future<List<Article>> Function({int page})? home}) =>
      list(theme ?? key, page: page);

  /// xHamster 只有 `/categories/*` tab 挂筛选行（且无子分类时 ✓）
  @override
  bool showsFilterRow(String key, {required bool hasSubs}) => key.startsWith('/categories/') && !hasSubs;

  /// xHamster 的「色情明星」tab ✓
  @override
  bool isStarTabKey(String key) => key == '/pornstars';

  /// xHamster 有「色情明星」tab（要维护它的 feed key 前缀 ✓）
  @override
  bool get hasStarTab => true;

  /// xHamster：`/pornstars/…` 与 `/creators/…` 进他的视频列表 ✓；
  /// `/shorts/…` 进竖屏短片瀑布流 ✓；其余走详情页 ✓。
  @override
  String? specialTap(String url) {
    if (url.contains('/pornstars/') || url.contains('/creators/')) return 'list';
    if (url.startsWith('/shorts/')) return 'shorts';
    return null;
  }

  /// 「色情明星」tab 用 xHamster 那套筛选行 ✓
  @override
  String get starRowKind => 'xh';

  /// xHamster 的短片路径（选中时要重置随机种子 ✓）
  @override
  bool isShortsPath(String key) => key.startsWith('/shorts');

  /// xHamster 的分类选择器按分组展示（40 个演员分类 ✓）
  @override
  bool get hasCatGroups => true;

  /// xHamster 的「色情明星列表」判定（照原逻辑一字不差 ✓）
  /// ⚠️ 注意：只有**演员列表**才是演员卡（`/pornstars`、`/pornstars/all/…`、
  /// `/pornstars/top/…` ✓）；`/pornstars/<名字>` 是**那个演员的视频列表** ✗。
  @override
  bool isStarList(String slug) =>
      slug == '/pornstars' ||
      slug.startsWith('/pornstars/all/') ||
      slug.startsWith('/pornstars/top/');

  /// "色情明星"tab 是竖版头像卡 → 一行 3 个 ✓
  @override
  bool get portraitStarCards => true;

  /// "色情明星"tab 挂本站专用筛选行 ✓
  @override
  bool get hasStarFilterRow => true;

  // ---- 对外入口 ----
  // ⚠️ 原方法全是私有（`_xhList`/`_xhDetail`）✗ —— 跨文件调不到 ✗，所以包一层公开的 ✓
  // （2026-10-03 Round 1 踩到的坑，已记进 DEVLOG 87 条续 ✓）
  Future<List<Article>> list(String path, {int page = 1}) =>
      _xhList(path, page: page);

@override
  Future<ArticleDetail> detail(String url) => _xhDetail(url);

  /// 短片随机起始页 / 每批打乱（原先在 `Api` 里，跟着搬过来 ✓）
  static final Random _rand = Random();
  // xHamster（tw.xhamster.com）—— 见 DEVLOG 75~81
  //
  // ⚠️ 三条硬事实（都实测过，别照别的站的经验改）：
  //  ① **必须用桌面 UA 取**：config 里的 Site.ua 是 iPhone UA，站点只给 **5 张卡/页**；
  //     桌面 UA 给 **50+ 张**。但桌面版 DOM 里第 13 张起全是**骨架屏占位** →
  //     真数据在**页面 JSON**里（跟 assignable / 相关推荐同一个套路）。
  //  ② 「短片」走**页面 JSON** ✓（`/shorts/newest`；翻页是**路径式** `/shorts/newest/{N}` ✓ ——
  //     静态 HTML 里 0 卡片 ✗，数据在页面的 `initials-script` JSON 里 ✓）。
  //  ③ 视频 CDN **不校验 Referer 也不校验 UA**（与 Pornhub 相反）→ 播放不用加特判。

  static const String _xhUa = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  static const Map<String, String> _xhDesk = {'User-Agent': _xhUa};


  /// 页面 JSON 里的字符串都是转义的（`https:\/\/`、中文 `\u516c`）→ 用 jsonDecode 还原。
  static String _xhUn(String? s) {
    if (s == null || s.isEmpty) return '';
    try {
      return jsonDecode('"$s"') as String;
    } catch (_) {
      return s;
    }
  }

  /// 秒 → 时长文本（1:12 / 1:02:03）。站点 JSON 里给的是秒。
  static String _xhClock(int sec) {
    if (sec <= 0) return '';
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
    return '$m:$ss';
  }

  /// 列表：按路径分流（短片接口 / 演员卡 / 普通视频卡）。入参都是**站内路径**。
  Future<List<Article>> _xhList(String path, {int page = 1}) async {
    final p = path.isEmpty ? '/' : path;
    // 「短片」不走 HTML，走 JSON 接口（翻页是 ?page=N，不是路径式）
    if (p.startsWith('/shorts')) return _xhMoments(page);
    final next = page > 1 ? (p == '/' ? '/$page' : '$p/$page') : p;
    final html = await _f.text(next, extraHeaders: _xhDesk);
    // 演员卡列表：'/pornstars'、'/pornstars/all/…'、'/pornstars/top/…'
    // ⚠️ '/pornstars/<名字>' 是**演员本人的页 → 视频列表**，不能走演员解析 ——
    //    那种页里通常带一段"相似演员"的 JSON，一旦按演员解析就是一屏演员卡
    //    （用户实报过"点图上这个人，进去又是明星卡片"）。
    if (p == '/pornstars' ||
        p.startsWith('/pornstars/all/') ||
        p.startsWith('/pornstars/top/')) {
      final stars = _xhStars(html);
      if (stars.isNotEmpty) return stars;
    }
    return _xhCards(html);
  }

  /// 视频卡：从**页面 JSON** 解（DOM 里只有前 ~12 张真卡，其余是骨架屏）。
  /// 字段顺序：id → duration(秒) → title → pageURL → thumbURL → imageURL。
  static List<Article> _xhCards(String html) {
    final out = <Article>[];
    final seen = <String>{};
    final re = RegExp(
        r'"id":(\d+),\s*"duration":(\d+),[\s\S]{0,600}?"title":"((?:[^"\\]|\\.)*)"'
        r'[\s\S]{0,900}?"pageURL":"((?:[^"\\]|\\.)*)"'
        r'[\s\S]{0,300}?"thumbURL":"((?:[^"\\]|\\.)*)"'
        r'[\s\S]{0,300}?"imageURL":"((?:[^"\\]|\\.)*)"');
    for (final m in re.allMatches(html)) {
      final url =
          _xhUn(m.group(4)).replaceFirst(RegExp(r'^https?://[^/]+'), '');
      final title = _xhUn(m.group(3)).replaceAll(RegExp(r'\s+'), ' ').trim();
      if (url.isEmpty || title.isEmpty || !seen.add(url)) continue;
      out.add(Article(
        title: title,
        url: url,
        cover: _xhUn(m.group(6)), // imageURL = 1280×720 大图
        meta: '',
        badge: _xhClock(int.tryParse(m.group(2) ?? '') ?? 0),
      ));
    }
    return out;
  }

  /// 演员卡：'/pornstars' 系页面里 **DOM 一张卡都没有**（整页客户端渲染），
  /// 数据在页面 JSON 的 `"pornstars":[{…}]` 里：videoCount → name → pageURL → logoThumbUrl。
  /// 点进去是他/她的**视频列表**（'/pornstars/<slug>'）。
  static List<Article> _xhStars(String html) {
    final out = <Article>[];
    final seen = <String>{};
    final re = RegExp(
        r'"videoCount":(\d+)[\s\S]{0,400}?"name":"((?:[^"\\]|\\.)*)"'
        r'[\s\S]{0,300}?"pageURL":"((?:[^"\\]|\\.)*)"'
        r'[\s\S]{0,300}?"logoThumbUrl":"((?:[^"\\]|\\.)*)"');
    for (final m in re.allMatches(html)) {
      final name = _xhUn(m.group(2)).replaceAll(RegExp(r'\s+'), ' ').trim();
      final url =
          _xhUn(m.group(3)).replaceFirst(RegExp(r'^https?://[^/]+'), '');
      if (name.isEmpty || url.isEmpty || !seen.add(url)) continue;
      out.add(Article(
        title: name,
        url: url,
        cover: _xhUn(m.group(4)),
        meta: '${m.group(1)} 部',
        badge: '',
        // 演员是**竖版头像**（用户 2026-10-02："色情明星要竖版显示"）；列表一行 3 个
        // （见 home_page 的 cols 条件，与 Pornhub 的 /pornstars 同一处理）。
        coverAspect: 3 / 4,
      ));
    }
    return out;
  }

  /// 「短片」旧路：JSON 接口 `/api/v1/moments` —— **2026-10-03 已整条撤掉** ✗（带 `X-Requested-With` 会被站点当 **404** ✗，sim-dev 逐头实测 ✓；翻页改走路径式 ✓，见下方 `_xhMoments` ✓）。
  /// ⚠️ 每页只有 5~6 条、单次要 2~5s，而且**页大小调不大**（itemsOnPage/limit/perPage/
  /// size/count/pageSize 全试过无效）→ **并发抓 4 页再合并**，否则就是"5 条…等好几秒…又 5 条"
  /// （用户实报过）。
  /// ⚠️ 2026-10-03 修正：上面这段「并发抓 4 页 / 随机起始页」是**旧实现** ✗ —— 现在第 2 页起
  ///    只抓**当页**；**翻页是路径式** ✓（`/shorts/newest/{N}` ✓，2026-10-03 sim-dev 实测 ✓ —— 见下方 `_xhMoments` ✓）。
  /// ⚠️ **随机**（用户 2026-10-02："短片的卡片列表每次进去也要随机。不然你老是显示第一批短片
  /// 意义在哪里？？？"）—— 站点接口是**固定分页序**，所以只打乱是不够的 ✗（池子还是那几条）：
  /// **起始页取随机 1~48**（该范围实测有内容 🔍），列表内往后顺延；每批打乱；按 url 去重。
  /// `resetShortsRandom()` 让下一次取数**重新随机**（切 tab 回来时调，与 sim 行为一致 ✓）。



  /// 短片列表：**每页都抓页面里内嵌的 JSON** ✓（第 1 页 `/shorts/newest` ✓，第 2 页起 `/shorts/newest/{N}` ✓）
  /// （用户 2026-10-03 定："**短片不用 api 请求了。直接抓 json 吧**" ✓）
  ///
  /// ⚠️（历史，2026-10-03 当时为什么改走页面 ✗）用户实机（**App 是直连架构**，DEVLOG 铁律 3）报
  /// "短片接口失败：Exception：所有域名均无法访问" ✗ —— 接口请求在他的网络下**整个失败**，
  /// 而**页面请求是通的** ✓（影片/分类 tab 一直有数据 ✓）。所以列表也改走页面 ✓。
  ///
  /// 页面 `/shorts/newest` 的 HTML 里有 `<script id="initials-script">window.initials={…}` ✓，
  /// 数据在 `layoutPage.videoListProps.videoThumbProps`（实测 **45 条** 🔍），每条：
  /// id / title / pageURL / **imageURL（405×720 竖版）** / thumbURL / landing / views ✓，
  /// ⚠️ **不含 sources** ✗ → 播放仍走详情页 `/shorts/<slug>`（那本来就是页面、通的 ✓）。
  /// 抠 JSON 用**黄果详情页同一套**（`hp.parse` + `querySelector` ✓），不自造大括号匹配 ✓。
  static const String _xhShortsPath = '/shorts/newest';

  static List<Article> _xhMomentsFromHtml(String html) {
    final doc = hp.parse(html);
    final raw = doc.querySelector('script#initials-script')?.text ?? '';
    if (raw.isEmpty) return const [];
    // 站点自己的分页元数据（sim-dev 实测 ✓）：`lastPage=100` ✓ → 用它判"到底" ✓（不盲试第 101 页 ✗）
    final mLast = RegExp(r'"lastPage":\s*(\d+)').firstMatch(raw);
    final nLast = int.tryParse(mLast?.group(1) ?? '');
    if (nLast != null && nLast > 0) _xhShortsLast = nLast;
    final at = raw.indexOf('{');
    if (at < 0) return const [];
    final j = _xhJson(raw.substring(at).trim().replaceFirst(RegExp(r';\s*$'), ''));
    if (j == null) return const [];
    final lp = j['layoutPage'];
    final vlp = (lp is Map) ? lp['videoListProps'] : null;
    final arr = (vlp is Map) ? vlp['videoThumbProps'] : null;
    if (arr is! List) return const [];
    final out = <Article>[];
    final seen = <String>{};
    for (final it in arr) {
      if (it is! Map) continue;
      final url = _xhUn((it['pageURL'] ?? '').toString())
          .replaceFirst(RegExp(r'^https?://[^/]+'), '');
      final title = _xhUn((it['title'] ?? '').toString())
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (url.isEmpty || title.isEmpty || !seen.add(url)) continue;
      out.add(Article(
        title: title,
        url: url,
        cover: _xhUn((it['imageURL'] ?? it['thumbURL'] ?? '').toString()),
        meta: '',
        badge: '',
        // 短片是**竖版**（抖音/Reels 形态）→ 3:4、一行 2 个 ✓
        coverAspect: 3 / 4,
      ));
    }
    return out;
  }

  static int? _xhShortsLast; // 站点自己给的最后一页（`lastPage` ✓，sim-dev 实测 =100 ✓）

  /// 短片列表：**每页都走页面 JSON** ✓（`/shorts/newest` 与 `/shorts/newest/{N}` 是同一套结构 ✓）。
  /// ⚠️ 2026-10-03 定论（sim-dev 实测 ✅）：**`?page=N` 参数会被站点忽略** ✗ ——
  ///    `?page=1/2/3` 返回的 45 条**完全相同** ✗；站点自己在 JSON 里给了分页模板
  ///    `paginationProps.pageLinkTemplate = "…/shorts/newest/{#}"` ✓ → **真翻页是路径式** ✅
  ///    （`/shorts/newest/2`、`/3`：HTTP 200 ✓ · **45 条/页** ✓ · `lastPage=100` ✓ · 与第 1 页**零重叠** ✓）。
  /// ⚠️ 请求头只用 `_xhDesk`（桌面 UA ✓）：**绝不能带 `X-Requested-With: XMLHttpRequest`** ✗ ——
  ///    sim-dev 逐头隔离实测：带上它 → **404** ✗，去掉 → 200 ✓（那套头是给 `/api/` 的 ✗，那条路已整条撤掉 ✓）。
  /// ⚠️ **空批次返回空列表** ✓（让界面判"到底"✗）；**只有请求本身失败**才由 `_f.text` 抛错 ✓
  ///    （界面据此标"可重试" ✓ —— "到底"与"失败"分得开 ✓）。
  Future<List<Article>> _xhMoments(int page) async {
    if (page < 1) return const [];
    final last = _xhShortsLast;
    if (last != null && page > last) return const []; // 已知过最后一页 → 到底 ✓（不盲试第 101 页 ✗）
    if (page == 1) return _xhMomentsPage(_xhShortsPath);
    return _xhMomentsPage('$_xhShortsPath/$page');
  }

  /// 抓**一页**页面 JSON（第 1 页与第 N 页同一套 ✓）→ Article 列表
  Future<List<Article>> _xhMomentsPage(String path) async {
    final html = await _f.text(path, extraHeaders: _xhDesk);
    final out = _xhMomentsFromHtml(html);
    if (out.isEmpty) {
      // 第 1 页空 = 站点结构可能变了 ✗ → 抛错（界面当"可重试" ✓）
      if (path == _xhShortsPath) {
        // 不吞掉 ✓：界面会把原因显示出来（home_page 的三态渲染 ✓）
        throw Exception('短片页面解析出 0 条（页面结构可能变了）');
      }
      // 第 N 页空 = 站点这边没更多了 ✓ → 返回空（界面判"到底" ✓）
      return const [];
    }
    out.shuffle(_rand); // 与 sim 一致：每批打乱 ✓
    return out;
  }

  static Map<String, dynamic>? _xhJson(String s) {
    try {
      final v = jsonDecode(s);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// 详情。⚠️ 标题在 h1 里但被 Vue 注释包着（`<!--[--><!--[!-->真标题<!---->`）→ 先剥注释。
  /// 源：静态 HTML 里唯一的 `.m3u8`（5 档 144p~1080p；4K 站多 2160p）。
  /// **短片例外**：'/shorts/…' 只用站点默认那条（用户 2026-10-02："短片的话你就使用网站
  /// 默认给的分辨率就行"）→ 不展开档位、不做清晰度选择器。
  Future<ArticleDetail> _xhDetail(String url) async {
    final html = await _f.text(url, extraHeaders: _xhDesk);
    final doc = hp.parse(html);

    var title = '';
    final h1 = doc.querySelector('h1');
    if (h1 != null) {
      title = h1.text
          .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }
    if (title.isEmpty) {
      title = (doc.querySelector('title')?.text ?? '')
          .replaceAll(
              RegExp(r'\s*[|\-–]\s*xHamster\s*$', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    final durSec = int.tryParse(
            RegExp(r'"duration":(\d+)').firstMatch(html)?.group(1) ?? '') ??
        0;
    final og = doc.querySelector('meta[property="og:image"]');
    final poster = og?.attributes['content'] ?? '';

    final tags = <MapEntry<String, String>>[];
    for (final a in doc.querySelectorAll('a[href*="/categories/"]')) {
      final name = (a.attributes['aria-label'] ?? a.text)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final href = a.attributes['href'] ?? '';
      final parts = href.split('/categories/');
      final slug =
          parts.length > 1 ? parts[1].split('?').first.split('#').first : '';
      if (name.isEmpty || slug.isEmpty) continue;
      if (tags.any((t) => t.value == name)) continue;
      tags.add(MapEntry(slug, name));
    }

    // 源：页面里唯一那条 .m3u8
    // ⚠️ 字符类里**别放单引号**：这是 Dart 的原始字符串 r'...'，中间出现 ' 会被当成
    //    字符串结束、把余下部分拆成"非原始字符串"拼接 → `\s` 变非法转义、编译直接报错。
    //    （上面 madou 那处也是同样写法：`r'https?://[^"\s\\]+\.m3u8[^"\s\\]*'`。）
    // ⚠️ 2026-10-03 补（用户实机：短片点进去一直转圈 ✗，日志 videos=0 srcs=0 ✓）：
    // 短片页的源**常常不是 m3u8** ✗，而是页面 JSON 里的**直链 mp4**，且斜杠是**转义**的 ✓：
    // "h264":[{"url":"https:\/\/video7.xhcdn.com\/…\/480p.h264.mp4","quality":"480p"}]
    // 原来只跑 m3u8 正则 ✗ → 这类页面解析出 0 条 → 上层静默返回 → 无限转圈 ✓。
    final h264 = RegExp(r'"url":"(https?:\\?/\\?/[^"]+?\.mp4[^"]*)"[^}]*?"quality":"(\d{3,4})p"').allMatches(html);
    final byQ = <int, String>{};
    for (final hm in h264) {
      final q = int.tryParse(hm.group(2) ?? '') ?? 0;
      byQ.putIfAbsent(q, () => hm.group(1)!.replaceAll(r'\/', '/'));
    }
    final mp4 = byQ.isEmpty
        ? <String>[]
        : ((byQ.keys.toList()..sort((a, b) => b.compareTo(a)))
            .map((k) => byQ[k]!)
            .toList());
    final m = RegExp(r'https://[^"\s\\]+\.m3u8[^"\s\\]*').firstMatch(html);
    var srcs = mp4; // ⚠️ 直链 mp4（短片页常见）优先 ✓；为空才走下面的 m3u8 ✓
    if (srcs.isEmpty && m != null) { // ← 直链 mp4 优先，没命中才回落 ✓
      final master = m.group(0)!;
      if (url.startsWith('/shorts/')) {
        srcs = [master]; // 短片：站点默认那条，交给播放器自己选档
      } else {
        final variants = await _f.hlsVariants(master);
        srcs = (variants != null && variants.isNotEmpty) ? variants : [master];
      }
    }

    // 相关推荐：DOM 里没有卡片，数据在页面 JSON 里（跟视频卡同一套结构）
    final related =
        _xhCards(html).where((a) => !a.url.startsWith('/shorts/')).toList();

    return ArticleDetail(
      title: title,
      time: '',
      // ⚠️ categories 是必需参数（models.dart 里是 required this.categories）——
      // 2026-10-02 第一次上 CI 就漏了它，报 Required named parameter must be provided ✗。
      // 其余 15 处 ArticleDetail 调用也都传 const []；本站分类信息走 tags（slug→名称），
      // 这个字段留空即可。
      categories: const [],
      images: poster.isEmpty ? const [] : [poster],
      intro: '',
      videos: srcs.isEmpty
          ? const []
          : [ArticleVideo(label: '视频', ordinal: 1, sources: srcs)],
      tags: tags,
      related: related.length > 20 ? related.sublist(0, 20) : related,
      duration: _xhClock(durSec),
      seriesPrefix: '',
    );
  }
}

// ===== 本站专属清单（2026-10-03 从 lib/sites.dart 下放 ✓；循环 import 允许 ✓）=====

const List<SiteTab> xhStarNav = [
  SiteTab('/pornstars', '色情明星'),
  SiteTab('/pornstars/top/us', '在US受歡迎'),
  SiteTab('/pornstars/all/countries', '按國家'),
];

const List<SiteTab> xhStarCats = [
  SiteTab('/pornstars/all/categories/creampie', '中出'),
  SiteTab('/pornstars/all/categories/asian', '亞洲'),
  SiteTab('/pornstars/all/categories/dildo', '假雞巴'),
  SiteTab('/pornstars/all/categories/cartoon', '卡通'),
  SiteTab('/pornstars/all/categories/blowjob', '口交'),
  SiteTab('/pornstars/all/categories/celebrity', '名人'),
  SiteTab('/pornstars/all/categories/bbw', '大美人'),
  SiteTab('/pornstars/all/categories/femdom', '女主導'),
  SiteTab('/pornstars/all/categories/lesbian', '女同性戀'),
  SiteTab('/pornstars/all/categories/milf', '媽媽我想做愛'),
  SiteTab('/pornstars/all/categories/cumshot', '射精畫面'),
  SiteTab('/pornstars/all/categories/vintage', '復古'),
  SiteTab('/pornstars/all/categories/german', '德國'),
  SiteTab('/pornstars/all/categories/mature', '成熟'),
  SiteTab('/pornstars/all/categories/cuckold', '戴綠帽'),
  SiteTab('/pornstars/all/categories/handjob', '手淫'),
  SiteTab('/pornstars/all/categories/massage', '按摩'),
  SiteTab('/pornstars/all/categories/swingers', '換妻者'),
  SiteTab('/pornstars/all/categories/japanese', '日本'),
  SiteTab('/pornstars/all/categories/amateur', '業餘'),
  SiteTab('/pornstars/all/categories/hairy', '毛茸茸'),
  SiteTab('/pornstars/all/categories/beach', '沙灘'),
  SiteTab('/pornstars/all/categories/french', '法式'),
  SiteTab('/pornstars/all/categories/squirting', '潮吹'),
  SiteTab('/pornstars/all/categories/hardcore', '硬核'),
  SiteTab('/pornstars/all/categories/cfnm', '穿衣女與裸體男'),
  SiteTab('/pornstars/all/categories/bdsm', '綁縛與調教'),
  SiteTab('/pornstars/all/categories/webcam', '網絡攝像頭'),
  SiteTab('/pornstars/all/categories/granny', '老奶奶'),
  SiteTab('/pornstars/all/categories/old-young', '老少配'),
  SiteTab('/pornstars/all/categories/anal', '肛交'),
  SiteTab('/pornstars/all/categories/footjob', '腳交'),
  SiteTab('/pornstars/all/categories/british', '英國佬'),
  SiteTab('/pornstars/all/categories/hentai', '變態'),
  SiteTab('/pornstars/all/categories/interracial', '跨種族'),
  SiteTab('/pornstars/all/categories/gangbang', '輪姦'),
  SiteTab('/pornstars/all/categories/casting', '選角'),
  SiteTab('/pornstars/all/categories/arab', '阿拉伯風情'),
  SiteTab('/pornstars/all/categories/bisexual', '雙性戀'),
  SiteTab('/pornstars/all/categories/teen', '青少年'),
];
final List<MapEntry<String, List<SiteTab>>> xhCatGroups = [
  const MapEntry("製作", [
    SiteTab("/categories/3d", "3D"),
    SiteTab("/categories/pmv", "PMV"),
    SiteTab("/categories/show", "Show"),
    SiteTab("/categories/pov", "主觀視角"),
    SiteTab("/categories/interactive", "互動式"),
    SiteTab("/categories/cartoon", "卡通"),
    SiteTab("/categories/behind-the-scenes", "幕後花絮"),
    SiteTab("/categories/vintage", "復古"),
    SiteTab("/categories/retro", "復古"),
    SiteTab("/categories/erotica", "情色文學"),
    SiteTab("/categories/funny", "搞笑"),
    SiteTab("/categories/story", "故事"),
    SiteTab("/categories/jav", "日本AV"),
    SiteTab("/categories/uncensored", "未經審查"),
    SiteTab("/categories/amateur", "業餘"),
    SiteTab("/categories/caption", "標題"),
    SiteTab("/categories/close-up", "特寫"),
    SiteTab("/categories/gonzo", "第一人稱視角"),
    SiteTab("/categories/compilation", "精選集"),
    SiteTab("/categories/webcam", "網絡攝像頭"),
    SiteTab("/categories/homemade", "自製"),
    SiteTab("/categories/pornstar", "色情明星"),
    SiteTab("/categories/hentai", "變態"),
    SiteTab("/categories/softcore", "軟性色情"),
  ]),
  const MapEntry("行動", [
    SiteTab("/categories/creampie", "中出"),
    SiteTab("/categories/scissoring", "交叉剪刀"),
    SiteTab("/categories/cumswap", "交換精液"),
    SiteTab("/categories/missionary", "傳教士體位"),
    SiteTab("/categories/69", "六九"),
    SiteTab("/categories/shaving", "刮毛"),
    SiteTab("/categories/prostate-massage", "前列腺按摩"),
    SiteTab("/categories/foreplay", "前戲"),
    SiteTab("/categories/cum-in-mouth", "口中射精"),
    SiteTab("/categories/blowjob", "口交"),
    SiteTab("/categories/face-fuck", "口交插入"),
    SiteTab("/categories/eating-pussy", "吃陰戶"),
    SiteTab("/categories/cum-swallowing", "吞精"),
    SiteTab("/categories/moaning", "呻吟"),
    SiteTab("/categories/blowbang", "多人吹"),
    SiteTab("/categories/bukkake", "多人顏射"),
    SiteTab("/categories/gaping", "大開口"),
    SiteTab("/categories/cowgirl", "女上位"),
    SiteTab("/categories/female-masturbation", "女性自慰"),
    SiteTab("/categories/titty-fucking", "奶交"),
    SiteTab("/categories/cum-on-tits", "射在胸上"),
    SiteTab("/categories/cumshot", "射精畫面"),
    SiteTab("/categories/screaming", "尖叫"),
    SiteTab("/categories/humping", "幹砲"),
    SiteTab("/categories/happy-ending", "快樂結局"),
    SiteTab("/categories/fingering", "手指愛撫"),
    SiteTab("/categories/handjob", "手淫"),
    SiteTab("/categories/twerking", "扭臀舞"),
    SiteTab("/categories/fisting", "拳交"),
    SiteTab("/categories/massage", "按摩"),
    SiteTab("/categories/pegging", "掛鉤"),
    SiteTab("/categories/extreme-insertion", "極端插入"),
    SiteTab("/categories/brutal-sex", "殘酷性愛"),
    SiteTab("/categories/deep-throat", "深喉"),
    SiteTab("/categories/squirting", "潮吹"),
    SiteTab("/categories/rough-sex", "激烈性愛"),
    SiteTab("/categories/rough-anal", "激烈肛交"),
    SiteTab("/categories/doggy-style", "狗爬式"),
    SiteTab("/categories/yoga", "瑜伽"),
    SiteTab("/categories/anal", "肛交"),
    SiteTab("/categories/ass-to-mouth", "肛口交"),
    SiteTab("/categories/anal-masturbation", "肛門自慰"),
    SiteTab("/categories/striptease", "脫衣舞"),
    SiteTab("/categories/cum-on-feet", "腳上射精"),
    SiteTab("/categories/footjob", "腳交"),
    SiteTab("/categories/facesitting", "臉坐"),
    SiteTab("/categories/ass-licking", "舔屁股"),
    SiteTab("/categories/rimjob", "舔肛"),
    SiteTab("/categories/cunnilingus", "舔陰"),
    SiteTab("/categories/kissing", "親吻"),
    SiteTab("/categories/edging", "邊緣控制"),
    SiteTab("/categories/dry-humping", "隔衣磨蹭"),
    SiteTab("/categories/double-penetration", "雙重插入"),
    SiteTab("/categories/flashing", "露鳥"),
    SiteTab("/categories/facial", "顏射"),
    SiteTab("/categories/riding", "騎乘"),
    SiteTab("/categories/dirty-talk", "髒話調情"),
    SiteTab("/categories/orgasm", "高潮"),
  ]),
  const MapEntry("戀物癖", [
    SiteTab("/categories/human-furniture", "人體家具"),
    SiteTab("/categories/human-ashtray", "人體菸灰缸"),
    SiteTab("/categories/condom", "保險套"),
    SiteTab("/categories/mouth-fetish", "口腔癖好"),
    SiteTab("/categories/cei", "吃精指南"),
    SiteTab("/categories/spitting", "吐口水"),
    SiteTab("/categories/predicament-bondage", "困境束縛"),
    SiteTab("/categories/weird", "奇怪"),
    SiteTab("/categories/femdom", "女主導"),
    SiteTab("/categories/lezdom", "女同支配"),
    SiteTab("/categories/sissy", "娘炮"),
    SiteTab("/categories/gyno-fetish", "婦科癖好"),
    SiteTab("/categories/pet-play", "寵物扮演"),
    SiteTab("/categories/small-penis-humiliation", "小陰莖羞辱"),
    SiteTab("/categories/small-penis-encouragement", "小陰莖鼓勵"),
    SiteTab("/categories/kinky", "性變態"),
    SiteTab("/categories/punishment", "懲罰"),
    SiteTab("/categories/suspension-bondage", "懸吊束縛"),
    SiteTab("/categories/fetish", "戀物癖"),
    SiteTab("/categories/dogging", "戶外群交"),
    SiteTab("/categories/hand-fetish", "手癖"),
    SiteTab("/categories/spanking", "打屁股"),
    SiteTab("/categories/futanari", "扶她"),
    SiteTab("/categories/oiled", "抹油"),
    SiteTab("/categories/smoking", "抽菸性愛"),
    SiteTab("/categories/wedgie", "拉內褲"),
    SiteTab("/categories/tickling", "搔癢"),
    SiteTab("/categories/wrestling", "摔跤"),
    SiteTab("/categories/pissing", "撒尿"),
    SiteTab("/categories/domination", "支配"),
    SiteTab("/categories/farting", "放屁"),
    SiteTab("/categories/balloon", "氣球"),
    SiteTab("/categories/lactating", "泌乳"),
    SiteTab("/categories/wet-messy", "濕滑混亂"),
    SiteTab("/categories/milk", "牛奶"),
    SiteTab("/categories/raceplay", "種族扮演"),
    SiteTab("/categories/smothering", "窒息玩法"),
    SiteTab("/categories/mind-control", "精神控制"),
    SiteTab("/categories/hogtied", "綁成豬蹄"),
    SiteTab("/categories/bdsm", "綁縛與調教"),
    SiteTab("/categories/bondage", "綑綁"),
    SiteTab("/categories/shibari", "繩縛"),
    SiteTab("/categories/humiliation", "羞辱"),
    SiteTab("/categories/armpit", "腋下"),
    SiteTab("/categories/foot-worship", "腳部崇拜"),
    SiteTab("/categories/belly-fetish", "腹部癖好"),
    SiteTab("/categories/tape-bondage", "膠帶束縛"),
    SiteTab("/categories/face-fetish", "臉部癖好"),
    SiteTab("/categories/wax-play", "蠟燭調教"),
    SiteTab("/categories/tied-up", "被綁起來"),
    SiteTab("/categories/chastity", "貞操"),
    SiteTab("/categories/foot-fetish", "足控"),
    SiteTab("/categories/pedal-pumping", "踏板泵送"),
    SiteTab("/categories/ballbusting", "踢蛋"),
    SiteTab("/categories/trampling", "踩踏"),
    SiteTab("/categories/body-paint", "身體彩繪"),
    SiteTab("/categories/ahegao", "阿嘿顏"),
    SiteTab("/categories/cbt", "雞巴與蛋蛋折磨"),
    SiteTab("/categories/estim", "電刺激"),
    SiteTab("/categories/whipping", "鞭打"),
    SiteTab("/categories/submissive", "順從者"),
    SiteTab("/categories/food", "食物"),
    SiteTab("/categories/gokkun", "飲精"),
    SiteTab("/categories/body-hair-fetish", "體毛癖"),
    SiteTab("/categories/orgasm-control", "高潮控制"),
  ]),
  const MapEntry("指示", [
    SiteTab("/categories/lesbian", "女同性戀"),
    SiteTab("/categories/bisexual", "雙性戀"),
  ]),
  const MapEntry("年齡", [
    SiteTab("/categories/18-year-old", "18歲"),
    SiteTab("/categories/milf", "媽媽我想做愛"),
    SiteTab("/categories/babe", "寶貝"),
    SiteTab("/categories/mature", "成熟"),
    SiteTab("/categories/cougar", "熟女"),
    SiteTab("/categories/gilf", "熟女祖母"),
    SiteTab("/categories/granny", "老奶奶"),
    SiteTab("/categories/old-young", "老少配"),
    SiteTab("/categories/old-man", "老頭子"),
    SiteTab("/categories/teen", "青少年"),
  ]),
  const MapEntry("種族", [
    SiteTab("/categories/amwf", "AMWF"),
    SiteTab("/categories/asian", "亞洲"),
    SiteTab("/categories/desi", "南亞裔"),
    SiteTab("/categories/mzansi", "南非"),
    SiteTab("/categories/latina", "拉丁裔"),
    SiteTab("/categories/european", "歐洲"),
    SiteTab("/categories/jewish", "猶太"),
    SiteTab("/categories/american", "美國佬"),
    SiteTab("/categories/interracial", "跨種族"),
    SiteTab("/categories/arab", "阿拉伯風情"),
    SiteTab("/categories/african", "非洲"),
    SiteTab("/categories/black", "黑人"),
  ]),
  const MapEntry("身體", [
    SiteTab("/categories/bwc", "BWC"),
    SiteTab("/categories/saggy-tits", "下垂奶"),
    SiteTab("/categories/nipples", "乳頭"),
    SiteTab("/categories/midget", "侏儒"),
    SiteTab("/categories/fake-tits", "假奶"),
    SiteTab("/categories/tattoo", "刺青"),
    SiteTab("/categories/cute", "可愛"),
    SiteTab("/categories/big-natural-tits", "大天然奶"),
    SiteTab("/categories/big-tits", "大奶"),
    SiteTab("/categories/big-nipples", "大奶頭"),
    SiteTab("/categories/big-ass", "大屁股"),
    SiteTab("/categories/pawg", "大屁股白妞"),
    SiteTab("/categories/big-cock", "大屌"),
    SiteTab("/categories/bbw", "大美人"),
    SiteTab("/categories/big-clit", "大陰蒂"),
    SiteTab("/categories/bbc", "大黑屌"),
    SiteTab("/categories/giantess", "女巨人"),
    SiteTab("/categories/fbb", "女性健美者"),
    SiteTab("/categories/tits", "奶子"),
    SiteTab("/categories/petite", "嬌小"),
    SiteTab("/categories/perfect-body", "完美身材"),
    SiteTab("/categories/pussy", "小穴"),
    SiteTab("/categories/small-tits", "小胸"),
    SiteTab("/categories/ass", "屁股"),
    SiteTab("/categories/giant", "巨型"),
    SiteTab("/categories/monster-cock", "巨屌"),
    SiteTab("/categories/pregnant", "懷孕"),
    SiteTab("/categories/amputee", "截肢者"),
    SiteTab("/categories/tan-girl", "曬黑妹"),
    SiteTab("/categories/hairy", "毛茸茸"),
    SiteTab("/categories/exotic", "異國風情"),
    SiteTab("/categories/skinny", "瘦弱"),
    SiteTab("/categories/piercing", "穿孔"),
    SiteTab("/categories/tight-pussy", "緊緻小穴"),
    SiteTab("/categories/beauty", "美女"),
    SiteTab("/categories/legs", "美腿"),
    SiteTab("/categories/muscular-woman", "肌肉女"),
    SiteTab("/categories/puffy-nipples", "膨脹乳頭"),
    SiteTab("/categories/nude", "裸體"),
    SiteTab("/categories/chubby", "豐滿"),
    SiteTab("/categories/ssbbw", "超大碼性感胖女人"),
    SiteTab("/categories/clit", "陰蒂"),
    SiteTab("/categories/hermaphrodite", "雌雄同體"),
    SiteTab("/categories/flexible", "靈活"),
    SiteTab("/categories/cameltoe", "駱駝蹄"),
  ]),
  const MapEntry("頭髮", [
    SiteTab("/categories/colored-hair", "彩色頭髮"),
    SiteTab("/categories/brunette", "棕髮女郎"),
    SiteTab("/categories/short-hair", "短髮"),
    SiteTab("/categories/redhead", "紅髮妹"),
    SiteTab("/categories/blonde", "金髮"),
    SiteTab("/categories/long-hair", "長髮"),
  ]),
  const MapEntry("人數", [
    SiteTab("/categories/threesome", "三人行"),
    SiteTab("/categories/foursome", "四人行"),
    SiteTab("/categories/couple", "情侶"),
    SiteTab("/categories/orgy", "狂歡"),
    SiteTab("/categories/solo", "獨自"),
    SiteTab("/categories/group-sex", "群交"),
    SiteTab("/categories/gangbang", "輪姦"),
  ]),
  const MapEntry("性玩具", [
    SiteTab("/categories/strapon", "假陽具"),
    SiteTab("/categories/dildo", "假雞巴"),
    SiteTab("/categories/ball-gagged", "口球束縛"),
    SiteTab("/categories/fucking-machine", "性愛機器"),
    SiteTab("/categories/sex-toy", "性玩具"),
    SiteTab("/categories/enema", "灌腸"),
    SiteTab("/categories/butt-plug", "肛塞"),
    SiteTab("/categories/anal-beads", "肛門珠"),
    SiteTab("/categories/blindfolded", "蒙眼"),
    SiteTab("/categories/sybian", "西比亞"),
    SiteTab("/categories/pussy-pump", "陰部吸泵"),
    SiteTab("/categories/double-dildo", "雙頭假陽具"),
    SiteTab("/categories/vibrator", "震動棒"),
    SiteTab("/categories/hitachi", "震動玩具"),
  ]),
  const MapEntry("服飾", [
    SiteTab("/categories/thong", "丁字褲"),
    SiteTab("/categories/latex", "乳膠"),
    SiteTab("/categories/panties", "內褲"),
    SiteTab("/categories/bodystocking", "全身網襪"),
    SiteTab("/categories/uniform", "制服"),
    SiteTab("/categories/nylon", "尼龍"),
    SiteTab("/categories/lingerie", "性感內衣"),
    SiteTab("/categories/gloves", "手套"),
    SiteTab("/categories/school-uniform", "校服"),
    SiteTab("/categories/bikini", "比基尼"),
    SiteTab("/categories/jeans", "牛仔褲"),
    SiteTab("/categories/leather", "皮革"),
    SiteTab("/categories/glasses", "眼鏡"),
    SiteTab("/categories/stockings", "絲襪"),
    SiteTab("/categories/fishnet", "網襪"),
    SiteTab("/categories/leggings", "緊身褲"),
    SiteTab("/categories/bra", "胸罩"),
    SiteTab("/categories/spandex", "萊卡緊身衣"),
    SiteTab("/categories/masked", "蒙面"),
    SiteTab("/categories/skirt", "裙子"),
    SiteTab("/categories/socks", "襪子"),
    SiteTab("/categories/pantyhose", "連褲襪"),
    SiteTab("/categories/high-heels", "高跟鞋"),
  ]),
  const MapEntry("設想", [
    SiteTab("/categories/asmr", "ASMR"),
    SiteTab("/categories/medieval", "中世紀"),
    SiteTab("/categories/agent", "代理人"),
    SiteTab("/categories/escort", "伴遊"),
    SiteTab("/categories/babysitter", "保姆"),
    SiteTab("/categories/nun", "修女"),
    SiteTab("/categories/cheating", "偷情"),
    SiteTab("/categories/upskirt", "偷拍裙底"),
    SiteTab("/categories/voyeur", "偷窺者"),
    SiteTab("/categories/princess", "公主"),
    SiteTab("/categories/public-sex", "公開性愛"),
    SiteTab("/categories/public-nudity", "公開裸露"),
    SiteTab("/categories/stuck", "卡住"),
    SiteTab("/categories/reverse-gangbang", "反向群交"),
    SiteTab("/categories/celebrity", "名人"),
    SiteTab("/categories/vampire", "吸血鬼"),
    SiteTab("/categories/gothic", "哥特"),
    SiteTab("/categories/cheerleader", "啦啦隊女孩"),
    SiteTab("/categories/alien", "外星人"),
    SiteTab("/categories/coed", "大學男女混宿"),
    SiteTab("/categories/mistress", "女主人"),
    SiteTab("/categories/maid", "女僕"),
    SiteTab("/categories/catfight", "女子打架"),
    SiteTab("/categories/girlfriend", "女朋友"),
    SiteTab("/categories/slave", "奴隸"),
    SiteTab("/categories/wife-sharing", "妻子共享"),
    SiteTab("/categories/doll", "娃娃"),
    SiteTab("/categories/wedding", "婚禮"),
    SiteTab("/categories/mom", "媽咪"),
    SiteTab("/categories/student", "學生"),
    SiteTab("/categories/housewife", "家庭主婦"),
    SiteTab("/categories/clown", "小丑"),
    SiteTab("/categories/bunny", "小兔子"),
    SiteTab("/categories/fantasy", "幻想"),
    SiteTab("/categories/cook", "廚師"),
    SiteTab("/categories/sex-instruction", "性愛指導"),
    SiteTab("/categories/nympho", "性癮者"),
    SiteTab("/categories/monster", "怪物"),
    SiteTab("/categories/horror", "恐怖"),
    SiteTab("/categories/valentines-day", "情人節"),
    SiteTab("/categories/emo", "情緒搖滾風"),
    SiteTab("/categories/parody", "惡搞"),
    SiteTab("/categories/cuckold", "戴綠帽"),
    SiteTab("/categories/fighting", "打架"),
    SiteTab("/categories/wife-swap", "換妻"),
    SiteTab("/categories/swingers", "換妻者"),
    SiteTab("/categories/pick-up", "搭訕"),
    SiteTab("/categories/morning", "早晨"),
    SiteTab("/categories/time-stop", "時間靜止"),
    SiteTab("/categories/nerd", "書呆子"),
    SiteTab("/categories/waitress", "服務生"),
    SiteTab("/categories/glory-hole", "榮耀洞"),
    SiteTab("/categories/plumber", "水管工"),
    SiteTab("/categories/party", "派對"),
    SiteTab("/categories/romantic", "浪漫"),
    SiteTab("/categories/naughty", "淘氣"),
    SiteTab("/categories/comic", "漫畫"),
    SiteTab("/categories/passionate", "熱情"),
    SiteTab("/categories/daddy", "爹地"),
    SiteTab("/categories/birthday", "生日"),
    SiteTab("/categories/truth-or-dare", "真心話大冒險"),
    SiteTab("/categories/hardcore", "硬核"),
    SiteTab("/categories/taboo", "禁忌"),
    SiteTab("/categories/secretary", "秘書"),
    SiteTab("/categories/cfnm", "穿衣女與裸體男"),
    SiteTab("/categories/cmnf", "穿衣男與裸體女"),
    SiteTab("/categories/first-time", "第一次"),
    SiteTab("/categories/e-girl", "網紅妹"),
    SiteTab("/categories/boss", "老大"),
    SiteTab("/categories/wife", "老婆"),
    SiteTab("/categories/teacher", "老師"),
    SiteTab("/categories/xmas", "聖誕節"),
    SiteTab("/categories/joi", "自慰指導"),
    SiteTab("/categories/halloween", "萬聖節"),
    SiteTab("/categories/virgin", "處女"),
    SiteTab("/categories/nudist", "裸體主義者"),
    SiteTab("/categories/cosplay", "角色扮演"),
    SiteTab("/categories/role-play", "角色扮演"),
    SiteTab("/categories/audition", "試鏡"),
    SiteTab("/categories/seduce", "誘惑"),
    SiteTab("/categories/police", "警察"),
    SiteTab("/categories/nurse", "護士"),
    SiteTab("/categories/ghetto", "貧民窟"),
    SiteTab("/categories/superhero", "超人"),
    SiteTab("/categories/dance", "跳舞"),
    SiteTab("/categories/body-swap", "身體交換"),
    SiteTab("/categories/military", "軍事角色扮演"),
    SiteTab("/categories/baddie", "辣妹"),
    SiteTab("/categories/game", "遊戲"),
    SiteTab("/categories/gamer-girl", "遊戲妹"),
    SiteTab("/categories/sport", "運動"),
    SiteTab("/categories/casting", "選角"),
    SiteTab("/categories/neighbor", "鄰居"),
    SiteTab("/categories/doctor", "醫生"),
    SiteTab("/categories/medical", "醫療"),
    SiteTab("/categories/stranger", "陌生人"),
    SiteTab("/categories/twins", "雙胞胎"),
    SiteTab("/categories/interview", "面試"),
    SiteTab("/categories/surprise", "驚喜"),
  ]),
  const MapEntry("位置", [
    SiteTab("/categories/sauna", "三溫暖"),
    SiteTab("/categories/fitness", "健身"),
    SiteTab("/categories/gym", "健身房"),
    SiteTab("/categories/jungle", "叢林"),
    SiteTab("/categories/college", "大學"),
    SiteTab("/categories/bus", "巴士"),
    SiteTab("/categories/toilet", "廁所"),
    SiteTab("/categories/kitchen", "廚房"),
    SiteTab("/categories/outdoor", "戶外"),
    SiteTab("/categories/hotel", "旅館"),
    SiteTab("/categories/underwater", "水下"),
    SiteTab("/categories/car", "汽車"),
    SiteTab("/categories/beach", "沙灘"),
    SiteTab("/categories/pool", "泳池"),
    SiteTab("/categories/bathroom", "浴室"),
    SiteTab("/categories/shower", "淋浴"),
    SiteTab("/categories/train", "火車"),
    SiteTab("/categories/prison", "監獄"),
    SiteTab("/categories/taxi", "計程車"),
    SiteTab("/categories/office", "辦公室"),
    SiteTab("/categories/farm", "農場"),
    SiteTab("/categories/village", "鄉村"),
    SiteTab("/categories/hospital", "醫院"),
  ]),
];

const List<SiteTab> xhCats = [
  // ── 製作（24 个）
  SiteTab('/categories/3d', '3D'),
  SiteTab('/categories/pmv', 'PMV'),
  SiteTab('/categories/show', 'Show'),
  SiteTab('/categories/pov', '主觀視角'),
  SiteTab('/categories/interactive', '互動式'),
  SiteTab('/categories/cartoon', '卡通'),
  SiteTab('/categories/behind-the-scenes', '幕後花絮'),
  SiteTab('/categories/vintage', '復古'),
  SiteTab('/categories/retro', '復古'),
  SiteTab('/categories/erotica', '情色文學'),
  SiteTab('/categories/funny', '搞笑'),
  SiteTab('/categories/story', '故事'),
  SiteTab('/categories/jav', '日本AV'),
  SiteTab('/categories/uncensored', '未經審查'),
  SiteTab('/categories/amateur', '業餘'),
  SiteTab('/categories/caption', '標題'),
  SiteTab('/categories/close-up', '特寫'),
  SiteTab('/categories/gonzo', '第一人稱視角'),
  SiteTab('/categories/compilation', '精選集'),
  SiteTab('/categories/webcam', '網絡攝像頭'),
  SiteTab('/categories/homemade', '自製'),
  SiteTab('/categories/pornstar', '色情明星'),
  SiteTab('/categories/hentai', '變態'),
  SiteTab('/categories/softcore', '軟性色情'),
  // ── 行動（58 个）
  SiteTab('/categories/creampie', '中出'),
  SiteTab('/categories/scissoring', '交叉剪刀'),
  SiteTab('/categories/cumswap', '交換精液'),
  SiteTab('/categories/missionary', '傳教士體位'),
  SiteTab('/categories/69', '六九'),
  SiteTab('/categories/shaving', '刮毛'),
  SiteTab('/categories/prostate-massage', '前列腺按摩'),
  SiteTab('/categories/foreplay', '前戲'),
  SiteTab('/categories/cum-in-mouth', '口中射精'),
  SiteTab('/categories/blowjob', '口交'),
  SiteTab('/categories/face-fuck', '口交插入'),
  SiteTab('/categories/eating-pussy', '吃陰戶'),
  SiteTab('/categories/cum-swallowing', '吞精'),
  SiteTab('/categories/moaning', '呻吟'),
  SiteTab('/categories/blowbang', '多人吹'),
  SiteTab('/categories/bukkake', '多人顏射'),
  SiteTab('/categories/gaping', '大開口'),
  SiteTab('/categories/cowgirl', '女上位'),
  SiteTab('/categories/female-masturbation', '女性自慰'),
  SiteTab('/categories/titty-fucking', '奶交'),
  SiteTab('/categories/cum-on-tits', '射在胸上'),
  SiteTab('/categories/cumshot', '射精畫面'),
  SiteTab('/categories/screaming', '尖叫'),
  SiteTab('/categories/humping', '幹砲'),
  SiteTab('/categories/happy-ending', '快樂結局'),
  SiteTab('/categories/fingering', '手指愛撫'),
  SiteTab('/categories/handjob', '手淫'),
  SiteTab('/categories/twerking', '扭臀舞'),
  SiteTab('/categories/fisting', '拳交'),
  SiteTab('/categories/massage', '按摩'),
  SiteTab('/categories/pegging', '掛鉤'),
  SiteTab('/categories/extreme-insertion', '極端插入'),
  SiteTab('/categories/brutal-sex', '殘酷性愛'),
  SiteTab('/categories/deep-throat', '深喉'),
  SiteTab('/categories/squirting', '潮吹'),
  SiteTab('/categories/rough-sex', '激烈性愛'),
  SiteTab('/categories/rough-anal', '激烈肛交'),
  SiteTab('/categories/doggy-style', '狗爬式'),
  SiteTab('/categories/yoga', '瑜伽'),
  SiteTab('/categories/anal', '肛交'),
  SiteTab('/categories/ass-to-mouth', '肛口交'),
  SiteTab('/categories/anal-masturbation', '肛門自慰'),
  SiteTab('/categories/striptease', '脫衣舞'),
  SiteTab('/categories/cum-on-feet', '腳上射精'),
  SiteTab('/categories/footjob', '腳交'),
  SiteTab('/categories/facesitting', '臉坐'),
  SiteTab('/categories/ass-licking', '舔屁股'),
  SiteTab('/categories/rimjob', '舔肛'),
  SiteTab('/categories/cunnilingus', '舔陰'),
  SiteTab('/categories/kissing', '親吻'),
  SiteTab('/categories/edging', '邊緣控制'),
  SiteTab('/categories/dry-humping', '隔衣磨蹭'),
  SiteTab('/categories/double-penetration', '雙重插入'),
  SiteTab('/categories/flashing', '露鳥'),
  SiteTab('/categories/facial', '顏射'),
  SiteTab('/categories/riding', '騎乘'),
  SiteTab('/categories/dirty-talk', '髒話調情'),
  SiteTab('/categories/orgasm', '高潮'),
  // ── 戀物癖（65 个）
  SiteTab('/categories/human-furniture', '人體家具'),
  SiteTab('/categories/human-ashtray', '人體菸灰缸'),
  SiteTab('/categories/condom', '保險套'),
  SiteTab('/categories/mouth-fetish', '口腔癖好'),
  SiteTab('/categories/cei', '吃精指南'),
  SiteTab('/categories/spitting', '吐口水'),
  SiteTab('/categories/predicament-bondage', '困境束縛'),
  SiteTab('/categories/weird', '奇怪'),
  SiteTab('/categories/femdom', '女主導'),
  SiteTab('/categories/lezdom', '女同支配'),
  SiteTab('/categories/sissy', '娘炮'),
  SiteTab('/categories/gyno-fetish', '婦科癖好'),
  SiteTab('/categories/pet-play', '寵物扮演'),
  SiteTab('/categories/small-penis-humiliation', '小陰莖羞辱'),
  SiteTab('/categories/small-penis-encouragement', '小陰莖鼓勵'),
  SiteTab('/categories/kinky', '性變態'),
  SiteTab('/categories/punishment', '懲罰'),
  SiteTab('/categories/suspension-bondage', '懸吊束縛'),
  SiteTab('/categories/fetish', '戀物癖'),
  SiteTab('/categories/dogging', '戶外群交'),
  SiteTab('/categories/hand-fetish', '手癖'),
  SiteTab('/categories/spanking', '打屁股'),
  SiteTab('/categories/futanari', '扶她'),
  SiteTab('/categories/oiled', '抹油'),
  SiteTab('/categories/smoking', '抽菸性愛'),
  SiteTab('/categories/wedgie', '拉內褲'),
  SiteTab('/categories/tickling', '搔癢'),
  SiteTab('/categories/wrestling', '摔跤'),
  SiteTab('/categories/pissing', '撒尿'),
  SiteTab('/categories/domination', '支配'),
  SiteTab('/categories/farting', '放屁'),
  SiteTab('/categories/balloon', '氣球'),
  SiteTab('/categories/lactating', '泌乳'),
  SiteTab('/categories/wet-messy', '濕滑混亂'),
  SiteTab('/categories/milk', '牛奶'),
  SiteTab('/categories/raceplay', '種族扮演'),
  SiteTab('/categories/smothering', '窒息玩法'),
  SiteTab('/categories/mind-control', '精神控制'),
  SiteTab('/categories/hogtied', '綁成豬蹄'),
  SiteTab('/categories/bdsm', '綁縛與調教'),
  SiteTab('/categories/bondage', '綑綁'),
  SiteTab('/categories/shibari', '繩縛'),
  SiteTab('/categories/humiliation', '羞辱'),
  SiteTab('/categories/armpit', '腋下'),
  SiteTab('/categories/foot-worship', '腳部崇拜'),
  SiteTab('/categories/belly-fetish', '腹部癖好'),
  SiteTab('/categories/tape-bondage', '膠帶束縛'),
  SiteTab('/categories/face-fetish', '臉部癖好'),
  SiteTab('/categories/wax-play', '蠟燭調教'),
  SiteTab('/categories/tied-up', '被綁起來'),
  SiteTab('/categories/chastity', '貞操'),
  SiteTab('/categories/foot-fetish', '足控'),
  SiteTab('/categories/pedal-pumping', '踏板泵送'),
  SiteTab('/categories/ballbusting', '踢蛋'),
  SiteTab('/categories/trampling', '踩踏'),
  SiteTab('/categories/body-paint', '身體彩繪'),
  SiteTab('/categories/ahegao', '阿嘿顏'),
  SiteTab('/categories/cbt', '雞巴與蛋蛋折磨'),
  SiteTab('/categories/estim', '電刺激'),
  SiteTab('/categories/whipping', '鞭打'),
  SiteTab('/categories/submissive', '順從者'),
  SiteTab('/categories/food', '食物'),
  SiteTab('/categories/gokkun', '飲精'),
  SiteTab('/categories/body-hair-fetish', '體毛癖'),
  SiteTab('/categories/orgasm-control', '高潮控制'),
  // ── 指示（2 个）
  SiteTab('/categories/lesbian', '女同性戀'),
  SiteTab('/categories/bisexual', '雙性戀'),
  // ── 年齡（10 个）
  SiteTab('/categories/18-year-old', '18歲'),
  SiteTab('/categories/milf', '媽媽我想做愛'),
  SiteTab('/categories/babe', '寶貝'),
  SiteTab('/categories/mature', '成熟'),
  SiteTab('/categories/cougar', '熟女'),
  SiteTab('/categories/gilf', '熟女祖母'),
  SiteTab('/categories/granny', '老奶奶'),
  SiteTab('/categories/old-young', '老少配'),
  SiteTab('/categories/old-man', '老頭子'),
  SiteTab('/categories/teen', '青少年'),
  // ── 種族（12 个）
  SiteTab('/categories/amwf', 'AMWF'),
  SiteTab('/categories/asian', '亞洲'),
  SiteTab('/categories/desi', '南亞裔'),
  SiteTab('/categories/mzansi', '南非'),
  SiteTab('/categories/latina', '拉丁裔'),
  SiteTab('/categories/european', '歐洲'),
  SiteTab('/categories/jewish', '猶太'),
  SiteTab('/categories/american', '美國佬'),
  SiteTab('/categories/interracial', '跨種族'),
  SiteTab('/categories/arab', '阿拉伯風情'),
  SiteTab('/categories/african', '非洲'),
  SiteTab('/categories/black', '黑人'),
  // ── 身體（45 个）
  SiteTab('/categories/bwc', 'BWC'),
  SiteTab('/categories/saggy-tits', '下垂奶'),
  SiteTab('/categories/nipples', '乳頭'),
  SiteTab('/categories/midget', '侏儒'),
  SiteTab('/categories/fake-tits', '假奶'),
  SiteTab('/categories/tattoo', '刺青'),
  SiteTab('/categories/cute', '可愛'),
  SiteTab('/categories/big-natural-tits', '大天然奶'),
  SiteTab('/categories/big-tits', '大奶'),
  SiteTab('/categories/big-nipples', '大奶頭'),
  SiteTab('/categories/big-ass', '大屁股'),
  SiteTab('/categories/pawg', '大屁股白妞'),
  SiteTab('/categories/big-cock', '大屌'),
  SiteTab('/categories/bbw', '大美人'),
  SiteTab('/categories/big-clit', '大陰蒂'),
  SiteTab('/categories/bbc', '大黑屌'),
  SiteTab('/categories/giantess', '女巨人'),
  SiteTab('/categories/fbb', '女性健美者'),
  SiteTab('/categories/tits', '奶子'),
  SiteTab('/categories/petite', '嬌小'),
  SiteTab('/categories/perfect-body', '完美身材'),
  SiteTab('/categories/pussy', '小穴'),
  SiteTab('/categories/small-tits', '小胸'),
  SiteTab('/categories/ass', '屁股'),
  SiteTab('/categories/giant', '巨型'),
  SiteTab('/categories/monster-cock', '巨屌'),
  SiteTab('/categories/pregnant', '懷孕'),
  SiteTab('/categories/amputee', '截肢者'),
  SiteTab('/categories/tan-girl', '曬黑妹'),
  SiteTab('/categories/hairy', '毛茸茸'),
  SiteTab('/categories/exotic', '異國風情'),
  SiteTab('/categories/skinny', '瘦弱'),
  SiteTab('/categories/piercing', '穿孔'),
  SiteTab('/categories/tight-pussy', '緊緻小穴'),
  SiteTab('/categories/beauty', '美女'),
  SiteTab('/categories/legs', '美腿'),
  SiteTab('/categories/muscular-woman', '肌肉女'),
  SiteTab('/categories/puffy-nipples', '膨脹乳頭'),
  SiteTab('/categories/nude', '裸體'),
  SiteTab('/categories/chubby', '豐滿'),
  SiteTab('/categories/ssbbw', '超大碼性感胖女人'),
  SiteTab('/categories/clit', '陰蒂'),
  SiteTab('/categories/hermaphrodite', '雌雄同體'),
  SiteTab('/categories/flexible', '靈活'),
  SiteTab('/categories/cameltoe', '駱駝蹄'),
  // ── 頭髮（6 个）
  SiteTab('/categories/colored-hair', '彩色頭髮'),
  SiteTab('/categories/brunette', '棕髮女郎'),
  SiteTab('/categories/short-hair', '短髮'),
  SiteTab('/categories/redhead', '紅髮妹'),
  SiteTab('/categories/blonde', '金髮'),
  SiteTab('/categories/long-hair', '長髮'),
  // ── 人數（7 个）
  SiteTab('/categories/threesome', '三人行'),
  SiteTab('/categories/foursome', '四人行'),
  SiteTab('/categories/couple', '情侶'),
  SiteTab('/categories/orgy', '狂歡'),
  SiteTab('/categories/solo', '獨自'),
  SiteTab('/categories/group-sex', '群交'),
  SiteTab('/categories/gangbang', '輪姦'),
  // ── 性玩具（14 个）
  SiteTab('/categories/strapon', '假陽具'),
  SiteTab('/categories/dildo', '假雞巴'),
  SiteTab('/categories/ball-gagged', '口球束縛'),
  SiteTab('/categories/fucking-machine', '性愛機器'),
  SiteTab('/categories/sex-toy', '性玩具'),
  SiteTab('/categories/enema', '灌腸'),
  SiteTab('/categories/butt-plug', '肛塞'),
  SiteTab('/categories/anal-beads', '肛門珠'),
  SiteTab('/categories/blindfolded', '蒙眼'),
  SiteTab('/categories/sybian', '西比亞'),
  SiteTab('/categories/pussy-pump', '陰部吸泵'),
  SiteTab('/categories/double-dildo', '雙頭假陽具'),
  SiteTab('/categories/vibrator', '震動棒'),
  SiteTab('/categories/hitachi', '震動玩具'),
  // ── 服飾（23 个）
  SiteTab('/categories/thong', '丁字褲'),
  SiteTab('/categories/latex', '乳膠'),
  SiteTab('/categories/panties', '內褲'),
  SiteTab('/categories/bodystocking', '全身網襪'),
  SiteTab('/categories/uniform', '制服'),
  SiteTab('/categories/nylon', '尼龍'),
  SiteTab('/categories/lingerie', '性感內衣'),
  SiteTab('/categories/gloves', '手套'),
  SiteTab('/categories/school-uniform', '校服'),
  SiteTab('/categories/bikini', '比基尼'),
  SiteTab('/categories/jeans', '牛仔褲'),
  SiteTab('/categories/leather', '皮革'),
  SiteTab('/categories/glasses', '眼鏡'),
  SiteTab('/categories/stockings', '絲襪'),
  SiteTab('/categories/fishnet', '網襪'),
  SiteTab('/categories/leggings', '緊身褲'),
  SiteTab('/categories/bra', '胸罩'),
  SiteTab('/categories/spandex', '萊卡緊身衣'),
  SiteTab('/categories/masked', '蒙面'),
  SiteTab('/categories/skirt', '裙子'),
  SiteTab('/categories/socks', '襪子'),
  SiteTab('/categories/pantyhose', '連褲襪'),
  SiteTab('/categories/high-heels', '高跟鞋'),
  // ── 設想（99 个）
  SiteTab('/categories/asmr', 'ASMR'),
  SiteTab('/categories/medieval', '中世紀'),
  SiteTab('/categories/agent', '代理人'),
  SiteTab('/categories/escort', '伴遊'),
  SiteTab('/categories/babysitter', '保姆'),
  SiteTab('/categories/nun', '修女'),
  SiteTab('/categories/cheating', '偷情'),
  SiteTab('/categories/upskirt', '偷拍裙底'),
  SiteTab('/categories/voyeur', '偷窺者'),
  SiteTab('/categories/princess', '公主'),
  SiteTab('/categories/public-sex', '公開性愛'),
  SiteTab('/categories/public-nudity', '公開裸露'),
  SiteTab('/categories/stuck', '卡住'),
  SiteTab('/categories/reverse-gangbang', '反向群交'),
  SiteTab('/categories/celebrity', '名人'),
  SiteTab('/categories/vampire', '吸血鬼'),
  SiteTab('/categories/gothic', '哥特'),
  SiteTab('/categories/cheerleader', '啦啦隊女孩'),
  SiteTab('/categories/alien', '外星人'),
  SiteTab('/categories/coed', '大學男女混宿'),
  SiteTab('/categories/mistress', '女主人'),
  SiteTab('/categories/maid', '女僕'),
  SiteTab('/categories/catfight', '女子打架'),
  SiteTab('/categories/girlfriend', '女朋友'),
  SiteTab('/categories/slave', '奴隸'),
  SiteTab('/categories/wife-sharing', '妻子共享'),
  SiteTab('/categories/doll', '娃娃'),
  SiteTab('/categories/wedding', '婚禮'),
  SiteTab('/categories/mom', '媽咪'),
  SiteTab('/categories/student', '學生'),
  SiteTab('/categories/housewife', '家庭主婦'),
  SiteTab('/categories/clown', '小丑'),
  SiteTab('/categories/bunny', '小兔子'),
  SiteTab('/categories/fantasy', '幻想'),
  SiteTab('/categories/cook', '廚師'),
  SiteTab('/categories/sex-instruction', '性愛指導'),
  SiteTab('/categories/nympho', '性癮者'),
  SiteTab('/categories/monster', '怪物'),
  SiteTab('/categories/horror', '恐怖'),
  SiteTab('/categories/valentines-day', '情人節'),
  SiteTab('/categories/emo', '情緒搖滾風'),
  SiteTab('/categories/parody', '惡搞'),
  SiteTab('/categories/cuckold', '戴綠帽'),
  SiteTab('/categories/fighting', '打架'),
  SiteTab('/categories/wife-swap', '換妻'),
  SiteTab('/categories/swingers', '換妻者'),
  SiteTab('/categories/pick-up', '搭訕'),
  SiteTab('/categories/morning', '早晨'),
  SiteTab('/categories/time-stop', '時間靜止'),
  SiteTab('/categories/nerd', '書呆子'),
  SiteTab('/categories/waitress', '服務生'),
  SiteTab('/categories/glory-hole', '榮耀洞'),
  SiteTab('/categories/plumber', '水管工'),
  SiteTab('/categories/party', '派對'),
  SiteTab('/categories/romantic', '浪漫'),
  SiteTab('/categories/naughty', '淘氣'),
  SiteTab('/categories/comic', '漫畫'),
  SiteTab('/categories/passionate', '熱情'),
  SiteTab('/categories/daddy', '爹地'),
  SiteTab('/categories/birthday', '生日'),
  SiteTab('/categories/truth-or-dare', '真心話大冒險'),
  SiteTab('/categories/hardcore', '硬核'),
  SiteTab('/categories/taboo', '禁忌'),
  SiteTab('/categories/secretary', '秘書'),
  SiteTab('/categories/cfnm', '穿衣女與裸體男'),
  SiteTab('/categories/cmnf', '穿衣男與裸體女'),
  SiteTab('/categories/first-time', '第一次'),
  SiteTab('/categories/e-girl', '網紅妹'),
  SiteTab('/categories/boss', '老大'),
  SiteTab('/categories/wife', '老婆'),
  SiteTab('/categories/teacher', '老師'),
  SiteTab('/categories/xmas', '聖誕節'),
  SiteTab('/categories/joi', '自慰指導'),
  SiteTab('/categories/halloween', '萬聖節'),
  SiteTab('/categories/virgin', '處女'),
  SiteTab('/categories/nudist', '裸體主義者'),
  SiteTab('/categories/cosplay', '角色扮演'),
  SiteTab('/categories/role-play', '角色扮演'),
  SiteTab('/categories/audition', '試鏡'),
  SiteTab('/categories/seduce', '誘惑'),
  SiteTab('/categories/police', '警察'),
  SiteTab('/categories/nurse', '護士'),
  SiteTab('/categories/ghetto', '貧民窟'),
  SiteTab('/categories/superhero', '超人'),
  SiteTab('/categories/dance', '跳舞'),
  SiteTab('/categories/body-swap', '身體交換'),
  SiteTab('/categories/military', '軍事角色扮演'),
  SiteTab('/categories/baddie', '辣妹'),
  SiteTab('/categories/game', '遊戲'),
  SiteTab('/categories/gamer-girl', '遊戲妹'),
  SiteTab('/categories/sport', '運動'),
  SiteTab('/categories/casting', '選角'),
  SiteTab('/categories/neighbor', '鄰居'),
  SiteTab('/categories/doctor', '醫生'),
  SiteTab('/categories/medical', '醫療'),
  SiteTab('/categories/stranger', '陌生人'),
  SiteTab('/categories/twins', '雙胞胎'),
  SiteTab('/categories/interview', '面試'),
  SiteTab('/categories/surprise', '驚喜'),
  // ── 位置（23 个）
  SiteTab('/categories/sauna', '三溫暖'),
  SiteTab('/categories/fitness', '健身'),
  SiteTab('/categories/gym', '健身房'),
  SiteTab('/categories/jungle', '叢林'),
  SiteTab('/categories/college', '大學'),
  SiteTab('/categories/bus', '巴士'),
  SiteTab('/categories/toilet', '廁所'),
  SiteTab('/categories/kitchen', '廚房'),
  SiteTab('/categories/outdoor', '戶外'),
  SiteTab('/categories/hotel', '旅館'),
  SiteTab('/categories/underwater', '水下'),
  SiteTab('/categories/car', '汽車'),
  SiteTab('/categories/beach', '沙灘'),
  SiteTab('/categories/pool', '泳池'),
  SiteTab('/categories/bathroom', '浴室'),
  SiteTab('/categories/shower', '淋浴'),
  SiteTab('/categories/train', '火車'),
  SiteTab('/categories/prison', '監獄'),
  SiteTab('/categories/taxi', '計程車'),
  SiteTab('/categories/office', '辦公室'),
  SiteTab('/categories/farm', '農場'),
  SiteTab('/categories/village', '鄉村'),
  SiteTab('/categories/hospital', '醫院'),
];

// ===== 本站档案（2026-10-03 从 lib/sites.dart 的 kSites 下放 ✓）=====

/// 本站档案：xHamster
const SiteEntry kSite14 = SiteEntry(
    name: 'xHamster',
    template: SiteTemplate.xhamster,
    // 站点自己的 favicon（sim 的 /icon 会代抓）
    iconUrl: '/favicon.ico',
    hosts: ['tw.xhamster.com'],
    // 相关推荐：移动版页面里**没有 DOM 卡片**（`div.m-related-container` 是"正在載入..."
    // 空壳），但静态 HTML 里有一整段 JSON（Vue props），每条带 pageURL/title/thumbURL/
    // duration → `xhDetail` 直接解析它。（用户 2026-10-02 指出"详情页的推荐视频你没加上"。）
    showRelated: true,
    // 主分类 = 站点顶栏的「影片」tab；全部/高畫質/4K/虛擬實境 是它**下面的子分类**
    // （用户 2026-10-02 纠正过一次：我一开始把四个子分类摆成了主分类）。
    // ⚠️ key 的语义 = **站内路径**（见 lib/api.dart 的 _xhList）：
    //    · 主分类 key 取 `/`（= 不选子分类时的默认，等同「全部」）
    //    · 「全部」= 首页 `/`（用户点击实测确认；站点导航里没有这个链接）
    //    · 其余三个是实测出来的真实路径
    // 翻页是**路径式**：第 N 页 = 该路径 + `/N`（`?page=N` 会被忽略）
    categories: [
      SiteTab('/', '影片', [
        SiteTab('/', '全部'),
        SiteTab('/hd', '高畫質'),
        SiteTab('/4k', '4K'),
        // ⚠️ /vr 与前三个**完全不同**：不是 HLS，是带签名的 mp4 直链 + 会员墙（实测无 m3u8）。
        // 先作为子分类放着，播放这块**待定**（见 DEVLOG 75）。
        SiteTab('/vr', '虛擬實境'),
      ]),
      // 主分类「分类」（用户 2026-10-02 指定）：**主展示** = 18-year-old 这一类的列表；
      // 388 个分类标签从筛选行的「分类」按钮**弹窗选**（照抄 Pornhub 那套选择器，
      // 清单就是下面的 `xhCats` —— 站点 /categories 页 `assignable` JSON 的 13 组）。
      SiteTab('/categories/18-year-old', '分类'),
      // 主分类「色情明星」（用户 2026-10-02 指定）：`/pornstars` 返回的是**演员卡**
      // （DOM 里一张都没有，整页客户端渲染 → 数据在页面 JSON 的 "pornstars":[…] 里，
      //   约 60 条，带 name / pageURL / logoThumbUrl / videoCount）。
      // 点演员卡进**他/她的视频列表**（`/creators/<slug>`），不是详情页。
      SiteTab('/pornstars', '色情明星'),
      // 主分类「短片」（用户 2026-10-02）：数据在**页面 JSON**（`initials-script` ✓），静态 HTML 里 0 卡片 ✗
      // （`/shorts` 页本身是纯客户端渲染 ✗）。
      // 实测（sim-dev 2026-10-03 ✅）：**真翻页是路径式** `/shorts/newest/{N}` ✓（`?page=N` **被站点忽略** ✗），
      // **45 条/页** ✓ · `lastPage=100` ✓ · 与第 1 页零重叠 ✓；每条带 title / pageURL(/shorts/<slug>) /
      // imageURL(405×720 竖版) / views ✓（**不含 sources** ✗ → 播放仍走详情页 ✓）。
      // ⚠️ 旧注释里那条 `/api/v1/moments` 接口**已整条撤掉** ✗（带上 `X-Requested-With` 会被站点当 **404** ✗）。
      // 展示走**竖版网格**（用户 2026-10-02 定的 A 方案；B 那个抖音式竖屏流先记待办）。
      SiteTab('/shorts', '短片'),
    ],
    // 分类选择器：与 Pornhub 的「分类选择」**同一个机制**（themes = 弹窗里那排 chip，
    // 选中后按该 key 的路径去请求列表，调用的还是 `_xhList` 那套路径分流）。
    // ⚠️ 这里 388 项、是 PH 的近 4 倍，但机制一模一样，**UI 一行都不用改**。
    filters: SiteFilters(
      themes: xhCats,
      languages: [],
      durations: [],
      sorts: [],
      themeLabel: '分类',
      themeEmptyLabel: '分类选择',
    ),
    color: Color(0xFFF5A623),
  );

/// **本站「明星分類」选中的状态**（用户 2026-10-03 要求：站点专属状态回到站点文件 ✓）
///
/// ⚠️ 原先 `_xhStar` 是公共页面 `home_page.dart` 的字段 ✗；现在选中状态归本站 ✓。
/// 页面负责：按钮/弹窗的界面、以及「选完重新拉列表」的调用（`_reloadXhStar` ✓）。
class XhStarController {
  /// 选中的明星分类 key（null = 不限 ✓）
  String? sel;

  /// 清空选择（页面点「清空」时调 ✓）
  void clear() => sel = null;

  /// 切换某个 key（点同一个 = 取消 ✓，与原逻辑一致 ✓）
  void toggle(String key) => sel = (sel == key) ? null : key;
}
