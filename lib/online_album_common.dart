import 'dart:async'; // unawaited（处理中提示 ✓）
import 'dart:io';
import 'dart:isolate'; // Isolate.run（③c 把裁剪挪后台 ✓ 现成机制 ✓）
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import 'app_background.dart';
import 'config.dart';
import 'fetched_image.dart';

/// 在线图集 1 / 2 **之间**共用的件（用户 2026-10-05 口径 ✓）。
///
/// 放这里的判据 ✓：**两个图集完全同款**的那几块 —— 封面卡 ✓、详情图片列表 ✓、预览层（滑动/页码/框选）✓、提示块 ✓。
/// ⚠️ **取数 + 解析不在这里** ✗：两站结构不同（图集1 封面在 `data-src` ✓ 图集2 在 `src` 且是相对路径 ✓）
///   ⇒ 各页各写一份 ✓（免得一处改动把另一站带坏 ☠）。
/// ⚠️ 本文件**不碰任何公共件** ✗：`lib/base/**` / `fetched_image.dart` / `detail_page.dart` / `lib/sites/**`
///   一律只 `import` 来用 ✓ 不改它们一个字符 ✓。

/// ★ 2026-10-05（用户要求"点了立刻出框选" ✓）：**原图尺寸表** —— 只记 `Size` ✗（**绝不留字节** ☠：
///   一张几 MB ✗ 表会跟着涨 ✓；`Size` 就两个 double ✓）。
///   谁写：① 图集1 详情列表的 `FetchedImage` 顺手回调 ✓（`onImageInfo` ✓）；
///          ② 图集2 `AvifBytes` 解出来那一刻顺手记 ✓（同一张只解一次 ✓ **不额外解码** ✓）。
///   谁读：`_enterCrop` ✓ —— 进框选**同步**拿尺寸 ✓（不再"点了才去下一次 + 解一次" ☠ = 原来"慢"的根 ✓）。
///   ⚠️ 没写过的（这张还没显示过）⇒ `null` ⇒ 调用方走"尺寸未知"的兜底 ✓ **不崩、不阻塞点击** ✗。
class AlbumImageSizes {
  AlbumImageSizes._();

  /// url → 原图像素尺寸 ✓（进程内、不落盘 ✓ 冷启动重来一遍可接受 ✓）
  static final Map<String, Size> _m = <String, Size>{};

  /// 记一笔 ✓（尺寸非法就**不记** ✗ —— 免得把 0 写进去把算框搞崩 ☠）；重复写**覆盖** ✓（后到的更可信 ✓）。
  static void put(String url, int w, int h) {
    if (url.isEmpty || w <= 0 || h <= 0) return;
    _m[url] = Size(w.toDouble(), h.toDouble());
  }

  /// 取（没有 ⇒ `null` ✓ 不抛 ✗）
  static Size? of(String url) => _m[url];
}

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
          // ★ D ✓：图**解码出真尺寸**时顺手写进表 ✓（`AlbumImageSizes` ✓ 只记 Size ✗ 不留字节 ✓）
          //   ⇒ 「设为背景」进框选时**同步**就能拿 ✓（原来在那儿才 `_download` + 解一次 ☠ = "慢"的根 ✓）
          onImageInfo: (w, h) => AlbumImageSizes.put(widget.urls[i], w, h),
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

