/// ★ 2026-11-08（用户拍板「方案 A · 全局一处」+「基准宽度按照 iOS 的来」+「按你推荐的」）
///
/// **安卓专属的「设计画布」**：把整个 App 按真实屏宽等比缩放到 iOS 设计基准。
///
/// 🛢️ 要解决什么（本机实测，2026-11-08）：
///   · 本仓库的 UI **全部是固定 dp** —— 固定 `fontSize: 数字` **221 处**、
///     `fontSize` 用变量的只有 **3 处**、固定 `width: 数字` **121 处**、固定 `height: 数字` **159 处**；
///     `MediaQuery` 覆盖 / `textScaler` 拦截 **0 处** ⇒ 没有任何按屏宽自适应的东西。
///   · ⇒ 观感完全由「设备逻辑宽度」决定。设计基准宽 **440**（依据见 [kDesignWidth]）时：
///       4 列宫格格子 = (440−20−24)/4 = **99dp**，62dp 图标占 **62.6%** —— 这是 iPhone 上的样子 ✅
///   · 用户实测的安卓机逻辑宽 ≈ **385dp**（从截图反推：4 列图标左边界 30/168/305/441px、
///     图标 91px、截图宽 565px ⇒ 62dp × 565 ÷ 91 = **385dp**，且列距 137px 交叉核对吻合）
///     ⇒ 格子 85.3dp、图标占 **72.7%** ⇒ 比 iPhone 上大 **16%**，整 App 等比放大 **1.14 倍** ☠
///
/// ✅ 机制（依据 Flutter 3.47.6 源码，不是推测）：
///   · `packages/flutter/lib/src/widgets/app.dart:369` 原文：
///       `'WidgetsApp never introduces its own MediaQuery; the View widget takes care of that.'`
///   · `packages/flutter/lib/src/widgets/view.dart:275`：
///       `child: MediaQuery.fromView(` ← **根 MediaQuery 只在 View 里产生，位于 MaterialApp 之上**
///   ⇒ 只要我们在 `View` 之下插一层自己的 `MediaQuery`，它一定生效、不会被冲掉 ✅
///
/// ✅ 做法：告诉 App「你的屏是 designW × designH」，再用 [FittedBox] 把绘制结果缩回真实屏。
///   于是 221 处字号、280 处固定宽高、62dp 图标**全部按同一系数回缩**，一处改动、所有页面生效 ✅
///
/// ⚠️ **只对 Android 生效**：`Platform.isAndroid` 为假时**原样返回 child** ⇒
///   iOS / Windows 桌面**逐字节不变**（用户硬性要求：不动手机端以外的既有表现）✅
/// ⚠️ 宽 ≥ 440dp 的设备（平板 / 横屏 / Fold 内屏 619~692dp）**不缩放**，保持现状 ✅
library;

// ⚠️ `library;` 必须在**所有其它指令之前**（analyzer: library_directive_not_first ☠）
//   ⇒ 文件级文档注释写在它上面，import 一律放在它下面 ✅
import 'dart:io' show Platform;
// ★ 2026-11-09：`DisplayFeature`（折叠屏铰链/挖孔）在 `dart:ui`，**不在** flutter/widgets 里
//   `show` 只取这一个符号 ⇒ 不会和 widgets 的其它名字撞名 ✅
import 'dart:ui' show DisplayFeature;

import 'package:flutter/widgets.dart';

/// 设计基准宽度 = 本项目唯一的 iOS 设计基准。
///
/// 依据（实锤）：
///   · `lib/main_win_dev.dart:321` → `dp.applyPreset(DevicePresets.iPhone16ProMax)`
///   · `device_preview` 的 `lib/src/presets.g.dart` 里该 preset =
///     `portraitSize: Size(440, 956)`、`devicePixelRatio: 3.0`
///   ⇒ 仓库里所有固定 dp 尺寸都是在这个 440pt 宽的画面下调出来的 ✅
const double kDesignWidth = 440.0;

/// 缩放下限（用户拍板「按你推荐的」= 采纳这条）。
///
/// 依据：2026 主流安卓机型逻辑宽度实测统计（screensizechecker Android 视口表，复核 2026-09-24）——
///   · 主流手机集中在 **410~414dp**（Pixel 全系 410/412/414、Galaxy S2x Ultra/Plus 412、
///     小米 15 Pro 412、华为 Mate 70 Pro 411、HONOR Magic7 Pro 400、OPPO Find X8 Pro 395、vivo X200 Pro 394）
///   · 次一档 **360dp**（Galaxy S25/S24/S23 标准版）、Galaxy S23+ 384、Z Flip6 393
///   · **折叠屏外屏很窄**：Galaxy Z Fold6 外屏 **323dp**（内屏 619dp、Pixel 10 Pro Fold 内屏 692dp）
///   ⇒ 323dp 严格等比会缩到 0.734（缩 27%）⇒ 字小得难受 ☠
///   ⇒ 加下限 0.80：Fold 外屏只缩 20%，而 360dp 及以上（0.818~0.94）**完全不受影响** ✅
const double kMinCanvasScale = 0.80;

