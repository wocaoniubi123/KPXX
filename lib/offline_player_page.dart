import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'api.dart';
import 'app_background.dart';
import 'app_bg.dart';
import 'base/downloads/download_manager.dart';
import 'base/downloads/download_model.dart';
import 'base/downloads/download_sheet.dart';
import 'favorites.dart';
import 'player_widget.dart';
import 'models.dart'; // ArticleDetail（未下载集按集号在线取源）
import 'settings.dart'; // PlayHistory / PlayRecord（播放记录同步）
import 'sites.dart';

/// 离线播放页（用户 2026-10-19 拍板；同日二次拍板「布局 1:1 照在线详情页」）。
///
/// 从「下载」tab 点已完成的剧进来：
/// - 播放器固定顶部，**本地文件优先（0 网络）**；
/// - **内容区完全不联网**：标题 / 时间 / 集数 / 时长 / 站点元信息 / 简介全部来自
///   [DownloadTask]（下载时快照）—— 用户口径「其他都跟视频一起保存好」；
/// - 布局与 `detail_page.dart` 的内容区一致（标题 18 粗体 + 元信息 Row + 选集 + 简介）；
///   按用户要求**不显示**剧照 / 相关推荐 / 分类标签；
/// - **选集 A 方案**：全部集都显示 —— ✅ 已下载 = 本地播；☁️ 未下载 = 在线播（断网提示，
///   点未下载集时才按需取源）；
/// - 控制条「↓」= 下载当前这一集（与详情页同一套状态口径：done/downloading/none）。
class OfflinePlayerPage extends StatefulWidget {
  final DownloadTask task;

  /// 从「播放记录」点进来时传：续播位置（null = 从头播）
  final Duration? initialPosition;

  /// 从「播放记录」点进来时传：默认播哪一集（null = 第一个已下载的集）
  final int? initialEpisodeIndex;

  const OfflinePlayerPage({
    super.key,
    required this.task,
    this.initialPosition,
    this.initialEpisodeIndex,
  });

  @override
  State<OfflinePlayerPage> createState() => _OfflinePlayerPageState();
}

class _OfflinePlayerPageState extends State<OfflinePlayerPage> {
  DownloadTask get _t => widget.task;

  SiteEntry? _site;
  Api? _api;
  VideoSwitcher? _switcher;

  /// 在线详情缓存（未下载集在线播 / 补下时**按集号**取源；一次请求后复用）
  ArticleDetail? _detailCache;

  /// 未下载集单独取到的在线源（详情里没有时的兜底；index → url）
  final Map<int, String> _extraSources = <int, String>{};

  /// 稳定 key：换集交给播放器内部复用同一实例（与详情页同一口径，别换 key）
  final Key _playerKey = const ValueKey<String>('offline-player');

  /// 上一轮看到的"当前集下载态"——只有它变了才整页重建
  /// （DownloadManager 进度回调是 250ms 节流的，不筛会让播放器跟着每 250ms 重建）
  String _lastStatus = '';

  /// 播放进度记录（用户 2026-10-19 拍板：离线播放也同步到播放记录 / 收藏进度，口径与在线详情页一致）
  Duration _lastPos = Duration.zero;
  Duration _lastDur = Duration.zero;
  int _lastReportMs = 0;

  /// 进入时**续播位置**（用户 2026-10-19：从下载页等入口进来没显式传参 ⇒ 用播放记录兜底）。
  /// `PlayerWidget` 只在首次生效一次（换集不重新 seek）⇒ 换集后不会跳位置 ✅
  Duration? _resumeAt;

