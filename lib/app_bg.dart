import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 背景图（用户要求：设置页能换背景图，默认用内置那张）。
///
/// - 默认：asset `assets/bg_default.jpg`（用户指定那张；打包前已从 3277×4096
///   缩到 1440 宽 —— 原图解码要 ~53MB 常驻内存，1440 宽只要 ~10MB，肉眼无差）
/// - 自选：相册选图 → 缩到同样规格 → 拷进沙盒 `documents/bg_custom_<毫秒时间戳>.jpg`
///   （**每次换图写新文件名**，原因见 `pickFromGallery()` 的注释）
///   → 路径存 shared_preferences
///
/// 谁用：`AppBackground`（铺满整屏）、设置页的背景图卡片（选图/恢复默认）。
class AppBg extends ChangeNotifier {
  AppBg._();
  static final AppBg i = AppBg._();

  static const String _kPath = 'bg_path';
  static const String defaultAsset = 'assets/bg_default.jpg';

  /// 自选图的沙盒路径；null = 用内置默认图
  String? _filePath;
  String? get filePath => _filePath;
  bool get isCustom => _filePath != null;

  /// 铺满整屏用的图源。
  ///
  /// ⚠️ 必须分开 return，不能写成 `p == null ? AssetImage(..) : FileImage(..)`：
  /// 三元表达式的静态类型会被推成 `Object`（两者只有 Object 这个公共超类），
  /// 赋给 `ImageProvider` 直接编译失败（第 60 条首次构建就是这么挂的）。
  ImageProvider get image {
    final p = _filePath;
    if (p == null) return const AssetImage(defaultAsset);
    return FileImage(File(p));
  }

  /// 背景图偏深还是偏浅 → "直接浮在图上的文字"照它切黑白（见 app_background.dart 的 kTxt）。
  /// 判定不了（读字节/解码失败）一律 false = 按浅色处理，不抛给调用方。
  bool _isDark = false;
  bool get isDark => _isDark;

  /// 重算明暗：位图缩到 32px 宽 → 逐像素算亮度 `0.299R+0.587G+0.114B`（0~1）
  /// → 数亮度 < 0.5 的像素占比，**> 50% 判深色**（照模拟器 sim/index.html 的 bgIsDark）。
  ///
  /// 像素量是常数级（32×~24），换图/启动各跑一次，不阻塞 UI。
  Future<void> _judgeDark() async {
    final key = _filePath; // 判定期间又换图 → 这次结果作废（同 sim 的 bgJudged 守卫）
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
    if (key != _filePath) return; // 判定期间又换了图 → 丢弃这次结果
    _isDark = dark;
    notifyListeners();
  }

  /// 启动时读一次；文件没了就当没设过（回默认图）
  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final p = sp.getString(_kPath);
      if (p != null && p.isNotEmpty && File(p).existsSync()) {
        _filePath = p;
        notifyListeners();
      }
      await _sweepOrphans(); // 兜底清扫（见方法注释）
    } catch (_) {
      // 读失败就用默认图，不影响启动
    }
    await _judgeDark(); // 定明暗（贴图文字的黑白靠它）
  }

  /// 清扫孤儿自选图：只保留当前这张，其它 `bg_custom_*.jpg`（含老版本的
  /// `bg_custom.jpg`）一律删掉。
  ///
  /// 为什么需要兜底：换图是"写新文件 → 删旧文件"，若在这两步之间进程被杀，
  /// 会残留一张（正常路径下不会，每次换图都已删掉上一张）。成本极低，
  /// 只列一次 documents 目录、数量是常数级。
  Future<void> _sweepOrphans() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final keep = _filePath?.split(Platform.pathSeparator).last;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final n = e.path.split(Platform.pathSeparator).last;
        final mine = n == 'bg_custom.jpg' ||
            (n.startsWith('bg_custom_') && n.endsWith('.jpg'));
        if (!mine || n == keep) continue;
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

  /// 从相册选图。true = 换好了；false = 用户取消
  /// （失败会抛异常，调用方 catch 后提示）
  ///
  /// ⚠️ 每次写**新文件名**（带毫秒时间戳），绝不覆写同一个路径。
  /// 原因（用户实测）：`FileImage` 的缓存键是 `(路径, scale)`。路径不变时，
  /// 即使 `evict()` 清掉 ImageCache，只要还有控件挂在这个 key 的 ImageStream 上
  /// （`gaplessPlayback` 会一直握着旧图），后续 resolve 依旧复用同一个
  /// ImageStreamCompleter → 换第二张没反应；而"先恢复默认再选"能换，正是因为
  /// 切回 `AssetImage` 把旧的流释放了。换新文件名 = 新 key = 必定重新解码。
  Future<bool> pickFromGallery() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1440, // 和内置默认图同规格：解码内存 ~10MB
      maxHeight: 2400,
      imageQuality: 88,
    );
    if (picked == null) return false;
    final dir = await getApplicationDocumentsDirectory();
    final old = _filePath;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dst = File(
        '${dir.path}${Platform.pathSeparator}bg_custom_$stamp.jpg');
    await File(picked.path).copy(dst.path);
    await FileImage(dst).evict(); // 双保险（新 key 本来也命中不了旧缓存）
    _filePath = dst.path;
    notifyListeners();
    await _judgeDark(); // 换了图 → 重新定明暗
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kPath, dst.path);
    } catch (_) {
      // 存失败也不影响本次会话（下次启动回默认图）
    }
    // 删掉上一张自选图：换图是"写新文件"，不清理的话沙盒里会越积越多
    if (old != null) {
      try {
        final f = File(old);
        if (f.existsSync()) await f.delete();
      } catch (_) {
        // 删不掉就算了（可能已被系统清理）
      }
    }
    return true;
  }

  /// 恢复默认背景（删掉自选图文件 + 清配置）
  Future<void> clear() async {
    final old = _filePath;
    _filePath = null;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_kPath);
      if (old != null) {
        final f = File(old);
        if (f.existsSync()) await f.delete();
      }
    } catch (_) {
      // 同上：失败只影响下次启动
    }
    await _judgeDark(); // 回默认图 → 重新定明暗
  }
}
