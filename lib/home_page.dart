import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'base/site_ui.dart';
import 'app_bg.dart';
import 'api.dart';
import 'app_background.dart';
import 'base/source_cache.dart';
import 'base/video_cache.dart';
import 'detail_page.dart';
import 'fetched_image.dart';
import 'models.dart';
import 'settings.dart'; // ★ 诊断开关 `AppSettings.i.logConsole` ✓（main.dart:31 接管了 debugPrint ✓）
import 'shorts_feed_page.dart';
import 'sites/hanime1.dart';
import 'sites/pornhub.dart';
import 'sites/xhamster.dart';
import 'sites.dart';

/// 单个站点的内容页：顶部分类 tab（可带子分类）+ 双列卡片列表。
class HomePage extends StatefulWidget {
  final SiteEntry site;
  const HomePage({super.key, required this.site});

  @override
  State<HomePage> createState() => _HomePageState();
}


/// 筛选行按钮（Hanime1 / Pektino 共用）：生效时橙色 + " ●"
Future<void> pickOptionDialog(
  BuildContext context,
  String title,
  List<MapEntry<String, String>> options,
  String current,
  void Function(String key) apply,
) async {
  final v = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      children: [
        for (final o in options)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, o.key),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    o.value,
                    style: TextStyle(
                        fontSize: 14,
                        color: o.key == current
                            ? const Color(0xFFE8590C)
                            : const Color(0xFF333333)),
                  ),
                ),
                if (o.key == current)
                  const Icon(Icons.check, size: 16, color: Color(0xFFE8590C)),
              ],
            ),
          ),
      ],
    ),
  );
  if (v != null && v != current) apply(v);
}



/// 在下拉选项（MapEntry 列表）里按 key 找显示名（找不到就回 key 本身）。
/// ⚠️ 此前签名误写成 List<SiteTab>（当时只有 MapEntry 调用），首次 CI 构建才暴露。
String _nameOf(List<MapEntry<String, String>> items, String key) {
  for (final t in items) {
    if (t.key == key) return t.value;
  }
  return key;
}

/// 主题/分类那组（`List<SiteTab>`）按 key 找显示名 —— 同 [_nameOf]，元素类型不同。
/// （`SiteFilters.themes` 是 `List<SiteTab>`，`durations`/`sorts` 才是 MapEntry；
///   2026-10-02 CI 报 `List<SiteTab>` can't be assigned… 就是这里混用了。）
String _tabNameOf(List<SiteTab> items, String key) {
  for (final t in items) {
    if (t.key == key) return t.name;
  }
  return key;
}





