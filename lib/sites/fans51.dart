// 51fans.net（www.51fans.net）—— **本站专属**的一切 ✅
//
// ★ 2026-10-12（用户拍板"探测完直接做" ✅）：**独立站点文件**（本站是**自研模板**，不是 WordPress 系 ☠
//   ⇒ 不落 `wordpress.dart`；与既有 `51fans`（kSite05，宿主 51fans1.com）是**两个不同站** ✅
//   ⇒ 入口名用 `51fans.net` 避免重名 ✅）
//
// 【🛢️ 本机实测（2026-10-12，移动 UA 抓页面、桌面 UA 抓详情）】
//   · 列表卡：`li.section-content__item` → `a[href="/video/<数字id>/"]`
//       · 封面 `.item-cover img[data-src]`（cloudfront 直链，**无扩展名** ✅、取图**不需要头** ✅，
//         但 `Content-Type` 给的是 `text/base64.jpg`（内容其实是 PNG）☠ ⇒ **别按 MIME 判** ✅）
//       · 时长 `.item-cover-overlay .cover-duration`（如 `52:59` ✅）
//       · 标题 `.item-texts h3.text-truncate` · 播放量 `.text-social .eye` · 标签 `.tag-items .tag-item span[data-link]`
//       ⚠️ **有广告卡**：`<li class="section-content__item module-two">` 里是**站外跳转**（`App.adsClick` / 外链）
//          ⇒ **只认 `a[href^="/video/"]` 的卡**，其余一律跳过 ✅（本机实测：分类页 44 个 li = 20 真卡 + 24 广告 ✅）
//   · 分页 = **路径式**：`/category/cate17/<n>/` ✅（本机实测 `page-link` 指向 `/category/cate17/2/`… ✅；每页 45 条 ✅）
//   · 顶部 **11 个组**（`div.navItem[data-link]` + 标签在 `div.navBtn` ✅，本机实测配对如下 ✅）：
//       网黄 `/group-category/recommend/`（⚠️ **站点自己就把「网黄/性癖/少女」三个组指到同一个 recommend 路径** ✅ 照实）
//       性癖 同 recommend · 乱伦 `/group-category/cate61/` · 少女 同 recommend · 直播 `/group-category/cate76/`
//       日韩 `/group-category/cate86/` · 传媒 `/group-category/cate109/` · 动漫 `/group-category/cate126/`
//       欧美 `/group-category/cate138/` · 性爱教学 `/group-category/cate156/` · 综合 `/group-category/cate171/`
//     · 每个组的下拉项（`div.dropdownBox > a.dropdownItem[href="/category/cateNN/"]`）**首页共 335 条** ✅
//       ☑️ **已落地**：采样得 **161 条**（去重后按组归属 ✅），做成**顶栏 tab 的悬浮抽屉**
//          （`tabDrawer => true` ✅；点 tab = 展开/收起；面板**竖排**、宽度=最长字符、可上下滑 ✅）
//       ⚠️ **还有一处导航没在组下拉里**：`a.menu-item[href="/category/cate155/"]` = **AI换脸**
//          （全站仅此 1 个这类 ✅）⇒ 已按用户要求放进 **综合组第一位** ✅
//   · 详情 `/video/<数字id>/`：标题 `h1.only-pc`（= `h2.vdetail-title` ✅ 两者同文）· 发布时间 = JSON-LD
//     `"datePublished":"2026-04-16 19:20:26"` ✅ · 标签 `.vdetail-intro … a[href^="/tag/"]` ✅ ·
//     简介在 `.vdetail-social` 的 `#pills-home` ✅ · 推荐块 = `.vdetail-right`（真站叫法 **「每日精选」** ✅，
//     ⚠️ 该 `h3` 取到的是**剧名**（站点结构如此 ✅）⇒ 标题按用户口径用「每日精选」✅）+ 条目 `a.vdetail-right__item` ✅
//   · **源**：页面内联 `window.__ARCHIVE_PLAYER__ = {"rawPath":"/video/<日期>/<时>/<id>/<hash>.m3u8",
//     "cdnLine":"https://d2qyuoh1tjbp7d.cloudfront.net",…}` ⇒ **播放地址 = `cdnLine + rawPath`** ✅
//     · 另有 `var cdn_lines = '[{cdnLine,…},…]'` 多线路（本机实测**第二条原文是 `https:/` 单斜杠** ☠ ⇒ 必须容错 ✅）
//     · media playlist（AES-128，key = m3u8 **同 host** 的 `/keyhome/video.key` ✅）· **不需要任何请求头** ✅
//     ⚠️ 本机实测注意：详情页 `rawPath` 里带的 id（`2033427824212946944`）与**页面 id**（`2044313930640719872`）
//       **不一样** ☑️（推测 = 平台保留的**原始上传**媒体路径，页面是再发布 ✅）⇒ 我们**照 recon 口径**用
//       `cdnLine + rawPath`，但**把两个 id 都打进日志**，方便日后对照 ✅

