import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 视频播放器组件。
/// - 内嵌模式：详情页顶部 16:9，点击全屏。
/// - 全屏模式：黑底沉浸，左右滑动快进/快退 ±10 秒（右滑快进，左滑快退。
///   注意：手势为"向当前时间轴推进"即向右滑动 seek 到更后的位置）。
class PlayerWidget extends StatefulWidget {
  final String videoUrl;
  final String referer;
  const PlayerWidget(
      {super.key, required this.videoUrl, required this.referer});

  @override
  State<PlayerWidget> createState() => _PlayerWidgetState();
}

class _PlayerWidgetState extends State<PlayerWidget> {
  VideoPlayerController? _ctl;
  String? _error;
  String? _toast; // 快进快退提示
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      _init = true;
      _initPlayer();
    }
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
    } catch (e) {
      if (mounted) setState(() => _error = '视频加载失败：$e');
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// 快进快退（秒），右滑 +
  void _seekBy(int seconds) {
    final ctl = _ctl;
    if (ctl == null) return;
    final target = (ctl.value.position + Duration(seconds: seconds))
        .clamp(Duration.zero, ctl.value.duration);
    ctl.seekTo(target);
    setState(() {
      _toast = '${seconds > 0 ? '快进' : '快退'} ${seconds.abs()} 秒';
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _openFullscreen() {
    final ctl = _ctl;
    if (ctl == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullscreenPlayer(
          controller: ctl,
          onSeek: _seekBy,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctl = _ctl;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        color: Colors.black,
        child: ctl == null
            ? Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      )
                    : const CircularProgressIndicator(color: Colors.white70),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      // 单击：显示/隐藏控制条
                      setState(() {});
                    },
                    child: Center(
                      child: VideoPlayer(ctl),
                    ),
                  ),
                  // 顶部小控制条
                  Positioned(
                    right: 8,
                    top: 8,
                    child: GestureDetector(
                      onTap: _openFullscreen,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.fullscreen,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                  // 进度条
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 4,
                    child: ValueListenableBuilder(
                      valueListenable: ctl,
                      builder: (_, v, __) => Row(
                        children: [
                          Text(
                            '${_fmt(v.position)} / ${_fmt(v.duration)}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11),
                          ),
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

/// 全屏播放页：黑底 + 左右滑动快进快退。
class FullscreenPlayer extends StatefulWidget {
  final VideoPlayerController controller;
  final void Function(int seconds) onSeek;
  const FullscreenPlayer(
      {super.key, required this.controller, required this.onSeek});

  @override
  State<FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<FullscreenPlayer> {
  String? _toast;

  @override
  void initState() {
    super.initState();
    widget.controller.play();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final ctl = widget.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 下滑返回
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 200) Navigator.pop(context);
        },
        // 左右滑动：快进快退 10 秒（右滑快进）
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() < 150) return;
          final sec = v > 0 ? 10 : -10;
          widget.onSeek(sec);
          setState(() {
            _toast = '${sec > 0 ? '快进' : '快退'} ${sec.abs()} 秒';
          });
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) setState(() => _toast = null);
          });
        },
        child: Stack(
          children: [
            // 全屏视频（填满，留黑边）
            Center(
              child: AspectRatio(
                aspectRatio: ctl.value.aspectRatio == 0
                    ? 16 / 9
                    : ctl.value.aspectRatio,
                child: VideoPlayer(ctl),
              ),
            ),
            // 顶部：返回 + 标题
            SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
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
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ValueListenableBuilder(
                  valueListenable: ctl,
                  builder: (_, v, __) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 进度滑动条
                        Slider(
                          value: v.duration.inMilliseconds == 0
                              ? 0
                              : v.position.inMilliseconds
                                  .clamp(0, v.duration.inMilliseconds)
                                  .toDouble(),
                          max: v.duration.inMilliseconds > 0
                              ? v.duration.inMilliseconds.toDouble()
                              : 1,
                          onChangeEnd: (val) {
                            ctl.seekTo(Duration(milliseconds: val.toInt()));
                          },
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_fmt(v.position)} / ${_fmt(v.duration)}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                            IconButton(
                              icon: Icon(
                                v.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                color: Colors.white,
                              ),
                              onPressed: () => v.isPlaying
                                  ? ctl.pause()
                                  : ctl.play(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