/// 画布参数（真实屏 → 画布逻辑尺寸）
@immutable
class CanvasMetrics {
  /// 绘制缩放系数（0.80 ~ 1.0）
  final double scale;

  /// 画布逻辑宽 = 真实宽 / [scale]
  final double designW;

  /// 画布逻辑高 = 真实高 / [scale]
  final double designH;

  const CanvasMetrics(this.scale, this.designW, this.designH);

  @override
  String toString() =>
      'CanvasMetrics(scale=${scale.toStringAsFixed(4)}, '
      'designW=${designW.toStringAsFixed(2)}, designH=${designH.toStringAsFixed(2)})';
}

/// 纯计算：给定真实逻辑尺寸，算出画布参数；**返回 `null` = 不需要缩放**。
///
/// 抽成纯函数是为了能脱离 BuildContext 核对数值（无副作用、不读平台）。
///
/// ★ 2026-11-09（用户要求「隐患都修」）：**基准取「短边」而不是「宽」**。
///   🛢️ 为什么改（旧口径的问题，用户实报后才暴露）：
///     · 旧口径 `raw = real.width / 440` ⇒ 竖屏 385 缩 0.875，**横屏 684 ≥ 440 ⇒ 完全不缩**
///       ⇒ 同一个控件在竖屏变小、横屏又变大（横屏比竖屏"看起来大 14%"）☠ 方向不一致
///     · 改用短边后：竖屏 min=385 ⇒ 0.875；横屏 min=385 ⇒ **同样 0.875**
///       ⇒ 横竖屏控件**物理大小一致** ✅（视频全屏那种横屏场景也一并受益）
///   ✅ 与旧口径的关系：**竖屏结果完全相同**（竖屏时 min 就是宽度）⇒ 竖屏观感零变化 ✅
///   ✅ 平板/Fold 内屏（如 800×1280、619×720）短边 ≥440 ⇒ 仍**不缩放** ✅
/// ⚠️ 注意 `designW` 不恒等于 [kDesignWidth]：被 [kMinCanvasScale] 夹住时会小于它
///   （例：短边 323dp ⇒ scale=0.80 ⇒ designW=403.75），这样「缩放系数」与「画布尺寸」始终自洽 ✅
///   ⚠️ 横屏时 `designW` 会明显大于 [kDesignWidth]（684/0.875 = 781.7），这是**对的**：
///     画布宽高比恒等于真实宽高比，不会变形。
@visibleForTesting
CanvasMetrics? canvasMetricsFor(Size real) {
  if (real.width <= 0 || real.height <= 0) return null;
  // 短边 = 基准（横竖屏都按它算 ⇒ 两向观感一致）
  final shortSide = real.width < real.height ? real.width : real.height;
  final raw = shortSide / kDesignWidth;
  if (raw >= 1.0) return null; // 短边 ≥ 基准 ⇒ 不缩（平板 / Fold 内屏 / 大屏横屏）
  final scale = raw < kMinCanvasScale ? kMinCanvasScale : raw;
  return CanvasMetrics(scale, real.width / scale, real.height / scale);
}

/// 安卓专属设计画布：把「固定 dp 布局」等比缩放到 iOS 设计基准。
///
/// 用法（见 `lib/main.dart`）：`runApp(const DesignCanvas(child: KpxxApp()));`
class DesignCanvas extends StatelessWidget {
  final Widget child;

