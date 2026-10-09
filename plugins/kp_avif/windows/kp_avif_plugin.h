#ifndef FLUTTER_PLUGIN_KP_AVIF_PLUGIN_H_
#define FLUTTER_PLUGIN_KP_AVIF_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

// NOTE: ASCII-only comments in this file on purpose. MSVC gets no /utf-8 from the Flutter
// template, so a UTF-8 non-ASCII comment is decoded with the system codepage (936 here) and
// breaks the build with C4819 -> C2220 (warnings as errors). Measured 2026-10-09.

namespace kp_avif {

// Windows side: one job only - decode AVIF bytes into PNG bytes.
// Same contract as the iOS side (ImageIO): channel "kp_avif", method "decodeToPng",
// args {"bytes": Uint8List}, reply Uint8List (PNG) or null when it cannot be decoded.
class KpAvifPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  KpAvifPlugin();
  ~KpAvifPlugin() override;

  KpAvifPlugin(const KpAvifPlugin&) = delete;
  KpAvifPlugin& operator=(const KpAvifPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace kp_avif

#endif  // FLUTTER_PLUGIN_KP_AVIF_PLUGIN_H_
