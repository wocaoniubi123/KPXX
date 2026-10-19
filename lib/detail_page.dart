import 'package:flutter/material.dart';

import 'app_bg.dart';
import 'api.dart';
import 'app_background.dart';
import 'base/downloads/download_manager.dart';
import 'base/downloads/download_model.dart';
import 'base/downloads/download_sheet.dart';
import 'favorites.dart';
import 'fetched_image.dart';
import 'home_page.dart';
import 'main.dart' show kNavObserver; // ★ ⑦：全局路由观察者（订阅"被压栈 / 回到栈顶" ✅）
import 'models.dart';
import 'player_widget.dart';
import 'settings.dart';
import 'sites.dart';
import 'web_page.dart';

/// 文章详情：顶部视频 + 标题/标签 + 选集 + 正文图片。
class DetailPage extends StatefulWidget {
  final SiteEntry site;
  final String baseUrl; // /archives/xxx/

  /// 从「播放记录」点进来时传：续播位置。
  /// 从站点入口（宫格/列表/相关推荐/标签…）进来一律不传 → null → 从头播（用户要求）。
  final Duration? initialPosition;

  /// 从「播放记录」点进来时传：篇内第几个视频（多视频文章续播用）
  final int initialVideoIndex;

  /// 列表页已经加载过的封面 URL（**播放记录/收藏/下载三处都优先用它当封面**，零额外请求）；
  /// 从站点入口/文字链进来时可能为空 → 三处统一退回正文首图（剧照）兜底
  final String listCover;

  const DetailPage({
    super.key,
    required this.site,
    required this.baseUrl,
    this.initialPosition,
    this.initialVideoIndex = 0,
    this.listCover = '',
  });

  @override
  State<DetailPage> createState() => DetailPageState();
}

/// ⚠️ 这里用 **`implements RouteAware`**（不用 `with RouteAware`）—— 本机没有 Flutter SDK、编译只能交 CI ✅，
///   所以取**不依赖**"`RouteAware` 在该版 Flutter 里是不是 `mixin class`"的写法 ☑️（零编译风险 ✅）；
///   代价 = 四个方法都得自己写（其中 `didPush`/`didPop` 是空的 ✅ 本页不需要动作 ✅）。
class DetailPageState extends State<DetailPage> implements RouteAware {
  late final Api _api = Api(site: widget.site);
  ArticleDetail? _detail;

  /// ★ 2026-10-12（用户批准 ✅ · 修"播放记录串剧"）：**这份 `_detail` 属于哪条 url** ——
  ///   只给 [_writeRecord] 开头那道"归属校验"用（宁可少写一条记录，绝不写串 ☠）。
  ///   ⚠️ **每次给 `_detail` 赋值都必须同时更新它**（`_load()` / `_refreshSources()` 两处 ✅）；
  ///   `baseUrl` 原地变化时 [didUpdateWidget] 会把它清成 null ⇒ 新剧详情到位前不写任何记录 ✅。
  String? _detailUrl;

  String? _error;
  List<Article> _series = []; // 当前系列文章（含当前集）
  /// 篇内视频切换（多视频文章；详情页/内嵌播放器/全屏页共用同一份）
  VideoSwitcher? _switcher;

  // ---------------------------------------------------------------------------
  // ★ 2026-10-08（用户拍板 ④ + ⑦ ✅）：**"跳走停、返回续播" + "只有当前显示的那一页写记录"**
  //
  // 实现收口在 RouteAware（`kNavObserver` ✅）—— 这样**任何** push（剧照 ✓ 相关推荐 ✓ 标签页 ✓
  // Web 页 ✓ 「猜你喜欢」格子卡 ✓ 以及以后新增的任何入口 ✓）都自动走同一套，
  // 比"每个跳转点手写一遍"更全 ✅（格子卡那种"导航在别处（`ArticleCard`）内部发起的"也兜得住 ✅）。

  /// 本页是不是被别的路由**压到了栈下面**（= 不再是"当前显示的那一页"）
  bool _pushedAway = false;

  /// ★ ⑦ 红线：**只续"我们自己停的"** ✅ —— 跳走那一刻"本来在播"才记 true；
  ///   用户**手动暂停**过再跳走 ⇒ 恒为 false ⇒ 回来**必须仍然暂停** ✅。
  bool _pausedByPush = false;

  /// 订阅用的那条路由（`didChangeDependencies` 里对一遍；`dispose` 里退订 ✅）
  PageRoute<dynamic>? _subscribedRoute;

  /// 内嵌播放器的 key：离开页面时要直接从它身上取最后位置（补写播放记录）
  final GlobalKey<PlayerWidgetState> _playerKey =
      GlobalKey<PlayerWidgetState>();

  /// 「清晰度」用户手选的档（null = 用 Api 给的默认档：那已经是 720P 优先，
  /// 没有 720P 就是最高档 —— 见 api.dart 的 `_phDetail`）。只有多档的视频才有意义。
  String? _quality;

  /// ★ 下载（用户指定：顶栏「下载」在收藏左边）：任务 key 与 Favorites **同一套口径**
  ///   （`'$站点名|$详情页相对路径'`，见 `favorites.dart` 的 `FavoriteItem.key`）。
  String get _downloadKey => '${widget.site.name}|${widget.baseUrl}';

  /// 播放器控制条那颗下载按钮当前该画哪一态（'none' / 'downloading' / 'done'）。
  /// 每次 `build` 按**当前集**算一遍（播放器只从构造参数取，见 `PlayerWidget.downloadStatus`）。
  String _downloadStatus = 'none';

  /// 正在为"当前这一集"取源入队（防连点：合集类取源最长要几秒）
  bool _downloadCurrentBusy = false;

  /// 从源 URL 里抠清晰度数字。兼容两种命名：
  /// Pornhub `.../1080P_4000K_xxx.mp4/master.m3u8`（大写 P + 下划线）、
  /// XVideos `.../hls-720p.m3u8`（小写 p，后跟 `.`/`?` 等非数字）。
  /// 抠不到（单档/无档位信息）返回 ''。
  ///
  /// ⚠️ 2026-10-02 xHamster 实锤：**必须先取路径最后一段（文件名）再匹配** ——
  /// 它的 URL 里带着 `media=hls4/multi=256x144:144p,426x240:240p,854x480:480p,…`
  /// 这种**解析参数**，直接对整个 URL 匹配会**先命中参数里的 `144p`**，
  /// 结果 5 档被全部认成 144P（实测：1080p/720p/480p/240p/144p → 全报 144P）。
  /// 只看文件名对其它站也更稳（XV 的 `hls-720p.m3u8`、PH 的 `1080P_4000K_…` 照样命中）。
  static String _qualityOf(String u) {
    final path = u.split('?').first; // 去掉查询参数 ✓
    // ⚠️ 2026-10-03 修（用户报「Pornhub 的分辨率选择丢失」✗）：
    // 原来只拿**最后一段路径**去匹配 ✗ —— 而 Pornhub 的源是
    //   `.../720P_4000K_63006305.mp4/master.m3u8`  ✗
    // 最后一段是 `master.m3u8` ✗ → 匹配不到档位 → `_qualitiesOf` 为空 → **选择器整块不显示** ✗。
    // 现在改成在**整个路径**（已去 query ✓）里找档位 ✓：
    //   · Pornhub 的 `720P_4000K_…` ✓ 命中 720
    //   · xHamster 的 `hls-720p.m3u8` ✓、XVideos 同理 ✓
    //   · query 里的 `multi=…:144p,…` 仍被排除 ✓（那是 2026-10-02 修过的坑 ✓）
    final m = RegExp(r'(\d{3,4})[pP](?![0-9])').firstMatch(path);
    return m?.group(1) ?? '';
  }

  /// 这一集**实际有的**档位（去重、数字从大到小）。多数站没有多档 → 返回空
  static List<String> _qualitiesOf(List<String> srcs) {
    final byQ = <String, int>{};
    for (final u in srcs) {
      final q = _qualityOf(u);
      if (q.isNotEmpty) byQ[q] = int.parse(q);
    }
    final ks = byQ.keys.toList()..sort((a, b) => byQ[b]!.compareTo(byQ[a]!));
    return ks;
  }

  /// 播放器实际会先用哪一档 = 源列表第一条的清晰度（Api 已按"720P 优先"排好）
  static String _firstQuality(List<String> srcs) =>
      srcs.isEmpty ? '' : _qualityOf(srcs.first);

  /// 交给播放器的源：选中的档排最前（播放器按顺序逐个试，失败自动往下走）
  static List<String> _orderByQuality(List<String> srcs, String? q) {
    if (q == null || q.isEmpty) return srcs;
    return [
      ...srcs.where((u) => _qualityOf(u) == q),
      ...srcs.where((u) => _qualityOf(u) != q),
    ];
  }

  @override
  void initState() {
    super.initState();
    // ★【常驻诊断】本页 State 建立（"返回后播放器假死/黑屏"先看这条：同一条 url 出现两次 = 页面被重建过 ✓）
    if (AppSettings.i.logConsole) {
      final pInit = Uri.tryParse(widget.baseUrl)?.path ?? widget.baseUrl;
      debugPrint('[DETAIL] initState path=${pInit.length <= 80 ? pInit : pInit.substring(0, 80)} 初始集=${widget.initialVideoIndex} 位置=${widget.initialPosition?.inMilliseconds ?? 0}ms');
    }
    _load();
    // ★ 下载：读一次盘（幂等）+ 监听状态 —— 控制条图标 / 弹层里的"已下载·下载中"要跟着变。
    //   ⚠️ 监听器只在**当前集的状态真的变了**时 setState（见 [_onDownloadChanged]）：
    //   下载进度每 250ms 通知一次，不能让它把整页（含播放器）每 250ms 重建一遍 ☠。
    DownloadManager.i.load();
    DownloadManager.i.addListener(_onDownloadChanged);
  }

