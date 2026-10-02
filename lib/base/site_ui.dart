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

  /// **本站**的「色情明星列表」判定（决定那类 tab 是否按竖版头像卡渲染 ✓）
  ///
  /// ⚠️ 注意各家规则**不一样** ✗：Pornhub 只认 `/pornstars` ✓；
  /// xHamster 还认 `/pornstars/all/…`、`/pornstars/top/…` ✓。
  /// ✅ 所以这里给的是**站点自己的判定函数** ✓，而不是一个合并的布尔 ✗
  /// （合并会让 Pornhub 多匹配 all/top ✗ = 改变行为 ✓）。
  bool isStarList(String slug) => false;

  /// 「色情明星」tab 挂**哪种**专用筛选行：`ph` = Pornhub 那套 ✓；`xh` = xHamster 那套 ✓。
  /// ⚠️ 两家是**两个不同的 widget** ✗ → 不能用同一个布尔 ✓，所以这里给"是哪家" ✓。
  String? get starRowKind => null;

  /// 这个 tab key 是不是"短片"路径（xHamster 的 `/shorts*` ✓）——
  /// 选中短片 tab 时要重置短片随机种子 ✓。
  bool isShortsPath(String key) => false;

  /// 分类选择器是否按**分组**展示（xHamster 有 40 个演员分类分组 ✓）。
  bool get hasCatGroups => false;
  /// 列表页是否挂**本站筛选行**（照站点的那几个下拉 ✓）—— Hanime1 ✓
  bool get hasFilterRow => false;
}
