// heitaodj —— **本站专属**的一切 ✓（黑桃短剧 heitaodj.com）
//
// ⚠️ 用户 2026-11-15 指定：新增独立站点，**不写公共站点函数** ✓（见 DEVLOG 顶部「写死的规则」）
//
// 🛢️ 实测（2026-11-15，真站 heitaodj.com，iPhone UA + 无 cookie）：
//   · 站点形态 = MacCMS 内核（路径全是 `/index.php/vod/...`）
//   · 首页列表      `GET /`                        ⇒ 200 / 44,129 B / `li.m-item` **51** 张卡
//                     ⚠️ `/?page=2` 与第 1 页**字节数完全相同** ⇒ **首页没有分页**（只取第 1 页）
//   · 分类列表      `GET /index.php/vod/type/id/<id>.html`
//                   第 2 页 = `/index.php/vod/type/id/<id>/page/<n>.html`（实测 200，最后一页 34）
//                   分类表（导航原文）：1 现代都市 / 2 古装传奇 / 3 仙侠玄幻 / 4 科幻脑洞 /
//                   5 灵异悬疑 / 6 其他短剧
//   · 搜索          `GET /index.php/vod/search.html?wd=<kw>`（+ `&page=<n>`）⇒ 200，30 张卡
//   · 标签          `GET /index.php/vod/search/tag/<编码名>.html`（+ `/page/<n>.html`）⇒ 200 / 30 张卡
//   · 卡片结构      `<li class="m-item">`
//                     `a.thumb[href]` → `/index.php/vod/detail/id/<id>.html`
//                     `img.quic[src]` → 封面（`img.heitaodj.com` 或 `vod.djqiepian.app`）
//                     `h3.stitle a[title]` → 标题；`p.des` → 分类名
//                     `div.icon-br span.label` → 集数角标（实测 30 张卡里 15 张有）
//   · 详情页        `GET /index.php/vod/detail/id/<id>.html`
//                     `h1.title` → 片名；`summary.albumDetailIntroTxt` → 简介
//                     `.detail-tags a.tag-chip` → 标签（href = `/index.php/vod/search/tag/<编码>.html`）
//                     选集 `.albumSelect li a` → `/index.php/vod/play/id/<id>/sid/<s>/nid/<n>.html`
//                     同类推荐 = 页面里的 `li.m-item`
//   · ☠ **播放源要过两道**（这是本站最关键的事实）：
//       ① 播放页 `/index.php/vod/play/id/<id>/sid/<s>/nid/<n>.html` 里只有**一个 iframe 的路径**：
//          `<iframe class="player-iframe" data-heitao-player-src="/index.php/vod/player/id/<id>/nid/<n>/sid/<s>.html">`
//       ② 播放器页 `/index.php/vod/player/...` **不带年龄 cookie 时只返回年龄门**（2.6KB，没有任何源）；
//          带上 `Cookie: heitao_age_confirmed=1`（实测自 `/static/js/heitao-age-gate.js` 的
//          `COOKIE_NAME='heitao_age_confirmed'` / `COOKIE_VALUE='1'` / max-age 15552000）
//          ⇒ 返回 `var player_aaaa={…}`，其中 `"url":"https://play.djqiepian.app/vod/t-…/index.m3u8"`
//          （同结构里 `from` = `zym3u8`、`encrypt` = 0）
//   · ✅ 实测取到的 m3u8：HTTP 200 / 2,587 B / `#EXTM3U` / `#EXT-X-KEY`(AES-128) / 非 master；
//       首分片 HTTP 200 / 264,896~779,456 B；**带不带 Referer 都是 200** ⇒ 播放器不需要额外头 ✅
//   · ✅ 多集：id=1324 共 5 集（nid=1..5），nid=2 的 m3u8 与 nid=1 **文件名不同** ⇒ 点哪集取哪集 ✅
//
// ⚠️ 用户规矩：站点文件**不 import material**（会与 html/dom 的 `Element`/`Text` 撞名）✓；
//    html/dom 一律 `as dom` ✓；要 `Color` 只 `import 'dart:ui' show Color;` ✓

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as hp;

import '../app_background.dart' show kTxt, kTxtSub, kStatusOverlay, PageBg;
import '../app_bg.dart' show AppBg;
import '../config.dart' show Site;
import '../sites.dart';
import '../base/site_ui.dart';
import '../base/fetch.dart';
import '../detail_page.dart' show DetailPage;
import '../fetched_image.dart' show FetchedImage;
import '../home_page.dart' show SearchPage;
import '../models.dart';
import '../settings.dart';

/// 黑桃短剧 本站专属实现（取数走公用底座 [SiteFetcher] ✓）
class HeitaoSite extends SiteUi {
  HeitaoSite(this._f);

  final SiteFetcher _f;

  /// 年龄确认 cookie —— 播放器页**不带它就是年龄门**（实测，见文件头）
  static const String _kAgeCookie = 'heitao_age_confirmed=1';

  /// 站内相对路径（绝对地址剥成 `/xxx`；本来就是相对的返回原样）
  String _toRelPath(String href) {
    final h = href.trim();
    if (!h.startsWith('http')) return h;
    final u = Uri.tryParse(h);
    if (u != null && u.path.isNotEmpty) {
      return u.query.isEmpty ? u.path : '${u.path}?${u.query}';
    }
    return h;
  }

