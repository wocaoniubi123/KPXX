// 离线下载 —— 数据模型（纯 Dart：这里**不** import Flutter / 网络 / 文件）。
//
// 为什么单独一个文件：
// · 管理器 `DownloadManager` 要继承 `ChangeNotifier`（依赖 Flutter），模型层不需要；
// · 模型只有"字段 + 容错 JSON"，拆出来后纯 Dart 脚本（自测、导出工具）也能直接
//   import，不用拉起 Flutter 引擎。
//
// JSON 键一律用**短键**（i / l / u …）：任务多、集数多时，落盘的那一整串 JSON
// 会小一大截（一部 100 集的剧，长键名白占几 KB；而且进度一变就要整串重写）。
//
// 容错口径（整个文件统一）：**缺字段给默认值、类型不对就跳过，绝不抛异常** ——
// 这是用户数据（下载记录），一条坏记录不能让 App 起不来，也不能让其余任务丢掉。

/// 单集状态机。
///
/// `downloading` 只应该出现在**内存**里：`DownloadManager.load()` 会把盘上的
/// `downloading` 一律降级成 `paused` —— App 被杀时没有任何地方能收到"失败"回调，
/// 留着 `downloading` 只会让界面永远转圈。
///
/// `missing` = 记录说下完了、但**文件找不到**（覆盖安装后容器路径变了 / 被清理）。
/// 关键口径：**不许静默清零** —— 保留 doneBytes/totalBytes/label，等用户点"重下"；
/// 调度只挑 `queued`，所以 missing 不会被自动启动。
enum EpStatus { queued, downloading, paused, failed, done, missing }

/// 一集（篇内的一个视频）。
///
/// [index] 用**篇内 0-based** —— 与详情页 `ArticleVideo.ordinal`（1 起）差 1，
/// 与播放记录里的 `epIndex` 同口径；写成 0-based 是为了直接当数组下标用。
class DownloadEpisode {
  final int index;

  /// 选集名（详情页卡片上显示的那个）
  final String label;

  /// 该集播放页 URL：重试/查看详情时用（不是视频源）
  final String playUrl;

  /// 合集类按需取源的入口（详情页里那片"子文章"的地址）；普通条目为 null
  final String? lazyUrl;

  /// 站点要求的额外请求头快照（Cookie / Referer 之类）。
  /// 值常带时效 ⇒ 每次 `enqueueTask` 拿新快照覆盖旧的（见 `DownloadManager`）
  Map<String, String>? headers;

  /// 已经拿到的**真实视频源**（m3u8 或 mp4 直链）；空串 = 还没取
  String sourceUrl;

  /// ★ 用户拍板：任务要存**全部集**（离线页要列全集：已下载 ✅ 本地播 / 未下载 ☁️ 在线播），
  ///   用这个标记"这一集要不要下载"。
  /// · `false` = 只登记、不下（`sourceUrl` 也留空，管理器调度/状态一律跳过它）
  /// · 默认 `true`：老版本落盘的记录没有这个键 ⇒ 全部当"要下载"（行为与之前一致 ✅）
  bool wanted;

  /// 下载完成后的本地文件路径（'' = 没下完）
  String localPath;

  int doneBytes;
  int totalBytes; // 未知时是 0（直链没给 Content-Length 的情况）
  EpStatus status;

  /// 失败原因（人话 + HTTP 状态码之类）；成功后清空
  String error;

  DownloadEpisode({
    required this.index,
    required this.label,
    this.playUrl = '',
    this.lazyUrl,
    this.headers,
    this.sourceUrl = '',
    this.localPath = '',
    this.wanted = true,
    this.doneBytes = 0,
    this.totalBytes = 0,
    this.status = EpStatus.queued,
    this.error = '',
  });

  bool get isDone => status == EpStatus.done;

  /// 0~1；总字节未知时退回"按集数"由 [DownloadTask.progress] 兜底
  double get progress {
    if (totalBytes <= 0) return isDone ? 1 : 0;
    final v = doneBytes / totalBytes;
    return v < 0 ? 0 : (v > 1 ? 1 : v);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'i': index,
        'l': label,
        'p': playUrl,
        if (lazyUrl != null) 'y': lazyUrl,
        if (headers != null && headers!.isNotEmpty) 'h': headers,
        'u': sourceUrl,
        'f': localPath,
        'w': wanted ? 1 : 0,
        'd': doneBytes,
        't': totalBytes,
        's': status.name,
        'e': error,
      };

  /// 容错解析：缺字段 / 类型不对 ⇒ 用默认值。
  /// [fallbackIndex] 给"旧数据没写 i"时兜底（调用方传列表下标）。
  static DownloadEpisode fromJson(Map<String, dynamic> j, {int fallbackIndex = 0}) {
    final i = _asInt(j['i'], fallbackIndex);
    final idx = i < 0 ? fallbackIndex : i;
    return DownloadEpisode(
      index: idx,
      label: _asString(j['l'], '第 ${idx + 1} 集'),
      playUrl: _asString(j['p'], ''),
      lazyUrl: _asNullableString(j['y']),
      headers: _asHeaders(j['h']),
      sourceUrl: _asString(j['u'], ''),
      localPath: _asString(j['f'], ''),
      // 缺失/坏值 ⇒ true（老数据全部当"要下载"，行为不变 ✅）
      wanted: _asBool(j['w'], true),
      doneBytes: _asInt(j['d'], 0),
      totalBytes: _asInt(j['t'], 0),
      status: _asStatus(j['s']),
      error: _asString(j['e'], ''),
    );
  }
}

/// 一部剧的下载任务。
///
/// [key] = `'$site|$detailUrl'`：同一部剧在详情页点多少次都只产生一个任务
/// （`enqueueTask` 按它合并）。
class DownloadTask {
  final String key;
  final String site;
  final String detailUrl;
  final String title;
  final String coverUrl;
  final String intro;
  final String time;
  final String duration;

