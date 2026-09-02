import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:html/dom.dart' as hd;
import 'package:html/parser.dart' as hp;

import 'config.dart';
import 'models.dart';

/// 51吃瓜站抓取层。
/// 页面结构（已验证）：
/// - 列表页:  article[itemscope][itemtype~=BlogPosting]（排除 .ad-item）
///            a[href^=/archives/] .post-card 内 h2.post-card-title + 封面 script
/// - 分页:    /category/{slug}/{n}/  首页 /page/n/
/// - 搜索:    /search/{keyword}/（/?s=xxx 会 301 到该路径）
/// - 详情:    h1.post-title、div.dplayer[data-config] 内的 video.url / video_h265.url
class Api {
  static final Api _i = Api._();
  factory Api() => _i;
  Api._();

  final http.Client _client = http.Client();
  String _host = Site.hosts.first;

  String get base => 'https://$_host';

  /// 顺序尝试域名，返回第一个成功的文本。
  Future<String> _fetchText(String path) async {
    for (final h in Site.hosts) {
      try {
        final r = await _client.get(
          Uri.parse('https://$h$path'),
          headers: {
            'User-Agent': Site.ua,
            'Referer': 'https://$h/',
            'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
          },
        ).timeout(const Duration(seconds: 12));
        if (r.statusCode == 200) {
          _host = h;
          return utf8.decode(r.bodyBytes);
        }
      } catch (_) {
        // 当前域名失败，换下一个
      }
    }
    throw Exception('所有域名均无法访问');
  }