  /// ★ 2026-11-15（用户实报「首页-加载失败:Exception:所有域名均无法访问」）：**本站必须自重试** ✅
  ///
  /// 🛢️ 实测（2026-11-15，本机，按底座同款请求头连打 5 次 `GET /`）：
  ///   `[1] TimeoutException 8040ms` · `[2] HandshakeException 5008ms` ·
  ///   `[3] 200 / 44,129 B / 5,221ms` · `[4] 200 / 1,548ms` · `[5] 200 / 801ms`
  ///   ⇒ **冷连接头一两次基本必失败**（TLS 握手被对端断），热了之后 0.8s 就回。
  ///   而底座 `SiteFetcher.text()` 是 **8 秒超时 + 只有 5xx 才在同域名重试**
  ///   （`base/fetch.dart:53-54` / `:87-90`）⇒ 一次超时就抛「所有域名均无法访问」☠
  ///   ⇒ 这里包一层：**最多 3 次、退避 500ms/1200ms**，仍失败才把原文抛给上层
  ///   ⚠️ 只在**本站文件**里做 ⇒ 其它站点零影响 ✅
  Future<String> _text(String path) async {
    Object? last;
    for (var i = 1; i <= 3; i++) {
      try {
        return await _f.text(path);
      } catch (e) {
        last = e;
        if (AppSettings.i.logConsole) {
          debugPrint('[NET] ${_f.site.name} 第$i次失败 path=${path.length <= 60 ? path : path.substring(0, 60)} '
              '原因=${e.runtimeType}');
        }
        if (i < 3) {
          await Future<void>.delayed(Duration(milliseconds: i == 1 ? 500 : 1200));
        }
      }
    }
    throw last ?? Exception('所有域名均无法访问');
  }

  // ---------------------------------------------------------------- 列表

  /// 卡片解析（首页 / 分类 / 搜索 / 标签 / 详情页的同类推荐**共用同一套结构** ✓）
  List<Article> parseCards(String html) {
    final doc = hp.parse(html);
    final out = <Article>[];
    for (final el in doc.querySelectorAll('li.m-item')) {
      final a = _cardOf(el);
      if (a != null) out.add(a);
    }
    return out;
  }

  /// 单张卡（`li.m-item` → [Article]）；解析不出返回 null
  /// ⚠️ 标题节点**两套**：手机版 `h3.stitle a` / 桌面版 `h3.title a`（实测两种 UA 的 HTML 不一样）
  Article? _cardOf(dom.Element el) {
    final a = el.querySelector('a.thumb[href]') ??
        el.querySelector('a[href*="/index.php/vod/detail/"]');
    if (a == null) return null;
    final href = _toRelPath(a.attributes['href'] ?? '');
    if (href.isEmpty) return null;
    final img = el.querySelector('img.quic') ?? el.querySelector('img[src]');
    final cover = (img?.attributes['src'] ?? '').trim();
    final titleEl = el.querySelector('h3.stitle a') ??
        el.querySelector('h3.title a') ??
        a;
    // 标题：优先 `a[title]`（站点一直带），否则用链接文字
    final attrTitle = (titleEl.attributes['title'] ?? '').trim();
    final textTitle = titleEl.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final title = attrTitle.isNotEmpty ? attrTitle : textTitle;
    if (title.isEmpty) return null;
    final badge = (el.querySelector('div.icon-br span.label')?.text ?? '').trim();
    final des = (el.querySelector('p.des')?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return Article(
      title: title,
      url: href,
      cover: cover,
      meta: des, // 本站卡片没有时间，标题下面那行放站点自己的分类名
      badge: badge,
    );
  }

  /// ★ 2026-11-15（用户：「首页根据网页实际模块添加。推荐-本周热播」）：
  ///   **首页按站点真实分区块**解析 —— 实测首页 8 个 `section.mod`（2026-11-15 原文）：
  ///     推荐(3) · 本周热播(3) · 最新更新(9) · 现代都市(6) · 古装传奇(6) ·
  ///     仙侠玄幻(6) · 科幻脑洞(6) · 灵异悬疑(6) · 其他短剧(6)
  ///   每个块 = `<h2 class="mod-head-name">标题</h2>` + `ul.m-list > li.m-item`；
  ///   后 6 个分类块带「更多」→ `/index.php/vod/type/id/<id>.html`（id 就写进 [HtSection.moreKey]）
  List<HtSection> parseSections(String html) {
    final doc = hp.parse(html);
    final out = <HtSection>[];
    final seen = <String>{};
    // ⚠️ 两种 UA 的版式不同（实测）：
    //   手机版 = `<section class="mod">` + `<h2 class="mod-head-name">`
    //   桌面版 = `<div class="mod">`    + `<h2 class="title" mod-skin="line">`
    for (final sec in doc.querySelectorAll('section.mod, div.mod')) {
      final t = ((sec.querySelector('h2.mod-head-name') ?? sec.querySelector('h2.title'))
                  ?.text ??
              '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (t.isEmpty) continue;
      final items = <Article>[];
      for (final el in sec.querySelectorAll('li.m-item')) {
        final a = _cardOf(el);
        if (a != null) items.add(a);
      }
      if (items.isEmpty) continue;
      // `div.mod` 可能嵌套 ⇒ 同一个块会被算两次：用首条 url + 标题去重
      if (!seen.add('$t|${items.first.url}')) continue;
      String? more;
      for (final a in sec.querySelectorAll('a[href*="/vod/type/id/"]')) {
        final m = RegExp(r'/vod/type/id/(\d+)\.html')
            .firstMatch(a.attributes['href'] ?? '');
        if (m != null) {
          more = m.group(1);
          break;
        }
      }
      out.add(HtSection(title: t, items: items, moreKey: more));
    }
    return out;
  }

  /// ★ 2026-11-15（用户：「首页根据网页实际模块添加。推荐-本周热播」）：
  ///   🛢️ 实测 —— **同一页 `/` 按 UA 给的内容不一样**：
  ///     手机 UA（`Site.ua`）⇒ 全页 `li.m-item` **51** 张，「本周热播」只有 **3** 张；
  ///     桌面 UA（Chrome/Win）⇒ 全页 **93** 张，「本周热播」**6** 张（与网页截图一致）
  ///   ⇒ 首页/分区**必须用桌面 UA 抓**，才对得上站点的真实模块 ✅
  ///   ✅ 已核实桌面 UA 对**详情页 / 播放器页**同样正常（detail 200 选集 6 条；player 200 且能取到 m3u8）
  static const String _kDesktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/140.0 Safari/537.36';

  /// 指定 UA 的取文本（同样 3 次重试；只在**本站**用）
  Future<String> _textWithUa(String path, String ua) async {
    Object? last;
    for (var i = 1; i <= 3; i++) {
      try {
        final r = await _f.client.get(
          Uri.parse('https://${_f.host}$path'),
          headers: {
            'User-Agent': ua,
            'Referer': 'https://${_f.host}/',
            'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
          },
        ).timeout(const Duration(seconds: 15));
        if (r.statusCode == 200) return utf8.decode(r.bodyBytes);
        last = Exception('HTTP ${r.statusCode}');
      } catch (e) {
        last = e;
      }
      if (AppSettings.i.logConsole) {
        debugPrint('[NET] ${_f.site.name} 第$i次失败（桌面UA） '
            'path=${path.length <= 60 ? path : path.substring(0, 60)} 原因=$last');
      }
      if (i < 3) {
        await Future<void>.delayed(Duration(milliseconds: i == 1 ? 500 : 1200));
      }
    }
    throw last ?? Exception('首页取不到');
  }

  /// 给「自管整页」用的公开取文本（内部就是带 3 次重试的 [_text]）
  Future<String> text(String path) => _text(path);

  /// 首页专用：**桌面 UA**（站点只在桌面 UA 下给完整模块，见 [_kDesktopUa]）
  Future<String> textDesktop(String path) => _textWithUa(path, _kDesktopUa);

  /// ★ 2026-11-15：本站**自管整页**（首页是分区块的，通用"单列分页"版式装不下）
  @override
  Widget? sitePage(BuildContext context, SiteEntry site) =>
      HtHomePage(site: site, ui: this);

  /// 首页 = `/`（**站点没有分页**，实测 `/?page=2` 与首页字节一致 ⇒ page>1 直接返回空）
  @override
  Future<List<Article>> home({required int page, String first = ''}) async {
    if (page > 1) return const <Article>[];
    final sw = Stopwatch()..start();
    final res = parseCards(await _textWithUa('/', _kDesktopUa));
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 入口=home 页=$page 解析出 ${res.length} 条 '
          'ms=${sw.elapsedMilliseconds}');
    }
    return res;
  }

