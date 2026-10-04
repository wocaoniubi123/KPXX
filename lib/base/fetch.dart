// 取数底座 —— **与站点无关**的公共部分 ✓
//
// ⚠️ 用户 2026-10-03 决策：**站点相关的一切改成站点独立** ✓（分类/子分类/多级分类/
//    标签选择器/重置按钮/选中状态/取数解析），但**底座保持公用** ✓ ——
//    否则 13 个站各写一份超时重试，早晚有一份忘了设（表现就是**永久转圈** ✗）。
//
// 本文件是从 `api.dart` 的 `Api` 里**原样搬**出来的（**行为不变** ✓，**没有重写** ✗）：
//   · `_fetchText`    → `text()`   域名轮换 + 5xx 重试一次 + 8 秒超时 + UTF-8 解码
//   · `_fetchAbs`     → `abs()`    绝对地址（跨域），Referer 用该地址自己的域名，拿不到返回空串
//   · `_client`       → `client`   iOS = NSURLSession（见 config.dart，铁律 3）
//   · `hosts`/`host` → `hosts`/`host`（含"上次跑通的域名排最前"）
//
// ⚠️ **不要往这里加任何"某站怎么办"的分支** ✗ —— 那些一律写进 `lib/sites/<站点>.dart` ✓。

import 'dart:convert';
import '../site_error_log.dart';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../sites.dart';

class SiteFetcher {
  SiteFetcher(this.site)
      : hosts = site.hosts,
        host = site.hosts.isNotEmpty ? site.hosts.first : '';

  final SiteEntry site;
  final List<String> hosts;
  String host;

  /// 共享客户端（iOS = NSURLSession，见 config.dart 的 Site.httpClient）
  static final http.Client _client = Site.httpClient;


  /// 当前正在用的域名（"上次跑通的那个"）。**可写** —— 有几个站的解析里会配合切换。


  /// 给少数需要在 `Api` 里直接用裸 client 的地方留的口子（2048/2277 行那两处）。
  http.Client get client => _client;

  /// 顺序尝试域名，返回第一个成功的文本。
  /// 上次跑通的域名排最前：站点常有一两个域名挂掉，若每次从列表头开始试，
  /// 每个请求都要先白等一次超时（列表/详情/视频启动全被拖慢）。
  Future<String> text(String path,
      {Map<String, String>? extraHeaders}) async {
    final order = [
      if (hosts.contains(host)) host,
      ...hosts.where((h) => h != host),
    ];
    for (final h in order) {
      // 5xx 是站点偶发（51fans1 实测会间歇性 500），同一个域名再试一次
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final r = await _client.get(
            Uri.parse('https://$h$path'),
            headers: {
              'User-Agent': Site.ua,
              'Referer': 'https://$h/',
              'Accept':
                  'text/html,application/xhtml+xml;application/json;q=0.9,*/*;q=0.8',
              ...?extraHeaders,
            },
          ).timeout(const Duration(seconds: 8));
          if (r.statusCode == 200) {
            host = h;
            return utf8.decode(r.bodyBytes);
          }
          if (r.statusCode < 500) break; // 4xx 重试没用，直接换域名
        } catch (e, st) {

          // ✅ 公共错误日志：时间 + 站点名 + 错误 ✓（用户 2026-10-03 要求）

          await SiteErrorLog.log(site.name, e, st);
          // 超时/连接失败：不再重试同域名，换下一个
          break;
        }
      }
    }
    throw Exception('所有域名均无法访问');
  }

  /// 绝对地址请求（跨域，如麻豆社详情页里 dash.madou.club 的视频分享页）。
  /// 同样走 [Site.httpClient]（iOS = NSURLSession）；Referer 用**该地址自身的域名**
  /// （视频源域名，不是站点域名）；拿不到就返回空串（调用方当"没有源"，不抛异常）。
  Future<String> abs(String url) async {
    try {
      final u = Uri.parse(url);
      final r = await _client.get(u, headers: {
        'User-Agent': Site.ua,
        'Referer': '${u.scheme}://${u.host}/',
        'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
      }).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return '';
      return utf8.decode(r.bodyBytes);
    } catch (e, st) {

      // ✅ 公共错误日志：时间 + 站点名 + 错误 ✓（用户 2026-10-03 要求）

      await SiteErrorLog.log(site.name, e, st);
      return '';
    }
  }

  /// HLS master 列表 → 各档地址（**高 → 低** 排序；单档列表返回 null）✓
  /// ⚠️ 2026-10-03 从 `api.dart` 搬到此处：它**会发网络请求**（拉 master）✓，
  /// 属于底座 ✓ —— xHamster 与其它站点的详情解析都要用 ✓（原先在 `Api` 里私有，
  /// 而 xHamster 已独立成文件 → 跨文件调不到 ✗，所以上移并公开 ✓）。
  /// 原注释：2026-10-02 改 —— 原来只留最高档（`_pickTopHlsVariant`），现在**全留着**
  /// 给详情页的「清晰度」行选 —— 顺序仍是"最高档在最前"，所以**默认播最高档**这点没变 ✓。
  Future<List<String>?> hlsVariants(String masterUrl) async {
    try {
      final mu = Uri.parse(masterUrl);
      final r = await _client
          .get(mu, headers: {
            'User-Agent': Site.ua,
            'Referer': '${mu.scheme}://${mu.host}/',
            'Accept-Language': 'zh-CN,zh;q=0.9',
          })
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      final text = utf8.decode(r.bodyBytes);
      if (!text.contains('#EXT-X-STREAM-INF')) return null; // 单档列表
      final lines = const LineSplitter().convert(text);
      final found = <MapEntry<int, String>>[]; // 分 → 子列表地址
      for (var i = 0; i + 1 < lines.length; i++) {
        if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
        final res = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(lines[i]);
        final bw = int.tryParse(
                RegExp(r'BANDWIDTH=(\d+)').firstMatch(lines[i])?.group(1) ??
                    '') ??
            0;
        final score = res == null
            ? bw
            : int.parse(res.group(1)!) * int.parse(res.group(2)!);
        final uri = lines[i + 1].trim();
        if (uri.isEmpty || uri.startsWith('#')) continue;
        final abs = mu.resolve(uri).toString();
        if (found.any((f) => f.value == abs)) continue;
        found.add(MapEntry(score, abs));
      }
      if (found.isEmpty) return null;
      found.sort((a, b) => b.key.compareTo(a.key)); // 高 → 低
      return [for (final f in found) f.value];
    } catch (e, st) {

      // ✅ 公共错误日志：时间 + 站点名 + 错误 ✓（用户 2026-10-03 要求）

      await SiteErrorLog.log(site.name, e, st);
      return null;
    }
  }

}
/// 秒数 → 时钟文本（`207` → `3:27`；`0`/非法 → 空串）✓
/// ⚠️ 2026-10-03 从 `api.dart` 上移：**多个站点共用**（Pektino ×3 / 黄果 ×2 / 另有 1 处）✓，
/// 而各站已拆成独立文件 → 跨文件调不到 ✗，所以上移并公开 ✓。
/// 接口里的时长是秒（字符串或数字）：207 → 3:27
String secClock(String raw) {
  final sec = int.tryParse(raw.trim());
  if (sec == null || sec <= 0) return '';
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}
