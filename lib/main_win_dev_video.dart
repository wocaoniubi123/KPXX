/// KPXX · **Windows 桌面开发专用**：`video_player` 的 **media_kit / libmpv** 实现
/// （☠ 只在 `-t lib/main_win_dev.dart` 时被编译进来，发布入口 `lib/main.dart` 完全不碰）
///
/// ═══════════════════════════════════════════════════════════════════════════════════════════════
/// 【为什么需要这个文件】
///   房间页 `lib/sites/xhamsterlive.dart:854/1015/1148` 用的是 **`video_player`** —— 该插件
///   在 iOS 上是 AVPlayer ✓，但 **Windows 上根本没有实现** ✗（pub 上没有 `video_player_windows`）。
///   ⇒ `VideoPlayerPlatform.instance` 恒为 `video_player_platform_interface` 里的
///     `_PlaceholderImplementation`（`video_player_platform_interface-6.9.0/lib/video_player_platform_interface.dart:200` ✓）
///     ⇒ `initialize()` 里第一次调平台方法就抛 `UnimplementedError('createWithOptions() …')` ☠
///     ⇒ 房间页走 catch ⇒ 屏幕上只有一行错误文案（黑屏）✗。
///
///   本文件就是在**桌面 dev** 侧补上那个缺失的实现：**接口还是 `video_player` 的接口**（所以房间页
///   `lib/sites/**` **一个字不用改** ✓），**底层换成 media_kit / libmpv**（本仓 `KpPlayer` 用的同一套引擎 ✓）。
///
/// ☠ **契约来源（逐条照真源码，不是凭记忆 ✓）**：
///   · 主接口 `video_player_platform_interface-6.9.0/lib/video_player_platform_interface.dart`
///     —— `create()` :53 / `createWithOptions()` :59 / `videoEventsFor()` :64 / `setLooping()` :69 /
///        `play()` :74 / `pause()` :79 / `setVolume()` :84 / `seekTo()` :89 / `setPlaybackSpeed()` :94 /
///        `getPosition()` :99 / `buildView()` :105 / `buildViewWithOptions()` :110 / `setMixWithOthers()` :116 /
///        `dispose()` :47 / `init()` :42 / `setWebOptions()` :135 / 音视频轨 :140-197 ✓
///     —— 消息类型：`DataSource` :204（`sourceType`/`uri`/`formatHint`/`httpHeaders` ✓）、
///        `VideoEvent` :300（`eventType` 必填 + `duration`/`size`/`rotationCorrection`/`buffered`/`isPlaying` ✓）、
///        `VideoEventType` :370（`initialized`/`completed`/`bufferingUpdate`/`bufferingStart`/`bufferingEnd`/
///        `isPlayingStateUpdate`/`unknown` ✓）、`VideoCreationOptions` :604、`VideoViewOptions` :594 ✓
///   · 调用方 `video_player-2.10.1/lib/video_player.dart`：
///     —— `initialize()` :473 `createWithOptions(creationOptions)`（**viewType 在 options 里** ✓）⇒ :499
///        收到 `initialized` 那刻 `isInitialized = event.duration != null` ☠ **duration 为 null 就不算初始化** ✓
///       :556 紧跟着 `videoEventsFor(_playerId)` ⇒ **必须先 create 后 events** ✓
///     —— `_timer` :625 每 100ms 调 `getPosition()`（:675）⇒ 这个「直播间 position 前进」的读数就是从这来的 ✓
///     —— `_VideoPlayerState.build` :901 `buildViewWithOptions(VideoViewOptions(playerId: _playerId))`
///        ☠ **每次 build 都会调** ⇒ 里面**绝不能重建播放器/控制器**（否则每帧泄漏一套 mpv ✗✗）
///     —— `dispose()` :563 先 `await _creatingCompleter`，再 `_eventSubscription.cancel()` + `dispose(_playerId)` ✓
///
/// ☠ **音量口径（用户 2026-10-10 拍的长期规则：桌面 dev 不许出声 ✓）**：
///   · 初始音量 = `KpPlayer.startupVolumeOverride`（dev 入口设为 `0` ✓）；`null` ⇒ 0（本文件**恒静音**）✓。
///     同时给 `PlayerConfiguration(muted: true)` ⇒ 从**引擎建起来那一刻**就静音，
///     不存在"open 起播到收到 setVolume(0) 之间"的出声窗口 ✓。
///   · ★ 房间页 `xhamsterlive.dart:1026` 会显式 `await c.setVolume(1.0)`（**给 iOS 真机用的、注释写明"不静音"** ✓）
///     —— 本实现**压住**它：任何 `volume > 0` 一律落成 `0.0`（转成 media_kit 的 0..100 ⇒ `0.0`）✓。
///     ⚠️ 这是**桌面 dev 专属的刻意偏离**（用户点名要求 ✓）：**iOS 侧走不到本文件** ⇒ 那边一字不变 ✓。
///     ⇒ 想临时听声音：把 `main_win_dev.dart` 里那句 `KpPlayer.startupVolumeOverride = 0` 改掉即可 ✓。
/// ═══════════════════════════════════════════════════════════════════════════════════════════════
library;

