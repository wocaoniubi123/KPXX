# kp_avif 的 Windows 实现（★ 2026-10-09 新增 ✓）
#
# ★ 解码走**系统自带**的 WIC（Windows Imaging Component）—— 本机实测：
#   AVIF 经 WIC 解出 1204x800 BGRA、codec 名字是 "Microsoft HEIF Decoder" ✓
#   （AVIF 解码器由 Store 包 **HEIF Image Extension** 提供；本机已装 1.2.48.0 ✓；
#    缺失时 decoder 创建失败 ⇒ 我们返回 null ⇒ Dart 侧回落占位，与今天行为一致 ✓）
#
# ⚠️ 本文件是**新增平台实现**：iOS 侧（`ios/`）一行未动 ✓、Dart 面（`lib/kp_avif.dart`）一行未动 ✓。

cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "kp_avif")
project(${PROJECT_NAME} LANGUAGES CXX)

# 插件的原生库名（Flutter 约定：<name>_plugin）
set(PLUGIN_NAME "${PROJECT_NAME}_plugin")

add_library(${PLUGIN_NAME} SHARED
  "kp_avif_plugin.cpp"
  "kp_avif_plugin_c_api.cpp"
  "include/kp_avif/kp_avif_plugin_c_api.h"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# WIC（windowscodecs）+ COM 基座（ole32：CoCreateInstance / CoInitializeEx）
target_link_libraries(${PLUGIN_NAME} PRIVATE windowscodecs ole32)

# 没有要跟包一起拷的第三方库（WIC 是系统组件）
set(kp_avif_bundled_libraries
  ""
  PARENT_SCOPE
)
