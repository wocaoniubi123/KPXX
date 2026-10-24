// ★ 2026-10-24（用户要求）：**直播聚合页**（顶栏 4 个分类 tab + 下拉双列选平台 + 主播列表）
//
// 🛢️ 用户 2026-10-24 拍板的口径（逐条对应实现）：
//   ① **主域名首选、备用域名兜底** ⇒ 数据层 `sites/live_zhibo.dart` 的 `ZhiboApi`
//   ② **进页面默认展示「星宝贝」** ⇒ `pickDefaultZhibo()`（按名字找，不写死下标）
//   ③ **顶栏 4 个分类 tab：直播平台1~4** ⇒ `kZhiboTabNames`
//   ④ **点 tab 向下拉出「直播站点选择」** ⇒ 复用 `home_page.dart` 那套悬浮抽屉（Stack + Positioned(top:0)）
//   ⑤ **抽屉里双列展示**（用户："这样就不用拉那么下面了"）⇒ 每组内部 `GridView` 2 列
//   ⑥ **136 个按目录数分 4 组、每组 34 个，第 4 组放最少的 34 个** ⇒ `groupZhibo()`
//   ⑦ **3 个坏平台（土豪/九尾狐 404、龙珠 空文件）直接隐藏** ⇒ `kZhiboHiddenNames`
//
// ⚠️ 播放：直接用 `KpPlayer`（media_kit/mpv，**原生支持 FLV over HTTP** ✅）。
//   接口返回的 `address` **已经带好 `wsSecret`/`wsTime` 签名**，不需要我们计算 ✅。
//   直播没有时长/进度 ⇒ 控制条走"直播模式"（不显示进度条，只有播放/暂停 + 音量）。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:media_kit_video/media_kit_video.dart';

import 'app_background.dart'; // kTxt / kTxtSub / kStatusOverlay
import 'app_bg.dart'; // AppBg（明暗）
import 'fetched_image.dart'; // FetchedImage（全站共用封面组件）
import 'player_widget.dart'; // KpPlayer（media_kit/mpv，原生支持 FLV ✅）
import 'settings.dart'; // AppSettings（logConsole 守卫）
import 'sites.dart'; // SiteEntry（从站点宫格传进来的那个）
import 'sites/live_zhibo.dart';

/// 底栏「直播」宫格点进来 = 这个页面（只有一个直播站：直播聚合）
class LiveZhiboPage extends StatefulWidget {
  const LiveZhiboPage({super.key, this.site});

  /// 从站点宫格进来时传（提供 name / 封面等）；为 null 也能独立使用
  final SiteEntry? site;

  @override
  State<LiveZhiboPage> createState() => _LiveZhiboPageState();
}

