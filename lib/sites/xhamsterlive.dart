// xhamsterlive —— **本站专属**的一切（直播站 ✓）
//
// 站点：`zh.xhamsterlive.com`（xHamsterLive 中文站 ✓）。
// ⚠️ 它和已有的 xHamster（`tw.xhamster.com`）是**两个不同的站** ✗（不同的接口、不同的字段、
// 不同的站点）→ 本站**独立一个文件** ✓，别混进 `xhamster.dart` ✗。
//
// 取数：`GET /api/front/models?...`（JSON ✓）。**UA 必须浏览器样** ✓ —— App 全局 UA 就是
// iPhone Safari ✓（`lib/config.dart` 的 `Site.ua` ✓，取数底座 `SiteFetcher.text` 会带上 ✓）；
// **不需要 cookie** ✓；`curl` 的默认 UA 会被站点 403 ✗。
//
// 实测证据（2026-10-04，本机 `curl.exe` 走系统代理 + iPhone UA + `Referer: https://zh.xhamsterlive.com/`
// + `Accept: …application/json…`，与 App 侧 `SiteFetcher.text` 发出的头一致 ✓）：
//   · 4 个主 tab：`?limit=60&offset=0&primaryTag=girls` + 尾部那串开关 + `specialEventTagIds`
//     → **HTTP 200** ✓，条数/前 3 条与"不带尾部开关"的那条**完全一致** ✓（`winter11|Hahaha_ha2|Puting_q` ✓）
//   · 移动流：`base 60/0&primaryTag=girls&filterGroupTags=[["mobile"]]&parentTag=mobile` → 200 ✓ `filteredCount=1000` ✓
//   · 手机版最新：`filterGroupTags=[["autoTagNew"],["mobile"]]&parentTag=mobile` → 200 ✓ `filteredCount=275` ✓
//     （≠1000 = 这一组**没撞封顶** ✓ → 275 就是它的真实终点 ✓；`/girls/new-mobile` 页 HTML 的前三条
//      是别的名字 ✓ 那是因为**直播数据每分钟都在变** ✗，不是参数错 ✓）
//   · `offset=960` 仍是 60 条 ✓ → **翻页一直能翻到 1000 封顶** ✓
//   · 付费房：每 60 条里 `groupShowType` 非空的 ≈10 个（`ticket` 9 / `perMinute` 1 ✓），
//     其中**有 2 条 `status` 仍是 `public`** ✗ → **只判 `status` 会漏付费房** ✓（简报里那条坑，实测复现 ✓）
//   · 封面 `https://img.doppiocdn.net/snapshot/<id>/<ts>`：**无 UA、无 Referer 也 200** ✓
//     （`image/webp` 11832 字节 ✓）→ 直接交给 `FetchedImage` ✓（它自己带 UA/Referer，不影响 ✓）
//   · 站点 `favicon.ico` → 200（`image/png` 1861 字节 ✓）→ 宫格图标用它 ✓
//
// ⚠️ **播放这条路和模拟器不一样** ✗✗：模拟器走的是"内嵌站点自己的播放器"（CDN 上的 React 组件 +
// `new Function` 加载 ✓）—— 那是**桌面 hack** ✗，App 上用不了 ✗（站点在 iPhone 上故意跳过 JS 播放器、
// 改用原生 `<video>` ✓）→ **App 端自己拼 HLS 直链、用自己的播放器放** ✓
// （pkey + master URL 见下面的 [kLivePkey] / [liveMasterUrl] ✓；2026-10-05 起**不再用 WebView 加载房间页** ✓）。

import 'dart:async'; // Timer（**直播起播看门狗** ✓ 站点文件自己的 ✓ —— 共用件 `web_embed.dart` 已还原、不含它 ✓）
import 'dart:convert';

// ⚠️ 本站是**唯一**要自己画界面的站点（下划线 tab / 房间卡 / 全屏房间页 ✓）→ 必须 import material ✓。
// （其它站点文件只 import `dart:ui show Color` ✗ —— 它们不画界面 ✓；这里的 import 不会引起
//  `Element`/`Text`/`Key` 撞名 ✗，因为本站不 import html/dom ✓ 也不 import encrypt ✓）
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
// ⭐ 2026-10-05（用户拍板）：直播房间页改用 **iOS 原生播放器** —— `video_player` 的 iOS 实现**就是 AVPlayer** ✓
//   （站点自己在 iPhone 上走的就是原生 `<video>` = AVPlayer ✓ 这正是它 ~2 秒出画面的原因 ✓）
//   mpv（`media_kit_video` / `KpPlayer`）那条路已从直播页**整条移除** ✗；`player_widget.dart` **没动** ✓ 别的站点还在用 ✓
import 'package:video_player/video_player.dart';

import '../app_background.dart';
import '../app_bg.dart';
import '../base/fetch.dart';
import '../config.dart' show Site;
// ⚠️ 2026-10-05 用户拍板：直播页的**全量日志已全删** ✗ ⇒ 这里**不再 import `site_error_log.dart`** ✓
//   （公共件 `lib/site_error_log.dart` **本身一字未动** ✓ 别的站点还在用 ✓）
import '../fetched_image.dart';
import '../home_page.dart' show RowsGrid;
import '../sites.dart';

// ===== 一、数据层 =====

/// 每页条数（站点接口的 `limit` ✓）· 服务端**封顶** 1000（`offset` 到 960 还能拿到 60 条 ✓）
const int _kPage = 60;
const int _kLiveMax = 1000;

/// 站点自己那串默认开关（简报原文照抄 ✓）。实测：带上它与不带它**结果一致** ✓（都 200 ✓）——
/// 照简报写全 ✓（不自己删参数 ✗）。
const String _kTail = '&sortBy=stripRanking&nic=true&byw=false&rcmGrp=A&rbCnGr=true'
    '&iem=true&decMb=false&dmv=false&ctryTop=true&mlfv=false&rectf=false'
    '&eab=false&sac=true';

/// `specialEventTagIds=["oktoberfest"]`（站点周年活动标签 ✓）—— **只有 4 个主 tab 带** ✓；
/// 移动流 / 手机版最新**不带** ✓（依据 recon 对 `/girls/mobile` 的直接抓包 ✓）。
/// 这里直接写**编码后的字面量** ✓（= `Uri.encodeQueryComponent('["oktoberfest"]')` ✓，实测用的就是这一串 ✓）。
const String _kSpecialEvent = '&specialEventTagIds=%5B%22oktoberfest%22%5D';

