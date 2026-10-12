// liz01 —— **荔枝短剧（liz01.com）本站专属**的一切 ✅
//
// 站点：`liz01.com`（竖版封面短剧站，3:4 ✅）。**自管整页**（第六个用 `SiteUi.sitePage` 的站点 ✅）。
//
// ---- 🛢️ recon-5 实测 + 本机复核的配方（照抄，别再造）----
//  · **首页**：`GET /` ⇒ 解 `<script id="__NUXT_DATA__">` 的 **Nuxt3 devalue 扁平数组**
//    （与野果同一套：数字=下标引用 ✅ ⇒ 助手函数 [_nuxt]/[_deref]/[_findObj]/[_obj] **逐字复用野果** ✅）
//    分区对象 = 带 `topicName` + `dramas`（+ `title`/`slug`/`homepageSize`）✅
//    实测首页 6 个分区：`【荔枝】最骚原创` / `精选推荐` / `上新必看` / `每日追更` / `贤者时间` / `你来评选` ✅
//    卡字段：`id/title/slug/coverUrl/totalEpisodes/displayViewText/displayViewCount/payMode/coverBadge` ✅
//  · **导航 6 个入口**：首页 `/` · 荔枝原创 `/original/` · 荔枝精选 `/featured/` · 分类 `/category/` ·
//    排行榜 `/rank/week/` · 回家之路 `/road/` ✅
//  · **分页 = 路径式** 🛢️：`/tag/<slug>/page/<n>/`、`/original/page/<n>/`、`/featured/page/<n>/`、
//    `/rank/<period>/page/<n>/` ✅ —— ⚠️ **绝不要用 `?page=`**：会被 CDN 缓存吃掉、**永远回第 1 页** ☠（实测坑 ✅）
//  · **搜索**：`GET /search/<urlencode(关键词)>/` ✅（SSR 里就有结果；页面另有两个 tab，**只做默认综合排序** ☑️）
//  · **详情**：`GET /api/v1/drama/<数字id>` ✅（⚠️ **只认数字 id**，给 slug ⇒ `请求参数错误` ☠）
//    + `GET /api/v1/drama/<id>/episodes` ⇒ `[{epNo,available,episodeId,title,durationSeconds,locked,preview}]` ✅
//  · **取流**：`GET /api/v1/drama/<id>/ep/<n>` ⇒ `data.playbackUrl`（**站内相对路径** ⇒ 必须拼 `https://liz01.com` ✅）
//    + `durationSeconds` ✅；**URL 带 `t`+`sign`、约 30 分钟时效** ⇒ **每次播放现取、绝不缓存** ✅
//    **播放不需要 Referer/Cookie/特殊 UA** 🛢️（实测）⇒ 交给播放器即可 ✅
//  · **锁定集**：按 `locked`/`preview`/`available` 判（抽样 104 部全免费 ✅，但字段在就照字段走 ✅）
//  · **封面**：站点页面里给了 `imageAesKeyHex=ea19c21e85d768da4165f5964ab886b2` /
//    `imageAesIvHex=f4d53ecbc273901e0d9cd7848233c702`，而底座 `fetched_image.dart:372/376` 里**写死的是另一对**
//    （`f5d965df75336270` / `97b60394abc2fbe1`）⇒ **底座那套对本站无效** ☠，而"按站点给 key/iv"要动公共区 ✗
//    ⇒ 首版**原 URL 直连** ☑️ + **TODO：封面解密**（需公共区加"站点专属 key/iv"槽位，见本文件尾 ❓）
//
// ---- ❓ 未验证（不猜，按 TODO 处理）----
//  1. **分类 `/category/` → 剧列表**的地址形态（`/category/392/` 是 404、索引页里没有链接）⇒ **分类 tab 只放提示** ✅
//  2. `/rank/<period>/` 与 `/road/`、`/original/`、`/featured/` 的**列表 blob 形态**：本机没抓（预算用在
//     首页/详情/剧集/取流 4 次上 ✅）⇒ 列表解析用**结构扫描**（找"元素都像卡对象"的第一个数组 ✅ 见 [_scanCards]）
//     并把"字段/结构若不符 ⇒ 空列表 + 日志"写清 ✅，**不猜具体字段名** ✅
//  3. **搜索分页**（`/search/<kw>/page/<n>/`？）⇒ `page > 1` 返回空 + TODO ✅
//  4. **封面解密**（见上）☑️ · **AES-128 TS-HLS 播放**：🔍 推断"播放器（mpv）原生支持"，**本机没做解密播放验证** ☑️
//
// ---- 日志（照本项目口径 ✅）----
//   可以打：剧/集 id、状态码、字节数、条数、耗时、Δ 时长 ✅；⚠️ **绝不打带 `sign` 的地址、不打 cookie** ☠

import 'dart:async'; // ★ unawaited（预热队列入队即走 ✅）
import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/material.dart';

import '../app_background.dart';
import '../app_bg.dart'; // ★ 顶部 tab 的选中色要跟着明暗翻 ⇒ 要 AppBg ✅（照野果 ✅）
import '../base/fetch.dart';
import '../base/image_cache.dart'; // ★ 封面预热要写磁盘缓存（公开 API ✅ 零公共区改动 ✅）
import '../base/site_ui.dart';
import '../config.dart' show Site;
import '../detail_page.dart'; // ★ 点卡 ⇒ 通用详情页（照野果模式 ✅）
import '../fetched_image.dart';
import '../home_page.dart' show SearchPage; // ★ 顶栏搜索入口用**底座通用搜索页**（同柚子那次 ✅）
import '../models.dart';
import '../settings.dart';
import '../sites.dart';

/// **分类节点**（通道 / 二级组 / 三级题材用同一个类型 ✅）
/// ★ 2026-10-12（**用户点名纠正**）：分类筛选弹窗必须**按 L2 分组**、**组内列该 L2 的 L3** ——
///   父子关系**不用猜**：🛢️ 实测 `GET /category/` 的 `__NUXT_DATA__` → `category-filters-1` 节点 =
///   `{channels:[{id,name,slug,categories:[{id,name,slug,**children:[{id,name,slug}]**}]}]}` ✅
///   ⇒ [kChannels] 里每个 L2 的 `subs` **逐条照该节点抄**（= 它的 children ✅；空 = 该组只有「全部」✅）
class LzCat {
  final int id;
  final String name;
  final List<LzCat> subs;
  const LzCat(this.id, this.name, {this.subs = const []});

  /// 该 L2 的 children（弹窗里这一组的 chips ✅）；`const []` ⇒ 该组**只显示「全部」** ✅
  List<LzCat> get children => subs;
}

/// 首页一个分区（标题 + 卡片 + **「查看更多 ›」的目标地址**）
class LzTopic {
  final String title;
  final List<Article> items;

  /// ★ 2026-10-12（用户点名"你漏了「查看更多」" ✅）：**分区整页地址** ——
  ///   🛢️ **站点自己给的**：首页 HTML 里每行是
  ///   `<h2 class="home-head__title">标题</h2>` 紧跟 `<a href="…" class="home-head__more">查看更多 ›</a>` ✅；
  ///   实测六行 = `【荔枝】最骚原创 → /original/` · `精选推荐 → /featured/` · `上新必看 → /topic/jin-bo/` ·
  ///   `每日追更 → /topic/daily-new/` · `贤者时间 → /topic/xianzhe/` · `你来评选 → /topic/nilai/` ✅
  ///   ⚠️ **不从 blob 的 `slug` 拼**（blob 里是 `lizhi-original` 这类，与站上链接**不是一套** ☠）
  ///   ⇒ 一律**照抄 HTML 的 href** ✅（**不猜地址** ✅）
  final String more;
  const LzTopic(this.title, this.items, {this.more = ''});
}

/// 荔枝短剧（liz01.com）本站实现（取数走 [SiteFetcher] ✅）
class Liz01Site extends SiteUi {
  Liz01Site(this._f);

  final SiteFetcher _f;

  static const String _kBase = 'https://liz01.com';

  /// 取流伪地址标记（详情里给 `lazyUrl`，播放时由 [fetchSources] 现取 ✅）
  /// 形态：`/lz01/play/<剧id>/<集号epNo>/<声明秒>/<nonce>/`
  static const String _kPlayTag = '/lz01/play/';

  static const Duration _kTimeout = Duration(seconds: 12);

  /// 顶部 tab（照站点导航 ✅；`分类` 是**未验证**项 ⇒ 只放提示 ✅）
  /// ★ 2026-10-12（**用户要求移除** ✅ 原话："回家之路是有用的吗？加上干嘛"）：
  ///   原第 6 个 tab `/road/`（回家之路）**已从本列表移除** ☑️ —— 站点导航里那个入口仍在，
  ///   但**我们不做**那段（形态从未验证 ✅）。要恢复就把这行加回：
  ///   `MapEntry('/road/', '回家之路'),`
  static const List<MapEntry<String, String>> kTabs = [
    MapEntry('/', '首页'),
    MapEntry('/original/', '荔枝原创'),
    MapEntry('/featured/', '荔枝精选'),
    MapEntry('category', '分类'),
    MapEntry('/rank/week/', '排行榜'),
  ];

  @override
  String get relatedTitle => '相关短剧'; // ★ 2026-10-12（🛢️ 真站原文 `<h2 class="home-head__title">相关短剧</h2>` ✅
  //   —— 此前我写的「猜你喜欢」是**未核实**的，按 HAR 实测改掉 ✅

  /// ★ 2026-10-12（🛢️ HAR 实测）：**原创/精选 tab 的 5 个排序 pills**
  ///   真站 DOM = `div.topic-pills > button.topic-pill ×5`，文案原文如下；**默认选中「当前热播」** ✅
  static const List<MapEntry<String, String>> kTopicSorts = [
    MapEntry('new', '最新更新'),
    MapEntry('hot', '当前热播'), // ← 默认 ✅
    MapEntry('fav', '收藏最多'),
    MapEntry('like', '点赞最多'),
    MapEntry('random', '随机推荐'),
  ];

  /// ★ 2026-10-12（🛢️ HAR 实测）：**分类页的 4 个排序 pills**
  ///   真站 DOM = `div.cat-sort-pills > button.cat-page__tag ×4`；**默认「最新」** ✅；真值 `latest|hot|fav|like` ✅
  static const List<MapEntry<String, String>> kCatSorts = [
    MapEntry('latest', '最新'), // ← 默认 ✅
    MapEntry('hot', '最热'),
    MapEntry('fav', '收藏最多'),
    MapEntry('like', '点赞最多'),
  ];

  /// topic 的 `tab` ⇒ `drama/list` 的 `sort`（选了子分类时用 ✅）
  ///   ⚠️ `random`（随机推荐）在 `drama/list` 上**没有实测值** ☑️ ⇒ 返回空 ⇒ **不传该参数**
  ///      （= 默认序；**不猜** ✅ 与"照实"口径一致 ✅）
  static String sortOfTopicTab(String tab) =>
      switch (tab) { 'new' => 'latest', 'hot' || 'fav' || 'like' => tab, _ => '' };

