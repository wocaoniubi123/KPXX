import 'package:flutter/material.dart';

import 'home_page.dart';

/// 入口页：第一行大按钮 + logo，后续可继续添加其他入口。
void main() => runApp(const KpxxApp());

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
      home: const EntryPage(),
    );
  }
}

class EntryPage extends StatelessWidget {
  const EntryPage({super.key});

  void _open51cg(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HomePage()), // 51吃瓜
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('KPXX'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 入口 1：51吃瓜（大按钮 + logo）
            Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _open51cg(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 24),
                  child: Row(
                    children: [
                      Container(
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.play_circle_fill,
                            size: 40),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('51吃瓜',
                                style: TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.bold)),
                            SizedBox(height: 4),
                            Text('吃瓜爆料第一站',
                                style:
                                    TextStyle(fontSize: 13, color: Colors.grey)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
            // 其他入口留空，后续按需添加
          ],
        ),
      ),
    );
  }
}