  const DesignCanvas({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // ⚠️ iOS / Windows 桌面 / 其它平台：**原样返回**，一行都不缩放（逐字节不变）✅
    //   `Platform.isAndroid` 是**运行期恒定**的 ⇒ 这条早返回不会在运行中来回切换 ✅
    if (!Platform.isAndroid) return child;

    final mq = MediaQuery.of(context);
    final m = canvasMetricsFor(mq.size);

    // 🛢️🛢️ 2026-11-09（用户实报「安卓点横版全屏直接跳回首页点播」）——
    //   **这里绝对不能再 `if (m == null) return child;`**。
    //   根因（日志 + 代码双向确认）：
    //     · 竖屏 385dp ⇒ 走「FittedBox 分支」；全屏强制横屏后宽 ≈684dp ≥ 440
    //       ⇒ 走「直接 return child 分支」⇒ **同一位置换了 widget 类型**
    //     ⇒ Flutter 销毁旧 Element 子树 ⇒ MaterialApp / Navigator / RootPage 全部重建
    //     ⇒ 新 Navigator 从 `home` 起 ⇒ `RootPage._index = 0` = **点播**（`main.dart:295`）
    //   现场日志（1.7.2 安卓，用户提交）时间正序：
    //     `[PLAY] 控件按钮按下 icon=58059`（点全屏）→ `[NAV] → PageRouteBuilder<Object?>`
    //     → `[PLAY] 全屏 转场状态=AnimationStatus.forward`（开始旋屏）
    //     → **`[NAV] → /`** → `[DETAIL] dispose` / `[PLAY] PlayerWidget.dispose`
    //   为什么只有安卓：iOS / Windows 走上面那条早返回 ⇒ 结构恒定 ⇒ 从不出事 ✅
    //   ✅ 修法：**结构必须与「要不要缩放」无关** —— 永远返回同一套
    //     `FittedBox → SizedBox → MediaQuery`；不需要缩放时 `scale = 1.0`、
    //     `designW/H = 真实宽高` ⇒ 数学上等价于原样，但 widget 类型不再变化 ⇒ Navigator 保住状态 ✅
    final double scale = m?.scale ?? 1.0;
    final double designW = m?.designW ?? mq.size.width;
    final double designH = m?.designH ?? mq.size.height;

    // 边距类数据必须按同一系数换算，否则状态栏/刘海/键盘避让会错位 ☠
    // ⚠️ scale == 1.0 时**原样返回**（不做除法，避免 1.0 除法的无意义误差）
    EdgeInsets s(EdgeInsets e) => scale == 1.0
        ? e
        : EdgeInsets.fromLTRB(
            e.left / scale,
            e.top / scale,
            e.right / scale,
            e.bottom / scale,
          );

    // ★ 2026-11-09（用户要求「隐患都修」）：**折叠屏铰链/挖孔也要换算**。
    //   🛢️ 为什么：`MediaQueryData.displayFeatures` 里的 `bounds` 同样是「真实逻辑像素」，
    //     不按 scale 换算 ⇒ 在折叠屏上铰链位置会偏（其它空间类字段 size/padding/viewInsets/
    //     viewPadding/systemGestureInsets 都已经换算了，就这个漏了）。
    //   ⚠️ 本仓目前没有手写使用 displayFeatures 的地方，但第三方控件/框架内部可能会读
    //     ⇒ 补齐这一项，避免以后上折叠屏出玄学问题 ✅
    final features = mq.displayFeatures;
    final scaledFeatures = scale == 1.0
        ? features
        : <DisplayFeature>[
            for (final f in features)
              DisplayFeature(
                bounds: Rect.fromLTRB(
                  f.bounds.left / scale,
                  f.bounds.top / scale,
                  f.bounds.right / scale,
                  f.bounds.bottom / scale,
                ),
                // cutout 类型要求 state 必须是 unknown（dart:ui 里的 assert）⇒ 原样透传最安全
                type: f.type,
                state: f.state,
              ),
          ];

    return FittedBox(
      // designH 是用同一个 scale 反算出来的 ⇒ 横纵缩放比严格相等（不会变形）✅
      // scale == 1.0 时 child 尺寸 == 可用尺寸 ⇒ 恒等变换（相当于没缩）✅
      fit: BoxFit.fill,
      child: SizedBox(
        width: designW,
        height: designH,
        child: MediaQuery(
          data: mq.copyWith(
            size: Size(designW, designH),
            // 每个「画布 dp」对应的物理像素 = 真实 dpr × scale ⇒ 图片按物理分辨率解码，不降清晰度 ✅
            devicePixelRatio: mq.devicePixelRatio * scale,
            padding: s(mq.padding), // 状态栏 / 刘海
            viewPadding: s(mq.viewPadding), // 键盘弹起时仍保留的系统栏
            viewInsets: s(mq.viewInsets), // 键盘高度（不换算 ⇒ 输入框避让错位）
            systemGestureInsets: s(mq.systemGestureInsets), // 手势条
            displayFeatures: scaledFeatures, // 折叠屏铰链 / 挖孔
          ),
          child: child,
        ),
      ),
    );
  }
}
