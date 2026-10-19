// 离线下载 —— 管理器（单例 + 持久化 + 调度）。
//
// 职责边界：UI 只跟这一层说话；真正"怎么下"全在 `DownloadEngine`（纯 Dart、可独立测）。
//
// 调度口径（用户拍板）：
// · 同时最多 [maxActiveTasks] = **2 部剧**"下载中"；
// · 一部剧内部**逐集**下（不并行下两集：同一部剧的分片已经很吃连接了）；
// · 一集内部的**分片并发**由引擎管（4）。
//
// 持久化：`shared_preferences` 里一个键 [storageKey]（JSON 数组字符串）。
// 变更后 [_scheduleSave] 防抖 250ms 再写盘 —— 进度回调每秒能来好几次，
// 每来一次就写盘会把主线程拖死（`shared_preferences` 在移动端是异步落盘的）。
//
// 为什么 `load()` 不自动续跑：
// 盘上的 `downloading` 一律降级成 `paused`（App 被杀过，没有任何回调能收尾）。
// 自动续跑会让"只是打开 App 看一眼"也立刻开始吃流量；由 UI 显式调
// `retryEpisode`（继续/重试同一个入口）才开始。
//
// 失败处理：某集失败 ⇒ 该集 `failed` + 原因，**这部剧停在这儿**（不回退已完成的集，
// 也不继续下一集 —— 网络/鉴权挂了时继续只会把剩下几十集全刷成 failed）。
// 其它剧照常跑（2 个槽位互不影响）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config.dart';
import '../../fetched_image.dart';
import '../../settings.dart';
import 'download_engine.dart';
import 'download_model.dart';

class DownloadManager extends ChangeNotifier {
  DownloadManager._();

  /// 全局单例（一个 App 一份下载队列；UI 直接 `DownloadManager.i`）
  static final DownloadManager i = DownloadManager._();

  /// 持久化键（与仓库既有做法一致：一个键存一整串 JSON）
  static const String storageKey = 'dl_tasks';

  /// 同时"下载中"的剧数上限（用户拍板 2）
  static const int maxActiveTasks = 2;

  /// 一集内部分片并发数（真正生效在引擎里，这里只是给 UI/日志一个口径）
  static const int maxSegmentsPerEpisode = DownloadEngine.segmentConcurrent;

  /// 落盘防抖（200~300ms 区间，用户口径）
  static const Duration saveDebounce = Duration(milliseconds: 250);

  /// 进度通知节流：≥250ms 才 notify 一次（引擎每块/每片都会回调）
  static const Duration _notifyInterval = Duration(milliseconds: 250);

  /// 速度显示的硬上限（B/s）：正常下载不可能超过 100 MB/s —— 超过就按尖峰压掉
  static const double _maxSpeedBps = 100 * 1024 * 1024;

  /// 速度采样最小窗口：分片并发时相邻进度回调可能只隔几毫秒、却一次跳几 MB
  /// ⇒ 瞬时值爆表（实测 536 / 1111 MB/s ☠）；**攒够这个窗口再算一次平均速度**
  static const Duration _speedWindow = Duration(milliseconds: 300);

  final List<DownloadTask> _tasks = [];

  /// 正在跑任务的剧 key（≤ [maxActiveTasks]）
  final Set<String> _activeTasks = <String>{};

  /// 正在下载的"集"（`任务key|集号`）
  final Set<String> _runningEpisodes = <String>{};

  /// 取消旗标（引擎轮询它；只对"正在下"的集有意义）
  final Set<String> _cancelEpisodes = <String>{};

  /// 被 `cancelTask` 停住的剧：pump 跳过它，直到 `enqueueTask` / `retryEpisode`
  final Set<String> _stoppedTasks = <String>{};

  /// 每集瞬时速度（B/s，EMA 平滑；key = `任务key|集号`）。
  /// **不持久化** —— App 重启后归零是合理的（不存在"历史速度"这回事）。
  final Map<String, double> _speeds = <String, double>{};

  /// 正在下封面的任务 key（防"同一部剧连续入队"时重复抓同一张图）
  final Set<String> _coverInflight = <String>{};

  bool _pumping = false;
  bool _loaded = false;
  Future<void>? _loading;
  Timer? _saveTimer;
  Directory? _dir;
  String _dirPath = '';

  /// 下载根目录（`getApplicationSupportDirectory()/downloads`）。
  /// ⚠️ 首次 [load] 之前是空串（目录是异步拿的）；UI 里 `load()` 之后再读。
  String get downloadDir => _dirPath;

