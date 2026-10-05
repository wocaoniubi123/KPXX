import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_background.dart';
import 'fetched_image.dart';

/// 在线图集 1 / 2 **之间**共用的件（用户 2026-10-05 口径 ✓）。
///
/// 放这里的判据 ✓：**两个图集完全同款**的那几块 —— 封面卡 ✓、详情图片列表 ✓、预览层（滑动/页码/框选）✓、提示块 ✓。
/// ⚠️ **取数 + 解析不在这里** ✗：两站结构不同（图集1 封面在 `data-src` ✓ 图集2 在 `src` 且是相对路径 ✓）
///   ⇒ 各页各写一份 ✓（免得一处改动把另一站带坏 ☠）。
/// ⚠️ 本文件**不碰任何公共件** ✗：`lib/base/**` / `fetched_image.dart` / `detail_page.dart` / `lib/sites/**`
///   一律只 `import` 来用 ✓ 不改它们一个字符 ✓。

/// 封面卡（两页同款 ✓）：**只由封面撑** ✓（用户 2026-10-05 拍板 ✗ 不渲染标题 ✓）
/// —— `Card(Clip.antiAlias)` + `AspectRatio(3:4)` + `FetchedImage`（fit 默认 `BoxFit.cover` ✓ 裁边不拉伸 ✓）。
class ArtCard extends StatelessWidget {
  final String cover;
  final VoidCallback onTap;
  /// 封面解码宽度（列表卡用 480 ✓ 与仓库既有封面同规格 ✓）
  final int memWidth;

  const ArtCard({
    super.key,
    required this.cover,
    required this.onTap,
    this.memWidth = 480,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: FetchedImage(url: cover, memWidth: memWidth),
        ),
      ),
    );
  }
}

/// 提示 / 错误 / 空态块（两页同款 ✓）—— 用 `ListView` 兜底 ✓：短内容也能下拉刷新 ✓
/// （同 `home_page.dart` 空列表分支与 `online_album_page.dart` 那份的思路 ✓）。
class ArtMsg extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;

  const ArtMsg({super.key, required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(text,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: kTxtSub)),
                if (onRetry != null) ...[
                  const SizedBox(height: 12),
                  TextButton(onPressed: onRetry, child: const Text('重试')),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 详情页的**图片纵排**（两页同款 ✓）：每张**占满宽度、原图直出、不许裁剪** ✗。
///
/// - `ratios == null`（图集1 ✓）：`FetchedImage` 内部是 `Image.memory`（**不带 width/height** ✓
///   `fetched_image.dart:255-261` ✓）⇒ 在 `ListView`（宽有界、高无界 ✓）里会**按自身比例**撑开 ✓
///   = 满宽 + 不变形 + 不裁 ✓。
/// - `ratios != null`（图集2 ✓）：站点**自己给了每张的比例**（`padding-bottom: N%` ✓）⇒ 用
///   `AspectRatio(1 / (N/100))` + `BoxFit.contain` ✓ = 同样是满宽不裁 ✓（**不许 cover** ✗）。
class ArtImageList extends StatefulWidget {
  final List<String> urls;
  final List<double>? ratios;
  final void Function(int index)? onTapImage;

  const ArtImageList({
    super.key,
    required this.urls,
    this.ratios,
    this.onTapImage,
  });

  @override
  State<ArtImageList> createState() => _ArtImageListState();
}

class _ArtImageListState extends State<ArtImageList> {
  /// ★ 2026-10-05（用户要求 ✓）：进详情页后**预先把整本图抓进缓存** ✗
  ///   ⇒ 之后预览里滑到哪张都不再临时拉图 ✓（sim 侧实测过"滑到没见过的图会 +1 条资源" ✓ 就是这个 ✗）。
  ///
  ///   **复用现成入口** ✓：`FetchedImage.warm`（`fetched_image.dart:61` ✓ 实现 :126-130 ✓）
  ///   —— fire-and-forget ✓ **失败静默** ✓ 与"真正显示时"**共用同一个在途 Future** ✓（`_inflight` ✓）
  ///   ⇒ **不会重复下载** ✓（所以前两张既显示、又被"顺手热到"也不亏 ✓）。
  ///
  ///   ⚠️ **不挡首屏** ✗：从第 3 张才开始热 ✓ —— 前两张交给 `ListView` 自己立刻去取 ✓（画面该出来就出来 ✓）；
  ///   ⚠️ **一张一张串着热**（每张之间让 80ms ✓）：一上来并发上百个请求会把首屏那两张挤慢 ☠。
  ///   ⚠️ 退出页面即停 ✓（`mounted` 判据 ✓ 不会在别的页面上继续热 ✗）。
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmRest());
  }

  Future<void> _warmRest() async {
    for (var i = 2; i < widget.urls.length; i++) {
      if (!mounted) return; // 页面已退出 ⇒ 停止预热 ✓
      FetchedImage.warm(widget.urls[i]);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: widget.urls.length,
      itemBuilder: (context, i) {
        final img = FetchedImage(
          url: widget.urls[i],
          fit: BoxFit.contain,
          memWidth: 1600,
        );
        final r = (widget.ratios != null && i < widget.ratios!.length)
            ? widget.ratios![i]
            : null;
        final child = (r == null || r <= 0) ? img : AspectRatio(aspectRatio: r, child: img);
        if (widget.onTapImage == null) return child;
        return GestureDetector(onTap: () => widget.onTapImage!(i), child: child);
      },
    );
  }
}

