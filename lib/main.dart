import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app_background.dart';
import 'app_bg.dart';
import 'fetched_image.dart';
import 'home_page.dart';
import 'play_history_page.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'sites.dart';
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
      // 背景层铺在最底下（含顶栏/底栏/状态栏区域），再把整棵树包一层文字描边：
      // 描边只加给字、不动图 —— 用户换任何一张背景图都能看清
      builder: (context, child) => AppBackground(
        child: DefaultTextStyle.merge(
          style: const TextStyle(shadows: kTextHalo),
          child: child ?? const SizedBox.shrink(),
        ),
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

/// 根页：底部两个 tab —— 模块（站点宫格）/ 推荐（第一个原生站点的内容）。
class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          ModuleGridPage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.black45,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_rounded),
            label: '模块',
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
    return Scaffold(
      // 透明：让根层的背景图从这里透出来（顶栏也是透明的，见 theme）
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const KpxxLogo(),
        centerTitle: true,
        elevation: 0,
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
          itemCount: kSites.length,
          itemBuilder: (_, i) => _SiteTile(
            entry: kSites[i],
            onTap: () => _open(context, kSites[i]),
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
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
