/// KPXX · Windows 桌面 dev —— **内存泄漏补测探针**（2026-10-10 补测轮 ✓ dev-only）
///
/// 用途：给"桌面 dev 构建"补测六块里**需要驱动 UI** 的三块（正片播放循环 / AVIF 重复解码 /
///   首页滚动），外加"长播 / 冷启动 / Dart 堆"的外部采样配合点 ✓。
///
/// ☠ **纪律**（用户口径 ✓）：本文件是**新建的 dev 文件**，只被 `lib/main_win_dev.dart` 里**一行**
///   挂钩调用 ✓；共享代码（`config.dart` / `player_widget.dart` / `sites/**` …）**一个字不改** ✓；
///   发布入口 `lib/main.dart` 不受影响（本文件只在 `-t lib/main_win_dev.dart` 时被编译 ✓）。
///
/// ★ 为什么用**运行时环境变量**而不是 `--dart-define`：`--dart-define` 是**编译期**常量
///   （`main_win_dev.dart` 现有的 ⑥ 探针就是那么写的 ✓）⇒ 换一个场景就要重编一次 ✗。
///   本文件全部参数走 `Platform.environment` ✓ ⇒ **一次构建跑完所有场景** ✓（省时间、省内存 ✓）。
///
/// 场景（`KPXX_SOAK` 环境变量选一个；不定义 ⇒ 本文件**一行都不执行** ✓ 入口行为逐字节不变 ✓）：
///   · `player` — 建 `KpPlayer` → `open(URL)` → 播 N 秒 → `shutdown()`，循环 ≥10 轮（项1）
///       `KPXX_SOAK_URL` `KPXX_SOAK_ROUNDS`(10) `KPXX_SOAK_PLAY_SECS`(20) `KPXX_SOAK_SETTLE_SECS`(8)
///       `KPXX_SOAK_FINAL_SECS`(60)
///   · `avif`   — `KpAvif.decodeToPng()` 重复 N 次（项2）
///       `KPXX_SOAK_AVIF`(文件路径) `KPXX_SOAK_AVIF_N`(100)
///   · `scroll` — 起**真首页**（`KpxxApp`）→ 程序化滚动 ≥N 屏（项3）
///       `KPXX_SOAK_LOAD_SECS`(25) `KPXX_SOAK_SCREENS`(12) `KPXX_SOAK_WHEEL_PX`(600)
///   · `live`   — 挂**真直播间页**（`LiveRoomPage` 本体 ✓）→ 停留 N 秒 → 摘掉（项4）
///       `KPXX_SOAK_ROOM`(`<id>[:<name>]`) `KPXX_SOAK_EXIT_SECS`(180)
///   通用：`KPXX_SOAK_NO_EXIT=1` ⇒ 场景结束**不退进程**（默认自动 `exit(0)` ⇒ 外部采样器好判收尾 ✓）。
///
/// 所有读数都带**统一前缀** `[SOAK]` + 进程启动以来的秒数 + 进程 RSS（`ProcessInfo.currentRss` ✓）——
///   外部同时用 `Get-Process` 采 WS/PRIV，两边对得上时间轴（见补测报告 ✓）。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind, PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:kp_avif/kp_avif.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'home_page.dart' show HomePage; // ★ 项3 补测：挂**真站点页**（长列表 feed 才填得动图片缓存 ✓）
import 'main.dart' show KpxxApp;
import 'player_widget.dart' show KpPlayer;
import 'sites.dart' show kSites, SiteGroup;
import 'sites/xhamsterlive.dart' show LiveRoomPage;

// ═══════════════ 公共：日志 / 环境变量 ═══════════════

final Stopwatch _clock = Stopwatch()..start();

/// 统一读数行：`[SOAK] +12.3s rss=123456KB <正文>` ✓
void _log(String s) {
  debugPrint('[SOAK] +${(_clock.elapsedMilliseconds / 1000).toStringAsFixed(1)}s '
      'rss=${ProcessInfo.currentRss ~/ 1024}KB $s');
}

