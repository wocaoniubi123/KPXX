// madou —— **本站专属**的一切 ✓
//
// ⚠️ 用户 2026-10-03 决策：取消全站共享，站点相关的一切改成站点独立专属 ✓；底座保持公用 ✓。
// 由 `tools/mover3.js` 从 `api.dart` 的 `Api` 里**原样搬**出（**不重写逻辑** ✓ 行为不变 ✓），
// 仅做等价替换：`_fetchText(`→`_f.text(`、`_secClock(`→`secClock(` 等 ✓；入口方法改名为公开 ✓。
// ⚠️ import 由脚本按**代码里实际用到的符号**推导 ✓（不是手写的 ✓）。

import 'package:html/dom.dart';
import '../sites.dart';
import '../base/site_ui.dart';
import 'package:html/parser.dart' as hp;
import '../base/fetch.dart';
import '../models.dart';
// ★ 诊断打印：`debugPrint` 在 foundation 里 ✓（**不能**引 material ✗ —— 会与 html/dom 撞名）；开关在 settings ✓
import 'package:flutter/foundation.dart' show debugPrint;
import '../settings.dart';

/// madou 本站专属实现（取数走公用底座 [SiteFetcher] ✓）
class MadouSite extends SiteUi {
  MadouSite(this._f);

  final SiteFetcher _f;

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

  /// 搜索 = /?s={kw} ✓；翻页参数是 **paged**（不是 page ✓），照站点原样 ✓
// 看：搜索解析出几条 —— 0 条就是 /?s= 的卡片选择器变了（或关键词被站点当成不存在）。
@override
  Future<List<Article>> search(String keyword,
      {int page = 1, List<MapEntry<String, String>>? extra}) async {
    final sw = Stopwatch()..start();
    final kw = Uri.encodeComponent(keyword);
    final res = cards(await _f.text(
        page <= 1 ? '/?s=$kw' : '/?paged=$page&s=$kw'));
    if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} 入口=search 页=$page kwLen=${keyword.length} 解析出 ${res.length} 条 ms=${sw.elapsedMilliseconds}');
    return res;
  }

  /// 标签列表页（原 `Api.tag` 的 case body 原样搬来 ✓）
  /// 详情页的标签是裸 slug（/tag/{slug} ✓）；以 / 开头的是卡片上的分类路径 ✓
// 看：标签页解析出几条 —— 0 条就是该标签没有内容或卡片选择器变了（裸 slug 与站内路径两种走法）。
@override
  Future<List<Article>> tag(String slug, {required int page}) async {
    final sw = Stopwatch()..start();
    final res = slug.startsWith('/')
        ? await cards(await _f.text(page <= 1 ? slug : '$slug/page/$page'))
        : await cards(await _f.text(
            page <= 1 ? '/tag/$slug' : '/tag/$slug/page/$page'));
    if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} 入口=tag slug=$slug 页=$page 解析出 ${res.length} 条 ms=${sw.elapsedMilliseconds}');
    return res;
  }

  /// 首页第 N 页 = /page/N（没有 /page/1 ✓；原 `Api.home` 的 case body 原样搬来 ✓）
// 看：首页解析出几条 —— 0 条就是首页卡片选择器（article.excerpt）变了或 /page/N 被站点改址。
@override
  Future<List<Article>> home({required int page, String first = ''}) async {
    final sw = Stopwatch()..start();
    final res = await cards(await _f.text(page <= 1 ? '/' : '/page/$page'));
    if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} 入口=home 页=$page 解析出 ${res.length} 条 ms=${sw.elapsedMilliseconds}');
    return res;
  }

  /// 「分类」tab 的列表（原 `Api.category` 的 case body 原样搬来 ✓）
  /// ⚠️ 空 key = 「首页」tab → 由调用方传入 `home` 兜底（那实际是 `Api.home` ✓）。
