import 'dart:async'; // ★ unawaited ✓（接管里"异步写盘、不阻塞 UI"要用 ✓）

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'aggregate_search_page.dart'; // ★ 2026-10-22 聚合搜索页
import 'app_background.dart';
import 'app_bg.dart';
import 'base/downloads/episode_update_checker.dart'; // ★ 启动后台静默检测集数更新（黄点）
import 'downloads_page.dart'; // ★ 底栏第 4 格「下载」页
import 'favorites.dart';
import 'favorites_page.dart';
import 'home_page.dart';
import 'settings.dart';
import 'settings_page.dart';
// ★ 2026-10-12（用户新需求 ✅）：站点管理页 + **站点展示清单的唯一读取口** `visibleSitesOf` ✅
import 'site_admin.dart';
import 'site_error_log.dart'; // ★ 接管里写日志用它 ✓（日志页读的就是同一记录器 ⇒ 自动可见 ✓）
import 'sites.dart';
import 'sites/xhamsterlive.dart';
import 'live_zhibo_page.dart'; // ★ 2026-10-24（用户要求）：直播聚合页（4 个分类 tab + 下拉双列选平台）
import 'panda_live_page.dart'; // ★ 2026-10-27（用户要求）：PandaTV 直播页（分类 + 排序 + 双列房间）
import 'web_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 播放器引擎 media_kit(libmpv) 必须在 runApp 之前初始化
  MediaKit.ensureInitialized();
  AppSettings.i.load(); // 读设置（双击快进秒数）
  // ★ 2026-10-05（用户要求 ✓「需要调试的时候打开开关」）：**接管控制台打印** ✗ ——
  //   开了 ⇒ 每条 `debugPrint` 都进 **App 自带的错误日志页**（手机上可见 ✓；原来只进 Xcode 控制台 ✗ 手机上看不到 ☠）；
  //   关了 ⇒ **第一句就 return** ✓ ⇒ 后面一个字都不执行（零开销 ✓ 佐证见下面那行 ✓）。
  //   ⚠️ 实现里**绝不再调 `debugPrint`** ☠（防自套）；写盘走 `SiteErrorLog.log` ✓ 且用 `unawaited` ⇒ **不阻塞 UI** ✓；
  //   ⚠️ 上限**沿用记录器既有的 `_trimTail`**（`SiteErrorLog.keepBytes` ≈2.5MB ✓ 见 `lib/site_error_log.dart:27` ✓）——
  //      **不另造"200 条"** ✓ 依据 = 那套已存在、日志页已按它工作 ✓；
  //   ⚠️ 单条**截断 ≤300 字** ✓（照用户口径 ✓）。
  debugPrint = (String? msg, {int? wrapWidth}) {
    if (!AppSettings.i.logConsole) return; // ☠ 关 ⇒ **第一句 return**（零开销 ✓）
    if (msg == null || msg.isEmpty) return;
    unawaited(SiteErrorLog.log(
        'console', msg.length > 300 ? '${msg.substring(0, 300)}…' : msg));
  };
  // ★【常驻诊断·启动】五点在**接管之后**逐个补打 ✓（这样开关打开时这五条才进得了日志页 ✓）
  //   ⚠️ 前三步（ensureInitialized / MediaKit.ensureInitialized / AppSettings.i.load）本身在 `:19-22` 执行 ✓
  //      —— 这里只补"打点"，**不改它们的顺序、也不改任何初始化逻辑** ☠。
  if (AppSettings.i.logConsole) debugPrint('[BOOT] 绑定初始化（ensureInitialized）✓');
  if (AppSettings.i.logConsole) debugPrint('[BOOT] 播放引擎（MediaKit）✓');
  if (AppSettings.i.logConsole) debugPrint('[BOOT] 设置加载（AppSettings）✓');
  // ★ 2026-10-05（用户口径变更 ✓）：**不再把框架错误写进错误日志** ✗ —— 只保留框架默认的控制台呈现
  //   （`presentError` ✓）；要查输出时用设置页的「控制台日志」开关 + 复现一次 ✓。
  //   ⚠️ 下面这块与 `:30-35` 的 `debugPrint` 接管**互不相干** ☠（那是开关生效的唯一通路，动不得 ✓）。
  // ★ 2026-10-08（本批 ✓）：**把框架异常的原文写进日志** —— 原来只 `presentError`（只进 Xcode 控制台 ✗），
  //   真机日志里就只剩一句 `Instance of 'DiagnosticsProperty<void>'`（Flutter 自己构造诊断信息时失败 ✗）
  //   ⇒ **等于看不到异常到底是什么** ☠（用户实报：每次退出详情页都出现这一句，`[DETAIL] dispose` 紧随其后 ✓）。
  //   现在守卫内补两条：异常原文 + 堆栈 ✓；打印本身用 try 兜住 ✓ ——
  //   就算它连 `toString()` 都抛，也至少留一条"打印不出来"的痕迹 ✓，不会再是一片空白 ☠。
  //   ⚠️ `presentError` **保留**（框架原有的控制台呈现一字不动 ✓）；关着开关时这里只多一次 bool 判断 ✓。
  FlutterError.onError = (d) {
    if (AppSettings.i.logConsole) {
      try {
        final es = '${d.exception}';
        debugPrint('[ERR] 框架异常 ${es.length <= 300 ? es : es.substring(0, 300)}');
        final st = d.stack;
        if (st != null) debugPrint('[ERR] 框架异常堆栈 ${st.toString()}');
      } catch (e) {
        debugPrint('[ERR] 框架异常打印不出来（$e）');
      }
    }
    FlutterError.presentError(d);
  };
  if (AppSettings.i.logConsole) debugPrint('[BOOT] 播放记录加载（PlayHistory）开始');
  PlayHistory.i.load(); // 读播放记录（设置页列表 + 续播都要）
  // ★ 2026-10-10（用户拍板 ✅）：收藏是**另一份独立存储**（`fav_list` ☠ 不与 play_history 混）——
  //   ⚠️ 这句**必须在任何 toggle/save 之前**跑完 ☠：收藏没读出来就写盘 ⇒ 会把用户已有收藏覆盖掉。
  if (AppSettings.i.logConsole) debugPrint('[BOOT] 收藏加载（Favorites）开始');
  Favorites.i.load(); // 读收藏（底栏「收藏」页 + 详情页那颗星都要）
  if (AppSettings.i.logConsole) debugPrint('[BOOT] 背景图加载（AppBg）开始');
  AppBg.i.load(); // 读背景图（没设过就用内置的 assets/bg_default.jpg）
  // ★ 2026-10-05（用户批准 · 内存 · ③c）：**给 Flutter 自己的图片缓存设预算** ✅ ——
  //   全项目此前没设过 ⇒ 走框架默认 **100MB**（`imageCache` 管的是**解码后的位图** ✅）。
  //   ⚠️ **48MB 是我们自己定的值**（依据：详情页/图集都是大图 ✅ 且真机偶发闪退怀疑内存）；
  //      它与 `fetched_image.dart` 的**原始字节缓存**（`_maxBytes` 96MB ✅）是**两层独立预算** ✅：
  //      那层管"下载到的字节"、这层管"解码后的位图" —— 不是重复算一份 ✅。
  //   ⚠️ `maximumSize`（张数）**保持框架默认** ☑️ 不动（只收字节上限）。
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20;
  runApp(const KpxxApp());
}

