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
// ⚠️ 播放器画面面（`Video(controller:)`）来自 media_kit_video ✓ —— 与 `player_widget.dart` 用的是同一个 ✓
import 'package:media_kit_video/media_kit_video.dart' show Video, NoVideoControls;

import '../app_background.dart';
import '../app_bg.dart';
import '../base/fetch.dart';
import '../config.dart' show Site;
import '../player_widget.dart';
// 直播**全量日志**（用户 2026-10-05 要求）✓ —— **复用现成设施** ✓（`site_error_log.dart` 那套：
// 写 App 沙盒 `kpxx_error.log` ✓ 设置页 → 错误日志页可看/可「复制全部」✓）⇒ **不新建日志系统** ✓
import '../site_error_log.dart';
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
  ///   · 「移动流」/「手机版最新」= 3 个入口 ✓（`kLiveFilters` ✓）
  ///   · 4 个主 tab = **1 个「筛选」入口** ✓（`kLiveMainFilters` ✓ —— 用户 2026-10-05 指出：
  ///     模拟器里 4 个主 tab 本来就有筛选 ✗ 之前 App 漏做了 ✓）
  bool get hasFilterRow => groups.isNotEmpty || filters.isNotEmpty;

  /// 「移动流」/「手机版最新」的 3 个页内过滤器 ✓（4 个主 tab 那是 [filters] ✗ 别混 ✓）
  bool get hasMobileFilters => groups.isNotEmpty;

  /// 这个 tab 的**筛选入口数据** ✓：4 个主 tab = [kLiveMainFilters] 里自己那一份 ✓；
  /// 其它 tab = 空 ✗（它们走 `kLiveFilters` ✓，见 `_LiveFeedView` ✓）
  final List<LiveFilter> filters;

  /// 接口的 `parentTag`（只有带了 `groups` 才拼 ✓）
  final String? parentTag;

  /// 要不要带 `specialEventTagIds`（= 4 个主 tab ✓）
  final bool specialEvent;

  const LiveTabDef(this.name, this.primaryTag,
      {this.groups = const [],
      this.filters = const [],
      this.parentTag,
      this.specialEvent = false});
}

