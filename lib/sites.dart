// 站点专属清单/档案已下放到各站点文件 ✓（循环 import 是允许的 ✓）
import 'sites/kmsvip.dart';
import 'sites/xvideos.dart';
import 'sites/hanime1.dart';
import 'sites/porna.dart';
import 'sites/wordpress.dart';
import 'sites/huangguo.dart';
import 'sites/pektino.dart';
import 'sites/madou.dart';
import 'sites/pornhub.dart';
import 'sites/xhamster.dart';
import 'sites/xhamsterlive.dart';

import 'package:flutter/material.dart';

/// 站点清单 —— 首页宫格里每个方块 = 这里的一条。
/// 加站点：在 kSites 里加一条即可，其他文件都不用动。
enum SiteKind {
  /// 应用内原生页面（抓取解析，见 lib/api.dart 顶部注释）
  native,
}

/// 站点**属于哪个宫格**（2026-10-04 加 ✓）：点播页 / 直播页各是一个清单 ✓。
///
/// ⚠️ 为什么用**字段**而不是"在共用 UI 里判模板" ✗：共用 UI 里不该出现任何站名/站点模板名 ✗
/// （`ModuleGridPage` 只看 `group` ✓、直播宫格也只看 `group` ✓）→ 以后加第二个直播站
/// **一行 UI 都不用改** ✓（站点文件里写 `group: SiteGroup.live` 就行 ✓）。
enum SiteGroup {
  /// 底栏「点播」宫格里的内容站（默认 ✓）
  module,

  /// 底栏「直播」宫格里的站点
  live,
}

/// native 站点的网页模板 —— 决定用哪套解析规则（见 lib/api.dart）
enum SiteTemplate {
  /// WordPress + DPlayer 系（51吃瓜 / 每日大赛 / 91吃瓜 / 911爆料网 / 51fans1）
  wordpress,

  /// 黄果短剧：列表走 JSON 接口，详情页内嵌 videoInitialData JSON
  huangguo,

  /// 91porna：video-item 卡片 + /index/detail_play 换播放地址
  porna,

  /// Pektino（X/Twitter 视频保存排行）：列表/搜索走 /api/media JSON，
  /// 视频源是推文原 mp4（video.twimg.com 直链）
  pektino,

  /// Hanime1.me（H動漫）：分类列表=网格卡（/search?genre=），
  /// 搜索=横排卡（/search?query=）；详情页 watch?v= 里是多档直链 mp4
  /// （vdownload.hembed.com，secure 签名约 12 小时有效，过期自动重取详情）
  hanime1,

  /// XVideos（tube 站）：列表/搜索/标签共用 thumb-block 卡片（页码从 0 计：
  /// 第 N 页 = 路径 /N-1）；详情页内嵌 setVideoHLS / setVideoUrlLow/High 直链
  /// （xvideos-cdn，无防盗链；secure 签名约 5 小时有效，过期自动重取详情）
  xvideos,

  /// 快猫（kmsvip.xyz）：Vue SPA，数据走**加密 API**（AES-128-CBC 大写 HEX +
  /// md5 签名，协议照站点前端 JS，见 api.dart _kmPost）；分类 = #/video_list
  /// ?type=0 热门视频 / type=1 视频广场；列表 19 条/页、页码从 1 起；详情给
  /// https 直链 mp4（实测无防盗链）。站点没有搜索页、也没有标签。
  kmsvip,

  /// 麻豆社（madou.club）：WordPress + 自研主题 showcase，卡片 `article.excerpt`
  /// （**没有 itemscope**，和上面 5 个 wordpress 站的类名完全不是一套）。
  /// 翻页：`/page/N`、`/category/{slug}/page/N`、`/tag/{slug}/page/N`、
  /// `/?paged=N&s=kw`（是 paged）；榜单 /likes /week /month 没有翻页。
  /// 站点**没有发布时间** → 卡片 meta 放观看数（".post-view" 里的数字，
  /// 站点原文是"观看(59.26K)"，只留"59.26K"）。
  /// 详情正文只有一个玩家 iframe（dash.madou.club 的分享页）：
  /// 分享页里 token + m3u8 路径拼出唯一播放源（见 api.dart _mdDetail）。
  madou,

