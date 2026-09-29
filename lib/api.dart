import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as hp;

import 'config.dart';
import 'models.dart';

/// 站点抓取层（同一套 WordPress 模板的站点通用，域名/分类由外部传入）。
/// 页面结构（已在 51吃瓜、每日大赛 两站实测验证）：
/// - 列表页:  article[itemscope][itemtype~=BlogPosting]（排除 .ad-item）
///            a[href^=/archives/] .post-card 内 h2.post-card-title + 封面 script
/// - 分页:    /category/{slug}/{n}/  首页 /page/n/
/// - 搜索:    /search/{keyword}/（/?s=xxx 会 301 到该路径）
/// - 详情:    h1.post-title、div.dplayer[data-config] 内的 video.url / video_h265.url
///            （视频是带 auth_key 时效签名的 m3u8，过期要重新抓本方法）
/// - 图片:    加密图见 fetched_image.dart
class Api {
  /// hosts：该站域名列表，第一个为主域名，其余为备用域名
  Api({required this.hosts}) : _host = hosts.first;

  final List<String> hosts;
  String _host;

  /// 共享连接池：多处 Api 实例复用同一条 client
  static final http.Client _client = http.Client();

  String get base => 'https://$_host';

  /// 顺序尝试域名，返回第一个成功的文本。
  /// 上次跑通的域名排最前：站点常有一两个域名挂掉，若每次从列表头开始试，
  /// 每个请求都要先白等一次超时（列表/详情/视频启动全被拖慢）。
  Future<String> _fetchText(String path) async {
    final order = [
      if (hosts.contains(_host)) _host,
      ...hosts.where((h) => h != _host),
    ];
    for (final h in order) {
      try {
        final r = await _client.get(
          Uri.parse('https://$h$path'),
          headers: {
            'User-Agent': Site.ua,
            'Referer': 'https://$h/',
            'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
          },
        ).timeout(const Duration(seconds: 8));
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

    // 简介：文章页 meta description（实测就是本篇的剧情摘要）
    final intro = (doc.querySelector('meta[name="description"]')?.attributes['content'] ??
            '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

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
    // 该站真实图地址放在 data-xkrkllgl（懒加载占位是站内 zw.png），只收图床的图。
    final images = <String>[];
    for (final img in doc.querySelectorAll('.post-content img')) {
      var src = img.attributes['data-src'] ?? '';
      if (src.isEmpty) src = img.attributes['data-xkrkllgl'] ?? '';
      if (src.isEmpty) src = img.attributes['src'] ?? '';
      // 绝对地址即真图（占位图是站内相对路径 zw.png / /usr/... 的图）。
      // 不按图床域名过滤：图床会换（实测同一站既用 pic.ndhixj.cn 也用 pic.sbhioa.cn）。
      if (src.startsWith('http')) {
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

    return ArticleDetail(
      title: title,
      time: time,
      categories: categories,
      images: images,
      intro: intro,
      videoUrl: videoUrl,
      videoUrlH265: videoUrlH265,
      seriesPrefix: _seriesPrefix(title),
    );
  }

  /// 标题中含"第 N 集"则提取系列前缀，否则空串。
  static String _seriesPrefix(String title) {
    final m = RegExp(r'第\s*\d+\s*集').firstMatch(title);
    if (m == null) return '';
    return title.substring(0, m.start).trim();
  }
}
