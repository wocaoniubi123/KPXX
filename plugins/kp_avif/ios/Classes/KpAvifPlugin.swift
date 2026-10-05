import Flutter
import UIKit
import ImageIO
import CoreGraphics

/// KPXX 本地插件（iOS 侧）：**用系统自带的 ImageIO 把 AVIF 解成 PNG** ✗ —— 不引入任何第三方解码库 ✓。
///
/// ⚠️ 为什么 UTI 走**字符串**：`CGImageDestinationCreateWithData(out, "public.png" as CFString, …)` ✓
///    —— 之所以**不** `import UniformTypeIdentifiers`（那样能写 `UTType.png.identifier` 更"现代"✓）☠
///    是因为那个框架**最低 iOS 14** ✗，而我们的部署目标是 **13.0** ✓（`.github/workflows/ios.yml:84-85` ✓）。
/// ⚠️ 失败一律返回 `nil` ✓ **绝不崩** ✗（参数不对 / 不是图片 / 解不出 ⇒ 都是 nil ✓）。
public class KpAvifPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // ⚠️ 通道名 `kp_avif` —— 必须与 Dart 侧 `lib/kp_avif.dart` 里的 `MethodChannel('kp_avif')` **逐字相同** ✓
    let channel = FlutterMethodChannel(name: "kp_avif", binaryMessenger: registrar.messenger())
    let instance = KpAvifPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "decodeToPng" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let typed = args["bytes"] as? FlutterStandardTypedData else {
      result(nil) // 参数不对 ⇒ nil ✓（不抛 ✗）
      return
    }
    // ⚠️ 解码放**后台队列** ✓ —— 别卡主线程 ✗（调用方一次只发一张 ✓ 不做并发轰炸 ✗）
    DispatchQueue.global(qos: .userInitiated).async {
      let png = KpAvifPlugin.decodeToPng(typed.data)
      DispatchQueue.main.async { result(png) }
    }
  }

  /// 字节 ⇒ PNG 字节；任何一步失败都返回 `nil`（`guard` 链 ✓ 不 `try!`/不 `fatalError` ✗）。
  static func decodeToPng(_ data: Data) -> FlutterStandardTypedData? {
    // ① 用 ImageIO 从内存字节建源（不解码成文件 ✓）
    guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    // ② 取第 0 帧（AVIF 单帧图 ✓；动图/多帧也只取第一张 ✓ 够用 ✓）
    guard let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    // ③ 写出 PNG（无损 ✓ —— 与"设为背景/预览"那条链路的 PNG 口径一致 ✓）
    let out = NSMutableData()
    guard let dst = CGImageDestinationCreateWithData(
      out as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dst, img, nil)
    guard CGImageDestinationFinalize(dst) else { return nil }
    return FlutterStandardTypedData(bytes: out as Data)
  }
}