  @override
  void initState() {
    super.initState();
    _site = _findSite(_t.site);
    final site = _site;
    if (site != null) _api = Api(site: site);

    final eps = _t.episodes;
    final sw = VideoSwitcher(eps.length);
    // 默认从"第一个已下载的集"开始；一集都没下完就第 0 集
    var start = 0;
    for (var i = 0; i < eps.length; i++) {
      if (_localFile(i) != null) {
        start = i;
        break;
      }
    }
    // 从「播放记录」点进来：记录里的集号优先
    // ★ 用户 2026-10-19：从「下载页」点卡片进来时**没有显式传参** ⇒ 这里用播放记录兜底
    //   （之前只认显式参数 ⇒ 离线播放总是从"第一个已下载的集 / 0 秒"开始 ☠）
    final rec = PlayHistory.i.find(_t.site, _t.detailUrl);
    final want = widget.initialEpisodeIndex ?? rec?.videoIndex;
    if (want != null && want >= 0 && want < eps.length) {
      start = want;
    }
    sw.index.value = start;
    // 续播位置：显式参数优先；否则用记录（要求：记录集号 == 启动集号、没看完、位置有效）
    if (widget.initialPosition != null) {
      _resumeAt = widget.initialPosition;
    } else if (rec != null &&
        !rec.finished &&
        rec.videoIndex == start &&
        rec.position > Duration.zero) {
      _resumeAt = rec.position;
    }
    sw.index.addListener(_onIndexChanged);
    _switcher = sw;
    _lastStatus = _statusFor(start);

    DownloadManager.i.addListener(_onManagerChanged);
  }

  @override
  void dispose() {
    // 离开页面补写一次播放记录（与在线详情页"离开时补写"同款）。
    // ⚠️ **不能在 dispose 里同步写**：dispose 发生在 `BuildOwner.finalizeTree`（框架已锁）阶段，
    //    `PlayHistory.touch` / `Favorites.touch` 里的 notifyListeners 会让仍在树上的
    //    ListenableBuilder setState ⇒ `setState() called when widget tree was locked`
    //    （🛢️ 实测完整堆栈：_writeRecord ← dispose ← finalizeTree）。
    //    ⇒ 这里只取快照，落盘推到事件队列（那时框架已解锁）。
    final pos = _lastPos;
    final dur = _lastDur;
    if (pos > Duration.zero || dur > Duration.zero) {
      final eps = _t.episodes;
      final idx = eps.isEmpty
          ? 0
          : (_switcher?.index.value ?? 0).clamp(0, eps.length - 1).toInt();
      unawaited(
          Future<void>(() => _writeRecordAt(idx, pos, dur, false, force: true)));
    }
    DownloadManager.i.removeListener(_onManagerChanged);
    final sw = _switcher;
    if (sw != null) {
      sw.index.removeListener(_onIndexChanged);
      sw.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 数据小工具
  // ---------------------------------------------------------------------------

  static SiteEntry? _findSite(String name) {
    for (final e in kSites) {
      if (e.name == name) return e;
    }
    return null;
  }

  /// 已下载的本地文件（记录说 done 还不够——文件被人删了就当没下）
  String? _localFile(int i) {
    final eps = _t.episodes;
    if (i < 0 || i >= eps.length) return null;
    final p = eps[i].localPath;
    if (p.isEmpty) return null;
    if (!File(p).existsSync()) return null;
    return p;
  }

  bool _isDone(int i) => _localFile(i) != null;

  /// 当前集的播放源：本地优先（file:// 交给 mpv，0 网络）；未下载 ⇒ 在线
  /// （点选未下载集时按需取到的兜底源）
  List<String> _sourcesFor(int i) {
    final local = _localFile(i);
    if (local != null) return <String>[Uri.file(local).toString()];
    final extra = _extraSources[i];
    if (extra != null && extra.isNotEmpty) return <String>[extra];
    return const <String>[];
  }

  Map<String, String>? _headersFor(int i) {
    final eps = _t.episodes;
    if (i < 0 || i >= eps.length) return null;
    return eps[i].headers;
  }

  /// 当前集的下载态：'done' / 'downloading' / 'none'（与详情页控制条同口径）
  String _statusFor(int i) {
    final mgr = DownloadManager.i;
    final key = _t.key;
    if (mgr.isEpisodeDownloaded(key, i)) return 'done';
    if (mgr.isEpisodeDownloading(key, i)) return 'downloading';
    final eps = _t.episodes;
    if (i >= 0 && i < eps.length) {
      final ep = eps[i];
      if (ep.wanted &&
          (ep.status == EpStatus.queued ||
              ep.status == EpStatus.downloading)) {
        return 'downloading';
      }
    }
    return 'none';
  }

  /// 绝对播放页 URL → 相对路径（Api 内部按站点 base 拼；传绝对会被拼坏）
  static String _relPath(String abs) {
    final u = Uri.tryParse(abs);
    if (u == null) return abs;
    return u.hasQuery ? '${u.path}?${u.query}' : u.path;
  }

  // ---------------------------------------------------------------------------
  // 按需取源（只给"未下载集在线播"用；页面内容仍全部来自 DownloadTask）
  // ---------------------------------------------------------------------------

  /// 未下载集点击时还没有源 ⇒ 现取一次（失败给「未下载」提示）
  ///
  /// ★ 用户 2026-10-19（真机：点 2~7 集全是第 1 集）🛢️：通用 `.dplayer` 站点**没有子文章 URL**
  ///   （7 块视频全在主页面）⇒ 老的 `ep.lazyUrl ?? _relPath(ep.playUrl)` 会回退到**详情页本身**
  ///   ⇒ `videoSourcesAt(详情页)` 永远只拿**第一块**的源 ☠
  ///   ⇒ 改为解析详情页后**按集号取 `videos[i].sources`**（缓存一次），子文章/播放页只作兜底。
  Future<void> _ensureOnlineSource(int i) async {
    final api = _api;
    if (api == null) return;
    final eps = _t.episodes;
    if (i < 0 || i >= eps.length) return;
    try {
      final srcs = await _onlineSourcesFor(i);
      if (!mounted || srcs.isEmpty) return;
      setState(() => _extraSources[i] = srcs.first);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(seconds: 1),
        content: Text('这一集还没下载，联网后才能看'),
      ));
    }
  }

