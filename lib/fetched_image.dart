import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as im;

import 'base/image_cache.dart';
// ★ 2026-10-05（用户拍板"甲"✓）：本地插件（iOS 侧 ImageIO 解 AVIF ⇒ PNG ✓；非 iOS/解不出 ⇒ null ✓）
import 'package:kp_avif/kp_avif.dart';
import 'config.dart';
import 'settings.dart'; // ★ 热点守卫用 ✓（`AppSettings.i.logConsole` ✓）

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

  /// ★ 2026-10-05（用户特批 ✓ 本文件唯一一次例外）：**可选**的"尺寸到了"回调 ——
  ///   图**真正解码出像素**时回传一次 `w/h`（= **原图像素** ✓ 不是显示尺寸 ✗）。
  ///   用途：在线图集侧「设为背景」要按**原图**算框 ✓ —— 别在点的那一刻再下一次 + 再解一次 ☠（那就是"慢"的根 ✓）。
  ///   ⚠️ **默认 `null` ⇒ 行为与以前一字不差** ✓（不传 ⇒ 什么都不做 ✓）。
  ///   ⚠️ 尺寸只能这么拿 ✓：`MemoryImage` 的 `resolve` + `ImageStreamListener`（`Image.memory` 内部就是这么解的 ✓）；
  ///      同 bytes 的 `MemoryImage` **相等** ✓ ⇒ 命中 `ImageCache` ⇒ **不二次解码** ✓。
  ///      ⚠️ 例外口径：`Image.memory` 带 `cacheWidth` 时包的其实是 `ResizeImage` ✗（key 不同 ⇒ 可能多一次
  ///      **全尺寸**解码 ✓）；但换来的是 `w/h` = **真原图尺寸** ✓ —— 算框**必须**用它 ✓ 不许用缩小后的 ✗。
  final void Function(int w, int h)? onImageInfo;

  const FetchedImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.memWidth,
    this.onImageInfo,
  });

  /// **预热**（#8 ✓ 用户拍板）：把这张图的字节先抓进内存缓存 ✓ —— **fire-and-forget** ✓、失败静默 ✓。
  /// ⚠️ 自研组件**不会被框架预取** ✗（列表用的是我们自己的 `FetchedImage` ✓）→ 由列表 itemBuilder 顺手调 ✓。
  /// ⚠️ 与"真正显示时"**共用同一个在途 Future** ✓（走 `_inflight` ✓）→ 不会重复下载 ✓。
  /// ★ 诊断用 [index]/[total] 是**可选具名**参数 ✓：不传 = 与老调用点**行为完全一致** ✓（日志里序号显示 `?` ✓）。
  ///   [index] = **被预热那张在列表里的 0 基位次** ✓（如屏幕上第 1 张预热的是第 9 张 ⇒ index = 8 ✓）。
  static void warm(String? url, {int? index, int? total}) =>
      _FetchedImageState.warm(url, index: index, total: total);

  @override
  State<FetchedImage> createState() => _FetchedImageState();
}

class _FetchedImageState extends State<FetchedImage> {
  static final Map<String, Uint8List> _cache = {};
  static final Map<String, Future<Uint8List?>> _inflight = {};
  static const int _maxCache = 400;
  /// #2 ✅（2026-10-03 用户拍板）：内存缓存按**字节**封顶（原来只看张数 ☑️）
  /// **图片内存上限 96MB：实测封面中位 52.1KB（sim-dev 2026-10-04，13 张多站样本）。**
  /// 400 张 × 中位 = 20.3MB；96MB = 400 × 245KB = 中位的 4.7 倍余量，作硬上界防大图爆发。
  /// p90(425.3KB) 满 400 张需 166.1MB、最大(464.8KB) 需 181.6MB —— 不按极端值设（iPhone 有 jetsam 风险）。
  /// 实测最小 4.3KB、最大 464.8KB ✅
  /// ★ 2026-10-05（用户批准 · 内存 · ③a）：**64MB → 96MB** ✅（用户点头 ✅）；同时把**字节闸**从"条数条件"里挪出来 ✅
  ///   —— 原来只有 `_cache.length >= _maxCache`（400 张）时才顺带按字节淘汰 ☑️ ⇒ 不到 400 张时**永不按字节淘汰**（大图只涨不落）。
  static const int _maxBytes = 96 * 1024 * 1024;

  /// ★ 2026-10-05（③a）：`_cache` 当前**总字节**（**增量维护** ✅ 写入 +len、淘汰 -len）——
  ///   不再每次写入都全量累加（那是 O(n) ☑️ 从条件里挪出来后会变成每次写入都跑）。
  static int _cacheBytes = 0;