// 看：分类页解析出几条 —— 0 条就是卡片选择器（article.excerpt）变了或该分类路径给的是空页。
@override
  Future<List<Article>> category(String key,
          {required int page,
          String? k,
          String? theme,
          String? duration,
          String? sort,
          List<MapEntry<String, String>>? extra,
          Future<List<Article>> Function({int page})? home}) async {
    final sw = Stopwatch()..start(); // ★【常驻诊断】只计时 ✓ 不动分流/取数路径 ☠
    // 并集里 kk 可空、home 可空 ✗ → 绑定回原语义 ✓（原来两者都必填）
    final kk = k ?? key;
    // key 平时是分类 slug（已编码，如 hongkongdoll）；以 / 开头 = 站内路径
    // （/likes /week /month 三个榜单 + /tags 标签云）
    // ⚠️ 空 key = 「首页」tab → 由调用方传入 `home` 兜底（那实际是 `Api.home` ✓）。
    if (kk.isEmpty) {
      final res = await home!(page: page);
      // ★【常驻诊断】「首页」tab 兜底：站名 + key + 页 + 条数 + 耗时 ✓
      if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} k=$key 页=$page 解析出 ${res.length} 条 ms=${sw.elapsedMilliseconds}');
      return res;
    }
    if (kk == '/tags') {
      final res = tags(await _f.text('/tags'));
      // ★【常驻诊断】列表解析结果：站名 + key + 页 + 条数 + 耗时 ✓
      if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} k=$key 页=$page 解析出 ${res.length} 条 ms=${sw.elapsedMilliseconds}');
      return res;
    }
    if (kk.startsWith('/')) {
      // 榜单**没有翻页**：第 2 页起直接给空，否则会把同一页重复追加
      final res = page > 1 ? const <Article>[] : cards(await _f.text(kk));
      // ★【常驻诊断】列表解析结果：站名 + key + 页 + 条数 + 耗时 ✓
      if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} k=$key 页=$page 解析出 ${res.length} 条 ms=${sw.elapsedMilliseconds}');
      return res;
    }
    // 详情页的分类 chip 传的是分类**名**（中文，没编码）→ 自己编码再拼路径
    // （站点对未编码的中文路径实测 400，编码后 200）
    final md = RegExp(r'[^\x00-\x7F]').hasMatch(kk) ? Uri.encodeComponent(kk) : kk;
    final res = cards(await _f.text(
        page <= 1 ? '/category/$md' : '/category/$md/page/$page'));
    // ★【常驻诊断】列表解析结果：站名 + key + 页 + 条数 + 耗时 ✓
    if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} k=$key 页=$page 解析出 ${res.length} 条 ms=${sw.elapsedMilliseconds}');
    return res;
  }
  /// 卡片解析（首页/分类/搜索/标签/榜单共用）
  List<Article> cards(String html) {
    final doc = hp.parse(html);
    final out = <Article>[];
    for (final el in doc.querySelectorAll('article.excerpt')) {
      final href =
          _toRelPath(el.querySelector('a.thumbnail')?.attributes['href'] ?? '');
      if (href.isEmpty) continue;
      final title = (el.querySelector('h2 a')?.text ?? '').trim();
      if (title.isEmpty) continue;
      // 封面必须是真图：img[src] 是懒加载占位（thumb.png），真封面在 data-src 上
      final cover =
          (el.querySelector('a.thumbnail img')?.attributes['data-src'] ?? '')
              .trim();
      if (cover.isEmpty || cover.endsWith('/showcase/img/thumb.png')) continue;
      // 观看数：站点原文「观看(59.26K)」**原样**显示（用户先要求只留数字、
      // 随后又说"观看数加回去"，以最终要求为准；见 DEVLOG 第 55/57 条）
      out.add(Article(
        title: title,
        url: href,
        cover: cover,
        meta: (el.querySelector('.post-view')?.text ?? '').trim(),
        // ⚠️ 卡片上的分类名**不取**：footer 里那个 `rel="category tag"`（如"麻豆传媒"）
        // 用户明确要求去掉（2026-10-01，见 DEVLOG 第 56 条）——挂 Article.tags 会在
        // 卡片上渲染成可点胶囊。详情页的分类/标签不受影响（走 detail 的 .item-3/.article-tags）。
      ));
    }
    final seen = <String>{};
    return [
      for (final a in out)
        if (seen.add(a.url)) a
    ];
  }

  /// 详情：标题/分类/标签/相关推荐/播放源（站点没有时长、系列、简介、发布时间）
