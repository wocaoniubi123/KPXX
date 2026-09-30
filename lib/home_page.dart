import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'api.dart';
import 'detail_page.dart';
import 'fetched_image.dart';
import 'models.dart';
import 'sites.dart';

/// 单个站点的内容页：顶部分类 tab（可带子分类）+ 双列卡片列表。
class HomePage extends StatefulWidget {
  final SiteEntry site;
  const HomePage({super.key, required this.site});

  @override
  State<HomePage> createState() => _HomePageState();
}

/// 单选弹窗（Hanime1 / Pektino 共用）：选项 key → 显示名，当前项橙色 + ✓，
/// 选完即关。（"这样的选择样式"——2026-10-01 用户指定）
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

/// 筛选行按钮（Hanime1 / Pektino 共用）：生效时橙色 + " ●"
Widget filterBtn(String label, bool on, VoidCallback tap) => OutlinedButton(
      onPressed: tap,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: Text(
        on ? '$label ●' : label,
        style: TextStyle(
            fontSize: 13,
            color: on ? const Color(0xFFE8590C) : const Color(0xFF444444)),
      ),
    );

/// 在 tab 列表里按 key 找显示名（找不到就回 key 本身）
String _nameOf(List<SiteTab> items, String key) {
  for (final t in items) {
    if (t.key == key) return t.name;
  }
  return key;
}

/// Hanime1 筛选选项（照站点四个下拉；'' 一律 = 全部）
const List<String> _hnSorts = [
  '最新上市', '最新上傳', '本日排行', '本週排行', '本月排行',
  '觀看次數', '讚好比例', '時長最長', '他們在看',
];
const List<String> _hnDates = [
  '過去 24 小時', '過去 2 天', '過去 1 週', '過去 1 個月', '過去 3 個月', '過去 1 年',
];
const List<String> _hnDurations = [
  '1 分鐘 +', '5 分鐘 +', '10 分鐘 +', '20 分鐘 +', '30 分鐘 +', '60 分鐘 +',
  '0 - 10 分鐘', '0 - 20 分鐘',
];

/// Hanime1 的四合一筛选状态（照站点：標籤/排序方式/發佈日期/時長）
class _HnFilters {
  String sort = '';
  String date = '';
  String duration = '';
  final List<String> tags = [];
  List<MapEntry<String, String>> toParams() => [
        if (sort.isNotEmpty) MapEntry('sort', sort),
        if (date.isNotEmpty) MapEntry('date', date),
        if (duration.isNotEmpty) MapEntry('duration', duration),
        for (final t in tags) MapEntry('tags[]', t),
      ];
}

/// Hanime1 的筛选行（照站点四个下拉）。单选类"选完即关"；
/// 標籤是 240 个标签的多选弹窗（确定/清除/取消）。
class _HnFilterBar extends StatelessWidget {
  final Api api;
  final _HnFilters filters;
  final VoidCallback onChanged;
  const _HnFilterBar(
      {required this.api, required this.filters, required this.onChanged});

  Future<void> _pickSingle(BuildContext context, String title,
          List<String> options, String current, void Function(String) apply) =>
      pickOptionDialog(
        context,
        title,
        [
          const MapEntry('', '全部'),
          for (final o in options) MapEntry(o, o),
        ],
        current,
        (v) {
          apply(v);
          onChanged();
        },
      );

  Future<void> _pickTags(BuildContext context) async {
    final sel = await showDialog<List<String>>(
      context: context,
      builder: (_) => _HnTagDialog(api: api, init: List.of(filters.tags)),
    );
    if (sel != null) {
      filters.tags
        ..clear()
        ..addAll(sel);
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = filters;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            filterBtn('標籤${f.tags.isEmpty ? '' : '(${f.tags.length})'}',
                f.tags.isNotEmpty, () => _pickTags(context)),
            const SizedBox(width: 6),
            filterBtn(
                f.sort.isEmpty ? '排序方式' : f.sort,
                f.sort.isNotEmpty,
                () => _pickSingle(context, '排序方式', _hnSorts, f.sort,
                    (v) => f.sort = v)),
            const SizedBox(width: 6),
            filterBtn(
                f.date.isEmpty ? '發佈日期' : f.date,
                f.date.isNotEmpty,
                () => _pickSingle(context, '發佈日期', _hnDates, f.date,
                    (v) => f.date = v)),
            const SizedBox(width: 6),
            filterBtn(
                f.duration.isEmpty ? '時長' : f.duration,
                f.duration.isNotEmpty,
                () => _pickSingle(context, '時長', _hnDurations, f.duration,
                    (v) => f.duration = v)),
          ],
        ),
      ),
    );
  }
}

/// Hanime1 标签弹窗：240 个标签多选（打开时动态抓取一次），确定/清除/取消。
class _HnTagDialog extends StatefulWidget {
  final Api api;
  final List<String> init;
  const _HnTagDialog({required this.api, required this.init});

