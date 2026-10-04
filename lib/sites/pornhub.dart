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


import 'package:flutter/material.dart';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as hp;

import '../base/fetch.dart';
import '../base/site_ui.dart';
import '../config.dart';
import '../models.dart';
import '../sites.dart';

/// Pornhub 本站专属实现（取数走公用底座 [SiteFetcher] ✓）
class PhSite extends SiteUi {
  PhSite(this._f);

  final SiteFetcher _f;




  /// 搜索 = /video/search?search=<kw>（站点自己的搜索页形态 ✓；kw 是原始文本，自己编码 ✓）
@override
  Future<List<Article>> search(String keyword,
      {int page = 1, List<MapEntry<String, String>>? extra}) =>
      list('/video/search?search=${Uri.encodeComponent(keyword)}', page: page);

  /// 标签列表页（原 `Api.tag` 的 case body 原样搬来 ✓）
  /// 详情页的标签是 `/video/search?search=<编码词>` ✓；演员卡传来的是 `/pornstar/xxx` ✓。
  /// 两者对本站都只是"一个站内路径"→ 直接当列表抓 ✓（演员路径回来的是视频卡 ✓）
@override
  Future<List<Article>> tag(String slug, {required int page}) => list(slug, page: page);

  /// 首页 = '/'（原 `Api.home` 的 case body 原样搬来 ✓）
@override
  Future<List<Article>> home({required int page, String first = ''}) => list('/', page: page);

