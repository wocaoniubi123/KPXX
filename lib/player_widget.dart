import 'dart:async';

// ValueListenable 不在 material.dart 的导出里，要单独引
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'fetched_image.dart';
import 'settings.dart';

/// 滑满一屏宽度对应的快进/快退秒数（滑动距离线性映射：滑多少快进多少）
const int _kSwipeSecondsPerScreen = 120;

/// 横向滑动位移 → 秒数（右滑为正，左滑为负）
int _swipeSeconds(double dx, double width) =>
    width <= 0 ? 0 : (dx / width * _kSwipeSecondsPerScreen).round();

Duration _clampDur(Duration d, Duration total) {
  if (d < Duration.zero) return Duration.zero;
  if (total > Duration.zero && d > total) return total;
  return d;
}

String _fmt(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// 篇内视频切换状态：详情页持有，内嵌播放器与全屏页共用同一份。
/// 共用一份是为了避免全屏页拿到"推送那一刻"的序号快照——
/// 那样切到最后一个后按钮状态会不对，再点还可能跳错集。
class VideoSwitcher {
  VideoSwitcher(this.total) : index = ValueNotifier<int>(0);

  /// 篇内视频总数（刷新后会变）
  int total;
  final ValueNotifier<int> index;

  bool get hasNext => index.value < total - 1;

  void next() {
    if (hasNext) index.value++;
  }

  void select(int i) {
    if (i >= 0 && i < total) index.value = i;
  }

  void dispose() => index.dispose();
}

/// 播放器状态快照：把引擎的若干条 stream 合成一个整体状态，UI 只认它。
class KpState {
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;
  final bool error;
  final String errorText; // 引擎的致命日志（便于把黑屏/加载失败的原因显示出来）
  /// 已缓存数据的最后时间戳（绝对值，来自 mpv demuxer-cache-time）。
  /// 注意：它不是"当前位置往后缓冲了多少秒"，别拿它加当前位置。
  final Duration buffer;

  /// 本段是否已播完
  final bool completed;

  /// 音量 0~100
  final double volume;
  const KpState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.error = false,
    this.errorText = '',
    this.buffer = Duration.zero,
    this.completed = false,
    this.volume = 100,
  });

  bool get ready => duration > Duration.zero;

  /// 已经开始播（位置走过 0），用于撤掉 poster
  bool get started => position > Duration.zero;

  KpState copyWith({
    Duration? position,
    Duration? duration,
    bool? playing,
    bool? buffering,
    bool? error,
    String? errorText,
    Duration? buffer,
    bool? completed,
    double? volume,
  }) =>
      KpState(
        position: position ?? this.position,
        duration: duration ?? this.duration,
        playing: playing ?? this.playing,
        buffering: buffering ?? this.buffering,
        error: error ?? this.error,
        errorText: errorText ?? this.errorText,
        buffer: buffer ?? this.buffer,
        completed: completed ?? this.completed,
        volume: volume ?? this.volume,
      );
}

