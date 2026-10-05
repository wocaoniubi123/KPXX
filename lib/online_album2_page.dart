import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_background.dart';
import 'app_bg.dart';
import 'config.dart';
import 'home_page.dart';
import 'online_album2_avif.dart'; // ★ 本页专用：AVIF 兜底（封面/详情图 ✓ 别的页不碰 ✗）
import 'online_album_common.dart';

/// 「在线图集2」列表页（站点：photos18 ✓ **服务端渲染** ✓ 2026-10-05 探站实录 ✓）。
///
/// ★ 2026-10-05 用户口径：**App 照 sim 抄** ✗。本页对齐的 sim 依据（逐条 ✓）：
///   · 21 条 tab（`全部` + 20 ✓ `sim/index.html:7239-7251` 的 `ALB2_TABS` 逐字 ✓ 繁体文案 ✓）
///   · tab 行高 = **33.8** ✓（sim-dev **实测值** ✓：`padding:9px 2px` + 14px 字 + 下边框 **1.18906px** ✓；
///     整行 ≈ **35.8** ✓）⇒ 逐项 `Tab(height: 33.8)` ✓（`Tab.height` 是 `double?` ⇒ **不取整** ✓）
///     ⚠️ 我先前写的 37 是**估算** ✗ 已作废 ✓；⚠️ `TabBar` 默认 46 ✗；本机无 SDK ⇒ 最终高度**本机测不了** ✗
///   · 5 个 chip（`#alb2Sorts .alb2chip` `sim:244-248` ✓）：`最新/最多/最火/推薦/最好` ✓ 默认 `最新` ✓
///     —— chip 照 sim **自绘** ✓：`padding:5px 12px` ✓ 圆角 15 ✓ `1px rgba(60,60,60,.35)` ✓ 12px 字 ✓
///     未选中透明底 + 自适应字色 ✓ 选中 `#e8590c` 底 + `#fff` 字 ✓（弃用 `ChoiceChip` ✗ 它做不出这套 ✓）
///   · 两轴独立 ✓（`alb2TabSel` 与 `alb2SortSel` 两个独立变量 ✓ `sim:7257` ✓）
///   · URL 三形态 ✓（`alb2PageUrl` `sim:7273-7282` ✓）：`/sort/<sort>` ✓ `/cat/<id>/<sort>` ✓ `/` ✓
///     · 分类+最新 = `/cat/<id>/created` ✓ · 翻页 `?page=N&per-page=100` ✓
///   · 卡片双列/3:4/无标题 ✓（`#alb2Cards` `:232-233` ✓）· 封面在 **`src`** 且**相对 ⇒ 补绝对** ✗
///   · 详情图 = `href` 绝对（`img.photos18.com` ✓ `data-fancybox` ✓）+ 外层 `padding-bottom` 给比例 ✓
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
    // ★ 2026-10-05（复核结论 ✓）：**站内相对这条路本来就修过了** ✓ —— `!startsWith('http') ⇒ 补 `$_p18Host` ✓
    //   （与 sim 口径一致 ✓）。⚠️ 本次只补**一个缺口** ✗：**协议相对 `//…`** ☠ ——
    //   老写法会把它拼成 `https://www.photos18.com//img…` ✗（**错的 URL**）；先判 `//` 再补 `https:` ✓
    //   （与图集1 的 `absArtUrl` 同口径 ✓）。其余一律不动 ✗（判定 / 去重 / 比例 / 文案 ✗）。
    if (cover.startsWith('//')) {
      cover = 'https:$cover';
    } else if (!cover.startsWith('http')) {
      cover = '$_p18Host$cover';
    }
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

