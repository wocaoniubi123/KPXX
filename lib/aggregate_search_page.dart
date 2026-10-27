// 聚合搜索（★ 2026-10-22 用户要求）：
//   · 入口：点播页（`ModuleGridPage`）右上角的搜索按钮；
//   · 布局：顶部输入框 → **左侧竖排导航**（全部站点 + 各站点） + 右侧结果列表；
//   · 数据：并行调 `Api(site).search(kw, page: 1)`（每站点第 1 页），按站点分组缓存；
//   · 卡片：复用全站共用卡片 `ArticleCard`（点击导航/样式与首页一致 ✅）。
import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'app_background.dart';
import 'home_page.dart' show ArticleCard, RowsGrid;
import 'models.dart';
import 'settings.dart';
import 'site_admin.dart' show visibleSitesOf;
import 'sites.dart';

class AggregateSearchPage extends StatefulWidget {
  const AggregateSearchPage({super.key});

  @override
  State<AggregateSearchPage> createState() => _AggregateSearchPageState();
}

class _AggregateSearchPageState extends State<AggregateSearchPage> {
  final TextEditingController _ctl = TextEditingController();
  final FocusNode _focus = FocusNode();

  // ★ 2026-10-28（用户要求：本页也自动升起键盘）—— 与站点搜索页同款状态
  bool _focusScheduled = false; // 转场后聚焦只安排一次
  Animation<double>? _focusAnim; // 挂过监听的转场动画（dispose 要摘）
  Timer? _focusTimer; // 延迟聚焦的定时器（dispose 要取消）

  /// 参与聚合的站点：点播组、可见（顺序与点播页一致）
  late final List<SiteEntry> _sites = visibleSitesOf(SiteGroup.module);

  /// 每个站点的结果（null/缺键 = 还没搜；空数组 = 搜过没结果）
  final Map<String, List<Article>> _results = {};

  /// 每个站点的状态：'loading' / 'ok' / 'fail'
  final Map<String, String> _state = {};

  String _kw = '';

  /// ★ 2026-10-22（自动翻页）：用 `ScrollController` 监听"距底 300px" ⇒ 比
  ///   `NotificationListener` 可靠（后者依赖通知冒泡，实测没触发）
  final ScrollController _sc = ScrollController();

  /// -1 = 全部站点；>=0 = `_sites[_sel]`
  int _sel = -1;

  /// ★ 2026-10-22（用户要求自动翻页）：每站点已加载到第几页 / 是否到底 / 正在加载更多
  final Map<String, int> _page = {};
  final Map<String, bool> _noMore = {};
  bool _loadingMore = false;

  Future<void> _search() async {
    final kw = _ctl.text.trim();
    if (kw.isEmpty) return;
    // ★ 2026-10-22（用户要求：搜索记录持久化）：提交就记一条（去重 / 最近在前 / 上限 20）
    unawaited(SearchHistory.i.add(kw));
    final sites = _sites;
    setState(() {
      _kw = kw;
      _results.clear();
      _state.clear();
      for (final s in sites) {
        _state[s.name] = 'loading';
      }
      _sel = -1; // 默认看「全部站点」
      _noMore.clear();
      for (final s in sites) {
        _page[s.name] = 1; // 首屏第 1 页
      }
    });
    if (AppSettings.i.logConsole) {
      debugPrint('[AGG] 聚合搜索 站数=${sites.length} kwLen=${kw.length}');
    }
    // 并行搜索（每站点第 1 页）
    await Future.wait(sites.map((s) async {
      try {
        final r = await Api(site: s).search(kw, page: 1);
        if (!mounted) return;
        setState(() {
          _results[s.name] = r;
          _state[s.name] = 'ok';
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _results[s.name] = const <Article>[];
          _state[s.name] = 'fail';
        });
      }
    }));
  }

  /// ★ 2026-10-22（用户要求）：**滚动到底 ⇒ 自动翻页**。
  ///   · 单站点：只给那一站加下一页；
  ///   · 全部站点：每个"还有更多且已成功"的站点各加一页，合并显示；
  ///   · 某站点返回空 / 请求失败 ⇒ 标记 `_noMore`，不再自动拉它。
  Future<void> _loadMore() async {
    if (_kw.isEmpty || _loadingMore) return;
    // ★ 2026-10-22 **真正的 bug**（日志实测：`sel=11 名字=Pornhub` 但目标恒为 0）：
    //   原来用 collection-if 写成
    //     `[if (_sel < 0) for (s in _sites) if (...) s else if (...) _sites[_sel]]`
    //   ⇒ **`else if` 绑定到了 `for` 里那个 `if`**（不是外层的 `if (_sel < 0)`）☠
    //   ⇒ 单站点模式下外层 `if (_sel < 0)` 为 false ⇒ 整段**不产出任何元素** ⇒ targets 恒空、永不翻页。
    //   ⇒ 改成显式 if/else 组装，语义不再依赖 collection-if 的绑定规则。
    final List<SiteEntry> targets;
    if (_sel < 0) {
      targets = <SiteEntry>[
        for (final s in _sites)
          if (!(_noMore[s.name] ?? false)) s,
      ];
    } else {
      final s = _sites[_sel];
      targets = (_noMore[s.name] ?? false) ? const <SiteEntry>[] : <SiteEntry>[s];
    }
    if (targets.isEmpty) return;
    _loadingMore = true;
    try {
      await Future.wait(targets.map((s) async {
        final next = (_page[s.name] ?? 1) + 1;
        try {
          final r = await Api(site: s).search(_kw, page: next);
          if (!mounted) return;
          setState(() {
            if (r.isEmpty) {
              _noMore[s.name] = true; // 这一站到底
            } else {
              _page[s.name] = next;
              _results[s.name] =
                  <Article>[...(_results[s.name] ?? const <Article>[]), ...r];
            }
          });
        } catch (_) {
          if (mounted) setState(() => _noMore[s.name] = true);
        }
      }));
    } finally {
      _loadingMore = false;
    }
  }

