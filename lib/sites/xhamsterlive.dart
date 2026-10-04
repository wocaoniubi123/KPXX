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
// 改用原生 `<video>` ✓）→ **App 端 = WebView 直接加载房间页** ✓（`lib/web_embed.dart` 的 `WebEmbed`
// ✓，自带静音注入 ✓、已开内联播放 ✓）。

import 'dart:convert';

// ⚠️ 本站是**唯一**要自己画界面的站点（下划线 tab / 房间卡 / 全屏房间页 ✓）→ 必须 import material ✓。
// （其它站点文件只 import `dart:ui show Color` ✗ —— 它们不画界面 ✓；这里的 import 不会引起
//  `Element`/`Text`/`Key` 撞名 ✗，因为本站不 import html/dom ✓ 也不 import encrypt ✓）
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../app_background.dart';
import '../app_bg.dart';
import '../base/fetch.dart';
import '../fetched_image.dart';
import '../home_page.dart' show RowsGrid;
import '../sites.dart';
import '../web_embed.dart';

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

  /// 接口的 `parentTag`（只有带了 `groups` 才拼 ✓）
  final String? parentTag;

  /// 要不要带 `specialEventTagIds`（= 4 个主 tab ✓）
  final bool specialEvent;

  /// 这个 tab 有没有那 3 个**页内过滤器** ✓（= 「移动流」/「手机版最新」两个叶子 ✓；
  /// 4 个主 tab **没有** ✗ —— 它们的子分类筛选不在本批范围 ✓）
  bool get hasFilterRow => groups.isNotEmpty;

  const LiveTabDef(this.name, this.primaryTag,
      {this.groups = const [], this.parentTag, this.specialEvent = false});
}

