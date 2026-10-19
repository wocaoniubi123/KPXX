import Flutter
import Foundation
import AVFoundation

/// KPXX 本地插件（iOS 侧）：把 HLS 下载产物 `.ts` 重封装成 `.mp4`（只换容器、不转码）。
///
/// 通道 `kp.video_export` / 方法 `remuxToMp4` / 入参 `{input: String, output: String}` / 出参 output 路径。
/// 失败：`EXPORT_FAILED`（`message` 带 `error.localizedDescription`）或 `NO_TRACKS`（asset 里没有音视频轨）。
///
/// 只用系统自带的 AVFoundation（`AVURLAsset` + `AVAssetExportSession`），不引第三方库、不联网。
/// 文件读写与导出都放后台队列；`FlutterResult` 一律回主线程调用。
public class KpVideoExportPlugin: NSObject, FlutterPlugin {
  /// 通道名 —— 必须与 Dart 侧 `lib/kp_video_export.dart` 里的
  /// `MethodChannel('kp.video_export')` 逐字相同。
  private static let channelName = "kp.video_export"
  private static let methodRemux = "remuxToMp4"

  /// 单次导出的结果。
  private enum ExportOutcome {
    /// 导出成功（输出文件已写好）。
    case success
    /// 导出失败 —— 换预设重试有意义。
    case failed(reason: String)
    /// 取消 / 未完成 / 前置 IO 失败 —— 不重试。
    case aborted(reason: String)
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: KpVideoExportPlugin.channelName,
                                       binaryMessenger: registrar.messenger())
    let instance = KpVideoExportPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == KpVideoExportPlugin.methodRemux else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let inputPath = args["input"] as? String,
          let outputPath = args["output"] as? String,
          !inputPath.isEmpty,
          !outputPath.isEmpty else {
      result(FlutterError(code: "EXPORT_FAILED",
                          message: "参数不对：input / output 必须是非空字符串",
                          details: nil))
      return
    }
    // 重封装 = 读文件 + 写文件，放后台队列，别卡主线程。
    DispatchQueue.global(qos: .userInitiated).async {
      KpVideoExportPlugin.remux(inputPath: inputPath,
                                outputPath: outputPath,
                                result: result)
    }
  }

  /// 重封装主体（调用前已保证在后台队列）。
  private static func remux(inputPath: String,
                            outputPath: String,
                            result: @escaping FlutterResult) {
    let fileManager = FileManager.default
    let inputURL = URL(fileURLWithPath: inputPath)
    let outputURL = URL(fileURLWithPath: outputPath)

    guard fileManager.fileExists(atPath: inputURL.path) else {
      finish(result, FlutterError(code: "EXPORT_FAILED",
                                  message: "输入文件不存在：\(inputURL.path)",
                                  details: nil))
      return
    }
    // 同一个路径会先把输入删掉 ⇒ 直接拒绝（避免误删下载好的 .ts）。
    guard inputURL.standardizedFileURL != outputURL.standardizedFileURL else {
      finish(result, FlutterError(code: "EXPORT_FAILED",
                                  message: "input 与 output 不能是同一个文件",
                                  details: nil))
      return
    }
    // 输出父目录不存在先建（已存在时 createDirectory 不报错）。
    do {
      try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(),
                                      withIntermediateDirectories: true,
                                      attributes: nil)
    } catch {
      finish(result, FlutterError(code: "EXPORT_FAILED",
                                  message: error.localizedDescription,
                                  details: nil))
      return
    }
    // AVFoundation 能直接打开本地 MPEG-TS 文件（与 HLS 分片同源）。
    let asset = AVURLAsset(url: inputURL)

    // ★ 2026-10-19（iOS 16+ 兼容）：`tracks(withMediaType:)` 是 **deprecated 的同步 API**
    //   —— 对某些资产它会先返回空数组（要等加载完成才有轨），直接用它判 `NO_TRACKS` 会误报。
    //   ⇒ 先异步把 `tracks` 加载好（iOS 13 起可用），加载成功后再同步取轨判断。
    asset.loadValuesAsynchronously(forKeys: ["tracks"]) {
      var loadError: NSError?
      let status = asset.statusOfValue(forKey: "tracks", error: &loadError)
      guard status == .loaded else {
        let reason = loadError?.localizedDescription
          ?? "轨道信息加载失败（status = \(status.rawValue)）"
        finish(result, FlutterError(code: "NO_TRACKS", message: reason, details: nil))
        return
      }
      let hasVideo = !asset.tracks(withMediaType: .video).isEmpty
      let hasAudio = !asset.tracks(withMediaType: .audio).isEmpty
      guard hasVideo || hasAudio else {
        finish(result, FlutterError(code: "NO_TRACKS",
                                    message: "输入文件里没有可导出的音视频轨：\(inputURL.lastPathComponent)",
                                    details: nil))
        return
      }

      // 第一次：Passthrough（只换容器、不转码，最快）。
      runExport(asset: asset,
                presetName: AVAssetExportPresetPassthrough,
                outputURL: outputURL) { firstOutcome in
        switch firstOutcome {
        case .success:
          result(outputPath) // runExport 保证回调在主线程
        case .aborted(let reason):
          result(FlutterError(code: "EXPORT_FAILED", message: reason, details: nil))
        case .failed(let firstReason):
          // 兜底：换最高质量预设转码重试一次（慢，但兼容性最好，保证能存相册）。
          runExport(asset: asset,
                    presetName: AVAssetExportPresetHighestQuality,
                    outputURL: outputURL) { secondOutcome in
            switch secondOutcome {
            case .success:
              result(outputPath)
            case .failed(let secondReason):
              result(FlutterError(
                code: "EXPORT_FAILED",
                message: "重封装失败：\(firstReason)；转码兜底也失败：\(secondReason)",
                details: nil))
            case .aborted(let secondReason):
              result(FlutterError(
                code: "EXPORT_FAILED",
                message: "重封装失败：\(firstReason)；转码兜底中断：\(secondReason)",
                details: nil))
            }
          }
        }
      }
    }
  }

  /// 用指定预设跑一次导出（异步）。`completion` 一律回主线程；
  /// 非成功（含取消 / 未完成）一律先把半截输出删掉（不存在时忽略，删失败也不影响回错）。
  private static func runExport(asset: AVAsset,
                                presetName: String,
                                outputURL: URL,
                                completion: @escaping (ExportOutcome) -> Void) {
    let report: (ExportOutcome) -> Void = { outcome in
      switch outcome {
      case .success:
        break // 成功：输出保留
      case .failed, .aborted:
        try? FileManager.default.removeItem(at: outputURL)
      }
      DispatchQueue.main.async { completion(outcome) }
    }

    // 每次导出前先删已存在的输出（导出不会覆盖已有文件；转码兜底重试前同样先删）。
    do {
      if FileManager.default.fileExists(atPath: outputURL.path) {
        try FileManager.default.removeItem(at: outputURL)
      }
    } catch {
      report(.aborted(reason: "无法删除已存在的输出文件：\(error.localizedDescription)"))
      return
    }

    guard let session = AVAssetExportSession(asset: asset, presetName: presetName) else {
      report(.failed(reason: "AVAssetExportSession 创建失败（预设 \(presetName) 不可用）"))
      return
    }
    // 设成不支持的文件类型会抛 NSInvalidArgumentException（直接崩）⇒ 先查一遍。
    guard session.supportedFileTypes.contains(.mp4) else {
      report(.failed(reason: "预设 \(presetName) 不支持输出 .mp4"))
      return
    }
    session.outputURL = outputURL
    session.outputFileType = .mp4

    session.exportAsynchronously {
      switch session.status {
      case .completed:
        report(.success)
      case .failed:
        let reason = session.error?.localizedDescription ?? "未知错误"
        report(.failed(reason: reason))
      case .cancelled:
        report(.aborted(reason: "导出被取消"))
      default:
        report(.aborted(reason: "导出未完成（status = \(session.status.rawValue)）"))
      }
    }
  }

  /// 后台队列 ⇒ 主线程回结果（`FlutterResult` 必须在 platform 线程调用）。
  private static func finish(_ result: @escaping FlutterResult, _ value: Any?) {
    DispatchQueue.main.async { result(value) }
  }
}