/// 6 个 tab（顺序 = 界面上的顺序 ✓；前 4 个是**主分类** ✓，后 2 个是**快捷叶子** ✓）
const List<LiveTabDef> kLiveTabs = [
  // 4 个主 tab：各带**自己那一份**子分类筛选 ✓（数据是脚本产物 ✓ 见下面生成块 ✓）
  LiveTabDef('女主播', 'girls', specialEvent: true,
      filters: kLiveMainFiltersGirls),
  LiveTabDef('情侣', 'couples', specialEvent: true,
      filters: kLiveMainFiltersCouples),
  LiveTabDef('男主播', 'men', specialEvent: true,
      filters: kLiveMainFiltersMen),
  LiveTabDef('跨性別', 'trans', specialEvent: true,
      filters: kLiveMainFiltersTrans),
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

// ===== 一·B、过滤器数据（只有「移动流」「手机版最新」这两个 tab 才有 ✓）=====
//
// ⚠️ 中间那一整块是**脚本产物** ✗ **别手改** ✓ —— 要改就改数据源再重新生成 ✓：
//    生成方式 = 从 `sim/index.html` 的 `MOBILE_FILTERS` **原样抽取** ✓
//    （recon 实测 + sim-dev 落地的最终数据 ✓：顺序 / 显示名 / tagId / 「未映射」全部照抄 ✓）。
//    手抄会抄错 ✗（lead 明确提醒过 ✓）。
// >>> LIVE_FILTERS_DATA_BEGIN
class LiveTag {
  final String name;

  /// 接口的 tagId；`null` = **未映射** ✓（recon 没给 → 界面灰显 + 点了不过滤 ✗ 不硬猜 ✓）
  final String? id;

  const LiveTag(this.name, this.id);
}

/// 过滤器里的一个**子分组**（界面 = 小标题 + 一行多选 chip ✓；组内多值 = OR ✓）
class LiveFilterGroup {
  final String name;
  final List<LiveTag> items;

  const LiveFilterGroup(this.name, this.items);
}

/// 一个过滤器（外貌 / 国家 / 可请求提供的表演）—— 界面 = **下划线 tab 样式**的 3 个入口 ✓
class LiveFilter {
  /// 稳定标识（本文件内部用 ✓；也是「已选」分桶的前缀 ✓）
  final String key;

  /// 入口上的名字 ✓
  final String name;
  final List<LiveFilterGroup> groups;

  /// **单选** ✓：点一个换一个 ✓、再点已选 = 取消 ✓。
  /// 4 个主 tab = true ✓（与站点侧栏一致：点一个子分类 = 跳到 `/girls/<slug>`，一次只有一个 ✓）；
  /// 移动流 / 手机版最新那 3 个入口 = false ✓（子分组间 AND、组内 OR ✓ 与站点那套弹窗本来就不同 ✓）。
  final bool single;

  const LiveFilter(this.key, this.name, this.groups, {this.single = false});
}

const List<LiveFilter> kLiveFilters = [
  LiveFilter('appearance', '外貌', [
    LiveFilterGroup('年龄', [
      LiveTag('成熟', 'ageMature'),
      LiveTag('老奶奶', 'ageOld'),
      LiveTag('少女18+', 'ageTeen'),
      LiveTag('熟女', 'ageMilf'),
      LiveTag('鲜嫩青年22+', 'ageYoung'),
    ]),
    LiveFilterGroup('种族', [
      LiveTag('阿拉伯人', 'ethnicityMiddleEastern'),
      LiveTag('白人', 'ethnicityWhite'),
      LiveTag('黑珍珠', 'ethnicityEbony'),
      LiveTag('混血主播', 'ethnicityMultiracial'),
      LiveTag('拉丁人', 'ethnicityLatino'),
      LiveTag('亚洲人', 'ethnicityAsian'),
      LiveTag('印度人', 'ethnicityIndian'),
    ]),
    LiveFilterGroup('体型', [
      LiveTag('大号美女', 'bodyTypeBBW'),
      LiveTag('丰满', 'bodyTypeCurvy'),
      LiveTag('瘦', 'bodyTypePetite'),
      LiveTag('运动型', 'bodyTypeAthletic'),
      LiveTag('中', 'bodyTypeMedium'),
    ]),
    LiveFilterGroup('头发', [
      LiveTag('彩色', 'hairColorColorful'),
      LiveTag('黑发', 'hairColorBlack'),
      LiveTag('红发', 'hairColorRed'),
      LiveTag('金发', 'hairColorBlonde'),
      LiveTag('棕发小妞', 'hairColorBrown'),
    ]),
    LiveFilterGroup('身体特征', [
      LiveTag('大屁股', 'specificsBigAss'),
      LiveTag('大乳头', 'specificBigNipples'),
      LiveTag('大阴蒂', 'specificBigClit'),
      LiveTag('多毛腋下', 'specificHairyArmpits'),
      LiveTag('巨乳', 'specificsBigTits'),
      LiveTag('剃光', 'specificShaven'),
      LiveTag('剃毛', 'specificTrimmed'),
      LiveTag('无发', 'hairColorHairless'),
      LiveTag('小胸部', 'specificSmallTits'),
      LiveTag('阴部多毛', 'specificsHairy'),
    ]),
  ]),
  LiveFilter('countries', '国家', [
    LiveFilterGroup('北美(3)', [
      LiveTag('加拿大人', null),
      LiveTag('美国人', 'tagLanguageUSModels'),
      LiveTag('墨西哥人', null),
    ]),
    LiveFilterGroup('南美(8)', [
      LiveTag('阿根廷人', null),
      LiveTag('巴西人', null),
      LiveTag('厄瓜多尔人', null),
      LiveTag('哥伦比亚人', null),
      LiveTag('秘鲁人', null),
      LiveTag('委内瑞拉人', null),
      LiveTag('乌拉圭人', null),
      LiveTag('智利人', null),
    ]),
    LiveFilterGroup('欧洲(32)', [
      LiveTag('爱尔兰人', null),
      LiveTag('爱沙尼亚人', null),
      LiveTag('奥地利人', null),
      LiveTag('保加利亚人', null),
      LiveTag('北欧', 'tagLanguageNordic'),
      LiveTag('比利时人', null),
      LiveTag('波兰语', null),
      LiveTag('丹麦语', null),
      LiveTag('德语', 'tagLanguageGermanSpeaking'),
      LiveTag('法语', null),
      LiveTag('芬兰语', null),
      LiveTag('格鲁吉亚人', null),
      LiveTag('荷兰语', null),
      LiveTag('捷克语', null),
      LiveTag('克罗地亚语', null),
      LiveTag('拉脱维亚人', null),
      LiveTag('立陶宛人', null),
      LiveTag('罗马尼亚语', null),
      LiveTag('挪威语', null),
      LiveTag('欧洲女孩', 'european'),
      LiveTag('葡萄牙语', null),
      LiveTag('瑞士人', null),
      LiveTag('瑞语', 'tagLanguageSwedish'),
      LiveTag('塞尔维亚语', null),
      LiveTag('斯洛伐克人', null),
      LiveTag('斯洛文尼亚', 'tagLanguageSlovenian'),
      LiveTag('乌克兰女主播', 'tagLanguageUkrainian'),
      LiveTag('西班牙语', null),
      LiveTag('希腊人', null),
      LiveTag('匈牙利语', null),
      LiveTag('意大利语', null),
      LiveTag('英国主播', 'tagLanguageUKModels'),
    ]),
    LiveFilterGroup('亚洲&太平洋(12)', [
      LiveTag('澳大利亚人', null),
      LiveTag('菲律宾', 'tagLanguageFilipino'),
      LiveTag('韩语', null),
      LiveTag('马来西亚人', null),
      LiveTag('孟加拉人', null),
      LiveTag('日语', null),
      LiveTag('斯里兰卡人', null),
      LiveTag('泰语', null),
      LiveTag('印度尼西亚语', null),
      LiveTag('印度人', 'ethnicityIndian'),
      LiveTag('越语', 'tagLanguageVietnamese'),
      LiveTag('中文', 'tagLanguageChinese'),
    ]),
    LiveFilterGroup('非洲(10)', [
      LiveTag('阿尔及利亚人', null),
      LiveTag('埃及人', null),
      LiveTag('非洲裔', 'tagLanguageAfrican'),
      LiveTag('津巴布韦人', null),
      LiveTag('肯尼亚人', null),
      LiveTag('马尔加什人', null),
      LiveTag('摩洛哥人', null),
      LiveTag('南非人', null),
      LiveTag('尼日利亚人', null),
      LiveTag('乌干达', 'tagLanguageUgandan'),
    ]),
    LiveFilterGroup('中东(3)', [
      LiveTag('阿拉伯人', 'ethnicityMiddleEastern'),
      LiveTag('土耳其语', null),
      LiveTag('以色列人', null),
    ]),
    LiveFilterGroup('语言(14)', [
      LiveTag('俄国人', 'tagLanguageRussianSpeaking'),
      LiveTag('说阿萨姆语', null),
      LiveTag('说奥里亚语', null),
      LiveTag('说古吉拉特语', null),
      LiveTag('说卡纳达语', null),
      LiveTag('说马拉地语', null),
      LiveTag('说马拉雅拉姆语', null),
      LiveTag('说孟加拉语', null),
      LiveTag('说旁遮普语', null),
      LiveTag('说葡萄牙语', 'tagLanguagePortugueseSpeaking'),
      LiveTag('说泰卢固语', null),
      LiveTag('说泰米尔语', null),
      LiveTag('说印地语', null),
      LiveTag('西班牙人', 'tagLanguageSpanishSpeaking'),
    ]),
  ]),
  LiveFilter('activitiesOnRequest', '可请求提供的表演', [
    LiveFilterGroup('表演', [
      LiveTag('潮吹', 'doSquirt'),
      LiveTag('肛交', 'doAnal'),
      LiveTag('互动玩具', 'autoTagInteractiveToy'),
      LiveTag('口交', 'doBlowjob'),
      LiveTag('炮机', 'fuckMachine'),
      LiveTag('自慰', 'doMasturbation'),
      LiveTag('69姿势', 'do69Position'),
      LiveTag('按摩', 'doMassage'),
      LiveTag('鞭打', 'doSpanking'),
      LiveTag('厕板洞', 'doSph'),
      LiveTag('赤裸上身', 'doTopless'),
      LiveTag('穿戴式阳具', 'doStrapon'),
      LiveTag('粗暴', 'doHardcore'),
      LiveTag('打飞机', 'doHandjob'),
      LiveTag('大屌评分', 'cockRating'),
      LiveTag('电臀舞', 'doTwerk'),
      LiveTag('肛交到口交', 'doAssToMouth'),
      LiveTag('高潮', 'doOrgasm'),
      LiveTag('高潮脸', 'doAhegao'),
      LiveTag('狗式', 'doDoggyStyle'),
      LiveTag('后庭玩具', 'doAnalToys'),
      LiveTag('集体颜射', 'doGangbang'),
      LiveTag('假阳具或震动器', 'doDildoOrVibrator'),
      LiveTag('假阴茎肛交', 'doPegging'),
      LiveTag('交换伴侣', 'subcultureSwingers'),
      LiveTag('精油表演', 'doOilShow'),
      LiveTag('开肛', 'doGape'),
      LiveTag('快闪裸体', 'doFlashing'),
      LiveTag('骑乘女', 'doCowgirl'),
      LiveTag('骑脸', 'doFacesitting'),
      LiveTag('强制塞口', 'doGagging'),
      LiveTag('情境扮演', 'doRolePlay'),
      LiveTag('拳交', 'doFisting'),
      LiveTag('裙底风光', 'doUpskirt'),
      LiveTag('群交', 'tagGroupSex'),
      LiveTag('乳交', 'doTittyFuck'),
      LiveTag('乳头玩具', 'doNippleToys'),
      LiveTag('三人性交', 'doDoublePenetration'),
      LiveTag('色情短信', 'sexting'),
      LiveTag('色情舞', 'doEroticDance'),
      LiveTag('射精', 'doEjaculation'),
      LiveTag('深喉', 'doDeepThroat'),
      LiveTag('手淫指导', 'jerkOffInstruction'),
      LiveTag('双茎插入', 'doDoublePenetration'),
      LiveTag('四人性交', 'doGangbang'),
      LiveTag('体内射精', 'doCreamPie'),
      LiveTag('舔鲍鱼', 'doPussyLicking'),
      LiveTag('脱衣舞', 'doStriptease'),
      LiveTag('洗澡', 'doShower'),
      LiveTag('下流話', 'doTalk'),
      LiveTag('性玩具', 'doSexToys'),
      LiveTag('羞辱', 'doHumiliation'),
      LiveTag('颜射', 'doFacial'),
      LiveTag('阴部骆驼趾', 'doCamelToe'),
      LiveTag('瑜伽', 'doYoga'),
      LiveTag('指交', 'doFingering'),
      LiveTag('足交', 'doFootFetish'),
      LiveTag('Cosplay', 'doCosplay'),
      LiveTag('Kiiroo', 'autoTagKiiroo'),
      LiveTag('Lovense', 'autoTagLovense'),
      LiveTag('The Handy', 'autoTagHandy'),
    ]),
  ]),
];

// -- 4 个主 tab 各自的子分类筛选（与上面 kLiveFilters 同一套 chip 弹窗 ✓）--
// ⚠️ 下面这段是**一次性脚本抽取的产物** ✗ 别手改 ✓ —— 数据源 = `sim/index.html` 的 `LIVE_MAIN` + `LIVE_TAG_MAP` ✓
//    （抽取规则：顺序 / 显示名 / tagId / 「未映射」全部原样照抄 ✓、逐层括号匹配不手抄 ✓；脚本已用完删除 ✓
//     —— 以后要改就**按同一规则重跑一次抽取** ✗ 别手改这段 ✗）。
//    ⚠️ 里面每个 `LiveFilter` 都是 **单选**（`single: true` ✓，与 sim 一致 ✓）：点一个换一个 ✓、再点已选 = 取消 ✓；
//    请求里 `parentTag` 取**当前选中的那个 tag** ✓（见 `LiveFilterSel.selTag` ✓），没选就整个不带 ✓。
//    依据（实测 ✓）：`[["tagLanguageChinese"]]` + `parentTag=tagLanguageChinese` → 200 / filteredCount 296 ✓；
//    清掉选择（不带这两件）→ 回到无筛选的 1000 ✓；leaf 那两套多选（移动流/手机版最新）不受影响 ✓。
/// ⚠️ 拆成 4 个具名常量 ✓ —— `const kLiveTabs` 里要按 tab 引用 const 值 ✗ 不能引用列表元素 ✓
/// `女主播` tab 的子分类筛选（7 组 / 58 项 ✓）
/// ⚠️ **单选** ✓（`single: true` —— 与 sim 一致 ✓）：点一个换一个 ✓、再点已选 = 取消 ✓；
///    `parentTag` 取当前选中的那个 tag ✓（见 `LiveFilterSel.selTag` ✓），没选就不带 ✓。
/// ⚠️ 拆成 4 个具名常量 ✓ —— `const kLiveTabs` 里要按 tab 引用 const 值 ✗ 不能引用列表元素 ✓
/// `女主播` tab 的子分类筛选（7 组 / 58 项 ✓）
const List<LiveFilter> kLiveMainFiltersGirls = [
  LiveFilter('女主播', '女主播', [
    LiveFilterGroup('特别', [
      LiveTag('Oktoberfest Party', null),
      LiveTag('中文', 'tagLanguageChinese'),
      LiveTag('美国人', 'tagLanguageUSModels'),
      LiveTag('乌克兰女主播', 'tagLanguageUkrainian'),
      LiveTag('新主播', 'autoTagNew'),
      LiveTag('VR摄像头', 'autoTagVr'),
      LiveTag('虐恋', 'subcultureBdsm'),
      LiveTag('购票表演', 'groupShow'),
    ]),
    LiveFilterGroup('年龄', [
      LiveTag('少女18+', 'ageTeen'),
      LiveTag('鲜嫩青年22+', 'ageYoung'),
      LiveTag('熟女', 'ageMilf'),
      LiveTag('成熟', 'ageMature'),
      LiveTag('老奶奶', 'ageOld'),
    ]),
    LiveFilterGroup('种族', [
      LiveTag('阿拉伯人', 'ethnicityMiddleEastern'),
      LiveTag('亚洲人', 'ethnicityAsian'),
      LiveTag('黑珍珠', 'ethnicityEbony'),
      LiveTag('印度人', 'ethnicityIndian'),
      LiveTag('拉丁人', 'ethnicityLatino'),
      LiveTag('混血主播', 'ethnicityMultiracial'),
      LiveTag('白人', 'ethnicityWhite'),
    ]),
    LiveFilterGroup('体型', [
      LiveTag('瘦', 'bodyTypePetite'),
      LiveTag('运动型', 'bodyTypeAthletic'),
      LiveTag('中', 'bodyTypeMedium'),
      LiveTag('丰满', 'bodyTypeCurvy'),
      LiveTag('大号美女', 'bodyTypeBBW'),
    ]),
    LiveFilterGroup('头发', [
      LiveTag('金发', 'hairColorBlonde'),
      LiveTag('黑', 'hairColorBlack'),
      LiveTag('棕发小妞', 'hairColorBrown'),
      LiveTag('红发', 'hairColorRed'),
      LiveTag('彩色', 'hairColorColorful'),
    ]),
    LiveFilterGroup('私秀表演', [
      LiveTag('8-12代币', 'privatePriceEight'),
      LiveTag('16-24代币', 'privatePriceSixteenToTwentyFour'),
      LiveTag('32-60代币', 'privatePriceThirtyTwoSixty'),
      LiveTag('90+代币', 'privatePriceNinetyPlus'),
      LiveTag('可录制私秀', 'autoTagRecordablePrivate'),
      LiveTag('偷窥表演', 'autoTagSpy'),
      LiveTag('视频通话(直播)', 'autoTagP2P'),
    ]),
    LiveFilterGroup('最受欢迎', [
      LiveTag('互动玩具', 'autoTagInteractiveToy'),
      LiveTag('移动流', 'mobile'),
      LiveTag('群交', 'tagGroupSex'),
      LiveTag('巨乳', 'specificsBigTits'),
      LiveTag('阴部多毛', 'specificsHairy'),
      LiveTag('户外', 'doPublicPlace'),
      LiveTag('大屁股', 'specificsBigAss'),
      LiveTag('肛交', 'doAnal'),
      LiveTag('潮吹', 'doSquirt'),
      LiveTag('炮机', 'fuckMachine'),
      LiveTag('粗暴', 'doHardcore'),
      LiveTag('口交', 'doBlowjob'),
      LiveTag('小胸部', 'specificSmallTits'),
      LiveTag('孕妇', 'specificPregnant'),
      LiveTag('拳交', 'doFisting'),
      LiveTag('自慰', 'doMasturbation'),
      LiveTag('剃光', 'specificShaven'),
      LiveTag('深喉', 'doDeepThroat'),
      LiveTag('恋足', 'doFootFetish'),
      LiveTag('办公室', 'doOffice'),
      LiveTag('全部分类', null),
    ]),
  ], single: true),
];
/// `情侣` tab 的子分类筛选（4 组 / 36 项 ✓）
const List<LiveFilter> kLiveMainFiltersCouples = [
  LiveFilter('情侣', '情侣', [
    LiveFilterGroup('特别', [
      LiveTag('Oktoberfest Party', null),
      LiveTag('中文', 'tagLanguageChinese'),
      LiveTag('美国人', 'tagLanguageUSModels'),
      LiveTag('乌克兰情侣主播', 'tagLanguageUkrainian'),
      LiveTag('新主播们', 'autoTagNew'),
      LiveTag('VR摄像头', 'autoTagVr'),
      LiveTag('购票表演', 'groupShow'),
    ]),
    LiveFilterGroup('种族', [
      LiveTag('印度人', 'ethnicityIndian'),
    ]),
    LiveFilterGroup('私秀表演', [
      LiveTag('8-12代币', 'privatePriceEight'),
      LiveTag('16-24代币', 'privatePriceSixteenToTwentyFour'),
      LiveTag('32-60代币', 'privatePriceThirtyTwoSixty'),
      LiveTag('90+代币', 'privatePriceNinetyPlus'),
      LiveTag('可录制私秀', 'autoTagRecordablePrivate'),
      LiveTag('偷窥表演', 'autoTagSpy'),
      LiveTag('视频通话(直播)', 'autoTagP2P'),
    ]),
    LiveFilterGroup('最受欢迎', [
      LiveTag('互动玩具', 'autoTagInteractiveToy'),
      LiveTag('移动流', 'mobile'),
      LiveTag('群交', 'tagGroupSex'),
      LiveTag('户外', 'doPublicPlace'),
      LiveTag('肛交', 'doAnal'),
      LiveTag('潮吹', 'doSquirt'),
      LiveTag('炮机', 'fuckMachine'),
      LiveTag('粗暴', 'doHardcore'),
      LiveTag('口交', 'doBlowjob'),
      LiveTag('孕妇', 'specificPregnant'),
      LiveTag('拳交', 'doFisting'),
      LiveTag('狗式', 'doDoggyStyle'),
      LiveTag('自慰', 'doMasturbation'),
      LiveTag('深喉', 'doDeepThroat'),
      LiveTag('恋足', 'doFootFetish'),
      LiveTag('办公室', 'doOffice'),
      LiveTag('假阳具或震动器', 'doDildoOrVibrator'),
      LiveTag('老少配22+', 'autoTagOldYoung'),
      LiveTag('69姿势', 'do69Position'),
      LiveTag('哥特', 'subcultureGoth'),
      LiveTag('全部分类', null),
    ]),
  ], single: true),
];
/// `男主播` tab 的子分类筛选（8 组 / 60 项 ✓）
const List<LiveFilter> kLiveMainFiltersMen = [
  LiveFilter('男主播', '男主播', [
    LiveFilterGroup('特别', [
      LiveTag('Oktoberfest Party', null),
      LiveTag('中文', 'tagLanguageChinese'),
      LiveTag('美国人', 'tagLanguageUSModels'),
      LiveTag('乌克兰男主播', 'tagLanguageUkrainian'),
      LiveTag('新主播们', 'autoTagNew'),
      LiveTag('VR摄像头', 'autoTagVr'),
      LiveTag('购票表演', 'groupShow'),
    ]),
    LiveFilterGroup('性取向', [
      LiveTag('双性恋', 'orientationBisexual'),
      LiveTag('同性恋', 'orientationGay'),
      LiveTag('直男', 'orientationStraight'),
    ]),
    LiveFilterGroup('年龄', [
      LiveTag('小鲜肉', 'tagMenTwinks'),
      LiveTag('鲜嫩青年22+', 'ageYoung'),
      LiveTag('老爹', 'ageDaddies'),
      LiveTag('成熟', 'ageMature'),
      LiveTag('老爷爷', 'ageGrandpas'),
    ]),
    LiveFilterGroup('种族', [
      LiveTag('阿拉伯人', 'ethnicityMiddleEastern'),
      LiveTag('亚洲人', 'ethnicityAsian'),
      LiveTag('黑珍珠', 'ethnicityEbony'),
      LiveTag('印度人', 'ethnicityIndian'),
      LiveTag('拉丁', 'ethnicityLatino'),
      LiveTag('混血主播', 'ethnicityMultiracial'),
      LiveTag('白人', 'ethnicityWhite'),
    ]),
    LiveFilterGroup('体型', [
      LiveTag('瘦', 'bodyTypeSkinny'),
      LiveTag('肌肉发达', 'bodyTypeMuscular'),
      LiveTag('中', 'bodyTypeMedium'),
      LiveTag('矮胖', 'bodyTypeChunky'),
      LiveTag('大', 'bodyTypeBig'),
    ]),
    LiveFilterGroup('头发', [
      LiveTag('金发', 'hairColorBlonde'),
      LiveTag('黑', 'hairColorBlack'),
      LiveTag('褐色头发', 'hairColorBrown'),
      LiveTag('红发', 'hairColorRed'),
      LiveTag('彩色', 'hairColorColorful'),
    ]),
    LiveFilterGroup('私秀表演', [
      LiveTag('8-12代币', 'privatePriceEight'),
      LiveTag('16-24代币', 'privatePriceSixteenToTwentyFour'),
      LiveTag('32-60代币', 'privatePriceThirtyTwoSixty'),
      LiveTag('90+代币', 'privatePriceNinetyPlus'),
      LiveTag('可录制私秀', 'autoTagRecordablePrivate'),
      LiveTag('偷窥表演', 'autoTagSpy'),
      LiveTag('视频通话(直播)', 'autoTagP2P'),
    ]),
    LiveFilterGroup('最受欢迎', [
      LiveTag('互动玩具', 'autoTagInteractiveToy'),
      LiveTag('移动流', 'mobile'),
      LiveTag('群交', 'tagGroupSex'),
      LiveTag('户外', 'doPublicPlace'),
      LiveTag('大屁股', 'specificsBigAss'),
      LiveTag('肛交', 'doAnal'),
      LiveTag('炮机', 'fuckMachine'),
      LiveTag('粗暴', 'doHardcore'),
      LiveTag('大乳头', null),
      LiveTag('口交', 'doBlowjob'),
      LiveTag('拳交', 'doFisting'),
      LiveTag('狗式', 'doDoggyStyle'),
      LiveTag('自慰', 'doMasturbation'),
      LiveTag('多毛腋下', null),
      LiveTag('指交', null),
      LiveTag('剃光', 'specificShaven'),
      LiveTag('体内射精', null),
      LiveTag('深喉', 'doDeepThroat'),
      LiveTag('大屌', null),
      LiveTag('洗澡', null),
      LiveTag('全部分类', null),
    ]),
  ], single: true),
];
/// `跨性別` tab 的子分类筛选（7 组 / 57 项 ✓）
const List<LiveFilter> kLiveMainFiltersTrans = [
  LiveFilter('跨性別', '跨性別', [
    LiveFilterGroup('特别', [
      LiveTag('Oktoberfest Party', null),
      LiveTag('中文', 'tagLanguageChinese'),
      LiveTag('美国人', 'tagLanguageUSModels'),
      LiveTag('乌克兰变性人主播', 'tagLanguageUkrainian'),
      LiveTag('新主播们', 'autoTagNew'),
      LiveTag('VR摄像头', 'autoTagVr'),
      LiveTag('购票表演', 'groupShow'),
    ]),
    LiveFilterGroup('年龄', [
      LiveTag('少年18+', 'ageTeen'),
      LiveTag('鲜嫩青年22+', 'ageYoung'),
      LiveTag('熟女', 'ageMilf'),
      LiveTag('成熟', 'ageMature'),
      LiveTag('老奶奶', 'ageOld'),
    ]),
    LiveFilterGroup('种族', [
      LiveTag('阿拉伯人', 'ethnicityMiddleEastern'),
      LiveTag('亚洲人', 'ethnicityAsian'),
      LiveTag('黑珍珠', 'ethnicityEbony'),
      LiveTag('印度人', 'ethnicityIndian'),
      LiveTag('拉丁人', 'ethnicityLatino'),
      LiveTag('混血主播', 'ethnicityMultiracial'),
      LiveTag('白人', 'ethnicityWhite'),
    ]),
    LiveFilterGroup('体型', [
      LiveTag('瘦', 'bodyTypePetite'),
      LiveTag('运动型', 'bodyTypeAthletic'),
      LiveTag('中', 'bodyTypeMedium'),
      LiveTag('丰满', 'bodyTypeCurvy'),
      LiveTag('大号美女', 'bodyTypeBBW'),
    ]),
    LiveFilterGroup('头发', [
      LiveTag('金发', 'hairColorBlonde'),
      LiveTag('黑', 'hairColorBlack'),
      LiveTag('棕发小妞', 'hairColorBrown'),
      LiveTag('红发', 'hairColorRed'),
      LiveTag('彩色', 'hairColorColorful'),
    ]),
    LiveFilterGroup('私秀表演', [
      LiveTag('8-12代币', 'privatePriceEight'),
      LiveTag('16-24代币', 'privatePriceSixteenToTwentyFour'),
      LiveTag('32-60代币', 'privatePriceThirtyTwoSixty'),
      LiveTag('90+代币', 'privatePriceNinetyPlus'),
      LiveTag('可录制私秀', 'autoTagRecordablePrivate'),
      LiveTag('偷窥表演', 'autoTagSpy'),
      LiveTag('视频通话(直播)', 'autoTagP2P'),
    ]),
    LiveFilterGroup('最受欢迎', [
      LiveTag('互动玩具', 'autoTagInteractiveToy'),
      LiveTag('移动流', 'mobile'),
      LiveTag('群交', 'tagGroupSex'),
      LiveTag('巨乳', 'specificsBigTits'),
      LiveTag('户外', 'doPublicPlace'),
      LiveTag('大屁股', 'specificsBigAss'),
      LiveTag('肛交', 'doAnal'),
      LiveTag('潮吹', 'doSquirt'),
      LiveTag('大阴蒂', null),
      LiveTag('炮机', 'fuckMachine'),
      LiveTag('粗暴', 'doHardcore'),
      LiveTag('大乳头', null),
      LiveTag('口交', 'doBlowjob'),
      LiveTag('小胸部', 'specificSmallTits'),
      LiveTag('拳交', 'doFisting'),
      LiveTag('狗式', 'doDoggyStyle'),
      LiveTag('自慰', 'doMasturbation'),
      LiveTag('多毛腋下', null),
      LiveTag('指交', null),
      LiveTag('剃光', 'specificShaven'),
      LiveTag('全部分类', null),
    ]),
  ], single: true),
];

// <<< LIVE_FILTERS_DATA_END

/// 一个 tab 的**已选过滤器状态** ✓
///
/// ⚠️ 分桶粒度 = **子分组** ✓（键 `<过滤器key>#<子分组名>` → tagId 数组 ✓）：同组多值 = OR ✓、
///    组与组之间 = AND ✓。依据 lead 实测：`mobile + ageTeen + ethnicityAsian + bodyTypePetite
///    + doAnal → 5 条` ✓（年龄/种族/体型各占一组 ✓）——整个过滤器当一桶会把 AND 变成 OR ✗。
/// ⚠️ **按 tab 各一份** ✓（「移动流」和「手机版最新」互不影响 ✓ —— 页面里按下标各存一个 ✓）。
/// ⚠️ 未映射项（`LiveTag.id == null`）**不写进来** ✓（点了不过滤 ✓ 不硬猜 tagId ✗）。
class LiveFilterSel {
  final Map<String, List<String>> _buckets = {};

  /// 这份选择属于哪一组过滤器入口 ✓ —— 弹窗据此决定画什么 ✓、
  /// 「入口上的文字」据此把 id 翻回名字 ✓：
  ///   · 「移动流」/「手机版最新」= [kLiveFilters]（3 个入口 ✓）
  ///   · 4 个主 tab = [kLiveMainFilters]（1 个入口「筛选」✓，每个主 tab 各一份 ✓）
  /// ⚠️ 必须**按 tab 传对** ✗ —— 传错的话 id 会翻成别的 tab 的名字（跨 tab 串味 ✓）。
  final List<LiveFilter> filters;

  LiveFilterSel({this.filters = kLiveFilters});

  /// 复制一份当**草稿** ✓（弹窗改草稿 ✓ 点「进行筛选」才提交 ✓；取消 = 什么都不变 ✗
  /// —— 与 App 现成那套弹窗（`pornhub.dart` 的 PhMoreDialog「取消不改」✓）同一套语义 ✓）
  LiveFilterSel.copyOf(LiveFilterSel o) : filters = o.filters {
    for (final e in o._buckets.entries) {
      _buckets[e.key] = List<String>.of(e.value);
    }
  }

  static String _bucket(LiveFilter f, LiveFilterGroup g) => '${f.key}#${g.name}';

  List<String> selIn(LiveFilter f, LiveFilterGroup g) =>
      _buckets[_bucket(f, g)] ?? const [];

  /// 这个过滤器选了几个（跨它的所有子分组 ✓）
  int count(LiveFilter f) {
    var n = 0;
    for (final g in f.groups) {
      n += selIn(f, g).length;
    }
    return n;
  }

  bool get any {
    for (final v in _buckets.values) {
      if (v.isNotEmpty) return true;
    }
    return false;
  }

  /// 点一下 chip；**未映射的直接忽略** ✓。
  /// [exclusive] = **单选**（4 个主 tab ✓ 与站点侧栏一致：点一个换一个 ✓、再点已选的 = 取消 ✓）
  ///   —— 会先把**这个过滤器**的所有桶清空 ✓；同组**多选**（移动流/手机版最新 ✓）就是 false ✓。
  void toggle(LiveFilter f, LiveFilterGroup g, LiveTag t,
      {bool exclusive = false}) {
    final id = t.id;
    if (id == null) return;
    final k = _bucket(f, g);
    if (exclusive) {
      final had = (_buckets[k] ?? const <String>[]).contains(id);
      resetFilter(f); // 单选：先把同过滤器里的清掉 ✓
      if (had) return; // 再点已选的那个 = 取消 ✓
    }
    final arr = _buckets.putIfAbsent(k, () => <String>[]);
    if (arr.contains(id)) {
      arr.remove(id);
    } else {
      arr.add(id);
    }
    if (arr.isEmpty) _buckets.remove(k); // 空桶不留 ✗（免得"有没有选"被空数组骗到 ✓）
  }

  /// 清掉**这一个过滤器**的全部组 ✓（弹窗里那颗「重置」✓）
  void resetFilter(LiveFilter f) {
    for (final g in f.groups) {
      _buckets.remove(_bucket(f, g));
    }
  }

  /// 全清 ✓（入口行那颗「重置」= 只清**当前 tab** 这份 ✓）
  void clear() => _buckets.clear();

  /// 草稿提交回正式状态 ✓
  void replaceWith(LiveFilterSel o) {
    _buckets.clear();
    for (final e in o._buckets.entries) {
      _buckets[e.key] = List<String>.of(e.value);
    }
  }

  String _labelOf(String id) {
    for (final f in filters) {
      for (final g in f.groups) {
        for (final t in g.items) {
          if (t.id == id) return t.name;
        }
      }
    }
    return id;
  }

  /// 入口上的文字 ✓（如 `外貌: 熟女 +1` ✓；没选就是过滤器名 ✓）
  /// ⚠️ 只给**多入口**那排用 ✓ —— 4 个主 tab 只有 1 个「筛选」入口，按钮文字不显示已选 ✗
  ///   （与站点一致：按钮就写「筛选」✓；已选状态在弹窗里看 ✓）
  String btnText(LiveFilter f) {
    final ids = <String>[];
    for (final g in f.groups) {
      ids.addAll(selIn(f, g));
    }
    if (ids.isEmpty) return f.name;
    final more = ids.length > 1 ? ' +${ids.length - 1}' : '';
    return '${f.name}: ${_labelOf(ids.first)}$more';
  }

  /// 拼进请求的组 ✓：**每个有选择的子分组一个数组** ✓（空的不拼 ✗；顺序 = 数据顺序 ✓ 稳定 ✓）
  /// ⚠️ 走的是 [filters] ✓ —— 所以 4 个主 tab 选的东西（同一组数据 ✓）也会被拼上 ✓；
  ///    tab 自己的 `groups`（移动流固定那几组 ✓）在 `XhLiveApi._path` 里**排在前面** ✓
  List<List<String>> groups() {
    final out = <List<String>>[];
    for (final f in filters) {
      for (final g in f.groups) {
        final ids = selIn(f, g);
        if (ids.isNotEmpty) out.add(List<String>.of(ids));
      }
    }
    return out;
  }

  /// **单选过滤器**（`f.single` ✓ = 4 个主 tab ✓）当前选中的那一个 tag ✓；没选 = 空串 ✓。
  /// 依据（用户 2026-10-05 拍板：以 sim 为准 ✓）：4 主 tab 的筛选与站点侧栏一致 ——
  /// 点一个子分类 = 跳到 `/girls/<slug>` 路径 ✓，**一次只有一个** ✓ →
  /// 请求里 `parentTag` 必须是**这个 tag** ✓（不是"组的第一个" ✗ 那是对多选组的口径 ✓），没选就不带 ✓。
  /// ⚠️ 多选那套（移动流 / 手机版最新 ✓）**不用它** ✗ —— 它的 `parentTag` 是 tab 自带的 `tab.parentTag` ✓。
  String selTag() {
    for (final f in filters) {
      if (!f.single) continue;
      for (final g in f.groups) {
        final ids = selIn(f, g);
        if (ids.isNotEmpty) return ids.first;
      }
    }
    return '';
  }
}

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
  LiveFeed(this._api, this.tab, this.sel);

  final XhLiveApi _api;
  final LiveTabDef tab;

  /// 这个 tab 自己的已选过滤器 ✓（`ensureMore` **每次都现读** ✓ → 改完再 `reload()` 就会带上新参数 ✓）
  final LiveFilterSel sel;

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
      final r = await _api.list(tab, _offset,
          extra: sel.groups(), parentTag: sel.selTag());
      if (gen != _gen) return; // 这次请求已被「进行筛选/重置」作废 ✗
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

  /// 每个 tab 一份**已选过滤器** ✓（**6 个 tab 互不影响** ✓ —— 用户点名要求 ✓；
  /// 4 个主 tab 用的是各自那份 `kLiveMainFilters*` ✓，两个叶子用 `kLiveFilters` ✓）
  final Map<int, LiveFilterSel> _sels = {};

  LiveFilterSel _selOf(int i) {
    final tab = kLiveTabs[i];
    return _sels.putIfAbsent(
        i,
        () => tab.hasMobileFilters
            ? LiveFilterSel() // 「移动流」/「手机版最新」：3 个过滤器入口 ✓
            : LiveFilterSel(
                filters: tab.filters)); // 4 个主 tab：只有自己那一个「筛选」✓
  }

  LiveFeed _feedOf(int i) =>
      _feeds.putIfAbsent(i, () => LiveFeed(_api, kLiveTabs[i], _selOf(i)));

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
            _LiveFeedView(key: ValueKey(i), feed: _feedOf(i), sel: _selOf(i)),
        ],
      ),
    );
  }
}