/// ★ 2026-10-05（用户要求 ✓）：**导航轨迹**（进了/退出了哪个页面 ✓）——
///   走 `debugPrint` ⇒ **受"控制台日志"开关控制** ✓；
///   ⚠️ **守卫写在前**（`if (AppSettings.i.logConsole)`）⇒ 关了时**连字符串都不拼** ⇒ 真正零开销 ✓；
///   ⚠️ 页面**名字**为空 ⇒ `runtimeType` 兜底 ✓（**不硬编名字表** ✗）。
/// ★ 2026-10-08（用户拍板 ⑦ ✅）：本类**同时**充当全局的 `RouteObserver<PageRoute>` ——
///   详情页 `subscribe` 它，就能在"被压栈（`didPushNext`）/ 回到栈顶（`didPopNext`）"时
///   暂停 / 续播 + 停写 / 恢复写播放记录 ✅（`[NAV]` 轨迹照旧，一个字不动 ✅）。
///   ⚠️ 两条 `didPush` / `didPop` 覆写里**必须 `super.…`** ☠ —— 订阅者的回调正是靠基类那两个方法发的
///   （漏了 ⇒ 详情页**永远收不到** didPushNext/didPopNext ✗，而且看不出任何报错 ☠）。
class _NavLog extends RouteObserver<PageRoute<dynamic>> {
  _NavLog(); // ★ CI error 2 修：`NavigatorObserver` 的构造器**不是 const** ⇒ 这里不能是 const ✗

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute); // ★ ⑦：转发给 RouteObserver（didPushNext 靠它 ✅）
    if (AppSettings.i.logConsole) debugPrint('[NAV] → ${route.settings.name ?? route.runtimeType}');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute); // ★ ⑦：同上（didPopNext 靠它 ✅）
    if (AppSettings.i.logConsole) debugPrint('[NAV] ← ${route.settings.name ?? route.runtimeType}');
  }
}