/// 一个 tab → 请求参数（**照简报的表** ✓；6 个 tab 的 `primaryTag` 全部实测可用 ✓）
class LiveTabDef {
  final String name;

  /// 接口的 `primaryTag`（只有 4 个值：girls / couples / men / trans ✓）
  final String primaryTag;

  /// 自带的 `filterGroupTags`（**移动流 / 手机版最新**才有 ✓；4 个主 tab 是空的 ✗）
  final List<List<String>> groups;

  /// 这个 tab 有没有那排**页内过滤器入口** ✓：
  ///     模拟器里 4 个主 tab 本来就有筛选 ✗ 之前 App 漏做了 ✓）
  bool get hasFilterRow => groups.isNotEmpty;




  /// 接口的 `parentTag`（只有带了 `groups` 才拼 ✓）
  final String? parentTag;

  /// 要不要带 `specialEventTagIds`（= 4 个主 tab ✓）
  final bool specialEvent;

  const LiveTabDef(this.name, this.primaryTag,
      {this.groups = const [],
      this.parentTag,
      this.specialEvent = false});
}

/// 6 个 tab（顺序 = 界面上的顺序 ✓；前 4 个是**主分类** ✓，后 2 个是**快捷叶子** ✓）
// 2026-10-05 用户拍板：6 个 tab 的筛选入口全部删掉（渲染 + 两套弹窗 + 那批筛选数据都已移除）。
const List<LiveTabDef> kLiveTabs = [
  // 4 个主 tab（女主播/情侣/男主播/跨性别 ✓）；后 2 个是快捷叶子（移动流/手机版最新 ✓）—— 各自的筛选数据已整体移除 ✓
  LiveTabDef('女主播', 'girls', specialEvent: true),
  LiveTabDef('情侣', 'couples', specialEvent: true),
  LiveTabDef('男主播', 'men', specialEvent: true),
  LiveTabDef('跨性別', 'trans', specialEvent: true),
  // 「移动流」= 4 个主分类共有的**叶子**（女主播的移动流在线最多 ✓）；`mobile` 是它的 tag ✓
  LiveTabDef('移动流', 'girls', groups: [
    ['mobile'],
  ], parentTag: 'mobile'),
  // 「手机版最新」= 两组 **AND** ✓（`autoTagNew` + `mobile` ✓；实测 200 ✓）
  LiveTabDef('手机版最新', 'girls', groups: [
    ['autoTagNew'],
    ['mobile'],
  ], parentTag: 'mobile'),
];

//    生成方式 = 从 `sim/index.html` 的 `MOBILE_FILTERS` **原样抽取** ✓
//    （recon 实测 + sim-dev 落地的最终数据 ✓：顺序 / 显示名 / tagId / 「未映射」全部照抄 ✓）。
//    手抄会抄错 ✗（lead 明确提醒过 ✓）。
// >>> LIVE_FILTERS_DATA_BEGIN


/// 过滤器里的一个**子分组**（界面 = 小标题 + 一行多选 chip ✓；组内多值 = OR ✓）


/// 一个过滤器（外貌 / 国家 / 可请求提供的表演）—— 界面 = **下划线 tab 样式**的 3 个入口 ✓



// ⚠️ 下面这段是**一次性脚本抽取的产物** ✗ 别手改 ✓ —— 数据源 = `sim/index.html` 的 `LIVE_MAIN` + `LIVE_TAG_MAP` ✓
//    （抽取规则：顺序 / 显示名 / tagId / 「未映射」全部原样照抄 ✓、逐层括号匹配不手抄 ✓；脚本已用完删除 ✓
//     —— 以后要改就**按同一规则重跑一次抽取** ✗ 别手改这段 ✗）。
//    ⚠️ 里面每个 `LiveFilter` 都是 **单选**（`single: true` ✓，与 sim 一致 ✓）：点一个换一个 ✓、再点已选 = 取消 ✓；
//    依据（实测 ✓）：`[["tagLanguageChinese"]]` + `parentTag=tagLanguageChinese` → 200 / filteredCount 296 ✓；
//    清掉选择（不带这两件）→ 回到无筛选的 1000 ✓；leaf 那两套多选（移动流/手机版最新）不受影响 ✓。
/// ⚠️ 拆成 4 个具名常量 ✓ —— `const kLiveTabs` 里要按 tab 引用 const 值 ✗ 不能引用列表元素 ✓
/// `女主播` tab 的子分类筛选（7 组 / 58 项 ✓）
/// ⚠️ **单选** ✓（`single: true` —— 与 sim 一致 ✓）：点一个换一个 ✓、再点已选 = 取消 ✓；
/// ⚠️ 拆成 4 个具名常量 ✓ —— `const kLiveTabs` 里要按 tab 引用 const 值 ✗ 不能引用列表元素 ✓
/// `女主播` tab 的子分类筛选（7 组 / 58 项 ✓）
/// `情侣` tab 的子分类筛选（4 组 / 36 项 ✓）
/// `男主播` tab 的子分类筛选（8 组 / 60 项 ✓）
/// `跨性別` tab 的子分类筛选（7 组 / 57 项 ✓）

// <<< LIVE_FILTERS_DATA_END

/// 一个 tab 的**已选过滤器状态** ✓
///
/// ⚠️ 分桶粒度 = **子分组** ✓（键 `<过滤器key>#<子分组名>` → tagId 数组 ✓）：同组多值 = OR ✓、
///    组与组之间 = AND ✓。依据 lead 实测：`mobile + ageTeen + ethnicityAsian + bodyTypePetite
///    + doAnal → 5 条` ✓（年龄/种族/体型各占一组 ✓）——整个过滤器当一桶会把 AND 变成 OR ✗。
/// ⚠️ **按 tab 各一份** ✓（「移动流」和「手机版最新」互不影响 ✓ —— 页面里按下标各存一个 ✓）。
/// ⚠️ 未映射项（没有 tagId 的标签）**不写进来** ✓（点了不过滤、也不硬猜 id ✓）。


/// 一条直播房（`models[]` 里**可显示**的那些 ✓）
class LiveRoom {
  /// 房间名 = 站内路径末段 ✓（房间页地址 = `https://zh.xhamsterlive.com/<username>` ✓）
  final String username;

  /// 观看人数（`viewersCount` ✓）
  final int viewers;

