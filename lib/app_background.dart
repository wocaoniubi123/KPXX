import 'package:flutter/widgets.dart';

import 'app_bg.dart';

/// 全屏背景层：铺在**整棵页面树的最底下**（含顶栏/底栏/状态栏区域）。
///
/// 配套约定（少一条就会"背景只在某一页可见"）：
/// 1. 背景图放 Stack 的第一层、页面放第二层 —— Flutter 里后画的在上面，
///    所以不会出现 Web 那种"背景盖住内容"的层叠坑（那边要额外加 z-index）。
/// 2. 页面自己必须透明：见 main.dart 的 theme（scaffold / appBar / 底栏都设成
///    Colors.transparent）。**不透明底色在哪一层，背景就会在哪一层断掉。**
/// 3. 图**不压任何白纱/蒙版** —— 用户明确嫌"发白"，可读性靠文字描边解决
///    （见 main.dart 的 kTextHalo）。
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

/// 文字描边（白色光晕）。**只加给字，不动背景图** —— 这样换任何一张背景都看得清，
/// 又不会把图冲淡。参数是照模拟器里调过的那套（用户先嫌"泡白"、又嫌"晃眼"）。
const List<Shadow> kTextHalo = [
  Shadow(color: Color(0xC7FFFFFF), blurRadius: 1),
  Shadow(color: Color(0x61FFFFFF), blurRadius: 2.5),
  Shadow(color: Color(0x1A000000), offset: Offset(0, 1), blurRadius: 1),
];

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
