import 'dart:async';

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

/// ★ 2026-10-08（本批修 ✓ · 用户实报「控件像假的」）：**控件/状态变了就主动踢一帧** ——
///   真机实锤（1.2.8 日志）：单击切换的状态翻转了、3 秒隐藏也执行了，但**屏幕纹丝不动**，
///   直到滚动/转场带来一帧才"追认" ☠ ⇒ 特征 = setState 排了队却没有帧来消化（帧调度停摆）✓。
///   ⇒ 官方 API `ensureVisualUpdate()`：幂等 ✓ 极轻 ✓ 确保有一帧会来 ✓（这个不进日志开关——它是功能修复）。
void kickPlayerFrame() {
  WidgetsBinding.instance.ensureVisualUpdate();
}

/// 篇内视频切换状态：详情页持有，内嵌播放器与全屏页共用同一份。
/// 共用一份是为了避免全屏页拿到"推送那一刻"的序号快照——
/// 那样切到最后一个后按钮状态会不对，再点就跳错集 ✗（切到最后一个后按钮状态会不对 ✓）
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

  /// ★ 2026-10-08（用户拍板 ⑦ ✅）：**与 [pauseTick] 对称的"继续播"信号**（自增计数）——
  ///   详情页被别的页压到栈下面、又回到栈顶时发一次（RouteAware 的 `didPopNext` ✅），
  ///   把"**我们自己停的**那一次暂停"续起来 ✅（原来只有停、没有续 ⇒ 回来得手点一下 ✗）。
  ///   ⚠️ 只续"我们停的"☑️：用户**手动**暂停过再跳走 ⇒ 详情页那侧**根本不会发**这个信号 ✅
  ///   （判据在详情页：`_pausedByPush = 跳走的那一刻本来在播` ✅）。
  ///   ⚠️ 跟 [pauseTick] 一样，不直接调播放器（实例由 PlayerWidget 持有、全屏页也共用它 ✓）。
  final ValueNotifier<int> resumeTick = ValueNotifier<int>(0);
  void resume() => resumeTick.value++;

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
    resumeTick.dispose();
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

  const KpState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.error = false,
    this.errorText = '',
    this.buffer = Duration.zero,
    this.completed = false,
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
        // ★【常驻诊断】只打**首次** position>0（首帧 ✓）⇒ 防刷屏 ☠；`_everStarted` 是既有字段 ✓ 不改它的用法 ✓
        if (v > Duration.zero && !_everStarted) {
          if (AppSettings.i.logConsole) debugPrint('[PLAY] 首帧 position=${v.inMilliseconds}ms');
        }
        if (v > Duration.zero) _everStarted = true;
      }),
      // ★【常驻诊断·★】时长拿到那一刻（**"总进度只有几秒"就看这一条** ✓ 只打一次 ✓ 不改逻辑 ☠）
      //   ⚠️ 这里**不打 host** ✗：本 State 里没有"当前源 URL"的字段（读不到 ⇒ 不猜 ✓）—— 要 host 得看 `[PLAY] host=` 那条 ✓
      _p.stream.duration.listen((v) {
        if (v > Duration.zero && value.duration <= Duration.zero) {
          if (AppSettings.i.logConsole) debugPrint('[PLAY] 时长=${v.inSeconds}s（首次拿到 ✓）');
        }
        value = value.copyWith(duration: v);
      }),
      // ★ 2026-10-08（本批修 ✓ · 用户实报 + 日志实锤）：**用户意图优先** ——
      //   media_kit 在 `pause()` 之后**仍然会报 `playing = true`** ☠（真机日志：连点 10 次暂停，
      //   控件那侧读到的 `当前playing` **一直是 true** ✗）⇒ 引擎的值会把"用户按了暂停"冲掉 ✗
      //   ⇒ 按钮图标不换、再点又判"当前在播" ⇒ **又一次 pause()** ☠
      //   ⇒ 所以「用户明确按过暂停」时，**引擎报"在播"一律不认** ✓；
      //     引擎报 `false`（真停了）照收 ✓；用户按下播放后 `_userPaused` 复位 ⇒ 之后照常收 ✓。
      //   ⚠️ 看门狗不看这个字段（它读 `_userPaused` + 位置 ✓）⇒ 这条只影响按钮状态显示 ✓。
      _p.stream.playing.listen((v) {
        // ★【常驻诊断·关键】引擎报的**每一个** playing 值都留痕（这个流只在变化时发 ⇒ 天然不刷屏 ✓）——
        //   "按钮状态被冲回在播"要看的正是「引擎什么时候报了 true」✓（这是绕了三轮才补上的判据 ✗）
        if (AppSettings.i.logConsole) {
          final blocked = _userPaused && v;
          debugPrint('[PLAY] 引擎 playing=$v（_userPaused=$_userPaused 状态里旧值=${value.playing}）'
              '${blocked ? ' ⇒ 拦下（用户暂停过，不采纳）' : ' ⇒ 采纳'}');
        }
        if (_userPaused && v) return; // 用户暂停过 ⇒ 引擎说"在播"也不认（否则状态被冲掉 ☠）
        // ★【常驻诊断·关键】**引擎自己**把 `playing` 置成 false（不是用户按的）——
        //   "返回后视频看着播了一下又停"要看的正是这条 ✓（它说明是引擎/会话侧停了，不是我们发的 pause ✓）
        if (!v && !_userPaused && value.playing) {
          if (AppSettings.i.logConsole) {
            debugPrint('[PLAY] 引擎自行停止（非用户暂停）pos=${value.position.inMilliseconds}ms buffering=${value.buffering}');
          }
        }
        value = value.copyWith(playing: v);
      }),
      // ★【常驻诊断·★】缓冲起/止（卡顿判据 ✓ 只在变化时打 ✓ 防刷屏 ☠）
      _p.stream.buffering.listen((v) {
        if (v != value.buffering) {
          if (AppSettings.i.logConsole) debugPrint('[PLAY] 缓冲 ${v ? '起' : '止'}');
        }
        value = value.copyWith(buffering: v);
      }),
      // mpv demuxer-cache-time = 已缓存数据的最后时间戳（绝对位置）
      _p.stream.buffer.listen((v) => value = value.copyWith(buffer: v)),
      // ★【常驻诊断】播放结束（一条流跑完 ✓ 只打一次 ✓）
      _p.stream.completed.listen((v) {
        if (v && !value.completed) {
          if (AppSettings.i.logConsole) debugPrint('[PLAY] 播放结束 position=${value.position.inSeconds}s duration=${value.duration.inSeconds}s');
        }
        value = value.copyWith(completed: v);
      }),
      // 引擎的 error 流里也会混入 FFmpeg 的偶发网络错误
      // （如 tcp: ffurl_read returned ...，此时视频往往还在正常播）。
      // 所以：已经在播就不弹提示（真卡住由看门狗负责判断）；**首帧前也不立刻当失败** ✓
      // ⚠️ 2026-10-05（用户报"明明能放，它也自动重试"）：原来首帧前**任何** error 都当场写
      //    `KpState.error` ✗ —— 而 `error` 同时是 `_openAndWait` 的"这条源失败"信号（:1005 ✓）
      //    → 启动期一次偶发 error = **无谓换源重载** ✗。
      //    现在只挂"待定"（`_startupErrPending` ✓），由看门狗宽限 [_kStartupErrHoldMs] 后
      //    **仍未就绪**才算这条源失败 ✓（见看门狗里那段 ✓）—— 单次偶发不再换源 ✓。
      _p.stream.error.listen((e) {
        // ★ 截断到 120 字 ✓（先取字符串再判长度 —— 别对字面量取子串 ✗ 会越界 ☠）
        final es = e;
        if (AppSettings.i.logConsole) debugPrint('[PLAY] 错误流 首帧前=$_everStarted ${es.length <= 120 ? es : es.substring(0, 120)}');
        _lastFatal = e;
        if (!_everStarted) _startupErrPending = true;
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
        // ★【常驻诊断】看门狗撤 error（位置又在走 = 确实在播 ✓ 只在真触发时打 ✓）
        if (AppSettings.i.logConsole) debugPrint('[PLAY] 看门狗 撤 error（位置已前进 ${(s.position - _lastPos).inMilliseconds}ms）');
        value = value.copyWith(error: false, errorText: '');
      }
      // ⚠️ 2026-10-05：卡顿期间 mpv 常把 playing 报成 false（缓冲中），原来这里 `!s.playing`
      //      直接清零 → **看门狗永远判不出"卡住"** ✗（表现：画面静止、不报错、不重试 ✓）。
      //      现在只把**用户主动暂停**排除（_userPaused ✓），缓冲中照常计时 ✓。
      // ⚠️ 2026-10-05（用户报"加载中就直接重试"）—— **首帧门禁**：
      //      还没出过第一帧（`_everStarted == false` ✓）时**不判"卡住"、也不写 `KpState.error`** ✗。
      //      依据：加载/缓冲期 position 恒为 0 ✓ → 原来凑够 9 秒就置 error ✓，而 `error` **同时**是
      //      `_openAndWait` 的"这条源失败"信号（`player_widget.dart:944` ✓）→ **提前换源重载** ✗。
      //      连接阶段的失败**交给原有兜底** ✓（`_openAndWait` 的 15 秒超时 :964-965 + 引擎 error 流
      //      :162-168 ✓）—— 不新造判据 ✓。首帧出来之后（`_everStarted == true` ✓）照旧按 9 秒判卡住 ✓。
      if (_userPaused || s.error) {
        _stuckMs = 0;
        _noFrameMs = 0;
        _startupErrPending = false; // 暂停 / 已失败：待定的偶发 error 作废 ✓
        _errHoldMs = 0;
        _lastPos = s.position;
        return;
      }
      if (!_everStarted) {
        // ★ 首帧前的**偶发 error 宽限**（2026-10-05，用户报"明明能放，它也自动重试" ✓）：
        //   启动期 mpv 偶发报错（ffmpeg 自己会重试 ✓ 见上面 log 流那段注释 ✓）——
        //   单次 error **绝不**当失败 ✗（那会被 `_openAndWait` 当"这条源失败" → 无谓换源重载 ✗）。
        //   · 判据：`_startupErrPending`（error 流挂的待定 ✓）连挂满 [_kStartupErrHoldMs] ✓
        //   · **`ready` 一到就作废** ✓（已经 open 成功 → 交给下面那条 12 秒无首帧兜底管 ✓，
        //     两条判据不重叠 ✓、也不重复判 ✓）
        //   · 到点只写 `error` ✓ → 后面走现成的失败路径 ✓（`_openAndWait` 判失败换源 /
        //     已在播则 `_onTick` 排重试 ✓），不另起状态机 ✓
        //   · **只触发一次** ✓：触发后 `error` 已置上 → 上面 `s.error` 分支每轮清零 ✓
        if (_startupErrPending) {
          if (s.ready) {
            _startupErrPending = false; // 就绪了 → 这次偶发作废 ✓（零换源 ✓）
            _errHoldMs = 0;
          } else {
            _errHoldMs += 1000;
            if (_errHoldMs >= _kStartupErrHoldMs) {
              // ★【常驻诊断】看门狗判"这条源不行"（首帧前偶发 error 宽限到点仍未就绪 ✓）
              if (AppSettings.i.logConsole) debugPrint('[PLAY] 看门狗 判失败(启动期error宽限${_kStartupErrHoldMs ~/ 1000}s) userPaused=$_userPaused everStarted=$_everStarted ready=${s.ready} pos=${s.position.inMilliseconds}ms 引擎日志=${_lastFatal.isEmpty ? '(无)' : (_lastFatal.length <= 80 ? _lastFatal : _lastFatal.substring(0, 80))}');
              _startupErrPending = false;
              _errHoldMs = 0;
              value = value.copyWith(
                error: true,
                errorText: _lastFatal.isEmpty
                    ? '打开失败（${_kStartupErrHoldMs ~/ 1000} 秒内没有就绪）'
                    : '打开失败；引擎日志：$_lastFatal',
              );
            }
          }
        }
        // ★ 首帧前的**长兜底**（2026-10-05，用户拍板 ✓）：堵住"`duration` 到了（=`ready` ✓，
        //   `_openAndWait` 已判成功 ✓）但**首帧永远不来**"这个洞（那时 15 秒超时已经用完了 ✗）。
        //   · 判据用 **`ready`（`duration > 0` = 已经 open 成功 ✓）**，**不是**"已连上" ✓
        //     —— 连接阶段归 `_openAndWait` 的 15 秒管 ✓，两条判据不打架 ✓（`!ready` → 清零 ✓）
        //   · 阈值 [_kFirstFrameLimitMs] = **12 秒** ✓（用户拍板：加载流畅优先、别等太久 ✓）：
        //     这里**不是**旧 bug 那个 9 秒 ✗ —— 那条是**从播放器构造就算**（连"连接 + 解析清单"
        //     都算进去 ✗ → 正常加载被误判 ✗）；这条**从 open 成功（`ready`）之后才算** ✓，
        //     那时清单已解析 ✓ 只等首帧 ✓，正常 1~3 秒 ✓ → 12 秒有 4~10 倍余量 ✓
        //     （正常加载绝不会触发 ✓，即"用户报的那个 bug 不许回来" ✓）
        //   · 到点 → 按"这条源不行"处理 ✓：**只写 `error`**，后面走**现成的失败路径** ✓
        //     （`_onTick` 的 errEdge → `_notePlaybackError` → 重开/换源 ✓），不另起状态机 ✓
        //   · **只触发一次** ✓：触发后 `error` 已被置上 → 上面 `s.error` 分支每轮清零 ✓
        //     （error 被撤掉后要再攒满 12 秒才可能再响 ✓；整条链还有 5 次重试上限兜着 ✓）
        _stuckMs = 0;
        _lastPos = s.position;
        if (s.ready) {
          _noFrameMs += 1000;
          if (_noFrameMs >= _kFirstFrameLimitMs) {
            // ★【常驻诊断】看门狗判"首帧超时"（已 open 成功但这么久没画面 ✓）
            if (AppSettings.i.logConsole) debugPrint('[PLAY] 看门狗 判失败(首帧超时${_kFirstFrameLimitMs ~/ 1000}s) userPaused=$_userPaused everStarted=$_everStarted ready=${s.ready} pos=${s.position.inMilliseconds}ms duration=${s.duration.inSeconds}s');
            _noFrameMs = 0;
            value = value.copyWith(
              error: true,
              errorText: '首帧超时（已打开但 ${_kFirstFrameLimitMs ~/ 1000} 秒没有画面）',
            );
          }
        } else {
          _noFrameMs = 0; // 还没 open 成功 → 这条不计（连接阶段不归它管 ✓）
        }
        return;
      }
      _noFrameMs = 0; // 首帧已到 → 这条兜底归零 ✓（之后只走下面 9 秒那条 ✓）
      _startupErrPending = false; // 首帧已到 → 待定的偶发 error 也无所谓了 ✓
      _errHoldMs = 0;
      if ((s.position - _lastPos).abs().inMilliseconds < 500) {
        _stuckMs += 1000;
        if (_stuckMs >= _stuckLimitMs) {
          // ★【常驻诊断】看门狗判"卡住"（位置连续不前进 ✓ 含 _userPaused / 位置 / _everStarted ✓）
          if (AppSettings.i.logConsole) debugPrint('[PLAY] 看门狗 判卡住(${_stuckLimitMs ~/ 1000}s 未前进) userPaused=$_userPaused everStarted=$_everStarted pos=${s.position.inMilliseconds}ms lastPos=${_lastPos.inMilliseconds}ms playing=${s.playing} buffering=${s.buffering} 引擎日志=${_lastFatal.isEmpty ? '(无)' : (_lastFatal.length <= 80 ? _lastFatal : _lastFatal.substring(0, 80))}');
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
  /// **首帧前**的长兜底计时（毫秒）：只在"已 open 成功（`ready` ✓）但还没首帧"时累加 ✓。
  /// 与 [_stuckMs] **分开两个计数器** ✗（两条阈值不同：首帧前 12 秒 / 首帧后 9 秒 ✓）。
  int _noFrameMs = 0;
  /// 首帧前**收到过引擎 error**（还没定罪 ✓）：由看门狗宽限 [_kStartupErrHoldMs] 后仍未就绪才判失败 ✓。
  /// 单次偶发 error（启动期常见 ✓）到这步就作废 ✓ → **不换源、不重载、不弹重试** ✓。
  bool _startupErrPending = false;
  /// 上面那条宽限的计时（毫秒）：只在 `_startupErrPending` 时累加 ✓（粒度 = 看门狗 1 秒 ✓）。
  int _errHoldMs = 0;

  /// 当前这个 error 是不是**看门狗自己判的卡住**（只有它才由看门狗自己撤）。
  /// 起播失败那类 error 不归它管 —— 撤了会把"真失败"静默掉。

  /// 位置连续多久不前进就判为卡住（毫秒）—— **首帧之后**用（保持不变 ✓）
  static const int _stuckLimitMs = 9000;

  /// **首帧前**的长兜底阈值（毫秒）：已 open 成功（`ready` = `duration > 0` ✓）后这么久还没首帧
  /// → 按"这条源不行"处理 ✓（写 `error` → 走现成失败路径 ✓）。**要调就改这一行** ✓。
  /// 为什么 **12 秒**（用户 2026-10-05 拍板：优先保证加载流畅、等待别太长 ✓）：
  ///   · 它与旧 bug 那个 9 秒**不是一回事** ✗ —— 旧的是**从播放器构造就开始算**（把"连接 + 解析清单"
  ///     都算进去了 → 正常加载被误判 ✗）；这条**从 open 成功之后才算** ✓（那时清单已解析 ✓ 只等首帧 ✓）。
  ///   · 清单解析完后正常首帧一般 1~3 秒 ✓ → 12 秒是 4~10 倍余量 ✓；也比 30 秒那版短得多 ✓，
  ///     真卡住能更早换源 ✓（用户：优先保证加载流畅 ✓）。
  ///   · **加载成功的场景不引入任何额外等待** ✗（它只在"真卡住"时才动作 ✓）。
  ///   · 与 `_openAndWait` 的 15 秒连接超时**不重叠** ✓（连接阶段 `!ready` → 这条不计 ✓）。
  static const int _kFirstFrameLimitMs = 12000;

  /// **首帧前**偶发 error 的**宽限期**（毫秒）：收到 error 后先挂待定（`_startupErrPending` ✓），
  /// 到期**仍未 `ready`**（= 还没 open 成功 ✓）才判"这条源不行" ✓（写 `error` → 换源 ✓）。
  /// 为什么 **3 秒**：目标"单次偶发不换源、真失败 ~3 秒内判掉" ✓ ——
  ///   · 启动期偶发 error（ffmpeg 自己会重试 ✓）通常几百毫秒内就恢复 ✓ → 3 秒足够漂过去 ✓
  ///   · 真死源（连不上/清单 404）不再干等 `_openAndWait` 的 15 秒 ✓
  ///   · 记账在**现成的 1 秒看门狗**里 ✓（不新起定时器 ✓/不新 await ✓）
  ///   · ⚠️ 粒度 = 1 秒 ⇒ 实际生效 = **2~3 秒**（error 落在 tick 之间的位置决定）✓
  ///   · `ready` 一到就作废 ✓（那时交给 [_kFirstFrameLimitMs] 那条管 ✓，两条不重叠 ✓）
  static const int _kStartupErrHoldMs = 3000;

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
    _noFrameMs = 0; // ⚠️ 2026-10-05：首帧前那条 12 秒兜底也**随换源归零** ✓（每条源各算各的 ✓）
    _startupErrPending = false; // 首帧前那条 3 秒宽限同理：新源重新算 ✓（上一条源的偶发不作数 ✓）
    _errHoldMs = 0;
    // ★ 2026-10-08 修（用户报"点推荐视频返回后不续播"✗ · 已核实的根因之一）：
    //   `open` **一律按 `play: true` 起播** ✓ ⇒ 打开新源这一刻，"用户意图"就是**在播** ✅，
    //   所以必须把 `_userPaused` 复位 ✗ —— 否则它会被上游那次**内部** pause 污染 ☠：
    //   换片（`didUpdateWidget`）/ 换档（`switchSources`）都**先**调过一次 `pause()`
    //   （本意只是"旧源先停住、别和新源抢声音"✓），那一下会把 `_userPaused` 置成 true ✗，
    //   于是详情页后来读到的是"用户**主动**暂停过" ✗ ⇒ 跳走不记续播 ⇒ 回来不播 ☠。
    _userPaused = false;
    return _p.open(Media(url, httpHeaders: httpHeaders), play: true);
  }

  /// ⚠️ **选择性**给某个实例设 libmpv 属性 ✓（目前只有短片页用 ✓：调"起播更快"的参数 ✓）。
  /// **不是**共用配置 ✗ —— 别处不调它就完全不受影响 ✓。
  /// **失败静默** ✗：属性名在 mpv 版本间有差异 ✓，设不上（或这一版不认 ✓）也绝不能影响播放 ✗。
  /// ⚠️ 起播参数总开关（用户 2026-10-03 拍板 #5 ✓）：**默认开** ✓ ——
  /// 真机若发现某站起播反而变卡 ✗，把这里改成 `false` 即可**一键关掉** ✗
  /// （短片页与详情页**共用这一处** ✓，不散落 ✗）。
  static const bool tuneStartup = true;

  /// **起播参数**（2026-10-03 用户拍板 #5：详情页也套上 ✓）——⚠️ **只对"传进来的这个实例"生效** ✗，
  /// **绝不碰本文件的共用配置** ✓（别处不调它 → 完全不受影响 ✓）。
  /// 设什么、为什么（都只碰"**起播门槛**" ✓，**没动**解码/硬解/网络层 ✗）：
  /// - `demuxer-lavf-analyzeduration` = **2.0** ✓（ffmpeg 探测"这是什么流"的最长时间，默认 5 秒 ✗ → 少等）；
  /// - `demuxer-lavf-probesize` = **1500000** ✓（探测用字节数，默认 5000000 ✗ → 少等）；
  /// - `cache-pause-initial` = **no** ✓（别等缓存填满才开播 ✓；mpv 默认本就是 no ✓，这里显式钉住 ✓）。
  /// ⚠️ 三个值都是**保守的中间值** ✗（不为快把探测量砍到极限 ✗）；
  /// ⚠️ 逐条 try/catch ✓：某个名字在这版 libmpv 上不认也**绝不影响播放** ✗（静默忽略 ✓）。
  static void tuneStartupQuiet(KpPlayer kp) {
    if (!tuneStartup) return;
    try {
      kp.setMpvOptionQuiet('demuxer-lavf-analyzeduration', '2.0');
      kp.setMpvOptionQuiet('demuxer-lavf-probesize', '1500000');
      kp.setMpvOptionQuiet('cache-pause-initial', 'no');
      // **硬件解码方式**（用户 2026-10-05 拍板：设置 → 播放 三选一 ✓ **影响所有站点** ✓）——
      //   0 自动 = **不设 `hwdec`** ✓（保持上游默认 ✓ 手册："Hardware decoding is **not enabled by default**" ✓）；
      //   1 硬解 = `hwdec=auto` ✓（手册："If hardware decoding is not possible, mpv **will fall back on software
      //     decoding**" ✓ 正是"安全档" ✓；⚠️ 手册这一版的值列表里**没有 `auto-safe`** ✗ ⇒ 不猜、不用 ✓）；
      //   2 软解 = `hwdec=no` ✓。
      //   ⚠️ 键名 `hwdec` ✓；所有调用点都在 `open()` **之前** ✓（mpv 只在打开流时读它 ✓）。
      final hw = AppSettings.i.hwdec;
      if (hw == 1) {
        kp.setMpvOptionQuiet('hwdec', 'auto');
      } else if (hw == 2) {
        kp.setMpvOptionQuiet('hwdec', 'no');
      }
      // ★【常驻诊断·③】我们**下发**的硬解档（0=不下发 ✓ 保持上游默认 ⇒ 与设置页那三档配对看 ✓；只看不改 ☠）
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 硬解下发=${hw == 0 ? '不设(上游默认)' : (hw == 1 ? 'hwdec=auto' : 'hwdec=no')}');
    } catch (_) {}
  }

  void setMpvOptionQuiet(String name, String value) {
    try {
      final plat = _p.platform; // media_kit 的 `Player.platform` ✓（iOS 上是 NativePlayer ✓）
      if (plat is NativePlayer) {
        plat.setProperty(name, value).catchError((Object _) {});
        // ★【常驻诊断·③】实际**生效**的通道 = 只有 `NativePlayer` 时才会下发 ✓（是原生 ✓）
        if (AppSettings.i.logConsole && name == 'hwdec') debugPrint('[PLAY] 硬解生效通道=NativePlayer setProperty("hwdec","$value") ✓');
      } else if (AppSettings.i.logConsole && name == 'hwdec') {
        // ⚠️ 如实报：平台不是 `NativePlayer`（如 Web/Stub）⇒ **这一档下发不出去** ✗（不改逻辑，只留痕 ✓）
        if (AppSettings.i.logConsole) debugPrint('[PLAY] 硬解生效通道=非 NativePlayer（${plat.runtimeType}）⇒ 未下发 ✗');
      }
    } catch (_) {}
  }

  /// 用户是不是**主动**暂停了（看门狗据此排除"暂停"、只判"卡住" ✓）。
  /// ⚠️ 由**本类自己的** [play]/[pause] 维护 ✓ —— 看门狗（本类构造函数里那个 `_stallTimer`）
  /// 读的就是它 ✓（同一个类，别搬到别处 ✗）。
  bool _userPaused = false;

  /// ★ 2026-10-08（用户报"点推荐视频跳转、返回原详情页，视频不自动续播"✗ · **已核实的根因**）：
  ///   **"用户意图是不是在播"** —— 详情页 RouteAware 判"跳走这一刻该不该记一笔'回来续播'"
  ///   **必须**读它 ✅。
  ///   ⚠️ **绝不能**改用引擎的 `value.playing` ☠ —— 那是**引擎状态**、不是用户意图：
  ///   · 本文件看门狗那段已写明：**mpv 在缓冲期就会把 `playing` 报成 false** ✓；
  ///   · 页面被压到栈下面之后，引擎自己停下来（或音频被新页面抢走 ✓）同样会让它变 false ✓。
  ///   拿它当判据 ⇒ "用户明明在看"被判成"没在播" ✗ ⇒ `_pausedByPush` 不置位 ⇒
  ///   返回时按 ⑦ 红线判定"这不是我们停的" ⇒ **不续播** ☠（用户实报的现象 ✓）。
  ///   ⚠️ 语义边界：只有**用户自己**按过暂停（控制条按钮 / 双击中间 / 全屏里的播放键 ✓）
  ///   才为 true ✅ —— 流程内部的 pause（换片、换档）已由 [open] 复位 ✅。
  bool get userPaused => _userPaused;

  /// ★ 2026-10-08（用户拍板 ⑦ 配套 ✅）：**"全屏路由是不是本实例推上去的"** ——
  ///   全屏页也是 `Navigator.push` 上去的路由 ✅ ⇒ 详情页**必然**收到 `didPushNext` ☑️。
  ///   详情页据此区分"进全屏"（**不是跳走**：要继续播 ✅、要继续写播放记录 ✅）
  ///   与"真的跳到别的页"（要暂停 + 停写 ✅）。
  ///   ⚠️ 置位点 = [_openFullscreen] push **之前**；复位点 = 那次 push 的 `whenComplete`（含异常路径 ✅）。
  bool fullscreenOpen = false;

  /// ★ 2026-10-08（本批修 ✓ · **用户实报 + 日志实锤**）：**按用户意图主动置位 `playing`**。
  ///   依据（日志里可复现，不是推断）：`pause()` 之后控件那侧读到的 `playing` **一直是 true** ——
  ///   连点 4 次暂停，四条日志全是 `当前playing=true` ✓，而 wakelock 早已掉到 0（引擎**确实**停了）✓。
  ///   ⇒ 根因：media_kit 的 `stream.playing` 在暂停/恢复那一刻**不总会更新** ☠。后果三条：
  ///     ① 播放/暂停按钮的**图标不换** ⇒ 看着像"点不动" ✓；
  ///     ② 再点一次仍判"当前在播" ⇒ **又调一次 `pause()`** ⇒ 想播却一直在暂停 ☠；
  ///     ③ 用户只有**滚动页面**（触发重建）才把它"刷出来" ⇒ 表现为「**必须划到上面才能按**」✓。
  ///   ⚠️ 为什么全屏按钮不受影响：它的 `onPressed` **直接调动作、不读状态** ✓ ⇒ 永远有反应 ✓。
  ///   ⇒ 修法：先按用户意图置位（界面立刻响应 ✓）；引擎的流随后到达时会覆盖它（如果它会发 ✓）。
  ///   ⚠️ 不做无谓通知：值没变就不置位 ✓。
  void _syncPlayingFlag(bool v) {
    if (value.playing == v) return;
    // ★【常驻诊断】主动置位也要留痕（"置了没生效/被谁改回去"就看这一对日志 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 主动置位 playing：${value.playing} → $v');
    value = value.copyWith(playing: v);
    kickPlayerFrame(); // ★ 状态变了 ⇒ 踢一帧（防"图标锁死" ✓）
  }

  Future<void> play() {
    // 看：谁在什么时机调了播放（配合"自动重试/看门狗"几条看是不是被反复拉起）。
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 播放');
    _userPaused = false;
    _syncPlayingFlag(true); // ★ 主动置位（见上）—— 按钮图标立刻换、下次点击才会判成"该 pause"
    return _p.play();
  }

  /// ★ 2026-10-08（用户拍板 ② ✅）：**自动路径专用**的续播 —— 与 [play] 的区别**只有一处**：
  ///   **不清 `_userPaused`** ✅（自动路径不许把"用户暂停"这件事抹掉 ✗）；
  ///   且**用户手动暂停过 ⇒ 直接不播**（`_userPaused == true` ⇒ return ✅）。
  /// ⚠️ 目前**唯一**的调用点 = 全屏页 `initState`（就是 ①"跟随进入前的状态" ✅）——
  ///   ☑️ **不是**"自动路径已全部改完"：看门狗 / 自动重试 / 缓冲结束那几条**本来就没有** `play()` 调用
  ///   （全仓 grep 过 ✅），它们的口径**一字未动** ✅。以后新增自动路径才用它 ✅。
  Future<void> autoResume() async {
    if (_userPaused) return; // 用户暂停过 ⇒ 自动路径**不许**再拉起来 ✅
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 自动续播');
    _syncPlayingFlag(true); // ★ 同上（口径与 play 一致 ✓）
    await _p.play();
  }

  Future<void> pause() {
    // 看：谁在什么时机调了暂停（用户操作还是流程自己暂停 ⇒ 与"看门狗"对着看）。
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 暂停');
    _userPaused = true;
    _syncPlayingFlag(false); // ★ 主动置位（见上）—— 否则图标不换、再点又判成"在播"⇒ 又 pause() ☠
    return _p.pause();
  }


  /// 播放倍速——长按快进用：按住时 2.0、松手回 1.0
  Future<void> setRate(double r) => _p.setRate(r);

  Future<void> seek(Duration d) {
    final t = _clampDur(d, value.duration);
    // 看：seek 的实际去向（从当前播到的位置 → 裁剪后的目标）—— "跳完从头/跳不动"对这条看。
    if (AppSettings.i.logConsole) debugPrint('[PLAY] seek 从=${value.position.inMilliseconds}ms 到=${t.inMilliseconds}ms');
    return _p.seek(t);
  }

  /// **不按时长裁剪**的 seek。续播/换档专用：那种场景下目标是"上一条源播到的
  /// 位置"，而 `seek()` 会按 `value.duration` 裁剪，万一时长还没报上来
  /// （或报了个半截值）就会被裁小 —— 表现同样是"从头发"。
  Future<void> seekExact(Duration d) {
    // 看：不裁剪的精确 seek（续播/换档用）—— 目标是多少 ms。
    if (AppSettings.i.logConsole) debugPrint('[PLAY] seek(精确) 从=${value.position.inMilliseconds}ms 到=${d.inMilliseconds}ms');
    return _p.seek(d);
  }

  /// ★ 2026-10-08（用户拍板 ⑤ ✅）：**幂等护栏** —— `shutdown()` 会被多处调（`PlayerWidget.dispose` ✅、
  ///   换源收旧实例 ✅、短片页 `dispose` ✅ ……）⇒ 第二次再进来会把 `Player.dispose()` 与
  ///   ChangeNotifier 的 `dispose()` **各跑第二遍** ⇒ 崩 ✗。现在第二次**直接返回** ✅（一行 ✅）。
  bool _disposed = false;

  Future<void> shutdown() async {
    if (_disposed) return;
    _disposed = true;
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
    // ★【常驻诊断】横滑开始（只记起点 ✓ 拖动过程不逐帧打 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 横滑开始 起点=${_dragFrom.inMilliseconds}ms 时长=${swipePlayer.value.duration.inSeconds}s');
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
    // ★【常驻诊断】横滑结束：起点 → 目标 + 实际跳不跳（松手那一下才 seek ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 横滑结束 起=${_dragFrom.inMilliseconds}ms 目标=${_dragTarget.inMilliseconds}ms 位移=${_dragDx.toStringAsFixed(1)}px 需要跳转=${_dragTarget != _dragFrom}');
    if (_dragTarget != _dragFrom) {
      if (AppSettings.i.logConsole) debugPrint('[PLAY] seek 触发源=横滑快进快退 到=${_dragTarget.inMilliseconds}ms');
      swipePlayer.seek(_dragTarget); // 只在这一下跳转（拖动中不动播放器）
    }
    if (swipePreview.value == null) return;
    // A 方案 ✓（2026-10-04 用户拍板）：**扛住预览** ✗ —— 清早了进度条会往回跳一下
    // （依据：`_SeekBar` 的显示值取自 `widget.position` ✓ 见 `:1847`；原 600ms 注释 `:396` 说的就是这件事 ✓）。
    // 改法：**等引擎回报的位置到达 seek 目标附近（±500ms）才清** ✓ —— 引擎每次回报都会更新
    // `swipePlayer.value` ✓，这里以 50ms 跟随它 ✓，命中第一帧即清 ✓（与"监听位置事件"等效 ✓，
    // 且**不在 build 里改 notifier** ✗ —— 那样会 setState-during-build ✗）。
    // 兜底：**600ms** 上限 ✗（用户 2026-10-04 拍板 ✓）—— seek 正常几十 ms 就回报、**提前清** ✓；
    // 600ms 是**慢 seek**（m3u8 / 网络卡）最多扛的上限 ✓。⚠️ "到达目标附近"的 **500ms 阈值不变** ✗
    final target = _dragTarget; // 复用拖拽终点 ✓（就是上面刚 seek 的那个值 ✓ 不新增字段 ✗）
    _swipeHoldTimer?.cancel();
    var waitedMs = 0;
    _swipeHoldTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      waitedMs += 50;
      final near = (swipePlayer.value.position - target).abs() <=
          const Duration(milliseconds: 500);
      if (near || waitedMs >= 600) {
        t.cancel(); // 自适应结束 ✓（到达就立刻清 ✓ / 满 600ms 强制清 ✗）
        if (swipePreview.value != null) swipePreview.value = null;
      }
    });
  }

  void disposeSwipe() {
    _swipeHoldTimer?.cancel();
    swipePreview.dispose();
  }
}

