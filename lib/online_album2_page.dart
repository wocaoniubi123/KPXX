import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_background.dart';
import 'app_bg.dart';
import 'config.dart';
import 'home_page.dart';
import 'online_album_common.dart';

/// 「在线图集2」列表页（站点：photos18 ✓ **服务端渲染** ✓ 2026-10-05 探站实录 ✓）。
///
/// 两轴**互相独立** ✗（用户上一轮报的 bug ✓ 的根因修法）：
///   `_catId`（分类 ✓ 0 = 全部）与 `_sort`（排序 ✓ 默认 `created` = 最新 ✓）**各自保存** ✓；
///   点排序**不动** tab ✓ 点 tab**不重置**排序 ✓ —— 每次都拿这两个字段**现拼 URL** ✓。
///
/// URL 三形态（2026-10-05 实站实测 ✓）：
///   全部 + 最新 = `/`  ✓   全部 + 其它排序 = `/sort/<sort>`  ✓
///   分类 + 最新 = `/cat/<id>/created`  ✓   分类 + 其它排序 = `/cat/<id>/<sort>`  ✓
///   翻页 = `?page=N&per-page=100`  ✓（**100 条/页** ✓ 实测 ✓）
///
/// ⚠️ 与「在线图集1」**共用的只有** `online_album_common.dart` 那几件 ✓；**取数与解析各写各的** ✗
///   （本站封面在 **`src`** 且是**相对路径** ⇒ 必须补绝对 ✗；图集1 在 **`data-src`** ✓ —— 两回事 ✓）。
class OnlineAlbum2Page extends StatefulWidget {
  const OnlineAlbum2Page({super.key});

  @override
  State<OnlineAlbum2Page> createState() => _OnlineAlbum2PageState();
}

/// 一个主分类（`/cat/<id>` ✓）。
class _Cat {
  final int id;
  final String name;
  const _Cat(this.id, this.name);
}

/// 一个排序项（路径段 `/sort/<key>` ✓）。
class _Sort {
  final String key;
  final String name;
  const _Sort(this.key, this.name);
}

/// 一条卡片（解析结果 ✓）。
class _P18Item {
  final String cover; // 绝对 URL ✓（列表里是相对路径 ⇒ 补站点根 ✓）
  final String detail; // `/v/<5 位 base62>` ✓
  final String title; // 本轮不渲染 ✗（先存着 ✓ 同图集1 口径 ✓）
  final double ratio; // 高/宽 ✓（列表页外层 `padding-top: N%` ✓）

  const _P18Item({
    required this.cover,
    required this.detail,
    required this.title,
    required this.ratio,
  });
}

/// 解析**列表页**（2026-10-05 探站实录 ✓ 逐字）：
///   `<div class="card-columns" id="videos">` … `<div class="card">`
///   `<img src="/images/node/96/965180.avif?1791129814" … loading="lazy">`
///   `<a class="visited" href="/v/ZQygA" …>` + `<a href="/v/ZQygA">Cosplayer御子miko普拉娜萬聖節</a>`
/// ⚠️ 卡片外层 `padding-top: 133.1667%`（= 高/宽 ✓ 每张可能不同 ✓ 实测另一张是 150% ✓）。
List<_P18Item> parseP18List(String html) {
  final out = <_P18Item>[];
  final cards = RegExp(r'<div class="card">').allMatches(html).toList();
  for (var i = 0; i < cards.length; i++) {
    final start = cards[i].end;
    final end = (i + 1 < cards.length) ? cards[i + 1].start : html.length;
    final chunk = html.substring(start, end);
    var cover = RegExp(r'<img[^>]*\ssrc="([^"]+)"').firstMatch(chunk)?.group(1) ?? '';
    if (cover.isEmpty) continue;
    if (!cover.startsWith('http')) cover = '$_p18Host$cover'; // **相对 ⇒ 补绝对** ✗
    final detail = RegExp(r'href="(/v/[A-Za-z0-9]+)"').firstMatch(chunk)?.group(1) ?? '';
    final title = RegExp(r'href="/v/[A-Za-z0-9]+">([^<]*)<').firstMatch(chunk)?.group(1)?.trim() ?? '';
    final pad = RegExp(r'padding-top:\s*([\d.]+)%').firstMatch(chunk)?.group(1);
    final ratio = pad == null ? (4 / 3) : ((double.tryParse(pad) ?? 133.3) / 100);
    if (detail.isEmpty) continue;
    out.add(_P18Item(cover: cover, detail: detail, title: title, ratio: ratio));
  }
  return out;
}

