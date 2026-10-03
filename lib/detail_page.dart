import 'package:flutter/material.dart';

import 'app_bg.dart';
import 'api.dart';
import 'app_background.dart';
import 'fetched_image.dart';
import 'home_page.dart';
import 'models.dart';
import 'player_widget.dart';
import 'settings.dart';
import 'sites.dart';
import 'web_page.dart';

/// 文章详情：顶部视频 + 标题/标签 + 选集 + 正文图片。
class DetailPage extends StatefulWidget {
  final SiteEntry site;
  final String baseUrl; // /archives/xxx/

  /// 从「播放记录」点进来时传：续播位置。
  /// 从站点入口（宫格/列表/相关推荐/标签…）进来一律不传 → null → 从头播（用户要求）。
  final Duration? initialPosition;

  /// 从「播放记录」点进来时传：篇内第几个视频（多视频文章续播用）
  final int initialVideoIndex;

  /// 列表页已经加载过的封面 URL（记播放记录当封面用，零额外请求）；
  /// 从站点入口/文字链进来时可能为空 → 记录里退回正文首图
  final String listCover;

  const DetailPage({
    super.key,
    required this.site,
    required this.baseUrl,
    this.initialPosition,
    this.initialVideoIndex = 0,
    this.listCover = '',
  });

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

  /// 内嵌播放器的 key：离开页面时要直接从它身上取最后位置（补写播放记录）
  final GlobalKey<PlayerWidgetState> _playerKey =
      GlobalKey<PlayerWidgetState>();

  /// 「清晰度」用户手选的档（null = 用 Api 给的默认档：那已经是 720P 优先，
  /// 没有 720P 就是最高档 —— 见 api.dart 的 `_phDetail`）。只有多档的视频才有意义。
  String? _quality;

  /// 从源 URL 里抠清晰度数字。兼容两种命名：
  /// Pornhub `.../1080P_4000K_xxx.mp4/master.m3u8`（大写 P + 下划线）、
  /// XVideos `.../hls-720p.m3u8`（小写 p，后跟 `.`/`?` 等非数字）。
  /// 抠不到（单档/无档位信息）返回 ''。
  ///
  /// ⚠️ 2026-10-02 xHamster 实锤：**必须先取路径最后一段（文件名）再匹配** ——
  /// 它的 URL 里带着 `media=hls4/multi=256x144:144p,426x240:240p,854x480:480p,…`
  /// 这种**解析参数**，直接对整个 URL 匹配会**先命中参数里的 `144p`**，
  /// 结果 5 档被全部认成 144P（实测：1080p/720p/480p/240p/144p → 全报 144P）。
  /// 只看文件名对其它站也更稳（XV 的 `hls-720p.m3u8`、PH 的 `1080P_4000K_…` 照样命中）。
  static String _qualityOf(String u) {
    final path = u.split('?').first;
    final name = path.substring(path.lastIndexOf('/') + 1);
    return RegExp(r'(\d{3,4})[pP](?![0-9])').firstMatch(name)?.group(1) ?? '';
  }

  /// 这一集**实际有的**档位（去重、数字从大到小）。多数站没有多档 → 返回空
  static List<String> _qualitiesOf(List<String> srcs) {
    final byQ = <String, int>{};
    for (final u in srcs) {
      final q = _qualityOf(u);
      if (q.isNotEmpty) byQ[q] = int.parse(q);
    }
    final ks = byQ.keys.toList()..sort((a, b) => byQ[b]!.compareTo(byQ[a]!));
    return ks;
  }

  /// 播放器实际会先用哪一档 = 源列表第一条的清晰度（Api 已按"720P 优先"排好）
  static String _firstQuality(List<String> srcs) =>
      srcs.isEmpty ? '' : _qualityOf(srcs.first);