/// ★ 2026-10-08（用户拍板 ③ ✅）：**"当前亮度"全局只留一份** —— 内嵌播放器与全屏页读写**同一个值** ✅
///   （原来是每个 State 各存一份字段 ✗ ⇒ 全屏里调过亮度、退出回内嵌**再一滑会跳回旧值** ✗）。
///   ⚠️ 放**模块级**而不是挂 `KpPlayer`：`bvPrime()` 是在 `didChangeDependencies` / `initState` 里跑的 ☑️，
///   而内嵌那侧那时 `_kp` **还没建好**（`_initPlayerOnce` 里才建 ✅）⇒ 挂播放器会拿到 null ✗。
///   ⚠️ 音量**不动** ✗ —— 它本来就是系统唯一值 ✓（每次拖动开始时后台刷新 ✓ 没问题 ✓）。
///   ⚠️ 系统亮度变化的订阅**保留**（[bvPrime] 里那条 ✅）⇒ 用实体键/控制中心改完，我们的值跟着变 ✅。
double _bvBrightShared = -1;

/// 竖向手势：左半屏上下滑调亮度、右半屏上下滑调音量（内嵌与全屏共用）。
/// 代价：内嵌播放器接管竖向拖动后，在视频区域内上下拖不会再滚动详情页
/// （这正是"在视频上调亮度/音量"的必要代价，详情页其它区域照常滚动）。
mixin _BrightnessVolume<T extends StatefulWidget> on State<T> {
  KpPlayer get gesturePlayer;

  bool _bvBrightness = false; // 本次调的是亮度？
  double _bvDy = 0; // 本次竖向累计位移
  double _bvStart = 0.5; // 本次拖动的起点值（亮度/音量都是 0~1）
  double? _bvShow; // 指示条的值 0~1（null = 不显示）
  Timer? _bvTimer;

  // 系统值缓存（-1 = 还没读到）。拖动开始立刻用缓存当起点，
  // 避免"拖动那一刻才异步去读、第一帧用到旧值"。
  // ★ 亮度 = **全局一份** ✅（读写 [_bvBrightShared] ✓ —— 内嵌与全屏共用 ✓ 见那边的说明 ✓）；
  //   音量仍按 State 各存一份 ☑️（它本来就是系统唯一值 ✓ 不动 ✗）。
  double get _bvBrightVal => _bvBrightShared;
  set _bvBrightVal(double v) => _bvBrightShared = v;
  double _bvVolVal = -1;
  bool _bvPrimed = false;
  StreamSubscription<double>? _bvBrightSub;
  StreamSubscription<double>? _bvVolSub;

  /// 本次拖动是否实际调整过（供全屏判断"要不要当作下滑退出"）

  /// 进入播放器时预热：读一次当前系统亮度/音量做缓存。
  /// 亮度另有变化回调（系统里改了也能跟上）；音量没有回调，改为每次拖动开始时后台刷新。
  Future<void> bvPrime() async {
    if (_bvPrimed) return;
    _bvPrimed = true;
    try {
      _bvBrightVal = await ScreenBrightness().current;
      if (!mounted) return; // B7：await 之后 State 可能已销毁，别再往下挂订阅
      _bvBrightSub = ScreenBrightness()
          .onCurrentBrightnessChanged
          .listen((v) => _bvBrightVal = v);
    } catch (_) {}
    await _bvRefreshVolume();
    if (!mounted) return; // B7：同上（挂音量订阅之前）
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
    // 起点立刻用缓存值（没有缓存才退回默认值），刷新留给下一次拖动
    _bvStart = _bvBrightness
        ? (_bvBrightVal >= 0 ? _bvBrightVal : 0.5)
        : (_bvVolVal >= 0 ? _bvVolVal : 1.0);
    // ★【常驻诊断】竖滑开始：左半=亮度 / 右半=音量 + 起手位置与起点数值（拖动中不逐帧打 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 竖滑开始 ${_bvBrightness ? '亮度(左半)' : '音量(右半)'} dx=${d.localPosition.dx.toStringAsFixed(1)} w=${w.toStringAsFixed(1)} 起点=${_bvStart.toStringAsFixed(2)}');
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
    // ★【常驻诊断】竖滑结束：本次调的是亮度还是音量 + 起点/终点数值（指示条 700ms 后收 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 竖滑结束 ${_bvBrightness ? '亮度(左半)' : '音量(右半)'} 起点=${_bvStart.toStringAsFixed(2)} 终点=${(_bvBrightness ? _bvBrightVal : _bvVolVal).toStringAsFixed(2)} 累计dy=${_bvDy.toStringAsFixed(1)}px');
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

  /// ★ 2026-10-05（用户拍板：起播优化 #1）：**提前建好的引擎**（还没上屏 ✓）。
  ///   为什么：`KpPlayer(...)` + `tuneStartupQuiet` **与 URL 无关** ✓ ⇒ 可以放在"按需取源"（最长 6 秒）**之前** ✓。
  ///   ⚠️ 只提前"构造" ✗ —— **`_attach`（上屏时机）一字不动** ✓ ⇒ 取源期间界面**不会**出现空壳播放器 ✓。
  ///   回收：交接给 `_kp` 后置空 ✓；失败/销毁路径由 [_dropPrebuiltKp] 收掉 ✓。
  ///   ⚠️ 2026-10-05 CI 修复：本字段原来落在 `class KpPlayer` 里 ✗ ⇒ 7 条 `undefined_identifier` ⇒ 挪到本类（使用点全在 `PlayerWidgetState` ✓）。
  KpPlayer? _prebuiltKp;
  late List<String> _sources =
      widget.sources.where((s) => s.isNotEmpty).toList();
  VoidCallback? _pauseHooked; // 挂在 switcher.pauseTick 上的监听（换 widget 时要摘）
  VoidCallback? _resumeHooked; // 挂在 switcher.resumeTick 上的监听（同上，⑦ 新增 ✅）
  String? _error;
  bool _busy = false;
  // 播放出错自动重试：最多 5 次（起播成功后清零；手动点重试也给新额度）
  int _autoRetries = 0;
  bool _autoRetrying = false; // 自动重试进行中（显示提示、暂藏重试按钮）
  Timer? _autoRetryTimer;
  bool _opening = false; // 正在依次尝试各源（期间不排自动重试，交给循环收尾）
  bool _init = false;

  /// ★ 2026-10-05（用户批准 · 内存 · ②c）：**`_initPlayer` 的重入锁** ✅ ——
  ///   多入口（换集 / `_retry` / `_autoRetryTimer` / `_recover`）可**并发**进来（原来没有在途标志 ☑️）⇒ 两个调用都挂在 `await` 上时
  ///   会**各建一个 `KpPlayer`**（见 [_initPlayerOnce] 里那段）⇒ 后到的覆盖 `_prebuiltKp`、
  ///   前一个**既没上屏也没人收** ⇒ native 泄漏（无异常、无日志 ☑️）。
  ///   ⚠️ 只挡「**并发重入**」：并在挂起期间**只记一笔**（[_initPending]）⇒ 跑完补跑一次（最后一次请求赢 ✅）；
  ///   `try/finally` ⇒ 所有 return 都解锁 ✅。
  bool _initRunning = false;
  /// ★ 2026-10-05（lead 复核时补）：挂起期间又来过的初始化请求 ⇒ 当前这次跑完**补跑一次** ✅
  ///   （直接丢弃会让"初始化中点的第 N 集"像没反应 ✗；只记一笔 ⇒ 不会自激 ☠）
  bool _initPending = false;
  /// 正在按需取源（合集/黄果选集）：点击那一刻就亮提示，别等网络回来才弹
  bool _fetchingLazy = false;
  int _curIndex = 0; // 当前已打开的篇内序号（判断是否换片）
  /// 续播位置（从播放记录进来）：首次成功起播后跳一次，之后置空不再用
  late Duration? _restoreTo = widget.initialPosition;
  /// 进度上报节流：每 10 秒一次（用户拍板），离开详情页时详情页再补一次 flush
  Timer? _reportTimer;
  Duration _repPos = Duration.zero;
  bool _errShown = false; // 播放中途出错（用于只在该状态翻转时重建）
  /// 上次"中途卡住 → 刷新源"的时刻（挡连续的卡住信号，10 秒内只恢复一次 ✓）
  int _lastRecoverMs = 0;
  bool _started = false; // 已开始播放（首帧/位置走动后撤掉 poster）
  /// 上一次 `_onTick` 看到的 position ✓（判"位置是不是**又在走**" → 用于"恢复即撤"那条，
  /// 见 `_onTick` 里的说明 ✓）。只做差值，不参与任何判据的门槛 ✓。
  Duration _lastSeenPos = Duration.zero;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  Offset _lastTapPos = Offset.zero; // 双击落点（判断左半/右半）
  IconData? _tapHint; // 双击提示图标（快退/快进/暂停/播放）
  double _tapHintX = 0; // 提示位置：-0.6 左 / 0 中 / 0.6 右
  Timer? _tapHintTimer;
  bool _longPressing = false; // 长按快进中（按住 2 倍速）

  @override
  void initState() {
    super.initState();
    // ★【常驻诊断】播放器 State 建立（同一条视频出现两次 = 内嵌播放器被整个重建过 ⇒ "画面假死"先看这条 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] PlayerWidget.initState 挂载 源=${widget.sources.length}条 poster=${widget.poster.isEmpty ? '无' : '有'} 续播=${widget.initialPosition?.inMilliseconds ?? 0}ms switcher=${widget.switcher != null}');
  }

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
        // ★【常驻诊断】切后台/失活前补报一次进度（"最后 10 秒进度丢了"看这条 ✓）
        if (AppSettings.i.logConsole) debugPrint('[PLAY] 切后台补报进度 state=${state.name} pos=${p.inMilliseconds}ms dur=${_kp?.value.duration.inSeconds ?? 0}s 播完=${_kp?.value.completed ?? false}');
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

  /// switcher 会在 initState 之后才传进来（详情页异步拿数据 ✓）（详情页是异步拿数据建 switcher 的），
  /// 所以每次依赖变化/更新都重新对一遍监听，挂的是同一个回调。
  /// ★ 2026-10-08（用户拍板 ⑦ ✅）：**与 pauseTick 对称的 resumeTick 在**同一处**挂** ——
  ///   详情页回到栈顶（`didPopNext` ✅）时发 `resume` ⇒ 这里调 `play()`：
  ///   ⚠️ 必须是 `play()`（= **用户意图** ✓ 会清 `_userPaused` ✓），**不是** `autoResume()` ✗ ——
  ///   因为这一次暂停本来就是"我们为了跳走而停的"（详情页用 `_pausedByPush` 记着 ✅），不是用户按的 ✅。
  void _syncPauseHook() {
    final tick = widget.switcher?.pauseTick;
    final rtick = widget.switcher?.resumeTick;
    if (tick == _pauseHookedTick && rtick == _resumeHookedTick) return;
    _pauseHookedTick?.removeListener(_pauseHooked!);
    _resumeHookedTick?.removeListener(_resumeHooked!);
    _pauseHookedTick = tick;
    _resumeHookedTick = rtick;
    if (tick != null) {
      // ★【常驻诊断】触发源=RouteAware（详情页被压栈 → switcher.pauseTick）
      _pauseHooked = () {
        if (AppSettings.i.logConsole) debugPrint('[PLAY] 暂停 触发源=RouteAware(详情页 didPushNext → switcher.pauseTick)');
        _kp?.pause();
      };
      tick.addListener(_pauseHooked!);
    } else {
      _pauseHooked = null;
    }
    if (rtick != null) {
      // ★【常驻诊断】触发源=RouteAware（详情页回到栈顶 → switcher.resumeTick）
      _resumeHooked = () {
        if (AppSettings.i.logConsole) debugPrint('[PLAY] 播放 触发源=RouteAware(详情页 didPopNext → switcher.resumeTick)');
        _kp?.play();
      };
      rtick.addListener(_resumeHooked!);
    } else {
      _resumeHooked = null;
    }
  }

  ValueNotifier<int>? _pauseHookedTick;
  ValueNotifier<int>? _resumeHookedTick;

  @override
  void didUpdateWidget(covariant PlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPauseHook();
    // ★【常驻诊断】父级重建：switcher 序号变没变（变了才走下面"换片"那一段 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] didUpdateWidget index=${widget.switcher?.index.value ?? 0} curIndex=$_curIndex 换片=${(widget.switcher?.index.value ?? 0) != _curIndex} 源=${widget.sources.length}条 lazy=${widget.lazyUrl != null}');
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
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 暂停 触发源=换片(didUpdateWidget：篇内序号→$_curIndex，旧源先停住别抢声音)');
      _kp?.pause();
      _fetchingLazy = widget.lazyUrl != null && _sources.isEmpty;
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 换片 ⇒ _initPlayer() 源=${_sources.length}条 需按需取源=$_fetchingLazy');
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
    if (AppSettings.i.logConsole) debugPrint('[PLAY] switchSources 传入=${srcs.length}条 有效=${list.length}条 ${list.isEmpty ? '⇒ 空表，直接返回（不换源）' : '⇒ 换源'}');
    if (list.isEmpty) return;
    _sources = list;
    _nextFired = false;
    _errShown = false;
    _error = null;
    _autoRetryTimer?.cancel();
    _autoRetryTimer = null;
    _autoRetries = 0;
    _autoRetrying = false;
    // ★【常驻诊断·③】换源/换档（用户点清晰度或换集走这里 ✓ 只看不改 ☠）
    if (AppSettings.i.logConsole) {
      debugPrint('[PLAY] 换源 n=${srcs.length} resumeTo=${resumeTo?.inMilliseconds ?? 0}ms '
      '首源host=${Uri.tryParse(srcs.isEmpty ? '' : srcs.first)?.host ?? '?'}');
    }
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 暂停 触发源=换源(switchSources：清晰度/外部换源，旧源先停住)');
    _kp?.pause(); // 换档：先把旧源停住，别和新源抢声音
    _fetchingLazy = false;
    if (resumeTo != null && resumeTo > Duration.zero) _restoreTo = resumeTo;
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 换源 ⇒ _initPlayer() 续播目标=${_restoreTo?.inMilliseconds ?? 0}ms');
    _initPlayer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPauseHook(); // switcher 后到时也对一遍监听 ✓（每次依赖变化 ✓）
    // ★【常驻诊断】依赖变化（首次那条会去建引擎 ⇒ 与 didUpdateWidget 分开看 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] didChangeDependencies 已初始化=$_init（false ⇒ 下面排微任务建引擎）switcher=${widget.switcher != null}');
    if (!_init) {
      _init = true;
      // 切后台/被杀前补报一次播放进度（不注册就收不到生命周期回调）
      WidgetsBinding.instance.addObserver(this);
      bvPrime(); // 预读系统亮度/音量做缓存
      // 微任务里再初始化：_initPlayer 结尾会 setState，不能在本元素 build 期间调用
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 首次依赖 ⇒ 排微任务 _initPlayer');
      Future.microtask(_initPlayer);
    }
  }

  @override
  void dispose() {
    // ★【常驻诊断】播放器 State 销毁（与 initState 配对 ⇒ 判断是不是被整个重建过 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] PlayerWidget.dispose kp=${_kp == null ? '(无)' : identityHashCode(_kp!).toString()} 预建kp=${_prebuiltKp == null ? '(无)' : '有'} busy=$_busy 重试额度=$_autoRetries 在途=$_initRunning');
    _pauseHookedTick?.removeListener(_pauseHooked!);
    _resumeHookedTick?.removeListener(_resumeHooked!); // ★ ⑦：对称地摘掉 resume 监听 ✅
    _hideTimer?.cancel();
    _tapHintTimer?.cancel();
    _autoRetryTimer?.cancel();
    _reportTimer?.cancel(); // 播放记录上报（详情页会在 dispose 时 flush 最后位置）
    WidgetsBinding.instance.removeObserver(this);
    disposeBv();
    disposeSwipe();
    _kp?.shutdown();
    _dropPrebuiltKp(); // ★ 还没上屏的引擎也要收掉 ✓（新增 ✓）
    super.dispose();
  }

  /// 依次尝试各视频源；全失败时刷新时效链接再试一轮。
  /// 注意顺序：先把播放器挂到界面上（画面/声音一有就出），
  /// 再等"就绪"——就绪只用来判断要不要换下一个源，不该拦住显示。
  ///
  /// ★ 2026-10-05（用户批准 · 内存 · ②c）：**重入锁** ✅ —— 说明见 [_initRunning] ✅。
  ///   主体原样搬进 [_initPlayerOnce]（**逐字搬、只改名字** ✅ —— 不是为了套 `try` 把上百行整体缩进 ☑️）。
  Future<void> _initPlayer() async {
    // ★【常驻诊断】初始化入口（多入口：换集/换档/重试/自动重试/恢复 都会到这里 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] _initPlayer 起 在途=$_initRunning 源=${_sources.length}条 index=${widget.switcher?.index.value ?? 0} curIndex=$_curIndex');
    if (_initRunning) {
      // ⚠️ 2026-10-05（lead 复核时补 · 内存 ②c）：**不能直接丢弃** ☠ ——
      //   初始化要几秒（要取源，最长 6 秒），这期间用户点了别集 / 触发了重试 ⇒
      //   丢请求 = 点了像没反应 ✗。改成**记一笔、这次跑完补跑一次** ✅（最后一次请求赢 ✓、
      //   依旧不会有第二个实例并存 ✓）。
      _initPending = true;
      // ★【常驻诊断】重入（初始化还在跑）⇒ 只记一笔、跑完补跑一次 ✓
      if (AppSettings.i.logConsole) debugPrint('[PLAY] _initPlayer 重入(在途) ⇒ 记账待补跑一次');
      return;
    }
    _initRunning = true;
    try {
      await _initPlayerOnce();
    } finally {
      _initRunning = false;
      // ★【常驻诊断】本次初始化收尾（补跑=true ⇒ 下面立刻再跑一次 ✓）
      if (AppSettings.i.logConsole) debugPrint('[PLAY] _initPlayer 结束 补跑=$_initPending');
      if (_initPending) {
        _initPending = false; // 先清再跑 ⇒ 每次挂起最多补跑一次，不会自激 ☠
        unawaited(_initPlayer());
      }
    }
  }

  /// [_initPlayer] 的**主体**（原来就在这个方法名下面 ✅ 逐字搬来、只改了名字 ✅）。
  Future<void> _initPlayerOnce() async {
    // 起播时把「当前篇内序号」对齐到 switcher：续播起点不是第 1 集时（例：第 3 集 ✓），
    // 不对齐的话 didUpdateWidget 会误判成"换片"、把刚打开的源又重开一遍。
    _curIndex = widget.switcher?.index.value ?? 0;
    // ★【常驻诊断】本次初始化的输入（源几条 / 是否要按需取源 / 续播目标 / 重试提示 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] _initPlayerOnce 起 源=${_sources.length}条 lazy=${widget.lazyUrl != null} 续播目标=${_restoreTo?.inMilliseconds ?? 0}ms 当前kp=${_kp == null ? '(无)' : '有'}');
    // ⚠️ 2026-10-05（用户报"提示还在"）：**重开就把"自动重试中"的提示撤掉** ✓
    //    （与 `switchSources` / `didUpdateWidget` 那两处一致 ✓）。原来这里只清 `_error` ✗
    //    → 从"排了重试 → 重开"这条路上来的时候，提示会一直挂到新播放的 position 抬起来为止 ✗。
    //    ⚠️ 只清提示（`_autoRetrying`）✗ **不动** `_autoRetries` 额度 ✓（连续失败仍受 5 次上限约束 ✓）。
    _autoRetrying = false;
    // ★ 2026-10-05（用户拍板：起播优化 #1）：**引擎构造提前**到"按需取源"之前 ✓
    //   —— 构造 + 起播参数都与 URL 无关 ✓ ⇒ 与取源窗口（最长 6 秒 ✓）**重叠** ✓；
    //   ⚠️ 上屏（`_attach`）**仍在取源完成之后** ✓（时机与改前逐字一致 ✓ 不出现空壳播放器 ✓）。
    // ★【常驻诊断】要不要现在建引擎（true ⇒ 下面新建一个"还没上屏"的 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 预建引擎 需要=${_kp == null && _prebuiltKp == null}（缓冲=${AppSettings.i.bufferMb}MB）');
    if (_kp == null && _prebuiltKp == null) {
      _prebuiltKp = KpPlayer(bufferMb: AppSettings.i.bufferMb);
      // ⭐ 详情页/全屏都套起播参数（#5 ✓）——与短片页**同一个实现** ✓（`KpPlayer.tuneStartupQuiet` ✓）
      KpPlayer.tuneStartupQuiet(_prebuiltKp!);
    }
    // 合集类：这一集还没有源 → **按需**去抓它自己的页面（点哪集抓哪集）
    // ★【常驻诊断】这次要不要按需取源（true ⇒ 先亮"正在取视频…"，最长等 6 秒 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 按需取源 需要=${_sources.isEmpty && widget.lazyUrl != null && widget.onFetchSources != null}');
    if (_sources.isEmpty &&
        widget.lazyUrl != null &&
        widget.onFetchSources != null) {
      setState(() {
        _busy = true;
        _fetchingLazy = true; // 立即亮"正在取视频…"（点击那一下就该看到）
        _error = null;
      });
      try {
        // ⚠️ 2026-10-05 修（用户报"正在取视频…永不消失"）✓：这个回调**原来没有超时** ✗ ——
        //    页面那边一旦卡住（网络 / 站点不响应 ✓），`await` 就永不返回 ✗ → `_fetchingLazy` 一直亮 ✗
        //    （提示永不消失 ✗）→ 自动重试**排不上** ✗（重试那两个入口都判它 ✓）。
        //    照 `_recover` 里那一处（本文件 :1246-1249 ✓）补 **6 秒**超时 ✓；超时 = 当次**没取到源** ✓
        //    → `got` 为空 → 走下面**既有**的失败分支 ✓（提示消失 + 错误文案 ✓），不多写一行逻辑 ✓。
        final got = (await widget.onFetchSources!(widget.lazyUrl!).timeout(
              const Duration(seconds: 6),
              onTimeout: () => const <String>[],
            ))
            .where((s) => s.isNotEmpty)
            .toList();
        if (!mounted) return;
        _sources = got;
        // ★【常驻诊断】按需取源结果（0 条 ⇒ 下面直接报"这一集已失效" ✓）
        if (AppSettings.i.logConsole) debugPrint('[PLAY] 按需取源 取到 ${got.length} 条');
      } catch (_) {
        // 下面统一误提示
      }
      if (!mounted) return;
      _fetchingLazy = false; // 源到手（或失败）：提示要么转播放、要么转错误
      if (_sources.isEmpty) {
        // ★【常驻诊断】按需取源拿空（页面卡住/子文章没有视频）⇒ 报"这一集已失效" ✓
        if (AppSettings.i.logConsole) debugPrint('[PLAY] 按需取源 0 条 ⇒ 报"这一集已失效" + 收掉预建引擎');
        setState(() {
          _busy = false;
          _error = '这一集已失效（子文章打不开或没有视频）';
        });
        _notePlaybackError();
        _dropPrebuiltKp(); // ★ 没上屏的引擎要收掉 ✓（本次新增 ✓）
        return;
      }
    }
    if (_sources.isEmpty) {
      // ★【常驻诊断】压根没有源（纯图文页/站点没给源）
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 没有可用源 ⇒ 报"该文章暂无视频" + 收掉预建引擎');
      setState(() => _error = '该文章暂无视频');
      _dropPrebuiltKp(); // ★ 同上 ✓
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    // ★【常驻诊断】已有实例就直接用；没有才拿预建引擎上屏（上屏时机=取源之后 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 交给播放器 已有实例=${_kp != null}（false ⇒ 用预建引擎 _attach 上屏）');
    var kp = _kp;
    if (kp == null) {
      kp = _prebuiltKp!; // ★ 引擎在取源前就建好了 ✓（上面那段 ✓）—— 这里只负责**上屏** ✓
      _prebuiltKp = null; // 交接完成 ⇒ 失败路径不再回收它 ✓
      _attach(kp); // 立刻上屏（**时机与改前一致** ✓）
      setState(() => _busy = false);
    }

    _opening = true; // 源尝试进行中：期间的出错排期让循环收尾统一处理
    try {
      for (var round = 0; round < 2; round++) {
        for (var i = 0; i < _sources.length; i++) {
          // ★【常驻诊断】每条源的尝试都留痕（与 _openAndWait 的 host=/起播= 两条配对 ✓）
          if (AppSettings.i.logConsole) debugPrint('[PLAY] 试源 round=$round i=$i/共${_sources.length}条');
          final ok = await _openAndWait(kp, _sources[i]);
          if (!mounted) return;
          if (ok) {
            // ★【常驻诊断】这条源起播成功（后面若不跳转就直接返回了 ✓）
            if (AppSettings.i.logConsole) debugPrint('[PLAY] 起播成功 i=$i ready=${kp.value.ready} duration=${kp.value.duration.inSeconds}s 续播目标=${_restoreTo?.inMilliseconds ?? 0}ms');
            // 续播：本次起播前记录下来的进度，跳完就置空（换集不再跳）
            final to = _restoreTo;
            _restoreTo = null;
            if (to != null && to > Duration.zero) {
              try {
                // ⚠️ 用 seekExact 而不是 seek：seek 会按 value.duration 裁剪，
                // 万一时长还没报上来就会被裁小（表现就是"从头发"）。
                if (AppSettings.i.logConsole) debugPrint('[PLAY] seekExact 触发源=续播(首个源起播后的跳转) 到=${to.inMilliseconds}ms');
                await kp.seekExact(to);
                // 再校验一次：mpv 偶尔会把早期的 seek 丢掉，没跳过去就补一枪。
                // 3 秒的容差是给"视频刚开始播、位置还在往上走"留的余量。
                await Future<void>.delayed(const Duration(milliseconds: 500));
                if (mounted &&
                    kp.value.duration > Duration.zero &&
                    kp.value.position < to - const Duration(seconds: 3)) {
                  if (AppSettings.i.logConsole) debugPrint('[PLAY] seekExact 触发源=续播补枪(早期 seek 被丢掉) pos=${kp.value.position.inMilliseconds}ms → ${to.inMilliseconds}ms');
                  await kp.seekExact(to);
                }
              } catch (_) {
                // 续播失败不影响播放，从头放就行
              }
            }
            // ★【常驻诊断】起播成功 ⇒ 排 3 秒自动隐藏（控件显隐的"排期者"之一 ✓）
            if (AppSettings.i.logConsole) debugPrint('[PLAY] 控件排期 3 秒后自动隐藏 原因=这条源起播成功');
            _scheduleHide();
            return;
          }
        }
        // 本轮全失败：刷新一次时效链接再来一轮
        // ★【常驻诊断】本轮全失败（true 的兜底 ⇒ 下面刷新时效链接再来一轮 ✓）
        if (AppSettings.i.logConsole) debugPrint('[PLAY] 本轮源全失败 round=$round ⇒ 刷新源兜底=${round == 0 && widget.onRefreshSources != null}');
        if (round == 0 && widget.onRefreshSources != null) {
          try {
            // ⚠️ 2026-10-05 修：这个回调**原来也没有超时** ✗（同一症状：提示永不消失 / 重试排不上 ✓）
            //    → 照 `_recover` 那一处补 **6 秒**超时 ✓；超时当"这次没刷到新源" ✓（`fresh` 为空 ✓）
            //    → 落到下面**既有**的 `break` 与错误收尾 ✓（`_busy = false` + `_error` ✓）。
            final fresh = (await widget.onRefreshSources!().timeout(
                  const Duration(seconds: 6),
                  onTimeout: () => const <String>[],
                ))
                .where((s) => s.isNotEmpty)
                .toList();
            if (fresh.isNotEmpty) {
              if (AppSettings.i.logConsole) debugPrint('[PLAY] 刷新源拿到 ${fresh.length} 条 ⇒ 再试一轮（round 1）');
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
      // ★【常驻诊断】两轮源都失败 ⇒ 报"视频加载失败" + 排自动重试 ✓
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 两轮源全失败 ⇒ error="视频加载失败" + 排自动重试');
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

    final ref = _playReferer(url);
    // ★ 2026-10-05【常驻诊断·播放层】只打 host+path 截 80 ✓ 不打完整 query（query 只记长度 ✓）；开关关着零开销 ✓
    {
      final du = Uri.tryParse(url);
      final dpath = du == null ? url : '${du.scheme}://${du.host}${du.path}';
      final qlen = du?.query.length ?? 0;
      if (AppSettings.i.logConsole) {
        debugPrint('[PLAY] host=${du?.host ?? '?'} path=${dpath.length <= 80 ? dpath : dpath.substring(0, 80)} '
        'qlen=$qlen ref=${ref.length <= 40 ? ref : ref.substring(0, 40)}');
      }
    }
    kp.addListener(listener);
    try {
      await kp.open(url, httpHeaders: {
        'User-Agent': _ua,
        'Referer': ref,
      });
      // ⚠️ 2026-10-05：实测（curl 走代理，Pornhub）**分片**必须要"站点域名"的 Referer ——
      //    站点域 200 / 不带 404 / CDN 自身域 404；而 master、variant 不带也能 200 ✓。
      //    media_kit 虽然把 httpHeaders 设成 mpv 的 `http-header-fields`（native/player/real.dart
      //    的 on_load 钩子 ✓，本机无构建产物、无法在真机验证它是否覆盖分片请求 ✗），
      //    这里再显式设一个 mpv 的 `referrer` 属性兜底（HLS 分片会带上它 ✓）→ 只影响这条源的 header ✓
      kp.setMpvOptionQuiet('referrer', ref);
      final ok = await done.future
          .timeout(const Duration(seconds: 15), onTimeout: () => false);
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 起播=${ok ? 'ok' : 'fail(超时或报错)'} host=${Uri.tryParse(url)?.host ?? '?'}');
      return ok;
    } catch (e) {
      // ★ 截断到 120 字 ✓（先取字符串再判长度 —— 别对字面量 `'$e'` 取子串 ✗ 会越界 ☠）
      final es = '$e';
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 起播失败 ${es.length <= 120 ? es : es.substring(0, 120)}');
      return false;
    } finally {
      kp.removeListener(listener);
    }
  }

  /// ★ 收掉"提前建好但没上屏"的引擎 ✓（失败路径 + dispose 共用 ✓）。
  ///   `shutdown()` 与 [dispose] 里对 `_kp` 用的是**同一个 API** ✓（:905 ✓）⇒ 不存在新机制 ✓。
  void _dropPrebuiltKp() {
    final pb = _prebuiltKp;
    // ★【常驻诊断】丢弃"提前建好但还没上屏"的引擎（失败路径 / dispose 共用 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 丢弃预建引擎 ${pb == null ? '(本来就没有)' : 'kp=${identityHashCode(pb)} ⇒ shutdown()'}');
    _prebuiltKp = null;
    if (pb != null) unawaited(pb.shutdown());
  }

  void _attach(KpPlayer kp) {
    final old = _kp;
    // ★【常驻诊断】上屏换引擎：新 kp 身份 / 旧 kp 身份（旧的非空 ⇒ 下面立刻 shutdown ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] _attach 新kp=${identityHashCode(kp)} vc=${identityHashCode(kp.videoController)} 旧kp=${old == null ? '(无=首次上屏)' : identityHashCode(old).toString()} 旧kp会被shutdown=${old != null} 预建kp=${_prebuiltKp == null ? '(已交接)' : '仍持有'}');
    if (old != null) old.shutdown();
    _kp = kp;
    kp.addListener(_onTick);
    // 播放进度上报（写播放记录）：每 10 秒一次，只在位置真前进了才报
    //（暂停/卡住时报上去没意义；离开详情页由详情页 flush 补最后一次）
    _reportTimer?.cancel();
    _reportTimer = Timer.periodic(const Duration(seconds: 2), (_) {  // ⚠️ 2026-10-03：10 秒改 2 秒 ✓（看门狗 9 秒，必须早于它 ✓）
      final p = _kp?.value.position ?? Duration.zero;
      if ((p - _repPos).abs() < const Duration(seconds: 1)) return;  // ⚠️ 阈值 5 秒 → 1 秒 ✓
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
    // ⚠️ 2026-10-05（用户报"提示还在 + 又重载一遍"）—— **恢复即撤**：
    //    "卡住/重试中"自己恢复了（位置**又在走** ✓）→ 立刻撤掉已排的重试 ✗。
    //    依据：原来只有 `startedEdge`（position 由 0 变正）会撤 ✗ —— 而**中途**卡住时
    //    position 一直 >0 ✓ → 没有那个上升沿 ✓ → 1.2 秒的定时器照跑 ✓ → 把刚恢复的视频
    //    又重载一遍、提示也一直挂着 ✗（就是用户报的那两个现象 ✓）。
    //    ⚠️ 只在**确实有排着的重试**（定时器非空 或 `_autoRetrying` ✓）且**位置在前进**时撤 ✓ ——
    //    正常播放期间一个字段都不碰 ✗（不然"后面再真卡住"的 5 次额度会被无谓清零 ✗）。
    final pos = _kp?.value.position ?? Duration.zero;
    final advanced = pos - _lastSeenPos;
    _lastSeenPos = pos;
    // ★【常驻诊断】恢复即撤（位置又在走 ⇒ 撤掉已排的自动重试；只在真有排期时打 ✓）
    if (AppSettings.i.logConsole && advanced >= const Duration(milliseconds: 100) && (_autoRetryTimer != null || _autoRetrying)) {
      debugPrint('[PLAY] 恢复即撤 位置又在走(+${advanced.inMilliseconds}ms) ⇒ 撤掉已排的自动重试、额度清零');
    }
    if (advanced >= const Duration(milliseconds: 100) &&
        (_autoRetryTimer != null || _autoRetrying)) {
      _autoRetryTimer?.cancel();
      _autoRetryTimer = null;
      _autoRetries = 0;
      if (mounted && _autoRetrying) {
        setState(() => _autoRetrying = false);
      } else {
        _autoRetrying = false;
      }
    }
    // 播完 → 按设置决定是否自动切下一个（每次播放只触发一次）
    if ((_kp?.value.completed ?? false) && !_nextFired) {
      _nextFired = true;
      // ★【常驻诊断】播完 ⇒ 是否自动切下一集（开关 + 有没有下一集 ✓）
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 播完 ⇒ 自动下一集开关=${AppSettings.i.autoNext} 有下一集=${widget.switcher?.hasNext ?? false} ${AppSettings.i.autoNext && (widget.switcher?.hasNext ?? false) ? '→ 切下一集' : '→ 不切'}');
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
    // ★【常驻诊断】双击落点判定：dx + 屏宽 + 区域（左半退 / 中间暂停播放 / 右半进 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 双击(内嵌) dx=${dx.toStringAsFixed(1)} w=${w.toStringAsFixed(1)} 区域=${dx > w * 0.35 && dx < w * 0.65 ? '中间' : (dx < w / 2 ? '左半' : '右半')} 步长=${AppSettings.i.step}s 引擎playing=${kp.value.playing} pos=${kp.value.position.inMilliseconds}ms');
    if (dx > w * 0.35 && dx < w * 0.65) {
      if (kp.value.playing) {
        if (AppSettings.i.logConsole) debugPrint('[PLAY] 暂停 触发源=双击中间(内嵌)');
        kp.pause();
        _flashTapHint(Icons.pause, 0);
      } else {
        if (AppSettings.i.logConsole) debugPrint('[PLAY] 播放 触发源=双击中间(内嵌)');
        kp.play();
        _flashTapHint(Icons.play_arrow, 0);
      }
      return;
    }
    final back = dx < w / 2;
    final secs = AppSettings.i.step;
    if (AppSettings.i.logConsole) debugPrint('[PLAY] seek 触发源=双击${back ? '左半(退)' : '右半(进)'}(内嵌) 从=${kp.value.position.inMilliseconds}ms 步长=${secs}s');
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
    // ★【常驻诊断】用户手动点了"重试"（与自动重试那条分开看 ✓ 触发来源=用户按钮 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 手动重试 触发源=用户点重试按钮 ⇒ 额度清零 + _initPlayer() 原额度=$_autoRetries');
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
    // 🚫 整段加载流程在跑时不排重试 —— 覆盖两处（原来只覆盖后一处 ✗）：
    //   · `_opening` = 正在**依次试各源**（`_initPlayer` 的循环 :866-914 ✓）
    //   · `_fetchingLazy` = 正在**按需取源**（合集/黄果选集，`_initPlayer` 开头那段 :820-838 ✓）
    // ⚠️ 2026-10-05（用户报"又重载一遍"）：只判 `_opening` 时，**取源窗口**里来的 errEdge
    //    会排下一个 1.2 秒重试 ✗ → 和**正在跑的那个 `_initPlayer`** 并发 → 两次加载 ✗。
    //    这两段合起来 = "整段加载流程" ✓；窗口期内的失败由流程自己收尾（`:840-847` / `:917-923` ✓）。
    // ★【常驻诊断】自动重试排期判定（三条早退原因都能看出来 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 自动重试判定 加载流程中=${_opening || _fetchingLazy} 额度=$_autoRetries/5 已排期=${_autoRetryTimer != null} 已播起来过=${_kp?.value.started ?? false}');
    if (_opening || _fetchingLazy) return;
    if (_autoRetries >= 5) {
      // 额度用完：撤掉"自动重试中"提示，把错误提示/重试按钮露出来
      // ★【常驻诊断】不再自动重试：5 次额度用完（错误提示/重试按钮露出来 ✓）
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 不排自动重试 原因=5 次额度用完');
      if (_autoRetrying) setState(() => _autoRetrying = false);
      return;
    }
    // 同一次失败会从两条通道各报一次（引擎 error + 源尝试失败 ✓）→ 排一次就够 ✓
    // ★【常驻诊断】不重复排期判定（已排期=true ⇒ 下面直接 return，这一次不再排 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 重复排期判定 已排期=${_autoRetryTimer != null}');
    if (_autoRetryTimer != null) return;
    _autoRetries++;
    // ⚠️ 2026-10-05：**中途**卡住（已经播起来过）不能拿同一批没刷新的源从 0 重开 ✗ ——
    //    用户实测"播几秒 → 从头再来"就是这么来的 ✓；改走"刷新源 + 原地续播" ✓
    final midStall = _kp?.value.started ?? false;
    setState(() => _autoRetrying = true);
    // ★【常驻诊断·★】自动重试排上（**"经常重新加载"看这一条** ✓ `_autoRetries` = 既有额度字段 ✓ 只看不改 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 准备重试 midStall=$midStall 已用额度=$_autoRetries');
    // ★【常驻诊断】自动重试排期：第几次 / 走哪条路（中途卡住走 _recover 原地续播，起播失败走 _initPlayer 重开 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 自动重试排期 1200ms 第$_autoRetries次/5 路径=${midStall ? '_recover(中途卡住→刷新源原地续播)' : '_initPlayer(起播失败→按旧源重开)'}');
    _autoRetryTimer = Timer(const Duration(milliseconds: 1200), () {
      _autoRetryTimer = null;
      if (!mounted) return;
      // ★【常驻诊断】排期到点（finally/销毁时这句不会出现 ⇒ 能看出"重试没跑成" ✓）
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 自动重试到点 ⇒ ${midStall ? '_recover()' : '_initPlayer()'}');
      if (midStall) {
        _recover();
      } else {
        _initPlayer();
      }
    });
  }

  /// 中途卡住的恢复：**先向页面要一批新源**（新签名 ✓），拿到就原地续播 ✓；
  /// 拿不到才退回既有的"按旧源重开"（_initPlayer ✓ 里面还有刷新一轮的兜底 ✓）。
  Future<void> _recover() async {
    // ★【常驻诊断】中途卡住恢复入口（距上次恢复 <10 秒会直接作废 ⇒ 那条也在这里看出来 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] _recover 起 index=${widget.switcher?.index.value ?? 0} curIndex=$_curIndex 距上次恢复=${DateTime.now().millisecondsSinceEpoch - _lastRecoverMs}ms 位置=${_kp?.value.position.inMilliseconds ?? 0}ms');
    // 用户已经切走（换集/换视频）→ 这次恢复作废，别去掐新视频 ✓
    if ((widget.switcher?.index.value ?? 0) != _curIndex) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastRecoverMs < 10000) return; // 连续卡住信号只恢复一次 ✓
    _lastRecoverMs = nowMs;
    // 记一下"刷新前的播放位置"：刷新这 6 秒里视频可能**自己恢复了** ✓（`_onTick` 的"恢复即撤"
    // 那时已经把重试撤掉了 ✓）→ 那就别再重开 ✗（用户报的"又重载一遍"里也有这一半 ✓）。
    final posBefore = _kp?.value.position ?? Duration.zero;
    final fresh = await (_refreshFromPage()).timeout(
      const Duration(seconds: 6),
      onTimeout: () => const <String>[],
    );
    // ★【常驻诊断】恢复：刷新前位置 + 这次拿到几条新源（只看 ✓ 下面判据一字未动 ☠）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 恢复 刷新前 position=${posBefore.inMilliseconds}ms 拿到新源=${fresh.length} 条');
    if (!mounted) return;
    // ★【常驻诊断】二次校验（切走了 / 别的加载在跑 / 位置自己又走了 ⇒ 三种作废都能看出来 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] _recover 二次校验 已切走=${(widget.switcher?.index.value ?? 0) != _curIndex} 加载在跑=${_opening || _fetchingLazy} posNow=${_kp?.value.position.inMilliseconds ?? 0}ms 刷新前=${posBefore.inMilliseconds}ms');
    if ((widget.switcher?.index.value ?? 0) != _curIndex) return;
    // ① 别的加载已经在跑了（换档/手动重试/流程自身 ✓）→ 让它去，别并发开第二次 ✓
    if (_opening || _fetchingLazy) return;
    // ② 位置**自己在走**了（≥100ms ✓ 与 `_onTick` 同一判据）→ 视频自己好了 ✓ 不重开 ✓
    final posNow = _kp?.value.position ?? Duration.zero;
    if (posNow - posBefore >= const Duration(milliseconds: 100)) return;
    if (fresh.any((s) => s.isNotEmpty)) {
      _sources = fresh.where((s) => s.isNotEmpty).toList();
    }
    // ★【常驻诊断】恢复的结论：原地重开（会走 _initPlayerOnce，用 _restoreTo 跳回原位 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] _recover 结论 ⇒ _restartFromLastPos() 用源=${_sources.length}条');
    _restartFromLastPos();
  }

  /// 重开当前源，并**跳回最后真实播到的位置**（用现成的 `_restoreTo` 机制 ✓ ——
  /// `_initPlayer` 起播后会 seek 到它；取不到位置（<1 秒）就当从头 ✓）
  void _restartFromLastPos() {
    final last = _kp?.lastKnownPosition ?? Duration.zero;
    _restoreTo = last > const Duration(seconds: 1) ? last : null;
    // ★【常驻诊断】重开时打算跳回哪儿（0 = 从头，说明 lastKnown 还没到 1 秒 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 原地重开 lastKnown=${last.inMilliseconds}ms ⇒ 续播目标=${_restoreTo?.inMilliseconds ?? 0}ms');
    _initPlayer();
  }

  /// 向页面要新源（详情页传的是 `_refreshSources` ✓ 会重新抓页面拿新签名 ✓）；
  /// 没传/失败/拿空 → 返回空表（调用方退回旧源重开 ✓）
  Future<List<String>> _refreshFromPage() async {
    final f = widget.onRefreshSources;
    if (f == null) return const <String>[];
    try {
      return await f();
    } catch (_) {
      return const <String>[];
    }
  }

  /// 控制条显示数秒后自动隐藏
  void _scheduleHide() {
    _hideTimer?.cancel();
    // ★【常驻诊断】控件隐藏排期（"谁排的"看调用点那条 ✓ 这里只记 3 秒计时器已起 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 控件排期 3 秒后自动隐藏(内嵌) 当前可见=$_controlsVisible');
    _hideTimer = Timer(const Duration(seconds: 3), () {
      // ★【常驻诊断】原因=3 秒计时到
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 控件隐藏 原因=3 秒计时到(内嵌)');
      if (mounted) setState(() => _controlsVisible = false);
      kickPlayerFrame(); // ★ 状态变了 ⇒ 踢一帧（防"假死" ✓）
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    kickPlayerFrame(); // ★ 状态变了 ⇒ 踢一帧（防"假死" ✓）
    // ★【常驻诊断】原因=单击切换（切换后的可见性一并打出来 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 控件${_controlsVisible ? '显示' : '隐藏'} 原因=单击切换(内嵌) 切换后可见=$_controlsVisible');
    if (_controlsVisible) _scheduleHide();
  }

  /// ★ 2026-10-08（用户拍板 ✅）：**"先按住、别藏"** —— 取消自动隐藏计时器并让控件可见，
  ///   **但不再重新起那 3 秒** ☑️（详情页被压到栈下面时用它 ✅ —— 那时看不见播放器，可 3 秒计时器
  ///   照样在跑 ✗ ⇒ 等回到详情页控件早藏没了 ✗ 用户以为"控件消失了"✗）。
  ///   ⚠️ 本方法**不参与任何手势** ✅：单击/双击/拖拽/长按与 [_toggleControls] 一个字不动 ✅。
  void holdControls() {
    // ★【常驻诊断】原因=holdControls（详情页被压栈 ⇒ 先按住别藏、**不**重起 3 秒 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 控件显示+按住 原因=holdControls(内嵌) 原可见=$_controlsVisible');
    _hideTimer?.cancel();
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    kickPlayerFrame(); // ★ 状态变了 ⇒ 踢一帧（防"假死" ✓）
  }

  /// ★ 2026-10-08（用户拍板 ✅）：**"显示 + 重新起 3 秒"** —— 回到栈顶（用户又看得见它了）时用 ✅。
  ///   与 [holdControls] **语义分开** ☑️：那个 = 按住不藏（不计时 ✗）；这个 = 显示并恢复老的自动隐藏 ✓。
  void showControls() {
    // ★【常驻诊断】原因=showControls（回到栈顶 ⇒ 显示 + 重新起 3 秒 ✓ 与 holdControls 不同 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 控件显示+重起3秒 原因=showControls(内嵌) 原可见=$_controlsVisible');
    _hideTimer?.cancel();
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    kickPlayerFrame(); // ★ 状态变了 ⇒ 踢一帧（防"假死" ✓）
    _scheduleHide();
  }

  void _openFullscreen({required bool vertical}) {
    final kp = _kp;
    if (kp == null) return;
    // ★ 2026-10-08（用户拍板 ⑦ 配套 ✅）：**进全屏不算"跳走"** —— 全屏页也是 push 上去的路由 ☑️
    //   ⇒ 详情页必然会收到 `didPushNext`，得让它区分得出"这次是全屏"（要继续播 ✅、继续写记录 ✅），
    //   否则它会暂停 + 停写播放记录 ✗（与 ①"在播时进全屏不断播"正面冲突 ✗）。
    //   ⚠️ 置位点 = 这里（push **之前** ✅）；复位点**两条都要有**（绝不留"永远为 true" ☠ ——
    //   那会让以后**所有**跳走都不停 ✗，是最糟的回归）：
    //     ① 路由 future 完成 ⇒ `whenComplete`（正常退出：返回手势/返回键/播完自动退 ✅；future 带错 ✅）
    //     ② `push` **同步抛**（极少见 ☑️ 例如 navigator 被锁）⇒ catch 里立刻复位 ✅ 再原样上抛 ✅。
    kp.fullscreenOpen = true;
    // ★【常驻诊断】进全屏：标记置位（push 之前 ✓ 详情页 didPushNext 靠它区分"全屏"与"跳走" ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 全屏 进 vertical=$vertical fullscreenOpen=true 引擎playing=${kp.value.playing} 用户暂停=${kp.userPaused}');
    Future<dynamic>? fut;
    try {
      // 进出全屏用快速淡入淡出：默认系统侧滑转场对全屏视频违和（用户实报"过渡难看"）
      fut = Navigator.of(context).push(
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
    } catch (_) {
      // ★【常驻诊断】push 同步抛（极少见：navigator 被锁）⇒ 立刻复位、原样上抛 ✓
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 全屏 push 同步抛异常 ⇒ fullscreenOpen 立刻复位 false 并 rethrow');
      kp.fullscreenOpen = false; // ☠ 第二条复位路径（否则标记会永远挂着）
      rethrow;
    }
    // 此处 fut 必非空：push 同步抛的路径已在上面 catch 里 rethrow ✅（故不用 ?.）
    // ★【常驻诊断】转场 future 已挂 whenComplete：退出（返回手势/返回键/播完自动退）时把 fullscreenOpen 复位 ✓
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 全屏 已挂 whenComplete（退出那一刻复位 fullscreenOpen）');
    fut.whenComplete(() {
      // ★【常驻诊断】复位**前**的值 + 引擎是否已 shutdown（赋值语句本身一个字符未动 ✓）
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 全屏 退出：whenComplete 复位前 fullscreenOpen=${kp.fullscreenOpen} 引擎已shutdown=${kp._disposed}');
      kp.fullscreenOpen = false;
      // ★【常驻诊断】复位**后**的值（应与上面那条配对看 ✓）
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 全屏 退出：whenComplete 复位后 fullscreenOpen=${kp.fullscreenOpen}');
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 必须调用
    final kp = _kp;
    // ★【常驻诊断·关键】视频层重建可见性：kp 身份 / 渲染上下文(vc) 身份 —— 身份不变 = 只是重建、没换引擎；
    //   身份变了 = 换了引擎（画面会重新附上下文 ⇒ "画面定格/不刷新"先对比这两行 ✓）
    //   ⚠️ 末尾那个 `_bvShow == null` 是**日志自己的**过滤（不是改既有条件）：上下滑亮度/音量时本 State 每帧 setState
    //      （`bvUpdate → _bvGauge`）⇒ 不过滤就是逐帧刷屏（违反"不做逐帧日志"）；其余重建一条不漏 ✓
    if (AppSettings.i.logConsole && _bvShow == null) {
      debugPrint('[PLAY] 视频层重建(内嵌) kp=${kp == null ? '(无=显示封面区)' : identityHashCode(kp).toString()} vc=${kp == null ? '-' : identityHashCode(kp.videoController).toString()} playing=${kp?.value.playing ?? false} buffering=${kp?.value.buffering ?? false} completed=${kp?.value.completed ?? false} pos=${kp?.value.position.inMilliseconds ?? 0}ms 首帧到=$_started 控件可见=$_controlsVisible poster=${widget.poster.isEmpty ? '无' : '有'}');
    }
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
                      // ★【常驻诊断】长按开始 = 2 倍速（触发源=长按 ✓）
                      if (AppSettings.i.logConsole) debugPrint('[PLAY] 长按开始 触发源=长按(内嵌) ⇒ setRate(2.0) 位置=${_kp?.value.position.inMilliseconds ?? 0}ms');
                      _kp?.setRate(2.0);
                      setState(() => _longPressing = true);
                    },
                    onLongPressEnd: (_) {
                      // ★【常驻诊断】长按结束 = 还原 1 倍速
                      if (AppSettings.i.logConsole) debugPrint('[PLAY] 长按结束 触发源=松手(内嵌) ⇒ setRate(1.0) 位置=${_kp?.value.position.inMilliseconds ?? 0}ms');
                      _kp?.setRate(1.0);
                      if (_longPressing) setState(() => _longPressing = false);
                    },
                    onLongPressCancel: () {
                      // ★【常驻诊断】长按被取消（手势被抢）⇒ 同样还原 1 倍速
                      if (AppSettings.i.logConsole) debugPrint('[PLAY] 长按取消 触发源=手势取消(内嵌) ⇒ setRate(1.0)');
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
                          color: Colors.black.withValues(alpha: 0.6),
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
                                Colors.black.withValues(alpha: 0.6),
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
          color: Colors.black.withValues(alpha: 0.6),
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
          color: Colors.black.withValues(alpha: 0.6),
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
      // ★【常驻诊断】按下那一刻的**坐标 + 是否禁用态** —— "控件按不动"要能分清
      //   「手指根本没落在按钮上」还是「点到了、回调却没跑」✓（坐标能和屏幕位置对上 ✓）。
      //   ⚠️ `onTapDown` 在 `onTap == null`（禁用）时**照样触发** ✓ ⇒ 禁用态也会留痕 ✓。
      onTapDown: (d) {
        if (AppSettings.i.logConsole) {
          debugPrint('[PLAY] 控件按钮按下 icon=${icon.codePoint} at=${d.globalPosition.dx.toStringAsFixed(0)},'
              '${d.globalPosition.dy.toStringAsFixed(0)} enabled=$enabled');
        }
      },
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
                        onPressed: () {
                          // ★【常驻诊断】触发源=用户按钮（控制条）；目标 index 拿不到（本组件只有 hasPrev/onPrev ✓）——
                          //   切完的新 index 由 `didUpdateWidget` 那条 `index=`/`换片=` 打 ✓
                          if (AppSettings.i.logConsole) debugPrint('[PLAY] 上一集 触发源=用户按钮(控制条) hasPrev=${widget.hasPrev} 动作=prev() 全屏控件=${!widget.showFullscreen}');
                          widget.onPrev?.call();
                        },
                      ),
                    _barBtn(
                      icon: s.playing ? Icons.pause : Icons.play_arrow,
                      onPressed: () {
                        // ★ 2026-10-08（本批修 ✓ · 日志实锤）：**动作改为点击时实时读** ——
                        //   原来读闭包捕获的 `s.playing`（= 界面上次 build 时的快照）☠ ——
                        //   真机实锤：控件条整段没重建的 11 秒里，连点 10+ 次**全部**读到旧的 true ⇒
                        //   点「播放」它一直发 `pause()`，直到双击（手势是点击时实时读）才恢复 ✓。
                        //   ⇒ 现在**动作**不依赖界面刷新：点的那一刻实时读引擎当前值 ✓（图标仍按 `s` 画 ✓）。
                        final live = widget.player.value.playing;
                        if (AppSettings.i.logConsole) {
                          debugPrint('[PLAY] ${live ? '暂停' : '播放'} 触发源=用户按钮(控制条) 快照playing=${s.playing} 实时playing=$live 动作=${live ? 'pause()' : 'play()'} 全屏控件=${!widget.showFullscreen}');
                        }
                        live ? widget.player.pause() : widget.player.play();
                      },
                    ),
                    // 下一集：篇内没有下一个视频时置灰禁用
                    _barBtn(
                      icon: Icons.skip_next,
                      enabled: widget.hasNext,
                      onPressed: () {
                        // ★【常驻诊断】触发源=用户按钮（控制条）；hasNext=false 时 _barBtn 里已禁用、点不动 ✓
                        if (AppSettings.i.logConsole) debugPrint('[PLAY] 下一集 触发源=用户按钮(控制条) hasNext=${widget.hasNext} 动作=next() 全屏控件=${!widget.showFullscreen}');
                        widget.onNext?.call();
                      },
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
    // ★【常驻诊断】进全屏那一刻的状态（"跟随进入前状态"看这条 ✓ 用户暂停过就不会被拉起来 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 全屏 initState vertical=${widget.vertical} 用户暂停=${widget.player.userPaused} 引擎playing=${widget.player.value.playing} fullscreenOpen=${widget.player.fullscreenOpen} 有下一集=${widget.switcher?.hasNext ?? false}');
    // ★【常驻诊断】下一步就走 autoResume（用户暂停过 ⇒ 它内部直接 return，日志里就不会出现"自动续播"那条 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 全屏 initState ⇒ autoResume() 触发源=进全屏');
    // ★ 2026-10-08（用户拍板 ① + ② ✅）：**跟随进入前的状态** ——
    //   在播 ⇒ 继续播（不断播 ✅）；进入前是暂停 ⇒ `autoResume()` 内部直接 return ⇒ **保持暂停** ☑️。
    //   原来是**无条件** `play()` ✗ ⇒ 暂停着进全屏也被拉起来 ✗（而且它还会清掉 `_userPaused` ✗）。
    widget.player.autoResume();
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
    // ★【常驻诊断】全屏路由转场状态（reverse=开始退场 ⇒ 立刻恢复竖屏，与退场动画并行 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 全屏 转场状态=$s（reverse ⇒ 提前恢复竖屏）');
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
    // ★【常驻诊断】恢复竖屏（退出路径都调它：返回键/边缘滑/播完自动退/退场动画/dispose 兜底 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 全屏 恢复竖屏（锁 portraitUp）');
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    // ★【常驻诊断】全屏页销毁（此刻 fullscreenOpen 仍为 true：复位在路由 future 的 whenComplete ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 全屏 dispose 引擎playing=${widget.player.value.playing} fullscreenOpen=${widget.player.fullscreenOpen} 用户暂停=${widget.player.userPaused}');
    _hideTimer?.cancel();
    _tapHintTimer?.cancel();
    disposeBv();
    // ★ 2026-10-08（用户拍板 ③ ✅）：原来这里有一句 `ScreenBrightness().resetScreenBrightness()` ✗ ——
    //   **删掉** ☑️。用户明确：**App 内不还原**（全屏里调好的亮度要留着 ✅ —— 详情页与全屏现在是
    //   同一份值 ✅，退出全屏再一滑不会跳回旧值 ✅）；**退出 App 的还原交给系统** ✅（不是我们的活 ✗）。
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
        // ★【常驻诊断】播完那一刻：有下一集就等自动下一集，没有就自己退全屏 ✓
        if (AppSettings.i.logConsole) debugPrint('[PLAY] 全屏 播完 有下一集=${widget.switcher?.hasNext ?? false} ${(widget.switcher?.hasNext ?? false) ? '⇒ 等自动切下一集' : '⇒ 恢复竖屏并自动退出全屏'}');
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
    // ★【常驻诊断】双击落点判定(全屏)：dx + 屏宽 + 区域（左半退 / 中间暂停播放 / 右半进 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 双击(全屏) dx=${dx.toStringAsFixed(1)} w=${w.toStringAsFixed(1)} 区域=${dx > w * 0.35 && dx < w * 0.65 ? '中间' : (dx < w / 2 ? '左半' : '右半')} 步长=${AppSettings.i.step}s 引擎playing=${widget.player.value.playing} pos=${widget.player.value.position.inMilliseconds}ms');
    if (dx > w * 0.35 && dx < w * 0.65) {
      if (widget.player.value.playing) {
        if (AppSettings.i.logConsole) debugPrint('[PLAY] 暂停 触发源=双击中间(全屏)');
        widget.player.pause();
        _flashTapHint(Icons.pause, 0);
      } else {
        if (AppSettings.i.logConsole) debugPrint('[PLAY] 播放 触发源=双击中间(全屏)');
        widget.player.play();
        _flashTapHint(Icons.play_arrow, 0);
      }
      return;
    }
    final back = dx < w / 2;
    final secs = AppSettings.i.step;
    if (AppSettings.i.logConsole) debugPrint('[PLAY] seek 触发源=双击${back ? '左半(退)' : '右半(进)'}(全屏) 从=${widget.player.value.position.inMilliseconds}ms 步长=${secs}s');
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
    // ★【常驻诊断】控件隐藏排期（全屏）：3 秒计时器已起（谁排的看调用点那条 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 控件排期 3 秒后自动隐藏(全屏) 当前可见=$_controls');
    _hideTimer = Timer(const Duration(seconds: 3), () {
      // ★【常驻诊断】原因=3 秒计时到（全屏）
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 控件隐藏 原因=3 秒计时到(全屏)');
      if (mounted) setState(() => _controls = false);
      kickPlayerFrame(); // ★ 状态变了 ⇒ 踢一帧（防"假死" ✓）
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    kickPlayerFrame(); // ★ 状态变了 ⇒ 踢一帧（防"假死" ✓）
    // ★【常驻诊断】原因=单击切换（全屏）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 控件${_controls ? '显示' : '隐藏'} 原因=单击切换(全屏) 切换后可见=$_controls');
    if (_controls) _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final kp = widget.player;
    // ★【常驻诊断·关键】视频层重建可见性(全屏)：与内嵌那条同一个 kp/vc 身份 ⇒ 只是重建、没换引擎 ✓
    //   （`_bvShow == null` 是日志自己的过滤：上下滑亮度/音量时每帧 setState，会逐帧刷屏 ✓ 见内嵌那段说明）
    if (AppSettings.i.logConsole && _bvShow == null) {
      debugPrint('[PLAY] 视频层重建(全屏) kp=${identityHashCode(kp).toString()} vc=${identityHashCode(kp.videoController).toString()} playing=${kp.value.playing} buffering=${kp.value.buffering} completed=${kp.value.completed} pos=${kp.value.position.inMilliseconds}ms 首帧到=${kp.value.started} 控件可见=$_controls vertical=${widget.vertical}');
    }
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
          // ★【常驻诊断】全屏横滑起手：边缘带内=返回手势，否则=快进快退 ✓
          if (AppSettings.i.logConsole) debugPrint('[PLAY] 全屏 横滑起手 x=${_hDownX.toStringAsFixed(1)} 边缘带=${_kEdgeWidth.toString()} ⇒ ${_edgeSwipe ? '返回手势（不进入快进快退）' : '快进快退'}');
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
            // ★【常驻诊断】边缘滑返回判定：速度/位移 vs 阈值（不触发=只是回弹 ✓）
            if (AppSettings.i.logConsole) debugPrint('[PLAY] 全屏 边缘滑返回判定 v=${(d.primaryVelocity ?? 0).toStringAsFixed(0)} 位移dx=${_edgeDx.toStringAsFixed(1)} 阈值=${(w * 0.28).toStringAsFixed(1)} 触发=${(d.primaryVelocity ?? 0) > 300 || _edgeDx > w * 0.28}');
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
          // ★【常驻诊断】长按开始 = 2 倍速（触发源=长按 ✓）
          if (AppSettings.i.logConsole) debugPrint('[PLAY] 长按开始 触发源=长按(全屏) ⇒ setRate(2.0) 位置=${widget.player.value.position.inMilliseconds}ms');
          widget.player.setRate(2.0);
          setState(() => _longPressing = true);
        },
        onLongPressEnd: (_) {
          // ★【常驻诊断】长按结束 = 还原 1 倍速
          if (AppSettings.i.logConsole) debugPrint('[PLAY] 长按结束 触发源=松手(全屏) ⇒ setRate(1.0) 位置=${widget.player.value.position.inMilliseconds}ms');
          widget.player.setRate(1.0);
          if (_longPressing) setState(() => _longPressing = false);
        },
        onLongPressCancel: () {
          // ★【常驻诊断】长按被取消（手势被抢）⇒ 同样还原 1 倍速
          if (AppSettings.i.logConsole) debugPrint('[PLAY] 长按取消 触发源=手势取消(全屏) ⇒ setRate(1.0)');
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
                        // ★【常驻诊断】全屏页"返回"按钮 ⇒ 恢复竖屏 + pop
                        if (AppSettings.i.logConsole) debugPrint('[PLAY] 全屏 返回按钮 ⇒ 恢复竖屏 + Navigator.pop');
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
                    color: Colors.black.withValues(alpha: 0.6),
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
    // ★【常驻诊断】进度条松手（触发源=进度条点击/拖动 ✓ 不跟手时不打 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 进度条松手 触发源=进度条点击/拖动 目标=${d?.inMilliseconds ?? 0}ms 需要跳转=${d != null}');
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