/// 一个 tab 的房间列表（2 列竖版卡 + 滚到底续拉 ✓；「移动流」/「手机版最新」上面还有过滤器入口 ✓）
class _LiveFeedView extends StatefulWidget {
  final LiveFeed feed;

  /// 这个 tab 自己的已选过滤器 ✓（只有那两个叶子用得上 ✓；其它 tab 传进来也不会显示 ✓）
  final LiveFilterSel sel;
  const _LiveFeedView({super.key, required this.feed, required this.sel});

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
    if (!widget.feed.tab.hasFilterRow) return body;
    // 有筛选入口的 tab 才画这排 ✓（**下划线 tab 样式** ✓ —— 见 LiveFilterBar ✓）：
    //   · 「移动流」/「手机版最新」= 3 个过滤器入口 ✓（文字带已选摘要 ✓）
    //   · **4 个主 tab** = 1 个「筛选」入口 ✓（文字就写「筛选」✓，已选状态在弹窗里看 ✓）
    return Column(
      children: [
        // ⚠️ 2026-10-05 用户真机反馈（**改了数值**）：主分类 tab 那排的**选中下划线**跟这排按钮
        //    "离得太近、有一点重叠" ✗ —— 根因是这排**紧贴**在 AppBar.bottom 的 TabBar 底下（间距 **0** ✓）。
        //    修法：**在这排自己头上留 padding**（给谁留都行 ✓ 留给下排最省事 ✓，不动 TabBar ✗）：
        //    间距 **0 → 12** ✓（下划线在 TabBar 盒子的最底 ✓ 现在它有 12px 净空 ✓ 不会被压住 ✓）
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: LiveFilterBar(
            sel: widget.sel,
            label: widget.feed.tab.hasMobileFilters ? null : '筛选',
            onApplied: () {
              setState(() {}); // 入口文字（已选 / 重置）跟着刷 ✓
              widget.feed.reload(); // 清空重拉：offset 归 0 ✓ + 带上新的 filterGroupTags ✓
            },
          ),
        ),
        Expanded(child: body),
      ],
    );
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
/// 入口 = `sel.filters`（「移动流」/「手机版最新」= 3 个 ✓；**4 个主 tab** = 1 个「筛选」✓）
/// + **有选择时**才出「重置」✓。
/// 入口文字 = 已选摘要 ✓（`外貌: 熟女 +1` ✓，同模拟器 ✓；**主 tab 那个入口不显示已选** ✗
/// —— 按钮就写「筛选」✓）；有选择的那项**橙字加粗 + 2px 下划线** ✓。
/// ⚠️ 挂在所有 `hasFilterRow` 的 tab 上 ✓（见 `_LiveFeedView` ✓）。
class LiveFilterBar extends StatelessWidget {
  final LiveFilterSel sel;

