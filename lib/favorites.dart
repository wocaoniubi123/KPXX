import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'play_record_tile.dart'; // 只为自检钉住**共用**的显示规则（`siteLine`，纯字符串函数 ✅）

/// 一条收藏（用户 2026-10-10 拍板 ✅：**与播放记录两份独立存储**，互不牵连 ☠）。
///
/// ⚠️ 字段口径**逐条对齐** `PlayRecord`（`settings.dart:158-200` ✅）：
///   `site` / `url` / `title` / `cover` / `videoIndex` / `total` / `position` / `duration` 同一套
///   （集号同样是 **0-based 篇内列表下标** ✅ ⇒ 显示时才 +1，见 `play_record_tile.dart` 的 `siteLine` ✅；
///    进度也是**秒精度**存 ✅ —— 用户口径："口径与 PlayRecord 完全一致" ✅）。
///   多出来的只有**两个时间戳**：`lastViewAt`（最近观看 —— 列表排序用它 ✅）/
///   `favAt`（收藏那一刻 —— `lastViewAt` 并列时兜底 ✅）。
/// ⚠️ 这里**没有** `finished` / `quality` ☑️：收藏行不计"已看完"（进度条恒橙、满格也不变绿），
///   也不记清晰度 —— 那些仍归播放记录 ☠（要的话得再拍板加字段）。
class FavoriteItem {
  /// 站点名（从 kSites 里反查 SiteEntry 用，站点入口进去时必须就是原站点）
  final String site;
  final String url; // 详情页相对路径，如 /archives/273630/
  final String title;
  final String cover; // 原始 URL，显示时走 FetchedImage（该解密的自动解密）
  final int videoIndex; // 篇内第几个视频（0-based；0 = 拿不到 ⇒ 行内不显示集号）

  /// ★ 2026-10-10（用户要求 ✅）：**本篇共几个视频**（与 `PlayRecord.total` 同口径 ✅）——
  ///   用来区分"电影 / 单集（只有 1 个视频）"与"多集文章的**第 1 集**"
  ///   （这两者 `videoIndex` 都是 0 ☠，只有这个字段能分开 ✅）。
  ///   ⚠️ **`0` = 不知道**（老收藏没有 `'n'` 这个键 ✅）
  ///      ⇒ 显示时按"没这回事"处理 ☑️ ⇒ **老收藏的行为与加字段之前完全一致** ✅。
  final int total;

  /// ★ 2026-10-10（用户要求 ✅）：进度存**收藏自己身上** ——
  ///   验收口径："删掉播放记录后，收藏里的进度依然显示" ✅（不跨读 `PlayHistory` ☠）。
  final Duration position; // 已看到哪
  final Duration duration; // 总时长（0 = 还没拿到）
  final int lastViewAt; // 最近一次观看（毫秒时间戳）—— 列表按它降序
  final int favAt; // 收藏那一刻（毫秒时间戳）—— lastViewAt 并列时用它兜底

  const FavoriteItem({
    required this.site,
    required this.url,
    required this.title,
    required this.cover,
    required this.videoIndex,
    required this.total,
    required this.position,
    required this.duration,
    required this.lastViewAt,
    required this.favAt,
  });

  /// 唯一键：同一站点同一篇 = 同一条（与 `PlayRecord.key` 同一形状 ✅）
  String get key => '$site|$url';

  /// 观看进度 0~1（**口径与 `PlayRecord.progress` 一致** ✅：时长没拿到时按 0、越界夹到 0~1）。
  /// ⚠️ 少一条 `finished ⇒ 1`（本模型没有 finished ☑️）—— 播到头 position 自然等于 duration ⇒ 结果也是 1 ✅。
  double get progress {
    final d = duration.inMilliseconds;
    if (d <= 0) return 0;
    return (position.inMilliseconds / d).clamp(0.0, 1.0).toDouble();
  }

  /// 有没有进度可显示（**没数据就不画进度条、不显示"已看 …"** ✅ 显示规范：缺则隐藏）——
  /// 老收藏（加字段之前存的）没有 `'p'/'d'` ⇒ 恒 false ⇒ 行的样子与加字段前**完全一致** ✅。
  bool get hasProgress => duration > Duration.zero;