@override
  Future<ArticleDetail> detail(String url) async {
    final sw = Stopwatch()..start();
    final doc = hp.parse(await _f.text(url));
    final title = (doc.querySelector('.article-title')?.text ?? '').trim();
    final catName = (doc.querySelector('.item-3 a')?.text ?? '').trim();
    // 标签：slug = URL 最后一段（原始编码值，不解码——与其它站点做法一致）
    final tags = <MapEntry<String, String>>[];
    for (final a in doc.querySelectorAll('.article-tags a')) {
      final name = a.text.trim();
      final slug = lastSeg(a.attributes['href'] ?? '');
      if (name.isEmpty || slug.isEmpty) continue;
      if (tags.any((e) => e.key == slug)) continue;
      tags.add(MapEntry(slug, name));
    }
    // 相关推荐：标题取锚的文本（<a> 里只有一个缩进的 span>img，没有别的文本节点）
    final related = <Article>[];
    for (final a in doc.querySelectorAll('.postitems li a')) {
      final href = _toRelPath(a.attributes['href'] ?? '');
      final t = a.text.trim();
      if (href.isEmpty || t.isEmpty || href == url) continue;
      if (related.any((x) => x.url == href)) continue;
      related.add(Article(
        title: t,
        url: href,
        cover:
            (a.querySelector('img[data-src]')?.attributes['data-src'] ?? '')
                .trim(),
        meta: '',
      ));
      if (related.length >= 12) break;
    }
    final play = await playUrl(doc);
    final det = ArticleDetail(
      title: title.isEmpty ? url : title,
      time: '',
      categories: [if (catName.isNotEmpty) catName],
      images: const [],
      intro: '',
      videos: [
        if (play.isNotEmpty)
          ArticleVideo(label: title, ordinal: 1, sources: [play]),
      ],
      tags: tags,
      related: related,
      seriesPrefix: '',
    );
    // ★【常驻诊断】详情解析结果：站名 + path(截 80) + 视频/图/相关条数 + 耗时 ✓（**不打完整 URL** ☠）
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] ${_f.site.name} path=${url.length <= 80 ? url : url.substring(0, 80)} 视频=${det.videos.length} 图=${det.images.length} 相关=${det.related.length} ms=${sw.elapsedMilliseconds}');
    return det;
  }

  /// URL 最后一段（标签 slug 用；空链接返回空串）
  static String lastSeg(String href) {
    final segs = href.split('/').where((s) => s.isNotEmpty).toList();
    return segs.isEmpty ? '' : segs.last;
  }

  /// 麻豆社「热门标签」标签云页（/tags）——**不是文章卡片**，别用 cards 解：
  /// `.tagslist li` 里 `a.name`=标签名（href 是 /tag/{slug}）、`<small>`=文章数
  /// （HTML 实体由 dom 包解出来，形如 ×2577）、`a.tit` 是"该标签下的一篇示例文章"
  /// （**忽略**）。没有封面 → 卡片变纯文字卡。站点**没有分页**（实测无 .pagination）。
  List<Article> tags(String html) {
    final doc = hp.parse(html);
    final out = <Article>[];
    for (final li in doc.querySelectorAll('.tagslist li')) {
      final a = li.querySelector('a.name');
      if (a == null) continue;
      final title = a.text.trim();
      final slug = lastSeg(a.attributes['href'] ?? '');
      if (title.isEmpty || slug.isEmpty) continue;
      if (out.any((x) => x.url == '/tag/$slug')) continue;
      out.add(Article(
        title: title,
        url: '/tag/$slug',
        cover: '',
        // 站点显示 "×N"（=该标签下的文章数），原样保留
        meta: (li.querySelector('small')?.text ?? '').trim(),
      ));
    }
    return out;
  }

  /// 播放源：正文第一个 iframe → dash.madou.club 分享页 → 页面里两行 JS
  /// （token 是双引号、m3u8 是单引号）→ `https://dash.madou.club{m3u8}?token=`。
  /// 任何一步拿不到就返回空串（videos 留空，不抛异常、不编假地址）；
  /// token 只有 100 秒时效，过期靠上层「起播失败 → 重新抓详情页」兜底。
  Future<String> playUrl(Document doc) async {
    final sw = Stopwatch()..start(); // ★【常驻诊断】只计时 ✓ 不动取数/正则路径 ☠
    final share = (doc.querySelector('.article-content iframe')
                ?.attributes['src'] ??
            '')
        .trim();
    if (share.isEmpty) {
      // 看：正文里没有 iframe ⇒ 拿不到分享页（正文结构变了 / 该篇本来就没视频）。
      if (AppSettings.i.logConsole) debugPrint('[SRC] ${_f.site.name} playUrl 无 iframe ⇒ 无源 ms=${sw.elapsedMilliseconds}');
      return '';
    }
    final html = await _f.abs(share);
    if (html.isEmpty) {
      // 看：分享页（dash.madou.club）取不到 ⇒ 无源（跨域取数失败 / 域名挂了）。
      if (AppSettings.i.logConsole) debugPrint('[SRC] ${_f.site.name} playUrl 分享页取不到 host=${Uri.tryParse(share)?.host ?? '?'} ⇒ 无源 ms=${sw.elapsedMilliseconds}');
      return '';
    }
    final tok =
        RegExp(r'var\s+token\s*=\s*"([^"]*)"').firstMatch(html)?.group(1) ?? '';
    final path =
        RegExp(r"var\s+m3u8\s*=\s*'([^']*)'").firstMatch(html)?.group(1) ?? '';
    if (tok.isEmpty || path.isEmpty) {
      // 看：分享页里的 token/m3u8 两行 JS 抠不出来 ⇒ 无源（站点换了变量名/换了页面结构）。
      if (AppSettings.i.logConsole) debugPrint('[SRC] ${_f.site.name} playUrl token或m3u8缺失 tok=${tok.isNotEmpty} m3u8=${path.isNotEmpty} ⇒ 无源 ms=${sw.elapsedMilliseconds}');
      return '';
    }
    final abs = path.startsWith('http') ? path : 'https://dash.madou.club$path';
    // 看：token 换取成功 —— 只打**首个媒体 host**（token 原串/query 一律不打 ☠）。
    if (AppSettings.i.logConsole) debugPrint('[SRC] ${_f.site.name} playUrl 拿到源=true 首个host=${Uri.tryParse(abs)?.host ?? '?'} ms=${sw.elapsedMilliseconds}');
    return '$abs?token=$tok';
  }
}

