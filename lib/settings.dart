import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置（双击快进秒数、播放缓冲大小）。
/// 单例 + ChangeNotifier：设置页改完，播放器下次用的时候就能取到新值。
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings i = AppSettings._();

  /// 双击快进/快退档位（默认 10 秒）
  static const List<int> stepOptions = [5, 10, 15];
  static const int defaultStep = 10;
  static const String _kStep = 'seek_step';

  /// 播放缓冲档位（MB，默认 200）
  static const List<int> bufferOptions = [100, 200, 300, 500, 1024];
  static const int defaultBufferMb = 200;
  static const String _kBuffer = 'buffer_mb';

  int _step = defaultStep;
  int get step => _step;

  int _bufferMb = defaultBufferMb;
  int get bufferMb => _bufferMb;

  /// 播完是否自动播下一篇里的下一个视频（默认关）
  static const String _kAutoNext = 'auto_next';
  bool _autoNext = false;
  bool get autoNext => _autoNext;

  /// 档位显示名：1024 显示成 1G
  static String bufferLabel(int mb) => mb >= 1024 ? '1G' : '${mb}MB';

  /// 启动时读一次；读不到就用默认值
  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      var changed = false;
      final v = sp.getInt(_kStep);
      if (v != null && stepOptions.contains(v) && v != _step) {
        _step = v;
        changed = true;
      }
      final b = sp.getInt(_kBuffer);
      if (b != null && bufferOptions.contains(b) && b != _bufferMb) {
        _bufferMb = b;
        changed = true;
      }
      final an = sp.getBool(_kAutoNext);
      if (an != null && an != _autoNext) {
        _autoNext = an;
        changed = true;
      }
      if (changed) notifyListeners();
    } catch (_) {
      // 读失败保持默认值
    }
  }

  Future<void> setStep(int v) async {
    if (!stepOptions.contains(v) || v == _step) return;
    _step = v;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_kStep, v);
    } catch (_) {
      // 存失败也不影响本次会话使用
    }
  }

  Future<void> setAutoNext(bool v) async {
    if (v == _autoNext) return;
    _autoNext = v;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kAutoNext, v);
    } catch (_) {
      // 存失败也不影响本次会话使用
    }
  }

  Future<void> setBufferMb(int v) async {
    if (!bufferOptions.contains(v) || v == _bufferMb) return;
    _bufferMb = v;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_kBuffer, v);
    } catch (_) {
      // 存失败也不影响本次会话使用
    }
  }
}

/// 一条播放记录（同一部片只留一条，重复看就覆盖进度——用户要求）。
class PlayRecord {
  /// 站点名（从 kSites 里反查 SiteEntry 用，站点入口进去时必须就是原站点）
  final String site;
  final String url; // 详情页相对路径，如 /archives/273630/
  final String title;
  final String cover; // 原始 URL，显示时走 FetchedImage（该解密的自动解密）
  final int videoIndex; // 篇内第几个视频（多视频文章用）
  final Duration position; // 已看到哪
  final Duration duration; // 总时长（0 = 还没拿到）

  /// 播到结尾（或手动拉到最后）：留记录但标已看完，再点是重头播（用户要求）
  final bool finished;
  final int updatedAt; // 毫秒时间戳，列表按它倒序

  /// 这条视频**上次选过的清晰度档**（如 '720'）✓；null = 跟随**站点默认** ✓
  /// （用户 2026-10-03 定的 A 方案：**跟着这条视频记** ✓，不串味到别的视频 ✓）
  final String? quality;

  const PlayRecord({
    required this.site,
    required this.url,
    required this.title,
    required this.cover,
    required this.videoIndex,
    required this.position,
    required this.duration,
    required this.finished,
    required this.updatedAt,
    this.quality, // 可空 ✓ —— 老记录没有这个字段 → null → 行为与以前完全一样 ✓
  });

  /// 唯一键：同一站点同一篇 = 同一条
  String get key => '$site|$url';

  /// 观看进度 0~1（时长没拿到时按 0）
  double get progress {
    if (finished) return 1;
    final d = duration.inMilliseconds;
    if (d <= 0) return 0;
    return (position.inMilliseconds / d).clamp(0.0, 1.0).toDouble();
  }

