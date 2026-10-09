#include "include/kp_avif/kp_avif_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "kp_avif_plugin.h"

void KpAvifPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  kp_avif::KpAvifPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