/// ★ ⑦：全局**唯一**那一份（`MaterialApp.navigatorObservers` 用它 ✅）——
///   ⚠️ 详情页订阅的**必须是同一个实例** ☠（各 new 一份 ⇒ 收不到任何回调 ✗）。
///   ☑️ 类型写成 `RouteObserver<PageRoute<dynamic>>`（不写成私有的 `_NavLog`）⇒ 公开 API 里不出现库私有类型 ✅。
final RouteObserver<PageRoute<dynamic>> kNavObserver = _NavLog();

class KpxxApp extends StatelessWidget {
  const KpxxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KPXX',
      // ★ 2026-10-05（用户要求 ✓）：**导航轨迹** —— 走 `debugPrint` ⇒ **受"控制台日志"开关控制** ✓
      // ★ 2026-10-08（用户拍板 ⑦ ✅）：同一个实例同时是全局 `RouteObserver`（详情页订阅它 ✓）
      navigatorObservers: [kNavObserver], // ★ CI error 2 修：去掉 `const`（const 列表要求 const 构造器 ✗）
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
        // ---- 全屏背景图配套：页面自己一律透明，图才不会在某几页断掉 ----
        // ⚠️ 不透明底色出现在哪一层，背景就会在哪一层被挡住（模拟器里踩过两次）
        scaffoldBackgroundColor: Colors.transparent,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
        ),
      ),
      // 背景层铺在最底下（含顶栏/底栏/状态栏区域）；文字可读性靠**按背景明暗自适应
      // 黑白字**（app_background.dart 的 kTxt）—— 不加描边、不加光晕（用户否掉了）
      builder: (context, child) => AppBackground(
        child: child ?? const SizedBox.shrink(),
      ),
      home: const RootPage(),
    );
  }
}

/// KPXX 品牌字标（宫格首页顶栏，居中）。
/// 照用户在模拟器里定下的样式：橙色圆角块 + 黑色粗体字（参考图风格，纯自绘、无外部素材）。
class KpxxLogo extends StatelessWidget {
  const KpxxLogo({super.key});

  @override
  Widget build(BuildContext context) {
    // ★ 2026-10-22（用户要求：胶囊缩短到文本大小范围，而且**文字不能偏**）：
    //   · 不能用 `Container.alignment` —— 它会让 Container 在 AppBar.title 的宽松约束里**撑满整行** ☠；
    //   · 也不能啥都不加 —— 那样 `Text` 会按 **topLeft** 排 ⇒ 文字偏上 ☠（用户实测抓到的就是这个）；
    //   ⇒ 用 `Center(widthFactor: 1)`：宽度贴合文字（不撑满）✅、高度撑满 30 ⇒ 垂直居中 ✅。
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFB63C), Color(0xFFF29A12)],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Color(0x47000000), blurRadius: 7, offset: Offset(0, 2)),
        ],
      ),
      child: const Center(
        widthFactor: 1,
        child: Text(
          'KPXX',
          style: TextStyle(
            color: Color(0xFF14100B),
            fontWeight: FontWeight.w800,
            fontSize: 17,
            letterSpacing: 0.6,
            // 字标自带底色，不需要描边光晕
            shadows: [],
          ),
        ),
      ),
    );
  }
}