  /// 列表页 / 搜索页通用的文章卡片解析。
  List<Article> _parseArticles(String html) {
    final doc = hp.parse(html);
    final out = <Article>[];
    for (final el in doc.querySelectorAll('article[itemscope]')) {
      final cls = el.className ?? '';
      // 广告卡与站外推广卡
      final a = el.querySelector('a[href^="/archives/"]');
      if (a == null || cls.contains('ad-item')) continue;
      final titleEl = el.querySelector('.post-card-title');
      final title = titleEl?.text.trim() ?? '';
      if (title.isEmpty) continue;
      // 封面：post-card 内的 loadBannerDirect('url', ...
      String cover = '';
      for (final s in el.querySelectorAll('script')) {
        final m = RegExp("loadBannerDirect\\('([^']+)'").firstMatch(s.text);
        if (m != null) {
          cover = m.group(1)!;
          break;
        }
      }
      if (cover.isEmpty) {
        final img = el.querySelector('img[data-src]');
        cover = img?.attributes['data-src'] ?? '';
      }
      final info = el.querySelector('.post-card-info');
      out.add(Article(
        title: title,
        url: a.attributes['href'] ?? '',
        cover: cover,
        meta: (info?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim(),
      ));
    }
    // 去重（同页重复卡片）
    final seen = <String>{};
    return [
      for (final a in out)
        if (seen.add(a.url)) a
    ];
  }

  /// 分类文章列表页。page 从 1 开始。
  Future<List<Article>> category(String slug, {int page = 1}) async {
    final path = page <= 1
        ? '/category/$slug/'
        : '/category/$slug/$page/';
    final html = await _fetchText(path);
    return _parseArticles(html);
  }

  /// 首页最新列表（未使用顶部分类时入口为推荐）。
  Future<List<Article>> home({int page = 1}) async {
    final path = page <= 1 ? '/' : '/page/$page/';
    final html = await _fetchText(path);
    return _parseArticles(html);
  }

  /// 搜索（关键词需原始文本，内部编码）。
  /// 站点未开放搜索分页（page/2 为 403），只支持第一页。
  Future<List<Article>> search(String keyword, {int page = 1}) async {
    if (page > 1) return []; // 站点无搜索分页
    final path = '/search/${Uri.encodeComponent(keyword)}/';
    final html = await _fetchText(path);
    return _parseArticles(html);
  }

  /// 文章详情（相对路径 /archives/xxx/）。
  /// 视频与正文图片全部来自原文 HTML，视频 URL 带 auth_key 时效签名，
  /// 过期时重新调用本方法即可拿到新地址。
  Future<ArticleDetail> detail(String url) async {
    final html = await _fetchText(url);
    final doc = hp.parse(html);

    final title = doc.querySelector('.post-title')?.text.trim() ?? '';

    String time = '';
    final timeMeta = doc.querySelector('meta[itemprop="datePublished"]');
    if (timeMeta != null) {
      time = timeMeta.attributes['content'] ?? '';
    }

    final categories = <String>[];
    for (final a in doc.querySelectorAll('a[href^="/category/"]')) {
      final href = a.attributes['href'] ?? '';
      final segs = Uri.parse('https://x$href').pathSegments;
      // pathSegments: ['category', 'wpcz', '']
      for (final s in segs) {
        if (s.isNotEmpty && s != 'category') {
          if (!categories.contains(s)) categories.add(s);
          break;
        }
      }
    }

    // 正文图片：post-content 内 img，图源属性优先级 data-src -> data-xkrkllgl -> src。
    // 该站真实图地址常放在 data-xkrkllgl（懒加载占位是站内 zw.png），只收 pic.sbhioa.cn 的图。
    final images = <String>[];
    for (final img in doc.querySelectorAll('.post-content img')) {
      var src = img.attributes['data-src'] ?? '';
      if (src.isEmpty) src = img.attributes['data-xkrkllgl'] ?? '';
      if (src.isEmpty) src = img.attributes['src'] ?? '';
      if (src.startsWith('http') && src.contains('pic.sbhioa.cn')) {
        if (!images.contains(src)) images.add(src);
      }
    }
    // 无 .post-content 容器的旧结构兜底
    if (images.isEmpty) {
      for (final img in doc.querySelectorAll('article img[data-src]')) {
        final src = img.attributes['data-src'] ?? '';
        if (src.startsWith('http') && !images.contains(src)) images.add(src);
      }
    }

    // 视频：div.dplayer[data-config] JSON
    // 注意：video_h265 可能是对象（有 H265 源）也可能是空数组（无），
    // 必须类型容错，否则一篇无 H265 的文章整体解析失败导致"无视频"。
    String videoUrl = '';
    String videoUrlH265 = '';
    for (final dp in doc.querySelectorAll('.dplayer[data-config]')) {
      try {
        final cfg = jsonDecode(dp.attributes['data-config']!) as Map<String, dynamic>;
        final video = cfg['video'];
        final h265 = cfg['video_h265'];
        if (video is Map<String, dynamic>) {
          videoUrl = (video['url'] as String?) ?? '';
        }
        if (h265 is Map<String, dynamic>) {
          videoUrlH265 = (h265['url'] as String?) ?? '';
        }
        break;
      } catch (_) {
        // 配置坏则该篇视为无视频继续
      }
    }

    // 合集文章：正文 .post-content 里的子文章链接（每个条目一篇独立文章）。
    // 排除本文自身、上一篇/下一篇导航（post-near）、尾部相关推荐区（hot-news）。
    final linked = <Article>[];
    final seen = <String>{};
    for (final a in doc.querySelectorAll('.post-content a[href^="/archives/"]')) {
      final href = a.attributes['href'] ?? '';
      if (href.isEmpty || href == url) continue;
      final t = a.text.trim();
      if (t.isEmpty) continue;
      if (_inBadAncestor(a)) continue;
      if (seen.add(href)) {
        linked.add(Article(title: t, url: href, cover: '', meta: ''));
      }
    }

    return ArticleDetail(
      title: title,
      time: time,
      categories: categories,
      images: images,
      videoUrl: videoUrl,
      videoUrlH265: videoUrlH265,
      seriesPrefix: _seriesPrefix(title),
      linkedItems: linked,
    );
  }

  /// 链接祖先是否位于"上一篇/下一篇 / 相关推荐"区域（这些不是合集条目）
  static bool _inBadAncestor(hd.Element e) {
    for (hd.Element? p = e; p != null; p = p.parent) {
      final c = p.className ?? '';
      if (c.contains('post-near') || c.contains('hot-news')) return true;
    }
    return false;
  }

  /// 标题中含"第 N 集"则提取系列前缀，否则空串。
  static String _seriesPrefix(String title) {
    final m = RegExp(r'第\s*\d+\s*集').firstMatch(title);
    if (m == null) return '';
    return title.substring(0, m.start).trim();
  }
}