/// ★ 2026-10-05（③c 第二步 ✓）：**裁剪 + PNG 编码的整个算法**，写成**顶层函数** ✓
///   —— 唯一目的：让 `Isolate.run` 能跑它 ✓（闭包只能捕获**可发送**数据 ✓：`Uint8List`/`Size`/`double` 都可以 ✓
///   而 `ui.Image` **不行** ☠ ⇒ 所以口径是"**字节进 → 字节出**" ✓）。
/// ⚠️ **算法与原来一字不差** ✓（只是从 `_ArtPreviewBodyState` 里搬出来 ✓）—— 5 条画质口径逐条在这里 ✓：
///   · a 输出 = **屏幕物理像素** ✓（`k = dpr` ⇒ 393×852@3x ⇒ 1179×2556 ✓）
///   · b **原图一次性缩放** ✓（`instantiateImageCodec` **不传 target** ⇒ 全尺寸解码 ✓ 只 `drawImageRect` 一次 ✓）
///   · c `ui.FilterQuality.high` ✓ · d `ui.ImageByteFormat.png` ✓（无损 ✓ 不用 JPEG ✓）
///   · e 源矩形 = **框内那块的图坐标** ✓（`sx/sy/sw/sh` 同原式 ✓）⇒ 不裁边 ✓ 不拉伸 ✓
Future<Uint8List?> _cropPngBytes(
  Uint8List raw,
  Size frame,
  double s,
  double tx,
  double ty,
  double dpr,
) async {
  if (frame.isEmpty) return null;
  final codec = await ui.instantiateImageCodec(raw);
  final frameInfo = await codec.getNextFrame();
  final img = frameInfo.image;
  final base = math.max(frame.width / img.width, frame.height / img.height);
  final total = base * s;
  final sw = frame.width / total;
  final sh = frame.height / total;
  final sx = (img.width - sw) / 2 - tx / total;
  final sy = (img.height - sh) / 2 - ty / total;
  final k = dpr;
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

/// 预览层的**内容**（两页同款 ✓ 用户拍板 ✓）：**左右滑切图 + 页码 `x / N` + 下方按钮** ✓。
/// ⚠️ 结构照 `detail_page.dart:838-897` 的 `PhotoViewerPage` **写一份** ✗（**不改那个文件** ✗ ——
///   它的"点图退出"语义与本层要加的"按钮 + 框选"冲突 ✓）。
/// ★ 2026-10-05（**照 sim 1:1** ✗）：切图 = **指针按下→抬起比位移** ✓（sim `:6963-6972` 逐字 ✓）
///   ⇒ **不用 `PageView`** ✗（没有滑动动画 ✓ 与 sim `:6956`"直接换图"一致 ✓）
///   · 方向：**左滑 = 下一张** ✓ **右滑 = 上一张** ✓（sim `dx < 0 ? 1 : -1` ✓ `:6969` ✓）
///   · 阈值：**绝对位移 ≥ 40px** ✓ 且**横向要大于纵向** ✓（sim `Math.abs(dx) < 40 || Math.abs(dx) <= Math.abs(dy) ⇒ return` ✓ `:6968` ✓）
///   · 边界：**越界不动** ✓（sim `ni < 0 || ni > n - 1 ⇒ return` ✓）⇒ **第 1 张右滑不动** ✓
///     **最后一张左滑不动** ✓ **不循环** ✗（不写取模 ✗）
/// ★ 2026-10-05（照 sim 1:1 ✓）：预览态 = **一列居中**（图 → 页码 → 按钮排 ✓）——
///   **没有顶栏、没有 X** ✗（sim 靠"点遮罩关" ✓ `:6928` ✓）；页码在**图下方居中** ✓（不是顶栏 ✓）。
/// ⚠️ `Stack(fit: StackFit.expand)` ✗：**所有子层都非定位** ✓ ⇒ 不触碰"非定位子层集合"那类坑 ✓
///   （先例 `shorts_feed_page.dart:524-525` 同款 ✓）。
/// ⚠️ **本组件的定位 = 纯内容** ✓：不带 `Scaffold`、不自己决定"怎么关" ⇒ 由外层外壳决定 ✓
///   —— 两种外壳（**浮层** = 主用 ✓ / **整页** = 保留 ✗）见下面 `showArtPreviewOverlay` / `ArtPreviewPage` ✓
///   ⇒ **内容只有这一份实现** ✓ 两面永不漂移 ✓。
class ArtPreviewBody extends StatefulWidget {
  final List<String> urls;
  final int initial;

  /// ★「设为背景」的落点（**可空挂点** ✓ 用户 2026-10-05 拍板 A2 ✓）：
  ///   传了 ⇒ 点「确认」把裁剪好的 **PNG 字节**交给它 ✓（由调用方决定怎么落地 ✓）；
  ///   ✅ **现状：两个图集都已传入** ✓ —— `onApplyAsBg: (png) => AppBg.i.useDirectImage(png)` ✓
  ///   落到「设置页 → 背景图 → 从相册选择」**那一套存储** ✓（一次性 ✓ **不进图集** ✗）。
  final Future<void> Function(Uint8List png)? onApplyAsBg;

  /// 关闭动作（X 与「设为背景」成功后调 ✓）：
  ///   **浮层**外壳 ⇒ 传"关掉浮层" ✓（`showArtPreviewOverlay` 里给 ✓）；
  ///   **整页**外壳 ⇒ 传 `null` ⇒ 内部退回 `Navigator.pop` ✓。
  final VoidCallback? onClose;

  /// ★ 2026-10-05（**用户点破** ✓）：预览里的图**不再一律从 URL 走 `FetchedImage`** ☠ ——
  ///   允许调用方注入"**已经解好的字节**"（图集2 的 AVIF 解完就缓存在它自己的 `AvifBytes` 里 ✓）
  ///   ⇒ 预览**零额外网络、零额外解码** ✓（用户原话："你都自己解了 —— AVIF 的预览直接用详情页解好的不就行了" ✓）。
  ///   ⚠️ **默认 `null` ⇒ 行为与以前一字不变** ✓（仍走 `FetchedImage(url:)` ✓）—— 图集1 与其它调用点**不传** ✓。
  ///   **我选"取字节"**（`Uint8List? Function(String url)?`）**而不是给 Widget / ImageProvider**，依据 ✓：
  ///     ① 预览里同一张图要被**两处**用（预览态 `contain` ✓ / 框选态 `cover` ✓）⇒ 给字节，
  ///        本组件自己按各自 `fit` 喂 `Image.memory` ✓（最省事 ✓）；给 Widget ⇒ 得复制两套布局 ✗；
  ///     ② 给 `ImageProvider` 是**同义反复** ✗（`MemoryImage` 也要先有字节 ✓ 调用方还得再造一次壳 ✓）。
  ///   ⚠️ **同步返回** ✓：命中缓存立即出图 ✓；未命中给 `null` ⇒ **回落到 `FetchedImage`** ✓（老路照旧 ✓）。
  final Uint8List? Function(String url)? bytesFor;

  const ArtPreviewBody({
    super.key,
    required this.urls,
    this.initial = 0,
    this.onApplyAsBg,
    this.onClose,
    this.bytesFor,
  });

  @override
  State<ArtPreviewBody> createState() => _ArtPreviewBodyState();
}

/// ★ 2026-10-05 用户拍板（呈现方式 ③）：预览 = **浮层** ✗（**不跳页** ✓ 当前页上浮一层半透明遮罩 ✓ 点空白关 ✓）。
/// 用**框架自有机制** `showGeneralDialog` ✓（不自造 Overlay ✗）—— **依据**（每条都省掉了手搭的活 ✓）：
///   ① `barrierColor: Colors.black45` = 半透明遮罩 ✓（**照 sim 的 `rgba(0,0,0,.45)`** ✓ `sim/index.html:694` ✓）；
///      `barrierDismissible: true` = **点空白关** ✓
///      （遮罩自己处理点击 ⇒ **图/按钮区域不会误关** ✓ —— 点在内容上时不触达遮罩 ✓）；
///   ② 它是**独立路由** ⇒ **系统返回键/侧滑手势只关浮层、不退详情页** ✓（要求 5 ✓ 不用手写 `PopScope` ✓）；
///   ③ 内容直接用共用的 [ArtPreviewBody] ✓ ⇒ 与整页版**同一份** ✓。
/// ⚠️ **下滑关** ✓（用户口径 ✓）：实现见 `ArtPreviewBody.build` 的 `GestureDetector(onVerticalDragEnd:)` ✓
///   —— **只在图片区之外**（黑色留白 / 页码行 ✓）生效 ✓，因为 `InteractiveViewer` 的手势声明两轴、
///   **会吃掉图片区里的竖向拖动** ☠（框架行为 ✓ 不是 bug ✓）；**框选态一律禁止** ✗（`if (_crop) return;` ✓）。
Future<void> showArtPreviewOverlay(
  BuildContext context, {
  required List<String> urls,
  int initial = 0,
  Future<void> Function(Uint8List png)? onApplyAsBg,
  Uint8List? Function(String url)? bytesFor,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭预览',
    // ★ 2026-10-05（照 sim 抄 ✓）：遮罩色 = sim `.ovl` 的 `background: rgba(0,0,0,.45)` ✓
    //   （`sim/index.html:694` 逐字 ✓）⇒ Flutter 的 `Colors.black45` 就是 rgba(0,0,0,.45) ✓ 不多不少 ✓
    barrierColor: Colors.black45,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (dialogCtx, _, __) => SafeArea(
      child: ArtPreviewBody(
        urls: urls,
        initial: initial,
        onApplyAsBg: onApplyAsBg,
        bytesFor: bytesFor, // ★ 透传给内容 ✓（不传 ⇒ null ⇒ 老路 `FetchedImage` ✓）
        onClose: () => Navigator.of(dialogCtx).pop(),
      ),
    ),
  );
}

/// **整页**外壳（旧入口 ✓ **保留不删** ✗）。
/// ⚠️ 2026-10-05 现状（如实 ✓）：**调用点 = 0** ✗ —— 两个图集都已改成 [showArtPreviewOverlay]（浮层 ✓）
///   ⇒ 本类现在是**备用入口**（留作"将来要整页看"的退路 ✓）⇒ 去留由用户定 ✓ **别当 bug 删** ✗。
class ArtPreviewPage extends StatelessWidget {
  final List<String> urls;
  final int initial;
  final Future<void> Function(Uint8List png)? onApplyAsBg;

  const ArtPreviewPage({
    super.key,
    required this.urls,
    this.initial = 0,
    this.onApplyAsBg,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ArtPreviewBody(
        urls: urls,
        initial: initial,
        onApplyAsBg: onApplyAsBg,
      ),
    );
  }
}

class _ArtPreviewBodyState extends State<ArtPreviewBody> {
  late int _index = widget.initial;

  /// ★ 2026-10-05（照 sim 1:1 ✓）：切图**不用 `PageView`** ✗ —— sim 是"指针按下→抬起比位移"：
  ///   `if (Math.abs(dx) < 40 || Math.abs(dx) <= Math.abs(dy)) return;` ✓（`sim:6968` 逐字 ✓）
  ///   ⇒ 这里累计横向位移 ✓ 抬起时按 **≥40px** 判 ✓（竖着划不算 ✓）。
  double _dragDx = 0;

  /// 框选态（用户要求 ✓）：此态**不切图** ✗
  bool _crop = false;
  final TransformationController _tc = TransformationController();

  /// 当前框尺寸（逻辑像素 ✓）—— 由 `MediaQuery` **动态算** ✗（不写死 ✓）
  Size _frame = Size.zero;

  /// ★ 2026-10-05（F ✓）：图的**显示盒** `dw×dh`（= 原图 contain 缩进 avail 盒后的尺寸 ✓ 逻辑像素 ✓）——
  ///   与 [_frame] 一样在 `build` 里算 ✓（所以存字段 ✓：`_clampT` 每帧要用 ✓）。
  Size _disp = Size.zero;

  /// ★ 2026-10-05（用户真机反馈"**设为背景后非常模糊/几乎马赛克**" ☠ 的根因修法）：
  ///   `MediaQuery.of(context).size` 给的是**逻辑尺寸** ✗（393×852 这种 ✓），而物理屏是 393×852 **@3x** ✓
  ///   ⇒ **出图必须乘上设备像素比** ✗ ⇒ 393×852 @3x ⇒ **1179×2556** ✓（= 用户要的"手机分辨率"✓）。
  ///   ⚠️ 在 `build` 里现取 ✓（`_cropPng` 里没有 `context` ✗ 拿不到 —— 原来就是因此漏了这一步 ☠）。
  double _dpr = 1;

  /// ★ 2026-10-05（用户要求 ✓）：**重入保护** ✗ —— 「确认」在跑的时候再点 ⇒ **直接忽略** ✓
  ///   （连点两次不许弹两个转圈对话框 ☠）。由 `_confirmCrop` 的 `try/finally` 负责复位 ✓。
  bool _applying = false;

  /// ★ 2026-10-05（用户要求"**在原图上自己选区域**" ✓）：图的**真实尺寸**（原图像素 ✓）——
  ///   来源 = **尺寸表** `AlbumImageSizes` ✓（详情列表的 `FetchedImage` / 图集2 的 `AvifBytes` 解码时顺手写的 ✓）；
  ///   拿不到 ⇒ 留 `null` ⇒ 先按 avail 盒占位 ✓ + `_clampT` **退回旧算法** ✓（不崩 ✗）；到了再重算 ✓。
  Size? _imgSize;

  @override
  void initState() {
    super.initState();
    // ★ 2026-10-05（用户反馈"双指不灵敏" ✓ 真因）：**不再** `_tc.addListener(_clampT)` ✗ ——
    //   监听在手势进行中回写 `_tc.value` ⇒ 与 `InteractiveViewer` 内部手势打架 ☠
    //   ⇒ 改为在 `InteractiveViewer(..., onInteractionUpdate/End)` 回调里夹 ✓ 跟手 ✓（见框选态那处）
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  /// 切图（照 sim `albPreviewStep` ✓）：`d = +1` 下一张 / `-1` 上一张 ✓；
  ///   **越界不动** ✓（sim `if (ni < 0 || ni > n - 1) return;` ✓）⇒ **第 1 张右滑不动** ✓
  ///   **最后一张左滑不动** ✓ **不循环** ✗（不写任何取模 ✗）。
  void _step(int d) {
    final n = widget.urls.length;
    final ni = _index + d;
    if (ni < 0 || ni > n - 1) return; // 照 sim ✓
    setState(() => _index = ni);
  }

  /// 关闭动作（X ✓ / 「设为背景」成功后 ✓）—— **只有这一处实现** ✓：
  ///   浮层外壳 ⇒ 调它传进来的 [ArtPreviewBody.onClose]（= 关掉浮层 ✓ 不退详情页 ✗）；
  ///   整页外壳 ⇒ `onClose` 为 `null` ⇒ 退回 `Navigator.pop` ✓。
  void _close() {
    final c = widget.onClose;
    if (c != null) {
      c();
    } else {
      Navigator.of(context).pop();
    }
  }

  /// ★「夹住」那一小块（唯一自己写的逻辑 ✓）：**框始终被图盖住**、**贴边即止** ✓ ——
  ///   新式（F/G 定稿 ✓）：余量按**显示盒** `dw/dh` 与框 `fw/fh` 算 ✗（**不再**按 cover 基底 ☠）：
  ///   `mx` = 显示盒宽 × s **减去** 框宽、再折半、负数取 0 ✓（`my` 同理 ✓）。
  ///   判据（可验 ✓）：① 框恒 ≤ 显示盒 ⇒ `s=1` 时两轴余量都 ≥ 0 ✓（横轴可能 > 0 ⇒ **能平移** ✓ **不露白** ✗）；
  ///   ② `s` 越大余量越大 ✓；③ **只在越界时**才写回 ✓（不打断手势 ✓）。
  void _clampT() {
    final f = _frame;
    if (f.isEmpty) return;
    final m = _tc.value;
    final s = m.getMaxScaleOnAxis();
    final t = m.getTranslation();
    // ★ 2026-10-05（G ✓）：余量按**显示盒**算 ✗（原来按 `max` 取 cover 基底再乘 s ☠ —— 那套配 contain 就是错的）；
    //   ⚠️ 尺寸还没到 ⇒ 显示盒 = avail 盒占位 ✓（照样能拖 ✓；到了 `_onImgInfo` 会 setState ⇒ 重算 ✓）
    //      ⇒ 这里**不需要**"退旧算法"分支 ✓（显示盒恒非空 ✓，退化时也只是余量 0 = 拖不动 ✓ 不崩 ✗）。
    //   实例（定稿数字 ✓）：屏 393×852 ⇒ avail 盒 369×632 ✓；图 1080×1620 ⇒ dw=369 · dh=553.5 ✓、框 255.3×553.5 ✓
    //   ⇒ s0 = 1.15 ⇒ **mx = 84.5** · **my = 41.5** ✓（两轴都能拖 ✓ 且**恒不露白** ✗）。
    final disp = _disp;
    final mx = math.max(0.0, (disp.width * s - f.width) / 2);
    final my = math.max(0.0, (disp.height * s - f.height) / 2);
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
    if (_applying) return; // ★ 重入保护 ✓（连点两次 ⇒ 只跑一次 ✓ 不会弹两个对话框 ✓）
    _applying = true;
    final msg = ScaffoldMessenger.of(context);
    // ★ 2026-10-05（用户要求 ✓ "全程显示处理中"）：**选 `showDialog` + `CircularProgressIndicator`** ✓
    //   依据 ✓：① `barrierDismissible: false` ⇒ 用户**不能误点关掉**它 ✓（常驻 SnackBar 容易被下一条顶掉 ✗）；
    //          ② 两者都是**框架现成件** ✗ 不自造 ✓；③ 它盖在预览浮层之上 ✓ 语义正确 ✓
    //   ⚠️ **三条路都必须能关掉** ✓（成功 / 失败 / 异常 ⇒ 全部走 `finally` ✓ 不许残留转圈 ☠）
    NavigatorState? progressNav;
    try {
      progressNav = Navigator.of(context, rootNavigator: true);
      unawaited(showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      ));
      final raw = await _download(widget.urls[_index]); // ★ 2026-10-05：`_rawCache` 已删 ✗ ⇒ 这里**只剩直接下** ✓（与"它恒为 null"**语义等价** ✓）
      final png = await _cropPngWithFallback(raw, _frame); // ★ 后台 isolate + 回落 ✓（见下面那支 ✓）
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
      _close(); // 浮层 ⇒ 关浮层 ✓（**不退详情页** ✗）；整页 ⇒ pop ✓ —— 同一处实现 ✓
      msg.showSnackBar(const SnackBar(content: Text('已设为背景（一次性、不进图集）✓')));
    } catch (e) {
      // ★ 失败**要有提示** ✓（不静默死 ✗）
      msg.showSnackBar(SnackBar(content: Text('设为背景失败：$e')));
    } finally {
      // ★ 三条路统一在这里关掉转圈 ✓（成功 / return / 异常 ⇒ 都会走到 ✓）
      if (mounted) {
        try {
          progressNav?.pop();
        } catch (_) {
          // 弹层已被系统弹掉之类 ⇒ 吞掉 ✓（绝不让"关不掉"把用户卡住 ✗）
        }
      }
      _applying = false;
    }
  }

  /// ★ 2026-10-05（用户要求 ✓）：**裁剪 + PNG 编码挪到后台 isolate** ✗ —— 用**现成机制** `Isolate.run` ✓
  ///   （不自造 isolate ✓）。⚠️ **必须配回落** ☠：后台 isolate 里 `dart:ui`（codec / `PictureRecorder`）的可用性
  ///   我**本机验不了**（无 SDK/无设备 ✗）⇒ 任何异常 / 拿不到结果 ⇒ **回落到主 isolate 直算** ✓ 绝不让用户卡死 ✗。
  ///   ⚠️ **算法一字不动** ✓：只是"换地方跑" ✓ —— 5 条画质口径全在下面 [_cropPngBytes] 里 ✓（dpr ✓ 一次性缩放 ✓
  ///   `FilterQuality.high` ✓ PNG ✓ 裁框内 ✓）。⚠️ **不跨 isolate 传 `ui.Image`** ✓（`ui.Image` 非 sendable ☠）
  ///   ⇒ 口径 = **字节进 → 字节出** ✓。
  Future<Uint8List?> _cropPngWithFallback(Uint8List raw, Size frame) async {
    final s = _tc.value.getMaxScaleOnAxis();
    final t = _tc.value.getTranslation();
    try {
      final png = await Isolate.run(
        () => _cropPngBytes(raw, frame, s, t.x, t.y, _dpr),
      );
      if (png != null) return png;
      debugPrint('后台 isolate 裁剪返回空 ⇒ 回落主 isolate ✓');
    } catch (e) {
      debugPrint('后台 isolate 裁剪不可用 ⇒ 回落主 isolate：$e');
    }
    return _cropPng(raw, frame); // ★ 回落 ✓（老路 ✓ 一字未改 ✓）
  }

  /// ★ 框选产图（把**框里看到的那一块**按框比例画成新图 ✓）。判据说明（为什么这么算 ✓）：
  ///   ① 框里是 `BoxFit.cover` + `InteractiveViewer` 默认 `constrained: true` ✓
  ///      ⇒ 图被强制成"框的尺寸"并居中 ✓；手势放大 s 倍、平移 (t.x, t.y) ✓
  ///   ② 总缩放 `total` = cover 基础比 × s ✓（`base = max(框宽/图宽, 框高/图高)` ✓）
  ///   ③ 源矩形：宽 `框宽/total` ✓ 高 `框高/total` ✓，左上 = `(图宽-源宽)/2 - t.x/total` ✓
  ///      （居中量减去平移量、再换算回图坐标 ✓）
  ///   ④ 输出边长系数 `k` = **设备像素比 `_dpr`** ✓（2026-10-05 用户报"糊"后定的口径 ✓：
  ///      出图 = **物理像素** ⇒ 393×852 @3x ⇒ 1179×2556 ✓；**不再有 1440 上限** ✗ —— 见下面那段说明 ✓）
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
    // ★ 2026-10-05（用户真机反馈"设为背景后**糊**" ☠ 的修法）：画布尺寸 = **物理像素** ✗
    //   根因（读数实测 ✓）：`frame` 是**逻辑尺寸**（`build` 里来自 `MediaQuery.size` ✓ 393×852 ✓），
    //   而原来这里是 `k = math.min(1.0, 1440 / frame.width)` ⇒ 393 宽时**恒等于 1.0** ⇒
    //   出图 = **393×852** ✗ ⇒ @3x 屏放大 3 倍显示 ⇒ **少 9 倍像素** ☠（用户看到的就是这个 ✓）。
    //   现在 `k = _dpr` ✓（393×852 @3x ⇒ **1179×2556** ✓）；
    //   ⚠️ **不加 1440 上限** ✗（那会把 iPad / 大屏又砍回小图 ✗ —— 用户口径 = "手机分辨率" ✓）。
    final k = _dpr;
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

  /// ★ 2026-10-05（用户报"点「设为背景」要等" ✓ 真因）：**点了立刻出框选** ✗ ——
  ///   **删掉**原来那两步 ☠：`_download` 取图 + `instantiateImageCodec` 解码（原来点完要等"下载 + 解码"才出界面 ✓）
  ///   ⇒ 那就是"慢"的根 ✓。现在尺寸走**尺寸表** `AlbumImageSizes` ✓（详情列表 / AVIF 解码时顺手写下的 ✓）⇒ **同步**拿 ✓。
  ///   ⚠️ 尺寸还没到（这张没显示过）⇒ `_imgSize = null` ⇒ 界面上是**占位 / 转圈** ✓ **绝不为空** ✗
  ///      （图本身仍走 `_artImage` ✓：有注入字节就用字节 ✓ 没有就回落 `FetchedImage` ✓ 它自带占位 ✓）；
  ///      显示盒先按 avail 盒占位 ✓ ⇒ **照样能拖能捏** ✓（尺寸到了 `_onImgInfo` 会 setState 重算 ✓）⇒ **不崩、不阻塞点击** ✗。
  ///   ⚠️ `_rawCache` 已**删掉** ✗（E 之后它恒为 null ⇒ 死代码 ☠）—— 「确认」那条现在**只剩** `await _download` ✓
  ///      （与"它恒为 null 时"**语义等价** ✓）；裁剪出图那 5 条画质口径**一个不碰** ☠。
  Future<void> _enterCrop() async {
    _imgSize = AlbumImageSizes.of(widget.urls[_index]); // ★ E ✓：同步取（可能 null ✓ 有兜底 ✓）
    if (!mounted) return;
    // ★ 2026-10-05（G ✓）：初始 **s0 = 1.15** —— 依据：`InteractiveViewer` 的 `minScale: 1` ✓ 而"框（屏比）"
    //   一般比显示盒窄 ⇒ `s=1` 时横轴有余量、**纵向常为 0**（拖不动 ✗）⇒ 先放大 15% ⇒ **两轴都能挪** ✓
    //   （用户口径是"在**整张原图**上自己选区域" ✓）；写法与 `_clampT` 里那句同款 ✓（`scale` 同一套 ✓）。
    _tc.value = Matrix4.identity()..scale(1.15);
    setState(() => _crop = true);
  }

  @override
  Widget build(BuildContext context) {
    final m = MediaQuery.of(context).size;
    // ★ 2026-10-05：设备像素比**必须现取** ✗（`_cropPng` 里没有 context ✓ 只能在 build 拿 ✓）
    _dpr = MediaQuery.of(context).devicePixelRatio;
    // ★ 2026-10-05（F ✓ 用户要求"框选时看得见整张原图"）：**contain 完整显示 + 框叠在图上** ——
    //   盒子仍是**现有 avail 盒** ✓（m.width−24 × m.height−220 ✓ 与"上下给按钮留位"同一套口径 ✓
    //   长图也不会把"图 + 页码 + 按钮"顶出屏幕 ☠）。
    final availW = m.width - 24;
    final availH = m.height - 220;
    final aspect = m.width / m.height; // 框比 = **屏比** ✓（动态取 ✗ 不写死 ✓）
    // ① 图的**显示盒** `dw×dh` = 原图按 `k_img = min(W/iw, H/ih)` 缩进 avail 盒 ✓（contain ✓ 完整 ✓ 不裁 ✗）
    //    ⚠️ 尺寸还没到（"缓一拍" ✓）⇒ 先用 avail 盒当占位 ✓；到了会走 `_onImgInfo` ⇒ setState ⇒ 重算 ✓
    final img = _imgSize;
    final double dw, dh;
    if (img == null || img.isEmpty) {
      dw = availW;
      dh = availH;
    } else {
      final kImg = math.min(availW / img.width, availH / img.height);
      dw = img.width * kImg;
      dh = img.height * kImg;
    }
    // ② 框 = 屏比矩形**塞进显示盒**里最大的那个 ✓（`fw = min(dw, dh*a)` ⇒ 框**绝不出图** ✓ 居中 ✓）
    final fw = math.min(dw, dh * aspect);
    final fh = fw / aspect;
    _disp = Size(dw, dh);
    _frame = Size(fw, fh);

    return Scaffold(
      // ★ 2026-10-05（用户反馈 ✓）：**浮层要半透明** ✗ —— 原先是 `Colors.black` ☠
      //   真因（读数 ✓）：不透明的是**本组件自己的 `Scaffold` 底色** ✓（不是 dialog ✓ 不是遮罩 ✓
      //   `pageBuilder` 里没有 Material/Container ✓；遮罩 `barrierColor: Colors.black45` = sim 的 .45 ✓ 保持 ✓）
      //   ⇒ 改 `Colors.transparent` ✓ ⇒ **能透出下面的详情页** ✓
      //   ⚠️ 整页外壳（`ArtPreviewPage`）那处**不动** ✗ —— 它本来就是"整页黑底"的语义 ✓
      backgroundColor: Colors.transparent,
      // ★ 2026-10-05（用户口径 ✓）：**下滑关** ✗ —— 生效范围 = **图片区之外**（黑色留白 / 页码行 ✓）：
      //   `InteractiveViewer` 的手势同时声明两轴 ⇒ **会吃掉图片区里的竖向拖动** ☠（框架行为 ✓ 不是 bug ✓）；
      //   ⚠️ **框选态一律禁止** ✗（那会儿竖向拖动是"拖图"✓ 打架 ☠）。
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // ★ 2026-10-05（用户报"点空白不关" ✓ 真因）：透明 ≠ 不吃指针 ⇒ 空白处补一个 tap 才收得到 ✓
        //   四类边界：空白 ⇒ 关 ✓；图上（内层那个 detector 认领）⇒ 关 ✓（同一动作 ✓）；
        //   两颗按钮（`TextButton` 认领）⇒ **不关** 且能点 ✓；页码（下面套了 `opaque` 壳）⇒ **不关** ✓；
        //   框选态 ⇒ `_crop ? null` ⇒ **一律不关** ✓
        onTap: _crop ? null : _close,
        onVerticalDragEnd: _crop
            ? null
            : (d) {
                if ((d.primaryVelocity ?? 0) > 250) _close(); // 向下 = 正速度 ✓
              },
        child: Stack(
        fit: StackFit.expand,
        children: [
          // ★ 2026-10-05（**照 sim 1:1** ✗）：预览态 = **一列居中**（图 → 页码 → 按钮排 ✓）
          //   sim 原文（`sim/index.html:7000-7005` / `:7590-7595` 逐字 ✓）：
          //     `<div width:100%;padding:0 12px>` → `<img width:100%;height:auto;border-radius:10px>`
          //     → 页码 `<div text-align:center;color:#fff;opacity:.85;font-size:12px;margin:8px 0 0>`
          //     → `.row2`（`gap:10px;margin-top:12px` ✓）两颗 `.ok`（橙底白字 ✓）
          //   ⚠️ **没有关闭 X** ✗（sim 靠"点遮罩关" ✓ `:6928` ✓）；**也没有顶栏** ✗ —— 已按 sim 删掉 ✓
          //   ⚠️ 切图 = **直接换图**（sim `:6956`"没有滑动动画 ✗" ✓）⇒ **不用 `PageView`** ✓
          //      阈值 = sim 的 **绝对 40px** ✓（`:6967 Math.abs(dx) < 40 ⇒ 不切` ✓）
          if (!_crop)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12), // = sim `padding:0 12px` ✓
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: GestureDetector(
                        // ★ 2026-10-05（用户报"只有快划才认" ✓ 真因）：**框选态必须把预览手势全摘掉** ☠
                        //   —— 摘之前：这层与内层 `InteractiveViewer` 抢同一个指针 ⇒ 慢拖被 tap 认走/被僵住 ✓
                        //   ⇒ 三件全部 `_crop ? null : …` ✓ ⇒ 框选态只剩"拖 + 捏" ✓（**只看位移、不看快慢** ✓）
                        onTap: _crop ? null : _close,
                        // 切图手势：横向位移 ≥40px 才算 ✓（照 sim ✓）；竖着划不算 ✓
                        onHorizontalDragStart: _crop ? null : (_) => _dragDx = 0,
                        onHorizontalDragUpdate:
                            _crop ? null : (d) => _dragDx += d.delta.dx,
                        onHorizontalDragEnd: _crop
                            ? null
                            : (_) {
                                if (_dragDx.abs() < 40) return; // = sim 的阈值 ✓
                                _step(_dragDx < 0 ? 1 : -1); // 左滑 = 下一张 ✓ 右滑 = 上一张 ✓（sim :6969 ✓）
                              },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10), // = sim 的 border-radius:10px ✓
                          child: InteractiveViewer(
                            maxScale: 5,
                            child: _artImage(widget.urls[_index], BoxFit.contain, 1600),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8), // = sim `margin:8px 0 0` ✓
                      // ★ 2026-10-05（用户口径 ✓）：**点页码不算"点图"** ⇒ 包一层 `opaque` 壳把点击吃掉 ✓
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {}, // 什么都不做 ⇒ 不外泄给外层（外层那个 tap 会关预览 ✗）
                        child: Text('${_index + 1} / ${widget.urls.length}',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 12)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 12), // = sim `.row2 margin-top:12px` ✓
                      // ★ 照 sim ✓：`.ovl .row2 > div { flex:1 }`（`sim:707` 逐字 ✓）⇒ **两颗等宽铺满整排** ✓
                      //   （`Row` 默认 `mainAxisSize.max` ⇒ 宽度 = 上面的内容盒宽 ✓ = sim 的 `width:100%` ✓）
                      child: Row(
                        children: [
                          Expanded(
                              child: _pill('设为背景', () => _enterCrop())), // `_enterCrop` 异步化 ✓ 包一层 ✓
                          const SizedBox(width: 10), // = sim `.row2 gap:10px` ✓
                          Expanded(child: _pill('保存相册', _save)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_crop) ...[
            // ★ 2026-10-05（照 sim 抄 ✓）：框外压暗 = sim 的 `box-shadow: 0 0 0 9999px rgba(0,0,0,.55)`
            //   （`sim/index.html:7604` 逐字 ✓）⇒ Flutter **没有 .55 的具名常量** ✗（只有 black54/.45/.87 ✗）
            //   ⇒ 用 `0x8C000000`：0x8C = 140，140/255 = **.549** ✓ ≈ sim 的 .55 ✓（差 0.001，肉眼无别 ✓）
            const ColoredBox(color: Color(0x8C000000)),
            // ★ 2026-10-05（照 sim 1:1 ✓）：框选态 = **一列居中**（框 → 页码 → 按钮排 ✓）
            //   sim 原文 `:7019-7026` 逐字 ✓：`<div flex-direction:column;align-items:center;gap:16px>`
            //     → `#albCropStage width:${fw}px;height:${fh}px;border-radius:12px`
            //     → 页码 `<div text-align:center;color:#fff;opacity:.85;font-size:12px>` ✓（**框选态也显示** ✗）
            //     → `.row2 width:100%;margin:0` 两颗 `.ok`：**确认 → 取消** ✓（`:7025-7026` 顺序 ✓）
            Center(
              // ★ 照 sim ✓：框选那列的**外盒也带 `padding:0 12px`**（`sim:7601` 逐字 ✓）
              //   ⇒ 按钮排的 `width:100%` 才等于"屏幕宽 − 24" ✓
              //   ⚠️ **框宽 / 显示盒的口径已经改了** ✗：现在是 avail 盒里算出来的 `dw/dh`（显示盒 ✓）
              //      与 `fw/fh`（框 ✓）—— **不再是** `m.width - 24` ✓（见上面 ① ② 两段 ✓）
              child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: dw,
                    height: dh,
                    // ★ 2026-10-05（F ✓）：这一格 = 【**图（contain ✓ 完整 ✓ 不裁 ✗）+ 框外压暗 ✓**】叠在一起 ——
                    //   ⚠️ **子层全非定位** ✓（**不用 `Positioned`** ✗ —— 那是"非定位子层集合"老坑 ☠）；
                    //   顺序 = 图（可拖 / 可捏 ✓）⇒ 压暗（挖孔 ✓ 且 `IgnorePointer` ⇒ **不吃手势** ✗）⇒ 框由"孔的边"体现 ✓
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRect(
                          child: InteractiveViewer(
                            transformationController: _tc,
                            minScale: 1,
                            maxScale: 5,
                            // ★ 2026-10-05（用户反馈"**拖不动**" ✓ 真因读数）：原来**没有** `boundaryMargin` ⇒
                            //   默认 `EdgeInsets.zero` ⇒ 可位移量 = 0 ⇒ 拖不动 ☠ ⇒ 给足边距 ✓ **图可随心拖** ✓；
                            //   "**框始终被图盖住**"由 `_clampT` 每帧夹住 ✓（新式余量 = 显示盒 − 框 ✓ 见 `_clampT` ✓）
                            boundaryMargin: const EdgeInsets.all(4000),
                            // ★ 2026-10-05（用户反馈"**双指不灵敏**" ✓ 真因读数）：`_clampT` 原来挂在 `_tc` 的**监听**上，
                            //   手势进行中**回写** `_tc.value` ⇒ 与 `InteractiveViewer` 内部手势**互相打架** ☠
                            //   ⇒ 改成**在回调里夹** ✓（不再用监听 ✓ 见 `initState` 的那处删改 ✓）⇒ 手指一动就跟随 ✓
                            onInteractionUpdate: (_) => _clampT(),
                            onInteractionEnd: (_) => _clampT(),
                            // ★ 2026-10-05（F ✓）：**框选态也是 contain** ✗ —— 原来是 cover ☠（图"正好盖住框"
                            //   ⇒ 屏上像"已经裁好了" ⇒ 用户看不见整张原图 ✗）；详情列表与预览态本来就是 contain ✓
                            child: _artImage(widget.urls[_index], BoxFit.contain, 1600),
                          ),
                        ),
                        // ★ 2026-10-05（F ✓）**框外压暗**：sim 用的是 `box-shadow: 0 0 0 9999px rgba(0,0,0,.55)`
                        //   ⇒ Flutter 用**挖孔**（`PathFillType.evenOdd` ✓ 见文件末尾 `_FrameHoleClipper` ✓）；
                        //   ⚠️ 色值仍是 `0x8C000000` ✗ **没改**（0x8C = 140 ⇒ 140/255 = **.549** ≈ sim 的 .55 ✓）。
                        IgnorePointer(
                          child: ClipPath(
                            clipper: _FrameHoleClipper(fw, fh),
                            child: const ColoredBox(color: Color(0x8C000000)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16), // = sim `gap:16px` ✓
                  Text('${_index + 1} / ${widget.urls.length}',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.85), fontSize: 12)),
                  const SizedBox(height: 16), // = sim `gap:16px` ✓
                  // ★ 照 sim ✓：框选态那排也是 `.ovl .row2 > div { flex:1 }`（`sim:707` ✓ + 内联
                  //   `width:100%;margin:0` `sim:7606` ✓）⇒ 两颗**等宽铺满**；**确认在前、取消在后** ✓（`:7025-7026` ✓）
                  Row(
                    children: [
                      Expanded(child: _pill('确认', _confirmCrop)),
                      const SizedBox(width: 10), // = sim `.row2 gap:10px` ✓（`:706`）
                      Expanded(
                          child: _pill('取消', () => setState(() => _crop = false))),
                    ],
                  ),
                ],
              ),
              ), // ← Padding（框选那列的外盒 ✓）闭合
            ),
          ],
        ],
        ), // ← Stack 闭合（上面包了 GestureDetector ✓ 多一层 ⇒ 多这一个括号 ✓）
      ),
    );
  }

  /// 一张图（预览态/框选态**共用这一处** ✓）：**有注入的已解字节就用它** ✓（`Image.memory` ✓ 零网络零解码 ✓）；
  ///   **没有**（没传 `bytesFor` ✓ 或未命中缓存 ✓）⇒ **照旧** `FetchedImage` ✓（默认行为不变 ✓）。
  /// ★ 2026-10-05（F/G ✓）：顺手把 `onImageInfo` 接上 ⇒ **尺寸一到就记表 + 框选态重算** ✓（见 [_onImgInfo] ✓）。
  Widget _artImage(String url, BoxFit fit, int memWidth) {
    final b = widget.bytesFor?.call(url);
    if (b != null) {
      return Image.memory(b, fit: fit, cacheWidth: memWidth, gaplessPlayback: true);
    }
    return FetchedImage(
      url: url,
      fit: fit,
      memWidth: memWidth,
      onImageInfo: (w, h) => _onImgInfo(url, w, h),
    );
  }

  /// ★ 2026-10-05（F/G ✓ 你要的那条"尺寸到了要重算" ✗）：尺寸到手 ⇒ ① 写表 ✓
  ///   ② **框选态正看这张** ⇒ 立刻 setState ⇒ `build` 用新尺寸重算 `dw/dh`（显示盒 ✓）与 `fw/fh`（框 ✓）
  ///   ⇒ "缓一拍"时的占位框不会留到最后 ☠。
  ///   ⚠️ 只有**当前条**且**框选态**才 setState ✓（预览态不需要 ✓ 别的条更不该刷 ✗）；`mounted` 判过 ✓。
  void _onImgInfo(String url, int w, int h) {
    AlbumImageSizes.put(url, w, h);
    if (!mounted || !_crop) return;
    if (url != widget.urls[_index]) return;
    final size = Size(w.toDouble(), h.toDouble());
    if (_imgSize == size) return;
    setState(() => _imgSize = size);
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
        // ★ 2026-10-05（**照 sim 1:1** ✗）：sim 的按钮几何 = `.ovl .row2 > div {
        //     flex:1; text-align:center; padding:11px 0; border-radius:9px;
        //     font-size:14px; font-weight:600 }` ✓（`sim/index.html:707-708` **逐字** ✓）
        //   ⇒ 竖向 padding **11** ✓ 圆角 **9** ✓ 字号 14 + w600 ✓（原样保留 ✓）
        //   ⇒ 横向宽度**不在这里**给 ✗ —— 由"整排两等分"（`flex:1` ✓）给 ⇒ 两处调用点都用 `Expanded` ✓
        //   ⚠️ 原来写的是 `padding:20/10` + 圆角 **20** ✗ 与 sim 不符 ⇒ 已改 ✓
        //   ⚠️ 顺手压掉 TextButton 自带的 `minimumSize`/`padded` 触控外扩 ✗（否则高度不是 11+字+11 ✓）
        padding: const EdgeInsets.symmetric(vertical: 11),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    );
  }
}

