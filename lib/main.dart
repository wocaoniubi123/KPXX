import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'fetched_image.dart';
import 'home_page.dart';
import 'sites.dart';
import 'web_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 播放器引擎 media_kit(libmpv) 必须在 runApp 之前初始化
  MediaKit.ensureInitialized();
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
      ),
      home: const RootPage(),
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

  /// 推荐 tab 用清单里第一个原生站点（想换就调 sites.dart 里的顺序/kind）
  static SiteEntry? _feedSite() {
    for (final s in kSites) {
      if (s.kind == SiteKind.native) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feedSite();
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const ModuleGridPage(),
          feed == null
              ? const Center(child: Text('还没有可用的原生站点'))
              : HomePage(site: feed),
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
            icon: Icon(Icons.play_circle_outline),
            label: '推荐',
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
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F9),
      appBar: AppBar(
        title: const Text('KPXX'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: 16,
            crossAxisSpacing: 4,
            childAspectRatio: 0.8,
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
            width: 50,
            height: 50,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: entry.color,
              borderRadius: BorderRadius.circular(13),
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
                : FetchedImage(url: entry.iconUrl, fit: BoxFit.cover),
          ),
          const SizedBox(height: 6),
          // Flexible：系统字体放大时让名字收缩，不至于把格子撑爆
          Flexible(
            child: Text(
              entry.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