  Map<String, dynamic> toJson() => {
        's': site,
        'u': url,
        't': title,
        'c': cover,
        'i': videoIndex,
        'p': position.inSeconds, // 秒精度就够（JSON 也小）
        'd': duration.inSeconds,
        'f': finished,
        'ts': updatedAt,
        if (quality != null) 'q': quality, // 没选过就不写 ✓（JSON 更小 ✓ 老版本也能读 ✓）
      };

  /// 解析容错：字段缺失/类型不对就退化（宁可丢一条，不能让整页崩）
  static PlayRecord? fromJson(Map<String, dynamic> j) {
    final site = j['s'], url = j['u'];
    if (site is! String || url is! String || site.isEmpty || url.isEmpty) {
      return null;
    }
    int sec(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
    return PlayRecord(
      site: site,
      url: url,
      title: j['t'] is String ? j['t'] as String : '',
      cover: j['c'] is String ? j['c'] as String : '',
      videoIndex: sec(j['i']),
      position: Duration(seconds: sec(j['p'])),
      duration: Duration(seconds: sec(j['d'])),
      finished: j['f'] == true,
      updatedAt: sec(j['ts']),
      quality: (j['q'] is String && (j['q'] as String).isNotEmpty)
          ? j['q'] as String
          : null,
    );
  }
}

/// 播放记录（持久化在 shared_preferences，一个 JSON 数组）。
/// 写入策略（用户拍板）：进度每前进 ≥10 秒写一次 + 离开详情页时补写一次。
class PlayHistory extends ChangeNotifier {
  PlayHistory._();
  static final PlayHistory i = PlayHistory._();

  static const String _kKey = 'play_history';
  static const int maxRecords = 100; // 超出淘汰最旧的

  final Map<String, PlayRecord> _m = {}; // key -> 记录（不是列表：去重靠它）

  /// 列表页看这个：按最近观看倒序
  List<PlayRecord> get records =>
      _m.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  bool get isEmpty => _m.isEmpty;

  /// 这条记录上次真正落盘时的进度（用来判断"要不要写"）
  final Map<String, int> _savedSec = {};

