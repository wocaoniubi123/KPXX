import 'package:flutter/material.dart';

import 'app_background.dart';
import 'fetched_image.dart';
import 'settings.dart';

/// **通用媒体行**（甲方案 ✅ 用户 2026-10-10 拍板）：封面 + 标题 +（可选）进度条 +
/// 小字行（左文案 / 右时间）+ 副标题 +（可选）删除键。
///
/// 布局照模拟器 `.srec`（sim/index.html）：封面 104×59 + 右侧一列
/// 标题（单行省略）/ 进度条 / 小字（进度 + 相对时间）/ 副标题。
///
/// ⚠️ 抽这一层**只把"取哪一份数据"参数化** ☠ —— 尺寸 / 颜色 / 间距 / 省略规则**一个字没改**；
///   `PlayRecordTile` 传进来的值与原实现**逐字等价** ⇒ 播放记录行渲染不变 ✅
///   （逐项对照见 [PlayRecordTile] 的类注释 ✅）。
///
/// - [progress] 为空 ⇒ **进度条整条不渲染**（收藏行**没有进度数据时**也传 null ✅ 不留空白 ☑️）
/// - [metaLeft] / [metaRight] **都为空** ⇒ 小字行整行不渲染
/// - [subtitle] = 最下面那行（播放记录/收藏都是 `siteLine(...)` 出的同一串 ✅）
/// - `onTap` 非空 → 整行可点（设置页预览、播放记录整页、收藏整页都传）
/// - `onDelete` 非空 → 右侧出现 ✕（只有整页传）
class MediaRow extends StatelessWidget {
  final String cover;
  final String title;
  final Widget? progress;
  final String metaLeft;
  final String metaRight;
  final String subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const MediaRow({
    super.key,
    required this.cover,
    required this.title,
    required this.subtitle,
    this.progress,
    this.metaLeft = '',
    this.metaRight = '',
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final metaStyle = TextStyle(fontSize: 11, color: kTxtSub);
    final hasMeta = metaLeft.isNotEmpty || metaRight.isNotEmpty;
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
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: kTxt,
                    ),
                  ),
                  // 间距 7 / 4 / 4 与原实现逐字一致（播放记录行三段全在 ✅；收藏行没进度条 ⇒ 只少 7+进度条）
                  if (progress != null) ...[
                    const SizedBox(height: 7),
                    progress!,
                  ],
                  if (hasMeta) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            metaLeft,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: metaStyle,
                          ),
                        ),
                        if (metaRight.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(metaRight, style: metaStyle),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
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
    if (cover.isEmpty) {
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
        child: FetchedImage(url: cover, memWidth: 240),
      ),
    );
  }
}

/// 一行播放记录（设置页预览 + 播放记录整页共用，样式只此一份）。
///
/// ★ 2026-10-10（甲方案 ✅）：**渲染全部交给 [MediaRow]**，本类只负责"取数据 + 拼文字"——
///   原来的 InkWell / Padding(16,13,6,0) / Row / Column 层次，
///   标题(13, w600, height 1.3, kTxt) / 进度条(上距 7、高 4 圆角 3、已看完绿否则橙) /
///   小字(11, kTxtSub，右段左距 6) / 副标题(上距 4, 11, kTxt) / 删除键(✕ size 18、行内边距 6)
///   **逐项原样搬进 [MediaRow] 与两个共用函数** —— 一个数值、一个文案分支都没改 ✅。
///   （★ 2026-10-10：收藏行也要**同一份**进度外观 ⇒ 进度条与进度小字从本类抽到
///    `playProgressBar` / `playProgressText` 两个顶层函数，两页共用 ✅；本类传参调用，结果逐字不变。）
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
    return MediaRow(
      cover: record.cover,
      title: record.title.isEmpty ? record.url : record.title,
      progress: _bar(),
      metaLeft: _metaLeft(),
      metaRight: fmtAgo(record.updatedAt),
      subtitle: siteLine(record.site, record.videoIndex, record.total),
      onTap: onTap,
      onDelete: onDelete,
    );
  }

  /// 进度条：**样式在共用函数里**（`playProgressBar` ✅ 收藏行用的是同一份）
  Widget _bar() =>
      playProgressBar(value: record.progress, finished: record.finished);

  /// 小字左段 = 进度文案：**格式在共用函数里**（`playProgressText` ✅ 收藏行用的是同一份）
  String _metaLeft() => playProgressText(
        finished: record.finished,
        progress: record.progress,
        position: record.position,
        duration: record.duration,
      );
}