  /// Pornhub（cn.pornhub.com，用户指定）：**中文站是域名自带的**
  /// （`<html class="language-cn" lang="cn">`，标题/导航/分类名全中文，不用选语言）。
  ///
  /// ⚠️ **按移动版 DOM 解析**（App 的全局 UA 就是 iPhone Safari，站点会返回移动版）：
  /// 卡片 = `li[data-video-vkey]`；标题 `a.thumbnailTitle`；时长 `div.bgEffect.time`
  /// （`4:00`）；封面 `a[data-poster]`（带 `hdnea=st=…~exp=…~hmac=…` 签名，约 24h）。
  /// 桌面 UA 下站点给的是**另一套**（`li.pcVideoListItem` + `a[title]` + `var.duration`
  /// + `img[src]`），字段名不同，别混用。
  ///
  /// 翻页 `?page=N`（首页 `/`、`/video?page=N`、分类 `/video?c=NN&page=N`）；
  /// 搜索 `/video/search?search=kw`；详情 `/view_video.php?viewkey=xxx`。
  ///
  /// ⚠️ 详情页视频源：`mediaDefinitions` 里有 4 档 HLS（240/480/720/1080，每档一个
  /// `master.m3u8`，带 `h=`/`e=` 签名）+ 一个 `/video/get_media?s=<base64>` 接口。
  /// **2026-10-02 实测：HLS 直连一律 410 Gone、get_media 返回 `[]`**（疑与会话/登录态
  /// 绑定，纯 HTTP 拿不到）——见 DEVLOG 第 70 条，这块**待解**。
  pornhub,

  /// xHamster（tw.xhamster.com，用户 2026-10-02 指定）。
  ///
  /// ⚠️ 三条与别的站不同的关键事实（均已实测，见 DEVLOG 第 75 条）：
  /// 1. **静态 HTML 里移动版和桌面版两套 DOM 同时存在**（与 UA 无关；移动版渲染是客户端
  ///    按**视口宽度**注水的）→ 我们只抓静态 HTML，所以**必须按移动版选择器解析**：
  ///    卡片 `[data-role="mobile-video-thumb"]`（移动版 9 处 / 桌面版 26 处）。
  ///    误用桌面的 `div.thumb-image-container` 会拿到**另一套卡**，字段名也不同。
  /// 2. **分页是路径式**：`/hd/2`、`/4k/2`、`/newest/2`……；`?page=N` 会被**忽略**。
  /// 3. **媒体源是 HLS master**，藏在静态 HTML 的 `<link rel="preload" as="fetch">` 里
  ///    （全文唯一的 `.m3u8`），5 档 144p~1080p；**CDN 既不校验 Referer 也不校验 UA**
  ///    （与 Pornhub 正好相反）→ 不需要 vproxy 那套 Referer 注入，
  ///    `_playReferer()` 也不用为它加特例。
  ///
  /// ⚠️ 详情页的**相关推荐在移动版是懒加载空壳**（只有「正在載入...」），静态 HTML 里
  /// 只有 JSON 形态的 `data-role="related-item"`（不是 DOM 元素）→ v1 先 `showRelated: false`。
  xhamster,

  /// xHamsterLive（zh.xhamsterlive.com）—— ⚠️ 与上面的 xHamster **是两个不同的站** ✗
  /// （不同的接口、不同的字段、不同的域名 ✓）。
  ///
  /// 这是**直播站**：**不走** `lib/api.dart` 那套列表/详情解析 ✗，而是走
  /// `lib/sites/xhamsterlive.dart` 里那套（JSON 接口 `/api/front/models` ✓ + 全屏 WebView 房间页 ✓）
  /// → 它**没有**列表页/详情页/搜索页 ✓（`Api.ui` 对它是 `null` ✓，也不会有人调 ✓）。
  /// 只在底栏「直播」宫格里出现 ✓（`group: SiteGroup.live` ✓）。
  xhamsterlive,
}

/// 一个分类 tab，可以带子分类（子项同样是 tab）。
/// key 的含义随模板不同（见 lib/api.dart 里各 SiteTemplate 的说明）：
/// - wordpress：分类 slug（"wpcz"）；以 / 开头 = 直接当站内路径用（如 51fans1 的 "/order/hot/"）
/// - huangguo：频道 slug（"ai-duanju"）；子项的 key 是排序值（latest/hot/original/random）
/// - porna：站内路径（"/comic/index/video?category=play"）；也可用 "search:关键词"
class SiteTab {
  final String key;
  final String name;
  final List<SiteTab> subs;

  const SiteTab(this.key, this.name, [this.subs = const []]);
}

class SiteEntry {
  /// 方块下面显示的名字
  final String name;
  final SiteKind kind;

  /// kind=native：用哪套解析规则
  final SiteTemplate template;

  /// kind=native：域名列表，抓取时逐个试，跑通的那个会被记住并优先使用。
  /// ⚠️ 51吃瓜 的很多"域名"只是跳转入口：只有根路径 / 会跳到真站，
  /// /category/... /archives/... 这类内容路径直接 404（cgwz1/cgwz2/51cgo13 实测都是
  /// 404 或跳到死域名）。所以只放能直接出内容的真站域名，否则每个都要白等一轮。
  final List<String> hosts;

  /// kind=native：顶部 tab（顺序即 tab 顺序），可以带子分类
  final List<SiteTab> categories;