  /// 在线取**第 i 集**的源：优先详情页按集号（一次请求 + 缓存），兜底子文章/播放页。
  Future<List<String>> _onlineSourcesFor(int i) async {
    final api = _api;
    final eps = _t.episodes;
    if (api == null || i < 0 || i >= eps.length) return const <String>[];
    var d = _detailCache;
    if (d == null) {
      try {
        d = await api.detail(_t.detailUrl);
        _detailCache = d;
      } catch (_) {
        d = null;
      }
    }
    if (d != null && i < d.videos.length) {
      final direct = d.videos[i].sources.where(_isHttp).toList();
      if (direct.isNotEmpty) return direct;
    }
    final ep = eps[i];
    final url = ep.lazyUrl ?? _relPath(ep.playUrl);
    if (url.isEmpty) return const <String>[];
    try {
      return (await api.videoSourcesAt(url)).where(_isHttp).toList();
    } catch (_) {
      return const <String>[];
    }
  }

  // ---------------------------------------------------------------------------
  // 交互
  // ---------------------------------------------------------------------------

  /// 播放进度回调（PlayerWidget 回调；这里再按 10 秒节流，与在线详情页同口径）
  void _onProgress(Duration pos, Duration dur, bool finished) {
    _lastPos = pos;
    _lastDur = dur;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (finished || now - _lastReportMs >= 10000) {
      _lastReportMs = now;
      _writeRecord(pos, dur, finished, force: finished);
    }
  }

  /// 写播放记录 + 已收藏那条的进度（用户 2026-10-19 拍板：离线播放与在线同口径同步）
  void _writeRecord(Duration pos, Duration dur, bool finished,
      {bool force = false}) {
    final eps = _t.episodes;
    final idx = eps.isEmpty
        ? 0
        : (_switcher?.index.value ?? 0).clamp(0, eps.length - 1).toInt();
    _writeRecordAt(idx, pos, dur, finished, force: force);
  }

