import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'config.dart';
import 'detail_page.dart';
import 'models.dart';

/// 51吃瓜主界面：顶部分类 tab + 双列瀑布流卡片列表。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final Api _api = Api();

  /// 每 tab 一页列表状态
  final Map<String, _CategoryFeed> _feeds = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: Site.categories.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  /// 懒创建：feed 首次被可见页 build 时才真正发起请求（见 _FeedViewState）
  _CategoryFeed _feedFor(String slug) =>
      _feeds.putIfAbsent(slug, () => _CategoryFeed(slug, _api));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text('51吃瓜'),
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
            for (final c in Site.categories) Tab(text: c.value),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          for (final c in Site.categories)
            _FeedView(feed: _feedFor(c.key)),
        ],
      ),
    );
  }

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SearchPage()),
    );
  }
}

/// 单个分类的列表状态与翻页
class _CategoryFeed {
  final String slug;
  final Api _api;
  final List<Article> items = [];
  int _page = 1;
  bool _loading = false;
  bool _done = false;

  _CategoryFeed(this.slug, this._api);

  Future<void> ensureMore() async {
    if (_loading || _done) return;
    _loading = true;
    try {
      final next = await _api.category(slug, page: _page);
      if (next.isEmpty) {
        _done = true;
      } else {
        items.addAll(next);
        _page++;
        // 不足一屏可继续拉
        if (next.length < 8) _done = true;
      }
    } catch (_) {
      _done = true; // 网络失败不再重试，避免死循环
    } finally {
      _loading = false;
    }
  }
}

class _FeedView extends StatefulWidget {
  final _CategoryFeed feed;
  const _FeedView({required this.feed});

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
    widget.feed.ensureMore();
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
        await feed.ensureMore();
      },
      child: feed.items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                Padding(
                  padding: EdgeInsets.only(top: 120),
                  child: Center(
                      child: CircularProgressIndicator()),
                ),
              ],
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              physics: const AlwaysScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.82,
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
                return _ArticleCard(article: feed.items[i]);
              },
            ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final Article article;
  const _ArticleCard({required this.article});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DetailPage(baseUrl: article.url),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: article.cover.isEmpty
                    ? const ColoredBox(color: Color(0xFFEEEEEE))
                    : CachedNetworkImage(
                        imageUrl: article.cover,
                        fit: BoxFit.cover,
                        memCacheWidth: 480,
                        fadeInDuration: const Duration(milliseconds: 200),
                        placeholder: (_, __) =>
                            const ColoredBox(color: Color(0xFFEEEEEE)),
                        errorWidget: (_, __, ___) => const ColoredBox(
                          color: Color(0xFFEEEEEE),
                          child: Icon(Icons.broken_image,
                              color: Colors.black26),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    article.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey),
                  ),
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
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _ctl = TextEditingController();
  final List<Article> _results = [];
  final Api _api = Api();
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
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: _results.length + 1,
                  itemBuilder: (ctx, i) {
                    if (i >= _results.length) {
                      if (!_done) _search(more: true);
                      return const Center(child: CircularProgressIndicator());
                    }
                    return _ArticleCard(article: _results[i]);
                  },
                ),
    );
  }
}