  /// `touch` 用：**只改被传进来的那几个字段**，其它一个字不动 ✅
  /// （传 null = 这一项**不更新** ☠ —— 不代表"更新成空"）
  FavoriteItem copyWith({
    int? videoIndex,
    int? total,
    Duration? position,
    Duration? duration,
    int? lastViewAt,
  }) =>
      FavoriteItem(
        site: site,
        url: url,
        title: title,
        cover: cover,
        videoIndex: videoIndex ?? this.videoIndex,
        total: total ?? this.total,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        lastViewAt: lastViewAt ?? this.lastViewAt,
        favAt: favAt,
      );

  Map<String, dynamic> toJson() => {
        's': site,
        'u': url,
        't': title,
        'c': cover,
        'i': videoIndex,
        'n': total, // ★ 2026-10-10：本篇共几个视频（0 = 不知道 ✅ 老版本读新 JSON 会**忽略**这个未知键 ✅）
        'p': position.inSeconds, // ★ 秒精度就够（与 PlayRecord 同口径 ✅ JSON 也小 ✅）
        'd': duration.inSeconds,
        'v': lastViewAt,
        'f': favAt,
      };

  /// 解析容错：字段缺失/类型不对就退化（宁可丢一条，不能让整页崩）。
  /// ⚠️ `asInt` 与 `PlayRecord.fromJson` 的 `sec()`（`settings.dart:236`）**同口径** ✅：
  ///   非 int 的"数字"按 `toInt()` 收下（`5.0 ⇒ 5` ✅）；非数字（字符串 / null / 键缺失）才退化 0 ✅。
  static FavoriteItem? fromJson(Map<String, dynamic> j) {
    final site = j['s'], url = j['u'];
    if (site is! String || url is! String || site.isEmpty || url.isEmpty) {
      return null;
    }
    int asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
    return FavoriteItem(
      site: site,
      url: url,
      title: j['t'] is String ? j['t'] as String : '',
      cover: j['c'] is String ? j['c'] as String : '',
      videoIndex: asInt(j['i']),
      total: asInt(j['n']), // ★ 缺键/非数字 ⇒ 0 = 不知道（老收藏走这条 ✅ 行为不变）
      position: Duration(seconds: asInt(j['p'])),
      duration: Duration(seconds: asInt(j['d'])),
      lastViewAt: asInt(j['v']),
      favAt: asInt(j['f']),
    );
  }
}

/// 收藏（持久化在 shared_preferences，一个 JSON 数组；键 `'fav_list'` ✅
/// **与播放记录的 `'play_history'` 分开** ☠ —— 用户口径：两份独立存储、互不牵连）。
///
/// ⚠️ **不设上限** ✅（用户 2026-10-10 口径；对照 `PlayHistory.maxRecords = 100` 那套淘汰**不存在** ☑️）。
/// 写入策略：收藏/取消/删除/清空**立刻落盘**；`touch`（播放中刷新进度 + "最近观看"）走
/// 与 `PlayHistory.touch` 同款**节流**（见下 ✅）。
class Favorites extends ChangeNotifier {
  Favorites._();
  static final Favorites i = Favorites._();

  static const String _kKey = 'fav_list';

  final Map<String, FavoriteItem> _m = {}; // key -> 收藏项（去重靠它）

  /// 列表页看这个：**最近观看降序**（并列用收藏时间 —— 判据只有 `_byRecency` 一份 ✅）
  List<FavoriteItem> get items => _m.values.toList()..sort(_byRecency);

  bool get isEmpty => _m.isEmpty;
  int get length => _m.length;

  /// 是否已收藏（详情页那颗星就是问它 ✅）
  bool contains(String site, String url) => _m.containsKey('$site|$url');

  /// 这条上次真正落盘时的 `lastViewAt`（`touch` 的节流判断，同 `PlayHistory._savedSec` 的做法 ✅）
  final Map<String, int> _savedMs = {};

  /// 排序口径（**只有这一份** ☠）：最近观看降序；并列（毫秒相同）用收藏时间降序。
  ///   ⚠️ `items` 与 `_selfCheck` **都用它** ✅ —— 各写一份的话自检测的就不是真身（等于没测 ☠）。
  static int _byRecency(FavoriteItem a, FavoriteItem b) {
    final c = b.lastViewAt.compareTo(a.lastViewAt);
    return c != 0 ? c : b.favAt.compareTo(a.favAt);
  }