/// 播放器引擎封装（media_kit / libmpv）。
/// 选它而不是 iOS 原生 AVPlayer：AVPlayer 的缓冲与 seek 容差在 iOS 上无法配置，
/// 长视频/加密 HLS 跳转容易长时间卡加载；libmpv 由 FFmpeg 层面处理 HLS，
/// 且 bufferSize 可调（就是网页播放器那种缓冲控制）。
class KpPlayer extends ValueNotifier<KpState> {
  KpPlayer({int bufferMb = 200})
      : _p = Player(
          configuration: PlayerConfiguration(
            bufferSize: bufferMb * 1024 * 1024,
            logLevel: MPVLogLevel.error,
          ),
        ),
        super(const KpState()) {
    // 关键顺序：渲染上下文（VideoController）必须在 player.open() 之前建好。
    // 否则 iOS 上 mpv 打开 vo/libmpv 时会报 "No render context set"，
    // 表现就是只有声音、画面全黑（media-kit issue #1192）。
    _vc = VideoController(_p);
    _subs = [
      _p.stream.position.listen((v) {
        value = value.copyWith(position: v);
        if (v > Duration.zero) _everStarted = true;
      }),
      _p.stream.duration.listen((v) => value = value.copyWith(duration: v)),
      _p.stream.playing.listen((v) => value = value.copyWith(playing: v)),
      _p.stream.buffering.listen((v) => value = value.copyWith(buffering: v)),
      // mpv demuxer-cache-time = 已缓存数据的最后时间戳（绝对位置）
      _p.stream.buffer.listen((v) => value = value.copyWith(buffer: v)),
      _p.stream.completed.listen((v) => value = value.copyWith(completed: v)),
      _p.stream.volume.listen((v) => value = value.copyWith(volume: v)),
      // 引擎的 error 流里也会混入 FFmpeg 的偶发网络错误
      // （如 tcp: ffurl_read returned ...，此时视频往往还在正常播）。
      // 所以：还没播起来时才当失败（用于换源）；已经在播就不弹提示，
      // 真卡住由看门狗负责判断。
      _p.stream.error.listen((e) {
        if (_everStarted) {
          _lastFatal = e;
        } else {
          value = value.copyWith(error: true, errorText: e);
        }
      }),
      // 引擎日志只静默留存最后一条 fatal：不再当错误弹提示
      // （网络类日志如 "tcp: ffurl_read returned ..." 是偶发的，ffmpeg 会自己重试，
      //   拿它当错误会误报；只有真的卡住时才把它作为附注带出来）
      _p.stream.log.listen((log) {
        if (log.level == 'fatal') _lastFatal = '${log.prefix}: ${log.text}';
      }),
    ];
    // 卡住看门狗：播放中位置连续 9 秒不前进 → 判为卡住（真卡住才提示）
    _stallTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = value;
      if (!s.playing || s.error) {
        _stuckMs = 0;
        _lastPos = s.position;
        return;
      }
      if ((s.position - _lastPos).abs().inMilliseconds < 500) {
        _stuckMs += 1000;
        if (_stuckMs >= _stuckLimitMs) {
          _stuckMs = 0;
          value = value.copyWith(
            error: true,
            errorText: _lastFatal.isEmpty
                ? '缓冲超时（网络或片源无响应）'
                : '缓冲超时；引擎日志：$_lastFatal',
          );
        }
      } else {
        _stuckMs = 0;
      }
      _lastPos = s.position;
    });
  }

  final Player _p;
  late final VideoController _vc;
  late final List<StreamSubscription> _subs;

  String _lastFatal = ''; // 最后一条 error/fatal 文本（仅作卡住时的附注）
  bool _everStarted = false; // 是否已经播起来过（用于区分"起播失败"和"播放中的网络抖动"）
  Timer? _stallTimer;
  Duration _lastPos = Duration.zero;
  int _stuckMs = 0;

  /// 位置连续多久不前进就判为卡住（毫秒）
  static const int _stuckLimitMs = 9000;

  VideoController get videoController => _vc;

  /// 打开地址（httpHeaders 用于带 Referer/UA 的防盗链）
  Future<void> open(String url, {Map<String, String>? httpHeaders}) {
    // 换源前先清掉上一次的错误标记：否则上一个源失败留下的 error=true
    // 会让下一个源一挂上就被判失败，整条兜底链直接失效
    value = value.copyWith(error: false, errorText: '', completed: false);
    _everStarted = false; // 新源重新算"还没播起来"
    return _p.open(Media(url, httpHeaders: httpHeaders), play: true);
  }

  Future<void> play() => _p.play();
  Future<void> pause() => _p.pause();

  /// 音量 0~100（竖向滑动调节用）
  Future<void> setVolume(double v) =>
      _p.setVolume(v.clamp(0.0, 100.0).toDouble());

  Future<void> seek(Duration d) => _p.seek(_clampDur(d, value.duration));

  Future<void> shutdown() async {
    _stallTimer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    await _p.dispose();
    dispose();
  }
}

/// 缓冲提示：跳转跨度大时要重新拉流，没提示看着像卡死。
Widget _bufferingHint(KpPlayer kp) {
  return Align(
    alignment: const Alignment(0, -0.45),
    child: ValueListenableBuilder<KpState>(
      valueListenable: kp,
      builder: (_, s, __) => s.buffering
          ? const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  color: Colors.white70, strokeWidth: 2),
            )
          : const SizedBox.shrink(),
    ),
  );
}

/// 视频画面（引擎自带纹理，等比缩放不拉伸）
Widget _videoSurface(KpPlayer kp) => Video(
      controller: kp.videoController,
      fit: BoxFit.contain,
      fill: Colors.black,
      controls: NoVideoControls,
    );

