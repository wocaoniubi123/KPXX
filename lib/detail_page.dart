import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';
import 'player_widget.dart';

/// 文章详情：顶部视频 + 标题/标签 + 选集 + 正文图片。
class DetailPage extends StatefulWidget {
  final String baseUrl; // /archives/xxx/
  const DetailPage({super.key, required this.baseUrl});

  @override
  State<DetailPage> createState() => DetailPageState();
}

class DetailPageState extends State<DetailPage> {
  final Api _api = Api();
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
      appBar: AppBar(title: const Text('详情')),
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
                      videoUrl: d.videoUrl.isNotEmpty
                          ? d.videoUrl
                          : d.videoUrlH265,
                      referer: _api.base,
                      poster: d.images.isNotEmpty ? d.images.first : '',
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
                          const SizedBox(height: 12),
                          // 选集横条
                          if (_series.isNotEmpty) _buildSeriesStrip(d),
                          const SizedBox(height: 8),
                          // 正文图片
                          for (final img in d.images)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: CachedNetworkImage(
                                imageUrl: img,
                                fit: BoxFit.contain,
                                memCacheWidth: 1280,
                                placeholder: (_, __) => const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(32),
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text('图片加载失败',
                                        style: TextStyle(
                                            color: Colors.grey, fontSize: 12)),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSeriesStrip(ArticleDetail d) {
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
                      builder: (_) => DetailPage(baseUrl: a.url),
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