  /// 入口文字固定用这个（给了就用 ✓，否则用过滤器名 ✗）：4 个主 tab 传 `'筛选'` ✓
  final String? label;

  /// 「进行筛选」/「重置」生效后回调宿主 ✓（宿主负责刷入口文字 + `feed.reload()` ✓）
  final VoidCallback onApplied;

  const LiveFilterBar(
      {super.key, required this.sel, required this.onApplied, this.label});

  Future<void> _open(BuildContext context, int idx) async {
    // 草稿：弹窗里改的是副本 ✓ —— 点「进行筛选」才提交 ✓（取消/点遮罩 = 什么都不变 ✓，
    // 与 App 现成那套弹窗的「取消不改」一致 ✓；也免得入口显示"已选"而列表其实没筛 ✗）
    final draft = LiveFilterSel.copyOf(sel);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => LiveFilterDialog(sel: draft, start: idx),
    );
    if (ok == true) {
      sel.replaceWith(draft);
      onApplied();
    }
  }

  void _reset() {
    sel.clear(); // 只清**当前 tab** 这份 ✓（另一个 tab 的已选不动 ✓）
    onApplied();
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ 2026-10-05 用户真机反馈：**行底分隔线整条删掉**（原来是底下那层 Container 的
    //    `Border(bottom:)` ✓）→ 连 Container 一起删 ✗，**不留空盒占位**（1px 空盒在有些
    //    缩放下仍会显浅线 ✗）。选中态的 2px 橙下划线画在各 tab 自己的 `_tab` 里 ✓ 不受影响 ✓
    final fs = sel.filters;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < fs.length; i++)
            _tab(fs[i], () => _open(context, i)),
          if (sel.any) _resetTab(),
        ],
      ),
    );
  }

  /// 筛选入口按钮（**照 sim 的 `.pkbar button` / `button.mf-btn` ✓，2026-10-05 用户真机反馈"没有边框" ✗**）：
  /// sim 原文（`sim/index.html:322-323`）：
  ///   `border: 1px solid rgba(60,60,60,.35); background: transparent; border-radius: 8px;
  ///    padding: 5px 10px; font-size: 13px;`
  /// 选中态（`sim/index.html:413`）：`border-color: #e8590c; color: #e8590c; font-weight: 600;`
  /// ⚠️ sim 这一排**没有下划线** ✗（那是**上面主分类 TabBar** 的样式 ✓，见 `:1087` 的 `indicatorColor` ✓）
  ///    —— 原来这里错用了"文字 + 2px 橙下划线"的 tab 观感 ✗，现按 sim 换成**带边框的按钮** ✓。
  /// ⚠️ 边框色 `rgba(60,60,60,.35)` → `0x593C3C3C`（0x59=89 ≈ 0.35×255 ✓）。
  Widget _tab(LiveFilter f, VoidCallback tap) {
    final on = sel.count(f) > 0;
    return InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(8), // 水波纹也照圆角 ✓
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), // sim: 5px 10px ✓
        decoration: BoxDecoration(
          border: Border.all(
            color: on ? const Color(0xFFE8590C) : const Color(0x593C3C3C),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          // 固定文字（主 tab = 「筛选」✓）优先 ✓；否则给已选摘要 ✓
          label ?? sel.btnText(f),
          style: TextStyle(
            fontSize: 13, // sim: 13px ✓（原来 14 是为下划线 tab 定的）
            fontWeight: on ? FontWeight.w600 : FontWeight.w400, // sim .on: 600 ✓
            color: on
                ? (AppBg.i.isDark
                    ? const Color(0xFFFFB07A)
                    : const Color(0xFFE8590C))
                : (AppBg.i.isDark ? Colors.white : const Color(0xFF111111)),
          ),
        ),
      ),
    );
  }

  /// 「重置」按钮：sim 里它也是 `.pkbar` 里的一颗 `<button>`（`sim/index.html:5914` ✓，红字 `#e03131` ✓）
  /// → 同样带边框 + 圆角 ✓（与相邻的入口按钮一致 ✓，只是文字色是红的 ✓）
  Widget _resetTab() => InkWell(
        onTap: _reset,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0x593C3C3C), width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('重置',
              style: TextStyle(fontSize: 13, color: Color(0xFFE03131))),
        ),
      );
}