  // ===== ★ 2026-10-12 分类快照（**来源 = 2026-10-12 recon-5 逐节点实测 108 个**）=====
  //
  // 【地址形态（🛢️ 实测）】`GET /category?categoryId=<id>` ⇒ 200 + 真卡；
  //   ⚠️ `/category/<id>/`、`/category/<slug>/` **都是 404** ☠ ⇒ **只能 query 式** ✅
  // 【分页（🛢️ 实测）】`/category/page/<n>/?categoryId=<id>` ⇒ 200（本机复测 376：第 1 页 **50 条** /
  //   第 2 页 **6 条**、`hasMore=false`、`total=56` ✅）；⚠️ `?…&page=2` **无效** ☠
  // 【只有有货的才放（🛢️）】顶层 2 通道 + 一级子分类 14 个（全部有货 ✅）；
  //   三级题材**只放"卡数 ≥3"的 14 个**（recon：92 个 L3 里 45 个有货，其中 **31 个只有 1~2 部**
  //   ⇒ 点开基本是空的 ☠ 所以不收）
  // 【刷新方法】逐类拉 `/category?categoryId=<id>`，读 blob 里 `page` 对象的 `total` ⇒ **≥3 才收** ✅
  // 【未实测 ⇒ **不做**（不许猜 ☠）】排序 tab / 时间筛选 / 筛选弹窗 —— 参数名都没测 ⇒ TODO：
  //   要补得先读 `/_nuxt/*.js` 或跑一次浏览器抓 HAR ✅
  //
  // ===== ★ 2026-10-12 三项**已做**（⚠️ 曾一度写成"不做"，此处为**更正后的正确口径**）=====
  //  🛢️ **推翻旧结论**：此前"服务端不接受 / 必须复刻加密信封"**是错的** —— 错因是探测时**带了
  //     `x-aes-key-id` 头**；**不带该头 ⇒ 服务端直接回明文 JSON**（真浏览器 HAR 实测 ✅）：
  //  ① **排序**（`最新/最热/收藏最多/点赞最多`）⇒ `GET /api/v1/drama/list?channelId=31&sort=hot&page=&size=`
  //     实测 `sort=hot` 首3 = `445,116,349` vs `sort=latest` 首3 = `563,557,560` ⇒ **真的生效** ✅
  //     （⚠️ 站点自己那两个"收藏最多/点赞最多"pill 请求里**不带 sort** ⇒ 等于默认序，**照实** ✅）
  //  ② **时间筛选** `publishedWithinDays` = `7|14|30|90`（"全部" = 不带）✅
  //  ③ **分类筛选弹窗** ⇒ 提交 `channelId + categoryId/categoryIds + publishedWithinDays + sort` ✅
  //  ⚠️ 仍**没有实测依据**的：`drama/list` 上 `random` 的真值 ❓（照实不传 ✅）
  //
  //  ★ 2026-10-12（**用户点名纠正**）：弹窗**按 L2 分组**显示各组 L3 —— 父子关系**已实测拿到了** ✅
  //    🛢️ 来源：`GET /category/` 的 `__NUXT_DATA__` → `category-filters-1` 节点（本机实测 2026-10-12 ✅）
  //    结构原文：`{channels:[{id,name,slug,categories:[{id,name,slug,children:[{id,name,slug}]}]}]}`
  //    ⇒ 下面每个 L2 的 `subs` = **该节点的 `children` 逐条照抄**（空 = 该组只显示「全部」✅ 实测 `cos(486)` 就是空 ✅）
  //    【刷新方法】重拉 `/category/`，解 `category-filters-1` 的 `children` 逐组比对 ✅
  static const List<LzCat> kChannels = [
    LzCat(31, '荔枝原创', subs: [
      LzCat(376, '都市', subs: [
        LzCat(390, '都市'), LzCat(391, '商战'), LzCat(392, '战神'), LzCat(393, '赘婿'),
        LzCat(394, '逆袭'), LzCat(395, '动作'), LzCat(396, '喜剧'),
      ]),
      LzCat(377, '情感', subs: [
        LzCat(397, '现言'), LzCat(398, '爱情'), LzCat(399, '甜宠'), LzCat(400, '青春'),
        LzCat(401, '女性成长'), LzCat(402, '家庭'), LzCat(403, '复仇'), LzCat(404, '穿越'),
        LzCat(405, '重生'), LzCat(406, '男同'), LzCat(407, '女同'),
      ]),
      LzCat(378, '古风', subs: [
        LzCat(408, '古装'), LzCat(409, '古言'), LzCat(410, '宫斗'), LzCat(411, '权谋'),
        LzCat(412, '种田'), LzCat(413, '武侠'), LzCat(414, '民国'),
      ]),
      LzCat(379, '玄幻', subs: [
        LzCat(415, '玄幻'), LzCat(416, '仙侠'), LzCat(417, '奇幻'), LzCat(418, '科幻'),
        LzCat(419, '脑洞'), LzCat(420, '志怪'),
      ]),
      LzCat(380, '悬疑', subs: [
        LzCat(421, '悬疑'), LzCat(422, '犯罪'), LzCat(423, '刑侦'), LzCat(424, '求生'),
        LzCat(425, '灵异'), LzCat(426, '恐怖'), LzCat(427, '惊悚'),
      ]),
      LzCat(381, '漫剧', subs: [
        LzCat(428, '恋爱'), LzCat(429, '都市'), LzCat(430, '古风'), LzCat(431, '玄幻'),
        LzCat(432, '悬疑'), LzCat(433, '搞笑'),
      ]),
    ]),
    LzCat(32, '荔枝精选', subs: [
      LzCat(486, 'cos'), // 🛢️ 实测 children=0 ⇒ 该组**只显示「全部」** ✅
      LzCat(383, '都市', subs: [
        LzCat(438, '都市'), LzCat(439, '商战'), LzCat(440, '战神'), LzCat(441, '赘婿'),
        LzCat(442, '逆袭'), LzCat(443, '动作'), LzCat(444, '喜剧'),
      ]),
      LzCat(384, '情感', subs: [
        LzCat(445, '现言'), LzCat(446, '爱情'), LzCat(447, '甜宠'), LzCat(448, '青春'),
        LzCat(449, '女性成长'), LzCat(450, '家庭'), LzCat(451, '复仇'), LzCat(452, '穿越'),
        LzCat(453, '重生'), LzCat(454, '男同'), LzCat(455, '女同'),
      ]),
      LzCat(385, '古风', subs: [
        LzCat(456, '古装'), LzCat(457, '古言'), LzCat(458, '宫斗'), LzCat(459, '权谋'),
        LzCat(460, '种田'), LzCat(461, '武侠'), LzCat(462, '民国'),
      ]),
      LzCat(386, '玄幻', subs: [
        LzCat(463, '玄幻'), LzCat(464, '仙侠'), LzCat(465, '奇幻'), LzCat(466, '科幻'),
        LzCat(467, '脑洞'), LzCat(468, '志怪'),
      ]),
      LzCat(387, '悬疑', subs: [
        LzCat(469, '悬疑'), LzCat(470, '犯罪'), LzCat(471, '刑侦'), LzCat(472, '求生'),
        LzCat(473, '灵异'), LzCat(474, '恐怖'), LzCat(475, '惊悚'),
      ]),
      LzCat(388, '漫剧', subs: [
        LzCat(476, '恋爱'), LzCat(477, '都市'), LzCat(478, '古风'), LzCat(479, '玄幻'),
        LzCat(480, '悬疑'), LzCat(481, '搞笑'),
      ]),
      LzCat(389, '更新', subs: [
        LzCat(482, '今日更新'), LzCat(483, '本周上新'), LzCat(484, '连载中'), LzCat(485, '已完结'),
      ]),
    ]),
  ];

  /// 三级题材（**卡数 ≥3 的那 14 个** ✅；括号里是 recon-5 实测卡数）
  /// ⚠️ 按**通道 id 段**分侧（原创 3xx / 精选 4xx —— recon 给的分段 ✅）⇒ 该层归属是 🔍 推断 ✅
  static const List<LzCat> kThemes = [
    LzCat(390, '都市(34)'), LzCat(391, '商战(3)'), LzCat(395, '动作(4)'),
    LzCat(397, '现言(10)'), LzCat(399, '甜宠(39)'), LzCat(400, '青春(5)'),
    LzCat(402, '家庭(10)'), LzCat(408, '古装(5)'), LzCat(415, '玄幻(4)'),
    LzCat(416, '仙侠(3)'),
    LzCat(438, '都市(3)'), LzCat(450, '家庭(10)'), LzCat(454, '男同(8)'),
    LzCat(477, '都市(3)'),
  ];

  /// 某通道下的三级题材（按 id 段分 ✅）
  static List<LzCat> themesOf(int channelIndex) => kThemes
      .where((t) => channelIndex == 0 ? t.id < 400 : t.id >= 400)
      .toList();

  @override
  bool get relatedAsGrid => true;

  static String _id8(Object? v) {
    final s = '$v';
    return s.length <= 8 ? s : s.substring(0, 8);
  }

  // ===== 一、devalue 扁平数组助手（**逐字复用野果** ✅ 同一套 Nuxt3 blob ✅）=====

  List<dynamic>? _nuxt(String html) {
    final k = html.indexOf('id="__NUXT_DATA__"');
    if (k < 0) return null;
    final s = html.indexOf('>', k);
    if (s < 0) return null;
    final e = html.indexOf('</script>', s);
    if (e < 0) return null;
    try {
      final j = jsonDecode(html.substring(s + 1, e));
      return j is List ? j : null;
    } catch (_) {
      return null;
    }
  }

  Object? _deref(List<dynamic> a, Object? v, [int depth = 0]) {
    if (depth > 14 || v is! num) return v;
    final i = v.toInt();
    if (i < 0 || i >= a.length) return null;
    final t = a[i];
    if (t is List) return [for (final x in t) _deref(a, x, depth + 1)];
    if (t is Map) {
      return {
        for (final e in t.entries) '${e.key}': _deref(a, e.value, depth + 1),
      };
    }
    return t;
  }

  /// 一个对象是不是"卡"：**结构判据**（`id` + `title` + `coverUrl` 都在 ✅）——
  ///   ⚠️ 这三条是**首页实测过的字段** ✅（不是猜的 ☑️），列表页也用它当"像不像卡"的判据 ✅
  static bool _looksLikeCard(Map<String, dynamic> o) =>
      _i(o['id']) > 0 &&
      '${o['title'] ?? ''}'.trim().isNotEmpty &&
      '${o['coverUrl'] ?? ''}'.trim().isNotEmpty;

  /// ★ 2026-10-12（用户点名"封面右下角要有集数" ✅）：**集数侧表**（`url → totalEpisodes`）
  ///   —— 自绘卡**右下角**用它 ✅（共享卡的集数走 `Article.badge` ✅ 见 [_item]）
  final Map<String, int> epsOf = <String, int>{};

  /// ★ 2026-10-12（**用户纠正** ✅："自绘你麻痹自绘，**站点自带有的**"）：
  ///   集数是**站点自带**的一栏（卡 DOM 里就有 `<span class="vcard__eps">` ✅）⇒ **处处都要显示** ✅。
  ///   分工定死（**不重复、不丢失**）：
  ///   · **共享卡片**（搜索 / 猜你喜欢 / 任何走底座卡的地方）：角标位 = `Article.badge` = **`N集`** ✅
  ///   · **本站自绘卡**（首页/列表/分类/榜单）：**左上 = 站点角标**（= 下面这张侧表 ✅）、
  ///     **右下 = 集数**（用 [epsOf] ✅）⇒ 各占一格 ✅
  final Map<String, String> siteBadgeOf = <String, String>{};

  /// ★ 2026-10-12（🛢️ 真站卡元素）：**右上角评分**（`span.vcard__score`，文案 `9.0分` ✅）——
  ///   数据 = 卡字段 `score`（实测存在 ✅）；共享卡**没有评分位** ⇒ 只给自绘卡右上 ✅
  final Map<String, String> scoreOf = <String, String>{};

  /// ★ 2026-10-12：**播放量侧表**（`url → displayViewText`，如 `7235`）—— 榜单行要显示 `<n> 播放`（真站
  ///   `rank-card` 里就是这个 ✅）；卡面（封面角）**不加播放量**（用户口径 ✅）
  final Map<String, String> playsOf = <String, String>{};

  /// ★ 2026-10-12：**标签/简介侧表** —— 榜单行里有「标签 pills + 简介」（真站 `rank-card__body` ✅）；
  ///   卡面不用（卡面只有 标题/时间/集数/角标/评分 ✅）
  final Map<String, List<String>> tagsOf = <String, List<String>>{};
  final Map<String, String> descOf = <String, String>{};

  /// ★ 2026-10-12（**按 `DEVLOG.md` §一 规范收口** ✅；规范原文行号见每条后面）：
  ///   · `:12` 卡片 = 封面 + 标题 + **发布时间（标题下方）**；封面角标：**时长 ＞ 集数 ＞ 播放量**
  ///   · 🛢️ **真站自己的卡**（首页/分类页 DOM 实测）：`<div class="vcard__meta"><span class="vcard__plays">2天前…`
  ///     —— 原文样例：`<span class="vcard__eps">2天前 · 更新至5集</span>` / `<span class="vcard__eps">全6集</span>`
  ///     ⇒ **时间与集数都在站点自带那一栏** ✅
  ///   ⇒ 本项目口径落法（**不猜**）：
  ///     · **`meta`（标题下方）= 发布时间**（相对时间，格式照真站 `N天前` ✅）—— 规范 `:12` 要求的第一项 ✅
  ///     · **`badge`（封面角标）= 集数**（真站原文 `全N集` / `更新至N集` ✅）—— 规范 `:12` 的优先级
  ///       **时长 ＞ 集数 ＞ 播放量**：本站**无时长** ⇒ 落到**集数** ✅（**播放量因此不进角标** ✅）
  ///     · **站点角标**（热播/独家/新上架…）= **自绘卡左上角**（侧表 ✅，真站也在角上 `vcard__corner` ✅）
  // ===== ★ 2026-10-12（**紧急修复** ✅ —— 🛢️ 真机日志：`Unhandled Exception: type 'String' is not a subtype of
  //   type 'num?'`）：站方字段**类型不稳** —— 实测 `score` 是 **String（`"9.5"`）**，
  //   而 `id/totalEpisodes/displayViewCount/publishedEpisodeCount/payMode/coinPrice/freePreviewEps/
  //   likeCount/ratingCount` 是 **Int64**；`viewBadge`/`coverProgress` 还会是 **null** ☠
  //   ⇒ **禁止对接口字段用 `as num`/`as int`/`as double`**（一抛就整页挂 ☠）
  //   ⇒ 统一走这三个容错助手：**数字 / 数字字符串 / null 都能吃**，吃不掉就兜底（**绝不抛** ✅）

  /// 容错取整数（`Int64` / `"9"` / `null` 都能吃 ✅）
  static int _i(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }

  /// 容错取小数（☠ **本站 `score` 就是 String**：`double.tryParse('9.5')` ✅；失败 ⇒ 0 = 不显示 ✅）
  static double _d(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? 0;
    return 0;
  }

  /// 容错取布尔（`true` / `"true"` ✅；其它 ⇒ false ✅）
  static bool _b(Object? v) =>
      v == true || (v is String && v.trim().toLowerCase() == 'true');

  Article? _item(Map<String, dynamic> o) {
    if (!_looksLikeCard(o)) return null;
    final id = _i(o['id']);
    final title = '${o['title'] ?? ''}'.trim();
    final slug = '${o['slug'] ?? ''}'.trim();
    final eps = _i(o['totalEpisodes']);
    final shown = _i(o['publishedEpisodeCount']);
    final partial = _b(o['partial']);
    final timeText = _relTime('${o['publishedAt'] ?? ''}');
    final badge = '${o['coverBadge'] ?? ''}'.trim();
    final url = '/drama/$id/${slug.isEmpty ? '-' : slug}/';
    // 🛢️ 集数文案**照真站原文**：`全N集`（完结）/ `更新至N集`（连载）✅
    final epsText = eps <= 0
        ? ''
        : (partial && shown > 0 ? '更新至$shown集' : '全$eps集');
    if (eps > 0) epsOf[url] = eps;
    if (badge.isNotEmpty) siteBadgeOf[url] = badge;
    // ★ 右上角评分（🛢️ 真站 `span.vcard__score` = `9.0分` ✅）
    //   ☠ **字段是 String（`"9.5"`）** ⇒ 必须走 [_d]（原来写 `as num?` ⇒ **整页解析挂** ☠ 已修）
    final score = _d(o['score']);
    if (score > 0) scoreOf[url] = '${score.toStringAsFixed(1)}分';
    // ★ 榜单行要用（播放量 / 标签 / 简介 ✅）—— 卡面不用这些 ✅
    playsOf[url] = '${o['displayViewText'] ?? ''}'.trim();
    descOf[url] = '${o['description'] ?? ''}'.trim();
    final tg = o['tags'];
    if (tg is List) {
      final names = <String>[];
      for (final t in tg) {
        if (t is Map) {
          final n = '${t['name'] ?? ''}'.trim();
          if (n.isNotEmpty) names.add(n);
        }
      }
      if (names.isNotEmpty) tagsOf[url] = names;
    }
    return Article(
      // 详情只认数字 id ✅ ⇒ 地址里**把 id 放最前**，slug 只是好看（[_idOf] 只读数字 ✅）
      url: url,
      title: title,
      cover: '${o['coverUrl'] ?? ''}'.trim(),
      meta: timeText, // ★ 规范 :12：标题下方 = **发布时间** ✅
      badge: epsText.isNotEmpty ? epsText : badge, // ★ 规范 :12 角标优先级 ⇒ 集数 ✅（没集数才退回站点角标）
    );
  }

