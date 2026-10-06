import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_background.dart';
import 'app_bg.dart';
import 'config.dart';
import 'home_page.dart';
import 'online_album_common.dart';

/// 「在线图集1」列表页（站点：xofulitu / MacCMS ✓ **服务端渲染** ✓ 2026-10-05 探站实录 ✓）。
///
/// ★ 2026-10-05 用户口径：**App 照 sim 抄** ✗（sim 的实测值 = 图纸 ✓）。本页对齐的 sim 依据：
///   · 分类 tab = **19 条**（`全部` + 18 个分类 ✓ `sim/index.html:6640-6660` 的 `ALB_TAGS` 逐字 ✓
///     —— ⚠️「19」是 sim 的**机器计数** ✓（`name:` 出现 19 次 ✓）；文案**不带括号数字** ✗；
///     `韩国` 照 sim **故意**指 `/arttype/5034/` ✓（站点导航给的 `/t/5034/` 探过是真空 ✓ `:6652` ✓）。
///   · tab 样式（`#albTags .albtab` `sim:227-230` ✓）：`font-size:14px` ✓ · 选中 `#e8590c` + `w600` + 下划线 `2px` ✓
///     · 未选中 `#111`（深色图由 `.darkbg .body *` 通配翻白 ✓）⇒ App 用 `kTxt`（深→白 / 浅→`0xFF1B1B1F` ✓）
///     · 容器 `gap:16px` + 项 `padding:0 2px` ⇒ 相邻文字距 = **20** ✓ = App `labelPadding: 10`×2 ✓（可核 ✓）
///   · 卡片双列/3:4/无标题 ✓（`#albCards` `:218-219` ✓）· 每页 **24** 条 ✓（`:6572` ✓）
///   ★ 2026-10-05（照 sim **实测值** ✓ 不是估算 ✗）：**单个 tab = 33.8px**
///     （sim-dev 实测：`padding:9px 2px` + 字号 14px + 下边框 **1.18906px** ✓；整行 ≈ **35.8** ✓）
///     ⇒ 逐项 `Tab(height: 33.8)` ✓（`Tab.height` 是 `double?` ⇒ **不取整** ✓；Flutter 3.13+ ✓ CI 钉 3.27.4 ✓）
///     ⚠️ 我先前写的 37 是**估算** ✗ 已作废 ✓；⚠️ 本机**无 Flutter SDK** ⇒ **渲染高度本机测不了** ✗。
class OnlineAlbumPage extends StatefulWidget {
  const OnlineAlbumPage({super.key});

  @override
  State<OnlineAlbumPage> createState() => _OnlineAlbumPageState();
}

/// 站点根（详情页也要用 ✓ —— 列表项给的 `detail` 是相对路径 `/art/pic/id/N/` ✓）。
const String kOnlineAlbumHost = 'https://zaeg-kiga-rpuv.xofulitu-108.com';

/// ★ 2026-10-05（用户报"有的分类整屏不显示" ✓ 真因）：把站点给的图片地址**绝对化** ✗ ——
///   逐类探测实录（19 类 ✓ 只读头 ✓ 已跑）证实**三种形态混着出现**：
///     · `https://img.img12345.com/comics/...` ⇒ 已经绝对 ✓（`全部 /arttype/2000/` 24/24 都这种 ✓）
///     · `/upload/art/20231019/xxx.jpg` ⇒ **站内相对** ☠（`/arttype/2003/` **24/24 全是** ✗；
///       `2001` 23/24 · `2002` 14/24 · `2004` 3/14 ✓ —— **占比逐类不同** ✓ 所以"只测一类"当年漏了 ✗）
///     · `//imagedatas.com/upload/...` ⇒ **协议相对** ☠（`2001/2002/2004` 里混着 ✓）
///   ⚠️ **不绝对化会怎样**：`FetchedImage` 拿到没有 scheme 的 URI ⇒ `Uri.parse` 的 host 为空 ⇒
///   请求发不出去 ✗、Referer 还会退到写死那条 ✗ ⇒ **那一类整屏不出封面** ☠（正是用户看到的 ✓）。
///   ⚠️ 只补前缀 ✗：路径本身一律不动 ✓（不编解码 / 不去重 / 不改大小写 ✗）。
String absArtUrl(String u) {
  final s = u.trim();
  if (s.isEmpty) return s;
  if (s.startsWith('//')) return 'https:$s'; // 协议相对 ⇒ 补 https: ✓
  if (s.startsWith('http://') || s.startsWith('https://')) return s; // 已绝对 ⇒ 原样 ✓
  if (s.startsWith('/')) return '$kOnlineAlbumHost$s'; // 站内相对 ⇒ 拼站点根 ✓
  return '$kOnlineAlbumHost/$s'; // 兜底（不带前导斜杠的少见形态 ✓）
}