  @override
  void initState() {
    super.initState();
    // ★ 2026-10-22（用户要求：搜索记录持久化 + 点输入框就展示）：
    //   复用全局 `SearchHistory`（`settings.dart`，StringList 落盘、最近在前、去重、上限 20）
    unawaited(SearchHistory.i.ensureLoaded());
    SearchHistory.i.addListener(_onHistoryChanged);
    _sc.addListener(_onScroll);
  }

  /// ★ 2026-10-28（**用户要求：聚合搜索页也自动升起键盘**）：
  ///   与站点内搜索页（`home_page.dart` 的 `_SearchPageState`）**同一套时序** ——
  ///   `等转场 completed → 让出一帧 → 再 80ms → requestFocus`。
  ///
  ///   🛢️ 为什么不能直接 `autofocus: true` 或 `initState` 里 requestFocus：
  ///     转场动画期间插 UIKit 键盘（`MediaQuery.viewInsets` 变 ⇒ 整页 relayout）
  ///     会和转场绘制叠在一起掉帧 —— 站点搜索页 2026-10-01 就踩过（提交 `9ad04dd`），
  ///     iOS 的 `CupertinoPageTransitionsBuilder` 比 Windows 的缩放转场重得多，
  ///     只在 `completed` 那一刻聚焦**仍不够**（2026-10-28 用户实报"只有 iOS 卡"）。
  ///   ⇒ 这里从一开始就用**完全错峰**的写法，不做两遍 ✅
  void _onRouteAnimStatus(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    _focusAnim?.removeStatusListener(_onRouteAnimStatus);
    _focusAnim = null;
    _focusAfterTransition();
  }

