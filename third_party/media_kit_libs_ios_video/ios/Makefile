all: Frameworks/*.xcframework Frameworks/.symlinks

# ★ 2026-10-12（用户拍板"直接 B，一步到位"）：以上游 1.1.4 的 Makefile 为蓝本。
#   **除下面这段注释 + 版本串 + 下载基址 + sha256 这四处外，其余行与上游一字不差**
#   （已逐行 diff 核对）。其余流程（curl 下载 → shasum 校验 → 解包到 Frameworks/ → 建 .symlinks）原样保留。
#
#   背景（依据 🛢️）：
#   · 官方 media-kit/libmpv-darwin-build 的预编译天花板 = mpv 0.36.0 / ffmpeg 6.0
#     （v0.6.0 / v0.7.2 / v0.7.3 全同），所以**自己编**。
#   · 自编必须**保留动态框架名 `Mpv`**：media_kit 的
#     `lib/src/player/native/core/native_library.dart` 在 iOS/macOS 上硬编码
#     `DynamicLibrary.open('Mpv.framework/Mpv')` ⇒ 只有【名为 Mpv 的动态框架】能被加载
#     （mpvkit/MPVKit 给的是 `Libmpv`，且内层是 `!<arch>` 静态归档 ⇒ 用不了）。
#   · 自编产物由 `.github/workflows/build-libmpv-ios.yml` 产出，资产名公式来自官方 nix：
#     `libmpv-${format}_${version}_${os}-${arch}-${variant}-${flavor}` ⇒
#     `libmpv-xcframeworks_<VERSION>_ios-universal-video-default.tar.gz`
#   ⚠️ 所以**本文件里的版本串必须与那次 workflow 的 Release tag 完全一致**。
MPV_XCFRAMEWORKS_VERSION=libmpv-ios-0.41.0-ffmpeg7.1

# ⚠️ 占位 —— 必须替换成【我们那次自编】的 sha256（来源二选一）：
#     ① 那次 workflow 的 step summary / 日志里 `===== SHA256: ... =====` 那一行
#     ② 那次 Release 的 notes 里 `sha256：` 那一行
#   没替换的话，下面的 `shasum -a 256 -c` 会**当场校验失败**（这是故意的：宁可构建红掉，
#   也不要静默用错包）。
# ✅ 已回填（2026-10-12）：来源 = 自编 workflow run 38214484349 的日志
#   `===== SHA256: eb31927e…54eb1 =====`（Release `libmpv-ios-0.41.0-ffmpeg7.1`，资产 21,001,770 B）
MPV_XCFRAMEWORKS_SHA256SUM=eb31927e51099f558d130f418f731cfe3363d7d9edd5e0c735ddbcfa63554eb1

.cache/xcframeworks/libmpv-xcframeworks-${MPV_XCFRAMEWORKS_VERSION}-ios-universal.tar.gz:
	mkdir -p .cache/xcframeworks
	rm -f .cache/xcframeworks/*.tmp .cache/xcframeworks/*-ios-universal.tar.gz
	curl -L \
		https://github.com/wocaoniubi123/KPXX/releases/download/${MPV_XCFRAMEWORKS_VERSION}/libmpv-xcframeworks_${MPV_XCFRAMEWORKS_VERSION}_ios-universal-video-default.tar.gz \
		-o .cache/xcframeworks/libmpv.tar.gz.tmp
	shasum -a 256 -c <<< '${MPV_XCFRAMEWORKS_SHA256SUM}  .cache/xcframeworks/libmpv.tar.gz.tmp'
	mv .cache/xcframeworks/libmpv.tar.gz.tmp .cache/xcframeworks/libmpv-xcframeworks-${MPV_XCFRAMEWORKS_VERSION}-ios-universal.tar.gz
	touch .cache/xcframeworks/libmpv-xcframeworks-${MPV_XCFRAMEWORKS_VERSION}-ios-universal.tar.gz

.cache/xcframeworks/libmpv-xcframeworks-ios-universal.tar.gz: .cache/xcframeworks/libmpv-xcframeworks-${MPV_XCFRAMEWORKS_VERSION}-ios-universal.tar.gz
	rm -f .cache/xcframeworks/libmpv-xcframeworks-ios-universal.tar.gz
	ln -s libmpv-xcframeworks-${MPV_XCFRAMEWORKS_VERSION}-ios-universal.tar.gz .cache/xcframeworks/libmpv-xcframeworks-ios-universal.tar.gz

Frameworks/*.xcframework: .cache/xcframeworks/libmpv-xcframeworks-ios-universal.tar.gz
	mkdir -p Frameworks
	rm -rf Frameworks/*.xcframework
	tar -xvf .cache/xcframeworks/libmpv-xcframeworks-ios-universal.tar.gz --strip-components 1 -C Frameworks
	touch Frameworks/*.xcframework

Frameworks/.symlinks: Frameworks/*.xcframework
	rm -rf Frameworks/.symlinks
	mkdir -p Frameworks/.symlinks/mpv
	sed -i '' 's/\r$$//g' create_framework_symlinks.sh # remove CRLF line terminator added by Flutter packaging (https://github.com/media-kit/media-kit/issues/338)
	sh create_framework_symlinks.sh Frameworks/Mpv.xcframework Frameworks/.symlinks/mpv

.PHONY: clean
clean:
	rm -rf .cache
	rm -f ./Headers/mpv/*.h
	rm -rf ./Frameworks/*.xcframework