  /// 站点自定义元信息（详情页元信息行末尾那一段，如野果「连载中 · 播放 38W」；
  /// 空串 = 不显示）。**下载时快照**，离线页照详情页布局原样显示。
  String metaLine;

  /// 本地封面路径（'' = 没存）
  String coverLocal;

  /// 毫秒时间戳（用于列表按"新 → 旧"排）
  final int createdAt;

  /// 集列表：按 [DownloadEpisode.index] 升序（构造/解析时都排一次）
  final List<DownloadEpisode> episodes;

  DownloadTask({
    required this.key,
    required this.site,
    required this.detailUrl,
    required this.title,
    this.coverUrl = '',
    this.intro = '',
    this.time = '',
    this.duration = '',
    this.metaLine = '',
    this.coverLocal = '',
    int? createdAt,
    required List<DownloadEpisode> episodes,
  })  : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        episodes = List<DownloadEpisode>.of(episodes);

  /// 全部**要下载的**集都完成了 ✅（`wanted=false` 的"只登记、不下"集不参与 ——
  /// 否则任务里只要有一集☁️在线集，离线页就永远显示"没下完"）。
  /// `missing`（文件丢了）也算**没完成** —— 不能因为状态不是 done 就漏判。
  bool get isAllDone {
    if (episodes.isEmpty) return false;
    for (final e in episodes) {
      if (e.wanted && e.status != EpStatus.done) return false;
    }
    return true;
  }

  int get doneCount {
    var n = 0;
    for (final e in episodes) {
      if (e.status == EpStatus.done) n++;
    }
    return n;
  }

  int get totalBytes {
    var n = 0;
    for (final e in episodes) {
      n += e.totalBytes;
    }
    return n;
  }

  /// 已落盘的字节：`missing`（文件丢了）**不算已下**，否则界面会显示一个磁盘上不存在的体积
  int get doneBytes {
    var n = 0;
    for (final e in episodes) {
      if (e.status == EpStatus.missing) continue;
      n += e.doneBytes;
    }
    return n;
  }

  /// 0~1：有字节口径就按字节，没有（全部未知）就按"已完成集数"。
  /// ⚠️ 有 `missing`（文件丢了）时**退回按集数**（missing 记 0）：
  ///   文件已经不在磁盘上，不能用它保留的 doneBytes 把进度条堆到接近 100%。
  double get progress {
    if (episodes.isEmpty) return 0;
    for (final e in episodes) {
      if (e.status == EpStatus.missing) return doneCount / episodes.length;
    }
    final t = totalBytes;
    if (t <= 0) return doneCount / episodes.length;
    final v = doneBytes / t;
    return v < 0 ? 0 : (v > 1 ? 1 : v);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'k': key,
        'st': site,
        'u': detailUrl,
        'ti': title,
        'co': coverUrl,
        'cl': coverLocal,
        'in': intro,
        'tm': time,
        'dr': duration,
        'ml': metaLine,
        'cr': createdAt,
        'ep': [for (final e in episodes) e.toJson()],
      };

  /// 容错解析；没有 key 的任务无法定位/去重 ⇒ 返回 null（调用方跳过这一条）
  static DownloadTask? fromJson(Map<String, dynamic> j) {
    final key = _asString(j['k'], '');
    if (key.isEmpty) return null;
    final eps = <DownloadEpisode>[];
    final raw = j['ep'];
    if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        final e = raw[i];
        if (e is! Map) continue;
        eps.add(DownloadEpisode.fromJson(
          Map<String, dynamic>.from(e),
          fallbackIndex: i,
        ));
      }
    }
    eps.sort((a, b) => a.index.compareTo(b.index));
    return DownloadTask(
      key: key,
      site: _asString(j['st'], ''),
      detailUrl: _asString(j['u'], ''),
      title: _asString(j['ti'], ''),
      coverUrl: _asString(j['co'], ''),
      coverLocal: _asString(j['cl'], ''),
      intro: _asString(j['in'], ''),
      time: _asString(j['tm'], ''),
      duration: _asString(j['dr'], ''),
      metaLine: _asString(j['ml'], ''),
      createdAt: _asInt(j['cr'], 0),
      episodes: eps,
    );
  }
}

// ---------------------------------------------------------------------------
// 下面都是"容错解析"的小工具：任何异常输入都退化成默认值，不抛
// ---------------------------------------------------------------------------

String _asString(dynamic v, String fallback) => v is String ? v : fallback;

String? _asNullableString(dynamic v) => v is String && v.isNotEmpty ? v : null;

int _asInt(dynamic v, int fallback) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final n = int.tryParse(v);
    if (n != null) return n;
  }
  return fallback;
}

/// 容错布尔：JSON 里可能写成 1/0（我们自己的落盘）、true/false、或字符串
bool _asBool(dynamic v, bool fallback) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase();
    if (s == '1' || s == 'true') return true;
    if (s == '0' || s == 'false') return false;
  }
  return fallback;
}

EpStatus _asStatus(dynamic v) {
  if (v is String) {
    for (final s in EpStatus.values) {
      if (s.name == v) return s;
    }
  }
  // 认不出来的状态 ⇒ 当"待下"（最安全：最多重下一遍，绝不会把没下完的标成完成）
  return EpStatus.queued;
}

Map<String, String>? _asHeaders(dynamic v) {
  if (v is! Map) return null;
  final out = <String, String>{};
  for (final e in v.entries) {
    final k = e.key;
    if (k is! String || k.isEmpty) continue;
    final val = e.value;
    if (val == null) continue;
    out[k] = val is String ? val : '$val';
  }
  return out.isEmpty ? null : out;
}
