import 'package:flutter/material.dart';

import 'api.dart';
import 'fetched_image.dart';
import 'home_page.dart';
import 'models.dart';
import 'player_widget.dart';
import 'sites.dart';
import 'web_page.dart';

/// 文章详情：顶部视频 + 标题/标签 + 选集 + 正文图片。
class DetailPage extends StatefulWidget {
  final SiteEntry site;
  final String baseUrl; // /archives/xxx/
  const DetailPage({super.key, required this.site, required this.baseUrl});

  @override
  State<DetailPage> createState() => DetailPageState();
}

class DetailPageState extends State<DetailPage> {
  late final Api _api = Api(site: widget.site);
  ArticleDetail? _detail;
  String? _error;
  List<Article> _series = []; // 当前系列文章（含当前集）
  /// 篇内视频切换（多视频文章；详情页/内嵌播放器/全屏页共用同一份）
  VideoSwitcher? _switcher;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _detail = null;
      _error = null;
    });
    try {
      final d = await _api.detail(widget.baseUrl);
      if (!mounted) return;
      _switcher?.dispose();
      _switcher = VideoSwitcher(d.videos.length)
        ..index.addListener(_onVideoIndexChanged);
      setState(() => _detail = d);
      // 系列聚合：异步填充，失败静默（无选集不影响主内容）
      if (d.seriesPrefix.isNotEmpty) {
        _fetchSeries(d.seriesPrefix).then((list) {
          if (mounted && list.isNotEmpty) setState(() => _series = list);
        }).catchError((_) {});
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// 用站点自己的网页播放器打开本篇（应用内 WebView）。
  /// 原生 AVPlayer 在个别片源上跳转会卡死，这里是另一个引擎的出口。
  void _openInWeb() {
    if (widget.site.hosts.isEmpty) return;
    _switcher?.pause(); // 跳走前先停一下，别两边同时出声
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebPage(
          title: widget.site.name,
          url: 'https://${widget.site.hosts.first}${widget.baseUrl}',
        ),
      ),
    );
  }

  /// 视频地址带 auth_key 时效签名，过期后重抓本页拿新地址（播放器失败时会调）
  Future<List<String>> _refreshSources() async {
    final fresh = await _api.detail(widget.baseUrl);
    if (!mounted || fresh.videos.isEmpty) return const [];
    final i = (_switcher?.index.value ?? 0)
        .clamp(0, fresh.videos.length - 1)
        .toInt();
    // 顺手整页刷新（简介/剧照也一起更新），当前视频序号保持不变
    _switcher?.total = fresh.videos.length;
    setState(() => _detail = fresh);
    return fresh.videos[i].sources;
  }

  /// 篇内序号变了整页重建（播放器据此换源，列表高亮跟着变）
  void _onVideoIndexChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _switcher?.dispose();
    super.dispose();
  }

  Future<List<Article>> _fetchSeries(String prefix) async {
    final d = _detail;
    if (d == null || d.categories.isEmpty) return [];
    final slug = d.categories.first;
    final re = RegExp(r'第\s*(\d+)\s*集');
    final matched = <(int, Article)>[];
    for (var p = 1; p <= 2; p++) {
      final list = await _api.category(slug, page: p);
      for (final a in list) {
        final m = re.firstMatch(a.title);
        if (m == null) continue;
        final pre = a.title.substring(0, m.start).trim();
        if (pre == prefix) matched.add((int.parse(m.group(1)!), a));
      }
    }
    matched.sort((x, y) => x.$1.compareTo(y.$1));
    return [for (final e in matched) e.$2];
  }

  String _fmtTime(String iso) {
    if (iso.isEmpty) return '';
    // "2026-09-28 17:34:23"（站点自带时分秒）→ 原样显示
    if (iso.length >= 19 && iso[10] == ' ') return iso;
    // 2026-09-01T14:57:00+00:00 -> 2026-09-01
    if (iso.length < 10) return iso;
    return iso.substring(0, 10);
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final videos = d?.videos ?? const <ArticleVideo>[];
    final idx = videos.isEmpty
        ? 0
        : (_switcher?.index.value ?? 0).clamp(0, videos.length - 1).toInt();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.site.name),
        actions: [
          // 原生播放器卡的时候换网页那套引擎（hls.js，跳转更快）
          IconButton(
            tooltip: '用网页播放器打开',
            icon: const Icon(Icons.public),
            onPressed: _openInWeb,
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('加载失败：$_error'),
                  TextButton(onPressed: _load, child: const Text('重试')),
                ],
              ),
            )
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    // 视频区：有视频、或有海报（剧照首图）才显示；
                    // 纯文字页（如小说）不显示空白播放器
                    if (videos.isNotEmpty || d.images.isNotEmpty)
                      PlayerWidget(
                      // 不换 key：换片由播放器内部复用同一实例开新源
                      // （重建实例会让全屏页拿着的旧实例失效 → 黑屏）
                        switcher: _switcher,
                        sources: videos.isEmpty ? const [] : videos[idx].sources,
                        referer: _api.base,
                        poster: d.images.isNotEmpty ? d.images.first : '',
                        onRefreshSources: _refreshSources,
                        // 合集类：当前这一集没有源时，按需去子文章取
                        lazyUrl:
                            videos.isEmpty ? null : videos[idx].lazyUrl,
                        onFetchSources: _api.videoSourcesAt,
                      ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.title,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.local_fire_department,
                                  size: 16, color: Colors.red),
                              const SizedBox(width: 4),
                              Text(
                                _fmtTime(d.time),
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(width: 12),
                              // 显示本篇的视频数（原来显示的是"同系列文章数"，
                              // 一篇挂多个视频但没有"第N集"的文章会显示成 0）；
                              // 图文帖（没有视频）就不显示这一段，别写"0 集"
                              if (videos.isNotEmpty)
                                Text('${videos.length} 集',
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                              // 站点自带时长（如 91porna 的 1:00:39、黄果的 3:34）
                              if (d.duration.isNotEmpty) ...[
                                const SizedBox(width: 12),
                                Text('时长 ${d.duration}',
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                              ],
                            ],
                          ),
                          // 多视频文章：列出来可切换（按集数排序）
                          if (videos.length > 1) ...[
                            const SizedBox(height: 14),
                            Text('视频（${videos.length}）',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            // 竖屏封面站（黄果短剧）：选集**横向排、按宽度自动换行**
                            // 的胶囊（这站是"第 N 集"这种短标签，竖排太占地方）；
                            // 其它站保持原来的竖排（标题可能很长）
                            if (widget.site.portraitCovers)
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final (i, v) in videos.indexed)
                                    InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () => _switcher?.select(i),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: i == idx
                                              ? const Color(0xFFE8590C)
                                              : const Color(0xFFF0F0F2),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          v.label,
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: i == idx
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color: i == idx
                                                  ? Colors.white
                                                  : const Color(0xFF444444)),
                                        ),
                                      ),
                                    ),
                                ],
                              )
                            else
                              for (final (i, v) in videos.indexed)
                                InkWell(
                                  onTap: () => _switcher?.select(i),
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 6),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 22,
                                          height: 22,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: i == idx
                                                ? Colors.deepOrange
                                                : const Color(0x1F000000),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text('${v.ordinal}',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: i == idx
                                                      ? Colors.white
                                                      : Colors.black54)),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            v.label,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: i == idx
                                                    ? FontWeight.w700
                                                    : FontWeight.w500),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                          ],
                          // 简介
                          if (d.intro.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            const Text('简介',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(
                              d.intro,
                              style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: Colors.black87),
                            ),
                          ],
                          // 选集横条（同系列文章）
                          if (_series.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _buildSeriesStrip(),
                          ],
                          // 剧照：横向小图，点开看大图
                          if (d.images.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            const Text('剧照',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 84,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: d.images.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 6),
                                itemBuilder: (_, i) => InkWell(
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => PhotoViewerPage(
                                        urls: d.images,
                                        initial: i,
                                      ),
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: SizedBox(
                                      width: 120,
                                      child: FetchedImage(
                                        url: d.images[i],
                                        memWidth: 360,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          // 分类 + 标签：横向单行滚动（点标签跳到对应列表）
                          if (d.categories.isNotEmpty || d.tags.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _buildTagsStrip(d),
                          ],
                          // 相关推荐（规范：必须显示在「剧照」下方）
                          if (d.related.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text('相关推荐',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            for (final a in d.related)
                              InkWell(
                                onTap: () {
                                  // 点相关推荐跳走：先把本页播放器停掉
                                  // （不然本页压栈继续放 + 新页也在放 = 两个声音）
                                  _switcher?.pause();
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => DetailPage(
                                        site: widget.site, baseUrl: a.url),
                                  ));
                                },
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: SizedBox(
                                          width: 108,
                                          height: 61,
                                          child: a.cover.isEmpty
                                              ? const ColoredBox(
                                                  color: Color(0xFFEEEEEE))
                                              : FetchedImage(
                                                  url: a.cover,
                                                  memWidth: 320),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          a.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  /// 分类名（站点清单里有就用中文名，没有就显示 slug）
  String _catName(String slug) {
    for (final c in widget.site.categories) {
      if (c.key == slug) return c.name;
    }
    return slug;
  }

  /// 标签/分类：横向单行滚动（放「剧照」下方）
  Widget _buildTagsStrip(ArticleDetail d) {
    final chips = <Widget>[
      for (final c in d.categories)
        _tagChip(_catName(c), () => _openList(_catName(c), c, false)),
      for (final t in d.tags)
        _tagChip('#${t.value}', () => _openList(t.value, t.key, true)),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }

  Widget _tagChip(String text, VoidCallback onTap) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }

  /// 点标签/分类 → 对应列表页
  void _openList(String title, String slug, bool isTag) {
    _switcher?.pause(); // 同上：跳列表页前先把本页播放器停掉
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TagListPage(
          site: widget.site,
          title: title,
          slug: slug,
          isTag: isTag,
        ),
      ),
    );
  }

  Widget _buildSeriesStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('选集',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in _series)
              ChoiceChip(
                label: Text(
                  RegExp(r'第\s*\d+\s*集')
                          .firstMatch(a.title)
                          ?.group(0) ??
                      a.title,
                  style: const TextStyle(fontSize: 12),
                ),
                selected: a.url == widget.baseUrl,
                onSelected: (_) {
                  if (a.url == widget.baseUrl) return;
                  _switcher?.pause(); // 切集同理（旧页马上会被 replace 销毁）
                  // 切集：replace 当前页，避免栈无限加深
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) =>
                          DetailPage(site: widget.site, baseUrl: a.url),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// 剧照大图页：左右滑看同一篇的全部剧照，双指缩放，点一下退出。
class PhotoViewerPage extends StatefulWidget {
  final List<String> urls;
  final int initial;
  const PhotoViewerPage({super.key, required this.urls, this.initial = 0});

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final PageController _pc =
      PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          children: [
            PageView.builder(
              controller: _pc,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: FetchedImage(
                    url: widget.urls[i],
                    fit: BoxFit.contain,
                    memWidth: 1600,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    Text(
                      '${_index + 1} / ${widget.urls.length}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 标签 / 分类的列表页（详情页点标签或分类跳这里）
class TagListPage extends StatefulWidget {
  final SiteEntry site;
  final String title;
  final String slug;
  final bool isTag; // true = /tag/{slug}/，false = /category/{slug}/
  const TagListPage({
    super.key,
    required this.site,
    required this.title,
    required this.slug,
    required this.isTag,
  });

  @override
  State<TagListPage> createState() => _TagListPageState();
}

class _TagListPageState extends State<TagListPage> {
  late final Api _api = Api(site: widget.site);
  final List<Article> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    _loading = true;
    try {
      final next = widget.isTag
          ? await _api.tag(widget.slug, page: _page)
          : await _api.category(widget.slug, page: _page);
      if (!mounted) return;
      setState(() {
        if (next.isEmpty) {
          _done = true;
        } else {
          _items.addAll(next);
          _page++;
        }
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _done = true;
        });
      }
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(title: Text(widget.title), centerTitle: true),
      body: _items.isEmpty
          ? Center(
              child: _error != null
                  ? Text('加载失败：$_error')
                  : const CircularProgressIndicator())
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              // 比例必须跟着站点走：竖屏封面站（黄果 3:4）用 1.05 的话，
              // 封面比格子还高 → 标题被挤出可视区裁掉（专题点进去只有封面没标题就是这么来的）
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                // 竖屏站（黄果）一行 3 个，横屏站一行 2 个
                crossAxisCount: widget.site.portraitCovers ? 3 : 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio:
                    widget.site.portraitCovers ? 0.45 : 1.00,
              ),
              itemCount: _items.length + 1,
              itemBuilder: (ctx, i) {
                if (i >= _items.length) {
                  _more();
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return ArticleCard(article: _items[i], site: widget.site);
              },
            ),
    );
  }
}
