// 短片瀑布流（竖屏流）—— App 端
//
// 对齐 sim 已经验过的那套（DEVLOG 83）：
//   · 一屏一条（PageView 竖向）+ 上划下划换条
//   · **单击**播放/暂停；**左右划**调进度；点进度条也能跳
//   · 进度条**贴底**、时间/总时长显示在**进度条右边**
//   · **暂停时**才显示状态栏与左上角 X；播放时沉浸（藏起来）
//   · X 刻意放在**状态栏之下**（`MediaQuery.padding.top` 再往下）—— 用户 2026-10-02：
//     "X 不要放到状态栏位置因为会点不到" ✗
//   · 播完**自动下一条**；滑到尾部自动续拉列表
//   · **预缓存 5 条**（滑动窗口：每往前一条补一条）—— 用户 2026-10-02 定的语义
//   · 从左边缘往右划 = 返回
//
// ⚠️ 只用**一个** `KpPlayer` 实例（用户明确否掉了双实例 ✗："双实例开销比预缓冲大多了"）。
//   相邻页显示封面图，不做多实例解码 —— 换条要快靠**预取片源地址**（mpv 自己 200MB 的
//   demux 缓冲 + 已就绪的源），不靠第二个解码器 ✓。
//
// ⚠️ 本站（xHamster）短片的详情页**只有一条源**（站点默认档，见 api.dart 的 _xhDetail：
//   '/shorts/…' 不展开档位）→ 这里直接用 `sources` 里的第一条 ✓。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'api.dart';
import 'models.dart';
import 'player_widget.dart';
import 'sites.dart';

class ShortsFeedPage extends StatefulWidget {
  const ShortsFeedPage({
    super.key,
    required this.api,
    required this.site,
    required this.items,
    required this.start,
  });

  final Api api;
  final SiteEntry site; // ⚠️ 类型是 `SiteEntry`（api.dart 里就是它），**不是 `Site`** ✗

  /// 进来时已有的短片列表（从「短片」tab 的网格点进来的那份）
  final List<Article> items;
  final int start;

  @override
  State<ShortsFeedPage> createState() => _ShortsFeedPageState();
}

class _ShortsFeedPageState extends State<ShortsFeedPage> {
  late final PageController _pc;
  late List<Article> _items;
  int _cur = 0;

  KpPlayer? _kp;
  bool _autoAdvanced = false; // completed 会连发，防重复翻页

  /// 片源缓存（url → sources）。**预缓存 5 条**就是靠它：提前把详情页抓了、源存这儿。
  final Map<String, List<String>> _srcCache = {};
  final Map<String, Future<List<String>>> _fetching = {};

  bool _playing = false; // 播放中（决定状态栏与 X 显示与否）
  bool _loadingMore = false;
  bool _done = false;
  int _page = 1;

  /// 播放器还没建好时给 `ValueListenableBuilder` 用的空壳（别在 build 里 new ✗ 那会每次重建）
  final ValueNotifier<KpState> _idle = ValueNotifier(const KpState());