  /// 正在播（`isLive` ✓）；"在线但没在播"是 false ✓（封面用的是模糊档 ✓）
  final bool isLive;

  /// 封面（直播中 = 清晰档 ✓ / 没在播 = 模糊档 ✓）
  final String cover;

  /// 站点返回的 **model id**（列表接口的 `id` ✓）—— 直播流 URL 靠它拼 ✓
  ///（见 [liveMasterUrl] ✓；2026-10-05 用户拍板：房间页改用**我们自己的播放器** ✓）
  final int id;

  const LiveRoom({
    required this.username,
    required this.viewers,
    required this.id,
    required this.isLive,
    required this.cover,
  });
}

/// 一页结果：**显示用的**（已筛掉付费房 ✓）+ **"到底"判据用的原始数** ✓
class LivePageResult {
  final List<LiveRoom> rooms;

  /// 这一页接口**原始**返回多少条（**"到底"必须用原始累计数** ✗ 别用筛完的 —— 用筛完的永远到不了 ✓）
  final int raw;

  /// 服务端的 `filteredCount`（封顶 1000 ✓）
  final int filteredCount;

  const LivePageResult(
      {required this.rooms, required this.raw, required this.filteredCount});
}

int _intOf(Object? v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;

/// **能不能显示**（用户明确要求：**付费房一律跳过** ✓，6 个 tab 一视同仁、翻页也一样 ✓）
///
/// ⚠️ 三件事**都要判** ✗：
///   ① `groupShowType` 空 = 免费 ✓（`ticket` = 门票房 / `perMinute` = 按分钟 都跳过 ✗）；
///   ② 只看 `status` **会漏** ✗ —— "已预告门票秀"是 `status='public'` + `groupShowType='ticket'` ✓
///      （实测 60 条里有 2 条就是这种 ✓）；
///   ③ `isOnline` 必须为真 ✓。
/// ⚠️ **不要**用 `doPrivate`/`doSpy`/`privateRate`/`spyRate`/`publicRecordingsRate` 判断 ✗ ——
///    那些只是"主播提供付费服务"的**能力标志** ✓，85%~90% 的**免费房也带** ✗，用了会把免费房全杀掉 ✗。
/// ⚠️ 字段缺失时：`groupShowType` 当**免费**算 ✓（免得字段一没整页被清空 ✗）；`status` 缺失 = 不显示 ✗。
bool _showable(Map<dynamic, dynamic> m) =>
    (m['groupShowType'] ?? '').toString().isEmpty &&
    (m['status'] ?? '').toString() == 'public' &&
    m['isOnline'] == true;

/// 本站取数（走公共底座 [SiteFetcher] ✓ —— 域名轮换 / 8 秒超时 / 5xx 重试 / UA / 错误日志都在那儿 ✓）
class XhLiveApi {
  XhLiveApi(this._f);

  final SiteFetcher _f;

  /// 拉一页房间（**已经筛掉付费房** ✓）。`offset` 步长 60 ✓，服务端封顶 1000 ✓。
  ///
  /// [extra] = 页内过滤器选的组 ✓（每个**有选择的子分组**一个数组 ✓，接在 tab 自带的组**后面** ✓；
  /// 不选就是空的 ✓ → 请求与第一批**一模一样** ✓ 行为不变 ✓）。
  /// [parentTag] = **单选过滤器（4 个主 tab）**当前选中的那一个 tag ✓（多选那套不用传 ✗ 见 [_path] ✓）。
  Future<LivePageResult> list(LiveTabDef tab, int offset,
      {List<List<String>> extra = const [], String parentTag = ''}) async {
    final txt = await _f.text(_path(tab, offset, extra, parentTag: parentTag));
    final j = jsonDecode(txt) as Map<String, dynamic>;
    final raw = j['models'] is List ? j['models'] as List : const <dynamic>[];
    final rooms = <LiveRoom>[];
    for (final m in raw) {
      if (m is! Map) continue;
      if (!_showable(m)) continue; // 付费房 / 非公开 / 离线 ✗
      final un = (m['username'] ?? '').toString();
      if (un.isEmpty) continue; // 没名字 → 进去就是坏页面 ✗（别把它放到列表里 ✗）
      final id = _intOf(m['id']);
      final live = m['isLive'] == true;
      rooms.add(LiveRoom(
        username: un,
        id: id, // 直播流 URL 要用它 ✓（见 liveMasterUrl ✓）
        viewers: _intOf(m['viewersCount']),
        isLive: live,
        // 封面：直播中 → 清晰档 ✓；在线但没播 → **模糊档** ✓（两个地址都是站点给的 ✓，CDN 不挑 UA/Referer ✓）
        cover: 'https://img.doppiocdn.net/'
            '${live ? 'snapshot' : 'snapshot_blurred'}/$id/'
            '${(m['snapshotTimestamp'] ?? '').toString()}',
      ));
    }
    return LivePageResult(
        rooms: rooms, raw: raw.length, filteredCount: _intOf(j['filteredCount']));
  }

  /// 拼请求路径（顺序照简报 ✓：`limit`/`offset`/`primaryTag` → 可选的两件 → 尾巴 → 活动标签 ✓）
  /// 组 = **该 tab 自带的**（`tab.groups` ✓）在前 + 页内/子分类筛选取的 ✓ 在后（照 lead 的拼装规则 ✓）。
  /// ⚠️ `parentTag` 分两条口径（用户 2026-10-05 拍板：4 主 tab 以 sim 为准 ✓）：
  ///   · 多选那套（移动流 / 手机版最新 ✓）= tab 自带的 `tab.parentTag`（`mobile` ✓）
  ///   · **单选那套（4 个主 tab ✓）= 当前选中的那一个 tag** ✓（[parentTag] 传进来 ✓；没选＝空 → 整个
  ///     `filterGroupTags`/`parentTag` 都不带 ✓，与"没筛选"那条请求一模一样 ✓）
  /// 实测（单选口径 ✓）：`[["ageMilf"]]` + `parentTag=ageMilf` → trans `filteredCount=57` ✓、
  ///   girls `432` ✓；`[["orientationStraight"]]` + 同名 parentTag → men `136` ✓。
  String _path(LiveTabDef tab, int offset, List<List<String>> extra,
      {String parentTag = ''}) {
    final groups = <List<String>>[...tab.groups, ...extra];
    final b = StringBuffer('/api/front/models?limit=$_kPage&offset=$offset'
        '&primaryTag=${tab.primaryTag}');
    if (groups.isNotEmpty) {
      // ⚠️ 必须按 JSON 形态编码 ✓（`[["mobile"]]` → `%5B%5B%22mobile%22%5D%5D` ✓ —— 实测用的就是这一串 ✓）。
      // 用 `encodeComponent` ✓：Dart 文档原文「除字母/数字/`-_.!~*'()` 外全部百分号编码」✓
      // （= ECMA-262 的 `encodeURIComponent` 那套 ✓，与模拟器发出去的一致 ✓）
      // → `[` `]` `"` `,` 都会被转义 ✓（`encodeQueryComponent` 对这几个字符**也是转义**的 ✓
      //    —— 文档原文「不是数字/字母/`-._~` 的都编码」✓ —— 两者对这串等价 ✓，取前者因为语义更贴"一个 JSON 值" ✓）
      b.write('&filterGroupTags=${Uri.encodeComponent(jsonEncode(groups))}');
      b.write('&parentTag=${tab.parentTag ?? (parentTag.isNotEmpty ? parentTag : groups.first.first)}');
    }
    b.write(_kTail);
    if (tab.specialEvent) b.write(_kSpecialEvent);
    return b.toString();
  }
}

/// 一个 tab 的房间列表状态（**每个 tab 各一份** ✓ —— 切 tab / 从房间页回来**都不重拉** ✓）
class LiveFeed extends ChangeNotifier {
  LiveFeed(this._api, this.tab);

  final XhLiveApi _api;
  final LiveTabDef tab;

  final List<LiveRoom> rooms = [];
  int _offset = 0;
  int _raw = 0;
  bool _loading = false;
  bool _done = false;

  /// 「进行筛选」用的作废计数 ✓：在途的旧请求回来时，`_gen` 已经变了 → 结果丢掉 ✗
  /// （不然旧筛选的房间会追加进刚清空的列表 ✗ —— 用户会看到"筛选了但还有旧房间"）
  int _gen = 0;

  bool error = false;

  /// 错误**原文**（界面上直接显示原因 ✓ —— 只存 bool 的话分不清"还在转圈"和"已经失败" ✗）
  String errorText = '';

  bool get done => _done;
  bool get loading => _loading;

  Future<void> ensureMore() async {
    if (_loading || _done) return;
    _loading = true;
    final gen = _gen;
    try {
      // 2026-10-05：筛选机制已整体移除 ⇒ 这里不再传那两个可选参数 ✓
      //   为什么等价：那两个参数的默认值本来就是"空"，而且已经没有任何地方能写入筛选值 ✓
      //   ⇒ 请求 URL 与移除前逐字节相同 ✓
      final r = await _api.list(tab, _offset);
      if (gen != _gen) return; // 列表被重置过一轮 ⇒ 这次请求作废 ✗
      rooms.addAll(r.rooms);
      _raw += r.raw;
      _offset += _kPage;
      error = false;
      // 「到底」三条判据（任一成立即停 ✓）：这页空 / 到服务端给的条数 / 撞 1000 封顶
      // ⚠️ 计数用**原始条数** ✗ 别用筛完的（否则永远到不了 ✓）；⚠️ `filteredCount` 是**带筛选后**的
      //    服务端计数 ✓（实测：外貌+国家叠加后它会变小 ✓）→ 换了筛选必须从 offset=0 重来 ✓ 见 `reload`
      if (r.raw == 0) {
        _done = true;
      } else if (r.filteredCount > 0 && _raw >= r.filteredCount) {
        _done = true;
      } else if (_offset >= _kLiveMax) {
        _done = true;
      }
    } catch (e) {
      if (gen != _gen) return;
      errorText = e.toString();
      error = true;
      _done = true; // 失败不自动重试（避免死循环 ✗）→ 界面给「重试」✓
    } finally {
      if (gen == _gen) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// 「重试」（错误态那颗按钮 ✓）：清掉错误、接着当前 offset 再拉 ✓
  void retry() {
    if (_loading) return;
    error = false;
    errorText = '';
    _done = false;
    notifyListeners();
    ensureMore();
  }

  /// 「进行筛选」/「重置」→ **清空重拉** ✓（offset 归 0 ✓ 因为带筛选的 `filteredCount` 是另一套 ✓；
  /// 付费房照旧逐条筛 ✓ —— 筛选和付费过滤是**叠加**的 ✓，翻页也一样 ✓）。
  void reload() {
    _gen++; // 在途的旧请求作废 ✗（它回来时 gen 对不上 → 直接丢掉 ✓）
    _loading = false;
    rooms.clear();
    _offset = 0;
    _raw = 0;
    _done = false;
    error = false;
    errorText = '';
    notifyListeners();
    ensureMore();
  }
}

// ===== 二、界面 =====

/// **直播站点页**：6 个下划线 tab + 2 列竖版房间卡（滚动到底续拉 ✓）。
/// ⚠️ 点卡片 = **全屏 WebView 房间页** ✓（不是详情页 ✗）—— 见 [LiveRoomPage] 的注释 ✓。
class LiveSitePage extends StatefulWidget {
  final SiteEntry site;
  const LiveSitePage({super.key, required this.site});

  @override
  State<LiveSitePage> createState() => _LiveSitePageState();
}

class _LiveSitePageState extends State<LiveSitePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab =
      TabController(length: kLiveTabs.length, vsync: this);

  /// 本站取数（底座的 SiteFetcher：域名 / UA / 超时 / 错误日志都归它 ✓）
  late final XhLiveApi _api = XhLiveApi(SiteFetcher(widget.site));

  /// 每个 tab 一份列表状态（切 tab 回来不重拉 ✓）
  final Map<int, LiveFeed> _feeds = {};

  LiveFeed _feedOf(int i) =>
      _feeds.putIfAbsent(i, () => LiveFeed(_api, kLiveTabs[i]));

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 整页跟着背景明暗重建（tab 文字 / 尾项文字 / 错误文字都读 kTxt ✓）
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => _pageView(context),
    );
  }

  Widget _pageView(BuildContext context) {
    return Scaffold(
      // 透明：让根层背景图透出来（顶栏也透明，见 main.dart 的 theme ✓）
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        systemOverlayStyle: kStatusOverlay,
        title: Text(widget.site.name),
        centerTitle: true,
        foregroundColor: kTxt,
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          // ⚠️ 2026-10-05 用户真机反馈：**6 个 tab 的间距缩短一点点** ✓
          //    依据（Flutter 3.24.5 源码 `packages/flutter/lib/src/material/tabs.dart:1683` +
          //    `constants.dart` 的 `kTabLabelPadding`）：**没设 labelPadding 时每侧 16** ✓
          //    → 相邻两个 tab 文字之间 = 16+16 = **32px** ✗。这里改成每侧 **10** ✓ → 相邻 **20px** ✓
          //    （只动间距 ✗ 不动布局：仍 `tabAlignment.start` + 横向可滚 ✓；选中态橙下划线/字色/字重照旧 ✓）
          labelPadding: const EdgeInsets.symmetric(horizontal: 10),
          // **下划线 tab**（用户指定 ✓）：选中 = 橙字加粗 + 2px 下划线
          // ⚠️ 2026-10-05 用户真机反馈：**行底那条分隔线不要**（`dividerColor` 置透明 ✓，
          //    不是删 TabBar 的线 —— 选中态的 2px 橙下划线由 `indicatorColor` 画，仍保留 ✓）
          // ⚠️ 不是胶囊按钮 ✗（胶囊那套是子分类行的样式 ✓，别混 ✗）
          indicatorColor: const Color(0xFFE8590C),
          indicatorWeight: 2,
          dividerColor: Colors.transparent,
          labelColor: AppBg.i.isDark
              ? const Color(0xFFFFB07A)
              : const Color(0xFFE8590C),
          unselectedLabelColor:
              AppBg.i.isDark ? Colors.white : const Color(0xFF111111),
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 14),
          tabs: [
            for (final t in kLiveTabs) Tab(text: t.name),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          for (var i = 0; i < kLiveTabs.length; i++)
            _LiveFeedView(key: ValueKey(i), feed: _feedOf(i)),
        ],
      ),
    );
  }
}