  /// ★ 2026-11-15（用户第二/三次反馈：「子分类-标签你还是没加」）：
  ///   **分类页顶部其实有四行**（实测桌面 UA 原文，`div.classifyWarp` 内 4 个 `div.classifyType`）：
  ///     ① 频道：   现代都市 … → `/index.php/vod/show/id/<父id>.html`（= App 的 tab，不重复画）
  ///     ② 分类：   全部/校园爱情/… → `/index.php/vod/show/id/<id>.html`
  ///     ③ 子分类： 情感爱恋/职场权色/… → `/index.php/vod/type/id/<id>.html`  ← **之前漏的**
  ///     ④ 标签：   都市/古装/仙侠/…（几十个）→ `/index.php/vod/search/tag/<编码名>.html` ← **之前漏的**
  ///   ⇒ 这里把 ②③④ 解析出来交给页面画三排胶囊
  HtClassify parseClassify(String html) {
    final doc = hp.parse(html);
    final cats = <HtChip>[];
    final subs = <HtChip>[];
    final tags = <HtChip>[];
    for (final box in doc.querySelectorAll('div.classifyType')) {
      final t = (box.querySelector('h5.u-title')?.text ?? '')
          .replaceAll('：', '')
          .replaceAll(':', '')
          .trim();
      for (final a in box.querySelectorAll('ul li a[href]')) {
        final name = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (name.isEmpty) continue;
        final href = (a.attributes['href'] ?? '').trim();
        final showM = RegExp(r'/vod/show/id/(\d+)\.html').firstMatch(href);
        final typeM = RegExp(r'/vod/type/id/(\d+)\.html').firstMatch(href);
        final tagM = RegExp(r'/vod/search/tag/([^/]+)\.html').firstMatch(href);
        if (t == '分类' && showM != null) {
          cats.add(HtChip(name, '/show/${showM.group(1)}'));
        } else if (t == '子分类' && typeM != null) {
          subs.add(HtChip(name, '/type/${typeM.group(1)}'));
        } else if (t == '标签' && tagM != null) {
          tags.add(HtChip(name, 'tag:${tagM.group(1)}'));
        }
      }
    }
    return HtClassify(cats: cats, subs: subs, tags: tags);
  }