/// 相对时间：刚刚 / N分钟前 / N小时前 / 昨天 / M-D
/// （**播放记录行与收藏行共用** ✅ —— 只此一份，口径不会分叉 ☠）
String fmtAgo(int ms) {
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

/// 时长：m:ss，超一小时 h:mm:ss；0（没拿到时长）返回空串
String fmtDuration(Duration d) {
  if (d <= Duration.zero) return '';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// 副标题 = 站点名 [· 第 N 集 / 共 M 集]（用户 2026-10-10 定的显示格式 ✅；
/// **播放记录行与收藏行共用** ✅ —— 只此一份 ☠，改这里两页同时生效）。
///
/// ⚠️ `videoIndex` 是 **0-based**（篇内视频的列表下标 ✅）：
///   写入点 `detail_page.dart:320` 直接存 `VideoSwitcher.index.value`，
///   而它**从 0 起步**（`player_widget.dart:46`）+ `hasPrev => index.value > 0`（:68）
///   ⇒ 显示时 `N = videoIndex + 1` 才是人看的"第几集" ✅（0 ⇒ 第 1 集）。
///
/// 规则表（用户 2026-10-10 拍板 ✅）：
///   · `total > 1`（多集）⇒ `站点名 · 第 N 集 / 共 M 集`（**N = 1 也显示** ✅）；
///   · `total == 1`（电影/单集）⇒ **只有 `站点名`** ☑️（后缀一律不显示，哪怕索引是脏的）；
///   · `total == 0`（**老数据没有 `'n'` 键** / 拿不到总数）⇒ `videoIndex > 0` 时 `站点名 · 第 N 集`
///     （**老行为一字不变** ✅），否则只有 `站点名` ✅ —— 兼容性全靠这一条 ☠；
///   · 脏数据防护：`videoIndex < 0` 当 0 ✅；`N > M` 时 **clamp 到 M** ✅
///     （用户口径：不出现"第 15 集 / 共 12 集"）。
String siteLine(String site, int videoIndex, int total) {
  final i = videoIndex < 0 ? 0 : videoIndex; // 脏数据兜底（别算出"第 0 集"）
  if (total > 1) {
    final n = i + 1;
    final cur = n > total ? total : n; // ★ clamp 到 M（不出现"第 15 集 / 共 12 集" ✅）
    return '$site · 第 $cur 集 / 共 $total 集';
  }
  if (total == 1) return site; // 电影/单集 ⇒ 后缀不显示
  return i > 0 ? '$site · 第 ${i + 1} 集' : site; // total == 0：老数据行为不变
}

/// 进度条：高 4、圆角 3；已看完满格绿，否则橙
/// （**播放记录行与收藏行共用** ✅ —— 收藏行没有 finished ☑️ ⇒ 恒传 false ⇒ 恒橙）。
Widget playProgressBar({required double value, required bool finished}) {
  final color = finished ? const Color(0xFF2E7D32) : const Color(0xFFE8590C);
  return ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: LinearProgressIndicator(
      value: value,
      minHeight: 4,
      backgroundColor: const Color(0xFFE8E8EC),
      valueColor: AlwaysStoppedAnimation<Color>(color),
    ),
  );
}

/// 进度小字（左段。例：`已看 47% · 1:26 / 3:01`、`已看完 · 3:01`）
/// （**播放记录行与收藏行共用** ✅ —— 格式只此一份，两页不会走样 ☠）。
///
/// ⚠️ 文案分支**逐字照搬**原来 `PlayRecordTile._metaLeft()` 的实现：
///   看完的显式标"已看完"；没时长的只报百分比（别显示 `0:00 / 0:00`）。
String playProgressText({
  required bool finished,
  required double progress,
  required Duration position,
  required Duration duration,
}) {
  final pct = (progress * 100).floor();
  final total = fmtDuration(duration);
  if (finished) return total.isEmpty ? '已看完' : '已看完 · $total';
  return total.isEmpty
      ? '已看 $pct%'
      : '已看 $pct% · ${fmtDuration(position)} / $total';
}
