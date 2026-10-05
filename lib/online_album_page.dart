import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_background.dart';
import 'app_bg.dart';
import 'config.dart';
import 'home_page.dart';
import 'online_album_common.dart';

/// 「在线图集1」列表页（站点：xofulitu / MacCMS ✓ **服务端渲染** ✓ 2026-10-05 探站实录 ✓）。
///
/// 本站已做 ✓：封面卡片（2 列 ✓）· 详情页（图片纵排满宽不裁 ✓）· 预览层（滑动/页码/保存相册/框选 ✓）。
/// ⚠️ 分类切换（19→20 个 id 已落档 ✓ 见文件底部注释 ✓）/ 翻页（形如 `/arttype/2000-2/` ✓ 共 53 页 ✓）以后再做 ✗。
/// ⚠️ 本站与「在线图集2」**共用的只有** `online_album_common.dart` 那几件 ✓；**取数与解析各写各的** ✗。

/// 站点根（**详情页也要用** ✓ —— 列表项给的 `detail` 是相对路径 `/art/pic/id/N/` ✓）。
const String kOnlineAlbumHost = 'https://zaeg-kiga-rpuv.xofulitu-108.com';

/// 「全部」的第一页（分类 id 实录 ✓：**2000 = 全部** ✓）。
const String kOnlineAlbumUrl = '$kOnlineAlbumHost/arttype/2000/';

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
List<ArtItem> parseArtList(String html) {
  final re = RegExp(r'<a href="(/art/pic/id/\d+/)" class="album-item">');
  final ms = re.allMatches(html).toList();
  final out = <ArtItem>[];
  for (var i = 0; i < ms.length; i++) {
    // 每个条目的正文 = 本条 `<a …>` 之后 → 下一条 `<a …>` 之前 ✓（不跨条抓字段 ✗）
    final start = ms[i].end;
    final end = (i + 1 < ms.length) ? ms[i + 1].start : html.length;
    final chunk = html.substring(start, end);
    var cover = RegExp(r'data-src="([^"]+)"').firstMatch(chunk)?.group(1) ?? '';
    if (cover.isEmpty) {
      // 退路：没 `data-src` 才用 `src` ✓ —— 但要**跳过占位 gif** ✗（原文里 `src` 就是它 ✓）
      final s = RegExp(r'<img[^>]*\ssrc="([^"]+)"').firstMatch(chunk)?.group(1);
      if (s != null && !s.contains('loading_3_green_dot')) cover = s;
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
    if (seen.add(u)) out.add(u);
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
      onTapImage: (i) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ArtPreviewPage(
          urls: _imgs,
          initial: i,
          // ★ 2026-10-05（用户拍板 A2 ✓）：把**裁剪结果**交给「从相册选择」那套存储 ✓
          //   （一次性 ✓ 不进图集 ✗）—— 与设置页那个按钮**同一个落地点** ✓
          onApplyAsBg: (png) => AppBg.i.useDirectImage(png),
        ),
      )),
    );
  }
}

class OnlineAlbumPage extends StatefulWidget {
  const OnlineAlbumPage({super.key});

  @override
  State<OnlineAlbumPage> createState() => _OnlineAlbumPageState();
}

class _OnlineAlbumPageState extends State<OnlineAlbumPage> {
  bool _loading = true;
  String? _err;
  List<ArtItem> _items = const <ArtItem>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Site.httpClient
          .get(Uri.parse(kOnlineAlbumUrl),
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
      if (!mounted) return;
      setState(() {
        _items = list;
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

  @override
  Widget build(BuildContext context) {
    // 整页跟着背景明暗重建（文字色读 kTxt/kTxtSub ✓ 同 bg_album_page ✓）
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.transparent, // 外层 PageBg 已铺背景图，别挡掉
        appBar: AppBar(
          systemOverlayStyle: kStatusOverlay,
          title: const Text('在线图集1'),
          centerTitle: true,
          foregroundColor: kTxt,
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final e = _err;
    if (e != null) return ArtMsg(text: e, onRetry: _load);
    if (_items.isEmpty) return const ArtMsg(text: '这一页是空的 ✗');
    return RowsGrid(
      cols: 2, // 用户指定：2 列 ✓
      physics: const AlwaysScrollableScrollPhysics(),
      count: _items.length,
      itemBuilder: (context, i) {
        final it = _items[i];
        return ArtCard(
          cover: it.cover,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ArtDetailPage(detailPath: it.detail, title: it.title),
          )),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------------------------
// 【已落档、本轮不做 ✗】「在线图集1」的分类 id（2026-10-05 探站实录 ✓ 逐字来自首页导航 ✓）：
//   全部 /arttype/2000/  ✓  热姐 /arttype/2001/  ✓  罗莉塔 /arttype/2002/  ✓  性感的 /arttype/2003/  ✓
//   杂志 /arttype/2004/  ✓  角色扮演 /arttype/5001/  ✓  美足 /arttype/5029/  ✓  唯美写真 /arttype/5030/  ✓
//   模特儿 /arttype/5031/  ✓  日本 /arttype/5032/  ✓  东盟 /arttype/5033/  ✓
//   ⚠️ 韩国 = **/t/5034/** ✓（**不是 `/arttype/`** ✗ 唯一异类 ✓）  柚木 /arttype/5035/  ✓
//   少女映画 /arttype/5036/  ✓  沫沫真爱 /arttype/5037/  ✓  Fushii_海堂 /arttype/5038/  ✓
//   年年 /arttype/5039/  ✓  網路收集系列 /arttype/5041/  ✓  福利姬 /arttype/5042/  ✓
//   ⚠️ id 从 5039 直接跳到 5041 ✓（**没有 5040** ✓）
// 翻页形式 ✓：`/arttype/<id>-<page>/`（原文 `<a href="/arttype/2000-2/" class="paging-item--next">下一页</a>` ✓ 共 **53** 页 ✓）
// ---------------------------------------------------------------------------------------------
