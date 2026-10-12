#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint media_kit_libs_ios_video.podspec` to validate before publishing.
#
# ★ 2026-10-12：以上游 1.1.4 的 podspec 为蓝本。**除下面这几行注释 + `s.version`
#   （上游那份写的是陈旧值 '1.0.4'，这里改成与本包 pubspec.yaml 一致的 '1.1.5'）外，
#   其余行与上游一字不差**（已逐行 diff 核对）。
#   **故意保持老布局**（`Classes/**/*`、无 Swift Package 目录）——
#   见同目录上一级 pubspec.yaml 顶部关于"带 Package.swift ⇒ 被判定支持 SPM ⇒ make 不跑 ⇒ Mpv 缺失"的说明。
#
Pod::Spec.new do |s|
  # 这一步是「真正把 Mpv.xcframework 交付到链接期」的地方：
  # 在 CocoaPods 求值本 podspec 时执行 `make` ⇒ 下载并解包 xcframework 到 ios/Frameworks/
  # （只有走 CocoaPods 路径才会执行；被 Flutter 判成 SPM 就会跳过 ⇒ 所以我们不要 Package.swift）
  system("make")

  s.name             = 'media_kit_libs_ios_video'
  s.version          = '1.1.5'
  s.summary          = 'iOS dependency package for package:media_kit'
  s.description      = <<-DESC
  iOS dependency package for package:media_kit.
                       DESC
  s.homepage         = 'https://github.com/media-kit/media-kit.git'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Hitesh Kumar Saini' => 'saini123hitesh@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'

  s.vendored_frameworks = 'Frameworks/*.xcframework'

  s.platform = :ios, '9.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # Flutter.framework does not contain a i386 slice.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'
end