/// 一个 tab 的房间列表（2 列竖版卡 + 滚到底续拉 ✓；「移动流」/「手机版最新」上面还有过滤器入口 ✓）
class _LiveFeedView extends StatefulWidget {
  final LiveFeed feed;

  /// 这个 tab 自己的已选过滤器 ✓（只有那两个叶子用得上 ✓；其它 tab 传进来也不会显示 ✓）
  const _LiveFeedView({super.key, required this.feed});

  @override
  State<_LiveFeedView> createState() => _LiveFeedViewState();
}

class _LiveFeedViewState extends State<_LiveFeedView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // 切走 tab 再回来不重新加载 ✓

  @override
  void initState() {
    super.initState();
    widget.feed.addListener(_onFeedChanged);
    widget.feed.ensureMore();
  }

  @override
  void dispose() {
    widget.feed.removeListener(_onFeedChanged);
    super.dispose();
  }

  void _onFeedChanged() {
    if (mounted) setState(() {});
  }

  // ⚠️ 换 feed 时必须换监听 + 触发加载 ✓（同 home_page 的 `_FeedView.didUpdateWidget` ✓：
  //    State 带 KeepAlive → 不会重建，新 feed **没人挂监听** ✗ → 界面永远停在转圈 ✓）
  @override
  void didUpdateWidget(covariant _LiveFeedView old) {
    super.didUpdateWidget(old);
    if (!identical(old.feed, widget.feed)) {
      old.feed.removeListener(_onFeedChanged);
      widget.feed.addListener(_onFeedChanged);
      widget.feed.ensureMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // keepAlive 必需 ✓
    final body = _body();
    // ① 2026-10-05 独立复查发现的功能缺口：原来这里有一句"没有筛选行就直接 return"的早退 ✗
    //   ⇒「4 个主分类 tab」拿不到 RefreshIndicator ⇒ **它们没有下拉刷新** ✗（删筛选行后的副作用 ✓）
    //   ⇒ 现在 6 个 tab 一律走同一条路 ✓（_refresh 用的是**当前 tab** 的 feed ✓ 未改 ✗）
    return RefreshIndicator(onRefresh: _refresh, child: body);
  }

  /// ② 下拉刷新（用户 2026-10-05：现在卡片出来了都没法刷新 ✓）—— **复用** feed.reload() ✓ 不新造 ✗。
  /// ⚠️ 收圈时机：reload() 是 void ✗ ⇒ 用 LiveFeed 自己暴露的 loading（:974 bool get loading ✓）轮询到它结束 ✓，
  ///   先放一帧（80ms）再轮询（reload 一进去就把 _loading 置 true，但极快的返回可能让我们扑空 ✗）；
  ///   加 12 秒上限兜底 ✗（万一永远不结束，也别把转圈挂死 ✗）。
  Future<void> _refresh() async {
    final f = widget.feed;
    f.reload();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    var waited = 0;
    while (f.loading && waited < 12000) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      waited += 100;
    }
  }

  Widget _body() {
    final f = widget.feed;
    if (f.error) {
      // 失败要**说出原因** ✓（用户报过"一直转圈"那种 ✗ —— 没有原因等于没法排查 ✗）
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 120),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '加载失败：${f.errorText.isEmpty ? '未知原因' : f.errorText}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kTxtSub, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: f.retry,
                    child: const Text('重试')),
              ],
            ),
          ),
        ],
      );
    }
    return RowsGrid(
      cols: 2, // 用户指定：2 列 ✓
      physics: const AlwaysScrollableScrollPhysics(),
      count: f.rooms.length,
      // 滚到尾部才构造 → 在那时续拉下一页（懒加载 ✓，与其它列表页同一套 ✓）
      tail: () {
        if (f.rooms.isEmpty && f.done) {
          // 一页被筛空 + 已经到底 → 明说（别留一片空白 ✗）
          return _hint('没有可显示的免费直播间');
        }
        if (f.done) return _hint('没有更多了');
        f.ensureMore();
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: f.loading
                ? const CircularProgressIndicator()
                : Text('上滑加载更多', style: TextStyle(color: kTxtSub, fontSize: 12)),
          ),
        );
      },
      itemBuilder: (ctx, i) {
        // 预取（同 home_page ✓）：顺手把"再往后第 8 张"的封面拉进内存缓存 ✓
        FetchedImage.warm(
            i + 8 < f.rooms.length ? f.rooms[i + 8].cover : null);
        final r = f.rooms[i];
        return LiveRoomCard(room: r, onTap: () => _openRoom(r));
      },
    );
  }

  /// 点卡片 = **push 全屏房间页** ✓。push 一个新路由 → 列表这一页**原样留着** ✓
  /// （`LiveFeed` 也在 State 里 ✓）→ **返回列表不重拉** ✓。
  void _openRoom(LiveRoom r) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LiveRoomPage(username: r.username, id: r.id)),
    );
  }

  Widget _hint(String s) => Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
            child: Text(s, style: TextStyle(color: kTxtSub, fontSize: 12))),
      );
}

