import 'dart:async';
import 'site_error_log.dart';

// ValueListenable 不在 material.dart 的导出里，要单独引
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
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

  /// "暂停一下"的信号（自增计数）。详情页点标签/相关推荐跳走时发一次——
  /// 否则原页面的播放器压在栈下面继续放，新页面也在放，就变成多个视频同时出声。
  /// 不直接调播放器是因为实例由 PlayerWidget 持有、全屏页也共用它，不能乱动。
  final ValueNotifier<int> pauseTick = ValueNotifier<int>(0);
  void pause() => pauseTick.value++;

  bool get hasNext => index.value < total - 1;
  bool get hasPrev => index.value > 0;

  void next() {
    if (hasNext) index.value++;
  }

  void prev() {
    if (hasPrev) index.value--;
  }

  void select(int i) {
    if (i >= 0 && i < total) index.value = i;
  }

  void dispose() {
    index.dispose();
    pauseTick.dispose();
  }
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
          SiteErrorLog.log('播放器', 'error 流（还没播起来）：$e');
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
      // 恢复判断必须在下面那行早退**之前**：error 一旦置上，早退每轮都命中，
      // 后面的逻辑全都不会执行 —— 放到 else 分支里等于永远不清。
      // 清它不只是为了撤提示：`_onTick` 的 errEdge 是 `err && !_errShown`，
      // 残留着 true 会让**后续的自动重试静默失效**（真挂掉时连一次都不重试）。
      // ⚠️ 2026-10-03 修（用户报"视频都开始播放了，加载失败提示还挂着"）：
      // 原来这里多要求一个 `_stalled` ✗ —— 只有**看门狗判的卡住**才撤 ✗，
      // 而"起播前的偶发 FFmpeg 错误"是在 `_everStarted == false` 时把 error 置上的 ✓，
      // 视频随后正常播起来也**没人撤它** ✗ → 提示永远挂在播放器上 ✓。
      // 判据改成"**位置真的在前进**" ✓：位置前进 = 确实在播 = 不是失败 ✓。
      // （真失败时位置不会前进 ✓ 所以不会误清 ✓）
      if (s.error &&
          (s.position - _lastPos).abs().inMilliseconds >= 500) {
        _stalled = false;
        value = value.copyWith(error: false, errorText: '');
      }
      if (!s.playing || s.error) {
        _stuckMs = 0;
        _lastPos = s.position;
        return;
      }
      if ((s.position - _lastPos).abs().inMilliseconds < 500) {
        _stuckMs += 1000;
        if (_stuckMs >= _stuckLimitMs) {
          _stuckMs = 0;
          _stalled = true; // 这次算"看门狗判的"：位置恢复前进时由它自己撤掉
          SiteErrorLog.log('播放器',
              '⚠️ 判缓冲超时：位置 ${_fmt(s.position)} 已 ${_stuckMs}ms 不动 | duration=${_fmt(s.duration)} buffering=${s.buffering}');
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

  /// 当前这个 error 是不是**看门狗自己判的卡住**（只有它才由看门狗自己撤）。
  /// 起播失败那类 error 不归它管 —— 撤了会把"真失败"静默掉。
  bool _stalled = false;

  /// 位置连续多久不前进就判为卡住（毫秒）
  static const int _stuckLimitMs = 9000;

  VideoController get videoController => _vc;

  /// 当前播放位置（离开页面时补写播放记录用）
  Duration get position => value.position;

  /// **最后真实前进过**的播放位置。
  /// 用途：换档/换源那一刻取"记到哪儿了"。不能用 `position` —— 换源会把
  /// state 里的 position 重置为 0（见 open()），而这个值只在位置真的前进了
  /// ≥500ms 时才更新，所以它保留的是"上一条源播到的真实进度"。
  Duration get lastKnownPosition => _lastPos;

  /// 打开地址（httpHeaders 用于带 Referer/UA 的防盗链）
  Future<void> open(String url, {Map<String, String>? httpHeaders}) {
    // 🔎 诊断日志（用户 2026-10-03 要求：慢站 seek 失败排查 ✓）——可在「设置→诊断→错误日志」复制 ✓
    SiteErrorLog.log('播放器',
        'open 源=${url.length > 100 ? url.substring(0, 100) : url} | Referer=${httpHeaders != null}');
    // 换源前先清掉上一次的错误标记：否则上一个源失败留下的 error=true
    // 会让下一个源一挂上就被判失败，整条兜底链直接失效
    //
    // ⚠️ 2026-10-02 **必须连 duration/position 一起重置**：`ready` 的判据是
    // `duration > Duration.zero`，而这里原来只清 error —— 于是换源时 duration
    // 还是**上一条源的残留值** → `_openAndWait` 的 ready 立刻为真、**秒返回**，
    // 调用方紧接着 seek 到记录的位置，可 mpv 还在加载新源 → **seek 被丢掉**，
    // 新源从 0 起播。用户实测"换分辨率后从头播"就是这个（Pornhub / XVideos 都有）。
    value = value.copyWith(
      error: false,
      errorText: '',
      completed: false,
      duration: Duration.zero,
      position: Duration.zero,
    );
    _everStarted = false; // 新源重新算"还没播起来"
    _stalled = false; // 错误已经清了 → 看门狗那个"我判的卡住"标记一并撤
    return _p.open(Media(url, httpHeaders: httpHeaders), play: true);
  }

  Future<void> play() => _p.play();
  Future<void> pause() => _p.pause();

  /// 音量 0~100（竖向滑动调节用）
  Future<void> setVolume(double v) =>
      _p.setVolume(v.clamp(0.0, 100.0).toDouble());

  /// 播放倍速——长按快进用：按住时 2.0、松手回 1.0
  Future<void> setRate(double r) => _p.setRate(r);

  Future<void> seek(Duration d) {
    final t = _clampDur(d, value.duration);
    SiteErrorLog.log('播放器',
        'seek ${_fmt(d)} → 实际 ${_fmt(t)} | duration=${_fmt(value.duration)} pos=${_fmt(value.position)} buffering=${value.buffering} err=${value.error}');
    return _p.seek(t);
  }

  /// **不按时长裁剪**的 seek。续播/换档专用：那种场景下目标是"上一条源播到的
  /// 位置"，而 `seek()` 会按 `value.duration` 裁剪，万一时长还没报上来
  /// （或报了个半截值）就会被裁小 —— 表现同样是"从头发"。
  Future<void> seekExact(Duration d) {
    SiteErrorLog.log('播放器',
        'seekExact ${_fmt(d)} | duration=${_fmt(value.duration)} pos=${_fmt(value.position)}');
    return _p.seek(d);
  }

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
  double _bvStart = 0.5; // 本次拖动的起点值（亮度/音量都是 0~1）
  double? _bvShow; // 指示条的值 0~1（null = 不显示）
  bool _bvApplied = false; // 本次是否真的调整过
  Timer? _bvTimer;

  // 系统值缓存（-1 = 还没读到）。拖动开始立刻用缓存当起点，
  // 避免"拖动那一刻才异步去读、第一帧用到旧值"。
  double _bvBrightVal = -1;
  double _bvVolVal = -1;
  bool _bvPrimed = false;
  StreamSubscription<double>? _bvBrightSub;
  StreamSubscription<double>? _bvVolSub;

  /// 本次拖动是否实际调整过（供全屏判断"要不要当作下滑退出"）
  bool get bvApplied => _bvApplied;

  /// 进入播放器时预热：读一次当前系统亮度/音量做缓存。
  /// 亮度另有变化回调（系统里改了也能跟上）；音量没有回调，改为每次拖动开始时后台刷新。
  Future<void> bvPrime() async {
    if (_bvPrimed) return;
    _bvPrimed = true;
    try {
      _bvBrightVal = await ScreenBrightness().current;
      _bvBrightSub = ScreenBrightness()
          .onCurrentBrightnessChanged
          .listen((v) => _bvBrightVal = v);
    } catch (_) {}
    await _bvRefreshVolume();
    try {
      // 音量由本 app 调，别让系统再弹一个音量 HUD（我们有自己的指示条）
      VolumeController().showSystemUI = false;
      // 跟随系统音量变化（含用手机音量键改的情况）
      _bvVolSub = VolumeController().listener((v) => _bvVolVal = v);
    } catch (_) {}
  }

  Future<void> _bvRefreshVolume() async {
    try {
      _bvVolVal = await VolumeController().getVolume();
    } catch (_) {}
  }

  void bvStart(DragStartDetails d) {
    final w = context.size?.width ?? MediaQuery.of(context).size.width;
    _bvBrightness = d.localPosition.dx < w / 2;
    _bvDy = 0;
    _bvApplied = false;
    // 起点立刻用缓存值（没有缓存才退回默认值），刷新留给下一次拖动
    _bvStart = _bvBrightness
        ? (_bvBrightVal >= 0 ? _bvBrightVal : 0.5)
        : (_bvVolVal >= 0 ? _bvVolVal : 1.0);
    if (_bvBrightness) {
      () async {
        try {
          _bvBrightVal = await ScreenBrightness().current;
        } catch (_) {}
      }();
    } else {
      _bvRefreshVolume();
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
      _bvBrightVal = v; // 自己改的，缓存同步跟上
      () async {
        try {
          await ScreenBrightness().setScreenBrightness(v);
        } catch (_) {}
      }();
      _bvGauge(v);
    } else {
      final v = (_bvStart + delta).clamp(0.0, 1.0).toDouble();
      _bvVolVal = v;
      // 系统音量（0~1）：和手机音量键是同一套，改动会留存
      VolumeController().setVolume(v);
      _bvGauge(v);
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

  void disposeBv() {
    _bvTimer?.cancel();
    _bvBrightSub?.cancel();
    _bvVolSub?.cancel();
  }

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

  /// 合集类：当前这一集要去哪个子文章页取源（为空 = 自带视频的普通条目）
  final String? lazyUrl;

  /// 合集类：按地址取源的入口（详情页接到 Api.videoSourcesAt）
  final Future<List<String>> Function(String url)? onFetchSources;

  /// 篇内视频切换状态（多视频文章才有；null = 单视频，没有"下一集"）
  final VideoSwitcher? switcher;

  /// 从"播放记录"点进来时的续播位置：首次成功起播后跳到这（只生效一次）。
  /// 从站点入口进来不传 → null → 完全按原行为从头播（用户要求）。
  final Duration? initialPosition;

  /// 进度上报（位置、总时长、是否播完）。详情页拿它写播放记录；不传就不上报。
  final void Function(Duration pos, Duration dur, bool finished)? onProgress;

  const PlayerWidget({
    super.key,
    required this.sources,
    required this.referer,
    this.poster = '',
    this.onRefreshSources,
    this.lazyUrl,
    this.onFetchSources,
    this.switcher,
    this.initialPosition,
    this.onProgress,
  });

  @override
  State<PlayerWidget> createState() => PlayerWidgetState();
}

/// 对外暴露一个 [player] getter：详情页离开时要从它身上取最后位置（写播放记录）
class PlayerWidgetState extends State<PlayerWidget>
    with
        _SwipeSeek<PlayerWidget>,
        AutomaticKeepAliveClientMixin,
        _BrightnessVolume,
        WidgetsBindingObserver {
  static const _ua =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  KpPlayer? _kp;
  late List<String> _sources =
      widget.sources.where((s) => s.isNotEmpty).toList();
  VoidCallback? _pauseHooked; // 挂在 switcher.pauseTick 上的监听（换 widget 时要摘）
  String? _error;
  bool _busy = false;
  // 播放出错自动重试：最多 5 次（起播成功后清零；手动点重试也给新额度）
  int _autoRetries = 0;
  bool _autoRetrying = false; // 自动重试进行中（显示提示、暂藏重试按钮）
  Timer? _autoRetryTimer;
  bool _opening = false; // 正在依次尝试各源（期间不排自动重试，交给循环收尾）
  bool _init = false;
  /// 正在按需取源（合集/黄果选集）：点击那一刻就亮提示，别等网络回来才弹
  bool _fetchingLazy = false;
  int _curIndex = 0; // 当前已打开的篇内序号（判断是否换片）
  /// 续播位置（从播放记录进来）：首次成功起播后跳一次，之后置空不再用
  late Duration? _restoreTo = widget.initialPosition;
  /// 进度上报节流：每 10 秒一次（用户拍板），离开详情页时详情页再补一次 flush
  Timer? _reportTimer;
  Duration _repPos = Duration.zero;
  bool _errShown = false; // 播放中途出错（用于只在该状态翻转时重建）
  bool _started = false; // 已开始播放（首帧/位置走动后撤掉 poster）
  bool _controlsVisible = true;
  Timer? _hideTimer;
  Offset _lastTapPos = Offset.zero; // 双击落点（判断左半/右半）
  IconData? _tapHint; // 双击提示图标（快退/快进/暂停/播放）
  double _tapHintX = 0; // 提示位置：-0.6 左 / 0 中 / 0.6 右
  Timer? _tapHintTimer;
  bool _longPressing = false; // 长按快进中（按住 2 倍速）

  @override
  KpPlayer get swipePlayer => _kp!;

  /// 当前播放器实例（详情页写播放记录时取位置用；未初始化时为 null）
  KpPlayer? get player => _kp;

  /// 切后台/被杀前补报一次进度：否则"最后看的 10 秒"会丢
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      final p = _kp?.value.position ?? Duration.zero;
      if (p > Duration.zero) {
        _repPos = p;
        widget.onProgress?.call(
          p,
          _kp?.value.duration ?? Duration.zero,
          _kp?.value.completed ?? false,
        );
      }
    }
  }

  @override
  KpPlayer get gesturePlayer => _kp!;

  /// 详情页往下翻看剧照时，播放器会滑出可视区。
  /// 不保活的话 ListView 会把它整个销毁，翻回来就从头重新加载/播放。
  @override
  bool get wantKeepAlive => true;

  /// switcher 可能在 initState 之后才传进来（详情页是异步拿数据建 switcher 的），
  /// 所以每次依赖变化/更新都重新对一遍监听，挂的是同一个回调。
  void _syncPauseHook() {
    final tick = widget.switcher?.pauseTick;
    if (tick == _pauseHookedTick) return;
    _pauseHookedTick?.removeListener(_pauseHooked!);
    _pauseHookedTick = tick;
    if (tick != null) {
      _pauseHooked = () => _kp?.pause();
      tick.addListener(_pauseHooked!);
    } else {
      _pauseHooked = null;
    }
  }

  ValueNotifier<int>? _pauseHookedTick;

  @override
  void didUpdateWidget(covariant PlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPauseHook();
    if ((widget.switcher?.index.value ?? 0) != _curIndex) {
      _curIndex = widget.switcher?.index.value ?? 0;
      // 换片（点"下一集"或自动下一集）：复用同一个播放器实例去开新源。
      // 不能销毁重建——全屏页手里拿的是这个实例，销毁掉它就黑屏了。
      _sources = widget.sources.where((s) => s.isNotEmpty).toList();
      _nextFired = false;
      _errShown = false;
      _error = null;
      // 换集：自动重试排期与计数一并清零
      _autoRetryTimer?.cancel();
      _autoRetryTimer = null;
      _autoRetries = 0;
      _autoRetrying = false;
      // 点击就要"立刻"有反应（用户要求）：旧视频先停住，别等新源就绪；
      // 这一集要按需取源的话，"正在取视频…"提示也立即亮（不用等网络）。
      _kp?.pause();
      _fetchingLazy = widget.lazyUrl != null && _sources.isEmpty;
      _initPlayer();
    }
  }

  /// 从外部换一批源并重开（详情页的「清晰度」选择用）。
  /// 走和「换集」同一套重开流程（见 didUpdateWidget 里那段），**不重建实例** ——
  /// 重建会让全屏页手里攥着的旧实例失效（黑屏）。
  /// 传进来的列表**顺序就是尝试顺序**：选中的档放最前，失败会自动往下试。
  /// [resumeTo] 传了就在新源起播后跳到这个位置（换档保留播放进度用，走的是本类
  /// 既有的续播机制 `_restoreTo`）。
  void switchSources(List<String> srcs, {Duration? resumeTo}) {
    final list = srcs.where((s) => s.isNotEmpty).toList();
    if (list.isEmpty) return;
    _sources = list;
    _nextFired = false;
    _errShown = false;
    _error = null;
    _autoRetryTimer?.cancel();
    _autoRetryTimer = null;
    _autoRetries = 0;
    _autoRetrying = false;
    _kp?.pause(); // 换档：先把旧源停住，别和新源抢声音
    _fetchingLazy = false;
    if (resumeTo != null && resumeTo > Duration.zero) _restoreTo = resumeTo;
    _initPlayer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPauseHook(); // switcher 可能是后到的，每次依赖变化都对一遍监听
    if (!_init) {
      _init = true;
      // 切后台/被杀前补报一次播放进度（不注册就收不到生命周期回调）
      WidgetsBinding.instance.addObserver(this);
      bvPrime(); // 预读系统亮度/音量做缓存
      // 微任务里再初始化：_initPlayer 结尾会 setState，不能在本元素 build 期间调用
      Future.microtask(_initPlayer);
    }
  }

  @override
  void dispose() {
    _pauseHookedTick?.removeListener(_pauseHooked!);
    _hideTimer?.cancel();
    _tapHintTimer?.cancel();
    _autoRetryTimer?.cancel();
    _reportTimer?.cancel(); // 播放记录上报（详情页会在 dispose 时 flush 最后位置）
    WidgetsBinding.instance.removeObserver(this);
    disposeBv();
    disposeSwipe();
    _kp?.shutdown();
    super.dispose();
  }

  /// 依次尝试各视频源；全失败时刷新时效链接再试一轮。
  /// 注意顺序：先把播放器挂到界面上（画面/声音一有就出），
  /// 再等"就绪"——就绪只用来判断要不要换下一个源，不该拦住显示。
  Future<void> _initPlayer() async {
    // 起播时把「当前篇内序号」对齐到 switcher：续播可能直接落在第 3 集，
    // 不对齐的话 didUpdateWidget 会误判成"换片"、把刚打开的源又重开一遍。
    _curIndex = widget.switcher?.index.value ?? 0;
    // 合集类：这一集还没有源 → **按需**去抓它自己的页面（点哪集抓哪集）
    if (_sources.isEmpty &&
        widget.lazyUrl != null &&
        widget.onFetchSources != null) {
      setState(() {
        _busy = true;
        _fetchingLazy = true; // 立即亮"正在取视频…"（点击那一下就该看到）
        _error = null;
      });
      try {
        final got = (await widget.onFetchSources!(widget.lazyUrl!))
            .where((s) => s.isNotEmpty)
            .toList();
        if (!mounted) return;
        _sources = got;
      } catch (_) {
        // 下面统一误提示
      }
      if (!mounted) return;
      _fetchingLazy = false; // 源到手（或失败）：提示要么转播放、要么转错误
      if (_sources.isEmpty) {
        setState(() {
          _busy = false;
          _error = '这一集已失效（子文章打不开或没有视频）';
        });
        _notePlaybackError();
        return;
      }
    }
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

    _opening = true; // 源尝试进行中：期间的出错排期让循环收尾统一处理
    try {
      for (var round = 0; round < 2; round++) {
        for (var i = 0; i < _sources.length; i++) {
          final ok = await _openAndWait(kp, _sources[i]);
          if (!mounted) return;
          if (ok) {
            // 续播：本次起播前记录下来的进度，跳完就置空（换集不再跳）
            final to = _restoreTo;
            _restoreTo = null;
            if (to != null && to > Duration.zero) {
              try {
                // ⚠️ 用 seekExact 而不是 seek：seek 会按 value.duration 裁剪，
                // 万一时长还没报上来就会被裁小（表现就是"从头发"）。
                await kp.seekExact(to);
                // 再校验一次：mpv 偶尔会把早期的 seek 丢掉，没跳过去就补一枪。
                // 3 秒的容差是给"视频刚开始播、位置还在往上走"留的余量。
                await Future<void>.delayed(const Duration(milliseconds: 500));
                if (mounted &&
                    kp.value.duration > Duration.zero &&
                    kp.value.position < to - const Duration(seconds: 3)) {
                  await kp.seekExact(to);
                }
              } catch (_) {
                // 续播失败不影响播放，从头放就行
              }
            }
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
    } finally {
      _opening = false;
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _error = '视频加载失败';
      });
      _notePlaybackError();
    }
  }

  /// 播放用的 Referer：统一用「视频源自身的域名」（不是站点域名）。
  /// 站点视频常托管在别的域名/IP（2026-09-30 实测：黄果→yd-hls.tktjpm.cn、
  /// WP 系→hls.qldjxf.cn / op.udhhzr.cn、91porna→yd-hls.tktjpm.cn、
  /// Pektino→video.twimg.com），拿站点域名当 Referer 会被 CDN 拒
  /// （video.twimg.com 对 pektino.com 直接 403）。全站回归实测：各 CDN 对
  /// 「源自身域名」均放行（m3u8/分片/密钥全 200）；视频与站点同域时新旧等价。
  /// **唯一例外**：Pornhub 的 phncdn.com 分片要站点域名（2026-10-02，见下面的分支）。
  String _playReferer(String url) {
    final u = Uri.tryParse(url);
    if (u != null && u.hasScheme && u.host.isNotEmpty) {
      // ⚠️ Pornhub 的 CDN（phncdn.com）是**反例**：HLS **分片**要「站点域名」当 Referer，
      // 拿源自身域名会被伪装成 404（2026-10-02 实测；sim/server.mjs 里同一套判断）。
      // 其余站照旧走下面的「源自身域名」（Pektino→video.twimg.com 拿站点域名会被拒，别改成通用）。
      if (u.host == 'phncdn.com' || u.host.endsWith('.phncdn.com')) {
        // ⚠️ Pornhub 的 CDN 分片要**站点域名**当 Referer ✓（拿源自带域名会被伪装成 404 ✓）。
        // 不写死域名 ✗ —— 用传进来的 referer（detail_page 传的是 _api.base = 当前站域名 ✓）。
        if (widget.referer.isNotEmpty) return '${widget.referer}/';
      }
      return '${u.scheme}://${u.host}/';
    }
    return '${widget.referer}/';
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
        'Referer': _playReferer(url),
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
    // 播放进度上报（写播放记录）：每 10 秒一次，只在位置真前进了才报
    //（暂停/卡住时报上去没意义；离开详情页由详情页 flush 补最后一次）
    _reportTimer?.cancel();
    _reportTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final p = _kp?.value.position ?? Duration.zero;
      if ((p - _repPos).abs() < const Duration(seconds: 5)) return;
      _repPos = p;
      widget.onProgress?.call(
        p,
        _kp?.value.duration ?? Duration.zero,
        _kp?.value.completed ?? false,
      );
    });
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
    final errEdge = err && !_errShown; // 出错的上升沿 → 自动重试
    final startedEdge = started && !_started; // 起播（含自动重试后恢复）→ 额度清零
    if ((err != _errShown || started != _started) && mounted) {
      setState(() {
        _errShown = err;
        _started = started;
        if (startedEdge && (_autoRetries != 0 || _autoRetrying)) {
          // 起播了：撤销已排期的自动重试（别把刚播起来的视频又重开）
          _autoRetryTimer?.cancel();
          _autoRetryTimer = null;
          _autoRetries = 0;
          _autoRetrying = false;
        }
      });
    }
    if (errEdge) _notePlaybackError();
  }

  /// 双击左半屏后退、右半屏快进（步长来自设置，默认 10 秒）
  void _onDoubleTapDown(TapDownDetails d) => _lastTapPos = d.localPosition;

  /// 双击：左三成退、右三成进（步长来自设置）、**中间暂停/播放**
  void _onDoubleTap() {
    final kp = _kp;
    if (kp == null) return;
    final w = context.size?.width ?? MediaQuery.of(context).size.width;
    final dx = _lastTapPos.dx;
    if (dx > w * 0.35 && dx < w * 0.65) {
      if (kp.value.playing) {
        kp.pause();
        _flashTapHint(Icons.pause, 0);
      } else {
        kp.play();
        _flashTapHint(Icons.play_arrow, 0);
      }
      return;
    }
    final back = dx < w / 2;
    final secs = AppSettings.i.step;
    kp.seek(kp.value.position + Duration(seconds: back ? -secs : secs));
    _flashTapHint(back ? Icons.fast_rewind : Icons.fast_forward,
        back ? -0.6 : 0.6);
  }

  void _flashTapHint(IconData icon, double x) {
    _tapHintTimer?.cancel();
    setState(() {
      _tapHint = icon;
      _tapHintX = x;
    });
    _tapHintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _tapHint = null);
    });
  }

  void _retry() {
    // 手动重试：撤销自动重试排期、额度清零（再失败会重新自动重试一轮）
    _autoRetryTimer?.cancel();
    _autoRetryTimer = null;
    _autoRetries = 0;
    if (_autoRetrying) setState(() => _autoRetrying = false);
    _initPlayer();
  }

  /// 播放出错 → 排一次自动重试（最多 5 次）。
  /// 5 次都失败后不再自动重试：错误提示留在屏幕上，由用户自己点重试。
  void _notePlaybackError() {
    if (!mounted) return;
    // 源尝试循环还在跑：这次失败由循环收尾统一排期（别掐断正在加载的下一路源）
    if (_opening) return;
    if (_autoRetries >= 5) {
      // 额度用完：撤掉"自动重试中"提示，把错误提示/重试按钮露出来
      if (_autoRetrying) setState(() => _autoRetrying = false);
      return;
    }
    // 同一次失败可能双通道报错（引擎 error + 源尝试失败），排一次就够
    if (_autoRetryTimer != null) return;
    _autoRetries++;
    setState(() => _autoRetrying = true);
    _autoRetryTimer = Timer(const Duration(milliseconds: 1200), () {
      _autoRetryTimer = null;
      if (mounted) _initPlayer();
    });
  }

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
    // 进出全屏用快速淡入淡出：默认系统侧滑转场对全屏视频违和（用户实报"过渡难看"）
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, __, ___) => FullscreenPlayer(
          player: kp,
          vertical: vertical,
          switcher: widget.switcher,
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(
            parent: anim,
            curve: Curves.easeOut,
            reverseCurve: Curves.easeIn,
          ),
          child: child,
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
                    // 长按快进：任意位置按住 = 2 倍速，松手还原 1 倍速
                    onLongPressStart: (_) {
                      _kp?.setRate(2.0);
                      setState(() => _longPressing = true);
                    },
                    onLongPressEnd: (_) {
                      _kp?.setRate(1.0);
                      if (_longPressing) setState(() => _longPressing = false);
                    },
                    onLongPressCancel: () {
                      _kp?.setRate(1.0);
                      if (_longPressing) setState(() => _longPressing = false);
                    },
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
                  // 双击左/中/右的提示图标（退 / 暂停播放 / 进）
                  if (_tapHint != null)
                    Align(
                      alignment: Alignment(_tapHintX, 0),
                      child: Icon(_tapHint!, color: Colors.white70, size: 34),
                    ),
                  // 长按快进中（2 倍速）提示
                  if (_longPressing)
                    Align(
                      alignment: const Alignment(0, -0.45),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text('2× 快进中',
                            style:
                                TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ),
                  // 跳转后重新拉流时的缓冲提示
                  _bufferingHint(kp),
                  // 正在按需取源（合集/黄果选集）：点击那一刻起亮着
                  if (_fetchingLazy) _lazyHint(),
                  // 亮度/音量指示条
                  buildGauge(),
                  // 播放出错：只显示自动重试进度（最多 5 次），用完就静默。
                  // 用户拍板（2026-10-01）：5 次都失败说明源/链路真有问题，**不再显示
                  // 「点此重试」那套**（含 mpv 的英文原文）—— 退出重进等价，没必要再烦人。
                  // 条件只看 `_error`（"这集本身没有/坏了"的中文说明），**不看 `_errShown`**：
                  // 引擎错误走上面的 n/5 提示，用完就不打扰；这样也不会再出现
                  // "视频已经在播、提示还挂着"（那个就是 `_errShown` 由看门狗置上、
                  // 之后没人撤留下的）。
                  if (_autoRetrying)
                    _autoRetryHint()
                  else if (_error != null)
                    Center(
                      child: TextButton.icon(
                        onPressed: _busy ? null : _retry,
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        label: Text(
                          _error!,
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
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
                            hasPrev: widget.switcher?.hasPrev ?? false,
                            onPrev: widget.switcher?.prev,
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
        if (_fetchingLazy)
          _lazyHint()
        else
          const Center(
              child: CircularProgressIndicator(color: Colors.white70)),
      ],
    );
  }

  /// "自动重试中 n/5…"提示（播放出错后自动重试期间显示）。
  Widget _autoRetryHint() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  color: Colors.white70, strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text('播放出错，自动重试 $_autoRetries/5…',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  /// "正在取视频…"提示（合集 / 黄果选集按需取源期间）。
  /// 点击那一刻就显示、不等网络——之前这段屏幕毫无反应（旧视频继续播），
  /// 看着就像"点了没动静、过 1 秒才弹出提示"（用户实报）。
  Widget _lazyHint() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  color: Colors.white70, strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('正在取视频…',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
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

  /// 上一集（已在第一集时置灰禁用）
  final bool hasPrev;
  final VoidCallback? onPrev;
  final bool showButtons;
  final VoidCallback? onFullscreen;
  final VoidCallback? onVerticalFullscreen;
  final bool showFullscreen;
  const _ControlBar({
    required this.player,
    required this.preview,
    this.hasNext = false,
    this.onNext,
    this.hasPrev = false,
    this.onPrev,
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
      // 控件放大一倍（用户要求）：图标 20→40、点击区 40×26→56×44
      child: SizedBox(
        width: 56,
        height: 44,
        child: Icon(icon,
            size: 40, color: enabled ? Colors.white : Colors.white24),
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
                    // 上一集：第一集（没有上一集）时整个隐藏（用户要求不显示；原来只是置灰）
                    if (widget.hasPrev)
                      _barBtn(
                        icon: Icons.skip_previous,
                        onPressed: widget.onPrev,
                      ),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

/// 全屏播放页：黑底 + 左右滑动快进快退 + 左边缘滑返回（仿 iOS）/返回按钮退出。
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
  IconData? _tapHint; // 双击提示图标（快退/快进/暂停/播放）
  double _tapHintX = 0; // 提示位置：-0.6 左 / 0 中 / 0.6 右
  Timer? _tapHintTimer;
  bool _longPressing = false; // 长按快进中（按住 2 倍速）
  Animation<double>? _routeAnim; // 全屏路由的转场动画（监听退场那一瞬，提前恢复方向）
  static const double _kEdgeWidth = 28; // 左边缘手势带宽度（仿 iOS 边缘滑返回）
  double _hDownX = 0; // 本次横向拖拽的起手位置
  bool _edgeSwipe = false; // 本次左右滑是否从边缘起手（=返回手势）
  double _edgeDx = 0; // 边缘返回手势的累计水平位移

  @override
  KpPlayer get gesturePlayer => widget.player;

  @override
  KpPlayer get swipePlayer => widget.player;

  @override
  void initState() {
    super.initState();
    bvPrime(); // 预读系统亮度/音量做缓存
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

  /// 路由转场状态：一开始退场（reverse）就恢复竖屏——
  /// 让系统旋转和退场动画并行跑，消除横版退出"先横版卡一会"（用户实报）。
  void _onRouteAnimStatus(AnimationStatus s) {
    if (s == AnimationStatus.reverse) _restoreOrientation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final anim = ModalRoute.of(context)?.animation;
    if (identical(anim, _routeAnim)) return;
    _routeAnim?.removeStatusListener(_onRouteAnimStatus);
    _routeAnim = anim;
    anim?.addStatusListener(_onRouteAnimStatus);
  }

  /// 恢复竖屏（退出路径都调它；dispose 里兜底）
  void _restoreOrientation() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
    _routeAnim?.removeStatusListener(_onRouteAnimStatus);
    // 兜底：退出路径都已在触发时恢复过，这里再保一次
    _restoreOrientation();
    super.dispose();
  }

  bool _errShown = false;
  bool _endHandled = false; // 本段播完是否已处理（换集后自动重置）

  void _onTick() {
    if (!mounted) return;
    final v = widget.player.value;
    if (v.error != _errShown) setState(() => _errShown = v.error);
    // 播完且没有下一集：自动退出全屏（竖版/横版都适用；用户要求）
    if (v.completed) {
      if (!_endHandled) {
        _endHandled = true;
        if (!(widget.switcher?.hasNext ?? false)) {
          _restoreOrientation();
          Navigator.pop(context);
        }
      }
    } else {
      _endHandled = false;
    }
  }

  /// 双击：左三成退、右三成进（步长来自设置）、**中间暂停/播放**
  void _onDoubleTap() {
    final w = context.size?.width ?? MediaQuery.of(context).size.width;
    final dx = _lastTapPos.dx;
    if (dx > w * 0.35 && dx < w * 0.65) {
      if (widget.player.value.playing) {
        widget.player.pause();
        _flashTapHint(Icons.pause, 0);
      } else {
        widget.player.play();
        _flashTapHint(Icons.play_arrow, 0);
      }
      return;
    }
    final back = dx < w / 2;
    final secs = AppSettings.i.step;
    widget.player.seek(
        widget.player.value.position + Duration(seconds: back ? -secs : secs));
    _flashTapHint(back ? Icons.fast_rewind : Icons.fast_forward,
        back ? -0.6 : 0.6);
  }

  void _flashTapHint(IconData icon, double x) {
    _tapHintTimer?.cancel();
    setState(() {
      _tapHint = icon;
      _tapHintX = x;
    });
    _tapHintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _tapHint = null);
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
        // 竖向：左半屏调亮度、右半屏调音量
        // （下滑退出已删——它和亮度/音量抢同一手势区，实际几乎触发不了；用户要求删除）
        onVerticalDragStart: bvStart,
        onVerticalDragUpdate: bvUpdate,
        onVerticalDragEnd: bvEnd,
        // 左右滑：默认=快进快退；从左边缘起手=返回（仿 iOS 边缘滑返回，用户选的 B 方案）
        onHorizontalDragDown: (d) => _hDownX = d.localPosition.dx,
        onHorizontalDragStart: (d) {
          _edgeSwipe = _hDownX <= _kEdgeWidth;
          _edgeDx = 0;
          if (!_edgeSwipe) swipeStart(d);
        },
        onHorizontalDragUpdate: (d) {
          if (_edgeSwipe) {
            _edgeDx += d.delta.dx;
            return;
          }
          swipeUpdate(d);
        },
        onHorizontalDragEnd: (d) {
          if (_edgeSwipe) {
            _edgeSwipe = false;
            final w = MediaQuery.sizeOf(context).width;
            if ((d.primaryVelocity ?? 0) > 300 || _edgeDx > w * 0.28) {
              _restoreOrientation();
              Navigator.pop(context);
            }
            return;
          }
          swipeEnd(d);
        },
        onHorizontalDragCancel: () {
          _edgeSwipe = false;
          _edgeDx = 0;
        },
        // 长按快进：任意位置按住 = 2 倍速，松手还原 1 倍速
        onLongPressStart: (_) {
          widget.player.setRate(2.0);
          setState(() => _longPressing = true);
        },
        onLongPressEnd: (_) {
          widget.player.setRate(1.0);
          if (_longPressing) setState(() => _longPressing = false);
        },
        onLongPressCancel: () {
          widget.player.setRate(1.0);
          if (_longPressing) setState(() => _longPressing = false);
        },
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
                      onPressed: () {
                        _restoreOrientation();
                        Navigator.pop(context);
                      },
                    ),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              ),
            // 亮度/音量指示条（图标 + 条，不显示数字）
            buildGauge(),            // 双击左/中/右的提示图标（必须判空：
            // 少了这层判断会直接 null! 崩溃，整页灰屏）
            if (_tapHint != null)
              Align(
                alignment: Alignment(_tapHintX, 0),
                child: Icon(
                  _tapHint!,
                  color: Colors.white70,
                  size: 40,
                ),
              ),
            // 长按快进中（2 倍速）提示
            if (_longPressing)
              Align(
                alignment: const Alignment(0, -0.45),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text('2× 快进中',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
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
                // 控制条整体上移（用户要求"适当上移"，控件放大后再多留一点）：
                // 横屏全屏 18、竖屏全屏 14
                final bottomPad = widget.vertical
                    ? const EdgeInsets.only(bottom: 14)
                    : const EdgeInsets.only(bottom: 18);
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
                          hasPrev: i > 0,
                          onPrev: sw.prev,
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
