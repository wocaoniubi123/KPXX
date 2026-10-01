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
          Image(
            image: AppBg.i.image,
            fit: BoxFit.cover,
            gaplessPlayback: true, // 换图时别闪白
            // 背景图解码尺寸已在选图/打包时限制过，这里不再额外处理
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