class _LiveZhiboPageState extends State<LiveZhiboPage>
    with SingleTickerProviderStateMixin {
  final ZhiboApi _api = ZhiboApi();

  TabController? _tab;

  /// 目录分组（null = 还在拉）
  List<List<ZhiboPlatform>>? _groups;

  /// 目录错误原文（空 = 没出错）
  String _catalogErr = '';

  /// 当前选中的平台（用户明确：默认「星宝贝」）
  ZhiboPlatform? _cur;

  /// 当前展开抽屉的 tab 下标（-1 = 收起）
  int _drawerTab = -1;

  /// 每个平台的主播列表缓存（切平台回来不重拉）
  final Map<String, List<ZhiboRoom>> _rooms = {};

  /// 每个平台自己的加载/错误状态
  final Map<String, bool> _loading = {};
  final Map<String, String> _roomErr = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: kZhiboTabNames.length, vsync: this);
    _tab!.addListener(_onTabChanged);
    _loadCatalog();
  }

  @override
  void dispose() {
    _tab?.removeListener(_onTabChanged);
    _tab?.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    // 滑动切 tab ⇒ 抽屉收起（与 51fans 那套口径一致 ✅）
    if (_drawerTab != -1) setState(() => _drawerTab = -1);
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _groups = null;
      _catalogErr = '';
    });
    try {
      final all = await _api.catalog();
      if (!mounted) return;
      final g = groupZhibo(all);
      setState(() {
        _groups = g;
        _cur = pickDefaultZhibo(g);
      });
      if (AppSettings.i.logConsole) {
        debugPrint('[ZHIBO] 目录 平台=${all.length} 分组=${g.map((e) => e.length).toList()} '
            '默认=${_cur?.name ?? '(无)'}');
      }
      final cur = _cur;
      if (cur != null) unawaited(_loadRooms(cur));
    } catch (e) {
      if (!mounted) return;
      setState(() => _catalogErr = '$e');
    }
  }

  Future<void> _loadRooms(ZhiboPlatform p) async {
    if (_rooms.containsKey(p.name) || _loading[p.name] == true) return;
    setState(() {
      _loading[p.name] = true;
      _roomErr.remove(p.name);
    });
    try {
      final list = await _api.rooms(p);
      if (!mounted) return;
      setState(() {
        _rooms[p.name] = list;
        _loading[p.name] = false;
      });
      if (AppSettings.i.logConsole) {
        debugPrint('[ZHIBO] 平台=${p.name} 主播=${list.length} 条');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading[p.name] = false;
        _roomErr[p.name] = '$e';
      });
    }
  }

  void _pick(ZhiboPlatform p) {
    setState(() {
      _cur = p;
      _drawerTab = -1; // 选完收起抽屉（同 51fans 口径 ✅）
    });
    if (AppSettings.i.logConsole) debugPrint('[ZHIBO] 选平台=${p.name} 目录数=${p.number}');
    unawaited(_loadRooms(p));
  }

  /// 点 tab：点的是当前 tab ⇒ 展开/收起；点别的 ⇒ 只切 tab、不展开（与 51fans 那套逐条一致 ✅）
  void _onTapTab(int i, bool sameTab) {
    setState(() {
      if (!sameTab) {
        _tab?.animateTo(i);
        _drawerTab = -1;
        return;
      }
      _drawerTab = _drawerTab == i ? -1 : i;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => _page(context),
    );
  }

  Widget _page(BuildContext context) {
    final tab = _tab;
    if (tab == null) return const SizedBox.shrink();
    final groups = _groups;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        systemOverlayStyle: kStatusOverlay,
        title: Text(widget.site?.name ?? '直播'),
        centerTitle: true,
        foregroundColor: kTxt,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: _tabRow(tab, groups),
        ),
      ),
      body: Stack(
        children: [
          // ---- 主体：当前平台的主播列表（4 个 tab 共用一个列表，切平台即换数据）----
          Positioned.fill(child: _body(groups)),
          // ---- 抽屉打开时先铺透明屏障：点空白收起、且不穿透到底下列表（同 51fans ✅）----
          if (_drawerTab >= 0)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _drawerTab = -1),
              ),
            ),
          // ---- 抽屉：紧贴 tab 行下方（Positioned(top:0) = body 顶部 = tab 行正下方 ✅）----
          if (_drawerTab >= 0 && groups != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {}, // 面板自身吸收点击（只有面板外的空白才收起 ✅）
                child: _drawerPanel(groups[_drawerTab]),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 顶栏 tab 行（4 个 tab 都带"下拉"语义 —— 点当前 tab 展开抽屉 ✅）
  // ---------------------------------------------------------------------------
  Widget _tabRow(TabController tab, List<List<ZhiboPlatform>>? groups) {
    final dark = AppBg.i.isDark;
    final on = dark ? const Color(0xFFFFB07A) : const Color(0xFFE8590C);
    final off = dark ? Colors.white : const Color(0xFF111111);
    // ⚠️ 不用 TabBar：TabBar 的 onTap 不能"点当前 tab 也触发"（它只在切 tab 时回调）⇒ 自己画 ✅
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          for (var i = 0; i < kZhiboTabNames.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _onTapTab(i, tab.index == i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            kZhiboTabNames[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: tab.index == i
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: tab.index == i ? on : off,
                            ),
                          ),
                        ),
                        // ★ 下拉小箭头（让用户知道"这个 tab 能点下来"）
                        Icon(
                          _drawerTab == i
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 15,
                          color: tab.index == i ? on : off,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // 选中态的 2px 橙色下划线（与全站 tab 风格一致 ✅）
                    Container(
                      height: 2,
                      width: 34,
                      color: tab.index == i ? on : Colors.transparent,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 抽屉面板：**双列**（用户："这样就不用拉那么下面了" ✅）
  // ---------------------------------------------------------------------------
  Widget _drawerPanel(List<ZhiboPlatform> items) {
    final dark = AppBg.i.isDark;
    final bg = dark ? const Color(0xFF1F1F1F) : Colors.white;
    return Container(
      constraints: BoxConstraints(
        // 最多占屏幕 55%（双列 17 行左右，留出下方列表可见，避免"整屏都是面板"）
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: items.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text('这一组暂时没有可用平台', style: TextStyle(fontSize: 12)),
            )
          : GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, // ★ 双列（用户指定 ✅）
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                // 一格 = 封面(16:9) + 名字一行 ⇒ 高度 ≈ 宽/2
                childAspectRatio: 2.35,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final p = items[i];
                final sel = _cur?.name == p.name;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _pick(p),
                  child: Container(
                    decoration: BoxDecoration(
                      color: sel
                          ? const Color(0xFFE8590C).withValues(alpha: dark ? 0.28 : 0.12)
                          : (dark ? const Color(0xFF2A2A2A) : const Color(0xFFF7F7F7)),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: sel
                            ? const Color(0xFFE8590C)
                            : const Color(0x223C3C3C),
                        width: sel ? 1.4 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        // 平台封面（我方 `FetchedImage` 在 base/site_ui.dart，全站共用 ✅）
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: SizedBox(
                            width: 52,
                            height: 32,
                            child: p.cover.isEmpty
                                ? Container(color: const Color(0x223C3C3C))
                                : FetchedImage(url: p.cover, memWidth: 160),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                                  color: kTxt,
                                ),
                              ),
                              Text(
                                '${p.number} 人',
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: kTxtSub,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // 主体：当前平台的主播列表
  // ---------------------------------------------------------------------------
  Widget _body(List<List<ZhiboPlatform>>? groups) {
    if (_catalogErr.isNotEmpty) {
      return _msg('直播接口打不开\n$_catalogErr', retry: _loadCatalog);
    }
    if (groups == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final cur = _cur;
    if (cur == null) return _msg('没有可用的直播平台');

    final list = _rooms[cur.name];
    if (_loading[cur.name] == true) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final err = _roomErr[cur.name] ?? '';
    if (err.isNotEmpty) {
      return _msg('「${cur.name}」加载失败\n$err', retry: () {
        setState(() => _roomErr.remove(cur.name));
        unawaited(_loadRooms(cur));
      });
    }
    if (list == null || list.isEmpty) {
      return _msg('「${cur.name}」暂无主播');
    }
    // 2 列竖版卡（与 xhamsterlive 那套视觉一致：封面上盖名字条 ✅）
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 3 / 4,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) => _RoomCard(
        room: list[i],
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ZhiboRoomPage(room: list[i], platform: cur.name),
              settings: const RouteSettings(name: '直播房间'),
            ),
          );
        },
      ),
    );
  }

  Widget _msg(String text, {VoidCallback? retry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: kTxtSub),
            ),
            if (retry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: retry, child: const Text('重试')),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 主播卡（2 列竖版）
// ---------------------------------------------------------------------------
class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room, required this.onTap});

  final ZhiboRoom room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (room.cover.isEmpty)
              Container(color: const Color(0x223C3C3C))
            else
              FetchedImage(url: room.cover, memWidth: 480),
            // 底部名字条（半透明黑，保证白字在任何封面上都可读 ✅）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                color: const Color(0x99000000),
                child: Text(
                  room.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 直播房间页（KpPlayer 直接播 FLV 直链；直播无时长 ⇒ 不做进度条）
// ---------------------------------------------------------------------------
class ZhiboRoomPage extends StatefulWidget {
  const ZhiboRoomPage({super.key, required this.room, required this.platform});

  final ZhiboRoom room;
  final String platform;

  @override
  State<ZhiboRoomPage> createState() => _ZhiboRoomPageState();
}

class _ZhiboRoomPageState extends State<ZhiboRoomPage> {
  KpPlayer? _kp;
  String _err = '正在打开直播…';

  // ★ 2026-10-24（用户要求"只需要右上角一个 X"）：照 `sites/xhamsterlive.dart:1129` 那套 ——
  //   X **默认隐藏**，点屏幕才出现；出现后 **3 秒自动隐藏**（Timer 必须在 dispose 里 cancel ✅）
  final ValueNotifier<bool> _showX = ValueNotifier<bool>(false);
  Timer? _hideX;

  void _toggleX() {
    _showX.value = !_showX.value;
    _hideX?.cancel();
    if (_showX.value) {
      _hideX = Timer(const Duration(seconds: 3), () {
        if (mounted) _showX.value = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _hideX?.cancel(); // ⚠️ 本仓库硬要求：Timer 一律要 cancel ✅
    _showX.dispose();
    _kp?.removeListener(_onTick);
    _kp?.shutdown();
    _kp = null;
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    final s = _kp?.value;
    if (s == null) return;
    // 起播后清掉"正在打开"（用 position 判断，与播放器那套一致 ✅）
    if (s.position > Duration.zero && _err.isNotEmpty) {
      setState(() => _err = '');
    }
    if (s.error && _err.isEmpty) {
      setState(() => _err = '直播流打不开');
    }
  }

  Future<void> _open() async {
    // ★ 先建引擎（渲染上下文必须在 open 之前，见 `KpPlayer` 构造注释 ✅）
    final kp = KpPlayer(bufferMb: 64); // 直播不需大缓冲
    _kp = kp;
    kp.addListener(_onTick);
    KpPlayer.tuneStartupQuiet(kp); // 起播参数（与站内其它页同一份实现 ✅）
    if (!mounted) return;
    setState(() {});
    try {
      await kp.open(widget.room.url);
      if (!mounted) return;
      setState(() => _err = '');
      if (AppSettings.i.logConsole) {
        debugPrint('[ZHIBO] 开播 平台=${widget.platform} 主播=${widget.room.name} '
            'url=${widget.room.url.length <= 60 ? widget.room.url : widget.room.url.substring(0, 60)}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '直播流打不开：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final kp = _kp;
    // ★ 2026-10-24（用户截图：画面被挤成一小块 + 要求"只有右上角一个 X"）——
    //   照既有直播站 `sites/xhamsterlive.dart` 的 `LiveRoomPage` 那套（`:1131-1251`）：
    //   · **没有 AppBar**、纯黑底、画面 `Positioned.fill` 铺满（`BoxFit.contain` 等比不裁切）
    //   · 控件只有**右上角一个圆底 X**（36 圆 + 32 图标），其余全让给画面
    //   · 点屏幕 **toggle X**（X 显示后 3 秒自动隐藏，照 xhamsterlive 的 `_toggleX` ✅）
    //   ⚠️ 原来我用 `Center + AspectRatio(16/9)` ⇒ **直播源是竖版时画面被压成中间一小块** ☠
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // ---- 画面：铺满整个屏幕（contain ⇒ 竖版源就是竖着完整显示 ✅）----
            if (kp != null)
              Positioned.fill(
                child: Video(
                  controller: kp.videoController,
                  fit: BoxFit.contain,
                  controls: NoVideoControls,
                  fill: Colors.black,
                ),
              )
            else
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            // ---- 错误/状态文字（画面之上、X 之下）----
            if (_err.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 40,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _err,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFFB0B4BA)),
                    ),
                  ),
                ),
              ),
            // ---- 点屏幕：显示/隐藏 X（画面不吃触摸 ⇒ 这一层必须盖在画面上，同 xhamsterlive ✅）----
            Positioned.fill(
              left: 24, // 让出左边缘 24px 给 iOS 侧滑返回（同 xhamsterlive ✅）
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleX,
                child: const SizedBox.expand(),
              ),
            ),
            // ---- 右上角 X（唯一控件）----
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: _showX,
                builder: (_, show, __) => !show
                    ? const SizedBox.shrink()
                    : SafeArea(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            // 与 xhamsterlive 同一条对齐口径（X 中心落在 AppBar 图标那条水平线）
                            padding: EdgeInsets.fromLTRB(
                                12, math.max(0.0, kToolbarHeight / 2 - 38), 5, 12),
                            child: Material(
                              color: Colors.transparent,
                              shape: const CircleBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => Navigator.of(context).pop(),
                                child: const SizedBox(
                                  width: 76,
                                  height: 76,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    // 看得见的圆 = 36（透明黑 0x73000000 ≈ 0.45），命中区仍是 76×76
                                    child: SizedBox(
                                      width: 36,
                                      height: 36,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Color(0x73000000),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Icon(Icons.close,
                                              color: Colors.white, size: 32),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
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