/// 左右滑动快进/快退：滑动距离线性映射成秒数（滑满一屏 120 秒），
/// 拖动时只有最底下那条进度条跟着手指走（不弹文字提示），松手才真正跳转。
/// 内嵌播放器和全屏播放器共用。
mixin _SwipeSeek<T extends StatefulWidget> on State<T> {
  KpPlayer get swipePlayer;

  Timer? _swipeHoldTimer;

  /// 拖动预览位置：非 null = 正在滑动（底部进度条据此显示并跟手）
  final ValueNotifier<Duration?> swipePreview = ValueNotifier<Duration?>(null);

  bool _dragging = false;
  double _dragDx = 0;
  Duration _dragFrom = Duration.zero;
  Duration _dragTarget = Duration.zero;

  void swipeStart(DragStartDetails d) {
    _dragging = true;
    _dragDx = 0;
    _dragFrom = swipePlayer.value.position;
    _dragTarget = _dragFrom;
  }

  void swipeUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    _dragDx += d.delta.dx;
    final total = swipePlayer.value.duration;
    final w = context.size?.width ?? MediaQuery.of(context).size.width;
    _dragTarget = _clampDur(
        _dragFrom + Duration(seconds: _swipeSeconds(_dragDx, w)), total);
    swipePreview.value = _dragTarget;
  }

  void swipeEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    if (_dragTarget != _dragFrom) {
      swipePlayer.seek(_dragTarget); // 只在这一下跳转（拖动中不动播放器）
    }
    if (swipePreview.value == null) return;
    // seek 生效前先保持预览值，避免进度条往回跳一下
    _swipeHoldTimer?.cancel();
    _swipeHoldTimer = Timer(const Duration(milliseconds: 600), () {
      if (swipePreview.value != null) swipePreview.value = null;
    });
  }

  void disposeSwipe() {
    _swipeHoldTimer?.cancel();
    swipePreview.dispose();
  }
}