  /// `mm:ss`（DEVLOG:17「时长」用 ✅ —— 站点给的是**秒** ✅）
  static String _mmss(int sec) {
    if (sec <= 0) return '';
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// 相对时间（**格式照真站实测** 🛢️：126 张卡的 `vcard__eps` 文案分布 =
  ///   `全N集` 83 · **`N天前` 42 · `N小时前` 1** · 分钟/刚刚/**周/月 = 0** ✅
  ///   ⇒ **只做"小时 + 天"两档**（<24h ⇒ `N小时前`；≥24h ⇒ `N天前` ✅），**不做周/月** ✅
  ///   ⚠️ 1 小时内的样本 = 0 ☑️ ⇒ 落 `刚刚`（**实测没有这一档**，纯兜底 ✅ 不编造"分钟" ✅）
  static String _relTime(String iso) {
    if (iso.trim().isEmpty) return '';
    final t = DateTime.tryParse(iso.trim());
    if (t == null) return '';
    final diff = DateTime.now().difference(t.toLocal());
    if (diff.inHours < 1) return '刚刚';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }

  // ===== ★ 2026-10-12 封面预热/解密（**站点文件内自解，零公共区改动** ✅）=====
  //
  // 【为什么要预热】本站封面是 **AES-CBC 加密图**，而底座 `fetched_image.dart` 里写死的 key/iv
  //   （`f5d965df75336270`/`97b60394abc2fbe1`）**与本站不同** ⇒ 控件自己解不开 ⇒ 图是空的 ☠。
  //
  // 【为什么这样接就够（🛢️ 机制来自 lead 核实，条条有 file:line）】
  //   ① `fetched_image.dart:200-213`：控件**先查磁盘缓存**，命中即"**解密后的明文**" ⇒ **不再下载、不再解密** ✅
  //   ② `base/image_cache.dart:22/:72`：**缓存 key 就是 URL 本身**；`ImageDiskCache.i.put(url, bytes)` 是公开 API ✅
  //   ③ `fetched_image.dart:304-305`：拿到的字节**本身是图**（看魔数）⇒ 不再解密 ✅
  //   ④ `fetched_image.dart:338-344`：非可解图 ⇒ **return null、不写缓存** ⇒ **没有"毒缓存"风险** ✅
  //   ⇒ 我们只要在**渲染之前**把"**明文**"按同一个 URL 塞进磁盘缓存即可 —— 控件随后命中缓存直接显示 ✅
  //     （若某次没赶上：那一次显示占位，等我们塞完/或控件自己再取时命中缓存即出图 ✅ 与控件**不打架** ✅）
  //
  // 【口径】幂等（已缓存 ⇒ 跳过 ✅）· 并发 **≤6**（满了就直接跳过，"滚到再补" ✅ 不排队不阻塞列表 ✅）·
  //   失败/异常**静默**（不写缓存、不上抛 ✅）· `logConsole` 时打一行（**只 host + 长度，不打 URL** ✅）

  /// 站点声明的图片 AES 参数（首页 HTML 原文 `imageAesKeyHex` / `imageAesIvHex` ✅ **hex**）
  static const String _kImgKeyHex = 'ea19c21e85d768da4165f5964ab886b2';
  static const String _kImgIvHex = 'f4d53ecbc273901e0d9cd7848233c702';

  /// hex 字符串 ⇒ 字节（`enc.Key`/`enc.IV` 要 `Uint8List` ✅）
  static Uint8List _hexBytes(String hex) => Uint8List.fromList([
        for (var i = 0; i + 1 < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);

  /// 明文图魔数判据（PNG/JPEG/GIF/WEBP/AVIF ✅ —— 与"是不是图"同一判据，**不猜内容** ✅）
  static bool _looksImage(List<int> b) {
    if (b.length < 12) return false;
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return true; // PNG
    if (b[0] == 0xFF && b[1] == 0xD8) return true; // JPEG
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return true; // GIF
    final s = String.fromCharCodes(b.sublist(0, 12));
    if (s.startsWith('RIFF') && s.contains('WEBP')) return true; // WEBP
    if (s.length > 11 && s.substring(4, 12) == 'ftypavif') return true; // AVIF
    return false;
  }

  /// 站点 key/iv（hex ⇒ 字节 ✅ 用项目现成的 `enc` 包，**不自己写密码学** ✅）
  static final enc.Encrypter _imgAes = enc.Encrypter(
      enc.AES(enc.Key(_hexBytes(_kImgKeyHex)), mode: enc.AESMode.cbc));
  static final enc.IV _imgIv = enc.IV(_hexBytes(_kImgIvHex));

  // ===== ★ 2026-10-12 **队列化**（修 Bug 2：原来"并发满了直接丢" ⇒ 一行 4 张里 3 张永远是灰的 ☠）=====
  //
  // 【原缺陷】`if (_warming >= _kMaxWarm) return;` —— 满了就**丢**，且**没有队列** ⇒
  //   首页 ~30 张封面、并发只有 6 ⇒ **大部分被丢且没人再排** ⇒ 灰色占位 ✅（lead 指出的就是这条）
  // 【现在】待办队列 + 并发 ≤6 + **worker 完成自动取下一个**（一个都不丢 ✅）+
  //   失败项**移出 `_queued`** 并允许**最多 1 次重排**（不死循环 ✅）+ 失败原因诊断（不打完整 URL ✅）+
  //   `warmTick` 进度通知：每解出一张就 +1（**节流**）⇒ 页面重建 ⇒ 刚解出来的封面**立刻出图** ✅
  final List<String> _q = <String>[]; // 待办（FIFO ✅）
  final Set<String> _queued = <String>{}; // 已进队/在跑的（去重 ✅）
  final Set<String> _retried = <String>{}; // 已重试过的（最多 1 次 ✅）
  int _active = 0; // 在途 worker 数
  static const int _kMaxWarm = 6;

  /// 预热进度通知（**只在"真的写进缓存"后 +1**，节流 300ms ✅）—— 页面监听它即可"图一解出来就重画" ✅
  final ValueNotifier<int> warmTick = ValueNotifier<int>(0);
  int _lastTick = 0;

  void _bumpTick() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTick < 300) return; // 节流：一批里只通知几次，避免反复重建 ✅
    _lastTick = now;
    warmTick.value++;
  }

  /// ★ 预热一批封面（**列表/详情拿到卡之后调** ✅；不 await、不阻塞 ✅ —— 自绘卡靠 `warmTick` 重建 ✅）
  void warmCovers(Iterable<Article> items) {
    for (final a in items) {
      warmCover(a.cover);
    }
  }

  /// ★ 2026-10-12（用户报"**搜索卡没封面**"后加的**同步预热** ✅ —— 这两处用的是**共享卡片**）：
  ///   共享 `ArticleCard`（搜索页 / 详情「猜你喜欢」）**不监听** [warmTick] ☠ ⇒ 它渲染那一刻缓存若还没写好，
  ///   控件自己那次"**拿底座的 key 解本站密文**"必然失败 ⇒ **图一直空到用户重进** ☠。
  ///   （**不是映射问题**：🛢️ 实测搜索页卡字段 = `id/title/slug/coverUrl/…` 与首页**同名同款** ✅）
  ///   ⇒ 这两处**先把封面解好再返回** ✅（前 [max] 张，并发 6 ✅ 不阻塞 UI 线程：全程 await 网络+解密）
  ///   ⚠️ 自绘卡那几处（首页/列表/分类/榜单）**仍走异步队列** `warmCovers` ✅（能靠 tick 重建，不必等）
  Future<void> warmCoversSync(Iterable<Article> items, {int max = 12}) async {
    final list = <String>[
      for (final a in items)
        if (a.cover.trim().isNotEmpty) a.cover.trim(),
    ];
    var i = 0;
    while (i < list.length && i < max) {
      var end = i + 6;
      if (end > max) end = max;
      if (end > list.length) end = list.length;
      final batch = list.sublist(i, end);
      await Future.wait([
        for (final u in batch)
          () async {
            if (_queued.contains(u)) return;
            if (ImageDiskCache.i.take(u) != null) return; // 已有明文 ⇒ 跳过（幂等 ✅）
            _queued.add(u);
            await _warmOne(u);
          }(),
      ]);
      i = end;
    }
    for (; i < list.length; i++) {
      warmCover(list[i]); // 其余照旧异步 ✅
    }
  }

  /// 预热**单个**封面 URL（进队 ✅ —— 队列满不满都**不丢** ✅）
  void warmCover(String url) {
    final u = url.trim();
    if (u.isEmpty) return;
    if (_queued.contains(u)) return; // 已进队/在跑 ⇒ 跳过（去重 ✅）
    if (ImageDiskCache.i.take(u) != null) return; // 已有明文缓存 ⇒ 不用排 ✅
    _queued.add(u);
    _q.add(u);
    _pump();
  }

  /// 拉满并发（worker 完成后会**再调一次** ⇒ 队列自动续跑 ✅）
  void _pump() {
    while (_active < _kMaxWarm && _q.isNotEmpty) {
      final u = _q.removeAt(0);
      _active++;
      unawaited(_warmOne(u).whenComplete(() {
        _active--;
        _pump(); // ★ 取下一个（**不再丢弃任何一张** ✅）
      }));
    }
  }

  /// 失败诊断（**不打完整 URL** ✅：只 host + 原因）＋ **最多 1 次重排** ✅
  void _warmFail(String u, String host, String why) {
    _queued.remove(u); // ★ 允许后续再排（不再"一次失败就永久拉黑" ☠）
    if (AppSettings.i.logConsole) {
      debugPrint('[IMG] 荔枝短剧 封面预热失败 host=$host $why');
    }
    if (_retried.contains(u)) return; // 已重试过 ⇒ 放弃（避免死循环 ✅）
    _retried.add(u);
    _queued.add(u);
    _q.add(u);
    _pump();
  }

  /// 下载密文 ⇒ 解密 ⇒ 入磁盘缓存（**失败只打诊断 + 重排一次**，不上抛 ✅）
  Future<bool> _warmOne(String url) async {
    final host = Uri.tryParse(url)?.host ?? '?';
    try {
      final r = await _f.client.get(Uri.parse(url), headers: {
        'User-Agent': Site.ua,
        'Referer': 'https://$host/',
        'Accept': 'image/*,*/*;q=0.8',
      }).timeout(_kTimeout);
      if (r.statusCode != 200) {
        _warmFail(url, host, 'code=${r.statusCode}');
        return false;
      }
      final raw = r.bodyBytes;
      if (_looksImage(raw)) {
        ImageDiskCache.i.put(url, raw); // 本来就是明文图 ⇒ 直接用 ✅
        _queued.remove(url);
        if (AppSettings.i.logConsole) {
          debugPrint('[IMG] 荔枝短剧 封面预热 host=$host 明文 字节=${raw.length}');
        }
        _bumpTick();
        return true;
      }
      final plain = _imgAes.decryptBytes(enc.Encrypted(raw), iv: _imgIv);
      if (_looksImage(plain)) {
        ImageDiskCache.i.put(url, Uint8List.fromList(plain));
        _queued.remove(url);
        if (AppSettings.i.logConsole) {
          debugPrint('[IMG] 荔枝短剧 封面预热 host=$host 解密 '
              '密文=${raw.length} 明文=${plain.length} 16对齐=${raw.length % 16 == 0}');
        }
        _bumpTick();
        return true;
      }
      // 解出来不像图 ⇒ **不写缓存**（同 fetched_image.dart:338-344 口径 ✅）+ 诊断
      _warmFail(url, host,
          '解出来不像图（密文=${raw.length} 16对齐=${raw.length % 16 == 0} '
          '明文=${plain.length} 头=${plain.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}）');
      return false;
    } catch (e) {
      _warmFail(url, host, '异常=${e.runtimeType}');
      return false;
    }
  }

  /// **结构扫描**（列表页/搜索页用 ✅）：在 blob 里找出**元素都像卡**的第一个数组 ✅
  ///
  /// ⚠️ 为什么用扫描而不是写死字段：列表页的 blob 形态 **本机没实测**（❓ 见文件头）⇒
  ///   **不猜字段名**，只按"像不像卡"这个**结构判据**（首页实测过的三字段 ✅）来找 ✅；
  ///   扫描不到 ⇒ 返回空 + 日志（调用方照"空列表"处理 ✅ 不静默）。
  List<Article> _scanCards(List<dynamic> a, String entry) {
    for (var i = 0; i < a.length; i++) {
      final t = a[i];
      if (t is! List || t.isEmpty) continue;
      // 解引用后看前 3 项
      final probe = <Map<String, dynamic>>[];
      for (var k = 0; k < t.length && k < 3; k++) {
        final d = _deref(a, t[k]);
        if (d is Map) probe.add(Map<String, dynamic>.from(d));
      }
      if (probe.isEmpty) continue;
      if (!probe.every(_looksLikeCard)) continue;
      final out = <Article>[];
      for (final x in t) {
        final d = _deref(a, x);
        if (d is Map) {
          final one = _item(Map<String, dynamic>.from(d));
          if (one != null) out.add(one);
        }
      }
      if (out.isNotEmpty) {
        if (AppSettings.i.logConsole) {
          debugPrint('[LIST] ${_f.site.name} 入口=$entry 扫描命中 数组@$i 条=${out.length}');
        }
        return out;
      }
    }
    return const [];
  }

  // ===== 二、首页分区（自管整页用 ✅）=====

  /// 首页 = blob 里所有"带 `topicName` + `dramas`"的分区对象 ✅（实测 6 个 ✅）
  ///
  /// ★ 2026-10-12：**同时解析站上自己的「查看更多 ›」链接**（`home-head__title` + `home-head__more`
  ///   成对出现 ✅）⇒ 得到 `标题 → href` 的映射，挂到每个 [LzTopic.more] 上 ✅（**照抄 href，不拼地址** ✅）
  Future<List<LzTopic>> homeTopics() async {
    final sw = Stopwatch()..start();
    final html = await _f.text('/');
    final a = _nuxt(html);
    final out = <LzTopic>[];
    // 站上"查看更多"链接：`<h2 class="home-head__title">T</h2>…<a href="H" class="home-head__more">`
    final moreOf = <String, String>{};
    for (final m in RegExp(
            r'home-head__title[^>]*>([^<]+)</h2>\s*<a\s+href="([^"]+)"[^>]*class="home-head__more"')
        .allMatches(html)) {
      moreOf[m.group(1)!.trim()] = m.group(2)!.trim();
    }
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 首页「查看更多」链接=${moreOf.length} 个'
          '${moreOf.isEmpty ? '（⚠️ 正则没命中 ⇒ 站点改版了 ☠）' : ''}');
    }
    if (a != null) {
      for (var i = 0; i < a.length; i++) {
        final t = a[i];
        if (t is! Map) continue;
        if (t['topicName'] == null || t['dramas'] == null) continue;
        final o = _deref(a, i);
        if (o is! Map) continue;
        final title = '${o['title'] ?? o['topicName'] ?? ''}'.trim();
        final ds = o['dramas'];
        if (title.isEmpty || ds is! List) continue;
        final items = <Article>[];
        for (final d in ds) {
          if (d is Map) {
            final one = _item(Map<String, dynamic>.from(d));
            if (one != null) items.add(one);
          }
        }
        if (items.isNotEmpty) out.add(LzTopic(title, items, more: moreOf[title] ?? ''));
      }
    }
    // ★ 2026-10-12（用户："封面有时候解密没跟上" ✅）：**首屏同步解好再返回**
    //   —— 实测：6 张并发 6 = **1917ms**（≈320ms/张 ✅）⇒ 取 **max=4**（≈1.3s，刚好覆盖首屏第一行 ✅；
    //      取 12 会 ≈3.8s = "卡成几秒" ☠ ⇒ **不取 12** ✅）；其余仍走异步队列 + `warmTick` 重建 ✅
    await warmCoversSync([for (final t in out) ...t.items], max: 4);
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 入口=推荐 分区=${out.length} '
          '每条=${out.isEmpty ? 0 : out.first.items.length} '
          '带查看更多=${out.where((t) => t.more.isNotEmpty).length} '
          'ms=${sw.elapsedMilliseconds}');
    }
    return out;
  }

  // ===== 三、列表页（路径式分页 ✅；⚠️ 绝不用 `?page=`）=====

  /// 列表页取数：`path` 形如 `/original/`；`page > 1` ⇒ 拼成 `<path>page/<n>/` ✅
  ///
  /// ⚠️ **不能用 `?page=`**：实测被 CDN 缓存吃掉、永远回第 1 页 ☠（🛢️ 站方自己也是路径式 ✅）
  Future<List<Article>> listPage(String path, int page, String entry) async {
    final sw = Stopwatch()..start();
    final base = path.endsWith('/') ? path : '$path/';
    final p = page <= 1 ? base : '${base}page/$page/';
    final html = await _f.text(p);
    final a = _nuxt(html);
    if (a == null) {
      if (AppSettings.i.logConsole) {
        debugPrint('[LIST] ${_f.site.name} 入口=$entry 页=$page ⇒ 页面没有 __NUXT_DATA__ ⇒ 0 条');
      }
      return const [];
    }
    final out = _scanCards(a, '$entry 页=$page');
    // ★ 首屏（页 1）同步解好封面（实测 ≈320ms/张 ⇒ max=4 ≈1.3s ✅）；翻页仍异步 + tick 重建 ✅
    if (page <= 1) {
      await warmCoversSync(out, max: 4);
    } else {
      warmCovers(out);
    }
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 入口=$entry 页=$page 路径=$p 条=${out.length} '
          'ms=${sw.elapsedMilliseconds}');
    }
    return out;
  }

  @override
  Future<List<Article>> tag(String slug, {required int page}) =>
      listPage('/tag/$slug/', page, '标签');

  @override
  Future<List<Article>> home({required int page, String first = ''}) =>
      listPage('/original/', page, '首页');

  @override
  Future<List<Article>> category(String key,
      {required int page,
      String? k,
      String? theme,
      String? duration,
      String? sort,
      List<MapEntry<String, String>>? extra,
      Future<List<Article>> Function({int page})? home}) {
    final path = key.startsWith('/') ? key : '/$key/';
    return listPage(path, page, '分类');
  }

  // ===== ★ 2026-10-12 分类取数（`/category?categoryId=<id>` ✅）=====

  /// blob 里的**列表口袋**：`page` 对象 = `{items[], size, total, hasMore}` ✅（🛢️ 实测 @761 ✅）
  ///   找不到 ⇒ 返回 null（调用方照"空"处理 + 日志 ✅ 不静默）
  ({List<Article> items, int total, bool hasMore})? _pageBag(
      List<dynamic> a, String entry) {
    for (var i = 0; i < a.length; i++) {
      final t = a[i];
      if (t is! Map || t['page'] == null) continue;
      final o = _deref(a, i);
      if (o is! Map) continue;
      final pg = o['page'];
      if (pg is! Map) continue;
      final raw = pg['items'];
      if (raw is! List) continue;
      final items = <Article>[];
      for (final x in raw) {
        final d = _deref(a, x);
        if (d is Map) {
          final one = _item(Map<String, dynamic>.from(d));
          if (one != null) items.add(one);
        }
      }
      warmCovers(items); // ★ 分类列表封面也预热 ✅
      final total = _i(pg['total']) == 0 ? items.length : _i(pg['total']);
      final hasMore = pg['hasMore'] == true;
      if (AppSettings.i.logConsole) {
        debugPrint('[LIST] ${_f.site.name} 入口=$entry size=${pg['size']} '
            'total=$total hasMore=$hasMore 条=${items.length}');
      }
      return (items: items, total: total, hasMore: hasMore);
    }
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 入口=$entry ⇒ blob 里没有 page 口袋 ⇒ 0 条');
    }
    return null;
  }

  /// 分类列表（**query 式** ✅）：`/category?categoryId=<id>`；
  ///   `page > 1` ⇒ `/category/page/<n>/?categoryId=<id>` ✅（⚠️ `?…&page=` **无效** ☠ 实测）
  Future<({List<Article> items, int total, bool hasMore})> categoryItems(
      int categoryId, int page, String entry) async {
    final sw = Stopwatch()..start();
    final p = page <= 1
        ? '/category?categoryId=$categoryId'
        : '/category/page/$page/?categoryId=$categoryId';
    try {
      final html = await _f.text(p);
      final a = _nuxt(html);
      if (a == null) return (items: const <Article>[], total: 0, hasMore: false);
      final bag = _pageBag(a, '$entry 页=$page id=$categoryId');
      // ★ 首屏（页 1）同步解好封面（max=4 ≈1.3s ✅）；翻页仍异步 + tick 重建 ✅
      if (page <= 1 && bag != null) {
        await warmCoversSync(bag.items, max: 4);
      }
      if (AppSettings.i.logConsole) {
        debugPrint('[LIST] ${_f.site.name} 入口=$entry 页=$page 路径=$p '
            'ms=${sw.elapsedMilliseconds}');
      }
      return bag ?? (items: const <Article>[], total: 0, hasMore: false);
    } catch (e) {
      if (AppSettings.i.logConsole) {
        debugPrint('[LIST] ${_f.site.name} 入口=$entry id=$categoryId 异常：$e');
      }
      return (items: const <Article>[], total: 0, hasMore: false);
    }
  }

  // ===== ★ 2026-10-12 排行榜取数（🛢️ 卡结构与首页**不同**：`{rankNo, drama{…}, …}` ✅）=====

  /// 榜单列表：`/rank/week/` · `/rank/month/`；`page > 1` ⇒ `/rank/<period>/page/<n>/` ✅
  ///
  /// ⚠️ **不能复用首页/分类那套"结构扫描"**：榜单项是 `{rankNo, dramaId, viewCount, …, drama:{…}, episodePreview[]}`
  ///   ⇒ 外层**没有** `title/coverUrl`（在**嵌套的 `drama`** 里 ✅）⇒ 这里**照字段解析** ✅；
  ///   排名 `rankNo` 放进 `Article.badge`（角标位 ✅ 用户要"显示排名" ✅）。
  Future<({List<Article> items, int total, bool hasMore})> rankItems(
      {required bool month, required int page, required String entry}) async {
    final sw = Stopwatch()..start();
    final base = month ? '/rank/month/' : '/rank/week/';
    final p = page <= 1 ? base : '${base}page/$page/';
    try {
      final html = await _f.text(p);
      final a = _nuxt(html);
      if (a == null) return (items: const <Article>[], total: 0, hasMore: false);
      final items = <Article>[];
      for (var i = 0; i < a.length && items.isEmpty; i++) {
        final t = a[i];
        if (t is! List || t.isEmpty) continue;
        final probe = _deref(a, t.first);
        if (probe is! Map || probe['rankNo'] == null || probe['drama'] == null) {
          continue;
        }
        for (final x in t) {
          final e = _deref(a, x);
          if (e is! Map) continue;
          final d = e['drama'];
          if (d is! Map) continue;
          final one = _item(Map<String, dynamic>.from(d));
          if (one == null) continue;
          final rn = _i(e['rankNo']);
          items.add(Article(
            url: one.url,
            title: one.title,
            cover: one.cover,
            meta: one.meta,
            badge: rn > 0 ? 'No.$rn' : one.badge, // ★ 角标位放排名 ✅
          ));
        }
      }
      warmCovers(items); // ★ 榜单封面也预热 ✅
      // ★ 首屏（页 1）同步解好（max=4 ≈1.3s ✅）；翻页仍异步 + tick 重建 ✅
      if (page <= 1) {
        await warmCoversSync(items, max: 4);
      }
      final bag = _pageBag(a, '$entry 页=$page'); // 榜单页同样有 `page` 口袋（total/hasMore ✅）
      final total = bag?.total ?? items.length;
      final hasMore = bag?.hasMore ?? items.isNotEmpty;
      if (AppSettings.i.logConsole) {
        debugPrint('[LIST] ${_f.site.name} 入口=$entry 页=$page 条=${items.length} '
            'total=$total hasMore=$hasMore ms=${sw.elapsedMilliseconds}');
      }
      return (items: items, total: total, hasMore: hasMore);
    } catch (e) {
      if (AppSettings.i.logConsole) {
        debugPrint('[LIST] ${_f.site.name} 入口=$entry 页=$page 异常：$e');
      }
      return (items: const <Article>[], total: 0, hasMore: false);
    }
  }

  /// ★ 2026-10-12（**HAR 实测** ✅，🛢️ 明文接口、**不带任何加密头**）：
  ///   · **topic**（原创/精选「全部」档）：`GET /api/v1/topic/<slug>?tab=<new|hot|fav|like|random>&page=&size=50`
  ///     ⇒ 明文 `data.dramas[]`（与列表卡**同构 22 字段** ✅）
  ///     实测：`lizhi-original?tab=hot` ⇒ 26 条 / 首3 = 445,116,349；`tab=new` ⇒ 26 条 / 首3 = **552,514,512** ✅（**首卡真的变** ✅）
  ///   · **drama/list**（子分类 / 分类页 / 筛选弹窗都走它）：`GET /api/v1/drama/list`
  ///     `?channelId=31|32[&categoryId=][&categoryIds=][&publishedWithinDays=7|14|30|90][&sort=latest|hot|fav|like]&page=&size=50`
  ///     ⇒ 明文 `data.page{items,total,hasMore}` ✅
  ///     实测：`channelId=31&sort=hot` ⇒ 50 条 / total=159 / 首3 = 445,116,349；`sort=latest` ⇒ 首3 = **563,557,560** ✅
  ///   ⚠️ 🛢️ **站方自己的"收藏最多/点赞最多"请求里没带 `sort`**（= 默认序）⇒ 我们**照实**传 `fav`/`like`
  ///     （呼应你的口径：**照实**，等站方修 ✅）
  Future<({List<Article> items, int total, bool hasMore})> dramaList({
    required int channelId,
    int categoryId = 0,
    List<int> categoryIds = const [],
    int publishedWithinDays = 0,
    String sort = '',
    required int page,
    required String entry,
  }) async {
    final q = <String>[
      'channelId=$channelId',
      if (categoryId > 0) 'categoryId=$categoryId',
      if (categoryIds.isNotEmpty) 'categoryIds=${categoryIds.join(",")}',
      if (publishedWithinDays > 0) 'publishedWithinDays=$publishedWithinDays',
      if (sort.isNotEmpty) 'sort=$sort',
      'page=$page',
      'size=50',
    ].join('&');
    return _plainList('/api/v1/drama/list?$q', entry, page);
  }

  /// topic 明文接口（原创/精选「全部」档 ✅）
  Future<({List<Article> items, int total, bool hasMore})> topicList(
      String slug, String tab, int page, String entry) async {
    final q = 'tab=$tab&page=$page&size=50';
    return _plainList('/api/v1/topic/$slug?$q', entry, page);
  }

  /// 明文 JSON 列表（`data.dramas[]` 或 `data.page{items,…}` 两种都吃 ✅）
  Future<({List<Article> items, int total, bool hasMore})> _plainList(
      String path, String entry, int page) async {
    final sw = Stopwatch()..start();
    try {
      final r = await _f.client
          .get(Uri.parse('$_kBase$path'), headers: {'User-Agent': Site.ua})
          .timeout(_kTimeout);
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map || j['success'] != true) {
        if (AppSettings.i.logConsole) {
          debugPrint('[LIST] ${_f.site.name} 入口=$entry code=${r.statusCode} '
              'success=${j is Map ? j['success'] : '?'} ⇒ 0 条');
        }
        return (items: const <Article>[], total: 0, hasMore: false);
      }
      final d = j['data'];
      final dm = d is Map ? Map<String, dynamic>.from(d) : null;
      List<dynamic>? raw;
      var total = 0;
      var hasMore = false;
      if (dm != null && dm['dramas'] is List) {
        raw = dm['dramas'] as List;
        total = raw.length;
        hasMore = raw.length >= 50;
      } else if (dm != null && dm['page'] is Map) {
        final pg = dm['page'] as Map;
        if (pg['items'] is List) raw = pg['items'] as List;
        total = _i(pg['total']);
        hasMore = pg['hasMore'] == true;
      }
      final items = <Article>[];
      for (final x in raw ?? const []) {
        if (x is Map) {
          final one = _item(Map<String, dynamic>.from(x));
          if (one != null) items.add(one);
        }
      }
      // ★ 首屏（页 1）同步解好封面（max=4 ≈1.3s ✅）；翻页仍异步 + tick ✅
      if (page <= 1) {
        await warmCoversSync(items, max: 4);
      } else {
        warmCovers(items);
      }
      if (AppSettings.i.logConsole) {
        debugPrint('[LIST] ${_f.site.name} 入口=$entry 页=$page 路径=$path '
            '条=${items.length} total=$total hasMore=$hasMore '
            'ms=${sw.elapsedMilliseconds}');
      }
      return (items: items, total: total, hasMore: hasMore);
    } catch (e) {
      if (AppSettings.i.logConsole) {
        debugPrint('[LIST] ${_f.site.name} 入口=$entry 页=$page 异常：$e');
      }
      return (items: const <Article>[], total: 0, hasMore: false);
    }
  }

  // ===== 四、搜索（只有 page 1 ✅；分页 ❓ TODO）=====

  @override
  Future<List<Article>> search(String keyword,
      {int page = 1, List<MapEntry<String, String>>? extra}) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return [];
    if (page > 1) {
      // ★ 2026-10-12（**已实测** ✅）：`/search/<kw>/page/2/` ⇒ **HTTP 404** ⇒ 本站搜索**只有第 1 页** ☑️
      //   （对比：`/original/page/2/` 200 ✅ ⇒ 路径式分页只在"列表页"上有效，搜索页**没有分页** ✅）
      //   ⇒ `page > 1` 返回空 + 日志 ⇒ 底座搜索页底部会显示「没有更多了」✅（**不是猜的** ✅）
      if (AppSettings.i.logConsole) {
        debugPrint('[LIST] ${_f.site.name} 入口=搜索 页=$page ⇒ 搜索无分页（page/2 实测 404），返回 0 条');
      }
      return [];
    }
    final sw = Stopwatch()..start();
    final p = '/search/${Uri.encodeComponent(kw)}/';
    final html = await _f.text(p);
    final a = _nuxt(html);
    final out = a == null ? const <Article>[] : _scanCards(a, '搜索');
    // ★ 2026-10-12（用户报"搜索卡没封面"）：搜索页用的是**共享卡片**（不监听 warmTick ☠）
    //   ⇒ **先同步把封面解好再返回** ✅（否则控件自己那次用错 key 解密必然失败 ⇒ 图一直空 ☠）
    await warmCoversSync(out, max: 12);
    if (AppSettings.i.logConsole) {
      debugPrint('[LIST] ${_f.site.name} 入口=搜索 页=1 kwLen=${kw.length} '
          '条=${out.length} ms=${sw.elapsedMilliseconds}');
    }
    return out;
  }

  // ===== 五、详情（只认数字 id ✅ ⇒ 地址里带 id ✅）=====

  static int _idOf(String url) {
    final m = RegExp(r'/drama/(\d+)').firstMatch(url);
    return m == null ? 0 : (int.tryParse(m.group(1)!) ?? 0);
  }

  /// 详情页用的接口：JSON（`{success, code, message, data}` ✅）
  Future<Map<String, dynamic>?> _getJson(String path, String entry) async {
    try {
      final r = await _f.client
          .get(Uri.parse('$_kBase$path'), headers: {'User-Agent': Site.ua})
          .timeout(_kTimeout);
      if (r.statusCode != 200) {
        if (AppSettings.i.logConsole) {
          debugPrint('[DETAIL] ${_f.site.name} 入口=$entry code=${r.statusCode} ⇒ 失败');
        }
        return null;
      }
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map || j['success'] != true) {
        if (AppSettings.i.logConsole) {
          debugPrint('[DETAIL] ${_f.site.name} 入口=$entry '
              'success=${j is Map ? j['success'] : '?'} ⇒ 失败');
        }
        return null;
      }
      final d = j['data'];
      return d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (e) {
      if (AppSettings.i.logConsole) {
        debugPrint('[DETAIL] ${_f.site.name} 入口=$entry 异常：$e');
      }
      return null;
    }
  }

  @override
  Future<ArticleDetail> detail(String url) async {
    final id = _idOf(url);
    if (id <= 0) throw Exception('荔枝短剧：详情地址里没有数字 id（$url）');
    final d = await _getJson('/api/v1/drama/$id', '详情');
    if (d == null) throw Exception('荔枝短剧：详情拿不到（id=$id）');
    final epsRaw = await _f.client
        .get(Uri.parse('$_kBase/api/v1/drama/$id/episodes'),
            headers: {'User-Agent': Site.ua})
        .timeout(_kTimeout);
    var eps = <Map<String, dynamic>>[];
    try {
      final j = jsonDecode(utf8.decode(epsRaw.bodyBytes));
      final list = (j is Map) ? j['data'] : null;
      if (list is List) {
        eps = [
          for (final e in list)
            if (e is Map) Map<String, dynamic>.from(e)
        ];
      }
    } catch (_) {
      // 分组解析失败 ⇒ 空选集（下面 videos 空 ⇒ 详情页"无视频" ✅ 不静默：打了日志 ✅）
      if (AppSettings.i.logConsole) {
        debugPrint('[DETAIL] ${_f.site.name} 剧集列表解析失败（id=$id）');
      }
    }

    final now = DateTime.now().microsecondsSinceEpoch;
    final videos = <ArticleVideo>[];
    var firstDur = 0; // ★ DEVLOG:17「时长」用：第 1 集（可播那集）的秒数 ✅
    for (final e in eps) {
      final epNo = _i(e['epNo']) == 0 ? (videos.length + 1) : _i(e['epNo']);
      final dur = _i(e['durationSeconds']);
      final title = '${e['title'] ?? ''}'.trim();
      // ★ 锁定/不可用口径（改 8 ✅ 用户点名"不重试 5 次"）：
      //   `available == false` ⇒ 没源；`locked`/`preview` 也照字段走（抽样全免费 ✅ 但字段在就照它 ✅）
      final available = e['available'] == true;
      final locked = e['locked'] == true || e['preview'] == true;
      final ok = available && !locked;
      if (ok && firstDur == 0 && dur > 0) firstDur = dur; // ★ 第一集时长（DEVLOG:17 ✅）
      videos.add(ArticleVideo(
        label: ok
            ? (title.isEmpty ? '第$epNo集' : title)
            : '${title.isEmpty ? '第$epNo集' : title}（未解锁）',
        ordinal: epNo,
        sources: const [],
        // ★ 不可用/锁定 ⇒ **不给取流地址** ⇒ 不触发取流、不会"重试 5 次" ✅（照野果"无源"口径 ✅）
        lazyUrl: ok && dur > 0
            ? '$_kPlayTag$id/$epNo/$dur/$now/'
            : (ok ? '$_kPlayTag$id/$epNo/0/$now/' : null),
      ));
    }

    final tags = <MapEntry<String, String>>[];
    final tg = d['tags'];
    if (tg is List) {
      for (final t in tg) {
        if (t is Map) {
          final name = '${t['name'] ?? ''}'.trim();
          final slug = '${t['slug'] ?? ''}'.trim();
          if (name.isNotEmpty && slug.isNotEmpty) tags.add(MapEntry(slug, name));
        }
      }
    }

    final count = _i(d['totalEpisodes']) == 0 ? videos.length : _i(d['totalEpisodes']);
    final view = '${d['displayViewText'] ?? ''}'.trim();
    // ★ 2026-10-12：详情页封面预热（**主封面** ✅ 不阻塞 ✅）
    warmCover('${d['coverUrl'] ?? ''}');

    // ===== ★ 2026-10-12「猜你喜欢」（🛢️ recon-5 实测 + 本机复核 ✅）=====
    //   · **数据就在详情响应里**：`data.related`（与 `/api/v1/drama/<id>/related?size=10` **同值** ✅）
    //     ⇒ **不必额外请求** ✅
    //   · 元素字段 = 与列表卡**完全同一套**（`id/title/slug/coverUrl/totalEpisodes/displayViewText/
    //     coverBadge…` ✅）⇒ **直接复用 [_item]**，不另写一套解析 ✅
    //   · 上限 `size ≤ 20`；本机实测：`/api/v1/drama/505` ⇒ `related` **只有 1 条**（id=452 ✅）
    //   · **缺字段/为空 ⇒ 不显示该区块**（不是错误态 ✅）—— 底座只在 `related` 非空时才画 ✅
    //   · ⚠️ 渲染方 = **底座通用详情页**（`relatedTitle`=「猜你喜欢」+ `relatedAsGrid`=3 列网格都是本类覆写的 ✅）
    //     ⇒ 这一块用的是**共享 `ArticleCard`**（不是本文件的 `_LzCard`）☑️ —— 因为本文件**不许改公共详情页** ✅；
    //     角标显示站点原样（热播/独家…），**集数不在这一块**（要集数得改公共卡片 ☠ 不做）
    final rel = <Article>[];
    final rw = d['related'];
    if (rw is List) {
      for (final x in rw) {
        if (x is! Map) continue;
        final one = _item(Map<String, dynamic>.from(x));
        if (one == null) continue;
        if (_idOf(one.url) == id) continue; // 排掉"自己"（万一同剧出现 ✅）
        rel.add(one);
      }
    }
    warmCovers(rel); // ★ 预热沿用（队列化那套 ✅）⇒ 这一块的封面也能出图 ✅
    // ★ 2026-10-12（用户报"猜你喜欢没封面"）：这一块也是**共享卡片**（不监听 warmTick ☠）
    //   ⇒ **同步预热前 12 张**（含主封面）再返回 ✅
    await warmCoversSync(rel, max: 12);
    await warmCoversSync([
      Article(
          title: '', url: '', cover: '${d['coverUrl'] ?? ''}'.trim(), meta: '')
    ], max: 1); // 详情页主封面（大图）也同步解好 ✅
    if (AppSettings.i.logConsole) {
      debugPrint('[DETAIL] ${_f.site.name} 猜你喜欢 id=$id 条=${rel.length}');
    }
    return ArticleDetail(
      title: '${d['title'] ?? ''}'.trim(),
      time: '${d['publishedAt'] ?? ''}'.trim(), // ★ DEVLOG:17「发布时间」✅
      // ★ DEVLOG:20「分类标签（可点）」—— 分类**标签**走 `tags`（`/tag/<slug>/` ⇒ 本站 [tag] 已实现 ✅）；
      //   ⚠️ 这里**不塞 `categories`**（那是底座的"分类 slug"位）：本站分类页是 **query 式 `?categoryId=`**，
      //     底座那条按 slug 拼路径 ⇒ 会变**死链** ☠ ⇒ 传空（不显示）比给死链好 ✅
      categories: const [],
      // ★ DEVLOG:20「剧照（横滑；点开查看器）」—— 🛢️ **本站详情接口没有剧照字段**（实测 `/api/v1/drama/563`
      //   的 data 键里 **无 `stills`/`images`/`gallery`** ✅）⇒ 按 DEVLOG:43「缺则隐藏」⇒ **传空 ⇒ 整块不显示** ✅
      //   （原来这里塞的是封面图——那是"冒充剧照" ☠ 已去掉 ✅）
      images: const [],
      intro: '${d['description'] ?? ''}'.trim(), // ★ DEVLOG:20「简介」✅
      videos: videos,
      tags: tags,
      related: rel, // ★ DEVLOG:21「推荐视频」：标题取真站叫法 ☑️（见 [relatedTitle] 的说明）；取不到就是空 ⇒ 底座不画 ✅
      seriesPrefix: '',
      // ★ DEVLOG:17「标题 · 发布时间 · 集数 · 时长」⇒ 元信息行给"集数"，`duration` 给"时长" ✅
      duration: _mmss(firstDur), // ★ DEVLOG:17「时长」= 第 1 集可播那集（站点只有每集时长 ✅）
      metaLine: [
        if (count > 0) '共$count集',
        if (view.isNotEmpty) '播放$view',
        if (d['partial'] == true) '连载中',
      ].join(' · '),
    );
  }

  // ===== 六、取流（每次现取 ✅ + 时长核对 ✅）=====

  /// `fetchSources`：**播放时现取**该集地址 ✅（URL 带 `t`+`sign`、约 30 分钟 ⇒ **绝不缓存** ✅）
  ///
  /// 伪地址（[detail] 生成 ✅）：`/lz01/play/<剧id>/<集号epNo>/<声明秒>/<nonce>/`
  ///   · `nonce` 让每次地址都不同（避开底座按地址的缓存 ✅ 不影响接口 ✅）
  ///   · **声明秒**带在地址里，供时长核对用（`episodes[].durationSeconds` ✅）
  ///
  /// ★ **站内相对路径必须拼域名** 🛢️（`playbackUrl` = `/api/v1/cdn/video/…/manifest.m3u8?t=…&sign=…` ✅）
  /// ★ 播放**不需要 Referer/Cookie/特殊 UA** 🛢️（实测）⇒ 只把地址交给播放器 ✅
  @override
  Future<List<String>?> fetchSources(String url) async {
    if (!url.startsWith(_kPlayTag)) return null; // 不是本站在用的伪地址 ⇒ 交回底座老路 ✅
    final seg = url.substring(_kPlayTag.length).split('/');
    if (seg.length < 3) return [];
    final dramaId = int.tryParse(seg[0]) ?? 0;
    final epNo = int.tryParse(seg[1]) ?? 0;
    final declared = int.tryParse(seg[2]) ?? 0;
    if (dramaId <= 0 || epNo <= 0) return [];
    final d = await _getJson('/api/v1/drama/$dramaId/ep/$epNo', '取流');
    if (d == null) return [];
    var u = '${d['playbackUrl'] ?? ''}'.trim();
    if (u.isEmpty) {
      // 照"未解锁/无源"口径 ✅（不重试 5 次 ☑️）
      if (AppSettings.i.logConsole) {
        debugPrint('[SRC] ${_f.site.name} 没有 playbackUrl（未解锁/不可用）'
            ' 剧=${_id8(dramaId)} 集=$epNo');
      }
      return [];
    }
    // ★ 站内相对路径 ⇒ 拼 `https://liz01.com` ✅（绝对地址原样 ✅）
    if (!u.startsWith('http')) u = u.startsWith('/') ? '$_kBase$u' : '$_kBase/$u';
    if (AppSettings.i.logConsole) {
      debugPrint('[SRC] ${_f.site.name} 取流 剧=${_id8(dramaId)} 集=$epNo '
          '地址长度=${u.length}（**不打地址本体** ☠）');
      final dur = _i(d['durationSeconds']) == 0 ? declared : _i(d['durationSeconds']);
      await _checkDuration(u, dur, epNo);
    }
    return [u];
  }

  /// 时长核对（**只读 + 只打日志** ✅）：GET m3u8、求和 `#EXTINF`、与声明秒比 ✅
  ///
  /// 判据：`|Δ| ≤ 2s` ⇒ 命中 ✅；**只打日志/判据，不因不匹配拒播** ✅；
  ///   ⚠️ **`logConsole` 关着时这次请求根本不发** ✅（调用点在开关里 ✅）。
  Future<void> _checkDuration(String m3u8, int declared, int epNo) async {
    if (declared <= 0) {
      debugPrint('[SRC] ${_f.site.name} 时长核对 集=$epNo 跳过（没拿到声明时长）');
      return;
    }
    try {
      final r = await _f.client
          .get(Uri.parse(m3u8), headers: {'User-Agent': Site.ua})
          .timeout(_kTimeout);
      if (r.statusCode != 200) {
        debugPrint('[SRC] ${_f.site.name} 时长核对 集=$epNo 清单 code=${r.statusCode} ⇒ 跳过');
        return;
      }
      final txt = utf8.decode(r.bodyBytes, allowMalformed: true);
      var total = 0.0;
      var n = 0;
      for (final m in RegExp(r'#EXTINF:\s*([0-9]+(?:\.[0-9]+)?)').allMatches(txt)) {
        total += double.tryParse(m.group(1)!) ?? 0;
        n++;
      }
      final sumSec = total.round();
      final dl = sumSec - declared;
      final hit = dl.abs() <= 2;
      debugPrint('[SRC] ${_f.site.name} 时长核对 集=$epNo 声明=${declared}s '
          '清单求和=${sumSec}s（分片 $n）Δ=${dl}s ⇒ 判据=${hit ? '命中' : '不匹配'}'
          '${hit ? '' : '（Δ 偏大优先怀疑前置广告/预告混入 ☑️）'}');
    } catch (e) {
      debugPrint('[SRC] ${_f.site.name} 时长核对 集=$epNo 异常：$e');
    }
  }

  // ===== 七、自管整页（第六个用 sitePage 的站点 ✅）=====

  @override
  Widget? sitePage(BuildContext context, SiteEntry site) =>
      LzHomePage(site: site, ui: this);
}

