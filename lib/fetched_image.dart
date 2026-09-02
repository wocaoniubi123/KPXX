import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// 网络图片加载（绕过 Flutter 默认网络图片对 Content-Type 的校验）。
/// 站点图片响应头是 binary/octet-stream，Image.network/CachedNetworkImage 会拒绝，
/// 这里用 http 下载字节后 Image.memory 解码（按字节魔数，不看 Content-Type），并做内存缓存。
class FetchedImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final int? memWidth; // 解码宽度，<原图尺寸可省内存
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
  static const int _maxCache = 400; // 简单上限，超出全部清空防止内存膨胀

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
    final f = _inflight.putIfAbsent(url, _download);
    final bytes = await f;
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _error = true);
    } else {
      setState(() => _bytes = bytes);
    }
  }

  static Future<Uint8List?> _download(String url) async {
    try {
      final r = await http
          .get(Uri.parse(url), headers: {
            'User-Agent':
                'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
            'Referer': 'https://51cg1.com/',
            'Accept': 'image/*,*/*;q=0.8',
          })
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
        if (_cache.length >= _maxCache) _cache.clear();
        _cache[url] = r.bodyBytes;
        return r.bodyBytes;
      }
    } catch (_) {
      // 网络失败，走 error 分支
    } finally {
      _inflight.remove(url);
    }
    return null;
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