/// **过滤器入口行**（**下划线 tab 样式** ✓ —— 与站点页上面那排主 tab **同一套观感** ✓，不是按钮 ✗）。





/// 房间卡：封面(3:4) + 「LIVE」标 + 观看数 + 主播名（照模拟器 `.lv-room` ✓）
class LiveRoomCard extends StatelessWidget {
  final LiveRoom room;
  final VoidCallback onTap;
  const LiveRoomCard({super.key, required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FetchedImage(url: room.cover, memWidth: 480),
                  // LIVE 标（左上 ✓；"在线但没在播"用灰底 ✓）
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: room.isLive
                            ? const Color(0xFFE03131)
                            : Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        room.isLive ? 'LIVE' : '在线',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight:
                              room.isLive ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  // 观看数（右下 ✓）
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${room.viewers} 人',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 10),
              child: Text(
                room.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// **全屏房间页**（⚠️ 播放路径与模拟器**不同** ✗）
///
/// 用户指定 ✓：① 左上角一个 X ② **点屏幕 toggle X 显隐**（默认隐藏 ✓）③ **静音**（没得商量 ✓）
/// ④ X **不压状态栏**（留安全区 ✓）⑤ 返回列表**不重拉** ✓。
///
/// ⚠️ 播放实现（2026-10-05 用户拍板换过 ✗，**别照着旧注释走** ✓）：**不再用 WebView 加载房间页** ✗ ——
/// 站点在 iPhone 上本来就会**跳过 JS 播放器、直接给原生 `<video>`** ✓，那条流的地址（master + pkey ✓）
/// 我们能直接拼出来 ✓ → 现在是**我们自己的播放器**放 [liveMasterUrl] 拼出来的 HLS ✓
/// （开播前先抓一次校验 200 且不含 `MOUFLON-ADVERT` ✓；不过就报错、**不播广告** ✗；见 `_checkAndPlay` ✓）。
/// **直播流 pkey**：站点页面 JS 里的**硬编码常量** ✓ ——
/// recon 实测（2026-10-05）：5 次采样全是这一个值、1 分钟内不变 ✓；`main.js` 里也有它 ✓。
/// ⚠️ **必须带**：不带 pkey 拿到的是**广告清单**（`#EXT-X-MOUFLON-ADVERT` ✓）—— `standard` / `lowLatency` **都一样** ✓
///   （`playlistType` 选哪个见 [liveMasterUrl] 的实测依据 ✓）。
const String kLivePkey = 'B0p93vi8Uj6AYyZb';

/// 由 **model id** 拼直播流 master URL（**站点特有逻辑** ✓ 只管构造 ✓ 不掺 UI ✗）。
/// 本机 curl 实测（走代理、iPhone UA，2026-10-05）：
///   · id=209778341 → master **200 / 1852 字节**、`MOUFLON-ADVERT=0`、变体 **5** 个、分片 **200 + video/mp4**
///   · id=182984051 → master **200 / 1292 字节**、`MOUFLON-ADVERT=0`、变体 **3** 个、分片 **200 + video/mp4**
///   · 变体清单：200 / 738B 与 730B，`EXT-X-MEDIA-SEQUENCE=1`、`EXT-X-ENDLIST=0`、`EXT-X-PART=0`、无 ADVERT ✓
/// ⚠️ **`playlistType` 用 `standard`** —— 依据 **recon 的真起播实测（8 次）**：
///   · `standard`：首帧 **1,606~2,034ms**（4/4）✓ **零错误** ✓
///   · `lowLatency`：首帧 **2,296~5,626ms**（4/4）✗ 且**偶发 stall**（`bufferStalledError`，非致命）✗
///   · 两者都**能播、都有声**（音频解码字节 8/8 > 0 ✓）⇒ **默认 `standard`** ✓
///     （2026-10-05 我先按"清单更厚 ⇒ 起播更快"换过 LL ✗ —— **被真机实测推翻** ✓ 换回来了 ✓；
///      本机 curl 那点数据只能证明"清单干净/分片更细" ✓ **推不出起播快慢** ✗，记着这个教训 ✓）
/// ⚠️ 无论哪个参数，**必须带 pkey** ✗：不带 pkey 拿到的是**广告清单**（`#EXT-X-MOUFLON-ADVERT` ✓）
///   ⇒ 校验与播放**必须同一套参数** ✓（`_checkAndPlay` 调的就是本函数 ✓ 天然一致 ✓）。
String liveMasterUrl(int id) =>
    'https://edge-hls.doppiocdn.net/hls/$id/master/${id}_auto.m3u8'
    '?playlistType=standard&pkey=$kLivePkey';

/// 会话内**按房间缓存**"上次用过的变体 URL" ✓（键 = model id ✓ 值 = 变体 URL ✓ 不持久化 ✓）
/// —— 下次进同一房间可**跳过"抓 master"那一跳**（真机实测那一跳 ~0.9 秒 ✗）✓；直拼那条失败会自动回退抓 master ✓（只回退一次 ✓ 见 `_checkAndPlay` / `_open` ✓）。
final Map<int, String> _variantCache = <int, String>{};

/// 从 master 里挑一条变体 URL ✓（**取第一档** ✓）
/// ⚠️ **档位偏好已撤掉** ✗（2026-10-05 用户拍板：**不许降分辨率、他要看画质** ✓）——
///   曾短暂改成"优先 480p"✗，现已恢复"**取 master 里的第一档**"（多数房间就是 `NAME="source"` / 720p ✓）。
///   ⇒ **本函数只负责"按 master 顺序取第一条"** ✓（省掉的是网络往返，与画质无关 ✓ 那两条改动仍在 ✓）。
/// ⚠️ 档位**不在 URL 里** ✗ —— 实测 master 原文（真页 curl，2026-10-05）：
///   `#EXT-X-STREAM-INF:BANDWIDTH=2427392,CODECS="avc1.4d0029,mp4a.40.2",RESOLUTION=720x960,FRAME-RATE=30.000,…,NAME="source"`
///   而**下一行**才是那条变体的 URL ✓ ⇒ 解析必须"读 `STREAM-INF` + 取下一行" ✓ 不能拿 URL 去匹配档位 ✗。
/// 解析不到就返回空串 ✓（调用方按"没有可用清晰度"处理 ✓）。
String pickVariantUrl(String master) {
  final lines = master.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final t = lines[i].trim();
    if (!t.startsWith('#EXT-X-STREAM-INF')) continue;
    // 下一行 = URL ✓（跳过空行；遇到下一个注释就说明本档没跟 URL ✗）
    for (var j = i + 1; j < lines.length; j++) {
      final u = lines[j].trim();
      if (u.isEmpty) continue;
      if (u.startsWith('#')) break;
      return u;
    }
  }
  return '';
}


class LiveRoomPage extends StatefulWidget {
  /// 房间名（= 站内路径末段 ✓）→ 房间页 = `https://zh.xhamsterlive.com/<username>` ✓（**兜底用** ✓）
  final String username;

  /// model id（列表接口给的 ✓）→ 直播流 master URL 靠它拼 ✓（[liveMasterUrl] ✓）
  final int id;

  const LiveRoomPage({super.key, required this.username, required this.id});

  @override
  State<LiveRoomPage> createState() => _LiveRoomPageState();
}

class _LiveRoomPageState extends State<LiveRoomPage> {
  /// X 默认**隐藏** ✓（点屏幕才出现 ✓）
  /// X 显隐用 notifier ✓ —— 点一下**只刷 X 这一小块**，不再 setState 重建整页（原来连播放器层一起重建 ✗）
  final ValueNotifier<bool> _showX = ValueNotifier<bool>(false);

  /// 错误提示 —— ⚠️ 2026-10-05 用户拍板：**"状态提示"（打开中/连接中/仍在加载…/90 秒兜底）全删** ✗，
  ///   但**这条错误提示保留** ✓ —— 打不开/初始化失败时屏幕上必须有一行明确文案，
  ///   否则失败就是黑屏、无从判断 ✓（错误提示 ≠ 状态提示 ✓）。
  String _err = '正在打开直播…';

  /// 当前交给播放器的**变体 URL** ✓（出画时用它确认"缓存可用" ✓）
  String? _kpVariantUrl;

  /// iOS 原生播放器（`video_player` = iOS 端 **AVPlayer** ✓）
  VideoPlayerController? _c;

  /// "这条 URL 已确认可用"只做一次 ✓（出画后写进 [_variantCache] ✓ 下次直拼跳过 master ✓）
  bool _cacheConfirmed = false;

  /// `initialize()` 的硬超时（毫秒）= **8000**：
  /// 网络那一段本机实测 ≈2.5 秒 ✓ ⇒ 8 秒 ≈3 倍余量 ✓；超时就当"这条不通"→ 直拼那条会回退 ✓（master 那条只报错 ✓）。
  static const int _kInitTimeoutMs = 8000;

  @override
  void initState() {
    super.initState();
    _checkAndPlay();
  }

  @override
  void dispose() {
    _showX.dispose(); // notifier 也要释放 ✓
    final c = _c;
    _c = null;
    if (c != null) {
      try {
        c.removeListener(_onTick);
      } catch (_) {}
      unawaited(c.dispose());
    }
    super.dispose();
  }

  /// 校验/缓存逻辑**保留**（与播放器无关 ✓ 省的是**我们自己**的抓取 ✓）：
  /// ① 缓存命中 → **跳过 master** 直接用上次那条变体 ✓（失败自动回退一次 ✓）；
  /// ② 没缓存 → 抓 master（**判 `MOUFLON-ADVERT` 的底线保留** ✓）→ 取**第一条变体**（保画质 ✓ 不交 master 让播放器挑低档 ✗）
  ///    → 缓存 → 交给 AVPlayer ✓。
  Future<void> _checkAndPlay() async {
    final id = widget.id;
    if (id <= 0) {
      if (mounted) setState(() => _err = '这个房间没拿到 id，打不开直播 ✗');
      return;
    }
    final cached = _variantCache[id];
    if (cached != null && cached.isNotEmpty) {
      await _open(cached, id, allowFallback: true);
      return;
    }
    try {
      final url = liveMasterUrl(id);
      final r = await Site.httpClient
          .get(Uri.parse(url), headers: <String, String>{'User-Agent': Site.ua})
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) {
        if (mounted) setState(() => _err = '直播流打不开（HTTP ${r.statusCode}）✗');
        return;
      }
      if (r.body.contains('MOUFLON-ADVERT')) {
        if (mounted) setState(() => _err = '这条流被换成了广告清单，已停止播放 ✗');
        return;
      }
      final vu = pickVariantUrl(r.body);
      if (vu.isEmpty) {
        if (mounted) setState(() => _err = '这条流的清单里没有可用的清晰度 ✗');
        return;
      }
      _kpVariantUrl = vu;
      _variantCache[id] = vu;
      await _open(vu, id, allowFallback: false);
    } catch (e) {
      if (mounted) setState(() => _err = '打开直播失败：$e');
    }
  }

  /// 真正把 URL 交给 **AVPlayer**（`video_player` ✓ iOS = AVPlayer ✓）
  /// ⚠️ `httpHeaders` 带我们的 UA（照 [Site.ua] ✓）—— HLS 请求会带上它 ✓。
  Future<void> _open(String url, int id, {required bool allowFallback}) async {
    if (!mounted) return;
    final c = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: <String, String>{'User-Agent': Site.ua},
    );
    _c = c;
    c.addListener(_onTick);
    try {
      await c.initialize().timeout(const Duration(milliseconds: _kInitTimeoutMs + 2000));
      await c.setVolume(1.0); // **不静音** ✓（给人看的 ✓ 音量走系统默认/满 ✓）
      await c.play();
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      // ⚠️⚠️ 2026-10-05 用户报"多刷几次、看一会儿再退出后整个 App 变迟钝" —— **这里是那个漏点** ✗：
      //   页面在 `await initialize()` 期间被 pop 时，`dispose()` 已经把 `_c` 拿走并释放了 ✓，
      //   而这里会继续往下走（回退分支会 **再建一个新 controller** ✗ ⇒ 僵尸播放器：网络+解码器都活着 ✗✗）
      //   ⇒ **先确认页面还在** ✓ 不在就只把自己那份收干净、**绝不重建** ✗（等价于旧版 `_kp?.shutdown()` 的收尾 ✓）。
      if (!mounted) {
        if (identical(_c, c)) _c = null;
        try {
          c.removeListener(_onTick);
          await c.dispose();
        } catch (_) {}
        return;
      }
      if (allowFallback) {
        // 直拼那条不通 ⇒ **丢掉缓存、回退抓 master 一次** ✓（只回退一次 ✓）
        _variantCache.remove(id);
        if (identical(_c, c)) _c = null;
        try {
          c.removeListener(_onTick);
          await c.dispose();
        } catch (_) {}
        if (!mounted) return;
        setState(() => _err = '正在打开直播…');
        _checkAndPlay(); // 再走一遍 ✓（缓存已删 ⇒ 这次抓 master ✓）
        return;
      }
      if (identical(_c, c)) _c = null;
      try {
        c.removeListener(_onTick);
        await c.dispose();
      } catch (_) {}
      if (mounted) setState(() => _err = '这条直播打不开：$e ✗');
      return;
    }
  }

  /// `VideoPlayerValue` 变化（**每次 tick 都会来** ✗ ⇒ 这里只做两件事：确认缓存可用 + 出错时显示文案 ✓）
  void _onTick() {
    final c = _c;
    if (c == null || !mounted) return;
    final v = c.value;
    if (v.position > Duration.zero) {
      // 真出过画面 ⇒ 这条 URL 才算"缓存可用" ✓（下次进同房间直接拼 ✓ 跳过 master ✓）
      if (!_cacheConfirmed) {
        _cacheConfirmed = true;
        final u = _kpVariantUrl;
        if (u != null && u.isNotEmpty) _variantCache[widget.id] = u;
      }
      return;
    }
    final et = v.errorDescription ?? '';
    if (et.isNotEmpty) {
      final msg = '直播中断：$et';
      if (msg != _err && mounted) setState(() => _err = msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 这一页是黑底全屏 → 状态栏图标固定用**白色** ✗ 别跟着背景图明暗翻 ✓
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // (a) 2026-10-05 用户报「左滑返回迟钝」✗ ⇒ 根因就是原来这层：GestureDetector 包住整个 Stack，
            //   加上 HitTestBehavior.opaque ⇒ 屏幕**最左边缘**也被我们揽进 Flutter 手势竞技场 ✗，
            //   iOS 原生侧滑返回得先等它判负 ⇒ 手感变钝 ✓ ⇒ 现在**只留左侧 24px 以外**的点击热区 ✓
            Positioned.fill(
              left: 24, // 让出左边缘 24px 给原生侧滑 ✓（代价：最左 24px 内点屏幕不再 toggle ✓ 已知 ✓）
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showX.value = !_showX.value, // 只改 notifier ⇒ 不重建整页 ✓
                child: const SizedBox.expand(),
              ),
            ),
              // 画面：AVPlayer（`video_player` **本身没有任何控件** ✓ 正合"只要画面 + X" ✓）
              //   等比铺满：`Center + AspectRatio` = contain ✓（不拉伸 ✓ 黑底补边 ✓）
              if (_c != null && _c!.value.isInitialized)
                Positioned.fill(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _c!.value.aspectRatio == 0 ? 16 / 9 : _c!.value.aspectRatio,
                      child: VideoPlayer(_c!),
                    ),
                  ),
                )
              else
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _err,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFB0B4BA), fontSize: 14),
                    ),
                  ),
                ),
              // X 层：**positioned 化** ✓ —— Stack 的尺寸由【非定位子层】决定 ✗：
              //   1.0.38 事故：ValueListenableBuilder 是**非定位**子层，!show 时它返回 0×0 的 SizedBox.shrink()
              //   ⇒ 整个 Stack 被压成 0×0 ⇒ Positioned.fill 的画面"填"了 0×0 ⇒ **有声无画** ✓（真机实测 ✓）
              //   ⇒ 包一层 Positioned.fill（仍是 children 的**一个元素** ✓ 1 换 1 ✓）= 与 1.0.37 的"无非定位子层⇒撑满"一致 ✓
              Positioned.fill(
                child: ValueListenableBuilder<bool>(
                valueListenable: _showX,
                builder: (_, show, __) => !show
                    ? const SizedBox.shrink()
                    : SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(5, 12, 12, 12), // ① 2026-10-05 用户拍板：左边距 12→8→**5** ✓（只动左边 ✓ 上右下仍 12 ✓ 垂直与 SafeArea 未动 ✓）
                      child: Material(
                        color: Colors.black.withOpacity(0.45),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(), // X = 关闭回列表 ✓
                          child: const SizedBox(
                            width: 76,
                            height: 76,
                            // ③ 图标**左对齐 + 垂直居中** ✓ —— 原来居中会把 76 方块左右一多半的内边距
                            //   算进"视觉距离"✗（看着离屏幕很远 ✓）；命中区仍是 76×76 不动 ✗
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Icon(Icons.close, color: Colors.white, size: 32),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ),
            ],
        ),
      ),
    );
  }
}

