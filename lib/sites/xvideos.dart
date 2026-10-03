// XVideos（tube 站）—— **本站专属**的一切 ✓
//
// ⚠️ 用户 2026-10-03 决策：取消全站共享，站点相关的一切改成站点独立专属 ✓；底座保持公用 ✓。
// 从 `api.dart` 的 `Api` 里**原样搬**过来（**不重写逻辑** ✓ 行为不变 ✓）。
// 入口方法**直接改名为公开**（`list`/`search`/`detail`/`cards`/`directory`/`profileVideos` ✓）。
// ⚠️ 搬运时发现：本站代码在 `api.dart` 里被**切成两段** ✗（`_xvDetail` 落在 kmsvip 段之后 ✓），
// 所以是"两段拼接"搬来的 ✓（中间那段 kmsvip 代码留在 `api.dart` 未动 ✓）。

import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as hp;

import '../base/fetch.dart';
import '../models.dart';

/// XVideos 本站专属实现（取数走公用底座 [SiteFetcher] ✓）
class XvSite {
  XvSite(this._f);

  final SiteFetcher _f;

  /// 详情页标签 = /tags/{slug}（翻页规则同分类页 ✓；原 `Api.tag` 的 case body 原样搬来 ✓）
  Future<List<Article>> tag(String slug, {required int page}) => list('/tags/$slug', page: page);

  /// 首页 = Newest 列表（原 `Api.home` 的 case body 原样搬来 ✓）
  Future<List<Article>> home({required int page}) => list('/new', page: page);

  /// 「分类」tab 的列表（原 `Api.category` 的 case body 原样搬来 ✓）
  /// 「分类」tab 的子分类 key（/c/xxx、/tags/xxx、/trans、/lang/…）优先 ✓；
  /// 主分类 key = /best、/new、/channels-index、/pornstars-index（见 list ✓）
  Future<List<Article>> category(String key,
          {required int page,
          String? k,
          String? theme,
          String? duration,
          String? sort,
          List<MapEntry<String, String>>? extra,
          Future<List<Article>> Function({int page})? home}) =>
      list(k ?? key, page: page);

  /// XVideos 的频道/演员卡（**不含** `/video.` 的真正视频页 ✓）→ 进"視頻"列表页 ✓
  @override
  String? specialTap(String url) => url.contains('/video.') ? null : 'list';
  // XVideos（tube 站）：列表/搜索/标签共用 thumb-block 卡片；详情页内嵌
  // setVideoHLS / setVideoUrlLow/High 直链（xvideos-cdn，无防盗链；secure 签名
  // 约 5 小时有效——过期走现有"失败→刷新详情"兜底）；相关推荐在页面内
  // JS 数组 video_related=[{u,i,t,d,…}]。

  /// 本地化：带 Accept-Language 才是**中文版**（照用户看到的站点；不带时
  /// 会按访问环境给英文）。只给 xvideos 的请求用，其他站点不受影响。
  static const Map<String, String> _xvLang = {
    'Accept-Language': 'zh-CN,zh;q=0.9',
  };

  /// 「最佳影片」当月月份（如 2026-08）：从上一次 /best 页的分页链接解析后缓存
  String? _xvBestMonth;

  /// 分类/标签列表：第 N 页 = base + '/${N-1}'（站点页码从 0 计；N=1 = base）；
  /// 「Newest」特殊：第 1 页 = '/'、第 N 页 = '/new/N-1'；
  /// 「最佳影片」特殊：第 1 页 = '/best'（服务端跳当月），第 N 页 =
  /// '/best/{YYYY-MM}/N-1'（月份从第 1 页分页链接解析）
  Future<List<Article>> list(String base, {int page = 1}) async {
    String path;
    if (base == '/new') {
      path = page <= 1 ? '/' : '/new/${page - 1}';
    } else if (base == '/best') {
      if (page <= 1) {
        final html = await _f.text('/best', extraHeaders: _xvLang);
        _xvBestMonth =
            RegExp(r'/best/(\d{4}-\d{2})/').firstMatch(html)?.group(1) ??
                _xvBestMonth;
        return cards(html);
      }
      var m = _xvBestMonth;
      if (m == null) {
        m = RegExp(r'/best/(\d{4}-\d{2})/')
            .firstMatch(await _f.text('/best', extraHeaders: _xvLang))
            ?.group(1);
        _xvBestMonth = m;
      }
      path = m == null ? '/best' : '/best/$m/${page - 1}';
    } else if (_isXvProfile(base)) {
      // 频道/演员卡进来的 slug：走「視頻」免费列表（JSON 接口，见 profileVideos）
      return profileVideos(base, page: page);
    } else {
      path = page <= 1 ? base : '$base/${page - 1}';
    }
    final html = await _f.text(path, extraHeaders: _xvLang);
    // 頻道/色情明星 = 目录页（卡片是频道/演员主页链接，不是视频卡片）
    if (base == '/channels-index' || base == '/pornstars-index') {
      return directory(html);
    }
    return cards(html);
  }