/// ★ ③④（✓ 用户拍板）：**预热口径集中在这三行** ✓（不许散落 ☠）—— 依据 = 上一轮核查读数：
///   两处预热都在 `addPostFrameCallback`（**首帧之后立刻跑** ✓）⇒ **正好压在转场那 ~300ms 上** ☠。
const Duration kWarmStart = Duration(milliseconds: 400); // ③ 等页面完全进入再起手 ✓（避开转场 ✓）
const Duration kWarmGap = Duration(milliseconds: 150); // ③ 每张间隔 ✓（分批 ✓）
const int kWarmCount = 12; // ④ 只预热**前几屏**（约 12 张 ✓）；其余靠 `ListView.builder` 懒建 ✓

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

  /// 分类标签 chip（5 个 ✓ **形态必须与 tab 不同** ✗ ⇒ 照 sim **自绘** ✓ 见下面 `_sortChip` ✓
  /// —— ⚠️ 原来用的 `ChoiceChip` 已弃用 ✗（它做不出 sim 那套圆角/描边/选中底色 ✓））
  static const List<_Sort> _sorts = [
    _Sort('created', '最新'),
    _Sort('hits', '最多'),
    _Sort('views', '最火'),
    _Sort('score', '推薦'),
    _Sort('likes', '最好'),
  ];

  late final TabController _tab =
      TabController(length: _cats.length + 1, vsync: this, initialIndex: 0);

  /// 排序（**全局共享** ✓ 与 tab **互相独立** ✗ —— 用户报过的 bug 就是这条 ✓）
  String _sort = 'created'; // 默认「最新」✓

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  /// 排序**胶囊**（**自绘** ✓ —— `ChoiceChip` 做不出 sim 那套形状 ✗；写法照仓库先例 `site_ui.dart:34 tagChip` ✓）。
  /// sim 实测（`sim:246-248` 逐字 ✓）：
  ///   · 未选中：`padding:5px 12px` ✓ `border-radius:15px` ✓ `font-size:12px` ✓
  ///     `border:1px solid rgba(60,60,60,.35)` ✓ `color:#2c2c2c` ✓（浅色图）· 深色图由 `.darkbg .body *` 翻白 ✓
  ///   · 选中：`background:#e8590c; color:#fff` ✓（sim 的 `.on` 只这两条 ✓）
  ///   ⇒ 文字色 = **自适应** `kTxt`（深→白 / 浅→`0xFF1B1B1F` ✓ `app_background.dart:53` ✓）；
  ///     未选中底色 `transparent` ✓（sim 原文 ✓）；描边 = `0x593C3C3C`（0x59 = 89 ⇒ 89/255 = **.349** ✓ = sim 的 .35 ✓）
  Widget _sortChip(_Sort s) {
    final bool on = s.key == _sort;
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () => _onSort(s.key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFE8590C) : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0x593C3C3C)),
        ),
        child: Text(s.name,
            style: TextStyle(fontSize: 12, color: on ? Colors.white : kTxt)),
      ),
    );
  }

  /// 换排序 ⇒ **只动 `_sort`** ✓（**不动 tab** ✗）⇒ `setState` ⇒ 各子页按新排序重拉 ✓
  void _onSort(String key) {
    if (key == _sort) return;
    setState(() => _sort = key);
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
            // ★ 照 sim 抄（`#alb2Tabs .alb2tab` `sim:234-237` ✓）：下划线式 ✓ 选中橙 + w600 ✓
            //   未选中自适应 ✓（见图集1 同款注释 ✓）
            //   ★ 2026-10-05（照 sim **实测值** ✓ 不是估算 ✗）：**单个 tab = 33.8** —— sim 的 tab =
            //     `padding:9px 2px` + 14px 字 + 下边框 **1.18906** ⇒ 单 tab **33.8** ✓（整行 ≈ 35.8 ✓ `sim:235` ✓）；
            //     `TabBar` 默认 **46** ✗
            //     ⇒ 逐项 `Tab(height: 33.8)` ✓（**不是估算的 37** ✗ —— sim-dev 实测值 ✓；`Tab.height`
            //       是 `double?` ⇒ 不取整 ✓；Flutter 3.13+ 的 `Tab.height` ✓；CI 钉 3.27.4 ✓）
            //     ⚠️ 本机**无 Flutter SDK** ⇒ 最终渲染高度**无法在本机实测** ✗
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 10),
            indicatorColor: const Color(0xFFE8590C),
            indicatorWeight: 2,
            labelColor: AppBg.i.isDark
                ? const Color(0xFFFFB07A)
                : const Color(0xFFE8590C),
            unselectedLabelColor: kTxt,
            tabs: [
              // ★ 2026-10-05（照 sim **实测值** ✓）：单个 tab = **33.8px**（sim-dev 实测：`padding:9px 2px`
              //   + 字号 14px + 下边框 **1.18906px** ✓）；`Tab.height` 是 `double?` ⇒ **写 33.8、不取整** ✓
              //   ⚠️ 先前的 37 是估算 ✗ 已改；⚠️ 本机无 SDK ⇒ 渲染高度测不了 ✗
              const Tab(height: 33.8, text: '全部'),
              for (final c in _cats) Tab(height: 33.8, text: c.name),
            ],
          ),
        ),
        body: Column(
          children: [
            // 分类标签 chip（与 tab **形态不同** ✓ 默认选中「最新」✓）
            // ★ 2026-10-05（**照 sim 1:1** ✗）：容器 `gap:8px` + `padding:8px 2px 0` ✓（`sim:244` 逐字 ✓）
            //   ⚠️ `ChoiceChip` **做不出 sim 那套形状** ✗ ⇒ 照仓库先例 `site_ui.dart:34 tagChip` **自绘** ✓
            //   ⚠️ 不写死行高 ✗（sim 的行高由内容撑 ✓）⇒ 用 `SingleChildScrollView + Row`（不是 `ListView` ✓）
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(top: 8, left: 2, right: 2), // = sim `padding:8px 2px 0` ✓
              child: Row(
                children: [
                  for (var i = 0; i < _sorts.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8), // = sim 容器 `gap:8px` ✓
                    _sortChip(_sorts[i]),
                  ],
                ],
              ),
            ),
            // ★ 内容区左右滑切 tab（用户批准 ✓）：**框架自带** `TabBarView` ✗（不自定阈值 ✓
            //   —— ⚠️ sim 里没有这个手势 ✓ 没有阈值可抄 ⇒ 取框架默认 ⇒ 已如实报 ✓）
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _CatFeed2(key: const ValueKey<String>('/'), catPath: '/', sort: _sort),
                  for (final c in _cats)
                    _CatFeed2(
                      key: ValueKey<String>('/cat/${c.id}'),
                      catPath: '/cat/${c.id}',
                      sort: _sort,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个分类的列表（一个 tab 一个 ✓ 自带三态/下拉刷新/续拉 ✓ 与排序联动 ✓）。
class _CatFeed2 extends StatefulWidget {
  /// `'/'` = 全部 ✓；其余 = `/cat/<id>` ✓
  final String catPath;
  final String sort;

  const _CatFeed2({super.key, required this.catPath, required this.sort});

  @override
  State<_CatFeed2> createState() => _CatFeed2State();
}

class _CatFeed2State extends State<_CatFeed2> {
  bool _loading = true;
  String? _err;
  List<_P18Item> _items = const <_P18Item>[];
  int _page = 1;
  bool _more = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _loadFirst();
  }

  @override
  void didUpdateWidget(covariant _CatFeed2 old) {
    super.didUpdateWidget(old);
    // 换了排序 ⇒ 按新排序重拉第 1 页 ✓（**tab 不动** ✗ —— 用户报过的 bug 就是这条 ✓）
    if (old.sort != widget.sort) _loadFirst();
  }

  /// URL 三形态 ✓（照 sim `alb2PageUrl` `:7273-7282` ✓；每次**现拼** ✓ 分类与排序各自生效 ✓）
  String _url(int page) {
    final base = widget.catPath == '/'
        ? (widget.sort == 'created' ? '/' : '/sort/${widget.sort}')
        : '${widget.catPath}/${widget.sort}';
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
    return RefreshIndicator(onRefresh: _loadFirst, child: _body());
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final e = _err;
    if (e != null) return ArtMsg(text: e, onRetry: _loadFirst);
    if (_items.isEmpty) return const ArtMsg(text: '这一页是空的 ✗');
    return RowsGrid(
      cols: 2, // 2 列 ✓（sim `#alb2Cards` 也是 `repeat(2, 1fr)` ✓）
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
        // ★ 2026-10-05（B 方案 ✓ 用户拍板）：封面**全是 `.avif`** ⇒ 用本页专用的 `AvifImage` ✓
        //   （结构照 `ArtCard` 同款：卡片 + `InkWell` + `AspectRatio(3/4)` ✓ —— **不改公共件** ✗）
        return Card(
          clipBehavior: Clip.antiAlias,
          color: Colors.white,
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => P18DetailPage(detailPath: it.detail, title: it.title),
            )),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: AvifImage(url: it.cover, memWidth: 480),
            ),
          ),
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
    _load().then((_) {
      // ★ 2026-10-05（用户要求 ✓）：**图一到手就开始全量解码** ✓（`_warmAll` 里逐张 await ✓ 串行 ✓）
      //   放在 `_load` 之后 ⇒ 不挡首屏 ✓；`addPostFrameCallback` 保证首帧先画 ✓ 静默 ✓ 无进度 ✓
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // ★ ③（✓ 用户拍板）：**帧后再等 400ms** 才起手 ✓ —— 原来"首帧后立刻跑"正好压在转场那 ~300ms 上 ☠
        await Future<void>.delayed(kWarmStart);
        if (!mounted) return; // 这 400ms 里已退出 ⇒ 不再预热 ✓
        _warmAll();
      });
    });
  }

  /// ★ ②（✓ 用户拍板）：**离页把"这一本"从解码字节表里清掉** ✗ —— 依据（读数 ✓）：用户报的是
  ///   "**48 张那本反复进出**就崩" ✓ = 典型**累积型** ⇒ 只靠 ① 的 LRU 也能封顶 ✓，但"离页清本"能让
  ///   **反复进出同一本完全不涨** ✓（LRU 只保证 40MB 封顶 ✓ 不保证"退页就掉" ✗）⇒ 两个一起上 ✓。
  ///   ⚠️ **只 forget 本页的 `_imgs`** ✓ —— 别的页 / 别的本 / 别的站点**一律不动** ☠。
  @override
  void dispose() {
    AvifBytes.forget(_imgs);
    super.dispose();
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

  /// ★ 2026-10-05（用户要求 ✓）：**进详情就全量加载/解码** ✗（含 AVIF ✓）——
  ///   串行 ✓（不并发轰炸 ✓）· `addPostFrameCallback` 起手 ⇒ **不挡首屏** ✓ · **静默 ✓ 无进度** ✗
  ///   ⇒ 解好的都进 `AvifBytes` **同一个缓存** ✓（同一张只解一次 ✓）⇒ 预览打开时**必然命中** ✓ **绝不给空白** ✗
  ///   ⚠️ 失败静默 ✓（`fetch` 自己重试 3 次 ✓）；解不到的图由 `AvifImage` 显示**占位** ✓
  Future<void> _warmAll() async {
    for (final u in _imgs.take(kWarmCount)) { // ★ ④ 只预热前 12 张 ✓（其余靠懒建 ✓）
      if (!mounted) return; // 页面已退出 ⇒ 停 ✓
      // ★ ③（✓ 用户拍板）：分批 ⇒ **每张间隔 150ms** ✓（原来一张接一张 ✗ 与转场/滚动抢资源 ☠）
        await Future<void>.delayed(kWarmGap);
        await AvifBytes.fetch(u);
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
    // ★ 2026-10-05（B 方案 ✓）：详情图也全是 `.avif` ⇒ 用本页专用件 ✓（**不改 `ArtImageList`** ✗）
    //   口径与共用件一致：站点给了 `padding-bottom` 比例 ⇒ `AspectRatio(1 / 高宽比)` + `contain` ✓ 满宽不裁 ✓。
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _imgs.length,
      itemBuilder: (context, i) {
        // 该图的"高/宽"（站点原文 `padding-bottom: N%` ✓）；缺了按 4:3 兜底 ✓
        final h = i < _ratios.length ? _ratios[i] : 4 / 3;
        return GestureDetector(
          onTap: () => showArtPreviewOverlay(
            context,
            urls: _imgs,
            initial: i,
            onApplyAsBg: (png) => AppBg.i.useDirectImage(png),
            // ★ 2026-10-05（用户点破 ✓）：预览用**本页已解好的字节** ✓ ⇒ 零额外网络、零额外解码 ✓；
            //   未命中（预览里还没被详情页解过的那些）⇒ 回调给 `null` ⇒ 预览**回落** `FetchedImage` ✓
            bytesFor: AvifBytes.cached,
            // ★ ⑤（✓ 用户拍板）：预览打开 ⇒ **相邻 ±2 串行预取** ✓（已就绪的跳过 ✓ 见 `AvifBytes.prefetch` ✓）
            //   ⚠️ **图集1 侧不传** ⇒ 默认 null ⇒ 行为一字不变 ✓（依据 = 它本来就全靠 `FetchedImage` 按需取 ✓）
            prefetch: AvifBytes.prefetch,
          ),
          child: AspectRatio(
            aspectRatio: 1 / h, // 高/宽 ⇒ 宽/高 ✓（AspectRatio 要的是宽/高 ✓）
            child: AvifImage(url: _imgs[i], fit: BoxFit.contain, memWidth: 1600),
          ),
        );
      },
    );
  }
}
