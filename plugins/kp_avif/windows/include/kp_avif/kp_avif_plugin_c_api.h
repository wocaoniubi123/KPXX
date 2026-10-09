#ifndef FLUTTER_PLUGIN_KP_AVIF_PLUGIN_C_API_H_
#define FLUTTER_PLUGIN_KP_AVIF_PLUGIN_C_API_H_

#include <flutter_plugin_registrar.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

// NOTE: ASCII-only comments on purpose (see kp_avif_plugin.h).

#if defined(__cplusplus)
extern "C" {
#endif

// Flutter plugin registration entry point. The name must be the CamelCase plugin name plus
// RegisterWithRegistrar; it is called from the generated generated_plugin_registrant.cc.
FLUTTER_PLUGIN_EXPORT void KpAvifPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_KP_AVIF_PLUGIN_C_API_H_