  /// 拉 HLS 主列表，返回**每个档的子列表地址**（按分辨率/码率**从高到低**）。
  /// 不是主列表（单档的）/ 请求失败 → null（调用方保留原地址，不至于不能播）。
  /// ⚠️ 2026-10-02 改：原来只留最高档（`_pickTopHlsVariant`），现在**全留着**给详情页的
  /// 「清晰度」行选 —— 顺序仍是"最高档在最前"，所以**默认播最高档**这点没变。


  /// 搜索：/?k=kw（翻页 &p=N-1，站点 p 从 0 计）
  Future<List<Article>> search(String keyword,
      {int page = 1, List<MapEntry<String, String>>? extra}) async {
    final path = '/?k=${Uri.encodeComponent(keyword)}'
        '${page > 1 ? '&p=${page - 1}' : ''}';
    return cards(await _f.text(path, extraHeaders: _xvLang));
  }

  /// thumb-block 卡片解析（分类 / 标签 / 搜索共用）
  List<Article> cards(String html) {
    final doc = hp.parse(html);
    final out = <Article>[];
    for (final el in doc.querySelectorAll('div.thumb-block')) {
      final a = el.querySelector('p.title a') ??
          el.querySelector('div.title a[href*="/video"]') ??
          el.querySelector('div.thumb a[href*="/video"]');
      var href = a?.attributes['href'] ?? '';
      if (!href.contains('/video')) continue;
      // 部分卡片的链接带未替换的占位符 THUMBNUM（真站由 JS 填数字；字面值会 404）。
      // 填 1 即可——实测任意数字等价，站点会把多余层级 302 到规范短链。
      if (href.contains('THUMBNUM')) href = href.replaceFirst('THUMBNUM', '1');
      // 标题：两种皮肤——首页 p.title / 最佳影片 div.title（容器上带 title 属性）；
      // 兜底取锚文本时先去掉 thl("…",0); 脚本残留（最佳影片缩略图锚里只有这段）
      var title = (el.querySelector('p.title')?.attributes['title'] ??
              el.querySelector('div.title')?.attributes['title'] ??
              a?.attributes['title'] ??
              '')
          .trim();
      if (title.isEmpty) {
        title = (a?.text ?? '')
            .replaceAll(RegExp(r'thl\("[^"]*",\s*\d+\);?'), ' ')
            .replaceAll(RegExp(r'\s*\d+ (min|分钟)\s*$'), '')
            .trim();
      }
      if (title.isEmpty) continue;
      final img = el.querySelector('img[data-src]') ?? el.querySelector('img');
      var cover = img?.attributes['data-src'] ?? img?.attributes['src'] ?? '';
      if (cover.contains('blank')) cover = '';
      // 封面同理：xv_THUMBNUM_t.jpg → xv_1_t.jpg（不填则 404）
      if (cover.contains('THUMBNUM')) cover = cover.replaceFirst('THUMBNUM', '1');
      final dur = el.querySelector('p.title span.duration')?.text.trim() ??
          el.querySelector('span.duration')?.text.trim() ??
          '';
      var meta = (el.querySelector('p.metadata')?.text ??
              el.querySelector('.video-metadata')?.text ??
              '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (dur.isNotEmpty && meta.startsWith(dur)) {
        meta = meta
            .substring(dur.length)
            .replaceAll(RegExp(r'^[\s\-–]+'), '');
      }
      // 最佳影片皮肤：时长在 metadata 末尾（"上传者 - 5.7M 观看次数 - 11分钟"）→ 去掉
      if (dur.isNotEmpty && meta.contains(dur)) {
        meta = meta
            .replaceAll(dur, ' ')
            .replaceAll(RegExp(r'\s*-\s*-\s*'), ' - ')
            .replaceAll(RegExp(r'^\s*[-–\s]+|[-–\s]+$'), '')
            .trim();
      }
      out.add(Article(
        title: title,
        url: href,
        cover: cover,
        meta: meta,
        badge: dur,
      ));
    }
    return out;
  }