/// 根页：底部五个 tab —— 点播（站点宫格）/ **直播**（直播站点宫格）/ **收藏** / **下载** / 设置。
/// ⚠️ 顺序是用户拍板的：**点播 → 直播 → 收藏 → 下载 → 设置**
///   （收藏 = 第 3 格 ✅ 用户 2026-10-10 口径；下载 = 第 4 格 ✅ 用户 2026-10-19 口径）——
///   （2026-10-03 那次定的是三格「点播 → 直播 → 设置」，2026-10-10 在**设置之前**插进「收藏」，
///     2026-10-19 再在**设置之前**插进「下载」⇒ 别把收藏/下载挪到最后 ☠）
class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // ★ 2026-10-21（用户拍板）：启动后延迟 3 秒后台静默检测一次「下载页 + 收藏页」的集数更新。
    //   ⚠️ 放在这里而**不是** `main()`：`lib/main_win_dev.dart` 是**独立入口**（调试用），
    //      它有自己的 `main()` ⇒ 走 `main.dart` 的钩子在调试入口里根本不执行（实测：
    //      热重启后检测器从未运行、`shared_preferences` 一个字节都没变 ☠）。
    //      `KpxxApp` 两个入口都用 ⇒ 挂在 `RootPage.initState` 才是唯一可靠点 ✅。
    Future<void>.delayed(const Duration(seconds: 3), () {
      unawaited(EpisodeUpdateChecker.i.run());
    });
  }

  @override
  Widget build(BuildContext context) {
    // 整页跟着背景明暗重建（底栏标签 = kTxt / 选中浅橙，都不是常量）。
    // ⚠️ 必须在 builder 里重新构造页面：把 widget 实例直接交给 builder，
    // Flutter 会因"实例相同"跳过整棵子树的重建，isDark 翻了也不会刷。
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => _pageView(context),
    );
  }

  Widget _pageView(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          ModuleGridPage(),
          LiveGridPage(),
          FavoritesPage(), // ★ 第 3 格「收藏」（用户 2026-10-10 拍板 ✅）
          DownloadsPage(), // ★ 第 4 格「下载」（用户 2026-10-19 拍板 ✅）
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: GestureDetector(
        // ★ 2026-10-12（**用户口径 · 最终** ✅）：**长按底栏「设置」tab ⇒ 进「站点管理」** ——
        //   用户原话："底栏tab长按点播进入站点管理界面…" ⇒ **当日更正**：长按的是**「设置」**那一格
        //   （**不是**「点播」；本处**只保留这一个入口** ☑️ 点播那边没有任何长按逻辑 ✅）。
        //   实现要点：
        //   ① `BottomNavigationBar` 本身**没有长按回调** ⇒ 在它**外面**套一层只申明"长按"的手势层：
        //      只注册 `onLongPressStart` ⇒ **单击仍由底栏自己的 `onTap` 处理，原行为一字不变** ✅
        //      （单击/长按是两套手势识别器，由手势竞技场分流 ☑️）。
        //   ② 只有按下的点落在**第 5 格「设置」**里才进管理页（宽度按 `items.length` 等分判断 ✅
        //      —— 五格：点播(0)/直播(1)/收藏(2)/下载(3)/设置(4)）；其余四格**长按什么都不做** ✅。
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (d) {
          const n = 5; // 底栏格数（点播/直播/收藏/下载/设置 ✅）
          const settingsSlot = 4; // 第 5 格 = 「设置」（0 起）
          final w = MediaQuery.sizeOf(context).width;
          final i = (d.globalPosition.dx / (w / n)).floor();
          if (i != settingsSlot) return; // 只有「设置」那一格能进站点管理 ✅
          if (AppSettings.i.logConsole) {
            debugPrint('[SITE] 长按底栏「设置」⇒ 进站点管理');
          }
          Navigator.of(context).push(MaterialPageRoute(
            settings: const RouteSettings(name: '站点管理'),
            builder: (_) => const PageBg(child: SiteManagePage()),
          ));
        },
        child: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        // 底栏直接压在背景图上 → 跟着明暗翻（选中用模拟器里的浅橙）
        selectedItemColor: AppBg.i.isDark
            ? const Color(0xFFFFB07A)
            : Theme.of(context).colorScheme.primary,
        unselectedItemColor: AppBg.i.isDark ? Colors.white : Colors.black45,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_rounded),
            label: '点播',
          ),
          // 直播语义图标（模拟器里画的是"电视框 + 天线" ✓ → Material 的 live_tv 同义 ✓；
          // 描边风格与「设置」那项一致 ✓）
          BottomNavigationBarItem(
            icon: Icon(Icons.live_tv_outlined),
            label: '直播',
          ),
          // ★ 第 3 格「收藏」（用户 2026-10-10 拍板 ✅：接在「直播」后、「设置」前）
          //   图标用空心星 —— 与「点播/直播/设置」那几项同为描边风格 ✅（详情页已收藏时才换成实心星）
          BottomNavigationBarItem(
            icon: Icon(Icons.star_border),
            label: '收藏',
          ),
          // ★ 第 4 格「下载」（用户 2026-10-19 拍板 ✅：接在「收藏」后、「设置」前）
          BottomNavigationBarItem(
            icon: Icon(Icons.download_outlined),
            label: '下载',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: '设置',
          ),
        ],
        ),
      ),
    );
  }
}