  /// 分类列表（★ 2026-11-15 补：**首页 tab + 子分类**）
  ///   · key = `/home`            ⇒ 首页最新（[home]）
  ///   · key = `/show/<id>`       ⇒ 「分类」行：`/index.php/vod/show/id/<id>.html`
  ///   · key = `/type/<id>`       ⇒ 「子分类」行：`/index.php/vod/type/id/<id>.html`
  ///   · key = `<id>`（纯数字）    ⇒ 主分类：`/index.php/vod/type/id/<id>.html`
  ///   以上第 2 页统一 `/page/<n>.html`
  /// ⚠️ 末页再往后站点回 **404**（实测 `show/id/64/page/2.html` ⇒ 404）⇒ page>1 失败当"到底"返回空，
  ///    否则列表会弹"加载失败"（不是真故障）。
  @override
  Future<List<Article>> category(String key,
      {required int page,
      String? k,
      String? theme,
      String? duration,
      String? sort,
      List<MapEntry<String, String>>? extra,
      Future<List<Article>> Function({int page})? home}) async {
    final kk = (k ?? key).trim();
    if (kk == '/home') return home != null ? home(page: page) : this.home(page: page);

    final String path;
    if (kk.startsWith('/show/')) {
      final id = kk.substring('/show/'.length);
      path = page <= 1
          ? '/index.php/vod/show/id/$id.html'
          : '/index.php/vod/show/id/$id/page/$page.html';
    } else if (kk.startsWith('/type/')) {
      // 「子分类」行（实测 href = /index.php/vod/type/id/<id>.html）
      final id = kk.substring('/type/'.length);
      path = page <= 1
          ? '/index.php/vod/type/id/$id.html'
          : '/index.php/vod/type/id/$id/page/$page.html';
    } else {
      path = page <= 1
          ? '/index.php/vod/type/id/$kk.html'
          : '/index.php/vod/type/id/$kk/page/$page.html';
    }

    final sw = Stopwatch()..start();
    List<Article> res;
    try {
      res = parseCards(await _f.text(path));
    } catch (e) {
      // 末页之后站点回 404 ⇒ 当作"到底"（page>1 返回空；第 1 页失败照旧抛给上层显示原因）
      if (page > 1) {
        if (AppSettings.i.logConsole) {
          debugPrint('[LIST] ${_f.site.name} k=$kk 页=$page 取不到（视为到底） 原因=$e');
        }
        return const <Article>[];
      }
      rethrow;
    }
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} k=$kk 页=$page 路径=$path '
          '解析出 ${res.length} 条 ms=${sw.elapsedMilliseconds}');
    }
    return res;
  }

  /// 标签列表：`/index.php/vod/search/tag/<slug>.html`（+ `/page/<n>.html`）
  @override
  Future<List<Article>> tag(String slug, {required int page}) async {
    final s = slug.trim();
    final path = page <= 1
        ? '/index.php/vod/search/tag/$s.html'
        : '/index.php/vod/search/tag/$s/page/$page.html';
    final sw = Stopwatch()..start();
    final res = parseCards(await _text(path));
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 入口=tag slugLen=${s.length} 页=$page '
          '解析出 ${res.length} 条 ms=${sw.elapsedMilliseconds}');
    }
    return res;
  }

  /// 搜索：`/index.php/vod/search.html?wd=<kw>`（+ `&page=<n>`）
  @override
  Future<List<Article>> search(String keyword,
      {int page = 1, List<MapEntry<String, String>>? extra}) async {
    final kw = Uri.encodeComponent(keyword.trim());
    final path = page <= 1
        ? '/index.php/vod/search.html?wd=$kw'
        : '/index.php/vod/search.html?wd=$kw&page=$page';
    final sw = Stopwatch()..start();
    final res = parseCards(await _text(path));
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 入口=search 页=$page kwLen=${keyword.length} '
          '解析出 ${res.length} 条 ms=${sw.elapsedMilliseconds}');
    }
    return res;
  }

  // ---------------------------------------------------------------- 详情

  @override
  Future<ArticleDetail> detail(String url) async {
    final sw = Stopwatch()..start();
    final path = _toRelPath(url);
    final html = await _text(path);
    final doc = hp.parse(html);

    var title = (doc.querySelector('.albumDetailMedia h1.title')?.text ??
            doc.querySelector('h1')?.text ??
            '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (title.isEmpty) title = path;

    final intro = (doc.querySelector('summary.albumDetailIntroTxt')?.text ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // 封面（详情页大图）也当剧照兜底用
    final cover =
        (doc.querySelector('.albumDetailImg img')?.attributes['src'] ?? '').trim();

    // 标签：href = /index.php/vod/search/tag/<已编码名>.html ⇒ slug 取中间那段（保持编码，直接拼 URL）
    final tags = <MapEntry<String, String>>[];
    for (final a in doc.querySelectorAll('.detail-tags a.tag-chip')) {
      final href = a.attributes['href'] ?? '';
      final name = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      var seg = href;
      final i = seg.indexOf('/search/tag/');
      if (i >= 0) seg = seg.substring(i + '/search/tag/'.length);
      final dot = seg.indexOf('.html');
      if (dot >= 0) seg = seg.substring(0, dot);
      seg = seg.replaceAll('/', '');
      if (seg.isEmpty || name.isEmpty) continue;
      if (!tags.any((e) => e.key == seg)) tags.add(MapEntry(seg, name));
    }

    // 选集：`.albumSelect li a`（同一部剧可能有多个 sid，按 nid 排序，sid 只影响取源路径）
    final videos = <ArticleVideo>[];
    for (final a in doc.querySelectorAll('.albumSelect li a[href*="/vod/play/"]')) {
      final href = _toRelPath(a.attributes['href'] ?? '');
      if (href.isEmpty) continue;
      final label = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final nidM = RegExp(r'/nid/(\d+)\.html').firstMatch(href);
      final nid = int.tryParse(nidM?.group(1) ?? '') ?? (videos.length + 1);
      // 已经是"第 N 集"就直接用，否则用 第N集 兜底
      final show = label.isEmpty ? '第$nid集' : label;
      if (videos.any((v) => v.ordinal == nid)) continue;
      videos.add(ArticleVideo(
        label: show,
        ordinal: nid,
        sources: const <String>[],
        lazyUrl: href, // 点哪集去抓哪一集（播放页 → 播放器页 → m3u8）
      ));
    }
    videos.sort((a, b) => a.ordinal.compareTo(b.ordinal));

    // 同类推荐（页面里的 m-item 卡）
    final related = parseCards(html).where((a) => a.url != path).toList();

    // 分类（详情页「分类：<a href="/index.php/vod/type/id/14.html">逆袭打脸</a>」，实测原文）
    final cats = <String>[];
    final catM = RegExp(r'分类：\s*<a[^>]*>([^<]+)</a>').firstMatch(html);
    if (catM != null) {
      final c = catM.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (c.isNotEmpty) cats.add(c);
    }

    final det = ArticleDetail(
      title: title,
      time: '',
      categories: cats,
      images: cover.isEmpty ? const <String>[] : <String>[cover],
      intro: intro,
      videos: videos,
      tags: tags,
      related: related,
      duration: '',
      seriesPrefix: '',
    );

    if (AppSettings.i.logConsole) {
      debugPrint('[DETAIL] ${_f.site.name} path=${path.length <= 80 ? path : path.substring(0, 80)} '
          '视频=${det.videos.length} 图=${det.images.length} 相关=${det.related.length} '
          '标签=${det.tags.length} ms=${sw.elapsedMilliseconds}');
    }
    return det;
  }

  // ---------------------------------------------------------------- 取源

  /// ★ 本站**必须自己取源**（通用 `.dplayer[data-config]` 这套页面里根本没有）：
  ///   ① 播放页 → `data-heitao-player-src` 的播放器路径
  ///   ② 播放器页（**带年龄 cookie**）→ `var player_aaaa={…}` 里的 `url`
  /// 返回 `null` = 不是本站播放页（交回底座老路）；返回空列表 = 抓了但没有源（播放器照旧提示）
  @override
  Future<List<String>?> fetchSources(String url) async {
    final path = _toRelPath(url);
    if (!path.contains('/vod/play/')) return null;
    final sw = Stopwatch()..start();

    // ① 播放页里找播放器 iframe 路径
    String playerPath = '';
    try {
      final html = await _text(path);
      final m = RegExp(r'data-heitao-player-src="([^"]+)"').firstMatch(html);
      if (m != null) playerPath = m.group(1)!.trim();
    } catch (e) {
      if (AppSettings.i.logConsole) {
        debugPrint('[SRC] ${_f.site.name} 播放页取不到 path=$path 原因=$e');
      }
    }
    if (playerPath.isEmpty) {
      if (AppSettings.i.logConsole) {
        debugPrint('[SRC] ${_f.site.name} 播放页里没找到播放器路径 path=$path');
      }
      return const <String>[];
    }

    // ② 播放器页（带年龄 cookie）→ player_aaaa.url
    try {
      final r = await _f.client.get(
        Uri.parse('https://${_f.host}$playerPath'),
        headers: {
          'User-Agent': Site.ua,
          'Referer': 'https://${_f.host}$path',
          'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
          'Cookie': _kAgeCookie,
        },
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        final body = utf8.decode(r.bodyBytes);
        final m = RegExp(r'var\s+player_aaaa\s*=\s*(\{[\s\S]*?\})</script>')
            .firstMatch(body);
        if (m != null) {
          final j = jsonDecode(m.group(1)!);
          if (j is Map) {
            final u = '${j['url'] ?? ''}'.trim();
            if (u.isNotEmpty) {
              if (AppSettings.i.logConsole) {
                debugPrint('[SRC] ${_f.site.name} 取源成功 from=${j['from']} '
                    'host=${Uri.tryParse(u)?.host ?? '?'} '
                    'ms=${sw.elapsedMilliseconds} path=$path');
              }
              return <String>[u];
            }
          }
        }
        if (AppSettings.i.logConsole) {
          debugPrint('[SRC] ${_f.site.name} 播放器页没解析到 player_aaaa.url '
              'HTTP=${r.statusCode} len=${r.bodyBytes.length} ms=${sw.elapsedMilliseconds}');
        }
      } else if (AppSettings.i.logConsole) {
        debugPrint('[SRC] ${_f.site.name} 播放器页 HTTP ${r.statusCode} '
            'path=$playerPath ms=${sw.elapsedMilliseconds}');
      }
    } catch (e) {
      if (AppSettings.i.logConsole) {
        debugPrint('[SRC] ${_f.site.name} 播放器页异常 $e');
      }
    }
    return const <String>[];
  }
}

// ---------------------------------------------------------------- 站点档案

/// 本站档案：黑桃短剧（heitaodj.com）
///
/// 🛢️ 实测（2026-11-15）：MacCMS 内核；封面 200×300 竖图 ⇒ `portraitCovers: true`；
///   详情页有「同类推荐」⇒ `showRelated` 用默认 true。
///
/// ★ 2026-11-15（用户反馈「少了首页」+「分类下面的子分类没加」）—— 两块都补上：
///   · **首页 tab** = `SiteTab('/home', '首页')`（路由见 `category()`）
///   · **子分类**：每个主分类页顶部有两道 classifyList，第 2 道就是子分类（原文实测）：
///       现代都市(1)：全部1 / 校园爱情64 / 情感爱恋11 / 职场权色12 / 家庭纠葛13 /
///                    逆袭打脸14 / 群芳后宫15 / 年代风月16 / 都市其他17
///       古装传奇(2)：全部2 / 宫廷权谋21 / 武侠江湖22 / 古装言情23 / 后宫争宠24 / 古装其他25
///       仙侠玄幻(3)：全部3 / 宗门情仇31 / 双修升级32 / 系统逆袭33 / 仙侠其他34
///       科幻脑洞(4)：全部4 / 未来科幻41 / 游戏副本42 / 异能超能43 / 身体奇谭44 / 末世求生45 / 科幻其他46
///       灵异悬疑(5)：全部5 / 都市怪谈51 / 鬼艳志怪52 / 悬疑反转53 / 灵异其他54
///       其他短剧(6)：全部6 / 综合脑洞61 / 未分类型62
///     ⚠️ 子分类走 `/index.php/vod/show/id/<id>.html`（**不是** type），所以 key 统一 `'/show/<id>'`
const SiteEntry kSite19 = SiteEntry(
  name: '黑桃短剧',
  template: SiteTemplate.heitao,
  hosts: ['heitaodj.com'],
  portraitCovers: true,
  // ★ 2026-11-15（用户要求「图标你自己画一个这个样式的，不要黑边」）：
  //   内置图标 = 橙渐变圆角方块 + 黑色黑桃（♠），128×128 透明底，**无边框** ✅
  assetIcon: 'assets/site_icons/heitaodj.png',
  iconUrl: '/favicon.ico', // 留档用（实际显示走 assetIcon，零网络）
  categories: [
    SiteTab('/home', '首页'),
    SiteTab('1', '现代都市', [
      SiteTab('/show/1', '全部'),
      SiteTab('/show/64', '校园爱情'),
      SiteTab('/show/11', '情感爱恋'),
      SiteTab('/show/12', '职场权色'),
      SiteTab('/show/13', '家庭纠葛'),
      SiteTab('/show/14', '逆袭打脸'),
      SiteTab('/show/15', '群芳后宫'),
      SiteTab('/show/16', '年代风月'),
      SiteTab('/show/17', '都市其他'),
    ]),
    SiteTab('2', '古装传奇', [
      SiteTab('/show/2', '全部'),
      SiteTab('/show/21', '宫廷权谋'),
      SiteTab('/show/22', '武侠江湖'),
      SiteTab('/show/23', '古装言情'),
      SiteTab('/show/24', '后宫争宠'),
      SiteTab('/show/25', '古装其他'),
    ]),
    SiteTab('3', '仙侠玄幻', [
      SiteTab('/show/3', '全部'),
      SiteTab('/show/31', '宗门情仇'),
      SiteTab('/show/32', '双修升级'),
      SiteTab('/show/33', '系统逆袭'),
      SiteTab('/show/34', '仙侠其他'),
    ]),
    SiteTab('4', '科幻脑洞', [
      SiteTab('/show/4', '全部'),
      SiteTab('/show/41', '未来科幻'),
      SiteTab('/show/42', '游戏副本'),
      SiteTab('/show/43', '异能超能'),
      SiteTab('/show/44', '身体奇谭'),
      SiteTab('/show/45', '末世求生'),
      SiteTab('/show/46', '科幻其他'),
    ]),
    SiteTab('5', '灵异悬疑', [
      SiteTab('/show/5', '全部'),
      SiteTab('/show/51', '都市怪谈'),
      SiteTab('/show/52', '鬼艳志怪'),
      SiteTab('/show/53', '悬疑反转'),
      SiteTab('/show/54', '灵异其他'),
    ]),
    SiteTab('6', '其他短剧', [
      SiteTab('/show/6', '全部'),
      SiteTab('/show/61', '综合脑洞'),
      SiteTab('/show/62', '未分类型'),
    ]),
  ],
  color: Color(0xFF1B1B1F), // 站点是深色主题（theme-color #0d0f14）
);

// ===== 自管整页（首页按站点真实分区块 ✅）=====

/// 首页一个分区：标题 + 卡片 +（可选）「更多」对应的分类 key
class HtSection {
  const HtSection({required this.title, required this.items, this.moreKey});

  final String title;
  final List<Article> items;

  /// 有「更多」时 = 该分类的主 key（`1`~`6`）；点它切到对应分类 tab
  final String? moreKey;
}

/// 分类页顶部的一枚胶囊
class HtChip {
  const HtChip(this.name, this.key);

  final String name;

  /// `/show/<id>` = 「分类」行 · `/type/<id>` = 「子分类」行 · `tag:<编码名>` = 「标签」行
  final String key;
}

/// 分类页顶部三行（频道不算 —— 那一行就是 App 的 tab）
class HtClassify {
  const HtClassify({required this.cats, required this.subs, required this.tags});

  final List<HtChip> cats;
  final List<HtChip> subs;
  final List<HtChip> tags;
}

/// 黑桃短剧 自管整页：Tab = 首页 + 6 个分类；首页按站点真实分区块排版
class HtHomePage extends StatefulWidget {
  const HtHomePage({super.key, required this.site, required this.ui});

  final SiteEntry site;
  final HeitaoSite ui;

  @override
  State<HtHomePage> createState() => _HtHomePageState();
}

class _HtHomePageState extends State<HtHomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab =
      TabController(length: widget.site.categories.length, vsync: this);

  List<HtSection> _secs = const [];
  bool _loading = true;
  String _err = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _err = '';
      });
    }
    try {
      final html = await widget.ui.textDesktop('/');
      final secs = widget.ui.parseSections(html);
      if (!mounted) return;
      setState(() {
        _secs = secs;
        _loading = false;
      });
      if (AppSettings.i.logConsole) {
        final n = secs.fold<int>(0, (a, b) => a + b.items.length);
        debugPrint('[HOME] ${widget.site.name} 分区=${secs.length} 卡片=$n '
            '块=${secs.map((s) => "${s.title}(${s.items.length})").join(" / ")}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = '$e';
        _loading = false;
      });
      if (AppSettings.i.logConsole) {
        debugPrint('[HOME] ${widget.site.name} 首页加载失败 $e');
      }
    }
  }

  void _openMore(String key) {
    final i = widget.site.categories.indexWhere((c) => c.key == key);
    if (i >= 0) _tab.animateTo(i);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          systemOverlayStyle: kStatusOverlay,
          title: Text(widget.site.name),
          centerTitle: true,
          foregroundColor: kTxt,
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: '搜索',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  settings: const RouteSettings(name: '搜索'),
                  builder: (_) => PageBg(child: SearchPage(site: widget.site)),
                ),
              ),
            ),
          ],
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
            tabs: [for (final c in widget.site.categories) Tab(text: c.name)],
          ),
        ),
        body: TabBarView(
          controller: _tab,
          children: [
            for (final c in widget.site.categories)
              c.key == '/home'
                  ? _homeBody()
                  : _HtCatTab(
                      site: widget.site,
                      ui: widget.ui,
                      tabKey: c.key,
                      subs: c.subs,
                    ),
          ],
        ),
      ),
    );
  }

  Widget _homeBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err.isNotEmpty) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.only(top: 120),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text('加载失败：$_err',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kTxtSub, fontSize: 14)),
            ),
          ),
        ),
      ]);
    }
    if (_secs.isEmpty) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.only(top: 120),
          child: Center(
              child: Text('没有数据（接口返回 0 条）',
                  style: TextStyle(color: kTxtSub, fontSize: 14))),
        ),
      ]);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        itemCount: _secs.length,
        itemBuilder: (context, i) => _sectionRow(_secs[i]),
      ),
    );
  }

  Widget _sectionRow(HtSection s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 6),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 14,
                margin: const EdgeInsets.only(right: 6),
                color: const Color(0xFFE8590C),
              ),
              Text(s.title,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: kTxt)),
              const Spacer(),
              if (s.moreKey != null)
                InkWell(
                  onTap: () => _openMore(s.moreKey!),
                  child: Row(children: [
                    Text('更多', style: TextStyle(fontSize: 12, color: kTxtSub)),
                    Icon(Icons.chevron_right, size: 16, color: kTxtSub),
                  ]),
                ),
            ],
          ),
        ),
        // ★ 2026-11-15（用户：「去除卡片样式，参考黄果」）：卡片不再是白色 Card，
        //   改成黄果那套**透明底 + 圆角封面 + 角标 + 标题 + 分类**（先例：`huangguo.dart:1509 _card`）
        //   高度 = 128×4/3(封面) + 46（标题 17 + 分类 14 + 间距）
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: s.items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) =>
                _HtCard(article: s.items[i], site: widget.site, width: 128),
          ),
        ),
      ],
    );
  }
}

