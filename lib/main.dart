import 'dart:async'; // ★ unawaited ✓（接管里"异步写盘、不阻塞 UI"要用 ✓）

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app_background.dart';
import 'app_bg.dart';
import 'favorites.dart';
import 'favorites_page.dart';
import 'fetched_image.dart';
import 'home_page.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'site_error_log.dart'; // ★ 接管里写日志用它 ✓（日志页读的就是同一记录器 ⇒ 自动可见 ✓）
import 'sites.dart';
import 'sites/xhamsterlive.dart';
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
    return Container(
      height: 30,
      alignment: Alignment.center,
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
      child: const Text(
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
    );
  }
}

/// 根页：底部四个 tab —— 点播（站点宫格）/ **直播**（直播站点宫格）/ **收藏** / 设置。
/// ⚠️ 顺序是用户拍板的：**点播 → 直播 → 收藏 → 设置**（收藏 = 第 3 格 ✅ 用户 2026-10-10 口径）——
///   （2026-10-03 那次定的是三格「点播 → 直播 → 设置」，本次在**设置之前**插进「收藏」⇒ 别把收藏挪到最后 ☠）
class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _index = 0;

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
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
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
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: '设置',
          ),
        ],
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
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => _grid(context),
    );
  }

  Widget _grid(BuildContext context) {
    final sites = kSites.where((e) => e.group == SiteGroup.module).toList();
    return Scaffold(
      // 透明：让根层的背景图从这里透出来（顶栏也是透明的，见 theme）
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        systemOverlayStyle: kStatusOverlay,
        title: const KpxxLogo(), // 橙底黑字，自带底色不跟明暗走
        centerTitle: true,
        elevation: 0,
        foregroundColor: kTxt, // 顶栏图标（返回/操作）跟着背景明暗
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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PageBg(child: LiveSitePage(site: e)), settings: const RouteSettings(name: '直播列表')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 同「点播」页：宫格图标名读 kTxt，整页跟着背景明暗重建 ✓
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => _grid(context),
    );
  }

  Widget _grid(BuildContext context) {
    final sites = kSites.where((e) => e.group == SiteGroup.live).toList();
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
              // 有 logo 时用浅底 + contain（避免宽 logo 被裁掉），没 logo 时用首字色块
              color: entry.iconUrl.isEmpty ? entry.color : Colors.white,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0x14000000)),
            ),
            child: entry.iconUrl.isEmpty
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
                    child: FetchedImage(
                      url: entry.iconUrl.startsWith('/')
                          ? 'https://${entry.hosts.isNotEmpty ? entry.hosts.first : ''}${entry.iconUrl}'
                          : entry.iconUrl,
                      fit: BoxFit.contain,
                      memWidth: 160,
                    ),
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
