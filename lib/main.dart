import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app_background.dart';
import 'app_bg.dart';
import 'fetched_image.dart';
import 'home_page.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'sites.dart';
import 'sites/xhamsterlive.dart';
import 'web_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 播放器引擎 media_kit(libmpv) 必须在 runApp 之前初始化
  MediaKit.ensureInitialized();
  AppSettings.i.load(); // 读设置（双击快进秒数）
  PlayHistory.i.load(); // 读播放记录（设置页列表 + 续播都要）
  AppBg.i.load(); // 读背景图（没设过就用内置的 assets/bg_default.jpg）
  runApp(const KpxxApp());
}

class KpxxApp extends StatelessWidget {
  const KpxxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KPXX',
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

/// 根页：底部三个 tab —— 模块（站点宫格）/ **直播**（直播站点宫格）/ 设置。
/// ⚠️ 顺序是用户 2026-10-03 拍板的：**模块 → 直播 → 设置**（与模拟器同序 ✓）—— 别改顺序 ✗。
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
            label: '模块',
          ),
          // 直播语义图标（模拟器里画的是"电视框 + 天线" ✓ → Material 的 live_tv 同义 ✓；
          // 描边风格与「设置」那项一致 ✓）
          BottomNavigationBarItem(
            icon: Icon(Icons.live_tv_outlined),
            label: '直播',
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
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PageBg(child: page)));
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

/// **直播**宫格页（底栏第二项）：直播站点的按钮宫格 —— 与「模块」页**同一套样式** ✓
/// （同一个 `_SiteTile` ✓、同样 4 列 ✓），只是清单换成 `group == SiteGroup.live` 的站点 ✓。
/// ⚠️ 共用 UI 里**不判站名/模板名** ✗ —— 只看 `SiteEntry.group` ✓（见 sites.dart 的 SiteGroup ✓）。
/// 点一个 → push 那个直播站的**全屏页** ✓（App 里 push 天然不带底栏 ✓）。
class LiveGridPage extends StatelessWidget {
  const LiveGridPage({super.key});

  void _open(BuildContext context, SiteEntry e) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PageBg(child: LiveSitePage(site: e))),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 同「模块」页：宫格图标名读 kTxt，整页跟着背景明暗重建 ✓
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
        title: const Text('直播'), // 占位、不返回 ✓（与「模块 / 设置」一致 ✓）
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
