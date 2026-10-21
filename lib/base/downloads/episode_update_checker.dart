// 集数更新检测（★ 2026-10-21 用户拍板 ✅：**本地优先，联网只追加**）
//
// 职责（只做这一件事）：启动后后台串行拉一次站点详情，
//   站点最新集数 > 本地记录 ⇒ **把新集追加进本地记录**（**不直接决定黄点**）。
//     · 收藏 ⇒ `Favorites.i.updateTotal(site, url, n)`（把 `total` 追大）
//     · 下载 ⇒ `DownloadManager.i.appendEpisodeIfMissing(task, ep)`（追加 ☁️ 未下载集）
//   追加完 `notifyListeners()` ⇒ 两个列表按**新的本地记录**重判黄点。
//
// 黄点判定（**纯本地**，在 UI 层，与联网无关）：
//   · 收藏页：`total > videoIndex + 1`（看到第几集 < 总集数）
//   · 下载页：`doneCount < episodes.length`（已下载 < 记录总集数）
//
// 运行方式（用户确认）：
//   · **只在启动时跑一次**；切到收藏页/下载页不再跑
//   · `main()` 里 `runApp` 之后 `Future.delayed(3 秒)`
//   · **收藏先跑、下载后跑**（收藏条数少、用户更常看 ⇒ 黄点更快出现）
//   · 串行 + 每条间隔 400ms（避免风控）
//   · 任何失败（站点找不到 / 详情拉不到 / 网络断）⇒ **静默跳过**，不动本地记录
import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;

import '../../api.dart';
import '../../favorites.dart';
import '../../models.dart';
import '../../settings.dart';
import '../../sites.dart'; // SiteEntry / kSites
import 'download_manager.dart';
import 'download_model.dart';

class EpisodeUpdateChecker extends ChangeNotifier {
  EpisodeUpdateChecker._();

  static final EpisodeUpdateChecker i = EpisodeUpdateChecker._();

  bool _running = false;

  /// 检测是否在跑（UI 现在没接，留给以后要显示"检测中"用）
  bool get isRunning => _running;

  /// 启动后调用一次：串行检测收藏 + 下载任务，把站点新增的集**追加进本地记录**。
  Future<void> run() async {
    if (_running) return;
    _running = true;
    var appended = 0;
    // ★ 临时排查（2026-10-21）：跑没跑、跑了几条 —— 直接写错误日志页
    debugPrint(
        '检测开始 收藏=${Favorites.i.items.length} 下载=${DownloadManager.i.tasks.length}');
    try {
      // ★ 收藏先跑
      for (final it in List<FavoriteItem>.of(Favorites.i.items)) {
        if (await _appendForFavorite(it)) appended++;
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      // ★ 下载任务后跑
      for (final t in List<DownloadTask>.of(DownloadManager.i.tasks)) {
        appended += await _appendForTask(t);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    } finally {
      _running = false;
      // ★ 临时排查（2026-10-21）：每条结果都进错误日志页（拉失败也记，便于定位）
      debugPrint( '检测结束 追加=$appended');
      if (AppSettings.i.logConsole) {
        debugPrint('[UPD] 联网追加完成：新增 $appended 条');
      }
      notifyListeners();
    }
  }

  /// 拉一次详情并返回集数；站点找不到/异常 ⇒ null（静默）。
  Future<ArticleDetail?> _detailOf(String site, String url) async {
    SiteEntry? entry;
    for (final s in kSites) {
      if (s.name == site) {
        entry = s;
        break;
      }
    }
    if (entry == null) return null; // 站点下线/改名 ⇒ 跳过
    try {
      return await Api(site: entry).detail(url);
    } catch (e) {
      // 静默：拉不到（域名全挂 / 解析失败 / 断网）⇒ 不动本地记录
      if (AppSettings.i.logConsole) {
        debugPrint('[UPD] 拉取失败 site=$site url=$url err=$e');
      }
      return null;
    }
  }

  /// 收藏：站点最新集数 > 本地 total ⇒ 把 total 追大（**只追加，不缩**）。
  Future<bool> _appendForFavorite(FavoriteItem it) async {
    final d = await _detailOf(it.site, it.url);
    if (d == null) {
      debugPrint( '收藏拉取失败 ${it.site} ${it.url}');
      return false;
    }
    final n = d.videos.length;
    debugPrint( '收藏 ${it.site} ${it.url} 站点=$n 本地total=${it.total}');
    if (n <= 1) return false; // 单集视频不处理
    if (n <= it.total) return false; // 本地已经知道这么多
    if (AppSettings.i.logConsole) {
      debugPrint('[UPD] 收藏追加 total ${it.total} ⇒ $n  site=${it.site} url=${it.url}');
    }
    await Favorites.i.updateTotal(it.site, it.url, n);
    return true;
  }

  /// 下载：站点最新集数 > 本地 `episodes.length` ⇒ 把缺的集按 ☁️ 追加进来。
  /// 返回追加的集数。
  Future<int> _appendForTask(DownloadTask t) async {
    final d = await _detailOf(t.site, t.detailUrl);
    if (d == null) {
      debugPrint( '下载拉取失败 ${t.site} ${t.detailUrl}');
      return 0;
    }
    final n = d.videos.length;
    debugPrint( '下载 ${t.site} ${t.detailUrl} 站点=$n 本地=${t.episodes.length}');
    if (n <= 1) return 0; // 单集视频不处理
    if (n <= t.episodes.length) return 0; // 本地已覆盖
    var added = 0;
    for (var i = 0; i < n; i++) {
      final v = d.videos[i];
      final ok = DownloadManager.i.appendEpisodeIfMissing(
        t,
        DownloadEpisode(
          index: i,
          label: v.label,
          playUrl: t.detailUrl, // 与详情页同口径：绝对路径由离线页按站点 base 拼
          lazyUrl: v.lazyUrl,
          headers: v.headers,
          sourceUrl: '',
          wanted: false,
        ),
      );
      if (ok) added++;
    }
    if (added > 0 && AppSettings.i.logConsole) {
      debugPrint('[UPD] 下载追加 $added 集（站点 $n / 本地 ${t.episodes.length - added}）site=${t.site}');
    }
    return added;
  }
}
