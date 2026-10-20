import 'dart:async';
import 'dart:convert' show utf8; // ★ probe32 A：只读 HLS 清单事实（仅 logConsole 时用）
import 'dart:io' show HttpClient; // ★ probe32 A：只读 HLS 清单事实（仅 logConsole 时用）

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

/// ★ 2026-10-11（用户拍板 A1 ✅）：**硬错误**判据 —— 命中即"这条源不行"，**不等超时**。
///
/// 为什么这几个算"硬"（= 确定性失败，再等 15 秒 `_openAndWait` 也不会有不同结果）：
/// · `403` / `404`：地址被拒 / 不存在（我们的地址都带 `auth_key` 时效签名，过期就是 403/404）
/// · `Forbidden` / `Not Found`：上面两个状态码的**文字形式**（mpv/ffmpeg 有时只给文字）
/// · `Connection refused`：端口关着 / 被拦截
/// · `Could not resolve` / `Name or service not known`：域名解析失败
/// · `No route to host`：网络层不可达
///
/// ⚠️ 偶发类错误（`tcp: ffurl_read returned ...`、`Connection reset by peer` 等）**不在**名单里 ⇒
///    只记录、不判死（那类 ffmpeg 自己会重试；判死会误伤 —— 见 error 流那段的注释 ✅）。
/// ⚠️ 判据**只此一处**：要加/减关键词就改这一行 RegExp，全局生效 ✅。
/// ⚠️ 数字码必须带 `http|status|error|code` 语境（避免把 **URL 里的数字**当状态码 ☠ ——
///    实测地址里就有 `auth_key=1791635503-...` 这种长数字串；用 `\bhttp\b` 而不是 `https?`
///    是为了不让 `https://...` 里的 "http" 混进来 ✅）。
final RegExp _kHardErrorRe = RegExp(
  r'\b(?:http|status|error|code)\b[^0-9]{0,20}(?:403|404)\b'
  r'|\bforbidden\b|\bnot found\b|\bconnection refused\b'
  r'|\bcould not resolve\b|\bname or service not known\b|\bno route to host\b',
  caseSensitive: false,
);

/// 错误文本是否是"硬错误"（判据见 [_kHardErrorRe] 的说明）
bool _isHardError(String text) => text.isNotEmpty && _kHardErrorRe.hasMatch(text);

/// 播放器引擎封装（media_kit / libmpv）。
/// 选它而不是 iOS 原生 AVPlayer：AVPlayer 的缓冲与 seek 容差在 iOS 上无法配置，
/// 长视频/加密 HLS 跳转容易长时间卡加载；libmpv 由 FFmpeg 层面处理 HLS，
/// 且 bufferSize 可调（就是网页播放器那种缓冲控制）。
class KpPlayer extends ValueNotifier<KpState> {
  /// ★ 2026-10-10（**dev 接缝** ✓ 用户拍板：桌面 dev 默认静音）：非空 ⇒ 每个新建的 Player 都按它
  ///   设**初始音量**（0 = 静音 ✓）。桌面 dev 入口在 runApp 之前设 0 ✓。
  ///   ✅ **iOS 零影响**：iOS 侧**没有任何代码**写它 ⇒ 恒为 null ⇒ 下面的 if 永不进入 ⇒
  ///      行为与不写这几行**逐字节相同** ✓。
  ///   ⚠️ 不许改它来动"系统音量"（那是全局的 ✗ 用户明确禁止 ✓）—— 这里动的是**播放器自己**的音量 ✓。
  static double? startupVolumeOverride;