String _env(String k, [String def = '']) => Platform.environment[k] ?? def;
int _envInt(String k, int def) => int.tryParse(_env(k)) ?? def;

/// 媒体请求的 UA（和 `Site.ua` 同源思路，但**不 import 共享文件** ⇒ 就地写一条浏览器 UA ✓
///   —— 项1 播的是公开直链 HLS，UA 不影响；写死只为"像真客户端" ✓）
const String _kUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

/// 场景收尾：默认 `exit(0)` ⇒ 外部采样脚本能"看到进程自己退出"（不用猜该不该 kill ✓）
Future<void> _finish([String why = '']) async {
  _log('场景结束${why.isEmpty ? '' : '（$why）'} ⇒ ${_env('KPXX_SOAK_NO_EXIT') == '1' ? '保持前台' : 'exit(0)'}');
  if (_env('KPXX_SOAK_NO_EXIT') == '1') return;
  await Future<void>.delayed(const Duration(milliseconds: 800));
  exit(0);
}

/// 静置观察点：每 [step] 秒打一条，共 [secs] 秒（"停手后是否回落"就靠它 ✓）
Future<void> _observe(String tag, int secs, {int step = 10}) async {
  for (var t = step; t <= secs; t += step) {
    await Future<void>.delayed(Duration(seconds: step));
    _log('$tag 静置 +${t}s');
  }
}

// ═══════════════ 入口挂钩 ═══════════════

/// dev 入口调它：`KPXX_SOAK` 非空 ⇒ 起对应场景并返回 true（入口不再起正常 UI）；
/// 返回 false ⇒ 入口**照原样**往下走（⑥ 那三条探针 / 正常首页 ✓）。
Future<bool> runSoakIfRequested() async {
  final mode = _env('KPXX_SOAK').trim();
  if (mode.isEmpty) return false;
  _log('补测探针启动 mode=$mode pid=$pid');
  switch (mode) {
    case 'player':
      runApp(const _SoakShell(child: _PlayerSoak()));
      return true;
    case 'avif':
      runApp(const _SoakShell(child: _AvifSoak()));
      return true;
    case 'scroll':
      // ★ 项3 要的是**真首页**（`KpxxApp` 本体 ✓，与发布入口同一个 ✓）——
      //   滚动由**外部驱动对象**在首帧之后跑（不插进页面树、不碰任何共享 widget ✓）。
      //   ⚠️ 2026-10-10 实测修正：`KpxxApp` 首屏是**5 列宫格**（站点图标，可滚 ~650px、图片只有 21 张/0.95MB ✓）
      //     —— "滚 ≥10 屏 + 图片缓存被填"在**宫格页**上不成立（那是"站点页 / 分类 feed"才有长列表 ✓）
      //     ⇒ 加 `KPXX_SOAK_SITE=<n>`：直接挂 `SiteGroup.module` 里第 n 个站的 `HomePage` 本体 ✓
      //       （1-based；不定义 = 老行为 = 真宫格首页 ✓）
      final siteIdx = _envInt('KPXX_SOAK_SITE', 0);
      if (siteIdx > 0) {
        final mods = kSites.where((e) => e.group == SiteGroup.module).toList();
        if (siteIdx <= mods.length) {
          final e = mods[siteIdx - 1];
          _log('scroll: 挂真站点页 idx=$siteIdx/${mods.length} name=${e.name} ✓');
          runApp(_SoakShell(child: HomePage(site: e)));
        } else {
          _log('scroll: KPXX_SOAK_SITE=$siteIdx 越界（点播站只有 ${mods.length} 个）⇒ 退回真宫格首页');
          runApp(const KpxxApp());
        }
      } else {
        runApp(const KpxxApp());
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_ScrollSoak().run());
      });
      return true;
    case 'live':
      final spec = _env('KPXX_SOAK_ROOM');
      final parts = spec.split(':');
      final id = int.tryParse(parts.first.trim()) ?? 0;
      if (id == 0) {
        _log('live: KPXX_SOAK_ROOM 解析失败（要 <id>[:<name>]，拿到 "$spec"）⇒ 不测');
        return false;
      }
      runApp(_SoakShell(
          child: _LiveSoak(
              roomId: id, username: parts.length > 1 ? parts[1].trim() : '')));
      return true;
    default:
      _log('未知 mode=$mode ⇒ 退回正常首页（不改行为 ✓）');
      return false;
  }
}