  /// 交给播放器的源：选中的档排最前（播放器按顺序逐个试，失败自动往下走）
  static List<String> _orderByQuality(List<String> srcs, String? q) {
    if (q == null || q.isEmpty) return srcs;
    return [
      ...srcs.where((u) => _qualityOf(u) == q),
      ...srcs.where((u) => _qualityOf(u) != q),
    ];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---------------------------------------------------------------------------
  // 播放记录：详情页是唯一的归档点（播放器只管每 10 秒回调一次 + 离开时给最后位置）

  /// 最后一次上报的进度（离开页面时补写用）
  Duration? _lastPos;
  Duration _lastDur = Duration.zero;
  bool _lastFinished = false;

  /// 播放器回调：位置/时长/播完都齐了才写（时长还没拿到就不记，免得进度算成 0）
  void _reportProgress(Duration pos, Duration dur, bool finished) {
    _lastPos = pos;
    _lastDur = dur;
    _lastFinished = finished;
    if (dur <= Duration.zero) return;
    _writeRecord(pos: pos, dur: dur, finished: finished);
  }

  /// 离开时补写：播放器实例还在（dispose 前调用），位置从它身上直接取
  void _flushProgress() {
    final kp = _playerKey.currentState?.player;
    final pos = kp?.position ?? _lastPos;
    final dur = kp?.value.duration ?? _lastDur;
    if (pos == null || dur <= Duration.zero || pos <= Duration.zero) return;
    _writeRecord(
      pos: pos,
      dur: dur,
      finished: kp?.value.completed ?? _lastFinished,
    );
  }

  void _writeRecord({
    required Duration pos,
    required Duration dur,
    required bool finished,
  }) {
    final d = _detail;
    if (d == null || d.videos.isEmpty) return; // 纯图文页不记
    // 站点名要和 kSites 里的对得上（记录列表点回来时要靠它反查 SiteEntry）；
    // 详情页收的 site 本来就是 kSites 里那一条，直接用它的 name
    PlayHistory.i.touch(PlayRecord(
      site: widget.site.name,
      url: widget.baseUrl,
      title: d.title,
      cover: _coverOf(d),
      videoIndex: _switcher?.index.value ?? widget.initialVideoIndex,
      position: pos,
      duration: dur,
      finished: finished,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  /// 记录列表的封面：优先用正文首图（详情页已经下载过、多半在内存缓存里），
  /// 没有再退回列表页传来的封面；都没有就空着（卡片会自适应不显示封面区）
  String _coverOf(ArticleDetail d) {
    if (d.images.isNotEmpty) return d.images.first;
    return widget.listCover;
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
      final sw = VideoSwitcher(d.videos.length)
        ..index.addListener(_onVideoIndexChanged);
      // 从播放记录进来：定位到上次看的第几集（越界就回第一集）
      if (widget.initialVideoIndex > 0 &&
          widget.initialVideoIndex < d.videos.length) {
        sw.index.value = widget.initialVideoIndex;
      }
      _switcher = sw;
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
        builder: (_) => PageBg(child: WebPage(
          title: widget.site.name,
          url: 'https://${widget.site.hosts.first}${widget.baseUrl}',
        )),
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

  /// 「清晰度」那一段（只有多档才画；其它站返回空盒子，不占位）。
  /// 位置照模拟器定稿：标题/选集之后、剧照之前。
  Widget _qualitySection(List<ArticleVideo> videos, int idx) {
    if (videos.isEmpty) return const SizedBox.shrink();
    final srcs = videos[idx].sources;
    final qs = _qualitiesOf(srcs);
    if (qs.length < 2) return const SizedBox.shrink();
    // 手选的档要是这一集没有（换集后可能发生），就退回"播放器实际会用的那档"
    final active = (_quality != null && qs.contains(_quality))
        ? _quality!
        : _firstQuality(srcs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text('清晰度',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: kTxt)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in qs)
              OutlinedButton(
                // 已选中的那颗点自己不做任何事（免得无谓重开一次）
                onPressed: () {
                  if (q == active) return;
                  _pickQuality(q, srcs);
                },
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  side: BorderSide(color: kChipBorder),
                ),
                // 选中态照 App 里筛选按钮的老规矩：橙色 + " ●"
                child: Text(q == active ? '${q}P ●' : '${q}P',
                    style: TextStyle(
                        fontSize: 13,
                        color: q == active ? const Color(0xFFE8590C) : kTxt)),
              ),
          ],
        ),
      ],
    );
  }

