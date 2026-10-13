import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ★ 2026-10-12（**用户决定** ✅ · 原话："柚子短剧还是删了吧。手机端播不了，都是问题。就这么决定了。删除柚子短剧"）：
//   **"柚子短剧默认隐藏"的那套特例逻辑已随站点一起删除** ☑️ ——
//   现在"站点入口显示"回到常规口径：**默认全可见**，只有用户在站点管理里手动关掉的才会隐藏 ✅
//   （⚠️ 用户盘上已有的 `site_hidden` / `site_hidden_default_v1_applied` 键**我们不动** —— 留着无害 ✅）。

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

  /// **硬件解码方式**（用户 2026-10-05 拍板加的三选一 ✓ 默认**自动** ✓）
  /// 取值 = 索引：0 自动（不设 `hwdec` ✓ 保持上游默认）/ 1 硬解（`hwdec=auto` ✓）/ 2 软解（`hwdec=no` ✓）
  /// ⚠️ 映射依据 = mpv 手册 `--hwdec=<api1,api2,...|no|auto|auto-copy>`：
  ///   "Specify the hardware video decoding API that should be used if possible. … **If hardware decoding is
  ///    not possible, mpv will fall back on software decoding.** Hardware decoding is **not enabled by default**"
  ///   ⇒ 硬解用 `auto`（**失败会自己回落软解** ✓ 正是我们要的"安全档" ✓）；
  ///   ⇒ 手册这一版的值列表里**没有 `auto-safe`** ✗（那是更新版 mpv 的写法）⇒ **不猜、不用它** ✓。
  static const List<int> hwdecOptions = [0, 1, 2];
  static const int defaultHwdec = 0;
  static const String _kHwdec = 'hwdec_mode';
  /// 三档显示名（给设置页用 ✓）
  static const List<String> hwdecLabels = ['自动', '硬解', '软解'];

  int _step = defaultStep;
  int get step => _step;

  int _bufferMb = defaultBufferMb;
  int get bufferMb => _bufferMb;

  int _hwdec = defaultHwdec;
  /// 0=自动 / 1=硬解 / 2=软解 ✓（见 [hwdecOptions] ✓）
  int get hwdec => _hwdec;

  /// 播完是否自动播下一篇里的下一个视频（默认关）
  static const String _kAutoNext = 'auto_next';
  bool _autoNext = false;
  bool get autoNext => _autoNext;

  /// ★ 2026-10-05（用户要求 ✓「需要调试的时候打开开关」）：**记录控制台日志**（默认**关** ✓ 持久化 ✓）。
  ///   照 `_kAutoNext` 逐行对齐 ✓（`SharedPreferences` = 本仓库既有的持久化做法 ✓ 不自造 ☠）。
  static const String _kLogConsole = 'log_console';
  bool _logConsole = false;
  bool get logConsole => _logConsole;

  /// ★ 2026-10-11（**用户拍板**）：**切集时是否"销毁重建"播放引擎**（**默认 false = 复用引擎**）。
  ///   · 关（**默认**）= **复用同一个引擎**、只换源 —— 少付一遍"打开"成本（切集更快）；部分站点可能黑屏 ☠
  ///   · 开 = 每次切集新建 `KpPlayer` + 新纹理，旧引擎延迟回收 —— 更稳（当年修"**切集黑屏**"就是靠它 ✅），
  ///     但每次切集要重新"打开"（更慢）☑️
  ///   ⚠️ **语义纪律（2026-10-11 用户要求改默认值）**：本次**只改"默认值"** ——
  ///      **盘上已存的值一律优先**（老用户手动开过 ⇒ 仍按他存的那个走，**绝不强制覆盖** ☠）。
  ///      三条路径见下面 `load()`：无键 ⇒ 用默认（false）；键=true ⇒ 保持 true；键=false ⇒ 保持 false ✅
  ///   持久化照 `_kAutoNext` 逐行对齐（`SharedPreferences` = 本仓库既有做法 ✅）；**改了立刻生效**（下一次切集读新值）。
  static const String _kSwitchRebuildEngine = 'switch_rebuild_engine';
  bool _switchRebuildEngine = false; // ★ 2026-10-11：默认 true → **false**（用户口径："设置默认关闭"）
  bool get switchRebuildEngine => _switchRebuildEngine;

  // ===========================================================================
  // ★ 2026-10-12（**用户新需求** ✅ · 站点管理）：**站点展示清单**（只管"入口显示" + "组内顺序"）
  //
  // 【用户原话】"底栏tab长按点播进入站点管理界面，站点用列表显示，点播分组，直播分组。
  //   站点后面加个开关（开显示站点按钮入口，关隐藏按钮入口）长按列表站点可以在分组内上下移动，
  //   必须要灵敏。改完站点管理首页实时生效"
  // 【影响面】**只影响入口按钮**（首页 5 列宫格 / 直播宫格）的**显示与顺序** ✅ ——
  //   **不动**站点数据、不动收藏、不动播放记录（隐藏一个站≠删任何东西 ✅）。
  // 【键名（本文件风格 `_kXxx` ✅；对外暴露名字给读取口/管理页用）】
  //   · [siteHiddenKey] `'site_hidden'` = JSON 字符串数组，存**被隐藏的站点名** ——
  //     存"隐藏"而不是"显示"：这样**新增站点默认可见** ✅（升级/加站绝不会被历史配置藏起来 ☑️）
  //   · [siteOrderKey] `'site_order'` = JSON 字符串 Map，形如 `{"module":[站名…],"live":[站名…]}`（组内顺序 ✅）
  // 【默认值】两个键都**读不到 / 解析失败 ⇒ 空** ⇒ 常规口径：**全站可见 + `kSites` 原顺序** ✅
  //   （⚠️ 2026-10-12：原来还有一条"柚子短剧一次性默认隐藏"的特例逻辑 —— 已随**柚子站点整体删除**
  //     一起去掉 ☑️；**"新增站点默认可见"原则回到常规、不再有任何默认隐藏** ✅）
  static const String siteHiddenKey = 'site_hidden';
  static const String siteOrderKey = 'site_order';

  final Set<String> _hiddenSites = <String>{};
  final Map<String, List<String>> _siteOrder = <String, List<String>>{};

  Set<String> get hiddenSites => _hiddenSites;
  bool isSiteHidden(String name) => _hiddenSites.contains(name);

  /// 组内自定义顺序（没存过 ⇒ 空表 ⇒ 调用方按 `kSites` 原顺序走 ✅）
  List<String> siteOrderOf(String group) => _siteOrder[group] ?? const <String>[];

  /// 开/关一个站点的**入口显示**：先改内存 + `notifyListeners`（首页/直播页**立刻**生效 ✅）再异步落盘 ✅
  /// ⚠️ 落盘失败只吞掉（本次会话照常 ✅）——与既有几个 setter 同口径 ☑️
  Future<void> setSiteHidden(String name, bool hidden) async {
    final had = _hiddenSites.contains(name);
    if (had == hidden) return; // 值没变 ⇒ 不白通知、不白写盘 ✅
    if (hidden) {
      _hiddenSites.add(name);
    } else {
      _hiddenSites.remove(name);
    }
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(siteHiddenKey, jsonEncode(_hiddenSites.toList()));
    } catch (_) {}
  }

  /// 存一组的新顺序（[names] = 该组**全部**站点的名字，顺序即界面顺序 ✅）
  Future<void> setSiteOrder(String group, List<String> names) async {
    _siteOrder[group] = List<String>.of(names);
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(siteOrderKey, jsonEncode(_siteOrder));
    } catch (_) {}
  }

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
      final hd = sp.getInt(_kHwdec);
      if (hd != null && hwdecOptions.contains(hd) && hd != _hwdec) {
        _hwdec = hd;
        changed = true;
      }
      final an = sp.getBool(_kAutoNext);
      if (an != null && an != _autoNext) {
        _autoNext = an;
        changed = true;
      }
      final lc = sp.getBool(_kLogConsole); // ★ 判 null ✓ 读不到就**保默认 false** ✗（绝不覆盖默认 ☠）
      if (lc != null && lc != _logConsole) {
        _logConsole = lc;
        changed = true;
      }
      // ★ 2026-10-11：切集是否重建引擎（**读不到 ⇒ 保默认 false** ☑️ —— 与上面 lc 同款"判 null"口径；
      //   ⚠️ **已存在的键优先**：键=true 仍 true、键=false 仍 false，本次改默认值**不覆盖盘上值** ✅）
      final sre = sp.getBool(_kSwitchRebuildEngine);
      if (sre != null && sre != _switchRebuildEngine) {
        _switchRebuildEngine = sre;
        changed = true;
      }
      // ★ 2026-10-12（站点管理）：读"隐藏集合 + 组内顺序"——
      //   · `site_order`：**读不到 / 解析失败 / 类型不对 ⇒ 保持空** ⇒ `kSites` 原顺序 ✅（绝不写坏已有配置 ☑️）
      //   · `site_hidden`：① **先**按盘上的值读（键不存在 / 解析失败 ⇒ 空集 ✅）
      //                    ② **再**看标记键 [siteDefaultHiddenSeededKey] 决定要不要做"一次性强制"（见下）
      final hs = sp.getString(siteHiddenKey);
      if (hs != null && hs.isNotEmpty) {
        try {
          final arr = jsonDecode(hs);
          if (arr is List) {
            final set = <String>{for (final x in arr) '$x'};
            if (set.length != _hiddenSites.length ||
                !set.containsAll(_hiddenSites)) {
              _hiddenSites
                ..clear()
                ..addAll(set);
              changed = true;
            }
          }
        } catch (_) {}
      }
      // ⚠️ 2026-10-12：这里原来还有一段"**一次性强制柚子默认隐藏**"（标记键 `site_hidden_default_v1_applied`）
      //   —— 已随**柚子站点整体删除**一起去掉 ✅（用户决定："柚子短剧还是删了吧…删除柚子短剧"）。
      //   ⇒ 现在 `site_hidden` **只认用户在站点管理里的手动开关**，不再有任何"默认隐藏"注入 ✅
      //   ⇒ 用户盘上若还留着那两个旧键（`site_hidden` / `site_hidden_default_v1_applied`）**我们不动**：
      //     前者照旧被读（用户在管理页关掉的站仍然隐藏 ✅），后者**不再被读**（成了无害的历史残留 ✅）。
      final so = sp.getString(siteOrderKey);
      if (so != null && so.isNotEmpty) {
        try {
          final m = jsonDecode(so);
          if (m is Map) {
            _siteOrder.clear();
            m.forEach((k, v) {
              if (v is List) _siteOrder['$k'] = <String>[for (final x in v) '$x'];
            });
            changed = true;
          }
        } catch (_) {}
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

  /// ★ 2026-10-11（用户拍板）：切集"销毁重建 ⇄ 复用引擎"开关的写入口
  ///   （照 [setAutoNext] 逐行对齐：先改内存 + `notifyListeners` ⇒ 再异步落盘 ⇒ 失败不影响本次会话 ✅）。
  Future<void> setSwitchRebuildEngine(bool v) async {
    if (v == _switchRebuildEngine) return;
    _switchRebuildEngine = v;
    notifyListeners(); // ⇒ 播放器那边"下一次切集"立刻按新值走（无需重启 ✅）
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kSwitchRebuildEngine, v);
    } catch (_) {
      // 存失败也不影响本次会话使用
    }
  }

  /// ★ 开关的写入口 ✓（照 [setAutoNext] 逐行对齐 ✓：先改内存 + `notifyListeners` ✓ 再异步落盘 ✓ 失败不影响本次会话 ✓）
  Future<void> setLogConsole(bool v) async {
    if (v == _logConsole) return;
    _logConsole = v;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kLogConsole, v);
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

  /// 改解码方式（0 自动 / 1 硬解 / 2 软解 ✓）—— 与上面几个 setter 同一套写法（照抄 bufferMb ✓）
  Future<void> setHwdec(int v) async {
    if (!hwdecOptions.contains(v) || v == _hwdec) return;
    _hwdec = v;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_kHwdec, v);
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

  /// ★ 2026-10-10（用户要求 ✅）：**本篇共几个视频**（详情页写 `d.videos.length` ✅）——
  ///   用来区分"电影 / 单集（只有 1 个视频）"与"多集文章的**第 1 集**"
  ///   （这两者 `videoIndex` 都是 0 ☠，只有这个字段能分开 ✅）。
  ///   ⚠️ **`0` = 不知道**（老记录没有 `'n'` 这个键 ✅ / 纯图文页不写 ✅）
  ///      ⇒ 显示时按"没这回事"处理 ☑️ ⇒ **老记录的行为与加字段之前完全一致** ✅。
  final int total;
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
    required this.total,
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
        'n': total, // ★ 2026-10-10：本篇共几个视频（0 = 不知道 ✅ 老版本读新 JSON 会**忽略**这个未知键 ✅）
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
      total: sec(j['n']), // ★ 缺键/非数字 ⇒ 0 = 不知道（老记录走这条 ✅ 行为不变）
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
          total: 12, // ★ 2026-10-10：总集数新字段也进往返
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
    assert(r.total == a.total, '总集数（本篇共几个视频）'); // ★ 2026-10-10 新字段
    assert(r.position == a.position, '位置（秒精度）');
    assert(r.duration == a.duration && r.finished && r.updatedAt == a.updatedAt,
        '时长/看完/时间戳');
    assert(r.key == a.key, '去重键必须一致：${r.key}');

    // 2) 字段缺失/类型错 → 不能抛异常（宁可丢一条，不能让整页崩）
    //    ⚠️ 2026-10-09 **更正期望值**（桌面 debug 首启撞出来的 ✓）：本段断言原先要求"非 int 数字退化到 0" ✗，
    //       而 `PlayRecord.fromJson` 里的 `int sec(dynamic v)` 对**非 int 的数字**是 `v.toInt()` **收下**（`5.0 ⇒ 5` ✓）
    //       ⇒ **断言与实现互相矛盾** ☠（release 里 `assert` 整段被剥掉 ⇒ 真机从没暴露；CI 只 analyze 不跑 ⇒ 也照不到 ✓）。
    //       ⇒ 现在按**实现**对齐 ✓：只有**非数字**（字符串 / null / 键缺失 ✓）才退化 0；非 int 的"数字"按 `toInt()` 收下 ✓。
    //    ⚠️ 只动**自检的期望值** ✗：`sec()` / `fromJson` / 任何落盘读写**一个字不动** ✓（release 行为逐字节不变 ✓）。
    assert(PlayRecord.fromJson(const {}) == null, '没有 site/url 的应丢弃');
    assert(PlayRecord.fromJson(const {'s': 'x'}) == null, '只有 site 的应丢弃');
    final messy = PlayRecord.fromJson(const {
      's': '站',
      'u': '/x/',
      'p': '坏值', // 非数字（字符串）
      'd': null, // 非数字（null）
      'f': 'yes', // 不是 true
      'i': 'abc', // ★ 非数字（字符串）⇒ 集号这条也一起断言上 ✓（原来不给 'i' ⇒ 走的是"键缺失"那条，覆盖弱一点 ✓）
      'n': 'abc', // ★ 2026-10-10：总集数同款——非数字（字符串）⇒ 退化 0（= 不知道）
      'ts': 5.0, // ★ **非 int 的"数字"** ⇒ 按 toInt() 收下 ⇒ 5（**不是** 0）✓
    });
    assert(messy != null && messy.position == Duration.zero, '非数字（字符串）⇒ 位置退化 0');
    assert(messy!.duration == Duration.zero, 'd = null ⇒ 时长退化 0');
    assert(!messy!.finished, 'f 不是 true 就当 false');
    assert(messy!.videoIndex == 0, '非数字（字符串）⇒ 集号退化 0');
    assert(messy!.total == 0, '非数字（字符串）⇒ 总集数退化 0（= 不知道，显示规则按老记录走）'); // ★ 2026-10-10
    assert(messy!.updatedAt == 5, '非 int 的"数字"按 toInt() 收下（5.0 ⇒ 5）—— 只有非数字才退化 0');

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

