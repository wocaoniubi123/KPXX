// Pornhub（cn.pornhub.com）—— **本站专属**的一切 ✓
//
// ⚠️ 用户 2026-10-03 决策：取消全站共享，站点相关的一切改成**站点独立专属** ✓
//（分类/子分类/多级分类/选择器/重置/选中状态/取数解析）；**底座保持公用** ✓。
//
// 从 `api.dart` 的 `Api` 里**原样搬**过来（**不重写逻辑** ✓，行为不变 ✓），
// 仅把 `_fetchText(` 等价换成 `_f.text(` ✓（取数走公用底座 `SiteFetcher` ✓）。
// 段内自带 `_or` 这个本站小工具 ✓（原先也是段内定义的 ✓）。
//
// 对外入口：`list()` / `detail()` ✓（原方法私有 ✗，跨文件调不到 → 包一层公开 ✓）。

import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as hp;

import '../base/fetch.dart';
import '../base/site_ui.dart';
import '../models.dart';

/// Pornhub 本站专属实现（取数走公用底座 [SiteFetcher] ✓）
class PhSite extends SiteUi {
  PhSite(this._f);

  final SiteFetcher _f;

  /// 搜索 = /video/search?search=<kw>（站点自己的搜索页形态 ✓；kw 是原始文本，自己编码 ✓）
  Future<List<Article>> search(String keyword, {required int page}) =>
      list('/video/search?search=${Uri.encodeComponent(keyword)}', page: page);

  /// 标签列表页（原 `Api.tag` 的 case body 原样搬来 ✓）
  /// 详情页的标签是 `/video/search?search=<编码词>` ✓；演员卡传来的是 `/pornstar/xxx` ✓。
  /// 两者对本站都只是"一个站内路径"→ 直接当列表抓 ✓（演员路径回来的是视频卡 ✓）
  Future<List<Article>> tag(String slug, {required int page}) => list(slug, page: page);

  /// 首页 = '/'（原 `Api.home` 的 case body 原样搬来 ✓）
  Future<List<Article>> home({required int page}) => list('/', page: page);

  /// 「分类」tab 的列表（原 `Api.category` 的 case body 原样搬来 ✓）
  /// 列表 key 本身就是站内路径 ✓；「分类」tab 选中的分类是 theme（/video?c=27 ✓）。
  /// 「色情明星」tab 的筛选走 extra（o / performerType / t / 更多筛选各组的 key ✓）
  Future<List<Article>> category(String k, String? theme,
      {required int page, List<MapEntry<String, String>>? extra}) async {
    var php = theme ?? k;
    if (extra != null && extra.isNotEmpty) {
      php += '${php.contains('?') ? '&' : '?'}'
          '${extra.map((e) => '${e.key}=${e.value}').join('&')}';
    }
    return list(php, page: page);
  }

  /// Pornhub 只有 `/video` tab 挂筛选行（且无子分类时 ✓）
  @override
  bool showsFilterRow(String key, {required bool hasSubs}) => key == '/video' && !hasSubs;

  /// Pornhub 的「色情明星」tab ✓
  @override
  bool isStarTabKey(String key) => key == '/pornstars';

  /// Pornhub 星标 tab 的选中项走 `extra`（四个筛选拼查询串 ✓）
  @override
  bool get starUsesExtra => true;

  /// Pornhub 的演员卡/演员标签（`/pornstar/…`、`/model/…`）→ 进他的视频列表 ✓
  @override
  String? specialTap(String url) =>
      (url.startsWith('/pornstar/') || url.startsWith('/model/')) ? 'list' : null;

  /// 「色情明星」tab 用 Pornhub 那套筛选行 ✓
  @override
  String get starRowKind => 'ph';

  /// Pornhub 的「色情明星列表」判定（照原逻辑一字不差 ✓）
  @override
  bool isStarList(String slug) => slug == '/pornstars';

  /// "色情明星"tab 是竖版头像卡 → 一行 3 个 ✓
  @override
  bool get portraitStarCards => true;

  /// "色情明星"tab 挂本站专用筛选行 ✓
  @override
  bool get hasStarFilterRow => true;

  Future<List<Article>> list(String path, {int page = 1}) =>
      _phList(path, page: page);