import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart'; // 也带出 debugPrint ⇒ 不必再单独 import foundation ✓（analyze 实测 ✓）
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
// ⚠️ 用前缀：`media_kit` 也有个 `VideoTrack`（播放轨），与接口里的质量档 `VideoTrack` **重名** ☠
//   ⇒ 不加前缀就是 `ambiguous_import`（analyze 实测 ✓）。
// ⚠️ ignore_depend_on_referenced_packages：它是 `video_player` 的**传递依赖**（锁文件里就是 6.9.0 ✓），
//   而本文件所在入口是 dev 专用 ⇒ **为它去改共享的 `pubspec.yaml` 不值得**（约束：共享文件不动 ✗）。
//   出处与版本我在文件头已逐行标明（`video_player_platform_interface-6.9.0` ✓）。
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    as vpi;

import 'player_widget.dart'; // ★ KpPlayer.startupVolumeOverride（与 dev 入口同一个静态字段 ✓）

/// ★ 入口：在 `runApp` **之前**调用（`main_win_dev.dart` 里那行 ✓）。
///
/// 为什么要装：`VideoPlayerPlatform.instance` 默认是 placeholder（见文件头 ✓），
/// 而**桌面 dev 侧没有别的注册途径**（pub 上没有 `video_player_windows` ✓）。
void installMediaKitVideoPlayerPlatform() {
  vpi.VideoPlayerPlatform.instance = MediaKitVideoPlayerPlatform();
  debugPrint(
      '[WIN-VIDEO] 已装上 media_kit 版 VideoPlayerPlatform（video_player 接口 → libmpv）✓');
}

/// `VideoPlayerPlatform` 的 **media_kit / libmpv** 实现（桌面 dev 专用 ✓）。
///
/// ⚠️ 用 `extends`（**不是** `implements`）—— 接口文档
///   `video_player_platform_interface.dart:11-15` 原文点名要求：
///   "Platform implementations should extend this class rather than implement it" ✓
///   （而且 `VideoPlayerPlatform()` 的构造器要传基类 token —— `implements` 根本拿不到 ✓）。
class MediaKitVideoPlayerPlatform extends vpi.VideoPlayerPlatform {
  /// 递增 id（= `video_player` 那边的 "playerId" ✓）。
  /// ⚠️ 本实现**不用**它去找 Flutter 纹理：画面由 `Video(controller:)` 自己带纹理 ✓
  ///   —— 但 id 必须**唯一且稳定**（`video_player` 拿它当 key 索引进本类的 `_entries` ✓）。
  int _nextId = 1;

  final Map<int, _Entry> _entries = <int, _Entry>{};

  @override
  Future<void> init() async {
    // 无全局状态要建（`MediaKit.ensureInitialized()` 由 dev 入口负责 ✓）。
    // ⚠️ 接口文档 :38-41 说本方法「disposes all existing players」⇒ 照做 ✓（本进程里就是清表）。
    final ids = _entries.keys.toList(growable: false);
    for (final id in ids) {
      await dispose(id);
    }
  }

