import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 图集里的一张背景（索引里存的就是这两样：路径 + 加入时间）。
@immutable
class BgItem {
  /// 沙盒绝对路径
  final String path;

  /// 加入图集的时间（毫秒时间戳；图集页直接显示 YYYY-MM-DD HH:mm）
  final int t;

  const BgItem({required this.path, required this.t});
}

/// 背景图（用户要求：设置页能换背景图，默认用内置那张；现在是**图集**）。
///
/// - 默认：asset `assets/bg_default.jpg`（用户指定那张；打包前已从 3277×4096
///   缩到 1440 宽 —— 原图解码要 ~53MB 常驻内存，1440 宽只要 ~10MB，肉眼无差）
/// - 图集：`documents/bg_album/bg_<毫秒>.jpg`（相册**多选**，选图时就缩到 1440 宽），
///   索引 `bg_album` = `[{path,t}]`，上限 [maxAlbum] 张，**新加的排最前**
/// - 单选：设置页「从相册选择」→ `documents/bg_direct_<毫秒>.jpg`，
///   **立即应用但不进图集**（用户明确的行为），也不混进 `bg_album/`
/// - 当前应用：`bg_current`（空串 = 内置默认图）
///
/// ⚠️ **每次换图都写新文件名**（绝不覆写同一个路径）。原因（用户实测）：
/// `FileImage` 的缓存键是 `(路径, scale)`，路径不变时即使 `evict()` 清了 ImageCache，
/// 只要还有控件挂在这个 key 的 ImageStream 上（`gaplessPlayback` 会一直握着旧图），
/// 后续 resolve 依旧复用同一个 ImageStreamCompleter → 换第二张没反应；
/// 而"先恢复默认再选"能换，正是因为切回 `AssetImage` 把旧的流释放了。
/// 新文件名 = 新 key = 必定重新解码。
///
/// 谁用：`AppBackground`（铺满整屏）、`PageBg`（每个被 push 的页面）、
/// 设置页的背景图卡片、图集页（`bg_album_page.dart`）。
class AppBg extends ChangeNotifier {
  AppBg._();
  static final AppBg i = AppBg._();

  static const String defaultAsset = 'assets/bg_default.jpg';

  /// 图集上限（同模拟器）：满了只提示、不加
  static const int maxAlbum = 20;

  static const String _kAlbum = 'bg_album'; // 索引（JSON 数组）
  static const String _kCurrent = 'bg_current'; // 当前应用（空串 = 内置默认图）
  static const String _kLegacy = 'bg_path'; // 老实现（单张）的键：只用于迁移
  static const String _albumDirName = 'bg_album';

  /// 图集索引（新加的在前）
  final List<BgItem> _album = [];
  List<BgItem> get album => List.unmodifiable(_album);

  /// 当前应用的图；null = 内置默认图
  String? _current;
  String? get currentPath => _current;
  bool get isDefault => _current == null;

  /// 不是内置默认图（设置页「恢复默认」的可用性判断）
  bool get isCustom => _current != null;

  /// 背景图偏深还是偏浅 → "直接浮在图上的文字"照它切黑白（见 app_background.dart 的 kTxt）。
  /// 判定不了（读字节/解码失败）一律 false = 按浅色处理，不抛给调用方。
  bool _isDark = false;
  bool get isDark => _isDark;

  /// 铺满整屏用的图源。
  ///
  /// ⚠️ 必须分开 return，不能写成 `p == null ? AssetImage(..) : FileImage(..)`：
  /// 三元表达式的静态类型会被推成 `Object`（两者只有 Object 这个公共超类），
  /// 赋给 `ImageProvider` 直接编译失败（第 60 条首次构建就是这么挂的）。
  ImageProvider get image {
    final p = _current;
    if (p == null) return const AssetImage(defaultAsset);
    return FileImage(File(p));
  }