  /// [_writeRecord] 的"集号已定"版本 —— **dispose 里只能用这个**（且必须由调用方
  /// 推到框架解锁之后，见 dispose 注释）。
  void _writeRecordAt(int index, Duration pos, Duration dur, bool finished,
      {bool force = false}) {
    final eps = _t.episodes;
    final idx = eps.isEmpty ? 0 : index.clamp(0, eps.length - 1).toInt();
    PlayHistory.i.touch(
      PlayRecord(
        site: _t.site,
        url: _t.detailUrl, // 相对路径，与在线记录同一个 key
        title: _t.title,
        cover: _t.coverUrl, // 下载时存的就是"列表封面"（用户 2026-10-19 口径）
        videoIndex: idx,
        total: eps.length,
        position: pos,
        duration: dur,
        finished: finished,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        quality: null, // 离线页没有清晰度选择
      ),
      force: force,
    );
    // 只更新"已存在的收藏"，绝不新建/删除（Favorites.touch 的既有语义）
    Favorites.i.touch(
      _t.site,
      _t.detailUrl,
      idx,
      position: pos,
      duration: dur,
      total: eps.length,
    );
  }

  void _onIndexChanged() {
    if (!mounted) return;
    final i = _switcher?.index.value ?? 0;
    _lastStatus = _statusFor(i);
    setState(() {});
  }

  void _onManagerChanged() {
    if (!mounted) return;
    final i = _switcher?.index.value ?? 0;
    final s = _statusFor(i);
    if (s == _lastStatus) return;
    _lastStatus = s;
    // ⚠️ 管理器的通知可能落在"框架正在 build/layout"的瞬间 ⇒ 直接 setState 会报
    // `setState() called when widget tree was locked`（实测返回本页时出现过 3 次）。
    // 统一推到本帧结束再刷（最多晚一帧，无感）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _selectEpisode(int i) {
    final sw = _switcher;
    if (sw == null || i == sw.index.value) return;
    sw.index.value = i; // 播放器 didUpdateWidget 会按新 sources 换片
    setState(() {});
    if (!_isDone(i) && _sourcesFor(i).isEmpty) {
      unawaited(_ensureOnlineSource(i));
    }
  }

  /// 控制条「↓」：下载当前这一集（未下载时可用）—— 内部走 [_enqueueEpisodes]，行为不变
  Future<void> _downloadCurrent() async {
    final sw = _switcher;
    if (sw == null) return;
    final i = sw.index.value;
    if (i < 0 || i >= _t.episodes.length) return;
    final r = await _enqueueEpisodes(<int>[i]);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (r.ok > 0) {
      messenger.showSnackBar(const SnackBar(
        duration: Duration(seconds: 1),
        content: Text('已加入下载'),
      ));
    } else {
      messenger.showSnackBar(const SnackBar(
        duration: Duration(seconds: 1),
        content: Text('这一集取不到源，暂时没法下载'),
      ));
    }
  }

