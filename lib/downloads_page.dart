import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:kp_video_export/kp_video_export.dart';
import 'package:path_provider/path_provider.dart';

import 'app_background.dart';
import 'app_bg.dart';
import 'base/downloads/download_manager.dart';
import 'base/downloads/download_model.dart';
import 'base/site_ui.dart'; // 公共确认框 confirmClear（收藏页/错误日志页同款）
import 'detail_page.dart';
import 'fetched_image.dart';
import 'offline_player_page.dart';
import 'play_record_tile.dart';
import 'settings.dart';
import 'sites.dart';

/// 下载列表页（底栏第 4 格「下载」）。
///
/// 结构（用户 2026-10-19 拍板）：
/// - AppBar「下载」+ 两个 tab：**【已完成】【下载中】**（顺序照用户原话）；
///   「已完成」= `DownloadManager.completed`（**有已下载的集**就进 —— 用户 2026-10-19 口径：
///   多集任务补下新集时，已下载的照旧显示，允许同时出现在「下载中」）；
///   「下载中」= `DownloadManager.active`（queued/downloading/paused/failed 都算）。
/// - 卡片照播放记录行（`play_record_tile.dart`）：封面 104×59 + 标题（2 行）+ 第二行
///   「站点 · 已下 X/N 集 · 大小」+ 进度条 + 状态（下载中/已暂停/失败可重试）。
/// - 左滑露出【导出】【删除】（交互照 `bg_album_page.dart` 的 `_SwipeRow`，本文件复制一份，
///   不动原文件）：**点了按钮才生效**，整剧删除一定先二次确认。
/// - 点卡片：**有已下载的集** ⇒ 进离线播放页（补下新集期间也能看已下载的）；
///   一集都没有 ⇒ 只弹一句「下载中 X%」。
/// - 长按卡片：底部菜单【播放】【删除整剧】【管理单集】【查看详情】。
///
/// 导出到相册（用户拍板 C：全部能存）：
/// - **仅 iOS**；非 iOS 点导出 ⇒ SnackBar「导出到相册仅支持 iOS」。
/// - 单集 ⇒ 二次确认后导出；多集 ⇒ 选集弹窗（只列已下载的集，可全选/反选）。
/// - `.mp4` 直存相册；`.ts` 先用 `KpVideoExport.remuxToMp4` 重封装成临时 `.mp4` 再存，
///   临时文件用完即删；**App 内的原文件保留**。
/// - 批量导出有进度弹窗（正在导出 X/N · 第Y集），可取消（剩余不再处理），结束给汇总。
class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  /// 品牌橙（与全 App 的进度条/选中 tab 同一个色）
  static const Color _orange = Color(0xFFE8590C);

  /// 危险色（删除按钮 / 失败文案；与背景图集页的删除钮同色）
  static const Color _red = Color(0xFFE5484D);

  @override
  void initState() {
    super.initState();
    // 页面在 IndexedStack 里常驻 ⇒ 这里只触发一次；load() 自身幂等（重复调用返回同一个 Future）
    unawaited(DownloadManager.i.load());
  }

  @override
  Widget build(BuildContext context) {
    // 整页跟着背景明暗 + 下载进度重建
    return ListenableBuilder(
      listenable: Listenable.merge([AppBg.i, DownloadManager.i]),
      builder: (context, _) => _pageView(context),
    );
  }

  Widget _pageView(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent, // 外层已铺背景图，别挡掉
        appBar: AppBar(
          systemOverlayStyle: kStatusOverlay,
          title: const Text('下载'),
          centerTitle: true,
          foregroundColor: kTxt,
          // 右上角「清空」（用户 2026-10-19："跟收藏那样式就行"）——
          // tooltip / 图标与 `favorites_page.dart:34-44` **逐字一致**；列表为空时隐藏
          actions: [
            ListenableBuilder(
              listenable: DownloadManager.i,
              builder: (context, _) => DownloadManager.i.tasks.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: '清空',
                      icon: const Icon(Icons.delete_sweep_outlined),
                      onPressed: () => _confirmClearDownloads(context),
                    ),
            ),
          ],
          bottom: TabBar(
            indicatorColor: _orange,
            // 透明化：M3 的 TabBar 默认在下面画一条浅灰分割线，压在背景图上很突兀
            dividerColor: Colors.transparent,
            // 直接压在背景图上：选中用浅橙（深色图）/ 橙（浅色图），未选中跟明暗翻
            labelColor: AppBg.i.isDark ? const Color(0xFFFFB07A) : _orange,
            unselectedLabelColor:
                AppBg.i.isDark ? Colors.white : const Color(0xFF3A3A3A),
            tabs: const [
              // 顺序照用户原话：【已完成】在前、【下载中】在后
              Tab(text: '已完成'),
              Tab(text: '下载中'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _taskList(context, DownloadManager.i.completed, empty: '还没有下载的视频'),
            _taskList(context, DownloadManager.i.active, empty: '暂无下载任务'),
          ],
        ),
      ),
    );
  }

  /// 一个 tab 的列表（空态文案两页不同）
  Widget _taskList(BuildContext context, List<DownloadTask> list,
      {required String empty}) {
    // 还在读盘 ⇒ 别急着说"没有"，先给个小转圈（免得启动瞬间空态闪一下）
    if (!DownloadManager.i.isLoaded) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (list.isEmpty) {
      return Center(
        child: Text(empty, style: TextStyle(color: kTxtSub, fontSize: 13)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: list.length,
      itemBuilder: (context, i) => _row(context, list[i]),
    );
  }

  /// 一行 = 左滑容器 + 卡片（key 用任务 key：增删一条时别把整行重新挂载）
  Widget _row(BuildContext context, DownloadTask task) {
    return _SwipeRow(
      key: ValueKey(task.key),
      onTap: () => _openTask(context, task),
      onLongPress: () => _menu(context, task),
      onExport: () => _export(context, task),
      onDelete: () => _removeTask(context, task),
      child: _card(task),
    );
  }

  /// 卡片：封面 104×59 / 标题 2 行 / 「站点 · 已下 X/N 集 · 大小」/ 进度条（+ 下载速度）/ 状态
  Widget _card(DownloadTask task) {
    final status = _taskStatus(task);
    final statusColor = status == '失败可重试'
        ? _red
        : (status == '下载中' ? _orange : kTxtSub);
    // 下载速度（B/s）：管理器只统计"正在下载"的集，没有活跃集 ⇒ 0
    // （依赖页面的 ListenableBuilder 监听 DownloadManager.i ⇒ 速度变了会随进度一起重绘）
    final speed = DownloadManager.i.speedOf(task);
    // 大小（固定 MB、1 位小数；用户 2026-10-19 口径：**下载中也要看总大小**）：
    // · 已完成 ⇒ 真实总字节
    // · 下载中 ⇒ `已下载 X / 约 Y MB` —— Y 里"未开始的集"按已开始集的平均大小外推
    //   （HLS 没下之前不知道每集多大，只能估 ⇒ 标「约」，不再出现 210.0/210.0 那种假满格）
    final String sizeText;
    if (task.isAllDone) {
      sizeText = _fmtMb(task.doneBytes);
    } else {
      final est = _estimatedTotal(task);
      // 用户 2026-10-19：「已下载」「约」都去掉（太占宽）⇒ 只显示 `X / Y MB`
      sizeText = est > task.doneBytes
          ? '${_fmtMb(task.doneBytes)} / ${_fmtMb(est)}'
          : _fmtMb(task.doneBytes);
    }
    final meta = '${task.site} · 已下 ${task.doneCount}/${task.episodes.length} 集'
        ' · $sizeText';
    return Padding(
      // 与播放记录行同一套内边距（左侧 16 / 顶部 13）；底部留 12 当行间距
      // （这里没有分割线，行与行靠间距分开）
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cover(task),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title.isEmpty ? task.detailUrl : task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: kTxt,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: kTxtSub),
                      ),
                    ),
                    if (_hasPaused(task))
                      // 已暂停 ⇒ 「继续」按钮（用户 2026-10-19：直接点就续传）
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _resumeButton(task),
                      )
                    else if (status == '下载中')
                      // 下载中 ⇒ 「暂停」按钮（用户 2026-10-19）
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _pauseButton(task),
                      )
                    else if (status.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          status,
                          style: TextStyle(fontSize: 11, color: statusColor),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                // 进度条 + 右侧速度（用户拍板 A 方案）：
                // **只有真正在下载（speed > 0）才显示速度** —— 排队/暂停/失败/未开始
                // 连占位都不留（speed == 0 ⇒ 不渲染 SizedBox + Text）。
                Row(
                  children: [
                    Expanded(
                      // 进度条复用播放记录行那一份（高 4 / 圆角 3；已下完转绿）
                      child: playProgressBar(
                        // 真实进度（用户 2026-10-19 口径：**已下载字节 / 估算总大小**）
                        value: _byteProgress(task),
                        finished: task.isAllDone,
                      ),
                    ),
                    if (speed > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        _fmtSpeed(speed),
                        maxLines: 1,
                        softWrap: false, // 速度文本不换行
                        // 颜色跟随"下载中"状态色（同一份 statusColor，跟背景明暗/失败色走）
                        style: TextStyle(fontSize: 11, color: statusColor),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 封面：有本地文件优先本地（下载时存的封面），否则走站点封面 URL；
  /// 两者都没有 ⇒ 灰底 + 电影图标占位（同尺寸）
  Widget _cover(DownloadTask task) {
    const w = 104.0;
    const h = 59.0;
    const radius = BorderRadius.all(Radius.circular(9));
    final local = task.coverLocal;
    final hasLocal = local.isNotEmpty && File(local).existsSync();
    if (!hasLocal && task.coverUrl.isEmpty) {
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
        // 小图别按原图解码（同背景图集的做法：ResizeImage 包一层）
        child: hasLocal
            ? Image(
                image: ResizeImage(FileImage(File(local)), width: 240),
                fit: BoxFit.cover,
              )
            : FetchedImage(url: task.coverUrl, memWidth: 240),
      ),
    );
  }

  /// 任务级状态文案（按"最该提示的那个"取优先级：下载中 > 失败 > 暂停 > 等待）。
  ///
  /// ★ `wanted` 口径（2026-10-19 跟随任务模型）：**只看要下载的集** ——
  ///   任务现在存**全部集**，☁️ 只登记集（`wanted=false`）的 `status` 恒为 `queued`；
  ///   若把它们一起聚合，一部已经下完的剧会永远显示「等待中」☠。
  ///   全是 ☁️（一集都不下）⇒ 显示「未下载」。
  String _taskStatus(DownloadTask task) {
    var downloading = false;
    var failed = false;
    var paused = false;
    var queued = false;
    var hasWanted = false;
    for (final ep in task.episodes) {
      if (!ep.wanted) continue; // ☁️ 只登记、不下：不参与任务状态
      hasWanted = true;
      if (ep.status == EpStatus.downloading) {
        downloading = true;
      } else if (ep.status == EpStatus.failed) {
        failed = true;
      } else if (ep.status == EpStatus.paused) {
        paused = true;
      } else if (ep.status == EpStatus.queued) {
        queued = true;
      }
    }
    if (!hasWanted) return '未下载'; // 全是 ☁️：这部剧没有任何一集要下载
    if (downloading) return '下载中';
    if (failed) return '失败可重试';
    if (paused) return '已暂停';
    if (queued) return '等待中';
    return '';
  }

  // ---------------------------------------------------------------------------
  // 点 / 长按 / 删除 / 详情
  // ---------------------------------------------------------------------------

  /// 点卡片：**有已下载的集就能进离线页**（用户 2026-10-19：补下新集时已下载的照旧可看）；
  /// 一集都没有 ⇒ 只提示进度。
  void _openTask(BuildContext context, DownloadTask task) {
    if (task.doneCount > 0) {
      Navigator.of(context).push(MaterialPageRoute(
        settings: const RouteSettings(name: '离线播放'),
        builder: (_) => PageBg(child: OfflinePlayerPage(task: task)),
      ));
      return;
    }
    final pct = (task.progress * 100).floor();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 1),
      content: Text('下载中 $pct%'),
    ));
  }

  /// 长按菜单（顺序照用户原话：播放 / 删除整剧 / 管理单集 / 查看详情）
  Future<void> _menu(BuildContext context, DownloadTask task) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('播放'),
              onTap: () => Navigator.pop(ctx, 'play'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除整剧'),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('管理单集'),
              onTap: () => Navigator.pop(ctx, 'episodes'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('查看详情'),
              onTap: () => Navigator.pop(ctx, 'detail'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'play') {
      _openTask(context, task);
    } else if (action == 'remove') {
      await _removeTask(context, task);
    } else if (action == 'episodes') {
      await _manageEpisodes(context, task);
    } else if (action == 'detail') {
      _openDetail(context, task);
    }
  }

  /// 删整剧（**二次确认**）：文件和下载记录一起删
  Future<void> _removeTask(BuildContext context, DownloadTask task) async {
    final ok = await _confirm(
      context,
      title: '删除整剧？',
      content: '「${task.title.isEmpty ? task.detailUrl : task.title}」已下载的文件和下载记录都会删掉，不能恢复。',
      yes: '删除',
    );
    if (!ok) return;
    if (!mounted) return;
    if (AppSettings.i.logConsole) {
      debugPrint('[DL] 删除整剧 剧=${task.title} 集数=${task.episodes.length}');
    }
    await DownloadManager.i.removeTask(task.key);
  }

  /// 右上角「清空」：二次确认 ⇒ 清掉所有下载（文件和记录）。
  /// 确认框走公共 `confirmClear`（`base/site_ui.dart:235`，按钮文案默认「清空」）；
  /// 日志格式照收藏页（`[UI] 清空收藏（原 N 条）`）。
  Future<void> _confirmClearDownloads(BuildContext context) async {
    final ok = await confirmClear(
      context: context,
      title: '清空下载？',
      content: '所有下载（文件和记录）都会删掉，不能恢复。',
    );
    if (!ok) return;
    if (AppSettings.i.logConsole) {
      debugPrint('[UI] 清空下载（原 ${DownloadManager.i.tasks.length} 条）');
    }
    await DownloadManager.i.clearAll();
  }

  /// 查看详情：收藏页同款"按站点名反查 SiteEntry"（站点改名/下线就提示一句）
  void _openDetail(BuildContext context, DownloadTask task) {
    final site = kSites.where((s) => s.name == task.site).toList();
    if (site.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        content: Text('找不到站点「${task.site}」，详情打不开了'),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      settings: const RouteSettings(name: '详情页'),
      builder: (_) => PageBg(
        child: DetailPage(
          site: site.first,
          baseUrl: task.detailUrl,
          listCover: task.coverUrl,
        ),
      ),
    ));
  }

  // ---------------------------------------------------------------------------
  // 管理单集
  // ---------------------------------------------------------------------------

  /// 单集管理（底部弹层）：每集一行状态 + 一个操作（下载/继续/重试/暂停/删除）
  Future<void> _manageEpisodes(BuildContext context, DownloadTask task) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetCtx).height * 0.68,
          // 弹层里实时跟着下载进度刷新
          child: ListenableBuilder(
            listenable: DownloadManager.i,
            builder: (ctx, _) {
              // 从管理器里重新取（task 可能已被删掉）
              final hit =
                  DownloadManager.i.tasks.where((x) => x.key == task.key);
              final eps = hit.isEmpty
                  ? const <DownloadEpisode>[]
                  : hit.first.episodes;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '管理单集 · 共 ${eps.length} 集',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (eps.isEmpty)
                    const Expanded(
                      child: Center(child: Text('这部剧的下载记录已删除')),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: eps.length,
                        itemBuilder: (_, i) => _epTile(ctx, task, eps[i]),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _epTile(BuildContext context, DownloadTask task, DownloadEpisode ep) {
    final action = _epActionLabel(ep);
    return ListTile(
      dense: true,
      title: Text(
        '第 ${ep.index + 1} 集 · ${ep.label}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        _epStatusText(ep),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: ep.status == EpStatus.failed ? _red : null,
        ),
      ),
      // ☁️ 只登记、不下的集 ⇒ action 为 null：**不给可点的假按钮**
      trailing: action == null
          ? null
          : TextButton(
              onPressed: () => _epAction(context, task, ep, action),
              child: Text(action),
            ),
    );
  }

  /// 每集按钮文案（按当前状态）；返回 null ⇒ 不显示按钮
  ///
  /// ★ `wanted` 口径（2026-10-19）：☁️ 只登记集（`wanted=false`、status 恒 queued）
  ///   压根没取过源，点「继续」只会静默无反应 ⇒ 这里直接不给动作。
  ///   例外：`done` 的集（文件真在）照旧给「删除」，那是删本地文件、与 wanted 无关。
  String? _epActionLabel(DownloadEpisode ep) {
    if (!ep.wanted && ep.status != EpStatus.done) return null;
    if (ep.status == EpStatus.done) return '删除';
    if (ep.status == EpStatus.downloading) return '暂停';
    if (ep.status == EpStatus.failed) return '重试';
    return '继续';
  }

  /// 每集状态文案
  String _epStatusText(DownloadEpisode ep) {
    // ☁️ 只登记、不下的集（status 恒 queued）⇒ 别显示「等待中」，那是假状态
    if (!ep.wanted && ep.status != EpStatus.done) return '未下载（可在线观看）';
    switch (ep.status) {
      case EpStatus.done:
        return '已下载 · ${_fmtBytes(ep.totalBytes > 0 ? ep.totalBytes : ep.doneBytes)}';
      case EpStatus.downloading:
        return '下载中 ${(ep.progress * 100).floor()}%';
      case EpStatus.failed:
        return ep.error.isEmpty ? '失败' : '失败：${ep.error}';
      case EpStatus.paused:
        return '已暂停';
      case EpStatus.queued:
        return '等待中';
    }
  }

  /// 每集操作：删除（二次确认）/ 暂停（停整部剧）/ 继续·重试（同一个入口）
  Future<void> _epAction(BuildContext context, DownloadTask task,
      DownloadEpisode ep, String action) async {
    if (action == '删除') {
      final ok = await _confirm(
        context,
        title: '删除这一集？',
        content: '第 ${ep.index + 1} 集的本地文件会删掉，下载记录保留（之后可以重新下载）。',
        yes: '删除',
      );
      if (!ok) return;
      if (AppSettings.i.logConsole) {
        debugPrint('[DL] 删除单集 剧=${task.title} 集=${ep.index}');
      }
      await DownloadManager.i.removeEpisode(task.key, ep.index);
      return;
    }
    // ☁️ 只登记集没有源：不该走到"继续/重试"（按钮已隐藏，这里再兜一道）
    if (!ep.wanted) return;
    if (action == '暂停') {
      await DownloadManager.i.cancelTask(task.key);
      return;
    }
    await DownloadManager.i.retryEpisode(task.key, ep.index);
  }

  // ---------------------------------------------------------------------------
  // 导出到相册（仅 iOS）
  // ---------------------------------------------------------------------------

  Future<void> _export(BuildContext context, DownloadTask task) async {
    final messenger = ScaffoldMessenger.of(context);
    // 用户口径：导出到相册只在 iOS 提供（Windows/桌面没有相册）
    if (!Platform.isIOS) {
      messenger.showSnackBar(const SnackBar(
        duration: Duration(seconds: 2),
        content: Text('导出到相册仅支持 iOS'),
      ));
      return;
    }
    // 只列"真的下好了、文件还在"的集（isEpisodeDownloaded 会查文件是否存在）
    final eps = <DownloadEpisode>[
      for (final ep in task.episodes)
        if (DownloadManager.i.isEpisodeDownloaded(task.key, ep.index)) ep
    ];
    if (eps.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        duration: Duration(seconds: 2),
        content: Text('没有已下载的集，先下完再导出'),
      ));
      return;
    }
    // 单集：二次确认后直接导出
    if (task.episodes.length == 1) {
      final ep = eps.first;
      final size = ep.totalBytes > 0 ? ep.totalBytes : ep.doneBytes;
      final ok = await _confirm(
        context,
        title: '导出到相册？',
        content: '第 ${ep.index + 1} 集会存进系统相册（${_fmtBytes(size)}）；App 里的文件保留。',
        yes: '导出',
      );
      if (!ok) return;
      if (!context.mounted) return;
      await _runExport(context, task, <DownloadEpisode>[ep]);
      return;
    }
    // 多集：选集弹窗（只列已下载的集）
    final picked = await _pickEpisodes(context, eps);
    if (picked == null || picked.isEmpty) return;
    if (!context.mounted) return;
    await _runExport(context, task, picked);
  }

  /// 选集弹窗：checkbox 多选 + 全选/反选；返回 null = 取消
  Future<List<DownloadEpisode>?> _pickEpisodes(
      BuildContext context, List<DownloadEpisode> eps) {
    return showDialog<List<DownloadEpisode>>(
      context: context,
      builder: (ctx) {
        // 默认全选（用户最常用的就是"全都存"）
        final picked = <int>{for (final ep in eps) ep.index};
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('选择要导出的集'),
            content: SizedBox(
              width: double.maxFinite,
              height: 320,
              child: Column(
                children: [
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => setLocal(() {
                          picked.addAll(eps.map((e) => e.index));
                        }),
                        child: const Text('全选'),
                      ),
                      TextButton(
                        onPressed: () => setLocal(() {
                          final all = {for (final ep in eps) ep.index};
                          final next = all.difference(picked);
                          picked
                            ..clear()
                            ..addAll(next);
                        }),
                        child: const Text('反选'),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final ep in eps)
                          CheckboxListTile(
                            dense: true,
                            value: picked.contains(ep.index),
                            onChanged: (v) => setLocal(() {
                              if (v == true) {
                                picked.add(ep.index);
                              } else {
                                picked.remove(ep.index);
                              }
                            }),
                            title: Text(
                              '第 ${ep.index + 1} 集 · ${ep.label}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              _fmtBytes(ep.totalBytes > 0
                                  ? ep.totalBytes
                                  : ep.doneBytes),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: picked.isEmpty
                    ? null
                    : () => Navigator.pop(
                          ctx,
                          <DownloadEpisode>[
                            for (final ep in eps)
                              if (picked.contains(ep.index)) ep
                          ],
                        ),
                child: Text('导出（已选 ${picked.length} 集）'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 执行导出：权限 → 进度弹窗（可取消）→ 逐集处理 → 汇总
  Future<void> _runExport(BuildContext context, DownloadTask task,
      List<DownloadEpisode> eps) async {
    final messenger = ScaffoldMessenger.of(context);
    // 权限照背景图集页（hasAccess / requestAccess）
    try {
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) {
          if (mounted) {
            messenger.showSnackBar(const SnackBar(
              duration: Duration(seconds: 2),
              content: Text('没有相册权限，导不出去 —— 去「设置 → 隐私 → 照片」里给 KPXX 打开'),
            ));
          }
          return;
        }
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('相册权限检查失败：${_short(e)}'),
        ));
      }
      return;
    }
    if (!context.mounted) return;

    final total = eps.length;
    final label = ValueNotifier<String>('准备导出…');
    final doneN = ValueNotifier<int>(0);
    final cancel = ValueNotifier<bool>(false);
    final dialogBuilt = Completer<void>();
    BuildContext? dialogCtx;
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogCtx = ctx;
        if (!dialogBuilt.isCompleted) dialogBuilt.complete();
        return AlertDialog(
          title: const Text('导出到相册'),
          content: SizedBox(
            width: 260,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: label,
                  builder: (_, v, __) =>
                      Text(v, style: const TextStyle(fontSize: 13)),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<int>(
                  valueListenable: doneN,
                  builder: (_, v, __) => LinearProgressIndicator(
                    value: total <= 0 ? null : v / total,
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancel.value = true;
                label.value = '取消中…（当前这集处理完就停）';
              },
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
    // 等弹窗真的建出来（拿到它自己的 context，收尾时才能精确 pop 它）
    await dialogBuilt.future;

    var okCount = 0;
    final fails = <String>[];
    try {
      for (var i = 0; i < eps.length; i++) {
        if (cancel.value) break; // 取消 ⇒ 剩余不再处理
        final ep = eps[i];
        label.value = '正在导出 ${i + 1}/$total · 第 ${ep.index + 1} 集';
        try {
          await _exportOne(ep);
          okCount++;
          if (AppSettings.i.logConsole) {
            debugPrint('[DL] 导出成功 剧=${task.title} 集=${ep.index}');
          }
        } catch (e) {
          // 某一集失败（重封装不支持 / 相册写入失败 / 文件丢失…）⇒ 记下来继续下一集
          fails.add('第 ${ep.index + 1} 集：${_short(e)}');
          if (AppSettings.i.logConsole) {
            debugPrint('[DL] 导出失败 剧=${task.title} 集=${ep.index} 原因=$e');
          }
        }
        doneN.value = i + 1;
      }
    } finally {
      if (dialogCtx != null && dialogCtx!.mounted) {
        Navigator.of(dialogCtx!).pop();
      }
      // 等弹窗的退场动画走完，再释放 notifier（否则退场期间可能重建到已释放的对象）
      await dialogFuture;
      label.dispose();
      doneN.dispose();
      cancel.dispose();
    }

    if (!context.mounted) return;
    final rest = total - okCount - fails.length;
    if (total == 1) {
      if (okCount == 1) {
        messenger.showSnackBar(const SnackBar(
          duration: Duration(seconds: 1),
          content: Text('已导出到相册'),
        ));
      } else if (fails.isNotEmpty) {
        messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('导出失败：${fails.first}'),
        ));
      } else {
        messenger.showSnackBar(const SnackBar(
          duration: Duration(seconds: 1),
          content: Text('已取消导出'),
        ));
      }
      return;
    }
    await _showSummary(context, total: total, ok: okCount, fails: fails, rest: rest);
  }

  /// 单集导出：`.mp4` 直存；`.ts` 先重封装成临时 `.mp4` 再存（临时文件用完即删）
  Future<void> _exportOne(DownloadEpisode ep) async {
    final path = ep.localPath;
    if (path.isEmpty) throw const _ExportError('本地文件路径为空');
    final lower = path.toLowerCase();
    if (lower.endsWith('.mp4')) {
      await Gal.putVideo(path);
      return;
    }
    if (lower.endsWith('.ts')) {
      final tmp = await getTemporaryDirectory();
      final out = '${tmp.path}/export_${DateTime.now().microsecondsSinceEpoch}.mp4';
      try {
        final mp4 = await KpVideoExport.remuxToMp4(path, out);
        if (mp4 == null || mp4.isEmpty) {
          // 非 iOS（插件没注册）就是 null —— 调用方会记成这一集失败
          throw const _ExportError('重封装不可用（仅 iOS 支持）');
        }
        await Gal.putVideo(mp4);
      } finally {
        // 导出的临时 mp4 删掉；App 里下载的原文件（.ts）保留
        try {
          final f = File(out);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      return;
    }
    throw const _ExportError('不支持的文件类型（不是 .mp4 / .ts）');
  }

  /// 批量导出的汇总（成功/失败/取消剩多少）
  Future<void> _showSummary(
    BuildContext context, {
    required int total,
    required int ok,
    required List<String> fails,
    required int rest,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出完成'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('共 $total 集 · 成功 $ok 集 / 失败 ${fails.length} 集'),
              if (rest > 0) ...[
                const SizedBox(height: 6),
                Text('已取消：还有 $rest 集没处理'),
              ],
              for (final f in fails) ...[
                const SizedBox(height: 6),
                Text(
                  f,
                  style: const TextStyle(fontSize: 12, color: _red),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 真实进度 / 继续下载（用户 2026-10-19）
  // ---------------------------------------------------------------------------

  /// 任务进度（0~1，用户 2026-10-19 口径：**已下载字节 / 总大小字节**）。
  /// 总大小用 [_estimatedTotal]（已开始的集是真实值，未开始的集按平均大小外推）；
  /// 估不出来（一集都没开始）⇒ 退回集数口径，至少不是 0。
  double _byteProgress(DownloadTask task) {
    if (task.isAllDone) return 1;
    final total = _estimatedTotal(task);
    if (total <= 0) {
      final n = task.episodes.length;
      return n == 0 ? 0 : (task.doneCount / n).clamp(0.0, 1.0);
    }
    return (task.doneBytes / total).clamp(0.0, 1.0);
  }

  /// 有没有"已暂停"的集（有就给「继续」按钮）
  static bool _hasPaused(DownloadTask task) =>
      task.episodes.any((e) => e.wanted && e.status == EpStatus.paused);

  Widget _resumeButton(DownloadTask task) {
    return GestureDetector(
      onTap: () => _resume(task),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: _orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _orange.withValues(alpha: 0.55)),
        ),
        child: const Text(
          '继续',
          style: TextStyle(
            fontSize: 11,
            color: _orange,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// 任务总大小的**估算**（字节，用户 2026-10-19：下载中要显示总大小）：
  /// 已开始的集用真实 `totalBytes`；**未开始的集**按"已开始集的平均大小"外推。
  /// ⚠️ HLS 在下载前拿不到每集大小 ⇒ 这是估算（显示时标「约」），误差来自各集大小不等。
  int _estimatedTotal(DownloadTask task) {
    var known = 0; // 已开始集的 totalBytes 之和
    var started = 0; // 已开始的集数
    var wanted = 0;
    for (final ep in task.episodes) {
      if (!ep.wanted) continue;
      wanted++;
      if (ep.status == EpStatus.done) {
        known += ep.totalBytes > 0 ? ep.totalBytes : ep.doneBytes;
        started++;
      } else if (ep.totalBytes > 0) {
        known += ep.totalBytes;
        started++;
      }
    }
    final remaining = wanted - started;
    if (remaining <= 0 || started <= 0) return known; // 一集都没开始 ⇒ 没法估
    return known + known ~/ started * remaining;
  }

  /// 下载中 ⇒ 「暂停」按钮（用户 2026-10-19）：停整部剧（正在下的那集取消，排队集保留）
  Widget _pauseButton(DownloadTask task) {
    return GestureDetector(
      onTap: () => _pause(task),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kTxtSub.withValues(alpha: 0.55)),
        ),
        child: Text(
          '暂停',
          style: TextStyle(
            fontSize: 11,
            color: kTxtSub,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// 点「暂停」：停整部剧
  Future<void> _pause(DownloadTask task) async {
    await DownloadManager.i.cancelTask(task.key);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      duration: Duration(seconds: 1),
      content: Text('已暂停'),
    ));
  }

  /// 点「继续」：恢复该任务所有已暂停的集
  Future<void> _resume(DownloadTask task) async {
    final n = await DownloadManager.i.resumeTask(task.key);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 1),
      content: Text(n > 0 ? '继续下载（$n 集）' : '没有可继续的集'),
    ));
  }

  // ---------------------------------------------------------------------------
  // 小工具
  // ---------------------------------------------------------------------------

  /// 下载速度（B/s → 人话）：≥ 1 MB/s 用 `MB/s`（1 位小数）；
  /// ≥ 1 KB/s 用 `KB/s`（整数）；再小用 `B/s`（别显示 `0 KB/s`，那看着像卡死）
  static String _fmtSpeed(double bytesPerSecond) {
    const mb = 1024 * 1024;
    const kb = 1024;
    if (bytesPerSecond >= mb) {
      return '${(bytesPerSecond / mb).toStringAsFixed(1)} MB/s';
    }
    if (bytesPerSecond >= kb) {
      return '${(bytesPerSecond / kb).round()} KB/s';
    }
    return '${bytesPerSecond.round()} B/s';
  }

  /// 大小（**固定 MB、1 位小数**）—— 下载卡片 meta 用（用户 2026-10-19 口径：
  /// 「已完成」显示已下载总大小、「下载中」显示已下载 / 总大小，单位一律 MB，
  /// 不做 KB / B 自适应）。0 / 负数 ⇒ `0.0 MB`。
  static String _fmtMb(int bytes) {
    final mb = bytes <= 0 ? 0.0 : bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// 大小（人话）：字节 / KB / MB / GB；未知返回「大小未知」
  static String _fmtBytes(int b) {
    if (b <= 0) return '大小未知';
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (b >= gb) return '${(b / gb).toStringAsFixed(2)} GB';
    if (b >= mb) return '${(b / mb).toStringAsFixed(1)} MB';
    if (b >= kb) return '${(b / kb).toStringAsFixed(0)} KB';
    return '$b B';
  }

  /// 异常文本压短（汇总里别弹一屏英文堆栈）
  static String _short(Object e) {
    final s = '$e';
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }

  /// 通用二次确认（沿用仓库 AlertDialog 的按钮顺序：取消在左、确认在右）
  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String content,
    String yes = '确定',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(yes),
          ),
        ],
      ),
    );
    return ok == true;
  }
}

/// 导出流程内部用的短错误（只为了汇总里出现人话，不是给框架看的）
class _ExportError implements Exception {
  final String message;
  const _ExportError(this.message);

  @override
  String toString() => message;
}

/// 一行：**左滑露出「导出 / 删除」两个按钮**，点了按钮才动手。
///
/// 复制自 `bg_album_page.dart`（原文件不动）：滑开固定宽度露出按钮、停顿一下再点；
/// 没滑开时点一下 = [onTap]；滑开时点一下 = 收回（不误触）。
/// 本页新增 [onLongPress]（长按卡片出菜单）—— 其余手势/动画逻辑与原文件逐行一致。
///
/// ⚠️ 不用 `Dismissible`：它只有"滑到底即触发"这一种形态，做不出"停在半路等点按钮"。
class _SwipeRow extends StatefulWidget {
  const _SwipeRow({
    super.key,
    required this.child,
    required this.onTap,
    required this.onLongPress,
    required this.onExport,
    required this.onDelete,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  State<_SwipeRow> createState() => _SwipeRowState();
}

class _SwipeRowState extends State<_SwipeRow>
    with SingleTickerProviderStateMixin {
  /// 每个按钮宽 64（和模拟器 `.bgal-acts > div` 一致）；滑开位移 = 两个按钮
  static const double _btnW = 64;
  static const double _total = _btnW * 2;

  /// 吸附动画（只用于"松手 / 点一下收回"；拖动中是直接跟手的）。
  ///
  /// ⚠️ 这里**不用** `AnimatedContainer(transform: Matrix4…)`：`Matrix4` 是 vector_math
  /// 的类型，不在 `package:flutter/material.dart` 的导出链上（3.24.5 的 basic.dart /
  /// painting.dart / tween.dart 都查过，没有 re-export）→ 用它有编译不过的风险。
  /// `Transform.translate` 收的是 `Offset`，配合自管的 AnimationController，全是确定可用的 API。
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(() => setState(() {}));

  /// 目标位移：0 = 合上，-[_total] = 全开（拖动时它就是实时位置）
  double _dx = 0;

  /// 本次吸附的起点（拖到一半松手 → 从当前位置接着走，不跳）
  double _snapFrom = 0;

  /// 跟手期间不走动画
  bool _dragging = false;

  /// 当前实际显示的位移
  double get _offset => _dragging
      ? _dx
      : _snapFrom + (_dx - _snapFrom) * Curves.easeOut.transform(_ac.value);

  bool get _open => _offset != 0;

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails d) {
    _ac.stop(); // 拖起来就打断正在跑的吸附动画（放 setState 外面：它自己会回调 setState）
    setState(() {
      _dragging = true;
      // ⚠️ clamp() 的静态返回类型是 num，直接赋给 double 编译不过（DEVLOG §4.6 踩过）
      _dx = (_dx + d.delta.dx).clamp(-_total, 0.0).toDouble();
    });
  }

  void _settle(DragEndDetails d) {
    // 左甩（速度够快）也算要开 —— 手滑一下不必非要拖过半
    final flung = d.velocity.pixelsPerSecond.dx < -300;
    _snap(open: flung || _dx < -_total / 2);
  }

  /// 吸附到开 / 合（松手、手势被取消、点一下收回，都走这里）
  void _snap({required bool open}) {
    final from = _offset; // setState 之前取：拖到一半松手就从当前位置接着动画
    setState(() {
      _dragging = false;
      _snapFrom = from;
      _dx = open ? -_total : 0;
    });
    _ac.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 按钮层：垫在行**底下**（行是透明的，不滑开就得藏起来）
        Positioned.fill(
          child: AnimatedOpacity(
            // 滑开 3px 以上才亮出按钮（免得点一下闪一下）
            opacity: _offset < -3 ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch, // 按钮撑满行高
              children: [
                // 点了就收回（不然导出完这行还停在滑开位，看着像没反应）
                _btn('导出', const Color(0xFF3C4043), () {
                  _snap(open: false);
                  widget.onExport();
                }),
                _btn('删除', const Color(0xFFE5484D), widget.onDelete),
              ],
            ),
          ),
        ),
        // 内容层：跟手位移。Transform 会连命中区域一起搬走 → 滑开后按钮点得到，
        // 没滑开时内容层盖在上面（透明也能接手势）→ 按钮点不到。
        Transform.translate(
          offset: Offset(_offset, 0),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque, // 行是透明的，不 opaque 空白处收不到手势
            onHorizontalDragUpdate: _update,
            onHorizontalDragEnd: _settle,
            onHorizontalDragCancel: () => _snap(open: _open),
            child: InkWell(
              onTap: _open ? () => _snap(open: false) : widget.onTap,
              onLongPress: _open ? null : widget.onLongPress,
              child: widget.child,
            ),
          ),
        ),
      ],
    );
  }

  Widget _btn(String text, Color bg, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: _btnW,
          color: bg,
          alignment: Alignment.center,
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}
