import 'package:flutter/material.dart';

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
    return Scaffold(
      backgroundColor: Colors.transparent, // 外层已铺背景图，别挡掉
      appBar: AppBar(
        title: const Text('播放记录'),
        centerTitle: true,
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
            return const Center(
              child: Text('还没有播放记录',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 12),
            // 行布局只有 PlayRecordTile 一份（设置页预览用的是同一个）
            itemBuilder: (context, i) {
              final r = list[i];
              return PlayRecordTile(
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空播放记录？'),
        content: const Text('所有记录会删掉，不能恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) await PlayHistory.i.clear();
  }

  /// 点一条记录 → 该篇详情续播
  void _open(BuildContext context, PlayRecord record) {
    // 站点名反查 SiteEntry（记录是按站点名存的）；站点改名/下线就跳过
    final site = kSites.where((s) => s.name == record.site).toList();
    if (site.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('找不到站点「${record.site}」，这条记录打不开了')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailPage(
          site: site.first,
          baseUrl: record.url,
          listCover: record.cover,
          // 续播位置：只有这条路会传（站点入口一律不传）。
          // 已看完的从头播——否则会跳到结尾立即又"看完"，等于看不了。
          initialPosition: record.finished ? null : record.position,
          initialVideoIndex: record.videoIndex,
        ),
      ),
    );
  }
}
