import 'dart:async';

// ValueListenable 不在 material.dart 的导出里，要单独引
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'fetched_image.dart';

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

/// 缓冲提示：滑动跳转跨度大时要重新拉流，没提示看着像卡死。
/// 放偏上位置，不和中间的滑动提示气泡重叠。
Widget _bufferingHint(VideoPlayerController ctl) {
  return Align(
    alignment: const Alignment(0, -0.45),
    child: ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: ctl,
      builder: (_, v, __) => v.isBuffering
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

/// 左右滑动快进/快退：滑动距离线性映射成秒数（滑满一屏 120 秒），
/// 拖动时只有最底下那条进度条跟着手指走（不弹文字提示），松手才真正跳转。
/// 内嵌播放器和全屏播放器共用。
mixin _SwipeSeek<T extends StatefulWidget> on State<T> {
  VideoPlayerController get swipeCtl;

  Timer? _swipeHoldTimer;

  /// 拖动预览位置：非 null = 正在滑动（底部进度条据此显示并跟手）。
  /// 用 ValueNotifier 而不是 setState：拖动时只重建进度条，
  /// 不重建整个播放器子树（长距离滑动=上百次重建，会顿一下）。
  final ValueNotifier<Duration?> swipePreview = ValueNotifier<Duration?>(null);

  bool _dragging = false;
  double _dragDx = 0;
  Duration _dragFrom = Duration.zero;
  Duration _dragTarget = Duration.zero;

  void swipeStart(DragStartDetails d) {
    _dragging = true;
    _dragDx = 0;
    _dragFrom = swipeCtl.value.position;
    _dragTarget = _dragFrom;
  }

  void swipeUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    _dragDx += d.delta.dx;
    final total = swipeCtl.value.duration;
    final w = context.size?.width ?? MediaQuery.of(context).size.width;
    _dragTarget = _clampDur(
        _dragFrom + Duration(seconds: _swipeSeconds(_dragDx, w)), total);
    swipePreview.value = _dragTarget;
  }

  void swipeEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    if (_dragTarget != _dragFrom) swipeCtl.seekTo(_dragTarget);
    if (swipePreview.value == null) return;
    // seek 生效前先保持预览值，避免进度条往回跳一下
    _swipeHoldTimer?.cancel();
    _swipeHoldTimer = Timer(const Duration(milliseconds: 600), () {
      if (swipePreview.value != null) swipePreview.value = null;
    });
  }

  void disposeSwipe() {
    _swipeHoldTimer?.cancel(); // 先停定时器，再销毁 notifier
    swipePreview.dispose();
  }
}

/// 视频播放器组件。
/// - 内嵌模式：详情页顶部 16:9，初始化前显示 poster 封面（正文首图）。
/// - 全屏模式：黑底沉浸，横屏/竖屏全屏，下滑返回。
/// - 控制条压在最底部：最下面是进度条（可直接拖），上面一排是播放/暂停 + 时间 + 全屏。
/// - 左右滑动快进快退：滑动距离决定秒数（滑满一屏 120 秒）；拖动时只让最底下那条
///   进度条跟着手指走（不弹秒数/时间文字），松手才真正跳转。
/// - 多个视频源按顺序尝试，全失败则用 onRefreshSources 重取时效链接再试一轮
///   （视频地址带 auth_key 签名，放久了会过期）。
class PlayerWidget extends StatefulWidget {
  /// 按优先级排列的视频地址（h264 主源在前，h265 兜底）
  final List<String> sources;
  final String referer;
  final String poster; // 视频封面，可为空

  /// 全部源都失败时调用：重新抓详情页拿新地址
  final Future<List<String>> Function()? onRefreshSources;

  const PlayerWidget({
    super.key,
    required this.sources,
    required this.referer,
    this.poster = '',
    this.onRefreshSources,
  });

  @override
  State<PlayerWidget> createState() => _PlayerWidgetState();
}

