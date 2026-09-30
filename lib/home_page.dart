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
  bool _themeOpen = false; // "筛选"按钮展开的主题面板

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
          ..sort = _sort);
  }

  /// 切筛选：所有分类的列表都重拉（筛选是页面级状态，照站点）
  void _applyFilters() {
    setState(() {});
    for (final f in _feeds.values) {
      f.applyFilters(theme: _theme, duration: _duration, sort: _sort);
    }
  }

  /// Pektino 的筛选行（照站点：筛选按钮 + 时长/排序下拉）；
  /// 点"筛选"展开一排主题胶囊（多级分类的第二层）
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
                OutlinedButton.icon(
                  onPressed: () => setState(() => _themeOpen = !_themeOpen),
                  icon: const Icon(Icons.search, size: 16),
                  // 选了主题时加个 ●，提示"标签正带着"
                  label: Text(_theme == null ? '筛选' : '筛选 ●',
                      style: const TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
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
                const SizedBox(width: 8),
                const Text('时长',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 2),
                SizedBox(
                  width: 96,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _duration,
                      isDense: true,
                      isExpanded: true,
                      style:
                          const TextStyle(fontSize: 13, color: Colors.black87),
                      items: [
                        for (final d in f.durations)
                          DropdownMenuItem(
                              value: d.key,
                              child: Text(d.value,
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        _duration = v;
                        _applyFilters();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Text('排序',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 2),
                SizedBox(
                  width: 96,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _sort,
                      isDense: true,
                      isExpanded: true,
                      style:
                          const TextStyle(fontSize: 13, color: Colors.black87),
                      items: [
                        for (final s in f.sorts)
                          DropdownMenuItem(
                              value: s.key,
                              child: Text(s.value,
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        _sort = v;
                        _applyFilters();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_themeOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 主题区（40 个，照站点弹窗原顺序）
                _filterChips(f.themes),
                const SizedBox(height: 8),
                // 语言区（10 个，照站点弹窗下半区）
                _filterChips(f.languages),
              ],
            ),
          ),
      ],
    );
  }

  /// 筛选面板里的一组标签胶囊（主题区 / 语言区共用）
  Widget _filterChips(List<SiteTab> items) {
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
          sort: sort);
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
  final List<Article> _results = [];
  late final Api _api = Api(site: widget.site);
  int _page = 1;
  bool _loading = false;
  bool _searched = false;
  bool _done = false;
  String _kw = '';

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
      final next = await _api.search(kw, page: _page);
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
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: '搜索文章关键词...'),
          onSubmitted: (_) => _search(),
        ),
        actions: [
          TextButton(onPressed: _search, child: const Text('搜索')),
        ],
      ),
      body: !_searched
          ? const Center(child: Text('输入关键词即可搜索'))
          : _results.isEmpty
              ? const Center(child: Text('无结果'))
              : RowsGrid(
                  // 跟列表页同一套：竖屏站一行 3 个
                  cols: widget.site.portraitCovers ? 3 : 2,
                  masonry: widget.site.template == SiteTemplate.pektino,
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
                                    color: Colors.grey, fontSize: 12))),
                      );
                    }
                    _search(more: true);
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child:
                          Center(child: CircularProgressIndicator()),
                    );
                  },
                  itemBuilder: (ctx, i) =>
                      ArticleCard(article: _results[i], site: widget.site),
                ),
    );
  }
}