class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late final Api _api = Api(site: widget.site);

  /// 每 (分类|子分类) 一页列表状态
  final Map<String, _CategoryFeed> _feeds = {};

  /// 每个主分类当前选中的一级子分类 key（没选过就用第一个子分类）
  final Map<String, String> _sub = {};

  /// 二级子分类：key = "主分类|一级子" → 选中的二级子 key
  final Map<String, String> _sub2 = {};

  // ---- 筛选器（多级分类：主题/时长/排序——目前只有 Pektino 有）----
  String? _theme; // 选中的主题 slug（null = 不限）
  String _duration = '0,0'; // 时长档（"0,0" = 全部）
  String _sort = 'favorite'; // 排序

  // ---- Hanime1 的筛选器（照站点：標籤/排序方式/發佈日期/時長）----
  final _hnCtl = HnFilterController();

  // ---- Pornhub「色情明星」tab 的筛选器（排序/类型/时间/更多）----
  final _phCtl = PhStarController();

  List<SiteTab> get _cats => widget.site.categories;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _cats.length, vsync: this);
    // 子分类行跟着当前分类变，切 tab 要重画
    _tab.addListener(() {
      if (!mounted) return;
      // ⚠️ 用户 2026-10-02："短片列表每次切换到别的 tab 再回去都要重新随机取一份"
      //   （"比如我切到影片，再切到短片，数据就要重新随机取一份"）
      // 默认 `_feedFor` 是 putIfAbsent **缓存**列表 → 切回去还是那批 ✗，而短片本来就是
      // "随机批次"，缓存等于把随机性废掉 ✗ → 每次**切到**短片 tab 就丢掉它的缓存 +
      // 重新随机起始页（与 sim 侧 `listState.delete(key)` + `xhMomentsBatchFrom = 0` 同一套 ✓）。
      // ⚠️ 必须挂在这里、不能挂在 `_feedFor`：那个函数每次 build 都会被调用 ✗，
      //    在那儿删缓存会变成"每次重画都重拉" ✗。
      // `indexIsChanging` 挡掉切换动画中间那一次，避免重复触发。
      if (!_tab.indexIsChanging) {
        final i = _tab.index;
        if (i >= 0 && i < _cats.length) {
          final c = _cats[i];
          if (_api.ui?.isShortsPath(c.key) ?? false) {
            // ⚠️ 2026-10-03 修（用户实机：短片 tab 一直转圈 ✗）：
            // 这里把该分类的 feed **从缓存里删掉** ✗ → 之后新建的 feed 是**空的** ✗（items 为空、_done 为 false ✓）→
            // 渲染分支 feed.items.isEmpty → 转圈 ✗，且**没人触发它去加载** ✗ → 永远转 ✓。
            // 修：删缓存后**立刻让新 feed 自己去拉一次** ✓（下拉刷新也会重建，但那是手动的 ✗）。
            _feeds.removeWhere((k, _) => k.startsWith('${c.key}|'));
            final fresh = _feedFor(c); // 签名就是 _feedFor(SiteTab c) ✓（只一个参数 ✗）
            if (!fresh._started) fresh.ensureMore();
          }
        }
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  /// 当前分类选中的一级子分类（没子分类返回 null）
  SiteTab? _level1(SiteTab c) {
    if (c.subs.isEmpty) return null;
    final want = _sub[c.key] ?? c.subs.first.key;
    for (final s in c.subs) {
      if (s.key == want) return s;
    }
    return c.subs.first;
  }

  /// 当前分类选中的二级子分类（一级子没有下级就返回 null）
  SiteTab? _level2(SiteTab c) {
    final l1 = _level1(c);
    if (l1 == null || l1.subs.isEmpty) return null;
    final want = _sub2['${c.key}|${l1.key}'] ?? l1.subs.first.key;
    for (final s in l1.subs) {
      if (s.key == want) return s;
    }
    return l1.subs.first;
  }

  /// 本 tab 是否挂「筛选行」—— **唯一判据** ✓：挂载 `_filterRow`、`_themeFor` 取数、
  /// `_applyFilters` 推送选中项，**三处都必须用它** ✓ ——
  /// 否则就会出现"选中项泄漏到别的 tab"那种 bug ✗（2026-10-03 实机抓到）。
  /// 传 key + 有无子分类（因为遍历 feed 时手上只有 slug ✓，没有 `SiteTab` ✗）。
  bool _tabShowsFilterRowKey(String key, {required bool hasSubs}) {
    if (widget.site.filters == null) return false;
    // ⚠️ 归属判定已**下放到各站**（showsFilterRow ✓）——
    // 默认 true = 每个 tab 都挂 ✓；Pornhub 只挂 `/video` ✓、xHamster 只挂 `/categories/*` ✓。
    return _api.ui?.showsFilterRow(key, hasSubs: hasSubs) ?? true;
  }

  bool _tabShowsFilterRow(SiteTab? cur) =>
      cur != null &&
      _tabShowsFilterRowKey(cur.key, hasSubs: cur.subs.isNotEmpty);

  /// 该 tab 实际生效的"主题/标签"选中值（按 key ✓）。
  ///
  /// ⚠️ 用户 2026-10-03 实机报：**"Pornhub 站点分类 tab 下分类选择器选了之后，色情明星下面
  ///    也变成了分类选择器选择标签后的数据"** ✗ —— 根因：`_theme` 是**页面级单值** ✗，
  ///    而 `_feedFor` 与 `_applyFilters` **两处**都把它发给了**每个** tab ✗。
  /// 修法：只有"**本 tab 自己挂筛选行**"（用户在这个 tab 上能选）才吃 `_theme` ✓，其余一律 `null` ✓。
  /// - xHamster「色情明星」tab 吃它自己的 `_xhCtl.sel` ✓（演员分类/榜單，与 388 视频分类隔离 ✓）
  /// - Pornhub「色情明星」tab 有**自己那套**筛选（`_phCtl.filters`，走 `extra` ✓）→ 不吃 `_theme` ✓
  String? _themeForKey(String key, {required bool hasSubs}) {
    // 星标 tab 吃它自己的选中值（判定下放各站 ✓）
    if (_api.ui?.isStarTabKey(key) ?? false) {
      return _xhCtl.sel;
    }
    return _tabShowsFilterRowKey(key, hasSubs: hasSubs) ? _theme : null;
  }

  String? _themeFor(SiteTab c) =>
      _themeForKey(c.key, hasSubs: c.subs.isNotEmpty);

  /// 懒创建：feed 首次被可见页 build 时才真正发起请求（见 _FeedViewState）
  _CategoryFeed _feedFor(SiteTab c) {
    final s1 = _level1(c)?.key ?? '';
    final s2 = _level2(c)?.key ?? '';
    final key = '${c.key}|$s1|$s2';
    return _feeds.putIfAbsent(
        key,
        () => _CategoryFeed(
            c.key, s1.isEmpty ? null : s1, s2.isEmpty ? null : s2, _api)
          // ⚠️ **选中项只发给"本 tab 自己挂筛选行"的那种 tab** ✓（唯一判据见 `_themeFor`）
          // —— 用户 2026-10-03 实机报：**"Pornhub 分类 tab 选了分类后，色情明星 tab 也变成了
          //    那个标签的数据"** ✗。根因就是这里原先无条件把**页面级单值** `_theme` 发给了每个 tab ✗。
          //    xHamster 的「色情明星」tab 吃它自己的 `_xhCtl.sel` ✓（与那 388 个视频分类彻底隔离 ✓）。
          ..theme = _themeFor(c)
          ..duration = _duration
          ..sort = _sort
          // Pornhub 的「色情明星」tab：四个筛选拼成 ?o=/?performerType=/?t=/更多组
          // 星标 tab 的选中项走 extra（哪些站走，判定在站点里 ✓）
          ..extra = ((_api.ui?.starUsesExtra ?? false) &&
                  (_api.ui?.isStarTabKey(c.key) ?? false))
              ? _phCtl.filters.toParams()
              : _hnCtl.filters.toParams());
  }

  /// 切筛选：所有分类的列表都重拉（筛选是页面级状态，照站点）
  ///
  /// ⚠️ 但**选中项只推给"该吃它的 tab"** ✓（判据与挂载筛选行、`_feedFor` 完全同一套 ✓）——
  /// 否则 Pornhub 的「色情明星」tab 会被「分类」tab 的选中项污染 ✗
  ///（用户 2026-10-03 实机报："分类选择器选了之后，色情明星下面也变成了分类选择器选择标签后的数据" ✗）
  void _applyFilters() {
    setState(() {});
    for (final f in _feeds.values) {
      f.applyFilters(
          theme: _themeForKey(f.slug, hasSubs: f.sub != null),
          duration: _duration,
          sort: _sort);
    }
  }

  /// Pornhub 色情明星：把当前筛选应用到所有列表 + 重建
  void _applyPhStar() {
    setState(() {});
    final p = _phCtl.filters.toParams();
    for (final f in _feeds.values) {
      // ⚠️ **只推给它自己那个 feed** ✓ —— 原先推给**所有** feed ✗，与刚修的 `_applyFilters`
      // 是**同一类泄漏** ✓（用户 2026-10-03 报的就是这种："分类 tab 的选中项跑到色情明星 tab"✗）。
      if (f.slug == '/pornstars') f.applyExtra(p);
    }
  }

  /// xHamster「色情明星」tab **自己的**选中路径（演员分类 / 榜單），与站点级 `_theme`
  /// （「分类」tab 的 388 视频分类）**分开存放** ✗ —— 用户 2026-10-02 明确：
  /// "色情明星的分类选择要显示正确的明星"（那 388 个是视频分类，挂到演员 tab 上是错的 ✗）。
  final _xhCtl = XhStarController();

  /// xHamster「色情明星」的筛选行：一个按钮 → 弹窗里两段（榜單 3 / 演员分类 40）
  Widget _xhStarRow() {
    final sel = _xhCtl.sel == null ? null : _tabNameOf([...xhStarNav, ...xhStarCats], _xhCtl.sel!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              siteFilterBtn(sel ?? '明星分類', _xhCtl.sel != null, _openXhStarDialog),
              // ⚠️ 「重置」要放在**选择器按钮后面**（用户 2026-10-03："重置是让你加到这个选择器
              //   按钮后面，跟分类tab下面的那个一样" ✗）—— 不能只放在弹窗里 ✓
              if (_xhCtl.sel != null) ...[
                const SizedBox(width: 6),
                siteFilterBtn('重置', false, () {
                  setState(_xhCtl.clear);
                  _reloadXhStar();
                }),
              ],
            ]),
          ),
        ),
      ],
    );
  }

  void _openXhStarDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => siteTagDialog(
        title: const Text('明星分類', style: TextStyle(fontSize: 16)),
        // A2：本处 content 自带 SizedBox + ConstrainedBox(420) + SingleChildScrollView
        // 再套一层会双层滚动，所以传 constrained: false 让原内容原样生效
        constrained: false,
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 榜單（3 项，对应站点顶部导航）
                  _filterChips(xhStarNav, () => Navigator.pop(ctx), true),
                  const SizedBox(height: 12),
                  // 演员分类（40 项，站点演员页 chip 原顺序）
                  _filterChips(xhStarCats, () => Navigator.pop(ctx), true),
                ],
              ),
            ),
          ),
        ),
        actions: [
          // ⚠️ **重置按钮**（用户 2026-10-03："明星分类标签选了，没有重置按钮" ✗）：
          // 选中后再点同一个 chip 虽然也能取消，但弹窗选完即关、用户不容易发现 ✓ → 给个明确的
          // 「重置」：清掉选中项 + 丢掉该 tab 的列表缓存（列表会退回 /pornstars 全部明星 ✓）。
          TextButton(
            onPressed: () {
              setState(_xhCtl.clear);
              _reloadXhStar();
              Navigator.pop(ctx);
            },
            child: const Text('重置'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  /// 选了明星分类/榜單 → 丢掉这个 tab 的旧列表（否则还在显示老结果 ✗）并重画
  void _reloadXhStar() {
    final key = _xhStarTabKey;
    if (key != null) _feeds.removeWhere((k, _) => k.startsWith('$key|'));
  }

  /// 「色情明星」tab 在 `_feeds` 里的 key 前缀（= `/pornstars|`），拿不到就 null
  String? get _xhStarTabKey {
    if (!(_api.ui?.hasStarTab ?? false)) return null;
    for (final c in _cats) {
      if (c.key == '/pornstars') return c.key;
    }
    return null;
  }
  /// Pornhub 的色情明星筛选行（照站点四个控件）：
  Widget _phStarRow() => _phCtl.row(onChanged: _applyPhStar);

  /// Hanime1：把当前筛选应用到所有列表 + 重建
  void _applyHn() {
    setState(() {});
    final p = _hnCtl.filters.toParams();
    for (final f in _feeds.values) {
      f.applyExtra(p);
    }
  }

  /// Hanime1 的筛选行（四个下拉，照站点）
  Widget _hnFilterRow() => _hnCtl.row(api: _api, onChanged: _applyHn);

  /// Pektino 的筛选行（照站点：筛选按钮 + 时长/排序下拉）；
  /// 点「筛选」弹出标签弹窗（照站点「按标签筛选」；2026-10-01 从"展开"改"弹窗"）
  Widget _filterRow(SiteFilters f) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal, // 兜底：极窄屏也不换行（可横滑）
            child: Row(
              children: [
                // 单选 → 选中后按钮直接显示那个标签名（Hanime1 是多选，那边保持原样）
                siteFilterBtn(
                  _theme == null
                      ? f.themeEmptyLabel // PH 上是「分类选择」，其余默认「筛选」
                      : _tabNameOf(f.themes, _theme!),
                  _theme != null,
                  () => _openFilterDialog(f),
                ),
                // ⚠️ 这里**不要**再插一个「重置」✗ —— 用户 2026-10-03 实机报：
                //   "别的站点也一起改了，有的分类选择器后面有 2 个重置" ✗。
                //   本行（`_filterRow`）是**全站共享**的 ✓，而**行尾本来就有**一个「重置」
                //   （红字、有筛选才出现，见本函数末尾 ✓，那是用户 2026-10-02 要的 ✓）。
                //   而且 xHamster 这行只有选择器一个按钮 ✓ → 那个"放最后"的重置**位置正好
                //   就在选择器后面** ✓ —— 需求本来就已满足 ✓，我加的纯属重复 ✗。
                // 时长/排序：Hanime1 式弹窗选择（按钮直接显示当前值 + ●，选完即关）。
                // ⚠️ 站点没给这组选项就**不画这个按钮**：Pornhub 的 durations/sorts 都是空列表
                // → 它只剩一个「分类选择」；Pektino 两组都非空 → 行为一字不变。
                if (f.durations.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  siteFilterBtn(
                    _duration == '0,0' ? '时长' : _nameOf(f.durations, _duration),
                    _duration != '0,0',
                    () => pickOptionDialog(
                      context,
                      '时长',
                      [for (final d in f.durations) MapEntry(d.key, d.value)],
                      _duration,
                      (v) {
                        _duration = v;
                        _applyFilters();
                      },
                    ),
                  ),
                ],
                if (f.sorts.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  siteFilterBtn(
                    _sort == 'favorite' ? '排序' : _nameOf(f.sorts, _sort),
                    _sort != 'favorite',
                    () => pickOptionDialog(
                      context,
                      '排序',
                      [for (final s in f.sorts) MapEntry(s.key, s.value)],
                      _sort,
                      (v) {
                        _sort = v;
                        _applyFilters();
                      },
                    ),
                  ),
                ],
                // 一键重置放**最后**、用**红字**（用户 2026-10-02 要求）；有筛选生效时才出现
                if (_theme != null ||
                    _duration != '0,0' ||
                    _sort != 'favorite') ...[
                  const SizedBox(width: 6),
                  OutlinedButton(
                    onPressed: () {
                      _theme = null;
                      _duration = '0,0';
                      _sort = 'favorite';
                      _applyFilters();
                    },
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: Colors.red,
                    ),
                    child: const Text('重置', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 筛选弹窗里的一组标签胶囊（主题区 / 语言区共用）。
  /// after：选完后的收尾动作（弹窗场景 = 关闭弹窗）。
  /// 标签芯片组。[starSel] = true 时它服务的是 xHamster「色情明星」tab 的**独立选中项**
  /// `_xhCtl.sel`（演员分类），而不是站点级 `_theme`（视频分类）—— 两者**绝不能混** ✗
  /// （用户 2026-10-02："色情明星的分类选择要显示正确的明星"）。
  Widget _filterChips(List<SiteTab> items, [VoidCallback? after, bool starSel = false]) {
    bool sel(SiteTab t) => starSel ? _xhCtl.sel == t.key : _theme == t.key;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final t in items)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              if (starSel) {
                setState(() => _xhCtl.sel = _xhCtl.sel == t.key ? null : t.key);
                _reloadXhStar();
              } else {
                _theme = _theme == t.key ? null : t.key;
                _applyFilters();
              }
              after?.call();
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                // 同 _chipsRow：未选中透明底 + 细描边（图能透出来）
                color: sel(t) ? const Color(0xFFE8590C) : Colors.transparent,
                border: sel(t) ? null : Border.all(color: const Color(0x593C3C3C)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                t.name,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: sel(t) ? FontWeight.w600 : FontWeight.w400,
                    color: sel(t) ? Colors.white : const Color(0xFF2C2C2C)),
              ),
            ),
          ),
      ],
    );
  }

  /// 点「筛选」弹出标签弹窗（照站点「按标签筛选」的形态；2026-10-01 用户要求
  /// 从"页面里展开一行"改成弹窗）。选标签即时生效并关闭弹窗；点关闭或遮罩收起。
  void _openFilterDialog(SiteFilters f) {
    showDialog<void>(
      context: context,
      builder: (ctx) => siteTagDialog(
        title: const Text('按标签筛选', style: TextStyle(fontSize: 16)),
        // A2：本处 content 自带 SizedBox + ConstrainedBox(420) + SingleChildScrollView
        // 再套一层会双层滚动，所以传 constrained: false 让原内容原样生效
        constrained: false,
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ⚠️ xHamster：388 个分类要**按站点原顺序分 13 组显示**（製作/行動/戀物癖/指示/年齡/
                  //   種族/身體/頭髮/人數/性玩具/服飾/設想/位置）—— 用户 2026-10-03 实机报：
                  //   "弹窗没有显示制作/行动/恋物癖… 所有标签全部挤在一块了" ✗
                  //   （App 原先用的是**拍平**的 `_xhCats`，分组只在注释里 ✗）。
                  //   分组数据 `xhCatGroups` 与 sim 的 `XH_CATS` **脚本同源生成** ✓（同顺序同内容 ✓）。
                  if (f.themes.isNotEmpty && (_api.ui?.hasCatGroups ?? false))
                    for (final g in xhCatGroups) ...[
                      Padding(
                        padding: EdgeInsets.only(
                            top: g == xhCatGroups.first ? 0 : 14, bottom: 6),
                        child: Text(g.key,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      _filterChips(g.value, () => Navigator.pop(ctx)),
                    ]
                  else ...[
                    // 主题区（照站点弹窗原顺序）
                    _filterChips(f.themes, () => Navigator.pop(ctx)),
                    const SizedBox(height: 8),
                    // 语言区（照站点弹窗下半区）
                    _filterChips(f.languages, () => Navigator.pop(ctx)),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 整页跟着背景明暗重建（顶栏/TabBar/胶囊/空态文字都读 kTxt）。
    // ⚠️ 必须在 builder 里重建页面：把 widget 实例直接交给 builder，
    // Flutter 会因"实例相同"跳过整棵子树的重建，isDark 翻了也不会刷。
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => _pageView(context),
    );
  }

  Widget _pageView(BuildContext context) {
    final idx = _cats.isEmpty ? 0 : _tab.index.clamp(0, _cats.length - 1);
    final cur = _cats.isEmpty ? null : _cats[idx];
    final l1 = cur == null ? null : _level1(cur);
    final l2 = cur == null ? null : _level2(cur);
    return Scaffold(
      // 透明：让根层背景图透出来（顶栏也透明，见 main.dart 的 theme）
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        systemOverlayStyle: kStatusOverlay,
        title: Text(widget.site.name),
        centerTitle: true,
        foregroundColor: kTxt, // 标题/搜索图标直接压在图上 → 跟明暗
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _openSearch(context),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          // 透明化：M3 的 TabBar 默认在下面画一条浅灰分割线，压在背景图上很突兀
          dividerColor: Colors.transparent,
          indicatorColor: const Color(0xFFE8590C),
          // 分类 tab 也直接压在图上：选中用模拟器的浅橙，未选中跟明暗翻
          labelColor: AppBg.i.isDark
              ? const Color(0xFFFFB07A)
              : const Color(0xFFE8590C),
          unselectedLabelColor:
              AppBg.i.isDark ? Colors.white : const Color(0xFF3A3A3A),
          tabs: [
            for (final c in _cats) Tab(text: c.name),
          ],
        ),
      ),
      body: Column(
        children: [
          // 子分类行（黄果短剧的排序、91porna 的子频道等）
          if (cur != null && cur.subs.isNotEmpty)
            _chipsRow(
              items: cur.subs,
              sel: l1?.key ?? '',
              onPick: (k) => setState(() => _sub[cur.key] = k),
            ),
          // 二级子分类行（如 91porna「热门排行榜」下面那 12 个排序）
          if (l1 != null && l1.subs.isNotEmpty)
            _chipsRow(
              items: l1.subs,
              sel: l2?.key ?? '',
              compact: true,
              onPick: (k) => setState(
                  () => _sub2['${cur!.key}|${l1.key}'] = k),
            ),
          // 筛选器（多级分类：主题/时长/排序——站点把它们放在"每天/每周"这些
          // 主分类页面里，照站点做一行筛选控件）
          // ⚠️ Pornhub 只在**「分类」tab** 显示这一行，而且只有一个按钮（时长/排序
          // 在 _filterRow 里按"该站没这组选项就不画"自动没了）；首页/视频 tab
          // 站点上没有这行；色情明星 tab 有自己那一行（见下）。
          // 判定不用 tab 显示名：PH 的「分类」= key 是 /video **且没有子分类**的那个
          // （「视频」tab 的 key 也是 /video，但它带 9 个子项）。
          // ⚠️ xHamster 同理（用户 2026-10-02 实机抓到"你又把分类选择乱挂到别的tab了" ✗）：
          // 那一行 388 分类选择**只属于「分类」tab**（key = /categories/... 且无子分类）；
          // 「影片」tab（key `/`，带 4 个子项）和「色情明星」「短片」tab 都不该出现它 ✗。
          // sim 侧本来就是这么做的（xhBar 只在 cat.name === '分类' 时挂上 ✓）。
          // ⚠️ 用**同一个判据** `_tabShowsFilterRow` ✓ —— 哪些 tab 挂筛选行，那些 tab 才吃选中项 ✓
          //（用户 2026-10-03："Pornhub 分类 tab 选了之后，色情明星 tab 也变了" ✗）
          if (_tabShowsFilterRow(cur)) _filterRow(widget.site.filters!),
          // Hanime1 的筛选行（照站点：標籤 / 排序方式 / 發佈日期 / 時長）
          if (_api.ui?.hasFilterRow ?? false) _hnFilterRow(),
          // Pornhub「色情明星」tab 的筛选行（排序 / 类型 / 时间 / 更多筛选设置）
          if ((_api.ui?.starRowKind ?? '') == 'ph' &&
              cur?.key == '/pornstars')
            _phStarRow(),
          // xHamster「色情明星」tab 的筛选行（榜單 3 + 演员分类 40）
          // ⚠️ 用户 2026-10-02："色情明星的分类选择要显示正确的明星" —— 这里给的是**演员分类**
          // （`/pornstars/all/categories/<slug>`），**不是**「分类」tab 那 388 个视频分类 ✗。
          if ((_api.ui?.starRowKind ?? '') == 'xh' &&
              cur?.key == '/pornstars')
            _xhStarRow(),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                for (final c in _cats)
                  _FeedView(
                    // ⚠️ key 必须**带上"选中项"** —— 用户 2026-10-03 实机报"选了分类按钮不显示对应的
                    //   明星" ✗。原 key 只有 分类/子分类，**不含 `_theme` / `_xhCtl.sel`** → 换了选中项
                    //   key 不变 → State 被复用，而 `_FeedViewState` **没有 didUpdateWidget** ✗
                    //   → 列表永远不会重新加载（「分类」tab 选那 388 个也一样不刷新 ✗）。
                    //   把两个选中项都写进 key：一变就换 State → 重新拉 ✓
                    // key 里的选中项也用 `_themeFor(c)` ✓（与取数同一个值 ✓）——
                    // 这样**别的 tab 不会因为切换它的选中项而白重拉** ✗，本 tab 选了才换 State ✓
                    key: ValueKey(
                        '${c.key}|${_level1(c)?.key ?? ''}|${_level2(c)?.key ?? ''}|${_themeFor(c) ?? ''}'),
                    feed: _feedFor(c),
                    site: widget.site,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 一行子分类胶囊（选中的高亮；点一下换 key，列表由 feed key 变化触发重建）
  Widget _chipsRow({
    required List<SiteTab> items,
    required String sel,
    required void Function(String) onPick,
    bool compact = false, // 二级子分类行：小一号、底色浅一点，跟一级区分开
  }) {
    return Container(
      // 透明：原来是一级 `Colors.white` / 二级 `0xFFFAFAFA`，两行深浅不同，
      // 交界处出现一条灰缝，而且整条把背景图挡死（用户截图指的就是这个）。
      // 胶囊自己保留浅色底（小方块，不挡图、保证字看得清）。
      color: Colors.transparent,
      padding: EdgeInsets.symmetric(vertical: compact ? 4 : 6),
      child: SizedBox(
        height: compact ? 26 : 30,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final s = items[i];
            final on = s.key == sel;
            return InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: () => onPick(s.key),
              child: Container(
                alignment: Alignment.center,
                padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
                decoration: BoxDecoration(
                  // 未选中：**透明底 + 细描边**（用户指定效果：背景图从胶囊里透出来，
                  // 不要浅灰实心块）；选中的保持品牌橙实底。
                  // 描边色也跟明暗走（深边框在深色图上等于没有）
                  color: on ? const Color(0xFFE8590C) : Colors.transparent,
                  border: on ? null : Border.all(color: kChipBorder),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  s.name,
                  style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    color: on ? Colors.white : kTxt,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      // ★ 2026-10-05【⑥ 页面起名】只加 `settings:` ✓（builder/PageBg 一字未动 ☠）
      MaterialPageRoute(
        settings: const RouteSettings(name: '搜索'),
        builder: (_) => PageBg(child: SearchPage(site: widget.site)),
      ),
    );
  }
}

/// 单个分类（或分类+子分类）的列表状态与翻页。
/// 继承 ChangeNotifier：数据返回后通知页面重建（否则列表首帧后永远停在转圈）。
class _CategoryFeed extends ChangeNotifier {
  final String slug;
  final String? sub; // 一级子分类 key：huangguo=排序值，porna=路径，wordpress 一般没有
  final String? sub2; // 二级子分类 key（目前只有 91porna 的「热门排行榜」有）
  final Api _api;

  // ---- Pektino 类站点的"筛选器"状态（多级分类：主题/时长/排序）----
  String? theme; // 选中的主题 slug（null = 不限）
  String duration = '0,0'; // 时长档 "min,max" 秒（"0,0" = 全部）
  String sort = 'favorite'; // 排序：favorite / pv / time / created

  /// Hanime1 类站点的筛选参数（sort/date/duration/tags[]，直接拼进请求）
  List<MapEntry<String, String>>? extra;

  final List<Article> items = [];
  int _page = 1;
  bool _loading = false;
  bool _done = false;
  bool _started = false; // 拉过至少一次（切筛选时决定要不要马上重拉）
  bool error = false;

  /// ⚠️ 错误的**原文**（用户 2026-10-03 实机"短片一直转圈"排查时加的）：
  /// 光有 `error` 这个 bool ✗，界面上分不清"还在转圈"和"已经失败" ✓。
  String errorText = '';

  /// 是否已经拉到底 —— 界面用它区分"还在加载"与"真的一条都没有" ✓，
  /// 免得"拿到 0 条但没抛异常"时**永远转圈** ✗。
  bool get done => _done;

  _CategoryFeed(this.slug, this.sub, this.sub2, this._api);

  /// 切筛选：清了重拉（对"已经加载过"的列表立即拉；没露过面的保持懒加载）
  void applyFilters(
      {String? theme, required String duration, required String sort}) {
    if (this.theme == theme && this.duration == duration && this.sort == sort) {
      return;
    }
    // 看：用户切了筛选（主题/时长/排序各有没有值）—— 列表突然空了/重拉先看这条。
    if (AppSettings.i.logConsole) debugPrint('[LIST] 切筛选 项数=${[theme, duration, sort].where((v) => v != null && v.isNotEmpty).length} theme=${theme ?? ''} duration=$duration sort=$sort');
    this.theme = theme;
    this.duration = duration;
    this.sort = sort;
    items.clear();
    _page = 1;
    _done = false;
    error = false;
    notifyListeners();
    if (_started) ensureMore();
  }

  /// 切 Hanime1 筛选：清了重拉（同 applyFilters 的懒加载逻辑）
  void applyExtra(List<MapEntry<String, String>>? e) {
    // 看：用户切了子分类/标签（传进来几个 key）—— 列表突然空了先看这条。
    if (AppSettings.i.logConsole) debugPrint('[LIST] 切子分类 k=${e == null ? '（清空）' : e.map((x) => x.key).join('&')} 项数=${e?.length ?? 0}');
    extra = e;
    items.clear();
    _page = 1;
    _done = false;
    error = false;
    notifyListeners();
    if (_started) ensureMore();
  }

  Future<void> ensureMore() async {
    if (_loading || _done) return;
    _loading = true;
    _started = true;
    final reqPage = _page; // ★ 诊断用：本次请求的页码（下面成功时 `_page++` 会改掉它 ⇒ 先存一份 ✓ 不参与任何判断 ☠）
    try {
      final next = await _api.category(slug,
          page: _page,
          sub: sub,
          sub2: sub2,
          theme: theme,
          duration: duration,
          sort: sort,
          extra: extra);
      if (next.isEmpty) {
        _done = true;
      } else {
        items.addAll(next);
        _page++;
        // 不足一屏可继续拉
        if (next.length < 8) _done = true;
      }
      // ★ 列表翻页诊断：哪个分类/子分类、请求的第几页、回来几条、累计几条、是否已到底
      //   —— "tab 一直转圈 / 翻页条数不涨 / 列表重复"时先看这行（累计=items.length ✓）
      if (AppSettings.i.logConsole) {
        debugPrint('[LIST] 站=${_api.site.name} slug=$slug 页=$reqPage '
        'sub=${sub ?? ''} sub2=${sub2 ?? ''} n=${next.length} 累计=${items.length} done=$_done');
      }
      error = false;
    } catch (e) {
      // ⚠️ 把**原文**留下来（不只是 bool ✗）—— 用户 2026-10-03："短片一直转圈圈"，
      //    而界面上看不到任何原因，就是因为它只存了个 bool ✓。
      errorText = e.toString();
      error = true;
      _done = true; // 失败不自动重试（避免死循环），靠用户下拉刷新
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

class _FeedView extends StatefulWidget {
  final _CategoryFeed feed;
  final SiteEntry site;
  const _FeedView({super.key, required this.feed, required this.site});

  @override
  State<_FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends State<_FeedView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // 切走分类再回来不重新加载

  @override
  void initState() {
    super.initState();
    widget.feed.addListener(_onFeedChanged);
    widget.feed.ensureMore();
  }

  @override
  void dispose() {
    widget.feed.removeListener(_onFeedChanged);
    super.dispose();
  }

  void _onFeedChanged() {
    if (mounted) setState(() {});
  }

  // ⚠️ 2026-10-03 修（用户实机：短片 tab 一直转圈 ✗；home_page:683 的注释早就记下这个坑，但一直没补 ✗）：
  // 本 State 带 AutomaticKeepAliveClientMixin → **切走再回来不重建** ✓，而 feed **会被换掉** ✗
  // （切到短片 tab 时 removeWhere 清缓存 → 下次拿到的是**新实例** ✗）→ 新实例**没人挂监听** ✗ →
  // notifyListeners 时界面不刷新 ✗ → 永远停在空列表的转圈分支 ✓。
  // 标准写法：在 didUpdateWidget 里**换监听 + 触发加载** ✓（ensureMore 自带 _loading/_started 守卫 ✓）。
  @override
  void didUpdateWidget(covariant _FeedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.feed, widget.feed)) {
      oldWidget.feed.removeListener(_onFeedChanged);
      widget.feed.addListener(_onFeedChanged);
      widget.feed.ensureMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // keepAlive 必须调用
    final feed = widget.feed;
    return RefreshIndicator(
      onRefresh: () async {
        feed.items.clear();
        feed._page = 1;
        feed._done = false;
        feed.error = false;
        await feed.ensureMore();
      },
      child: feed.items.isEmpty
          // ⚠️ **永远不能无限转圈**（用户 2026-10-03 实机："短片一直转圈圈" ✗）：
          //   原来的逻辑是"error 为真才显示失败，否则转圈" ✗ —— 而"拿到 0 条但没抛异常"
          //   这种就落进了转圈分支、永远转下去 ✗。而且 `error` 只是个 bool ✓、**具体原因没存** ✗。
          //   现在按三态渲染：出错 → 显示**错误原文**；拉完了但 0 条 → 明说 0 条；否则才转圈 ✓。
          ? (feed.error
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 120),
                      child: Center(
                          child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                            '加载失败：${feed.errorText.isEmpty ? '未知原因' : feed.errorText}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: kTxtSub, fontSize: 14)),
                      )),
                    ),
                  ],
                )
              : (feed.done
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 120),
                          child: Center(
                              child: Text('没有数据（接口返回 0 条）',
                                  style: TextStyle(
                                      color: kTxtSub, fontSize: 14))),
                        ),
                      ],
                    )
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        Padding(
                          padding: EdgeInsets.only(top: 120),
                          child:
                              Center(child: CircularProgressIndicator()),
                        ),
                      ],
                    )))
          : RowsGrid(
              // 竖屏封面站（黄果）**一行 3 个**；但吃瓜社区（/chigua*）的帖子卡
              // 是横版大图（站点桌面就是 2 列网格）→ 走 2 列；横屏站本来 2 列
              cols: ((widget.site.portraitCovers &&
                          !widget.feed.slug.startsWith('/chigua')) ||
                      // Pornhub「色情明星」tab 是演员卡（竖版头像）→ 跟竖屏站一样一行 3 个
                      // ⚠️ 只认**演员列表**（`/pornstars`、`/pornstars/all/…`、`/pornstars/top/…` ✓）；
                      // `/pornstars/<名字>` 是**那个演员的视频列表** ✗ —— 判定在站点里（isStarList ✓）
                      (feed._api.ui?.isStarList(widget.feed.slug) ?? false))
                  ? 3
                  : 2,
              // Pektino：瀑布流（横竖混排按顺序填充两列，不留空档；照站点）
              masonry: feed._api.ui?.masonry ?? false,
              physics: const AlwaysScrollableScrollPhysics(),
              count: feed.items.length,
              // 滚动到尾部才构造 → 在那时触发翻页（懒加载）
              tail: () {
                if (feed._done) {
                  // 到底就明说（同搜索页）：别让圈圈一直空转
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                        child: Text('没有更多了',
                            style: TextStyle(
                                color: kTxtSub, fontSize: 12))),
                  );
                }
                feed.ensureMore();
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                      child: CircularProgressIndicator()),
                );
              },
              itemBuilder: (ctx, i) {
                // ⭐ 预取（#8 ✓）：顺手把"再往后第 8 张"的封面拉进内存缓存 ✓
                //（自研 FetchedImage 不会被框架预取 ✗；失败静默 ✓、与显示时共用同一个在途请求 ✓）
                FetchedImage.warm(
                    i + 8 < feed.items.length ? feed.items[i + 8].cover : null,
                    index: i + 8,
                    total: feed.items.length);
                return ArticleCard(article: feed.items[i], site: widget.site);
              },
            ),
    );
  }
}