  /// 「分类」tab 的列表（原 `Api.category` 的 case body 原样搬来 ✓）
  /// 列表 key 本身就是站内路径 ✓；「分类」tab 选中的分类是 theme（/video?c=27 ✓）。
  /// 「色情明星」tab 的筛选走 extra（o / performerType / t / 更多筛选各组的 key ✓）
@override
  Future<List<Article>> category(String key,
          {required int page,
          String? k,
          String? theme,
          String? duration,
          String? sort,
          List<MapEntry<String, String>>? extra,
          Future<List<Article>> Function({int page})? home}) async {
    // 并集里 kk 可空、theme 具名 ✗ → 绑定回原语义 ✓
    final kk = k ?? key;
    var php = theme ?? kk;
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

  /// "色情明星"tab 挂本站专用筛选行 ✓

  Future<List<Article>> list(String path, {int page = 1}) =>
      _phList(path, page: page);

@override
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
  List<Article> _phCards(dom.Document doc, [dom.Element? scope]) {
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
  List<Article> _phStarCards(dom.Document doc) {
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

  /// **已知坏子域**缓存（进程内 ✓、不持久化 ✗、不跨进程 ✗）。
  /// 键 = 子域（`em-h.phncdn.com` ✓）、值 = (上次探测用的 URL ✓, 判定时刻 ✓)；
  /// 寿命 [_phBadTtl] = 10 分钟（recon 实测坏域稳定：`hm-h` 7 次加载全 410 ✓，
  /// `em-h`/`km-h`/`im-h` 全 200 ✓ → 短期不会变 ✓）；上限 [_phBadMax] = 8 条
  /// （实测只见过 4 个子域 ✓；满了淘汰最早插入的一条 ✓，只是个防增长的小闸 ✓）。
  final Map<String, (String, DateTime)> _phBadHosts = {};
  static const Duration _phBadTtl = Duration(minutes: 10);
  static const int _phBadMax = 8;

  /// 这条源还能不能用 —— 判据只看**响应码**（410 = 坏子域；403/404 = 签名/资源不可用），
  /// **不写死子域名**（坏子域名会变 ✓）。探测形态：**HEAD 优先**（最轻 ✓；实测这个 CDN 上
  /// HEAD 与 GET 同结果：坏域 410 / 好域 200 ✓），HEAD 给别的码（405/501 之类不认 HEAD 的
  /// 情况 ✓）才退一次 GET（最坏多 1 个请求 ✓，不把"不认 HEAD"误判成"坏"✗）。
  /// 超时/异常 → 返回 true（= **不据此判坏** ✓，交给播放器按顺序降级 ✓，避免误杀慢源 ✓）。
  Future<bool> _phProbeOk(String u) async {
    final uri = Uri.tryParse(u);
    if (uri == null) return true;
    final host = uri.host;
    final cached = _phBadHosts[host];
    if (cached != null &&
        DateTime.now().difference(cached.$2) < _phBadTtl) {
      return false; // 已知坏 + 没过期 → 跳过探测，直接让上层重抓换子域 ✓
    }
    final headers = {
      'User-Agent': Site.ua,
      'Referer': 'https://${_f.host}/',
    };
    try {
      final h = await _f.client
          .head(uri, headers: headers)
          .timeout(const Duration(seconds: 8));
      if (h.statusCode == 410 || h.statusCode == 404 || h.statusCode == 403) {
        _phMarkBad(host, u);
        return false;
      }
      if (h.statusCode >= 200 && h.statusCode < 300) return true;
      // 其它码（HEAD 不被支持等）→ 用 GET 复核一次，别误判 ✓
      final g = await _f.client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 8));
      if (g.statusCode == 410 || g.statusCode == 404 || g.statusCode == 403) {
        _phMarkBad(host, u);
        return false;
      }
      return true;
    } catch (_) {
      return true; // 超时/异常不判坏 ✓
    }
  }

  void _phMarkBad(String host, String u) {
    _phBadHosts[host] = (u, DateTime.now());
    while (_phBadHosts.length > _phBadMax) {
      _phBadHosts.remove(_phBadHosts.keys.first); // 插满淘汰最早的 ✓
    }
  }

  /// 详情。`videos[0].sources` = 各档 HLS（master.m3u8 / 短片页的 index.m3u8），
  /// **站点标了 `"defaultQuality":true` 的档排最前**（实测：站点给 720P 标了 true），
  /// 取不到标记才退回站点原始顺序 ×（见下方）。
  /// （播放器按 sources 顺序逐个试，所以"顺序"就是"默认档 + 降级顺序"；见 player_widget
  /// 的 `_openAndWait` 循环）。页面里 `mediaDefinitions` 的原始顺序是乱的（实测 1080/240/480/720）。
  Future<ArticleDetail> _phDetail(String url) async {
    final pairs = <MapEntry<int, String>>[];
    var defIdx = -1; // `"defaultQuality":true` 那条的下标（站点自己的默认档）
    var html = '';
    // 抓 + 判：**只探"将要用到的那一档"**（默认档已排最前；recon 复核：同一页面 4 档
    // 永远同一个子域 = 第一档坏则整页坏 ✓ → 坏页 4 个 GET 变 1 个 HEAD ✓）；
    // 坏子域就重抓换子域，上限 5 次（recon：坏子域命中率 7/25）
    for (var i = 0; i < 5; i++) {
      html = await _f.text(url);
      pairs.clear();
      defIdx = -1;
      for (final m in RegExp(
              r'"height":(\d+)[^}]*?"videoUrl":"(https:[^"]*?(?:master|index)\.m3u8[^"]*)"')
          .allMatches(html)) {
        final u = m.group(2)!.replaceAll(r'\/', '/');
        if (!pairs.any((p) => p.value == u)) {
          pairs.add(MapEntry(int.parse(m.group(1)!), u));
          if (m.group(0)!.contains('"defaultQuality":true')) {
            defIdx = pairs.length - 1;
          }
        }
      }
      if (pairs.isEmpty) break; // 空源 → 上层报"暂无视频"，别空转 ✓
      // 先排默认档（探的、播的都是它 = "将要用到的那一档" ✓）
      if (defIdx > 0 && defIdx < pairs.length) {
        final d = pairs.removeAt(defIdx);
        pairs.insert(0, d);
      }
      if (await _phProbeOk(pairs.first.value)) break; // 第一档能用 → 整页能用 ✓
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
    final srcs = pairs.map((p) => p.value).toList();
    // （默认档已在上面循环里排到最前 ✓ —— 探的就是它、播的也是它 ✓）
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

/// **本站「色情明星」筛选的状态 + 筛选行**（用户 2026-10-03 要求：站点专属逻辑回到站点文件 ✓）
///
/// ⚠️ 原先 `_phStar` 与行组装都在公共页面里 ✗；现在状态归本站 ✓，页面只提供"重新拉列表"回调 ✓。
class PhStarController {
  final PhStarFilters filters = PhStarFilters();

  Widget row({required VoidCallback onChanged}) =>
      PhStarBar(filters: filters, onChanged: onChanged);
}

/// Pornhub 色情明星筛选行（四个控件，照站点；前三个单选、选完即关）
class PhStarBar extends StatelessWidget {
  final PhStarFilters filters;
  final VoidCallback onChanged;
  const PhStarBar({super.key, required this.filters, required this.onChanged});

  /// 控件按钮上的文字：选中的显示选项名，没选显示默认名
  String _label(List<SiteTab> opts, String cur, String dft) {
    for (final o in opts) {
      if (o.key == cur) return cur.isEmpty ? dft : o.name;
    }
    return dft;
  }

  Future<void> _pick(BuildContext context, String title, List<SiteTab> opts,
          String cur, void Function(String) apply) =>
      _phPickOptionDialog(
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
            siteFilterBtn(_label(phStarSorts, f.sort, '最受欢迎'), f.sort.isNotEmpty,
                () => _pick(context, '排序', phStarSorts, f.sort,
                    (v) => f.sort = v)),
            const SizedBox(width: 6),
            siteFilterBtn(_label(phStarTypes, f.type, '色情明星和模特'), f.type.isNotEmpty,
                () => _pick(context, '类型', phStarTypes, f.type,
                    (v) => f.type = v)),
            const SizedBox(width: 6),
            siteFilterBtn(_label(phStarTimes, f.time, '每月'), f.time.isNotEmpty,
                () => _pick(context, '时间区段', phStarTimes, f.time,
                    (v) => f.time = v)),
            const SizedBox(width: 6),
            siteFilterBtn('+ 更多筛选设置', f.moreCount > 0, () => _pickMore(context)),
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
  const PhMoreDialog({super.key, required this.init});
  @override
  State<PhMoreDialog> createState() => PhMoreDialogState();
}

class PhMoreDialogState extends State<PhMoreDialog> {
  late final Map<String, String> _sel = Map.of(widget.init);

  @override
  Widget build(BuildContext context) {
    return siteTagDialog(
      title: const Text('更多筛选设置'),
      // A2：本站弹窗没有 420 上限、内部用 shrinkWrap ListView 保留差异
      constrained: false,
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

/// 筛选按钮（本站自带副本 ✓）



/// 单选弹窗（本站自带副本 ✓）
Future<void> _phPickOptionDialog(
  BuildContext context,
  String title,
  List<MapEntry<String, String>> options,
  String current,
  void Function(String key) apply,
) async {
  final v = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      children: [
        for (final o in options)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, o.key),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    o.value,
                    style: TextStyle(
                        fontSize: 14,
                        color: o.key == current
                            ? const Color(0xFFE8590C)
                            : const Color(0xFF333333)),
                  ),
                ),
                if (o.key == current)
                  const Icon(Icons.check, size: 16, color: Color(0xFFE8590C)),
              ],
            ),
          ),
      ],
    ),
  );
  if (v != null && v != current) apply(v);
}

