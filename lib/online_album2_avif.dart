import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kp_avif/kp_avif.dart';

import 'config.dart';

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
  static Future<Uint8List?> fetch(String url) async {
    final cached = _mem[url];
    if (cached != null) return cached;
    try {
      final r = await Site.httpClient
          .get(Uri.parse(url), headers: <String, String>{'User-Agent': Site.ua})
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return null;
      final raw = r.bodyBytes;
      var bytes = raw;
      if (looksAvif(raw)) {
        final png = await KpAvif.decodeToPng(raw);
        if (png == null) {
          // 解不出（老系统 / 插件没进包 / 非 AVIF 变体）⇒ 记一行 ✓ 返回 null ⇒ 显示占位 ✓ 不崩 ✗
          debugPrint('kp_avif 解不出（${_short(url)}）：长度 ${raw.length} ✓');
          return null;
        }
        bytes = png;
      }
      _mem[url] = bytes;
      return bytes;
    } catch (e) {
      debugPrint('图集2 取图失败（${_short(url)}）：$e');
      return null;
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
