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

  /// 铺满整屏用的图源
  ImageProvider get image => _filePath == null
      ? const AssetImage(defaultAsset)
      : FileImage(File(_filePath!));

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