// ===== 本站专属清单（2026-10-03 从 lib/sites.dart 下放 ✓；循环 import 允许 ✓）=====

const List<SiteTab> phCats = [
  SiteTab('/video?c=17', '黑人女'),
  SiteTab('/video?c=6', '大号美女'),
  SiteTab('/video?c=492', '女性自慰'),
  SiteTab('/video?c=7', '巨屌'),
  SiteTab('/video?c=22', '手淫'),
  SiteTab('/transgender', '跨性别'),
  SiteTab('/categories/pornstar', '色情明星'),
  SiteTab('/video?c=115', '独家'),
  SiteTab('/video?c=25', '跨种族'),
  SiteTab('/video?c=59', '贫乳'),
  SiteTab('/categories/teen', '18-25歲'),
  SiteTab('/video?c=65', '3P'),
  SiteTab('/video?c=105', '60帧'),
  SiteTab('/video?c=241', 'Cosplay'),
  SiteTab('/sfw', '上班时观赏'),
  SiteTab('/video?c=2', '乱交群欢'),
  SiteTab('/video?c=1', '亚洲人'),
  SiteTab('/interactive', '交互式'),
  SiteTab('/video?c=542', '佩戴式阳具'),
  SiteTab('/video?c=99', '俄国人'),
  SiteTab('/video?c=24', '公众野战'),
  SiteTab('/video?c=15', '内射中出'),
  SiteTab('/video?c=732', '内嵌字幕'),
  SiteTab('/video?c=21', '劲爆重口味'),
  SiteTab('/video?c=86', '卡通'),
  SiteTab('/video?c=101', '印度人'),
  SiteTab('/video?c=76', '双性恋男'),
  SiteTab('/video?c=72', '双龙入洞'),
  SiteTab('/video?c=13', '口交'),
  SiteTab('/video?c=43', '古典派'),
  SiteTab('/video?c=57', '合集'),
  SiteTab('/video?c=12', '名人'),
  SiteTab('/categories/college', '大学'),
  SiteTab('/video?c=27', '女同'),
  SiteTab('/popularwithwomen', '女性之选'),
  SiteTab('/video?c=502', '女性高潮'),
  SiteTab('/video?c=242', '娇妻偷吃'),
  SiteTab('/video?c=16', '射精'),
  SiteTab('/video?c=8', '巨乳'),
  SiteTab('/video?c=482', '已认证情侣'),
  SiteTab('/video?c=139', '已认证模特'),
  SiteTab('/video?c=138', '已认证素人'),
  SiteTab('/video?c=102', '巴西人'),
  SiteTab('/video?c=95', '德国人'),
  SiteTab('/video?c=23', '性玩具'),
  SiteTab('/video?c=18', '恋物癖'),
  SiteTab('/video?c=93', '恋足'),
  SiteTab('/video?c=97', '意大利人'),
  SiteTab('/video?c=20', '手交'),
  SiteTab('/video?c=91', '抽烟'),
  SiteTab('/video?c=26', '拉丁裔美女'),
  SiteTab('/video?c=19', '拳交'),
  SiteTab('/video?c=592', '指交'),
  SiteTab('/video?c=78', '按摩'),
  SiteTab('/video?c=10', '捆绑'),
  SiteTab('/video?c=100', '捷克人'),
  SiteTab('/video?c=32', '搞笑'),
  SiteTab('/video?c=211', '撒尿'),
  SiteTab('/video?c=891', '播客'),
  SiteTab('/video?c=111', '日本人'),
  SiteTab('/video?c=88', '校园'),
  SiteTab('/video?c=55', '欧洲人'),
  SiteTab('/video?c=94', '法国人'),
  SiteTab('/video?c=522', '浪漫'),
  SiteTab('/video?c=11', '深发女'),
  SiteTab('/video?c=201', '滑稽模仿'),
  SiteTab('/video?c=69', '潮吹'),
  SiteTab('/video?c=89', '火辣保姆'),
  SiteTab('/video?c=28', '熟女'),
  SiteTab('/video?c=35', '爆菊'),
  SiteTab('/video?c=141', '片场直击'),
  SiteTab('/video?c=92', '男性自慰'),
  SiteTab('/video?c=31', '真人实拍'),
  SiteTab('/video?c=41', '第一视角'),
  SiteTab('/video?c=67', '粗暴性爱'),
  SiteTab('/video?c=3', '素人'),
  SiteTab('/video?c=42', '红毛'),
  SiteTab('/video?c=562', '纹身女'),
  SiteTab('/video?c=444', '继家庭幻想'),
  SiteTab('/video?c=181', '老少欢'),
  SiteTab('/video?c=53', '聚会'),
  SiteTab('/video?c=512', '肌肉男'),
  SiteTab('/video?c=4', '肥臀'),
  SiteTab('/video?c=33', '脱衣舞'),
  SiteTab('/described-video', '自述视频'),
  SiteTab('/video?c=131', '舔屄'),
  SiteTab('/categories/hentai', '色情日漫'),
  SiteTab('/video?c=96', '英国人'),
  SiteTab('/vr', '虚拟现实'),
  SiteTab('/video?c=61', '视频激情'),
  SiteTab('/video?c=81', '角色扮演'),
  SiteTab('/video?c=90', '试镜'),
  SiteTab('/video?c=881', '赌博'),
  SiteTab('/video?c=80', '轮交'),
  SiteTab('/video?c=29', '辣妈'),
  SiteTab('/video?c=9', '金发女'),
  SiteTab('/video?c=98', '阿拉伯人'),
  SiteTab('/video?c=14', '集体颜射'),
  SiteTab('/video?c=103', '韩国人'),
  SiteTab('/video?c=121', '音乐'),
  SiteTab('/categories/babe', '风情少女'),
  SiteTab('/hd', '高清色情片'),
];