/// 探针自己的最小壳（**只有这几条探针用它** ✓ —— 正常首页/直播间页都是**真页面** ✓）
class _SoakShell extends StatelessWidget {
  const _SoakShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'kpxx-soak',
        theme: ThemeData(useMaterial3: true),
        debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: Colors.black, body: child),
      );
}

// ═══════════════ 项1：KpPlayer 建/播/销 循环 ═══════════════

class _PlayerSoak extends StatefulWidget {
  const _PlayerSoak();

  @override
  State<_PlayerSoak> createState() => _PlayerSoakState();
}

class _PlayerSoakState extends State<_PlayerSoak> {
  KpPlayer? _kp; // 当前**在树上**的那个（null = 已摘掉 ✓）
  int _round = 0;
  String _stage = '准备';

  @override
  void initState() {
    super.initState();
    unawaited(_loop());
  }

  @override
  void dispose() {
    // 兜底：别把引擎留在进程里（正常路径每轮都已 shutdown ✓）
    final kp = _kp;
    _kp = null;
    if (kp != null) unawaited(kp.shutdown());
    super.dispose();
  }

  Future<void> _loop() async {
    final url = _env('KPXX_SOAK_URL');
    final rounds = _envInt('KPXX_SOAK_ROUNDS', 10);
    final playSecs = _envInt('KPXX_SOAK_PLAY_SECS', 20);
    final settleSecs = _envInt('KPXX_SOAK_SETTLE_SECS', 8);
    final finalSecs = _envInt('KPXX_SOAK_FINAL_SECS', 60);
    if (url.isEmpty) {
      _log('player: KPXX_SOAK_URL 为空 ⇒ 不测');
      await _finish('无 URL');
      return;
    }
    _log('player: 起点 建/播/销 循环 rounds=$rounds 每轮播 ${playSecs}s 结算 ${settleSecs}s '
        '收尾静置 ${finalSecs}s url=$url');

    for (var r = 1; r <= rounds; r++) {
      _round = r;
      _stage = 'r$r 建实例';
      final kp = KpPlayer();
      if (mounted) setState(() => _kp = kp);
      _log('player: r$r 建 KpPlayer ✓（VideoController 已建 ✓）');
      await Future<void>.delayed(const Duration(milliseconds: 400)); // 让 Video 上屏（纹理就位 ✓）

      _stage = 'r$r open';
      // ★ 与**正片路径**（详情页）一致：open 之前套一次起播参数（`PlayerWidget` 侧调的就是它 ✓）
      //   —— `demuxer-lavf-analyzeduration=2.0` / `probesize=1.5M` / `cache-pause-initial=no` ✓
      //   （实测定性影响：不调它时这条多码率 HLS 首帧 ≈16s ✓ ⇒ 每轮"真播"时间被吃掉一大半 ✓）
      KpPlayer.tuneStartupQuiet(kp);
      final tOpen = DateTime.now();
      try {
        await kp.open(url, httpHeaders: <String, String>{'User-Agent': _kUa})
            .timeout(const Duration(seconds: 30));
        _log('player: r$r open() 返回（${DateTime.now().difference(tOpen).inMilliseconds}ms）');
      } catch (e) {
        _log('player: r$r open() 抛了/超时（${DateTime.now().difference(tOpen).inMilliseconds}ms）：$e');
      }

      // 等首帧（最多 40s）：判据 `KpState.started`（= position>0 ✓ 与仓里既有判据同源 ✓）
      _stage = 'r$r 等首帧';
      final tFF = DateTime.now();
      while (!kp.value.started && DateTime.now().difference(tFF).inSeconds < 40) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      _log('player: r$r 首帧${kp.value.started ? '✓' : '✗(40s 超时未出画)'} '
          '耗时=${DateTime.now().difference(tFF).inMilliseconds}ms pos=${kp.value.position.inMilliseconds}ms');

      _stage = 'r$r 播 $playSecs s';
      final tPlay = DateTime.now();
      while (DateTime.now().difference(tPlay).inSeconds < playSecs) {
        await Future<void>.delayed(const Duration(seconds: 5));
        final v = kp.value;
        _log('player: r$r 播中 pos=${v.position.inMilliseconds}ms '
            'dur=${v.duration.inMilliseconds}ms started=${v.started} '
            'playing=${v.playing} buffering=${v.buffering} err=${v.error}');
      }
      final v = kp.value;
      _log('player: r$r 本轮结束读数 pos=${v.position.inMilliseconds}ms '
          'dur=${v.duration.inMilliseconds}ms errText=${v.errorText.isEmpty ? '(无)' : v.errorText}');

      // 摘掉 Video（= 离页那条路 ✓），再按 PlayerWidget.dispose 那套收引擎 ✓
      _stage = 'r$r 摘画面';
      if (mounted) setState(() => _kp = null);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _stage = 'r$r shutdown';
      final sw = Stopwatch()..start();
      await kp.shutdown();
      _log('player: r$r shutdown() 返回（${sw.elapsedMilliseconds}ms）');

      _stage = 'r$r 结算';
      await _observe('player: r$r 结算', settleSecs, step: settleSecs);
    }

    _round = -1;
    _stage = '收尾静置';
    _log('player: 全部 $rounds 轮跑完 ⇒ 收尾静置 ${finalSecs}s（看有没有回落 ✓）');
    await _observe('player: 收尾', finalSecs, step: 15);
    await _finish();
  }

