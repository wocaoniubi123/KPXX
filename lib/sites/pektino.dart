// Pektino（pektino.com）—— **本站专属**的一切 ✓
//
// ⚠️ 用户 2026-10-03 决策：取消全站共享，站点相关的一切改成站点独立专属 ✓；底座保持公用 ✓。
// 从 `api.dart` 的 `Api` 里**原样搬**过来（**不重写逻辑** ✓ 行为不变 ✓），
// 仅把 `_fetchText(`→`_f.text(`、`_secClock(`→`secClock(`（已上移 base ✓）等**等价替换** ✓。

import 'dart:convert';

// ⚠️ 本站只用 `Color`（SiteEntry.color ✓），**不要** import flutter/material ✗
// —— material 会同时导出 `Element`/`Text`/`Key`，与 html/dom、encrypt 撞名 ✗（2026-10-03 analyze 报的 7 条错误就是这个 ✓）
// `Color` 本来就定义在 dart:ui ✓ Flutter 只是转发 ✓
import 'dart:ui' show Color;
import '../sites.dart';


import '../base/fetch.dart';
import '../base/site_ui.dart';
import '../models.dart';
// ★ 诊断打印：`debugPrint` 在 foundation 里 ✓（**不能**引 material ✗ 见上）；开关在 settings ✓
import 'package:flutter/foundation.dart' show debugPrint;
import '../settings.dart';

/// Pektino 本站专属实现（取数走公用底座 [SiteFetcher] ✓）
class PektinoSite extends SiteUi {
  PektinoSite(this._f);

  final SiteFetcher _f;

  /// 搜索 = 把输入当分类名传同一个接口（实测：搜 anime 出 50 条 ✓；原 `Api.search` 原样搬来 ✓）
@override
  Future<List<Article>> search(String keyword,
      {int page = 1, List<MapEntry<String, String>>? extra}) =>
      list('all', keyword, page: page);

  /// "标签" = 主题筛选（走同一个接口，全时段 ✓；原 `Api.tag` 的 case body 原样搬来 ✓）
@override
  Future<List<Article>> tag(String slug, {required int page}) => list('all', slug, page: page);

  /// 首页 = 每日榜（和站点首页一致 ✓；原 `Api.home` 的 case body 原样搬来 ✓）
@override
  Future<List<Article>> home({required int page, String first = ''}) => list('timely', '', page: page);

  /// 「分类」tab 的列表（原 `Api.category` 的 case body 原样搬来 ✓）
  /// 主分类 4 个都是路径型（/zh-CN/、/zh-CN/weekly…）→ 从路径解出 range ✓；
  /// 主题/时长/排序是主分类页面里的筛选器（多级分类），由列表页传入 ✓
@override
  Future<List<Article>> category(String key,
          {required int page,
          String? k,
          String? theme,
          String? duration,
          String? sort,
          List<MapEntry<String, String>>? extra,
          Future<List<Article>> Function({int page})? home}) async {
    final _sw = Stopwatch()..start();
    final r = key.endsWith('/weekly')
        ? 'weekly'
        : key.endsWith('/monthly')
            ? 'monthly'
            : key.endsWith('/all')
                ? 'all'
                : 'timely';
    final _list = await list(r, theme ?? '', page: page, duration: duration, sort: sort);
    // ★【常驻诊断】列表解析结果：站名 + key + 页 + 条数 + 耗时 ✓
    if (AppSettings.i.logConsole) debugPrint('[LIST] ${_f.site.name} k=$key 页=$page 解析出 ${_list.length} 条 ms=${_sw.elapsedMilliseconds}');
    return _list;
  }

  /// 列表走瀑布流（逐条按分辨率混排，不留空档 ✓）
  @override
  bool get masonry => true;

