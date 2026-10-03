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
//   · **预缓存 5 条**（滑动窗口：每往前一条补一条）—— 用户 2026-10-02 定的语义；
//     **片源地址 + 把后面 5 条预下载到本地** ✓（用户 2026-10-03 定："单实例 + 缓冲五条" ✓）
//   · 从左边缘往右划 = 返回
//
// ⚠️ 只用**一个** `KpPlayer` 实例（用户明确否掉了双实例 ✗："双实例开销比预缓冲大多了"）。
//   换条快靠这两件事，**都不需要第二个解码器** ✓：
//   ① **预取片源地址**（`SourceCache` ✓ —— 省掉一次详情页请求 ✓；入口"点卡片"还会**先**预热一次 ✓）；
//   ② **预下载后面 5 条到本地文件**（`base/video_cache.dart` ✓）→ 划到它时把 `file://`
//      交给**同一个** mpv ✓（mpv 只把**当前**这条缓进内存 ✗，且不读我们的 HTTP 缓存 ✗）。
//
// ⚠️ 本站（xHamster）短片的详情页**只有一条源**（站点默认档，见 api.dart 的 _xhDetail：
//   '/shorts/…' 不展开档位）→ 这里直接用 `sources` 里的第一条 ✓。

import 'dart:async';
import 'base/source_cache.dart';
import 'base/video_cache.dart';
import 'fetched_image.dart';

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

  // ⚠️ 片源缓存**已挪进共享底座** ✓（`lib/base/source_cache.dart`）：入口（点卡片）在本页之前就会预热
  //    第 0 条的源 ✓；当年那份**页内私有**缓存导致"网格抓的那次白费 ✗ → 进页面再抓一次 ✗"
  //    （用户实测"点进来要好几秒才有画面"✗）→ 现在换成共享的 ✓（同一 url 只飞一次 ✓）。

  bool _playing = false; // 播放中（决定状态栏与 X 显示与否）
  /// C ✓（用户 2026-10-03 拍板）：播放器**缓冲**时让预下载**让路** —— 去抖计时器（短暂抖动不折腾 ✓）
  Timer? _bufTimer;
  bool _bufPaused = false;
  bool _loadingMore = false;
  bool _done = false;
  /// 最近一次"续拉"是**失败**（网络/被挡/限流 ✓）——**不是**没内容 ✗ → 允许下次滑动重试 ✓
  bool _tailFailed = false;
  /// 已经**成功**续拉过的页数：**0 起步** ✓ → 首次请求的就是 `page: 1`（页面 JSON = 45 条 ✓）。
  /// ⚠️ 原来从 `1` 起步 ✗ → 首次就请求 page 2 ✗ → 45 条那批**永远拿不到** ✗
  /// （用户实测：只有 1 + 5~6 条 → 「划 5 个左右就到底」✗）
  int _page = 0;

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
      VideoCache.i.init(); // 建预下载目录 + 清一次 LRU ✓（缓存内部全静默 ✓）
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
    // ⚠️ C：退出时把"让路"撤掉 ✓ —— 缓存是**全局单例** ✗，留着暂停会把预下载永久停住 ✗
    _bufTimer?.cancel();
    _bufTimer = null;
    if (_bufPaused) {
      _bufPaused = false;
      VideoCache.i.resume();
    }
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
    // ⚠️ C ✓：缓冲就让预下载让路（去抖后 ✓）
    _watchBuffering(s.buffering);
  }

  /// C ✓（用户 2026-10-03 拍板）：**播放器一缓冲，预下载就让路** ✗ —— 带宽全给当前这条 ✓。
  /// ⚠️ 去抖 1.5 秒 ✓：网络抖动导致的瞬时 buffering 不折腾 ✓（真卡住才让路 ✓）；
  /// ⚠️ 恢复是**立刻**的 ✓（缓冲一结束就放开 ✓）。
  void _watchBuffering(bool buffering) {
    if (buffering) {
      if (_bufPaused || _bufTimer != null) return; // 已经在让路 / 已经排上队 ✓
      _bufTimer = Timer(const Duration(milliseconds: 1500), () {
        _bufTimer = null;
        if (!mounted) return;
        _bufPaused = true;
        VideoCache.i.pause();
      });
      return;
    }
    _bufTimer?.cancel();
    _bufTimer = null;
    if (_bufPaused) {
      _bufPaused = false;
      VideoCache.i.resume();
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

  /// 拿片源：走**共享缓存** ✓（`lib/base/source_cache.dart`）—— 入口"点卡片"时已经发起过的那次，
  /// 这里会直接命中**在途的 Future** ✓ → **同一 url 只飞一次** ✓
  Future<List<String>> _sourcesOf(int i) {
    if (i < 0 || i >= _items.length) return Future.value(const []);
    final url = _items[i].url;
    // ⚠️ #9：key 带命名空间 `s|` ✓（详情页的合集取源用 `d|` ✓ —— 两条策略不同，**不能共用 key** ✗）
    return SourceCache.i.get('s|$url', () async {
      final d = await widget.api.detail(url);
      return SourceCache.sourcesOfDetail(d);
    });
  }

  Future<void> _open(int i) async {
    if (i < 0 || i >= _items.length) return;
    // ⚠️ 取源加超时 ✓：原来没有超时 → 一旦卡住就无限转圈（用户截图那个转圈 ✓）
    // 超时就当"取不到源" → 走上层分支，不再干转 ✗
    final srcs = await _sourcesOf(i)
        .timeout(const Duration(seconds: 20), onTimeout: () => const <String>[]);
    if (!mounted) return;
    if (srcs.isEmpty) return;
    var kp = _kp;
    if (kp == null) {
      final created = KpPlayer(bufferMb: 64); // 短片很短，64MB 足够（省内存）
      _tuneMpvStartup(created); // ⚠️ 只调**这一个实例** ✓（绝不碰 player_widget.dart 的共用配置 ✗）
      _kp = created;
      created.addListener(_onTick);
      kp = created;
      setState(() {});
    }
    // ⚠️ 这里 kp 已经是非空的局部变量（Dart 的流分析不会把 `_kp` 认成非空 ✗）
    // ⚠️ **预下载好的本地文件优先** ✓：还是**同一个** mpv，只是把地址换成 `file://` ✓
    //（用户 2026-10-03 定的方案 ✓）；没下完 / 不是直链 mp4（m3u8…）→ 回落在线直连 ✓
    final local = VideoCache.i.ready(srcs.first);
    if (local == null) {
      // ⚠️ A 项（用户 2026-10-03 拍板 ✓）：本地**还没就绪** → 这一次只能在线播 → 把它的预下载**放弃** ✗
      //    （不许跟播放抢同一份流量 ✓；入口那一小段"抢跑"没抢到就干脆让路 ✓）
      VideoCache.i.drop(srcs.first);
    }
    await kp.open(local?.uri.toString() ?? srcs.first);
  }

  /// 起播参数：**实现收在 `KpPlayer.tuneStartupQuiet`** ✓（#5 起详情页也用同一个 ✓，只有一份 ✗）；
  /// 开关也那边（`KpPlayer.tuneStartup` ✓ 默认开 ✓，改一处即可关 ✗）。
  /// ⚠️ 旧注释里"**只给短片这个实例**"已作废 ✗（详情页现在也调 ✓）。
  void _tuneMpvStartup(KpPlayer kp) => KpPlayer.tuneStartupQuiet(kp);

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
      // 已缓存 / 在途 / 正在下的都交给共享缓存去判 ✓（同一 url 只飞一次 ✗ 不用在这里查表 ✓）
      _sourcesOf(j); // 并发跑，不 await（别挡当前这条起播）
    }
    _primeWindow(count); // 源解析完再交给预下载（同样不 await ✓）
  }

  /// 把"后面 5 条"的**源地址**交给 [VideoCache] **预下载到本地** ✓
  ///（用户 2026-10-03 定：**单实例 + 缓冲五条** ✓ —— 播放时还是同一个 mpv，只把地址换成 `file://` ✓）
  /// 划 1 条 → 窗口整体前移 → 缓存自动补新的一条 ✓、并把已经划走那条**中止** ✗（省带宽 ✓）。
  Future<void> _primeWindow(int count) async {
    final urls = <String>[];
    // ⚠️ A 项 ✓：**`k` 从 0 起** —— 必须把**当前条**也放进窗口 ✓。
    //    入口（点卡片）那一刻已经给它起过预下载 ✓；这里若不含它，`window()` 会把"不在窗口里"的下载**中止** ✗
    //    → 抢跑白做 ✓。等 `_open()` 真的开播而本地还没就绪时，那边会 `drop()` 它 ✓（那时才该让路 ✓）。
    for (var k = 0; k <= count; k++) {
      final j = _cur + k;
      if (j >= _items.length) break;
      final srcs = await _sourcesOf(j); // 命中共享缓存在途的 Future 时立即返回 ✓
      if (!mounted) return;
      if (srcs.isNotEmpty) urls.add(srcs.first);
    }
    await VideoCache.i.window(urls);
  }

  /// 尾部续拉（往后拿下一批）✓
  /// ⚠️ 页数语义（2026-10-03 修）：`_page` 从 **0** 起步 ✓ → 首次请求 **page 1** ✓（= 页面 JSON，
  ///    **45 条** ✓）；之后 2、3、… ✓（走站点接口，5~6 条/页 ✓）。
  /// ⚠️ **"失败"与"到底"必须分开** ✗：**空批次**才算到底（`_done` ✓）；**抛错**只标 `_tailFailed` ✓
  ///    —— 原来一律 `_done = true` ✗ → 一次失败就"本次进入永久到底" ✗（用户实测那个"划不动"✓）；
  ///    现在不置 `_done` ✓ → 再滑一下就自动重试 ✓（也可以点左上角那个 ↻ ✓）。
  Future<void> _loadMore() async {
    if (_loadingMore || _done) return;
    _loadingMore = true;
    try {
      // ⚠️ `Api.category` 的第一个参数（key）是**位置参数**，不是 `k:` ✗
      final List<Article> more =
          await widget.api.category('/shorts', page: _page + 1);
      if (!mounted) return;
      _page++;
      _tailFailed = false;
      final have = _items.map((a) => a.url).toSet();
      final fresh = more.where((a) => a.url.isNotEmpty && !have.contains(a.url)).toList();
      if (fresh.isEmpty) {
        _done = true; // 站点给不出新内容了（**空批次**）→ 真到底 ✓
      } else {
        setState(() => _items.addAll(fresh));
      }
    } catch (_) {
      // ⚠️ 抛错 ≠ 到底 ✗（原因站点层已写进**公共错误日志** ✓，这里不重复记 ✗）
      if (mounted) setState(() => _tailFailed = true);
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
                  return Stack(
                    children: [
                      _GestureLayer(
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
                    child: Video(
                      controller: _kp!.videoController,
                      // ⚠️ 2026-10-03（用户实测）：不传 controls 时 media_kit_video 会**自带一条控制条** ✗
                      // → 屏幕上出现**两个进度条**（自带那条 + 本页自己画的那条 ✓），而且**自带控制条会吃掉竖滑手势** ✗
                      // → 上划下划换条失灵 ✓。这里关掉它，只留本页自己的 UI ✓。
                      controls: NoVideoControls,
                    ),
                      ),
                      // ⚠️ 2026-10-03 加（用户实测 1.0.13 ✓）**换源遮罩** ✓ —— 一次治两个体验问题：
                      //   ① 「划到下一条，先看到上一条的帧约 1.2 秒」✗：`kp.open()` 换源用的是**同一个**
                      //      `Video`/controller ✓（不能重建 ✗，历史坑 ✓）→ 纹理里**还是上一帧** ✗；
                      //   ② 「点卡片进来要等几秒才有画面」✗：同一段等待期 ✓。
                      // 判据用 `position` ✓：`KpPlayer.open()` 会先把 position 清 0（见 player_widget.dart:256-262 ✓），
                      // 新源真的走起来才会 > 0 ✓ → 这段时间用**本条封面**（黑底 + 图 + 转圈）盖住 ✓。
                      // ⚠️ **必须 `IgnorePointer`** ✓：否则会把点击/竖滑全吃掉 ✗（点按与左右划仍归下面的 `_GestureLayer` ✓）。
                      // ⚠️ **黑底必需** ✓：封面图本身还要下载 ✓（一般刚在网格/上一条见过 → 命中图片缓存 ✓ 秒出 ✓）。
                      ValueListenableBuilder<KpState>(
                        valueListenable: _kp ?? _idle,
                        builder: (c, s, _) {
                          if (s.position > Duration.zero) {
                            return const SizedBox.shrink(); // 新画面已经在走 → 撤遮罩 ✓
                          }
                          return Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                color: Colors.black,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if ((art?.cover ?? '').isNotEmpty)
                                      FetchedImage(url: art!.cover, fit: BoxFit.contain),
                                    const Center(
                                      child: SizedBox(
                                        width: 22, height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      // ⚠️ 2026-10-03 修（用户实测 1.0.11「左上角两个 X 重叠」＋「暂停时两条标题」✗，lead 确认 ✓）：
                      //    这层原来是多画的 —— **一个无圆底的 X**（与外层暂停层的圆底 X 重复 ✗）+ **一份不加粗的标题**
                      //    （与贴底的加粗标题条重复 ✗）→ **整层删掉** ✓：X 只留圆底的、标题只留贴底那条 ✓
                      //    注：**▶ 暂停标志不在这层里** ✓ —— 它挂在它自己的暂停守卫上（见本文件 :365），已确认还在 ✓
                    ],
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
            // ⚠️ 2026-10-03（用户要求）：暂停时正中显示**暂停标志** ✓（与本层的 X 同一层，跟着 _playing 刷新 ✓）
            // ⚠️ 2026-10-03 补：原来这里**漏了暂停守卫** ✗ —— 播放中画面正中也常挂一个 96px 半透明 ▶ ✗；
            //    补上后与下面同层的圆底 X 一致：都只在**暂停时**出现 ✓
            if (!_playing)
              const Positioned(
                left: 0, right: 0, top: 0, bottom: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Icon(Icons.play_arrow_rounded, color: Color(0xB3FFFFFF), size: 96),
                  ),
                ),
              ),
            if (!_playing)
              Positioned(
                left: 12,
                top: topPad + 10,
                child: _RoundBtn(
                  icon: Icons.close,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
            // ⚠️ **续拉失败**时才出现的"重试" ✓（用户 2026-10-03：划到底要能自己救回来 ✓）——
            //    放在 X 右边（12 + 40 + 8 = 60 ✓）、同在状态栏之下 ✓、同样只在暂停时可见 ✓
            if (!_playing && _tailFailed)
              Positioned(
                left: 60,
                top: topPad + 10,
                child: _RoundBtn(
                  icon: Icons.refresh,
                  onTap: () {
                    setState(() => _tailFailed = false);
                    _loadMore();
                  },
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