  /// 重算明暗：位图缩到 32px 宽 → 逐像素算亮度 `0.299R+0.587G+0.114B`（0~1）
  /// → 数亮度 < 0.5 的像素占比，**> 50% 判深色**（照模拟器 sim/index.html 的 bgIsDark）。
  ///
  /// 像素量是常数级（32×~24），换图/切图各跑一次，不阻塞 UI。
  Future<void> _judgeDark() async {
    final key = _current; // 判定期间又换图 → 这次结果作废（同 sim 的 bgJudged 守卫）
    var dark = false;
    try {
      // 内置图走 asset 字节，自选图读沙盒文件；失败一律当浅色
      final data = key == null ? await rootBundle.load(defaultAsset) : null;
      final bytes = data != null
          ? data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)
          : await File(key!).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 32);
      final img = (await codec.getNextFrame()).image;
      final px = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      codec.dispose();
      img.dispose();
      if (px != null) {
        final rgba = px.buffer.asUint8List(px.offsetInBytes, px.lengthInBytes);
        var darkPx = 0;
        for (var i = 0; i < rgba.length; i += 4) {
          final l =
              (0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2]) /
                  255;
          if (l < 0.5) darkPx++;
        }
        final total = rgba.length ~/ 4;
        final ratio = total == 0 ? 0.0 : darkPx / total;
        dark = ratio > 0.5;
        debugPrint('背景明暗：暗像素占比 ${(ratio * 100).toStringAsFixed(1)}% '
            '→ ${dark ? '深色' : '浅色'}');
      }
    } catch (e) {
      debugPrint('背景明暗：判定失败，按浅色处理（$e）');
      dark = false;
    }
    if (key != _current) return; // 判定期间又换了图 → 丢弃这次结果
    _isDark = dark;
    notifyListeners();
  }

  /// 启动时读一次：图集索引 + 当前应用 +（老版单张）迁移 + 清孤儿 + 定明暗
  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _album
        ..clear()
        ..addAll(_parseAlbum(sp.getString(_kAlbum)));
      final cur = sp.getString(_kCurrent);
      if (cur != null && cur.isNotEmpty && File(cur).existsSync()) {
        _current = cur;
      } else if (cur == null || cur.isEmpty) {
        // 没写过新键 → 可能是升级前的老实现（单张 bg_path）
        await _migrateLegacy(sp);
      }
      notifyListeners();
    } catch (_) {
      // 读失败就用默认图，不影响启动
    }
    await _sweepOrphans(); // 兜底清扫（见方法注释）
    await _judgeDark(); // 定明暗（贴图文字的黑白靠它）
  }

  /// 老实现（单张：`bg_path` + `documents/bg_custom_<ts>.jpg`，更早还有无时间戳的
  /// `bg_custom.jpg`）→ **迁进图集并设为当前**。
  ///
  /// ⚠️ **迁成功才删老键**：迁不动（改名/落盘失败）就留着老键、本次会话照旧用它，
  /// 下次启动再试 —— 升级绝不能把用户已经设好的图弄丢。
  Future<void> _migrateLegacy(SharedPreferences sp) async {
    final old = sp.getString(_kLegacy);
    if (old == null || old.isEmpty) return;
    final f = File(old);
    if (!f.existsSync()) {
      await sp.remove(_kLegacy); // 文件没了 = 没什么可迁的
      return;
    }
    try {
      final dir = await _albumDir();
      final t =
          _stampFromName(old) ?? f.lastModifiedSync().millisecondsSinceEpoch;
      final dst = File('${dir.path}${Platform.pathSeparator}bg_$t.jpg');
      await f.rename(dst.path); // 同一个沙盒内，rename 是原子的
      _album.insert(0, BgItem(path: dst.path, t: t));
      _current = dst.path;
      await _persistAlbum();
      await _persistCurrent();
      await sp.remove(_kLegacy);
      debugPrint('背景图集：已把升级前的老图迁进图集（$t）');
    } catch (e) {
      _current = old; // 迁不动：本次会话照旧用它（老键还在，下次再试）
      debugPrint('背景图集：老图迁移失败，先照旧使用（$e）');
    }
  }

  /// 从文件名里抠时间戳（`bg_custom_1700000000000.jpg` / `bg_<ts>.jpg`）；
  /// 老的无时间戳文件名（`bg_custom.jpg`）返回 null（调用方改用文件 mtime）
  static int? _stampFromName(String path) {
    final m = RegExp(r'_(\d{10,})\.jpg$').firstMatch(_name(path));
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// 清扫孤儿图（启动时跑一次，只列两个目录，成本极低）：
  /// - `documents/bg_album/`：**索引里没有的** `bg_*.jpg` 删掉（加图/换图/删图中途被杀留下的）
  /// - `documents/`：老实现的 `bg_custom*`、以及不是当前那张的 `bg_direct_*` 删掉
  ///   （「从相册选择」也是写新文件名，不清理会越积越多）
  ///
  /// 保留：索引里全部 + 当前应用那张（含"迁移失败、仍在 documents/ 里"的老图）。
  Future<void> _sweepOrphans() async {
    try {
      final root = await getApplicationDocumentsDirectory();
      final keep = <String>{for (final it in _album) it.path};
      final cur = _current;
      if (cur != null) keep.add(cur);
      final dir =
          Directory('${root.path}${Platform.pathSeparator}$_albumDirName');
      if (await dir.exists()) {
        await for (final e in dir.list()) {
          if (e is! File || keep.contains(e.path)) continue;
          final n = _name(e.path);
          if (!n.startsWith('bg_') || !n.endsWith('.jpg')) continue;
          try {
            await e.delete();
          } catch (_) {
            // 删不掉就算了
          }
        }
      }
      await for (final e in root.list()) {
        if (e is! File || keep.contains(e.path)) continue;
        final n = _name(e.path);
        if (!n.startsWith('bg_direct_') && !n.startsWith('bg_custom')) continue;
        try {
          await e.delete();
        } catch (_) {
          // 删不掉就算了
        }
      }
    } catch (_) {
      // 清扫失败不影响背景图使用
    }
  }

  /// 图集页右上角「＋」：相册**多选** → 逐张存进 `bg_album/` → 加进索引（新加的排最前）
  /// → **不自动应用**。返回 `(加入成功张数, 因为满 [maxAlbum] 张被跳过的张数)`，
  /// 调用方据此提示。选图失败会抛异常（调用方 catch 后提示）。
  Future<({int added, int full})> addFromGallery() async {
    final picked = await ImagePicker().pickMultiImage(
      maxWidth: 1440, // 和内置默认图同规格：解码内存 ~10MB
      maxHeight: 2400,
      imageQuality: 88,
    );
    if (picked.isEmpty) return (added: 0, full: 0);
    final dir = await _albumDir();
    var added = 0;
    var skipped = 0;
    for (final p in picked) {
      if (_album.length >= maxAlbum) {
        skipped++; // 到上限：剩下的一律不加（继续数个数，把"跳过几张"报准）
        continue;
      }
      try {
        // 同一毫秒里连选多张时往后挪，保证文件名不撞
        var t = DateTime.now().millisecondsSinceEpoch;
        while (File('${dir.path}${Platform.pathSeparator}bg_$t.jpg')
            .existsSync()) {
          t++;
        }
        final dst = File('${dir.path}${Platform.pathSeparator}bg_$t.jpg');
        await File(p.path).copy(dst.path);
        _album.insert(0, BgItem(path: dst.path, t: t));
        added++;
      } catch (_) {
        // 单张失败跳过，不影响其它
      }
    }
    if (added > 0) {
      await _persistAlbum();
      notifyListeners();
    }
    debugPrint('背景图集：本次加入 $added 张（到上限跳过 $skipped 张）'
        '→ 共 ${_album.length}/$maxAlbum');
    return (added: added, full: skipped);
  }

  /// 设置页「从相册选择」：**单选 → 立即应用，但不进图集**（用户明确要的行为）。
  /// true = 换好了；false = 用户取消（选图/写盘失败会抛异常，调用方 catch 后提示）
  Future<bool> pickFromGallery() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1440, // 和内置默认图同规格：解码内存 ~10MB
      maxHeight: 2400,
      imageQuality: 88,
    );
    if (picked == null) return false;
    final root = await getApplicationDocumentsDirectory();
    final old = _current;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dst =
        File('${root.path}${Platform.pathSeparator}bg_direct_$stamp.jpg');
    await File(picked.path).copy(dst.path);
    await FileImage(dst).evict(); // 双保险（新 key 本来也命中不了旧缓存）
    _current = dst.path;
    notifyListeners();
    await _judgeDark(); // 换了图 → 重新定明暗
    await _persistCurrent();
    // 删掉上一张**单选**图（图集里的那张别动：它归图集管）
    if (old != null && old != dst.path && _isDirect(old)) {
      try {
        final f = File(old);
        if (f.existsSync()) await f.delete();
      } catch (_) {
        // 删不掉就算了（下次启动清扫还会试）
      }
    }
    return true;
  }

  /// 应用图集第 i 张（图集页点一条 = 立即应用，不跳页）
  Future<void> applyAlbum(int i) async {
    if (i < 0 || i >= _album.length) return;
    if (_current == _album[i].path) return; // 已经是它了
    final old = _current;
    _current = _album[i].path;
    notifyListeners();
    await _judgeDark(); // 每次切换都要重算明暗
    await _persistCurrent();
    if (old != null && _isDirect(old)) {
      try {
        final f = File(old);
        if (f.existsSync()) await f.delete(); // 上一张是单选图 → 清掉
      } catch (_) {
        // 删不掉就算了
      }
    }
  }

  /// 删图集第 i 张：删文件 + 出索引；**删的正是当前应用那张 → 回内置默认图**。
  /// 返回 true = 删的就是当前那张（调用方可以提示一句）。不二次确认（用户要求）。
  Future<bool> removeAlbum(int i) async {
    if (i < 0 || i >= _album.length) return false;
    final it = _album.removeAt(i);
    final wasCurrent = _current == it.path;
    if (wasCurrent) _current = null; // 回内置默认图
    notifyListeners();
    try {
      final f = File(it.path);
      if (f.existsSync()) await f.delete();
    } catch (_) {
      // 删不掉就算了（索引已摘掉，下次启动清扫会再试）
    }
    await _persistAlbum();
    if (wasCurrent) {
      await _persistCurrent();
      await _judgeDark(); // 回内置图 → 重新定明暗
    }
    return wasCurrent;
  }

  /// 恢复默认：只清当前 → 回内置图，**不动图集**
  Future<void> clear() async {
    _current = null;
    notifyListeners();
    await _persistCurrent();
    await _judgeDark(); // 回默认图 → 重新定明暗
  }

  // ---------------- 内部：目录 / 索引 / 落盘 ----------------

  static String _name(String path) => path.split(Platform.pathSeparator).last;

  /// 是不是「从相册选择」的单选题文件（`bg_direct_*`；老实现是 `bg_custom*`）——
  /// 换图时只有这种可以删，图集里的文件归图集管
  static bool _isDirect(String path) {
    final n = _name(path);
    return n.startsWith('bg_direct_') || n.startsWith('bg_custom');
  }

  Future<Directory> _albumDir() async {
    final root = await getApplicationDocumentsDirectory();
    final d = Directory('${root.path}${Platform.pathSeparator}$_albumDirName');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// 索引 JSON → 列表（文件已经没了的条目直接剔掉，不让它变成一行破图）
  static List<BgItem> _parseAlbum(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final j = jsonDecode(raw);
      if (j is! List) return const [];
      final out = <BgItem>[];
      for (final e in j) {
        if (e is! Map) continue;
        final p = e['path'];
        if (p is! String || p.isEmpty || !File(p).existsSync()) continue;
        final t = e['t'];
        out.add(BgItem(path: p, t: t is int ? t : 0));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// 落盘索引（失败只影响下次启动，不抛给调用方）
  Future<void> _persistAlbum() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kAlbum,
          jsonEncode([for (final it in _album) {'path': it.path, 't': it.t}]));
    } catch (_) {
      // 同上
    }
  }

  /// 落盘"当前应用"（空串 = 内置默认图）
  Future<void> _persistCurrent() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kCurrent, _current ?? '');
    } catch (_) {
      // 同上
    }
  }
}