  /// kind=web：目标地址
  final String url;

  /// 竖屏封面站（如 黄果短剧 封面是 3:4 竖图）→ 卡片封面按竖屏比例显示
  final bool portraitCovers;

  /// 详情页要不要显示「相关推荐」（默认显示；51吃瓜 按用户要求关掉）
  final bool showRelated;

  /// 列表页的"筛选器"（多级分类：主题/时长/排序，如 Pektino）。null = 没有
  final SiteFilters? filters;

  /// 可选图标地址；以 / 开头 = 用该站第一个域名拼（例：'/favicon.ico'）；
  /// 留空 = 用名字首字画色块。站点 favicon 是 ICO，app 内解码（见 fetched_image.dart）
  final String iconUrl;

  /// 首字色块底色（有 iconUrl 时不用）
  final Color color;

  /// 这个站进**哪个宫格**（默认「点播」✓；直播站写 `SiteGroup.live` ✓）。
  /// 共用 UI 只按它过滤 ✓，不认站名/模板名 ✗（见 [SiteGroup] 的注释 ✓）
  final SiteGroup group;

  const SiteEntry({
    required this.name,
    this.kind = SiteKind.native,
    this.template = SiteTemplate.wordpress,
    this.hosts = const [],
    this.categories = const [],
    this.url = '',
    this.portraitCovers = false,
    this.showRelated = true,
    this.filters,
    this.iconUrl = '',
    this.color = const Color(0xFFFF7043),
    this.group = SiteGroup.module,
  });
}

/// 黄果短剧每个频道的 4 个排序子 tab（key 即接口的 sort 值）。
/// 注意：模拟器（sim/server.mjs）用正则解析本文件，子分类必须写成内联字面量，
/// 不能抽成常量/函数引用，否则模拟器读不到（App 侧不受影响）。

/// Pektino 主分类页面里的"筛选器"——这是站点的**多级分类**：
/// 主题（40 个标签）/ 语言（10 个）/ 时长（6 档）/ 排序（4 档）。
/// 主分类（每日/每周/每月/所有时间）是平级的 4 个 tab，筛选挂在页面里。
/// 主题和语言照站点"按标签筛选"弹窗分两区（数据显示名不带 #）。
class SiteFilters {
  final List<SiteTab> themes;
  final List<SiteTab> languages;
  final List<MapEntry<String, String>> durations;
  final List<MapEntry<String, String>> sorts;

  /// [themes] 那一组在 UI 上叫什么（弹窗标题 / 按钮文字）。
  /// Pektino 照站点叫「主题」；Pornhub 的这组是**分类清单**，所以要显示「分类」。
  final String themeLabel;

  /// 那一组**还没选**时按钮上的文案（选中后显示选中项的名字）。
  /// Pektino 用默认的「筛选」；Pornhub 的分类清单照站点/模拟器写「分类选择」。
  final String themeEmptyLabel;

  const SiteFilters({
    required this.themes,
    required this.languages,
    required this.durations,
    required this.sorts,
    this.themeLabel = '主题',
    this.themeEmptyLabel = '筛选',
  });
}

/// Pektino 的 40 个主题标签（照站点"按标签筛选"弹窗原顺序、原名；
/// 数据源 = 站点 /api/tags，is_language=false 的那批）。
/// ⚠️ 模拟器（sim/server.mjs）用正则解析本文件——具名常量可以，函数不行。

/// Pektino 的 10 个语言标签（/api/tags 里 is_language=true 的那批）

/// Pektino 时长档：value = 接口的 "min,max"（秒；"0,0" = 全部，不带参数）

/// Pektino 排序档（接口的 sort 值；默认按点赞）

/// 麻豆社「其他原创/企划」的 28 个分类（照站点导航原顺序、原名）。
/// key = 站点链接里那段**已编码的 slug**，逐字照抄站点导航（别自己重新编码）。
/// ⚠️ 模拟器（sim/server.mjs）用正则解析本文件：子分类只能是①内联字面量数组、
/// ②顶层 `const List<SiteTab> _xxx = [...]`，所以这里是顶层常量（同 hgSorts）。

/// 麻豆社「筛选」的 3 个榜单（照站点导航：/likes /week /month）。
/// 都以 / 开头 = 站内路径；**没有翻页**（/week /month 站点目前就是空的，
/// 解析出 0 条 = 空列表，不是错）。

