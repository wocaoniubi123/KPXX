import 'package:flutter/material.dart';

import 'api.dart';
import 'fetched_image.dart';
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
  late final Api _api = Api(hosts: widget.site.hosts);
  ArticleDetail? _detail;
  String? _error;
  List<Article> _series = []; // 当前系列文章（含当前集）

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
    return [
      if (fresh.videoUrl.isNotEmpty) fresh.videoUrl,
      if (fresh.videoUrlH265.isNotEmpty) fresh.videoUrlH265,
    ];
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
    // 2026-09-01T14:57:00+00:00 -> 2026-09-01
    if (iso.length < 10) return iso;
    return iso.substring(0, 10);
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
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
                    // 视频区（无视频时显示封面/占位；用正文首图做海报）
                    PlayerWidget(
                      sources: [
                        if (d.videoUrl.isNotEmpty) d.videoUrl,
                        if (d.videoUrlH265.isNotEmpty) d.videoUrlH265,
                      ],
                      referer: _api.base,
                      poster: d.images.isNotEmpty ? d.images.first : '',
                      onRefreshSources: _refreshSources,
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
                              Text('${_series.length} 集',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey)),
                            ],
                          ),
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
                        ],
                      ),
                    ),
                  ],
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