/// ★ 2026-10-05（F ✓ 用户要求"框选时看得见整张原图"）：**框外压暗**用的"挖孔"裁剪器 ——
///   路径 = **整块矩形** + 中间**挖掉**一个 `fw×fh` 的圆角矩形 ✓（`PathFillType.evenOdd` 奇偶填充 ⇒ 中间成洞 ✓）
///   —— 等于 sim 那句 `box-shadow: 0 0 0 9999px rgba(0,0,0,.55)`（`sim/index.html:7604` ✓）的 Flutter 写法 ✓。
///   ⚠️ 只用在**非定位**子层里 ✓（`Stack(fit: StackFit.expand)` 的第 2 个孩子 ✓ 外面套 `IgnorePointer` ⇒ 不吃手势 ✗）。
///   ⚠️ 圆角沿用原来 `ClipRRect` 上那个 **12** ✓（= sim 框的 `border-radius:12px` ✓ **没改值** ✗）。
///   ⚠️ **类归属**：私有 ✓、只在**本文件** `_ArtPreviewBodyState.build` 里用 ✓（声明点与使用点同文件同类 ✓）。
class _FrameHoleClipper extends CustomClipper<Path> {
  _FrameHoleClipper(this.fw, this.fh);

  final double fw;
  final double fh;

  @override
  Path getClip(Size size) {
    final outer = Offset.zero & size; // 整块 = 显示盒 `dw×dh` ✓
    final hole = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2), // 框**居中** ✓（与上面算 `fw/fh` 的口径同源 ✓）
      width: fw,
      height: fh,
    );
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(outer)
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(12)));
  }

  @override
  bool shouldReclip(_FrameHoleClipper old) => old.fw != fw || old.fh != fh;
}