  @override
  Widget build(BuildContext context) {
    final kp = _kp;
    return Stack(children: [
      if (kp != null)
        Positioned.fill(
          child: Video(
            controller: kp.videoController,
            fit: BoxFit.contain,
            fill: Colors.black,
            controls: NoVideoControls,
          ),
        ),
      Positioned(
        left: 8,
        top: 8,
        child: Text('player soak r$_round  $_stage',
            style: const TextStyle(color: Color(0xFFB0B4BA), fontSize: 12)),
      ),
    ]);
  }
}

// ═══════════════ 项2：AVIF 重复解码 ═══════════════

class _AvifSoak extends StatefulWidget {
  const _AvifSoak();

  @override
  State<_AvifSoak> createState() => _AvifSoakState();
}

class _AvifSoakState extends State<_AvifSoak> {
  String _stage = '读样本';
  int _done = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loop());
  }

  Future<void> _loop() async {
    final path = _env('KPXX_SOAK_AVIF');
    final n = _envInt('KPXX_SOAK_AVIF_N', 100);
    if (path.isEmpty) {
      _log('avif: KPXX_SOAK_AVIF 为空 ⇒ 不测');
      await _finish('无样本');
      return;
    }
    Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } catch (e) {
      _log('avif: 读样本失败：$e');
      await _finish('样本读不到');
      return;
    }
    _log('avif: 样本 $path ${bytes.length}B ⇒ 解码 $n 次（KpAvif.decodeToPng ✓ 公开接口 ✓）');
    var ok = 0, nul = 0, totalMs = 0;
    int firstLen = -1;
    for (var i = 1; i <= n; i++) {
      final t = DateTime.now();
      final png = await KpAvif.decodeToPng(bytes);
      final ms = DateTime.now().difference(t).inMilliseconds;
      totalMs += ms;
      if (png == null) {
        nul++;
      } else {
        ok++;
        if (firstLen < 0) firstLen = png.length;
      }
      _done = i;
      if (i <= 2 || i % 10 == 0 || i == n) {
        _log('avif: #$i png=${png?.length ?? -1}B ${ms}ms 累计 ok=$ok null=$nul');
      }
    }
    _log('avif: $n 次结束 ok=$ok null=$nul 首张PNG=${firstLen}B '
        '平均=${(totalMs / n).toStringAsFixed(1)}ms');
    if (nul == n) {
      _log('avif: ☠ 全部返回 null ⇒ 本平台/本机解不出来（WIC 缺 AVIF 解码器）⇒ 本次只能算"通道跑通"');
    }
    _stage = '结束';
    if (mounted) setState(() {});
    await _observe('avif: 解码结束', 60, step: 15);
    await _finish();
  }

  @override
  Widget build(BuildContext context) => Center(
        child: Text('avif soak $_done  $_stage',
            style: const TextStyle(color: Color(0xFFB0B4BA))),
      );
}

