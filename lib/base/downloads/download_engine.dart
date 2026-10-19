// 离线下载 —— 下载引擎（纯 Dart：只依赖 dart:io / dart:convert / http / encrypt / 本仓 config）。
//
// 为什么单独一层、且这一层**不打日志**：
// · 管理器 `DownloadManager` 才依赖 Flutter（ChangeNotifier / debugPrint），引擎保持纯
//   Dart ⇒ 可以拿普通 `dart run` 脚本直接跑真实下载做自测，不必为了一个下载器拉起 Flutter；
// · 日志统一由管理器按 `AppSettings.i.logConsole` 开关打 ⇒ 这个文件里没有任何
//   可能把 cookie / 完整签名 URL 写出去的打印点，从源头上少一个泄密面。
//
// 两种形态（入口按 URL 后缀 + 响应 content-type 自动判）：
// · 直链 mp4：流式写 `<baseName>.mp4.part`；`.part` 已存在就发 `Range` 续传；下完改名
// · HLS m3u8：master 挑 BANDWIDTH 最大的变体 → 解析媒体清单 → 4 并发拉分片
//   → AES-128-CBC 解密（有 KEY 时）→ 按清单顺序拼成 `<baseName>.ts`
//
// 为什么中断保留 `.part`、只有"明确失败"才删：
// 下载是"用户等很久"的操作，网络抖一下就丢掉几十 MB 很浪费。直链下次能用 Range
// 从原地续；HLS 顺序拼接没有可靠的断点偏移，下次整条重来，但留个半成品至少能看出
// "下到哪一步断的"。取消（用户主动）保留、异常（源站/磁盘出错）删除。

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:http/http.dart' as http;

import '../../config.dart';

/// 用户主动取消（或任务被移除）。管理器据此把该集标成 `paused`，**不算失败**。
class DownloadCancelled implements Exception {
  const DownloadCancelled();

  @override
  String toString() => '已取消（保留 .part，下次可续）';
}

/// 真失败：HTTP 状态码、源站返回空、加解密不支持等，都带一句人话原因。
class DownloadException implements Exception {
  final String reason;

  const DownloadException(this.reason);

  @override
  String toString() => '下载失败：$reason';
}

class DownloadEngine {
  DownloadEngine._();

  /// HLS 分片并发数（用户拍板 4）。再高对源站不友好，也更容易被 CDN 限速。
  static const int segmentConcurrent = 4;

  /// 单片失败重试次数（不含第一次）。分片是"整条里的一小段"，重试成本低。
  static const int segmentRetries = 2;

  /// 建连 / 拿响应头的超时；分片体下载用更长的 [_timeoutChunk]
  static const Duration timeoutConnect = Duration(seconds: 20);
  static const Duration timeoutChunk = Duration(seconds: 60);

  /// master 嵌套跟随上限（正常就 1 层；给 3 层是防"变体清单里还是 master"的怪站）
  static const int _masterDepthMax = 3;

  /// 下载 [url] 到 `destDir/<baseName>.mp4`（直链）或 `.ts`（HLS）。
  ///
  /// [headers] 由调用方给（UA 本方法补、站点额外头如 Cookie/Referer 原样带上）；
  /// [onProgress] 的 `total` 在直链没给 Content-Length 时是 0，HLS 是估算值；
  /// [isCancelled] 在每片/每块前后轮询，返回 true ⇒ 抛 [DownloadCancelled]；
  /// [client] 可注入：**下载 worker 的 isolate 里必须传纯 `http.Client()`** ——
  ///   `Site.httpClient` 在 iOS 是 `cupertino_http`，在 isolate 里初始化有风险；
  ///   不传则退回全局客户端（普通调用方/自测脚本用）。
  ///
  /// 返回：落地后的完整文件路径（`.part` 已改名）。
  static Future<String> download({
    required String url,
    Map<String, String>? headers,
    required String destDir,
    required String baseName,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
    http.Client? client,
  }) async {
    final c = client ?? Site.httpClient;
    final dir = Directory(destDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      throw const DownloadException('URL 不合法');
    }
    if (uri.path.toLowerCase().endsWith('.m3u8')) {
      return _downloadHls(
        url: url,
        headers: headers,
        destDir: destDir,
        baseName: baseName,
        onProgress: onProgress,
        isCancelled: isCancelled,
        client: c,
      );
    }
    return _downloadDirect(
      url: url,
      headers: headers,
      destDir: destDir,
      baseName: baseName,
      onProgress: onProgress,
      isCancelled: isCancelled,
      client: c,
    );
  }