  Future<void> load() async {
    // 纯逻辑自检（debug 构建生效）：JSON 往返 / 字段退化 / 排序 / 去重键 / copyWith / 显示规则边界
    assert(() {
      _selfCheck();
      return true;
    }());
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_kKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw);
      if (list is! List) return;
      _m.clear();
      for (final e in list) {
        if (e is! Map) continue;
        final it = FavoriteItem.fromJson(Map<String, dynamic>.from(e));
        if (it != null) _m[it.key] = it;
      }
      for (final it in _m.values) {
        _savedMs[it.key] = it.lastViewAt;
      }
      notifyListeners();
    } catch (_) {
      // 数据坏了就当空：不能因为一条坏收藏让 App 起不来
    }
  }

  /// 收藏 / 取消收藏（同一篇 = 同一条，靠 key 去重 ✅）。
  ///
  /// 口径（用户 2026-10-10 ✅）：
  ///   - **收藏时** `lastViewAt = favAt = now`（刚收藏 ⇒ 排在列表最前 ✅）
  ///   - `videoIndex` = 详情页**当前集号**（拿不到就传 0 ⇒ 行内不显示集号，与记录一致 ✅）
  ///   - ★ [total] / [position] / [duration]：详情页**手上就有**就一起带上（默认 0 = 不知道 ✅）——
  ///     否则"收藏了但还没播"的那一条，第 1 集的集号与进度要等下一次 `touch`（约 10 秒）才出现 ☑️。
  /// 返回值：true = 现在是"已收藏"（详情页据此弹提示 ✅）
  Future<bool> toggle({
    required String site,
    required String url,
    required String title,
    required String cover,
    required int videoIndex,
    int total = 0,
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
  }) async {
    final k = '$site|$url';
    final had = _m.containsKey(k);
    if (had) {
      _m.remove(k);
      _savedMs.remove(k);
    } else {
      final now = DateTime.now().millisecondsSinceEpoch;
      _m[k] = FavoriteItem(
        site: site,
        url: url,
        title: title,
        cover: cover,
        videoIndex: videoIndex,
        total: total,
        position: position,
        duration: duration,
        lastViewAt: now,
        favAt: now,
      );
      _savedMs[k] = now;
    }
    notifyListeners();
    await save();
    return !had;
  }

  /// **只更新已存在**的收藏：刷新 `lastViewAt` + `videoIndex` +（★ 2026-10-10）`total` / `position` / `duration`
  /// ⇒ ☠ **绝不新建、绝不删除**（用户口径：没收藏过就什么都不做 ✅）。
  ///
  /// ⚠️ 传 null = **该项不更新**（不是"清空" ☠）；详情页每次都会把三样都传齐 ✅。
  ///
  /// 节流（与 `PlayHistory.touch` 同款 ✅）：内存里**每次都更新**（列表排序/进度条立刻跟着变 ✅），
  /// 但只有与上次落盘差 ≥ [minDeltaSec] 秒（或 [force]）才真写盘 ⇒ 不跟着播放回调每 10 秒写一次盘 ☑️。
  Future<void> touch(String site, String url, int index,
      {int? total,
      Duration? position,
      Duration? duration,
      bool force = false,
      int minDeltaSec = 2}) async {
    final k = '$site|$url';
    final old = _m[k];
    if (old == null) return; // 没收藏过 ⇒ 什么都不做（不新建 ☠）
    final now = DateTime.now().millisecondsSinceEpoch;
    _m[k] = old.copyWith(
      videoIndex: index,
      total: total,
      position: position,
      duration: duration,
      lastViewAt: now,
    );
    notifyListeners();
    final saved = _savedMs[k];
    if (force || saved == null || (now - saved).abs() >= minDeltaSec * 1000) {
      _savedMs[k] = now;
      await save();
    }
  }

  Future<void> remove(String key) async {
    if (_m.remove(key) == null) return; // 本来就没有 ⇒ 不白写一次盘
    _savedMs.remove(key);
    notifyListeners();
    await save();
  }

  Future<void> clear() async {
    if (_m.isEmpty) return;
    _m.clear();
    _savedMs.clear();
    notifyListeners();
    await save();
  }

  /// 落盘（列表页/详情页那几处改完就调；`touch` 里按节流调）。
  Future<void> save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final arr = _m.values.map((it) => it.toJson()).toList();
      await sp.setString(_kKey, jsonEncode(arr));
    } catch (_) {
      // 存失败不影响本次会话（下次改动还会再试）
    }
  }

  /// 自检（debug 构建生效，release 自动剔除；`load()` 里跑一次）。
  /// ⚠️ 覆盖的是**纯逻辑**：JSON 往返、字段退化、排序、去重键、`copyWith` 边界、
  ///   以及**与播放记录行共用**的显示规则（`siteLine` ✅）。
  ///   真正写盘/读盘是异步的（SharedPreferences），由真机 + 下次启动验证，不在这里假装测了 ✅。
  static void _selfCheck() {
    FavoriteItem mk({
      required String u,
      int i = 0,
      int n = 3,
      int p = 0,
      int d = 0,
      int v = 1,
      int f = 1,
    }) =>
        FavoriteItem(
          site: '麻豆社',
          url: u,
          title: '标题 $u',
          cover: 'https://x/c.jpg',
          videoIndex: i,
          total: n,
          position: Duration(seconds: p),
          duration: Duration(seconds: d),
          lastViewAt: v,
          favAt: f,
        );

    // 1) JSON 往返：每个字段都要原样回来（含 ★ 2026-10-10 新增的 total/position/duration）
    final a = mk(u: '/a.html', i: 2, n: 12, p: 86, d: 181, v: 1700000000000, f: 1699999999999);
    final b = FavoriteItem.fromJson(jsonDecode(jsonEncode(a.toJson())));
    assert(b != null, '往返不能丢收藏');
    final r = b!;
    assert(r.site == a.site && r.url == a.url && r.title == a.title, '基本字段');
    assert(r.cover == a.cover && r.videoIndex == a.videoIndex, '封面/集号');
    assert(r.total == a.total, '总集数（本篇共几个视频）');
    assert(r.position == a.position && r.duration == a.duration, '进度（秒精度）');
    assert(r.lastViewAt == a.lastViewAt && r.favAt == a.favAt, '两个时间戳');
    assert(r.key == a.key, '去重键必须一致：${r.key}');

    // 2) 字段缺失/类型错 → 不能抛异常（宁可丢一条，不能让整页崩）
    assert(FavoriteItem.fromJson(const {}) == null, '没有 site/url 的应丢弃');
    assert(FavoriteItem.fromJson(const {'s': 'x'}) == null, '只有 site 的应丢弃');
    assert(FavoriteItem.fromJson(const {'s': '', 'u': '/x/'}) == null, 'site 空串也丢弃');
    final messy = FavoriteItem.fromJson(const {
      's': '站',
      'u': '/x/',
      't': 5, // 不是 String
      'c': null, // 不是 String
      'i': 'abc', // 非数字（字符串）⇒ 集号退化 0
      'n': 'abc', // ★ 非数字 ⇒ 总集数退化 0（= 不知道）
      'p': 'abc', // ★ 非数字 ⇒ 位置退化 0
      'd': null, // ★ 非数字（null）⇒ 时长退化 0
      'v': null, // 非数字（null）⇒ 最近观看退化 0
      'f': 'yes', // 非数字 ⇒ 收藏时间退化 0
    });
    assert(messy != null && messy.videoIndex == 0, '非数字（字符串）⇒ 集号退化 0');
    assert(messy!.total == 0, '非数字（字符串）⇒ 总集数退化 0');
    assert(messy!.position == Duration.zero && messy.duration == Duration.zero,
        '非数字 ⇒ 位置/时长退化 0');
    assert(!messy!.hasProgress, '没时长 ⇒ hasProgress = false（行内不画进度条、不显示"已看 …"）');
    assert(messy!.progress == 0, '没时长 ⇒ 进度算 0（除零不崩）');
    assert(messy!.lastViewAt == 0 && messy.favAt == 0, '时间戳缺失/非数字 ⇒ 0');
    assert(messy!.title.isEmpty && messy.cover.isEmpty, '类型不对的标题/封面 ⇒ 空串');
    assert(
        FavoriteItem.fromJson(const {'s': '站', 'u': '/x/', 'v': 5.0})!
                .lastViewAt ==
            5,
        '非 int 的"数字"按 toInt() 收下（5.0 ⇒ 5）—— 只有非数字才退化 0');

    // 2b) 老收藏（加字段之前的 JSON：只有 s/u/t/c/i/v/f）⇒ 三个新字段全 0，行为与以前一致
    final old = FavoriteItem.fromJson(
        const {'s': '站', 'u': '/x/', 'i': 4, 'v': 7, 'f': 6})!;
    assert(old.total == 0 && !old.hasProgress, '老收藏：total=0、没进度 ⇒ 不显示进度、集号照旧按 i 显示');
    assert(siteLine(old.site, old.videoIndex, old.total) == '站 · 第 5 集',
        '老收藏（total=0）已看到第 5 集 ⇒ 与加字段前一样显示集号');

    // 2c) 进度公式边界（与 PlayRecord.progress 同口径 ✅）
    assert(mk(u: '/p1.html', p: 0, d: 0).progress == 0, '没时长 ⇒ 0');
    assert((mk(u: '/p2.html', p: 86, d: 181).progress - 0.475).abs() < 0.01, '1:26 / 3:01 ⇒ ≈47%');
    assert(mk(u: '/p3.html', p: 999, d: 181).progress == 1, '越界夹到 1');

    // 3) 排序：最近观看降序；并列（同一毫秒）用收藏时间降序
    final list = <FavoriteItem>[
      mk(u: '/old.html', v: 3, f: 3),
      mk(u: '/new.html', v: 9, f: 1),
      mk(u: '/newer.html', v: 9, f: 8), // 与 /new.html 的 lastViewAt 并列 ⇒ 收藏时间晚的在前
    ]..sort(_byRecency);
    assert(
        list[0].url == '/newer.html' &&
            list[1].url == '/new.html' &&
            list[2].url == '/old.html',
        '按最近观看降序、并列用收藏时间');

    // 4) 去重键：同站同篇 = 同一条；换站不算同一条
    assert(mk(u: '/a.html').key == mk(u: '/a.html').key, '同站同篇 ⇒ 同一个 key');
    const other = FavoriteItem(
      site: '别的站',
      url: '/a.html',
      title: '',
      cover: '',
      videoIndex: 0,
      total: 0,
      position: Duration.zero,
      duration: Duration.zero,
      lastViewAt: 1,
      favAt: 1,
    );
    assert(other.key != mk(u: '/a.html').key, '不同站 ⇒ 不算同一条');

    // 5) copyWith：被传进来的才改，其它一个字不动（`touch` 就靠它 ☠）
    final c = mk(u: '/c.html', i: 1, n: 3, p: 10, d: 100, v: 10, f: 20).copyWith(
        videoIndex: 4, total: 24, position: const Duration(seconds: 55),
        duration: const Duration(seconds: 200), lastViewAt: 99);
    assert(
        c.videoIndex == 4 &&
            c.total == 24 &&
            c.position == const Duration(seconds: 55) &&
            c.duration == const Duration(seconds: 200) &&
            c.lastViewAt == 99 &&
            c.favAt == 20 &&
            c.site == '麻豆社' &&
            c.url == '/c.html',
        'copyWith 改该改的、别的字段原样');
    final keep = mk(u: '/d.html', i: 2, n: 9, p: 5, d: 60).copyWith(lastViewAt: 33);
    assert(keep.videoIndex == 2 && keep.total == 9 && keep.position.inSeconds == 5 &&
        keep.duration.inSeconds == 60, 'copyWith 没传的字段不许被清掉');

    // 6) 显示规则（`siteLine` —— **播放记录行与收藏行共用** ✅）：四种取值 + 两条脏数据防护
    assert(siteLine('站', 0, 0) == '站', '老数据（total=0）第 1 集 ⇒ 不显示集号（与加 total 之前完全一致）');
    assert(siteLine('站', 4, 0) == '站 · 第 5 集', '老数据（total=0）看到 i=4 ⇒ 照旧"第 5 集"（**不带**"共 M 集"）');
    assert(siteLine('站', 0, 1) == '站', '电影/单集（total=1，i=0）⇒ 后缀不显示');
    assert(siteLine('站', 4, 1) == '站', 'total=1 但索引是脏的（i=4）⇒ 照样不显示后缀');
    assert(siteLine('站', 0, 12) == '站 · 第 1 集 / 共 12 集',
        '★ 多集文章第 1 集（total>1）⇒ 要显示"... · 第 1 集 / 共 12 集"');
    assert(siteLine('站', 2, 12) == '站 · 第 3 集 / 共 12 集', '★ 用户给的样例：站 · 第 3 集 / 共 12 集');
    assert(siteLine('站', 14, 12) == '站 · 第 12 集 / 共 12 集',
        '★ N > M ⇒ clamp 到 M（不出现"第 15 集 / 共 12 集"）');
    assert(siteLine('站', -1, 12) == '站 · 第 1 集 / 共 12 集', '脏数据（负数）⇒ 当 0 ⇒ 第 1 集');
    assert(siteLine('站', -1, 0) == '站', '脏数据 + 老数据 ⇒ 什么都不显示');
  }
}