class _PlayerWidgetState extends State<PlayerWidget>
    with _SwipeSeek<PlayerWidget>, AutomaticKeepAliveClientMixin {
  static const _ua =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  VideoPlayerController? _ctl;
  late List<String> _sources =
      widget.sources.where((s) => s.isNotEmpty).toList();
  String? _error;
  bool _busy = false;
  bool _init = false;
  bool _refreshed = false; // 已重取过一次链接，避免失败时死循环
  bool _playError = false; // 播放中途出错
  bool _controlsVisible = true;
  Timer? _hideTimer;

  @override
  VideoPlayerController get swipeCtl => _ctl!;

  /// 详情页往下翻看剧照时，播放器会滑出可视区。
  /// 不保活的话 ListView 会把它整个销毁，翻回来就从头重新加载/播放。
  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      _init = true;
      // 微任务里再初始化：_initPlayer 开头会 setState，不能在本元素 build 期间调用
      Future.microtask(_initPlayer);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    disposeSwipe();
    _ctl?.removeListener(_onTick);
    _ctl?.dispose(); // 退出页面立即停止播放，不在后台继续
    super.dispose();
  }

  void _onTick() {
    final err = _ctl?.value.hasError ?? false;
    if (err != _playError && mounted) setState(() => _playError = err);
  }

  /// 依次尝试各视频源；全失败时刷新时效链接再试一轮。
  Future<void> _initPlayer() async {
    if (_sources.isEmpty) {
      setState(() => _error = '该文章暂无视频');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _playError = false;
    });

    for (var i = 0; i < _sources.length; i++) {
      final ctl = VideoPlayerController.networkUrl(
        Uri.parse(_sources[i]),
        httpHeaders: {'User-Agent': _ua, 'Referer': '${widget.referer}/'},
      );
      try {
        await ctl.initialize();
        await ctl.play();
        if (!mounted) {
          await ctl.dispose();
          return;
        }
        _attach(ctl);
        setState(() => _busy = false);
        _scheduleHide();
        return;
      } catch (_) {
        await ctl.dispose(); // 该源不行，试下一个
      }
    }

    // 所有源都失败：重取链接（签名过期）再试一轮
    if (!_refreshed && widget.onRefreshSources != null) {
      _refreshed = true;
      try {
        final fresh = (await widget.onRefreshSources!())
            .where((s) => s.isNotEmpty)
            .toList();
        if (fresh.isNotEmpty) {
          _sources = fresh;
          return _initPlayer(); // _refreshed 已置位，只会再来这一轮
        }
      } catch (_) {
        // 刷新失败，走下面的错误提示
      }
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _error = '视频加载失败';
      });
    }
  }

  void _attach(VideoPlayerController ctl) {
    final old = _ctl;
    if (old != null) {
      old.removeListener(_onTick);
      old.dispose();
    }
    _ctl = ctl;
    ctl.addListener(_onTick);
  }

  void _retry() {
    _refreshed = false; // 手动重试允许再刷新一次链接
    _initPlayer();
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
    final ctl = _ctl;
    if (ctl == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullscreenPlayer(
          controller: ctl,
          vertical: vertical,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 必须调用
    final ctl = _ctl;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        color: Colors.black,
        child: ctl == null
            ? _coverArea()
            : Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleControls, // 单击显示/隐藏控制条
                    onHorizontalDragStart: swipeStart,
                    onHorizontalDragUpdate: swipeUpdate,
                    onHorizontalDragEnd: swipeEnd,
                    child: Center(
                      // FittedBox contain：等比缩放，绝不拉伸
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: ctl.value.size.width > 0
                              ? ctl.value.size.width
                              : 16,
                          height: ctl.value.size.height > 0
                              ? ctl.value.size.height
                              : 9,
                          child: VideoPlayer(ctl),
                        ),
                      ),
                    ),
                  ),
                  // 跳转后重新拉流时的缓冲提示
                  _bufferingHint(ctl),
                  // 播放中途出错：给个重试入口（否则画面卡住没有任何提示）
                  if (_playError)
                    Center(
                      child: TextButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        label: const Text('播放出错，点此重试',
                            style: TextStyle(color: Colors.white)),
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
                            controller: ctl,
                            preview: swipePreview,
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

  /// 未初始化完成前的区域：poster 封面 + 加载指示；失败则错误 + 重试
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

/// 底部控制条：最底下是进度条（拖动时可拖），上面一排是播放/暂停 + 时间 + 全屏。
/// 视频区左右滑动时 showButtons=false：那排按钮（含时间文字）隐藏，
/// 只留最底下的进度条跟着手指走。
class _ControlBar extends StatefulWidget {
  final VideoPlayerController controller;

  /// 视频区滑动的预览位置（非 null = 正在滑动）
  final ValueListenable<Duration?> preview;
  final bool showButtons;
  final VoidCallback? onFullscreen;
  final VoidCallback? onVerticalFullscreen;
  final bool showFullscreen;
  const _ControlBar({
    required this.controller,
    required this.preview,
    this.showButtons = true,
    this.onFullscreen,
    this.onVerticalFullscreen,
    this.showFullscreen = false,
  });

  @override
  State<_ControlBar> createState() => _ControlBarState();
}

class _ControlBarState extends State<_ControlBar> {
  double? _dragMs; // 直接拖进度条时的预览值

  /// 底部那排小按钮：做紧凑些，别和进度条离太远
  Widget _barBtn({required IconData icon, VoidCallback? onPressed}) {
    return IconButton(
      iconSize: 20,
      color: Colors.white,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration?>(
      valueListenable: widget.preview,
      builder: (_, preview, __) => ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: widget.controller,
        builder: (_, v, __) {
          final totalMs = v.duration.inMilliseconds.toDouble()
              .clamp(1.0, double.infinity)
              .toDouble();
          final posMs = v.position.inMilliseconds.toDouble();
          final shownMs = (_dragMs ??
                  preview?.inMilliseconds.toDouble() ??
                  posMs)
              .clamp(0.0, totalMs)
              .toDouble();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showButtons)
                Row(
                  children: [
                    _barBtn(
                      icon: v.isPlaying ? Icons.pause : Icons.play_arrow,
                      onPressed: () => v.isPlaying
                          ? widget.controller.pause()
                          : widget.controller.play(),
                    ),
                    Expanded(
                      child: Text(
                        '${_fmt(Duration(milliseconds: shownMs.round()))} / '
                        '${_fmt(v.duration)}',
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
              // 进度条压到最底下（只留一点点边距），整条高度收窄贴近上面那排按钮
              SizedBox(
                height: 22,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 10),
                  ),
                  child: Slider(
                    value: shownMs,
                    max: totalMs,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white24,
                    onChanged: (val) => setState(() => _dragMs = val),
                    onChangeEnd: (val) {
                      widget.controller
                          .seekTo(Duration(milliseconds: val.toInt()));
                      setState(() => _dragMs = null);
                    },
                  ),
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
  final VideoPlayerController controller;
  final bool vertical;
  const FullscreenPlayer({
    super.key,
    required this.controller,
    this.vertical = false,
  });

  @override
  State<FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<FullscreenPlayer> with _SwipeSeek {
  bool _controls = true;
  bool _playError = false;
  Timer? _hideTimer;

  @override
  VideoPlayerController get swipeCtl => widget.controller;

  @override
  void initState() {
    super.initState();
    widget.controller.play();
    widget.controller.addListener(_onTick);
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
    disposeSwipe();
    widget.controller.removeListener(_onTick);
    // 退出全屏恢复竖屏
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _onTick() {
    final err = widget.controller.value.hasError;
    if (err != _playError && mounted) setState(() => _playError = err);
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
    final ctl = widget.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        // 下滑返回
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 200) Navigator.pop(context);
        },
        onHorizontalDragStart: swipeStart,
        onHorizontalDragUpdate: swipeUpdate,
        onHorizontalDragEnd: swipeEnd,
        child: Stack(
          children: [
            // 全屏视频（FittedBox contain 等比缩放，绝不拉伸）
            Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: ctl.value.size.width > 0
                      ? ctl.value.size.width
                      : 16,
                  height: ctl.value.size.height > 0
                      ? ctl.value.size.height
                      : 9,
                  child: VideoPlayer(ctl),
                ),
              ),
            ),
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
            // 跳转后重新拉流时的缓冲提示
            _bufferingHint(ctl),
            // 播放出错提示
            if (_playError)
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
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    top: false,
                    child: _ControlBar(
                      controller: ctl,
                      preview: swipePreview,
                      showButtons: _controls && !dragging,
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
