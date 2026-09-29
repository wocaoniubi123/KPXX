import 'package:flutter/material.dart';

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
            c.key, s1.isEmpty ? null : s1, s2.isEmpty ? null : s2, _api));
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
  final List<Article> items = [];
  int _page = 1;
  bool _loading = false;
  bool _done = false;
  bool error = false;

  _CategoryFeed(this.slug, this.sub, this.sub2, this._api);

  Future<void> ensureMore() async {
    if (_loading || _done) return;
    _loading = true;
    try {
      final next =
          await _api.category(slug, page: _page, sub: sub, sub2: sub2);
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
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              physics: const AlwaysScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                // 默认 16:9 封面；竖屏封面站（黄果短剧）用 3:4。
                // 比例按"封面 + 两行标题 + 一行时间"的实际高度定：竖屏封面高，
                // 给 0.58（0.62 时内容比格子高，标题会被挤掉/溢出）
                childAspectRatio: widget.site.portraitCovers ? 0.58 : 1.05,
              ),
              // 滚动到底部附近时翻页
              itemCount: feed.items.length + 1,
              itemBuilder: (ctx, i) {
                if (i >= feed.items.length) {
                  feed.ensureMore();
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                        child: CircularProgressIndicator()),
                  );
                }
                return ArticleCard(
                  article: feed.items[i],
                  site: widget.site,
                );
              },
            ),
    );
  }
}

class ArticleCard extends StatelessWidget {
  final Article article;
  final SiteEntry site;
  const ArticleCard({required this.article, required this.site});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      child: InkWell(
        onTap: () {
          // 专题卡（/topics/xxx/）点开的是"该专题下的视频列表"，不是某一篇详情
          if (article.url.startsWith('/topics/')) {
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面：默认 16:9，竖屏封面站 3:4；右下角叠视频时长（站点有才显示）
            AspectRatio(
              aspectRatio: site.portraitCovers ? 3 / 4 : 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (article.cover.isEmpty)
                    const ColoredBox(color: Color(0xFFEEEEEE))
                  else
                    FetchedImage(url: article.cover, memWidth: 480),
                  if (article.duration.isNotEmpty)
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
                          article.duration,
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
                  Text(
                    article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  if (article.meta.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    // 时间居中显示（卡片标题下面那行）
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
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    // 跟列表页同一套比例（原来 0.82 格子比内容高一截，
                    // 卡片下面会空出一大片）
                    childAspectRatio: widget.site.portraitCovers ? 0.58 : 1.05,
                  ),
                  itemCount: _results.length + 1,
                  itemBuilder: (ctx, i) {
                    if (i >= _results.length) {
                      if (!_done) _search(more: true);
                      return const Center(child: CircularProgressIndicator());
                    }
                    return ArticleCard(article: _results[i], site: widget.site);
                  },
                ),
    );
  }
}