  /// 右上角「下载」→ 多选弹层（列出全部集，勾选补下载）
  Future<void> _openDownloadSheet() async {
    final eps = _t.episodes;
    if (eps.isEmpty) return;
    final r = await showModalBottomSheet<DlSubmitResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DownloadSheet(
        labels: <String>[for (final e in eps) e.label],
        isDone: _isDone,
        // 与播放器控制条同一口径：queued 也算"下载中"（置灰）
        isBusy: (i) => _statusFor(i) == 'downloading',
        isQueued: _isQueuedEpisode,
        onSubmit: _enqueueEpisodes,
      ),
    );
    if (!mounted || r == null) return;
    final msg = StringBuffer('已加入下载 ${r.ok} 集');
    if (r.failed.isNotEmpty) {
      msg.write('，${r.failed.length} 集取源失败：${r.failed.join('、')}');
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 1),
      content: Text(msg.toString()),
    ));
  }

  /// 把选中的集取源后合并进下载任务（弹层提交 / 控制条↓ 共用）。
  /// 源优先级（用户口径）：`_sourcesFor` 里的 http(s) → 详情里的 sources → 现取子文章/播放页；
  /// 取不到源 ⇒ 该集记失败、不阻塞其它；一集都没成功 ⇒ 不入队。
  Future<DlSubmitResult> _enqueueEpisodes(List<int> indices) async {
    final eps = _t.episodes;
    final picked = <DownloadEpisode>[];
    final failed = <String>[];
    for (final i in indices) {
      if (i < 0 || i >= eps.length) continue;
      final ep = eps[i];
      final srcs = await _httpSourcesFor(i);
      if (srcs.isEmpty) {
        failed.add(ep.label);
        continue;
      }
      picked.add(DownloadEpisode(
        // ⚠️ 用记录里的真实集号（老任务可能不是 0..N 连续；正常任务与位置相同）
        index: ep.index,
        label: ep.label,
        playUrl: ep.playUrl,
        lazyUrl: ep.lazyUrl,
        headers: _headersFor(i),
        sourceUrl: srcs.first,
        wanted: true,
      ));
    }
    if (picked.isEmpty) return DlSubmitResult(0, failed);
    await DownloadManager.i.enqueueTask(DownloadTask(
      key: _t.key,
      site: _t.site,
      detailUrl: _t.detailUrl,
      title: _t.title,
      coverUrl: _t.coverUrl,
      intro: _t.intro,
      time: _t.time,
      duration: _t.duration,
      metaLine: _t.metaLine,
      episodes: picked,
    ));
    return DlSubmitResult(picked.length, failed);
  }

  /// 能用来**下载**的 http(s) 源（本地 file:// 不算）；优先级见 [_enqueueEpisodes]
  Future<List<String>> _httpSourcesFor(int i) async {
    var srcs = _sourcesFor(i).where(_isHttp).toList();
    if (srcs.isNotEmpty) return srcs;
    // ★ 与 `_ensureOnlineSource` 同口径：**按集号**取（别回退详情页拿第一块 ☠）
    srcs = await _onlineSourcesFor(i);
    if (srcs.isNotEmpty && mounted) {
      setState(() => _extraSources[i] = srcs.first);
    }
    return srcs;
  }

  static bool _isHttp(String s) =>
      s.startsWith('http://') || s.startsWith('https://');

  /// 已加入下载但还在排队（弹层显示「等待中」；正在跑的不算）
  bool _isQueuedEpisode(int i) {
    final eps = _t.episodes;
    if (i < 0 || i >= eps.length) return false;
    final ep = eps[i];
    return ep.wanted && ep.status == EpStatus.queued;
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final sw = _switcher;
    final eps = _t.episodes;
    final idx = eps.isEmpty
        ? 0
        : (sw?.index.value ?? 0).clamp(0, eps.length - 1).toInt();
    final intro = _t.intro; // 内容全部来自下载快照（不再联网补全）
    final sources = _sourcesFor(idx);
    final done = _isDone(idx);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        systemOverlayStyle: kStatusOverlay,
        title: Text(_t.site),
        foregroundColor: kTxt,
        actions: [
          // ★ 下载（用户 2026-10-19）：不用回在线详情页，直接勾选补下别的集
          IconButton(
            tooltip: '下载',
            icon: const Icon(Icons.download_outlined),
            onPressed: eps.isEmpty ? null : _openDownloadSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          if (eps.isNotEmpty)
            PlayerWidget(
              key: _playerKey,
              switcher: sw,
              sources: sources,
              referer: _api?.base ?? '',
              poster: _t.coverUrl,
              title: _t.title,
              epLabels: <String>[for (final e in eps) e.label],
              // 未下载 + 没源：把取源交给播放器的按需兜底
              lazyUrl: (done || sources.isNotEmpty)
                  ? null
                  : (eps[idx].lazyUrl ?? _relPath(eps[idx].playUrl)),
              // ⚠️ 用户 2026-10-19（真机：记录在第 3 集却播第 1 集）🛢️：
              //   `lazyUrl` 只是"有源可取"的**占位**（PlayerWidget 仅在 lazyUrl!=null 时才调 onFetchSources）；
              //   真正的源必须由 onFetchSources**按当前集号**取 —— 之前传 `_api.videoSourcesAt`，
              //   拿到的是 lazyUrl（通用 `.dplayer` 站没有子文章 URL ⇒ 回退详情页）⇒ 永远返回第一块的源 ☠
              onFetchSources: (_) => _onlineSourcesFor(idx),
              httpHeaders: _headersFor(idx),
              onDownloadCurrent: _downloadCurrent,
              downloadStatus: _statusFor(idx),
              // 用户 2026-10-19 拍板：离线播放也同步播放记录 / 收藏进度
              onProgress: _onProgress,
              // 续播到上次位置（显式参数 / 播放记录兜底，见 initState）——PlayerWidget 语义：只生效一次
              initialPosition: _resumeAt,
            ),
          Expanded(
            child: SingleChildScrollView(
              // 与 detail_page.dart:1152 的内容区同款：Padding(all:12) + Column(start)
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题（与详情页同字号/字重，detail_page.dart:1157）
                    Text(
                      _t.title,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: kTxt),
                    ),
                    const SizedBox(height: 8),
                    // 元信息行：顺序/间距/字号照 detail_page.dart:1163-1204
                    Row(
                      children: [
                        if (_fmtTime(_t.time).isNotEmpty) ...[
                          const Icon(Icons.local_fire_department,
                              size: 16, color: Colors.red),
                          const SizedBox(width: 4),
                          Text(
                            _fmtTime(_t.time),
                            style: TextStyle(fontSize: 12, color: kTxtSub),
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (eps.isNotEmpty)
                          Text('${eps.length} 集',
                              style: TextStyle(fontSize: 12, color: kTxtSub)),
                        if (_t.duration.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Text('时长 ${_t.duration}',
                              style: TextStyle(fontSize: 12, color: kTxtSub)),
                        ],
                        if (_t.metaLine.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              _t.metaLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: kTxtSub),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (eps.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _section('选集'),
                      const SizedBox(height: 8),
                      _episodeChips(eps, idx),
                    ],
                    if (intro.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _section('简介'),
                      const SizedBox(height: 6),
                      Text(
                        intro,
                        style:
                            TextStyle(fontSize: 12.5, height: 1.6, color: kTxt),
                      ),
                    ],
                    // 剧照 / 相关推荐 / 分类标签：用户明确不要，一个都不渲染
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 时间显示（**与 `detail_page.dart:998-1005` 的 `_fmtTime` 同款**，直接复制；
  /// 私有方法没法跨文件复用，按用户口径不抽公共组件）。
  String _fmtTime(String iso) {
    if (iso.isEmpty) return '';
    // "2026-09-28 17:34:23"（站点自带时分秒）→ 原样显示
    if (iso.length >= 19 && iso[10] == ' ') return iso;
    // 2026-09-01T14:57:00+00:00 -> 2026-09-01
    if (iso.length < 10) return iso;
    return iso.substring(0, 10);
  }

  Widget _section(String title) => Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: kTxt,
        ),
      );

  /// 选集：全部集都列（✅ 已下载 / ☁️ 未下载），当前集橙底
  Widget _episodeChips(List<DownloadEpisode> eps, int cur) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (var i = 0; i < eps.length; i++)
          GestureDetector(
            onTap: () => _selectEpisode(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: i == cur ? const Color(0xFFE8590C) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: i == cur
                      ? const Color(0xFFE8590C)
                      : (AppBg.i.isDark
                          ? const Color(0x59FFFFFF)
                          : const Color(0x593C3C3C)),
                ),
              ),
              child: Text(
                '${eps[i].label}${_isDone(i) ? ' ✅' : ' ☁️'}',
                style: TextStyle(
                  fontSize: 12,
                  color: i == cur ? Colors.white : kTxt,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