/// 单个分类 tab：子分类胶囊行 + 三列网格 + 滚到底自动翻页
class _HtCatTab extends StatefulWidget {
  const _HtCatTab({
    required this.site,
    required this.ui,
    required this.tabKey,
    required this.subs,
  });

  final SiteEntry site;
  final HeitaoSite ui;
  final String tabKey;
  final List<SiteTab> subs;

  @override
  State<_HtCatTab> createState() => _HtCatTabState();
}

class _HtCatTabState extends State<_HtCatTab> {
  final List<Article> _items = [];
  final ScrollController _scroll = ScrollController();
  int _page = 1;
  bool _loading = false;
  bool _done = false;
  String _err = '';

  /// ★ 2026-11-15（用户："切顶栏 tab 会提示「没有数据（接口返回 0 条）」"）：
  ///   根因 = **首帧空窗**：切 tab 后要先等 `_init()` 抓分类页（~300ms）再发列表请求，
  ///   这段时间 `_items` 空、`_loading` 又是 false ⇒ 被当成"拉完了但 0 条" ☠
  ///   ⇒ 加 `_ready`：**首轮请求真正返回之前一律显示转圈**，不显示空态 ✅
  bool _ready = false;

  /// 分类页顶部三行（分类 / 子分类 / 标签）—— 由 [HeitaoSite.parseClassify] 解析
  HtClassify? _cls;
  String _sel = '';