  @override
  void initState() {
    super.initState();
    _items = List<Article>.of(widget.items);
    _cur = widget.start.clamp(0, _items.isEmpty ? 0 : _items.length - 1);
    _pc = PageController(initialPage: _cur);
    _applyImmersive(false); // 刚进来还没播 → 按"暂停态"显示状态栏与 X（否则没有退出口）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _open(_cur);
      _precache();
    });
  }

  @override
  void dispose() {
    final kp = _kp;
    if (kp != null) {
      kp.removeListener(_onTick);
      kp.shutdown(); // 与详情页同一套收尾（KpPlayer 暴露的是 shutdown，不是 stream ✗）
    }
    _pc.dispose();
    _idle.dispose();
    // 退出必须恢复（不然整个 App 都还是沉浸式 ✗）
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  /// ⚠️ `KpPlayer` 是 `ValueNotifier<KpState>`，**没有 `stream`** ✗ —— 只能 `addListener` ✓
  /// （它内部把 mpv 的 `_p.stream.*` 收进 `value`，见 player_widget.dart:147-157）。
  void _onTick() {
    if (!mounted) return;
    final s = _kp?.value;
    if (s == null) return;
    if (s.playing != _playing) {
      setState(() => _playing = s.playing);
      _applyImmersive(s.playing);
    }
    // **播完自动下一条**（抖音式流的标准行为；completed 会连发 → 用一个标志防抖）
    if (s.completed) {
      if (!_autoAdvanced) {
        _autoAdvanced = true;
        final nxt = _cur + 1;
        if (nxt < _items.length) {
          _pc.nextPage(
              duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
        }
      }
    } else {
      _autoAdvanced = false;
    }
  }

  /// 沉浸模式：播放 = 藏状态栏；暂停 = 露出（用户 2026-10-02 要求）
  void _applyImmersive(bool playing) {
    try {
      SystemChrome.setEnabledSystemUIMode(
        playing ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
      // 瀑布流**锁竖屏**（不跟着转横屏）
      if (playing) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
    } catch (_) {}
  }

  /// 拿片源：先看缓存（预取过的），没有就抓详情页
  Future<List<String>> _sourcesOf(int i) {
    if (i < 0 || i >= _items.length) return Future.value(const []);
    final url = _items[i].url;
    final hit = _srcCache[url];
    if (hit != null) return Future.value(hit);
    final flying = _fetching[url];
    if (flying != null) return flying;
    final f = widget.api.detail(url).then((d) {
      final srcs = (d.videos.isNotEmpty) ? d.videos.first.sources : const <String>[];
      _srcCache[url] = srcs;
      _fetching.remove(url);
      return srcs;
    }).catchError((_) {
      _fetching.remove(url);
      return const <String>[];
    });
    _fetching[url] = f;
    return f;
  }

  Future<void> _open(int i) async {
    if (i < 0 || i >= _items.length) return;
    final srcs = await _sourcesOf(i);
    if (!mounted) return;
    if (srcs.isEmpty) return;
    var kp = _kp;
    if (kp == null) {
      final created = KpPlayer(bufferMb: 64); // 短片很短，64MB 足够（省内存）
      _kp = created;
      created.addListener(_onTick);
      kp = created;
      setState(() {});
    }
    // ⚠️ 这里 kp 已经是非空的局部变量（Dart 的流分析不会把 `_kp` 认成非空 ✗）
    await kp.open(srcs.first);
  }

  /// **预缓存 5 条**（滑动窗口）：从当前的下一条起，保证前面 5 条都已抓好源；
  /// 每往前滑一条，就补一条 —— 用户 2026-10-02："我划到第二条你就要再预缓冲一条补上，
  /// 我连划三次，你就要补3条" ✓
  void _precache() {
    const count = 5;
    for (var k = 1; k <= count; k++) {
      final j = _cur + k;
      if (j >= _items.length) {
        _loadMore(); // 窗口越过尾部 → 顺手把列表续上（不然"划不动了" ✗）
        continue;
      }
      final url = _items[j].url;
      if (_srcCache.containsKey(url) || _fetching.containsKey(url)) continue;
      _sourcesOf(j); // 并发跑，不 await（别挡当前这条起播）
    }
  }

  /// 尾部续拉：短片列表是随机的批次，每批 ≈ 20 条
  Future<void> _loadMore() async {
    if (_loadingMore || _done) return;
    _loadingMore = true;
    try {
      // ⚠️ `Api.category` 的第一个参数（key）是**位置参数**，不是 `k:` ✗
      final more = await widget.api.category('/shorts', page: _page + 1);
      if (!mounted) return;
      _page++;
      final have = _items.map((a) => a.url).toSet();
      final fresh = more.where((a) => a.url.isNotEmpty && !have.contains(a.url)).toList();
      if (fresh.isEmpty) {
        _done = true;
      } else {
        setState(() => _items.addAll(fresh));
      }
    } catch (_) {
      _done = true;
    } finally {
      _loadingMore = false;
    }
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t), duration: const Duration(milliseconds: 900)),
    );
  }

  static String _fmt(Duration d) {
    final t = d.inSeconds.clamp(0, 86399);
    final h = t ~/ 3600, m = (t % 3600) ~/ 60, s = t % 60;
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
    return '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top; // 状态栏高度（X 要避开它 ✓）
    final art = (_cur >= 0 && _cur < _items.length) ? _items[_cur] : null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        child: Stack(
          children: [
            // ---- 视频区：竖向翻页，一屏一条 ----
            PageView.builder(
              controller: _pc,
              scrollDirection: Axis.vertical,
              onPageChanged: (i) {
                setState(() => _cur = i);
                _open(i);
                _precache();
              },
              itemCount: _items.length,
              itemBuilder: (c, i) {
                // 只有当前页有播放器（一个实例 ✓）；相邻页先显封面
                if (i == _cur && _kp != null) {
                  return _GestureLayer(
                    kp: _kp!,
                    onTap: () {
                      final kp = _kp;
                      if (kp == null) return;
                      if (kp.value.playing) {
                        kp.pause();
                        _toast('已暂停');
                      } else {
                        kp.play();
                      }
                    },
                    onSeekHint: _toast,
                    child: Video(controller: _kp!.videoController),
                  );
                }
                final it = _items[i];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (it.cover.isNotEmpty)
                      Image.network(it.cover, fit: BoxFit.contain),
                    const Center(
                      child: SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ],
                );
              },
            ),

            // ---- 顶部：暂停时才出现的 X（**放在状态栏之下**，不然点不到 ✗）----
            if (!_playing)
              Positioned(
                left: 12,
                top: topPad + 10,
                child: _RoundBtn(
                  icon: Icons.close,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),

            // ---- 底部：标题/作者 + 进度条（贴底）+ 时间在**进度条右边** ----
            Positioned(
              left: 12,
              right: 12,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (art != null) ...[
                    Text(
                      art.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                    ),
                    if (art.meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(art.meta,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                      ),
                    const SizedBox(height: 10),
                  ],
                  ValueListenableBuilder<KpState>(
                    valueListenable: _kp ?? _idle,
                    builder: (c, s, _) {
                      final dur = s.duration;
                      final pos = s.position;
                      final p = dur.inMilliseconds <= 0
                          ? 0.0
                          : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
                      return Row(
                        children: [
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 2.5,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6),
                                overlayShape: SliderComponentShape.noOverlay,
                                activeTrackColor: Colors.white,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                              ),
                              child: Slider(
                                value: p.toDouble(),
                                onChanged: (v) {
                                  final kp = _kp;
                                  if (kp == null || dur.inMilliseconds <= 0) return;
                                  kp.seek(Duration(
                                      milliseconds:
                                          (dur.inMilliseconds * v).round()));
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 时间/总时长在进度条**右边** ✓
                          Text(
                            '${_fmt(pos)} / ${_fmt(dur)}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 视频上的手势层：左右划 = 调进度（复用 KpPlayer 自带的 swipe* 逻辑，与详情页同一手感），
/// 轻点 = 播放/暂停（外层 onTap）。上下划交给 PageView 自己（要 `behavior: translucent`
/// 才不会把竖直拖动吃掉 ✗）。
class _GestureLayer extends StatelessWidget {
  const _GestureLayer({
    required this.kp,
    required this.child,
    required this.onTap,
    required this.onSeekHint,
  });

  final KpPlayer kp;
  final Widget child;
  final VoidCallback onTap;
  final void Function(String) onSeekHint;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      onHorizontalDragStart: kp.swipeStart,
      onHorizontalDragUpdate: (d) {
        kp.swipeUpdate(d);
        final secs = (d.primaryDelta ?? 0) / 10; // 粗提示，真正的跳转在 swipeEnd 里
        if (secs.abs() > 1) {
          onSeekHint('${secs > 0 ? '▶' : '◀'} ${secs.abs().toStringAsFixed(0)}s');
        }
      },
      onHorizontalDragEnd: kp.swipeEnd,
      child: child,
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