  bool get isLoaded => _loaded;

  /// 全部任务，**新 → 旧**（按创建时间倒序）
  List<DownloadTask> get tasks {
    _sortTasks();
    return List<DownloadTask>.unmodifiable(_tasks);
  }

  /// 「已完成」分组（用户 2026-10-19 拍板）：**只要有已下载的集就进这里**（doneCount > 0）。
  /// ⚠️ 多集任务可以**同时出现在「已完成」和「下载中」**：补下新集时，
  ///   已下载的集不能让整个任务从「已完成」消失（否则已下的集在列表里就看不到了）。
  ///   `active` 仍按"有未完成集"判定 —— 两者互补、允许重叠。
  List<DownloadTask> get completed =>
      <DownloadTask>[for (final t in tasks) if (t.doneCount > 0) t];

  /// 还没下完的（含失败/暂停；列表页"下载中/未完成"分组）。
  /// ★ `wanted` 口径：只看**要下载的**集 —— 任务里那些"只登记、不下"的☁️集（wanted=false）
  ///   即使 status 还是 queued 也不算"没下完"（否则离线页/列表永远显示在下载中）。
  List<DownloadTask> get active => <DownloadTask>[
        for (final t in tasks)
          if (t.episodes.any((e) => e.wanted && e.status != EpStatus.done)) t
      ];

  /// 启动时读一次盘。重复调用不会重复加载（返回同一个 Future）。
  Future<void> load() {
    final inflight = _loading;
    if (inflight != null) return inflight;
    final f = _load();
    _loading = f;
    return f;
  }

