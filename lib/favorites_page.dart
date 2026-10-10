import 'package:flutter/material.dart';

import 'base/site_ui.dart';
import 'app_bg.dart';
import 'app_background.dart';
import 'detail_page.dart';
import 'favorites.dart';
import 'play_record_tile.dart';
import 'settings.dart';
import 'sites.dart';

/// 收藏列表（底栏第 3 格「收藏」进来）。
/// 点一条 = 回到该篇详情，**并从上一次的进度续播**（进度仍归播放记录 ☠ —— 两份存储互不牵连 ✅）。
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 整页跟着背景明暗重建（顶栏标题/图标、收藏行文字都读 kTxt）
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
        title: const Text('收藏'),
        centerTitle: true,
        foregroundColor: kTxt, // 标题/图标直接压在图上 → 跟明暗
        actions: [
          ListenableBuilder(
            listenable: Favorites.i,
            builder: (context, _) => Favorites.i.isEmpty
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
        listenable: Favorites.i,
        builder: (context, _) {
          final list = Favorites.i.items; // 最近观看降序（判据在 favorites.dart 的 _byRecency ✅）
          if (list.isEmpty) {
            return Center(
              child: Text('还没有收藏',
                  style: TextStyle(color: kTxtSub, fontSize: 13)),
            );
          }
          // ★ 2026-10-10（用户要求 ✅）：**两个列表都去掉条目分割线**（收藏 + 播放记录，嫌丑）——
          //   所以这里用 `ListView.builder`（不带 separator ☠）；行的 padding/间距**一个字没动** ✅。
          //   ⚠️ 播放记录页 `play_history_page.dart:56` 是**同款改法**（两边口径一致 ✅）。
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: list.length,
            // ★ 甲方案：行布局与播放记录**同一个** MediaRow（样式只此一份 ✅）
            itemBuilder: (context, i) {
              final it = list[i];
              // ★ 2026-10-10：有进度数据才画进度（老收藏 / 还没播过的 ⇒ false，
              //   行的样子与加进度之前**完全一致** ✅ —— 显示规范：缺则隐藏）
              final hasProg = it.hasProgress;
              return MediaRow(
                key: ValueKey(it.key), // 稳定身份：增删一条时别把整列封面重挂载
                cover: it.cover,
                title: it.title.isEmpty ? it.url : it.title,
                // ★ 2026-10-10（用户要求 ✅）：进度条 + 进度小字 —— 与播放记录行用
                //   **同一个** `playProgressBar` / `playProgressText` ⇒ 外观格式逐项一致 ✅
                //   （含 `已看 47% · 1:26 / 3:01` ✅）。
                //   ⚠️ 数据来自**收藏自己**（`it.position` / `it.duration` ☠ 不跨读 PlayHistory）
                //      ⇒ 用户验收口径："删掉播放记录后，收藏里的进度依然显示" ✅
                //   ☑️ 收藏没有 finished 字段 ⇒ 恒传 false（进度条恒橙、不标"已看完"）
                progress: hasProg
                    ? playProgressBar(value: it.progress, finished: false)
                    : null,
                metaLeft: hasProg
                    ? playProgressText(
                        finished: false,
                        progress: it.progress,
                        position: it.position,
                        duration: it.duration,
                      )
                    : '',
                metaRight: fmtAgo(it.lastViewAt),
                // 站点名 [+ 集数]：与播放记录行**同一个函数** ⇒ 口径不会分叉 ✅
                //   （★ 2026-10-10：`total > 1` 时连第 1 集也显示 ✅）
                subtitle: siteLine(it.site, it.videoIndex, it.total),
                onTap: () => _open(context, it),
                onDelete: () => Favorites.i.remove(it.key),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await confirmClear(
        context: context, title: '清空收藏？', content: '所有收藏会删掉，不能恢复。');
    if (ok) {
      if (AppSettings.i.logConsole) {
        debugPrint('[UI] 清空收藏（原 ${Favorites.i.length} 条）');
      }
      await Favorites.i.clear();
    }
  }

  /// 点一条收藏 → 该篇详情（进度照旧走播放记录续播 ✅）
  void _open(BuildContext context, FavoriteItem it) {
    // 站点名反查 SiteEntry（收藏是按站点名存的）；站点改名/下线就跳过
    final site = kSites.where((s) => s.name == it.site).toList();
    if (site.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            duration: const Duration(seconds: 1), // ★ 2026-10-10（用户批准）：默认 4 秒 → 1 秒
            content: Text('找不到站点「${it.site}」，这条收藏打不开了')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '详情页'),
        builder: (_) => PageBg(
          child: DetailPage(
            site: site.first,
            baseUrl: it.url,
            listCover: it.cover,
            // 集号：收藏时存的那个（0 = 拿不到 ⇒ 详情页自己按播放记录定位 ✅ 同 PlayRecord 口径）
            initialVideoIndex: it.videoIndex,
            // ⚠️ 不传 initialPosition：续播位置由详情页自己查播放记录
            //   （`detail_page.dart:696` `widget.initialPosition ?? _resumeFrom()` ✅）——
            //   收藏里本来就没有进度字段（两份存储互不牵连 ✅）
          ),
        ),
      ),
    );
  }
}