  Future<ArticleDetail> detail(String url) => _phDetail(url);
  // Pornhub（cn.pornhub.com）
  //
  // ⚠️ 全部按**移动版 DOM**解析（App 的 UA 是 iPhone Safari）。桌面版是另一套结构，
  //    两套选择器不能混用 —— 2026-10-02 我混用后才误判"站点没有源"。
  // ⚠️ 列表类的 key 就是**站内路径**（sites.dart 的 pornhub 条目直接写路径）：
  //    '/'、'/video'、'/recommended'、'/video?o=ht'、'/shorties'、'/video?c=27'、
  //    '/pornstars'（演员卡）、'/pornstar/xxx'（该演员的视频）、'/video/search?search=<kw>'。

  /// 列表（视频卡；'/pornstars' 是演员卡）。翻页 = `?page=N`。
  Future<List<Article>> _phList(String path, {int page = 1}) async {
    var p = path.isEmpty ? '/' : path;
    // 首页第 2 页起站点自己指向 /video（实测），照它换
    if (page > 1 && p.split('?').first == '/') p = '/video';
    if (page > 1) p += '${p.contains('?') ? '&' : '?'}page=$page';
    final doc = hp.parse(await _f.text(p));
    return p.split('?').first == '/pornstars'
        ? _phStarCards(doc)
        : _phCards(doc);
  }

  /// Dart 没有 JS 那种「`a || b` 取第一个非空」——这就是它的替身（两边都空回 ''）。
  /// ⚠️ 2026-10-02 CI 报 `A value of type 'String' can't be assigned to a variable of
  /// type 'bool'`：我照 JS 惯用写了 `String || String`，Dart 的 `||` **只吃 bool**。
  String _or(String a, String b) => a.isNotEmpty ? a : b;