/// **过滤器弹窗**（**居中** ✓；尺寸/观感照 App 现成那套弹窗 ✓ —— `pornhub.dart` 的 `PhMoreDialog` ✓：
/// `AlertDialog` + `SizedBox(width: double.maxFinite)` + `ConstrainedBox(maxHeight: 420)` + 滚动内容 ✓）。
/// 顶部 = 3 个过滤器切换 chip ✓（带已选数 ✓）；内容 = 当前过滤器的子分组（小标题 + 多选 chip ✓）；
/// **未映射**项灰显、点了不过滤 ✓；底部 = 「重置」（只清当前过滤器 ✓）「进行筛选」（提交草稿并关窗 ✓）。
class LiveFilterDialog extends StatefulWidget {
  /// **草稿** ✓（调用方复制好的 ✓ —— 取消时原状态一个字都不动 ✓）
  final LiveFilterSel sel;

  /// 打开哪个过滤器（点哪个入口 ✓）
  final int start;

  const LiveFilterDialog({super.key, required this.sel, required this.start});

  @override
  State<LiveFilterDialog> createState() => _LiveFilterDialogState();
}

class _LiveFilterDialogState extends State<LiveFilterDialog> {
  /// ⚠️ 过滤器条目取自**草稿自己那份** [LiveFilterSel.filters] ✓ —— 4 个主 tab 只有 1 个入口 ✓；
  ///    别再硬引用全局 `kLiveFilters` ✗（那会让主 tab 的弹窗画错内容 ✓）。
  List<LiveFilter> get _fs => widget.sel.filters;

  late int _idx = widget.start.clamp(0, _fs.length - 1);

  @override
  Widget build(BuildContext context) {
    final f = _fs[_idx];
    return AlertDialog(
      // 顶部切换 chip 只有 1 个时（4 个主 tab ✓）标题就用过滤器名 ✓（否则照旧「筛选器」✓）
      title: Text(_fs.length == 1 ? f.name : '筛选器',
          style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 过滤器切换 chip（只有 1 个时也照画 ✓ —— 4 个主 tab 就是只有 1 个 ✓）
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < _fs.length; i++) _topChip(i),
                  ],
                ),
                const SizedBox(height: 4),
                // 当前过滤器的子分组（**组间 AND** ✓；组内多值 = **OR** ✓）
                for (final g in f.groups) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 6),
                    child: Text(
                      widget.sel.selIn(f, g).isEmpty
                          ? g.name
                          : '${g.name}（已选 ${widget.sel.selIn(f, g).length}）',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF888888)),
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in g.items) _chip(f, g, t),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => widget.sel.resetFilter(f)),
          child: const Text('重置', style: TextStyle(color: Color(0xFFE03131))),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('进行筛选'),
        ),
      ],
    );
  }

  Widget _topChip(int i) {
    final f = _fs[i];
    final n = widget.sel.count(f);
    final on = i == _idx;
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () => setState(() => _idx = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFFFE8D9) : const Color(0xFFF2F3F5),
          border: Border.all(
              color: on ? const Color(0xFFE8590C) : Colors.transparent),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          n > 0 ? '${f.name} ($n)' : f.name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            color: on ? const Color(0xFFC2410C) : const Color(0xFF333333),
          ),
        ),
      ),
    );
  }

  /// 多选 chip（照模拟器 `.chip` / `.chip.on` / `.chip.na` ✓）：
  /// 未映射（`id == null`）→ **灰显 + 「（未映射）」 + 点了没反应** ✓（不硬猜 tagId ✗、也不弹错 ✗）。
  /// ⚠️ 单选过滤器（`f.single` ✓ = 4 个主 tab ✓）→ 走 `exclusive` ✓：点一个换一个 ✓、再点已选 = 取消 ✓
  Widget _chip(LiveFilter f, LiveFilterGroup g, LiveTag t) {
    final na = t.id == null;
    final on = !na && widget.sel.selIn(f, g).contains(t.id);
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: na
          ? null
          : () => setState(() => widget.sel.toggle(f, g, t, exclusive: f.single)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: na
              ? const Color(0xFFF7F8F9)
              : (on ? const Color(0xFFFFE8D9) : const Color(0xFFF2F3F5)),
          border: Border.all(
              color: on ? const Color(0xFFE8590C) : Colors.transparent),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          na ? '${t.name}（未映射）' : t.name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            color: na
                ? const Color(0xFFB0B4BA)
                : (on ? const Color(0xFFC2410C) : const Color(0xFF333333)),
          ),
        ),
      ),
    );
  }
}

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