  /// 转场彻底结束后再聚焦（两帧 + 80ms，见 [_onRouteAnimStatus] 的来由）
  void _focusAfterTransition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusTimer?.cancel();
      _focusTimer = Timer(const Duration(milliseconds: 80), () {
        if (mounted) _focus.requestFocus();
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_focusScheduled) return;
    _focusScheduled = true;
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null || anim.status == AnimationStatus.completed) {
      _focusAfterTransition();
    } else {
      _focusAnim = anim;
      anim.addStatusListener(_onRouteAnimStatus);
    }
  }

  /// ★ 2026-10-22：滚动监听（距底 300px ⇒ 自动翻页）
  void _onScroll() {
    if (!_sc.hasClients) return;
    final p = _sc.position;
    if (p.pixels >= p.maxScrollExtent - 300) {
      unawaited(_loadMore());
    }
  }

  void _onHistoryChanged() {
    if (mounted) setState(() {});
  }

  /// ★ 2026-10-22（用户要求）：× ⇒ **清空输入框 + 清空所有站点的结果与分页状态**
  void _clearAll() {
    _ctl.clear();
    setState(() {
      _kw = '';
      _results.clear();
      _state.clear();
      _page.clear();
      _noMore.clear();
      _loadingMore = false;
      _sel = -1;
    });
    _focus.requestFocus(); // 焦点要回来（接着输入）
  }

  /// ★ 2026-10-22（用户要求）：搜索历史**显示在右侧结果区顶部**（复用站点搜索那套胶囊样式）。
  ///   点胶囊本体 ⇒ 填入 + 立刻搜；点 × ⇒ 只删这条；「全部删除」⇒ 全清。
  Widget _historyStrip() {
    final his = SearchHistory.i.items;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('搜索历史', style: TextStyle(fontSize: 12, color: kTxtSub)),
            const Spacer(),
            InkWell(
              onTap: () => unawaited(SearchHistory.i.clear()),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child:
                    Text('全部删除', style: TextStyle(fontSize: 12, color: kTxtSub)),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final kw in his) _historyChip(kw)],
          ),
        ],
      ),
    );
  }

  /// 一条历史胶囊（本体 = 搜 / × = 删）—— 两个独立 InkWell（与站点搜索页同款）
  Widget _historyChip(String kw) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F2),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(9)),
            onTap: () {
              _ctl.text = kw;
              unawaited(SearchHistory.i.add(kw));
              _search();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 5, 4, 5),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  kw,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF444444)),
                ),
              ),
            ),
          ),
          InkWell(
            borderRadius:
                const BorderRadius.horizontal(right: Radius.circular(9)),
            onTap: () => unawaited(SearchHistory.i.remove(kw)),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(2, 5, 8, 5),
              child: Icon(Icons.close, size: 13, color: Color(0xFF888888)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // ★ 2026-10-28：取消延迟聚焦定时器 + 摘掉转场动画监听（与站点搜索页同款）
    _focusTimer?.cancel();
    _focusAnim?.removeStatusListener(_onRouteAnimStatus);
    SearchHistory.i.removeListener(_onHistoryChanged);
    _sc.removeListener(_onScroll);
    _sc.dispose();
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        systemOverlayStyle: kStatusOverlay,
        title: const Text('聚合搜索'),
        centerTitle: true,
        elevation: 0,
        foregroundColor: kTxt,
      ),
      body: PageBg(
        child: SafeArea(
          child: Column(
            children: [
              // 顶部搜索框
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _ctl,
                      focusNode: _focus,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        hintText: '输入关键词，聚合搜索全部站点',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        // ★ 2026-10-22（用户要求）：输入框最后加 × ⇒ 点击**清空输入 + 清空搜索结果**
                        suffixIcon: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _ctl,
                          builder: (context, v, _) {
                            if (v.text.isEmpty) return const SizedBox.shrink();
                            return IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              tooltip: '清空',
                              visualDensity: VisualDensity.compact,
                              onPressed: _clearAll,
                            );
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(onPressed: _search, child: const Text('搜索')),
                ]),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 左侧：站点导航
                    SizedBox(width: 92, child: _navList()),
                    const VerticalDivider(width: 1),
                    // 右侧：结果
                    Expanded(child: _resultView()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navList() {
    // 第一项 = 全部站点；其后 = 各站点
    final items = <MapEntry<int, String>>[
      MapEntry<int, String>(-1, '全部站点'),
      for (var i = 0; i < _sites.length; i++) MapEntry<int, String>(i, _sites[i].name),
    ];
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final it = items[i];
        final on = _sel == it.key;
        // 站点自己的加载状态（「全部站点」不显示小圈）
        final st = it.key < 0 ? null : _state[_sites[it.key].name];
        return InkWell(
          onTap: () => setState(() => _sel = it.key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: on ? const Color(0x22FFB63C) : null,
              border: Border(
                left: BorderSide(
                  color: on ? const Color(0xFFF29A12) : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(children: [
              Expanded(
                child: Text(
                  it.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    color: kTxt,
                  ),
                ),
              ),
              if (st == 'loading')
                const SizedBox(
                  width: 8,
                  height: 8,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              if (st == 'fail')
                const Icon(Icons.error_outline, size: 10, color: Color(0xFFE5484D)),
            ]),
          ),
        );
      },
    );
  }

  Widget _resultView() {
    if (_kw.isEmpty) {
      // ★ 2026-10-22（用户要求）：右侧结果区顶部显示搜索历史（复用站点搜索那套胶囊）
      if (SearchHistory.i.isEmpty) {
        return Center(
          child: Text(
            '输入关键词搜索全部站点',
            style: TextStyle(color: kTxtSub, fontSize: 13),
          ),
        );
      }
      return SingleChildScrollView(child: _historyStrip());
    }
    // 组装当前要显示的列表：全部站点 = 按站点顺序拼接；单站点 = 只看那个
    final list = <MapEntry<SiteEntry, Article>>[];
    if (_sel < 0) {
      for (final s in _sites) {
        for (final a in _results[s.name] ?? const <Article>[]) {
          list.add(MapEntry<SiteEntry, Article>(s, a));
        }
      }
    } else {
      final s = _sites[_sel];
      for (final a in _results[s.name] ?? const <Article>[]) {
        list.add(MapEntry<SiteEntry, Article>(s, a));
      }
    }
    if (list.isEmpty) {
      final busy = _state.values.any((v) => v == 'loading');
      return Center(
        child: busy
            ? const CircularProgressIndicator()
            : Text('没有结果', style: TextStyle(color: kTxtSub, fontSize: 13)),
      );
    }
    // ★ 2026-10-22（自动翻页）：改用 `ScrollController` 监听（见 `_onScroll`）
    return RowsGrid(
      // ★ 2026-10-22（用户要求：切站点 ⇒ 回到顶部）：key 跟着选中项变 ⇒ 列表重建 ⇒ 滚动位置归零 ✅
      //   （翻页/数据变化时 `_sel` 不变 ⇒ key 不变 ⇒ 滚动位置保持 ✅）
      key: ValueKey<String>('agg_res_$_sel'),
      controller: _sc,
      count: list.length,
      cols: 2,
      itemBuilder: (ctx, i) =>
          ArticleCard(article: list[i].value, site: list[i].key),
    );
  }
}