  // -------------------------------------------------------------------------
  // 直链
  // -------------------------------------------------------------------------

  static Future<String> _downloadDirect({
    required String url,
    required Map<String, String>? headers,
    required String destDir,
    required String baseName,
    required void Function(int done, int total)? onProgress,
    required bool Function()? isCancelled,
    required http.Client client,
    bool freshRetry = false,
  }) async {
    final dest = File('$destDir/$baseName.mp4');
    final part = File('$destDir/$baseName.mp4.part');
    // 已经下完（重复点、失败重试的幂等出口）：直接还现有文件
    if (await dest.exists()) return dest.path;

    var existing = 0;
    if (!freshRetry) {
      try {
        if (await part.exists()) existing = await part.length();
      } catch (_) {
        existing = 0; // 读不到大小 ⇒ 当没下过（最坏是白下一遍）
      }
    }

    final req = http.Request('GET', Uri.parse(url));
    _applyHeaders(req, headers);
    if (existing > 0) req.headers['Range'] = 'bytes=$existing-';
    final resp = await client.send(req).timeout(timeoutConnect);

    // 没有 .m3u8 后缀、但响应头说是 HLS 的站（少见，但省得用户手动判断）
    final ct = (resp.headers['content-type'] ?? '').toLowerCase();
    if (ct.contains('mpegurl')) {
      final text = utf8.decode(await _readAll(resp), allowMalformed: true);
      return _downloadHls(
        url: url,
        headers: headers,
        destDir: destDir,
        baseName: baseName,
        playlistText: text,
        onProgress: onProgress,
        isCancelled: isCancelled,
        client: client,
      );
    }

    if (resp.statusCode == 416 && existing > 0) {
      // `.part` 比远端还大 / 远端文件换了 ⇒ Range 不成立，丢掉重来一次
      try {
        await part.delete();
      } catch (_) {}
      return _downloadDirect(
        url: url,
        headers: headers,
        destDir: destDir,
        baseName: baseName,
        onProgress: onProgress,
        isCancelled: isCancelled,
        client: client,
        freshRetry: true,
      );
    }

    final isPartial = resp.statusCode == 206;
    final isFull = resp.statusCode == 200;
    if (!isPartial && !isFull) throw DownloadException('HTTP ${resp.statusCode}');

    // 只有"真续传"才 append；服务器没理 Range（回了 200）就从 0 重写
    final append = isPartial && existing > 0;
    final start = append ? existing : 0;
    final len = resp.contentLength;
    final total = len == null ? 0 : start + len;

    final raf = await part.open(mode: append ? FileMode.append : FileMode.write);
    var done = start;
    try {
      await for (final chunk in resp.stream.timeout(timeoutChunk)) {
        if (_cancelled(isCancelled)) throw const DownloadCancelled();
        if (chunk.isEmpty) continue;
        await raf.writeFrom(chunk);
        done += chunk.length;
        onProgress?.call(done, total);
      }
      await raf.flush();
    } finally {
      await raf.close();
    }

    // 整份下完才改名：半截文件对播放器没意义（mp4 的 moov 可能在尾部）
    if (await dest.exists()) {
      try {
        await dest.delete();
      } catch (_) {}
    }
    await part.rename(dest.path);
    onProgress?.call(done, done);
    return dest.path;
  }

  // -------------------------------------------------------------------------
  // HLS
  // -------------------------------------------------------------------------

