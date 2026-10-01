import 'package:flutter/material.dart';

import 'app_background.dart';
import 'fetched_image.dart';
import 'settings.dart';

/// 一行播放记录（设置页预览 + 播放记录整页共用，样式只此一份）。
///
/// 布局照模拟器 `.srec`（sim/index.html）：封面 104×59 + 右侧一列
/// 标题（单行省略）/ 进度条 / 小字（进度 + 相对时间）/ 站点名。
///
/// - 标题**只占一行**（用户要求）：长了省略号
/// - `onTap` 非空 → 整行可点（设置页预览、播放记录页都传续播回调）
/// - `onDelete` 非空 → 右侧出现 ✕（只有播放记录整页传）
class PlayRecordTile extends StatelessWidget {
  final PlayRecord record;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const PlayRecordTile({
    super.key,
    required this.record,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        // 模拟器 .srec：padding: 13px 16px 0；右侧删除键自带内边距，这里给 6
        padding: const EdgeInsets.fromLTRB(16, 13, 6, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cover(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title.isEmpty ? record.url : record.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: kTxt,
                    ),
                  ),
                  const SizedBox(height: 7),
                  _bar(),
                  const SizedBox(height: 4),
                  _meta(),
                  const SizedBox(height: 4),
                  Text(
                    record.site,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: kTxt,
                    ),
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                tooltip: '删除',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, size: 18, color: kTxt),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }

  /// 封面：站点本来没封面就用灰底 + 电影图标占位（同尺寸）
  Widget _cover() {
    const w = 104.0;
    const h = 59.0;
    const radius = BorderRadius.all(Radius.circular(9));
    if (record.cover.isEmpty) {
      return Container(
        width: w,
        height: h,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFFECEEF3),
          borderRadius: radius,
        ),
        child: const Icon(Icons.movie_outlined, size: 22, color: Colors.black26),
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: w,
        height: h,
        child: FetchedImage(url: record.cover, memWidth: 240),
      ),
    );
  }

  /// 进度条：高 4、圆角 3；已看完满格绿，否则橙
  Widget _bar() {
    final color =
        record.finished ? const Color(0xFF2E7D32) : const Color(0xFFE8590C);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: record.progress,
        minHeight: 4,
        backgroundColor: const Color(0xFFE8E8EC),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }

  /// 左 = 进度小字，右 = 相对时间
  Widget _meta() {
    final style = TextStyle(fontSize: 11, color: kTxtSub);
    final total = _fmt(record.duration);
    final done = record.finished;
    // 看完的显式标"已看完"；没时长的只报百分比（别显示 0:00 / 0:00）
    final left = done
        ? (total.isEmpty ? '已看完' : '已看完 · $total')
        : (total.isEmpty
            ? '已看 ${_pct}%'
            : '已看 ${_pct}% · ${_fmt(record.position)} / $total');
    final ago = _ago(record.updatedAt);
    return Row(
      children: [
        Expanded(
          child: Text(
            left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (ago.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(ago, style: style),
          ),
      ],
    );
  }

  /// 观看百分比（`progress` 已是 0~1，越界已在 settings.dart 夹住）
  int get _pct => (record.progress * 100).floor();

  /// 时长：m:ss，超一小时 h:mm:ss；0（没拿到时长）返回空串
  static String _fmt(Duration d) {
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
    if (diff.inDays == 1) return '昨天';
    return '${t.month}-${t.day}';
  }
}