  /// ★ 2026-10-12（用户批准 ✅ · **断根**）：`baseUrl` 变了 ⇒ **本页整体清整 + 重载**。
  ///
  /// 【为什么必须加】本页原来**没有 `didUpdateWidget`** ⇒ 一旦被"原地换 url"（widget 更新而 State 复用），
  ///   `_detail` 仍是**上一部剧**的 ⇒ `_writeRecord`（全仓唯一落盘点）就写出"A 的 url + B 的标题" ☠。
  ///   实测依据见 [_writeRecord] 开头那段：prefs 里两条柚子短剧记录**相差 48.001 秒、进度 8→56**、
  ///   `t/n/d` 全是前一部剧的 🛢️（= 同一次播放的连续上报，url 中途被换）。
  ///
  /// 【清整清单 · 逐项理由】
  ///   ① `_switcher`：**先 `pause()` 再 `dispose()` 再置 null** —— 停掉旧剧的播放意图，丢掉篇内序号对象
  ///      ⇒ 新剧详情到位前**不会继续播旧剧**（`_detail = null` 后 build 走 `d == null` 分支 ⇒
  ///      `PlayerWidget` 整棵被卸载、旧引擎随之退场 ✅）。
  ///   ② `_detail` / `_detailUrl`：清掉 ⇒ 归属校验立刻失效（这段时间**任何**上报都不落盘 ☑️ 不写串）。
  ///   ③ `_error`：清掉 ⇒ 新剧从"载入中"干净起步（不残留上一部的错误横幅/重试态）。
  ///   ④ `_series`：它是"**当前**系列文章（含当前集）" ⇒ 属于上一部剧，必须丢（否则选集横条串剧）。
  ///   ⑤ `_lastPos` / `_lastDur` / `_lastFinished`：`_flushProgress` 的兜底值 ⇒ 不清的话，
  ///      新剧第一次上报前若发生补写，会拿**旧剧的位置/时长**去写 ☠。
  ///   ⑥ `_quality`：手选清晰度跟着"这一集/这部剧" ⇒ 不带过去（`_load()` 会按新 url 的记录重新取 ✅）。
  ///   ⑦ `_pausedByPush`：那笔"我们自己停的"属于旧剧 ⇒ 清掉，回栈顶时不会误给新剧续播 ☑️。
  ///      （`_pushedAway` / `_subscribedRoute` / `_playerKey` **不动**：它们描述"本页在路由栈里的位置"，
  ///        与 url 无关 ✅。）
  ///   ⑧ 最后 `_load()`：按**新** `widget.baseUrl` 重新拉详情（它开头就会置加载态 ✅）。
  ///   ⚠️ `widget.initialVideoIndex` / `initialPosition` 是**新 widget 自带**的值 ⇒ 新剧续播照旧生效 ✅。
  ///   ⚠️ 已知边界：`_api`（`late final`）绑的是 `widget.site` ⇒ **同一站点内换 url 没问题**；
  ///      若哪天有调用方连 `site` 一起换，这里只记日志、不重建 `_api`（需要时另行拍板 ☑️）。
  ///
  ///   ⚠️ 本方法里**直接给字段赋值、不 setState**（紧跟其后的 build 会照新状态渲染 ✅）；
  ///      `_load()` 内部本来就有 setState（在"被祖先 build 触发"的语境下是合法的 ✅）。
  @override
  void didUpdateWidget(covariant DetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baseUrl == widget.baseUrl) return;
    if (AppSettings.i.logConsole) {
      final pOld = Uri.tryParse(oldWidget.baseUrl)?.path ?? oldWidget.baseUrl;
      final pNew = Uri.tryParse(widget.baseUrl)?.path ?? widget.baseUrl;
      debugPrint('[DETAIL] didUpdateWidget：baseUrl 变了 ⇒ 清整 + 重载 '
          'old=${pOld.length <= 80 ? pOld : pOld.substring(0, 80)} '
          'new=${pNew.length <= 80 ? pNew : pNew.substring(0, 80)} '
          '站点也变=${oldWidget.site.name != widget.site.name}');
    }
    _switcher?.pause();
    _switcher?.dispose();
    _switcher = null;
    _detail = null;
    _detailUrl = null;
    _error = null;
    _series = [];
    _lastPos = null;
    _lastDur = Duration.zero;
    _lastFinished = false;
    _quality = null;
    _pausedByPush = false;
    _load();
  }

  // ---------------------------------------------------------------------------
  // ★ ⑦：RouteAware —— "跳走停、返回续播"（本页被压栈 / 回到栈顶两条回调）

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final pr = route is PageRoute<dynamic> ? route : null;
    // ★【常驻诊断】重复订阅判据（"同一条 route 又订一次 / 没订上"看这条 ✓）
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] didChangeDependencies route=${route?.runtimeType} 可订=${pr != null} 与上次同条=${identical(pr, _subscribedRoute)} 已有订阅=${_subscribedRoute != null}');
    if (identical(pr, _subscribedRoute)) return;
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] RouteAware 同步订阅 pr=${pr?.runtimeType} 先退旧订阅=${_subscribedRoute != null}');
    if (_subscribedRoute != null) kNavObserver.unsubscribe(this);
    _subscribedRoute = pr;
    if (pr != null) kNavObserver.subscribe(this, pr);
  }

  /// ★ ⑦：`RouteAware` 的另外两个回调**本页用不到** ⇒ 空实现 ✅
  ///   （`didPush` = 本页自己被 push 上去 ☑️ 那时还没有内容；`didPop` = 本页自己被弹出 ⇒
  ///   收尾统一在 [dispose] 里做 ✅，不在这里做第二遍 ✗）。
  @override
  void didPush() {
    // ★【常驻诊断】本页自己被推入（RouteAware 回调，与 main.dart 的 [NAV] 配对看 ✓）
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] didPush（本页被推入）pushedAway=$_pushedAway pausedByPush=$_pausedByPush');
  }

  @override
  void didPop() {
    // ★【常驻诊断】本页被弹出（= 用户在详情页按返回）那一刻的三个值 ✓
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] didPop（本页被弹出=返回）pushedAway=$_pushedAway pausedByPush=$_pausedByPush fullscreen=${_playerKey.currentState?.player?.fullscreenOpen ?? false}');
  }

  /// ★ ⑦（用户拍板 ✅）：本页被**另一个页面**压到栈下面 ⇒ **暂停播放 + 停写播放记录** ✅。
  ///   ⚠️ **进全屏不算"跳走"**（全屏页也是 push 上去的路由 ☑️）：那种情况必须继续播 ✅、继续写 ✅
  ///   —— 判据 = 播放器上那个 `fullscreenOpen` 标记（`_openFullscreen` 在 push **之前**置位 ✅）。
  ///   ⚠️ 暂停走 `switcher.pause()`（= 原来那几处用的同一套 ✓），**不是**直接动播放器 ✓。
  @override
  void didPushNext() {
    final kp = _playerKey.currentState?.player;
    // ★【常驻诊断】被压栈这一刻的现场（用户报的"点推荐视频返回后假死"全靠这条定时刻 ✓）
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] didPushNext 进入 pushedAway=$_pushedAway pausedByPush=$_pausedByPush fullscreen=${kp?.fullscreenOpen ?? false} userPaused=${kp?.userPaused ?? false} 引擎playing=${kp?.value.playing ?? false} completed=${kp?.value.completed ?? false} pos=${kp?.value.position.inMilliseconds ?? 0}ms');
    if (kp?.fullscreenOpen ?? false) return; // 进全屏 ⇒ 不是"跳走" ✅（不暂停、不停写）
    _pushedAway = true; // ★ ④：被压栈期间**一律不写**播放记录 ✅（防"进度回弹" ✗）
    // ★ 2026-10-08 修（用户报"点推荐视频跳转、返回原详情页不续播"✗ · **已核实的根因**）：
    //   判据原来是 `kp.value.playing`（= **引擎**状态）☠ —— 本文件之外的既有事实是：
    //   **mpv 在缓冲期就会把 playing 报成 false**（`player_widget.dart` 看门狗那段的注释 ✓），
    //   页面被压到栈下面之后引擎自己停掉也一样 ⇒ "用户明明在看"被判成"没在播" ✗ ⇒
    //   `_pausedByPush` 不置位 ⇒ 回来后按 ⑦ 红线判定"这不是我们停的" ⇒ **不续播** ☠。
    //   现在改成读**用户意图**（`KpPlayer.userPaused` ✓：只有用户自己按过暂停才为 true ✓，
    //   流程内部的换片/换档那两次 pause 已在 `KpPlayer.open` 里复位 ✓）。
    //   ⚠️ 保留一条 `!completed`：**已经播完**的那次（从没被用户暂停过 ✓）不该被当成"待续播" ✓
    //   —— 与旧判据在这一点上的行为**保持一致** ✓。
    final wantPlay = kp != null && !kp.userPaused && !kp.value.completed;
    // ★【常驻诊断】续播判定（true ⇒ 记一笔"我们自己停的" + switcher.pause() ⇒ 回来才续播 ✓）
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] didPushNext 判定 wantPlay=$wantPlay（判据=非用户暂停 且 未播完）');
    if (wantPlay) {
      _pausedByPush = true; // ★ ⑦ 红线：只有"本来在播"才记这一笔 ✅
      _switcher?.pause();
    }
    // ★ 用户拍板（新）：**被压栈期间让控件"先按住、别藏"** —— 播放器那个 3 秒自动隐藏计时器
    //   压到栈下面照样在跑 ✗ ⇒ 回来时控件已经藏掉（表现为"控件消失了" ✗）；
    //   这里按住，回到栈顶再由 [didPopNext] "显示 + 重新起 3 秒" ✅。
    _playerKey.currentState?.holdControls();
    // ★【常驻诊断】收尾：控件已被按住（不被 3 秒计时器藏掉）+ 记下的三个值 ✓
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] didPushNext 收尾 pausedByPush=$_pausedByPush pushedAway=$_pushedAway → holdControls()');
  }

  /// ★ ⑦：回到栈顶 ⇒ **恢复写** ✅（把 `_pushedAway` 解掉），并且**只续"我们自己停的那一次"** ✅
  ///   （用户手动暂停过 ⇒ 跳走时 `userPaused == true` ⇒ `_pausedByPush` 仍是 false ⇒ 这里什么都不做 ✅）。
  @override
  void didPopNext() {
    // ★【常驻诊断】回到栈顶这一刻的现场（与上面 didPushNext 那条配对看 ✓）
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] didPopNext 进入 pushedAway=$_pushedAway pausedByPush=$_pausedByPush fullscreen=${_playerKey.currentState?.player?.fullscreenOpen ?? false} userPaused=${_playerKey.currentState?.player?.userPaused ?? false}');
    _pushedAway = false;
    // ★ 用户拍板（新）：回到栈顶 ⇒ **控件必须显示** ✅（并按老规矩重新起 3 秒自动隐藏 ✓）。
    //   ⚠️ 必须放在下面那句 `if (!_pausedByPush) return;` **之前** ☠ —— 否则"用户自己暂停过再跳走"
    //   那条路会连控件都不显示 ✗（两件事互不影响：显示控件 ≠ 续播 ✅）。
    _playerKey.currentState?.showControls();
    // ★【常驻诊断】控件已恢复显示（在续播判定之前 ✓ 两件事互不影响 ✓）
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] didPopNext 已 showControls() → 续播判定 pausedByPush=$_pausedByPush');
    if (!_pausedByPush) return;
    _pausedByPush = false;
    // ★【常驻诊断】续播排期（1200ms：等**新页面彻底销毁完**再恢复 ✓）
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] didPopNext 排 1200ms 后 switcher.resume()（等新页面销毁完 + 退场动画）');
    // ★ 2026-10-08（本批修 ✓ · 用户实报 + 日志时序）：**延迟 300ms → 1200ms** ——
    //   `resume()` 虽然被调了（日志有「播放 触发源=RouteAware」✓）但**视频没有播起来** ✗：
    //   它和**新详情页的销毁撞在同一秒**（21:39:09 恢复 → 21:39:10 B 的 `_p.dispose()` ✓）——
    //   iOS 上销毁一个 mpv 实例会动全局音频会话，把刚恢复的那一路打断 ☠（且引擎侧无日志 ☠）。
    //   用户实报：「返回之后没有自动续播」「动了 1 秒又停止」✓ ⇒ 时序错开 ✓。
    //   ⚠️ 1.2.6 曾改过 1200ms 又被撤回 —— 那次撤回的**依据**（"dispose 不碰全局所以无影响"）是错的 ✗：
    //      不碰我们自己的全局对象 ≠ 不碰 iOS 的全局音频会话 ✓。这次依据是**日志时序** ✓。
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      // ★【常驻诊断】排期到点：这一刻才真正续播 ✓
      if (AppSettings.i.logConsole) debugPrint('[DETAIL] didPopNext 1200ms 到 → switcher.resume()');
      _switcher?.resume(); // 播放器那侧监听到 ⇒ 调 `play()`（用户意图 ✅）
      kickPlayerFrame(); // ★ 续播/控件/状态刚全变 ⇒ 确保有一帧画出来（防"假死" ✓）
    });
  }

  // ---------------------------------------------------------------------------
  // 播放记录：详情页是唯一的归档点（播放器只管每 10 秒回调一次 + 离开时给最后位置）

  /// 最后一次上报的进度（离开页面时补写用）
  Duration? _lastPos;
  Duration _lastDur = Duration.zero;
  bool _lastFinished = false;

  /// 播放器回调：位置/时长/播完都齐了才写（时长还没拿到就不记，免得进度算成 0）
  /// 续播位置：**不管从哪点进来**，只要播放记录里有这条视频就续 ✓（用户 2026-10-03 要求）
  ///
  /// ⚠️ 三种**不续**的情况：① 没记录 ✓ ② 已播完 ✓ ③ **只剩不到 5 秒** ✓
  /// （③ 的阈值是用户 2026-10-03 定的：改成「最后 5 秒」✓ —— 免得点进去立刻又播完 ✓）
  Duration? _resumeFrom() {
    try {
      final r = PlayHistory.i.find(widget.site.name, widget.baseUrl);
      if (r == null || r.position <= Duration.zero) {
        // ★ 2026-10-12（**用户口径 · 分级读取** ✅）：播放记录没有 ⇒ **回落到收藏自己那份进度** ——
        //   用户原话："如果有收藏就存 2 份，播放记录一份，收藏一份。省得冲突，记录进度的时候判断一下
        //   这个视频有没有进收藏" ⇒ 删掉播放记录后收藏里**仍显示进度**，那点进去就必须**续播到那个位置**
        //   （否则又回到"显示有进度、播却从 0"的不一致 ☠）。
        //   实现：`Favorites.i.find`（`favorites.dart:150` 新增的**只读**取法 ✅）
        //   · 判据用收藏自己的 `hasProgress`（= `duration > 0`，`favorites.dart:66` ✅）——
        //     老收藏（没有 `'p'/'d'` 字段）⇒ false ⇒ 不续 ✅（旧数据兼容，绝不崩 ✅）；
        //   · "不能续"的两条与记录那条**同口径**：位置为 0 ⇒ 不续；**只剩 ≤5 秒** ⇒ 不续 ✅
        //     （收藏没有 `finished` 字段 ⇒ 用 5 秒阈值兜 ☑️）。
        final f = Favorites.i.find(widget.site.name, widget.baseUrl);
        if (f == null || !f.hasProgress || f.position <= Duration.zero) {
          return null;
        }
        if ((f.duration - f.position) <= const Duration(seconds: 5)) return null;
        return f.position;
      }
      if (r.finished) return null;
      if (r.duration > Duration.zero &&
          (r.duration - r.position) <= const Duration(seconds: 5)) {
        return null;
      }
      return r.position;
    } catch (_) {
      return null; // 查记录失败绝不拦播放 ✓
    }
  }

  void _reportProgress(Duration pos, Duration dur, bool finished) {
    // ⚠️ 2026-10-03（用户报「跳进度后自动重试又从头开始」）：
    // **跳变**（拖/点/滑进度条 ✓）= 用户指定了新位置 → 立刻把新位置写进记录 ✓，
    // 这样随后即使自动重试/重载换源，也能从**你要的位置**续播 ✓，而不是回到 0 ✗。
    // （普通前进维持原样 ✓，不额外增加写盘 ✗）
    final jumped = _lastPos != null &&
        (pos - _lastPos!).abs() >= const Duration(seconds: 10);
    _lastPos = pos;
    _lastDur = dur;
    _lastFinished = finished;
    if (dur <= Duration.zero) return;
    // ⚠️ 跳变（拖/点/滑进度条）= 用户指定了新位置 → **绕过节流立刻落盘** ✓
    _writeRecord(pos: pos, dur: dur, finished: finished, force: jumped);
  }

  /// 离开时补写：播放器实例还在（dispose 前调用），位置从它身上直接取
  /// ⚠️ **只给"非锁树期"的调用点用** ✅（现仅 `_pickQuality` :640 选清晰度那条 ⇒ 保持同步写、行为不变 ☑️）。
  ///    `dispose()` **不要**再调它 —— 那里必须走 [_flushProgressDeferred]（依据见该方法的注释 ☠）。
  void _flushProgress() {
    final kp = _playerKey.currentState?.player;
    final pos = kp?.position ?? _lastPos;
    final dur = kp?.value.duration ?? _lastDur;
    if (pos == null || dur <= Duration.zero || pos <= Duration.zero) return;
    _writeRecord(
      pos: pos,
      dur: dur,
      finished: kp?.value.completed ?? _lastFinished,
    );
  }

  /// ★ 2026-10-12（用户批准 ✅ · 修 `setState() … widget tree was locked`）：**`dispose()` 专用的补写**
  ///   —— **同步取现场 + 微任务写**（采用方案 A，理由与风险见下）。
  ///
  /// 【依据 · 用户侧 verify-4 的完整堆栈 🛢️】
  /// ```
  /// DetailPageState.dispose → _flushProgress → _writeRecord → PlayHistory.touch
  ///   → ChangeNotifier.notifyListeners → _AnimatedState._handleChange（设置页预览行/播放记录页）
  ///   → Element.markNeedsBuild 断言：setState() … widget tree was locked
  /// ```
  /// 原因：`dispose()` 发生在 Flutter **卸载控件树**期间（`lockState(_inactiveElements._unmountAll)`）
  ///   ⇒ 这段时间里任何 `markNeedsBuild` 都会撞断言（异常被 `notifyListeners` 的 try/catch 上报，
  ///   不崩，但**那一次监听页刷新被吞掉** ☠）。
  /// 同一处紧跟着的 `Favorites.i.touch(...)`（在 `_writeRecord` 末尾）**同样是通知** ⇒ 一并被本方法覆盖 ✅。
  ///
  /// 【为什么选 A（而不是改公共存储类的通知时序）】
  ///   · B 方案（`PlayHistory.touch`/`Favorites` 内部 `scheduleMicrotask(notifyListeners)`）会动**公共存储类**
  ///     的通知时序 ⇒ 影响所有调用方（详情页每 10 秒上报、设置页预览、播放记录页、收藏页、排序刷新…），
  ///     风险面大 ☠；A 只影响"离开页面这一笔"，**范围最小** ✅。
  ///
  /// 【挪动的代价 · 已核清】
  ///   · **现场必须同步取**（上面那几行）：微任务执行时本页子树**已经卸载** ⇒ `_playerKey.currentState`
  ///     会是 null ⇒ 只能退回 `_lastPos`（播放器每 2 秒上报一次 ⇒ 最多旧 ~2 秒）☠。
  ///     所以这里**同步**先把 `pos/dur/finished` 抓下来 ⇒ 与原来的同步写法**数值完全一样**，**不降级** ✅。
  ///   · `_switcher` 也**同步**抓住并**延后** dispose：`_writeRecord` 要读 `sw.index.value`，
  ///     若先 dispose 会踩"ValueNotifier used after dispose" ☠ ⇒ 顺序必须是"**先写记录、再 dispose**" ✅。
  ///   · **写丢失风险**：微任务在"当前同步块结束后"立即执行（同一事件循环、早于下一帧，量级 = 毫秒）
  ///     ⇒ 只有"进程被强杀/isolate 终止"才可能不跑；而那种情况下**原来的同步路径也不保证落盘**
  ///     （`touch()` 内部的 `_save()` 本来就是异步写 SharedPreferences ✅）⇒ **A 没有引入新的必然丢失路径** ✅
  ///     ⇒ 因此**不需要**再加 `AppLifecycleState.detached` 之类的同步兜底 ☑️。
  ///   · 逐行核过：本方法 + `_writeRecord()` 都**不碰 `context`/`mounted`/`setState`**（只用自身字段与 `widget.*`），
  ///     所以推迟到微任务后调用是安全的 ✅。
  void _flushProgressDeferred() {
    final kp = _playerKey.currentState?.player;
    final pos = kp?.position ?? _lastPos;
    final dur = kp?.value.duration ?? _lastDur;
    final finished = kp?.value.completed ?? _lastFinished;
    final sw = _switcher; // 同步抓住（微任务里还要用它读集号，见上面"代价"那条 ☠）
    Future.microtask(() {
      // ① 写记录（= 会 notifyListeners ⇒ 监听页 setState）：此刻锁树期已结束 ✅
      if (pos != null && dur > Duration.zero && pos > Duration.zero) {
        _writeRecord(pos: pos, dur: dur, finished: finished);
      }
      // ② 写完再解掉篇内序号（原来在 dispose 里紧跟 `_flushProgress()` 那一句 ⇒ 位置不变，只是晚了 1 个微任务）
      sw?.dispose();
    });
  }

  void _writeRecord({
    required Duration pos,
    required Duration dur,
    required bool finished,
    bool force = false, // true = 绕过节流立刻落盘 ✓（跳进度时用）
  }) {
    // ★ 2026-10-08（用户拍板 ④ ✅）：**只有"当前显示的那一页"写** —— 被别的页压栈期间**一律不写** ✅
    //   （原来被压栈的页照样每 10 秒写一次 ⇒ 把前台那页的进度**顶回去** ⇒ 表现就是"进度回弹" ✗）。
    //   ⚠️ 进全屏**不算被压栈**（同一个播放器、同一个位置 ⇒ 不可能回弹 ✅；而且全屏看几十分钟
    //   也要照常落盘 ✅ —— 否则 App 被杀就丢进度 ✗）；判据就是 `_pushedAway` 怎么置的（见 [didPushNext] ✅）。
    if (_pushedAway) return;

    // ★ 2026-10-12（用户批准 ✅ · **止血**）：**归属校验** —— 只写"这份详情确实属于当前 url"的记录。
    //
    // 【依据 · prefs 实测 🛢️】`%APPDATA%\com.example\kpxx\shared_preferences.json` 里那两条柚子短剧记录：
    //   ① {"u":"/dramas/tiktok-sex-system/season-2/",     "t":"抖音性爱系统 · 第2季","n":29,"p":8, "d":113,"ts":1791739493581}
    //   ② {"u":"/dramas/high-school-love-story/season-1/","t":"抖音性爱系统 · 第2季","n":29,"p":56,"d":113,"ts":1791739541582}
    //   · 两条 **时间相差 48.001 秒**、进度 **8 → 56（正好 +48 秒）** ⇒ 是**同一次播放的连续上报** ☠；
    //   · 而 `u` 中途从 B 换成了 A，`t/n/d` 却一直是 B 的 ⇒ 页面 **url 换了、`_detail` 没换** ☠；
    //   · 站点侧已排除（现场抓 A 页：`高中爱情故事 · 第1季`、42 集、封面非空 ⇒ 与记录里的 `n=29/c=''` 不符）。
    // 【原因】本页原来**没有 `didUpdateWidget`** ⇒ 被"原地换 url"时不会重载、也不会校验 `_detail` 归属；
    //   `_writeRecord` 又是**唯一**落盘点（全仓 grep 过）⇒ 于是写出"A 的键 + B 的标题"。
    // 【这条守卫的语义】`_detailUrl` 为空（正在载入 / 刚换页）或与当前 url 不一致 ⇒ **直接不写** ✅
    //   （不为它兜底、不猜 —— 记录可以少一条，绝不能串 ☠）。
    if (_detailUrl != widget.baseUrl) {
      if (AppSettings.i.logConsole) {
        final rawDet = _detailUrl;
        final pDet = (rawDet == null || rawDet.isEmpty)
            ? '(null)'
            : (Uri.tryParse(rawDet)?.path ?? rawDet);
        final pPage = Uri.tryParse(widget.baseUrl)?.path ?? widget.baseUrl;
        debugPrint('[DETAIL] 跳过写记录（详情归属不符）detailUrl=${pDet.length <= 80 ? pDet : pDet.substring(0, 80)} 页url=${pPage.length <= 80 ? pPage : pPage.substring(0, 80)}');
      }
      return;
    }

    final d = _detail;
    if (d == null || d.videos.isEmpty) return; // 纯图文页不记
    // 站点名要和 kSites 里的对得上（记录列表点回来时要靠它反查 SiteEntry）；
    // 详情页收的 site 本来就是 kSites 里那一条，直接用它的 name
    PlayHistory.i.touch(
      PlayRecord(
        site: widget.site.name,
        url: widget.baseUrl,
        title: d.title,
        cover: _coverOf(d),
        videoIndex: _switcher?.index.value ?? widget.initialVideoIndex,
        // ★ 2026-10-10（用户要求 ✅）：本篇共几个视频 —— 区分"电影/单集"与"多集文章的第 1 集" ✅
        //   （两者 videoIndex 都是 0；没这个字段就分不开 ⇒ 老记录 = 0 = 不知道 ✅ 行为不变）
        total: d.videos.length,
        quality: _quality, // ⚠️ A 方案：记住这条视频选过的清晰度 ✓
        position: pos,
        duration: dur,
        finished: finished,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      force: force, // ⚠️ 具名参数必须在位置参数之后 ✓
    );
    // ★ 2026-10-10（用户拍板 ✅）：**收藏**跟着同一套时机刷新"最近观看 + 集号"
    //   （用户口径：收藏列表按"最近观看"降序 ⇒ 看过哪条哪条排最前 ✅）。
    //   ⚠️ `Favorites.touch` **只更新已存在的收藏** ☠ —— 没收藏过就是空操作（**绝不新建、绝不删除** ✅），
    //      所以这里不需要判 `contains`，也不会因为播放而凭空多出收藏 ✅。
    //   ⚠️ 挂这里的理由（与 PlayHistory **完全同一套节奏** ✅）：一处覆盖
    //      "播放中每 ~10 秒（:280）" + "离开详情页/换清晰度补写（:289）"两条时机，
    //      而且沿用本方法既有的两道守卫（`_pushedAway` 被压栈不写 / 纯图文页不记 ✅）。
    //   ⚠️ 不 await：与紧邻的 `PlayHistory.i.touch` 同款（内存先更新、落盘在后台走 ✅）。
    Favorites.i.touch(
      widget.site.name,
      widget.baseUrl,
      _switcher?.index.value ?? widget.initialVideoIndex,
      // ★ 2026-10-10（用户要求 ✅）：把**同一份** pos/dur 也交给收藏自己存 ——
      //   收藏页据此显示 `已看 47% · 1:26 / 3:01`，且**删掉播放记录后依然显示** ✅（不跨读 PlayHistory ☠）；
      //   total 用来区分"电影"与"多集文章的第 1 集" ✅
      position: pos,
      duration: dur,
      total: d.videos.length,
    );
  }

  /// 封面口径（用户 2026-10-19 拍板）：**列表卡片封面优先**（用户在列表里看到的那张），
  /// 没有才退回详情正文图（剧照）兜底；都没有就空着。
  String _coverOf(ArticleDetail d) {
    if (widget.listCover.isNotEmpty) return widget.listCover;
    if (d.images.isNotEmpty) return d.images.first;
    return '';
  }

  /// 播放源（用户 2026-10-19 拍板 A）：**当前集已下载 ⇒ 播本地文件**（file://，0 网络）；
  /// 没下载 / 文件丢了 ⇒ 原逻辑（按清晰度排序的网络源）。
  /// ⚠️ 集下标与下载任务里的 `index` 同一套（建任务时就是 videos 下标）✅
  List<String> _playSourcesOf(List<ArticleVideo> videos, int idx) {
    if (videos.isEmpty || idx < 0 || idx >= videos.length) {
      return const <String>[];
    }
    final local = DownloadManager.i.localPathOf(_downloadKey, idx);
    if (local != null) {
      if (AppSettings.i.logConsole) {
        debugPrint('[DL] 详情页本地优先播放 集=$idx path=$local');
      }
      return <String>[Uri.file(local).toString()];
    }
    return _orderByQuality(videos[idx].sources, _quality);
  }

  // ---------------------------------------------------------------------------
  // 收藏（用户 2026-10-10 拍板 ✅）：与播放记录是**两份独立存储**
  //   （`lib/favorites.dart`，键 `fav_list` ☠ —— 删播放记录不动收藏、删收藏不动播放记录）

  /// 当前这一篇是否已收藏（键 = 站点名 + 详情页相对路径，与 `PlayRecord.key` 同一套口径 ✅）
  bool get _isFav => Favorites.i.contains(widget.site.name, widget.baseUrl);

  /// 顶栏那颗星：收藏 / 取消收藏（同一篇 = 同一条 ⇒ 再点一次就是取消 ✅）。
  /// ⚠️ 取值与写播放记录**同一套**（`_coverOf` / `_switcher.index` ✅）：
  ///   详情还没载入完就点 ⇒ 标题空串、封面走列表封面（没有就空着），照旧能收藏 ✅。
  Future<void> _toggleFav() async {
    final d = _detail;
    final added = await Favorites.i.toggle(
      site: widget.site.name,
      url: widget.baseUrl,
      title: d?.title ?? '',
      cover: d == null ? widget.listCover : _coverOf(d),
      // 集号 = 当前播到第几集（0-based，与 PlayRecord.videoIndex 同一套下标 ✅）
      videoIndex: _switcher?.index.value ?? widget.initialVideoIndex,
      // ★ 2026-10-10：收藏这一刻**手上就有的**三样一起带上 ——
      //   否则"收藏了但还没播"的那条，第 1 集的集号与进度要等下一次上报（约 10 秒）才出现 ☑️。
      //   拿不到就按默认（total 0 = 不知道 ✅ / 0 时长 ⇒ 收藏行**不显示进度** ✅ 缺则隐藏）
      total: d?.videos.length ?? 0,
      position: _lastPos ?? Duration.zero,
      duration: _lastDur,
    );
    if (!mounted) return;
    if (AppSettings.i.logConsole) {
      final path = Uri.tryParse(widget.baseUrl)?.path ?? widget.baseUrl;
      debugPrint('[DETAIL] ${added ? '收藏' : '取消收藏'} path=${path.length <= 80 ? path : path.substring(0, 80)}');
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(
            duration: const Duration(seconds: 1), // ★ 2026-10-10（用户批准）：默认 4 秒 → 1 秒
            content: Text(added ? '已收藏' : '已取消收藏')));
  }

  // ---------------------------------------------------------------------------
  // 下载（用户口径：顶栏「下载」放收藏左边 → 多选弹层；播放器控制条 ↓ 只下当前这一集）

  /// 这一集是否"已加入下载、还在排队"（弹层显示「等待中」用；正在跑的不算）
  bool _isEpisodeQueued(int i) {
    for (final t in DownloadManager.i.tasks) {
      if (t.key != _downloadKey) continue;
      for (final ep in t.episodes) {
        if (ep.index != i) continue;
        return ep.wanted && ep.status == EpStatus.queued;
      }
    }
    return false;
  }

  /// 某一集此刻的下载态：'done' / 'downloading' / 'none'。
  /// 已下载 = 管理器实探（状态 done 且文件还在）；下载中 = 正在跑 **或** 还在队列里
  /// （与播放器控制条同一口径，见用户要求"queued 也算下载中"）。
  String _downloadStatusOf(int i) {
    final mgr = DownloadManager.i;
    final key = _downloadKey;
    if (mgr.isEpisodeDownloaded(key, i)) return 'done';
    if (mgr.isEpisodeDownloading(key, i)) return 'downloading';
    for (final t in mgr.tasks) {
      if (t.key != key) continue;
      for (final ep in t.episodes) {
        if (ep.index != i) continue;
        // ⚠️ 必须看 wanted：任务存全集后，☁️ 只登记集（wanted=false）的 status 也是 queued，
        //    单看 status 会把"从没下过的集"显示成下载中、按钮还点不动 ☠
        if (ep.wanted &&
            (ep.status == EpStatus.queued ||
                ep.status == EpStatus.downloading)) {
          return 'downloading';
        }
        return 'none';
      }
    }
    return 'none';
  }

  /// 下载状态变了 ⇒ 只在"当前这一集的状态真的变了"时重建整页。
  /// （进度回调节流后也是 250ms 一次，不筛的话播放器会跟着每 250ms 重建 ☠）
  void _onDownloadChanged() {
    if (!mounted) return;
    final idx = _switcher?.index.value ?? widget.initialVideoIndex;
    if (_downloadStatusOf(idx) == _downloadStatus) return;
    setState(() {});
  }

  /// 把选中的集解析源、构建成一部剧的 [DownloadTask] 入队。
  /// ★ 用户拍板：任务存**全部集**（离线页列全集：已下载 ✅ 本地播 / 未下载 ☁️ 在线播），
  ///   `wanted` 标记这一集要不要下；**只为勾选的集取源**，☁️ 集的 `sourceUrl` 留空（不发请求）。
  /// 返回：成功入队的集数（= wanted 的集）+ 取源失败的集名（调用方负责提示，失败不阻塞其余集）。
  Future<DlSubmitResult> _downloadEpisodes(List<int> indices) async {
    final d = _detail;
    if (d == null || d.videos.isEmpty) {
      return const DlSubmitResult(0, <String>[]);
    }
    // ★ 绝对播放页 URL（用户口径）：manager 的 Referer 兜底要从 playUrl 取 host，
    //   相对路径取不到 ⇒ 部分站点会 403。`resolve` 对已是绝对地址的 baseUrl 也安全 ✅
    final absUrl = Uri.parse(_api.base).resolve(widget.baseUrl).toString();
    final picked = indices.toSet();
    final eps = <DownloadEpisode>[];
    final failed = <String>[];
    var wantedCount = 0;
    for (var i = 0; i < d.videos.length; i++) {
      final v = d.videos[i];
      var want = picked.contains(i);
      var source = '';
      if (want) {
        var srcs = v.sources;
        final lazy = v.lazyUrl;
        // 合集类：详情页没自带源 ⇒ 现去子文章取（只为勾选的集发请求）
        if (srcs.isEmpty && lazy != null) {
          try {
            srcs = await _api.videoSourcesAt(lazy);
          } catch (_) {
            srcs = const <String>[];
          }
        }
        if (srcs.isEmpty) {
          failed.add(v.label);
          want = false; // 取不到源 ⇒ 别让管理器拿空地址去下（转成 ☁️ 在线集）
        } else {
          // 与播放器同一口径：用户手选的清晰度排最前（没选过 = 站点默认顺序）
          final ordered = _orderByQuality(srcs, _quality);
          if (ordered.isEmpty) {
            failed.add(v.label);
            want = false;
          } else {
            source = ordered.first;
          }
        }
      }
      if (want) wantedCount++;
      eps.add(DownloadEpisode(
        index: i,
        label: v.label,
        playUrl: absUrl, // 绝对地址（Referer 兜底要用 host；Favorites 键仍用相对路径）
        lazyUrl: v.lazyUrl,
        headers: v.headers,
        sourceUrl: source,
        wanted: want,
      ));
    }
    if (wantedCount == 0) return DlSubmitResult(0, failed);
    await DownloadManager.i.enqueueTask(DownloadTask(
      key: _downloadKey, // ⚠️ key 仍用相对路径：与 Favorites / 老记录同口径（换绝对会合并不上）
      site: widget.site.name,
      // ⚠️ detailUrl 保持**相对路径**：downloads_page 拿它当 DetailPage.baseUrl
      //    （站点请求按 'https://host' + path 拼，传绝对会拼坏）；Referer 兜底只读 playUrl
      detailUrl: widget.baseUrl,
      title: d.title,
      // ★ 封面口径与播放记录/收藏一致（用户 2026-10-19）：列表封面优先 → 剧照兜底 → 空
      coverUrl: _coverOf(d),
      intro: d.intro,
      time: d.time,
      duration: d.duration,
      episodes: eps,
    ));
    return DlSubmitResult(wantedCount, failed);
  }

  /// 顶栏「下载」→ 底部多选弹层（公共 [DownloadSheet]；状态口径 = 本页 `_downloadStatusOf`）
  Future<void> _openDownloadSheet() async {
    final d = _detail;
    if (d == null || d.videos.isEmpty) return;
    final r = await showModalBottomSheet<DlSubmitResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DownloadSheet(
        labels: <String>[for (final v in d.videos) v.label],
        // 已下载 / 下载中·排队 都走本页同一套状态口径（与播放器控制条一致）
        isDone: (i) => _downloadStatusOf(i) == 'done',
        isBusy: (i) => _downloadStatusOf(i) == 'downloading',
        // 其中排队那一类显示「等待中」（任务存全集后必须带 wanted 判断）
        isQueued: _isEpisodeQueued,
        onSubmit: _downloadEpisodes,
      ),
    );
    if (!mounted || r == null) return;
    final msg = StringBuffer('已加入下载 ${r.ok} 集');
    if (r.failed.isNotEmpty) {
      msg.write('，${r.failed.length} 集取源失败：${r.failed.join('、')}');
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text(msg.toString()),
    ));
  }

  /// 播放器控制条「下载」→ 只下当前这一集（复用 [_downloadEpisodes] 的解析/入队逻辑）
  Future<void> _downloadCurrent() async {
    if (_downloadCurrentBusy) return; // 取源要几秒，防连点重复入队
    final d = _detail;
    final raw = _switcher?.index.value ?? widget.initialVideoIndex;
    // 与 `_pageView` 的 idx 同一套夹取（换源后视频数可能变少）
    final i = (d == null || d.videos.isEmpty)
        ? raw
        : raw.clamp(0, d.videos.length - 1).toInt();
    _downloadCurrentBusy = true;
    late final DlSubmitResult r;
    try {
      r = await _downloadEpisodes(<int>[i]);
    } finally {
      _downloadCurrentBusy = false;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (r.ok > 0) {
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 1),
        content: Text('已加入下载 ${r.ok} 集'),
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(r.failed.isEmpty ? '没有可下载的源' : '取源失败：${r.failed.join('、')}'),
      ));
    }
  }

  Future<void> _load() async {
    // ★【常驻诊断】载入开始（"重试"按钮也走这里 ✓ 与下面"载入 …"那条配对算耗时 ✓）
    if (AppSettings.i.logConsole) {
      final pLoad = Uri.tryParse(widget.baseUrl)?.path ?? widget.baseUrl;
      debugPrint('[DETAIL] 载入开始 path=${pLoad.length <= 80 ? pLoad : pLoad.substring(0, 80)}');
    }
    setState(() {
      _detail = null;
      _error = null;
    });
    final stopwatch = Stopwatch()..start(); // 只给下面那条日志计时 ✓（请求/错误路径一字不动 ☠）
    try {
      final d = await _api.detail(widget.baseUrl);
      // 这条对着「详情页一直转圈 / 打开后内容缺段」看：请求的 path（截 80）+ 视频/剧照/相关各几条 + 耗时
      final pathOnly = Uri.tryParse(widget.baseUrl)?.path ?? widget.baseUrl;
      if (AppSettings.i.logConsole) debugPrint('[DETAIL] 载入 path=${pathOnly.length <= 80 ? pathOnly : pathOnly.substring(0, 80)} 视频=${d.videos.length} 图=${d.images.length} 相关=${d.related.length} ms=${stopwatch.elapsedMilliseconds}');
      if (!mounted) return;
      _switcher?.dispose();
      final sw = VideoSwitcher(d.videos.length)
        ..index.addListener(_onVideoIndexChanged);
      // 定位到上次看的第几集（越界就回第一集）✓
      // ⚠️ 2026-10-03 用户要求：**不管从哪进来**都要续到上次那一集 ✓ ——
      // 调用方给了集数就用它 ✓（从播放记录点进来）；没给就**自己查记录** ✓。
      // 集号来自 PlayRecord.videoIndex ✓（和 d.videos 同一套下标 ✓，建 switcher 时就应用 → **不会闪第 1 集** ✓）。
      final wantIdx = widget.initialVideoIndex > 0
          ? widget.initialVideoIndex
          : (PlayHistory.i.find(widget.site.name, widget.baseUrl)?.videoIndex ??
              // ★ 2026-10-12（**同一套分级读取** ✅）：播放记录没有 ⇒ 回落到**收藏自己那份**集号 ——
              //   必须与 `_resumeFrom()` 成对：位置取自收藏时，集号也得取自同一条，
              //   否则会"位置是第 3 集的、却从第 1 集开始播" ☠。
              Favorites.i.find(widget.site.name, widget.baseUrl)?.videoIndex ??
              0);
      if (wantIdx > 0 && wantIdx < d.videos.length) {
        sw.index.value = wantIdx;
      }
      // ⚠️ A 方案（用户 2026-10-03 定）：这条视频**上次选过的清晰度**优先 ✓；
      // 没选过 → null → 跟随**站点默认** ✓（用户要求：站点给哪个就播哪个 ✓）
      _quality = PlayHistory.i.find(widget.site.name, widget.baseUrl)?.quality;
      _switcher = sw;
      setState(() {
        _detail = d;
        _detailUrl = widget.baseUrl; // ★ 2026-10-12（用户批准）：记下"这份详情属于哪条 url"（写记录前的归属校验用 ☠）
      });
      // 系列聚合：异步填充，失败静默（无选集不影响主内容）
      if (d.seriesPrefix.isNotEmpty) {
        _fetchSeries(d.seriesPrefix).then((list) {
          if (mounted && list.isNotEmpty) setState(() => _series = list);
        }).catchError((_) {});
      }
    } catch (e) {
      // ★【常驻诊断】载入失败（"详情页一直转圈/空页"看这条 ✓ 截 160 字防超长 ✓）
      if (AppSettings.i.logConsole) {
        final es = '$e';
        debugPrint('[DETAIL] 载入失败 ${es.length <= 160 ? es : es.substring(0, 160)}');
      }
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// 用站点自己的网页播放器打开本篇（应用内 WebView）。
  /// 原生 AVPlayer 在个别片源上跳转会卡死，这里是另一个引擎的出口。
  void _openInWeb() {
    // ★【常驻诊断】点顶栏"用网页播放器打开"（hosts 为空 ⇒ 点了没反应，这里也能看出来 ✓）
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] 点网页播放器 hosts=${widget.site.hosts.length} → ${widget.site.hosts.isEmpty ? '空，直接返回（无跳转）' : 'push Web 页'}');
    if (widget.site.hosts.isEmpty) return;
    // ★ ⑦（用户拍板 ✅）：**不再在这里手动 pause** —— 交给 `didPushNext`（RouteAware）统一收口 ✅。
    //   ⚠️ 先手动停会让 `didPushNext` 读到"本来没在播" ⇒ 记不上 `_pausedByPush` ⇒ 回来**不会**续播 ✗。
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'Web 页'),
        builder: (_) => PageBg(child: WebPage(
          title: widget.site.name,
          url: 'https://${widget.site.hosts.first}${widget.baseUrl}',
        )),
      ),
    );
  }

  /// 视频地址带 auth_key 时效签名，过期后重抓本页拿新地址（播放器失败时会调）
  Future<List<String>> _refreshSources() async {
    // ★【常驻诊断】刷新源被触发（播放器"第二轮兜底"或"中途卡住恢复"都会调它 ✓）
    if (AppSettings.i.logConsole) {
      final pRef = Uri.tryParse(widget.baseUrl)?.path ?? widget.baseUrl;
      debugPrint('[DETAIL] 刷新源开始 path=${pRef.length <= 80 ? pRef : pRef.substring(0, 80)}');
    }
    final stopwatch = Stopwatch()..start(); // 只给下面那条日志计时 ✓
    final fresh = await _api.detail(widget.baseUrl);
    // 这条对着「播着播着断了、重抓本页也救不回」看：path（截 80）+ 重抓回几集 + 首条几条源 + 耗时（首条源 0=这次没救回 ✓）
    final pathOnly = Uri.tryParse(widget.baseUrl)?.path ?? widget.baseUrl;
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] 刷新源 path=${pathOnly.length <= 80 ? pathOnly : pathOnly.substring(0, 80)} 视频=${fresh.videos.length} 首条源=${fresh.videos.isEmpty ? 0 : fresh.videos.first.sources.length} ms=${stopwatch.elapsedMilliseconds}');
    if (!mounted || fresh.videos.isEmpty) return const [];
    final i = (_switcher?.index.value ?? 0)
        .clamp(0, fresh.videos.length - 1)
        .toInt();
    // 顺手整页刷新（简介/剧照也一起更新），当前视频序号保持不变
    _switcher?.total = fresh.videos.length;
    setState(() {
      _detail = fresh;
      _detailUrl = widget.baseUrl; // ★ 2026-10-12（用户批准）：同上（刷新源拿到的是**同一条 url**的详情 ✅）
    });
    return fresh.videos[i].sources;
  }

  /// 「清晰度」那一段（只有多档才画；其它站返回空盒子，不占位）。
  /// 位置照模拟器定稿：标题/选集之后、剧照之前。
  Widget _qualitySection(List<ArticleVideo> videos, int idx) {
    if (videos.isEmpty) return const SizedBox.shrink();
    final srcs = videos[idx].sources;
    final qs = _qualitiesOf(srcs);
    if (qs.length < 2) return const SizedBox.shrink();
    // 手选的档要是这一集没有（换集后可能发生），就退回"播放器实际会用的那档"
    final active = (_quality != null && qs.contains(_quality))
        ? _quality!
        : _firstQuality(srcs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text('清晰度',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: kTxt)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in qs)
              OutlinedButton(
                // 已选中的那颗点自己不做任何事（免得无谓重开一次）
                onPressed: () {
                  // ★【常驻诊断】点了哪一档（"已选中 ⇒ 什么都不做"那条路原来完全看不见 ✓）
                  if (AppSettings.i.logConsole) debugPrint('[DETAIL] 点清晰度 ${q}P 当前=${active}P ${q == active ? '→ 已选中，不动作' : '→ 换档'}');
                  if (q == active) return;
                  _pickQuality(q, srcs);
                },
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  side: BorderSide(color: kChipBorder),
                ),
                // 选中态照 App 里筛选按钮的老规矩：橙色 + " ●"
                child: Text(q == active ? '${q}P ●' : '${q}P',
                    style: TextStyle(
                        fontSize: 13,
                        color: q == active ? const Color(0xFFE8590C) : kTxt)),
              ),
          ],
        ),
      ],
    );
  }

  /// 换档：记住选择，再让播放器用**同一个实例**换一批源重开（不换集、不重建实例）。
  /// **保留播放进度**：先记下当前位置，交给播放器在新源起播后跳过去。
  /// ⚠️ 用 `lastKnownPosition`（最后**真实前进过**的位置）而不是 `position`：
  /// 换源会把 state 里的 position 重置为 0，取到 0 就等于"从头播"。
  void _pickQuality(String q, List<String> srcs) {
    final st = _playerKey.currentState;
    final kp = st?.player;
    final Duration? pos = (kp == null)
        ? null
        : (kp.lastKnownPosition > Duration.zero ? kp.lastKnownPosition : kp.position);
    // ★【常驻诊断】换档：目标档 + 带着走的进度（"换分辨率后从头播"看这条 ✓）
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] 换清晰度 ${_quality ?? '(站点默认)'} → ${q}P 源=${srcs.length}条 续播位置=${pos?.inMilliseconds ?? 0}ms');
    setState(() => _quality = q);
    _flushProgress(); // ⚠️ 选完清晰度**立刻落盘** ✓（把 quality 一起写进记录 ✓，下次这条视频就按它播 ✓）
    st?.switchSources(_orderByQuality(srcs, q), resumeTo: pos);
  }

  /// 篇内序号变了整页重建（播放器据此换源，列表高亮跟着变）
  void _onVideoIndexChanged() {
    if (mounted) setState(() {});
  }

  /// 点击选集就**立即**开始取源（合集 / 黄果选集）——不等播放器重建那几帧；
  /// 播放器随后调 videoSourcesAt 会共享同一个请求（Api 里做了去重）。
  /// 用户要求："点击就立马执行提取播放"。
  void _prefetchLazy(ArticleVideo v) {
    final lz = v.lazyUrl;
    if (lz == null) return;
    // 这条对着「点了某集要等好几秒才出画面」看：**发起预取**这一刻就打（只 host+path 截 80 ✓ 不带 query）
    final uri = Uri.tryParse(lz);
    final pf = uri?.path ?? lz;
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] 预取源 host=${uri?.host ?? '?'} path=${pf.length <= 80 ? pf : pf.substring(0, 80)}');
    _api.videoSourcesAt(lz).then<void>((_) {}, onError: (_) {});
  }

  @override
  void dispose() {
    // ★【常驻诊断】页面销毁这一刻的现场（配 didPop/didPopNext 看"返回后假死" ✓）
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] dispose pushedAway=$_pushedAway pausedByPush=$_pausedByPush 播放器State=${_playerKey.currentState != null} fullscreen=${_playerKey.currentState?.player?.fullscreenOpen ?? false}');
    // ★ ⑦：退订（不退的话观察者里留着已销毁的 State ⇒ 回调打给死对象 ✗）
    if (_subscribedRoute != null) kNavObserver.unsubscribe(this);
    // ★ 下载：退订（DownloadManager 是全局单例，监听器里必须用 mounted 兜底）
    DownloadManager.i.removeListener(_onDownloadChanged);
    // ★ 2026-10-12（用户批准 ✅ · 修 `setState() … widget tree was locked`）：
    //   **锁树期里不能同步写记录** ⇒ 换 `_flushProgressDeferred()`（同步取现场 + 微任务写，依据见其注释 🛢️）。
    //   原来是这两句：`_flushProgress();` + `_switcher?.dispose();`
    //   —— 前者会经 `PlayHistory.touch → notifyListeners → 监听页 setState` 撞断言 ☠；
    //   后者已挪进**同一个微任务**（先写记录、再解篇内序号）⇒ 时序上晚 1 个微任务 ✅。
    _flushProgressDeferred();
    super.dispose();
  }

  Future<List<Article>> _fetchSeries(String prefix) async {
    final d = _detail;
    if (d == null || d.categories.isEmpty) return [];
    final slug = d.categories.first;
    final re = RegExp(r'第\s*(\d+)\s*集');
    final matched = <(int, Article)>[];
    // ⚠️ 2026-10-05 修：两页**并发**取 ✓ —— 原来是 `for` 里 `await`，**串行** ✗（第 2 页白等第 1 页 ✗）。
    //    `Future.wait` 保证**结果顺序与入参一致** ✓（第 1 页仍在最前 ✓，后面还按集号排序 ✓）；
    //    错误语义与原来**等价** ✓：任一页抛错 → 整体抛错 ✓（`eagerError: true` = 第一个错**立刻**抛 ✓，
    //    与"原来第 1 页错就不再往下走"同一手感 ✓；调用方 :231 是静默 `catchError` ✓ 行为不变 ✓）。
    final pages = await Future.wait(
      [for (var p = 1; p <= 2; p++) _api.category(slug, page: p)],
      eagerError: true,
    );
    for (final list in pages) {
      for (final a in list) {
        final m = re.firstMatch(a.title);
        if (m == null) continue;
        final pre = a.title.substring(0, m.start).trim();
        if (pre == prefix) matched.add((int.parse(m.group(1)!), a));
      }
    }
    matched.sort((x, y) => x.$1.compareTo(y.$1));
    // 这条对着「选集那一段是空的 / 少了几集」看：系列前缀 + 请求了几页 + 页里原始共几条 + 按集号匹配到几条
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] 选集 prefix=$prefix slug=$slug 页=2 原始=${pages.expand((l) => l).length} 匹配=${matched.length} 条');
    return [for (final e in matched) e.$2];
  }

  String _fmtTime(String iso) {
    if (iso.isEmpty) return '';
    // "2026-09-28 17:34:23"（站点自带时分秒）→ 原样显示
    if (iso.length >= 19 && iso[10] == ' ') return iso;
    // 2026-09-01T14:57:00+00:00 -> 2026-09-01
    if (iso.length < 10) return iso;
    return iso.substring(0, 10);
  }

  @override
  Widget build(BuildContext context) {
    // 整页跟着背景明暗重建（顶栏 / 标题 / 小字 / 小节标题都读 kTxt）。
    // ⚠️ 必须在 builder 里重建页面：把 widget 实例直接交给 builder，
    // Flutter 会因"实例相同"跳过整棵子树的重建，isDark 翻了也不会刷。
    // ★ 2026-10-08（本批修 ✓ · 用户实报 + 日志实锤）：**同时监听篇内序号** ——
    //   原来只听 `AppBg.i` ✗ ⇒ 点「下一集 / 上一集」时 `switcher.index` 确实变了 ✓，
    //   但**没有任何东西让本页重建** ☠ ⇒ `sources` 还是旧的、播放器收不到新 widget
    //   ⇒ `didUpdateWidget` 不触发 ⇒ **换集看起来"按不动"** ✓
    //   （用户实报：返回后 播放暂停 / 上一集 / 下一集 都按不动；而两个全屏按钮有效 ——
    //    因为它们**直接 push 路由**，顺手把整页逼着重建了一次 ✓）。
    //   日志铁证：`下一集 … 动作=next()` 之后一直静默，直到进全屏那一刻才冒出
    //   `didUpdateWidget index=1 换片=true` ✓。
    //   ⚠️ `_switcher` 还没建好时传 null 项（`Listenable.merge` 会忽略 null ✓）；
    //   `_switcher` 换新实例时本行会重新订阅 ✓（listenables 变了 ⇒ builder 自己换订阅 ✓）。
    return ListenableBuilder(
      // ★ 2026-10-10（收藏 ✅）：把 `Favorites.i` 一并监听 —— 顶栏那颗星（空心/实心 + 主题色）
      //   在收藏/取消收藏后立刻翻，不用等别的重建 ✅（`AppBg.i` / 篇内序号原本就在 ✅）。
      listenable: Listenable.merge(<Listenable?>[
        AppBg.i,
        _switcher?.index,
        Favorites.i,
      ]),
      builder: (context, _) => _pageView(context),
    );
  }

  Widget _pageView(BuildContext context) {
    final d = _detail;
    final videos = d?.videos ?? const <ArticleVideo>[];
    final idx = videos.isEmpty
        ? 0
        : (_switcher?.index.value ?? 0).clamp(0, videos.length - 1).toInt();
    // ★ 全屏顶部标题的集标签：与详情页选集胶囊**同一份** `ArticleVideo.label`（下标同 `_switcher.index`）——
    //   多集时全屏标题拼成 `文章标题 · 第 N 集`（换集实时变 ✅）；单集/电影用不到（全屏侧不加后缀 ✅）
    final epLabels = <String>[for (final v in videos) v.label];
    // ★ 下载：控制条那颗按钮的三态（按**当前这一集**算；换集 ⇒ 本页重建 ⇒ 这里重算 ✅）
    final downloadStatus = _downloadStatusOf(idx);
    _downloadStatus = downloadStatus; // 给 [_onDownloadChanged] 做"是否真的变了"的比较基准
    return Scaffold(
      // 透明：详情页也吃根层背景图（播放器画面本身是视频纹理，不受影响）
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        systemOverlayStyle: kStatusOverlay,
        title: Text(widget.site.name),
        foregroundColor: kTxt, // 标题/图标直接压在图上 → 跟明暗
        actions: [
          // ★ 下载（用户拍板 ✅）：位置 = `actions` **第一个**（收藏星左边，用户口径别挪）
          //   没视频 / 详情还没到位 ⇒ 禁用（灰着，点了没反应）
          IconButton(
            tooltip: '下载',
            icon: const Icon(Icons.download_outlined),
            onPressed:
                (d == null || videos.isEmpty) ? null : _openDownloadSheet,
          ),
          // ★ 收藏（用户 2026-10-10 拍板 ✅）：未收藏 = 空心星 / 已收藏 = **实心星 + 主题色**；
          //   ⚠️ 位置固定在「用网页播放器打开」**左边** ☠（用户口径，别挪）
          //   ⚠️ 状态读的是 `Favorites.i`（同一份存储）；本页 `build` 已把 `Favorites.i` 并进监听
          //      （见 `_pageView` 上方那段 `Listenable.merge` ✅）⇒ 星形立刻跟着翻 ✅
          IconButton(
            tooltip: _isFav ? '取消收藏' : '收藏',
            icon: Icon(
              _isFav ? Icons.star : Icons.star_border,
              color: _isFav ? Theme.of(context).colorScheme.primary : kTxt,
            ),
            onPressed: _toggleFav,
          ),
          // 原生播放器卡的时候换网页那套引擎（hls.js，跳转更快）
          IconButton(
            tooltip: '用网页播放器打开',
            icon: const Icon(Icons.public),
            onPressed: _openInWeb,
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('加载失败：$_error'),
                  TextButton(onPressed: _load, child: const Text('重试')),
                ],
              ),
            )
          : d == null
              ? const Center(child: CircularProgressIndicator())
              // ⚠️ 2026-10-03（用户要求）：下滑看详情信息时，**内嵌播放器一直置顶** ✓
              // 原来播放器是 ListView 的第一个子项 ✗ → 一滚就跟着走、画面看不见了 ✓
              // 现在：播放器固定顶部（不滚动 ✓），下方信息**单独滚动** ✓
              : Column(
                  children: [
                      if (videos.isNotEmpty || d.images.isNotEmpty)
                        PlayerWidget(
                          key: _playerKey,
                        // 不换 key：换片由播放器内部复用同一实例开新源
                        // （重建实例会让全屏页拿着的旧实例失效 → 黑屏）
                          switcher: _switcher,
                          // 用户 2026-10-19 拍板 A：当前集已下载 ⇒ **播本地文件**（0 网络）；
                          // 没下载 ⇒ 原逻辑（按清晰度排序的网络源）
                          sources: _playSourcesOf(videos, idx),
                          referer: _api.base,
                          poster: d.images.isNotEmpty ? d.images.first : '',
                          // ★ 用户要求：全屏（竖版/横屏）顶部显示视频标题；内嵌播放器不显示 ✅
                          title: d.title,
                          // 多集时全屏标题带"第 N 集"（换集实时更新）；单集/电影忽略它 ✅
                          epLabels: epLabels,
                          onRefreshSources: _refreshSources,
                          // 合集类：当前这一集没有源时，按需去子文章取
                          lazyUrl:
                              videos.isEmpty ? null : videos[idx].lazyUrl,
                          onFetchSources: _api.videoSourcesAt,
                          // ★ 2026-10-11（**可选** ✅）：**当前这一集**的额外请求头 ——
                          //   取流要 cookie 的站点（柚子短剧 ✅）靠它；默认 null（其余站点都如此）✅
                          //   ⇒ 行为逐字不变 ✅。刷新源时父级 setState ⇒ 下一轮 open 自动换成新头 ✅。
                          httpHeaders:
                              videos.isEmpty ? null : videos[idx].headers,
                          // 续播：只有从「播放记录」点进来才传（站点入口进来是 null）
                          // ⚠️ 2026-10-03 用户要求：**不管从哪进来**，只要播放记录里有这条就续播 ✓
                        initialPosition: widget.initialPosition ?? _resumeFrom(),
                          onProgress: _reportProgress,
                          // ★ 下载（用户口径）：控制条 ↓ 的按钮只下**当前这一集**；
                          //   downloadStatus 三态：none/downloading/done（只影响图标，不碰播放逻辑）
                          onDownloadCurrent: _downloadCurrent,
                          downloadStatus: downloadStatus,
                        ),
                    Expanded(
                      // ★【常驻诊断·滚动】只包一层 NotificationListener：**不拦截通知**（onNotification 一律 return false ✓）
                      //   滚动行为一字不动 ✓；下面这一棵 ListView 本身没动 ✓
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          // ★ 只记三个节点：开始 / 结束 / （结束时的）是否已滚过"播放器那一屏高"
                          //   ⚠️ ScrollUpdateNotification 每帧都来 ⇒ **绝不打**（防刷屏 ✓）
                          if (AppSettings.i.logConsole) {
                            if (n is ScrollStartNotification) {
                              debugPrint('[DETAIL] 滚动开始 offset=${n.metrics.pixels.toStringAsFixed(1)} 视口高=${n.metrics.viewportDimension.toStringAsFixed(1)} 最远=${n.metrics.maxScrollExtent.toStringAsFixed(1)}');
                            } else if (n is ScrollEndNotification) {
                              final vpW = MediaQuery.sizeOf(context).width;
                              final playerH = vpW * 9 / 16; // 内嵌播放器高（16:9 参照值 ✓）
                              debugPrint('[DETAIL] 滚动结束 offset=${n.metrics.pixels.toStringAsFixed(1)} maxScrollExtent=${n.metrics.maxScrollExtent.toStringAsFixed(1)} 剩余=${(n.metrics.maxScrollExtent - n.metrics.pixels).toStringAsFixed(1)} 到底=${n.metrics.pixels >= n.metrics.maxScrollExtent} 已滚过播放器高(参照${playerH.toStringAsFixed(1)}px)=${n.metrics.pixels > playerH}');
                            }
                          }
                          return false; // ⚠️ 不拦截：滚动行为一字不动 ✓
                        },
                        child: ListView(
                          children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.title,
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: kTxt)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              // ★ 2026-10-08（显示规范「缺则隐藏」✅）：没有时间就**整段不渲染** ——
                              //   原来无条件画那个红火焰图标 ⇒ 没时间的站（野果短剧）会剩一个孤零零的火苗 ☑️
                              if (_fmtTime(d.time).isNotEmpty) ...[
                                const Icon(Icons.local_fire_department,
                                    size: 16, color: Colors.red),
                                const SizedBox(width: 4),
                                Text(
                                  _fmtTime(d.time),
                                  style: TextStyle(
                                      fontSize: 12, color: kTxtSub),
                                ),
                                const SizedBox(width: 12),
                              ],
                              // 显示本篇的视频数（原来显示的是"同系列文章数"，
                              // 一篇挂多个视频但没有"第N集"的文章会显示成 0）；
                              // 图文帖（没有视频）就不显示这一段，别写"0 集"
                              if (videos.isNotEmpty)
                                Text('${videos.length} 集',
                                    style: TextStyle(
                                        fontSize: 12, color: kTxtSub)),
                              // 站点自带时长（如 91porna 的 1:00:39、黄果的 3:34）
                              if (d.duration.isNotEmpty) ...[
                                const SizedBox(width: 12),
                                Text('时长 ${d.duration}',
                                    style: TextStyle(
                                        fontSize: 12, color: kTxtSub)),
                              ],
                              // ★ 2026-10-06（**通用槽位**）：站点自定的元信息（空串 = 不显示 ✅）
                              //   例：野果短剧「连载中 · 播放 38W · 追剧 36931」（站点文件拼好传进来 ✅）
                              if (d.metaLine.isNotEmpty) ...[
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Text(d.metaLine,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 12, color: kTxtSub)),
                                ),
                              ],
                            ],
                          ),
                          // 多视频文章：列出来可切换（按集数排序）
                          if (videos.length > 1) ...[
                            const SizedBox(height: 14),
                            Text('视频（${videos.length}）',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: kTxt)),
                            const SizedBox(height: 6),
                            // 竖屏封面站（黄果短剧）：选集**横向排、按宽度自动换行**
                            // 的胶囊（这站是"第 N 集"这种短标签，竖排太占地方）；
                            // 其它站保持竖排（标题可能很长）——吃瓜社区的帖子视频
                            // （/archives/）label 是长标题，也走竖排
                            if (widget.site.portraitCovers &&
                                !widget.baseUrl.startsWith('/archives/'))
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final (i, v) in videos.indexed)
                                    InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () {
                                        // ★【常驻诊断】点选集（横排胶囊版式）
                                        if (AppSettings.i.logConsole) debugPrint('[DETAIL] 点选集(横排) i=$i "${v.label}" 当前=$idx 自带源=${v.sources.length}条 懒取=${v.lazyUrl != null}');
                                        _prefetchLazy(v); // 点击立即开抓
                                        _switcher?.select(i);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: i == idx
                                              ? const Color(0xFFE8590C)
                                              : const Color(0xFFF0F0F2),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          v.label,
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: i == idx
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color: i == idx
                                                  ? Colors.white
                                                  : const Color(0xFF444444)),
                                        ),
                                      ),
                                    ),
                                ],
                              )
                            else
                              for (final (i, v) in videos.indexed)
                                InkWell(
                                  onTap: () {
                                    // ★【常驻诊断】点选集（竖排版式）
                                    if (AppSettings.i.logConsole) debugPrint('[DETAIL] 点选集(竖排) i=$i "${v.label}" 当前=$idx 自带源=${v.sources.length}条 懒取=${v.lazyUrl != null}');
                                    _prefetchLazy(v); // 点击立即开抓
                                    _switcher?.select(i);
                                  },
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 6),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 22,
                                          height: 22,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: i == idx
                                                ? Colors.deepOrange
                                                : const Color(0x1F000000),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text('${v.ordinal}',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: i == idx
                                                      ? Colors.white
                                                      : Colors.black54)),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            v.label,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: i == idx
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                color: kTxt),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                          ],
                          // 简介
                          if (d.intro.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text('简介',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: kTxt)),
                            const SizedBox(height: 6),
                            Text(
                              d.intro,
                              style: TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: kTxt),
                            ),
                          ],
                          // 选集横条（同系列文章）
                          if (_series.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _buildSeriesStrip(),
                          ],
                          // 清晰度：横排胶囊、**只列这一集实际有的档**（高→低），默认选中
                          // 播放器实际会用的那档；只有一档（或没有档位信息）时不占位。
                          _qualitySection(videos, idx),
                          // 剧照：横向小图，点开看大图
                          if (d.images.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text('剧照',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: kTxt)),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 84,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: d.images.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 6),
                                itemBuilder: (_, i) => InkWell(
                                  onTap: () {
                                    // 看：点开第几张剧照（共几张）—— 大图页空白/错位先看这条。
                                    if (AppSettings.i.logConsole) debugPrint('[DETAIL] 打开剧照 idx=$i n=${d.images.length}');
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        settings: const RouteSettings(name: '图片查看'),
                                        builder: (_) => PageBg(child: PhotoViewerPage(
                                          urls: d.images,
                                          initial: i,
                                        )),
                                      ),
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: SizedBox(
                                      width: 120,
                                      child: FetchedImage(
                                        url: d.images[i],
                                        memWidth: 360,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          // 分类 + 标签：横向单行滚动（点标签跳到对应列表）
                          if (d.categories.isNotEmpty || d.tags.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _buildTagsStrip(d),
                          ],
                          // 相关推荐（规范：必须显示在「剧照」下方）
                          // ★ 2026-10-08（新增通用槽位 ✅ 默认值 ⇒ 老站零变化）：标题与版式都可由站点给 ——
                          //   标题空串 = 「相关推荐」✅；`relatedAsGrid` = 3 列网格 + 角标（野果短剧 ✅）。
                          if (d.related.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                                (_api.ui?.relatedTitle.isNotEmpty ?? false)
                                    ? _api.ui!.relatedTitle
                                    : '相关推荐',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: kTxt)),
                            const SizedBox(height: 6),
                            if (_api.ui?.relatedAsGrid ?? false)
                              // ★ 2026-10-08（用户报"标题两行会被遮挡"✗ 已核实）：原来用
                              //   `GridView.count(childAspectRatio: 0.62)` ⇒ **高度写死** ⇒ 两行标题溢/遮 ✗
                              //   ⇒ 改成与 `RowsGrid` **同一套行语义**（`IntrinsicHeight` + `Row(stretch)`：
                              //   行高 = 该行最高卡 · 行内等高 · 卡片高**随内容自适应** ✅ —— 即"取长补短" ✓）。
                              //   ⚠️ **不能直接用 `RowsGrid`** ✗：它内部是 `ListView`（没有 shrinkWrap）
                              //   ⇒ 嵌在详情页的滚动视图里会"无界高度"报错 ☠（已读它的实现确认 ✅）。
                              Column(
                                children: [
                                  for (var r = 0;
                                      r * 3 < d.related.length;
                                      r++)
                                    Padding(
                                      padding:
                                          EdgeInsets.only(top: r == 0 ? 0 : 8),
                                      child: IntrinsicHeight(
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            for (var c = 0; c < 3; c++)
                                              Expanded(
                                                child: Padding(
                                                  padding: EdgeInsets.only(
                                                      left: c == 0 ? 0 : 8),
                                                  child: (r * 3 + c) <
                                                          d.related.length
                                                      ? ArticleCard(
                                                          article: d.related[
                                                              r * 3 + c],
                                                          site: widget.site)
                                                      : const SizedBox
                                                          .shrink(),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              )
                            else
                            for (final a in d.related)
                              InkWell(
                                onTap: () {
                                  // ★【常驻诊断】点推荐视频（列表版式）：目标 url + 路由方式（"返回后假死"的入口那一下 ✓）
                                  if (AppSettings.i.logConsole) debugPrint('[DETAIL] 点推荐视频(列表版式) url=${a.url} → Navigator.push MaterialPageRoute(name=详情页)，不手动 pause（交给 didPushNext）');
                                  // ★ ⑦（用户拍板 ✅）：原来这里手动 pause ✗ —— 现在**不手动停**，
                                  // 由 `didPushNext`（RouteAware）统一收口：暂停 ✓ 停写 ✓ 回来续播 ✓
                                  // （手动先停会让它读到"本来没在播" ⇒ 记不上 ⇒ 回来不续播 ✗）
                                  Navigator.of(context).push(MaterialPageRoute(
                                    settings: const RouteSettings(name: '详情页'),
                                    builder: (_) => PageBg(child: DetailPage(
                                        site: widget.site, baseUrl: a.url)),
                                  ));
                                },
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: SizedBox(
                                          width: 108,
                                          height: 61,
                                          child: a.cover.isEmpty
                                              ? const ColoredBox(
                                                  color: Color(0xFFEEEEEE))
                                              : FetchedImage(
                                                  url: a.cover,
                                                  memWidth: 320),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          a.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: kTxt),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                              ],
                          ),
                        ),
                      ),
                      ],
                ),
    );
  }

  /// 分类名（站点清单里有就用中文名，没有就显示 slug）
  String _catName(String slug) {
    for (final c in widget.site.categories) {
      if (c.key == slug) return c.name;
    }
    return slug;
  }

  /// 标签/分类：横向单行滚动（放「剧照」下方）
  Widget _buildTagsStrip(ArticleDetail d) {
    final chips = <Widget>[
      for (final c in d.categories)
        _tagChip(_catName(c), () => _openList(_catName(c), c, false)),
      for (final t in d.tags)
        _tagChip('#${t.value}', () => _openList(t.value, t.key, true)),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }

  Widget _tagChip(String text, VoidCallback onTap) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }

  /// 点标签/分类 → 对应列表页
  void _openList(String title, String slug, bool isTag) {
    // ★【常驻诊断】点标签/分类：标题 + slug + 走 tag 还是 category + 路由方式 ✓
    if (AppSettings.i.logConsole) debugPrint('[DETAIL] 点标签/分类 "$title" slug=$slug ${isTag ? 'tag' : 'category'} → Navigator.push MaterialPageRoute(name=标签页)');
    // ★ ⑦（用户拍板 ✅）：同上 —— 不再手动停，交给 `didPushNext` 统一收口 ✅
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '标签页'),
        builder: (_) => PageBg(child: TagListPage(
          site: widget.site,
          title: title,
          slug: slug,
          isTag: isTag,
        )),
      ),
    );
  }

  Widget _buildSeriesStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('选集',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in _series)
              ChoiceChip(
                label: Text(
                  RegExp(r'第\s*\d+\s*集')
                          .firstMatch(a.title)
                          ?.group(0) ??
                      a.title,
                  style: const TextStyle(fontSize: 12),
                ),
                selected: a.url == widget.baseUrl,
                onSelected: (_) {
                  // ★【常驻诊断】点"选集"横条（同系列文章）：手动 pause + pushReplacement ✓
                  if (AppSettings.i.logConsole) debugPrint('[DETAIL] 点系列选集 ${a.url} → ${a.url == widget.baseUrl ? '就是本页，不动作' : 'switcher.pause() + pushReplacement(name=详情页)'}');
                  if (a.url == widget.baseUrl) return;
                  // ★ ⑦（用户拍板 ✅）：这一条**保留手动 pause** —— `pushReplacement` 走的是 `didReplace`，
                  //   被替换掉的这一页**收不到** `didPushNext` ☑️，而且它马上就被销毁 ✅
                  _switcher?.pause(); // 切集同理（旧页马上会被 replace 销毁）
                  // 切集：replace 当前页，避免栈无限加深
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      settings: const RouteSettings(name: '详情页'),
                      builder: (_) => PageBg(child: DetailPage(
                          site: widget.site, baseUrl: a.url)),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// 剧照大图页：左右滑看同一篇的全部剧照，双指缩放，点一下退出。
class PhotoViewerPage extends StatefulWidget {
  final List<String> urls;
  final int initial;
  const PhotoViewerPage({super.key, required this.urls, this.initial = 0});

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final PageController _pc =
      PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          children: [
            PageView.builder(
              controller: _pc,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: FetchedImage(
                    url: widget.urls[i],
                    fit: BoxFit.contain,
                    memWidth: 1600,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    Text(
                      '${_index + 1} / ${widget.urls.length}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(width: 8),
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

/// 标签 / 分类的列表页（详情页点标签或分类跳这里）
class TagListPage extends StatefulWidget {
  final SiteEntry site;
  final String title;
  final String slug;
  final bool isTag; // true = /tag/{slug}/，false = /category/{slug}/
  const TagListPage({
    super.key,
    required this.site,
    required this.title,
    required this.slug,
    required this.isTag,
  });

  @override
  State<TagListPage> createState() => _TagListPageState();
}

class _TagListPageState extends State<TagListPage> {
  late final Api _api = Api(site: widget.site);
  final List<Article> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    _loading = true;
    try {
      final next = widget.isTag
          ? await _api.tag(widget.slug, page: _page)
          : await _api.category(widget.slug, page: _page);
      // 这条对着「标签/分类列表翻不动、少了条目」看：走的是 tag 还是 category + 请求的页号 + 这一页几条
      if (AppSettings.i.logConsole) debugPrint('[DETAIL] 列表 ${widget.isTag ? 'tag' : 'category'} slug=${widget.slug} 页=$_page 本页=${next.length} 条');
      if (!mounted) return;
      setState(() {
        if (next.isEmpty) {
          _done = true;
        } else {
          _items.addAll(next);
          _page++;
        }
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          // ⚠️ 2026-10-05 修：**出错不置 `_done`** ✗ —— 原来置了 → 尾部把失败装成"没有更多了" ✗，
          //    而且 `_done` 会把重试**直接挡掉** ✗（`_more` 第 2 行就 return ✓）。这里只记错 ✓，
          //    尾部据此改显"加载失败，点击重试" ✓（见 `tail` ✓），点了重跑**同一页** ✓（`_page` 没动 ✓）。
          _error = '$e';
        });
      }
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 整页跟着背景明暗重建（顶栏标题 / 尾项文字读 kTxt）
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => _pageView(),
    );
  }

  Widget _pageView() {
    return Scaffold(
      backgroundColor: Colors.transparent, // 同上：吃根层背景图
      appBar: AppBar(
        systemOverlayStyle: kStatusOverlay,
        title: Text(widget.title),
        centerTitle: true,
        foregroundColor: kTxt, // 标题/返回箭头直接压在图上 → 跟明暗
      ),
      body: _items.isEmpty
          ? Center(
              child: _error != null
                  // ⚠️ 2026-10-05 修：整页（首页请求）失败也给**可点**重试 ✓ —— 原来只有一行字 ✗ 走不掉 ✗；
                  //    按钮就照本文件 `:418` 的老写法只写"重试" ✓（上面那行已经写了"加载失败：…" ✓ 不重复 ✗）。
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('加载失败：$_error'),
                        TextButton(
                          onPressed: () {
                            setState(() => _error = null);
                            _more();
                          },
                          child: const Text('重试'),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator())
          : RowsGrid(
              // 竖屏站（黄果）一行 3 个，横屏站一行 2 个
              cols: widget.site.portraitCovers ? 3 : 2,
              // Pektino：瀑布流（横竖混排按顺序填充，不留空档；照站点）
              masonry: _api.ui?.masonry ?? false,
              count: _items.length,
              // 滚动到尾部才构造 → 在那时触发翻页（懒加载）；
              // 到底后显示"没有更多了"，不再空转圈（同列表/搜索页）
              tail: () {
                if (_done) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                        child: Text('没有更多了',
                            style: TextStyle(
                                color: kTxtSub, fontSize: 12))),
                  );
                }
                if (_error != null) {
                  // ⚠️ 2026-10-05 修：翻页**失败** → 给个**可点**的重试 ✓
                  //    （原来失败时 `_done` 被置上 ✗ → 这里显示"没有更多了"、而且点不动 ✗）。
                  //    点一下先撤 `_error` ✓ → 尾部自己回到"转圈"并重跑**这一页** ✓（`_page` 没动 ✓）。
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: TextButton(
                        onPressed: () {
                          setState(() => _error = null);
                          _more();
                        },
                        child: Text('加载失败，点击重试',
                            style: TextStyle(color: kTxtSub, fontSize: 12)),
                      ),
                    ),
                  );
                }
                _more();
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              },
              itemBuilder: (ctx, i) =>
                  ArticleCard(article: _items[i], site: widget.site),
            ),
    );
  }
}