/// 一个主分类（照 sim 的 `ALB_TAGS` ✓ 逐条 ✓）。
class AlbCat {
  final String path;
  final String name;
  const AlbCat(this.path, this.name);
}

/// 19 条分类 tab（**顺序/文案照 sim** ✓ `sim/index.html:6640-6660` 逐字 ✓；不带括号数字 ✗）。
const List<AlbCat> kAlbCats = [
  AlbCat('/arttype/2000/', '全部'),
  AlbCat('/arttype/2001/', '热姐'),
  AlbCat('/arttype/2002/', '罗莉塔'),
  AlbCat('/arttype/2003/', '性感的'),
  AlbCat('/arttype/2004/', '杂志'),
  AlbCat('/arttype/5001/', '角色扮演'),
  AlbCat('/arttype/5029/', '美足'),
  AlbCat('/arttype/5030/', '唯美写真'),
  AlbCat('/arttype/5031/', '模特儿'),
  AlbCat('/arttype/5032/', '日本'),
  AlbCat('/arttype/5033/', '东盟'),
  // ⚠️ 唯一一条偏离站点导航：`韩国` ⇒ `/arttype/5034/` ✓（照 sim 的有意修订 ✓ `:6652` ✓）
  AlbCat('/arttype/5034/', '韩国'),
  AlbCat('/arttype/5035/', '柚木'),
  AlbCat('/arttype/5036/', '少女映画'),
  AlbCat('/arttype/5037/', '沫沫真爱'),
  AlbCat('/arttype/5038/', 'Fushii_海堂'),
  AlbCat('/arttype/5039/', '年年'),
  AlbCat('/arttype/5041/', '網路收集系列'),
  AlbCat('/arttype/5042/', '福利姬'),
];

/// 一条图集卡片（解析结果 ✓）。
class ArtItem {
  /// 封面真图 —— 站点原文里在 **`data-src`** ✓（`src` 是占位 gif ✗ `loading_3_green_dot.gif` ✓）
  final String cover;

  /// `album-name` ✓ —— ⚠️ **留着但不渲染（用户 2026-10-05）✓ 别当没删干净再删一遍** ✗
  ///   （卡片已改成"只由封面撑" ✓；详情页顶部标题要用它 ✓）
  final String title;

  /// `/art/pic/id/2632/` ✓（详情页自己拼站点根 ✓）
  final String detail;

  const ArtItem({required this.cover, required this.title, required this.detail});
}

/// 解析列表 HTML（**只认原生 HTML ✓ 该站是服务端渲染 ✓ 不跑 JS ✓**）。
///
/// 依据（2026-10-05 探站实录 ✓ 逐字）：
///   `<a href="/art/pic/id/2632/" class="album-item">`
///   `<img src="/MDassets/img/loading_3_green_dot.gif" data-src="https://img.img12345.com/comics/images01710/001.jpg">`
///   `<div class="album-name">Shiro x Kuro</div>`
/// ⚠️ 2026-10-05（逐类实测 ✓）：`data-src` 拿到的可能是**站内相对 / 协议相对** ✗ ⇒ 一律过 [absArtUrl] ✓。
List<ArtItem> parseArtList(String html) {
  final re = RegExp(r'<a href="(/art/pic/id/\d+/)" class="album-item">');
  final ms = re.allMatches(html).toList();
  final out = <ArtItem>[];
  for (var i = 0; i < ms.length; i++) {
    // 每个条目的正文 = 本条 `<a …>` 之后 → 下一条 `<a …>` 之前 ✓（不跨条抓字段 ✗）
    final start = ms[i].end;
    final end = (i + 1 < ms.length) ? ms[i + 1].start : html.length;
    final chunk = html.substring(start, end);
    var cover = absArtUrl(RegExp(r'data-src="([^"]+)"').firstMatch(chunk)?.group(1) ?? '');
    if (cover.isEmpty) {
      // 退路：没 `data-src` 才用 `src` ✓ —— 但要**跳过占位 gif** ✗（原文里 `src` 就是它 ✓）
      final s = RegExp(r'<img[^>]*\ssrc="([^"]+)"').firstMatch(chunk)?.group(1);
      if (s != null && !s.contains('loading_3_green_dot')) cover = absArtUrl(s);
    }
    final title =
        RegExp(r'class="album-name">([^<]*)<').firstMatch(chunk)?.group(1)?.trim();
    if (cover.isEmpty || title == null || title.isEmpty) continue;
    out.add(ArtItem(cover: cover, title: title, detail: ms[i].group(1)!));
  }
  return out;
}