/// 荔枝短剧整页：顶部 6 tab（照站点导航 ✅）
///
/// 版式：**首页 = 分区行**（小标题 + 横排卡 ✅ 照站点/野果那套）；其它 tab = 网格 + 「加载更多」（路径式分页 ✅）；
///   `分类` = **未验证**（❓ 见文件头）⇒ 只放提示，**不猜地址** ✅。
class LzHomePage extends StatefulWidget {
  final SiteEntry site;
  final Liz01Site ui;
  const LzHomePage({super.key, required this.site, required this.ui});

  @override
  State<LzHomePage> createState() => _LzHomePageState();
}

class _LzHomePageState extends State<LzHomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab =
      TabController(length: Liz01Site.kTabs.length, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        systemOverlayStyle: kStatusOverlay,
        title: Text(widget.site.name),
        centerTitle: true,
        foregroundColor: kTxt,
        actions: [
          // ★ 2026-10-12（用户点名"搜索没做"）：顶栏搜索入口 ——
          //   走**底座通用搜索页** `SearchPage`（输入框 + 3 列卡 + 「无结果」+ 到底提示 ✅），
          //   它内部只调 `Api.search` ⇒ 落到本站 `search()`（`/search/<kw>/` ✅）
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(name: '搜索页'),
                builder: (_) => PageBg(child: SearchPage(site: widget.site)),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: const Color(0xFFE8590C),
          dividerColor: Colors.transparent,
          labelColor:
              AppBg.i.isDark ? const Color(0xFFFFB07A) : const Color(0xFFE8590C),
          unselectedLabelColor:
              AppBg.i.isDark ? Colors.white : const Color(0xFF3A3A3A),
          tabs: [for (final t in Liz01Site.kTabs) Tab(text: t.value)],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          for (final t in Liz01Site.kTabs)
            t.key == '/'
                ? _LzHomeTab(ui: widget.ui, site: widget.site)
                : (t.key == 'category'
                    ? _LzCatTab(ui: widget.ui, site: widget.site)
                    : (t.key == '/rank/week/'
                        ? _LzRankTab(ui: widget.ui, site: widget.site)
                        // ★ 2026-10-12（**用户当场报**"荔枝原创和荔枝精选的子分类还是没做"）：
                        //   这两个 tab 改用 `_LzCatTab` 的**固定通道**模式：
                        //   顶部 = **「全部」**（该通道原始列表 `/original/`、`/featured/` ✅）+ 该通道 L2 子分类 ✅
                        //   依据 `DEVLOG.md:11`（"分类 / 多级标签展开 + 横滑" ✅）+ 分类页 tree 实测清单 ✅
                        : (t.key == '/original/'
                            ? _LzCatTab(
                                ui: widget.ui,
                                site: widget.site,
                                fixedChannel: 0,
                                basePath: '/original/')
                            : (t.key == '/featured/'
                                ? _LzCatTab(
                                    ui: widget.ui,
                                    site: widget.site,
                                    fixedChannel: 1,
                                    basePath: '/featured/')
                                : _LzListTab(
                                    ui: widget.ui,
                                    site: widget.site,
                                    path: t.key,
                                    entry: t.value))))),
        ],
      ),
    );
  }
}