/// 宫格首页：5 列图标 + 名字，点击打开对应站点（清单见 lib/sites.dart）。
/// ⚠️ 只显示 `SiteGroup.module` 的站 ✓ —— 直播站（`SiteGroup.live`）归底栏「直播」那页 ✓。
class ModuleGridPage extends StatelessWidget {
  const ModuleGridPage({super.key});

  void _open(BuildContext context, SiteEntry e) {
    final Widget page;
    if (e.kind == SiteKind.native) {
      page = HomePage(site: e);
    } else {
      page = WebPage(title: e.name, url: e.url);
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PageBg(child: page), settings: RouteSettings(name: e.kind == SiteKind.native ? '站点页' : '网页')));
  }

  @override
  Widget build(BuildContext context) {
    // 同上：宫格图标名读 kTxt，整页要跟着背景明暗重建
    // ★ 2026-10-12（用户新需求 ✅）：**同时监听 `AppSettings.i`** —— 站点管理里改开关/拖动顺序
    //   ⇒ 这一页**立刻**增减/重排（顺序与过滤在 `_grid` 里现算 ✅；`Listenable.merge` 同款用法见
    //   `detail_page.dart` 的 `Listenable.merge([AppBg.i, …])` ✅）。单击行为一字未动 ✅。
    return ListenableBuilder(
      listenable: Listenable.merge([AppBg.i, AppSettings.i]),
      builder: (context, _) => _grid(context),
    );
  }

  Widget _grid(BuildContext context) {
    // ★ 2026-10-12（用户新需求 ✅）：**站点展示清单走唯一读取口** `visibleSitesOf`（`site_admin.dart`）——
    //   它 = 组内自定义顺序（`orderedSitesOf`，含"新站点追加在后"✅）+ 去掉被隐藏的站点 ✅
    //   （原来这里是写死的 `kSites.where(...)` ⇒ 换掉后开关/拖动才可能对首页生效 ✅）
    final sites = visibleSitesOf(SiteGroup.module);
    return Scaffold(
      // 透明：让根层的背景图从这里透出来（顶栏也是透明的，见 theme）
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        systemOverlayStyle: kStatusOverlay,
        title: const KpxxLogo(), // 橙底黑字，自带底色不跟明暗走
        centerTitle: true, // ★ KPXX 胶囊**始终居中**：右侧只放一个 action，两侧对称不会把标题挤偏
        elevation: 0,
        foregroundColor: kTxt, // 顶栏图标（返回/操作）跟着背景明暗
        // ★ 2026-10-22（用户要求）：右上角「聚合搜索」入口
        //   `centerTitle: true` ⇒ Flutter 的 AppBar 会把左右两侧**对称平衡**，标题（KPXX 胶囊）始终居中
        actions: [
          IconButton(
            tooltip: '聚合搜索',
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  settings: const RouteSettings(name: '聚合搜索'),
                  // ★ 2026-10-22（用户要求：按"播放记录/错误日志"那套修）：
                  //   转场重影的根因就是**被 push 的页面本身没套 `PageBg`**（`Scaffold` 透明 ⇒ 盖不住旧页面）。
                  //   ⇒ 这里补上 `PageBg`（与 `settings_page.dart:110/318/477` 同款）。
                  builder: (_) => const PageBg(child: AggregateSearchPage()),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 18,
            crossAxisSpacing: 8,
            childAspectRatio: 0.86,
          ),
          itemCount: sites.length,
          itemBuilder: (_, i) => _SiteTile(
            entry: sites[i],
            onTap: () => _open(context, sites[i]),
          ),
        ),
      ),
    );
  }
}

/// **直播**宫格页（底栏第二项）：直播站点的按钮宫格 —— 与「点播」页**同一套样式** ✓
/// （同一个 `_SiteTile` ✓、同样 4 列 ✓），只是清单换成 `group == SiteGroup.live` 的站点 ✓。
/// ⚠️ 共用 UI 里**不判站名/模板名** ✗ —— 只看 `SiteEntry.group` ✓（见 sites.dart 的 SiteGroup ✓）。
/// 点一个 → push 那个直播站的**全屏页** ✓（App 里 push 天然不带底栏 ✓）。
class LiveGridPage extends StatelessWidget {
  const LiveGridPage({super.key});