import 'dart:convert'; // JSON-LD / 播放器 JSON

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as hp;

import '../base/fetch.dart';
import '../base/site_ui.dart';
import '../models.dart';
import '../settings.dart';
import '../sites.dart' show SiteEntry, SiteTab, SiteTemplate;

/// 51fans.net 本站实现（取数走公用底座 [SiteFetcher] ✅）
class Fans51Site extends SiteUi {
  Fans51Site(this._f);

  final SiteFetcher _f;

  static const String _kHost = 'www.51fans.net';
  static const String _kBase = 'https://$_kHost';

  /// 🛢️ 本机实测：**列表页用移动 UA** 才带导航 `data-link`；**详情页要用桌面 UA** 才有
  ///   `window.__ARCHIVE_PLAYER__`（移动 UA 抓到的详情页里**没有**播放器 JSON ☠）⇒ 分开 ✅
  static const String _kUaMobile =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
  static const String _kUaDesk =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  static const Duration _kTimeout = Duration(seconds: 15);

  // ===== 取数 =====

  Future<String> _get(String path, {bool desktop = false}) async {
    final u = path.startsWith('http') ? path : '$_kBase$path';
    final r = await _f.client
        .get(Uri.parse(u), headers: {
          'User-Agent': desktop ? _kUaDesk : _kUaMobile,
          'Accept-Language': 'zh-CN,zh;q=0.9',
        })
        .timeout(_kTimeout);
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }

  static String _abs(String u) {
    final s = u.trim();
    if (s.isEmpty) return '';
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    return s.startsWith('/') ? '$_kBase$s' : '$_kBase/$s';
  }

  /// 「45 条一页、路径式分页」：`<path><n>/`（🛢️ 实测 `/category/cate17/2/` ✅）
  static String _paged(String path, int page) {
    final p = path.endsWith('/') ? path : '$path/';
    return page <= 1 ? p : '$p$page/';
  }

