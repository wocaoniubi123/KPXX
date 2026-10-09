/// ★ 2026-10-10（**dev 专用** ✓ 用户拍板）：给 `hanime1.me` 开的 **HTTP/2 取回通道**。
///
/// 背景（实锤 ✓）：同一 IP、同一 UA —— `curl` 200 / 桌面 `dart:io`（HTTP/1.1）403；用户换出口
/// 节点后 `dart:io` 依然 403 ⇒ 是**客户端指纹**（HTTP/1.1 + dart 的握手特征）被站点的 WAF 挑 ✓
/// ⇒ 用**真正的 h2 + ALPN 协商**（浏览器同款路径）绕过去 ✓；播放源不受影响（CDN77 三方全通 ✓）。
///
/// ⚠️ **只在 Windows dev 生效**：本文件只被 `lib/main_win_dev.dart` import ✓（iOS 构建不含它 ✓），
///   且只在非 iOS 的 `_makeClient()` 回落成 `http.Client()` 时才可能被装上 ✓。
/// ⚠️ 这里硬编码了站名 —— 按仓规"站点逻辑只在 sites/<站名>.dart"这本不该 ✗，但这是**dev 专用
///   桌面通道**（不进 iOS 包、不改站点文件 ✓），是 lead/用户明确拍板的例外 ✓。要再加站点就往
///   [hosts] 里加 ✓（别把它挪进底座 ✗）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint; // ★ 只取 debugPrint（不引 material ✓）
import 'package:http/http.dart' as http;
import 'package:http2/transport.dart';

import 'config.dart';
import 'settings.dart';

class DevHanimeH2Client extends http.BaseClient {
  DevHanimeH2Client(this._inner);

  /// 委托目标：**原来的** client（桌面 = `IOClient(HttpClient())` ✓）——其它 host 原样走它 ✓
  final http.Client _inner;

  /// 走 h2 的 host 白名单（**只有这些** ✓）
  static const Set<String> hosts = <String>{'hanime1.me'};

  /// 现有取数的头（与 `base/fetch.dart:61-69` 保持一致 ✓，改那边时这里要跟着改 ✓）
  static const String _accept =
      'text/html,application/xhtml+xml;application/json;q=0.9,*/*;q=0.8';

  /// 客户端侧兜底超时（外层 `fetch.dart` 自己还有 8s ✓ ⇒ 这里给 8s 只是**双保险** ✓）
  static const Duration _timeout = Duration(seconds: 8);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!hosts.contains(request.url.host)) {
      return _inner.send(request); // ★ 别的 host：原样委托 ✓（`abs()` 打 CDN 也走这里 ✓）
    }
    try {
      return await _overH2(request).timeout(_timeout);
    } catch (e) {
      // ⚠️ 一律**抛 `http.ClientException`**（与 IOClient 网络失败同类 ✓）：
      //   `fetch.dart:87` 那句裸 `catch (_) ⇒ break` 会接住它 ⇒ 走既有"换域名"逻辑 ✓
      //   ⇒ **绝不崩** ✓；非 200 那条路则**不进这里**（正常返回响应，交给 fetch 的 4xx/5xx 逻辑 ✓）。
      if (AppSettings.i.logConsole) {
        debugPrint('[WIN-DEV-H2] hanime1 走 h2 失败 ⇒ 交给上层换域名/重试：$e');
      }
      throw http.ClientException('h2 fetch failed: $e', request.url);
    }
  }

  Future<http.StreamedResponse> _overH2(http.BaseRequest request) async {
    final uri = request.url;
    final socket = await SecureSocket.connect(
      uri.host,
      443,
      supportedProtocols: const <String>['h2'], // ★ 只允许 h2 ⇒ 才能验证"真的协商到了" ✓
      timeout: _timeout,
    );
    // ★ **必须验证 ALPN 结果**：没协商到 h2 就别硬发（否则又是 HTTP/1.1 指纹 ⇒ 白搭 + 难排查 ✓）
    if (socket.selectedProtocol != 'h2') {
      socket.destroy();
      throw const HttpException('ALPN 未协商到 h2（selectedProtocol 为空或其它）');
    }
    final transport = ClientTransportConnection.viaSocket(socket);
    try {
      // `:path` 必须是**编码后**的 ASCII 形态（h2 头只允许 ASCII ✓）⇒ 用 `Uri` 重新编码一遍 ✓
      final path = Uri(
        path: uri.path,
        query: uri.query.isEmpty ? null : uri.query,
      ).toString();
      final stream = transport.makeRequest(<Header>[
        Header.ascii(':method', request.method),
        Header.ascii(':scheme', 'https'),
        Header.ascii(':authority', uri.host),
        Header.ascii(':path', path),
        Header.ascii('user-agent', Site.ua),
        Header.ascii('accept', _accept),
        Header.ascii('referer', 'https://${uri.host}/'),
        // ★ 取**不压缩**（`fetch.dart` 会直接 `utf8.decode(bodyBytes)` ⇒ 压缩字节会解析成乱码 ☠）；
        //   但仍会检测 gzip 魔数兜底（万一站点无视 identity ✓ 见下）
        Header.ascii('accept-encoding', 'identity'),
      ], endStream: true);

      final bytes = <int>[];
      var status = 0;
      final respHeaders = <String, String>{};
      await for (final event in stream.incomingMessages) {
        if (event is HeadersStreamMessage) {
          for (final h in event.headers) {
            final name = utf8.decode(h.name, allowMalformed: true).toLowerCase();
            final value = utf8.decode(h.value, allowMalformed: true);
            if (name == ':status') {
              status = int.tryParse(value) ?? 0;
            } else {
              respHeaders[name] = value;
            }
          }
        } else if (event is DataStreamMessage) {
          bytes.addAll(event.bytes);
        }
      }
      if (status == 0) throw const HttpException('h2 响应里没有 :status');
      // 兜底：站点无视 identity 回了 gzip ⇒ 自己解（`1f 8b` 魔数 ✓）
      var body = bytes;
      if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        try {
          body = gzip.decode(bytes);
          if (AppSettings.i.logConsole) {
            debugPrint('[WIN-DEV-H2] 站点无视 identity 回了 gzip ⇒ 已自行解压 '
                '${bytes.length}→${body.length}B');
          }
        } catch (_) {
          // 解不开就用原字节（上层会 `utf8.decode` ⇒ 显式失败比静默乱码更好排查 ✓）
        }
      }
      if (AppSettings.i.logConsole) {
        debugPrint('[WIN-DEV-H2] hanime1 h2 成功 ALPN=${socket.selectedProtocol} '
            'code=$status len=${body.length}B');
      }
      return http.StreamedResponse(Stream<List<int>>.value(Uint8List.fromList(body)),
          status,
          headers: respHeaders, request: request);
    } finally {
      unawaited(transport.finish().catchError((Object _) {}));
      socket.destroy();
    }
  }
}
