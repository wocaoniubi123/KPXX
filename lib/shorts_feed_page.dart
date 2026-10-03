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
import 'fetched_image.dart';
import 'site_error_log.dart';

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
    // 🔎 发出前先记一笔 ✓（否则「卡住」和「抛错」都没日志 ✗）
    SiteErrorLog.log('短片', '取源开始 #$i $url');
    final _t0 = DateTime.now().millisecondsSinceEpoch;
    final f = widget.api.detail(url).then((d) {
      final srcs = (d.videos.isNotEmpty) ? d.videos.first.sources : const <String>[];
      // 🔎 取源诊断（用户 2026-10-03 报：短片页一直转圈 ✓ —— 上一条埋点只盖了翻页 ✗，这条盖第一页 ✓）
      SiteErrorLog.log('短片',
          '取源成功 #$i ${DateTime.now().millisecondsSinceEpoch - _t0}ms → videos=${d.videos.length} srcs=${srcs.length} 首条=${srcs.isEmpty ? "（空）" : srcs.first.split('?').first}');
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
    // ⚠️ 取源加超时 ✓：原来没有超时 → 一旦卡住就无限转圈（用户截图那个转圈 ✓）
    final srcs = await _sourcesOf(i).timeout(const Duration(seconds: 20), onTimeout: () {
      SiteErrorLog.log('短片', '取源超时 ✗ #$i（20 秒没回来）');
      return const <String>[]; // 当空处理 → 走上层「取不到源」的分支 ✓ 不再干转 ✗
    });
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
      // 🔎 翻页诊断（同上 ✓）
    final List<Article> more;
    try {
      more = await widget.api.category('/shorts', page: _page + 1);
      SiteErrorLog.log('短片', '翻页 page=${_page + 1} → ${more.length} 条 ✓');
    } catch (e, st) {
      SiteErrorLog.log('短片', '翻页 page=${_page + 1} 抛错 ✗：$e', st);
      rethrow;
    }
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

  // ---- 左右划调进度（自己算；不能用 kp.swipe* ✗ 那几个方法在播放器的私有 mixin 里）----
  // 手感对齐详情页：**滑满一屏 = 120 秒**，**松手才真正跳**（拖动过程中只给个提示 ✓）。
  Duration _dragFrom = Duration.zero;
  double _dragDx = 0;

  void _seekStart() {
    final kp = _kp;
    if (kp == null) return;
    // ⚠️ 起点用 `lastKnownPosition` 打底（刚换源时 `value.position` 会被清零 —— 就是"换分辨率
    //    从头发"那个坑，见 DEVLOG 73 ✗）。与详情页 `_pickQuality` 的取法一致 ✓
    _dragFrom = kp.lastKnownPosition > Duration.zero
        ? kp.lastKnownPosition
        : kp.value.position;
    _dragDx = 0;
  }

  void _seekUpdate(double dx) => _dragDx += dx;

  void _seekEnd() {
    final kp = _kp;
    if (kp == null) return;
    final w = MediaQuery.of(context).size.width;
    final dx = _dragDx;
    _dragDx = 0;
    if (w <= 0 || dx == 0) return;
    final secs = dx / w * 120; // 滑满一屏 120 秒
    if (secs.abs() < 1) return; // 手抖不算
    var to = _dragFrom + Duration(milliseconds: (secs * 1000).round());
    if (to < Duration.zero) to = Duration.zero;
    final dur = kp.value.duration;
    if (dur > Duration.zero && to > dur) to = dur;
    _toast(secs > 0
        ? '▶ ${secs.round()}s'
        : '◀ ${(-secs).round()}s');
    // 用 seekExact：`seek` 会按 value.duration 裁剪（时长还没报上来时会被裁小 ✗）
    kp.seekExact(to);
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
                    onTap: () {
                      final kp = _kp;
                      if (kp == null) return;
                      if (kp.value.playing) {
                        kp.pause();
                      } else {
                        kp.play();
                      }
                    },
                    onSeekStart: _seekStart,
                    onSeekUpdate: _seekUpdate,
                    onSeekEnd: _seekEnd,
                    child: Video(controller: _kp!.videoController),
                  );
                }
                final it = _items[i];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (it.cover.isNotEmpty)
                      // ⚠️ 2026-10-03 修（用户报「短片卡片加载不出来」✗）：原来用 Image.network ✗ ——
                      // **不带 Referer/UA** ✗ → xHamster 封面是防盗链的 ✓ → 403；且 Image.network 失败时
                      // **什么都不画** ✗ → 屏上只剩背景 + 转圈 ✓（正是用户截图 ✓）。改用带站点头的 FetchedImage ✓
                      FetchedImage(url: it.cover, fit: BoxFit.contain),
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

/// 视频上的手势层：轻点 = 播放/暂停（页面给的回调）；左右划 = 调进度。
///
/// ⚠️ 这里**不能**用 `kp.swipeStart/swipeUpdate/swipeEnd` ✗ —— 那几个方法**不在 `KpPlayer` 上**，
/// 而是播放器里一个**私有 mixin** `_SwipeSeek<T> on State<T>`（`player_widget.dart`，带 `_` 前缀，
/// 别的库引用不到 ✗）。CI 第一版就是报：
/// `lib/shorts_feed_page.dart:400:33: Error: The getter 'swipeStart' isn't defined for the class 'KpPlayer'` ✗
/// → 所以这里自己算（滑满一屏 = 120 秒，与详情页同一手感），真正的跳转在松手时做 ✓。
class _GestureLayer extends StatelessWidget {
  const _GestureLayer({
    required this.child,
    required this.onTap,
    required this.onSeekStart,
    required this.onSeekUpdate,
    required this.onSeekEnd,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback onSeekStart;
  final void Function(double dx) onSeekUpdate;
  final VoidCallback onSeekEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      onHorizontalDragStart: (_) => onSeekStart(),
      onHorizontalDragUpdate: (d) => onSeekUpdate(d.primaryDelta ?? 0),
      onHorizontalDragEnd: (_) => onSeekEnd(),
      onHorizontalDragCancel: onSeekEnd,
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