/// 按行排的卡片列表：**行高 = 该行最高的卡片**，行内其它卡片拉伸到同高；
/// 行高完全由内容决定 —— 不像"固定宽高比网格"（childAspectRatio 是按内容
/// 最多的卡片估出来的），内容少的行（专题/排行榜卡）底部不会再多出一大块空白
/// （2026-09-30 用户实报"所有站点都留白很多"）。
/// [count]=数据条数；[tail] 是列表尾项（"没有更多了"/转圈），**只在滚到尾部
/// 时才构造** —— "加载下一页"的触发时机与原来一致（懒加载，不会一进页面就预拉）。
class RowsGrid extends StatelessWidget {
  final int count;
  final int cols;
  final Widget Function(BuildContext, int) itemBuilder;
  final Widget Function()? tail;
  final ScrollPhysics? physics;

  /// 瀑布流模式（仅 Pektino）：卡片**按顺序**轮流放进两列、**列内连续**——
  /// 横竖混排时不会像"按行布局"那样在矮卡下面留空档（照站点）。
  /// false = 默认"按行"布局：行高 = 该行最高卡、行内等高（用户要求）。
  final bool masonry;

  const RowsGrid({
    super.key,
    required this.count,
    required this.cols,
    required this.itemBuilder,
    this.tail,
    this.physics,
    this.masonry = false,
  });

