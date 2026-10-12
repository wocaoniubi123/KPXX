import Flutter
import UIKit

// ★ 2026-10-12：**代码**与上游 1.1.4 的 Classes/MediaKitLibsIosVideoPlugin.swift **逐字节相同**，
//   只多了下面这两行注释（已用 sha256 + 逐行 diff 核对过）
// （这个类只是 Flutter 插件注册占位；原生库由同目录上一级的 podspec + Makefile 交付）
public class MediaKitLibsIosVideoPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
  }
}
