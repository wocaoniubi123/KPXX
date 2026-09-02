import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'fetched_image.dart';

/// 视频播放器组件。
/// - 内嵌模式：详情页顶部 16:9，常驻控制条（播放/暂停 + 可拖动进度条 + 时间 + 全屏）。
///   视频初始化前显示 poster 封面（正文首图）。
/// - 全屏模式：黑底沉浸，左右滑动快进/快退 ±10 秒（右滑快进），进度条可直接拖动。
class PlayerWidget extends StatefulWidget {
  final String videoUrl;
  final String referer;
  final String poster; // 视频封面，可为空
  const PlayerWidget({
    super.key,
    required this.videoUrl,
    required this.referer,
    this.poster = '',
  });

  @override
  State<PlayerWidget> createState() => _PlayerWidgetState();
}

class _PlayerWidgetState extends State<PlayerWidget> {
  VideoPlayerController? _ctl;
  String? _error;
  String? _toast;
  bool _init = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      _init = true;
      _initPlayer();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _ctl?.dispose(); // 退出页面立即停止播放，不在后台继续
    super.dispose();
  }

  Future<void> _initPlayer() async {
    if (widget.videoUrl.isEmpty) {
      setState(() => _error = '该文章暂无视频');
      return;
    }
    final ctl = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
      httpHeaders: {
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
        'Referer': '${widget.referer}/',
      },
    );
    try {
      await ctl.initialize();
      await ctl.play();
      if (mounted) setState(() => _ctl = ctl);
      _scheduleHide();
    } catch (e) {
      if (mounted) setState(() => _error = '视频加载失败：$e');
    }
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

  /// 内嵌模式也支持左右滑快进快退（右滑快进）
  void _seekBy(int seconds) {
    final ctl = _ctl;
    if (ctl == null) return;
    final pos = ctl.value.position + Duration(seconds: seconds);
    final Duration target;
    if (pos < Duration.zero) {
      target = Duration.zero;
    } else if (pos > ctl.value.duration) {
      target = ctl.value.duration;
    } else {
      target = pos;
    }
    ctl.seekTo(target);
    setState(() {
      _toast = '${seconds > 0 ? '快进' : '快退'} ${seconds.abs()} 秒';
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  @override
  Widget build(BuildContext context) {
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
                    // 左右滑：快进快退 10 秒（不弹出控制条）
                    onHorizontalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v.abs() < 150) return;
                      _seekBy(v > 0 ? 10 : -10);
                    },
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
                  // 快进快退提示
                  if (_toast != null)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_toast!,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15)),
                      ),
                    ),
                  // 底部控制条（未操作时隐藏，单击视频显示）
                  if (_controlsVisible)
                    Align(
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
                          onVerticalFullscreen: () =>
                              _openFullscreen(vertical: true),
                          onFullscreen: () => _openFullscreen(vertical: false),
                          showFullscreen: true,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  /// 未初始化完成前的区域：poster 封面 + 加载指示
  Widget _coverArea() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(_error!,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center),
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

/// 底部控制条：播放/暂停 + 可拖进度条 + 时间 + 全屏。
/// 拖动时的预览值由本组件内部状态持有，松手才 seek。
class _ControlBar extends StatefulWidget {
  final VideoPlayerController controller;
  final VoidCallback? onFullscreen;
  final VoidCallback? onVerticalFullscreen;
  final bool showFullscreen;
  const _ControlBar({
    required this.controller,
    this.onFullscreen,
    this.onVerticalFullscreen,
    this.showFullscreen = false,
  });

  @override
  State<_ControlBar> createState() => _ControlBarState();
}

class _ControlBarState extends State<_ControlBar> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.controller,
      builder: (_, v, __) {
        final totalMs = v.duration.inMilliseconds.toDouble()
            .clamp(1.0, double.infinity)
            .toDouble();
        final posMs = v.position.inMilliseconds.toDouble();
        final shownMs = (_dragMs ?? posMs).clamp(0.0, totalMs).toDouble();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 12),
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
            Row(
              children: [
                IconButton(
                  iconSize: 20,
                  color: Colors.white,
                  icon: Icon(
                    v.isPlaying ? Icons.pause : Icons.play_arrow,
                  ),
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
                  IconButton(
                    iconSize: 20,
                    color: Colors.white,
                    icon: const Icon(Icons.crop_portrait),
                    onPressed: widget.onVerticalFullscreen,
                  ),
                  IconButton(
                    iconSize: 20,
                    color: Colors.white,
                    icon: const Icon(Icons.fullscreen),
                    onPressed: widget.onFullscreen,
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}

String _fmt(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// 全屏播放页：黑底 + 左右滑动快进快退。
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

class _FullscreenPlayerState extends State<FullscreenPlayer> {
  String? _toast;
  bool _controls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.play();
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
    // 退出全屏恢复竖屏
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
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

  /// 快进快退（秒），右滑 +
  void _seekBy(int seconds) {
    final ctl = widget.controller;
    final pos = ctl.value.position + Duration(seconds: seconds);
    final Duration target;
    if (pos < Duration.zero) {
      target = Duration.zero;
    } else if (pos > ctl.value.duration) {
      target = ctl.value.duration;
    } else {
      target = pos;
    }
    ctl.seekTo(target);
    setState(() {
      _toast = '${seconds > 0 ? '快进' : '快退'} ${seconds.abs()} 秒';
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _toast = null);
    });
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
        // 左右滑动：快进快退 10 秒（右滑快进，不弹控制条）
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() < 150) return;
          _seekBy(v > 0 ? 10 : -10);
        },
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
            // 中间：快进快退提示
            if (_toast != null)
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_toast!,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15)),
                ),
              ),
            // 底部：控制条
            if (_controls)
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ControlBar(controller: ctl),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
