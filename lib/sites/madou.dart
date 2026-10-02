// madou —— **本站专属**的一切 ✓
//
// ⚠️ 用户 2026-10-03 决策：取消全站共享，站点相关的一切改成站点独立专属 ✓；底座保持公用 ✓。
// 由 `tools/mover3.js` 从 `api.dart` 的 `Api` 里**原样搬**出（**不重写逻辑** ✓ 行为不变 ✓），
// 仅做等价替换：`_fetchText(`→`_f.text(`、`_secClock(`→`secClock(` 等 ✓；入口方法改名为公开 ✓。
// ⚠️ import 由脚本按**代码里实际用到的符号**推导 ✓（不是手写的 ✓）。

import 'package:html/dom.dart';
import 'package:html/parser.dart' as hp;
import '../base/fetch.dart';
import '../base/parse.dart';
import '../models.dart';

/// madou 本站专属实现（取数走公用底座 [SiteFetcher] ✓）
class MadouSite {
  MadouSite(this._f);

  final SiteFetcher _f;
  /// 卡片解析（首页/分类/搜索/标签/榜单共用）
  List<Article> cards(String html) {
    final doc = hp.parse(html);
    final out = <Article>[];
    for (final el in doc.querySelectorAll('article.excerpt')) {
      final href =
          toRelPath(el.querySelector('a.thumbnail')?.attributes['href'] ?? '');
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
      final href = toRelPath(a.attributes['href'] ?? '');
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