const List<SiteTab> phStarSorts = [
  SiteTab('', '最受欢迎'),
  SiteTab('mv', '最多次观看'),
  SiteTab('t', '最热门'),
  SiteTab('ms', '最多订阅'),
  SiteTab('a', '按字母排序'),
  SiteTab('nv', '视频数量'),
  SiteTab('r', '随机'),
];

const List<SiteTab> phStarTypes = [
  SiteTab('', '色情明星和模特'),
  SiteTab('pornstar', '色情明星'),
  SiteTab('amateur', '素人模特'),
];

const List<SiteTab> phStarTimes = [
  SiteTab('w', '每周'),
  SiteTab('', '每月'),
  SiteTab('a', '每年'),
];

const List<SiteTab> phStarMore = [
  SiteTab('gender', '性别', [
    SiteTab('', '全部'),
    SiteTab('male', '男性'),
    SiteTab('female', '女性'),
    SiteTab('m2f', '变性女'),
    SiteTab('f2m', '变性男'),
  ]),
  SiteTab('ethnicity', '种族', [
    SiteTab('', '全部'),
    SiteTab('asian', 'Asian'),
    SiteTab('black', 'Black'),
    SiteTab('indian', 'Indian'),
    SiteTab('latin', 'Latin'),
    SiteTab('middle+eastern', 'Middle Eastern'),
    SiteTab('mixed', 'Mixed'),
    SiteTab('white', 'White'),
    SiteTab('other', 'Other'),
  ]),
  SiteTab('tattoos', '纹身',
      [SiteTab('', '全部'), SiteTab('yes', 'Yes'), SiteTab('no', 'No')]),
  SiteTab('hair', '发色', [
    SiteTab('', '全部'),
    SiteTab('auburn', 'Auburn'),
    SiteTab('bald', 'Bald'),
    SiteTab('black', 'Black'),
    SiteTab('blonde', 'Blonde'),
    SiteTab('brunette', 'Brunette'),
    SiteTab('grey', 'Grey'),
    SiteTab('red', 'Red'),
    SiteTab('various', 'Various'),
    SiteTab('other', 'Other'),
  ]),
  SiteTab('piercings', '穿环',
      [SiteTab('', '全部'), SiteTab('yes', 'Yes'), SiteTab('no', 'No')]),
  SiteTab('cup', '罩杯', [
    SiteTab('', '全部'),
    SiteTab('a', 'A'),
    SiteTab('b', 'B'),
    SiteTab('c', 'C'),
    SiteTab('d', 'D'),
    SiteTab('e', 'E'),
    SiteTab('f-z', 'F-Z'),
  ]),
  SiteTab('breasttype', '胸型', [
    SiteTab('', '全部'),
    SiteTab('natural', 'Natural'),
    SiteTab('fake', 'Fake'),
  ]),
];