// ===== 本站专属清单（2026-10-03 从 lib/sites.dart 下放 ✓；循环 import 允许 ✓）=====

const List<SiteTab> mdOther = [
  SiteTab('hongkongdoll', 'HongKongDoll'),
  SiteTab('psychoporntw', 'PsychopornTW'),
  SiteTab('91%e5%88%b6%e7%89%87%e5%8e%82', '91制片厂'),
  SiteTab('%e6%9e%9c%e5%86%bb%e4%bc%a0%e5%aa%92', '果冻传媒'),
  SiteTab('%e8%9c%9c%e6%a1%83%e5%bd%b1%e5%83%8f', '蜜桃影像'),
  SiteTab('%e5%a4%a9%e7%be%8e%e4%bc%a0%e5%aa%92', '天美传媒'),
  SiteTab('%e7%9a%87%e5%ae%b6%e5%8d%8e%e4%ba%ba', '皇家华人'),
  SiteTab('%e5%85%94%e5%ad%90%e5%85%88%e7%94%9f', '兔子先生'),
  SiteTab('%e6%98%9f%e7%a9%ba%e6%97%a0%e9%99%90%e4%bc%a0%e5%aa%92', '星空无限传媒'),
  SiteTab('%e7%88%b1%e8%b1%86', '爱豆'),
  SiteTab('%e9%ba%bb%e8%b1%86%e5%af%bc%e6%bc%94%e7%b3%bb%e5%88%97', '麻豆导演系列'),
  SiteTab('%e5%a4%a7%e8%b1%a1%e4%bc%a0%e5%aa%92', '大象传媒'),
  SiteTab('%e7%8c%ab%e7%88%aa%e5%bd%b1%e5%83%8f', '猫爪影像'),
  SiteTab('%e7%b2%be%e4%b8%9c%e5%bd%b1%e4%b8%9a', '精东影业'),
  SiteTab('%e6%9d%8f%e5%90%a7', '杏吧'),
  SiteTab('%e4%b9%90%e6%92%ad%e4%bc%a0%e5%aa%92', '乐播传媒'),
  SiteTab('%e8%8d%89%e8%8e%93', '草莓'),
  SiteTab('%e6%8a%96%e9%98%b4', '抖阴'),
  SiteTab('sa%e5%9b%bd%e9%99%85%e4%bc%a0%e5%aa%92', 'SA国际传媒'),
  SiteTab('%e8%b5%b7%e7%82%b9%e4%bc%a0%e5%aa%92-%e6%80%a7%e8%a7%86%e7%95%8c%e4%bc%a0%e5%aa%92',
      '起点传媒/性视界传媒'),
  SiteTab('%e5%a4%a7%e9%b8%9f%e5%8d%81%e5%85%ab', '大鸟十八'),
  SiteTab('%e5%b0%8f%e9%b9%8f%e5%a5%87%e5%95%aa%e8%a1%8c', '小鹏奇啪行'),
  SiteTab('%e5%a5%b3%e4%bc%98%e6%b7%ab%e5%a8%83%e5%9f%b9%e8%ae%ad%e8%90%a5', '女优淫娃培训营'),
  SiteTab('%e6%b7%ab%e6%ac%b2%e6%b8%b8%e6%88%8f%e7%8e%8b', '淫欲游戏王'),
  SiteTab('%e5%a5%b3%e7%a5%9e%e7%be%9e%e7%be%9e%e7%a0%94%e7%a9%b6%e6%89%80', '女神羞羞研究所'),
  SiteTab('%e7%aa%81%e8%a2%ad%e5%a5%b3%e4%bc%98%e5%ae%b6', '突袭女优家'),
  SiteTab('%e6%83%85%e8%b6%a3k%e6%ad%8c%e6%88%bf', '情趣K歌房'),
  SiteTab('kiss%e7%b3%96%e6%9e%9c%e5%b1%8b', 'KISS糖果屋'),
];