// ═══════════════ 项3：首页程序化滚动 ═══════════════

class _ScrollSoak {
  int _pointer = 900001;

  /// 图片缓存读数（**框架那一层**：`imageCache.maximumSizeBytes` 已由 dev 入口设 48MB ✓）
  String _cache() {
    final c = PaintingBinding.instance.imageCache;
    final cur = c.currentSizeBytes / (1 << 20);
    final maxB = c.maximumSizeBytes / (1 << 20);
    return 'imageCache=${cur.toStringAsFixed(2)}MB/${maxB.toStringAsFixed(0)}MB '
        '张=${c.currentSize}/${c.maximumSize} 在用=${c.liveImageCount} 在途=${c.pendingImageCount}';
  }

  /// 收集 element 树里**所有竖着能滚**的 `ScrollableState`（按 maxScrollExtent 从大到小 ✓）——
  ///   ⚠️ 只挑"最远的那个"是不够的（实测：宫格页里另有小列表，pick 到的不是主列表 ⇒ 白滚 ✓）。
  List<ScrollableState> _vertical() {
    final root = WidgetsBinding.instance.rootElement;
    final out = <ScrollableState>[];
    if (root == null) return out;
    void visit(Element e) {
      final w = e.widget;
      if (w is Scrollable && e is StatefulElement) {
        final ad = w.axisDirection;
        if (ad == AxisDirection.down || ad == AxisDirection.up) {
          final st = e.state;
          if (st is ScrollableState) {
            try {
              final p = st.position;
              if (p.hasContentDimensions && p.hasPixels) out.add(st);
            } catch (_) {
              // position 尚未挂上（attach 之前）⇒ 跳过 ✓
            }
          }
        }
      }
      e.visitChildren(visit);
    }

    visit(root);
    out.sort((a, b) {
      final x = a.position.maxScrollExtent;
      final y = b.position.maxScrollExtent;
      return y.compareTo(x);
    });
    return out;
  }

  /// 树里竖列表的概览（给日志用 ✓）：`max@px` 前三个
  String _cands(List<ScrollableState> l) {
    if (l.isEmpty) return '(没有竖列表)';
    final take = l.length > 3 ? l.sublist(0, 3) : l;
    return take
        .map((s) => '${s.position.maxScrollExtent.toStringAsFixed(0)}@'
            '${s.position.pixels.toStringAsFixed(0)}')
        .join(' ');
  }