  /// 视频卡。选择器用 `[data-video-vkey]`（**不要求是 li**）：分类/搜索页的卡是 <li>，
  /// 但演员页的视频卡不是 li（实测 `li[data-video` 在演员页 0 条）。
  /// 标题取 `img[alt]` —— 卡片里第一个 <a> 是"已观看"角标，取它会拿到"已观看"三个字。
  /// [scope] 传了就在该子树里找（详情页的「相关推荐」= `#relatedVideos`）。
  List<Article> _phCards(Document doc, [Element? scope]) {
    final out = <Article>[];
    for (final el in (scope ?? doc).querySelectorAll('[data-video-vkey]')) {
      final a = el.querySelector('a[href*="view_video.php?viewkey="]');
      if (a == null) continue;
      final img = el.querySelector('img.videoThumb') ?? el.querySelector('img');
      final title = _or(img?.attributes['alt'] ?? '',
              el.querySelector('a.thumbnailTitle')?.text ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (title.isEmpty) continue;
      final durEl = el.querySelector('div.bgEffect.time') ??
          el.querySelector('div.time') ??
          el.querySelector('[class*="duration"]');
      final poster = el.querySelector('a[data-poster]');
      out.add(Article(
        title: title,
        url: a.attributes['href'] ?? '',
        cover: _or(img?.attributes['src'] ?? '',
            poster?.attributes['data-poster'] ?? ''),
        meta: '',
        badge: durEl?.text.trim() ?? '',
      ));
    }
    return out;
  }

  /// 演员卡（`/pornstars`）：`.performerCard` → 名字、头像、排名角标（`.rank_number`）。
  List<Article> _phStarCards(Document doc) {
    final out = <Article>[];
    for (final el in doc.querySelectorAll('.performerCard')) {
      final href = el.querySelector('a[href]')?.attributes['href'] ?? '';
      if (!RegExp(r'/(pornstar|model)/').hasMatch(href)) continue;
      final img = el.querySelector('img');
      final name = _or(el.querySelector('.performerCardName')?.text ?? '',
              img?.attributes['alt'] ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (name.isEmpty) continue;
      out.add(Article(
        title: name,
        url: href,
        cover: _or(img?.attributes['src'] ?? '',
            img?.attributes['data-thumb_url'] ?? ''),
        meta: '',
        badge: el.querySelector('.rank_number')?.text.trim() ?? '',
        coverAspect: 3 / 4, // 演员是竖版头像（列表一行 3 个，见 home_page 的星 tab 分支）
      ));
    }
    return out;
  }

  /// 抓到的源是否落在**被 Cloudflare 挡的子域**上。
  /// 实测：`hm-h.phncdn.com` 对新浪云外的所有非浏览器请求一律 410（`Server: cloudflare`
  /// + `__cf_bm`），而 `em-h`/`im-h` 畅通；子域是**每次抓页面随机分配**的 → 命中就重抓。
  bool _phBadHost(String html) {
    final m = RegExp(r'"videoUrl":"(https:[^"]*?master\.m3u8[^"]*)"').firstMatch(html);
    return m != null && m.group(1)!.contains('hm-h.phncdn.com');
  }

  /// 详情。`videos[0].sources` = 各档 master.m3u8，**720P 排最前** = 默认播 720P
  /// （播放器按 sources 顺序逐个试，所以"顺序"就是"默认档 + 降级顺序"；见 player_widget
  /// 的 `_openAndWait` 循环）。页面里 `mediaDefinitions` 的原始顺序是乱的
  /// （实测 1080/240/480/720），先按 height 排高→低再挑。
  Future<ArticleDetail> _phDetail(String url) async {
    var html = await _f.text(url);
    for (var i = 0; i < 2 && _phBadHost(html); i++) {
      html = await _f.text(url);
    }
    final doc = hp.parse(html);
    var title =
        (doc.querySelector('h1')?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (title.isEmpty) {
      title = (doc.querySelector('title')?.text ?? '')
          .replaceFirst(
              RegExp(r'\s*-\s*Pornhub\.com\s*$', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }
    final pairs = <MapEntry<int, String>>[];
    for (final m in RegExp(
            r'"height":(\d+)[^}]*?"videoUrl":"(https:[^"]*?master\.m3u8[^"]*)"')
        .allMatches(html)) {
      final u = m.group(2)!.replaceAll(r'\/', '/');
      if (!pairs.any((p) => p.value == u)) {
        pairs.add(MapEntry(int.parse(m.group(1)!), u));
      }
    }
    pairs.sort((a, b) => b.key.compareTo(a.key)); // 高 → 低
    final all = pairs.map((p) => p.value).toList();
    final srcs = <String>[
      ...all.where((u) => u.contains('720P_')), // 默认档放最前
      ...all.where((u) => !u.contains('720P_')),
    ];
    // 标签：播放器下方那排 `a.isTag`（实测一页约 25 个），href 是
    // /video/search?search=<编码词>，显示名在 <span>（站点已翻译成中文）
    final tags = <MapEntry<String, String>>[];
    for (final a in doc.querySelectorAll('a.isTag[href]')) {
      final name = a.text
          .replaceFirst(RegExp(r'^#'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final slug = a.attributes['href'] ?? '';
      if (name.isNotEmpty && slug.isNotEmpty) tags.add(MapEntry(slug, name));
    }
    // 相关推荐：页面里是**静态的** `#relatedVideos`（实测，不用额外请求）
    final relBox = doc.querySelector('#relatedVideos');
    return ArticleDetail(
      title: title.isEmpty ? url : title,
      time: '',
      categories: const [],
      images: const [],
      intro: '',
      videos: srcs.isEmpty
          ? const []
          : [ArticleVideo(label: '视频', ordinal: 1, sources: srcs)],
      tags: tags,
      related: relBox == null ? const [] : _phCards(doc, relBox),
      duration: doc.querySelector('div.duration')?.text.trim() ?? '',
      seriesPrefix: '',
    );
  }
  // ---------------------------------------------------------------------------
}

/// Pornhub「色情明星」tab 的筛选状态（照站点右上角那四个控件）：
/// 最受欢迎 ▾ / 色情明星和模特 ▾ / 每月 ▾ / + 更多筛选设置。
/// 值都直接是**URL 参数值**（o / performerType / t，选项见 sites.dart 的 phStar*），
/// 空串 = 该控件的默认（站点默认就是最受欢迎 / 色情明星和模特 / 每月）。
class PhStarFilters {
  String sort = '';
  String type = '';
  String time = '';

  /// 参数名（gender/ethnicity/tattoos/hair/piercings/cup/breasttype）→ 选中值
  final Map<String, String> more = {};

  /// 拼成 `extra`（Api 的 pornhub 分支会把它接在 /pornstars 后面）
  List<MapEntry<String, String>> toParams() => [
        if (sort.isNotEmpty) MapEntry('o', sort),
        if (type.isNotEmpty) MapEntry('performerType', type),
        if (time.isNotEmpty) MapEntry('t', time),
        for (final e in more.entries)
          if (e.value.isNotEmpty) MapEntry(e.key, e.value),
      ];

  /// 「更多筛选设置」里选中了几个（按钮高亮用）
  int get moreCount => more.values.where((v) => v.isNotEmpty).length;
}

/// Pornhub 色情明星筛选行（四个控件，照站点；前三个单选、选完即关）
class PhStarBar extends StatelessWidget {
  final PhStarFilters filters;
  final VoidCallback onChanged;
  const PhStarBar({required this.filters, required this.onChanged});

  /// 控件按钮上的文字：选中的显示选项名，没选显示默认名
  String _label(List<SiteTab> opts, String cur, String dft) {
    for (final o in opts) {
      if (o.key == cur) return cur.isEmpty ? dft : o.name;
    }
    return dft;
  }

  Future<void> _pick(BuildContext context, String title, List<SiteTab> opts,
          String cur, void Function(String) apply) =>
      pickOptionDialog(
        context,
        title,
        [for (final o in opts) MapEntry(o.key, o.name)],
        cur,
        (v) {
          apply(v);
          onChanged();
        },
      );

  Future<void> _pickMore(BuildContext context) async {
    final sel = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => PhMoreDialog(init: Map.of(filters.more)),
    );
    if (sel != null) {
      filters.more
        ..clear()
        ..addAll(sel);
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = filters;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            filterBtn(_label(phStarSorts, f.sort, '最受欢迎'), f.sort.isNotEmpty,
                () => _pick(context, '排序', phStarSorts, f.sort,
                    (v) => f.sort = v)),
            const SizedBox(width: 6),
            filterBtn(_label(phStarTypes, f.type, '色情明星和模特'), f.type.isNotEmpty,
                () => _pick(context, '类型', phStarTypes, f.type,
                    (v) => f.type = v)),
            const SizedBox(width: 6),
            filterBtn(_label(phStarTimes, f.time, '每月'), f.time.isNotEmpty,
                () => _pick(context, '时间区段', phStarTimes, f.time,
                    (v) => f.time = v)),
            const SizedBox(width: 6),
            filterBtn('+ 更多筛选设置', f.moreCount > 0, () => _pickMore(context)),
          ],
        ),
      ),
    );
  }
}

/// Pornhub「+ 更多筛选设置」：7 组（性别/种族/纹身/发色/穿环/罩杯/胸型），
/// 组内单选、组间独立；確定写回、清除全空、取消不改。
class PhMoreDialog extends StatefulWidget {
  final Map<String, String> init;
  const PhMoreDialog({required this.init});
  @override
  State<PhMoreDialog> createState() => PhMoreDialogState();
}

class PhMoreDialogState extends State<PhMoreDialog> {
  late final Map<String, String> _sel = Map.of(widget.init);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('更多筛选设置'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final g in phStarMore) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Text(g.name,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF666666))),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in g.subs)
                    GestureDetector(
                      onTap: () => setState(() {
                        if (o.key.isEmpty) {
                          _sel.remove(g.key); // 「全部」= 该组不传参数
                        } else {
                          _sel[g.key] = o.key;
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: (_sel[g.key] ?? '') == o.key
                              ? const Color(0xFFE8590C)
                              : const Color(0xFFF0F0F2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(o.name,
                            style: TextStyle(
                                fontSize: 12,
                                color: (_sel[g.key] ?? '') == o.key
                                    ? Colors.white
                                    : const Color(0xFF444444))),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, <String, String>{}),
            child: const Text('清除')),
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(
            onPressed: () => Navigator.pop(context, _sel),
            child: const Text('確定')),
      ],
    );
  }
}