const List<SiteTab> mdScreens = [
  SiteTab('/likes', '点赞排行'),
  SiteTab('/week', '7天热门'),
  SiteTab('/month', '30天热门'),
];

// ===== 本站档案（2026-10-03 从 lib/sites.dart 的 kSites 下放 ✓）=====

/// 本站档案：麻豆社
const SiteEntry kSite12 = SiteEntry(
    name: '麻豆社',
    template: SiteTemplate.madou,
    iconUrl: '/favicon.ico',
    hosts: ['madou.club'],
    portraitCovers: false,
    showRelated: true,
    categories: [
      // 空 key = 站点首页（api.dart 的 category() 里特判走 home 那条路——
      // 不特判就会请求 /category/ → 站点 404）
      SiteTab('', '首页'),
      SiteTab('%e9%ba%bb%e8%b1%86%e4%bc%a0%e5%aa%92', '麻豆传媒'),
      SiteTab('%e9%ba%bb%e8%b1%86%e7%95%aa%e5%a4%96%e7%af%87', '麻豆番外篇'),
      SiteTab('%e9%ba%bb%e8%b1%86%e8%8a%b1%e7%b5%ae', '麻豆花絮'),
      SiteTab('筛选', '其他原创/企划', mdOther),
      // 标签云页 /tags：50 个标签卡，点进去是该标签的列表页（站点没有分页）
      SiteTab('/tags', '热门标签'),
      SiteTab('筛选', '筛选', mdScreens),
    ],
  );