  @override
  State<_HnTagDialog> createState() => _HnTagDialogState();
}

class _HnTagDialogState extends State<_HnTagDialog> {
  List<String>? _all;
  bool _error = false;
  late final List<String> _sel = List.of(widget.init);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await widget.api.hanimeTags();
      if (mounted) setState(() => _all = t);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    return AlertDialog(
      title: const Text('內容標籤', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: _error
              ? const Center(child: Text('标签加载失败'))
              : all == null
                  ? const Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in all)
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => setState(() => _sel.contains(t)
                                  ? _sel.remove(t)
                                  : _sel.add(t)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: _sel.contains(t)
                                      ? const Color(0xFFE8590C)
                                      : const Color(0xFFF0F0F2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  t,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: _sel.contains(t)
                                          ? Colors.white
                                          : const Color(0xFF444444)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, <String>[]),
          child: const Text('清除'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _sel),
          child: const Text('確定'),
        ),
      ],
    );
  }
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
  final _hn = _HnFilters();

  List<SiteTab> get _cats => widget.site.categories;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _cats.length, vsync: this);
    // 子分类行跟着当前分类变，切 tab 要重画
    _tab.addListener(() {
      if (mounted) setState(() {});
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

  /// 懒创建：feed 首次被可见页 build 时才真正发起请求（见 _FeedViewState）
  _CategoryFeed _feedFor(SiteTab c) {
    final s1 = _level1(c)?.key ?? '';
    final s2 = _level2(c)?.key ?? '';
    final key = '${c.key}|$s1|$s2';
    return _feeds.putIfAbsent(
        key,
        () => _CategoryFeed(
            c.key, s1.isEmpty ? null : s1, s2.isEmpty ? null : s2, _api)
          ..theme = _theme
          ..duration = _duration
          ..sort = _sort
          ..extra = _hn.toParams());
  }

  /// 切筛选：所有分类的列表都重拉（筛选是页面级状态，照站点）
  void _applyFilters() {
    setState(() {});
    for (final f in _feeds.values) {
      f.applyFilters(theme: _theme, duration: _duration, sort: _sort);
    }
  }

  /// Hanime1：把当前筛选应用到所有列表 + 重建
  void _applyHn() {
    setState(() {});
    final p = _hn.toParams();
    for (final f in _feeds.values) {
      f.applyExtra(p);
    }
  }

  /// Hanime1 的筛选行（四个下拉，照站点）
  Widget _hnFilterRow() =>
      _HnFilterBar(api: _api, filters: _hn, onChanged: _applyHn);

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
                filterBtn('筛选', _theme != null, () => _openFilterDialog(f)),
                // 有筛选生效时给个一键重置（不然切来切去总带着老标签）
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
                    ),
                    child: const Text('重置', style: TextStyle(fontSize: 13)),
                  ),
                ],
                const SizedBox(width: 6),
                // 时长/排序：Hanime1 式弹窗选择（按钮直接显示当前值 + ●，选完即关）
                filterBtn(
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
                const SizedBox(width: 6),
                filterBtn(
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
            ),
          ),
        ),
      ],
    );
  }

  /// 筛选弹窗里的一组标签胶囊（主题区 / 语言区共用）。
  /// after：选完后的收尾动作（弹窗场景 = 关闭弹窗）。
  Widget _filterChips(List<SiteTab> items, [VoidCallback? after]) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final t in items)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              _theme = _theme == t.key ? null : t.key;
              _applyFilters();
              after?.call();
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _theme == t.key
                    ? const Color(0xFFE8590C)
                    : const Color(0xFFF0F0F2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                t.name,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        _theme == t.key ? FontWeight.w600 : FontWeight.w400,
                    color: _theme == t.key
                        ? Colors.white
                        : const Color(0xFF444444)),
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
      builder: (ctx) => AlertDialog(
        title: const Text('按标签筛选', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 主题区（40 个，照站点弹窗原顺序）
                  _filterChips(f.themes, () => Navigator.pop(ctx)),
                  const SizedBox(height: 8),
                  // 语言区（10 个，照站点弹窗下半区）
                  _filterChips(f.languages, () => Navigator.pop(ctx)),
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
    final idx = _cats.isEmpty ? 0 : _tab.index.clamp(0, _cats.length - 1);
    final cur = _cats.isEmpty ? null : _cats[idx];
    final l1 = cur == null ? null : _level1(cur);
    final l2 = cur == null ? null : _level2(cur);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Text(widget.site.name),
        centerTitle: true,
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
          if (widget.site.filters != null) _filterRow(widget.site.filters!),
          // Hanime1 的筛选行（照站点：標籤 / 排序方式 / 發佈日期 / 時長）
          if (widget.site.template == SiteTemplate.hanime1) _hnFilterRow(),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                for (final c in _cats)
                  _FeedView(
                    key: ValueKey(
                        '${c.key}|${_level1(c)?.key ?? ''}|${_level2(c)?.key ?? ''}'),
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
      color: compact ? const Color(0xFFFAFAFA) : Colors.white,
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
                  color: on ? const Color(0xFFE8590C) : const Color(0xFFF0F0F2),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  s.name,
                  style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    color: on ? Colors.white : const Color(0xFF444444),
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
      MaterialPageRoute(builder: (_) => SearchPage(site: widget.site)),
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

  _CategoryFeed(this.slug, this.sub, this.sub2, this._api);

  /// 切筛选：清了重拉（对"已经加载过"的列表立即拉；没露过面的保持懒加载）
  void applyFilters(
      {String? theme, required String duration, required String sort}) {
    if (this.theme == theme && this.duration == duration && this.sort == sort) {
      return;
    }
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
      error = false;
    } catch (_) {
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
          ? (feed.error
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    Padding(
                      padding: EdgeInsets.only(top: 120),
                      child: Center(
                          child: Text('加载失败，请下拉重试',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 14))),
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    Padding(
                      padding: EdgeInsets.only(top: 120),
                      child: Center(
                          child: CircularProgressIndicator()),
                    ),
                  ],
                ))
          : RowsGrid(
              // 竖屏封面站（黄果）**一行 3 个**；但吃瓜社区（/chigua*）的帖子卡
              // 是横版大图（站点桌面就是 2 列网格）→ 走 2 列；横屏站本来 2 列
              cols: (widget.site.portraitCovers &&
                      !widget.feed.slug.startsWith('/chigua'))
                  ? 3
                  : 2,
              // Pektino：瀑布流（横竖混排按顺序填充两列，不留空档；照站点）
              masonry: widget.site.template == SiteTemplate.pektino,
              physics: const AlwaysScrollableScrollPhysics(),
              count: feed.items.length,
              // 滚动到尾部才构造 → 在那时触发翻页（懒加载）
              tail: () {
                if (feed._done) {
                  // 到底就明说（同搜索页）：别让圈圈一直空转
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                        child: Text('没有更多了',
                            style: TextStyle(
                                color: Colors.grey, fontSize: 12))),
                  );
                }
                feed.ensureMore();
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                      child: CircularProgressIndicator()),
                );
              },
              itemBuilder: (ctx, i) =>
                  ArticleCard(article: feed.items[i], site: widget.site),
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
  const ArticleCard({required this.article, required this.site});

  @override
  Widget build(BuildContext context) {
    // 卡片按内容自然高度（不再靠"撑满固定格子"对齐）；同一行的高度对齐
    // 由 RowsGrid 统一处理（用户要求：行内等高，但不要按写死的比例留大片空白）
    return Card(
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      child: InkWell(
        onTap: () {
          // 专题卡（/topics/xxx/）、合集卡（/moviesets/...）点开的是"下面那批视频的列表"，
          // 不是某一篇详情
          if (article.url.startsWith('/topics/') ||
              article.url.startsWith('/moviesets/')) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TagListPage(
                  site: site,
                  title: article.title,
                  slug: article.url,
                  isTag: false,
                ),
              ),
            );
            return;
          }
          // XVideos 的频道/演员卡（頻道、色情明星 列表）：进该频道/演员的
          // 「視頻」免费列表（站点顶上 RED 是收费的，不取）
          if (site.template == SiteTemplate.xvideos &&
              !article.url.contains('/video.')) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TagListPage(
                  site: site,
                  title: article.title,
                  slug: article.url,
                  isTag: false,
                ),
              ),
            );
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DetailPage(site: site, baseUrl: article.url),
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
                          color: Colors.black.withOpacity(0.6),
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
                                        builder: (_) => TagListPage(
                                          site: site,
                                          title: t.value,
                                          slug: t.key,
                                          isTag: true,
                                        ),
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
  final _hn = _HnFilters();

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
    try {
      final next = await _api.search(kw, page: _page, extra: _hn.toParams());
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
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctl,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: '输入关键词即可搜索'),
          onSubmitted: (_) => _search(),
        ),
        actions: [
          TextButton(onPressed: _search, child: const Text('搜索')),
        ],
      ),
      body: Column(
        children: [
          // Hanime1：搜索页顶部也有筛选行（照站点四个下拉）
          if (widget.site.template == SiteTemplate.hanime1)
            _HnFilterBar(
              api: _api,
              filters: _hn,
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
                        masonry:
                            widget.site.template == SiteTemplate.pektino,
                        count: _results.length,
                        tail: () {
                          if (_done) {
                            // 到底就明说，别一直空转圈（之前 done 后圈还一直转，
                            // 看起来像"卡住了"）
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                  child: Text('没有更多了',
                                      style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12))),
                            );
                          }
                          _search(more: true);
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                                child: CircularProgressIndicator()),
                          );
                        },
                        itemBuilder: (ctx, i) => ArticleCard(
                            article: _results[i], site: widget.site),
                      ),
          ),
        ],
      ),
    );
  }
}