  @override
  Widget build(BuildContext context) {
    final tailCount = tail == null ? 0 : 1;
    if (masonry) {
      // 瀑布流（SliverMasonryGrid 懒加载）：按顺序把每张卡放进当前最矮的列
      return CustomScrollView(
        physics: physics,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(8),
            sliver: SliverMasonryGrid.count(
              crossAxisCount: cols,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childCount: count + tailCount,
              itemBuilder: (ctx, i) {
                if (i >= count) return tail!();
                return itemBuilder(ctx, i);
              },
            ),
          ),
        ],
      );
    }
    final rows = (count + cols - 1) ~/ cols;
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      physics: physics,
      itemCount: rows + tailCount,
      itemBuilder: (ctx, r) {
        if (r >= rows) return tail!();
        final start = r * cols;
        // IntrinsicHeight：把这行的高度定成"最高的那张卡片"，
        // 其它卡片随 stretch 拉伸对齐；行与行互不影响
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var c = 0; c < cols; c++)
                if (start + c < count)
                  Expanded(
                    child: Padding(
                      // 列间距 8（最后一列不用，右侧留给 ListView 的 padding）
                      padding: EdgeInsets.only(
                          right: c < cols - 1 ? 8 : 0, bottom: 8),
                      child: itemBuilder(ctx, start + c),
                    ),
                  )
                else
                  // 最后一行不满：占位保持列宽
                  const Expanded(child: SizedBox()),
            ],
          ),
        );
      },
    );
  }
}

