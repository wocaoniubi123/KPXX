import 'dart:async';

import '../models.dart';

/// **片源共享缓存**（`url → sources` ✓）—— 用户 2026-10-03 定：**点卡片那一刻就预热第 0 条的源** ✓
///
/// 为什么要有它：以前这份缓存是 `ShortsFeedPage` 的 **State 私有**字段 ✗
/// （旧的 `_srcCache` / `_fetching`）—— 网格在"点卡片"时抓到的源**进不了页面** ✗ →
/// 页面进 `initState` 只好**再抓一次详情页** ✗ = 白等 1~2 秒（用户实测"点进来要好几秒才有画面"✗）。
///
/// 现在两边都走这里 ✓：
/// - 入口（网格点卡片）先 `get(...)` 发起一次 ✓（与转场动画重叠 ✓）；
/// - 页面 `get(...)` 直接拿到**在途的那个 Future** ✓ → **同一个 url 只飞一次** ✓（在途去重 ✓）。
///
/// ⚠️ 与站点无关 ✓（所以进底座 ✓）：**怎么取源**由调用方传进来的闭包决定 ✓
/// （`Api.detail` 那一套留在调用方 ✓，这里不认识任何站点 ✓）。
class SourceCache {
  SourceCache._();

  static final SourceCache i = SourceCache._();

  /// 上限（LRU ✓）—— 只存 `url → 源地址`，很轻 ✓（短片一次会话够用 ✓，绝不让它无界增长 ✗）
  static const int maxEntries = 80;

  /// Dart 的 Map 是**插入有序** ✓ → 命中时 remove + set 就把它挪到队尾 ✓（LRU 用 ✓）
  final Map<String, Future<List<String>>> _map = {};

  /// 取源：命中 / 在途 → 返回**同一个 Future** ✓；没有才发起一次 ✓
  /// ⚠️ **失败不进缓存** ✗（否则这一次的失败会一直粘着 ✗，用户再滑也拿不到源 ✓）
  Future<List<String>> get(String url, Future<List<String>> Function() fetch) {
    final hit = _map.remove(url);
    if (hit != null) {
      _map[url] = hit; // LRU：挪到队尾 ✓
      return hit;
    }
    final f = fetch().catchError((Object _) {
      _map.remove(url);
      return const <String>[];
    });
    _map[url] = f;
    while (_map.length > maxEntries) {
      _map.remove(_map.keys.first); // 淘汰最久没用的 ✓
    }
    return f;
  }

  /// 详情 → 片源（**唯一**一份规则 ✓：页面与入口共用，别各自抄一份 ✗）
  static List<String> sourcesOfDetail(ArticleDetail d) =>
      d.videos.isNotEmpty ? d.videos.first.sources : const <String>[];
}