  /// ★ 2026-10-11（用户拍板 A2 ✅）：**自动重试进行中**（0 = 不在重试；>0 = 第几次/共 5 次）。
  ///   为什么挂在引擎上：**全屏页**手里只有这个 `KpPlayer`（它拿不到内嵌那侧的 `_autoRetrying`）——
  ///   全屏那条"播放出错，请返回重试"要**同样让位**给"重连中"角标，就得读同一个值 ✅。
  ///   写入方**只有**内嵌 `PlayerWidgetState`（`_pushRetrying()` 单点 ✅）；
  ///   全屏页**只读**（`ValueListenableBuilder`）✅。
  final ValueNotifier<int> retrying = ValueNotifier<int>(0);

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
    // ★ 2026-10-10（dev 接缝的应用点 ✓）：只在被显式要求时设 ⇒ iOS（null）一字不变 ✓
    final sv = KpPlayer.startupVolumeOverride;
    if (sv != null) unawaited(_p.setVolume(sv));
    _subs = [
      _p.stream.position.listen((v) {
        value = value.copyWith(position: v);
        // ★【常驻诊断】只打**首次** position>0（首帧 ✓）⇒ 防刷屏 ☠；`_everStarted` 是既有字段 ✓ 不改它的用法 ✓
        if (v > Duration.zero && !_everStarted) {
          if (AppSettings.i.logConsole) debugPrint('[PLAY] 首帧 position=${v.inMilliseconds}ms');
          // ★ probe32 A：④ 首帧时刻（只在 logConsole 时记）
          if (AppSettings.i.logConsole) _tFrameMs ??= _nowMs();
          // ★ 2026-10-11（B2 ✅）：记下"位置首次真的推进"的时刻 ⇒ 起播保护期从这一刻算 ✅
          //   （`open()` 会清空它 ⇒ 每条源各自重新拥有保护期 ✓）
          _startedAtMs = DateTime.now().millisecondsSinceEpoch;
	}
        if (v > Duration.zero) _everStarted = true;
      }),
      // ★【常驻诊断·★】时长拿到那一刻（**"总进度只有几秒"就看这一条** ✓ 只打一次 ✓ 不改逻辑 ☠）
      //   ⚠️ 这里**不打 host** ✗：本 State 里没有"当前源 URL"的字段（读不到 ⇒ 不猜 ✓）—— 要 host 得看 `[PLAY] host=` 那条 ✓
      _p.stream.duration.listen((v) {
        if (v > Duration.zero && value.duration <= Duration.zero) {
          if (AppSettings.i.logConsole) debugPrint('[PLAY] 时长=${v.inSeconds}s（首次拿到 ✓）');
          // ★ probe32 A：③ 拿到 duration 的时刻（= ready 判据那一刻；只在 logConsole 时记）
          if (AppSettings.i.logConsole) _tDurMs ??= _nowMs();
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
        // ★ probe32 A：⑤ 首次缓冲结束（true→false）
        if (!v && AppSettings.i.logConsole) _tBufEndMs ??= _nowMs();
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
      // ★ 2026-10-11（用户拍板 A1 ✅）：**报错只记录，不判死** ——
      //   原来那条"首帧前挂待定、宽限 3 秒仍未就绪 ⇒ 判死"的路径**已停用** ✗：
      //   实测站点侧本来就慢（详情页 2.3~4.5s、CDN 密钥 2.2s ⇒ 见本轮网络实测），
      //   3 秒宽限会把"马上就能播"的源误判成坏源 ⇒ 白弹一次重试 ✗。
      //   现在判死**只由超时类判据**触发 ✅：
      //     · `_openAndWait` 的单源 15 秒（:1535）· 首帧 6 秒（:451）· 卡住 9 秒（:440）
      //     · 外加下面这条"**硬错误早判**"（确定性失败，早判只是省时间 ✅）。
      _p.stream.error.listen((e) {
        // ★ 截断到 120 字 ✓（先取字符串再判长度 —— 别对字面量取子串 ✗ 会越界 ☠）
        final es = e;
        if (AppSettings.i.logConsole) debugPrint('[PLAY] 错误流 首帧前=$_everStarted ${es.length <= 120 ? es : es.substring(0, 120)}');
        _lastFatal = e;
        // ★ A1：**硬错误早判** —— 命中即判死、不等 15 秒超时 ✅
        //   ⚠️ 只在 `!_everStarted`（还没起来）时早判 ☠：播放中的 error 流里可能混入**子请求**失败
        //      （某个 variant / 某个分片 404）而视频**还在正常放** ⇒ 那时早判 = 误杀 ✗；
        //      播放中真卡住由下面 9 秒卡住那条（B1/B2 已加豁免与保护期）负责 ✅。
        //      判据本体（关键词表）在文件顶部 `_kHardErrorRe` ✅（只此一处）。
        if (!_everStarted && !value.error && _isHardError(es)) {
          if (AppSettings.i.logConsole) debugPrint('[PLAY] 错误流 命中硬错误 ⇒ 立即判死（不等超时）文本=${es.length <= 80 ? es : es.substring(0, 80)}');
          value = value.copyWith(
            error: true,
            errorText: '打不开（硬错误）：${es.length <= 60 ? es : es.substring(0, 60)}',
          );
        }
      }),
      // 引擎日志只静默留存最后一条 fatal：不再当错误弹提示
      // （网络类日志如 "tcp: ffurl_read returned ..." 是偶发的，ffmpeg 会自己重试，
      //   拿它当错误会误报；只有真的卡住时才把它作为附注带出来）
      _p.stream.log.listen((log) {
        if (log.level == 'fatal') _lastFatal = '${log.prefix}: ${log.text}';
        // ★ probe32 A：② 首个 mpv 事件（日志流第一条；只在 logConsole 时记）
        if (AppSettings.i.logConsole) _tMpvMs ??= _nowMs();
      }),
    ];
    // ★ probe32 A：把**我们下发的全部 mpv 参数**打一行（只读；logConsole 关着时什么都不做）
    _logMpvParams(bufferMb);
    // 卡住看门狗：播放中位置连续 9 秒不前进 → 判为卡住（真卡住才提示）
    _stallTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // ★ probe32 A（只读）：里程碑齐了 / 到点 20s ⇒ 打**一行**分段计时汇总（只一次；不做任何别的事）
      if (AppSettings.i.logConsole && !_tLogged) {
        final done = _tDurMs != null && _tBufEndMs != null;
        final timeout = _tOpenMs != null && _nowMs() - _tOpenMs! > 20000;
        if (done || timeout) {
          _tLogged = true;
          unawaited(_logTiming(done ? '里程碑齐(时长+缓冲止)' : '20s 到点(部分值)')); // async（要读 hwdec-current）
        }
      }
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
      //      ⚠️ 2026-10-11（A1 ✅）：首帧前**唯一**会写 `error` 的只剩"硬错误早判"（:280 ✓，
      //         确定性失败：403/404/连接被拒/解析不了 ✓）与下面这条 6 秒无首帧 —— 3 秒宽限那条已删 ✅。
      if (_userPaused || s.error) {
        _stuckMs = 0;
        _noFrameMs = 0;
        _bufExcuseMs = 0; // 暂停 / 已失败：缓冲豁免额度也复位 ✓
        _lastPos = s.position;
        return;
      }
      if (!_everStarted) {
        // ★ 首帧前：**早判已停用**（A1 ✅）—— 这里只保留"首帧前的长兜底"（超时类判据 ✓）。
        //   ⚠️ 2026-10-11 删掉的那段（`_startupErrPending` + 3 秒宽限 ⇒ 判死）见 git 历史；
        //      现在启动期报错**只记录到 `_lastFatal`**（error 流那段 :271-286 ✓），
        //      判死只能来自：15 秒单源超时（:1535）/ 6 秒无首帧（下面这条）/ 硬错误早判（:280）✅
        // ★ 首帧前的**长兜底**（2026-10-05，用户拍板 ✓）：堵住"`duration` 到了（=`ready` ✓，
        //   `_openAndWait` 已判成功 ✓）但**首帧永远不来**"这个洞（那时 15 秒超时已经用完了 ✗）。
        //   · 判据用 **`ready`（`duration > 0` = 已经 open 成功 ✓）**，**不是**"已连上" ✓
        //     —— 连接阶段归 `_openAndWait` 的 15 秒管 ✓，两条判据不打架 ✓（`!ready` → 清零 ✓）
        //   · 阈值 [_kFirstFrameLimitMs] = **6 秒** ✓（★ 2026-10-14 用户拍板改值；原 12 秒 = 2026-10-05 旧值 ☑️）：
        //     这里**不是**旧 bug 那个 9 秒 ✗ —— 那条是**从播放器构造就算**（连"连接 + 解析清单"
        //     都算进去 ✗ → 正常加载被误判 ✗）；这条**从 open 成功（`ready`）之后才算** ✓，
        //     那时清单已解析 ✓ 只等首帧 ✓，正常 1~3 秒 ✓ → 6 秒仍有 2 倍以上余量 ✓（实测成功首帧 ≤3.8s ✓）
        //     （正常加载绝不会触发 ✓，即"用户报的那个 bug 不许回来" ✓）
        //   · 到点 → 按"这条源不行"处理 ✓：**只写 `error`**，后面走**现成的失败路径** ✓
        //     （`_onTick` 的 errEdge → `_notePlaybackError` → 重开/换源 ✓），不另起状态机 ✓
        //   · **只触发一次** ✓：触发后 `error` 已被置上 → 上面 `s.error` 分支每轮清零 ✓
        //     （error 被撤掉后要再攒满 6 秒才可能再响 ✓；整条链还有 5 次重试上限兜着 ✓）
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
      // ★ 2026-10-11（用户拍板 B2 ✅）：**起播保护期** —— 首次"位置真的推进"之后 10 秒内不判卡住。
      //   为什么：起播那几秒解码/缓存都还没铺开，位置本来就可能一顿一顿（弱网更明显）；
      //   此时判卡住 = 把"刚起播成功的视频"又重载一遍（用户实报的正是这个 ☠）。
      //   ⚠️ 每条源各自重新拥有这 10 秒（`open()` 里会清 `_startedAtMs` ✅）。
      if (_startedAtMs != null &&
          DateTime.now().millisecondsSinceEpoch - _startedAtMs! <
              _kStartupStuckGraceMs) {
        _stuckMs = 0;
        _bufExcuseMs = 0;
        _lastPos = s.position;
        return;
      }
      if ((s.position - _lastPos).abs().inMilliseconds < 500) {
        // ★ 2026-10-11（用户拍板 B1 ✅）：**缓冲豁免（必须带上限）** ——
        //   `s.buffering` 的来源已在 pub cache 里核实：media_kit 1.1.11 的
        //   `lib/src/player/native/player/real.dart:1635-1652`（`core-idle` ⇒ true，带
        //   `isBufferingStateChangeAllowed` 闸）与 `:1654-1660`（`paused-for-cache` ⇒ 直接等于该值）。
        //   ⚠️ 依据同一条核实结论：**真卡死（网断/片源无响应）时它也可能长期 true** ⇒ 不能无限豁免 ☠
        //   ⇒ 单次卡顿里最多豁免 [_kBufferingExcuseMs] = 30 秒，超了照旧按 9 秒判卡住 ✅
        //   （豁免额度在"位置恢复前进"/暂停/换源时复位 ⇒ 下一次卡顿重新拥有 ✅）
        if (s.buffering && _bufExcuseMs < _kBufferingExcuseMs) {
          _bufExcuseMs += 1000;
          _stuckMs = 0; // 缓冲中：不计入卡住累计 ✅
        } else {
          _stuckMs += 1000;
        }
        if (_stuckMs >= _stuckLimitMs) {
          // ★【常驻诊断】看门狗判"卡住"（位置连续不前进 ✓ 含 _userPaused / 位置 / _everStarted ✓）
          //   ⚠️ 日志补 `豁免已用=`：判断"是缓冲超了 30 秒上限被判的"还是"压根没缓冲" ✓
          if (AppSettings.i.logConsole) debugPrint('[PLAY] 看门狗 判卡住(${_stuckLimitMs ~/ 1000}s 未前进) userPaused=$_userPaused everStarted=$_everStarted pos=${s.position.inMilliseconds}ms lastPos=${_lastPos.inMilliseconds}ms playing=${s.playing} buffering=${s.buffering} 豁免已用=${_bufExcuseMs}ms/上限${_kBufferingExcuseMs}ms 引擎日志=${_lastFatal.isEmpty ? '(无)' : (_lastFatal.length <= 80 ? _lastFatal : _lastFatal.substring(0, 80))}');
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
        _bufExcuseMs = 0; // 位置恢复前进 ⇒ 豁免额度复位 ✅
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

  // ★ 2026-10-11（**probe32 A：只读分段计时** —— 用户要让 iPhone 侧日志能定位"6~7 秒花在哪"）：
  //   ⚠️ **只在 `logConsole` 打开时**才记录/打印（生产路径零开销、零行为变化）；**不打地址/cookie**。
  int? _tOpenMs; // ① `open()` 提交时刻（= "--建/--open 提交" 的起点）
  int? _tMpvMs; // ② 首个 mpv 事件（日志流里第一条）
  int? _tDurMs; // ③ 拿到 duration（= 我们的 ready 判据；与"起播成功"同一刻）
  int? _tFrameMs; // ④ 首帧（position 首次 >0；`started`）
  int? _tBufEndMs; // ⑤ 首次缓冲结束（buffering true→false）
  bool _tLogged = false; // 汇总只打一行
  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  /// 逐条列出**我们下发给 mpv 的全部参数**（只读、仅 logConsole）—— 便于判断"是不是预读/探测在拖起播"。
  ///   ⚠️ 除下面这些，media_kit 内部还会自己设（`vo=libmpv`、`http-header-fields`=站点头等）—— 那些**不在我们代码里**。
  void _logMpvParams(int bufferMb) {
    if (!AppSettings.i.logConsole) return;
    final hw = AppSettings.i.hwdec;
    debugPrint('[PLAY] mpv参数 bufferSize=${bufferMb}MB logLevel=error '
        'demuxer-lavf-analyzeduration=2.0 demuxer-lavf-probesize=1500000 '
        'cache-pause-initial=no network-timeout=20 '
        'stream-lavf-o=reconnect=1,reconnect_streamed=1,reconnect_delay_max=5,'
        'reconnect_on_network_error=1,reconnect_on_http_error=5xx '
        'hwdec=${hw == 1 ? 'auto' : (hw == 2 ? 'no' : '(不下发·上游默认)')} '
        'referrer=(每源现设·不进日志) '
        '｜未设：cache/cache-secs/demuxer-readahead-secs/hls-*（保持上游默认）');
  }

  /// 一行汇总（只打一次；里程碑没到齐就在 `_stallTimer` 里到点打部分值 —— 绝不阻塞流程）。
  /// ⚠️ 口径：`时长` = 首次拿到 duration（= ready）；`ready` 与它同刻（不再单独计时）；
  ///   `缓冲止` = 首次 `buffering=false`（起播后往往会立刻 true 一次 ⇒ 看它更贴近"能连续放"）。
  /// ★ 2026-10-11（用户批"补日志并出 1.3.4"）：**同时打出 mpv 当前解码方式**（`hwdec-current`）——
  ///   判"iPhone 上 6~7s 是不是软解在拖"。读法：media_kit 的 `NativePlayer.getProperty`（**已核：存在**，
  ///   见 `media_kit …/native/player/real.dart` 的 `Future<String> getProperty(String)`）；
  ///   拿不到（非 NativePlayer / 超时 / 异常）⇒ 打 `（拿不到）`，**不硬编** ✅。
  Future<String> _mpvProp(String name) async {
    try {
      final plat = _p.platform;
      if (plat is NativePlayer) {
        return await plat.getProperty(name).timeout(const Duration(seconds: 2));
      }
    } catch (_) {}
    return '（拿不到）';
  }

  Future<void> _logTiming(String why) async {
    if (!AppSettings.i.logConsole) return;
    final hw = await _mpvProp('hwdec-current');
    if (!AppSettings.i.logConsole) return; // async ⇒ 用前再判一次（同 `_logHlsFacts` 口径）
    int d(int? t) => (t == null || _tOpenMs == null) ? -1 : t - _tOpenMs!;
    debugPrint('[PLAY] 计时 kp=${identityHashCode(this)} why=$why '
        'open提交=${_tOpenMs == null ? -1 : 0}ms '
        '首事件=${d(_tMpvMs)}ms 时长=${d(_tDurMs)}ms 首帧=${d(_tFrameMs)}ms 缓冲止=${d(_tBufEndMs)}ms '
        'hwdec-current=$hw');
  }

  Duration _lastPos = Duration.zero;
  int _stuckMs = 0;
  /// **首帧前**的长兜底计时（毫秒）：只在"已 open 成功（`ready` ✓）但还没首帧"时累加 ✓。
  /// 与 [_stuckMs] **分开两个计数器** ✗（两条阈值不同：首帧前 6 秒 / 首帧后 9 秒 ✓）。
  int _noFrameMs = 0;
  /// **缓冲豁免已用**（毫秒）：卡住判据里 `buffering == true` 的那部分时间不累计卡住 ✅
  /// （B1 ✅）—— 但**总豁免有上限**（[_kBufferingExcuseMs]）☠：真卡死时 `buffering` 可能长期 true。
  int _bufExcuseMs = 0;
  /// **起播保护期**的起点（毫秒时间戳）：`_everStarted` 首次置位那一刻记下 ✅（B2）
  /// —— 置位后 [_kStartupStuckGraceMs] 内不判卡住（每条源各自重新拥有，`open()` 会清空 ✓）。
  int? _startedAtMs;

  /// 当前这个 error 是不是**看门狗自己判的卡住**（只有它才由看门狗自己撤）。
  /// 起播失败那类 error 不归它管 —— 撤了会把"真失败"静默掉。

  /// 位置连续多久不前进就判为卡住（毫秒）—— **首帧之后**用（保持不变 ✓）
  static const int _stuckLimitMs = 9000;

  /// **首帧前**的长兜底阈值（毫秒）：已 open 成功（`ready` = `duration > 0` ✓）后这么久还没首帧
  /// → 按"这条源不行"处理 ✓（写 `error` → 走现成失败路径 ✓）。**要调就改这一行** ✓。
  /// 为什么 **6 秒**（★ 2026-10-14 用户拍板改值 —— 依据=当日日志两例“ready 后久无首帧”（Win 冷启动 / iPhone 真机）；原 12 秒 = 2026-10-05 旧值 ☑️）：
  ///   · 它与旧 bug 那个 9 秒**不是一回事** ✗ —— 旧的是**从播放器构造就开始算**（把"连接 + 解析清单"
  ///     都算进去了 → 正常加载被误判 ✗）；这条**从 open 成功之后才算** ✓（那时清单已解析 ✓ 只等首帧 ✓）。
  ///   · 清单解析完后正常首帧一般 1~3 秒 ✓ → 12 秒是 4~10 倍余量 ✓；也比 30 秒那版短得多 ✓，
  ///     真卡住能更早换源 ✓（用户：优先保证加载流畅 ✓）。
  ///   · **加载成功的场景不引入任何额外等待** ✗（它只在"真卡住"时才动作 ✓）。
  ///   · 与 `_openAndWait` 的 15 秒连接超时**不重叠** ✓（连接阶段 `!ready` → 这条不计 ✓）。
  static const int _kFirstFrameLimitMs = 6000;

  /// ⚠️ 原 `_kStartupErrHoldMs`（首帧前 3 秒宽限 ⇒ 判死）**已删**（A1 ✅，2026-10-11）：
  ///   启动期报错**只记录不判死**（见 error 流那段），判死只由超时类判据 + 硬错误早判触发。
  /// **缓冲豁免的上限**（毫秒，B1 ✅）：单次卡顿里 `buffering == true` 最多豁免这么久，
  ///   超了照旧按 [_stuckLimitMs] 判卡住 ☠。为什么是 30 秒：
  ///   · 正常 HLS 一次卡顿/重新拉流一般 1~10 秒（实测站点侧单跳 0.3~2.5s）⇒ 30 秒有 3 倍以上余量 ✅
  ///   · 真卡死（网断、片源无响应）时 `buffering` 可能**长期 true** ⇒ 必须有上限，否则永远不判死 ☠
  static const int _kBufferingExcuseMs = 30000;

  /// **起播保护期**（毫秒，B2 ✅）：`_everStarted` 首次置位后的这段时间内不判卡住 ✅
  /// 为什么 10 秒：起播后解码/缓存还没铺开，位置一顿一顿属正常（弱网更明显）；
  ///   实测单源等待上限是 15 秒（`_openAndWait`），10 秒保护期不会拖长"真失败"的判死 ——
  ///   真死源在那之前就被 `_openAndWait` 的 15 秒超时判掉了 ✅
  static const int _kStartupStuckGraceMs = 10000;

  VideoController get videoController => _vc;

  /// 当前播放位置（离开页面时补写播放记录用）
  Duration get position => value.position;

  /// **最后真实前进过**的播放位置。
  /// 用途：换档/换源那一刻取"记到哪儿了"。不能用 `position` —— 换源会把
  /// state 里的 position 重置为 0（见 open()），而这个值只在位置真的前进了
  /// ≥500ms 时才更新，所以它保留的是"上一条源播到的真实进度"。
  Duration get lastKnownPosition => _lastPos;

  /// ★ probe32 A（**只读**）：取到票后顺手看一眼 **m3u8 事实**（≤3 个请求、几 KB）——
  ///   直接量化"分片多大 / 远跳要下多少数据"，用于判断"起播 6~7s"是不是在等清单/首片。
  ///   ⚠️ 只在 `logConsole` 打开时跑；**fire-and-forget**（调用方不 await ⇒ 不阻塞开流）；任何异常静默。
  ///   打一行：`[SRC] 分片列表 段数=… 平均段长=…s 总时长=…s 首段字节=… 列表字节=…`
  ///   ⚠️ **不打地址/cookie**（只打数字）✅
  Future<void> _logHlsFacts(String url, Map<String, String> hdrs) async {
    if (!AppSettings.i.logConsole) return;
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      Future<String> get(String u) async {
        final rq = await c.getUrl(Uri.parse(u));
        hdrs.forEach(rq.headers.set);
        final r = await rq.close().timeout(const Duration(seconds: 8));
        return r.transform(utf8.decoder).join();
      }

      final master = await get(url);
      final variants = RegExp(r'#EXT-X-STREAM-INF').allMatches(master).length;
      // ⚠️ 用 multiLine: true + trim（别在正则里塞 `\r\n` —— 分析器会报"invalid regexp"）
      final vUri = RegExp(r'^([^#]\S*\.m3u8)', multiLine: true)
          .firstMatch(master)
          ?.group(1)
          ?.trim();
      if (vUri == null) {
        // ★ 2026-10-11（用户批"补开关"）：与本文件其它 `[SRC]`/`[PLAY]` 日志**同款** —— 只有 logConsole
        //   打开时才插值+打印（⚠️ 本方法是 async：入口那一道判断之后 logConsole 可能被关掉 ⇒ 这里**再判一次**）
        if (AppSettings.i.logConsole) {
          debugPrint('[SRC] 分片列表 变体=$variants 无变体行（不是 master？）列表字节=${master.length}');
        }
        return;
      }
      final vAbs = vUri.startsWith('http') ? vUri : '${url.substring(0, url.lastIndexOf('/') + 1)}$vUri';
      final vs = await get(vAbs);
      final segs = RegExp(r'^([^#]\S*\.(?:m4s|ts|mp4))', multiLine: true)
          .allMatches(vs)
          .map((m) => m.group(1)!.trim())
          .toList();
      final durs = RegExp(r'#EXTINF:([\d.]+)')
          .allMatches(vs)
          .map((m) => double.tryParse(m.group(1)!) ?? 0)
          .toList();
      final sum = durs.fold<double>(0, (a, b) => a + b);
      final target = RegExp(r'#EXT-X-TARGETDURATION:(\d+)').firstMatch(vs)?.group(1) ?? '?';
      var firstBytes = -1;
      if (segs.isNotEmpty) {
        final sAbs = segs.first.startsWith('http')
            ? segs.first
            : '${vAbs.substring(0, vAbs.lastIndexOf('/') + 1)}${segs.first}';
        try {
          final rq = await c.getUrl(Uri.parse(sAbs));
          hdrs.forEach(rq.headers.set);
          rq.headers.set('Range', 'bytes=0-0');
          final r = await rq.close().timeout(const Duration(seconds: 8));
          final cr = r.headers.value('content-range');
          firstBytes = int.tryParse(RegExp(r'/(\d+)$').firstMatch(cr ?? '')?.group(1) ?? '') ??
              (r.contentLength > 0 ? r.contentLength : -1);
          await r.drain<void>();
        } catch (_) {}
      }
      // ★ 2026-10-11（用户批"补日志并出 1.3.4"）：**首个分片实测速率** —— 用来区分"网络吞吐慢"还是"解析/解码慢"。
      //   ⚠️ 分片**忽略 `Range`**（probe32 实测：带 Range 也回 `200` 整片）⇒ 做法是 **流式读到 1MB 就 break**，
      //      再 `client.close(force: true)` 掐断，**绝不下整片**（首片实测 ~6.3MB ⇒ 不下它）✅
      //   ⚠️ 只在 `logConsole` 打开时才发这次请求（async ⇒ 用前再判一次；异常拦掉并打一行）✅
      var fbMs = -1;
      var oneMbMs = -1;
      var gotBytes = 0;
      if (AppSettings.i.logConsole && segs.isNotEmpty) {
        final sAbs = segs.first.startsWith('http')
            ? segs.first
            : '${vAbs.substring(0, vAbs.lastIndexOf('/') + 1)}${segs.first}';
        final sw = Stopwatch()..start();
        final c2 = HttpClient()..connectionTimeout = const Duration(seconds: 6);
        try {
          final rq = await c2.getUrl(Uri.parse(sAbs));
          hdrs.forEach(rq.headers.set);
          final r = await rq.close().timeout(const Duration(seconds: 8));
          fbMs = sw.elapsedMilliseconds; // 首字节耗时（响应头到手）
          await for (final chunk in r) {
            gotBytes += chunk.length;
            if (gotBytes >= 1024 * 1024) break; // ★ 读满 1MB 立即停
            if (sw.elapsedMilliseconds > 15000) break; // 保险丝：最多 15s
          }
          oneMbMs = sw.elapsedMilliseconds;
        } catch (e) {
          if (AppSettings.i.logConsole) {
            final es = '$e';
            debugPrint('[SRC] 分片速率 异常=${es.length <= 60 ? es : es.substring(0, 60)}');
          }
        } finally {
          c2.close(force: true); // ★ 掐断（剩余数据不再收）
        }
        if (AppSettings.i.logConsole) {
          final mb = gotBytes / 1048576.0;
          final sec = (oneMbMs - fbMs) / 1000.0;
          final spd = (sec > 0 && mb > 0) ? mb / sec : 0.0;
          debugPrint('[SRC] 分片速率 首字节=${fbMs}ms 读满1MB=${oneMbMs}ms '
              '实收=${mb.toStringAsFixed(2)}MB 速率=${spd.toStringAsFixed(2)}MB/s（dart:io 直连·读满即掐断）');
        }
      }
      // ★ 2026-10-11（用户批"补开关"）：同款 —— 只有 logConsole 打开时才插值+打印（async ⇒ 再判一次）
      if (AppSettings.i.logConsole) {
        debugPrint('[SRC] 分片列表 变体=$variants 段数=${segs.length} '
            '平均段长=${segs.isEmpty ? '?' : (sum / segs.length).toStringAsFixed(1)}s '
            '总时长=${sum.toStringAsFixed(1)}s TARGET=$target '
            '首段字节=$firstBytes 列表字节=${vs.length}');
      }
    } catch (e) {
      // 只读探针：失败什么都不做（不打错误、不影响播放）
    } finally {
      c.close(force: true);
    }
  }

  /// 打开地址（httpHeaders 用于带 Referer/UA 的防盗链）
  Future<void> open(String url, {Map<String, String>? httpHeaders}) {
    // ★ 2026-10-11（**用户实测**：全屏卡死 + "切集偶尔也弹"同类异常；依据 verify-4 审计表 #6）：
    //   本方法原来缺"已释放"护栏（另外 6 个公开操作早就有）⇒ 补上，与它们口径一致（忽略 + 留痕，不抛）。
    if (_disposed) return _skip('open');
    // ★ probe32 A：**每条源各自重新计时**（只读；logConsole 关着时这段等于不存在）
    if (AppSettings.i.logConsole) {
      _tOpenMs = _nowMs();
      _tMpvMs = null;
      _tDurMs = null;
      _tFrameMs = null;
      _tBufEndMs = null;
      _tLogged = false;
    }
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
    _noFrameMs = 0; // ⚠️ 2026-10-05：首帧前那条 6 秒兜底也**随换源归零** ✓（每条源各算各的 ✓）
    // ⚠️ 2026-10-11（B1/B2 ✅）：新源 ⇒ 缓冲豁免额度与起播保护期都**重新拥有** ✓
    _bufExcuseMs = 0;
    _startedAtMs = null;
    // ★ 2026-10-08 修（用户报"点推荐视频返回后不续播"✗ · 已核实的根因之一）：
    //   `open` **一律按 `play: true` 起播** ✓ ⇒ 打开新源这一刻，"用户意图"就是**在播** ✅，
    //   所以必须把 `_userPaused` 复位 ✗ —— 否则它会被上游那次**内部** pause 污染 ☠：
    //   换片（`didUpdateWidget`）/ 换档（`switchSources`）都**先**调过一次 `pause()`
    //   （本意只是"旧源先停住、别和新源抢声音"✓），那一下会把 `_userPaused` 置成 true ✗，
    //   于是详情页后来读到的是"用户**主动**暂停过" ✗ ⇒ 跳走不记续播 ⇒ 回来不播 ☠。
    _userPaused = false;
    // ★ 用户 2026-10-20（退出重进续播**黑屏**）⇒ **先去掉 hr-seek**：
    //   它是 mpv 的**持久属性**（player 级），设上之后**所有 seek 都走精确模式** ——
    //   包括续播的 `seekExact(375ms)` ⇒ 疑似本次黑屏元凶。
    //   ⚠️ 若去掉后"来回跳卡帧"复发 ⇒ 改成"只在 seek 前临时设、seek 完成恢复 no"。
    // unawaited(() async {
    //   try {
    //     await (_p.platform as dynamic).setProperty('hr-seek', 'yes');
    //   } catch (_) {}
    // }());
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
      // ★ 2026-10-11（用户拍板 A4 ✅）：**网络自愈**两条 —— 让"偶发坏响应 / HTTP 中断"在**播放器内部**
      //   自己缓过来，App 层尽量看不到错误（配合"报错不再直接判死"= A1 ✅）。
      //   ⚠️ 下发时机：本方法在**建实例后、每次 `open()` 之前**都被调（`:1327` 预建引擎那处 ✓），
      //      两个键在 open 前设才稳（mpv 打开流时才读它们 ✓）；通道 = `setMpvOptionQuiet` →
      //      `NativePlayer.setProperty` → `mpv_set_property_string`（媒体库源码 real.dart:1392-1406 ✓ 实例级 ✓）。
      //   ① `network-timeout` —— mpv 官方手册原文：
      //      「Specify the network timeout in seconds (**default: 60 seconds**). This affects at least HTTP.
      //        The special value 0 uses the FFmpeg defaults.」
      //      ⇒ 默认 **60 秒**（本机 libmpv-2.dll 回读实测 = `60.000000` ✓）；这里收到 **20 秒**：
      //        坏源更早给出 error ⇒ 交给 App 层换源/重试；正常慢网也不至于 20 秒还没动静 ✅
      //      ⚠️ **不要设 0**（那会退回 FFmpeg 默认、行为不可控 ✗）。
      //   ② `stream-lavf-o` —— mpv 官方手册原文：「Set AVOptions on streams opened with libavformat.」
      //      下面这几项取自 **FFmpeg 官方 http 协议文档**（ffmpeg-protocols.html）原文：
      //        · `reconnect=1`                  「Reconnect automatically when disconnected before EOF is hit.」
      //        · `reconnect_streamed=1`         「If set then even streamed/non seekable streams will be
      //                                          reconnected on errors.」← HLS 是**流式**读取，必须这条 ✅
      //        · `reconnect_delay_max=5`        「Set the maximum delay in seconds after which to give up
      //                                          reconnecting.」⇒ 最多忍 5 秒就放弃（别让我们卡在重连里 ✗）
      //        · `reconnect_on_network_error=1` 「Reconnect automatically in case of TCP/TLS errors during connect.」
      //        · `reconnect_on_http_error=5xx`  「A comma separated list of HTTP status codes to reconnect on.
      //                                          …or the strings '4xx' / '5xx'.」⇒ **只 5xx**：4xx 是签名/防盗链
      //                                          那类**确定性**失败，重试没意义（403/404 已是"硬错误早判"）
      //      ⚠️ **两个"不要"**（避免踩坑）：
      //        · **不要**加 `reconnect_at_eof`（官方原文：it is useful for **live / endless streams** ⇒
      //          点播（有 `#EXT-X-ENDLIST`）正常结束会被当成断流去重连 ✗）
      //        · **不要**用 FFmpeg 的 `timeout=`（单位是**微秒**、与上面 `network-timeout` 语义重叠，
      //          极易写错一个数量级 ✗）
      //      ⚠️ **最大风险（官方原文）**：mpv 手册写明「**Unknown or misspelled options are silently
      //        ignored.**」⇒ 键名打错**不会报错、静默失效** ☠ ⇒ 上真机必须实测确认一次
      //        （本次已在本机 libmpv-2.dll 上离线验证：这两个 mpv 选项名都被接受、回读生效 ✅，
      //          但 AVOption 是否真生效只能由真机行为确认 ☑️）。
      kp.setMpvOptionQuiet('network-timeout', '20');
      // ★ 2026-10-14：`multiple_requests=1` **已撤**（当天加、当天退）☑️ —— 依据（**别再按"对标 AniBaka"顺手加回** ☠）：
      //   · 1.4.1（含此键）真机实测：柚子**起播即卡**（打开成功、时长都拿到，零首帧、位置恒 0、
      //     引擎自停；自动重试 2 次同症状）；用户对照 **1.4.0（无此键）同剧正常** ⇒ 单变量指向它 ⇒ 撤。
      //   · 语义是 HTTP **持久连接**（复用同一条连接）⇒ 与站方媒体链路犯冲时会把数据流卡死；
      //     先前"不认=静默忽略、无副作用"的假设**已被真机否掉** ☠。
      //   · 历史旁证（`DEVLOG_archive.md:3748`）：`multiple_requests` / `Connection: keep-alive`
      //     这两条当年就是"实测无提速、已排除"的尝试 ⇒ 没有加回来的理由。
      kp.setMpvOptionQuiet(
        'stream-lavf-o',
        'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5,'
        'reconnect_on_network_error=1,reconnect_on_http_error=5xx',
      );
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
    if (_disposed) return _skip('play');
    _userPaused = false;
    _syncPlayingFlag(true); // ★ 主动置位（见上）—— 按钮图标立刻换、下次点击才会判成"该 pause"
    return _p.play();
  }

  /// ★ 2026-10-11（**用户实测"退不出全屏"** ⇒ 本防御）：引擎已释放 ⇒ **忽略本次操作、只留痕、不抛**。
  ///   背景：全屏里切集会把旧引擎延迟回收，而全屏页/手势回调可能还攥着那个实例（见下面那条堆栈），
  ///   媒体库会抛 `A KpPlayer was used after being disposed.` ⇒ 串发框架异常 ⇒ **整条全屏路由卡死**。
  ///   那一处在 UI 层也修了（全屏页动态取当前引擎 + 自愈），这里是**兜底**：任何漏网的调用点都不会再炸。
  Future<void> _skip(String op) {
    if (AppSettings.i.logConsole) debugPrint('[PLAY] ⚠️ 已释放引擎收到 $op() ⇒ 忽略（防 used-after-disposed 连锁）');
    return Future<void>.value();
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
    if (_disposed) return _skip('autoResume');
    _syncPlayingFlag(true); // ★ 同上（口径与 play 一致 ✓）
    await _p.play();
  }

  Future<void> pause() {
    // 看：谁在什么时机调了暂停（用户操作还是流程自己暂停 ⇒ 与"看门狗"对着看）。
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 暂停');
    if (_disposed) return _skip('pause');
    _userPaused = true;
    _syncPlayingFlag(false); // ★ 主动置位（见上）—— 否则图标不换、再点又判成"在播"⇒ 又 pause() ☠
    return _p.pause();
  }


  /// 播放倍速——长按快进用：按住时 2.0、松手回 1.0
  Future<void> setRate(double r) async {
    if (_disposed) return _skip('setRate');
    await _p.setRate(r);
  }

  /// ★ 用户 2026-10-20（1.5.5 实机：退出重进**卡在首帧**）：把"seek 后让解码器出帧"的两步
  ///   抽成公共方法 —— `seek`（用户跳转）**和** `seekExact`（续播/换档）都要用（续播同样会不出帧）。
  ///   ⚠️ **不再退 `frame-step`**：mpv 的 `frame-step` 是"前进一帧并**暂停**"⇒ 会把画面停住 ☠
  Future<void> _afterSeek(Duration t) async {
    if (_disposed) return;
    // ① 微偏移 reseek（+1ms）—— 让解码器重新出帧（肉眼无差）
    try {
      await _p.seek(t + const Duration(milliseconds: 1));
    } catch (_) {}
    if (_disposed) return;
    // ⑤ 让 mpv 刷新视频输出（内部 API；命令不存在 / 不支持 ⇒ 静默）
    try {
      await (_p.platform as dynamic).command(<String>['video-refresh']);
    } catch (_) {}
  }

  /// seek（★ 用户 2026-10-20：快跳 / 远跳 / 来回跳之后 **画面卡在 seek 前那一帧**）
  ///
  /// 三层"体验无感"的缓解（用户拍板 ①+③+⑤，全部不影响正常播放）：
  ///   ③ `hr-seek=yes` 在 [_openUrl] 里设（精确 seek）；
  ///   ① seek 完成后**微偏移 reseek（+1ms）** ⇒ 让解码器重新出帧；
  ///   ⑤ 下发 mpv `video-refresh`（失败退 `frame-step`）⇒ 刷新视频输出。
  ///      ⚠️ 内部 API（`NativePlayer.command`）⇒ 全部 try/catch 静默，失败不影响播放。
  Future<void> seek(Duration d) async {
    final t = _clampDur(d, value.duration);
    // 看：seek 的实际去向（从当前播到的位置 → 裁剪后的目标）—— "跳完从头/跳不动"对这条看。
    if (AppSettings.i.logConsole) debugPrint('[PLAY] seek 从=${value.position.inMilliseconds}ms 到=${t.inMilliseconds}ms');
    if (_disposed) return _skip('seek'); // ★ 幂等护栏

    await _p.seek(t);
    await _afterSeek(t);
  }

  /// **不按时长裁剪**的 seek。续播/换档专用：那种场景下目标是"上一条源播到的
  /// 位置"，而 `seek()` 会按 `value.duration` 裁剪，万一时长还没报上来
  /// （或报了个半截值）就会被裁小 —— 表现同样是"从头发"。
  Future<void> seekExact(Duration d) async {
    // 看：不裁剪的精确 seek（续播/换档用）—— 目标是多少 ms。
    if (AppSettings.i.logConsole) debugPrint('[PLAY] seek(精确) 从=${value.position.inMilliseconds}ms 到=${d.inMilliseconds}ms');
    if (_disposed) return _skip('seekExact');
    await _p.seek(d);
    await _afterSeek(d); // ★ 续播同样要"让解码器出帧"（1.5.5 实测：不加会卡在首帧）
  }

  /// ★ 2026-10-11（**用户实测"退不出全屏"** 的防御配套）：给外部一个**可查询的**释放状态。
  ///   依据的用户栈：`_FullscreenPlayerState._onDoubleTap`（`:2664`）⇒ `KpPlayer.seek` ⇒ 媒体库
  ///   `A KpPlayer was used after being disposed.` ⇒ 串发框架异常 ⇒ 全屏路由卡死。
  ///   ⚠️ 全屏页那边已改成"**每次都取当前引擎**"+自愈；这里是给那类判断用的公开只读口子。
  bool get isDisposed => _disposed;

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
    retrying.dispose(); // ★ A2：本实例自己那个 notifier 也要收（全屏页只读它 ⇒ 不会留着乱发）
    dispose();
  }
}

/// 缓冲提示：跳转跨度大时要重新拉流，没提示看着像卡死。
///
/// ★ 用户 2026-10-20（实测）：**进度都到底了中间还在转圈** —— 播完（`completed`）或位置到结尾
///   （留 400ms 容差）时 mpv 的 `buffering` 可能仍为 true ⇒ 这里直接不显示，把位置让给「重播」按钮。
Widget _bufferingHint(KpPlayer kp) {
  return Align(
    alignment: const Alignment(0, -0.45),
    child: ValueListenableBuilder<KpState>(
      valueListenable: kp,
      builder: (_, s, __) {
        if (!s.buffering) return const SizedBox.shrink();
        if (s.completed) return const SizedBox.shrink();
        final d = s.duration;
        if (d > Duration.zero &&
            s.position >= d - const Duration(milliseconds: 400)) {
          return const SizedBox.shrink();
        }
        return const SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
              color: Colors.white70, strokeWidth: 2),
        );
      },
    ),
  );
}

/// ★ 2026-10-11（**用户实测**：全屏卡死 + "切集偶尔也弹"同类异常；依据 **verify-4 审计表** #5/#6/#12/#21/#22）：
///   **护栏统一日志口径** —— 任何一处发现"手里的引擎已释放"都打这一行（仅 `logConsole` 打开时），
///   格式固定为 `忽略已释放引擎的操作: <op> @<位置>` ⇒ 以后真机上再出问题时，一眼看出是**哪个位置**晚了。
void _logDisposedSkip(String op, String where) {
  if (AppSettings.i.logConsole) {
    debugPrint('[PLAY] 忽略已释放引擎的操作: $op @$where');
  }
}

/// ★ 2026-10-11（**用户新规格**）：**倍速按钮** —— **正圆 + 半透明**、**只有数字变化**
///   （`1X`/`2X` 样式**完全一致**：无橙色/主色高亮、底色/文字色/尺寸都不变）；**跟随"控件可见"显隐**
///   （内嵌复用 `_controlsVisible`、全屏复用 `_controls` —— **不新造计时器**）；**贴右缘、垂直居中**。
///   ⚠️ 手势竞争（"不吃播放器手势"的关键）：
///     · **只注册 `onTap`** ⇒ 起手拖动/双击/长按落到这块时，tap 识别器会在竞技场里**失败退出** ⇒
///       手势**回落到下层**（播放器的滑动 seek / 双击 seek / 长按 2×）✅
///     · 命中区 = 这个直径 [_kRateD] 的正圆（`HitTestBehavior.opaque`）⇒ "小而准" ✅
///     · 层级：Stack 里在"视频 + 手势层"**之上**、提示/控制条**之下** ✅
/// ★ 2026-10-11（**用户微调**："倍率按钮小了一点，再加大一点点"）：直径 36 → **42**、字号 13 → **15**
///   （只动这两个数 ⇒ 正圆/半透明 45% 黑底/白字/无高亮/跟随显隐/只注册 onTap 全部不变）
const double _kRateD = 42; // 直径（36 → 42：略大一点点，仍"小而准"）

Widget _rateButton(ValueNotifier<double> n) {
  return SizedBox(
    width: _kRateD,
    height: _kRateD,
    child: ValueListenableBuilder<double>(
      valueListenable: n,
      builder: (_, r, __) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => n.value = r >= 1.5 ? 1.0 : 2.0, // 只有两档
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45), // 半透明（黑底白字；1X/2X 完全同款）
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                r >= 1.5 ? '2X' : '1X', // ★ 唯一区别 = 数字
                // ★ 2026-10-11（**用户实拍："字体没居中"** ⇒ 定位 + 修复）：
                //   原因 = 上面那句 `height: 1.0`（**不是** `Center` 缺失：盒子是 42×42 紧约束、`Center` 已经
                //   在几何上居中）。`height: 1.0` 把行盒**压缩到正好 15px** ⇒ 字体自然的
                //   ascent/descent（约 0.93em/0.24em）被等比压进 15px ⇒ 基线落到 0.795em 处，
                //   而数字（无降部、只占 cap height）的视觉中心 ≈ 0.435em，比盒子中心（0.5em）**偏高约 1px**
                //   ⇒ 看着"没居中"。修法 = **去掉 `height: 1.0`**，用字体自然行高：此时基线在 0.93em、
                //   数字视觉中心 ≈ 0.57em，与盒子中心 0.585em 只差 **≈0.2px**（<1px，无需 `Transform` 补偿 ✅）。
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15, // 13 → 15（与直径 42 同步；1X/2X 仍完全同款）
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        );
      },
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
  /// ★ 2026-10-11（verify-4 **R2**）：**可空** —— 切集空窗期可能"一个活引擎都没有"；
  ///   调用方一律 `?.`（拿不到就跳过这次手势，绝不空断言崩）。
  KpPlayer? get swipePlayer;

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
    // ★ 2026-10-11（verify-4 **R2**）：引擎可能**在切集空窗里暂时不存在**（旧的已转回收、新的还没上屏）
    //   ⇒ getter 改为**可空**，这里用 `?.` + 兜底值（绝不再用 `!` 空断言：那会直接崩在空窗期）
    _dragFrom = swipePlayer?.value.position ?? Duration.zero;
    _dragTarget = _dragFrom;
    // ★【常驻诊断】横滑开始（只记起点 ✓ 拖动过程不逐帧打 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 横滑开始 起点=${_dragFrom.inMilliseconds}ms 时长=${swipePlayer?.value.duration.inSeconds ?? 0}s');
  }