  @override
  Future<int?> create(vpi.DataSource dataSource) async {
    final uri = dataSource.uri;
    if (uri == null || uri.isEmpty) {
      throw PlatformException(
        code: 'invalid_source',
        message: '[WIN-VIDEO] create() 只支持有 uri 的源'
            '（拿到 sourceType=${dataSource.sourceType}）✗',
      );
    }

    final id = _nextId++;

    // ★ 初始音量（见文件头「音量口径」✓）：dev 入口设 0 ⇒ 全程静音。
    //   `startupVolumeOverride == null`（理论上桌面 dev 不会发生）也按 0 走 —— 本文件恒静音 ✓。
    final raw = KpPlayer.startupVolumeOverride;
    final initialVolume = (raw ?? 0.0).clamp(0.0, 1.0);

    // ① 先建 Player（muted 从建立那一刻就生效 ⇒ 没有出声窗口 ✓）
    //    ⚠️ **bufferSize 用 media_kit 默认（32MB ✓）**：
    //       它进去就是 `demuxer-max-bytes` / `demuxer-max-back-bytes`（`native/player/real.dart:2565-2566` ✓）
    //       ⇒ **等于 mpv 的缓冲上限**。本机实测：按 `KpPlayer` 那个 200MB 设，
    //       播 1080p HLS 时进程 RSS 从 ~350MB 一路涨到 ~770MB（26 秒内 ✓ `_tmp_win_video_logs/run6_hls.log` ✓）。
    //       直播**不需要**那么大的前向缓冲 ⇒ 保持默认，别在 16G 机器上白占内存 ✓。
    final player = Player(
      configuration: PlayerConfiguration(
        muted: initialVolume <= 0.0,
      ),
    );
    // ② ★ 渲染上下文（VideoController）**必须在 `open()` 之前**建好 ——
    //    先例：本仓 `player_widget.dart:161-164` 的注释（"否则 iOS 上 mpv 打开 vo/libmpv 时会报
    //    `No render context set`，表现就是只有声音、画面全黑（media-kit issue #1192）" ✓）。
    final controller = VideoController(player);

    final entry = _Entry(
      id: id,
      player: player,
      controller: controller,
      volume: initialVolume *
          100.0, // media_kit 口径 0..100（`Player.setVolume` 文档 :857 ✓）
    );
    // ★ 登记必须**在 `open()` 之前**（且在同一段同步代码里）：`getPosition()` / `_onTick` 从
    //   `open()` 那一瞬间就可能被调到 ⇒ 查不到 id 就会抛 ☠。
    _entries[id] = entry;

    // 流接线（全部挂在 entry 上、由 `dispose()` 负责收 ✓）
    entry.subs.addAll(<StreamSubscription<Object?>>[
      player.stream.width.listen((_) => entry.maybeEmitInitialized()),
      player.stream.height.listen((_) => entry.maybeEmitInitialized()),
      player.stream.duration.listen((_) => entry.maybeEmitInitialized()),
      // 播放态（房间页的 `value.isPlaying` 用得上；`_VideoAppLifeCycleObserver` 也靠它 ✓）
      player.stream.playing.listen((v) {
        entry.emit(vpi.VideoEvent(
          eventType: vpi.VideoEventType.isPlayingStateUpdate,
          isPlaying: v,
        ));
      }),
      player.stream.completed.listen((v) {
        if (v) {
          entry.emit(vpi.VideoEvent(eventType: vpi.VideoEventType.completed));
        }
      }),
      // 缓冲态：media_kit 只有一个 bool 流 ⇒ 只在前沿变化时报 start/end（防秒级刷屏 ☠）
      player.stream.buffering.listen((v) {
        if (entry.lastBuffering == v) return;
        entry.lastBuffering = v;
        entry.emit(vpi.VideoEvent(
          eventType: v
              ? vpi.VideoEventType.bufferingStart
              : vpi.VideoEventType.bufferingEnd,
        ));
      }),
      // ★ 错误：media_kit 的 `stream.error` 只收**真错误**（`native/player/real.dart:2229-2265` 逐条过滤：
      //   `file` / `ffmpeg tcp:` / `vd` / `ad` / `cplayer` / `stream` 且 level == error ✓）
      //   ⇒ **直通**给 `video_player`，走它自己的 `errorListener`（`video_player.dart:547-554` ✓）
      //   ⇒ 房间页 `_onTick` 的 `errorDescription` 分支照旧能亮 ✗（= 用户要的"房间页原有错误分支要能暴露出来" ✓）。
      //   ☠ 必须包成 `PlatformException`：调用方那句是 `obj as PlatformException`（`video_player.dart:548` ✓）
      //      —— 直传 String 会 **强制转换失败** ☠（更糟：那异常会炸在 listen 的 onError 里）。
      player.stream.error.listen((e) {
        final code = e.startsWith('Http') ? 'error_http' : 'error_media';
        entry.emitError(PlatformException(code: code, message: e));
      }),
    ]);

    // ③ 真正开流（httpHeaders 带房间页给的 UA ✓ —— `video_player.dart:447` 把 httpHeaders 放进了 DataSource ✓）
    try {
      await player.open(
        Media(
          uri,
          httpHeaders:
              dataSource.httpHeaders.isEmpty ? null : dataSource.httpHeaders,
        ),
        play:
            false, // ★ 交给 `play()`（`video_player` 的 `_applyPlayPause()` ✓），这里不抢着起播
      );
    } catch (e) {
      debugPrint(
          '[WIN-VIDEO] id=$id open() 抛了（照抛给 video_player，让房间页的失败分支处理）✗ $e');
      rethrow;
    }

    // ④ 等渲染上下文就位再返回 id —— 理由：
    //    `Player.dispose()`（native/player/real.dart:79）会 `await waitForVideoControllerInitializationIfAttached`
    //    ⇒ 建完 Player 又赶在 VideoController 初始化完成前 dispose ⇒ **dispose 会一直挂着** ☠；
    //    在这里等一下，能让 `video_player` 的 `dispose()` 拿到一个必然能走完的 Player ✓。
    try {
      await controller.platform.future.timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[WIN-VIDEO] id=$id VideoController 初始化失败/超时（画面可能出不来）✗ $e');
    }
    entry.maybeEmitInitialized();

    debugPrint(
        '[WIN-VIDEO] ①create id=$id host=${Uri.tryParse(uri)?.host ?? '?'} '
        '初始音量=${entry.volume}（0..100 口径；0=静音 ✓）');
    return id;
  }

