import 'package:flutter/services.dart';

/// 本地插件 `kp_video_export` 的 Dart 面：**把 HLS 下载产物 `.ts` 重封装成 `.mp4`**（只换容器、不转码）。
///
/// ⚠️ 通道名 `kp.video_export` 必须与
///   `plugins/kp_video_export/ios/Classes/KpVideoExportPlugin.swift` 里的
///   `FlutterMethodChannel(name: "kp.video_export", …)` **逐字相同**。
/// ⚠️ 只有 iOS 有实现（`pubspec.yaml` 只声明 ios）：非 iOS 上插件没注册 ⇒ 返回 `null`（不崩）。
/// ⚠️ 原生导出失败会抛 `PlatformException`（code = `EXPORT_FAILED` / `NO_TRACKS`，
///   message 带原生 `error.localizedDescription`）—— 调用方要么 catch，要么按"失败"处理。
/// ⚠️ 原生侧：Passthrough（不转码）失败时会**自动转码兜底重试一次**（`HighestQuality`，较慢）——
///   所以本方法**可能耗时到分钟级**，调用方必须给等待/进度提示（不要干等）。
class KpVideoExport {
  static const MethodChannel _ch = MethodChannel('kp.video_export');

  /// 把 [inputPath]（`.ts`）重封装成 [outputPath]（`.mp4`）：copy 视频/音频轨、不转码。
  ///
  /// 成功返回 [outputPath]；非 iOS（插件未注册）返回 `null`；原生失败抛 `PlatformException`。
  static Future<String?> remuxToMp4(String inputPath, String outputPath) async {
    try {
      return await _ch.invokeMethod<String>(
        'remuxToMp4',
        <String, dynamic>{'input': inputPath, 'output': outputPath},
      );
    } on MissingPluginException {
      return null; // 非 iOS / 插件没注册 —— 不崩
    }
  }
}