/// 预览层（两页同款 ✓ 用户拍板 ✓）：**左右滑切图 + 页码 `x / N` + 下方按钮** ✓。
/// ⚠️ 结构照 `detail_page.dart:838-897` 的 `PhotoViewerPage` **写一份** ✗（**不改那个文件** ✗ ——
///   它的"点图退出"语义与本层要加的"按钮 + 框选"冲突 ✓）。
/// ★ 2026-10-05 用户**最终**口径：**左滑 = 下一张** ✓ **右滑 = 上一张** ✓（= `PageView` 框架默认 ✓
///   故**不加** `reverse` ✗ —— 上一轮曾按"左滑 = 上一张"加过一次，已被这次口径作废 ✓）。
///   ⇒ **第 1 张右滑不动** ✓ **最后一张左滑不动** ✓ **不循环** ✗ —— 两个边界由 `PageView` 自身的
///   `ScrollPhysics` 夹住 ✓（**不写任何边界代码** ✗ 也没有任何循环代码 ✓）。
/// ⚠️ `Stack(fit: StackFit.expand)` ✗：**所有子层都非定位** ✓ ⇒ 不触碰"非定位子层集合"那类坑 ✓
///   （先例 `shorts_feed_page.dart:524-525` 同款 ✓）。
class ArtPreviewPage extends StatefulWidget {
  final List<String> urls;
  final int initial;

  /// ★「设为背景」的落点（**可空挂点** ✓ 用户 2026-10-05 拍板 A2 ✓）：
  ///   传了 ⇒ 点「确认」把裁剪好的 **PNG 字节**交给它 ✓（由调用方决定怎么落地 ✓）；
  ///   ✅ **现状：两个图集都已传入** ✓ —— `onApplyAsBg: (png) => AppBg.i.useDirectImage(png)` ✓
  ///   落到「设置页 → 背景图 → 从相册选择」**那一套存储** ✓（一次性 ✓ **不进图集** ✗）。
  final Future<void> Function(Uint8List png)? onApplyAsBg;

  const ArtPreviewPage({
    super.key,
    required this.urls,
    this.initial = 0,
    this.onApplyAsBg,
  });

  @override
  State<ArtPreviewPage> createState() => _ArtPreviewPageState();
}