  void swipeUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    _dragDx += d.delta.dx;
    final total = swipePlayer?.value.duration ?? Duration.zero;
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
      swipePlayer?.seek(_dragTarget); // 只在这一下跳转（拖动中不动播放器）；空窗期无引擎 ⇒ 跳过
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
      final near = ((swipePlayer?.value.position ?? target) - target).abs() <=
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
  /// ★ 2026-10-11（verify-4 **R2**）：可空，同 [swipePlayer]。
  KpPlayer? get gesturePlayer;

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
      // ★ 2026-10-09（Windows 桌面链路 ✓）：**必须包一层** ☠ —— `volume_controller 2.0.8` 的
      //   pubspec 只声明了 **android/ios** 两个平台（实测读该包 pubspec ✓），桌面上调用会抛
      //   `MissingPluginException` ☠；本函数是**拖动回调**（右半屏竖滑），不在手势里接住的话
      //   每滑一下都往 `FlutterError.onError` 抛一条 ✗（用户会看到日志刷屏，观感像"播放坏了" ✓）。
      //   ⚠️ 口径与同文件 `bvPrime`/`_bvRefreshVolume` 那两处**完全一致**（它们本来就 `catch (_) {}` ✓）；
      //      iOS 上调用**照旧成功** ⇒ 行为零变化 ✓（只是多了个永不会走的 catch ✓）。
      try {
        VolumeController().setVolume(v);
      } catch (_) {}
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