// ===== 本站档案（2026-10-03 起站点档案都在自己的文件里 ✓）=====

/// 本站档案：xHamsterLive。
/// ⚠️ `group: SiteGroup.live` = 只在底栏「直播」那个宫格出现 ✓，**不进「模块」宫格** ✗
/// （模块宫格 = 14 个内容站 ✓；与模拟器一致 ✓ —— 那边直播区也是**另一个**清单 ✓）。
/// 房间列表/房间页都在本文件里 ✓（站点逻辑不往共用文件里放 ✓）。
///
/// ⚠️ 常量名**故意不叫 `kSite15`** ✓：模拟器（`sim/server.mjs:115`）是拿 `\b(kSite\d+)\b`
/// 从 `kSites` 里取站点名、再去合并源码里找 `const SiteEntry kSiteNN =` ✓ —— 名字里不带数字
/// → 它**认不出本站** ✓ → 模拟器的「模块」宫格仍是 **14 格** ✓（与 App 一致 ✓；那边直播本来
/// 就是另一个清单 ✓）。要是叫 `kSite15`，模拟器的模块宫格会**白多一格「xHamster直播」** ✗。
const SiteEntry kSiteLive = SiteEntry(
  name: 'xHamster直播',
  template: SiteTemplate.xhamsterlive,
  group: SiteGroup.live,
  hosts: ['zh.xhamsterlive.com'],
  iconUrl: '/favicon.ico', // 实测 200（image/png 1861B ✓）
  color: Color(0xFFE03131),
);