/// 解析**详情页**的图片（2026-10-05 实测 ✓ `/art/pic/id/2632/` **一页就含全部原图** ✓ 无分页 ✓）。
/// 依据（逐字 ✓）：`<div class="picture-item"><a href="/article/2632/page/1/">`
///   `<img src="/MDassets/img/loading_3_green_dot.gif" data-src="https://img.img12345.com/comics/images01710/001.jpg">`
/// ⚠️ 该页其余 `<img>`（站标 / 广告位）走的都是 **`src`** ✓ ⇒ **只收 `data-src`** ✓ 不会误收广告 ✓。
/// ⚠️ 实测扩展名**两种混用**（`001.jpg` 与 `013.jpeg`）⇒ 不许按扩展名过滤 ✗。
List<String> parseArtImages(String html) {
  final out = <String>[];
  final seen = <String>{};
  for (final m in RegExp(r'data-src="([^"]+)"').allMatches(html)) {
    final u = m.group(1)!;
    // 占位图一律跳过（详情页的 `src` 是占位 gif ✓；万一 data-src 也被写成它 ⇒ 挡住 ✗）
    if (u.contains('loading_3_green_dot')) continue;
    final abs = absArtUrl(u); // ★ 2026-10-05：详情页同样混着"相对 / 协议相对" ✗ ⇒ 一并绝对化 ✓
    if (seen.add(abs)) out.add(abs);
  }
  return out;
}

/// 详情页：**图片纵向排列、每张占满宽度、原图直出** ✓（用户要求 ✓ **不许裁剪** ✗）。
/// 列表本体在共用件 `ArtImageList` 里 ✓（`ratios == null` ⇒ 按图片自身比例撑开 ✓ 满宽不裁 ✓）。
class ArtDetailPage extends StatefulWidget {
  /// 列表项给的详情路径（形如 `/art/pic/id/2632/` ✓）
  final String detailPath;
  final String title;

  const ArtDetailPage({super.key, required this.detailPath, required this.title});

  @override
  State<ArtDetailPage> createState() => _ArtDetailPageState();
}

class _ArtDetailPageState extends State<ArtDetailPage> {
  bool _loading = true;
  String? _err;
  List<String> _imgs = const <String>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Site.httpClient
          .get(Uri.parse('$kOnlineAlbumHost${widget.detailPath}'),
              headers: <String, String>{'User-Agent': Site.ua})
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) {
        if (mounted) {
          setState(() {
            _err = '打不开（HTTP ${r.statusCode}）✗';
            _loading = false;
          });
        }
        return;
      }
      final list = parseArtImages(utf8.decode(r.bodyBytes, allowMalformed: true));
      if (!mounted) return;
      setState(() {
        _imgs = list;
        _err = list.isEmpty ? '这一页没解析到图片 ✗（站点结构可能变了）' : null;
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
      // ★ 2026-10-05 用户拍板（呈现方式 ③）：点图 ⇒ **浮层预览** ✓（不跳页 ✓ 点空白关 ✓
      //   系统返回键/侧滑只关浮层 ✗）—— 整页版 `ArtPreviewPage` 保留但**已无调用点** ✓
      //   （见 `online_album_common.dart` 里 `ArtPreviewPage` 那段"现状：调用点 = 0"的说明 ✓）
      onTapImage: (i) => showArtPreviewOverlay(
        context,
        urls: _imgs,
        initial: i,
        // ★ 同款挂点 ✓（裁剪结果 ⇒ 交给「从相册选择」那套存储 ✓ 一次性 ✓ 不进图集 ✗）
        onApplyAsBg: (png) => AppBg.i.useDirectImage(png),
      ),
    );
  }
}

