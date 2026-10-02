// Pektino（pektino.com）—— **本站专属**的一切 ✓
//
// ⚠️ 用户 2026-10-03 决策：取消全站共享，站点相关的一切改成站点独立专属 ✓；底座保持公用 ✓。
// 从 `api.dart` 的 `Api` 里**原样搬**过来（**不重写逻辑** ✓ 行为不变 ✓），
// 仅把 `_fetchText(`→`_f.text(`、`_secClock(`→`secClock(`（已上移 base ✓）等**等价替换** ✓。

import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as hp;

import '../base/fetch.dart';
import '../base/site_ui.dart';
import '../models.dart';

/// Pektino 本站专属实现（取数走公用底座 [SiteFetcher] ✓）
class PektinoSite implements SiteUi {
  PektinoSite(this._f);

  final SiteFetcher _f;

  /// 列表走瀑布流（逐条按分辨率混排，不留空档 ✓）
  @override
  bool get masonry => true;

  // ---- 对外入口（原方法私有 ✗ 跨文件调不到 → 包一层公开 ✓，签名与调用点一字不差 ✓）----
  Future<List<Article>> list(String range, String category,
          {required int page, String? duration, String? sort}) =>
      _pektinoList(range, category,
          page: page, duration: duration, sort: sort);

  Future<ArticleDetail> detail(String url) => _pektinoDetail(url);
  // Pektino（X/Twitter 视频保存排行站：Next.js）
  //
  // 列表/搜索共用接口：/api/media?range=..&page=..&per_page=50
  //   &category=..&ids=&isFilteredOnly=0&sort=favorite
  // 视频源 = 推文原 mp4（video.twimg.com 直链，列表字段 url 里就带）；
  // 详情页 HTML 的 Next.js payload 里也有完整数据块（转义 JSON），正则抽取。

  /// 列表（主分类 / 搜索共用）。[category] 空串 = 全站（= 不选主题）。
  /// [duration] = 时长档 "min,max"（秒，"0,0"=全部）；[sort] = favorite/pv/time/created
  Future<List<Article>> _pektinoList(String range, String category,
      {required int page, String? duration, String? sort}) async {
    final d = (duration ?? '').split(',');
    final min = d.length == 2 ? (int.tryParse(d[0]) ?? 0) : 0;
    final max = d.length == 2 ? (int.tryParse(d[1]) ?? 0) : 0;
    final path = '/api/media?range=$range&page=$page&per_page=50'
        '&category=${Uri.encodeComponent(category)}'
        '&ids=&isFilteredOnly=0&sort=${sort ?? 'favorite'}'
        '${min > 0 ? '&min_time=$min' : ''}'
        '${max > 0 ? '&max_time=$max' : ''}';
    final data = jsonDecode(await _f.text(path));
    final items =
        data is Map<String, dynamic> ? (data['items'] ?? const []) : const [];
    return [
      for (final it in items)
        if (it is Map<String, dynamic>) _pektinoArticle(it),
    ];
  }

  /// 一条视频 → 卡片。站点卡片就三样：Twitter 封面（横竖混排）+ 右下角时长
  /// + 播放/评论/收藏数，**没有标题**（照站点，title 留空、卡片端不渲染标题）。
  Article _pektinoArticle(Map<String, dynamic> v) {
    final urlCd = '${v['url_cd'] ?? ''}';
    final pv = '${v['pv'] ?? ''}';
    final fav = '${v['favorite'] ?? ''}';
    final cc = v['commentCount'];
    final parts = <String>[
      if (pv.isNotEmpty) '播放 $pv',
      if (cc is num) '评论 $cc',
      if (fav.isNotEmpty) '收藏 $fav',
    ];
    return Article(
      title: '',
      url: '/zh-CN/movie/$urlCd',
      cover: '${v['thumbnail'] ?? ''}',
      meta: '',
      badge: secClock('${v['time'] ?? ''}'),
      desc: parts.join(' · '),
      coverAspect: _pektinoAspect('${v['url'] ?? ''}'),
    );
  }

