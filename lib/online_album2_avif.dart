import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kp_avif/kp_avif.dart';

import 'config.dart';
import 'settings.dart'; // ★ 诊断守卫（`AppSettings.i.logConsole` ✓）；`debugPrint` 由 material 带入 ✓
import 'online_album_common.dart'; // ★ C ✓：尺寸表 `AlbumImageSizes`（只记 Size ✗ 不留字节 ✓）

/// 「在线图集2」**专用的 AVIF 兜底层**（photos18 的封面与详情图**全是 `.avif`** ✓ 实测 ✓）。
///
/// ⚠️ **只在图集2 这条线里用** ✗ —— **不碰任何公共件** ☠（`fetched_image.dart` / `online_album_common.dart`
///   一个字都没动 ✓ 别的站点/图集一律照旧 ✓）。
/// ⚠️ 本机**无 Flutter SDK / 无 Xcode** ⇒ 本文件与插件的**编译、Swift 语法、ImageIO 实际行为**
///   **一律只能 CI / 真机验** ✗（报告里已逐条标 ✗ 不许当成"已验证" ✓）。
class AvifBytes {
  /// 解码结果缓存：`url → 可直接给 `Image.memory` 的字节` ✓
  /// —— **选内存 Map 的依据**（最简 ✓）：图集2 一次进页最多几十张 ✓；这张表随进程走 ✓
  ///   不落盘 ⇒ 不引入文件缓存/清理逻辑 ✗（YAGNI ✓）；下次冷启动重解一遍可接受 ✓。
  static final Map<String, Uint8List> _mem = <String, Uint8List>{};

  /// 魔数判定 ✓：偏移 4 = `ftyp` ✓，紧随其后的 brand ∈ {avif, avis, heic, heix, mif1, msf1} ✓
  ///   （依据 = 我探站抓到的前 16 字节：`00 00 00 20 66 74 79 70 61 76 69 66` ⇒ `ftypavif` ✓）。
  /// **同步**取已缓存的"可直接渲染字节"（命中 ⇒ 立刻渲染 ✓；未命中 ⇒ `null` ✓）。
  ///   ⚠️ 与 [fetch] **共用同一个 `_mem`** ✓ ⇒ **同一张图只解一次** ✓（用户点破那条 ✓：
  ///   预览里那几张就是详情页**已经解好并缓存**的 ✓ ⇒ 零额外网络、零额外解码 ✓）。
  static Uint8List? cached(String url) => _mem[url];

  static bool looksAvif(Uint8List b) {
    if (b.length < 12) return false;
    if (b[4] != 0x66 || b[5] != 0x74 || b[6] != 0x79 || b[7] != 0x70) return false; // ftyp
    final brand = String.fromCharCodes(b.sublist(8, 12));
    return brand == 'avif' || brand == 'avis' || brand == 'heic' ||
        brand == 'heix' || brand == 'mif1' || brand == 'msf1';
  }