  static Future<String> _downloadHls({
    required String url,
    required Map<String, String>? headers,
    required String destDir,
    required String baseName,
    required void Function(int done, int total)? onProgress,
    required bool Function()? isCancelled,
    required http.Client client,
    String? playlistText,
  }) async {
    if (_cancelled(isCancelled)) throw const DownloadCancelled();

    var mediaUrl = url;
    var text = playlistText ?? await _getText(url, headers, client);

    // master：选 BANDWIDTH 最大的变体（用户口径"清晰度优先"）
    for (var depth = 0; depth < _masterDepthMax; depth++) {
      if (!text.contains('#EXT-X-STREAM-INF')) break;
      final variants = _parseVariants(text);
      if (variants.isEmpty) {
        throw const DownloadException('master 里没有可用的变体行');
      }
      var best = variants.first;
      for (final v in variants) {
        if (v.bandwidth > best.bandwidth) best = v;
      }
      mediaUrl = Uri.parse(mediaUrl).resolve(best.uri).toString();
      text = await _getText(mediaUrl, headers, client);
    }
    if (text.contains('#EXT-X-STREAM-INF')) {
      throw const DownloadException('m3u8 嵌套超过 $_masterDepthMax 层，放弃');
    }

    final segs = _parseMedia(text);
    if (segs.isEmpty) throw const DownloadException('m3u8 里解析不出分片');

    final part = File('$destDir/$baseName.ts.part');
    final prog = File('$destDir/$baseName.ts.progress');
    final dest = File('$destDir/$baseName.ts');

    // ---- 分片级断点续传（用户要求：「继续」不要整集重下）----
    // 进度文件 = {"segs":总片数,"done":已落盘片数,"bytes":已落盘字节}。
    // 片数对不上 / 进度文件坏 / .part 比"已落盘字节"还短 ⇒ 全部作废，从头来（旧行为）。
    final resume = await _readHlsProgress(prog, segs.length, part);
    if (resume == null) {
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
      try {
        if (await prog.exists()) await prog.delete();
      } catch (_) {}
    }
    final doneFrom = resume?.done ?? 0;
    var doneBytes = resume?.bytes ?? 0;
    var doneSegs = doneFrom;
    // HLS 没有 Content-Length ⇒ 总字节只能估，且**一次算定不跳动**：
    // · 全新下载：首片字节 × 总片数（首片落盘前 total = 0）
    // · 续传：已下片的平均大小 × 总片数（同样从头到尾不变）
    var totalBytes = doneFrom > 0 ? (doneBytes ~/ doneFrom) * segs.length : 0;

    final raf = await part.open(
      mode: doneFrom > 0 ? FileMode.append : FileMode.write,
    );
    final keyCache = <String, Uint8List>{};
    try {
      var start = doneFrom;
      while (start < segs.length) {
        final end = math.min(start + segmentConcurrent, segs.length);
        final futures = <Future<Uint8List>>[];
        for (var i = start; i < end; i++) {
          futures.add(_fetchSegment(
            segment: segs[i],
            base: mediaUrl,
            headers: headers,
            isCancelled: isCancelled,
            keyCache: keyCache,
            client: client,
          ));
        }
        final window = await Future.wait(futures);
        // 并发完成顺序不可靠，落盘必须按清单顺序
        for (var i = start; i < end; i++) {
          if (_cancelled(isCancelled)) throw const DownloadCancelled();
          final data = window[i - start];
          if (data.isEmpty) {
            throw DownloadException('第 ${i + 1}/${segs.length} 片为空');
          }
          await raf.writeFrom(data);
          doneBytes += data.length;
          doneSegs++;
          if (totalBytes == 0) {
            // 首片到手 ⇒ 锁定总大小（之后不再重算，避免"总大小"跳动）
            totalBytes = data.length * segs.length;
          }
          // 每落一片更新断点文件（不 flush：掉电最多丢一格，重下一片而已）
          await _writeHlsProgress(prog, segs.length, doneSegs, doneBytes);
          onProgress?.call(doneBytes, totalBytes);
        }
        start = end;
      }
      await raf.flush();
    } catch (e) {
      try {
        await raf.close();
      } catch (_) {}
      // 取消/失败都**保留** `.part` + 进度文件：下次从断点继续。
      // （最坏情况只浪费"写完但还没记进度"的那一片 —— 续传时会按进度文件把多出的字节截掉）
      rethrow;
    }
    await raf.close();

    if (await dest.exists()) {
      try {
        await dest.delete();
      } catch (_) {}
    }
    await part.rename(dest.path);
    // 完成 ⇒ 进度文件没用了（.part 已被 rename 走）
    try {
      if (await prog.exists()) await prog.delete();
    } catch (_) {}
    // 收尾校正：首片外推只是估计，真实大小 = 已落盘字节（管理器据此把 total 收敛到实数）
    onProgress?.call(doneBytes, doneBytes);
    return dest.path;
  }