/// 竖向手势：左半屏上下滑调亮度、右半屏上下滑调音量（内嵌与全屏共用）。
/// 代价：内嵌播放器接管竖向拖动后，在视频区域内上下拖不会再滚动详情页
/// （这正是"在视频上调亮度/音量"的必要代价，详情页其它区域照常滚动）。
mixin _BrightnessVolume<T extends StatefulWidget> on State<T> {
  KpPlayer get gesturePlayer;

  bool _bvBrightness = false; // 本次调的是亮度？
  double _bvDy = 0; // 本次竖向累计位移
  double _bvStart = 0.5; // 起点值（亮度 0~1 / 音量 0~100）
  double? _bvShow; // 指示条的值 0~1（null = 不显示）
  bool _bvApplied = false; // 本次是否真的调整过
  Timer? _bvTimer;

  /// 本次拖动是否实际调整过（供全屏判断"要不要当作下滑退出"）
  bool get bvApplied => _bvApplied;

  void bvStart(DragStartDetails d) {
    final w = context.size?.width ?? MediaQuery.of(context).size.width;
    _bvBrightness = d.localPosition.dx < w / 2;
    _bvDy = 0;
    _bvApplied = false;
    if (_bvBrightness) {
      () async {
        try {
          final v = await ScreenBrightness().current;
          if (mounted) _bvStart = v;
        } catch (_) {}
      }();
    } else {
      _bvStart = gesturePlayer.value.volume;
    }
  }

  void bvUpdate(DragUpdateDetails d) {
    final h = context.size?.height ?? MediaQuery.of(context).size.height;
    if (h <= 0) return;
    _bvDy += d.delta.dy;
    if (_bvDy.abs() > 8) _bvApplied = true;
    final delta = -_bvDy / h; // 向上滑为正
    if (_bvBrightness) {
      final v = (_bvStart + delta).clamp(0.02, 1.0).toDouble();
      () async {
        try {
          await ScreenBrightness().setScreenBrightness(v);
        } catch (_) {}
      }();
      _bvGauge(v);
    } else {
      final v = (_bvStart + delta * 100).clamp(0.0, 100.0).toDouble();
      gesturePlayer.setVolume(v);
      _bvGauge(v / 100);
    }
  }

  void bvEnd(DragEndDetails d) {
    _bvTimer?.cancel();
    _bvTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _bvShow = null);
    });
  }

  void _bvGauge(double v) {
    _bvTimer?.cancel();
    setState(() => _bvShow = v.clamp(0.0, 1.0).toDouble());
  }

  void disposeBv() => _bvTimer?.cancel();

  /// 指示条：图标 + 进度条（不显示数字）
  Widget buildGauge() {
    final v = _bvShow;
    if (v == null) return const SizedBox.shrink();
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _bvBrightness ? Icons.brightness_6 : Icons.volume_up,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 110,
              height: 4,
              child: LinearProgressIndicator(
                value: v,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 视频播放器组件。
/// - 内嵌模式：详情页顶部 16:9，初始化前显示 poster 封面（正文首图）。
/// - 全屏模式：黑底沉浸，横屏/竖屏全屏，下滑返回。
/// - 控制条压在最底部：最下面是进度条（可直接拖），上面一排是播放/暂停 + 时间 + 全屏。
/// - 左右滑动快进快退：滑动距离决定秒数（滑满一屏 120 秒）；松手才真正跳转。
/// - 多个视频源按顺序尝试，全失败则用 onRefreshSources 重取时效链接再试一轮
///   （视频地址带 auth_key 签名，放久了会过期）。
class PlayerWidget extends StatefulWidget {
  /// 按优先级排列的视频地址（h264 主源在前，h265 兜底）
  final List<String> sources;
  final String referer;
  final String poster; // 视频封面，可为空

  /// 全部源都失败时调用：重新抓详情页拿新地址
  final Future<List<String>> Function()? onRefreshSources;

  /// 篇内视频切换状态（多视频文章才有；null = 单视频，没有"下一集"）
  final VideoSwitcher? switcher;

  const PlayerWidget({
    super.key,
    required this.sources,
    required this.referer,
    this.poster = '',
    this.onRefreshSources,
    this.switcher,
  });

  @override
  State<PlayerWidget> createState() => _PlayerWidgetState();
}

class _PlayerWidgetState extends State<PlayerWidget>
    with _SwipeSeek<PlayerWidget>, AutomaticKeepAliveClientMixin, _BrightnessVolume {
  static const _ua =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  KpPlayer? _kp;
  late List<String> _sources =
      widget.sources.where((s) => s.isNotEmpty).toList();
  String? _error;
  bool _busy = false;
  bool _init = false;
  int _curIndex = 0; // 当前已打开的篇内序号（判断是否换片）
  bool _errShown = false; // 播放中途出错（用于只在该状态翻转时重建）
  bool _started = false; // 已开始播放（首帧/位置走动后撤掉 poster）
  bool _controlsVisible = true;
  Timer? _hideTimer;
  Offset _lastTapPos = Offset.zero; // 双击落点（判断左半/右半）
  bool? _tapHintBack; // 双击提示：true=后退 false=快进
  Timer? _tapHintTimer;

  @override
  KpPlayer get swipePlayer => _kp!;

  @override
  KpPlayer get gesturePlayer => _kp!;

  /// 详情页往下翻看剧照时，播放器会滑出可视区。
  /// 不保活的话 ListView 会把它整个销毁，翻回来就从头重新加载/播放。
  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant PlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.switcher?.index.value ?? 0) != _curIndex) {
      _curIndex = widget.switcher?.index.value ?? 0;
      // 换片（点"下一集"或自动下一集）：复用同一个播放器实例去开新源。
      // 不能销毁重建——全屏页手里拿的是这个实例，销毁掉它就黑屏了。
      _sources = widget.sources.where((s) => s.isNotEmpty).toList();
      _nextFired = false;
      _errShown = false;
      _error = null;
      _initPlayer();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      _init = true;
      // 微任务里再初始化：_initPlayer 结尾会 setState，不能在本元素 build 期间调用
      Future.microtask(_initPlayer);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _tapHintTimer?.cancel();
    disposeBv();
    disposeSwipe();
    _kp?.shutdown();
    super.dispose();
  }

  /// 依次尝试各视频源；全失败时刷新时效链接再试一轮。
  /// 注意顺序：先把播放器挂到界面上（画面/声音一有就出），
  /// 再等"就绪"——就绪只用来判断要不要换下一个源，不该拦住显示。
  Future<void> _initPlayer() async {
    if (_sources.isEmpty) {
      setState(() => _error = '该文章暂无视频');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    var kp = _kp;
    if (kp == null) {
      kp = KpPlayer(bufferMb: AppSettings.i.bufferMb);
      _attach(kp); // 立刻上屏
      setState(() => _busy = false);
    }

    for (var round = 0; round < 2; round++) {
      for (var i = 0; i < _sources.length; i++) {
        final ok = await _openAndWait(kp, _sources[i]);
        if (!mounted) return;
        if (ok) {
          _scheduleHide();
          return;
        }
      }
      // 本轮全失败：刷新一次时效链接再来一轮
      if (round == 0 && widget.onRefreshSources != null) {
        try {
          final fresh = (await widget.onRefreshSources!())
              .where((s) => s.isNotEmpty)
              .toList();
          if (fresh.isNotEmpty) {
            _sources = fresh;
            continue;
          }
        } catch (_) {
          // 刷新失败就走错误提示
        }
      }
      break;
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _error = '视频加载失败';
      });
    }
  }

  /// 打开某个源并等它"能播了"（拿到时长）或明确失败
  Future<bool> _openAndWait(KpPlayer kp, String url) async {
    final done = Completer<bool>();
    void listener() {
      if (done.isCompleted) return;
      if (kp.value.error) {
        done.complete(false);
      } else if (kp.value.ready) {
        done.complete(true);
      }
    }

    kp.addListener(listener);
    try {
      await kp.open(url, httpHeaders: {
        'User-Agent': _ua,
        'Referer': '${widget.referer}/',
      });
      return await done.future
          .timeout(const Duration(seconds: 15), onTimeout: () => false);
    } catch (_) {
      return false;
    } finally {
      kp.removeListener(listener);
    }
  }

  void _attach(KpPlayer kp) {
    final old = _kp;
    if (old != null) old.shutdown();
    _kp = kp;
    kp.addListener(_onTick);
  }

  /// 只在「出错 / 已开播」这两个状态翻转时重建：位置/缓冲的变化由控制条和
  /// 缓冲提示自己用 ValueListenableBuilder 局部刷新，避免每 200ms 重建整个视频子树
  bool _nextFired = false; // 本次播放是否已触发过自动下一集

  void _onTick() {
    final err = _kp?.value.error ?? false;
    final started = _kp?.value.started ?? false;
    // 播完 → 按设置决定是否自动切下一个（每次播放只触发一次）
    if ((_kp?.value.completed ?? false) && !_nextFired) {
      _nextFired = true;
      if (AppSettings.i.autoNext && (widget.switcher?.hasNext ?? false)) {
        widget.switcher?.next();
      }
    }
    if ((err != _errShown || started != _started) && mounted) {
      setState(() {
        _errShown = err;
        _started = started;
      });
    }
  }

  /// 双击左半屏后退、右半屏快进（步长来自设置，默认 10 秒）
  void _onDoubleTapDown(TapDownDetails d) => _lastTapPos = d.localPosition;

  void _onDoubleTap() {
    final kp = _kp;
    if (kp == null) return;
    final w = context.size?.width ?? MediaQuery.of(context).size.width;
    final back = _lastTapPos.dx < w / 2;
    final secs = AppSettings.i.step;
    kp.seek(kp.value.position + Duration(seconds: back ? -secs : secs));
    _flashTapHint(back);
  }

  void _flashTapHint(bool back) {
    _tapHintTimer?.cancel();
    setState(() => _tapHintBack = back);
    _tapHintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _tapHintBack = null);
    });
  }

  void _retry() => _initPlayer();

  /// 控制条显示数秒后自动隐藏
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _openFullscreen({required bool vertical}) {
    final kp = _kp;
    if (kp == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullscreenPlayer(
          player: kp,
          vertical: vertical,
          switcher: widget.switcher,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 必须调用
    final kp = _kp;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        color: Colors.black,
        child: kp == null
            ? _coverArea()
            : Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleControls, // 单击显示/隐藏控制条
                    onDoubleTapDown: _onDoubleTapDown,
                    onDoubleTap: _onDoubleTap, // 双击左半后退/右半快进
                    // 竖向：左半屏调亮度、右半屏调音量
                    // （代价：在视频区域内上下拖不再滚动详情页）
                    onVerticalDragStart: bvStart,
                    onVerticalDragUpdate: bvUpdate,
                    onVerticalDragEnd: bvEnd,
                    onHorizontalDragStart: swipeStart,
                    onHorizontalDragUpdate: swipeUpdate,
                    onHorizontalDragEnd: swipeEnd,
                    child: _videoSurface(kp),
                  ),
                  // 出画面前盖着 poster（首帧一到就撤，不放着不动）
                  if (widget.poster.isNotEmpty && !_started)
                    IgnorePointer(
                      child: FetchedImage(
                        url: widget.poster,
                        fit: BoxFit.cover,
                        memWidth: 1280,
                      ),
                    ),
                  // 双击左/右的提示图标
                  if (_tapHintBack != null)
                    Align(
                      alignment: Alignment(_tapHintBack! ? -0.6 : 0.6, 0),
                      child: Icon(
                        _tapHintBack!
                            ? Icons.fast_rewind
                            : Icons.fast_forward,
                        color: Colors.white70,
                        size: 34,
                      ),
                    ),
                  // 跳转后重新拉流时的缓冲提示
                  _bufferingHint(kp),
                  // 播放中途出错：给个重试入口
                  // 亮度/音量指示条
                  buildGauge(),
                  if (_errShown || _error != null)
                    Center(
                      child: TextButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        label: Text(
                          kp.value.errorText.isEmpty
                              ? '播放出错，点此重试'
                              : '播放出错：${kp.value.errorText}（点此重试）',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  // 底部：进度条在最底；单击视频显示整条控制条，
                  // 左右滑动时只留进度条跟手（按钮和时间文字都隐藏）
                  ValueListenableBuilder<Duration?>(
                    valueListenable: swipePreview,
                    builder: (_, preview, __) {
                      final dragging = preview != null;
                      if (!_controlsVisible && !dragging) {
                        return const SizedBox.shrink();
                      }
                      return Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.6),
                              ],
                            ),
                          ),
                          child: _ControlBar(
                            player: kp,
                            preview: swipePreview,
                            hasNext: widget.switcher?.hasNext ?? false,
                            onNext: widget.switcher?.next,
                            showButtons: _controlsVisible && !dragging,
                            onVerticalFullscreen: () =>
                                _openFullscreen(vertical: true),
                            onFullscreen: () =>
                                _openFullscreen(vertical: false),
                            showFullscreen: true,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
      ),
    );
  }

  /// 未就绪前的区域：poster 封面 + 加载指示；失败则错误 + 重试
  Widget _coverArea() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _retry,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.poster.isNotEmpty)
          FetchedImage(url: widget.poster, fit: BoxFit.cover, memWidth: 1280),
        const Center(
            child: CircularProgressIndicator(color: Colors.white70)),
      ],
    );
  }
}