/// ★ 2026-10-12（**用户批准**："全局搜索历史：输入框下面列出搜过的词，每条带 × 删除，另有「全部删除」" ✅）：
///   **全局搜索历史**（**一份、不分站点** ✅）。
///
///  · 键名：`search_history`（`SharedPreferences` 的 **StringList** ✅）
///  · 口径（用户/lead 定 ✅）：**最近在最前** ✅ · **去重**（已存在 ⇒ 移到最前 ✅）· **上限 20 条**（超出丢最旧 ✅）·
///    输入 **trim** ✅ · 空串不记 ✅ · **读盘缺失/损坏 ⇒ 空列表（绝不上抛 ✅）** · **写盘异步、不阻塞 UI** ✅
///  · 加载：**惰性**（`ensureLoaded()` 由搜索页首帧调 ✅）—— 这样**不必动** `main.dart` / `main_win_dev.dart`
///    （本轮不许碰那两个文件 ✅）；若将来要与 `PlayHistory`/`Favorites` 一样"启动即加载"，
///    只需在那两处各加一行 `SearchHistory.i.load();` 即可 ✅（本类的 `load()` 已经自带兜错 ✅）。
class SearchHistory extends ChangeNotifier {
  SearchHistory._();
  static final SearchHistory i = SearchHistory._();