  /// 从 mp4 直链解分辨率算宽高比（/vid/avc1/1920x1080/ → 16:9）。
  /// 拿不到返回 null → 卡片退回站点默认比例。
  static double? _pektinoAspect(String mp4) {
    final m = RegExp(r'/(\d{2,5})x(\d{2,5})/').firstMatch(mp4);
    if (m == null) return null;
    final w = int.tryParse(m.group(1)!);
    final h = int.tryParse(m.group(2)!);
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }

  /// 详情：页面 HTML 的 Next.js payload 里就有完整数据块，
  /// 把 `\"` 反转义后按 `"url_cd"` 切块、正则抽字段（整段 JSON 解析不划算）。
  /// 相关推荐 = payload 里的其它视频（各条都带 url_cd/thumbnail/time/url）。
  Future<ArticleDetail> _pektinoDetail(String url) async {
    final html = await _f.text(url);
    final urlCd = url.split('/movie/').last.replaceAll('/', '');
    final plain = html.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
    final starts = <int>[];
    var at = -1;
    while ((at = plain.indexOf('"url_cd"', at + 1)) >= 0) starts.add(at);
    final entries = <Map<String, String>>[];
    for (var i = 0; i < starts.length; i++) {
      final end = i + 1 < starts.length ? starts[i + 1] : plain.length;
      final cap = starts[i] + 2000;
      final chunk = plain.substring(starts[i], end > cap ? cap : end);
      String grab(String key) {
        final m =
            RegExp('"' + key + r'":\s*("(?:[^"]*)"|[0-9.]+|null)').firstMatch(chunk);
        if (m == null) return '';
        final v = m.group(1)!;
        return v == 'null' ? '' : (v.startsWith('"') ? v.substring(1, v.length - 1) : v);
      }

      final e = {
        'url_cd': grab('url_cd'),
        'url': grab('url'),
        'time': grab('time'),
        'thumbnail': grab('thumbnail'),
        'pv': grab('pv'),
        'favorite': grab('favorite'),
        'tweet_account': grab('tweet_account'),
      };
      // 只收"真视频条目"（有 mp4 有封面），挡掉 tags 表之类的噪音
      if (e['url']!.isNotEmpty && e['thumbnail']!.isNotEmpty) entries.add(e);
    }
    Map<String, String>? main;
    final rel = <Map<String, String>>[];
    for (final e in entries) {
      if (e['url_cd'] == urlCd && main == null) {
        main = e;
      } else {
        rel.add(e);
      }
    }
    main ??= entries.isNotEmpty ? entries.first : null;
    final mp4 = main?['url'] ?? '';
    final pv = main?['pv'] ?? '';
    final fav = main?['favorite'] ?? '';
    final acc = main?['tweet_account'] ?? '';
    return ArticleDetail(
      title: urlCd.isEmpty ? url : urlCd,
      time: '',
      categories: const [],
      images: const [],
      intro: [
        if (acc.isNotEmpty) '@$acc',
        if (pv.isNotEmpty) '$pv 次播放',
        if (fav.isNotEmpty) '$fav 收藏',
      ].join(' · '),
      duration: secClock(main?['time'] ?? ''),
      videos: [
        if (mp4.isNotEmpty)
          ArticleVideo(label: '视频', ordinal: 1, sources: [mp4]),
      ],
      tags: const [],
      related: [
        for (final e in rel.take(12))
          if (e['url_cd']!.isNotEmpty)
            Article(
              title: '',
              url: '/zh-CN/movie/${e['url_cd']}',
              cover: e['thumbnail']!,
              meta: '',
              badge: secClock(e['time'] ?? ''),
              coverAspect: _pektinoAspect(e['url'] ?? ''),
            ),
      ],
      seriesPrefix: '',
    );
  }
}