class _OnlineAlbumPageState extends State<OnlineAlbumPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab =
      TabController(length: kAlbCats.length, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 整页跟着背景明暗重建（tab 文字色读 kTxt ✓ 同 bg_album_page ✓）
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.transparent, // 外层 PageBg 已铺背景图，别挡掉
        appBar: AppBar(
          systemOverlayStyle: kStatusOverlay,
          title: const Text('在线图集1'),
          centerTitle: true,
          foregroundColor: kTxt,
          bottom: TabBar(
            // ★ 照 sim 抄（`#albTags .albtab` `sim/index.html:227-230` ✓）：
            //   下划线式 ✓（不是胶囊 ✗）· 选中 `#e8590c` + `w600` ✓ · 下划线 2px ✓
            //   未选中：sim 是 `#111`，深色图由 `.darkbg .body *` 通配**翻白** ✓
            //   ⇒ App 对应 = `kTxt`（深→白 / 浅→`0xFF1B1B1F` ✓ 见 app_background.dart:53 ✓）
            //   ★ 2026-10-05（照 sim **实测值** ✓ 不是估算 ✗）：**单个 tab = 33.8** —— sim 的 tab =
            //     `padding:9px 2px` + 14px 字 + 下边框 **1.18906** ⇒ 单 tab **33.8** ✓（整行 ≈ 35.8 ✓ `:228` ✓）；
            //     `TabBar` 默认 **46** ✗
            //     ⇒ 逐项 `Tab(height: 33.8)` ✓（**不是估算的 37** ✗ —— sim-dev 实测值 ✓；`Tab.height`
            //       是 `double?` ⇒ 不取整 ✓；Flutter 3.13+ 的 `Tab.height` 参数 ✓；CI 钉 3.27.4 ✓）
            //     ⚠️ 本机**无 Flutter SDK** ⇒ 最终渲染高度**无法在本机实测** ✗（下面 tabs 里已加 ✓）
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 10), // = sim 的 gap16 + padding2×2 ✓
            indicatorColor: const Color(0xFFE8590C),
            indicatorWeight: 2, // = sim 的 border-bottom 2px ✓
            labelColor: AppBg.i.isDark
                ? const Color(0xFFFFB07A)
                : const Color(0xFFE8590C),
            unselectedLabelColor: kTxt,
            tabs: [
              // ★ 2026-10-05（照 sim **实测值** ✓ 不是估算 ✗）：单个 tab = **33.8px**
              //   （sim-dev 实测：`padding:9px 2px` + 字号 14px + 下边框 **1.18906px** ✓；整行 ≈ 35.8 ✓）
              //   ⇒ 直接写 **33.8** ✓（`Tab.height` 是 `double?` ⇒ **不取整** ✓）
              //   ⚠️ 之前写的 37 是**估算值** ✗ ⇒ 已按实测改 ✓；⚠️ 本机无 Flutter SDK ⇒ 渲染后高度**本机测不了** ✗
              for (final c in kAlbCats) Tab(height: 33.8, text: c.name),
            ],
          ),
        ),
        // ★ 内容区左右滑切 tab（用户批准 ✓）：用**框架自带的** `TabBarView` ✗（不自定阈值 ✓
        //   —— ⚠️ sim 里**没有**这个手势 ✓ 没有阈值可抄 ⇒ 只能取框架默认 ⇒ 已如实报 ✓）
        body: TabBarView(
          controller: _tab,
          children: [
            for (final c in kAlbCats)
              _CatFeed(key: ValueKey<String>(c.path), catPath: c.path),
          ],
        ),
      ),
    );
  }
}

/// 单个分类的列表（一个 tab 一个 ✓ 各自管自己的三态/刷新 ✓ 互不串台 ✓）。
class _CatFeed extends StatefulWidget {
  final String catPath;

  const _CatFeed({super.key, required this.catPath});

  @override
  State<_CatFeed> createState() => _CatFeedState();
}

class _CatFeedState extends State<_CatFeed> {
  bool _loading = true;
  String? _err;
  List<ArtItem> _items = const <ArtItem>[];