  /// 视频标题（详情页传文章标题，可为空）——
  /// ★ 用户要求：**只在两种全屏**（竖版全屏 `vertical=true` / 横屏全屏 `vertical=false`）的顶部显示；
  ///   内嵌播放器**不显示**（原样不动 ✅）。显隐跟随全屏页那套 `_controls`（不另起定时器 ✅）。
  final String title;

  /// 各集标签（与详情页选集同一份：`ArticleVideo.label`，如"第 3 集"），下标与 [switcher] 的 index 同一套。
  /// ★ 用户要求：**多集**时全屏标题为 `文章标题 · 第 N 集`（换集实时变 ✅），**单集/电影**不加后缀 ✅。
  /// 标签为空（或下标越界）时全屏侧兜底成 `第 N 集`（1-based）✅。
  final List<String> epLabels;

  /// 全部源都失败时调用：重新抓详情页拿新地址
  final Future<List<String>> Function()? onRefreshSources;

  /// 合集类：当前这一集要去哪个子文章页取源（为空 = 自带视频的普通条目）
  final String? lazyUrl;

  /// 合集类：按地址取源的入口（详情页接到 Api.videoSourcesAt）
  final Future<List<String>> Function(String url)? onFetchSources;

  /// 篇内视频切换状态（多视频文章才有；null = 单视频，没有"下一集"）
  final VideoSwitcher? switcher;

  /// ★ 2026-10-11（**新增 · 可选** ✅）：这一集额外要带的请求头（默认 null ⇒ 所有站点零变化 ✅）。
  /// 用途：取流要 cookie 的站点（柚子短剧 ✅ 的 `Cookie: eden_play_<videoId>=…` ✅）。
  /// ⚠️ **每次 `open` 现读**（见 `_openAndWait` ✅）—— 不在 init 时缓存 ☑️
  ///   ⇒ "刷新源拿到新头 ⇒ 重试那一轮就用新头" ✅。
  final Map<String, String>? httpHeaders;

  /// 从"播放记录"点进来时的续播位置：首次成功起播后跳到这（只生效一次）。
  /// 从站点入口进来不传 → null → 完全按原行为从头播（用户要求）。
  final Duration? initialPosition;

  /// 进度上报（位置、总时长、是否播完）。详情页拿它写播放记录；不传就不上报。
  final void Function(Duration pos, Duration dur, bool finished)? onProgress;

  /// ★ 下载（用户要求）：控制条上的「下载」按钮 —— 点它就下**当前这一集**。
  /// null = 不显示这个按钮（其它入口/降级场景）；由详情页传入。
  /// ⚠️ 只加按钮，不参与 open / 换片 / 重试 / 全屏 / 手势任何逻辑。
  final VoidCallback? onDownloadCurrent;

  /// 当前这一集的下载态：'none' / 'downloading' / 'done'（只决定图标 + 是否可点）。
  final String downloadStatus;

  const PlayerWidget({
    super.key,
    required this.sources,
    required this.referer,
    this.poster = '',
    this.title = '',
    this.epLabels = const [],
    this.onRefreshSources,
    this.lazyUrl,
    this.onFetchSources,
    this.switcher,
    this.httpHeaders,
    this.initialPosition,
    this.onProgress,
    this.onDownloadCurrent,
    this.downloadStatus = 'none',
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

  // ★ 2026-10-11（**probe23/26 实测驱动** ✅）：切集改为"**重建引擎 + 新纹理**"，并给新引擎配"**首帧自愈**"。
  //   依据：probe23（新库）**每集新建引擎 5/5 正常**（1.8~4.3s 出画）；probe26（App 界面路径、复用引擎）
  //   实测 **16/17 次黑**（新源 `Opening done` 后不出帧、位置恒 0）⇒ 复用那条路不可用。
  // ★ 2026-10-13（**用户指令：去掉 9s 自愈** ✅）：原先这里还配了"**首帧自愈**"（`_ffTimer` / `_ffHeals` /
  //   `_kFfHealAfter=9s` —— 新引擎 9s 没首帧 ⇒ 再 `_initPlayer()` 一次）☠ 已**整段删除**，原因（🛢️）：
  //   ① 它是给"复用档黑屏"当兜底的 —— 黑屏**根因已查明并修复**（`media_kit` 1.1.11→1.2.6，见 DEVLOG 第三条）；
  //   ② 在**重建档=关（默认）**时，它那句"⇒ 重建引擎"实际走的仍是复用档 ⇒ **同一个 kp、不换引擎** ☠
  //      ⇒ **治不了慢，还多花一次"重开源"的时间**（🛢️ 2026-10-13 iOS 柚子日志：14:08:17 触发 ⇒
  //      14:08:19 仍是 `kp=788293175`，随后 10.27s 才首帧 ⇒ 首帧慢的真因是**数据侧速率**（分片 4MB / 0.5~1.35MB/s））；
  //   ③ 它唯一的有效场景是"重建档=开"（那时才真换引擎）—— 该场景由"切集重建"本身覆盖 ✅
  static const Duration _kRetireDelay = Duration(milliseconds: 800); // 旧引擎延迟回收（先挂新、再收旧）
  /// ★ 2026-10-11：回收**硬上限** —— 条件（新引擎上屏 / 全屏退出）一直不满足也不能永久留着（防泄漏）
  static const Duration _kRetireMaxWait = Duration(seconds: 20);
  /// ★ 2026-10-11（**复用档取证**，只读标记）：本次切集/换源走的是"复用"档吗？
  ///   仅用于在源循环里补一行诊断日志（`logConsole` 下），**不参与任何判据、不改行为** ✅
  bool _reuseSwitch = false;
  int _kpCreated = 0; // 引擎创建计数（仅诊断日志用：与回收计数配对看是否漏）
  int _kpRetired = 0; // 引擎回收完成计数

  /// ★ 2026-10-11（**用户实测**："窗口内都好了，但**全屏里切集黑**"）：**当前引擎的对外通知口**。
  ///   全屏页（`FullscreenPlayer`）是**另一条路由**、push 时抓的是**那一刻的 `KpPlayer` 实例**；
  ///   现在切集 = 重建引擎（probe23/26 依据）⇒ 全屏页必须**跟着换实例**，否则它握着已回收的引擎 ⇒ 黑。
  ///   用法：`_attach`（新引擎上屏）时 `kpCurrent.value = kp`；全屏页用 `ValueListenableBuilder` 监听，
  ///   并以 `identityHashCode(kp)` 作 `ValueKey` ⇒ 引擎一变，全屏页 State 整个重建（纹理/手势/控件全跟新引擎 ✓）。
  ///   ⚠️ 故意**不 dispose**（`PlayerWidget` 先销毁、全屏路由还挂着时，dispose 会让监听方抛"used after dispose"；
  ///   它只持一个指针、无 native 资源 ☑️）。
  final ValueNotifier<KpPlayer?> kpCurrent = ValueNotifier<KpPlayer?>(null);
  bool _inheritFullscreen = false; // 重建时把"正在全屏"带给新引擎（见 _initPlayerOnce / _attach）

  /// ★ 2026-10-11（**用户规格**）：**常驻倍速开关**（1X ⇄ 2X）—— 只有两档、**不写磁盘**（离开详情页回 1×）。
  ///   ⚠️ 用 `ValueNotifier` 共享给**全屏页**（独立路由）⇒ 哪边点都同步 ✅。
  ///   ⚠️ 换集/换源/自愈/重试之后**新引擎上屏必须重新下发**（切集 = 重建引擎）⇒ 见 [_attach] 里的 `_applyRate`。
  ///   ⚠️ 故意**不 dispose**（同 [kpCurrent]：PlayerWidget 先销毁、全屏路由还挂着时会抛 "used after dispose"）。
  final ValueNotifier<double> rateNotifier = ValueNotifier<double>(1.0);

  /// 把"当前开关状态"下发到**当前活着的引擎**（幂等；空窗/已释放 ⇒ 静默跳过）。
  ///   [why] 只进日志（`logConsole` 时打），便于以后定位"谁把倍速改回去了"。
  void _applyRate(String why) {
    final r = rateNotifier.value;
    final kp = _kp;
    if (kp == null || kp.isDisposed) return;
    unawaited(kp.setRate(r));
    if (AppSettings.i.logConsole) {
      debugPrint('[PLAY] 倍速 ⇒ ${r == 2.0 ? '2.0' : '1.0'}×（$why）');
    }
  }

  void _onRateChanged() => _applyRate('开关变更');
  /// ★ 2026-10-11（用户实测"退不出全屏"的同源修复，内嵌侧）：**最近一次上屏的引擎**。
  ///   切集/换源会重建引擎，而 `_kp` 在"切掉旧的、还没挂新的"这段时间里是 `null`；
  ///   此刻若手势回调（左右滑快进/亮度音量）还在跑，`swipePlayer => _kp!` 会直接**空断言崩**。
  ///   配合 `_retireKp` 的**条件回收**（新引擎上屏前不 shutdown 旧的）⇒ 这个实例在空窗里**仍然活着** ✓
  ///   ⇒ 手势打到它身上是"继续操作旧引擎"（不黑、不崩）；真正的回收发生在它被清空之后 ✓
  KpPlayer? _lastEngine;
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

  /// 「重播」按钮是否显示中（进度回调里比对变化 ⇒ 立刻重建，不依赖别的 setState）
  bool _replayShown = false;
  Timer? _hideTimer;
  Offset _lastTapPos = Offset.zero; // 双击落点（判断左半/右半）
  IconData? _tapHint; // 双击提示图标（快退/快进/暂停/播放）
  double _tapHintX = 0; // 提示位置：-0.6 左 / 0 中 / 0.6 右
  Timer? _tapHintTimer;
  bool _longPressing = false; // 长按快进中（按住 2 倍速）

  @override
  void initState() {
    super.initState();
    // ★ 2026-10-11（用户规格）：倍速开关的状态变化 ⇒ 立刻下发到当前引擎（按钮点哪儿都走这一条）
    rateNotifier.addListener(_onRateChanged);
    // ★【常驻诊断】播放器 State 建立（同一条视频出现两次 = 内嵌播放器被整个重建过 ⇒ "画面假死"先看这条 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] PlayerWidget.initState 挂载 源=${widget.sources.length}条 poster=${widget.poster.isEmpty ? '无' : '有'} 续播=${widget.initialPosition?.inMilliseconds ?? 0}ms switcher=${widget.switcher != null}');
  }

  @override
  // ★ 2026-10-11：切集空窗里 `_kp == null` ⇒ 退到"最近一次上屏的引擎"（它此刻还活着，见 [_lastEngine]），
  //   空断言 `_kp!` 会在"切集瞬间还在拖手势"时直接崩 ✗
  // ★ 2026-10-11（verify-4 **R2**）：**去掉 `!` 空断言** —— 切集空窗期 `_kp`/`_lastEngine` 都可能是 null
  //   （回退链两个都空 ⇒ 返回 null ⇒ 手势调用点 `?.` 跳过这次操作，不崩）
  KpPlayer? get swipePlayer => _kp ?? _lastEngine;

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
  KpPlayer? get gesturePlayer => _kp ?? _lastEngine; // ★ 同 swipePlayer（R2：可空、无空断言）

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
      // 换片（点"下一集"或自动下一集）：**重建引擎 + 新纹理**（旧的延迟回收）。
      // ★ 2026-10-11（probe23/26 实测驱动 ✅）：原来这里是"复用同一个播放器实例去开新源"——
      //   注释写的是"不能销毁重建——销毁掉它就黑屏了"，那是**旧库时代 + 先收后挂**的结论。
      //   现在改成"**先挂新、再收旧**"（见 [_initPlayerOnce] 里那段 + [_retireKp]）⇒ 复用那条路才是黑的：
      //   probe26（界面路径、复用）**16/17 次黑**（新源 Opening done 后不出帧）；probe23（每集新建）**5/5 正常**。
      _sources = widget.sources.where((s) => s.isNotEmpty).toList();
      _nextFired = false;
      _errShown = false;
      _error = null;
      // 换集：自动重试排期与计数一并清零
      _autoRetryTimer?.cancel();
      _autoRetryTimer = null;
      _autoRetries = 0;
      _setAutoRetrying(false);
      // 点击就要"立刻"有反应（用户要求）：旧视频先停住，别等新源就绪；
      // 这一集要按需取源的话，"正在取视频…"提示也立即亮（不用等网络）。
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 暂停 触发源=换片(didUpdateWidget：篇内序号→$_curIndex，旧源先停住别抢声音)');
      _kp?.pause();
      _fetchingLazy = widget.lazyUrl != null && _sources.isEmpty;
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 换片 ⇒ _initPlayer() 源=${_sources.length}条 需按需取源=$_fetchingLazy');
      // ★ 状态已更新（`_curIndex`/`_sources`/`_error`/`_fetchingLazy`）⇒ 踢一帧，防"状态变了没有帧来消化"
      //   （与 `_syncPlayingFlag`/控件那几处同一修法 ✅）
      kickPlayerFrame();
      // ★ 2026-10-11（**probe26 实测驱动** ✅）：这一句**必须挪出 build 期** —— `didUpdateWidget` 是在
      //   **父级 build 期间**同步跑的，而 `_initPlayer → _initPlayerOnce` 里既有 `setState`
      //   （:1345/:1386/:1390/:1402 等）又会 `await` 按需取源（:1342-1350，最长 6 秒）⇒ 在 build 期开跑
      //   会把"换集"整步卡住。probe26 实测：**界面路径**切集 16/17 次命中"新源从未起播、位置恒 0、
      //   `buffering` 永真"，而**直接调 `open`** 的对照 12/12 正常 ⇒ 差别就在"是否在 build 期同步开跑"。
      //   首次进入本来就特意用微任务躲这个坑（见 :1260-1262 原文"不能在本元素 build 期间调用"）⇒ 与它保持一致 ✅。
      Future.microtask(_initPlayer);
    }
  }