  String get _key => _sel.isNotEmpty
      ? _sel
      : (widget.subs.isNotEmpty ? widget.subs.first.key : widget.tabKey);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 400) {
        _load();
      }
    });
    _init();
  }

  /// ① 先用**桌面 UA** 抓分类页，解析顶部三行；② 再拉列表
  Future<void> _init() async {
    try {
      final html = await widget.ui
          .textDesktop('/index.php/vod/type/id/${widget.tabKey}.html');
      final cls = widget.ui.parseClassify(html);
      if (!mounted) return;
      setState(() {
        _cls = cls;
        _sel = cls.cats.isNotEmpty
            ? cls.cats.first.key
            : (widget.subs.isNotEmpty ? widget.subs.first.key : widget.tabKey);
      });
      if (AppSettings.i.logConsole) {
        debugPrint('[CLASSIFY] ${widget.site.name} tab=${widget.tabKey} '
            '分类=${cls.cats.length} 子分类=${cls.subs.length} 标签=${cls.tags.length}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sel = widget.subs.isNotEmpty ? widget.subs.first.key : widget.tabKey;
      });
      if (AppSettings.i.logConsole) {
        debugPrint('[CLASSIFY] ${widget.site.name} tab=${widget.tabKey} '
            '顶部筛选取不到 $e');
      }
    }
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (!reset && _done) return;
    setState(() {
      _loading = true;
      if (reset) _err = '';
    });
    final p = reset ? 1 : _page;
    final k = _key;
    try {
      final List<Article> next;
      if (k.startsWith('tag:')) {
        // 「标签」行 ⇒ 标签页
        next = await widget.ui.tag(k.substring(4), page: p);
      } else {
        next = await widget.ui.category(widget.tabKey, page: p, k: k);
      }
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(next);
        _page = p + 1;
        if (next.isEmpty) _done = true;
        _err = '';
        _loading = false;
        _ready = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = '$e';
        _loading = false;
        _done = true;
        _ready = true;
      });
      if (AppSettings.i.logConsole) {
        debugPrint('[LIST] ${widget.site.name} 分类 $k 第$p页失败 $e');
      }
    }
  }

  void _pick(String key) {
    if (key == _sel) return;
    setState(() {
      _sel = key;
      _page = 1;
      _done = false;
      _items.clear();
    });
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ★ 2026-11-15（用户：站点分类页有 分类 / 子分类 / 标签 **三排**，我原来只做了「分类」一排）
          //   现在三排都画：没数据的那排自动不占位 ✅
          // ★ 2026-11-15（用户指定）：**只有「现代都市」画子分类这一排**
          //   其余 5 个 tab（古装传奇/仙侠玄幻/科幻脑洞/灵异悬疑/其他短剧）的子分类与「分类」
          //   几乎是同一份（实测：type2 分类=全部+5 个 / 子分类=同样 5 个）⇒ 重复，去掉 ✅
          if (_cls != null) ...[
            _chipRow('分类', _cls!.cats),
            if (widget.tabKey == '1') _chipRow('子分类', _cls!.subs),
            _chipRow('标签', _cls!.tags),
          ],
          Expanded(child: _grid()),
        ],
      ),
    );
  }

  /// 一排胶囊：左侧标签（照站点 `分类：` / `子分类：` / `标签：`），右侧横滑
  Widget _chipRow(String label, List<HtChip> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 46,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 10, right: 4),
            child: Text(label,
                style: TextStyle(fontSize: 12, color: kTxtSub)),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 10, top: 8, bottom: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final s = items[i];
                final on = _key == s.key;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _pick(s.key),
                  child: Container(
                    height: 30,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: on
                          ? const Color(0xFFF97316)
                          : (AppBg.i.isDark
                              ? const Color(0x1AFFFFFF)
                              : const Color(0xFFF2F2F4)),
                      borderRadius: BorderRadius.circular(9),
                      border: on
                          ? null
                          : Border.all(
                              color: AppBg.i.isDark
                                  ? const Color(0x26FFFFFF)
                                  : const Color(0x14000000)),
                    ),
                    child: Text(
                      s.name,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.0,
                        color: on ? Colors.white : kTxt,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid() {
    if (_items.isEmpty) {
      // 首轮还没回来（含"先抓分类页"的那段）⇒ 转圈，**不要**显示"没有数据"
      if (_loading || !_ready) {
        return const Center(child: CircularProgressIndicator());
      }
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.only(top: 120),
          child: Center(
            child: Text(
              _err.isEmpty ? '没有数据（接口返回 0 条）' : '加载失败：$_err',
              textAlign: TextAlign.center,
              style: TextStyle(color: kTxtSub, fontSize: 14),
            ),
          ),
        ),
      ]);
    }
    // 格子高度按**实际格宽**算：封面 3:4 + 文字 ≈46
    //（2026-11-15 用户实机报黄色溢出条 ⇒ 原来写死 childAspectRatio 0.54 不够高 ✅ 已改成算出来）
    return LayoutBuilder(
      builder: (context, cs) {
        const pad = 10.0;
        const gap = 8.0;
        final cellW = (cs.maxWidth - pad * 2 - gap * 2) / 3;
        final cellH = cellW * 4 / 3 + 46;
        return GridView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(pad, 4, pad, 20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            mainAxisExtent: cellH,
          ),
          itemCount: _items.length,
          itemBuilder: (context, i) =>
              _HtCard(article: _items[i], site: widget.site, width: cellW),
        );
      },
    );
  }
}

