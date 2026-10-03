// madou —— **本站专属**的一切 ✓
//
// ⚠️ 用户 2026-10-03 决策：取消全站共享，站点相关的一切改成站点独立专属 ✓；底座保持公用 ✓。
// 由 `tools/mover3.js` 从 `api.dart` 的 `Api` 里**原样搬**出（**不重写逻辑** ✓ 行为不变 ✓），
// 仅做等价替换：`_fetchText(`→`_f.text(`、`_secClock(`→`secClock(` 等 ✓；入口方法改名为公开 ✓。
// ⚠️ import 由脚本按**代码里实际用到的符号**推导 ✓（不是手写的 ✓）。

import 'package:html/dom.dart';
import 'package:html/parser.dart' as hp;
import '../base/fetch.dart';
import '../models.dart';

/// madou 本站专属实现（取数走公用底座 [SiteFetcher] ✓）
class MadouSite {
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
  Future<List<Article>> search(String keyword,
      {int page = 1, List<MapEntry<String, String>>? extra}) async {
    final kw = Uri.encodeComponent(keyword);
    return cards(await _f.text(
        page <= 1 ? '/?s=$kw' : '/?paged=$page&s=$kw'));
  }

  /// 标签列表页（原 `Api.tag` 的 case body 原样搬来 ✓）
  /// 详情页的标签是裸 slug（/tag/{slug} ✓）；以 / 开头的是卡片上的分类路径 ✓
  Future<List<Article>> tag(String slug, {required int page}) async {
    if (slug.startsWith('/')) {
      return cards(await _f.text(page <= 1 ? slug : '$slug/page/$page'));
    }
    return cards(await _f.text(
        page <= 1 ? '/tag/$slug' : '/tag/$slug/page/$page'));
  }

  /// 首页第 N 页 = /page/N（没有 /page/1 ✓；原 `Api.home` 的 case body 原样搬来 ✓）
  Future<List<Article>> home({required int page}) async =>
      cards(await _f.text(page <= 1 ? '/' : '/page/$page'));

  /// 「分类」tab 的列表（原 `Api.category` 的 case body 原样搬来 ✓）
  /// ⚠️ 空 key = 「首页」tab → 由调用方传入 `home` 兜底（那实际是 `Api.home` ✓）。
  Future<List<Article>> category(String key,
          {required int page,
          String? k,
          String? theme,
          String? duration,
          String? sort,
          List<MapEntry<String, String>>? extra,
          Future<List<Article>> Function({int page})? home}) async {
    // 并集里 kk 可空、home 可空 ✗ → 绑定回原语义 ✓（原来两者都必填）
    final kk = k ?? key;
    // key 平时是分类 slug（已编码，如 hongkongdoll）；以 / 开头 = 站内路径
    // （/likes /week /month 三个榜单 + /tags 标签云）
    if (kk.isEmpty) return home!(page: page);
    if (kk == '/tags') return tags(await _f.text('/tags'));
    if (kk.startsWith('/')) {
      // 榜单**没有翻页**：第 2 页起直接给空，否则会把同一页重复追加
      return page > 1 ? const [] : cards(await _f.text(kk));
    }
    // 详情页的分类 chip 传的是分类**名**（中文，没编码）→ 自己编码再拼路径
    // （站点对未编码的中文路径实测 400，编码后 200）
    final md = RegExp(r'[^\x00-\x7F]').hasMatch(kk) ? Uri.encodeComponent(kk) : kk;
    return cards(await _f.text(
        page <= 1 ? '/category/$md' : '/category/$md/page/$page'));
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
  Future<ArticleDetail> detail(String url) async {
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
    return ArticleDetail(
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
    final share = (doc.querySelector('.article-content iframe')
                ?.attributes['src'] ??
            '')
        .trim();
    if (share.isEmpty) return '';
    final html = await _f.abs(share);
    if (html.isEmpty) return '';
    final tok =
        RegExp(r'var\s+token\s*=\s*"([^"]*)"').firstMatch(html)?.group(1) ?? '';
    final path =
        RegExp(r"var\s+m3u8\s*=\s*'([^']*)'").firstMatch(html)?.group(1) ?? '';
    if (tok.isEmpty || path.isEmpty) return '';
    final abs = path.startsWith('http') ? path : 'https://dash.madou.club$path';
    return '$abs?token=$tok';
  }
}
