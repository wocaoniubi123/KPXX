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

  /// 从**详情页 HTML** 里挖出播放源（各站自己解析 ✓）。
  ///
  /// 返回 `null` = 用**通用做法**（找页面里的 `.dplayer[data-config]` 配置 ✓）；
  /// 返回列表（可为空）= 本站自己解析（**不再走通用路径** ✓）。
  /// ⚠️ 原先这段逻辑在共享的 `_fetchSourcesAt` 里按模板 if 分叉 ✗ ——
  /// 那正是"站点逻辑散在公用函数里"的典型 ✓，现在下放给站点 ✓。
  List<String>? sourcesFromHtml(String html) => null;

  // ===== 分发：各站自己实现（并集签名 ✓ —— 用不到的参数忽略即可 ✓）=====
  //
  // ⚠️ 为什么是"并集签名"：各站参数天然不同 ✗（有的要 k、有的要 theme、有的要 home 回调 ✓），
  //    而 Dart 的覆写要求子类具名参数不能比父类少 ✗ → 这里给出**全集** ✓，各站按需取用 ✓。
  //
  // ✅ 它取代了 `Api` 里原来的 5 个 `switch (site.template)`（50 个 case ✓，每个都只是一行委托 ✓）。
  // ⚠️ 各站实现时**必须保持原语义**：把并集参数重新绑定回原来的名字 ✓（见各站的 `kk`/`home!` ✓）。

  /// 「分类」tab 列表。
  /// `k` = 子分类解析后的 key（原先是**位置参数** ✗，现在挪到具名 ✓）；
  /// `home` = 「首页」兜底回调（仅个别站用 ✓，原先对它们必填 ✗ 现在是可空 ✓）。
  Future<List<Article>> category(String key,
          {required int page,
          String? k,
          String? theme,
          String? duration,
          String? sort,
          List<MapEntry<String, String>>? extra,
          Future<List<Article>> Function({int page})? home}) =>
      throw UnimplementedError();

  /// 首页最新列表（`first` = 站点第一个分类 key ✓，原对 3 个站是位置参数 ✗，现统一具名 ✓）
  Future<List<Article>> home({required int page, String first = ''}) => throw UnimplementedError();

  /// 标签列表页
  Future<List<Article>> tag(String slug, {required int page}) => throw UnimplementedError();

  /// 搜索
  Future<List<Article>> search(String keyword,
          {int page = 1, List<MapEntry<String, String>>? extra}) =>
      throw UnimplementedError();

  /// 文章详情
  Future<ArticleDetail> detail(String url) => throw UnimplementedError();
  /// 「色情明星」tab 挂**哪种**专用筛选行：`ph` = Pornhub 那套 ✓；`xh` = xHamster 那套 ✓。
  /// ⚠️ 两家是**两个不同的 widget** ✗ → 不能用同一个布尔 ✓，所以这里给"是哪家" ✓。
  String? get starRowKind => null;

  /// 这个 tab key 是不是"短片"路径（xHamster 的 `/shorts*` ✓）——
  /// 选中短片 tab 时要重置短片随机种子 ✓。
  bool isShortsPath(String key) => false;

  /// 点这张卡的**特殊去向**：`null` = 走详情页 ✓
  /// `list` = 进"他/她的视频列表"页（TagListPage ✓）· `shorts` = 进竖屏短片瀑布流 ✓。
  ///
  /// ⚠️ 各站判定**不同** ✗，所以判定本身下放到站点 ✓（不是在 UI 里 if 模板 ✓）。
  String? specialTap(String url) => null;

  /// 分类选择器是否按**分组**展示（xHamster 有 40 个演员分类分组 ✓）。
  bool get hasCatGroups => false;
  /// 列表页是否挂**本站筛选行**（照站点的那几个下拉 ✓）—— Hanime1 ✓
  bool get hasFilterRow => false;

  /// **这个 tab** 是否挂筛选行（比站点级的 [hasFilterRow] 更细 ✓）。
  /// 默认 true = "每个 tab 都挂"（多数站点如此 ✓）；
  /// 只有特定站点才限制到某几个 tab ✓（Pornhub 只挂 `/video` ✓，xHamster 只挂 `/categories/*` ✓）。
  bool showsFilterRow(String key, {required bool hasSubs}) => true;

  /// 这个 key 是不是本站的「色情明星」tab ✓（各家 slug 相同但**归属判定**不同 ✗）。
  bool isStarTabKey(String key) => false;

  /// 本站有没有「色情明星」tab（决定要不要维护它的 feed key 前缀 ✓）。
  bool get hasStarTab => false;

  /// 「色情明星」tab 的选中项是否走 `extra` 参数（Pornhub 那四个筛选拼查询串 ✓）。
  bool get starUsesExtra => false;
}
