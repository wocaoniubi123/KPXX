import 'package:flutter/material.dart';
// ⚠️ `SystemUiOverlayStyle` 在 services 库里 —— **material.dart 不导出它**
// （2026-10-02 我漏了这个 import，CI 直接报 "Type 'SystemUiOverlayStyle' not found"）。
import 'package:flutter/services.dart';

import 'app_bg.dart';

/// 全屏背景层：铺在**整棵页面树的最底下**（含顶栏/底栏/状态栏区域）。
///
/// 配套约定（少一条就会"背景只在某一页可见"）：
/// 1. 背景图放 Stack 的第一层、页面放第二层 —— Flutter 里后画的在上面，
///    所以不会出现 Web 那种"背景盖住内容"的层叠坑（那边要额外加 z-index）。
/// 2. 页面自己必须透明：见 main.dart 的 theme（scaffold / appBar / 底栏都设成
///    Colors.transparent）。**不透明底色在哪一层，背景就会在哪一层断掉。**
/// 3. 图**不压任何白纱/蒙版** —— 用户明确嫌"发白"；可读性靠**按背景明暗自适应
///    黑白字**解决（见下面的 kTxt / kTxtSub / kChipBorder），不加描边/光晕。
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          // ⚠️ 背景图必须单独一个 repaint 层：它和 Navigator 同在一个 Stack 里，
          // 不隔离的话每次转场（push/pop 每帧）都要把这张全屏大图重新 raster，
          // 表现就是"点了没反应、过一会儿才慢慢切过去"（用户实测 0.5s 卡顿）。
          RepaintBoundary(
            child: Image(
              image: AppBg.i.image,
              fit: BoxFit.cover,
              gaplessPlayback: true, // 换图时别闪白
              // 背景图解码尺寸已在选图/打包时限制过，这里不再额外处理
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// 直接浮在背景图上的文字色：深色图→白、浅色图→深（照模拟器 `.darkbg` 那套）。
///
/// **只给"直接贴图"的字用**：字压在自己底色上的（白底卡片 / 分段控件 / 带底色按钮 /
/// 输入框 / 图标方块里的字 / 播放器覆盖层）一律别用，翻了就看不清。
///
/// ⚠️ 这只是取值，不会自己触发重建：读它的控件要挂在 `AppBg.i` 上
/// （`ListenableBuilder` 或已有的 merged `Listenable`）才会随明暗刷新。
Color get kTxt => AppBg.i.isDark ? Colors.white : const Color(0xFF1B1B1F);

/// 次级文字（说明/时间/站点名等）：深色图上不用纯白，柔一档
Color get kTxtSub =>
    AppBg.i.isDark ? const Color(0xFFE8E8EC) : const Color(0xFF3B4250);

/// 描边胶囊的边框（未选中态）：深色图上深边框看不见，转浅
Color get kChipBorder =>
    AppBg.i.isDark ? const Color(0x8CFFFFFF) : const Color(0x593C3C3C);

/// **状态栏**（iOS 系统画的时间/信号/电量）的图标样式：跟着背景明暗走。
///
/// ⚠️ 2026-10-02 用户实测报的 bug：切浅色（甚至纯白）背景图时，页内文字跟着变黑了，
/// 但**状态栏还是白的** → 白压白、一片空白；深色图那边也一直白着没变。
///
/// 根因：我们的 AppBar 全是 `Colors.transparent`（好让背景图透上来），而 Flutter 的
/// AppBar 会**按自己背景色的亮度**推断状态栏样式 —— `Colors.transparent` 的亮度算
/// **0（深色）** → 它把状态栏图标刷成**白色**。而且 AppBar 自己那个
/// `AnnotatedRegion<SystemUiOverlayStyle>` 会**盖过**命令式的
/// `SystemChrome.setSystemUIOverlayStyle`，所以只能**逐个 AppBar 显式传**这个值。
/// （`app_bg.dart` 里那次命令式设置保留着，当没有 AppBar 的页面/启动阶段的兜底。）
///
/// 语义提醒：`SystemUiOverlayStyle.light` = **白色内容**、`.dark` = **深色内容**；
/// iOS 侧真正生效的是 `statusBarBrightness`（那个字段是**反的**：dark = 白色内容）。
SystemUiOverlayStyle get kStatusOverlay =>
    AppBg.i.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;

/// **每个被 push 的页面都要套这一层。**
///
/// 为什么需要：转场时靠"新页面自己不透明"来盖住旧页面。而全 App 的 Scaffold 都设成了
/// `Colors.transparent`（为了让背景图透出来）→ 新页面盖不住旧页面，两个页面直接叠在
/// 一起（用户实测截图：设置页和播放记录页文字/进度条全部重影，看着像"卡半秒 + 闪"）。
///
/// 解法：让每个页面自己铺一层**同一张**背景图（`AppBg.i.image` 已有 ImageCache，
/// 不会重复解码），这样转场期间新页面是实心的、旧页面被真正挡住，
/// 页面内部的透明控件照旧能看到图。
class PageBg extends StatelessWidget {
  final Widget child;
  const PageBg({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: Image(
              image: AppBg.i.image,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
          child,
        ],
      ),
    );
  }
}
