import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as im;

import 'base/image_cache.dart';
import 'config.dart';

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

  /// **预热**（#8 ✓ 用户拍板）：把这张图的字节先抓进内存缓存 ✓ —— **fire-and-forget** ✓、失败静默 ✓。
  /// ⚠️ 自研组件**不会被框架预取** ✗（列表用的是我们自己的 `FetchedImage` ✓）→ 由列表 itemBuilder 顺手调 ✓。
  /// ⚠️ 与"真正显示时"**共用同一个在途 Future** ✓（走 `_inflight` ✓）→ 不会重复下载 ✓。
  static void warm(String? url) => _FetchedImageState.warm(url);

  @override
  State<FetchedImage> createState() => _FetchedImageState();
}

class _FetchedImageState extends State<FetchedImage> {
  static final Map<String, Uint8List> _cache = {};
  static final Map<String, Future<Uint8List?>> _inflight = {};
  static const int _maxCache = 400;
  /// #2 ✓（2026-10-03 用户拍板）：内存缓存按**字节**封顶 ✗（原来只看张数 ✗）
  /// **图片内存上限 64MB：实测封面中位 52.1KB（sim-dev 2026-10-04，13 张多站样本）。**
  /// 400 张 × 中位 = 20.3MB；64MB = 400 × 164KB = 中位的 3 倍余量，作硬上界防大图爆发。
  /// p90(425.3KB) 满 400 张需 166.1MB、最大(464.8KB) 需 181.6MB —— 不按极端值设（iPhone 有 jetsam 风险）。
  /// 实测最小 4.3KB、最大 464.8KB ✓
  static const int _maxBytes = 64 * 1024 * 1024;

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
    final hit = _cache.remove(url);
    if (hit != null) {
      _cache[url] = hit; // #1 LRU ✓：命中挪到队尾（Map 迭代按插入序 ✓）
      setState(() => _bytes = hit);
      return;
    }
    // ⭐ 磁盘缓存（2026-10-03 用户拍板 #7 ✓）：冷启动的第一张图走这里 ✓ ——
    // 命中就是**解密后的明文** ✓ → 不再下载、不再跑 `compute` 解密 isolate ✓（`_fetchAndDecode:147-150`）
    await ImageDiskCache.i.init(); // 幂等 ✓
    final disk = ImageDiskCache.i.take(url);
    if (disk != null) {
      _cache[url] = disk; // 顺手进内存缓存 ✓
      if (!mounted) return;
      setState(() => _bytes = disk);
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

  /// 预热（#8 ✓）：已有就跳过 ✓、否则挂进 `_inflight` ✓（= 与真正显示时同一个请求 ✓）
  static void warm(String? url) {
    if (url == null || url.isEmpty) return;
    if (_cache.containsKey(url)) return;
    _inflight.putIfAbsent(url, () => _download(url));
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
    // Referer 统一用「图片自身的域名」（同播放器的铁律）：写死某个站的 Referer
    // 会被别的图床拒——实测 hanime1 的 hembed 图床见到 51cg1 的 Referer 直接
    // 403（自家域名/不带 = 200），App 里表现为"图标和封面不显示"。
    final u = Uri.parse(url);
    final ref = (u.hasScheme && u.host.isNotEmpty)
        ? '${u.scheme}://${u.host}/'
        : 'https://51cg1.com/';
    final r = await Site.httpClient
        .get(u, headers: {
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
          'Referer': ref,
          'Accept': 'image/*,*/*;q=0.8',
        })
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
    final raw = r.bodyBytes;
    Uint8List? img;
    if (_looksLikeImage(raw)) {
      img = raw; // 未加密（不是 AES 密文 ✓）
    } else if (_isIco(raw)) {
      img = _icoToPng(raw); // 站点 favicon：ICO 解成 PNG
    } else {
      // AES-CBC 解密是纯 Dart 计算，一张图几百 KB~几 MB。
      // 直接在 UI isolate 里做：详情页十几张图同时下完时会整页卡住
      // （视频是平台层在播所以还在动，界面却点不动）→ 丢到后台 isolate。
      img = await compute(_decryptInIsolate, raw);
    }
    if (img == null || !_looksLikeImage(img)) return null;
    // ⭐ 落盘（只存**真图** ✓：明文 ✓、原子改名 ✓、失败静默 ✓）
    ImageDiskCache.i.put(url, img);
    if (_cache.length >= _maxCache) {
      // #1+#2 ✓：LRU（命中已挪队尾 ✓）+ 字节封顶 → **只从头砍最久没用的**，砍到合规为止 ✗
      // （原来一次丢 100 张 ✗ → 屏幕上的图会被丢 → 立刻重下 + 重解密 ✗）
      var totalBytes = 0;
      for (final v in _cache.values) {
        totalBytes += v.length;
      }
      while (_cache.isNotEmpty &&
          (_cache.length > _maxCache || totalBytes > _maxBytes)) {
        totalBytes -= _cache.remove(_cache.keys.first)?.length ?? 0;
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
      // 解密失败（不是 AES 密文，或不是图片格式 ✓），交回上层判断
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