/// 首页 tab：分区行（小标题 + 横排卡 ✅）
class _LzHomeTab extends StatefulWidget {
  final Liz01Site ui;
  final SiteEntry site; // ★ 点卡进详情要用（照野果 ✅）
  const _LzHomeTab({required this.ui, required this.site});

  @override
  State<_LzHomeTab> createState() => _LzHomeTabState();
}

class _LzHomeTabState extends State<_LzHomeTab> {
  List<LzTopic>? _topics;

  @override
  void initState() {
    super.initState();
    widget.ui.homeTopics().then((v) {
      if (mounted) setState(() => _topics = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = _topics;
    if (t == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (t.isEmpty) {
      return Center(child: Text('没拿到首页分区', style: TextStyle(color: kTxtSub)));
    }
    // ★ 监听预热进度（同列表页）：图一解出来就重建 ⇒ 立刻出图 ✅
    return ValueListenableBuilder<int>(
      valueListenable: widget.ui.warmTick,
      builder: (_, tick, __) => ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: t.length,
        itemBuilder: (ctx, i) {
          final topic = t[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ★ 2026-10-12（用户点名"你漏了「查看更多」" ✅）：标题右侧「查看更多 ›」
            //   ⇒ 目标是**站点自己给的 href**（`home-head__more` ✅ 见 [LzTopic.more]）
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(topic.title,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: kTxt)),
                  ),
                  if (topic.more.isNotEmpty)
                    InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          settings: const RouteSettings(name: '分区页'),
                          builder: (_) => PageBg(
                            child: _LzSectionPage(
                              ui: widget.ui,
                              site: widget.site,
                              path: topic.more,
                              title: topic.title,
                            ),
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Text('查看更多 ›',
                            style: TextStyle(fontSize: 13, color: kTxtSub)),
                      ),
                    ),
                ],
              ),
            ),
            // ★ 高度按算术配：封面 120×4/3=160 + gap 4 + 标题 2×14.4=28.8 + 播放量 13.2 ≈ 206
            //   ⇒ 给 212（**留 6px 余量**）；文本块另有 Flexible 兜底 ⇒ 永不溢出 ✅
            SizedBox(
              height: 212,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: topic.items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, j) => SizedBox(
                    width: 120,
                    child: _LzCard(
                      a: topic.items[j],
                      tick: tick,
                      eps: widget.ui.epsOf[topic.items[j].url] ?? 0,
                      // ★ 左上角 = 站点角标（`a.badge` 现在是集数 ☠ ⇒ 站点角标走侧表 ✅）
                      topBadge: widget.ui.siteBadgeOf[topic.items[j].url] ?? '',
                      score: widget.ui.scoreOf[topic.items[j].url] ?? '',
                      // ★ 点卡 ⇒ 详情页（照野果模式 ✅）
                      onTap: () =>
                          lzOpenDetail(context, widget.site, topic.items[j]),
                    )),
              ),
            ),
          ],
        );
        },
      ),
    );
  }
}