/// 从 master 清单里挑**第一条变体**的地址（用于"变体可达性"校验 ✓）。
/// ⚠️ 为什么加这条：实测 **id=209778341 的 master 200 / 无诱饵，但它的变体是 `403`（10 字节）** ✗
///   —— 只校验 master 会**放过这种流** → 播放器拿到 403 干等/黑屏 ✗。
///   解析不到就返回空串 ✓（调用方按"校验不过"处理 ✓）。
String firstVariantUrl(String master) {
  for (final l in master.split('\n')) {
    final t = l.trim();
    if (t.startsWith('http') && t.contains('.m3u8')) return t;
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
  bool _showX = false;

  /// 校验通过后的**我们自己的播放器** ✓（null = 还没开播 / 打不开 ✓）
  KpPlayer? _kp;

  /// 状态/错误提示 —— **不静默、不白屏** ✓：校验不过就把原因写在屏幕上 ✓
  String _err = '正在打开直播…';

  /// 起播看门狗（**不许无限转圈** ✓）：超时没出画面 → 重开一次 → 再超时 → 报错停 ✓
  Timer? _wd;

  /// 只重开**一次** ✓（不连环 ✗）
  bool _wdRetried = false;

  /// 起播看门狗阈值（毫秒）—— **8 秒**：
  /// 本机实测（curl 走代理）"master 0.52~0.80s + 变体 0.48~0.76s + 首个分片 0.32~0.90s" ≈ **2.5 秒** 是网络那段 ✓
  /// ⇒ 8 秒给了 ~3 倍余量 ✓；两次合计 ≈16 秒 ⇒ 落在用户要的"最多等十几秒" ✓（不是几分钟 ✗）。
  static const int _kLiveStartMs = 8000;

  /// 起播计时（秒）—— 只用来在**屏幕上**显示卡在哪一步 ✓（真机取证 ✓ 不写文件 ✗ 不加日志 ✗）
  int _secs = 0;
  Timer? _stageT;

  /// 直播**全量日志**用：从"进入房间页"起算的毫秒表 ✓（配 [SiteErrorLog] 里自带的时间戳 ✓）
  final Stopwatch _sw = Stopwatch();
  bool _logReady = false;
  bool _logStarted = false;
  int _logPosSec = -1;

  /// 记一条直播日志 ✓（**复用 [SiteErrorLog]** ✓：同一个文件/格式/导出方式 ✓ 不新建一套 ✗）。
  /// ⚠️ 节流（用户要求"不许影响性能" ✓）：只在**里程碑**记 ✓ ——
  ///   进入页面 / URL / 校验（状态码+字节+耗时）/ mpv 选项 / open 前后 / `ready`/`started` 的**跳变** /
  ///   position **每 5 秒**一条 / 看门狗 / 每一条错误 / 出画面总耗时 / 离开页面 ✓
  ///   —— 绝不每次 tick 都写盘 ✗（`KpState` tick 一秒可能有几十次 ✗）。
  void _log(String msg) {
    // `unawaited` = 明确"不等它" ✓（`SiteErrorLog.log` 自己吞错 ✓ 绝不把主流程带崩 ✓）
    unawaited(SiteErrorLog.log('直播/${widget.username}#${widget.id}', '+${_sw.elapsedMilliseconds}ms $msg'));
  }

  /// ⚠️ 2026-10-05（lead 要求）：**把 mpv 自己的日志接进来** —— 真机日志已证明卡点在 mpv 内部
  /// （我们这侧 1.7 秒全做完 ✓ mpv 从 open 到 `ready` ~27 秒 ✗）⇒ 要看清它卡在 DNS/TLS/HTTP/分片哪一步 ✓。
  /// **API 实证**（包源码，本机下载后查的 ✓）：
  ///   · `kp.videoController.player` 是**公开**的 ✓（`media_kit_video-1.2.5` 的
  ///     `lib/src/video_controller/video_controller.dart:56-58`：`class VideoController { … final Player player; }` ✓）
  ///     ⇒ 站点侧就能拿到 `Player` ✓ **不用动 `player_widget.dart`** ✓（它里面 `_p` 是私有的 ✗ 本来也碰不到 ✓）；
  ///   · 日志流：`media_kit-1.1.11` 的 `lib/src/models/player_stream.dart:91` = `final Stream<PlayerLog> log;` ✓
  ///     每条 = `PlayerLog{prefix, level, text}`（`lib/src/models/player_log.dart:15-23` ✓）。
  /// ⚠️ 过滤 + 限速（不然全量 mpv 日志会把 512KB 的日志文件冲爆 ✗）：
  ///   只留 [kMpvLogKeywords] 里的关键字行 ✓（http/tls/dns/hls/demux/error/cache/buffer…）；
  ///   每秒最多 4 条 ✓；每次打开最多 [kMpvLogMax] 条 ✓（到顶记一行"已达上限" ✓）；单行截到 400 字符 ✓。
  static const List<String> kMpvLogKeywords = <String>[
    'http', 'tls', 'dns', 'hls', 'demux', 'cache', 'buffer', 'stream',
    'error', 'fail', 'timeout', 'retry', 'conn', 'proxy', 'refused', 'reset',
  ];
  static const int kMpvLogMax = 200;
  int _mpvN = 0;
  int _mpvSec = -1;
  int _mpvInSec = 0;

  /// 订阅 mpv 日志 ✓（失败绝不影响播放 ✓ —— 整段 try/catch ✓）
  void _tapMpvLog(KpPlayer kp) {
    try {
      kp.videoController.player.stream.log.listen((e) {
        if (!mounted) return;
        if (_mpvN >= kMpvLogMax) {
          if (_mpvN == kMpvLogMax) {
            _mpvN++;
            _log('mpv 日志：已达上限 $kMpvLogMax 条 → 后续不再记 ✓（下一轮要更多就把这个常量调大 ✓）');
          }
          return;
        }
        final raw = '${e.prefix} ${e.level} ${e.text}'.replaceAll('\n', ' ');
        final low = raw.toLowerCase();
        var hit = false;
        for (final k in kMpvLogKeywords) {
          if (low.contains(k)) {
            hit = true;
            break;
          }
        }
        if (!hit) return; // 不相关行丢掉 ✓（过滤 ✓）
        final now = _sw.elapsedMilliseconds ~/ 1000;
        if (now == _mpvSec && _mpvInSec >= 4) return; // 每秒最多 4 条 ✓（限速 ✓）
        if (now != _mpvSec) {
          _mpvSec = now;
          _mpvInSec = 0;
        }
        _mpvInSec++;
        _mpvN++;
        _log('mpv[${now}s] ${raw.length > 400 ? raw.substring(0, 400) : raw}');
      }, onError: (Object _) {});
    } catch (_) {
      // 拿不到日志流也不影响播放 ✓
    }
  }

  /// 屏幕上的阶段文案（判据只用 `KpState` 那几个：`ready` / `started` / `position` ✓）：
  /// `打开中…` → `连接中…`（还没 `ready`）→ `缓冲中…`（`ready` 但没 `started`）→ 出画后**空**（不显示 ✓）
  /// ⚠️ 2026-10-05 修（真机日志里发现的）：**放弃之后这个轮询还在打** ✗（日志里 +17.7s 已"报错停止"，
  ///   +21.7s/+26.7s 却还有"等待 20s/25s" ✗）⇒ 放弃时把 [`_stageT`] 停掉 ✓，[`_gaveUp`] 之后不再显示/不再记 ✓。
  bool _gaveUp = false;

  String get _stage {
    if (_gaveUp) return ''; // 已经放弃（看门狗两次都超时 ✓）→ 别再刷"等待 Ns" ✗
    final k = _kp;
    if (k != null && k.value.started) return ''; // 出画面 ✓ 不显示 ✓
    if (k == null && _err != '正在打开直播…') return ''; // 中间已经在报错 ✗ 别再叠一行 ✓
    final s = '${_secs}s';
    if (k == null) return '打开中… $s';
    if (!k.value.ready) return '连接中… $s';
    return '缓冲中… $s'; // `ready` = duration>0（清单已解析 ✓）但 position 还是 0 ⇒ 还没出画 ✓
  }

  @override
  void initState() {
    super.initState();
    _sw.start(); // 全量日志的起算点 = **点卡片进入房间页这一瞬间** ✓
    _log('进入房间页 username=${widget.username} id=${widget.id}');
    _checkAndPlay();
  }

  /// 打开前**先抓一次 master**（很小 ✓ 实测 1.3~1.9KB）校验：**200 且正文里没有 `MOUFLON-ADVERT`** ✓。
  /// ⚠️ 2026-10-05 用户拍板：**兜底（WebEmbed）已删** ✗ ⇒ 校验不过 / 抓取失败 / 打开失败时
  ///   **不播**（播了就是广告 ✗）→ 屏幕上给**明确提示** ✓（不静默、不白屏 ✓）。
  /// 全部走 [Site.httpClient]（与全 App 同一套网络配置/代理 ✓）+ 站点 UA ✓。
  Future<void> _checkAndPlay() async {
    final id = widget.id;
    if (id <= 0) {
      _log('错误：没拿到 id（id=$id）→ 打不开 ✗');
      setState(() => _err = '这个房间没拿到 id，打不开直播 ✗');
      return;
    }
    KpPlayer? kp;
    try {
      final url = liveMasterUrl(id);
      _log('master URL 原文 = $url');
      final tM0 = _sw.elapsedMilliseconds;
      final r = await Site.httpClient
          .get(Uri.parse(url), headers: <String, String>{'User-Agent': Site.ua})
          .timeout(const Duration(seconds: 8));
      final ad = r.body.contains('MOUFLON-ADVERT');
      _log('校验 master → HTTP ${r.statusCode} / ${r.body.length} 字节 / 耗时 ${_sw.elapsedMilliseconds - tM0}ms / 是广告清单=$ad');
      if (r.statusCode != 200) {
        _log('错误：master 非 200（HTTP ${r.statusCode}）→ 不播 ✗');
        if (mounted) setState(() => _err = '直播流打不开（HTTP ${r.statusCode}）✗');
        return;
      }
      if (ad) {
        _log('错误：拿到广告清单（MOUFLON-ADVERT）→ 不播 ✗');
        if (mounted) setState(() => _err = '这条流被换成了广告清单，已停止播放 ✗');
        return; // ⚠️ 广告清单 → 千万别播 ✗
      }
      // ⚠️ 2026-10-05 新增（实测逼出来的）：**master 干净不等于能播** ✗ ——
      //   实测 id=209778341：master **200 / 无诱饵**，但它的变体是 **403（10 字节）** ✗
      //   ⇒ 只校验 master 会放过这种流 → 播放器拿到 403 黑屏/干等 ✗。
      //   这里再抓一次**第一条变体**（很小 ✓ 实测 0.48~0.76 秒 ✓ 3 秒超时 ✓）：
      //   非 200 就**不播**、直接报错 ✓（本机实测耗时：master 0.52~0.80s + 变体 0.48~0.76s ≈ 1.3 秒 ✓ 不是"转圈几分钟"的来源 ✓）
      final vu = firstVariantUrl(r.body);
      _log('master 里第一条变体 = ${vu.isEmpty ? '(没有 ✗)' : vu}');
      if (vu.isEmpty) {
        _log('错误：清单里没有可用清晰度 → 不播 ✗');
        if (mounted) setState(() => _err = '这条流的清单里没有可用的清晰度 ✗');
        return;
      }
      final tV0 = _sw.elapsedMilliseconds;
      final rv = await Site.httpClient
          .get(Uri.parse(vu), headers: <String, String>{'User-Agent': Site.ua})
          .timeout(const Duration(seconds: 3));
      _log('校验变体 → HTTP ${rv.statusCode} / ${rv.body.length} 字节 / 耗时 ${_sw.elapsedMilliseconds - tV0}ms');
      if (rv.statusCode != 200) {
        _log('错误：变体非 200（HTTP ${rv.statusCode}）→ 不播 ✗');
        if (mounted) {
          setState(() => _err = '这条流现在不可用（清晰度 HTTP ${rv.statusCode}）✗');
        }
        return;
      }
      _log('校验通过 ✓ 准备起播（变体只用于校验 ✓ 播放交 master ✓）');
      if (!mounted) return;
      kp = KpPlayer();
      KpPlayer.tuneStartupQuiet(kp);
      _tapMpvLog(kp); // ① 从这一刻起把 mpv 自己的日志接进来 ✓（过滤+限速 ✓ 见上面说明 ✓）
      _log('mpv(open 前)：tuneStartupQuiet 设了 demuxer-lavf-analyzeduration=2.0 / demuxer-lavf-probesize=1500000 / cache-pause-initial=no');
      // ⚠️ 2026-10-05 真机反馈"**出画面要 1 分钟**"（本机真起播只要 1.6~2 秒 ⇒ 是 mpv 侧 ✗）——
      //    **直播这边再收紧两刀**（只用 `KpPlayer` 已暴露的 `setMpvOptionQuiet` ✓ **不碰共用件** ✓；
      //     必须在 `open()` **之前**设 ✓（这几个是"加载时读"的缓存参数 ✓））：
      //   · `cache-secs = 2` —— mpv 手册原文：`--cache-secs=<seconds>` "How many seconds of audio/video to
      //     prefetch if the cache is active… **The default value is set to something very high**, so the
      //     actually achieved readahead will usually be limited by the value of the --demuxer-max-bytes option.
      //     Setting this option is usually only useful for limiting readahead." ⇒ 默认**极高** ✓ 起播前会拼命堆 ✓。
      //     值 = **2 秒**：直播分片本身就 2~6 秒 ✓ ⇒ 只要攒够"约一个分片"就能开 ✓（再多只会拖慢起播 ✓）。
      //   · `demuxer-max-bytes = 8388608`（8MB）—— 手册接着说**真正卡住 readahead 的是 `--demuxer-max-bytes`** ✓；
      //     而 `KpPlayer` 传的是 `bufferSize: bufferMb * 1024 * 1024`，默认 **200MB** ✗（实测原文：
      //     `player_widget.dart:134` `KpPlayer({int bufferMb = 200})` + `:137` `bufferSize: bufferMb * 1024 * 1024`）
      //     ⇒ 直播用 200MB 当上限 = 允许它堆**极多**才开 ✗。值 = **8MB**：按直播常见 2~6 Mbps 算 ⇒
      //     ≈ **10~30 秒**的缓冲 ✓（够吸收抖动 ✓ 又不会让人等 ✓）。
      //   ⚠️ 风险（诚实写在这）：值再往下（比如 2MB/1 秒）在弱网下更容易 underrun/断续 ✗ —— 我**不**再激进 ✓；
      //     真机若发现画面不稳，先回调 `demuxer-max-bytes` ✓。8 秒起播看门狗照旧兜底 ✓（没删 ✓）。
      //   ⚠️ **没设** `hls-bitrate`（手册里有它、"decide which track to select" ✓）—— 选哪档会掉画质 ✗，
      //     而"哪档更稳"我**没有实测** ✗ ⇒ **不猜** ✓；`demuxer-readahead-secs` 也不用设 ✓
      //     （手册：`cache-secs` 在 cache 开启且值更大时会**覆盖**它 ✓ ⇒ 设了上面那条它就不是瓶颈 ✓）。
      kp.setMpvOptionQuiet('cache-secs', '2');
      kp.setMpvOptionQuiet('demuxer-max-bytes', '8388608');
      kp.setMpvOptionQuiet('cache-pause-initial', 'no'); // 站点侧再显式钉一次 ✓（与 tuneStartupQuiet 同值 ✓ 无害 ✓）
      // 起播计时（只为屏幕提示 ✓）：从"开始 open"起每秒 +1 ✓，出画/销毁就停 ✓
      _secs = 0;
      _stageT?.cancel();
      _stageT = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || _gaveUp || (_kp != null && _kp!.value.started)) {
          t.cancel(); // 出画 ✓ 或已放弃 ✓ → 停掉 ✓（别一直跑 ✗）
          return;
        }
        setState(() => _secs++);
        // 全量日志：**每 5 秒一条**（节流 ✓ 绝不按 tick 写盘 ✗）—— 卡住时能看出卡在哪一步、卡多久 ✓
        if (_secs % 5 == 0) {
          final k = _kp;
          final st = k == null
              ? '还没建播放器（校验/连接中）'
              : 'ready=${k.value.ready} started=${k.value.started} '
                  'position=${k.value.position.inMilliseconds}ms duration=${k.value.duration.inMilliseconds}ms '
                  'error=${k.value.error}${k.value.errorText.isEmpty ? '' : ' errorText=${k.value.errorText}'}';
          _log('等待 ${_secs}s：$st');
        }
      });
      // ⚠️ 2026-10-05 用户拍板**改回"交 master"** ✓（上一轮交变体是**偏离站点做法** ✗）——
      //   依据 recon 实测：**站点自己在 iPhone 上给原生 `<video src>` 的就是 master**
      //     `.../master/<id>_auto.m3u8?playlistType=…&pkey=…`（不是变体 ✓）
      //   ⇒ 站点自己的原生播放**就是吃 master** ✓ 我们照它来 ✓（mpv 拿到 master 会自己选档/跟随 ✓）。
      //   `vu`（上面那条校验过的变体）**只用于校验** ✓ 不再交给播放器 ✓（校验逻辑原样保留 ✓ 挡 403/广告 ✓）。
      final tO0 = _sw.elapsedMilliseconds;
      _log('kp.open() 开始：URL=$url headers=User-Agent(${Site.ua.length} 字符)');
      await kp.open(url, httpHeaders: <String, String>{'User-Agent': Site.ua});
      _log('kp.open() 返回 ✓ 耗时 ${_sw.elapsedMilliseconds - tO0}ms（无异常 ✓）');
      // ⚠️ 2026-10-05：**open 之后再钉一次**这三条 ✓ ——
      //   实测顺序（行号）：`setMpvOptionQuiet` 在 `:1780-1782`、`open` 在它们**之后** ✓
      //   ⇒ **"参数调晚了"这个假设被排除** ✗（那三行本来就在 open 前 ✓）；
      //   但 `KpPlayer` 的 `bufferSize`（默认 **200MB** ✗ 见 `player_widget.dart:134/137`）是 media_kit
      //   **在 open 时**自己设的 ✓ ⇒ 它**可能盖掉**我前面那条 `demuxer-max-bytes` 🔍[推断] ⇒ 这里**再覆盖一次** ✓
      //   （幂等无害 ✓；真机若还慢，这条至少把"被 media_kit 盖掉"这种可能也排除了 ✓）。
      kp.setMpvOptionQuiet('cache-secs', '2');
      kp.setMpvOptionQuiet('demuxer-max-bytes', '8388608');
      kp.setMpvOptionQuiet('cache-pause-initial', 'no');
      _log('mpv(open 后)：再钉 cache-secs=2 / demuxer-max-bytes=8388608 / cache-pause-initial=no');
      // ⚠️ 2026-10-05：**这里不静音** ✗ —— 探测才静音（那是为了自动化测试不出声 ✓）；
      //   房间页是**给人看的** ✓ ⇒ 不设 `setVolume` ✓ 音量走系统默认 ✓
      //   （`KpState` 默认音量 = 100 ✓，见 `player_widget.dart:97` `this.volume = 100` ✓）。
      //   ⚠️ 只删了这处直播间页的静音 ✓ —— `_guardJs`（WebView 静音守护）与别的播放器**一个都没动** ✓。
      if (!mounted) {
        kp.shutdown();
        return;
      }
      final k2 = kp;
      // ⚠️ 2026-10-05 用户要求：**起播看门狗**（不许无限转圈 ✗）——
      //   判据 = `k2.value.position > Duration.zero` ✓（= `KpState.started` ✓，见 `player_widget.dart:103`
      //     `bool get started => position > Duration.zero;` ✓ —— 这是 `KpState` 唯一能读到的"出画"信号 ✓
      //     它**没有**暴露 width/height ✗ 所以没得选 ✓）。
      //   阈值 [_kLiveStartMs] = **8 秒**（理由：本机实测"master 0.52~0.80s + 变体 0.48~0.76s + 首个分片 0.32~0.90s"
      //     ≈ **2.5 秒**是网络那一段 ✓ → 8 秒给它 ~3 倍余量 ✓；两次共 ~16 秒 ⇒ 落在你要的"最多等十几秒" ✓）。
      //   超时 → **重开一次**（只一次 ✓ 不连环）；再超时 → 明确报错并停 ✓。
      _startWatchdog(k2, url);
      // 开播后真断了（校验过了但流中途坏）→ **说清楚** ✓（别让用户对着黑屏 ✗）；
      // ⚠️ 只在"还没出画面"时报 ✗ —— mpv 起播期偶发网络错误不该弹（用户的痛点是慢/黑屏，不是弹错 ✓）
      k2.addListener(() {
        if (!identical(_kp, k2)) return;
        // 全量日志：只记 **ready / started 的跳变**（不按 tick 写 ✗ ✓ 节流 ✓）
        if (k2.value.ready && !_logReady) {
          _logReady = true;
          _log('KpState: ready=true（duration=${k2.value.duration.inMilliseconds}ms）');
        }
        if (k2.value.position > Duration.zero) {
          if (!_logStarted) {
            _logStarted = true;
            _log('KpState: started=true（出画面 ✓ 从进入页面算总耗时 ${_sw.elapsedMilliseconds}ms）');
          }
          // 出画了 → 撤掉看门狗 ✓（这一刻起不再重开/不再报"没画面" ✓）
          _wd?.cancel();
          _wd = null;
          return;
        }
        // 出画前每 5 秒也留一条 position（与上面那条"等待 Ns"互补 ✓ 都是节流过的 ✓）
        final ps = (k2.value.position.inMilliseconds / 1000).floor();
        if (ps > 0 && ps != _logPosSec && ps % 5 == 0) {
          _logPosSec = ps;
          _log('KpState: position=${ps}s duration=${k2.value.duration.inMilliseconds}ms '
              'ready=${k2.value.ready} started=${k2.value.started} +${_sw.elapsedMilliseconds}ms');
        }
        if (k2.value.error) {
          final t = k2.value.errorText;
          final msg = t.isEmpty ? '直播中断 ✗' : '直播中断：$t';
          _log('错误：播放器报 error=true errorText=${t.isEmpty ? '(空)' : t} @+${_sw.elapsedMilliseconds}ms');
          if (msg != _err && mounted) setState(() => _err = msg);
        }
      });
      setState(() => _kp = kp);
    } catch (e, st) {
      _log('错误：打开直播抛异常 → $e\n${st.toString().split('\n').take(4).join(' <- ')}');
      _wd?.cancel();
      _wd = null;
      kp?.shutdown();
      if (mounted) setState(() => _err = '打开直播失败：$e');
    }
  }

  /// 起播看门狗：`_kLiveStartMs` 内没出画面（`position > 0` ✓）→ **重开一次** ✓；再超时 → 报错停 ✓
  /// `url` = **master**（与站点自己的原生播放一致 ✓ 见 `_checkAndPlay` 里的说明 ✓）
  void _startWatchdog(KpPlayer kp, String url) {
    _wd?.cancel();
    _wd = Timer(const Duration(milliseconds: _kLiveStartMs), () async {
      if (!mounted || !identical(_kp, kp)) return;
      if (kp.value.position > Duration.zero) return; // 已经出画 ✓（listener 那边也会撤 ✓）
      if (!_wdRetried) {
        _wdRetried = true;
        _log('看门狗：8 秒到，仍未出画面 → **重开一次** ✓（position=${kp.value.position.inMilliseconds}ms '
            'ready=${kp.value.ready} error=${kp.value.error}）');
        if (mounted) setState(() => _err = '直播还没出画面，正在重试一次…');
        try {
          // **重开一次**：也交 **master** ✓（与站点自己的做法一致 ✓；重开 = 真重开 ✗ 不是只重置计时器 ✗）
          final t1 = _sw.elapsedMilliseconds;
          await kp.open(url, httpHeaders: <String, String>{'User-Agent': Site.ua});
          _log('看门狗：重开 kp.open() 返回 ✓ 耗时 ${_sw.elapsedMilliseconds - t1}ms');
          // 这里同样**不静音** ✓（给人看的 ✓ 音量系统默认 ✓ 见上面那段说明 ✓）
        } catch (e) {
          _log('看门狗：重开抛异常 → $e');
          // 重开失败也不用管 ✓：下面那次超时会直接报错 ✓
        }
        _startWatchdog(kp, url);
        return;
      }
      _log('看门狗：第二次 8 秒也过了 → 报错停止 ✓（总耗时 ${_sw.elapsedMilliseconds}ms，'
          'position=${kp.value.position.inMilliseconds}ms ready=${kp.value.ready} '
          'error=${kp.value.error} errorText=${kp.value.errorText.isEmpty ? '(空)' : kp.value.errorText}）');
      // ⚠️ 2026-10-05 修：**放弃了就要真停** ✓ —— 那个每秒轮询（_stageT）也 cancel 掉 ✓
      //    （真机日志里出现过"+17.7s 已报错停止，+21.7s/+26.7s 还在打'等待 20s/25s'"✗）
      _gaveUp = true;
      _stageT?.cancel();
      _stageT = null;
      if (mounted) {
        setState(() => _err = '这条直播一直没出画面，可能主播没有在推流 ✗');
      }
      _wd = null;
    });
  }

  @override
  void dispose() {
    _log('离开房间页（页面存活 ${_sw.elapsedMilliseconds}ms）'); // 全量日志的最后一条 ✓
    _sw.stop();
    _wd?.cancel(); // 看门狗别在页面销毁后还动 ✓
    _stageT?.cancel(); // 起播计时的每秒 Timer ✓
    _kp?.shutdown();
    super.dispose();
  }



  @override
  Widget build(BuildContext context) {
    // 这一页是黑底全屏 → 状态栏图标固定用**白色** ✗ 别跟着背景图明暗翻 ✓
    // （否则浅色背景下会变成深色图标 = 黑压黑看不见 ✗）
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          // ⚠️ 2026-10-05 真机反馈"点屏幕 X 不显示" —— **根因（读代码即实锤）**：这句 onTap **只关不开** ✗
          //    （原来"显示 X"是 `WebEmbed(toggleX: true)` 那个参数干的 ✓，上一轮"去掉兜底"时它被一起删了 ✗
          //     ⇒ 就再也没有任何人把它打开 ✓）。现在改成**真 toggle** ✓。
          //    另：`opaque` ✓ —— 让**整屏任意位置**的点击都归我们 ✓（原来的 `translucent` 会被上层
          //    `Video`(Texture) 先接走 ✗）。X 层在 Stack 里**排在 Video 之后** = 在最上面 ✓（位置/默认隐藏都没动 ✓）。
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _showX = !_showX),
          child: Stack(
            children: [
                // ⚠️ 2026-10-05 用户拍板：**只用我们自己的播放器** ✓ —— WebEmbed 那条路**已删** ✗
                //    （校验不过/抓取失败 → 报错提示 ✓ 不静默、不白屏、也**不播广告** ✓）
                if (_kp != null)
                  // ⚠️ 2026-10-05 用户要求：**直播界面极简** —— 不要进度条 / 不要全屏按钮 / 不要中间那颗播放键 ✓
                  //    `controls: NoVideoControls` 就是 media_kit_video 的"关掉它自带那套控件"开关 ✓
                  //    （名字与用法照仓库现成那处 ✓：`lib/player_widget.dart:466-471` 用的就是它 ✓
                  //     包源码实证：`media_kit_video-1.2.5` 的 `.../controls/no.dart:14` = `const NoVideoControls = null;` ✓
                  //     该文件由 `media_kit_video_controls.dart:7` 导出 ✓）
                  //    `fit/fill` 与详情页那处保持一致（等比不拉伸 ✓ 黑底 ✓）
                  Positioned.fill(
                    child: Video(
                      controller: _kp!.videoController,
                      fit: BoxFit.contain,
                      fill: Colors.black,
                      controls: NoVideoControls,
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
              if (_showX)
                // SafeArea：X 落在**状态栏下面** ✓（用户明确要求：不压状态栏 ✓）
                // ⚠️ 2026-10-05 真机反馈"X 太小" → **尺寸翻倍** ✓（图标 20→**40**、触摸区 38→**76** ✓，
                //    圆底 padding 8→**12** ✓ 一并放大；位置/默认隐藏/点击 toggle **都没动** ✓）
                SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Material(
                        color: Colors.black.withOpacity(0.45),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(), // X = 关闭回列表 ✓
                          child: const SizedBox(
                            width: 76,
                            height: 76,
                            child: Icon(Icons.close,
                                color: Colors.white, size: 40),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // ⚠️ 2026-10-05：**起播状态提示**（真机取证用 ✓）—— 只显示在屏幕上 ✓
              //    **不写文件、不加日志** ✗；出画面（`started`）后自己消失 ✓；出错误时用 `_err` ✓。
              if (_stage.isNotEmpty)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: Text(
                      _stage,
                      style: const TextStyle(color: Color(0xFFB0B4BA), fontSize: 13),
                    ),
                  ),
                ),
            ],
          ),
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