  /// 换档：记住选择，再让播放器用**同一个实例**换一批源重开（不换集、不重建实例）。
  /// **保留播放进度**：先记下当前位置，交给播放器在新源起播后跳过去。
  /// ⚠️ 用 `lastKnownPosition`（最后**真实前进过**的位置）而不是 `position`：
  /// 换源会把 state 里的 position 重置为 0，取到 0 就等于"从头播"。
  void _pickQuality(String q, List<String> srcs) {
    final st = _playerKey.currentState;
    final kp = st?.player;
    final Duration? pos = (kp == null)
        ? null
        : (kp.lastKnownPosition > Duration.zero ? kp.lastKnownPosition : kp.position);
    setState(() => _quality = q);
    st?.switchSources(_orderByQuality(srcs, q), resumeTo: pos);
  }

  /// 篇内序号变了整页重建（播放器据此换源，列表高亮跟着变）
  void _onVideoIndexChanged() {
    if (mounted) setState(() {});
  }

  /// 点击选集就**立即**开始取源（合集 / 黄果选集）——不等播放器重建那几帧；
  /// 播放器随后调 videoSourcesAt 会共享同一个请求（Api 里做了去重）。
  /// 用户要求："点击就立马执行提取播放"。
  void _prefetchLazy(ArticleVideo v) {
    final lz = v.lazyUrl;
    if (lz == null) return;
    _api.videoSourcesAt(lz).then<void>((_) {}, onError: (_) {});
  }

