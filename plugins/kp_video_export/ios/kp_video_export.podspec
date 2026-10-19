#
# 与 `pubspec.yaml` 的字段一致性（三处必须对上）：
#   s.name    = pubspec 的 `name: kp_video_export`
#   s.version = pubspec 的 `version: 0.1.0`
#   pluginClass（pubspec `flutter.plugin.platforms.ios.pluginClass: KpVideoExportPlugin`）
#     = `ios/Classes/KpVideoExportPlugin.swift` 里的 `public class KpVideoExportPlugin`
#
Pod::Spec.new do |s|
  s.name             = 'kp_video_export'
  s.version          = '0.1.0'
  s.summary          = 'KPXX 本地插件：用 AVFoundation 把 .ts 重封装成 .mp4'
  s.description      = <<-DESC
用 iOS 自带的 AVFoundation（AVURLAsset + AVAssetExportSession 的 Passthrough 预设）
把 .ts 文件里的音视频轨原样 copy 进 .mp4 容器，不转码。
只 iOS 生效。
                       DESC
  s.homepage         = 'https://example.com/kpxx'
  s.license          = { :type => 'MIT' }
  s.author           = { 'KPXX' => 'kpxx@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  # 与本 App 的部署目标保持一致（`.github/workflows/ios.yml` 里 IPHONEOS_DEPLOYMENT_TARGET 与 Podfile 都钉 13.0）
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