// ===== 本站档案（2026-10-03 从 lib/sites.dart 的 kSites 下放 ✓）=====

/// 本站档案：Pornhub
const SiteEntry kSite13 = SiteEntry(
    name: 'Pornhub',
    template: SiteTemplate.pornhub,
    iconUrl: '/favicon.ico',
    hosts: ['cn.pornhub.com'],
    categories: [
      SiteTab('/', '首页'),
      SiteTab('/video', '视频', [
        SiteTab('/video', '探索视频'),
        SiteTab('/recommended', '推荐视频'),
        SiteTab('/video?o=ht', '最热门'),
        SiteTab('/video?o=mv', '最多次观看'),
        SiteTab('/video?o=tr', '最高分'),
        SiteTab('/video?p=homemade&o=tr', '热门自制'),
        SiteTab('/shorties', '短片'),
        SiteTab('/channels', '频道'),
        SiteTab('/video?o=cm', '最新'),
      ]),
      // ⚠️ 「分类」**是主分类 tab，必须保留**（用户 2026-10-02 指出：首页 / 视频 / 分类 三个都在）——
      // 只是它**不要平铺子项**：站点顶栏那个「分类」是下拉，我们让它进**全部视频**，
      // 再由列表页顶部的「分类」筛选按钮弹窗选那 102 个（见下面的 filters / phCats）。
      SiteTab('/video', '分类'),
      // 色情明星：站点顶栏第 5 项。进去是**演员卡列表**（61 个/页，名字+头像+排名），
      // 点演员 → 演员页（`/pornstar/xxx`、`/model/xxx`）——**那是他的视频列表**，不是视频详情。
      // 筛选（用户 2026-10-02 点名要的）：排序（`?o=`，7 项，见 phStarSorts）
      // + 演员类型（`?performerType=`，见 phStarTypes）+ 时间区段（`?t=`，见 phStarTimes）
      // + 「更多筛选设置」7 组（见 phStarMore，组各自的 URL 参数名已从站点实测确认）。
      SiteTab('/pornstars', '色情明星'),
    ],
    // 「分类」**不做平铺 tab**（站点顶栏那个是下拉、不是列表页）：做成列表页上的
    // 筛选按钮 → 点开**弹窗**选，候选 = /categories 页的 102 个（见 phCats）。
    // 按钮与弹窗标题用 themeLabel 显示成「分类」；**没选时**按钮写「分类选择」
    // （themeEmptyLabel，照模拟器定稿）；durations/sorts 给空列表 → 那两个按钮不画。
    filters: SiteFilters(
      themes: phCats,
      languages: [],
      durations: [],
      sorts: [],
      themeLabel: '分类',
      themeEmptyLabel: '分类选择',
    ),
    color: Color(0xFFFF9000),
  );
