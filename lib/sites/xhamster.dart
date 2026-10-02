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
import 'dart:math';

import 'package:html/parser.dart' as hp;

import '../base/fetch.dart';
import '../base/site_ui.dart';
import '../models.dart';

/// xHamster 本站专属实现（取数走公用底座 [SiteFetcher] ✓）
class XhSite implements SiteUi {
  XhSite(this._f);

  final SiteFetcher _f;

  /// 标签列表页（原 `Api.tag` 的 case body 原样搬来 ✓）
  /// 演员卡传过来的是 '/pornstars/<slug>'（本人页 → 视频列表 ✓）；详情页标签也走这里 ✓。
  /// 全是站内路径，交给 list 分流（它会避开"把演员页当演员列表解析"的坑 ✓）
  Future<List<Article>> tag(String slug, {required int page}) => list(slug, page: page);

  /// 首页 = '/'（原 `Api.home` 的 case body 原样搬来 ✓）
  Future<List<Article>> home({required int page}) => list('/', page: page);

  /// 「分类」tab 的列表（原 `Api.category` 的 case body 原样搬来 ✓）
  /// key / theme 都是**站内路径** ✓（「色情明星」tab 自己的选择器也走 theme ✓）：
  ///   · 「影片」tab：'/'、'/hd'、'/4k'、'/vr'
  ///   · 「分类」tab：默认 '/categories/18-year-old'；选中标签后 theme = '/categories/<slug>'
  ///   · 「色情明星」tab：默认 '/pornstars'；选中后 '/pornstars/top/us' 等
  ///   · 「短片」tab：'/shorts' → 内部走 JSON 接口（与路径无关 ✓）
  Future<List<Article>> category(String key, String? theme, {required int page}) =>
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

  Future<ArticleDetail> detail(String url) => _xhDetail(url);

  /// 短片随机起始页 / 每批打乱（原先在 `Api` 里，跟着搬过来 ✓）
  static final Random _rand = Random();
  // xHamster（tw.xhamster.com）—— 见 DEVLOG 75~81
  //
  // ⚠️ 三条硬事实（都实测过，别照别的站的经验改）：
  //  ① **必须用桌面 UA 取**：config 里的 Site.ua 是 iPhone UA，站点只给 **5 张卡/页**；
  //     桌面 UA 给 **50+ 张**。但桌面版 DOM 里第 13 张起全是**骨架屏占位** →
  //     真数据在**页面 JSON**里（跟 assignable / 相关推荐同一个套路）。
  //  ② 「短片」走 **JSON 接口** `/api/v1/moments`（'/shorts' 页面本身客户端渲染，静态 HTML 0 卡片）。
  //  ③ 视频 CDN **不校验 Referer 也不校验 UA**（与 Pornhub 相反）→ 播放不用加特判。

  static const String _xhUa = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  static const Map<String, String> _xhDesk = {'User-Agent': _xhUa};

  /// 页面 JSON 里的字符串都是转义的（`https:\/\/`、中文 `\u516c`）→ 用 jsonDecode 还原。
  static String _xhUn(String? s) {
    if (s == null || s.isEmpty) return '';
    try {
      return jsonDecode('"' + s + '"') as String;
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

  /// 「短片」：JSON 接口 `/api/v1/moments`（无需 cookie）。
  /// ⚠️ 每页只有 5~6 条、单次要 2~5s，而且**页大小调不大**（itemsOnPage/limit/perPage/
  /// size/count/pageSize 全试过无效）→ **并发抓 4 页再合并**，否则就是"5 条…等好几秒…又 5 条"
  /// （用户实报过）。
  /// ⚠️ **随机**（用户 2026-10-02："短片的卡片列表每次进去也要随机。不然你老是显示第一批短片
  /// 意义在哪里？？？"）—— 站点接口是**固定分页序**，所以只打乱是不够的 ✗（池子还是那几条）：
  /// **起始页取随机 1~48**（该范围实测有内容 🔍），列表内往后顺延；每批打乱；按 url 去重。
  /// `resetShortsRandom()` 让下一次取数**重新随机**（切 tab 回来时调，与 sim 行为一致 ✓）。
  static final Random _rand = Random();

  int? _xhShortsFrom;

  void resetShortsRandom() {
    _xhShortsFrom = null;
  }

  /// 短片列表：**直接抓页面里内嵌的 JSON** ✓
  /// （用户 2026-10-03 定："**短片不用 api 请求了。直接抓 json 吧**" ✓）
  ///
  /// ⚠️ 为什么不用 `/api/v1/moments` ✗：用户实机（**App 是直连架构**，DEVLOG 铁律 3）报
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

  Future<List<Article>> _xhMoments(int page) async {
    if (page < 1) return const [];
    final p = page < 1 ? 1 : page;
    final html = await _f.text(
        p > 1 ? '$_xhShortsPath?page=$p' : _xhShortsPath,
        extraHeaders: _xhDesk);
    final out = _xhMomentsFromHtml(html);
    if (out.isEmpty) {
      // 不吞掉 ✓：界面会把原因显示出来（home_page 的三态渲染 ✓）
      throw Exception('短片页面解析出 0 条（页面结构可能变了）');
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
    final m = RegExp(r'https://[^"\s\\]+\.m3u8[^"\s\\]*').firstMatch(html);
    var srcs = <String>[];
    if (m != null) {
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
