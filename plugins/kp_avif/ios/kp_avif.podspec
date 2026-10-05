#
# 与 `pubspec.yaml` 的字段一致性（三处 ✓ 门禁会核）：
#   s.name  = pubspec 的 `name: kp_avif` ✓
#   s.version = pubspec 的 `version: 0.1.0` ✓
#   pluginClass（pubspec `flutter.plugin.platforms.ios.pluginClass: KpAvifPlugin` ✓）
#     = `ios/Classes/KpAvifPlugin.swift` 里的 `public class KpAvifPlugin` ✓
#
Pod::Spec.new do |s|
  s.name             = 'kp_avif'
  s.version          = '0.1.0'
  s.summary          = 'KPXX 本地插件：用 iOS 自带 ImageIO 把 AVIF 解成 PNG'
  s.description      = <<-DESC
用 iOS 自带的 ImageIO（CGImageSource / CGImageDestination）把 AVIF 解成 PNG。
只 iOS 生效；解不出 ⇒ null ⇒ Dart 侧显示占位、不崩。
                       DESC
  s.homepage         = 'https://example.com/kpxx'
  s.license          = { :type => 'MIT' }
  s.author           = { 'KPXX' => 'kpxx@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  # 与本 App 的部署目标保持一致（见 `.github/workflows/ios.yml:84-85` 与 `:93` 两处都钉 13.0 ✓）
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