  @override
  void dispose() {
    _flushProgress(); // 离开详情页：把最后位置补写进播放记录（此时播放器还活着）
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
    // 整页跟着背景明暗重建（顶栏 / 标题 / 小字 / 小节标题都读 kTxt）。
    // ⚠️ 必须在 builder 里重建页面：把 widget 实例直接交给 builder，
    // Flutter 会因"实例相同"跳过整棵子树的重建，isDark 翻了也不会刷。
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => _pageView(context),
    );
  }

  Widget _pageView(BuildContext context) {
    final d = _detail;
    final videos = d?.videos ?? const <ArticleVideo>[];
    final idx = videos.isEmpty
        ? 0
        : (_switcher?.index.value ?? 0).clamp(0, videos.length - 1).toInt();
    return Scaffold(
      // 透明：详情页也吃根层背景图（播放器画面本身是视频纹理，不受影响）
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        systemOverlayStyle: kStatusOverlay,
        title: Text(widget.site.name),
        foregroundColor: kTxt, // 标题/图标直接压在图上 → 跟明暗
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
              // ⚠️ 2026-10-03（用户要求）：下滑看详情信息时，**内嵌播放器一直置顶** ✓
              // 原来播放器是 ListView 的第一个子项 ✗ → 一滚就跟着走、画面看不见了 ✓
              // 现在：播放器固定顶部（不滚动 ✓），下方信息**单独滚动** ✓
              : Column(
                  children: [
                      if (videos.isNotEmpty || d.images.isNotEmpty)
                        PlayerWidget(
                          key: _playerKey,
                        // 不换 key：换片由播放器内部复用同一实例开新源
                        // （重建实例会让全屏页拿着的旧实例失效 → 黑屏）
                          switcher: _switcher,
                          sources: videos.isEmpty
                              ? const []
                              : _orderByQuality(videos[idx].sources, _quality),
                          referer: _api.base,
                          poster: d.images.isNotEmpty ? d.images.first : '',
                          onRefreshSources: _refreshSources,
                          // 合集类：当前这一集没有源时，按需去子文章取
                          lazyUrl:
                              videos.isEmpty ? null : videos[idx].lazyUrl,
                          onFetchSources: _api.videoSourcesAt,
                          // 续播：只有从「播放记录」点进来才传（站点入口进来是 null）
                          initialPosition: widget.initialPosition,
                          onProgress: _reportProgress,
                        ),
                    Expanded(
                      child: ListView(
                          children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.title,
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: kTxt)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.local_fire_department,
                                  size: 16, color: Colors.red),
                              const SizedBox(width: 4),
                              Text(
                                _fmtTime(d.time),
                                style: TextStyle(
                                    fontSize: 12, color: kTxtSub),
                              ),
                              const SizedBox(width: 12),
                              // 显示本篇的视频数（原来显示的是"同系列文章数"，
                              // 一篇挂多个视频但没有"第N集"的文章会显示成 0）；
                              // 图文帖（没有视频）就不显示这一段，别写"0 集"
                              if (videos.isNotEmpty)
                                Text('${videos.length} 集',
                                    style: TextStyle(
                                        fontSize: 12, color: kTxtSub)),
                              // 站点自带时长（如 91porna 的 1:00:39、黄果的 3:34）
                              if (d.duration.isNotEmpty) ...[
                                const SizedBox(width: 12),
                                Text('时长 ${d.duration}',
                                    style: TextStyle(
                                        fontSize: 12, color: kTxtSub)),
                              ],
                            ],
                          ),
                          // 多视频文章：列出来可切换（按集数排序）
                          if (videos.length > 1) ...[
                            const SizedBox(height: 14),
                            Text('视频（${videos.length}）',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: kTxt)),
                            const SizedBox(height: 6),
                            // 竖屏封面站（黄果短剧）：选集**横向排、按宽度自动换行**
                            // 的胶囊（这站是"第 N 集"这种短标签，竖排太占地方）；
                            // 其它站保持竖排（标题可能很长）——吃瓜社区的帖子视频
                            // （/archives/）label 是长标题，也走竖排
                            if (widget.site.portraitCovers &&
                                !widget.baseUrl.startsWith('/archives/'))
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final (i, v) in videos.indexed)
                                    InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () {
                                        _prefetchLazy(v); // 点击立即开抓
                                        _switcher?.select(i);
                                      },
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
                                  onTap: () {
                                    _prefetchLazy(v); // 点击立即开抓
                                    _switcher?.select(i);
                                  },
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
                                                    : FontWeight.w500,
                                                color: kTxt),
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
                            Text('简介',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: kTxt)),
                            const SizedBox(height: 6),
                            Text(
                              d.intro,
                              style: TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: kTxt),
                            ),
                          ],
                          // 选集横条（同系列文章）
                          if (_series.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _buildSeriesStrip(),
                          ],
                          // 清晰度：横排胶囊、**只列这一集实际有的档**（高→低），默认选中
                          // 播放器实际会用的那档；只有一档（或没有档位信息）时不占位。
                          _qualitySection(videos, idx),
                          // 剧照：横向小图，点开看大图
                          if (d.images.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text('剧照',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: kTxt)),
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
                                      builder: (_) => PageBg(child: PhotoViewerPage(
                                        urls: d.images,
                                        initial: i,
                                      )),
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
                            Text('相关推荐',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: kTxt)),
                            const SizedBox(height: 6),
                            for (final a in d.related)
                              InkWell(
                                onTap: () {
                                  // 点相关推荐跳走：先把本页播放器停掉
                                  // （不然本页压栈继续放 + 新页也在放 = 两个声音）
                                  _switcher?.pause();
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => PageBg(child: DetailPage(
                                        site: widget.site, baseUrl: a.url)),
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
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: kTxt),
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
        builder: (_) => PageBg(child: TagListPage(
          site: widget.site,
          title: title,
          slug: slug,
          isTag: isTag,
        )),
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
                      builder: (_) => PageBg(child: DetailPage(
                          site: widget.site, baseUrl: a.url)),
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
    // 整页跟着背景明暗重建（顶栏标题 / 尾项文字读 kTxt）
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => _pageView(),
    );
  }

  Widget _pageView() {
    return Scaffold(
      backgroundColor: Colors.transparent, // 同上：吃根层背景图
      appBar: AppBar(
        systemOverlayStyle: kStatusOverlay,
        title: Text(widget.title),
        centerTitle: true,
        foregroundColor: kTxt, // 标题/返回箭头直接压在图上 → 跟明暗
      ),
      body: _items.isEmpty
          ? Center(
              child: _error != null
                  ? Text('加载失败：$_error')
                  : const CircularProgressIndicator())
          : RowsGrid(
              // 竖屏站（黄果）一行 3 个，横屏站一行 2 个
              cols: widget.site.portraitCovers ? 3 : 2,
              // Pektino：瀑布流（横竖混排按顺序填充，不留空档；照站点）
              masonry: _api.ui?.masonry ?? false,
              count: _items.length,
              // 滚动到尾部才构造 → 在那时触发翻页（懒加载）；
              // 到底后显示"没有更多了"，不再空转圈（同列表/搜索页）
              tail: () {
                if (_done) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                        child: Text('没有更多了',
                            style: TextStyle(
                                color: kTxtSub, fontSize: 12))),
                  );
                }
                _more();
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              },
              itemBuilder: (ctx, i) =>
                  ArticleCard(article: _items[i], site: widget.site),
            ),
    );
  }
}