  @override
  Future<void> dispose(int playerId) async {
    final entry = _entries.remove(playerId);
    if (entry == null) return; // 幂等（`video_player` 只调一次，但别让二次调用炸 ☠）
    entry.disposed = true;
    for (final s in entry.subs) {
      unawaited(s.cancel().catchError((Object _) {}));
    }
    entry.subs.clear();
    // ★ 真释放（用户点名要求，不许泄漏 ✓）：
    //   `Player.dispose()` ⇒ native `mpv_terminate_destroy`（`native/player/real.dart:87-95` ✓，
    //   注意它在 5 秒延迟后才 terminate —— 那是 media_kit 自己的收尾节奏 ✓）；
    //   `VideoController` 的纹理/解码面由 `player.platform.release` 回调带走
    //   （`media_kit_video/.../native_video_controller/real.dart:89` `release.add(controller._dispose)` ✓）
    //   ⇒ **dispose Player 一条就够**，不用（也没有）单独的 VideoController.dispose() ✓。
    try {
      await entry.player.dispose();
      debugPrint('[WIN-VIDEO] ②dispose id=$playerId 完成（mpv 已 terminate）✓');
    } catch (e) {
      debugPrint('[WIN-VIDEO] ②dispose id=$playerId 抛了：$e');
    }
  }

  @override
  Stream<vpi.VideoEvent> videoEventsFor(int playerId) {
    final entry = _entries[playerId];
    if (entry == null) {
      return const Stream<vpi.VideoEvent>.empty();
    }
    return entry.events.stream;
  }

  @override
  Future<void> play(int playerId) async {
    final entry = _entries[playerId];
    if (entry == null) return;
    await entry.player.play();
    entry.emit(vpi.VideoEvent(
      eventType: vpi.VideoEventType.isPlayingStateUpdate,
      isPlaying: true,
    ));
  }

  @override
  Future<void> pause(int playerId) async {
    final entry = _entries[playerId];
    if (entry == null) return;
    await entry.player.pause();
    entry.emit(vpi.VideoEvent(
      eventType: vpi.VideoEventType.isPlayingStateUpdate,
      isPlaying: false,
    ));
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    final entry = _entries[playerId];
    if (entry == null) return;
    // `PlaylistMode.single` = 单曲循环 ✓；`none` = 播完就停 ✓（`player.setPlaylistMode` ✓）
    await entry.player
        .setPlaylistMode(looping ? PlaylistMode.single : PlaylistMode.none);
  }

