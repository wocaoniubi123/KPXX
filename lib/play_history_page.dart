import 'package:flutter/material.dart';

import 'detail_page.dart';
import 'fetched_image.dart';
import 'settings.dart';
import 'sites.dart';

/// 播放记录列表（从设置页进来）。
/// 点一条 = 回到该篇详情，**并从上一次的进度续播**（站点入口进来不受影响）。
class PlayHistoryPage extends StatelessWidget {
  const PlayHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            itemBuilder: (context, i) => _RecordTile(record: list[i]),
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
}

class _RecordTile extends StatelessWidget {
  final PlayRecord record;
  const _RecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final pct = (record.progress * 100).floor();
    final total = _clock(record.duration);
    final pos = _clock(record.position);
    // 进度文案：看完的显式标"已看完"，其余显示"已看 N%"
    final sub = record.finished
        ? '已看完${total.isEmpty ? '' : ' · $total'}'
        : (total.isEmpty ? '已看 $pct%' : '已看 $pct% · $pos / $total');

    return InkWell(
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面：站点本来没有封面就不占位（同列表卡片的原则）
            if (record.cover.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 96,
                  height: 54, // 16:9，和列表封面一致
                  child: FetchedImage(url: record.cover, memWidth: 240),
                ),
              )
            else
              Container(
                width: 96,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFEFF2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.movie_outlined,
                    size: 22, color: Colors.black26),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title.isEmpty ? record.url : record.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 11,
                      color: record.finished
                          ? const Color(0xFF2E7D32)
                          : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 5),
                  // 进度条（已看完 = 满格）
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: record.progress,
                      minHeight: 4,
                      backgroundColor: const Color(0xFFE8E8EC),
                      valueColor: AlwaysStoppedAnimation(
                          record.finished
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFE8590C),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(record.site,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black38)),
                      const Spacer(),
                      Text(_ago(record.updatedAt),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black38)),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.close, size: 18, color: Colors.black38),
              onPressed: () => PlayHistory.i.remove(record.key),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context) {
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

  static String _clock(Duration d) {
    if (d <= Duration.zero) return '';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// 相对时间：刚刚 / N分钟前 / N小时前 / 昨天 / M-D
  static String _ago(int ms) {
    if (ms <= 0) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24 && now.day == t.day) return '${diff.inHours}小时前';
    if (now.difference(t).inDays == 1) return '昨天';
    return '${t.month}-${t.day}';
  }
}