/// 底部控制条：最底下是进度条（可拖），上面一排是播放/暂停 + 时间 + 全屏。
/// 视频区左右滑动时 showButtons=false：那排按钮（含时间文字）隐藏，
/// 只留最底下的进度条跟着手指走。
class _ControlBar extends StatefulWidget {
  final KpPlayer player;

  /// 视频区滑动的预览位置（非 null = 正在滑动）
  final ValueListenable<Duration?> preview;
  final bool hasNext;
  final VoidCallback? onNext;
  final bool showButtons;
  final VoidCallback? onFullscreen;
  final VoidCallback? onVerticalFullscreen;
  final bool showFullscreen;
  const _ControlBar({
    required this.player,
    required this.preview,
    this.hasNext = false,
    this.onNext,
    this.showButtons = true,
    this.onFullscreen,
    this.onVerticalFullscreen,
    this.showFullscreen = false,
  });

  @override
  State<_ControlBar> createState() => _ControlBarState();
}

class _ControlBarState extends State<_ControlBar> {
  Duration? _drag; // 直接拖进度条时的预览值

  /// 底部那排小按钮。
  /// 不用 IconButton：Material 3 的 IconButton 有 48px 最小点击区
  /// （tapTargetSize 机制），constraints 压不下去，整排就一直是 48 高、
  /// 和进度条之间空一大截。这里自己定尺寸。
  Widget _barBtn({
    required IconData icon,
    VoidCallback? onPressed,
    bool enabled = true,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onPressed : null,
      child: SizedBox(
        width: 40,
        height: 26,
        child: Icon(icon,
            size: 20, color: enabled ? Colors.white : Colors.white24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration?>(
      valueListenable: widget.preview,
      builder: (_, preview, __) => ValueListenableBuilder<KpState>(
        valueListenable: widget.player,
        builder: (_, s, __) {
          final total = s.duration;
          final totalMs = total.inMilliseconds
              .toDouble()
              .clamp(1.0, double.infinity)
              .toDouble();
          final shown = _drag ?? preview ?? s.position;
          final shownMs = shown.inMilliseconds.toDouble().clamp(0.0, totalMs);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showButtons)
                Row(
                  children: [
                    _barBtn(
                      icon: s.playing ? Icons.pause : Icons.play_arrow,
                      onPressed: () =>
                          s.playing ? widget.player.pause() : widget.player.play(),
                    ),
                    // 下一集：篇内没有下一个视频时置灰禁用
                    _barBtn(
                      icon: Icons.skip_next,
                      enabled: widget.hasNext,
                      onPressed: widget.onNext,
                    ),
                    Expanded(
                      child: Text(
                        '${_fmt(Duration(milliseconds: shownMs.round()))} / ${_fmt(total)}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11),
                      ),
                    ),
                    if (widget.showFullscreen) ...[
                      // 竖屏全屏（全屏按钮左边）
                      _barBtn(
                        icon: Icons.crop_portrait,
                        onPressed: widget.onVerticalFullscreen,
                      ),
                      _barBtn(
                        icon: Icons.fullscreen,
                        onPressed: widget.onFullscreen,
                      ),
                    ],
                  ],
                ),
              // 进度条：自绘（Material Slider 自带上下留白，压不到最底、也贴不紧按钮）
              SizedBox(
                height: 12,
                child: _SeekBar(
                  position: shown,
                  duration: total,
                  buffer: s.buffer,
                  onPreview: (d) => setState(() => _drag = d),
                  onSeek: widget.player.seek,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 全屏播放页：黑底 + 左右滑动快进快退 + 下滑返回。
/// vertical=true 竖屏全屏（视频 contain 居中不拉伸），false 横屏全屏。
class FullscreenPlayer extends StatefulWidget {
  final KpPlayer player;
  final bool vertical;

  /// 篇内切换状态（与内嵌播放器共用同一份，取实时值）
  final VideoSwitcher? switcher;
  const FullscreenPlayer({
    super.key,
    required this.player,
    this.vertical = false,
    this.switcher,
  });

  @override
  State<FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<FullscreenPlayer>
    with _SwipeSeek, _BrightnessVolume {
  bool _controls = true;
  Timer? _hideTimer;
  Offset _lastTapPos = Offset.zero;
  bool? _tapHintBack;
  Timer? _tapHintTimer;
  @override
  KpPlayer get gesturePlayer => widget.player;

  @override
  KpPlayer get swipePlayer => widget.player;

  @override
  void initState() {
    super.initState();
    widget.player.play();
    widget.player.addListener(_onTick);
    if (widget.vertical) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _tapHintTimer?.cancel();
    disposeBv();
    // 退出全屏把窗口亮度还原（否则系统亮度被这次播放改掉了）
    () async {
      try {
        await ScreenBrightness().resetScreenBrightness();
      } catch (_) {}
    }();
    disposeSwipe();
    widget.player.removeListener(_onTick);
    // 退出全屏恢复竖屏
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  bool _errShown = false;

  void _onTick() {
    final err = widget.player.value.error;
    if (err != _errShown && mounted) setState(() => _errShown = err);
  }

  /// 双击左半屏后退、右半屏快进（步长来自设置）
  void _onDoubleTap() {
    final w = context.size?.width ?? MediaQuery.of(context).size.width;
    final back = _lastTapPos.dx < w / 2;
    final secs = AppSettings.i.step;
    widget.player
        .seek(widget.player.value.position + Duration(seconds: back ? -secs : secs));
    _tapHintTimer?.cancel();
    setState(() => _tapHintBack = back);
    _tapHintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _tapHintBack = null);
    });
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final kp = widget.player;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: (d) => _lastTapPos = d.localPosition,
        onDoubleTap: _onDoubleTap,
        // 竖向：左半屏调亮度、右半屏调音量；没实际调整时的快速下滑仍是退出
        onVerticalDragStart: bvStart,
        onVerticalDragUpdate: bvUpdate,
        onVerticalDragEnd: (d) {
          bvEnd(d);
          if (!bvApplied && (d.primaryVelocity ?? 0) > 900) {
            Navigator.pop(context);
          }
        },
        onHorizontalDragStart: swipeStart,
        onHorizontalDragUpdate: swipeUpdate,
        onHorizontalDragEnd: swipeEnd,
        child: Stack(
          children: [
            Center(child: _videoSurface(kp)),
            // 顶部：返回
            if (_controls)
              SafeArea(
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              ),
            // 亮度/音量指示条（图标 + 条，不显示数字）
            buildGauge(),            // 双击左/右的提示图标（必须判空：_tapHintBack 为 null 时
            // 少了这层判断会直接 null! 崩溃，整页灰屏）
            if (_tapHintBack != null)
              Align(
                alignment: Alignment(_tapHintBack! ? -0.6 : 0.6, 0),
                child: Icon(
                  _tapHintBack! ? Icons.fast_rewind : Icons.fast_forward,
                  color: Colors.white70,
                  size: 40,
                ),
              ),
            // 跳转后重新拉流时的缓冲提示
            _bufferingHint(kp),
            // 播放出错提示
            if (_errShown)
              const Center(
                child: Text('播放出错，请返回重试',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
              ),
            // 底部：进度条在最底；点一下出整条控制条，左右滑动时只留进度条
            ValueListenableBuilder<Duration?>(
              valueListenable: swipePreview,
              builder: (_, preview, __) {
                final dragging = preview != null;
                if (!_controls && !dragging) return const SizedBox.shrink();
                final sw = widget.switcher;
                // 竖屏全屏：整条控制条（含进度条）再上移 3px
                final bottomPad = widget.vertical
                    ? const EdgeInsets.only(bottom: 3)
                    : EdgeInsets.zero;
                if (sw == null) {
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: bottomPad,
                        child: _ControlBar(
                          player: kp,
                          preview: swipePreview,
                          showButtons: _controls && !dragging,
                        ),
                      ),
                    ),
                  );
                }
                // 序号变化要重建控制条，否则"下一集"按钮状态是旧的
                return ValueListenableBuilder<int>(
                  valueListenable: sw.index,
                  builder: (_, i, __) => Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: bottomPad,
                        child: _ControlBar(
                          player: kp,
                          preview: swipePreview,
                          hasNext: i < sw.total - 1,
                          onNext: sw.next,
                          showButtons: _controls && !dragging,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部进度条（自绘）。
/// 用 Material Slider 时它有固定的上下留白，压不到最底、也很难贴近上面那排按钮，
/// 这里自己画：轨道 3px、离底边 4px，拖到哪就在哪松手跳转。
class _SeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;

  /// 已缓存数据的最后时间戳（绝对位置），画成浅色一段
  final Duration buffer;

  /// 拖动中的预览（null = 松手了）
  final ValueChanged<Duration?> onPreview;
  final ValueChanged<Duration> onSeek;

  const _SeekBar({
    required this.position,
    required this.duration,
    required this.buffer,
    required this.onPreview,
    required this.onSeek,
  });

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  Duration? _drag;

  void _moveTo(double dx, double width) {
    if (width <= 0) return;
    final ms = (dx / width).clamp(0.0, 1.0) * widget.duration.inMilliseconds;
    final d = Duration(milliseconds: ms.round());
    setState(() => _drag = d);
    widget.onPreview(d);
  }

  void _release() {
    final d = _drag;
    setState(() => _drag = null);
    widget.onPreview(null);
    if (d != null) widget.onSeek(d);
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration.inMilliseconds.toDouble();
    final shownMs = (_drag ?? widget.position).inMilliseconds.toDouble();
    final frac =
        (totalMs <= 0 ? 0.0 : (shownMs / totalMs).clamp(0.0, 1.0)).toDouble();
    // 缓冲段 = 已缓存数据的最后时间戳 / 总时长。
    // （demuxer-cache-time 本身就是绝对位置，叠加当前位置会把位置算两遍，
    //   表现就是那条浅色带一直跟着播放进度跑）
    final bufFrac = (totalMs <= 0
            ? 0.0
            : (widget.buffer.inMilliseconds / totalMs).clamp(0.0, 1.0))
        .toDouble();
    return LayoutBuilder(
      builder: (ctx, c) {
        final w = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _moveTo(d.localPosition.dx, w),
          onTapUp: (_) => _release(),
          onHorizontalDragStart: (d) => _moveTo(d.localPosition.dx, w),
          onHorizontalDragUpdate: (d) => _moveTo(d.localPosition.dx, w),
          onHorizontalDragEnd: (_) => _release(),
          child: Stack(
            children: [
              // 底轨
              Positioned(
                left: 0,
                right: 0,
                bottom: 3,
                height: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 已缓冲（浅色一段，压在已播下面）
              Positioned(
                left: 0,
                bottom: 3,
                height: 3,
                width: (w * bufFrac).clamp(0.0, w).toDouble(),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 已播部分
              Positioned(
                left: 0,
                bottom: 3,
                height: 3,
                width: (w * frac).clamp(0.0, w).toDouble(),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 圆点
              Positioned(
                left: (w * frac - 4).clamp(0.0, (w - 8).clamp(0.0, w)).toDouble(),
                bottom: 0.5,
                width: 8,
                height: 8,
                child: const DecoratedBox(
                  decoration:
                      BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