  static const String _kKey = 'search_history';
  static const int maxItems = 20; // 超出淘汰最旧的（用户口径 ✅）

  final List<String> _items = []; // 最近在最前 ✅
  bool _loaded = false;

  /// 只读视图（**最近在最前** ✅）
  List<String> get items => List<String>.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  int get length => _items.length;

  /// 惰性加载（幂等 ✅）—— UI 首次要用时调一次 ✅
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await load();
  }

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getStringList(_kKey) ?? const <String>[];
      _items
        ..clear()
        ..addAll(raw.where((s) => s.trim().isNotEmpty).take(maxItems));
    } catch (_) {
      // 读盘失败 / 数据损坏 ⇒ 当**空历史**（**绝不上抛** ✅ —— 与"不许抛"口径一致 ✅）
      _items.clear();
    }
    _loaded = true;
    notifyListeners();
  }

  /// 记一条：**去重（已存在 ⇒ 移到最前）** + **截断 20** ✅；空串 / 纯空白**不记** ✅
  Future<void> add(String kw) async {
    final k = kw.trim();
    if (k.isEmpty) return;
    _items.removeWhere((e) => e == k); // 去重：先删旧的 ✅
    _items.insert(0, k); // 最近在最前 ✅
    if (_items.length > maxItems) {
      _items.removeRange(maxItems, _items.length); // 超出丢最旧 ✅
    }
    notifyListeners(); // 内存先更新（UI 立刻变 ✅）
    await _save(); // 落盘异步（不阻塞 UI ✅）
  }

  Future<void> remove(String kw) async {
    if (!_items.remove(kw)) return;
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_kKey, _items);
    } catch (_) {
      // 落盘失败也不影响本次会话（内存里还在 ✅）—— **不上抛** ✅
    }
  }
}