  // ---- 对外入口（原方法私有 ✗ 跨文件调不到 → 包一层公开 ✓，签名与调用点一字不差 ✓）----
  Future<List<Article>> list(String range, String category,
          {required int page, String? duration, String? sort}) =>
      _pektinoList(range, category,
          page: page, duration: duration, sort: sort);

@override
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
    final _sw = Stopwatch()..start();
    final html = await _f.text(url);
    final urlCd = url.split('/movie/').last.replaceAll('/', '');
    final plain = html.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
    final starts = <int>[];
    var at = -1;
    while ((at = plain.indexOf('"url_cd"', at + 1)) >= 0) {
      starts.add(at);
    }
    final entries = <Map<String, String>>[];
    for (var i = 0; i < starts.length; i++) {
      final end = i + 1 < starts.length ? starts[i + 1] : plain.length;
      final cap = starts[i] + 2000;
      final chunk = plain.substring(starts[i], end > cap ? cap : end);
      String grab(String key) {
        final m =
            RegExp('"$key":\\s*("(?:[^"]*)"|[0-9.]+|null)').firstMatch(chunk);
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
      if (e['url']!.isNotEmpty && e['thumbnail']!.isNotEmpty) {
        entries.add(e);
      }
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
    final _d = ArticleDetail(
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
    // ★【常驻诊断】详情解析结果：站名 + path(截 80) + 视频/图/相关条数 + 耗时 ✓（**不打完整 URL** ☠）
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] ${_f.site.name} path=${url.length <= 80 ? url : url.substring(0, 80)} 视频=${_d.videos.length} 图=${_d.images.length} 相关=${_d.related.length} ms=${_sw.elapsedMilliseconds}');
    return _d;
  }
}

// ===== 本站专属清单（2026-10-03 从 lib/sites.dart 下放 ✓；循环 import 允许 ✓）=====

const List<SiteTab> pkThemes = [
  SiteTab('shirouto', '业余'),
  SiteTab('kyonyu', '丰胸'),
  SiteTab('masturbation', '自我表达'),
  SiteTab('jk', '女高中生'),
  SiteTab('anime', '动漫 / 二次元'),
  SiteTab('female-teacher', '女教师'),
  SiteTab('nurse', '护士'),
  SiteTab('female-pervert', '大胆女性'),
  SiteTab('married-woman', '已婚女性'),
  SiteTab('beautiful-girl', '美少女'),
  SiteTab('big-sister', '姐姐'),
  SiteTab('gal', '时尚女孩'),
  SiteTab('shaved', '光滑风格'),
  SiteTab('small-breasts', '小胸'),
  SiteTab('lolita', '少女系'),
  SiteTab('swimsuit', '泳装'),
  SiteTab('sm', 'SM 题材'),
  SiteTab('special-feature', '企划'),
  SiteTab('incest', '家庭主题'),
  SiteTab('rape', '冲突主题'),
  SiteTab('molestation', '骚扰主题'),
  SiteTab('voyeur', '隐藏拍摄'),
  SiteTab('pickup', '邂逅'),
  SiteTab('massage', '按摩'),
  SiteTab('outdoor', '户外场景'),
  SiteTab('orgy', '群体场景'),
  SiteTab('anal', '背面主题'),
  SiteTab('deep-throat', '深层表达'),
  SiteTab('facial', '面部艺术'),
  SiteTab('cum-swallowing', '吞咽主题'),
  SiteTab('handjob', '手部表演'),
  SiteTab('creampie', '内部主题'),
  SiteTab('titjob', '胸部表演'),
  SiteTab('fellatio', '口部艺术'),
  SiteTab('bukkake', '泼洒艺术'),
  SiteTab('hamedori', '自摄'),
  SiteTab('personal-filming', '私人拍摄'),
  SiteTab('uncensored', '未修饰'),
  SiteTab('gay', '男同性恋・男娘'),
  SiteTab('cosplay', '角色扮演'),
];

const List<SiteTab> pkLangs = [
  SiteTab('ja', '日本'),
  SiteTab('zh-CN', '中国'),
  SiteTab('th', '泰国'),
  SiteTab('en', '英语'),
  SiteTab('zh-TW', '繁体中文'),
  SiteTab('ko', '韩语'),
  SiteTab('id', '印尼语'),
  SiteTab('pt', '葡萄牙语'),
  SiteTab('fr', '法语'),
  SiteTab('de', '德语'),
];

const List<MapEntry<String, String>> pkDurations = [
  MapEntry('0,0', '全部'),
  MapEntry('0,300', '0-5分钟'),
  MapEntry('300,900', '5-15分钟'),
  MapEntry('900,1800', '15-30分钟'),
  MapEntry('1800,3600', '30分钟-1小时'),
  MapEntry('3600,0', '1小时以上'),
];

const List<MapEntry<String, String>> pkSorts = [
  MapEntry('favorite', '按点赞'),
  MapEntry('pv', '按观看数'),
  MapEntry('time', '按时长'),
  MapEntry('created', '最近添加'),
];

// ===== 本站档案（2026-10-03 从 lib/sites.dart 的 kSites 下放 ✓）=====

/// 本站档案：Pektino
const SiteEntry kSite08 = SiteEntry(
    name: 'Pektino',
    template: SiteTemplate.pektino,
    iconUrl: '/favicon.ico',
    hosts: ['pektino.com'],
    // 主分类（顶部导航）**只有 4 个**：每日 / 每周 / 每月 / 所有时间
    //（站点还有个"收藏"页，要登录，未接）。
    // 20 个主题标签 + 时长 + 排序是**主分类页面里的筛选器**（多级分类），
    // 全部放进 filters，由列表页的筛选行渲染（照站点：筛选按钮 + 两个下拉）。
    categories: [
      SiteTab('/zh-CN/', '每日'),
      SiteTab('/zh-CN/weekly', '每周'),
      SiteTab('/zh-CN/monthly', '每月'),
      SiteTab('/zh-CN/all', '所有时间'),
    ],
    filters: SiteFilters(
      themes: pkThemes,
      languages: pkLangs,
      durations: pkDurations,
      sorts: pkSorts,
    ),
    color: Color(0xFF1DA1F2),
  );