  /// ★ 2026-10-05（用户要求 ✓）：**自动翻页（无限滚动）** ✗ —— 原来只加载第 1 页 ☠（tab 重做时丢了 ✓）。
  ///   ⚠️ 口径**照图集2**（`online_album2_page.dart:282-402` ✓ 现成那套 ✓ **不自造** ✗）：
  ///   `_page` = 已加载到第几页 ✓ · `_more` = 正在续拉 ✓ · `_done` = 到底 ✓。
  int _page = 1;
  bool _more = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 站点翻页形态 ✓（原文实测：`<a href="/arttype/2000-2/" class="paging-item--next">下一页</a>` ✓ 共 53 页 ✓）：
  ///   **第 1 页 = `catPath` 本身** ✓（不拼 `-1` ✗）；之后 = `/arttype/<id>-<page>/` ✓。
  String _url(int page) {
    if (page <= 1) return '$kOnlineAlbumHost${widget.catPath}';
    final m = RegExp(r'/arttype/(\d+)/').firstMatch(widget.catPath);
    if (m == null) return '$kOnlineAlbumHost${widget.catPath}';
    return '$kOnlineAlbumHost/arttype/${m.group(1)}-$page/';
  }

  Future<void> _load() async {
    // ★ 照图集2 ✓：刷新期间内容换成转圈 ⇒ **尾部不会被构造** ⇒ 续拉与"下拉刷新"**互不打架** ✓
    setState(() {
      _loading = true;
      _err = null;
      _done = false;
    });
    try {
      final r = await Site.httpClient
          .get(Uri.parse('$kOnlineAlbumHost${widget.catPath}'),
              headers: <String, String>{'User-Agent': Site.ua})
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) {
        if (mounted) {
          setState(() {
            _err = '打不开（HTTP ${r.statusCode}）✗';
            _loading = false;
          });
        }
        return;
      }
      // 站点的 `<meta charset="utf-8">` 在正文里 ✓，响应头不一定带 ⇒ **显式按 UTF-8 解** ✗（否则标题乱码 ✓）
      final list = parseArtList(utf8.decode(r.bodyBytes, allowMalformed: true));
      // ★ 2026-10-05【常驻诊断·解析层】只拼字符串 ✓ 不碰解析/去重/分页/缓存 ☠（开关关着零开销 ✓ 走同名 debugPrint ✓）
      //   ⚠️ 上限 400 字：首 3 条 + 末 1 条，标题截 40 / 详情截 80 ✓ 超长整体截断加 `…` ✓
      //   ★ 2026-10-05 补：分类路径真名 = **`widget.catPath`** ✓（出处：本文件 `:310 final String catPath;` ✓ 传值处 `:300 _CatFeed(key: ValueKey<String>(c.path), catPath: c.path)` ✓）
      String diag() {
        String cut(String s, int n) => s.length <= n ? s : s.substring(0, n);
        String one(ArtItem it) =>
            '${cut(it.title, 40)} | ${Uri.tryParse(it.cover)?.host ?? '?'} | ${cut(it.detail, 80)}';
        final b = StringBuffer('[LIST] cat=${widget.catPath} n=${list.length} ');
        for (var i = 0; i < list.length && i < 3; i++) {
          b.write(one(list[i]));
          b.write(' || ');
        }
        if (list.length > 3) b.write(one(list.last));
        final s = b.toString();
        return s.length <= 400 ? s : '${s.substring(0, 400)}…';
      }
      debugPrint(diag());
      if (!mounted) return;
      setState(() {
        _items = list;
        _page = 1; // 刷回第 1 页 ✓（续拉的凭据一起复位 ✓）
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

  /// 续拉下一页 ✓（照图集2 `_loadMore` ✓ **逐条同款** ✗）：
  ///   · 守卫 `_more || _done || _loading` ✓ ⇒ 与刷新 / 自己**不并发** ✓
  ///   · **某页解析为空** ⇒ `_done = true` ✓（= "到底"判据 ✓）。⚠️ **不按"不足 24 条"判** ✗ ——
  ///     我们的解析器会**丢条目** ✓（实测 `/arttype/2004/` 首页只解析出 **15** 条 ✓ 但站点并没到底 ✗）
  ///     ⇒ 用"条数不足"当到底会**提前截断** ☠。
  ///   · 追加时按 `detail` **去重** ✓：万一越界页返回的是"最后一页的重复" ✗ ⇒ 不会重复铺一屏 ✓；
  ///     且"这一页全是旧的"也当到底 ✓ —— 即口径里的"**不足则停**" ✓（用净增量判 ✓ 比看条数稳 ✗）。
  ///   · 失败**静默** ✓（下拉刷新仍可救 ✓ 与图集2 同款 ✓）
  Future<void> _loadMore() async {
    if (_more || _done || _loading) return;
    _more = true;
    try {
      final r = await Site.httpClient
          .get(Uri.parse(_url(_page + 1)),
              headers: <String, String>{'User-Agent': Site.ua})
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200 || !mounted) return;
      final list = parseArtList(utf8.decode(r.bodyBytes, allowMalformed: true));
      if (!mounted) return;
      setState(() {
        final have = _items.map((a) => a.detail).toSet();
        final fresh = list.where((a) => have.add(a.detail)).toList();
        if (fresh.isEmpty) {
          _done = true; // 空页 / 全是旧的 ⇒ 到头 ✓
        } else {
          _items = [..._items, ...fresh];
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
    return RefreshIndicator(onRefresh: _load, child: _body());
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final e = _err;
    if (e != null) return ArtMsg(text: e, onRetry: _load);
    if (_items.isEmpty) return const ArtMsg(text: '这一页是空的 ✗');
    return RowsGrid(
      cols: 2, // 用户指定：2 列 ✓（sim `#albCards` 也是 `repeat(2, 1fr)` ✓）
      physics: const AlwaysScrollableScrollPhysics(),
      count: _items.length,
      // ★ 2026-10-05（用户要求 ✓）：**滚到尾部 ⇒ 顺手续拉下一页** ✗（懒加载 ✓ 不在进页时预拉 ✗）——
      //   口径照图集2（`online_album2_page.dart:389-403` ✓）；到底 ⇒ 留一小段白 ✓ **不再空转圈** ✓。
      tail: () {
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
            // ★ 2026-10-05【⑥ 页面起名】：只加 `settings:` 一个参数 ✓（不碰 `builder`/`PageBg` ☠）
            settings: const RouteSettings(name: '图集1 详情'),
            // ★ 2026-10-05（用户报"转场时两页叠影"☠ 根因 `ac1d1b2`：全 App 底色透明 ⇒ 新页盖不住旧页）：
            //   照 `365d6a4` 的原样写法包一层 `PageBg` ✓（在页面**最底层**铺不透明背景图 ⇒ 转场期间"实心" ✓
            //   走 `ImageCache`/同一个 `ImageProvider` ⇒ **不重复解码** ✓）；⚠️ 只加这一层 ✗ 别的什么都不碰 ✓
            builder: (_) => PageBg(child: ArtDetailPage(detailPath: it.detail, title: it.title)),
          )),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------------------------
// 【已落档 ✓ 本轮已实现 ✓】「在线图集1」的分类（2026-10-05 探站实录 ✓ 逐字来自首页导航 ✓）：
//   全部 /arttype/2000/ ✓ 热姐 /arttype/2001/ ✓ 罗莉塔 /arttype/2002/ ✓ 性感的 /arttype/2003/ ✓
//   杂志 /arttype/2004/ ✓ 角色扮演 /arttype/5001/ ✓ 美足 /arttype/5029/ ✓ 唯美写真 /arttype/5030/ ✓
//   模特儿 /arttype/5031/ ✓ 日本 /arttype/5032/ ✓ 东盟 /arttype/5033/ ✓
//   ⚠️ 韩国 = **/arttype/5034/** ✓（站点导航给的是 `/t/5034/` ✗ 探过是真空 ⇒ 照 sim 的有意修订 ✓）
//   柚木 /arttype/5035/ ✓ 少女映画 /arttype/5036/ ✓ 沫沫真爱 /arttype/5037/ ✓ Fushii_海堂 /arttype/5038/ ✓
//   年年 /arttype/5039/ ✓ 網路收集系列 /arttype/5041/ ✓ 福利姬 /arttype/5042/ ✓
//   ⚠️ id 从 5039 直接跳到 5041 ✓（**没有 5040** ✓）
// 翻页形式 ✓：`/arttype/<id>-<page>/`（原文 `<a href="/arttype/2000-2/" class="paging-item--next">下一页</a>` ✓ 共 **53** 页 ✓）—— 本轮不做 ✗
// ---------------------------------------------------------------------------------------------
