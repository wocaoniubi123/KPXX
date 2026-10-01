import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 背景图（用户要求：设置页能换背景图，默认用内置那张）。
///
/// - 默认：asset `assets/bg_default.jpg`（用户指定那张；打包前已从 3277×4096
///   缩到 1440 宽 —— 原图解码要 ~53MB 常驻内存，1440 宽只要 ~10MB，肉眼无差）
/// - 自选：相册选图 → 缩到同样规格 → 拷进沙盒 `documents/bg_custom.jpg`
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

  /// 启动时读一次；文件没了就当没设过（回默认图）
  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final p = sp.getString(_kPath);
      if (p == null || p.isEmpty) return;
      if (!File(p).existsSync()) return;
      _filePath = p;
      notifyListeners();
    } catch (_) {
      // 读失败就用默认图，不影响启动
    }
  }

  /// 从相册选图。true = 换好了；false = 用户取消
  /// （失败会抛异常，调用方 catch 后提示）
  Future<bool> pickFromGallery() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1440, // 和内置默认图同规格：解码内存 ~10MB
      maxHeight: 2400,
      imageQuality: 88,
    );
    if (picked == null) return false;
    final dir = await getApplicationDocumentsDirectory();
    final dst = File('${dir.path}${Platform.pathSeparator}bg_custom.jpg');
    await File(picked.path).copy(dst.path);
    // ⚠️ 每次都覆写同一个路径 → FileImage 的缓存键是 (路径, scale)，路径没变，
    // ImageCache 会把**第一次解码的那张旧图**继续给你（用户实测：换第二张还是第一张）。
    // 覆写完必须 evict 掉这个条目，下一帧才会重新读盘解码。
    await FileImage(dst).evict();
    _filePath = dst.path;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kPath, dst.path);
    } catch (_) {
      // 存失败也不影响本次会话（下次启动回默认图）
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
  }
}