/// 列表 tab：网格 + 「加载更多」（**路径式分页** ✅ `?page=` 是坑 ☠）
class _LzListTab extends StatefulWidget {
  final Liz01Site ui;
  final SiteEntry site; // ★ 点卡进详情要用 ✅
  final String path;
  final String entry;
  const _LzListTab(
      {required this.ui,
      required this.site,
      required this.path,
      required this.entry});

  @override
  State<_LzListTab> createState() => _LzListTabState();
}

class _LzListTabState extends State<_LzListTab> {
  final List<Article> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    setState(() => _loading = true);
    final r = await widget.ui.listPage(widget.path, _page, widget.entry);
    if (!mounted) return;
    setState(() {
      _items.addAll(r);
      _loading = false;
      if (r.isEmpty) _done = true;
      _page++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // ★ 监听预热进度：[Liz01Site.warmTick] 一变就重建 ⇒ 刚解出来的封面**立刻出图** ✅
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) _more();
        return false;
      },
      child: ValueListenableBuilder<int>(
        valueListenable: widget.ui.warmTick,
        builder: (_, tick, __) => GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            // 3:4 封面 + 两行字 ✅；按算术：卡宽≈115 ⇒ 封面 153.8 + 4 + 28.8 + 13.2 ≈ 200
            //   ⇒ 0.55（=高 209.7）**留足余量**；文本块另有 Flexible 兜底 ⇒ 不溢出 ✅
            childAspectRatio: 0.55,
          ),
          itemCount: _items.length + 1,
          itemBuilder: (ctx, i) {
            if (i >= _items.length) {
              if (_done) {
                return Center(
                    child: Text('没有更多了',
                        style: TextStyle(fontSize: 12, color: kTxtSub)));
              }
              if (_items.isEmpty && !_loading) {
                return Center(
                    child: Text('没拿到列表（字段/结构待验证）',
                        style: TextStyle(fontSize: 12, color: kTxtSub)));
              }
              return const Center(child: CircularProgressIndicator());
            }
            return _LzCard(
              a: _items[i],
              tick: tick,
              eps: widget.ui.epsOf[_items[i].url] ?? 0,
              topBadge: widget.ui.siteBadgeOf[_items[i].url] ?? '',
              score: widget.ui.scoreOf[_items[i].url] ?? '',
              onTap: () => lzOpenDetail(context, widget.site, _items[i]),
            );
          },
        ),
      ),
    );
  }
}

/// **分区整页**（「查看更多 ›」⇒ 站上给的那个地址 ✅，如 `/original/`、`/topic/xianzhe/` ✅）
///
/// 版式与列表 tab 完全同款（网格 + 上拉加载 ✅）—— 只是路径来自**站点自己的 href** ✅
/// （分页 = 路径式 `<path>page/<n>/` ✅：`/original/page/2/` **实测有效** ✅；
///  `/topic/<slug>/page/<n>/` 属 🔍 推断（同一套路径式），拉不到就自然"没有更多了" ✅）
class _LzSectionPage extends StatelessWidget {
  final Liz01Site ui;
  final SiteEntry site; // ★ 点卡进详情要用 ✅
  final String path;
  final String title;
  const _LzSectionPage(
      {required this.ui,
      required this.site,
      required this.path,
      required this.title});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          systemOverlayStyle: kStatusOverlay,
          title: Text(title),
          centerTitle: true,
          foregroundColor: kTxt,
        ),
        body: _LzListTab(ui: ui, site: site, path: path, entry: title),
      );
}

/// 未验证 tab 的占位（**不猜地址** ✅）—— 现在只剩应急用（当前没有 tab 用它 ✅）
// ignore: unused_element
class _LzTodoTab extends StatelessWidget {
  final String name;
  const _LzTodoTab(this.name);

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '$name：地址形态未验证 ⇒ 本期不做（等实测后再补）',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: kTxtSub),
          ),
        ),
      );
}

/// 通用网格体（分类/榜单共用 ✅）：**卡片 + 集数 + 预热 tick + 点卡进详情** 都与别处一致 ✅
class _LzGridList extends StatelessWidget {
  final List<Article> items;
  final bool loading;
  final bool done;
  final int tick;
  final Liz01Site ui;
  final SiteEntry site;

  /// 空态文案 = `该分类暂无内容`（**不静默** ✅）；榜单已改成"行列表"（见 [_LzRankRow]）⇒ 本网格不再有榜单模式 ✅
  const _LzGridList({
    required this.items,
    required this.loading,
    required this.done,
    required this.tick,
    required this.ui,
    required this.site,
  });

  @override
  Widget build(BuildContext context) => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.55,
        ),
        itemCount: items.length + 1,
        itemBuilder: (ctx, i) {
          if (i >= items.length) {
            if (items.isEmpty && !loading) {
              // ★ 空/失败态：**照口径明说**（不重试、不转圈 ✅）
              return Center(
                  child: Text('该分类暂无内容',
                      style: TextStyle(fontSize: 13, color: kTxtSub)));
            }
            if (done) {
              return Center(
                  child: Text('没有更多了',
                      style: TextStyle(fontSize: 12, color: kTxtSub)));
            }
            return const Center(child: CircularProgressIndicator());
          }
          return _LzCard(
            a: items[i],
            tick: tick,
            eps: ui.epsOf[items[i].url] ?? 0,
            // 左上角 = **站点角标**（侧表 ✅，因为 `badge` 现在是集数 ☠）
            topBadge: ui.siteBadgeOf[items[i].url] ?? '',
            score: ui.scoreOf[items[i].url] ?? '', // ★ 右上角评分 ✅
            onTap: () => lzOpenDetail(context, site, items[i]),
          );
        },
      );
}