  /// 从外部换一批源并重开（详情页的「清晰度」选择用）。
  /// 走和「换集」同一套重开流程（见 didUpdateWidget 里那段），**同样"重建引擎 + 新纹理"**（行为一致 ✅）。
  /// ★ 2026-10-11（probe23/26）：这里原来写的是"不重建实例——重建会让全屏页手里攥着的旧实例失效（黑屏）"。
  ///   现在改为重建，两条护栏（**2026-10-11 晚更新**）：
  ///     ① **先挂新、再收旧**（旧引擎延迟 [_kRetireDelay] 回收，见 [_retireKp]）；
  ///     ② **全屏页跟随引擎变化**：`_attach` 更新 [kpCurrent] ⇒ 全屏页按 `ValueKey(引擎身份)` 整页重建
  ///        （用户实测"全屏里切集黑" ⇒ 这条是那次修复的核心；见 [_openFullscreen]）。
  ///   ⇒ 所以换清晰度/换集在**全屏里**也走重建，且全屏画面会跟着换到新纹理 ✅（不再回落老行为）。
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
    _setAutoRetrying(false);
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
    rateNotifier.removeListener(_onRateChanged); // ★ 倍速开关监听（与 initState 成对；notifier 本身不 dispose，见字段注释）
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
    _setAutoRetrying(false);
    // ★ 2026-10-05（用户拍板：起播优化 #1）：**引擎构造提前**到"按需取源"之前 ✓
    //   —— 构造 + 起播参数都与 URL 无关 ✓ ⇒ 与取源窗口（最长 6 秒 ✓）**重叠** ✓；
    //   ⚠️ 上屏（`_attach`）**仍在取源完成之后** ✓（时机与改前逐字一致 ✓ 不出现空壳播放器 ✓）。
    // ★【常驻诊断】要不要现在建引擎（true ⇒ 下面新建一个"还没上屏"的 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 预建引擎 需要=${_kp == null && _prebuiltKp == null}（缓冲=${AppSettings.i.bufferMb}MB）');
    // ★ 2026-10-11（**probe23/26 实测驱动** ✅）：**切集/换源/重试一律"重建引擎 + 新纹理"**。
    //   依据：probe23（新库）每集新建引擎 **5/5 正常**（1.8~4.3s 出画）；probe26（App 界面路径、**复用**引擎）
    //   实测 **16/17 次黑**（新源 `Opening done` 后不出帧、位置恒 0）⇒ 复用那条路不可用。
    //   ⚠️ 顺序必须"**先挂新、再收旧**"（旧引擎此刻**不** shutdown，等新引擎上屏后按 [_kRetireDelay] 延迟回收，
    //      见 [_retireKp]）—— 旧库时代"不能销毁重建"那条注释说的是**先收后挂**的场景（那时确实会黑）。
    //   ✅ 2026-10-11 晚：**全屏页现在也跟随重建**（`kpCurrent` 通知口 + `ValueKey(引擎身份)` ⇒ 全屏页 State 重建），
    //      所以原来那条"全屏打开时跳过重建"的护栏**已移除**；"正在全屏"这个标记会**继承给新引擎**（[_inheritFullscreen]）。
    // ★ 2026-10-11（**用户拍板：新增两档开关** `AppSettings.i.switchRebuildEngine`）：
    //   · **开（默认，安全档）** = 下面那段"**销毁重建**"**原样执行**（当年修"切集黑屏"就是靠它 ✅）
    //   · **关（实验性）** = "**复用引擎**"：切集**不新建、不回收** ⇒ 后面的源循环直接命中 `var kp = _kp;`
    //     在**同一个引擎**上 `open` 新源（= 旧行为；少付一遍"打开"成本，但**部分站点可能黑屏** ☠）
    //   ⚠️ 两档**共用**下面的"预建引擎"与源循环；**守卫一律保留**（`_live`/`_guardDead`/`isDisposed`/
    //      `_popping`/`_lastEngine`/`_retireKp` 全在原处，不因复用档而删 ✅）
    final rebuildEngine = AppSettings.i.switchRebuildEngine;
    if (AppSettings.i.logConsole) {
      debugPrint('[PLAY] 模式=${rebuildEngine ? '重建' : '复用'} 切集/换源：当前 kp='
          '${_kp == null ? '(无)' : identityHashCode(_kp!).toString()}');
    }
    if (rebuildEngine) {
    _reuseSwitch = false; // ★ 2026-10-11（复用档取证用；只读标记，不改任何行为）
    final kpFullscreen = _kp?.fullscreenOpen ?? false;
    if (_kp != null) {
      final old = _kp!;
      old.removeListener(_onTick); // 旧引擎不再驱动本页 UI（回收前先摘监听，避免它继续 setState）
      _reportTimer?.cancel();
      _kp = null; // ⇒ 下面照旧"新建 + 上屏"；`_attach` 里 old==null ⇒ 不会立刻 shutdown ✓
      _inheritFullscreen = kpFullscreen; // 新引擎要接住"正在全屏"（详情页 didPushNext 靠它区分全屏/跳走 ✓）
      _retireKp(old); // 延迟回收（先挂新、再收旧 ✓）
      if (AppSettings.i.logConsole) {
        debugPrint('[PLAY] 切集重建：旧引擎 kp=${identityHashCode(old)} 转入延迟回收；'
            '新建计=$_kpCreated 已回收=$_kpRetired 全屏中=$kpFullscreen');
      }
    }
    } else {
      // ★ 复用档：**什么都不做**（不摘监听、不停上报、不置空、不回收）—— 引擎继续被本页驱动 ✅
      //   ★ 2026-10-11（**用户报"复用档切集黑屏"后的取证**）：这里是 **"只加日志"** 的取证点 ——
      //     把"三步"的真实入参打出来，下次一眼能看出是"三步走错"还是"打开了但不出帧"：
      //       · `pause`  = **上游已发**（`didUpdateWidget`/`switchSources` 里那句"旧源先停住"）
      //       · `open`   = 走 `_openAndWait → KpPlayer.open`，**内部固定 `play: true`**（`player_widget.dart:707`）
      //       · `stop`   = **历史（≤1.2.9）与现在都没有用过**（两边一致，`grep .stop(` 0 命中）
      //     ⚠️ 本分支**只读**：不 stop、不 play、不 attach（与 ≤1.2.9 那条路逐字等价 ✅）
      _reuseSwitch = true;
      if (AppSettings.i.logConsole) {
        debugPrint('[PLAY] 模式=复用：沿用当前引擎（不新建/不回收）kp='
            '${_kp == null ? '(无·由下面预建引擎补上)' : identityHashCode(_kp!).toString()}');
        debugPrint('[PLAY] 复用取证 三步：pause=上游已发 open=即将发(内部 play:true) stop=两边都没用过 '
            'attach=不发（同实例同纹理）');
      }
    }
    if (_kp == null && _prebuiltKp == null) {
      _prebuiltKp = KpPlayer(bufferMb: AppSettings.i.bufferMb);
      // ⭐ 详情页/全屏都套起播参数（#5 ✓）——与短片页**同一个实现** ✓（`KpPlayer.tuneStartupQuiet` ✓）
      KpPlayer.tuneStartupQuiet(_prebuiltKp!);
      _kpCreated++;
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
          // ★ 2026-10-11（verify-4 **#5 高**）：`kp` 是**本地缓存**的实例 —— 每次进循环先判一次
          //   （上一轮 await 期间用户可能又换集 ⇒ 它已被转入延迟回收/已 shutdown）
          if (kp.isDisposed) {
            _logDisposedSkip('源循环-本轮开始', '_initPlayerOnce:1519（for i 顶部）');
            return;
          }
          // ★【常驻诊断】每条源的尝试都留痕（与 _openAndWait 的 host=/起播= 两条配对 ✓）
          if (AppSettings.i.logConsole) debugPrint('[PLAY] 试源 round=$round i=$i/共${_sources.length}条');
          final ok = await _openAndWait(kp, _sources[i]);
          if (!mounted) return;
          // ★ 2026-10-11（**复用档取证，只加日志**）：把"打开了但没出帧"这一形**直接打出来** ——
          //   用户报"复用档切集黑屏"时，没有这条就只能靠猜（logConsole 关着时连 `模式=` 都没有 ☠）。
          //   判读：`ok=true` 但 时长/位置 都是 0 ⇒ **打开成功却不出帧**（= 复用档黑屏那一形）；
          //          `ok=false` ⇒ 属于"打不开"（票/网络/源），是另一类问题。
          if (AppSettings.i.logConsole && _reuseSwitch) {
            debugPrint('[PLAY] 复用取证 i=$i ok=$ok 时长=${kp.value.duration.inMilliseconds}ms '
                '位置=${kp.value.position.inMilliseconds}ms 缓冲=${kp.value.buffering} err=${kp.value.error} '
                '（时长/位置都 0 = 打开成功但没出帧 ⇒ 复用档黑屏）');
          }
          // ★ 2026-10-11（verify-4 #5）：**await 之后必须重判** —— 否则后面那段会继续操作一个已释放引擎
          if (kp.isDisposed) {
            _logDisposedSkip('源循环-试源后', '_initPlayerOnce:1527（await _openAndWait 之后）');
            return;
          }
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
                // ★ 2026-10-11（verify-4 #5）：seek 前后各判一次（await 期间可能被回收）
                if (kp.isDisposed) {
                  _logDisposedSkip('源循环-续播 seekExact 前', '_initPlayerOnce:1532');
                  return;
                }
                await kp.seekExact(to);
                if (kp.isDisposed) {
                  _logDisposedSkip('源循环-续播 seekExact 后', '_initPlayerOnce:1532（await 之后）');
                  return;
                }
                // 再校验一次：mpv 偶尔会把早期的 seek 丢掉，没跳过去就补一枪。
                // 3 秒的容差是给"视频刚开始播、位置还在往上走"留的余量。
                await Future<void>.delayed(const Duration(milliseconds: 500));
                if (kp.isDisposed) {
                  _logDisposedSkip('源循环-补枪前', '_initPlayerOnce:1540（500ms 等待之后）');
                  return;
                }
                if (mounted &&
                    kp.value.duration > Duration.zero &&
                    kp.value.position < to - const Duration(seconds: 3)) {
                  if (AppSettings.i.logConsole) debugPrint('[PLAY] seekExact 触发源=续播补枪(早期 seek 被丢掉) pos=${kp.value.position.inMilliseconds}ms → ${to.inMilliseconds}ms');
                  await kp.seekExact(to);
                  if (kp.isDisposed) {
                    _logDisposedSkip('源循环-补枪后', '_initPlayerOnce:1540（await 之后）');
                    return;
                  }
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
            // ★ 2026-10-11（verify-4 #5）：这个 await 之后也要判（下一轮还会用同一个 `kp`）
            if (kp.isDisposed) {
              _logDisposedSkip('源循环-刷新源后', '_initPlayerOnce:1560（await 刷新源之后）');
              return;
            }
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
    // ★ 2026-10-11（verify-4 #6）：**入口先判** —— 已释放就**不 add/remove listener**（ChangeNotifier 在
    //   dispose 之后 add/remove 会直接断言抛 "used after being disposed" ⇒ 那正是用户撞到的连锁起点）
    if (kp.isDisposed) {
      _logDisposedSkip('_openAndWait-入口(addListener)', '_openAndWait:1625');
      return false;
    }
    kp.addListener(listener);
    try {
      // ★ 2026-10-11（verify-4 #6）：`addListener` 与 `open` 之间/之后都可能被回收 ⇒ 开流前再判一次
      if (kp.isDisposed) {
        _logDisposedSkip('_openAndWait-open', '_openAndWait:1627（开流前）');
        return false;
      }
      // ★ probe32 A（只读、不阻塞）：HLS 源 ⇒ 顺手把清单事实打一行（变体数/段数/平均段长/首段字节）。
      //   ⚠️ **不 await**（fire-and-forget）⇒ 与开流并行、绝不影响起播时序 ✅；logConsole 关着时整段不存在 ✅
      if (AppSettings.i.logConsole && url.contains('.m3u8')) {
        unawaited(kp._logHlsFacts(url, {
          'User-Agent': _ua,
          'Referer': ref,
          ...?widget.httpHeaders,
        }));
      }
      await kp.open(url, httpHeaders: {
        'User-Agent': _ua,
        'Referer': ref,
        // ★ 2026-10-11（**可选头** ✅）：站点给的额外头（如柚子短剧的 `Cookie: eden_play_<videoId>=…` ✅）
        //   —— 放在 UA/Referer **之后** ⇒ 同名键以站点为准 ✅。
        //   ⚠️ `widget.httpHeaders` **就在这一刻现读**（每次 open 各读一次 ✅）—— 不在 init 缓存 ☑️
        //   ⇒ "刷新源拿到新凭证 ⇒ 下一轮 open 带新头" ✅；默认 null ⇒ 与改前**逐字同款**（只有两项）✅。
        ...?widget.httpHeaders,
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
      // ★ 2026-10-11（verify-4 #6）：已释放 ⇒ **跳过 removeListener**（否则又是一次 dispose 后断言）
      if (kp.isDisposed) {
        _logDisposedSkip('_openAndWait-removeListener', '_openAndWait:1652');
      } else {
        kp.removeListener(listener);
      }
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

  /// ★ 2026-10-11（**probe23/26 实测驱动** ✅）：**延迟回收**被替换下来的旧引擎。
  ///   为什么延迟（不立刻 shutdown）：切集是"**先挂新、再收旧**"—— 新的 `KpPlayer` + 新纹理先交给界面，
  ///   旧引擎还在屏上跑着最后一帧/最后几个回调 ⇒ 立刻收会闪黑、也容易和媒体库的 teardown 抢资源。
  ///   为什么必须收：每次切换都新建引擎（probe23/26 依据）⇒ 不收就是 native 泄漏（内存/解码器/网络连接）。
  ///   `_kpCreated`/`_kpRetired` 是**配对计数**（仅 logConsole 打开时打日志）：相等 ⇒ 没漏。
  void _retireKp(KpPlayer old) {
    final t0 = DateTime.now();
    if (AppSettings.i.logConsole) {
      debugPrint('[PLAY] 延迟回收排期 kp=${identityHashCode(old)}；条件=≥${_kRetireDelay.inMilliseconds}ms 且'
          '（新引擎已上屏 或 全屏已退出），最多等 ${_kRetireMaxWait.inSeconds}s');
    }
    // ★ 2026-10-11（**用户实测"全屏里切集 ⇒ 退不出全屏"** ⇒ 修法 **A**：全屏期间**不急着回收**）：
    //   原来的"固定 800ms 后 shutdown"留了个空窗 —— 全屏页/手势回调还攥着这个实例，
    //   800ms 之后它就成了"已释放引擎"⇒ 双击 seek 撞出 `used after being disposed` ⇒ 整条全屏路由卡死。
    //   ⇒ 改成**条件回收**：必须等到 (a) 新引擎**真的上屏**（`kpCurrent` 指向了别的实例 ⇒ 全屏页已跟随换新，
    //      见 `FullscreenPlayer.follow`/`_live`）**或** (b) 全屏已退出（`fullscreenOpen == false`，没人再攥它），
    //      二者之一成立才回收；另有 [_kRetireMaxWait] 硬上限兜底（绝不因为条件不成立而永久泄漏）。
    //   为什么选 A 而不是"只靠全屏页重建"：重建发生在**新引擎上屏那一刻**，切集与上屏之间有几秒空窗，
    //   只靠重建挡不住空窗里的手势/回调（用户就是这么撞上的）⇒ A 把空窗本身消掉，最稳。
    Timer.periodic(const Duration(milliseconds: 300), (t) {
      final el = DateTime.now().difference(t0);
      final newOnScreen = kpCurrent.value != null && !identical(kpCurrent.value, old);
      final fsClosed = !old.fullscreenOpen;
      final safe = el >= _kRetireDelay && (newOnScreen || fsClosed);
      if (!safe && el < _kRetireMaxWait) return; // 条件未满足 ⇒ 继续等（旧引擎仍然可用 ✓）
      t.cancel();
      final why = newOnScreen ? '新引擎已上屏' : (fsClosed ? '全屏已退出' : '超时兜底');
      // ★ 2026-10-11（**verify-4 R1**，复核点名"必须先修"）：**超时兜底那一支**原来会在
      //   "全屏中切集 + 新集取源一直失败"时把引擎收掉，而 `kpCurrent` 仍指着它 ⇒ 全屏页会**继续渲染
      //   已释放引擎的纹理**（那类异常不走手势路径，`_guardDead` 兜不住）。
      //   ⇒ shutdown **之前**：若通知口还指着它，就置空 —— 全屏页那边把"follow 变 null"当成"引擎已死"，
      //      立刻换成 [_FullscreenDeadExit]（下一帧自愈退出全屏），绝不会再拿它当活引擎用。
      if (identical(kpCurrent.value, old)) {
        kpCurrent.value = null;
        if (AppSettings.i.logConsole) {
          debugPrint('[PLAY] 兜底回收前把 kpCurrent 置空（原因=$why）⇒ 全屏页会自愈退出');
        }
      }
      unawaited(old.shutdown());
      if (identical(_lastEngine, old)) _lastEngine = null; // ★ 回收完成 ⇒ 手势回调不再引用它
      _kpRetired++;
      if (AppSettings.i.logConsole) {
        debugPrint('[PLAY] 延迟回收完成 kp=${identityHashCode(old)} 原因=$why（等了 ${el.inMilliseconds}ms）；'
            '创建=$_kpCreated 回收=$_kpRetired 在册=${_kpCreated - _kpRetired}');
      }
    });
  }

  void _attach(KpPlayer kp) {
    final old = _kp;
    // ★【常驻诊断】上屏换引擎：新 kp 身份 / 旧 kp 身份（旧的非空 ⇒ 下面立刻 shutdown ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] _attach 新kp=${identityHashCode(kp)} vc=${identityHashCode(kp.videoController)} 旧kp=${old == null ? '(无=首次上屏)' : identityHashCode(old).toString()} 旧kp会被shutdown=${old != null} 预建kp=${_prebuiltKp == null ? '(已交接)' : '仍持有'}');
    if (old != null) old.shutdown(); // ⚠️ 只有"首次上屏"会走到（切集那条已把旧引擎交给延迟回收 ⇒ old==null ✓）
    _kp = kp;
    _lastEngine = kp; // ★ 供切集空窗里的手势回调使用（见 [_lastEngine]）
    // ★ 2026-10-11：新引擎上屏 ⇒ **通知全屏页换纹理**（全屏页用 ValueKey(引擎身份) ⇒ State 重建 ✓）
    kpCurrent.value = kp;
    // ★ 重建时把"正在全屏"接过来（详情页 didPushNext 靠 kp.fullscreenOpen 区分"全屏"与"跳走" ✓）
    if (_inheritFullscreen) {
      kp.fullscreenOpen = true;
      _inheritFullscreen = false;
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 新引擎继承 fullscreenOpen=true（切集发生在上层是全屏时）');
    }
    kp.addListener(_onTick);
    // ★ 2026-10-11（用户规格第 4 条）：**新引擎上屏后必须重新下发倍速** —— 切集/换源/自愈/重试都是"重建引擎"，
    //   不补这一枪就会静默回到 1×（开关还显示 2× ⇒ 自相矛盾）。
    _applyRate('新引擎上屏后补下发');
    // ★ 状态/引擎已更新 ⇒ 踢一帧（防"状态变了没有帧来消化"，与 :639 那套同一修法 ✓）
    kickPlayerFrame();
    // ★ 2026-10-13：原来这里武装"首帧自愈"（9s 没首帧 ⇒ 再重建一次）—— **已按用户指令删除**（理由见字段区注释）
    // ★ 2026-10-11（A2 ✅）：新引擎上屏时把"重连中"同步给它（预建引擎阶段可能已经排着重试 ✓）
    _pushRetrying();
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
        setState(() => _setAutoRetrying(false));
      } else {
        _setAutoRetrying(false);
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
      // ★ 用户 2026-10-19：播完**没有下一集** ⇒ 中间显示「重播」—— 控件不能被 3 秒定时器藏掉，
      //   否则按钮跟着消失（"播完了什么也看不到"）。这里强制显示并取消隐藏排期。
      if (!(widget.switcher?.hasNext ?? false) && mounted) {
        // ★ 用户口径（2026-10-20）：**重播按钮不受控件显隐影响** —— 播完就一直显示；
        //   ⇒ 这里只重建一次让按钮出现，**不碰** `_controlsVisible` / 隐藏定时器
        //     （否则等于偷偷把控件也强制显示了，覆盖用户的隐藏操作 ✗）。
        setState(() {});
      }
    }
    // ★ 到结尾/播完：进度回调里比对「重播」显隐变化 ⇒ 立刻 setState（控件本来就可见时也要重建）
    final replayNow = _showReplay;
    if (replayNow != _replayShown && mounted) {
      _replayShown = replayNow;
      setState(() {});
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
          _setAutoRetrying(false);
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
    if (_autoRetrying) setState(() => _setAutoRetrying(false));
    _initPlayer();
  }

  /// ★ 2026-10-11（用户拍板 A2 ✅）：**`_autoRetrying` 的唯一写入口** ——
  ///   顺带把它同步到引擎上的 [KpPlayer.retrying]（全屏页只读那个值来决定"让位"✅）。
  ///   ⚠️ 别绕过本方法直接给 `_autoRetrying` 赋值 ☠（否则全屏那条提示会不同步）。
  void _setAutoRetrying(bool v) {
    _autoRetrying = v;
    _pushRetrying();
  }

  /// 把"重连中第几次"推给引擎侧（0 = 不在重试 ⇒ 全屏/内嵌都不显示角标 ✅）
  void _pushRetrying() {
    final kp = _kp;
    // ⚠️ `_kp` 还没上屏（预建引擎阶段）时不同步 ✅ —— `_attach` 里会补一次（见那边 ✓）
    if (kp == null) return;
    // ⚠️ 引擎已收（`shutdown()` 里连 notifier 一起 dispose 了）⇒ **绝不能再写它** ☠
    //    （同文件可见 `_disposed` ✓；否则会抛 "used after being disposed"）
    // ★ 2026-10-11（verify-4 #12）：改为同一口径的护栏 + 留痕（原来只静默 return）
    if (kp.isDisposed) {
      _logDisposedSkip('_pushRetrying-写 retrying', '_pushRetrying:1954');
      return;
    }
    final want = _autoRetrying ? _autoRetries : 0;
    if (kp.retrying.value == want) return;
    // ★ 2026-10-11（自己复核时补的护栏 ☠）：**不能在 build 期间直接写这个 notifier** ——
    //   本方法会被 `didUpdateWidget → _initPlayerOnce`（= build 阶段内的同步段）调到，
    //   而**全屏页**正监听着它（`ValueListenableBuilder`）⇒ 直接写会让它在 build 中
    //   markNeedsBuild ⇒ 触发断言 "setState() or markNeedsBuild() called during build" ☠。
    //   ⇒ 统一挪到**微任务**里写（帧末/事件循环下一拍都安全 ✓；角标出现晚一帧，肉眼无差）。
    Future<void>.microtask(() {
      if (kp._disposed) return;
      if (kp.retrying.value != want) kp.retrying.value = want;
    });
  }

  /// ★ 2026-10-11（用户拍板 B4 ✅）：**清掉"重连中"提示**（早退路径也要清 ☠）——
  ///   `_recover()` 的两条早退以前直接 `return`，提示会一直挂在屏上（直到位置恢复前进才撤）。
  void _clearRetryingHint() {
    if (!_autoRetrying) return;
    if (mounted) {
      setState(() => _setAutoRetrying(false));
    } else {
      _setAutoRetrying(false);
    }
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
      if (_autoRetrying) setState(() => _setAutoRetrying(false));
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
    setState(() => _setAutoRetrying(true));
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
    // ★ B4（2026-10-11）：作废也要**把"重连中"提示撤掉** ☠ —— 原来这里直接 return，
    //   提示会一直挂在屏上（位置本来就不动 ⇒ 连"恢复即撤"都等不到）。
    if ((widget.switcher?.index.value ?? 0) != _curIndex) {
      if (AppSettings.i.logConsole) debugPrint('[PLAY] _recover 作废（已切走）⇒ 清掉"重连中"提示');
      _clearRetryingHint();
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastRecoverMs < 10000) {
      // ★ B4（同上）：10 秒闸门挡下的这一次也要撤提示 ✓（否则提示长挂 ☠）
      if (AppSettings.i.logConsole) debugPrint('[PLAY] _recover 作废（距上次恢复 <10s）⇒ 清掉"重连中"提示');
      _clearRetryingHint();
      return;
    }
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

  /// 播完 + 没有下一集 ⇒ 播放器中间显示「重播」（用户 2026-10-19）。
  /// 单视频（`switcher == null`）也算"没有下一集"。
  /// ⚠️ 用户实测："进度到底了就该显示" —— 有些源**不报 completed**，所以位置到结尾
  ///   （400ms 容差）也算播完，不能死等 `completed` ☠
  bool get _showReplay {
    if (widget.switcher?.hasNext ?? false) return false;
    final kp = _kp;
    if (kp == null) return false;
    final v = kp.value;
    if (v.completed) return true;
    final d = v.duration;
    return d > Duration.zero &&
        v.position >= d - const Duration(milliseconds: 400);
  }

  /// 重播：回到 0 秒重新播（完成态随 playing 复位 ⇒ 按钮自动消失）
  Future<void> _replay() async {
    final kp = _kp;
    if (kp == null) return;
    try {
      await kp.seek(Duration.zero);
      await kp.play();
    } catch (_) {}
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
    // ★ 2026-10-11（verify-4 ③）：**推路由前判** —— 引擎已被回收就不要再推全屏（推上去也只会黑/卡）
    if (kp.isDisposed) {
      _logDisposedSkip('_openFullscreen-推全屏', '_openFullscreen:2140');
      return;
    }
    // ★ R1 配套：确保通知口**有值**（正常路径 `_attach` 已设过；这里只兜"万一"⇒ 免得 builder 一上来
    //   就走"哑页面自愈"把刚进的全屏弹掉）
    if (kpCurrent.value == null) kpCurrent.value = kp;
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
          pageBuilder: (_, __, ___) => ValueListenableBuilder<KpPlayer?>(
            // ★ 2026-10-11（**用户实测"全屏里切集黑"** ⇒ 本修法的核心）：
            //   切集 = 重建引擎 ⇒ **全屏页必须跟着换实例**（否则它握着已回收的引擎 ⇒ 全屏黑）。
            //   做法：监听 [kpCurrent]（`_attach` 里更新）；`ValueKey(引擎身份)` ⇒ 引擎一变、全屏页 State
            //   **整个重建**（`Video` 用的是新 `kp.videoController` ⇒ 新纹理 ✓；手势/进度条等内部
            //   `widget.player` 引用也一起指向新引擎 ⇒ 不会"纹理新、逻辑旧"）。
            //   ★ verify-4 R1：**`kpCurrent` 变 null 也是"引擎已死"的一种**（兜底回收置空）⇒ 这里必须
            //     换成一个"哑页面"去自愈退出，**不能**再回退到 push 时那个实例（它可能已被释放 ⇒ 渲染死纹理）。
            valueListenable: kpCurrent,
            builder: (_, cur, __) {
              if (cur == null || cur.isDisposed) {
                if (AppSettings.i.logConsole) {
                  debugPrint('[PLAY] 全屏 follow 为空/已释放 ⇒ 用哑页面自愈退出（verify-4 R1）');
                }
                return const _FullscreenDeadExit();
              }
              return FullscreenPlayer(
                // ⚠️ Key 用**对象本身**（`KpPlayer` 没重写 `==` ⇒ 按身份比较 ✓）——不用 `identityHashCode`
                //   （哈希理论上可碰撞 ⇒ 极小概率"换引擎但 Key 没变"⇒ 全屏继续用旧纹理 ☠）
                key: ValueKey<KpPlayer>(cur),
                player: cur,
                // ★ 2026-10-11（用户实测"退不出全屏"的修复）：把**当前引擎的通知口**传进去 ——
                //   全屏页里所有引擎操作都动态取它（`_live`），构造时那个实例被回收也不会再炸 ✓
                follow: kpCurrent,
                // ★ 2026-10-11（用户规格第 2 条）：把**同一份倍速状态**交给全屏页 ⇒ 内嵌/竖版/横版一套控件 ✅
                rate: rateNotifier,
                vertical: vertical,
                switcher: widget.switcher,
                title: widget.title,
                epLabels: widget.epLabels,
                // ★ 下载：控制条那颗按钮（只下当前这一集）+ 三态；全屏页直接复用内嵌那份回调/状态
                onDownload: widget.onDownloadCurrent,
                downloadStatus: widget.downloadStatus,
              );
            },
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
      // ★ 2026-10-11：复位目标改为**当前引擎**（全屏期间可能已重建过 ⇒ push 时那个实例可能已被回收，
      //   只复位它 ⇒ 新引擎的 fullscreenOpen 会永远为 true ⇒ 以后所有"跳走"都不停播 ☠）
      final cur = kpCurrent.value ?? kp;
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 全屏 退出：whenComplete 复位前 fullscreenOpen=${cur.fullscreenOpen} 引擎已shutdown=${cur._disposed}');
      cur.fullscreenOpen = false;
      // ★【常驻诊断】复位**后**的值（应与上面那条配对看 ✓）
      if (AppSettings.i.logConsole) debugPrint('[PLAY] 全屏 退出：whenComplete 复位后 fullscreenOpen=${cur.fullscreenOpen}');
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
      // ⚠️ 2026-10-19（用户实测 Windows 卡/未响应）：这里原来**每次 build 都 debugPrint**
      //   （播放时 ~10 次/秒，滚动/切控件时更多）—— debug 下 debugPrint 同步写 stdout，
      //   高频时直接拖慢主线程。⇒ 删掉这条"视频层重建"日志（排障已结束，要查时再加）。
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
                    // 长按快进：任意位置按住 = 2 倍速；**松手恢复到"当前开关状态"**（1× 或 2×）
                    // ★ 2026-10-11（用户规格坑 1）：原来硬编码回 1.0 ⇒ 用户把开关拨到 2× 后长按一次
                    //   就被降回 1×（与开关自相矛盾）⇒ 现在读 `rateNotifier.value` 恢复。
                    onLongPressStart: (_) {
                      // ★【常驻诊断】长按开始 = 2 倍速（触发源=长按 ✓）
                      if (AppSettings.i.logConsole) debugPrint('[PLAY] 长按开始 触发源=长按(内嵌) ⇒ setRate(2.0) 位置=${_kp?.value.position.inMilliseconds ?? 0}ms');
                      _kp?.setRate(2.0);
                      setState(() => _longPressing = true);
                    },
                    onLongPressEnd: (_) {
                      final back = rateNotifier.value;
                      // ★【常驻诊断】长按结束 = 恢复到"当前开关状态"
                      if (AppSettings.i.logConsole) debugPrint('[PLAY] 长按结束 触发源=松手(内嵌) ⇒ setRate(${back == 2.0 ? '2.0' : '1.0'})（回到开关状态）位置=${_kp?.value.position.inMilliseconds ?? 0}ms');
                      _kp?.setRate(back);
                      if (_longPressing) setState(() => _longPressing = false);
                    },
                    onLongPressCancel: () {
                      final back = rateNotifier.value;
                      // ★【常驻诊断】长按被取消（手势被抢）⇒ 同样恢复到"当前开关状态"
                      if (AppSettings.i.logConsole) debugPrint('[PLAY] 长按取消 触发源=手势取消(内嵌) ⇒ setRate(${back == 2.0 ? '2.0' : '1.0'})（回到开关状态）');
                      _kp?.setRate(back);
                      if (_longPressing) setState(() => _longPressing = false);
                    },
                    child: _videoSurface(kp),
                  ),
                  // ★ 2026-10-11（用户新规格）：**倍速按钮** —— 贴右缘、垂直居中；
                  //   **跟随"控件可见"一起显隐**（复用既有 `_controlsVisible`，**不新造计时器**）；
                  //   只接管点击（见 [_rateButton] 说明）⇒ 不吃双击/滑动/单击手势。
                  if (_controlsVisible)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8), // 贴边安全间距
                        child: _rateButton(rateNotifier),
                      ),
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
                  // 播放出错：★ 2026-10-11（用户拍板 A2 ✅）**重试期间 UI 静默** ——
                  //   只留右上角一个**不闪的小角标**（`重连中 n/5`），**不再**在屏幕中央摆
                  //   `播放出错，自动重试 n/5…` 那种大提示（原来那版会随排期/重开一显一隐地闪 ✗）。
                  //   ⚠️ 用户拍板（2026-10-01）那条不变：5 次都失败后**不再显示「点此重试」**
                  //      （见下面 `else if (_error != null)` 分支只用于"这集本身没有/坏了"的中文说明 ✓）。
                  //   ⚠️ 日志一字未动（`logConsole` 那套照旧）✅ —— 只是 UI 静默 ✅。
                  if (_autoRetrying)
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: _RetryBadge(attempt: _autoRetries),
                      ),
                    )
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
                    )
                  else if (_showReplay)
                    // ★ 用户 2026-10-19：播完 + 没有下一集 ⇒ 中间「重播」（点了从头播）
                    Center(child: kReplayButton(_replay)),
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
                            // ★ 下载：控制条 ↓ 那颗（内嵌时在竖版全屏左边）
                            onDownload: widget.onDownloadCurrent,
                            downloadStatus: widget.downloadStatus,
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
  /// ★ 2026-10-11（用户拍板 A2 ✅）：**重试期间不摆大字/按钮** —— `_autoRetrying` 为真时
  ///   只留右上角的小角标（`重连中 n/5` ✓），海报+转圈照旧（用户看得出在加载 ✅）。
  Widget _coverArea() {
    if (_error != null && !_autoRetrying) {
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
        // A2：重试中的小角标（不闪 ✅ —— 没有转圈、不占屏幕中央）
        if (_autoRetrying)
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: _RetryBadge(attempt: _autoRetries),
            ),
          ),
      ],
    );
  }

  // ★ 2026-10-11（A2 ✅）：原来的 `_autoRetryHint()`（屏幕中央"播放出错，自动重试 n/5…"）
  //   **已删** —— 它带转圈（会闪）+ 占屏幕中央（"经常弹"的观感来源之一）。
  //   现在统一用右上角的 `_RetryBadge`（见文件底部那个小部件 ✓）。

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
/// 播放器中间的「重播」按钮（用户 2026-10-19）：
/// 触发条件 = **播完 + 没有下一集**（单视频也算）。内嵌 / 竖版全屏 / 横版全屏共用这一个。
/// 点击 = 回到 0 秒重新播放（`completed` 随播放复位，按钮自动消失）。
Widget kReplayButton(Future<void> Function() onTap) {
  return GestureDetector(
    onTap: () => onTap(),
    behavior: HitTestBehavior.opaque,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.replay, color: Colors.white, size: 34),
          SizedBox(height: 4),
          Text('重播', style: TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    ),
  );
}

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

  /// ★ 下载（用户要求）：控制条上那颗 ↓ 按钮（null = 不显示）。
  /// 位置固定在**时间文本之后 / 竖版全屏按钮之前**：内嵌时紧挨竖版全屏左边；
  /// 全屏页（`showFullscreen=false`）时它就是最右那颗 = 右下角。
  final VoidCallback? onDownload;

  /// 当前这一集的下载态：'none' / 'downloading' / 'done'
  final String downloadStatus;

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
    this.onDownload,
    this.downloadStatus = 'none',
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
                    // ★ 下载（用户要求）：时间文本之后、竖版全屏之前 ——
                    //   内嵌 = 紧挨竖版全屏左边；全屏页 = 最右（右下角）✅
                    //   三态：没下过 = download / 下载中 = downloading / 已下好 = download_done
                    //   ⚠️ 只有 'none' 可点（已下好/正在下再点没有意义，也避免重复入队）
                    if (widget.onDownload != null)
                      _barBtn(
                        icon: switch (widget.downloadStatus) {
                          'done' => Icons.download_done,
                          'downloading' => Icons.downloading,
                          _ => Icons.download,
                        },
                        enabled: widget.downloadStatus == 'none',
                        onPressed: widget.onDownload,
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
/// ★ 2026-10-11（**verify-4 R1**）：全屏页的"**哑页面**" —— 当 `kpCurrent` 变 `null`（引擎被兜底回收）
///   或它已释放时，`_openFullscreen` 的 builder 用它顶上：**完全不引用任何引擎**，
///   只在下一帧把这条路由弹回去（自愈）。为什么不用"回退到 push 时的实例"：那个实例此时很可能已被释放
///   ⇒ 会继续渲染**已释放引擎的纹理**（用户实报那类异常不走手势路径 ⇒ `_guardDead` 兜不住）。
class _FullscreenDeadExit extends StatefulWidget {
  const _FullscreenDeadExit();

  @override
  State<_FullscreenDeadExit> createState() => _FullscreenDeadExitState();
}

class _FullscreenDeadExitState extends State<_FullscreenDeadExit> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Colors.black, child: SizedBox.expand());
}