  /// ★★ 桌面 dev 的**静音压口**：任何 `volume > 0` 一律落成 `0`（见文件头「音量口径」✓）。
  @override
  Future<void> setVolume(int playerId, double volume) async {
    final entry = _entries[playerId];
    if (entry == null) return;
    final requested = volume.clamp(0.0, 1.0).toDouble();
    // ⚠️ 请求多少都压成 0 ⇒ dev 恒静音（用户点名要求 ✓）；只打日志方便验证 ✓。
    const double effective = 0.0;
    entry.volume = effective * 100.0;
    debugPrint('[WIN-VIDEO] setVolume id=$playerId 请求=$requested 实际=$effective'
        '${requested > 0 ? '（**被 dev 静音压住**，见 main_win_dev_video.dart 文件头 ✓）' : ''}');
    await entry.player.setVolume(entry.volume);
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    final entry = _entries[playerId];
    if (entry == null) return;
    await entry.player.seek(position);
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {
    final entry = _entries[playerId];
    if (entry == null) return;
    await entry.player.setRate(speed);
  }

  /// ★ 房间页 `_onTick` 那句 `v.position > Duration.zero`（"真首帧"判据）读的就是它；
  ///   `video_player` 的 100ms 定时器（`video_player.dart:625`）也每拍读一次 ✓。
  ///   ⚠️ 拿不到（id 已 dispose / 已释放）⇒ 返 `Duration.zero`，**绝不抛** ✗
  ///   —— 抛了会变成 100ms 一次未处理异常 ☠。
  @override
  Future<Duration> getPosition(int playerId) async {
    final entry = _entries[playerId];
    if (entry == null) return Duration.zero;
    try {
      return entry.player.state.position;
    } catch (_) {
      return Duration.zero;
    }
  }

  /// ☠ **每次 build 都调**（`video_player.dart:906` ✓）⇒ 这里**只能拼 widget**，
  /// 绝不新建 Player / VideoController（否则每帧泄漏一套 mpv ✗✗）。控制器在 `create()` 里建、`dispose()` 里收 ✓。
  ///   `controls: null` —— 房间页只要"画面 + X"（`xhamsterlive.dart:1141` 注释原文 ✓），
  ///   而且它外面套了 `IgnorePointer`（`:1148`）⇒ 就算给控件也点不动，不如不给 ✓。
  @override
  Widget buildView(int playerId) {
    final entry = _entries[playerId];
    if (entry == null) return const SizedBox.shrink();
    return Video(
      key: ValueKey<int>(playerId),
      controller: entry.controller,
      controls: null,
      fit: BoxFit.contain,
    );
  }

  /// 老接口（`video_player` 2.10.1 走的是 `buildViewWithOptions` ⇒ 这里显式转发，保持两条路一致 ✓）
  @override
  Widget buildViewWithOptions(vpi.VideoViewOptions options) =>
      buildView(options.playerId);

  // ── 以下按接口契约补齐（桌面 dev 用不到，但**不能留着基类抛 UnimplementedError** ☠，
  //    因为调用方随时可能摸到：`video_player.dart:468` 就是一句无条件 `setMixWithOthers` ✓）──

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {
    // 无对应项：libmpv 的音频会话本来就不独占（本仓桌面播放线一直如此 ✓）⇒ no-op ✓
  }

  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {
    // 无对应项 ⇒ no-op（桌面窗口最小化时 mpv 照旧在播，与 iOS 后台策略无关 ✓）
  }

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool preventsDisplaySleepDuringVideoPlayback,
  ) async {
    // 无对应项 ⇒ no-op（房间页从不调它 ✓；不引 wakelock 依赖，桌面 dev 没这个必要 ✓）
  }

  @override
  Future<void> setWebOptions(
      int playerId, vpi.VideoPlayerWebOptions options) async {
    // web-only ⇒ 桌面 no-op ✓（基类默认抛 UnimplementedError，这里按契约补齐 ✓）
  }

  @override
  Future<List<vpi.VideoAudioTrack>> getAudioTracks(int playerId) async =>
      const <vpi.VideoAudioTrack>[];

  @override
  Future<void> selectAudioTrack(int playerId, String trackId) async {}

  @override
  bool isAudioTrackSupportAvailable() => false;

  @override
  Future<List<vpi.VideoTrack>> getVideoTracks(int playerId) async =>
      const <vpi.VideoTrack>[];