/// 解析**详情页**（2026-10-05 实测 ✓ `/v/ZQygA` ✓ 一页 **24 张** ✓ 无分页 ✓ 绝对 URL ✓ 域名 `img.photos18.com` ✓）：
///   `<div class="my-2 imgHolder"><a href="https://img.photos18.com/…/33287815.avif?0" data-fancybox="gallery">`
///   `<div data-id="33287815" style="position:relative;width:100%;height:0;padding-bottom:133.30078125%">`
/// 返回 `(url, 高/宽比例)` 两列 ✓ —— 详情页用它做 `AspectRatio` ⇒ **满宽不裁** ✓（**不许 cover** ✗）。
({List<String> urls, List<double> ratios}) parseP18Detail(String html) {
  final urls = <String>[];
  final ratios = <double>[];
  final seen = <String>{};
  for (final m in RegExp(r'href="(https://img\.photos18\.com/[^"]+)"\s+data-fancybox="gallery"').allMatches(html)) {
    final u = m.group(1)!;
    if (!seen.add(u)) continue;
    // 紧跟其后（同一条 `imgHolder` 里）的 `padding-bottom: N%` ⇒ 比例 = 100/N ✓（缺省按 4:3 ✓）
    final after = html.substring(m.end, (m.end + 600 < html.length) ? m.end + 600 : html.length);
    final pad = RegExp(r'padding-bottom:\s*([\d.]+)%').firstMatch(after)?.group(1);
    final h = pad == null ? 133.3 : (double.tryParse(pad) ?? 133.3);
    urls.add(u);
    ratios.add(h / 100);
  }
  return (urls: urls, ratios: ratios);
}

const String _p18Host = 'https://www.photos18.com';

class _OnlineAlbum2PageState extends State<OnlineAlbum2Page>
    with SingleTickerProviderStateMixin {
  /// 主分类 tab（**顺序与文案照 sim** ✓ 文案**不显示括号数字** ✗）
  static const List<_Cat> _cats = [
    _Cat(11, '極品美女'),
    _Cat(3, '清涼寫真'),
    _Cat(7, '性感激情'),
    _Cat(1, '歐美寫真'),
    _Cat(5, '美女圖'),
    _Cat(4, '絲襪美腿'),
    _Cat(8, 'COSPLAY'),
    _Cat(9, '亞洲美女'),
    _Cat(6, '素人正妹'),
    _Cat(17, 'Chinese'),
    _Cat(13, 'Aidol'),
    _Cat(12, 'Gravure'),
    _Cat(10, '歐美美女'),
    _Cat(16, 'Thailand'),
    _Cat(15, 'Korea'),
    _Cat(21, '國產美女'),
    _Cat(20, '港台美女'),
    _Cat(14, 'Magazine'),
    _Cat(19, '日韓美女'),
    _Cat(2, '夜店辣妹'),
  ];

  /// 分类标签 chip（5 个 ✓ **形态必须与 tab 不同** ✗ ⇒ 用仓库既有的 `ChoiceChip` ✓ 先例 `detail_page.dart:800-812` ✓）
  static const List<_Sort> _sorts = [
    _Sort('created', '最新'),
    _Sort('hits', '最多'),
    _Sort('views', '最火'),
    _Sort('score', '推薦'),
    _Sort('likes', '最好'),
  ];

  late final TabController _tab =
      TabController(length: _cats.length + 1, vsync: this, initialIndex: 0);

  int _catId = 0; // 0 = 全部 ✓
  String _sort = 'created'; // 默认「最新」✓

  bool _loading = true;
  String? _err;
  List<_P18Item> _items = const <_P18Item>[];
  int _page = 1;
  bool _more = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _tab.addListener(_onTab);
    _loadFirst();
  }

  @override
  void dispose() {
    _tab.removeListener(_onTab);
    _tab.dispose();
    super.dispose();
  }

  /// 换 tab ⇒ **只动 `_catId`** ✓（**不重置 `_sort`** ✗ —— 用户报的 bug 就是这条 ✓）
  void _onTab() {
    if (_tab.indexIsChanging) return; // 只在真正落定后取一次 ✓（避免动画中途重复拉 ✗）
    final idx = _tab.index;
    final id = idx == 0 ? 0 : _cats[idx - 1].id;
    if (id == _catId) return;
    _catId = id;
    _loadFirst();
  }

  /// 换排序 ⇒ **只动 `_sort`** ✓（**不动 tab** ✗）
  void _onSort(String key) {
    if (key == _sort) return;
    _sort = key;
    _loadFirst();
  }

  /// URL 三形态 ✓（每次**现拼** ✓ 两个字段各自生效 ✓）
  String _url(int page) {
    final base = _catId == 0
        ? (_sort == 'created' ? '/' : '/sort/$_sort')
        : '/cat/$_catId/$_sort';
    return '$_p18Host$base?page=$page&per-page=100';
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _err = null;
      _done = false;
    });
    try {
      final r = await Site.httpClient
          .get(Uri.parse(_url(1)), headers: <String, String>{'User-Agent': Site.ua})
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        if (mounted) {
          setState(() {
            _err = '打不开（HTTP ${r.statusCode}）✗';
            _loading = false;
          });
        }
        return;
      }
      final list = parseP18List(utf8.decode(r.bodyBytes, allowMalformed: true));
      if (!mounted) return;
      setState(() {
        _items = list;
        _page = 1;
        _err = list.isEmpty ? '这一页没解析到卡片 ✗（站点结构可能变了）' : null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = '打开失败：$e';
          _loading = false;
        });
      }
    }
  }

  /// 续拉下一页（照 `xhamsterlive.dart:582-583` 的尾部懒加载口径 ✓）
  Future<void> _loadMore() async {
    if (_more || _done || _loading) return;
    _more = true;
    try {
      final r = await Site.httpClient
          .get(Uri.parse(_url(_page + 1)),
              headers: <String, String>{'User-Agent': Site.ua})
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200 || !mounted) return;
      final list = parseP18List(utf8.decode(r.bodyBytes, allowMalformed: true));
      if (!mounted) return;
      setState(() {
        if (list.isEmpty) {
          _done = true; // 这一页空 ⇒ 到头 ✓
        } else {
          _items = [..._items, ...list];
          _page += 1;
        }
      });
    } catch (_) {
      // 续拉失败静默 ✓（下拉刷新仍可救 ✓）
    } finally {
      _more = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          systemOverlayStyle: kStatusOverlay,
          title: const Text('在线图集2'),
          centerTitle: true,
          foregroundColor: kTxt,
          bottom: TabBar(
            // 照 `xhamsterlive.dart:418-432` 那套 ✓（下划线式 ✓ 不是胶囊 ✗）
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 10),
            indicatorColor: const Color(0xFFE8590C),
            tabs: [
              const Tab(text: '全部'),
              for (final c in _cats) Tab(text: c.name),
            ],
          ),
        ),
        body: Column(
          children: [
            // 分类标签 chip（与 tab **形态不同** ✓ 默认选中「最新」✓）
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  for (final s in _sorts)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
                      child: ChoiceChip(
                        label: Text(s.name, style: const TextStyle(fontSize: 12)),
                        selected: s.key == _sort,
                        onSelected: (_) => _onSort(s.key),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadFirst,
                child: _body(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final e = _err;
    if (e != null) return ArtMsg(text: e, onRetry: _loadFirst);
    if (_items.isEmpty) return const ArtMsg(text: '这一页是空的 ✗');
    return RowsGrid(
      cols: 2, // 2 列 ✓
      physics: const AlwaysScrollableScrollPhysics(),
      count: _items.length,
      tail: () {
        // 滚到尾部 ⇒ 顺手续拉 ✓（懒加载 ✓ 不在进页时预拉 ✗）
        _loadMore();
        return _done
            ? const SizedBox(height: 24)
            : const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
      },
      itemBuilder: (context, i) {
        final it = _items[i];
        return ArtCard(
          cover: it.cover,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => P18DetailPage(detailPath: it.detail, title: it.title),
          )),
        );
      },
    );
  }
}