class FullscreenPlayer extends StatefulWidget {
  final KpPlayer player;
  final bool vertical;

  /// 篇内切换状态（与内嵌播放器共用同一份，取实时值）
  final VideoSwitcher? switcher;

  /// 顶部标题（可为空 = 不画标题，只留返回键）——竖版全屏/横屏全屏都走这个页面 ✅
  final String title;

  /// 各集标签（与详情页选集同一份；下标同 `switcher.index`）。多集时全屏标题带"第 N 集" ✅
  final List<String> epLabels;

  /// ★ 2026-10-11（**用户实测"全屏里切集 ⇒ 退不出全屏"** 的修复）：**当前引擎的实时通知口**。
  ///   切集 = 重建引擎（probe23/26 依据）⇒ 全屏页**构造时捕获的那个实例会被延迟回收**，
  ///   而手势/双击/长按这些回调仍挂在旧 State 上 ⇒ 打到已释放引擎 ⇒ 媒体库抛
  ///   `A KpPlayer was used after being disposed.` ⇒ 串发框架异常 ⇒ **整条全屏路由卡死**（用户实报）。
  ///   ⇒ 现在全屏页**每次都动态取**（见 `_live`）：`follow`（= `kpCurrent`）有新引擎就用新的。
  final ValueListenable<KpPlayer?>? follow;
  /// ★ 2026-10-11（**用户规格**）：**常驻倍速开关的共享状态**（与内嵌播放器同一份 ⇒ 哪边点都同步）。
  ///   null = 老调用方/降级场景 ⇒ 全屏页退化为"只有长按 2×"的老行为 ✅。
  final ValueNotifier<double>? rate;