  /// 頻道 / 色情明星 索引卡（div.thumb-block-profile）：名字 + 主页链接 + 头像。
  /// 头像图在卡片内 <script>document.write(…)</script> 的字符串里（DOM 里没有 img
  /// 节点），从 script 文本正则取；名字用 .profile-name（频道=span、演员=p>a）。
  List<Article> directory(String html) {
    final doc = hp.parse(html);
    final out = <Article>[];
    for (final el in doc.querySelectorAll('div.thumb-block')) {
      final a = el.querySelector('div.thumb a[href]');
      final href = a?.attributes['href'] ?? '';
      if (href.isEmpty || href.contains('/video.')) continue;
      final name = ((el.querySelector('p.profile-name a') ??
                      el.querySelector('.profile-name'))
                  ?.text ??
              '')
          .trim();
      if (name.isEmpty) continue;
      final script = el.querySelector('script')?.text ?? '';
      final cover =
          RegExp(r'<img src="([^"]+)"').firstMatch(script)?.group(1) ?? '';
      final counts = (el.querySelector('p.profile-counts')?.text ?? '').trim();
      out.add(Article(
        title: name,
        url: href,
        cover: cover,
        meta: counts,
      ));
    }
    return out;
  }

  /// 频道/演员路径（頻道、色情明星 卡点进来的 slug）：'/xxx' 或 '/models/xxx'。
  /// 其它已知分支（/c/、/tags、/best、/lang/、/channels-index、/pornstars-index、
  /// /new、/trans、/gay）都排除掉。
  bool _isXvProfile(String base) =>
      base.startsWith('/models/') ||
      (!base.startsWith('/c/') &&
          !base.startsWith('/tags') &&
          !base.startsWith('/best') &&
          !base.startsWith('/lang/') &&
          !base.startsWith('/channels-index') &&
          !base.startsWith('/pornstars-index') &&
          base != '/new' &&
          base != '/trans' &&
          base != '/gay');

  /// 频道/演员的「視頻」标签页 = 免费全量列表（站点顶上有 RED 收费 tab，不取）：
  /// GET /channels/<slug>/videos/best/{N-1}（0 计页、36/页）→ JSON。
  /// 频道 slug 直接接 /channels 下；演员 /models/xxx → /channels/xxx。
  Future<List<Article>> profileVideos(String base, {int page = 1}) async {
    final seg = base.startsWith('/models/')
        ? '/channels/${base.substring('/models/'.length)}'
        : '/channels$base';
    final j = jsonDecode(
        await _f.text('$seg/videos/best/${page - 1}', extraHeaders: _xvLang));
    final vids = (j is Map) ? j['videos'] : null;
    if (vids is! List) return const [];
    final out = <Article>[];
    for (final v in vids) {
      if (v is! Map) continue;
      var url = (v['u'] ?? '').toString();
      if (url.isEmpty) continue;
      // 站上给的是 /prof-video-click/… 跳转链接：改写成直链 /video.<eid>/<slug>
      // （少一跳、少一处失败面；两种形式实测都可达）
      if (url.startsWith('/prof-video-click')) {
        final eid = (v['eid'] ?? '').toString();
        final segs = url.split('/');
        if (eid.isNotEmpty && segs.isNotEmpty) {
          url = '/video.$eid/${segs[segs.length - 1]}';
        }
      }
      var title = (v['tf'] ?? v['t'] ?? '').toString();
      // 解 HTML 实体（tf 里带 &#039; 之类）；DocumentFragment.text 可为空 → 兜底 ''
      if (title.contains('&')) title = hp.parseFragment(title).text ?? '';
      final n = (v['n'] ?? '').toString().trim();
      out.add(Article(
        title: title.trim().isEmpty ? url : title.trim(),
        url: url,
        cover: (v['i'] ?? v['il'] ?? '').toString(),
        meta: n.isEmpty ? '' : '$n 观看次数',
        badge: (v['d'] ?? '').toString(),
      ));
    }
    return out;
  }