  /// 拉一片：带 headers、失败重试 [segmentRetries] 次、有 KEY 就解密。
  /// 分片地址相对 [base]（媒体清单自己的 URL）解析 —— 相对地址在 HLS 里很常见。
  static Future<Uint8List> _fetchSegment({
    required _Segment segment,
    required String base,
    required Map<String, String>? headers,
    required bool Function()? isCancelled,
    required Map<String, Uint8List> keyCache,
    required http.Client client,
  }) async {
    final abs = Uri.parse(base).resolve(segment.uri).toString();
    Uint8List? data;
    Object? last;
    for (var attempt = 0; attempt <= segmentRetries; attempt++) {
      if (_cancelled(isCancelled)) throw const DownloadCancelled();
      try {
        final r = await client
            .get(Uri.parse(abs), headers: headers)
            .timeout(timeoutConnect);
        if (r.statusCode != 200) throw DownloadException('分片 HTTP ${r.statusCode}');
        if (r.bodyBytes.isEmpty) throw const DownloadException('分片为空');
        data = r.bodyBytes;
        break;
      } catch (e) {
        if (e is DownloadCancelled) rethrow;
        last = e;
        if (attempt < segmentRetries) {
          // 递增退避：源站偶发 5xx / 连接被掐时给一点恢复时间
          await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
          if (_cancelled(isCancelled)) throw const DownloadCancelled();
        }
      }
    }
    if (data == null) {
      throw DownloadException('分片重试 $segmentRetries 次仍失败：${last ?? '未知'}');
    }

    final key = segment.key;
    if (key == null) return data; // 明文清单
    final keyBytes = await _keyBytes(key, base, headers, keyCache, client);
    return _decrypt(data, keyBytes, key.iv ?? _defaultIv(segment.seq));
  }

  static Future<Uint8List> _keyBytes(
    _HlsKey key,
    String base,
    Map<String, String>? headers,
    Map<String, Uint8List> cache,
    http.Client client,
  ) async {
    final abs = Uri.parse(base).resolve(key.uri).toString();
    final hit = cache[abs];
    if (hit != null) return hit;
    final r = await client
        .get(Uri.parse(abs), headers: headers)
        .timeout(timeoutConnect);
    if (r.statusCode != 200) throw DownloadException('密钥 HTTP ${r.statusCode}');
    if (r.bodyBytes.length != 16) {
      throw DownloadException('AES-128 密钥长度=${r.bodyBytes.length}（应为 16）');
    }
    cache[abs] = r.bodyBytes;
    return r.bodyBytes;
  }

