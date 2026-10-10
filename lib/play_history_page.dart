import 'package:flutter/material.dart';

import 'base/site_ui.dart';
import 'app_bg.dart';
import 'app_background.dart';
import 'detail_page.dart';
import 'play_record_tile.dart';
import 'settings.dart';
import 'sites.dart';

/// 播放记录列表（从设置页进来）。
/// 点一条 = 回到该篇详情，**并从上一次的进度续播**（站点入口进来不受影响）。
class PlayHistoryPage extends StatelessWidget {
  const PlayHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 整页跟着背景明暗重建（顶栏标题/图标、记录行文字都读 kTxt）
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => _pageView(context),
    );
  }

  Widget _pageView(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // 外层已铺背景图，别挡掉
      appBar: AppBar(
        systemOverlayStyle: kStatusOverlay,
        title: const Text('播放记录'),
        centerTitle: true,
        foregroundColor: kTxt, // 标题/图标直接压在图上 → 跟明暗
        actions: [
          ListenableBuilder(
            listenable: PlayHistory.i,
            builder: (context, _) => PlayHistory.i.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: '清空',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: () => _confirmClear(context),
                  ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: PlayHistory.i,
        builder: (context, _) {
          final list = PlayHistory.i.records;
          if (list.isEmpty) {
            return Center(
              child: Text('还没有播放记录',
                  style: TextStyle(color: kTxtSub, fontSize: 13)),
            );
          }
          // ★ 2026-10-10（用户要求 ✅）：**播放记录列表不要条目分割线**（与收藏页**同口径** ✅）——
          //   原来这里有一条 `Divider(height: 1, indent: 12)` ☑️ 已去掉 ⇒ 改用 `ListView.builder`
          //   （不带 separator ☠）；行的 padding/间距**一个字没动** ✅。
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: list.length,
            // 行布局只有 PlayRecordTile 一份（设置页预览用的是同一个）
            itemBuilder: (context, i) {
              final r = list[i];
              return PlayRecordTile(
                key: ValueKey(r.key), // 稳定身份：增删一条时别把整列封面重挂载
                record: r,
                onTap: () => _open(context, r),
                onDelete: () => PlayHistory.i.remove(r.key),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await confirmClear(
                      context: context,
                      title: '清空播放记录？',
                      content: '所有记录会删掉，不能恢复。');
    if (ok == true) {
      // ★ 2026-10-05【常驻诊断·④】清空播放记录（只看不改逻辑 ☠ 清空本身仍走同一句 ✓）
      if (AppSettings.i.logConsole) debugPrint('[UI] 清空播放记录（原 ${PlayHistory.i.records.length} 条）');
      await PlayHistory.i.clear();
    }
  }

  /// 点一条记录 → 该篇详情续播
  void _open(BuildContext context, PlayRecord record) {
    // 站点名反查 SiteEntry（记录是按站点名存的）；站点改名/下线就跳过
    final site = kSites.where((s) => s.name == record.site).toList();
    if (site.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            duration: const Duration(seconds: 1), // ★ 2026-10-10（用户批准）：默认 4 秒 → 1 秒
            content: Text('找不到站点「${record.site}」，这条记录打不开了')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '详情页'), // ★ 全仓唯一没起名的路由 ⇒ 补上（`[NAV]` 日志要显示页面名 ✓）
        builder: (_) => PageBg(child: DetailPage(
          site: site.first,
          baseUrl: record.url,
          listCover: record.cover,
          // 续播位置：只有这条路会传（站点入口一律不传）。
          // 已看完的从头播——否则会跳到结尾立即又"看完"，等于看不了。
          initialPosition: record.finished ? null : record.position,
          initialVideoIndex: record.videoIndex,
        )),
      ),
    );
  }
}