/// 6 个 tab（顺序 = 界面上的顺序 ✓；前 4 个是**主分类** ✓，后 2 个是**快捷叶子** ✓）
const List<LiveTabDef> kLiveTabs = [
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

  const LiveFilter(this.key, this.name, this.groups);
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

  LiveFilterSel();

  /// 复制一份当**草稿** ✓（弹窗改草稿 ✓ 点「进行筛选」才提交 ✓；取消 = 什么都不变 ✗
  /// —— 与 App 现成那套弹窗（`pornhub.dart` 的 PhMoreDialog「取消不改」✓）同一套语义 ✓）
  LiveFilterSel.copyOf(LiveFilterSel o) {
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

  /// 点一下 chip（同组可多选 ✓、再点取消 ✓）；**未映射的直接忽略** ✓
  void toggle(LiveFilter f, LiveFilterGroup g, LiveTag t) {
    final id = t.id;
    if (id == null) return;
    final k = _bucket(f, g);
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
    for (final f in kLiveFilters) {
      for (final g in f.groups) {
        for (final t in g.items) {
          if (t.id == id) return t.name;
        }
      }
    }
    return id;
  }

  /// 入口上的文字 ✓（如 `外貌: 熟女 +1` ✓；没选就是过滤器名 ✓）
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
  List<List<String>> groups() {
    final out = <List<String>>[];
    for (final f in kLiveFilters) {
      for (final g in f.groups) {
        final ids = selIn(f, g);
        if (ids.isNotEmpty) out.add(List<String>.of(ids));
      }
    }
    return out;
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

  const LiveRoom({
    required this.username,
    required this.viewers,
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
  Future<LivePageResult> list(LiveTabDef tab, int offset,
      {List<List<String>> extra = const []}) async {
    final txt = await _f.text(_path(tab, offset, extra));
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
  /// 组 = **该 tab 自带的**（`tab.groups` ✓）在前 + 页内过滤器选的 ✓ 在后（照 lead 的拼装规则 ✓）
  String _path(LiveTabDef tab, int offset, List<List<String>> extra) {
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
      b.write('&parentTag=${tab.parentTag ?? groups.first.first}');
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
      final r = await _api.list(tab, _offset, extra: sel.groups());
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

  /// 每个 tab 一份**已选过滤器** ✓（「移动流」/「手机版最新」**互不影响** ✓ —— 用户点名要求 ✓）
  final Map<int, LiveFilterSel> _sels = {};

  LiveFilterSel _selOf(int i) => _sels.putIfAbsent(i, LiveFilterSel.new);

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
          // **下划线 tab**（用户指定 ✓）：选中 = 橙字加粗 + 2px 下划线；行底一条分隔线 ✓
          // ⚠️ 不是胶囊按钮 ✗（胶囊那套是子分类行的样式 ✓，别混 ✗）
          indicatorColor: const Color(0xFFE8590C),
          indicatorWeight: 2,
          dividerColor: const Color(0xFFECEEF1),
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
    // 「移动流」「手机版最新」才有那 3 个过滤器入口 ✓（**下划线 tab 样式** ✓ —— 见 LiveFilterBar ✓）
    return Column(
      children: [
        LiveFilterBar(
          sel: widget.sel,
          onApplied: () {
            setState(() {}); // 入口文字（已选 / 重置）跟着刷 ✓
            widget.feed.reload(); // 清空重拉：offset 归 0 ✓ + 带上新的 filterGroupTags ✓
          },
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
      MaterialPageRoute(builder: (_) => LiveRoomPage(username: r.username)),
    );
  }

  Widget _hint(String s) => Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
            child: Text(s, style: TextStyle(color: kTxtSub, fontSize: 12))),
      );
}

/// **过滤器入口行**（**下划线 tab 样式** ✓ —— 与站点页上面那排主 tab **同一套观感** ✓，不是按钮 ✗）。
/// 3 个入口 = `kLiveFilters`（外貌 / 国家 / 可请求提供的表演 ✓）+ **有选择时**才出「重置」✓。
/// 入口文字 = 已选摘要 ✓（`外貌: 熟女 +1` ✓，同模拟器 ✓）；有选择的那项**橙字加粗 + 2px 下划线** ✓。
/// ⚠️ 只挂在「移动流」/「手机版最新」两个 tab 上 ✓（见 `LiveTabDef.hasFilterRow` ✓）。
class LiveFilterBar extends StatelessWidget {
  final LiveFilterSel sel;

  /// 「进行筛选」/「重置」生效后回调宿主 ✓（宿主负责刷入口文字 + `feed.reload()` ✓）
  final VoidCallback onApplied;

  const LiveFilterBar({super.key, required this.sel, required this.onApplied});

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
    return Container(
      // 行底一条分隔线（与上面那排主 tab 的分隔线**同一个色** ✓）
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFECEEF1))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < kLiveFilters.length; i++)
              _tab(kLiveFilters[i], () => _open(context, i)),
            if (sel.any) _resetTab(),
          ],
        ),
      ),
    );
  }

  /// 下划线 tab（选中 = 橙字加粗 + 2px 下划线 ✓；未选中 = 普通字 + 透明下划线占位 ✓）
  Widget _tab(LiveFilter f, VoidCallback tap) {
    final on = sel.count(f) > 0;
    return InkWell(
      onTap: tap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 7),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: on ? const Color(0xFFE8590C) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          sel.btnText(f),
          style: TextStyle(
            fontSize: 14,
            fontWeight: on ? FontWeight.w700 : FontWeight.w400,
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

  Widget _resetTab() => InkWell(
        onTap: _reset,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 7),
          child: const Text('重置',
              style: TextStyle(fontSize: 14, color: Color(0xFFE03131))),
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
  late int _idx = widget.start.clamp(0, kLiveFilters.length - 1);

  @override
  Widget build(BuildContext context) {
    final f = kLiveFilters[_idx];
    return AlertDialog(
      title: const Text('筛选器', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 三个过滤器（切换 + 已选数 ✓）
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < kLiveFilters.length; i++) _topChip(i),
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
    final f = kLiveFilters[i];
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
  /// 未映射（`id == null`）→ **灰显 + 「（未映射）」 + 点了没反应** ✓（不硬猜 tagId ✗、也不弹错 ✗）
  Widget _chip(LiveFilter f, LiveFilterGroup g, LiveTag t) {
    final na = t.id == null;
    final on = !na && widget.sel.selIn(f, g).contains(t.id);
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: na ? null : () => setState(() => widget.sel.toggle(f, g, t)),
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
/// ⚠️ 为什么是 WebView 而不是模拟器那套内嵌播放器 ✗：模拟器用 `new Function` 在桌面上加载站点
/// CDN 的 React 组件 ✓，那是桌面 hack ✗、App 上没有 ✗；站点在 iPhone 上本来就会**跳过 JS 播放器、
/// 直接给原生 `<video>`** ✓ → 用 `WebEmbed` 加载房间页就是"站点自己那条正常路径" ✓
/// （顶层加载 ✓、静音由 `WebEmbed` 的注入全程压着 ✓、`allowsInlineMediaPlayback` 已开 ✓）。
class LiveRoomPage extends StatefulWidget {
  /// 房间名（= 站内路径末段 ✓）→ 房间页 = `https://zh.xhamsterlive.com/<username>` ✓
  final String username;
  const LiveRoomPage({super.key, required this.username});

  @override
  State<LiveRoomPage> createState() => _LiveRoomPageState();
}

class _LiveRoomPageState extends State<LiveRoomPage> {
  /// X 默认**隐藏** ✓（点屏幕才出现 ✓）
  bool _showX = false;

  @override
  Widget build(BuildContext context) {
    // 这一页是黑底全屏 → 状态栏图标固定用**白色** ✗ 别跟着背景图明暗翻 ✓
    // （否则浅色背景下会变成深色图标 = 黑压黑看不见 ✗）
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          // 点屏幕 = 只切 X 的显隐 ✓（列表状态在上一层，这里什么都不动 ✓）
          behavior: HitTestBehavior.translucent,
          onTap: () => setState(() => _showX = !_showX),
          child: Stack(
            children: [
              // 房间页：站点自己的页面（自带静音注入 ✓ / 内联播放 ✓）
              WebEmbed(url: 'https://zh.xhamsterlive.com/${widget.username}'),
              if (_showX)
                // SafeArea：X 落在**状态栏下面** ✓（用户明确要求：不压状态栏 ✓）
                SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Material(
                        color: Colors.black.withOpacity(0.45),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(), // X = 关闭回列表 ✓
                          child: const SizedBox(
                            width: 38,
                            height: 38,
                            child: Icon(Icons.close,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ),
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