/// Pornhub 的**全部分类**（102 个）——用户 2026-10-02 要求「分类」做成**弹窗选择**，
/// 内容照站点 `/categories` 页（「热门色情片类型」+「所有色情片类型」）**原序原名**。
/// ⚠️ 顶栏「分类」下拉里只有它推荐的十几个热门项，**不是**这个清单；
/// ⚠️ 也不要再往里塞「性取向 / 视频内语言」的筛选项（异性恋 / 男同 / 跨性别 / 女女萨福系 / chinese）
/// —— 用户点名去掉过。key 直接是站内路径，列表按它请求（`/video?c=NN`、少数是 `/categories/xxx`
/// 或 `/vr` `/hd` `/sfw` `/interactive` 这类特殊入口）。

/// xHamster「分类」清单：站点 `/categories` 页里 `assignable` JSON 的 **13 组 × 388 个标签**。
/// ⚠️ 这 388 个标签**不在 DOM 里**（页面只渲染了「製作」那一组，其余要点了锚点才 JS 加载），
/// 完整数据藏在页面的 Vue props JSON（`assignable`）里 → 这一份是**离线抄下来硬编码**的
/// （跟 `phCats` 同一套路数：站点加了新标签得手动更新）。
/// 分组顺序照站点：製作 → 行動 → 戀物癖 → 指示 → 年齡 → 種族 → 身體 → 頭髮 → 人數 → 性玩具 → 服飾 → 設想 → 位置
/// xHamster「色情明星」tab **自己那套**筛选清单（用户 2026-10-02 明确要求：
/// "色情明星的分类选择要显示正确的明星"）。
/// ⚠️ **跟 `xhCats` 那 388 个视频分类是两回事** —— 用户为这个混用发过火 ✗：
/// 388 个是「分类」tab 的**视频分类**；这里是**演员分类**（站点演员页自己的 40 个 chip，
/// 逐条实测 slug 可用 ✓）。两个清单的路径前缀都不一样：
///   视频分类  `/categories/<slug>`
///   演员分类  `/pornstars/all/categories/<slug>`
/// 榜單三项（色情明星 / 在US受歡迎 / 按國家）与站点顶部导航一致 ✓。

/// 演员分类 40 个（站点演员页 chip 的原顺序，逐条实测 slug 可用 ✓）。
/// 名字取自 `xhCats` 同一张表；german/japanese/french/british 四个表里没有，
/// 照站点 chip 写死（sim 的 `XH_STAR_CATS` 同源）。

/// xHamster「分类」tab 的 388 个分类，**按站点原顺序分 13 组**（製作→行動→戀物癖→指示→
/// 年齡→種族→身體→頭髮→人數→性玩具→服飾→設想→位置）。
/// ⚠️ 用户 2026-10-03 实机报："弹窗没有显示制作/行动/恋物癖… 所有标签全部挤在一块了" ✗
/// —— App 侧原先用的是**拍平**的 `xhCats`（分组只在注释里 ✗），所以弹窗只有一片标签、没有标题 ✗。
/// 这份分组结构与 sim 的 `XH_CATS` **由脚本同源生成** ✓（同顺序、同内容），别手工改。
/// ⚠️ **不能写成 `const List<MapEntry<…>>`** ✗ —— Dart 的 `MapEntry` **不是 const 构造**
/// （`MapEntry(this.key, this.value)`，没有 const），外面套 `const` 会直接编译失败 ✗。
/// 所以用顶层 `final`（内层每个 `const [...]` 仍然是 const ✓）。

/// Pornhub「色情明星」页（/pornstars）的筛选 —— 用户 2026-10-02 要求照站点右上角
/// 那四个控件做：最受欢迎 ▾ / 色情明星和模特 ▾ / 每月 ▾ / + 更多筛选设置。
/// 参数形态全部是 URL 查询串（桌面版页面里 `<a href="/pornstars?…">` 实测出来的，
/// **不是猜的**）：`?o=` 排序、`?performerType=` 类型、`?t=` 时间区段。
/// key 空串 = 该控件的默认值（站点默认：最受欢迎 / 色情明星和模特 / 每月）。

/// 「+ 更多筛选设置」里那 7 组（照站点筛选面板；组内第一个空 key 都代表"全部"）。
/// ⚠️ 每组的 `key` 是**URL 参数名**（gender/ethnicity/tattoos/hair/piercings/cup/breasttype，
/// 从站点筛选面板的链接实测），`name` 才是中文显示名。

const List<SiteEntry> kSites = [
  kSite01,
  kSite02,
  kSite03,
  kSite04,
  kSite05,
  kSite06,
  kSite07,
  kSite08,
  kSite09,
  kSite10,
  kSite11,
  kSite12,
  kSite13,
  kSite14,
  // 直播站（xHamsterLive ✓）：`group: SiteGroup.live` → 只进底栏「直播」宫格 ✓，不进「点播」✗。
  // ⚠️ 名字**故意不带数字** ✓ —— 模拟器只认 `kSiteNN` ✗（见 lib/sites/xhamsterlive.dart 里那条注释 ✓）
  kSiteLive,
];
