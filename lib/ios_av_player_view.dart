/// ★★ 2026-10-13（**用户拍板：iOS 侧换 AVPlayer 验证版** ✅）—— 只给 **iOS** 用的**最小验证视图**：
///   播放/暂停 · seek（拖进度条）· 切集（换源）· 时长/位置/缓冲读数 ✅
///   ⚠️ 其余（倍速/长按/全屏/手势/续播/播放记录）**本验证版不提供**（与 libmpv 那条路互不影响 ✅）——
///     进入本视图时会打一行日志说明（见 [IosAvPlayerView] 的说明 ✅）。
///   ⚠️ **Windows 一行不受影响**：只有 `Platform.isIOS && iosUseAvPlayer` 才会走到这里 ✅。
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'player_widget.dart' show VideoSwitcher;
import 'settings.dart';

class IosAvPlayerView extends StatefulWidget {
  const IosAvPlayerView({
    super.key,
    required this.sources,
    required this.referer,
    this.httpHeaders,
    this.switcher,
    this.lazyUrl,
    this.onFetchSources,
    this.poster = '',
    this.title = '',
  });

  final List<String> sources;
  final String referer;
  final Map<String, String>? httpHeaders;
  final VideoSwitcher? switcher;

  /// 合集类：这一集还没源 ⇒ 按需取（与详情页既有回调同款 ✅）
  final String? lazyUrl;
  final Future<List<String>?> Function(String url)? onFetchSources;
  final String poster;
  final String title;

  @override
  State<IosAvPlayerView> createState() => _IosAvPlayerViewState();
}

class _IosAvPlayerViewState extends State<IosAvPlayerView> {
  static const String _ua =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  VideoPlayerController? _c;
  List<String> _srcs = const <String>[];
  int _idx = 0;
  bool _busy = true;
  String _err = '';
  int _firstFrameMs = -1;
  final Stopwatch _sw = Stopwatch();

  static void _log(String s) {
    if (AppSettings.i.logConsole) debugPrint('[PLAY-IOS] $s');
  }

  @override
  void initState() {
    super.initState();
    _srcs = widget.sources.where((e) => e.isNotEmpty).toList();
    widget.switcher?.index.addListener(_onSwitch);
    _log('引擎=AVPlayer 进入验证视图（只提供 播放/暂停·seek·切集·读数；'
        '倍速/全屏/手势/续播在本模式下不可用 ✅）');
    unawaited(_open(0));
  }

  @override
  void dispose() {
    widget.switcher?.index.removeListener(_onSwitch);
    final c = _c;
    _c = null;
    if (c != null) unawaited(c.dispose());
    super.dispose();
  }

  void _onSwitch() {
    final i = widget.switcher?.index.value ?? 0;
    if (i == _idx) return;
    _idx = i;
    unawaited(_open(i));
  }

  /// 打不开/没源 ⇒ 0 条（不静默假装成功 ✅）
  Future<void> _open(int i) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _err = '';
    });
    _firstFrameMs = -1;
    _sw.reset();
    try {
      var list = _srcs;
      if (list.isEmpty && widget.lazyUrl != null && widget.onFetchSources != null) {
        final got = await widget.onFetchSources!(widget.lazyUrl!).timeout(const Duration(seconds: 8),
            onTimeout: () => const <String>[]);
        list = (got ?? const <String>[]).where((e) => e.isNotEmpty).toList();
      }
      if (list.isEmpty) {
        setState(() {
          _busy = false;
          _err = '该文章暂无视频';
        });
        _log('引擎=AVPlayer 源=0 条 ⇒ 报"该文章暂无视频"');
        return;
      }
      _srcs = list;
      final src = list[i.clamp(0, list.length - 1)];
      final host = Uri.tryParse(src)?.host ?? '?';
      _log('引擎=AVPlayer 试源 idx=$i/共${list.length}条 host=$host');
      final old = _c;
      final c = VideoPlayerController.networkUrl(
        Uri.parse(src),
        httpHeaders: <String, String>{
          'User-Agent': _ua,
          'Referer': widget.referer,
          ...?widget.httpHeaders, // 站点给的（Cookie 等）✅
        },
      );
      _c = c;
      await old?.dispose();
      await c.initialize().timeout(const Duration(seconds: 20));
      unawaited(c.play());
      // 首帧：位置首次 > 0（与 libmpv 那条路同一判据 ✅）
      void tick() {
        if (!mounted || !identical(_c, c)) return;
        if (_firstFrameMs < 0 && c.value.position > Duration.zero) {
          _firstFrameMs = _sw.elapsedMilliseconds;
          _log('引擎=AVPlayer 源=$host 首帧=${_firstFrameMs}ms 时长=${c.value.duration.inSeconds}s ✅');
        }
        setState(() {});
      }

      c.addListener(tick);
      final dur = c.value.duration.inMilliseconds;
      _log('引擎=AVPlayer 源=$host 起播=ok 时长=${dur}ms');
      if (mounted) {
        setState(() {
          _busy = false;
          _err = '';
        });
      }
    } catch (e) {
      if (!mounted) return;
      _log('引擎=AVPlayer 起播=fail（$e）');
      setState(() {
        _busy = false;
        _err = '播放失败：$e';
      });
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final v = c?.value;
    final ready = v != null && v.isInitialized;
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            Center(
              child: AspectRatio(
                aspectRatio: v.aspectRatio <= 0 ? 16 / 9 : v.aspectRatio,
                child: VideoPlayer(c!),
              ),
            )
          else if (_busy)
            const Center(child: CircularProgressIndicator())
          else
            Center(
              child: Text(
                _err.isEmpty ? '加载失败' : _err,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          if (ready)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          iconSize: 20,
                          color: Colors.white,
                          icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow),
                          onPressed: () => v.isPlaying ? c!.pause() : c!.play(),
                        ),
                        Text(
                          '${_fmt(v.position)} / ${_fmt(v.duration)}'
                          '${v.isBuffering ? '  缓冲中' : ''}'
                          '${_firstFrameMs > 0 ? '  首帧=${_firstFrameMs}ms' : ''}',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        const Spacer(),
                        Text('AVPlayer', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
                      ],
                    ),
                    Slider(
                      value: v.position.inMilliseconds
                          .clamp(0, v.duration.inMilliseconds <= 0 ? 1 : v.duration.inMilliseconds)
                          .toDouble(),
                      max: (v.duration.inMilliseconds <= 0 ? 1 : v.duration.inMilliseconds).toDouble(),
                      onChanged: (x) => c!.seekTo(Duration(milliseconds: x.round())),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 让"是否走 AVPlayer"只在一处判断（iOS 才可能为真 ✅；Windows 恒 false ⇒ 行为逐字不变 ✅）
bool iosAvPlayerSelected() {
  if (!Platform.isIOS) return false; // ★ Windows/其它平台：**恒 false** ⇒ 现有 media_kit 路径一字不改 ✅
  return AppSettings.i.iosUseAvPlayer;
}