  /// 真·滚轮事件（次要手段；主手段是 `jumpTo` ⇒ 不受"仿真手机框坐标"影响 ✓）
  void _wheel(double dy) {
    final binding = WidgetsBinding.instance;
    final views = binding.platformDispatcher.views;
    if (views.isEmpty) return;
    final v = views.first;
    final size = v.physicalSize / v.devicePixelRatio;
    binding.handlePointerEvent(PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: Offset(size.width / 2, size.height * 0.55),
      scrollDelta: Offset(0, dy),
      device: _pointer++,
    ));
  }

  Future<void> run() async {
    final loadSecs = _envInt('KPXX_SOAK_LOAD_SECS', 25);
    final screens = _envInt('KPXX_SOAK_SCREENS', 12);
    final px = _envInt('KPXX_SOAK_WHEEL_PX', 600);

    _log('scroll: 等页面加载 ${loadSecs}s（每 5s 打一条：竖列表 max@px 前3 + 图片缓存）');
    for (var t = 5; t <= loadSecs; t += 5) {
      await Future<void>.delayed(const Duration(seconds: 5));
      final l = _vertical();
      _log('scroll: 加载中 +${t}s 竖列表=${l.length} 前3=${_cands(l)} ${_cache()}');
    }

    var events = 0;
    var jumps = 0;
    var moved = 0.0; // 累计**滚动位移**（不是 pixels 位置 ✓ —— 换列表后位置会跳 ✓）
    var noMove = 0;
    for (var s = 1; s <= screens; s++) {
      final l = _vertical();
      // 挑"还有下探空间、且最长"的那条（每轮重挑 ⇒ 主列表长出来后自动切过去 ✓）
      ScrollableState? tgt;
      for (final st in l) {
        if (st.position.pixels < st.position.maxScrollExtent - 1) {
          tgt = st;
          break;
        }
      }
      if (tgt == null) {
        _log('scroll: 第 $s 屏 —— 所有竖列表都到底了（候选 ${l.length} 个）⇒ 停');
        break;
      }
      final before = tgt.position.pixels;
      final maxE = tgt.position.maxScrollExtent;
      final step = px.toDouble();
      // 主手段：直接 jumpTo（一跳一屏 ≈ 0.8×屏高）—— 每跳一小步，给图片解码/落盘留时间 ✓
      try {
        tgt.position.jumpTo((before + step).clamp(0.0, maxE).toDouble());
        jumps++;
      } catch (e) {
        _log('scroll: 第 $s 屏 jumpTo 抛了：$e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      // 次要手段：真滚轮事件（验"事件路由到 Scrollable"这条链 ✓；坐标没落在仿真框里也不影响主手段 ✓）
      _wheel(step);
      events++;
      await Future<void>.delayed(const Duration(milliseconds: 1000));

      final l2 = _vertical();
      final after = tgt.position.pixels;
      final d = after - before;
      moved += d < 0 ? 0 : d;
      if (d.abs() < 1) noMove++;
      _log('scroll: 第 $s/$screens 屏 本条 max=${maxE.toStringAsFixed(0)} '
          '${before.toStringAsFixed(0)}→${after.toStringAsFixed(0)}（Δ=${d.toStringAsFixed(0)}）'
          ' 候选=${l2.length} 前3=${_cands(l2)} 累计位移=${moved.toStringAsFixed(0)} ${_cache()}');
    }

    _log('scroll: 滚动段结束（累计位移 ${moved.toStringAsFixed(0)}px，按 800px/屏 ≈ '
        '${(moved / 800).toStringAsFixed(1)} 屏；jump=$jumps 滚轮=$events 无位移次数=$noMove）'
        ' ⇒ 静置看缓存/RSS 是否收敛');
    await _observe('scroll: 停手', 60, step: 15);
    _log('scroll: 收尾 ${_cache()}');
    await _finish();
  }
}

// ═══════════════ 项4：单房长播（真直播间页） ═══════════════

class _LiveSoak extends StatefulWidget {
  const _LiveSoak({required this.roomId, required this.username});
  final int roomId;
  final String username;

  @override
  State<_LiveSoak> createState() => _LiveSoakState();
}

class _LiveSoakState extends State<_LiveSoak> {
  bool _show = true;
  Timer? _timer;
  final Stopwatch _in = Stopwatch();

  @override
  void initState() {
    super.initState();
    final exitSecs = _envInt('KPXX_SOAK_EXIT_SECS', 180);
    _in.start();
    _log('live: 进房 id=${widget.roomId} name=${widget.username.isEmpty ? '(空)' : widget.username} '
        '停留 ${exitSecs}s（到点把房间页从树上摘掉 ⇒ 它 dispose() ⇒ 播放器释放 ✓）');
    _timer = Timer(Duration(seconds: exitSecs), () async {
      if (mounted) setState(() => _show = false);
      _log('live: 已摘掉房间页（在房 ${_in.elapsed.inSeconds}s）');
      await _observe('live: 退房', 30, step: 10);
      await _finish();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _show
      ? LiveRoomPage(username: widget.username, id: widget.roomId)
      : const Center(
          child: Text('已退房（探针）', style: TextStyle(color: Color(0xFFB0B4BA))));
}