  /// AES-128-CBC + PKCS7（HLS 的标准做法；`encrypt` 的 AES 默认 padding 就是 PKCS7）
  static Uint8List _decrypt(Uint8List encrypted, Uint8List key, Uint8List iv) {
    if (encrypted.length % 16 != 0) {
      throw DownloadException('AES 密文长度 ${encrypted.length} 不是 16 的倍数');
    }
    try {
      final encrypter = enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.cbc));
      return Uint8List.fromList(
        encrypter.decryptBytes(enc.Encrypted(encrypted), iv: enc.IV(iv)),
      );
    } catch (e) {
      throw DownloadException('AES 解密失败：$e');
    }
  }

  /// 没写 `IV=` 时 HLS 规定用"媒体序号"当 IV（16 字节大端）
  static Uint8List _defaultIv(int seq) {
    final iv = Uint8List(16);
    var v = seq;
    for (var i = 15; i >= 0 && v > 0; i--) {
      iv[i] = v & 0xff;
      v >>= 8;
    }
    return iv;
  }

  // -------------------------------------------------------------------------
  // m3u8 解析
  // -------------------------------------------------------------------------

  static Future<String> _getText(
    String url,
    Map<String, String>? headers,
    http.Client client,
  ) async {
    try {
      final r = await client
          .get(Uri.parse(url), headers: headers)
          .timeout(timeoutConnect);
      if (r.statusCode != 200) throw DownloadException('清单 HTTP ${r.statusCode}');
      if (r.bodyBytes.isEmpty) throw const DownloadException('清单为空');
      return utf8.decode(r.bodyBytes, allowMalformed: true);
    } on DownloadException {
      rethrow;
    } catch (e) {
      throw DownloadException('清单请求异常：$e');
    }
  }

  // -------------------------------------------------------------------------
  // HLS 断点续传（`<base>.ts.progress`）
  // -------------------------------------------------------------------------

  /// 读断点文件并校验。返回 null = 不可信（片数变了 / JSON 坏 / `.part` 比"已落盘字节"还短）⇒ 从头。
  ///
  /// 若 `.part` 比进度记录的字节**多**（上次"写完片、还没来得及记进度"就被杀）：
  /// 把多出来的尾巴截掉 —— 保住前面已经完整的片，丢掉那半片。
  static Future<_HlsResume?> _readHlsProgress(
    File prog,
    int expectSegs,
    File part,
  ) async {
    try {
      if (!await prog.exists() || !await part.exists()) return null;
      final raw = await prog.readAsString();
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final segs = j['segs'];
      final done = j['done'];
      final bytes = j['bytes'];
      if (segs is! int || done is! int || bytes is! int) return null;
      if (segs != expectSegs || done < 0 || done > expectSegs || bytes < 0) {
        return null;
      }
      final len = await part.length();
      if (len < bytes) return null; // 记录说写了更多、文件却更短 ⇒ 整个不可信
      if (len > bytes) {
        try {
          final raf = await part.open(mode: FileMode.append);
          try {
            await raf.truncate(bytes);
          } finally {
            await raf.close();
          }
        } catch (_) {
          return null;
        }
      }
      return _HlsResume(done, bytes);
    } catch (_) {
      return null;
    }
  }

  /// 每落一片写一次断点（`writeAsString` 到 `.tmp` 再改名；不 flush —— 掉电最多重下一片）
  static Future<void> _writeHlsProgress(
    File prog,
    int segs,
    int done,
    int bytes,
  ) async {
    try {
      final tmp = File('${prog.path}.tmp');
      await tmp.writeAsString(
        jsonEncode(<String, int>{'segs': segs, 'done': done, 'bytes': bytes}),
      );
      try {
        if (await prog.exists()) await prog.delete();
      } catch (_) {}
      await tmp.rename(prog.path);
    } catch (_) {
      // 断点文件写失败不能影响下载本身（最坏是下次从头）
    }
  }

  /// master 清单里的变体：`#EXT-X-STREAM-INF` 行给 BANDWIDTH，下一行非注释行给地址
  static List<_Variant> _parseVariants(String text) {
    final out = <_Variant>[];
    final lines = const LineSplitter().convert(text);
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i].trim();
      if (!l.startsWith('#EXT-X-STREAM-INF')) continue;
      final bw = int.tryParse(
            RegExp(r'BANDWIDTH=(\d+)').firstMatch(l)?.group(1) ?? '',
          ) ??
          0;
      for (var j = i + 1; j < lines.length; j++) {
        final t = lines[j].trim();
        if (t.isEmpty || t.startsWith('#')) continue;
        out.add(_Variant(bandwidth: bw, uri: t));
        break;
      }
    }
    return out;
  }

  /// 媒体清单 → 分片列表（每片带上"当时生效的 KEY"）。
  ///
  /// 为什么逐条跟 `#EXT-X-KEY` 而不是只读第一个：
  /// 有的站中途换 key（甚至 `METHOD=NONE` 切回明文），只认第一条会解错后面所有片。
  static List<_Segment> _parseMedia(String text) {
    // byterange：分片是按字节区间切的，跟"整片下载"是两套逻辑；
    // 硬啃容易把偏移算错造成播放异常，这里直接明确拒绝（管理器会标失败并给原因）
    if (text.contains('#EXT-X-BYTERANGE')) {
      throw const DownloadException('不支持 #EXT-X-BYTERANGE（按字节区间切分的清单）');
    }
    var mediaSeq = 0;
    final seqMatch = RegExp(r'#EXT-X-MEDIA-SEQUENCE:(\d+)').firstMatch(text);
    if (seqMatch != null) {
      mediaSeq = int.tryParse(seqMatch.group(1) ?? '') ?? 0;
    }

    final segs = <_Segment>[];
    _HlsKey? key;
    final lines = const LineSplitter().convert(text);
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i].trim();
      if (l.isEmpty) continue;
      if (l.startsWith('#EXT-X-KEY')) {
        key = _parseKey(l); // METHOD=NONE 时返回 null ⇒ 后续片明文
        continue;
      }
      if (!l.startsWith('#EXTINF')) continue;
      for (var j = i + 1; j < lines.length; j++) {
        final t = lines[j].trim();
        if (t.isEmpty || t.startsWith('#')) continue;
        segs.add(_Segment(uri: t, key: key, seq: mediaSeq + segs.length));
        break;
      }
    }
    return segs;
  }

  static _HlsKey? _parseKey(String line) {
    final method =
        RegExp(r'METHOD=([A-Za-z0-9_-]+)').firstMatch(line)?.group(1)?.toUpperCase();
    if (method == null) throw const DownloadException('#EXT-X-KEY 缺 METHOD');
    if (method == 'NONE') return null;
    if (method != 'AES-128') {
      throw DownloadException('不支持的加密方法 $method（目前只做 AES-128）');
    }
    final uri = RegExp(r'URI="([^"]*)"').firstMatch(line)?.group(1);
    if (uri == null || uri.isEmpty) {
      throw const DownloadException('AES-128 的 KEY 缺 URI');
    }
    final ivHex = RegExp(r'IV=0[xX]([0-9a-fA-F]{32})').firstMatch(line)?.group(1);
    return _HlsKey(uri, ivHex == null ? null : _hexToBytes(ivHex));
  }

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // 小工具
  // -------------------------------------------------------------------------

  /// 统一补 UA（站点普遍按 UA 区分移动端），再叠加调用方给的头（同名以调用方为准）
  static void _applyHeaders(http.BaseRequest req, Map<String, String>? headers) {
    req.headers['User-Agent'] = Site.ua;
    req.headers['Accept'] = '*/*';
    if (headers != null) {
      for (final e in headers.entries) {
        req.headers[e.key] = e.value;
      }
    }
  }

  static Future<Uint8List> _readAll(http.StreamedResponse resp) async {
    final buf = BytesBuilder(copy: false);
    await for (final chunk in resp.stream.timeout(timeoutChunk)) {
      buf.add(chunk);
    }
    return buf.takeBytes();
  }

  /// 取消回调本身炸了不能把下载带崩（最差结果是"取消不生效"，比抛异常好）
  static bool _cancelled(bool Function()? f) {
    if (f == null) return false;
    try {
      return f();
    } catch (_) {
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// 解析用的小结构（只在本文件用）
// ---------------------------------------------------------------------------

class _Variant {
  final int bandwidth;
  final String uri;

  const _Variant({required this.bandwidth, required this.uri});
}

class _HlsKey {
  final String uri;

  /// 显式 `IV=0x…`；null ⇒ 用分片序号（`_Segment.seq`，= MEDIA-SEQUENCE + 片号）当默认 IV
  final Uint8List? iv;

  const _HlsKey(this.uri, this.iv);
}

class _Segment {
  final String uri;
  final _HlsKey? key;
  final int seq;

  const _Segment({required this.uri, required this.key, required this.seq});
}

/// HLS 断点状态（来自 `<base>.ts.progress`）
class _HlsResume {
  final int done;
  final int bytes;

  const _HlsResume(this.done, this.bytes);
}