  Future<void> _load() async {
    await _ensureDir();
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(storageKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) {
          for (final e in list) {
            if (e is! Map) continue;
            final t = DownloadTask.fromJson(Map<String, dynamic>.from(e));
            if (t == null) continue;
            if (_indexOf(t.key) >= 0) continue; // 同一部剧只留一条
            for (final ep in t.episodes) {
              if (ep.status == EpStatus.downloading) {
                // App 被杀过 ⇒ 降级成 paused（等用户点继续）
                ep.status = EpStatus.paused;
              }
              if (ep.status == EpStatus.done) {
                // 记录说下完了，但文件被人删了 / 路径丢了 ⇒ 回到待下
                if (ep.localPath.isEmpty || !_fileExists(ep.localPath)) {
                  ep.status = EpStatus.queued;
                  ep.localPath = '';
                  ep.doneBytes = 0;
                }
              }
            }
            _tasks.add(t);
          }
        }
      }
    } catch (e) {
      // 数据坏了就当空（与仓库既有做法一致：一条坏记录不能拖垮启动）
      _log('读取失败：$e');
    }
    _sortTasks();
    _loaded = true;
    // 历史任务里可能存着"密文封面"（旧 ensureCover 用 httpClient 原样存盘的 bug）
    // ⇒ 载入后逐个自愈/补齐。fire-and-forget：封面只是列表上的一张图，不能拖住页面初始化。
    for (final t in _tasks) {
      unawaited(ensureCover(t));
    }
    _log('加载完成 任务=${_tasks.length} 目录=${_dirPath.isEmpty ? 'null' : _dirPath}');
    notifyListeners();
  }

  /// 把一部剧加入下载（同 key 已存在 ⇒ 合并）。
  ///
  /// 合并规则（用户口径）：新集补进去；**已 done 的集跳过**；未完成的集用新快照替换
  /// （重下必须用新的源地址/请求头 —— 签名和 Cookie 都会过期）。
  Future<void> enqueueTask(DownloadTask t) async {
    await load();
    final idx = _indexOf(t.key);
    if (idx < 0) {
      _normalizeNewEpisodes(t);
      _tasks.add(t);
      _log('入队 ${_tagTask(t)} 集数=${t.episodes.length}');
    } else {
      final old = _tasks[idx];
      if (old.coverLocal.isEmpty && t.coverLocal.isNotEmpty) {
        old.coverLocal = t.coverLocal;
      }
      var added = 0;
      var replaced = 0;
      for (final ep in t.episodes) {
        final k = _indexOfEp(old, ep.index);
        if (k < 0) {
          if (ep.status == EpStatus.done && ep.localPath.isEmpty) {
            ep.status = EpStatus.queued;
          }
          // ☁️ 只登记、不下的集：status 留 queued 也不会被调度（`_runTask` 只看 wanted）
          old.episodes.add(ep);
          added++;
          continue;
        }
        final oldEp = old.episodes[k];
        // ★ 本次**没勾选**这一集 ⇒ 完全不动旧记录（"没勾" ≠ "取消下载"：
        //   已排队/已下好的集在弹层里本来就不可选，绝不能被新快照降级成 wanted=false）
        if (!ep.wanted) continue;
        // ★ 补下载：旧记录 wanted=false、这次勾上了 ⇒ 置 true（下面会用新快照换源/头）
        oldEp.wanted = true;
        // 正在下 / 已经下好且文件还在 ⇒ 都不动：
        // · 换对象会让跑着的下载把进度写到旧引用上（UI 再也看不到进度）；
        // · 下好的集不因重复入队而重下。
        if (_runningEpisodes.contains(_epKey(old.key, ep.index))) continue;
        if (oldEp.status == EpStatus.done && _fileExists(oldEp.localPath)) continue;
        if (ep.status == EpStatus.done && ep.localPath.isEmpty) {
          ep.status = EpStatus.queued;
        }
        old.episodes[k] = ep;
        replaced++;
      }
      old.episodes.sort((a, b) => a.index.compareTo(b.index));
      _log('合并 ${_tagTask(old)} 新增=$added 替换=$replaced');
    }
    // 用户主动入队 ⇒ 解除之前的暂停闸
    _stoppedTasks.remove(t.key);
    _sortTasks();
    notifyListeners();
    _scheduleSave();
    // 封面本地化：fire-and-forget（失败静默，不能因为它拖住入队/调度）
    unawaited(ensureCover(_findTask(t.key) ?? t));
    _pump();
  }

  /// 封面本地化：把**明文**封面图存到任务目录，并写回 [DownloadTask.coverLocal]。
  ///
  /// 为什么放在管理器：任务目录名（[_taskDirName]）和下载根目录（[_ensureDir]）都是本类私有，
  /// UI 层拼不出来；写完还要 `_scheduleSave()`，同样是本类的职责。
  ///
  /// ⚠️ **不能**自己用 `Site.httpClient` 存原样字节：51吃瓜等站的图是 AES **密文**，
  /// 存下来 Flutter 会报 `Exception: Invalid image data`（2026-10-19 用户实测）。
  /// 一律走 [FetchedImage.fetchDecoded]：它会「下载 → 按站点规则解密 → 魔数校验 → 落盘明文缓存」。
  ///
  /// 自动自愈：本地封面存在但**魔数不是 jpg/png/gif/webp**（历史版本存进去的密文）⇒ 删掉重抓。
  /// 失败**静默**（封面只是列表上的一张图，不能因为抓图失败把下载入口变成错误弹窗）。
  Future<void> ensureCover(DownloadTask t) async {
    if (t.coverUrl.isEmpty && t.coverLocal.isEmpty) return;
    // ① 已有本地封面：先验魔数；坏图（密文 / 半截 / 非图片）删掉重抓
    if (t.coverLocal.isNotEmpty) {
      if (await _coverFileOk(t.coverLocal)) return; // 正常图 ⇒ 什么都不做
      // 只删"下载根目录内"的文件：coverLocal 来自本地持久化，万一被改坏也不能删到用户别处
      final root = _dir?.path ?? '';
      if (root.isNotEmpty && t.coverLocal.startsWith(root)) {
        try {
          final old = File(t.coverLocal);
          if (await old.exists()) await old.delete();
        } catch (_) {}
      }
      t.coverLocal = '';
      _scheduleSave();
      _log('封面失效已清 ${_tagTask(t)}');
    }
    if (t.coverUrl.isEmpty) return;
    if (_coverInflight.contains(t.key)) return;
    _coverInflight.add(t.key);
    try {
      final dir = await _episodeDir(t);
      if (dir == null) return;
      // 走 FetchedImage（下载→解密→魔数校验）；**不要**自己存密文
      final bytes = await FetchedImage.fetchDecoded(t.coverUrl);
      if (bytes == null || bytes.isEmpty) {
        _log('封面失败（解密后为空）${_tagTask(t)}');
        return;
      }
      final ext = _coverExtByMagic(bytes); // 明文按魔数定扩展名（URL/Content-Type 是密文那层的，不可信）
      final f = File('$dir/cover.$ext');
      await f.writeAsBytes(bytes, flush: false);
      // 抓图期间任务被删了（用户点了删除）⇒ 别留下孤儿文件
      if (_indexOf(t.key) < 0) {
        try {
          await f.delete();
        } catch (_) {}
        // 任务没了 ⇒ 空的任务目录也收掉（"清空下载"与封面抓取撞车时会走到这里）
        try {
          final d = f.parent;
          if (await d.exists() && await d.list().isEmpty) await d.delete();
        } catch (_) {}
        return;
      }
      t.coverLocal = f.path;
      _log('封面已存 ${_tagTask(t)} 字节=${bytes.length} 格式=$ext');
      notifyListeners();
      _scheduleSave();
    } catch (e) {
      _log('封面失败 ${_tagTask(t)} 原因=$e');
    } finally {
      _coverInflight.remove(t.key);
    }
  }

  /// 这一集是否已下好（状态 done **且**文件还在）
  bool isEpisodeDownloaded(String taskKey, int epIndex) {
    final ep = _findEpisode(taskKey, epIndex);
    if (ep == null || ep.status != EpStatus.done) return false;
    if (ep.localPath.isEmpty) return false;
    return _fileExists(ep.localPath);
  }

  /// 这一集此刻是否在下载（UI 用来显示转圈 / 禁用按钮）
  bool isEpisodeDownloading(String taskKey, int epIndex) =>
      _runningEpisodes.contains(_epKey(taskKey, epIndex));

  /// 继续一部被暂停/中断的剧（下载页「继续」按钮，用户 2026-10-19 要求）：
  /// 把所有 `wanted && paused` 的集改回 queued、解除暂停闸、重新调度。
  /// 返回恢复的集数（0 = 没有可恢复的，调用方不必提示）。
  Future<int> resumeTask(String taskKey) async {
    await load();
    final t = _findTask(taskKey);
    if (t == null) return 0;
    _stoppedTasks.remove(taskKey);
    var n = 0;
    for (final ep in t.episodes) {
      if (!ep.wanted || ep.status != EpStatus.paused) continue;
      ep.status = EpStatus.queued;
      ep.error = '';
      n++;
    }
    if (n > 0) {
      _log('继续任务 ${_tagTask(t)} 集数=$n');
      notifyListeners();
      _scheduleSave();
      _pump();
    }
    return n;
  }

  /// 该任务**活跃集**的速度之和（B/s）。没有活跃集 ⇒ 0。
  ///
  /// 为什么按任务求和：一部剧同一时刻只下一集（调度口径），但偶尔会有"上一集收尾、
  /// 下一集刚起"的重叠瞬间，求和比"取第一个"更稳；没有活跃集就明确返回 0，
  /// UI 直接据此隐藏速度行。
  double speedOf(DownloadTask t) {
    var sum = 0.0;
    for (final ep in t.episodes) {
      final k = _epKey(t.key, ep.index);
      if (!_runningEpisodes.contains(k)) continue;
      sum += _speeds[k] ?? 0;
    }
    return sum;
  }

  /// 停掉一部剧：正在下的那集被取消（状态回到 paused），排队的集保持 queued 但不会自己再起
  Future<void> cancelTask(String taskKey) async {
    final t = _findTask(taskKey);
    if (t == null) return;
    _stoppedTasks.add(taskKey);
    for (final ep in t.episodes) {
      final k = _epKey(taskKey, ep.index);
      if (!_runningEpisodes.contains(k)) continue;
      _cancelEpisodes.add(k);
      _speeds.remove(k); // 暂停 ⇒ 速度立刻归零（别让界面留一个"卡住的速度"）
      ep.status = EpStatus.paused;
    }
    _log('暂停任务 ${_tagTask(t)}');
    notifyListeners();
    _scheduleSave();
  }

  /// 重试/继续一集（失败、暂停、手动"继续"都走这里）
  Future<void> retryEpisode(String taskKey, int epIndex) async {
    await load();
    final t = _findTask(taskKey);
    final ep = _findEpisode(taskKey, epIndex);
    if (t == null || ep == null) return;
    final k = _epKey(taskKey, epIndex);
    if (_runningEpisodes.contains(k)) return; // 正在下，别重复起
    // ★ ☁️ 只登记集（wanted=false）没有源：管理器这边取不了源 ⇒ 不启动。
    //   否则必然失败，会把整部剧从"已完成"拖回"未完成"（要下它请在详情页「下载」里勾选）
    if (ep.sourceUrl.isEmpty) {
      _log('跳过重试（这一集没有源）${_tagTask(t)} 集=$epIndex');
      return;
    }
    _stoppedTasks.remove(taskKey);
    // ★ 用户点"继续/重试"就是明确要下载这一集 ⇒ 把 wanted 补上
    //   （任务现在存全集，☁️ 只登记集也是 queued；不补的话 pump 会一直跳过它）
    ep.wanted = true;
    ep.status = EpStatus.queued;
    ep.error = '';
    ep.doneBytes = 0;
    ep.localPath = '';
    // totalBytes 留着：进度条不会突然从"有总长"变成"未知"
    _log('重试 ${_tagTask(t)} 集=$epIndex');
    notifyListeners();
    _scheduleSave();
    _pump();
  }

  /// 删整部剧：停下载 → 删目录（成品 + .part 一起）→ 删记录 → 落盘
  Future<void> removeTask(String taskKey) async {
    final t = _findTask(taskKey);
    _stoppedTasks.add(taskKey);
    if (t != null) {
      for (final ep in t.episodes) {
        final k = _epKey(taskKey, ep.index);
        _speeds.remove(k);
        if (_runningEpisodes.contains(k)) _cancelEpisodes.add(k);
      }
    }
    await _waitTaskStopped(taskKey);
    final root = _dir?.path ?? '';
    if (t != null && root.isNotEmpty) {
      try {
        final dir = Directory('$root/${_taskDirName(taskKey)}');
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (e) {
        _log('删目录失败 ${_tagTask(t)} 原因=$e');
      }
    }
    if (t != null) {
      _tasks.remove(t);
      _log('移除任务 ${_tagTask(t)}');
      notifyListeners();
      _scheduleSave();
    }
    _pump();
  }

  /// 删一集：停（如果在下）→ 删文件 → 回到"暂停"（**不自动重下**，等用户点重试）
  Future<void> removeEpisode(String taskKey, int epIndex) async {
    await load();
    final t = _findTask(taskKey);
    final ep = _findEpisode(taskKey, epIndex);
    if (t == null || ep == null) return;

    final k = _epKey(taskKey, epIndex);
    _speeds.remove(k);
    if (_runningEpisodes.contains(k)) {
      _cancelEpisodes.add(k);
      ep.status = EpStatus.paused;
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (_runningEpisodes.contains(k) && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    if (ep.localPath.isNotEmpty) {
      try {
        final f = File(ep.localPath);
        if (await f.exists()) await f.delete();
      } catch (e) {
        _log('删集文件失败 ${_tagTask(t)} 集=$epIndex 原因=$e');
      }
    }
    final root = _dir?.path ?? '';
    if (root.isNotEmpty) {
      final base = _epBaseName(epIndex);
      for (final suffix in const ['.mp4', '.ts', '.mp4.part', '.ts.part']) {
        try {
          final f = File('$root/${_taskDirName(taskKey)}/$base$suffix');
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }

    ep.localPath = '';
    ep.status = EpStatus.paused; // 删了就是"没下"，但别让 pump 立刻又拖回来
    ep.error = '';
    ep.doneBytes = 0;
    ep.totalBytes = 0;
    _log('移除集 ${_tagTask(t)} 集=$epIndex');
    notifyListeners();
    _scheduleSave();
  }

  /// **清空所有下载**（下载页「清空」按钮）：停止正在下的 → 删所有任务目录/文件 →
  /// 清空任务记录/速度表 → 落盘 → `notifyListeners`。
  ///
  /// 为什么先 [cancelTask] 再 [removeTask]：`removeTask` 虽然会等 `_waitTaskStopped`（≤5s），
  /// 但引擎可能正卡在一个分片请求上；先把取消旗标打上，让它在下一个分片/分块检查点退出，
  /// 删目录时就不会跟"正在写的文件"打架（Windows 上尤其明显）。
  ///
  /// 幂等：重复调用只是再落一次盘。**单个任务删失败不影响其余**（只记日志，继续下一个）。
  Future<void> clearAll() async {
    await load(); // 没加载过也能清（否则会把"还没读出来的任务"当成不存在）
    final snapshot = List<DownloadTask>.of(_tasks);

    // ① 先停：只打取消旗标，真正退出由引擎在检查点完成
    for (final t in snapshot) {
      try {
        await cancelTask(t.key);
      } catch (e) {
        _log('清空：暂停失败 ${_tagTask(t)} 原因=$e');
      }
    }

    // ② 再删：removeTask 内部会等集停下 + 删整个任务目录（含 .part / 封面）
    for (final t in snapshot) {
      try {
        await removeTask(t.key);
      } catch (e) {
        _log('清空：删任务失败 ${_tagTask(t)} 原因=$e');
      }
    }

    // ③ 兜底清空记录/速度（上面删失败的条目也一并清掉，界面不能残留"删不掉的条目"）
    _tasks.clear();
    _speeds.clear();

    // 还在跑的"任务循环"要保留它的暂停闸：现在就把 `_stoppedTasks` 全清的话，
    // `_runTask` 会接着去下它后面排队的集 ⇒ 刚清空的目录又会被写回来。
    // 等一会儿（≤2s），只给仍在跑的 key 保留闸门。
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (_activeTasks.isNotEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _stoppedTasks.removeWhere((k) => !_activeTasks.contains(k));

    // ④ 删目录兜底：removeTask 已经删过；万一因为文件占用/封面回写又冒出来，
    //    按**本次快照**再删一遍（只删快照里的任务目录，不碰下载根目录下的其它东西）
    final root = _dir?.path ?? '';
    if (root.isNotEmpty) {
      for (final t in snapshot) {
        try {
          final d = Directory('$root/${_taskDirName(t.key)}');
          if (await d.exists()) await d.delete(recursive: true);
        } catch (_) {}
      }
    }
    _log('清空完成 删除任务=${snapshot.length}');

    // ⑤ 立刻落盘：清空是用户明确动作，不能等防抖（马上被杀会留下旧记录）
    _saveTimer?.cancel();
    await _saveNow();
    notifyListeners();
  }

  /// 立即落盘（App 退到后台 / 页面销毁时想强制写一次就调它；平时交给防抖）
  Future<void> flush() async {
    _saveTimer?.cancel();
    await _saveNow();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // 调度
  // -------------------------------------------------------------------------

  /// 起任务：最多 2 部同时跑；每部内部逐集；每集内部并发交给引擎
  void _pump() {
    if (_pumping) return;
    _pumping = true;
    Future<void>(() async {
      try {
        while (true) {
          if (_activeTasks.length >= maxActiveTasks) break;
          final t = _nextRunnable();
          if (t == null) break;
          _activeTasks.add(t.key);
          unawaited(_runTask(t));
        }
      } finally {
        _pumping = false;
      }
    });
  }

  DownloadTask? _nextRunnable() {
    for (final t in tasks) {
      if (_stoppedTasks.contains(t.key)) continue;
      if (_activeTasks.contains(t.key)) continue;
      for (final ep in t.episodes) {
        // ★ 只调度 wanted 的集：want=false 的"只登记、不下"集永远是 queued，不能让它把整剧拖进队列
        if (ep.wanted && ep.status == EpStatus.queued) return t;
      }
    }
    return null;
  }

  Future<void> _runTask(DownloadTask t) async {
    try {
      while (!_stoppedTasks.contains(t.key)) {
        DownloadEpisode? next;
        for (final ep in t.episodes) {
          // ★ 同上：wanted=false 的集一律跳过（离线页用 ☁️ 在线播，不占下载资源）
          if (ep.wanted && ep.status == EpStatus.queued) {
            next = ep;
            break;
          }
        }
        if (next == null) break;
        await _runEpisode(t, next);
        if (next.status == EpStatus.failed) {
          // 失败即停本剧（见文件头：别把剩下几十集全刷成 failed）
          _log('失败即停 ${_tagTask(t)} 集=${next.index}');
          break;
        }
      }
    } finally {
      _activeTasks.remove(t.key);
      _scheduleSave();
      _pump();
    }
  }

  Future<void> _runEpisode(DownloadTask t, DownloadEpisode ep) async {
    final epKey = _epKey(t.key, ep.index);
    _runningEpisodes.add(epKey);
    _speeds.remove(epKey); // 清掉上一轮残留 ⇒ 本次首个样本必然"直接 = 瞬时值"
    ep.status = EpStatus.downloading;
    ep.error = '';
    ep.doneBytes = 0;
    notifyListeners();
    _scheduleSave();

    final startedAt = DateTime.now();
    var lastNotifyMs = -1000;
    var lastBytes = 0; // 上一回调的字节（算瞬时速度）
    var lastSpeedMs = startedAt.millisecondsSinceEpoch;
    try {
      final dir = await _episodeDir(t);
      if (dir == null) throw const DownloadException('下载目录不可用');
      _log('开下 ${_tagTask(t)} 集=${ep.index} 源host=${_hostOf(ep.sourceUrl)}');
      final path = await DownloadEngine.download(
        url: ep.sourceUrl,
        headers: _headersFor(ep),
        destDir: dir,
        baseName: _epBaseName(ep.index),
        onProgress: (done, total) {
          ep.doneBytes = done;
          // 只增不减：HLS 的 total 是"首片 × 总片数"的估算值，换片重算可能变小
          // ⇒ 界面"总大小"回跳（实测 168.3 → 165.2MB）。完成时会用真实字节校正（见下）。
          if (total > ep.totalBytes) ep.totalBytes = total;

          // 速度：**最小采样窗口 _speedWindow（300ms）** —— 分片并发时相邻进度回调
          //   可能只隔几毫秒、一次却跳几 MB ⇒ 瞬时值爆表（实测 536 / 1111 MB/s ☠）。
          //   窗口不够就攒着（lastBytes/lastSpeedMs 不动），够了一次算平均速度；
          //   再 clamp 到 _maxSpeedBps 兜底；EMA(0.7/0.3) 继续平滑。
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final dtMs = nowMs - lastSpeedMs;
          if (dtMs >= _speedWindow.inMilliseconds && done >= lastBytes) {
            final inst = ((done - lastBytes) * 1000.0 / dtMs)
                .clamp(0.0, _maxSpeedBps);
            final prev = _speeds[epKey];
            _speeds[epKey] = prev == null ? inst : prev * 0.7 + inst * 0.3;
            lastBytes = done;
            lastSpeedMs = nowMs;
          }

          final ms = nowMs - startedAt.millisecondsSinceEpoch;
          if (ms - lastNotifyMs >= _notifyInterval.inMilliseconds) {
            lastNotifyMs = ms;
            notifyListeners();
          }
        },
        isCancelled: () => _cancelEpisodes.contains(epKey),
      );
      ep.localPath = path;
      ep.status = EpStatus.done;
      ep.error = '';
      // 完成后用**真实**字节校正 total：首片外推可能偏大，若只增不减会让进度永远差一点到 1
      if (ep.doneBytes > 0) ep.totalBytes = ep.doneBytes;
      _log('完成 ${_tagTask(t)} 集=${ep.index} 字节=${ep.doneBytes}');
    } on DownloadCancelled {
      ep.status = EpStatus.paused;
      _log('暂停 ${_tagTask(t)} 集=${ep.index} 已下=${ep.doneBytes}');
    } catch (e) {
      ep.status = EpStatus.failed;
      ep.error = '$e';
      _log('失败 ${_tagTask(t)} 集=${ep.index} 原因=$e');
    } finally {
      _runningEpisodes.remove(epKey);
      _cancelEpisodes.remove(epKey);
      _speeds.remove(epKey); // 完成/暂停/失败/取消 ⇒ 速度归零
      notifyListeners();
      _scheduleSave();
    }
  }

  /// 等某部剧"正在下的集"退出（引擎每块/每片都会查取消旗标，正常 <1s）
  Future<void> _waitTaskStopped(String taskKey) async {
    final prefix = '$taskKey|';
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      var running = false;
      for (final k in _runningEpisodes) {
        if (k.startsWith(prefix)) {
          running = true;
          break;
        }
      }
      if (!running) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _log('等待任务停止超时（继续删目录）');
  }

  // -------------------------------------------------------------------------
  // 目录 / 请求头 / 落盘
  // -------------------------------------------------------------------------

  Future<Directory?> _ensureDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/downloads');
      if (!await dir.exists()) await dir.create(recursive: true);
      _dir = dir;
      _dirPath = dir.path;
      return dir;
    } catch (e) {
      _log('下载目录不可用：$e');
      return null;
    }
  }

  Future<String?> _episodeDir(DownloadTask t) async {
    final root = await _ensureDir();
    if (root == null) return null;
    final dir = Directory('${root.path}/${_taskDirName(t.key)}');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  /// 请求头：UA 兜底 + 站点快照 + Referer 兜底（播放页的站点根）。
  /// ⚠️ 站点快照里的同名键优先（站点最清楚自己要什么）。
  Map<String, String> _headersFor(DownloadEpisode ep) {
    final h = <String, String>{'User-Agent': Site.ua};
    final snap = ep.headers;
    if (snap != null) h.addAll(snap);
    if (!h.keys.any((k) => k.toLowerCase() == 'referer')) {
      final u = Uri.tryParse(ep.playUrl);
      if (u != null && u.host.isNotEmpty) {
        h['Referer'] = '${u.scheme}://${u.host}/';
      }
    }
    return h;
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDebounce, () {
      unawaited(_saveNow());
    });
  }

  Future<void> _saveNow() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = jsonEncode(<Map<String, dynamic>>[
        for (final t in _tasks) t.toJson(),
      ]);
      await sp.setString(storageKey, raw);
    } catch (e) {
      _log('保存失败：$e');
    }
  }

  // -------------------------------------------------------------------------
  // 小工具
  // -------------------------------------------------------------------------

  void _sortTasks() {
    _tasks.sort((a, b) {
      final byTime = b.createdAt.compareTo(a.createdAt);
      return byTime != 0 ? byTime : a.key.compareTo(b.key);
    });
  }

  void _normalizeNewEpisodes(DownloadTask t) {
    for (final ep in t.episodes) {
      // "状态说 done 但没路径" 的自相矛盾数据 ⇒ 待下
      if (ep.status == EpStatus.done && ep.localPath.isEmpty) {
        ep.status = EpStatus.queued;
      }
    }
    t.episodes.sort((a, b) => a.index.compareTo(b.index));
  }

  int _indexOf(String key) {
    for (var i = 0; i < _tasks.length; i++) {
      if (_tasks[i].key == key) return i;
    }
    return -1;
  }

  DownloadTask? _findTask(String key) {
    final i = _indexOf(key);
    return i < 0 ? null : _tasks[i];
  }

  DownloadEpisode? _findEpisode(String taskKey, int epIndex) {
    final t = _findTask(taskKey);
    if (t == null) return null;
    for (final ep in t.episodes) {
      if (ep.index == epIndex) return ep;
    }
    return null;
  }

  static int _indexOfEp(DownloadTask t, int epIndex) {
    for (var i = 0; i < t.episodes.length; i++) {
      if (t.episodes[i].index == epIndex) return i;
    }
    return -1;
  }

  static bool _fileExists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  static String _epKey(String taskKey, int epIndex) => '$taskKey|$epIndex';

  static String _epBaseName(int index) => 'ep_${index.toString().padLeft(4, '0')}';

  /// 封面扩展名：按**字节魔数**判（存的是解密后的明文；URL/Content-Type 是密文那层的，不可信）
  static String _coverExtByMagic(List<int> b) {
    if (b.length >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return 'png';
    }
    if (b.length >= 4 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38) {
      return 'gif'; // GIF8
    }
    if (b.length >= 12 &&
        b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return 'webp'; // RIFF....WEBP
    }
    return 'jpg'; // JPEG（FFD8）与"认不出来"都按 jpg 存
  }

  /// 是不是可显示的图片魔数（与 `FetchedImage._looksLikeImage` 同口径）
  static bool _isCoverMagic(List<int> b) {
    if (b.length < 12) return false;
    if (b[0] == 0xFF && b[1] == 0xD8) return true; // JPEG
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return true; // PNG
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38) return true; // GIF8
    if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return true; // RIFF....WEBP
    }
    return false;
  }

  /// 本地封面是否有效：只读头 12 字节判魔数（不把整张图读进内存）
  static Future<bool> _coverFileOk(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return false;
      final raf = await f.open();
      try {
        final head = await raf.read(12);
        return _isCoverMagic(head);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// 任务 key（`site|detailUrl`，含 `|:/?`）不能直接当目录名 ⇒ 用 FNV-1a 压成 8 位
  /// （与 `video_cache._keyOf` 同款做法：不依赖 `String.hashCode` 的进程内实现）
  static String _taskDirName(String key) {
    var h = 0x811c9dc5;
    for (final c in utf8.encode(key)) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return 't_${h.toRadixString(16).padLeft(8, '0')}';
  }

  static String _hostOf(String url) => Uri.tryParse(url)?.host ?? '';

  /// 日志只到 [AppSettings.i.logConsole] 开关后面；**不打完整 URL / cookie**
  /// （完整签名 URL 里有票据，host 足够定位问题）
  void _log(String msg) {
    if (!AppSettings.i.logConsole) return;
    debugPrint('[DL] ${_safeText(msg)}');
  }

  /// 日志脱敏：异常文本里可能带完整 URL（http 包的 `ClientException` 会带上 uri）
  /// ⇒ 打印前一律抹成 `<url>`。UI 展示用的 `ep.error` 不经过这里。
  static String _safeText(String s) => s.replaceAll(RegExp(r'https?://\S+'), '<url>');

  static String _tagTask(DownloadTask t) =>
      '剧=${t.title} 站=${t.site} host=${_hostOf(t.detailUrl)}';
}