/// 详情页（photos18 ✓）：图片纵排、每张**满宽不裁** ✓（用站点自己给的比例做 `AspectRatio` ✓ + `contain` ✓）。
class P18DetailPage extends StatefulWidget {
  final String detailPath; // `/v/<5 位 base62>` ✓
  final String title;

  const P18DetailPage({super.key, required this.detailPath, required this.title});

  @override
  State<P18DetailPage> createState() => _P18DetailPageState();
}

class _P18DetailPageState extends State<P18DetailPage> {
  bool _loading = true;
  String? _err;
  List<String> _imgs = const <String>[];
  List<double> _ratios = const <double>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Site.httpClient
          .get(Uri.parse('$_p18Host${widget.detailPath}'),
              headers: <String, String>{'User-Agent': Site.ua})
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        if (mounted) {
          setState(() {
            _err = '打不开（HTTP ${r.statusCode}）✗';
            _loading = false;
          });
        }
        return;
      }
      final d = parseP18Detail(utf8.decode(r.bodyBytes, allowMalformed: true));
      if (!mounted) return;
      setState(() {
        _imgs = d.urls;
        _ratios = d.ratios;
        _err = d.urls.isEmpty ? '这一页没解析到图片 ✗（站点结构可能变了）' : null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = '打开失败：$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          systemOverlayStyle: kStatusOverlay,
          title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          centerTitle: true,
          foregroundColor: kTxt,
        ),
        body: RefreshIndicator(onRefresh: _load, child: _body()),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final e = _err;
    if (e != null) return ArtMsg(text: e, onRetry: _load);
    if (_imgs.isEmpty) return const ArtMsg(text: '这一页是空的 ✗');
    return ArtImageList(
      urls: _imgs,
      ratios: _ratios, // 站点给的每张比例 ✓ ⇒ 满宽不裁 ✓
      onTapImage: (i) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ArtPreviewPage(
          urls: _imgs,
          initial: i,
          // ★ 2026-10-05（用户拍板 A2 ✓）：把**裁剪结果**交给「从相册选择」那套存储 ✓
          //   （一次性 ✓ 不进图集 ✗）—— 与图集1 / 设置页那两处**同一个落地点** ✓
          onApplyAsBg: (png) => AppBg.i.useDirectImage(png),
        ),
      )),
    );
  }
}