  Future<void> load() async {
    // 纯逻辑自检（debug 构建生效）：JSON 往返 / 字段退化 / 进度 / 节流阈值
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
        final r = PlayRecord.fromJson(Map<String, dynamic>.from(e));
        if (r != null) _m[r.key] = r;
      }
      for (final r in _m.values) {
        _savedSec[r.key] = r.position.inSeconds;
      }
      notifyListeners();
    } catch (_) {
      // 数据坏了就当空：不能因为一条坏记录让 App 起不来
    }
  }

  PlayRecord? find(String site, String url) => _m['$site|$url'];

  /// 播放中不断调这里。
  ///
  /// 节流：进度比上次落盘变化 <[minDeltaSec] 秒就只更新内存 ✓（不落盘 ✗）。
  /// 进度回退（快退/从头看）同样会落盘（取绝对值判断 ✓），否则退出时会把新位置丢掉 ✓。
  ///
  /// ⚠️ 2026-10-03（用户要求两处改动 ✓）：
  /// ① 节流从 **10 秒收紧到 2 秒** ✓ —— 用户反馈"记录放得太宽、进度容易丢" ✓；
  /// ② 新增 [force] ✓ —— 用户**拖/点进度条**（位置跳变 ✓）时**绕过节流立刻落盘** ✓，
  ///    否则随后"自动重试重新加载"会从旧记录开始 ✗（用户实测过：跳完进度又从头播 ✗）。
  Future<void> touch(PlayRecord r, {bool force = false, int minDeltaSec = 2}) async {
    final old = _m[r.key];
    _m[r.key] = r;
    notifyListeners(); // 列表/进度条实时刷新
    final last = _savedSec[r.key];
    final p = r.position.inSeconds;
    if (force || last == null || (p - last).abs() >= minDeltaSec) {
      _savedSec[r.key] = p;
      await _save();
    }
  }

  /// 离开详情页时调：把最后的位置补写进去（不再重复判断节流）
  Future<void> flush() => _save();

  Future<void> remove(String key) async {
    _m.remove(key);
    _savedSec.remove(key);
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    _m.clear();
    _savedSec.clear();
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      // 超上限先淘汰最旧的（按 updatedAt）
      if (_m.length > maxRecords) {
        final sorted = _m.values.toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        for (final r in sorted.skip(maxRecords)) {
          _m.remove(r.key);
          _savedSec.remove(r.key);
        }
      }
      final sp = await SharedPreferences.getInstance();
      final arr = _m.values.map((r) => r.toJson()).toList();
      await sp.setString(_kKey, jsonEncode(arr));
    } catch (_) {
      // 存失败不影响本次会话（下次 touch 还会再试）
    }
  }

  /// 自检（debug 构建生效，release 自动剔除；`load()` 里跑一次）。
  /// ⚠️ 覆盖的是**纯逻辑**：JSON 往返、去重键、字段退化、进度计算、
  /// 落盘阈值那套算术。真正写盘/读盘是异步的（SharedPreferences），
  /// 由真机 + 下次启动验证，不在这里假装测了。
  static void _selfCheck() {
    PlayRecord mk({
      required String u,
      required int p,
      int d = 1200,
      bool f = false,
      int ts = 1,
    }) =>
        PlayRecord(
          site: '麻豆社',
          url: u,
          title: '标题 $u',
          cover: 'https://x/c.jpg',
          videoIndex: 2,
          position: Duration(seconds: p),
          duration: Duration(seconds: d),
          finished: f,
          updatedAt: ts,
        );

    // 1) JSON 往返：每个字段都要原样回来
    final a = mk(u: '/a.html', p: 123, f: true, ts: 1700000000000);
    final b = PlayRecord.fromJson(jsonDecode(jsonEncode(a.toJson())));
    assert(b != null, '往返不能丢记录');
    // 解包成非空变量再用：`b!` 之后 Dart 不会把 b 当非空，
    // CI 实测报过 "Property 'cover' cannot be accessed on 'PlayRecord?'"
    final r = b!;
    assert(r.site == a.site && r.url == a.url && r.title == a.title, '基本字段');
    assert(r.cover == a.cover && r.videoIndex == a.videoIndex, '封面/集号');
    assert(r.position == a.position, '位置（秒精度）');
    assert(r.duration == a.duration && r.finished && r.updatedAt == a.updatedAt,
        '时长/看完/时间戳');
    assert(r.key == a.key, '去重键必须一致：${r.key}');

    // 2) 字段缺失/类型错 → 不能抛异常（宁可丢一条，不能让整页崩）
    assert(PlayRecord.fromJson(const {}) == null, '没有 site/url 的应丢弃');
    assert(PlayRecord.fromJson(const {'s': 'x'}) == null, '只有 site 的应丢弃');
    final messy = PlayRecord.fromJson(const {
      's': '站',
      'u': '/x/',
      'p': '坏值',
      'd': null,
      'f': 'yes',
      'ts': 5.0,
    });
    assert(messy != null && messy!.position == Duration.zero, '坏字段退化到 0');
    assert(!messy!.finished, 'f 不是 true 就当 false');
    assert(messy!.videoIndex == 0 && messy!.updatedAt == 0, '非 int 数字退化');

    // 3) 进度计算
    assert(mk(u: '/p.html', p: 0).progress == 0, '没动过 = 0');
    assert((mk(u: '/p.html', p: 600).progress - 0.5).abs() < 1e-9, '一半');
    assert(mk(u: '/p.html', p: 600, f: true).progress == 1, '看完 = 满');
    assert(mk(u: '/p.html', p: 10, d: 0).progress == 0, '没时长不瞎算');
    assert(mk(u: '/p.html', p: 9999, d: 1200).progress == 1, '越界夹到 1');

    // 4) 落盘阈值那套算术（touch 的节流判断就是它）：
    //    差 <10 秒不写、≥10 秒写、**回退（快退）也要写**（取绝对值）
    int gap(int pos, int saved) => (pos - saved).abs();
    assert(gap(100, 100) < 10, '没动 → 不写');
    assert(gap(105, 100) < 10, '前进 5 秒 → 不写');
    assert(gap(110, 100) >= 10, '前进 10 秒 → 写');
    assert(gap(60, 100) >= 10, '回退 40 秒 → 必须写');
  }
}