/// **分类 tab**（用户口径："子分类 tab 跟同级子分类" ✅）
///
/// 版式：顶部 **通道（荔枝原创 / 荔枝精选）** ⇒ 下面**横滑的"同级子分类 tab"**（该通道的 L2 ✅）
///   ⇒ 再下面**三级题材 chips（只放卡数 ≥3 的 14 个 ✅）** ⇒ 网格列表（**路径+query 分页** ✅）
///
/// ★ 2026-10-12（**用户当场报**："荔枝原创和荔枝精选的子分类还是没做" ✅）：
///   同一个组件加 `fixedChannel`（固定通道、**不显示通道行与三级行**）——
///   `_l2 == -1` = **「全部」**（走该通道的原始列表 [basePath]，如 `/original/`、`/featured/` ✅）；
///   其余 = 该通道的 L2 子分类 ⇒ 走 `?categoryId=<id>` ✅。
///   依据：`DEVLOG.md:11`「站点页 — 顶部 tab 照真站；**分类 / 多级标签展开 + 横滑**」✅
///   + 分类页 tree 实测清单（recon 逐节点，2026-10-12 ✅ 见 [Liz01Site.kChannels] ✅）
class _LzCatTab extends StatefulWidget {
  final Liz01Site ui;
  final SiteEntry site;

  /// null = 分类 tab 本体（有通道行）；0/1 = 固定到第 N 个通道（原创/精选 tab ✅）
  final int? fixedChannel;

  /// 「全部」时走的路径（仅 fixedChannel != null 时用 ✅）
  final String basePath;
  const _LzCatTab(
      {required this.ui,
      required this.site,
      this.fixedChannel,
      this.basePath = ''});

  @override
  State<_LzCatTab> createState() => _LzCatTabState();
}

class _LzCatTabState extends State<_LzCatTab> {
  int _ch = 0; // 通道
  /// 排序 key：固定通道（原创/精选）= [Liz01Site.kTopicSorts] 的值（**默认 `hot` = 当前热播** ✅）；
  /// 分类 tab = [Liz01Site.kCatSorts] 的值（**默认 `latest` = 最新** ✅）—— 🛢️ 两套都是 HAR 实测默认 ✅
  String _sortKey = 'hot';
  int _days = 0; // 时间筛选：0 = 全部（🛢️ `publishedWithinDays` = 7|14|30|90 ✅）
  /// 弹窗**已应用**的分类筛选（`categoryId`，0 = 不筛 ✅）—— 弹窗里是临时值、点「筛选」才落这里 ✅
  int _catSel = 0;
  final List<Article> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _done = false;

  static const String _kTopicSlug0 = 'lizhi-original'; // 通道 31（HAR 实测 ✅）
  static const String _kTopicSlug1 = 'lizhi-picked'; // 通道 32（HAR 实测 ✅）

  bool get _fixed => widget.fixedChannel != null;

  String get _slug => _ch == 0 ? _kTopicSlug0 : _kTopicSlug1;

  @override
  void initState() {
    super.initState();
    if (_fixed) {
      _ch = widget.fixedChannel!;
      _sortKey = 'hot'; // 原创/精选默认「当前热播」✅
    } else {
      _sortKey = 'latest'; // 分类页默认「最新」✅
    }
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear(); // ★ 切分类**先清空**（不许把两个分类的卡混一起 ☠）
      _page = 1;
      _done = false;
    });
    await _more();
  }

  /// 取数路由（🛢️ **四个接口全实测明文** ✅，见 [Liz01Site.dramaList]/[Liz01Site.topicList] 的注释）：
  ///   · 固定通道（原创/精选） ⇒ `topicList(slug, tab)`（`/api/v1/topic/<slug>?tab=…` ✅）
  ///     ★ 2026-10-12：**子分类档已随"删掉子分类行"一起去掉** ✅（真站该页没有子分类 ✅）
  ///   · 分类 tab ⇒ `dramaList(channelId, [categoryId], [publishedWithinDays], sort)` ✅
  Future<void> _more() async {
    if (_loading || _done) return;
    setState(() => _loading = true);
    final ch = Liz01Site.kChannels[_ch];
    final r = _fixed
        ? await widget.ui.topicList(_slug, _sortKey, _page, '全部')
        : await widget.ui.dramaList(
            channelId: ch.id,
            categoryId: _catSel,
            publishedWithinDays: _days,
            sort: _sortKey,
            page: _page,
            entry: '分类');
    if (!mounted) return;
    setState(() {
      _items.addAll(r.items);
      _loading = false;
      _page++;
      if (!r.hasMore || r.items.isEmpty) _done = true;
    });
  }

  void _pick(int ch) {
    setState(() => _ch = ch);
    _reload(); // ★ 切完**清空重载** ✅
  }

  /// ★ 2026-10-12（**用户点名纠正：弹窗结构照真站截图** ✅）
  ///
  /// 结构（截图原文）：
  /// ```
  /// 筛选  全部分类                              ✕
  /// 都市        ← L2 = **组标题**
  ///   [全部] 都市 商战 战神 赘婿 逆袭 动作 喜剧  ← 该 L2 的 `children`（🛢️ 实测树 ✅）
  /// 情感
  ///   [全部] 现言 爱情 甜宠 …（11 个）
  /// …（漫剧 / 上新 等组）
  /// 时间
  ///   [全部] 7天内上新 14天内上新 30天内上新 90天内上新   ← 真站放**最后一组** ✅
  ///             [ 重置 ]        [    筛选    ]
  /// ```
  /// 样式：`SimpleDialog` + `DEVLOG.md:44`（**标题 16 · 选项 14 · 选中橙 + 勾** ✅）；
  ///   每组**自带「全部」**（该组默认选中 ✅）；`children` 为空 ⇒ 该组**只显示「全部」**（🛢️ 实测 `cos(486)` 就是空 ✅）
  /// 依据：`GET /category/` 的 `category-filters-1` 节点（本机实测 2026-10-12 ✅，见 [kChannels] 注释 ✅）
  Future<void> _openFilter() async {
    var cat = _catSel;
    var days = _days;
    final ch = Liz01Site.kChannels[_ch];
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => SimpleDialog(
          // 标题行：`筛选`（左）+ `全部分类`（次要文字）+ 右侧 `✕`（关）—— 照截图 ✅
          title: Row(
            children: [
              Text('筛选', style: TextStyle(fontSize: 16, color: kTxt)),
              const SizedBox(width: 10),
              Text('全部分类', style: TextStyle(fontSize: 12, color: kTxtSub)),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.pop(ctx, false),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 18, color: kTxtSub),
                ),
              ),
            ],
          ),
          children: [
            // ① **每个 L2 一组**（组标题 = L2 名；组内 = 「全部」+ 该 L2 的 children ✅）
            for (var g = 0; g < ch.subs.length; g++)
              _dlRow(ch.subs[g].name, [
                (
                  label: '全部',
                  on: cat == 0, // 该组默认 ✅
                  tap: () => setD(() => cat = 0)
                ),
                for (final k in ch.subs[g].children)
                  (
                    label: k.name,
                    on: cat == k.id,
                    tap: () => setD(() => cat = cat == k.id ? 0 : k.id)
                  ),
              ]),
            // ② 时间行（真站放**最后一组** ✅；真值 `publishedWithinDays=7|14|30|90`，"全部"不带 ✅）
            _dlRow('时间', [
              (label: '全部', on: days == 0, tap: () => setD(() => days = 0)),
              for (final d in const [7, 14, 30, 90])
                (
                  label: '$d天内上新',
                  on: days == d,
                  tap: () => setD(() => days = d)
                ),
            ]),
            // ③ 底部：`重置`（描边）+ `筛选`（大填充）—— 照截图 ✅
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setD(() {
                        cat = 0;
                        days = 0;
                      }),
                      child: const Text('重置'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('筛选'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (res == true) {
      setState(() {
        _catSel = cat;
        _days = days;
      });
      _reload();
    }
  }

  /// 弹窗里的一行（标题 + 横排 options；**选中橙 + 勾** ✅ 照 `DEVLOG.md:44`）
  Widget _dlRow(String title, List<({String label, bool on, VoidCallback tap})> items) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: kTxtSub)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in items)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: t.tap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: t.on ? const Color(0xFFE8590C) : Colors.transparent,
                      border: t.on
                          ? null
                          : Border.all(color: const Color(0x593C3C3C)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(t.on ? '${t.label} ✓' : t.label,
                        style: TextStyle(
                            fontSize: 14, // ★ DEVLOG:44 选项 14 ✅
                            color: t.on ? Colors.white : kTxt)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 筛选计数徽标（照真站 `cat-filter-trigger__n` 的判据 ✅）：分类选了 或 时间选了 ⇒ 有值 ✅
  int get _filterN => (_catSel > 0 ? 1 : 0) + (_days > 0 ? 1 : 0);

  // ★ 2026-10-12（**用户点名**："看看 91porna 的子分类是怎么样的" + "不要贴边"）：
  //   旧的 `_chipRow`（横滑 Row + 自配色）**整组删掉** ⇒ 全部改用顶层 [lzChips]（照底座 `_filterChips` ✅）
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.ui.warmTick,
      builder: (_, tick, __) => Column(
        // ★ 2026-10-12（用户："他妈的谁他妈让你居中一坨了"）：`Column` 默认
        //   `crossAxisAlignment: CrossAxisAlignment.center` ⇒ chips 整组（Wrap 只有内容宽）
        //   被**居中** ☠；改成 **stretch** ⇒ 整组铺满可用宽度 ⇒ `Wrap` 左起 ✅
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ① **排序行**（🔴 2026-10-12 照真站**行的顺序**改：真站 `/category/` 是
          //   `cat-page__tag`×4（排序）**在通道上面** ✅ —— 原来我做成"通道行在前" ☠ 已调正 ✅）
          //   · 原创/精选：真站 5 个 topic pills（默认「当前热播」✅）
          //   · 分类 tab：真站 4 个 `cat-sort-pills`（默认「最新」✅）+ **`分类筛选` 按钮（带计数徽标 ✅）**
          if (_fixed)
            lzChips([
              for (final s in Liz01Site.kTopicSorts)
                (
                  label: s.value,
                  on: _sortKey == s.key,
                  tap: () {
                    setState(() => _sortKey = s.key);
                    _reload();
                  }
                ),
            ])
          else
            lzChips([
              for (final s in Liz01Site.kCatSorts)
                (
                  label: s.value,
                  on: _sortKey == s.key,
                  tap: () {
                    setState(() => _sortKey = s.key);
                    _reload();
                  }
                ),
              // ★ `分类筛选`：**按钮**，点开弹窗；右侧计数徽标（真站 `cat-filter-trigger__n` ✅）
              (
                label: _filterN > 0 ? '分类筛选 $_filterN' : '分类筛选',
                on: _filterN > 0,
                tap: _openFilter
              ),
            ]),
          // ② **通道行**（只有分类 tab 本体 ✅；真站在排序行**下面** ✅）
          if (!_fixed)
            lzChips([
              for (var i = 0; i < Liz01Site.kChannels.length; i++)
                (
                  label: Liz01Site.kChannels[i].name,
                  on: i == _ch,
                  tap: () => _pick(i)
                ),
            ]),
          // ③ ⛔ **原创/精选 原来那排子分类 chips 已删**（2026-10-12 用户口径 + 真站实测：
          //   真站 `/original/`、`/featured/` 两页**没有子分类行** ☠ —— recon-5 真浏览器 DOM 逐页实测 ✅
          //   ⇒ 这两页只保留：**排序 ×5 + 网格（+分页）** ✅
          //   ☑️ 备注：文件里曾有一条"把它恢复 ✅"的旧注释（来自上一轮）——**与本单口径冲突**，
          //      已按本单（用户最新口径"跟着站点框架有的走"）删除；要回滚只是把这段加回来 ✅）
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
                  _more();
                }
                return false;
              },
              child: _LzGridList(
                items: _items,
                loading: _loading,
                done: _done,
                tick: tick,
                ui: widget.ui,
                site: widget.site,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// **排行榜 tab**（🛢️ 榜单卡是 `{rankNo, drama{…}}` ⇒ 照字段解析 ✅；角标位放 `No.<排名>` ✅）
class _LzRankTab extends StatefulWidget {
  final Liz01Site ui;
  final SiteEntry site;
  const _LzRankTab({required this.ui, required this.site});

  @override
  State<_LzRankTab> createState() => _LzRankTabState();
}

class _LzRankTabState extends State<_LzRankTab> {
  bool _month = false; // 默认周榜 ✅
  final List<Article> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _done = false;

  /// ★ 2026-10-12（照真站）：**首屏只放 5 条**，底部按钮每次再放 5 条 ✅（真站按钮 = `TOP 6 - 50` 就是这意思 ✅）
  int _shown = 5;

  /// ★ 2026-10-12（用户："**排行榜需要自动翻页**"）：**在途标记** ——
  ///   滚到底时 `ScrollNotification` **一帧会来好几次、还会连着来** ☠ ⇒ 光靠 [_more] 的 `_loading`
  ///   挡不住"一次滚动触发多次" ⇒ 加 `_paging`：**在途期间一律忽略**新触发 ✅（与 `_loading` 双保险 ✅）
  bool _paging = false;

  /// ★ **自动翻页 + 底部按钮共用同一个方法** ✅（别写两份 ☠）
  ///   ① 缓冲里还有没露出的 ⇒ 直接多放 5 条（**纯 UI，不发请求** ✅）
  ///   ② 缓冲用光且还有下一页 ⇒ 先拉下一页（[_more]），再放 5 条 ✅
  ///   ③ 已到底（`_done`）⇒ 什么都不做（界面显示「没有更多了」✅）
  Future<void> _loadMore() async {
    if (_paging) return; // ← 在途 ⇒ 忽略（防重复触发 ✅）
    if (_shown < _items.length) {
      setState(() => _shown += 5);
      return;
    }
    if (_done) return;
    _paging = true;
    try {
      await _more();
    } finally {
      _paging = false;
    }
    if (mounted) setState(() => _shown += 5);
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _page = 1;
      _done = false;
      _shown = 5; // ★ 切榜/重载 ⇒ 回到首屏 5 条 ✅
    });
    await _more();
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    setState(() => _loading = true);
    final r = await widget.ui
        .rankItems(month: _month, page: _page, entry: _month ? '月榜' : '周榜');
    if (!mounted) return;
    setState(() {
      _items.addAll(r.items);
      _loading = false;
      _page++;
      if (!r.hasMore || r.items.isEmpty) _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.ui.warmTick,
      builder: (_, tick, __) => Column(
        // ★ 2026-10-12（同上：chips 被 Column 默认 center 居中 ☠）：stretch ⇒ 左起 + 左右各 12 ✅
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ★ 2026-10-12（**用户点名**"你排行榜的子分类都贴他妈边框上去了"）：
          //   这一行原来是**裸 `Row`（padding = 0）** ☠ ⇒ 贴边；现在改用**统一的 [lzChips]** ✅
          //   （= 底座 `_filterChips` 那套：Wrap + 橙底/细描边 + **整组左右各 12**，与网格左边距一致 ✅）
          lzChips([
            for (final m in [false, true])
              (
                label: m ? '月榜' : '周榜',
                on: m == _month,
                tap: () {
                  if (m == _month) return;
                  setState(() => _month = m);
                  _reload();
                }
              ),
          ]),
          // ★ 2026-10-12（🔴 照真站改：**榜单不是网格，是"行列表"** ✅ ——
          //   🛢️ 真站 `/rank/week/` DOM 实测：`div.rank-list > article.rank-card`，元素 =
          //   `span.rank-card__badge.chip.white`（**名次数字**）+ `a.rank-card__poster > img`（竖版海报）
          //   + `a.rank-card__title`（剧名）+ `<n> 播放` + 标签 + 简介 + 「播放正片」+ 集号 chips
          //   + 底部 **「加载更多榜单剧目 (TOP 6 - 50)」** ✅）
          Expanded(
            // ★ 2026-10-12（用户："**排行榜需要自动翻页**"）：滚到底**自动加载** ——
            //   与首页/列表/分类那些 tab **同一套写法** ✅（`pixels >= maxScrollExtent - 300` ✅）；
            //   触发后走的就是**底部按钮那个 [_loadMore]**（共用一份，不写两份 ✅）；
            //   连续触发由 `_paging` 在途标记挡掉 + [_more] 里的 `_loading` 双保险 ✅
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
                  _loadMore();
                }
                return false;
              },
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (var i = 0; i < _items.length && i < _shown; i++)
                    _LzRankRow(
                      ui: widget.ui,
                      site: widget.site,
                      a: _items[i],
                      rank: i + 1, // 名次（接口给的 rankNo 顺序排列 ✅）
                    ),
                  if (_items.isEmpty && !_loading)
                    Center(
                        child: Text('榜单暂时没拿到',
                            style: TextStyle(fontSize: 13, color: kTxtSub))),
                  if (_loading && _items.isEmpty)
                    const Center(child: CircularProgressIndicator()),
                  // ★ 底部按钮**保留**（照真站文案 ✅）—— 与自动翻页共用 [_loadMore] ✅
                  if (_items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 20),
                      child: (_shown < _items.length || !_done)
                          ? OutlinedButton(
                              onPressed: _loadMore,
                              child: Text(
                                  '加载更多榜单剧目 (TOP ${_shown + 1} - 50)'),
                            )
                          : Center(
                              child: Text('没有更多了',
                                  style: TextStyle(
                                      fontSize: 12, color: kTxtSub))),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// **榜单行**（照真站 `article.rank-card` 的元素顺序 ✅）
///   名次 → 竖版小海报 → 剧名 → `<播放量> 播放` → 标签 pills → 简介 → 「播放正片」 → 集号 chips
///   · 点整行 / 点标题 / 点「播放正片」 ⇒ **进详情**（底座详情页 ✅ 集号选择在详情页里做 ✅）
///   · 集号 chips = `1..min(总集数, 12)`（真站就是列到 12 ✅）；点 chips 同样进详情 ✅
class _LzRankRow extends StatelessWidget {
  final Liz01Site ui;
  final SiteEntry site;
  final Article a;
  final int rank;
  const _LzRankRow(
      {required this.ui, required this.site, required this.a, required this.rank});

  @override
  Widget build(BuildContext context) {
    final eps = ui.epsOf[a.url] ?? 0;
    final plays = ui.playsOf[a.url] ?? '';
    final tags = ui.tagsOf[a.url] ?? const <String>[];
    final desc = ui.descOf[a.url] ?? '';
    final score = ui.scoreOf[a.url] ?? '';
    final badgeText = a.badge.replaceFirst('No.', ''); // 名次（rankItems 放进 badge ✅）
    return InkWell(
      onTap: () => lzOpenDetail(context, site, a),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ① 名次（真站 `rank-card__badge` ✅）
            SizedBox(
              width: 26,
              child: Text(badgeText.isEmpty ? '$rank' : badgeText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE8590C))),
            ),
            // ② 竖版小海报
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 56,
                height: 75,
                child: a.cover.isEmpty
                    ? Container(color: const Color(0xFF2A2A2A))
                    : FetchedImage(url: a.cover, memWidth: 160),
              ),
            ),
            const SizedBox(width: 10),
            // ③ 右侧信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: kTxt)),
                  const SizedBox(height: 3),
                  Text(
                      [
                        if (plays.isNotEmpty) '$plays 播放',
                        if (eps > 0) '共$eps集',
                        if (score.isNotEmpty) score,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: kTxtSub)),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final t in tags.take(4))
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: const Color(0x593C3C3C)),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(t,
                                style:
                                    TextStyle(fontSize: 10, color: kTxtSub)),
                          ),
                      ],
                    ),
                  ],
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: kTxtSub)),
                  ],
                  const SizedBox(height: 6),
                  // ④ 「播放正片」+ 集号 chips（1..min(eps,12) ✅）
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      InkWell(
                        onTap: () => lzOpenDetail(context, site, a),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8590C),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('播放正片',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.white)),
                        ),
                      ),
                      if (eps > 0)
                        for (var n = 1; n <= (eps > 12 ? 12 : eps); n++)
                          InkWell(
                            onTap: () => lzOpenDetail(context, site, a),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                border:
                                    Border.all(color: const Color(0x593C3C3C)),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('$n',
                                  style: TextStyle(fontSize: 11, color: kTxt)),
                            ),
                          ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一张卡（3:4 竖封面 + 角标 + 标题 + 播放量 ✅）
