import 'dart:typed_data';

import 'package:flutter/services.dart';

/// 本地插件 `kp_avif` 的 Dart 面：**iOS 侧用 ImageIO 把 AVIF 解成 PNG** ✓。
///
/// ⚠️ 通道名 `kp_avif` 必须与 `plugins/kp_avif/ios/Classes/KpAvifPlugin.swift` 里的
///   `FlutterMethodChannel(name: "kp_avif", …)` **逐字相同** ✓（门禁会核 ✓）。
/// ⚠️ **任何异常都吞掉返回 `null`** ✗（原生侧没注册 / 平台不是 iOS / 解码失败 ⇒ 一律 null ✓）
///   —— 调用方按"解不出"走占位 ✓ **不许崩** ✗。
class KpAvif {
  static const MethodChannel _ch = MethodChannel('kp_avif');

  /// 入参 = 原始字节（AVIF）✓；出参 = **PNG 字节**（失败/不支持 ⇒ `null` ✓）。
  static Future<Uint8List?> decodeToPng(Uint8List bytes) async {
    try {
      return await _ch.invokeMethod<Uint8List>(
        'decodeToPng',
        <String, dynamic>{'bytes': bytes},
      );
    } catch (_) {
      return null; // 一律吞掉 ✓（不崩 ✗）
    }
  }
}