  void _open(BuildContext context, SiteEntry e) {
    // ★ 2026-10-24（用户要求）：**直播聚合站**走它自己的整页
    //   （4 个分类 tab + 下拉双列选平台；不走 xhamsterlive 那套 LiveSitePage ✅）
    // ★ 2026-10-27（用户要求）：**PandaTV** 同样走自己的整页 `PandaLivePage` ✅
    //   ⚠️ 共用 UI 里**不判站名** ✗ —— 判的是"是不是本类整页"，用 `hosts.first`：
    //      只有直播聚合用 `hclyz`、只有 PandaTV 用 `5721004.xyz` ✅
    final h = e.hosts.isNotEmpty ? e.hosts.first : '';
    final isZhibo = h.contains('hclyz');
    final isPanda = h.contains('5721004');
    final Widget page = isZhibo
        ? LiveZhiboPage(site: e)
        : (isPanda ? PandaLivePage(site: e) : LiveSitePage(site: e));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PageBg(child: page),
        settings: RouteSettings(
            name: isZhibo ? '直播聚合' : (isPanda ? 'PandaTV' : '直播列表')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 同「点播」页：宫格图标名读 kTxt，整页跟着背景明暗重建 ✓
    // ★ 2026-10-12（用户新需求 ✅）：**同时监听 `AppSettings.i`**（站点管理的开关/顺序 ⇒ 本页立刻生效 ✅）
    return ListenableBuilder(
      listenable: Listenable.merge([AppBg.i, AppSettings.i]),
      builder: (context, _) => _grid(context),
    );
  }

  Widget _grid(BuildContext context) {
    // ★ 2026-10-12（用户新需求 ✅）：**站点展示清单走唯一读取口** `visibleSitesOf`（`site_admin.dart`）
    //   —— 它 = 组内自定义顺序（`orderedSitesOf`，含"新站点追加在后"✅）+ 去掉被隐藏的站点 ✅
    //   （原来这里是写死的 `kSites.where(...)` ⇒ 换掉后开关/拖动才可能对首页生效 ✅）
    final sites = visibleSitesOf(SiteGroup.live);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        systemOverlayStyle: kStatusOverlay,
        title: const Text('直播'), // 占位、不返回 ✓（与「点播 / 设置」一致 ✓）
        centerTitle: true,
        elevation: 0,
        foregroundColor: kTxt,
      ),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 18,
            crossAxisSpacing: 8,
            childAspectRatio: 0.86,
          ),
          itemCount: sites.length,
          itemBuilder: (_, i) => _SiteTile(
            entry: sites[i],
            onTap: () => _open(context, sites[i]),
          ),
        ),
      ),
    );
  }
}

class _SiteTile extends StatelessWidget {
  final SiteEntry entry;
  final VoidCallback onTap;

  const _SiteTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: 62,
            height: 62,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              // 有**内置**图标时用浅底 + contain（避免宽 logo 被裁掉），没有时用首字色块
              // ★ 2026-10-12（用户口径 ✅）：图标**只走内置资源** ⇒ 不再有"联网取 favicon"那条路
              // ★ 2026-10-24：有 `iconText` 时也用 `color` 做底（黑底白字 LIVE 就靠这条 ✅）
              color: (entry.assetIcon.isEmpty || entry.iconText.isNotEmpty)
                  ? entry.color
                  : Colors.white,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0x14000000)),
            ),
            // ★ 2026-10-24（用户要求）：**图标文字**优先（直播聚合 = 黑底 + 白色 LIVE ✅）
            //   字号按字数自适应：4 字符（LIVE）用 17，更长的自动缩到 14
            child: entry.iconText.isNotEmpty
                ? Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          entry.iconText,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: entry.iconText.length <= 4 ? 17 : 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  )
                : entry.assetIcon.isEmpty
                    ? Center(
                        child: Text(
                          entry.name.isEmpty ? '?' : entry.name.substring(0, 1),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(9),
                        // ★ 本地资源、**零网络** ✅（`assets/site_icons/xxx.png`，128×128 透明底）
                        child: Image.asset(entry.assetIcon, fit: BoxFit.contain),
                      ),
          ),
          const SizedBox(height: 6),
          // Flexible：系统字体放大时让名字收缩，不至于把格子撑爆
          Flexible(
            child: Text(
              entry.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: kTxt),
            ),
          ),
        ],
      ),
    );
  }
}