///
/// ★ 2026-10-12（**修"黑黄条溢出"** ✅ —— 用户截图 `BOTTOM OVERFLOWED BY 4.0 PIXELS`）：
///   **根因（算术）**：分区行卡宽 120 ⇒ 封面 = 120×4/3 = **160.0**；gap **4**；
///   标题 `fontSize:12` 且**没写 `height`** ⇒ 用字体默认行高（≈1.4）⇒ 2 行 ≈ **33.6**；
///   播放量 `fontSize:11` ⇒ ≈ **15.4** ⇒ 合计 ≈ **213.0**，而外层固定高只有 **210** ⇒ **差 ~3~4px** ✅（与截图吻合）
///   **改法（不用 `clipBehavior` 掩盖 ☠）**：
///   ① 文本行高**写死 1.2**（12×1.2=14.4、11×1.2=13.2 ⇒ 高度可预测 ✅）
///   ② 卡片 `mainAxisSize: min` + **文本块整块 `Flexible`** ⇒ 空间紧时**文本让位**，
///      **任何标题长度都不溢出**（长标题 `maxLines:2 + ellipsis` ✅ 短标题不塌陷 ✅）
///   ③ 外层固定高按①算出的 206 给到 **212**（分区行 ✅，留 6px 余量）
class _LzCard extends StatelessWidget {
  final Article a;

  /// 预热进度（变了就重建 ⇒ **刚解出来的封面立刻出现** ✅ —— 见 [Liz01Site.warmTick]）
  final int tick;

  /// ★ 2026-10-12（用户点名"封面右下角要有集数" ✅）：集数（0 = 不显示）
  ///   —— 站点角标（独家/完结…）**保留原样**，只是**挪到左上角**、右下角让给 `N集`（两者不叠 ✅）
  final int eps;

  /// ★ 2026-10-12（**用户纠正后的分工** ✅）：**左上角**显示什么 ——
  ///   · 普通卡 = **站点角标**（`siteBadgeOf[url]` ✅，因为 `a.badge` 现在放的是**集数** ☠）
  ///   · 榜单卡 = **`No.N`**（排名优先 ✅，取 `a.badge`）
  final String topBadge;

  /// 点卡 ⇒ 详情页（照野果 [lzOpenDetail] ✅）
  final VoidCallback? onTap;
  /// ★ 2026-10-12（🛢️ 真站卡 `span.vcard__score`）：**右上角评分**（如 `9.0分`）——共享卡没有评分位 ⇒ 只给自绘卡 ✅
  final String score;
  const _LzCard(
      {required this.a,
      this.tick = 0,
      this.eps = 0,
      this.topBadge = '',
      this.score = '',
      this.onTap});

  /// 文本行高统一写死（不写就吃字体默认 ≈1.4 ☠ ⇒ 高度算不准）
  static const double _kLine = 1.2;

  @override
  Widget build(BuildContext context) {
    // ★ 2026-10-12（用户点名"点卡没反应 / 详情页没做"）：**整张卡可点** ⇒ 详情页 ✅
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min, // ★ 内容自适应（不再由外层固定高决定 ✅）
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        AspectRatio(
          aspectRatio: 3 / 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 封面（加密图 ⇒ 由本站预热解密后写进磁盘缓存 ✅ 见 warmCovers）
                //   ⚠️ key 带 tick：预热成功后**重建**这个控件 ⇒ 立刻命中磁盘缓存出图 ✅
                FetchedImage(
                    key: ValueKey('$tick|${a.cover}'),
                    url: a.cover,
                    memWidth: 320),
                if (topBadge.isNotEmpty)
                  Positioned(
                    left: 4, // ★ 左上角 = 站点角标（侧表 ✅）/ 榜单卡 = `No.N` ✅
                    top: 4,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(topBadge,
                          style: const TextStyle(
                              fontSize: 10,
                              height: _kLine,
                              color: Colors.white)),
                    ),
                  ),
                // ★ 2026-10-12（🛢️ 真站）：**右上角 = 评分**（`9.0分`）✅
                if (score.isNotEmpty)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(score,
                          style: const TextStyle(
                              fontSize: 10,
                              height: _kLine,
                              color: Colors.white)),
                    ),
                  ),
                // ★ 2026-10-12（用户点名）：**封面右下角 = 集数** ✅（只有拿到 totalEpisodes 才显示）
                if (eps > 0)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('$eps集',
                          style: const TextStyle(
                              fontSize: 10,
                              height: _kLine,
                              color: Colors.white)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        // ★ 文本块**整块 Flexible**：空间不够时由它让位 ⇒ 永不溢出 ✅
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, height: _kLine, color: kTxt)),
              if (a.meta.isNotEmpty)
                Text(a.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, height: _kLine, color: kTxtSub)),
            ],
          ),
        ),
      ],
      ),
    );
  }
}

/// ★ 2026-10-12（**用户点名**："你踏马脑子不好去看看 91porna 的子分类是怎么样的" + "子分类都需要左对齐（不要贴边）"）：
///   **本站所有 chips/子分类行**统一照**底座 `_filterChips`**（`home_page.dart:471-497` ✅）——
///   · `Wrap(spacing: 6, runSpacing: 6)` ⇒ **可换行、天然左对齐** ✅（旧的"横滑 Row"已删 ☠）
///   · chip：`padding h10/v5` + `radius 8` ✅
///   · 选中 = **橙底 `0xFFE8590C`**（白字）✅；未选中 = **透明底 + 细描边 `0x593C3C3C`**（`kTxt` 字）✅
///   · **整组外边距 = `EdgeInsets.fromLTRB(2, 6, 2, 3)`** —— 🛢️ **严格照 `DEVLOG.md:14`**
///     （点播站点第 5 条原文：**排序行间距 `top6 / left2 / right2 / bottom3`** ✅；
///      此前我用的 12 是**网格卡片**的内边距、不是这条规定值 ☠ ⇒ 已按规范改 ✅ 规范优先 ✅）
Widget lzChips(List<({String label, bool on, VoidCallback tap})> items) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 3), // ★ DEVLOG.md:14 原文数值 ✅
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final t in items)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: t.tap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: t.on ? const Color(0xFFE8590C) : Colors.transparent,
                  border: t.on
                      ? null
                      : Border.all(color: const Color(0x593C3C3C)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(t.label,
                    style: TextStyle(
                        fontSize: 12, color: t.on ? Colors.white : kTxt)),
              ),
            ),
        ],
      ),
    );

/// ★ 2026-10-12：点卡 ⇒ 通用详情页（**照野果 `yeguodj.dart:899` 的现成模式** ✅）
///
/// 本站 `detail()` 已实现（`/api/v1/drama/<数字id>` + `/episodes` ✅）；`listCover` 让播放记录零额外请求 ✅
void lzOpenDetail(BuildContext context, SiteEntry site, Article a) {
  Navigator.of(context).push(
    MaterialPageRoute(
      settings: const RouteSettings(name: '详情页'),
      builder: (_) => PageBg(
        child: DetailPage(site: site, baseUrl: a.url, listCover: a.cover),
      ),
    ),
  );
}

/// 本站档案：荔枝短剧（**默认可见**，无隐藏 ✅）
const SiteEntry kSite18 = SiteEntry(
  name: '荔枝短剧',
  template: SiteTemplate.liz01,
  hosts: ['liz01.com'],
  iconUrl: '/favicon.ico',
  assetIcon: 'assets/site_icons/liz01.png', // ★ 2026-10-12 内置图标（抓一次、零网络 ✅；原图 256×256 ⇒ 缩到 128×128）
  portraitCovers: true, // 3:4 竖版封面 ✅（站上就是竖图）
  color: Color(0xFFE53935),
);