  @override
  Future<List<Article>> home({required int page, String first = ''}) async {
    final sw = Stopwatch()..start();
    // 首页第 1 页 = `/`；翻页按站点风格试 `/page/<n>/`（☑️ 未实测 ⇒ 拿不到就空 + 日志，不猜别处）
    final path = page <= 1 ? '/' : '/page/$page/';
    final html = await _get(path);
    final out = _cards(html, '首页');
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 入口=home 页=$page 路径=$path '
          '解析出 ${out.length} 条 ms=${sw.elapsedMilliseconds}');
    }
    return out;
  }

  @override
  Future<List<Article>> category(String key,
      {required int page, String? k, String? theme, String? duration, String? sort,
      List<MapEntry<String, String>>? extra,
      Future<List<Article>> Function({int page})? home}) async {
    final sw = Stopwatch()..start();
    // ★ 2026-10-15 修（**用户实测**：抽屉里点分类 ⇒ 列表没切换 ☠）：
    //   底座把"当前选中的子分类"放在 **`k`** 里传进来（日志原文：
    //   `k=/group-category/recommend/` + 选中后 `k=/category/cate24/ sub=/category/cate24/` ✅）
    //   而本方法原来**只用了 `key`**（= tab 的组链接）⇒ 永远拉组列表（132 条）☠
    //   ⇒ 现在：**有 `k` 就用 `k`**（子分类优先 ✅），没有才退回 `key` ✅
    //   · key 可能是 `/group-category/xxx/`、`/category/cateNN/`、也可能是裸 `cateNN` ✅
    final raw = (k != null && k.trim().isNotEmpty) ? k.trim() : key;
    final path = raw.startsWith('/') ? raw : '/category/$raw/';
    // ★ 2026-10-15 修：**分组页没有翻页**（实测 `/group-category/…/2/` 解析出 0 条 ☠）
    //   ⇒ 第 2 页起直接返回空（底座据此判 done ✅，少发一次无用请求 ✅）
    if (page > 1 && path.startsWith('/group-category/')) return const [];
    final html = await _get(_paged(path, page));
    final out = _cards(html, '分类');
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 入口=分类 k=$key'
          '${raw == key ? '' : ' → 用子分类=$raw ✅'} 页=$page 路径=${_paged(path, page)} '
          '解析出 ${out.length} 条 ms=${sw.elapsedMilliseconds}');
    }
    return out;
  }

  @override
  Future<List<Article>> tag(String slug, {required int page}) async {
    final sw = Stopwatch()..start();
    final path = slug.startsWith('/') ? slug : '/tag/$slug/';
    final html = await _get(_paged(path, page));
    final out = _cards(html, '标签');
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 入口=tag slug=$slug 页=$page '
          '解析出 ${out.length} 条 ms=${sw.elapsedMilliseconds}');
    }
    return out;
  }

  @override
  Future<List<Article>> search(String keyword,
      {int page = 1, List<MapEntry<String, String>>? extra}) async {
    final sw = Stopwatch()..start();
    final kw = keyword.trim();
    if (kw.isEmpty) return const <Article>[];
    // 🛢️ 实测形态：`/search/<encodeURIComponent(关键词)>/`
    final path = '/search/${Uri.encodeComponent(kw)}/';
    final html = await _get(_paged(path, page));
    final out = _cards(html, '搜索');
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 入口=search 词=$kw 页=$page '
          '解析出 ${out.length} 条 ms=${sw.elapsedMilliseconds}');
    }
    return out;
  }

  // ===== 列表解析（**只认站内 `/video/<id>/` 卡；广告卡跳过** ✅）=====

  List<Article> _cards(String html, String entry) {
    final doc = hp.parse(html);
    final out = <Article>[];
    final seen = <String>{};
    for (final li in doc.querySelectorAll('li.section-content__item')) {
      final a = li.querySelector('a[href^="/video/"]');
      if (a == null) continue; // ☠ 广告卡（外链 / App.adsClick）⇒ 跳过 ✅
      final href = a.attributes['href'] ?? '';
      if (href.isEmpty || !seen.add(href)) continue;
      final img = li.querySelector('.item-cover img');
      final cover = _abs(img?.attributes['data-src'] ??
          img?.attributes['src'] ??
          '');
      final dur = (li.querySelector('.cover-duration')?.text ?? '').trim();
      final h3 = li.querySelector('.item-texts h3') ?? li.querySelector('h3');
      var title = (h3?.text ?? '').trim();
      if (title.isEmpty) title = (img?.attributes['alt'] ?? '').trim();
      final eye = (li.querySelector('.text-social .eye')?.text ?? '').trim();
      final tagEls = li.querySelectorAll('.tag-items .tag-item span[data-link]');
      final tags = <MapEntry<String, String>>[];
      for (final t in tagEls) {
        final link = (t.attributes['data-link'] ?? '').trim();
        final name = t.text.trim();
        if (link.isNotEmpty && name.isNotEmpty) tags.add(MapEntry(link, name));
      }
      if (title.isEmpty || cover.isEmpty) continue;
      out.add(Article(
        url: href, // 站内路径（`/video/<id>/` ✅）
        title: title,
        cover: cover,
        // 卡片角标口径：**时长 ＞ 集数 ＞ 播放量**（DEVLOG §一:12 ✅；本站无集数 ✅）
        badge: dur.isNotEmpty ? dur : eye,
        meta: eye, // 副行 = 播放量（站上 `.text-eye` ✅）
      ));
    }
    if (AppSettings.i.logConsole && out.isEmpty) {
      debugPrint('[LIST] ${_f.site.name} 入口=$entry ⚠️ 0 条（广告卡已跳过；若整页空 ⇒ 选择器可能变了）');
    }
    return out;
  }

  // ===== 详情 =====

  @override
  Future<ArticleDetail> detail(String url) async {
    final sw = Stopwatch()..start();
    final target = _abs(url);
    // ★ 详情页必须用**桌面 UA**（🛢️ 实测：移动 UA 的详情页没有 `__ARCHIVE_PLAYER__` ✅）
    final html = await _get(target, desktop: true);

    // 标题：`h1.only-pc`（= `h2.vdetail-title` ✅）
    var title = (html.contains('h1.only-pc')) ? '' : '';
    final doc = hp.parse(html);
    title = (doc.querySelector('h1.only-pc')?.text ??
            doc.querySelector('h2.vdetail-title')?.text ??
            '')
        .trim();
    if (title.isEmpty) {
      title = (doc.querySelector('meta[property="og:title"]')?.attributes['content'] ?? '')
          .trim();
    }

    // 发布时间 = JSON-LD `datePublished`（🛢️ 原文 `2026-04-16 19:20:26` ✅）
    final time =
        RegExp('"datePublished"\\s*:\\s*"([^"]{4,40})"').firstMatch(html)?.group(1)?.trim() ?? '';

    // 标签：`.vdetail-intro … a[href^="/tag/"]`（兜底：全页 `/tag/` 链接 ✅）
    final tags = <MapEntry<String, String>>[];
    final seenTag = <String>{};
    for (final a in [
      ...doc.querySelectorAll('.vdetail-intro a[href^="/tag/"]'),
      ...doc.querySelectorAll('a[href^="/tag/"]'),
    ]) {
      final h = (a.attributes['href'] ?? '').trim();
      final n = a.text.trim();
      if (h.isEmpty || n.isEmpty || !seenTag.add(h)) continue;
      tags.add(MapEntry(h, n));
      if (tags.length >= 12) break;
    }

    // 简介：正文**只在** `p.vd-infos__desc` 里（🛢️ 2026-10-15 harness 实测：有简介的视频 = 105 字 ✅）
    //   ★ 2026-10-15 修（**用户实测抓到**：某个视频**没有简介**，我们却把整个 tab 当简介塞进去了 ☠）——
    //     现场原文（用户截图）：简介块里出现了「标签：/ 网黄 / 手机在线看 / 使用手机浏览器扫码观看 /
    //     标题重复 / 454.2K / 分享」⇒ 就是旧的**兜底**（`#pills-home` / `.vdetail-social`）吞的 ☠
    //   ⇒ **取消兜底** ✅：找不到 `vd-infos__desc` ⇒ **简介就是空**（不猜、不硬编 ✅）
    //   ⇒ 顺带：站点正文的**前缀是双层的**（🛢️ 2026-10-15 实测原文：`影片简介：简介：超骚潮妹…`
    //      / `影片简介：简介：极品熟女…`）⇒ 两层都要去掉，只留正文 ✅
    //   ⇒ 找不到就是空（不猜 ✅）；去掉前缀后 < 4 字也当空 ✅
    var intro =
        ((doc.querySelector('p.vd-infos__desc') ?? doc.querySelector('.vd-infos__desc'))?.text ??
                '')
            .trim();
    intro = intro.replaceFirst(RegExp(r'^(影片简介[:：]\s*)+'), '').trim();
    intro = intro.replaceFirst(RegExp(r'^(简介[:：]\s*)+'), '').trim();
    if (intro.length < 4) intro = '';
    if (intro.length > 2000) intro = '${intro.substring(0, 2000)}…'; // 防爆（正常不会触发 ✅）

    // 推荐块：真站叫「每日精选」（右栏竖排单列 ✅ —— 标题与版式由 SiteEntry/SiteUi 覆写给 ✅）
    final related = <Article>[];
    for (final a in doc.querySelectorAll('a.vdetail-right__item')) {
      final href = (a.attributes['href'] ?? '').trim();
      if (href.isEmpty) continue;
      final img = a.querySelector('.item-cover img');
      final cover = _abs(img?.attributes['data-src'] ??
          img?.attributes['src'] ??
          '');
      final dur = (a.querySelector('.cover-duration')?.text ?? '').trim();
      final t = (a.querySelector('h4.item-title')?.text ?? a.attributes['title'] ?? '').trim();
      if (t.isEmpty || cover.isEmpty) continue;
      related.add(Article(
        url: href,
        title: t,
        cover: cover,
        badge: dur,
        meta: '',
      ));
      if (related.length >= 12) break;
    }

    // 源（先在这里取一次 ⇒ 播放时直接可用；刷新时另有 [sourcesFromHtml] 兜底 ✅）
    final srcs = _sources(html, target);

    final det = ArticleDetail(
      title: title,
      time: time,
      categories: const [], // 本站没有"分类 slug"体系 ⇒ 不塞（塞了会变死链 ☠）；可点的标签走 tags ✅
      images: const [], // 本站**没有剧照/图集** ⇒ 传空 ⇒ 整块不显示 ✅（DEVLOG §一:20/22 ✅）
      intro: intro,
      videos: [
        if (srcs.isNotEmpty || title.isNotEmpty)
          ArticleVideo(
            label: '正片',
            ordinal: 1,
            sources: srcs, // 条目自带源优先（0 网络 ✅）；取不到 ⇒ 空 ⇒ 底座会按 [sourcesFromHtml] 再取 ✅
            lazyUrl: srcs.isEmpty ? target : null,
          ),
      ],
      tags: tags,
      related: related,
      seriesPrefix: '', // 本站没有"系列/选集"概念（一视频一页 ✅）
    );
    if (AppSettings.i.logConsole) {
      debugPrint('[DETAIL] ${_f.site.name} 标题=${title.length <= 24 ? title : '${title.substring(0, 24)}…'} '
          '时间=$time 标签=${tags.length} 简介=${intro.length}字 推荐=${related.length} 源=${srcs.length} '
          'ms=${sw.elapsedMilliseconds}');
    }
    return det;
  }

  /// 从详情页 HTML 里挖源（**站点自有解析** ✅）：`__ARCHIVE_PLAYER__` 的 `cdnLine + rawPath`，
  /// 外加 `cdn_lines` 里的其它线路（⚠️ 第二条原文是 `https:/` **单斜杠** ☠ ⇒ 统一补成 `https://` ✅）
  List<String> _sources(String html, String pageUrl) {
    final out = <String>[];
    void add(String cdn, String path) {
      var c = cdn.trim();
      var p = path.trim();
      if (c.isEmpty || p.isEmpty) return;
      // ☠ 站点的拼写错误容错：`https:/dfdf.tjacq.com` ⇒ `https://dfdf.tjacq.com`
      if (c.startsWith('https:/') && !c.startsWith('https://')) {
        c = 'https://${c.substring('https:/'.length)}';
      } else if (c.startsWith('http:/') && !c.startsWith('http://')) {
        c = 'http://${c.substring('http:/'.length)}';
      }
      final u = p.startsWith('/') ? '$c$p' : '$c/$p';
      if (!out.contains(u)) out.add(u);
    }

    // ① 主线路：`window.__ARCHIVE_PLAYER__ = { "rawPath":"…", "cdnLine":"…" }`（值是 JSON 转义过的 ✅）
    final m = RegExp(
            r'__ARCHIVE_PLAYER__\s*=\s*\{([\s\S]{0,4000}?)\}\s*;?\s*</script>')
        .firstMatch(html);
    if (m != null) {
      final body = m.group(1) ?? '';
      final raw = _jsonStr(body, 'rawPath');
      final cdn = _jsonStr(body, 'cdnLine');
      // 日志（**不打全串**：只打 host + 路径形态 ✅）
      if (AppSettings.i.logConsole) {
        final host = Uri.tryParse(cdn)?.host ?? cdn;
        final shape = raw.replaceAll(RegExp(r'[0-9a-fA-F]{16,}'), '<hash>');
        debugPrint('[SRC] ${_f.site.name} 播放器 cdnLine=$host rawPath=${shape.length <= 60 ? shape : shape.substring(0, 60)}');
      }
      add(cdn, raw);
    }

    // ② 其它线路：`var cdn_lines = '[{…}]'`（字符串里再套 JSON ✅）
    final ml = RegExp(r"cdn_lines\s*=\s*'([\s\S]{0,4000}?)'").firstMatch(html);
    if (ml != null) {
      try {
        final arr = jsonDecode(ml.group(1)!.replaceAll(r'\/', '/'));
        if (arr is List) {
          final raw = _jsonStrRaw(html);
          for (final e in arr) {
            if (e is Map) add('${e['cdnLine'] ?? ''}', raw);
          }
        }
      } catch (_) {}
    }
    return out;
  }

  /// 从 `{…}` 片段里取一个字符串字段（容忍 `\/` 转义 ✅）
  static String _jsonStr(String body, String key) {
    final m = RegExp('"$key"\\s*:\\s*"([^"]*)"').firstMatch(body);
    return (m?.group(1) ?? '').replaceAll(r'\/', '/').trim();
  }

  /// 单独取 rawPath（给"多线路"那步复用 ✅）
  static String _jsonStrRaw(String html) {
    final m = RegExp(r'__ARCHIVE_PLAYER__\s*=\s*\{([\s\S]{0,4000}?)\}\s*;?\s*</script>')
        .firstMatch(html);
    return m == null ? '' : _jsonStr(m.group(1) ?? '', 'rawPath');
  }

  /// 底座"刷新源/首次取源"走这里（返回非 null ⇒ 不再走通用 `.dplayer` 路径 ✅）
  @override
  List<String>? sourcesFromHtml(String html) {
    final list = _sources(html, '');
    if (AppSettings.i.logConsole) {
      debugPrint('[SRC] ${_f.site.name} sourcesFromHtml ⇒ ${list.length} 条');
    }
    return list.isEmpty ? const <String>[] : list;
  }

  /// ★ 推荐块标题：**真站叫法「每日精选」**（右栏 `h3` ✅ —— ⚠️ 本机实测该 `h3` 取到的是剧名，
  //     站点结构如此；用户口径要「每日精选」⇒ 这里写死站点叫法 ✅）
  @override
  String get relatedTitle => '每日精选';

  /// ★ 推荐块版式 = **竖排单列**（真站右栏 ✅）—— 底座默认就是单列，这里显式覆写以锁死口径 ✅
  @override
  bool get relatedAsGrid => false;

  /// ★ 2026-10-15（用户拍板"B 悬浮式" ✅）：顶栏 tab **点击展开悬浮抽屉**（底座 [SiteUi.tabDrawer] 钩子 ✅）
  @override
  bool get tabDrawer => true;
}

