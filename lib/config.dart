import 'dart:io' show Platform;

import 'package:cupertino_http/cupertino_http.dart';
import 'package:http/http.dart' as http;

/// 通用网络配置。
/// 站点清单（域名、分类）已挪到 lib/sites.dart，这里只留各站点共用的请求头。
class Site {
  static const String ua =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  /// 全 App 共用的 HTTP 客户端：**iOS 用 NSURLSession**（cupertino_http）——
  /// 与 Safari 同一条系统网络栈：读系统的 Wi-Fi 代理 / VPN 配置、支持 HTTP/2。
  /// dart:io 的 HttpClient 默认 "DIRECT"、**不读系统代理**：手机上挂着代理才
  /// 能打开的站（如 hanime1.me），浏览器能开、App 却直连被墙——2026-10-01 实锤
  /// （同一套请求头：走代理 200 / 直连 000）。其它平台/异常时退回默认客户端。
  /// ★ 2026-10-10（**dev 接缝** ✓ 用户拍板）：原来的 `static final httpClient` 拆成下面三行 ——
  ///   ① `_baseClient` = 原逻辑**一字不动** ✓；② `devClientOverride` = **只有 Windows dev 入口会设** ✓；
  ///   ③ `httpClient` = getter：非空优先用覆盖件 ✓。
  ///   ✅ **iOS 零影响**：全仓赋值点扫描 = **0 处**（只有读取 ✓ ⇒ iOS 取值恒为 `_baseClient`
  ///      ⇒ 行为**逐字节不变** ✓）。覆盖件用法见 `lib/main_win_dev_h2.dart`（只对 `hanime1.me` 走
  ///      h2 通道、其余 host 原样委托回 `_baseClient` ✓）。
  static final http.Client _baseClient = _makeClient();
  static http.Client? devClientOverride;
  static http.Client get httpClient => devClientOverride ?? _baseClient;

  static http.Client _makeClient() {
    if (Platform.isIOS) {
      try {
        return CupertinoClient.defaultSessionConfiguration();
      } catch (_) {}
    }
    return http.Client();
  }
}