  /// ★ 下载（用户要求）：控制条上的「下载」按钮 —— 下当前这一集（null = 不显示）
  final VoidCallback? onDownload;

  /// 当前这一集的下载态：'none' / 'downloading' / 'done'（只决定图标 + 是否可点）
  final String downloadStatus;

  const FullscreenPlayer({
    super.key,
    required this.player,
    this.vertical = false,
    this.switcher,
    this.title = '',
    this.epLabels = const [],
    this.follow,
    this.rate,
    this.onDownload,
    this.downloadStatus = 'none',
  });

  @override
  State<FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<FullscreenPlayer>
    with _SwipeSeek, _BrightnessVolume {
  bool _controls = true;

  /// 播完 + 没有下一集 ⇒ 中间显示「重播」（用户 2026-10-19）。
  /// ⚠️ **保留**原来"播完且无下一集 ⇒ 自动退全屏"的逻辑（用户明确要求不改成全屏卡住）；
  ///    万一用户仍停在全屏（没触发退出/手动再进全屏），这里也能看到重播按钮。
  bool get _showReplay {
    if (widget.switcher?.hasNext ?? false) return false;
    final v = widget.player.value;
    if (v.completed) return true;
    final d = v.duration;
    return d > Duration.zero &&
        v.position >= d - const Duration(milliseconds: 400);
  }

  Future<void> _replay() async {
    try {
      await widget.player.seek(Duration.zero);
      await widget.player.play();
    } catch (_) {}
  }
  /// ★ 2026-10-11（verify-4 #21/#22）：本页**是否真的**给引擎挂了 `_onTick` —— 与 `dispose` 成对，
  ///   避免"没挂成却在 dispose 里摘"（摘一个已 dispose 的 notifier 会断言抛）。
  bool _fsListening = false;
  /// ★ 2026-10-11（**verify-4 R3**）：`_guardDead` 的**幂等标志** —— 同帧被调多次时只排一次退场，
  ///   否则会连弹两层路由（把详情页也弹掉）。
  bool _popping = false;
  /// ★ 2026-10-11（用户规格）：本页是否挂了倍速监听（与 `dispose` 成对；`widget.rate` 可能为 null）
  bool _rateListening = false;

  /// 开关变化（或进全屏时）⇒ 把当前倍速下发到**本页当前活着的引擎**（`_live`）。
  ///   ⚠️ 走 `_live` 而不是构造实例（切集重建后构造实例可能已被回收，见 verify-4 那批护栏）。
  void _onRateChangedFs() {
    final n = widget.rate;
    if (n == null) return;
    final kp = _live;
    if (kp.isDisposed) return;
    unawaited(kp.setRate(n.value));
    if (AppSettings.i.logConsole) {
      debugPrint('[PLAY] 全屏 倍速 ⇒ ${n.value == 2.0 ? '2.0' : '1.0'}×（开关同步/进全屏）');
    }
  }
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
  // ★ 2026-10-11（verify-4 R2）：可空 —— 已释放 ⇒ 返回 null（调用点 `?.` 跳过），不再把死引擎交出去
  KpPlayer? get gesturePlayer => _live.isDisposed ? null : _live;

  @override
  KpPlayer? get swipePlayer => _live.isDisposed ? null : _live; // ★ R2：同 gesturePlayer

  /// ★ 2026-10-11（用户实测"退不出全屏"的修复）：**当前活着的引擎** ——
  ///   `follow`（`kpCurrent`，`_attach` 里随新引擎更新）优先；没有/已释放 ⇒ 退回构造时的实例。
  ///   ⚠️ 所有引擎操作都必须走这里，**不许**直接用 `widget.player`（那正是事故点：旧实例被回收后还在收手势）。
  KpPlayer get _live {
    final f = widget.follow?.value;
    if (f != null && !f.isDisposed) return f;
    return widget.player;
  }

  /// 引擎是否已失效（切集空窗：旧的已收、新的还没上屏）⇒ 操作一律忽略 + **自愈弹回**，
  /// 绝不再让 `used after disposed` 把整条路由带崩（用户实报"退不出全屏"）。
  bool _guardDead() {
    if (!_live.isDisposed) return false;
    // ★ 2026-10-11（**verify-4 R3**）：**幂等** —— 同一个帧里可能被调两次（例如双击先判一次、
    //   接着长按/手势又判一次）⇒ 两个 post-frame `maybePop` 会**连弹两层**（把详情页也弹掉 ☠）。
    if (_popping) return true;
    _popping = true;
    if (AppSettings.i.logConsole) {
      debugPrint('[PLAY] ⚠️ 全屏：当前引擎已释放（切集空窗）⇒ 忽略本次操作 + 自动退出全屏（防卡死）');
    }
    // 自愈：把全屏路由弹回去（用户可以在窗口内继续操作；比"卡死在全屏"好得多）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
    return true;
  }

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
    // ★ 2026-10-11（verify-4 #21/#22）：**成对护栏** —— 引擎若已被回收（切集空窗撞上"进全屏"），
    //   既不 `autoResume()` 也不 `addListener`（ChangeNotifier 在 dispose 后两者都会断言抛）；
    //   `_fsListening` 记住"到底挂没挂" ⇒ `dispose` 里据此决定要不要 `removeListener`（成对 ✅）。
    if (widget.player.isDisposed) {
      _logDisposedSkip('全屏 initState-autoResume/addListener', '_FullscreenPlayerState.initState:2711');
    } else {
      widget.player.autoResume();
      widget.player.addListener(_onTick);
      _fsListening = true;
    }
    // ★ 2026-10-11（用户规格第 2/4 条）：全屏页也要**跟随同一个倍速状态** ——
    //   进全屏先按当前值下发一次（万一引擎是刚重建的）；之后开关一变就再下发（见 [_onRateChangedFs]）。
    widget.rate?.addListener(_onRateChangedFs);
    _rateListening = true;
    _onRateChangedFs();
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
    if (s == AnimationStatus.reverse) {
      _restoreOrientation();
    }
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
    // ★ 2026-10-11（verify-4 #22）：**成对** —— 只有真挂过（`_fsListening`）且实例还活着才摘；
    //   否则摘一个已 dispose 的 notifier 同样会断言（见 initState 那段的说明）
    if (_fsListening) {
      if (widget.player.isDisposed) {
        _logDisposedSkip('全屏 dispose-removeListener', '_FullscreenPlayerState.dispose:2699');
      } else {
        widget.player.removeListener(_onTick);
      }
    }
    _routeAnim?.removeStatusListener(_onRouteAnimStatus);
    // ★ 2026-10-11（用户规格）：摘掉倍速监听（与 initState 成对；notifier 本体归内嵌页，**不要 dispose**）
    if (_rateListening) {
      widget.rate?.removeListener(_onRateChangedFs);
      _rateListening = false;
    }
    // 兜底：退出路径都已在触发时恢复过，这里再保一次
    _restoreOrientation();
    super.dispose();
  }

  bool _errShown = false;
  bool _endHandled = false; // 本段播完是否已处理（换集后自动重置）

  /// 「重播」按钮是否显示中（变化时 setState —— 否则点重播后 completed 变 false 但界面不重建，按钮不消失 ☠）
  bool _replayShown = false;

  void _onTick() {
    if (!mounted) return;
    final v = _live.value; // ★ 动态取当前引擎（切集后 follow 立刻给新引擎 ⇒ 不再读到已回收实例）
    if (v.error != _errShown) setState(() => _errShown = v.error);
    // ★ 用户 2026-10-20（改）：**播完不再自动退出全屏** —— 由用户手动退出。
    //   原因（🛢️ 实测）：切集瞬间 `completed`/`_endHandled` 的时序会把新集误判成
    //   "播完且无下一集" ⇒ 自动 pop ⇒ "自动下一集会退出全屏" ☠。
    //   删掉 pop 后，全屏只由用户操作退出（返回键/下滑/双击/系统手势）；
    //   自动连播（`switcher.next()`）在 PlayerWidget 那边处理，这里不动。
    if (v.completed) {
      if (!_endHandled) {
        _endHandled = true;
        if (AppSettings.i.logConsole) {
          debugPrint('[PLAY] 全屏 播完 有下一集=${widget.switcher?.hasNext ?? false} '
              '${(widget.switcher?.hasNext ?? false) ? '⇒ 等自动切下一集（保持全屏）' : '⇒ 停在全屏（不自动退出，等用户手动退）'}');
        }
      }
    } else {
      _endHandled = false;
    }
    // ★ 用户 2026-10-20（实测：点了重播按钮还在）：`_onTick` 原来只在 completed 分支动状态、
    //   且**没有 setState** ⇒ 重播后（completed=false / 位置回 0）全屏 UI 不重建 ⇒ 按钮不消失 ☠
    final rs = _showReplay;
    if (rs != _replayShown) {
      _replayShown = rs;
      if (mounted) setState(() {});
    }
  }