/// 本站档案：**51fans.net**（kSite17 ✅ 2026-10-12 新增）
///
/// 顶部 11 个组 = 🛢️ 本机实测 `div.navItem[data-link]` + `div.navBtn` 标签**配对**（顺序照真站 ✅）：
///   ⚠️ **站点自己**把「网黄 / 性癖 / 少女」三个组都指向 `/group-category/recommend/`（照实 ✅ 不改）
/// ☑️ 每组的子分类下拉（`div.dropdownBox > a.dropdownItem`，首页共 **335 条**）**本轮未落进代码**
///   ⇒ 子分类横滑行暂缺（lead 口径："别为抓全 335 条把时间耗光" ✅）
///   ⇒ 补法：拉首页 HTML，用 `div.navItem` 分块后取 `a.dropdownItem[href]`（中文名在链接文字里 ✅）
const SiteEntry kSite17 = SiteEntry(
  name: '51fans.net',
  template: SiteTemplate.fans51,
  hosts: ['www.51fans.net', '51fans.net'],
  iconUrl: '/favicon.ico', // ☑️ 未转 PNG（站点是 .ico；转不出就按规范走首字色块 ✅）
  portraitCovers: false, // ★ 横版 16:9 封面 ⇒ **双列**（DEVLOG §一:13 ✅）
  color: Color(0xFF06080C), // 站点主色（近黑 ✅）
  categories: [
    // ⚠️ **数据来源**：lead 采集的 `_tmp_fans51_subs.txt`（2026-10-15，真站首页导航 ✅）——
    //    11 组 / 子分类合计 **161** 条（26/17/6/7/9/22/16/11/16/14/17 ✅）
    //    ⚠️ 网黄 / 性癖 / 少女 **三组组链接相同**（`/group-category/recommend/`，真站如此 ✅）
    //       ⇒ **按组索引存**（不能按 link 去重 ☠ 会互相覆盖）
    //    ★ 每组第 1 项＝**「全部」**（key = 该组链接 ✅）⇒ 抽屉里「更多 ›」/组名点它就切到**组列表** ✅
    SiteTab('/group-category/recommend/', '网黄', [
      SiteTab('/group-category/recommend/', '全部'),
      SiteTab('/category/cate17/', '网黄合集'), SiteTab('/category/cate18/', '饼干姐姐'),
      SiteTab('/category/cate19/', '台北娜娜'), SiteTab('/category/cate20/', '桥本香菜'),
      SiteTab('/category/cate21/', '玩偶姐姐'), SiteTab('/category/cate22/', '😻黑猫露娜酱（小水水闺蜜）'),
      SiteTab('/category/cate23/', 'kittykum'), SiteTab('/category/cate24/', 'kitty'),
      SiteTab('/category/cate25/', '樱空桃桃'), SiteTab('/category/cate26/', 'ONLY FANS'),
      SiteTab('/category/cate27/', 'Naomiii'), SiteTab('/category/cate28/', '👠行简（抖音御姐）'),
      SiteTab('/category/cate29/', '小水水'), SiteTab('/category/cate30/', '苏畅'),
      SiteTab('/category/cate31/', '阿朱'), SiteTab('/category/cate32/', '御梦子'),
      SiteTab('/category/cate33/', 'hongkong doll'), SiteTab('/category/cate34/', '柚子猫'),
      SiteTab('/category/cate35/', 'cola酱'), SiteTab('/category/cate36/', '辛尤里'),
      SiteTab('/category/cate37/', '兔子米菲'), SiteTab('/category/cate38/', '米胡桃'),
      SiteTab('/category/cate39/', '狐不妖'), SiteTab('/category/cate40/', '鸡教练'),
      SiteTab('/category/cate41/', 'NicoLove'), SiteTab('/category/cate42/', '下面有根棒棒糖'),
    ]),
    SiteTab('/group-category/recommend/', '性癖', [
      SiteTab('/group-category/recommend/', '全部'),
      SiteTab('/category/cate44/', '🩱金主调教（精盆之物）'), SiteTab('/category/cate45/', '迷奸/强奸'),
      SiteTab('/category/cate46/', '骚浪反差婊'), SiteTab('/category/cate47/', 'SM调教'),
      SiteTab('/category/cate48/', '熟女少妇'), SiteTab('/category/cate49/', '绿帽/偷情'),
      SiteTab('/category/cate50/', '足交'), SiteTab('/category/cate51/', '肛交'),
      SiteTab('/category/cate52/', '百合女同'), SiteTab('/category/cate53/', '偷拍'),
      SiteTab('/category/cate54/', '孕妇'), SiteTab('/category/cate55/', '自慰潮吹'),
      SiteTab('/category/cate56/', '车震/野战'), SiteTab('/category/cate57/', '黑料吃瓜'),
      SiteTab('/category/cate58/', '口爆吞精'), SiteTab('/category/cate59/', 'TS人妖'),
      SiteTab('/category/cate60/', '男上加男'),
    ]),
    SiteTab('/group-category/cate61/', '乱伦', [
      SiteTab('/group-category/cate61/', '全部'),
      SiteTab('/category/cate62/', '乱伦合集'), SiteTab('/category/cate63/', '兄妹乱伦'),
      SiteTab('/category/cate64/', '父女乱伦'), SiteTab('/category/cate65/', '母子乱伦'),
      SiteTab('/category/cate66/', '姐弟乱伦'), SiteTab('/category/cate67/', '乱交群P'),
    ]),
    SiteTab('/group-category/recommend/', '少女', [
      SiteTab('/group-category/recommend/', '全部'),
      SiteTab('/category/cate69/', '少女精选'), SiteTab('/category/cate70/', '制服诱惑'),
      SiteTab('/category/cate71/', '女神尤物'), SiteTab('/category/cate72/', '童颜巨乳'),
      SiteTab('/category/cate73/', '白虎MM'), SiteTab('/category/cate74/', '学妹校花'),
      SiteTab('/category/cate75/', '清纯萝莉'),
    ]),
    SiteTab('/group-category/cate76/', '直播', [
      SiteTab('/group-category/cate76/', '全部'),
      SiteTab('/category/cate77/', '💘主播研究所（播你所愿）'), SiteTab('/category/cate78/', 'ASMR精选'),
      SiteTab('/category/cate79/', 'Yoonying'), SiteTab('/category/cate80/', '椰椰拿铁'),
      SiteTab('/category/cate81/', '璐璐哄睡屋'), SiteTab('/category/cate82/', 'yuuu'),
      SiteTab('/category/cate83/', 'ポメ子-波美子'), SiteTab('/category/cate84/', '高画質'),
      SiteTab('/category/cate85/', '阿郁的小黑猫'),
    ]),
    SiteTab('/group-category/cate86/', '日韩', [
      SiteTab('/group-category/cate86/', '全部'),
      SiteTab('/category/cate87/', '小编精选'), SiteTab('/category/cate88/', 'FC2 无码'),
      SiteTab('/category/cate89/', '韩国影片'), SiteTab('/category/cate90/', '伦理'),
      SiteTab('/category/cate91/', '素人'), SiteTab('/category/cate92/', '无码影片'),
      SiteTab('/category/cate93/', '中文字幕'), SiteTab('/category/cate94/', '轮奸强奸'),
      SiteTab('/category/cate95/', '巨乳'), SiteTab('/category/cate96/', '人妻少妇'),
      SiteTab('/category/cate97/', 'AV解说'), SiteTab('/category/cate98/', 'VR'),
      SiteTab('/category/cate99/', '无套内射'), SiteTab('/category/cate100/', '重口调教'),
      SiteTab('/category/cate101/', '波多野結衣'), SiteTab('/category/cate102/', '三上优雅'),
      SiteTab('/category/cate103/', '深田咏美'), SiteTab('/category/cate104/', '松本一香'),
      SiteTab('/category/cate105/', '河北彩花'), SiteTab('/category/cate106/', '瀬戸环奈'),
      SiteTab('/category/cate107/', '森泽佳奈'), SiteTab('/category/cate108/', '枫可怜 (田中柠檬)'),
    ]),
    SiteTab('/group-category/cate109/', '传媒', [
      SiteTab('/group-category/cate109/', '全部'),
      SiteTab('/category/cate110/', '传媒合集'), SiteTab('/category/cate111/', '蜜桃传媒'),
      SiteTab('/category/cate112/', '麻豆传媒'), SiteTab('/category/cate113/', '台湾swag'),
      SiteTab('/category/cate114/', '大象传媒'), SiteTab('/category/cate115/', '糖心传媒'),
      SiteTab('/category/cate116/', '91制片厂'), SiteTab('/category/cate117/', '乌托邦'),
      SiteTab('/category/cate118/', '爱神传媒'), SiteTab('/category/cate119/', '性世界传媒'),
      SiteTab('/category/cate120/', '精东传媒'), SiteTab('/category/cate121/', '果冻传媒'),
      SiteTab('/category/cate122/', '星空无限传媒'), SiteTab('/category/cate123/', '香蕉视频'),
      SiteTab('/category/cate124/', '爱豆传媒'), SiteTab('/category/cate125/', '天美传媒'),
    ]),
    SiteTab('/group-category/cate126/', '动漫', [
      SiteTab('/group-category/cate126/', '全部'),
      SiteTab('/category/cate127/', '里番'), SiteTab('/category/cate128/', '动态日漫'),
      SiteTab('/category/cate129/', '泡面番'), SiteTab('/category/cate130/', '国产同人'),
      SiteTab('/category/cate131/', '元神启动'), SiteTab('/category/cate132/', '斗破苍穹'),
      SiteTab('/category/cate133/', '斗罗大陆'), SiteTab('/category/cate134/', '完美世界'),
      SiteTab('/category/cate135/', '超清3D动漫'), SiteTab('/category/cate136/', 'Cosplay'),
      SiteTab('/category/cate137/', '其他'),
    ]),
    SiteTab('/group-category/cate138/', '欧美', [
      SiteTab('/group-category/cate138/', '全部'),
      SiteTab('/category/cate139/', '欧美精选'), SiteTab('/category/cate140/', '啄木鸟'),
      SiteTab('/category/cate141/', '黑人巨屌'), SiteTab('/category/cate142/', '洋马品鉴'),
      SiteTab('/category/cate143/', '萝莉'), SiteTab('/category/cate144/', '调教'),
      SiteTab('/category/cate145/', '戶外'), SiteTab('/category/cate146/', '菲律宾'),
      SiteTab('/category/cate147/', '泰國'), SiteTab('/category/cate148/', '印度'),
      SiteTab('/category/cate149/', '肛交'), SiteTab('/category/cate150/', '群交'),
      SiteTab('/category/cate151/', '老北鼻'), SiteTab('/category/cate152/', '杂交'),
      SiteTab('/category/cate153/', '69式'), SiteTab('/category/cate154/', '综合'),
    ]),
    SiteTab('/group-category/cate156/', '性爱教学', [
      SiteTab('/group-category/cate156/', '全部'),
      SiteTab('/category/cate157/', 'SM教學頻道'), SiteTab('/category/cate158/', '中指通一下'),
      SiteTab('/category/cate159/', '小哥哥艾理'), SiteTab('/category/cate160/', 'Dr.She許藍方'),
      SiteTab('/category/cate161/', '1G.老濕'), SiteTab('/category/cate162/', '系统认知方法论'),
      SiteTab('/category/cate163/', '挖掘你的聊天天赋'), SiteTab('/category/cate164/', '约会黄金法则'),
      SiteTab('/category/cate165/', '男生恋商提升课'), SiteTab('/category/cate166/', '男女徵信社'),
      SiteTab('/category/cate167/', '薇傲的性趣'), SiteTab('/category/cate168/', '一三蜜桃說 Dr.Yishan'),
      SiteTab('/category/cate169/', 'Carrie雨千'), SiteTab('/category/cate170/', '全部'),
    ]),
    SiteTab('/group-category/cate171/', '综合', [
      SiteTab('/group-category/cate171/', '全部'),
      // ★ 2026-10-15（**用户要求**）：`AI换脸` 放到**综合组第一位** ✅
      //   🛢️ 它在真站**不在任何组的下拉里**，而是另一个导航元素
      //      `a.menu-item[href="/category/cate155/"]`（全站仅此 1 个这类 ✅）⇒ 采集时漏了它 ☠
      SiteTab('/category/cate155/', 'AI换脸'),
      SiteTab('/category/cate172/', '糖芯女郎'), SiteTab('/category/cate173/', 'JVID精选'),
      SiteTab('/category/cate174/', '抖阴风'), SiteTab('/category/cate175/', '嫩穴动漫'),
      SiteTab('/category/cate176/', '蜜桃甄选'), SiteTab('/category/cate177/', '花季少女'),
      SiteTab('/category/cate178/', '熟女淫妻'), SiteTab('/category/cate179/', '独家黑料'),
      SiteTab('/category/cate180/', '网红直播'), SiteTab('/category/cate181/', '探花专家'),
      SiteTab('/category/cate182/', '特殊性癖'), SiteTab('/category/cate183/', '监控偷拍'),
      SiteTab('/category/cate184/', '国产重口'), SiteTab('/category/cate185/', '猎奇人兽'),
      SiteTab('/category/cate186/', '高潮秘籍'), SiteTab('/category/cate187/', '欧版千人斩'),
      SiteTab('/category/cate188/', '歐美群交Party'),
    ]),
  ],
);