class ArticleCard extends StatelessWidget {
  final Article article;
  final SiteEntry site;
  const ArticleCard({super.key, required this.article, required this.site});

  @override
  Widget build(BuildContext context) {
    // 卡片按内容自然高度（不再靠"撑满固定格子"对齐）；同一行的高度对齐
    // 由 RowsGrid 统一处理（用户要求：行内等高，但不要按写死的比例留大片空白）
    return Card(
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      child: InkWell(
        onTap: () {
          // 站点 UI 事实（各站自己实现 ✓；没实现的返回 null → 走默认，行为不变 ✓）
          final ui = Api(site: site).ui;
          // 专题卡（/topics/xxx/）、合集卡（/moviesets/...）点开的是"下面那批视频的列表"，
          // 不是某一篇详情
          if (article.url.startsWith('/topics/') ||
              article.url.startsWith('/moviesets/')) {
            Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(name: '标签页'),
                builder: (_) => PageBg(child: TagListPage(
                  site: site,
                  title: article.title,
                  slug: article.url,
                  isTag: false,
                )),
              ),
            );
            return;
          }
          // 标签卡（url 形如 /tag/xxx，麻豆社的「热门标签」标签云页）：
          // 点进的是该标签的列表页，不是文章详情
          if (article.url.startsWith('/tag/')) {
            Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(name: '标签页'),
                builder: (_) => PageBg(child: TagListPage(
                  site: site,
                  title: article.title,
                  slug: article.url,
                  isTag: true,
                )),
              ),
            );
            return;
          }
          // XVideos 的频道/演员卡（頻道、色情明星 列表）：进该频道/演员的
          // 「視頻」免费列表（站点顶上 RED 是收费的，不取）
          // 卡片点击的**特殊去向**已下放到各站（specialTap ✓）——
          // `list` = 进他/她的视频列表页 ✓（XVideos 频道/演员 · Pornhub 演员 · xHamster 明星 ✓）；
          // `shorts` = 进竖屏短片瀑布流 ✓（xHamster 短片 ✓）；null = 走详情页 ✓。
          if ((ui?.specialTap(article.url) ?? '') == 'list') {
            Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(name: '标签页'),
                builder: (_) => PageBg(child: TagListPage(
                  site: site,
                  title: article.title,
                  slug: article.url,
                  isTag: false,
                )),
              ),
            );
            return;
          }
          // ⚠️ xHamster 短片卡 → 进**竖屏瀑布流**（用户 2026-10-02 要求），**不是**详情页 ✗。
          // 只把"点的那条"传进去打头，往后的由瀑布流自己续拉（短片列表本身是随机的 ✓）。
          if ((ui?.specialTap(article.url) ?? '') == 'shorts') {
            // ⚠️ 2026-10-03 加（用户拍板 ② ✓）：**点卡片这一刻就开始抓片源** ✓ —— 与转场动画重叠 ✓，
            //    进页面就不用再白等这一次详情页请求（用户实测"点进来要好几秒才有画面"✗）。
            //    走**共享缓存** ✓：页面里的 `_sourcesOf` 会命中这个**在途 Future** ✓
            //    → **同一个 url 只飞一次** ✗（不会变成两次请求 ✓）；失败也不影响导航 ✓（缓存里会清掉 ✓）。
            //    ⚠️ #9：key 带命名空间 `s|` ✓ —— 与详情页的合集取源（`d|` ✓）**分开** ✗
            //    （两条路取源策略不同 ✗，同一 url 的取源结果来自两套不同实现 ✓（不保证相同 ✗） → 绝不能共用 key ✗）
            SourceCache.i.get('s|${article.url}', () async {
              final d = await Api(site: site).detail(article.url);
              return SourceCache.sourcesOfDetail(d);
            }).then((srcs) {
              // ⚠️ A 项（用户 2026-10-03 拍板 ✓）：**首条也预下载** ✓ —— 源一拿到就开下，
              //    与转场动画抢那 0.5~1.5 秒 ✓；下完 → 页面里 `ready()` 命中 → `file://` 秒开 ✓。
              //    下不完也不亏 ✗：页面 `_open()` 发现本地没就绪会 `drop()` 它 ✓（让路给在线播 ✓）。
              if (srcs.isNotEmpty) VideoCache.i.window(<String>[srcs.first]);
            });
            Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(name: '短片'),
                builder: (_) => PageBg(
                  child: ShortsFeedPage(
                    api: Api(site: site),
                    site: site,
                    items: <Article>[article],
                    start: 0,
                  ),
                ),
              ),
            );
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute(
              settings: const RouteSettings(name: '详情页'),
              builder: (_) => PageBg(child: DetailPage(
                site: site,
                baseUrl: article.url,
                listCover: article.cover, // 记播放记录时的封面（零额外请求）
              )),
            ),
          );
        },
        child: Column(
          // 自然高度：内容多少就多高（行内对齐交给 RowsGrid 拉伸处理）
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面：默认 16:9，竖屏封面站 3:4；右下角叠角标
            // （一般是时长；黄果短剧按站点习惯显示集数）
            // 站点本来就没有封面（如 91porna 的小说）→ 整块不渲染，卡片变纯文字卡
            if (article.cover.isNotEmpty)
              AspectRatio(
              // 封面比例优先级：该条目自带（Pektino 横竖混排，从 mp4 分辨率算）>
              // 吃瓜社区帖子卡（/archives/，横版大图）> 站点默认（竖屏 3:4 / 横屏 16:9）
              aspectRatio: article.coverAspect ??
                  (article.url.startsWith('/archives/')
                      ? 16 / 9
                      : (site.portraitCovers ? 3 / 4 : 16 / 9)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FetchedImage(url: article.cover, memWidth: 480),
                  if (article.badge.isNotEmpty)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          article.badge,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题：**所有站点都居中**；**能一行就一行**，长了才换两行。
                  // 没有标题的卡片（Pektino 站点的卡片就没有标题）整行不渲染。
                  if (article.title.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                        article.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  // 小字简介（黄果的卡片有）：同样一行就一行
                  if (article.desc.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      article.desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, height: 1.3, color: Colors.black54),
                    ),
                  ],
                  // 分类标签：站点卡片上能点的，这里也能点（进该标签的列表）
                  if (article.tags.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        for (final t in article.tags.take(4))
                          InkWell(
                            borderRadius: BorderRadius.circular(9),
                            onTap: t.key.isEmpty
                                ? null
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        settings: const RouteSettings(name: '标签页'),
                                        builder: (_) => PageBg(child: TagListPage(
                                          site: site,
                                          title: t.value,
                                          slug: t.key,
                                          isTag: true,
                                        )),
                                      ),
                                    ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0F0F2),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                t.value,
                                style: const TextStyle(
                                    fontSize: 10, color: Color(0xFF555555)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  // 时间（居中，站点有才显示）
                  if (article.meta.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                        article.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 搜索页，复用列表卡片。
class SearchPage extends StatefulWidget {
  final SiteEntry site;
  const SearchPage({super.key, required this.site});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _ctl = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _focusScheduled = false; // 转场后聚焦只安排一次
  Animation<double>? _focusAnim; // 挂过监听的转场动画（dispose 要摘）
  final List<Article> _results = [];
  late final Api _api = Api(site: widget.site);
  int _page = 1;
  bool _loading = false;
  bool _searched = false;
  bool _done = false;
  String _kw = '';

  // ---- Hanime1：搜索页顶部也有筛选行（照站点四个下拉）----
  final _hnCtl = HnFilterController();

  /// 转场动画结束后再聚焦（弹键盘）：键盘第一次冷启动开销大，和页面转场叠在一起
  /// 会掉帧（用户实报"第一次点开搜索有点掉帧"）。页面滑入完再弹，两者错峰。
  void _onRouteAnimStatus(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    _focusAnim?.removeStatusListener(_onRouteAnimStatus);
    _focusAnim = null;
    if (mounted) _focus.requestFocus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_focusScheduled) return;
    _focusScheduled = true;
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null || anim.status == AnimationStatus.completed) {
      // 没有转场（或已完成）：下一帧直接聚焦
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    } else {
      _focusAnim = anim;
      anim.addStatusListener(_onRouteAnimStatus);
    }
  }

  @override
  void dispose() {
    _focusAnim?.removeStatusListener(_onRouteAnimStatus);
    _focus.dispose();
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _search({bool more = false}) async {
    final kw = _ctl.text.trim();
    if (kw.isEmpty || _loading || (!more && _kw == kw && _results.isNotEmpty)) {
      return;
    }
    if (!more) {
      _results.clear();
      _page = 1;
      _done = false;
    }
    _kw = kw;
    setState(() => _searched = true);
    _loading = true;
    final reqPage = _page; // ★ 诊断用：本次请求的页码（下面成功时 `_page++` 会改掉它 ⇒ 先存一份 ✓ 不参与任何判断 ☠）
    try {
      final next = await _api.search(kw, page: _page, extra: _hnCtl.filters.toParams());
      // ★ 搜索诊断：关键词**只打长度**（不打全文 ☠）、请求的第几页、回来几条 —— "搜不到 / 翻页重复"先看这行
      if (AppSettings.i.logConsole) {
        debugPrint(
        '[LIST] 站=${widget.site.name} 搜 页=$reqPage n=${next.length} kwLen=${kw.length}');
      }
      if (next.isEmpty) {
        _done = true;
      } else {
        if (more) {
          _results.addAll(next);
        } else {
          _results
            ..clear()
            ..addAll(next);
        }
        _page++;
      }
    } catch (_) {
      _done = true;
    } finally {
      _loading = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // 整页跟着背景明暗重建（顶栏图标 / 筛选行 / 尾项文字都读 kTxt）
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => _pageView(context),
    );
  }

  Widget _pageView(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        systemOverlayStyle: kStatusOverlay,
        title: TextField(
          controller: _ctl,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          // 输入框自身透明（直接压在照片上）：字和提示词都要跟明暗翻，
          // 不然深色图下白底没有、字也是深色 = 看不见。
          // ⚠️ 用 bodyLarge.copyWith(color:) 而不是只给一个 color：bodyLarge 就是
          // M3 下输入框/提示词的默认字型，这样写在"整体替换"和"与默认合并"两种
          // 语义下结果一致；只给 color 时若框架是替换语义会连字号/行高一起丢掉。
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: kTxt),
          decoration: InputDecoration(
            hintText: '输入关键词即可搜索',
            hintStyle:
                Theme.of(context).textTheme.bodyLarge?.copyWith(color: kTxtSub),
          ),
          onSubmitted: (_) => _search(),
        ),
        foregroundColor: kTxt, // 返回箭头直接压在图上 → 跟明暗
        actions: [
          TextButton(onPressed: _search, child: const Text('搜索')),
        ],
      ),
      body: Column(
        children: [
          // Hanime1：搜索页顶部也有筛选行（照站点四个下拉）
          if (_api.ui?.hasFilterRow ?? false)
            HnFilterBar(
              api: _api,
              filters: _hnCtl.filters,
              onChanged: () {
                setState(() {});
                if (_searched) {
                  _kw = ''; // 绕过"同关键词不重复搜"守卫：筛选变了必须重搜
                  _search();
                }
              },
            ),
          Expanded(
            child: !_searched
                ? const SizedBox.shrink() // 空态不再放居中文字：键盘弹出时它会往上跳，看着卡（用户实报）
                : _results.isEmpty
                    ? const Center(child: Text('无结果'))
                    : RowsGrid(
                        // 跟列表页同一套：竖屏站一行 3 个
                        cols: widget.site.portraitCovers ? 3 : 2,
                        masonry: _api.ui?.masonry ?? false,
                        count: _results.length,
                        tail: () {
                          if (_done) {
                            // 到底就明说，别一直空转圈（之前 done 后圈还一直转，
                            // 看起来像"卡住了"）
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                  child: Text('没有更多了',
                                      style: TextStyle(
                                          color: kTxtSub, fontSize: 12))),
                            );
                          }
                          _search(more: true);
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                                child: CircularProgressIndicator()),
                          );
                        },
                        itemBuilder: (ctx, i) {
                          // #4 ✓（2026-10-03）：顺手预热**后面第 8 张**的封面 ✓（与首页那处同一套 ✓）
                          if (i + 8 < _results.length) {
                            FetchedImage.warm(_results[i + 8].cover,
                                index: i + 8, total: _results.length);
                          }
                          return ArticleCard(article: _results[i], site: widget.site);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