class _ArtPreviewPageState extends State<ArtPreviewPage> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  /// 框选态（用户要求 ✓）：此态**不切图** ✗（`PageView` 置 `NeverScrollableScrollPhysics` ✓）
  bool _crop = false;
  final TransformationController _tc = TransformationController();

  /// 当前框尺寸（逻辑像素 ✓）—— 由 `MediaQuery` **动态算** ✗（不写死 ✓）
  Size _frame = Size.zero;

  @override
  void initState() {
    super.initState();
    _tc.addListener(_clampT);
  }

  @override
  void dispose() {
    _tc.removeListener(_clampT);
    _tc.dispose();
    _pc.dispose();
    super.dispose();
  }

  /// ★「夹住」那一小块（唯一自己写的逻辑 ✓）：**图始终盖住框** ⇒ 平移锁在 `±框×(缩放-1)/2` 内 ✓
  ///   （图居中放大 s 倍后四周各多出 (s-1)/2 个框尺寸 ✓）。判据（可验 ✓）：
  ///   ① s=1 ⇒ 上下限都 0 ⇒ **拖不动** ✓（此时 `cover` 已盖满框 ✓ 不会露白 ✓）；
  ///   ② s=2 ⇒ 每轴最多只能拖半个框 ✓ 再多就露边 ⇒ 被拦 ✗；③ **只在越界时**才写回 ✓（不打断手势 ✓）。
  void _clampT() {
    final f = _frame;
    if (f.isEmpty) return;
    final m = _tc.value;
    final s = m.getMaxScaleOnAxis();
    final t = m.getTranslation();
    final mx = f.width * (s - 1) / 2;
    final my = f.height * (s - 1) / 2;
    final x = t.x.clamp(-mx, mx).toDouble();
    final y = t.y.clamp(-my, my).toDouble();
    if ((x - t.x).abs() > 0.01 || (y - t.y).abs() > 0.01) {
      _tc.value = Matrix4.identity()
        ..translate(x, y)
        ..scale(s);
    }
  }

  /// 取**原图字节**（`FetchedImage` 的缓存不外露 ✗ ⇒ 自己下一次 ✓ —— 保存与裁剪都要原图 ✓）
  Future<Uint8List> _download(String url) async {
    final r = await Site.httpClient
        .get(Uri.parse(url), headers: <String, String>{'User-Agent': Site.ua})
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    return r.bodyBytes;
  }

  /// 「保存相册」= **原图无损、不裁剪、直存** ✓
  /// （复用 `package:gal` ✓ —— 与 `bg_album_page.dart:144-159` 同一套权限/落库调用 ✓）
  Future<void> _save() async {
    final msg = ScaffoldMessenger.of(context);
    try {
      final bytes = await _download(widget.urls[_index]);
      final f = File(
          '${Directory.systemTemp.path}/kp_album_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await f.writeAsBytes(bytes, flush: true);
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) {
          msg.showSnackBar(const SnackBar(
              content: Text('没有相册权限 —— 去「设置 → 隐私 → 照片」里给 KPXX 打开')));
          return;
        }
      }
      await Gal.putImage(f.path);
      msg.showSnackBar(const SnackBar(content: Text('已保存到相册')));
      try {
        await f.delete();
      } catch (_) {
        // 临时文件删不掉就算了（系统临时目录自己会清）
      }
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  /// 「确认」（框选态 ✓）：算出裁好的 PNG ⇒ 交给挂点 ✓
  /// ✅ 现状：两个图集都传了挂点 ✓ ⇒ 真的设为背景并关闭预览 ✓（失败有提示 ✓ 不静默死 ✗）；
  ///   ⚠️ 挂点为空的提示分支只在"将来别处复用本页却没传"时才会走到 ✓（保留着当兜底 ✓）
  Future<void> _confirmCrop() async {
    final msg = ScaffoldMessenger.of(context);
    try {
      final raw = await _download(widget.urls[_index]);
      final png = await _cropPng(raw, _frame);
      if (png == null) {
        msg.showSnackBar(const SnackBar(content: Text('裁剪失败：拿不到图片数据 ✗')));
        return;
      }
      final hook = widget.onApplyAsBg;
      if (hook == null) {
        // ★ 2026-10-05（用户拍板 A2 之后 ✓）：这只是"**可空挂点为空**"的兜底文案 ✓
        //   —— 两个图集**都已传入挂点** ✓（见本文件 `onApplyAsBg` 的说明 ✓）⇒ 正常路径走不到这里 ✓
        //   ⚠️ 别再写成"待定/待用户定"✗（那是接挂点之前的说法 ✓ 已经过期 ✓）
        msg.showSnackBar(const SnackBar(
            content: Text('这个页面没有接「设为背景」的挂点 ✗')));
        return;
      }
      await hook(png);
      if (!mounted) return;
      Navigator.of(context).pop();
      msg.showSnackBar(const SnackBar(content: Text('已设为背景（一次性、不进图集）✓')));
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('设为背景失败：$e')));
    }
  }

  /// ★ 框选产图（把**框里看到的那一块**按框比例画成新图 ✓）。判据说明（为什么这么算 ✓）：
  ///   ① 框里是 `BoxFit.cover` + `InteractiveViewer` 默认 `constrained: true` ✓
  ///      ⇒ 图被强制成"框的尺寸"并居中 ✓；手势放大 s 倍、平移 (t.x, t.y) ✓
  ///   ② 总缩放 `total` = cover 基础比 × s ✓（`base = max(框宽/图宽, 框高/图高)` ✓）
  ///   ③ 源矩形：宽 `框宽/total` ✓ 高 `框高/total` ✓，左上 = `(图宽-源宽)/2 - t.x/total` ✓
  ///      （居中量减去平移量、再换算回图坐标 ✓）
  ///   ④ 输出边长系数 `k` = 长边上限 1440 ÷ 框宽 ✓（与 `AppBg.pickFromGallery` 的 `maxWidth: 1440`
  ///      **同规格** ✓ —— 那条是既有代码 ✓ 只对齐数值 ✗ 不调它 ✓）
  ///   ⇒ 画布 1px = 图坐标 `1/total` ⇒ `drawImageRect` 一次画完 ✓（输出 **PNG** ✓ —— Flutter 只能编码 PNG ✗）
  Future<Uint8List?> _cropPng(Uint8List raw, Size frame) async {
    if (frame.isEmpty) return null;
    final codec = await ui.instantiateImageCodec(raw);
    final frameInfo = await codec.getNextFrame();
    final img = frameInfo.image;
    final s = _tc.value.getMaxScaleOnAxis();
    final base = math.max(frame.width / img.width, frame.height / img.height);
    final total = base * s;
    final t = _tc.value.getTranslation();
    final sw = frame.width / total;
    final sh = frame.height / total;
    final sx = (img.width - sw) / 2 - t.x / total;
    final sy = (img.height - sh) / 2 - t.y / total;
    const double kMax = 1440;
    final k = math.min(1.0, kMax / frame.width);
    final ow = (frame.width * k).round();
    final oh = (frame.height * k).round();
    final rec = ui.PictureRecorder();
    final cv = Canvas(rec, Rect.fromLTWH(0, 0, ow.toDouble(), oh.toDouble()));
    cv.drawImageRect(
      img,
      Rect.fromLTWH(sx, sy, sw, sh),
      Rect.fromLTWH(0, 0, ow.toDouble(), oh.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final out = await rec.endRecording().toImage(ow, oh);
    final bd = await out.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    out.dispose();
    return bd?.buffer.asUint8List();
  }

  void _enterCrop() {
    _tc.value = Matrix4.identity();
    setState(() => _crop = true);
  }

  @override
  Widget build(BuildContext context) {
    final m = MediaQuery.of(context).size;
    // 框 = **设备屏幕比例** ✓（动态取 ✗ 不写死 ✓）+ 尽量大（上下给按钮留位 ✓）
    final aspect = m.width / m.height;
    final availW = m.width - 24;
    final availH = m.height - 220;
    var fw = availW;
    var fh = fw / aspect;
    if (fh > availH) {
      fh = availH;
      fw = fh * aspect;
    }
    _frame = Size(fw, fh);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pc,
            // ★ 2026-10-05 用户最终口径：左滑=下一张 · 右滑=上一张（框架默认 ✓ 故不加 reverse ✓）
            //   ⇒ 第 1 张右滑不动 ✓ 最后一张左滑不动 ✓ 不循环 ✓ —— 全由 `PageView` 自身物理夹住 ✓
            //     （不写边界代码 ✗；上一轮加过的 reverse 已按本次口径**删掉** ✓）
            physics: _crop ? const NeverScrollableScrollPhysics() : null, // 框选态**不切图** ✗
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: FetchedImage(
                  url: widget.urls[i],
                  fit: BoxFit.contain,
                  memWidth: 1600,
                ),
              ),
            ),
          ),
          if (!_crop)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    Text('${_index + 1} / ${widget.urls.length}',
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          if (!_crop)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _pill('设为背景', _enterCrop),
                      const SizedBox(width: 14),
                      _pill('保存相册', _save),
                    ],
                  ),
                ),
              ),
            ),
          if (_crop) ...[
            const ColoredBox(color: Colors.black54), // 框外压暗 ✓（框叠在它上面 ✓ 不受影响 ✓）
            Center(
              child: SizedBox(
                width: fw,
                height: fh,
                child: ClipRect(
                  child: InteractiveViewer(
                    transformationController: _tc,
                    minScale: 1,
                    maxScale: 5,
                    child: FetchedImage(
                      url: widget.urls[_index],
                      // 框选态才用 cover（**盖满框** ✓）；详情列表与预览态仍是 contain ✓
                      fit: BoxFit.cover,
                      memWidth: 1600,
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _pill('取消', () => setState(() => _crop = false)),
                      const SizedBox(width: 14),
                      _pill('确认', _confirmCrop),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill(String text, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        // ★ 2026-10-05（用户拍板 ✓ 与 sim 对齐 ✓）：**橙底白字** ✗ —— 与 `settings_page._orange`
        //   （`0xFFE8590C` ✓）**同色** ✓；sim 那套也是橙（`sim/index.html:6998` 注释原文 ✓：
        //   "原来 保存相册 用的是 .cancel 灰底 ✗ ⇒ 改成主按钮那套橙底白字 ✓"）。
        //   ⚠️ 本方法**一处改** ⇒ 预览态那两颗（设为背景 / 保存相册）与框选态那两颗（取消 / 确认）
        //      —— 全页 4 个按钮**一起**变 ✓ 不存在两套配色 ✗（框选那两颗也是调 `_pill` ✓）。
        //   ⚠️ 只动颜色 ✗：尺寸 / 圆角 / 间距 / 文案 / 顺序 / `onTap` 一律未动 ✓。
        backgroundColor: const Color(0xFFE8590C),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    );
  }
}