  /// 取字节 ⇒ （**是 AVIF** ⇒ 走本地插件解成 PNG ✓ / **不是** ⇒ 原字节照旧 ✓）。
  /// ⚠️ 失败 ⇒ `null` ✓（不抛 ✗）；`Site.httpClient` 是**仓库既有**的网络件 ✓ 不自造下载器 ✗。
  /// ★ 2026-10-05（用户要求 ✓）：失败 ⇒ **立刻重试** ✗ —— 上限 **3 次** ✓ 间隔 **200 / 400ms** ✓（递进 ✓ 短 ✓）；
  ///   覆盖两条 ✓：**取图**（非 200 / 抛异常 ✓）+ **AVIF 解码**（`png == null` ✓）；**静默** ✓ 不弹错 ✗；
  ///   ⚠️ 仍失败 ⇒ `null` ⇒ 上层**现有占位** ✓（**不加"重试按钮"** ✗ —— 靠下拉刷新 / 重进 ✓ 用户口径 ✓）。
  static Future<Uint8List?> fetch(String url) async {
    final cached = _mem[url];
    if (cached != null) return cached;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(
            Duration(milliseconds: attempt == 1 ? 200 : 400));
      }
      try {
        final r = await Site.httpClient
            .get(Uri.parse(url), headers: <String, String>{'User-Agent': Site.ua})
            .timeout(const Duration(seconds: 20));
        if (r.statusCode != 200) continue; // ① 取图失败 ⇒ 重试 ✓
        final raw = r.bodyBytes;
        var bytes = raw;
        if (looksAvif(raw)) {
          final png = await KpAvif.decodeToPng(raw);
          // ★【常驻诊断·⑧】AVIF 原生解码结果（null = 解不出 ⇒ 会重试 ✓；与 `fetched_image` 那条同口径 ✓）
          if (AppSettings.i.logConsole) {
            debugPrint('[AVIF] 解码=${png == null ? 'null ✗（原生解不出）' : '${png.length}B ✓'} '
            '原图=${raw.length}B 第${attempt + 1}次');
          }
          if (png == null) continue; // ② AVIF 解码失败 ⇒ 重试 ✓（老系统 / 插件没进包 / 非 AVIF 变体 ✓）
          bytes = png;
        }
        _mem[url] = bytes;
        // ★ C ✓：解出来那一刻**顺手**把原图尺寸记进表 ✓（不额外下载 ✗ 不再解一遍 ✓ "同一张只解一次" ✓）
        _rememberSize(url, bytes);
        return bytes;
      } catch (e) {
        if (AppSettings.i.logConsole) debugPrint('图集2 取图失败（第 ${attempt + 1} 次，${_short(url)}）：$e');
      }
    }
    if (AppSettings.i.logConsole) debugPrint('图集2 取图最终失败（已重试 3 次，${_short(url)}）⇒ 显示占位 ✓');
    return null;
  }

  /// ★ 2026-10-05（C ✓ 用户要求"点了立刻出框选"）：把**原图像素尺寸**顺手记进 `AlbumImageSizes` ✓ ——
  ///   机制与 `FetchedImage.onImageInfo` **同一套** ✓：`MemoryImage` + `ImageStreamListener`；
  ///   同 bytes 的 `MemoryImage` **相等** ⇒ 命中 `ImageCache` ⇒ **不二次解码** ✓（拿的是**真原图**尺寸 ✓）。
  ///   ☠ 加/摘成对 ✓：拿到就**摘**，但**不在回调里当场摘** ✗（回调期间改监听集合有风险 ☠）⇒ 延到**帧后**摘 ✓。
  ///   ⚠️ 失败/抛异常 ⇒ 静默 ✓（框选那边有"尺寸未知"的兜底 ✓ **绝不崩** ✗）。
  static void _rememberSize(String url, Uint8List bytes) {
    try {
      final stream = MemoryImage(bytes).resolve(ImageConfiguration.empty);
      late final ImageStreamListener l;
      l = ImageStreamListener((info, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          stream.removeListener(l); // ☠ 配对的那一半 ✓（延到帧后 ✓）
        });
        AlbumImageSizes.put(url, info.image.width, info.image.height);
      });
      stream.addListener(l);
    } catch (e) {
      if (AppSettings.i.logConsole) debugPrint('图集2 记尺寸失败（不影响显示 ✓）：$e');
    }
  }

  static String _short(String u) => u.length <= 60 ? u : '${u.substring(0, 60)}…';
}

/// 图集2 专用图片件：**AVIF 也能显示** ✓（其余行为与 `FetchedImage` 保持同款口径 ✓：
///   `Image.memory` + `cacheWidth: memWidth` + `fit` ✓）。失败 ⇒ **占位方块 + 图标** ✓ **不崩** ✗。
class AvifImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final int memWidth;

  const AvifImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.memWidth = 480,
  });

  @override
  State<AvifImage> createState() => _AvifImageState();
}

class _AvifImageState extends State<AvifImage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await AvifBytes.fetch(widget.url);
    if (!mounted) return;
    setState(() {
      _bytes = b;
      _failed = b == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    if (_failed) {
      // 占位：灰底 + 图标 ✓（沿用仓库列表里那种 `Icons.broken_image` 的口径 ✓）
      return const ColoredBox(
        color: Color(0xFFECEFF3),
        child: Center(child: Icon(Icons.broken_image, color: Color(0xFF9AA0A6))),
      );
    }
    if (b == null) {
      return const ColoredBox(
        color: Color(0xFFECEFF3),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Image.memory(
      b,
      fit: widget.fit,
      cacheWidth: widget.memWidth,
      gaplessPlayback: true,
    );
  }
}