  /// 按「条数 + 字节」双闸淘汰：**只从头砍最久没用的**，砍到合规为止 ✅
  ///   ⚠️ 两处写入（网络/解密那张、磁盘命中那张）**共用**这一个函数 ✅ ⇒ ③a 的"每次写入后都检查"两处都成立 ✅
  ///   ⚠️ 只计入"实际从 `_cache` 里移除的字节"（`remove` 的返回值 ✅）⇒ 增量口径不会漂。
  /// 返回淘汰张数（给日志用 ✅）。
  static int _evict() {
    var n = 0;
    while (_cache.isNotEmpty &&
        (_cache.length > _maxCache || _cacheBytes > _maxBytes)) {
      _cacheBytes -= _cache.remove(_cache.keys.first)?.length ?? 0;
      n++;
    }
    return n;
  }

  Uint8List? _bytes;
  bool _error = false;

  /// ★ 2026-10-05：尺寸监听的**配对**持有 ☠ —— 加/摘必须成对 ✓（否则每次重建挂一个 ⇒ 泄漏 ✗）。
  ///   同一份字节只挂**一个** ✓（`identical` 判据 ✓）；换字节 / 退出页面都走 [_unwatchSize] ✓。
  ImageStream? _sizeStream;
  ImageStreamListener? _sizeListener;
  Uint8List? _sizeBytes; // 已经挂过监听的那份字节 ✓（同一份 ⇒ 不重复挂 ✗）

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FetchedImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _unwatchSize(); // ☠ 换图先摘旧监听 ✓（配对的那一半 ✓ 不然旧图那个会一直挂着 ✗）
      _bytes = null;
      _error = false;
      _load();
    }
  }

  /// ☠ **必须摘** ✓：不摘 ⇒ `ImageCache` 里那个 completer 一直攥着这个监听 ⇒ 每次重建多一个 ⇒ 泄漏 ✗。
  @override
  void dispose() {
    _unwatchSize();
    super.dispose();
  }

  /// 只对**当前这份字节**挂一次尺寸监听 ✓ —— 在 `build` 里调 ✓（同一份 ⇒ 直接返回 ✓ 不会每帧挂一个 ☠）。
  ///   ⚠️ 挂上后**不在这里等结果** ✓：结果由回调丢到**帧后**处理 ✓（见下面那两行注释 ✓）。
  void _watchSize() {
    // ★ 2026-10-05（用户批准 · 内存 · ③b）：**没人要尺寸就别解** ✅ ——
    //   本函数唯一的产物就是 `widget.onImageInfo`（全仓只有下面回调里那一处消费它 ✅；
    //   真要用尺寸的调用方都显式传了：`online_album_common.dart:174 / :1020` ✅）。
    //   为它 `MemoryImage(b).resolve(...)`（下面那行）会让**同一份字节再全尺寸解码一份**驻留 ☑️
    //   —— 而绘制那边 `Image.memory`（见 `build` 里）本来就会自己解一份 ✅
    //   ⇒ 没传回调就直接返回（不挂监听、不多解一份）。
    if (widget.onImageInfo == null) return;
    final b = _bytes;
    if (b == null || identical(b, _sizeBytes)) return;
    _unwatchSize();
    _sizeBytes = b;
    final stream = MemoryImage(b).resolve(ImageConfiguration.empty);
    var sent = false; // 同一份字节只上报一次 ✗（动图每帧都会回调 ✓）
    final l = ImageStreamListener((info, _) {
      if (sent) return;
      sent = true;
      // ⚠️ **异步再抛** ✗：`addListener` 在"图已经在 `ImageCache` 里"时是**同步**回调 ✓
      //   ⇒ 若直接抛出去，上层在构建期 `setState` 会撞到"构建期间 setState" ☠ ⇒ 一律丢到帧后 ✓
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onImageInfo?.call(info.image.width, info.image.height);
      });
    });
    _sizeStream = stream;
    _sizeListener = l;
    stream.addListener(l);
  }

  /// 摘掉监听 ✓（换字节 / 退出页面都走这里 ✓ —— 配对的那一半 ✓）。重复调也安全 ✓（摘过就是 null ✓）。
  void _unwatchSize() {
    final s = _sizeStream;
    final l = _sizeListener;
    if (s != null && l != null) s.removeListener(l);
    _sizeStream = null;
    _sizeListener = null;
    _sizeBytes = null;
  }

  Future<void> _load() async {
    final url = widget.url;
    final hit = _cache.remove(url);
    if (hit != null) {
      _cache[url] = hit; // #1 LRU ✓：命中挪到队尾（Map 迭代按插入序 ✓）
      // 看：这张图直接命内存缓存（没网、没解密）⇒ 卡顿时先看这里是不是全命中。
      if (AppSettings.i.logConsole) debugPrint('[IMG] 命内存 host=${Uri.tryParse(url)?.host ?? '?'}');
      setState(() => _bytes = hit);
      return;
    }
    // ⭐ 磁盘缓存（2026-10-03 用户拍板 #7 ✓）：冷启动的第一张图走这里 ✓ ——
    // 命中就是**解密后的明文** ✓ → 不再下载、不再跑 `compute` 解密 isolate ✓（`_fetchAndDecode:147-150`）
    await ImageDiskCache.i.init(); // 幂等 ✓
    final disk = ImageDiskCache.i.take(url);
    if (disk != null) {
      _cache[url] = disk; // 顺手进内存缓存 ✅
      // ★ 2026-10-05（③a）：磁盘命中也是"写入" ⇒ 走同一套「条数 + 字节」双闸 ✅
      _cacheBytes += disk.length;
      _evict();
      // 看：这张图命中磁盘缓存（冷启动第一张常走这里）⇒ 没有下载、没有解密。
      if (AppSettings.i.logConsole) debugPrint('[IMG] 命磁盘 字节=${disk.length} host=${Uri.tryParse(url)?.host ?? '?'}');
      if (!mounted) return;
      setState(() => _bytes = disk);
      return;
    }
    // 看：这张图要走网络（内存/磁盘都没命中）⇒ 卡图/限流都从这里开始。
    if (AppSettings.i.logConsole) {
      final uri = Uri.tryParse(url);
      final pathOnly = uri == null ? url : '${uri.scheme}://${uri.host}${uri.path}';
      debugPrint('[IMG] 取数 host=${uri?.host ?? '?'} path=${pathOnly.length <= 80 ? pathOnly : pathOnly.substring(0, 80)}');
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
  static void warm(String? url, {int? index, int? total}) {
    if (url == null || url.isEmpty) return;
    if (_cache.containsKey(url)) return;
    // 看：预热发起了哪一张图（序号/总数 + host + path 截 80）—— 与"取数"那几条对着看就是预热命中率。
    //   ⚠️ 原来只打 host ⇒ 同 CDN 的 8 张缩略图会连出 8 条一模一样的行、分不出是哪张（用户实报 ✓）。
    if (AppSettings.i.logConsole) {
      final uri = Uri.tryParse(url);
      final pathOnly = uri == null ? url : '${uri.scheme}://${uri.host}${uri.path}';
      debugPrint('[IMG] 预热 ${index == null || total == null ? '?' : '${index + 1}/$total'} '
          'host=${uri?.host ?? '?'} path=${pathOnly.length <= 80 ? pathOnly : pathOnly.substring(0, 80)}');
    }
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
    // ★ 2026-10-05【临时 1 行】取数结果（开关那套做好前先落这一行 ✓ 只加不删 ✓ 定位后删本行即可 ✓）
    // ★ 2026-10-05【治刷屏】：只在**取数异常**时打一行 ✓（原来每张都打 ☠）—— 定位取数失败就够用了
    if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
      if (AppSettings.i.logConsole) debugPrint('[IMG] 取数异常 code=${r.statusCode} host=${u.host} len=${r.bodyBytes.length}');
      return null;
    }
    final raw = r.bodyBytes;
    // ★ 2026-10-05【真凶修复】：**AVIF/HEIF 头必须在解密之前判** ✗ —— 原来 `_looksLikeImage(raw)` 不认 AVIF
    //   ⇒ AVIF 被当"密文"送去 AES 解密 ⇒ 解出来是垃圾 ⇒ 品牌判断永远拿不到 `ftyp` ⇒ 图空白 ☠（`lib/online_album2_avif.dart:32-33` 同一判据 ✓）
    //   ⚠️ 非 AVIF ⇒ `rawIsAvif` 为假 ⇒ `||` 短路 ⇒ 下面原路**零变化** ✓
    final rawBrand = (raw.length >= 12 &&
            raw[4] == 0x66 && raw[5] == 0x74 && raw[6] == 0x79 && raw[7] == 0x70)
        ? String.fromCharCodes(raw.sublist(8, 12))
        : '';
    final rawIsAvif = rawBrand == 'avif' ||
        rawBrand == 'avis' ||
        rawBrand == 'heic' ||
        rawBrand == 'heix' ||
        rawBrand == 'mif1' ||
        rawBrand == 'msf1';
    Uint8List? img;
    if (rawIsAvif || _looksLikeImage(raw)) {
      img = raw; // AVIF/HEIF 头 ✓、或未加密的真图（不是 AES 密文）✓
    } else if (_isIco(raw)) {
      img = _icoToPng(raw); // 站点 favicon：ICO 解成 PNG
    } else {
      // AES-CBC 解密是纯 Dart 计算，一张图几百 KB~几 MB。
      // 直接在 UI isolate 里做：详情页十几张图同时下完时会整页卡住
      // （视频是平台层在播所以还在动，界面却点不动）→ 丢到后台 isolate。
      // ★【常驻诊断】解密前后各一行 ✓ 只打长度/host ✓（进出都是同一函数 ⇒ isolate 里失败也能从"解出长度"看出来 ✓）
      if (AppSettings.i.logConsole) debugPrint('[IMG] 解密前 len=${raw.length} host=${Uri.tryParse(url)?.host ?? '?'}');
      img = await compute(_decryptInIsolate, raw);
      if (AppSettings.i.logConsole) debugPrint('[IMG] 解密后 len=${img?.length ?? -1} host=${Uri.tryParse(url)?.host ?? '?'}');
    }
    // ★ 2026-10-05（用户拍板"**甲**"✓）：**AVIF ⇒ 走本地插件解成 PNG** ✗ —— 判据极窄（只看头 12 字节 ✓）；
    //   ⚠️ **解不出 / 返回 null / 抛异常 ⇒ 一律原样回落** ✓：`img` 不动 ⇒ 下面护栏照旧判 ⇒ **绝不报错或空白** ☠
    if (img != null &&
        img.length >= 12 &&
        img[4] == 0x66 && img[5] == 0x74 && img[6] == 0x79 && img[7] == 0x70) {
      final brand = String.fromCharCodes(img.sublist(8, 12));
      if (brand == 'avif' ||
          brand == 'avis' ||
          brand == 'heic' ||
          brand == 'heix' ||
          brand == 'mif1' ||
          brand == 'msf1') {
        // ★【常驻诊断·★】AVIF 原生解码结果（**返回 null = 解不出** ⇒ 后面会被护栏拦下 ⇒ 走占位 ✓）
        final png = await KpAvif.decodeToPng(img);
        if (AppSettings.i.logConsole) {
          debugPrint('[IMG] AVIF品牌=$brand 解码=${png == null ? 'null ✗（原生解不出）' : '${png.length}B ✓'} '
          'host=${Uri.tryParse(url)?.host ?? '?'}');
        }
        if (png != null) img = png; // 成功才顶替 ✓（失败 ⇒ 保持原字节 ✓）
      }
    }
    if (img == null || !_looksLikeImage(img)) {
      if (AppSettings.i.logConsole) {
        debugPrint('[IMG] 被护栏拦下（img=${img == null ? 'null' : '${img.length}B'} 非可解图）⇒ 走占位 '
        'host=${Uri.tryParse(url)?.host ?? '?'}');
      }
      return null;
    }
    // ⭐ 落盘（只存**真图** ✓：明文 ✓、原子改名 ✓、失败静默 ✓）
    ImageDiskCache.i.put(url, img);
    // ★【常驻诊断】落盘 + 内存缓存（只打长度/条数 ✓ 不打 URL ✓）
    if (AppSettings.i.logConsole) {
      debugPrint('[IMG] 落盘+入内存缓存 len=${img.length} 缓存条数=${_cache.length + 1} '
      'host=${Uri.tryParse(url)?.host ?? '?'}');
    }
    // ★ 2026-10-05（用户批准 · 内存 · ③a）：**字节闸从"条数条件"里挪出来** ✅ ——
    //   原来外面套着 `if (_cache.length >= _maxCache)`（400 张）⇒ 不到 400 张就**永不按字节淘汰** ☑️
    //   （大图场景内存只涨不落）。现在**每次写入后**都走双闸 ✅（[`_evict`] ✅ 只从头砍最久没用的）；
    //   ⚠️ 字节改为**增量维护**（`_cacheBytes` ✅）⇒ 每次写入 O(1)（原来是每次全量累加、O(n) ☑️）。
    _cacheBytes += img.length; // 本次要写入的那张（下面淘汰完才落进 `_cache` ✅）
    _cache[url] = img;
    final evicted = _evict(); // ★【常驻诊断】只计数 ✅ 不改淘汰规则
    // ★【常驻诊断】只在**真淘汰过**时打（条数上限 $_maxCache / 字节上限 $_maxBytes ✅）
    //   ⚠️ 原来这条只可能在"≥400 张"时打；现在挪到每次写入 ⇒ 必须加 `evicted > 0` 守卫，免得刷屏 ☑️
    if (AppSettings.i.logConsole && evicted > 0) {
      debugPrint('[IMG] LRU 淘汰 $evicted 张 ⇒ 剩=${_cache.length} 张 剩字节=$_cacheBytes');
    }
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
    // ★ 2026-10-05：只对**当前这份字节**挂一次尺寸监听 ✓（同一份 ⇒ 直接返回 ✓ 不会每帧挂一个 ☠）；
    //   ⚠️ 回调**不在构建期**发生 ✓（`_watchSize` 里丢到帧后 ✓）⇒ 上层 `setState` 不会撞构建期 ☠。
    _watchSize();
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
