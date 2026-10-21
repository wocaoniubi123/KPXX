import 'package:flutter/gestures.dart'
    show MultiDragGestureRecognizer, DelayedMultiDragGestureRecognizer;
import 'package:flutter/material.dart';

import 'base/site_ui.dart';
import 'app_bg.dart';
import 'app_background.dart';
import 'detail_page.dart';
import 'favorites.dart';
import 'play_record_tile.dart';
import 'base/downloads/episode_update_checker.dart'; // ★ 集数更新检测（黄点）
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
      builder: (context, _) => ListenableBuilder(
        // ★ 2026-10-21（用户拍板）：启动后台检测完 ⇒ 重建列表，黄点随之出现
        listenable: EpisodeUpdateChecker.i,
        builder: (context, __) => _pageView(context),
      ),
    );
  }

  /// ★ 2026-10-21（用户要求）：**收藏自己有记录（看到第几集 / 总集数），直接用它判，立刻亮不等联网**。
  ///   总集数：收藏自己的 `total`；老收藏 `total == 0` ⇒ 回落播放记录的 `total`。
  ///   另外：联网检测到**站点新增集**也亮（`EpisodeUpdateChecker`，启动后台跑）。
  static bool _hasUpdate(FavoriteItem it) {
    // ★ 纯本地：总集数 > 看到第几集 ⇒ 黄点。
    //   联网只在后台把 `total` 追大（`EpisodeUpdateChecker`），**不参与这里的判定** ✅
    final total = it.total > 0
        ? it.total
        : (PlayHistory.i.find(it.site, it.url)?.total ?? 0);
    return total > it.videoIndex + 1;
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
        // ★ 2026-10-12（**用户最终口径** ✅）：收藏页**只**监听收藏自己 ——
        //   "如果有收藏就存 2 份，播放记录一份，收藏一份。省得冲突，记录进度的时候判断一下
        //    这个视频有没有进收藏" ⇒ 收藏那份**独立于播放记录**：**删掉播放记录也不清它** ✅
        //   （所以这里**不合并监听 `PlayHistory.i`** —— 那是本轮先按"单一真源"做过、随后按用户口径
        //     **回退**掉的做法 ☑️）。
        //   两处保持一致的时机 = **写进度那一次**（`detail_page.dart:472` `Favorites.i.touch(...)`，
        //   与 `PlayHistory.i.touch` 同一处、同一份 pos/dur ✅）；
        //   续播的**分级读取**在详情页：`_resumeFrom()` / `wantIdx`（记录没有 ⇒ 用收藏那份 ✅）。
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
          // ★ 2026-10-21（用户拍板 A）：支持**长按拖拽排序**（150ms 触发，比默认 500ms 灵敏）；
          //   拖完把 key 顺序存进 `Favorites.setOrder()`（持久化到 `fav_order`）。
          return ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: list.length,
            buildDefaultDragHandles: false, // 用下面每行自己的 150ms 长按监听器
            onReorderItem: (oldIndex, newIndex) {
              // ★ Flutter 3.41+ 的 onReorderItem：newIndex **已经是调整后**的，不要再 -1
              final keys = list.map((e) => e.key).toList();
              final moved = keys.removeAt(oldIndex);
              keys.insert(newIndex, moved);
              Favorites.i.setOrder(keys);
            },
            // ★ 甲方案：行布局与播放记录**同一个** MediaRow（样式只此一份 ✅）
            itemBuilder: (context, i) {
              final it = list[i];
              // ★ 2026-10-12（**用户最终口径** ✅ · 回退本轮先做的"单一真源"那版）：
              //   进度读**收藏自己那份快照**（`'p'/'d'` 字段，`favorites.dart:35-36/58-66` ✅）——
              //   用户原话："如果有收藏就存 2 份…记录进度的时候判断一下这个视频有没有进收藏"
              //   ⇒ **两处各存一份、写进度时同步**（同步点 = `detail_page.dart:472` `Favorites.i.touch`，
              //     只更新已存在的收藏、绝不新建/删除 ✅）；
              //   ⇒ **删掉播放记录时不动收藏这份** ⇒ 收藏页**继续显示进度**（用户要的 ✅），
              //     而点进去**也能续播到同一位置**（详情页 `_resumeFrom()` 的分级读取 ✅）
              //     ⇒ 显示与行为**一致** ✅。
              //   ⚠️ 老收藏（没有 `'p'/'d'`）⇒ `hasProgress = false` ⇒ 不画进度、不显示"已看 …" ✅（旧数据兼容 ✅）。
              final hasProg = it.hasProgress;
              // ★ 2026-10-21（用户拍板 A）：外层 key + 长按拖拽监听器（ReorderableListView 要求每行有 key）
              //   ⚠️ Flutter 3.47 的 `ReorderableDelayedDragStartListener` **没有 delay 参数**
              //      （框架固定 kLongPressTimeout = 500ms）⇒ 灵敏只能靠这个类本身，无法再调。
              return _ShortDelayDragStartListener(
                key: ValueKey(it.key),
                index: i,
                child: MediaRow(
                  cover: it.cover,
                  title: it.title.isEmpty ? it.url : it.title,
                // ★ 2026-10-10（用户要求 ✅）：进度条 + 进度小字 —— 与播放记录行用
                //   **同一个** `playProgressBar` / `playProgressText` ⇒ 外观格式逐项一致 ✅
                //   （含 `已看 47% · 1:26 / 3:01` ✅）。
                //   ⚠️ 数据来自**收藏自己那份快照**（`it.position` / `it.duration` ✅ —— 口径见上面
                //      itemBuilder 开头那段 2026-10-12 的说明）⇒ **删掉播放记录后这里照样显示进度** ✅
                //      （用户要的效果）—— 详情页会用 `_resumeFrom()` 的分级读取**续播到同一位置** ✅。
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
                // ★ 2026-10-21（用户要求：收藏自己有记录，直接用它判，立刻亮不等联网）
                dot: _hasUpdate(it),
                ),
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

/// ★ 2026-10-21（用户要求：**灵敏度按"站点管理"那套**）：
///   把 `ReorderableDelayedDragStartListener` 的识别器换成 **180ms** 的
///   `DelayedMultiDragGestureRecognizer`（与 `site_admin.dart` 的 `_ShortDelayDragStartListener` 同款）。
///   ⇒ 长按约 0.18 秒即进入拖拽（框架默认 500ms）；滚动/点击不受影响（抬手未移动 ⇒ 判点击）。
class _ShortDelayDragStartListener extends ReorderableDelayedDragStartListener {
  const _ShortDelayDragStartListener({
    required super.index,
    required super.child,
    super.key,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() =>
      DelayedMultiDragGestureRecognizer(
        delay: const Duration(milliseconds: 180),
        debugOwner: this,
      );
}