  @override
  Future<void> selectVideoTrack(int playerId, vpi.VideoTrack? track) async {}

  @override
  bool isVideoTrackSupportAvailable() => false;
}

/// 一个 playerId 的全部运行时状态（`create()` 建 / `dispose()` 收 ✓）。
class _Entry {
  _Entry({
    required this.id,
    required this.player,
    required this.controller,
    required this.volume,
  });

  final int id;
  final Player player;
  final VideoController controller;

  /// 当前**实际**音量，media_kit 口径 0..100（本实现恒 0 ✓ —— 见文件头）
  double volume;

  final StreamController<vpi.VideoEvent> events =
      StreamController<vpi.VideoEvent>.broadcast();

  final List<StreamSubscription<Object?>> subs =
      <StreamSubscription<Object?>>[];

  /// `initialized` **只许发一次**（接口文档 `video_player_platform_interface.dart:372` 原文：
  /// "A maximum of one event of this type may be emitted per instance" ✓；
  /// 多发还会撞上调用方的断言 `video_player.dart:502` ☠）
  /// ☠ 注意**不是**"一次就够"那么简单：调用方把 `initialized` 当**唯一一次**的握手
  ///（多发 ⇒ 它内部断言直接炸，实测踩过 ✓ 见下面 `_initLatch` 的说明）⇒ 这里用**不可回退**的闩 +
  /// "已发过就永不再发"两道闸 ✓
  bool initializedEmitted = false;

  /// `initialized` 到底发了几次（只看日志 ✓）
  int initializedCount = 0;

  /// 缓冲态前沿（只在前沿变化时报 start/end ✓）
  bool lastBuffering = false;

  bool disposed = false;

  void emit(vpi.VideoEvent e) {
    if (disposed || events.isClosed) return;
    events.add(e);
  }

  void emitError(Object e) {
    if (disposed || events.isClosed) return;
    // ☠ 记一笔：**出过错就永远不发 `initialized`**（下面 `maybeEmitInitialized` 的闸之一 ✓）——
    //   理由（实测踩到 ✓）：调用方把 `initialized` 当**唯一一次**的握手，
    //   若它先用 `errorListener` 把 `initializingCompleter` 完成（`video_player.dart:551-553`），
    //   之后再来一条 `initialized` ⇒ 那句 `assert(!initializingCompleter.isCompleted, …)`
    //   （`video_player.dart:502-508`）**直接抛**（真机实测原文见本仓 `_tmp_win_video_logs/run5_hls_dispose2.log:54` ✓）。
    errorSeen = true;
    events.addError(e);
  }

  /// 这条流上出过错（⇒ 不再发 `initialized` ✓）
  bool errorSeen = false;

  /// ★ 发 `initialized` 的条件（缺一不可）：
  ///   ① 宽高都拿到了（libmpv 报的 `video-params/dw|dh` ⇒ 说明解码面/纹理真出来了 ✓，
  ///      依据 `native/player/real.dart:2175-2198`：dw/dh 有效才写 width/height ✓）；
  ///   ② 还没发过；
  ///   ③ **这条流没出过错**（☠ 关键：见 [emitError] 的说明 —— 出错后再发就是撞调用方断言 ✓）。
  ///   ⚠️ `duration` **不能为 null** —— 调用方据此判 `isInitialized`（`video_player.dart:498` ✓）：
  ///      直播流 duration 可能是 0（无从算总长 ✓ 房间页不看它 `xhamsterlive.dart:1103` 只看 position ✓），
  ///      但**不能是 null** ⇒ 这里给 `state.duration`（`Duration` 非空类型 ✓）。
  void maybeEmitInitialized() {
    if (initializedEmitted || disposed || errorSeen) return;
    final w = player.state.width;
    final h = player.state.height;
    if (w == null || h == null || w <= 0 || h <= 0) return;
    initializedEmitted = true;
    debugPrint('[WIN-VIDEO] emit initialized id=$id（共 ${++initializedCount} 次）'
        ' w=$w h=$h dur=${player.state.duration.inMilliseconds}ms');
    emit(vpi.VideoEvent(
      eventType: vpi.VideoEventType.initialized,
      duration: player.state.duration,
      size: Size(w.toDouble(), h.toDouble()),
      rotationCorrection: 0, // 不转（`Video` 自己铺满，房间页外面还有 AspectRatio ✓）
    ));
  }
}