/// 本站卡片 —— **照黄果那套做**（用户 2026-11-15：「去除卡片样式，参考黄果」）
///
/// 形态（先例 `lib/sites/huangguo.dart:1509 _card()`，**只参考、黄果一个字没改** ✅）：
///   · **没有**白色 Card / 阴影 / 外边距 —— 直接贴在页面上
///   · 封面 `ClipRRect(radius 6)` + 3:4 固定比例；封面空 → 淡灰占位
///   · 右下角角标 = 集数（黑底 60% + 圆角 3 + 9 号白字）
///   · 标题 12/w600（单行省略）；下面一行 10 号浅字 = 站点分类名
class _HtCard extends StatelessWidget {
  const _HtCard({
    required this.article,
    required this.site,
    required this.width,
  });

  final Article article;
  final SiteEntry site;
  final double width;

  @override
  Widget build(BuildContext context) {
    final h = width * 4 / 3; // 竖版站 3:4（档案 portraitCovers: true）
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: '详情页'),
          builder: (_) => PageBg(
            child: DetailPage(
              site: site,
              baseUrl: article.url,
              listCover: article.cover,
            ),
          ),
        ),
      ),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: width,
                height: h,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (article.cover.isEmpty)
                      Container(color: const Color(0x223C3C3C))
                    else
                      FetchedImage(url: article.cover, memWidth: 360),
                    if (article.badge.isNotEmpty)
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
                          child: Text(article.badge,
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
              article.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: kTxt),
            ),
            if (article.meta.isNotEmpty)
              Text(
                article.meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: kTxtSub, height: 1.25),
              ),
          ],
        ),
      ),
    );
  }
}