  Future<ArticleDetail> detail(String url) async {
    final html = await _f.text(url, extraHeaders: _xvLang);
    final doc = hp.parse(html);
    var title =
        RegExp(r"setVideoTitle\('([^']*)'\)").firstMatch(html)?.group(1)?.trim() ??
            '';
    if (title.isEmpty) {
      title = doc.querySelector('h2.page-title')?.text.trim() ?? url;
    }
    final dur =
        doc.querySelector('h2.page-title span.duration')?.text.trim() ?? '';
    // 播放源：HLS 优先（免费片的 High/Low 两条实测都是同一个 mp4_sd 最低画质），
    // mp4 兜底（单文件、无防盗链）
    final srcs = <String>[];
    for (final re in [
      RegExp(r"setVideoHLS\('([^']+)'\)"),
      RegExp(r"setVideoUrlHigh\('([^']+)'\)"),
      RegExp(r"setVideoUrlLow\('([^']+)'\)"),
    ]) {
      final u = re.firstMatch(html)?.group(1) ?? '';
      if (u.isNotEmpty && !srcs.contains(u)) srcs.add(u);
    }
    // HLS 主列表 → 展开成**各个档的子列表地址**（高→低）。原来只换「最高档」一条，
    // 因为 mpv 播 master 时挑哪档不可靠（老 libmpv 默认第一档=480p，且不做 ABR 上爬）；
    // 现在全留着：第一条仍是最高档（默认播它），详情页的「清晰度」行可换档（换档后
    // 由 detail_page 把选中的那档排到最前）。失败保留原地址。
    final hlsIdx = srcs.indexWhere((s) => s.contains('.m3u8'));
    if (hlsIdx >= 0) {
      final variants = await _f.hlsVariants(srcs[hlsIdx]);
      if (variants != null && variants.isNotEmpty) {
        srcs.removeAt(hlsIdx);
        srcs.insertAll(hlsIdx, variants);
      }
    }
    final videos = <ArticleVideo>[];
    if (srcs.isNotEmpty) {
      videos.add(ArticleVideo(label: '视频', ordinal: 1, sources: srcs));
    }
    final poster = doc
            .querySelector('meta[property="og:image"]')
            ?.attributes['content'] ??
        '';
    // 标签：/tags/xxx
    final tags = <MapEntry<String, String>>[];
    for (final a in doc.querySelectorAll('a[href^="/tags/"]')) {
      final name = a.querySelector('span.name')?.text.trim() ?? a.text.trim();
      final href = a.attributes['href'] ?? '';
      if (name.isEmpty || href == '/tags') continue;
      if (tags.any((t) => t.value == name)) continue;
      tags.add(MapEntry(href.replaceFirst('/tags/', ''), name));
    }
    // 相关推荐：页面内 JS 数组 video_related=[{u,i,t,d,…}]
    final related = <Article>[];
    final rm =
        RegExp(r'video_related=\[(.*?)\];', dotAll: true).firstMatch(html);
    if (rm != null) {
      try {
        final arr = jsonDecode('[${rm.group(1)}]');
        if (arr is List) {
          for (final e in arr) {
            if (e is! Map) continue;
            final u = '${e['u'] ?? ''}';
            final t = '${e['t'] ?? e['tf'] ?? ''}'.trim();
            if (u.isEmpty || t.isEmpty) continue;
            related.add(Article(
              title: t,
              url: u,
              cover: '${e['i'] ?? e['il'] ?? ''}',
              meta: '',
              badge: '${e['d'] ?? ''}',
            ));
            if (related.length >= 20) break;
          }
        }
      } catch (_) {
        // 解析不了当无相关推荐
      }
    }
    return ArticleDetail(
      title: title.isEmpty ? url : title,
      time: '',
      categories: const [],
      images: poster.isEmpty ? const [] : [poster],
      intro: '',
      videos: videos,
      tags: tags,
      related: related,
      seriesPrefix: '',
      duration: dur,
    );
  }
}
