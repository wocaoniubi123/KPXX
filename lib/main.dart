import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'fetched_image.dart';
import 'home_page.dart';
import 'play_history_page.dart';
import 'settings.dart';
import 'sites.dart';
import 'web_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 播放器引擎 media_kit(libmpv) 必须在 runApp 之前初始化
  MediaKit.ensureInitialized();
  AppSettings.i.load(); // 读设置（双击快进秒数）
  PlayHistory.i.load(); // 读播放记录（设置页列表 + 续播都要）
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

/// 设置页
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListenableBuilder(
        listenable: AppSettings.i,
        builder: (context, _) => ListView(
          children: [
            // 播放记录：进去是独立页面（列表 + 单条删除 + 清空）
            ListenableBuilder(
              listenable: PlayHistory.i,
              builder: (context, _) => ListTile(
                leading: const Icon(Icons.history),
                title: const Text('播放记录'),
                subtitle: Text(PlayHistory.i.isEmpty
                    ? '还没有记录；看过视频后自动记在这'
                    : '${PlayHistory.i.records.length} 条 · 点一条从上次的进度继续看'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PlayHistoryPage()),
                ),
              ),
            ),
            const Divider(height: 32),
            const ListTile(
              title: Text('快进/快退秒数'),
              subtitle: Text('播放器里双击画面左侧后退、右侧快进，一次跳转的时长'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final s in AppSettings.stepOptions)
                    ChoiceChip(
                      label: Text('$s 秒'),
                      selected: AppSettings.i.step == s,
                      onSelected: (_) => AppSettings.i.setStep(s),
                    ),
                ],
              ),
            ),
            const Divider(height: 32),
            SwitchListTile(
              title: const Text('自动播放下一集'),
              subtitle: const Text('一篇里有多个视频时，播完自动切下一个（默认关）'),
              value: AppSettings.i.autoNext,
              onChanged: (v) => AppSettings.i.setAutoNext(v),
            ),
            const Divider(height: 32),
            const ListTile(
              title: Text('播放缓冲大小'),
              subtitle: Text('越大越抗卡、拖动越顺，但更吃内存（1G 在低内存机型上可能被杀进程）；改完重进视频生效'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final mb in AppSettings.bufferOptions)
                    ChoiceChip(
                      label: Text(AppSettings.bufferLabel(mb)),
                      selected: AppSettings.i.bufferMb == mb,
                      onSelected: (_) => AppSettings.i.setBufferMb(mb),
                    ),
                ],
              ),
            ),
            const Divider(height: 32),
            const ListTile(
              title: Text('左右滑动'),
              subtitle: Text('按滑动距离快进/快退：滑满一屏 = 120 秒，松手才跳转'),
            ),
          ],
        ),
      ),
    );
  }
}
