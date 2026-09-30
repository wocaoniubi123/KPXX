import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as im;
import 'package:http/http.dart' as http;

/// 是不是 ICO（站点 favicon 都是 ICO：头 00 00 01 00）
bool _isIco(Uint8List b) =>
    b.length > 6 && b[0] == 0 && b[1] == 0 && b[2] == 1 && b[3] == 0;

/// ICO → PNG。Flutter 的解码器不认识 ICO，而站点 favicon 都是 ICO
/// （实测是 ICO 内嵌 BMP），所以用纯 Dart 的 image 包解码后重新编码成
/// PNG 再交给 Flutter。解不出来返回 null（上层会走占位图）。
///
/// ⚠️ 多尺寸 ICO（如黄果的 16/32/48 三帧）会被 decodeIco 解成"多帧图像"，
/// 而 encodePng 对多帧会输出**动画 PNG（APNG，写 acTL/fcTL 帧控制块）**——
/// Flutter 的 Image 会把它当动画循环播放（帧尺寸还不一致）→ 首页图标
/// 一闪一闪（2026-09-30 用户实报，对照 image 包源码确认）。
/// 这里只取**面积最大的一帧**转单帧 PNG，保证是静图。
/// 单帧 ICO（其余站点）走同一段逻辑，行为不变。
Uint8List? _icoToPng(Uint8List b) {
  try {
    final img = im.decodeIco(b);
    if (img == null) return null;
    var best = img;
    for (final f in img.frames) {
      if (f.width * f.height > best.width * best.height) best = f;
    }
    return Uint8List.fromList(im.encodePng(best));
  } catch (_) {
    return null;
  }
}

/// 给 compute 用的解密入口（后台 isolate 只能调顶层/静态函数）
Uint8List? _decryptInIsolate(Uint8List raw) => _FetchedImageState._decrypt(raw);

/// 网络图片加载。
/// 站点图片下载下来是 AES-CBC 加密的二进制密文（密钥/IV 与该站网页端一致的公开参数），
/// 需解密后才得到真实图片（jpeg/png/gif/webp）。这里下载→（必要时）解密→Image.memory，
/// 并做内存缓存。解密后的图片字节按魔数校验，确保只向解码器投递真图片。
class FetchedImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final int? memWidth;
  const FetchedImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.memWidth,
  });

  @override
  State<FetchedImage> createState() => _FetchedImageState();
}

class _FetchedImageState extends State<FetchedImage> {
  static final Map<String, Uint8List> _cache = {};
  static final Map<String, Future<Uint8List?>> _inflight = {};
  static const int _maxCache = 400;

  Uint8List? _bytes;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FetchedImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _bytes = null;
      _error = false;
      _load();
    }
  }

  Future<void> _load() async {
    final url = widget.url;
    final hit = _cache[url];
    if (hit != null) {
      setState(() => _bytes = hit);
      return;
    }
    final f = _inflight.putIfAbsent(url, () => _download(url));
    final bytes = await f;
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _error = true);
    } else {
      setState(() => _bytes = bytes);
    }
  }

  /// 偶发失败（本地代理超时、图床限流、密文被截断）重试一次就好；
  /// 失败结果不写缓存 → 下次进这个页面会自动再试。
  static Future<Uint8List?> _download(String url) async {
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
        try {
          final img = await _fetchAndDecode(url);
          if (img != null) return img;
        } catch (_) {
          // 这次失败，循环里再试一次
        }
      }
      return null;
    } finally {
      _inflight.remove(url);
    }
  }

  static Future<Uint8List?> _fetchAndDecode(String url) async {
    final r = await http
        .get(Uri.parse(url), headers: {
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
          'Referer': 'https://51cg1.com/',
          'Accept': 'image/*,*/*;q=0.8',
        })
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
    final raw = r.bodyBytes;
    Uint8List? img;
    if (_looksLikeImage(raw)) {
      img = raw; // 未加密（可能是站外图）
    } else if (_isIco(raw)) {
      img = _icoToPng(raw); // 站点 favicon：ICO 解成 PNG
    } else {
      // AES-CBC 解密是纯 Dart 计算，一张图几百 KB~几 MB。
      // 直接在 UI isolate 里做：详情页十几张图同时下完时会整页卡住
      // （视频是平台层在播所以还在动，界面却点不动）→ 丢到后台 isolate。
      img = await compute(_decryptInIsolate, raw);
    }
    if (img == null || !_looksLikeImage(img)) return null;
    if (_cache.length >= _maxCache) {
      // 只淘汰最早的一批（Map 迭代按插入序 ≈ FIFO）。整片 clear 会让
      // 已经在屏幕上的图全部重新下载一遍，看起来就是"列表又变慢了"。
      for (final k in _cache.keys.take(_maxCache ~/ 4).toList()) {
        _cache.remove(k);
      }
    }
    _cache[url] = img;
    return img;
  }

  /// AES-128-CBC 解密（PKCS7 padding），兼容"密文"与"密文的 Base64 文本"两种形态。
  static Uint8List? _decrypt(Uint8List raw) {
    try {
      final encrypter = enc.Encrypter(
        enc.AES(
          enc.Key.fromUtf8('f5d965df75336270'),
          mode: enc.AESMode.cbc,
        ),
      );
      final iv = enc.IV.fromUtf8('97b60394abc2fbe1');
      // 形态1：直接二进制密文
      if (raw.length % 16 == 0) {
        final out = Uint8List.fromList(
          encrypter.decryptBytes(enc.Encrypted(raw), iv: iv));
        if (_looksLikeImage(out)) return out;
      }
      // 形态2：Base64 文本密文（去掉空白后解码再解密）
      try {
        final txt = utf8.decode(raw, allowMalformed: true).trim();
        final b64 = base64Decode(txt.replaceAll(RegExp(r'\s+'), ''));
        if (b64.length % 16 == 0) {
          final out = Uint8List.fromList(
            encrypter.decryptBytes(enc.Encrypted(b64), iv: iv));
          if (_looksLikeImage(out)) return out;
        }
      } catch (_) {
        // 非 base64 形态
      }
    } catch (_) {
      // 解密失败（该图可能未加密/其他格式），交回上层判断
    }
    return null;
  }

  /// 常见图片格式魔数校验
  static bool _looksLikeImage(Uint8List b) {
    if (b.length < 12) return false;
    if (b[0] == 0xFF && b[1] == 0xD8) return true; // JPEG
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return true; // PNG
    }
    final s = String.fromCharCodes(b.sublist(0, 6));
    if (s.startsWith('GIF8')) return true; // GIF
    if (s.startsWith('RIFF') &&
        String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') {
      return true; // WebP
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: widget.fit,
        gaplessPlayback: true,
        cacheWidth: widget.memWidth,
        errorBuilder: (_, __, ___) => const _Placeholder(error: true),
      );
    }
    return _Placeholder(error: _error);
  }
}

class _Placeholder extends StatelessWidget {
  final bool error;
  const _Placeholder({this.error = false});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFEEEEEE),
      child: Center(
        child: error
            ? const Icon(Icons.broken_image, color: Colors.black26, size: 28)
            : const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
      ),
    );
  }
}
