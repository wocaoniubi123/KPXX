// 底座：**站点专属 UI 事实**的统一接口 ✓
//
// ⚠️ 用户 2026-10-03 决策：站点相关的一切（含分类/标签选择器 UI、重置按钮、选中状态 ✓）
//    都改成**站点独立专属** ✓；底座只留公用部分 ✓。
//
// ✅ 这个文件就是"站点 UI 事实"的**唯一入口**：
//    - 每个站点类 `implements SiteUi` ✓，**只覆盖自己那条** ✓；
//    - 默认值就是"没有这个特性" ✓ → **不涉及该特性的站点一行都不用写** ✓；
//    - `home_page` 只读 `api.ui?.xxx ?? 默认值` ✓ —— ✅ **行为与改造前完全一致** ✓
//      （因为默认值 = 改造前"不是这个模板就 false/null"的判断 ✓）。
//
// ⚠️ 这里**故意不 import flutter** ✗ —— 全是纯 Dart 的布尔事实 ✓，
//    这样各站点文件不必因为本接口而引入 material ✓（widget 级的筛选行留到后续单独做 ✓）。

/// 站点专属 UI 事实（各站只覆盖自己那条 ✓）
abstract class SiteUi {
  /// 列表是否走**瀑布流**（逐条按分辨率混排，不留空档）—— Pektino ✓
  bool get masonry => false;

  /// "色情明星"tab 的卡片是不是**竖版头像**（→ 一行 3 个）—— Pornhub / xHamster ✓
  bool get portraitStarCards => false;

  /// "色情明星"tab 是否挂**专用筛选行**（排序/类型/时间/更多 ✓）—— Pornhub / xHamster ✓
  bool get hasStarFilterRow => false;

  /// 列表页是否挂**本站筛选行**（照站点的那几个下拉 ✓）—— Hanime1 ✓
  bool get hasFilterRow => false;
}
