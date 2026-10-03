// kmsvip —— **本站专属**的一切 ✓
//
// ⚠️ 用户 2026-10-03 决策：取消全站共享，站点相关的一切改成站点独立专属 ✓；底座保持公用 ✓。
// 由 `tools/mover3.js` 从 `api.dart` 的 `Api` 里**原样搬**出（**不重写逻辑** ✓ 行为不变 ✓），
// 仅做等价替换：`_fetchText(`→`_f.text(`、`_secClock(`→`secClock(` 等 ✓；入口方法改名为公开 ✓。
// ⚠️ import 由脚本按**代码里实际用到的符号**推导 ✓（不是手写的 ✓）。

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import '../base/fetch.dart';
import '../config.dart';
import '../models.dart';

/// kmsvip 本站专属实现（取数走公用底座 [SiteFetcher] ✓）
class KmSite {
  KmSite(this._f);

  final SiteFetcher _f;

  /// 本站**没有搜索功能**（照站点实况 ✓；原 `Api.search` 的 case body 原样搬来 ✓）
  Future<List<Article>> search(String keyword, {required int page}) async =>
      throw Exception('该站点没有搜索功能');

  /// 本站没有标签功能（原 `Api.tag` 的 case body 原样搬来 ✓）
  Future<List<Article>> tag(String slug, {required int page}) async => const [];

  /// 首页 = listHot（原 `Api.home` 的 case body 原样搬来 ✓）
  Future<List<Article>> home({required int page}) =>
      list('/api/videos/listHot', page: page);

  /// 「分类」tab 的列表（本站专属 ✓ —— 原 `Api.category` 里的 case body 原样搬来 ✓）
  /// key = 站点 type：'0' 热门视频（listHot）/ '1' 视频广场（listAll）✓
  Future<List<Article>> category(String key, {required int page}) =>
      list(key == '1' ? '/api/videos/listAll' : '/api/videos/listHot', page: page);
  static final _kmAes =
      Encrypter(AES(Key(utf8.encode('625202f9149maomi')), mode: AESMode.cbc));
  static final _kmIv = IV(utf8.encode('5efd3f6060emaomi'));

  String _kmHex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();

  /// hex → 字节。encrypt 包的 Encrypted 要 Uint8List（不是 List<int>）
  Uint8List _kmBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i + 1 < hex.length; i += 2) {
      out[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return out;
  }

  /// 快猫的加密 API：请求体 JSON → AES-128-CBC（Pkcs7）→ 大写 HEX；form 编码
  /// POST `data=<hex>&sig=<md5('data=<hex>maomi_pass_xyz')>`；响应同密钥密文 →
  /// 解密成 JSON。站点有访客态接口（不用登录），md5 用 crypto 包。
  Future<Map<String, dynamic>> _kmPost(
      String path, Map<String, dynamic> body) async {
    final hex = _kmHex(
        _kmAes.encryptBytes(utf8.encode(jsonEncode(body)), iv: _kmIv).bytes);
    final sig =
        md5.convert(utf8.encode('data=$hex' 'maomi_pass_xyz')).toString();
    final order = [
      if (_f.hosts.contains(_f.host)) _f.host,
      ..._f.hosts.where((h) => h != _f.host),
    ];
    for (final h in order) {
      try {
        final r = await _f.client
            .post(
              Uri.parse('https://$h$path'),
              headers: {
                'User-Agent': Site.ua,
                'Referer': 'https://$h/',
                'Origin': 'https://$h',
                'Accept-Language': 'zh-CN,zh;q=0.9',
                'Content-Type':
                    'application/x-www-form-urlencoded; charset=UTF-8',
              },
              body: 'data=$hex&sig=$sig',
            )
            .timeout(const Duration(seconds: 10));
        if (r.statusCode != 200) continue;
        _f.host = h;
        final plain = _kmAes.decryptBytes(
            Encrypted(_kmBytes(utf8.decode(r.bodyBytes).trim())),
            iv: _kmIv);
        return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      } catch (_) {
        // 换下一个域名
      }
    }
    throw Exception('请求失败');
  }

  /// 快猫列表：listHot（热门视频）/ listAll（视频广场），19 条/页、页码从 1 起。
  /// 卡片：竖版封面、标题、发布时间（用户要求不显示作者名），角标 = 点赞数（♡N）；
  /// is_cat_ads=1 是广告位（站点本会跳外链），跳过。
  Future<List<Article>> list(String api, {int page = 1}) async {
    final j = await _kmPost(api, {'perPage': 19, 'page': page});
    if (j['code'] != 0) return const [];
    final data = j['data'];
    final list =
        (data is Map ? (data['list'] ?? const []) : const []) as List;
    final out = <Article>[];
    for (final v in list) {
      if (v is! Map) continue;
      if ((v['is_cat_ads'] ?? 0) == 1) continue;
      final id = (v['mv_id'] ?? '').toString();
      if (id.isEmpty) continue;
      final created = (v['mv_created'] ?? '').toString();
      out.add(Article(
        title: (v['mv_title'] ?? '').toString(),
        url: id,
        cover: (v['mv_img_url'] ?? '').toString(),
        // 用户要求：不显示作者名，只留发布时间（"09-29 18:12"）
        meta: created.length >= 16 ? created.substring(5, 16) : created,
        badge: '♡${v['mv_like'] ?? 0}',
      ));
    }
    return out;
  }

  /// 快猫详情：/api/videos/detail（必须带 uId——站点访客默认 60364099，不带会报
  /// "用户未登录"）。播放地址取详情里的 **https 直链**（列表中那份是 http://IP/…
  /// 形式，iOS ATS 不允许 http，且从开发机实测不可达）。
  Future<ArticleDetail> detail(String url) async {
    final j =
        await _kmPost('/api/videos/detail', {'mvId': url, 'uId': '60364099'});
    final data = j['data'];
    final d = data is Map ? data : const <dynamic, dynamic>{};
    final play = (d['mv_play_url'] ?? '').toString();
    final cover = (d['mv_img_url'] ?? '').toString();
    return ArticleDetail(
      title: (d['mv_title'] ?? '').toString(),
      time: (d['mv_created'] ?? '').toString(),
      categories: const [],
      images: cover.isEmpty ? const [] : [cover],
      intro: '',
      videos: [
        if (play.isNotEmpty)
          ArticleVideo(label: '视频', ordinal: 1, sources: [play]),
      ],
      tags: const [],
      related: const [],
      seriesPrefix: '',
    );
  }
}