  /// 双击：左三成退、右三成进（步长来自设置）、**中间暂停/播放**
  void _onDoubleTap() {
    if (_guardDead()) return; // ★ 用户事故点：这次双击原本会打到"已回收引擎" ⇒ 撞出 used-after-disposed ⇒ 全屏卡死
    final e = _live; // ★ 动态取当前引擎（不用构造时捕获的实例）
    final w = context.size?.width ?? MediaQuery.of(context).size.width;
    final dx = _lastTapPos.dx;
    // ★【常驻诊断】双击落点判定(全屏)：dx + 屏宽 + 区域（左半退 / 中间暂停播放 / 右半进 ✓）
    if (AppSettings.i.logConsole) debugPrint('[PLAY] 双击(全屏) dx=${dx.toStringAsFixed(1)} w=${w.toStringAsFixed(1)} 区域=${dx > w * 0.35 && dx < w * 0.65 ? '中间' : (dx < w / 2 ? '左半' : '右半')} 步长=${AppSettings.i.step}s 引擎playing=${e.value.playing} pos=${e.value.position.inMilliseconds}ms 引擎=#${identityHashCode(e)}');
    if (dx > w * 0.35 && dx < w * 0.65) {
      if (e.value.playing) {
        if (AppSettings.i.logConsole) debugPrint('[PLAY] 暂停 触发源=双击中间(全屏)');
        e.pause();
        _flashTapHint(Icons.pause, 0);
      } else {
        if (AppSettings.i.logConsole) debugPrint('[PLAY] 播放 触发源=双击中间(全屏)');
        e.play();
        _flashTapHint(Icons.play_arrow, 0);
      }
      return;
    }
    final back = dx < w / 2;
    final secs = AppSettings.i.step;
    if (AppSettings.i.logConsole) debugPrint('[PLAY] seek 触发源=双击${back ? '左半(退)' : '右半(进)'}(全屏) 从=${e.value.position.inMilliseconds}ms 步长=${secs}s');
    e.seek(e.value.position + Duration(seconds: back ? -secs : secs));
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

  /// 顶部标题行（用户选定「甲」方案 ✅）：
  ///   ① 有标题 + 多集 ⇒ `[标题 Flexible ⇒ 可压缩/超长省略] 6 [集号 Text ⇒ 固定、绝不省略]`
  ///   ② 标题为空 + 多集 ⇒ **只有集号**（左对齐、样式同上 ✅ —— 标题那一格根本不生成 ✅）
  ///   （③ 空标题 + 单集/电影 = 整块不画，判据在调用点 `if (widget.title.isEmpty && !_multiEp)` ✅）
  /// ★ 显隐不受这里管：外层就是 `if (_controls)`（那个**唯一真源** ✅），本方法只管"画什么" ✅。
  /// ★ 换集实时更新：直接监听详情页那份 `switcher.index`（**同一份真源** ✅，不另起状态/定时器 ✅）。
  Widget _titleRow() {
    final sw = widget.switcher;
    if (sw == null) return _titleRowLine(0); // 没有切换状态 ⇒ 单条（无集号）✅
    return ValueListenableBuilder<int>(
      valueListenable: sw.index,
      builder: (_, i, __) => _titleRowLine(i),
    );
  }

  Widget _titleRowLine(int i) {
    final ep = _epText(i);
    final hasTitle = widget.title.isNotEmpty;
    return Row(
      children: [
        // 标题：空标题 ⇒ 这一格**不生成**（不留 0 宽占位、也不留多余间距）✅
        if (hasTitle) Flexible(child: _titleLine(widget.title)),
        if (ep != null) ...[
          if (hasTitle) const SizedBox(width: 6), // 只有"标题 + 集号"之间才要那条间距 ✅
          // 集号：**非** Flexible ⇒ 拿自己的固有宽度、不参与省略 ✅（标题超长时先压标题）
          Text(ep, maxLines: 1, softWrap: false, style: _titleStyle),
        ],
      ],
    );
  }

  /// 多集（本篇视频数 > 1）⇒ 集号该显示；单集/电影 ⇒ 不显示 ✅
  ///   ⚠️ `total` 是详情页那份 `VideoSwitcher` 上的**共享**字段（换源刷新时会更新 `detail_page.dart:479`）
  bool get _multiEp => (widget.switcher?.total ?? 0) > 1;

  /// "标签长得像集号"的判据（用户拍板 ✅）：形如 `第 5 集` / `第5集`（中间允许空白）——
  ///   ⚠️ **只认这一种写法**：站点里目前只有黄果/野果产这种真集号标签（`sites/huangguo.dart:508/519`、
  ///   `sites/yeguodj.dart:517`）；其余站的标签是**视频标题型**（`视频` / `视频 2` / 子标题 / 文章标题）
  ///   ⇒ 用序号。发现别的"真集号"写法**先报再改**，不许自己扩正则 ☠
  static final _epLabelRe = RegExp(r'^第\s*\d+\s*集$');

  /// 集号文本：多集才有（单集/电影 ⇒ null ⇒ **不显示集号** ✅，行为不变）
  ///   ★ 用户拍板：标签**长得像集号** ⇒ **保留标签原文**（页面从"第 5 集"起也对 ✅）；
  ///     标签不是集号形态（视频标题型）或**为空 / 下标越界** ⇒ 改用**序号** `第 ${i + 1} 集`（1-based）✅
  ///   ⚠️ 本方法只喂全屏标题；详情页选集胶囊仍原样显示 `ArticleVideo.label`（一个字没动 ✅）
  String? _epText(int i) {
    if (!_multiEp) return null;
    final labels = widget.epLabels;
    final raw = (i >= 0 && i < labels.length) ? labels[i].trim() : '';
    if (_epLabelRe.hasMatch(raw)) return raw; // 真集号形态 ⇒ 原文（含前后空白已 trim 掉）✅
    return '第 ${i + 1} 集'; // 视频标题型标签 / 空 / 越界 ⇒ 序号 ✅
  }

  /// 标题与集号共用同一套 HUD 样式（白字 + 轻投影，两处必须是同一份 ⇒ 视觉不割裂 ✅）
  static const _titleStyle = TextStyle(
    color: Colors.white,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    shadows: [
      Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black87),
    ],
  );

  Widget _titleLine(String text) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _titleStyle,
      );

  @override
  Widget build(BuildContext context) {
    final kp = _live; // ★ 动态取当前引擎（全屏里切集后画面立刻跟到新纹理 ✓）
    // ★【常驻诊断·关键】视频层重建可见性(全屏)：与内嵌那条同一个 kp/vc 身份 ⇒ 只是重建、没换引擎 ✓
    //   （`_bvShow == null` 是日志自己的过滤：上下滑亮度/音量时每帧 setState，会逐帧刷屏 ✓ 见内嵌那段说明）
    if (AppSettings.i.logConsole && _bvShow == null) {
      debugPrint('[PLAY] 视频层重建(全屏) kp=${identityHashCode(kp).toString()} vc=${identityHashCode(kp.videoController).toString()} playing=${kp.value.playing} buffering=${kp.value.buffering} completed=${kp.value.completed} pos=${kp.value.position.inMilliseconds}ms 首帧到=${kp.value.started} 控件可见=$_controls vertical=${widget.vertical}');
    }
    return Scaffold(
      backgroundColor: Colors.black,
      // ★ 2026-10-11（**修法 A**，用户已批准）：外层再套一层 `Stack`，把**倍速按钮挪成下面这个 GestureDetector 的
      //   **兄弟层**（与内嵌同构）—— `Stack` 命中测试**从后往前、命中即截断** ⇒ 点在按钮上时，
      //   下面那个大 GestureDetector（注册了 `onTap`/`onDoubleTap`/拖动/长按）**根本不参与**这次点击的竞技场
      //   ⇒ 不再等"双击识别器占场（Flutter `kDoubleTapTimeout` ≈300ms）" ⇒ 手感与内嵌一致 ✅。
      //   ⚠️ 下面 GestureDetector 的注册项**一行未动**（双击跳 / 下滑音量亮度 / 边缘返回 / 长按 2× 原样 ✅）；
      //   ⚠️ 按钮仍在**视频之上**；它与顶/底栏**几何上不重叠** ⇒ 绘制顺序的细微变化无视觉差 ✅
      //   （⚠️ 最小改动：内层大块的缩进**未重排**，避免无谓 diff）
      body: Stack(
        children: [
          GestureDetector(
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
          if (AppSettings.i.logConsole) debugPrint('[PLAY] 长按开始 触发源=长按(全屏) ⇒ setRate(2.0) 位置=${_live.value.position.inMilliseconds}ms');
          if (_guardDead()) return;
          _live.setRate(2.0);
          setState(() => _longPressing = true);
        },
        onLongPressEnd: (_) {
          // ★ 2026-10-11（用户规格坑 1）：恢复到"**当前开关状态**"（1× 或 2×），不再硬编码 1.0
          final back = widget.rate?.value ?? 1.0;
          // ★【常驻诊断】长按结束 = 回到开关状态
          if (AppSettings.i.logConsole) debugPrint('[PLAY] 长按结束 触发源=松手(全屏) ⇒ setRate(${back == 2.0 ? '2.0' : '1.0'})（回到开关状态）位置=${_live.value.position.inMilliseconds}ms');
          _live.setRate(back); // setRate 自带"已释放 ⇒ 忽略"护栏（见 KpPlayer.setRate）✓
          if (_longPressing) setState(() => _longPressing = false);
        },
        onLongPressCancel: () {
          final back = widget.rate?.value ?? 1.0;
          // ★【常驻诊断】长按被取消（手势被抢）⇒ 同样回到开关状态
          if (AppSettings.i.logConsole) debugPrint('[PLAY] 长按取消 触发源=手势取消(全屏) ⇒ setRate(${back == 2.0 ? '2.0' : '1.0'})（回到开关状态）');
          _live.setRate(back);
          if (_longPressing) setState(() => _longPressing = false);
        },
        child: Stack(
          children: [
            Center(child: _videoSurface(kp)),
            // ★ 用户 2026-10-19：播完 + 没有下一集 ⇒ 中间「重播」按钮
            //   （kReplayButton 自带 GestureDetector，会在手势竞技场赢过外层单击 ⇒ 点它不会误触发控件切换）
            if (_showReplay) Center(child: kReplayButton(_replay)),
            // ★ 2026-10-11（修法 A）：**倍速按钮已从此处移出** —— 原来它在这个 Stack 里 ⇒ 等于挂在
            //   大 GestureDetector（上面那个）**子树内** ⇒ 点击要跟 `onTap`/`onDoubleTap` 抢竞技场 ⇒ 慢。
            //   现在它搬去**外层 Stack**、作为那个 GestureDetector 的**兄弟层**（见本 build 末尾）。
            // 顶部：返回 + 视频标题
            // ★ 用户要求（2026-10）：两种全屏（竖版/横屏）顶部都显示标题，且**跟随控件一起显隐** ——
            //   本块整体挂在既有的 `_controls` 上 ✅（与返回键、底部控制条**同一套**状态、同一个 3 秒
            //   计时器/单击切换 ☑️）⇒ 不新增任何定时器、不新增任何状态 ✅；
            //   ⚠️ 内嵌播放器不显示标题（那边一个字没动 ✅）。
            if (_controls) ...[
              // 轻量渐变遮罩：只为标题可读性（纯装饰 ⇒ IgnorePointer 包住，绝不抢触摸/手势 ✅）
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    // 高度 = 顶部安全区 + 标题行高（避开刘海/状态栏）
                    height: MediaQuery.paddingOf(context).top + 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.62),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
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
                    const SizedBox(width: 8),
                    // 顶部标题行（用户选定「甲」方案）：标题可伸缩 + **集号独立、不参与省略** ✅
                    //   ① 有标题 + 多集 ⇒ 标题 + 集号；② 标题为空 + 多集 ⇒ **只有集号**（左对齐）✅；
                    //   ③ 标题为空 + 单集/电影 ⇒ 什么都不画（保持原样 ✅）
                    if (widget.title.isEmpty && !_multiEp)
                      const Expanded(child: SizedBox())
                    else
                      Expanded(child: _titleRow()),
                    const SizedBox(width: 14),
                  ],
                ),
              ),
            ],
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
            // 播放出错提示 / 重连中（★ 2026-10-11 用户拍板 A2 ✅：**重试期间让位**）——
            //   原来这里只看 `_errShown`（= `kp.value.error`）⇒ 自动重试**进行中**也照样显示
            //   "播放出错，请返回重试"大提示，而每次重试重开都会把它清掉、再失败又出现
            //   ⇒ 用户看到的就是"提示反复弹"（内嵌那侧早就有 `_autoRetrying` 让位，全屏没有 ✗）。
            //   现在：读引擎上的 `kp.retrying`（A2 新增，见 [KpPlayer.retrying]）——
            //     >0 ⇒ 只显示右上角/安全区下的小角标「重连中 n/5」（不闪 ✅）；
            //     =0 且仍出错 ⇒ 才显示原来那句大提示 ✅。
            ValueListenableBuilder<int>(
              valueListenable: kp.retrying,
              builder: (_, retrying, __) {
                if (retrying > 0) {
                  return Positioned(
                    // 落在顶部标题行**下方**，避免和标题/集号挤在一起 ✅
                    top: MediaQuery.paddingOf(context).top + 56,
                    right: 12,
                    child: _RetryBadge(attempt: retrying),
                  );
                }
                if (!_errShown) return const SizedBox.shrink();
                return const Center(
                  child: Text('播放出错，请返回重试',
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                );
              },
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
                          // ★ 下载：全屏页同样有这颗（最右 = 右下角）
                          onDownload: widget.onDownload,
                          downloadStatus: widget.downloadStatus,
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
                          // ★ 下载：全屏页同样有这颗（最右 = 右下角）
                          onDownload: widget.onDownload,
                          downloadStatus: widget.downloadStatus,
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
          // ★ 2026-10-11（**修法 A**）：**倍速按钮 = 大 GestureDetector 的兄弟层**（与内嵌 `:2389-2395` 同构）——
          //   位置/尺寸/间距/显隐条件**逐字保持**（贴右缘 `right:10`、42×42、`_controls` 一起显隐）；
          //   它仍是**最后一个 child** ⇒ 画在最上层（下方是视频）⇒ 与顶/底栏不重叠、无视觉差 ✅；
          //   命中落在它身上时**截断** Stack 反向命中 ⇒ 下面那个 GestureDetector 不参与竞技场 ✅。
          if (widget.rate != null && _controls)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 10), // 与原来完全一致
                child: _rateButton(widget.rate!),
              ),
            ),
        ],
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

/// ★ 2026-10-11（用户拍板 A2 ✅）：**"重连中 n/5"小角标** —— 自动重试期间**唯一**的 UI 提示。
/// 为什么这么简：用户反馈"重试提示经常弹" ⇒ 重试期间**不闪、不占屏幕中央**（没有转圈动画 ✅、
/// 也不会随排期/重开一显一隐地更替大段文字 ✗），只在角落留一行小字 ✅。
/// 内嵌播放器（视频区右上角）与全屏页（顶部安全区下方）**共用同一个部件** ✅。
class _RetryBadge extends StatelessWidget {
  /// 当前是第几次（1..5）；调用方只在 >0 时显示它
  final int attempt;
  const _RetryBadge({required this.attempt});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('重连中 $attempt/5',
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      );
}
