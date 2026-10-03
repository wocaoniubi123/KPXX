// 站点专属清单/档案已下放到各站点文件 ✓（循环 import 是允许的 ✓）
import 'sites/huangguo.dart';
import 'sites/pektino.dart';
import 'sites/madou.dart';
import 'sites/pornhub.dart';
import 'sites/xhamster.dart';

import 'package:flutter/material.dart';

/// 站点清单 —— 首页宫格里每个方块 = 这里的一条。
/// 加站点：在 kSites 里加一条即可，其他文件都不用动。
enum SiteKind {
  /// 应用内原生页面（抓取解析，见 lib/api.dart 顶部注释）
  native,

  /// 应用内 WebView 直接打开 url
  web,
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
  SiteEntry(
    name: '51吃瓜',
    template: SiteTemplate.wordpress,
    iconUrl: '/favicon.ico',
    // 用户要求：51吃瓜 详情页不显示「相关推荐」（它那个热闻区是纯文字链）
    showRelated: false,
    // 固定用这个：2026-09-29 实测 /category/wpcz/ 返回 200 + 25 篇文章（真站）
    hosts: ['51cg1.com'],
    // 顺序 = 站点导航原顺序（27 个，2026-09-30 实测首页导航）
    categories: [
      SiteTab('wpcz', '今日吃瓜'),
      SiteTab('xsxy', '学生校园'),
      SiteTab('whhl', '网红黑料'),
      SiteTab('rdsj', '热门大瓜'),
      SiteTab('mrdg', '吃瓜榜单'),
      SiteTab('bkdg', '必看大瓜'),
      SiteTab('cbdj', 'AI成人短剧'),
      SiteTab('ysyl', '成人视频'),
      SiteTab('mrds', '每日大赛'),
      SiteTab('lldd', '伦理道德'),
      SiteTab('gcjq', '国产视频'),
      SiteTab('thjx', '探花精选'),
      SiteTab('whhj', '网黄合集'),
      SiteTab('snsn', '骚男骚女'),
      SiteTab('whmx', '明星爆料'),
      SiteTab('hwcg', '海外吃瓜'),
      SiteTab('rrcg', '人人吃瓜'),
      SiteTab('ldcg', '领导干部'),
      SiteTab('jpll', '软萌甜妹'),
      SiteTab('sjb', '竞技吃瓜'),
      SiteTab('qubk', '吃瓜看戏'),
      SiteTab('dcbq', '擦边撩骚'),
      SiteTab('zzs', '性爱技巧'),
      SiteTab('cgxw', '吃瓜新闻'),
      SiteTab('yczq', '原创博主'),
      SiteTab('51djc', '51剧场'),
      SiteTab('51hd', '往期活动'),
    ],
    color: Color(0xFFFF6B6B),
  ),
  SiteEntry(
    name: '每日大赛',
    template: SiteTemplate.wordpress,
    iconUrl: '/favicon.ico',
    hosts: ['www.mrds66.com'],
    categories: [
      SiteTab('mrds', '每日大赛'),
      SiteTab('ztds', '主题大赛'),
      SiteTab('rstt', '热搜吃瓜'),
      SiteTab('xazd', '校园学生'),
      SiteTab('blyp', '必撸大赛'),
      SiteTab('fctg', '反差泄密'),
      SiteTab('mhds', '网红黑料'),
      SiteTab('lqdp', '猎奇重口'),
      SiteTab('jdsj', 'AV看片'),
      SiteTab('mxwh', '明星大赛'),
      SiteTab('smdh', '动漫之家'),
      SiteTab('dypd', '影视国漫'),
      SiteTab('mtds', 'cos写真'),
      SiteTab('ysds', '声控ASMR'),
      SiteTab('czds', '寸止挑战'),
      SiteTab('hjds', '混剪PMV'),
      SiteTab('tgds', '原创投稿'),
      SiteTab('omjp', '欧美精品'),
      SiteTab('qwcs', '全网参赛'),
      SiteTab('aijc', 'AI剧场'),
    ],
    color: Color(0xFF7C4DFF),
  ),
  SiteEntry(
    name: '91吃瓜',
    template: SiteTemplate.wordpress,
    iconUrl: '/favicon.ico',
    // 2026-09-29 实测：/category/zxcghl/ 会 302 到 www.91cg1.com 后返回 30 篇文章（同模板站）
    hosts: ['91cg1.com', 'www.91cg1.com'],
    categories: [
      SiteTab('zxcghl', '今日吃瓜'),
      SiteTab('sports-live', '体育直播'),
      SiteTab('dydj', 'AI短剧'),
      SiteTab('rsdg', '最高点击'),
      SiteTab('zdtop', '91周榜'),
      SiteTab('ydtop', '91月榜'),
      SiteTab('bcdg', '必吃大瓜'),
      SiteTab('whhl', '网红黑料'),
      SiteTab('mxhl', '明星黑料'),
      SiteTab('qwys', '社会奇闻'),
      SiteTab('mrds', '每日大赛'),
      SiteTab('sstp', '实时偷拍'),
      SiteTab('lpsd', '深夜撸片'),
      SiteTab('hjll', '海角乱伦'),
      SiteTab('91th', '91探花'),
      SiteTab('crdm', '成人动漫'),
      SiteTab('xsjlb', '师生专栏'),
      SiteTab('fclv', '反差靓女'),
      SiteTab('tgqg', '投稿求瓜'),
      SiteTab('gcwh', '网黄合集'),
      SiteTab('aikj', '明星AI'),
      SiteTab('zptp', '自拍偷拍'),
      SiteTab('lqzk', '猎奇重口'),
    ],
    color: Color(0xFF2F80ED),
  ),
  SiteEntry(
    name: '911爆料网',
    template: SiteTemplate.wordpress,
    iconUrl: '/favicon-v4.ico',
    // 2026-09-29 实测：/category/jrgb/ 会跳到 CloudFront 域名后返回 52 篇文章（同模板站）
    hosts: ['911bl.com', 'd3gn4v6ng8b20o.cloudfront.net'],
    categories: [
      SiteTab('jrgb', '今日大瓜'),
      SiteTab('aidj', 'AI短剧'),
      SiteTab('shijiebei', '优先投放区'),
      SiteTab('mrds', '每日大赛'),
      SiteTab('hjsq', '海角社区'),
      SiteTab('crfys', '午夜剧场'),
      SiteTab('dmhv', '动漫天堂'),
      SiteTab('sgpjs', '水果派解说'),
      SiteTab('rmgb', '独家爆料'),
      SiteTab('rlph', '黑料排行'),
      SiteTab('ssdbl', '热点吃瓜'),
      SiteTab('xyss', '校园吃瓜'),
      SiteTab('bgzq', '反差爆料'),
      SiteTab('whbl', '网红黑料'),
      SiteTab('mxhl', '明星吃瓜'),
      SiteTab('blqw', '猎奇吃瓜'),
      SiteTab('tksm', '偷窥泄密'),
      SiteTab('zksr', 'SM专区'),
      SiteTab('ntll', '男男女女'),
      SiteTab('thjx', '探花经典'),
      SiteTab('fljq', '福利视频'),
      SiteTab('crlz', '网黄专辑'),
      SiteTab('slec', '影视床戏'),
      SiteTab('kpzj', '看片专辑'),
      SiteTab('mjmsjb', '世界杯黑料'),
      SiteTab('zqbb', '世界杯宝贝'),
    ],
    color: Color(0xFF27AE60),
  ),
  // ---------------------------------------------------------------------------
  SiteEntry(
    name: '51fans',
    template: SiteTemplate.wordpress, // 同 WordPress 系（/category/{slug}/ + DPlayer），解析器兼容其卡片结构
    iconUrl: '/favicon.ico',
    hosts: ['51fans1.com'],
    // 顺序 = 站点导航（#navbar 里的「全部分类」组）原顺序，别自己排：
    // 51fans首页、51fans热门、今日更新、我的订阅、网黄精选、国产专栏、原创投稿、
    // 主题合集、AI短剧、成人综艺、探花大神、乱伦禁忌、吃瓜黑料、AV鉴赏、里番动漫、官方公告板
    // （首页/我的订阅不放 tab：一个是首页、一个要登录）
    categories: [
      SiteTab('/order/hot/', '热门'),
      SiteTab('/order/today/', '今日更新'),
      SiteTab('txwh', '网黄精选'),
      SiteTab('txfc', '国产专栏'),
      SiteTab('txyc', '原创投稿'),
      SiteTab('ztds', '主题合集'),
      SiteTab('aidj', 'AI短剧'),
      SiteTab('txzy', '成人综艺'),
      SiteTab('thtp', '探花大神'),
      SiteTab('txll', '乱伦禁忌'),
      SiteTab('txhl', '吃瓜黑料'),
      SiteTab('txav', 'AV鉴赏'),
      SiteTab('txdm', '里番动漫'),
      SiteTab('yczm', '官方公告板'),
    ],
    color: Color(0xFFE91E63),
  ),
  SiteEntry(
    name: '黄果短剧',
    template: SiteTemplate.huangguo,
    iconUrl: '/favicon.ico',
    hosts: ['huangguoai.com'],
    // 封面是 3:4 竖图
    portraitCovers: true,
    // 顺序 = 站点导航原顺序：精选推荐 / 最近上新（首页两个板块，路径型）
    // → AI成人短剧 / AI成人漫剧 / AI换脸 / AI魔改（各带 4 个排序）
    // → 专题 / 排行榜 / 黄果吃瓜（顶部导航里 AI魔改 后面那三个）
    categories: [
      SiteTab('/recommend', '精选推荐'),
      SiteTab('/newest', '最近上新'),
      SiteTab('ai-duanju', 'AI成人短剧', hgSorts),
      SiteTab('ai-manju', 'AI成人漫剧', hgSorts),
      SiteTab('ai-huanlian', 'AI换脸', hgSorts),
      SiteTab('ai-mogai', 'AI魔改', hgSorts),
      SiteTab('/topics/', '专题'),
      SiteTab('/ranks/hot/', '排行榜'),
      // 吃瓜社区：站名就叫「黄果吃瓜」（不是"吃瓜黑料"——之前起错了），
      // 且下面带 3 个子分类，照站点导航原样。帖子卡是**横版大图**
      // （站点桌面就是 2 列网格）→ 列表页按 key 前缀走 2 列横版
      SiteTab('/chigua/', '黄果吃瓜', [
        SiteTab('/chigua/', '全部'),
        SiteTab('/chigua/remen/', '热门吃瓜'),
        SiteTab('/chigua/yuanchuang/', 'AI原创'),
      ]),
    ],
    color: Color(0xFFFFB300),
  ),
  SiteEntry(
    name: '91porna',
    template: SiteTemplate.porna,
    iconUrl: '/favicon.ico',
    hosts: ['91porna.com'],
    // 顺序 = 站点导航原顺序（首页、91视频、91短视频、黑料吃瓜、AI成人、日本AV、
    // 91动漫、精选合集、色情小说、91品牌），已接入的排前面、按站点相对顺序；
    // 尚未接入的：精选合集（列表 JS 渲染）、色情小说（纯文字）、91品牌（外链导航）
    categories: [
      SiteTab('/comic/index/video?category=play', '91视频', [
        // 一级子分类 = 站点下拉菜单里的入口（顺序照站点原样：热门排行榜、国产原创、吃瓜爆料…三级片）
        // 「热门排行榜」自己还带二级子分类 —— 那 12 个排序（正在播放…收藏最多）
        SiteTab('/comic/index/video?category=now_month_hot', '热门排行榜', [
          SiteTab('/comic/index/video?category=play', '正在播放'),
          SiteTab('/comic/index/video?category=now_hot', '当前最热'),
          SiteTab('/comic/index/video?category=new_update', '最近更新'),
          SiteTab('/comic/index/video?category=original', '91原创'),
          SiteTab('/comic/index/video?category=now_month_hot', '本月最热'),
          SiteTab('/comic/index/video?category=ten_minutes', '10分钟以上'),
          SiteTab('/comic/index/video?category=twenty_minutes', '20分钟以上'),
          SiteTab('/comic/index/video?category=now_month_collect', '本月收藏'),
          SiteTab('/comic/index/video?category=hd', '高清'),
          SiteTab('/comic/index/video?category=month_hot', '每月最热'),
          SiteTab('/comic/index/video?category=now_month_comment', '本月讨论'),
          SiteTab('/comic/index/video?category=max_collect', '收藏最多'),
        ]),
        SiteTab('/comic/index/video?category=original', '国产原创'),
        SiteTab('search:吃瓜 黑料 爆料', '吃瓜爆料'),
        SiteTab('search:熟女', '熟女做爱'),
        SiteTab('search:萝莉', '可爱萝莉'),
        SiteTab('search:动漫', '成人动漫'),
        SiteTab('search:黑人', '大屌黑人'),
        SiteTab('search:巨乳', '童颜巨乳'),
        SiteTab('search:换妻', '少妇换妻'),
        SiteTab('search:内射', '内射中出'),
        SiteTab('search:按摩', '会所按摩'),
        SiteTab('search:探花', '91探花'),
        SiteTab('search:家庭乱伦', '家庭乱伦'),
        SiteTab('search:三级片', '三级片'),
      ]),
      SiteTab('/melonshort', '91短视频', [
        SiteTab('/melonshort', '全部'),
        SiteTab('/melonshort/amateur', '素人自拍'),
        SiteTab('/melonshort/hunjian', '高燃混剪'),
        SiteTab('/melonshort/fancha', '反差系列'),
        SiteTab('/melonshort/wanghong', '网红达人'),
        SiteTab('/melonshort/mingxing', '明星大瓜'),
        SiteTab('/melonshort/zipai', '原创自拍'),
      ]),
      SiteTab('/%E9%BB%91%E6%96%99%E5%90%83%E7%93%9C/%E6%8E%A8%E8%8D%90', '黑料吃瓜', [
        SiteTab('/%E9%BB%91%E6%96%99%E5%90%83%E7%93%9C/%E6%8E%A8%E8%8D%90', '全部'),
        SiteTab('/%E9%BB%91%E6%96%99%E5%90%83%E7%93%9C/%E4%BB%8A%E6%97%A5%E5%90%83%E7%93%9C/%E6%9C%80%E6%96%B0', '今日吃瓜'),
        SiteTab('/%E9%BB%91%E6%96%99%E5%90%83%E7%93%9C/%E5%AD%A6%E7%94%9F%E6%A0%A1%E5%9B%AD/%E6%8E%A8%E8%8D%90', '学生校园'),
        SiteTab('/%E9%BB%91%E6%96%99%E5%90%83%E7%93%9C/%E6%98%8E%E6%98%9F%E9%BB%91%E6%96%99/%E6%8E%A8%E8%8D%90', '明星黑料'),
        SiteTab('/%E9%BB%91%E6%96%99%E5%90%83%E7%93%9C/%E7%BD%91%E7%BA%A2%E9%BB%91%E6%96%99/%E6%8E%A8%E8%8D%90', '网红黑料'),
        SiteTab('/%E9%BB%91%E6%96%99%E5%90%83%E7%93%9C/%E6%AF%8F%E6%97%A5%E5%A4%A7%E8%B5%9B/%E6%8E%A8%E8%8D%90', '每日大赛'),
        SiteTab('/%E9%BB%91%E6%96%99%E5%90%83%E7%93%9C/%E5%90%8D%E4%BA%BA%E5%90%88%E9%9B%86/%E6%8E%A8%E8%8D%90', '名人合集'),
      ]),
      SiteTab('search:ai成人', 'AI成人', [
        SiteTab('search:ai成人', '全部'),
        SiteTab('search:ai短剧', 'AI成人短剧'),
        SiteTab('search:ai漫剧', 'AI漫剧'),
        SiteTab('search:ai美女', 'AI美女'),
        SiteTab('search:+ai换脸', 'AI换脸'),
      ]),
      SiteTab('/comic/index/av', '日本AV', [
        SiteTab('/comic/index/av', '最新更新'),
        SiteTab('/comic/av/relvideo?model=1&type=theme&order=week', '多P群交'),
        SiteTab('/comic/av/relvideo?model=12&type=theme&order=week', '无码解放'),
        SiteTab('/comic/av/relvideo?model=5&type=theme&order=week', '中文字幕'),
        SiteTab('/comic/av/relvideo?model=6&type=theme&order=week', '制服诱惑'),
        SiteTab('/comic/av/relvideo?model=107&type=tag&order=week', '黑人专区'),
        SiteTab('/comic/av/relvideo?model=7&type=theme&order=week', 'SM调教'),
      ]),
      SiteTab('search:h动漫', '91动漫', [
        SiteTab('search:h动漫', '全部'),
        SiteTab('search:成人动漫', '成人动漫'),
        SiteTab('search:日本动漫', '日本动漫'),
        SiteTab('search:国产动漫', '国产动漫'),
        SiteTab('search:3d动漫', '3d动漫'),
        SiteTab('search:同人动漫', '同人动漫'),
      ]),
      // 精选合集：列表页是"合集卡"（点开进该合集的视频列表）
      SiteTab('/moviesets', '精选合集', [
        SiteTab('/moviesets', '最新合集'),
        SiteTab('/moviesets/rank', '排行榜合集'),
        SiteTab('/moviesets/category', '分类合集'),
        SiteTab('/moviesets/people', '人物合集'),
        SiteTab('/moviesets/brand', '品牌合集'),
      ]),
      // 色情小说：列表是文字卡（无封面），详情是小说正文（article.markdown-body）
      SiteTab('/novels', '色情小说', [
        SiteTab('/novels', '全部'),
        SiteTab('/novels/dushi-jiqing/new', '都市激情'),
        SiteTab('/novels/xiaoyuan-zhilian/new', '校园之恋'),
        SiteTab('/novels/renqi-shunv/new', '人妻熟女'),
        SiteTab('/novels/jiating-luanlun/new', '家庭乱伦'),
      ]),
    ],
    color: Color(0xFF3B5998),
  ),
  SiteEntry(
    name: 'Pektino',
    template: SiteTemplate.pektino,
    iconUrl: '/favicon.ico',
    hosts: ['pektino.com'],
    // 主分类（顶部导航）**只有 4 个**：每日 / 每周 / 每月 / 所有时间
    //（站点还有个"收藏"页，要登录，未接）。
    // 20 个主题标签 + 时长 + 排序是**主分类页面里的筛选器**（多级分类），
    // 全部放进 filters，由列表页的筛选行渲染（照站点：筛选按钮 + 两个下拉）。
    categories: [
      SiteTab('/zh-CN/', '每日'),
      SiteTab('/zh-CN/weekly', '每周'),
      SiteTab('/zh-CN/monthly', '每月'),
      SiteTab('/zh-CN/all', '所有时间'),
    ],
    filters: SiteFilters(
      themes: pkThemes,
      languages: pkLangs,
      durations: pkDurations,
      sorts: pkSorts,
    ),
    color: Color(0xFF1DA1F2),
  ),
  SiteEntry(
    name: 'Hanime1',
    template: SiteTemplate.hanime1,
    // 站点的 favicon 实际是 tab_logo.png（在 vdownload.hembed.com，**必须带 secure
    // 签名**，不带 = 403；签名到 2124 年，可直接当常量用）
    iconUrl:
        'https://vdownload.hembed.com/image/icon/tab_logo.png?secure=EJYLwnrDlidVi_wFp3DaGw==,4867726124',
    hosts: ['hanime1.me'],
    // 封面是竖版（实测 268×394）→ 竖屏封面站
    portraitCovers: true,
    // 主分类 = 首页分类 tabs（照站点原序，10 个）。
    // 「H漫畫」是站外链接（hanimeone.me，未接）；「新番預告」桌面上另有 /previews
    // 月表页，这里用与首页 tabs 一致的 search?genre= 形态（同一套列表卡片）。
    categories: [
      SiteTab('裏番', '裏番'),
      SiteTab('泡麵番', '泡麵番'),
      SiteTab('Motion Anime', 'Motion Anime'),
      SiteTab('3DCG', '3DCG'),
      SiteTab('2.5D', '2.5D'),
      SiteTab('2D動畫', '2D動畫'),
      SiteTab('AI生成', 'AI生成'),
      SiteTab('MMD', 'MMD'),
      SiteTab('Cosplay', 'Cosplay'),
      SiteTab('新番預告', '新番預告'),
    ],
    // 相关推荐走 AJAX POST（/video/load-playlist-chunk + _token），v1 未接
    showRelated: false,
    color: Color(0xFF5B2A86),
  ),
  SiteEntry(
    name: 'XVideos',
    template: SiteTemplate.xvideos,
    // 官方 logo 的 32px PNG（绝对地址）
    iconUrl:
        'https://assets-cdn77.xvideos-cdn.com/v3/img/skins/default/logo/xv.white.32.png',
    hosts: ['www.xvideos.com'],
    // 主分类 = **站点顶部导航**（照站点中文版）：最佳影片 / 分类 / 頻道 / 色情明星。
    // 其余导航项经核对不上：「RED 视频」是外站(xvideos.red 付费网站)、
    // 「现场直播摄影机/约会/女友/遊戲」是 zline0 广告外链、「簡介」(/profileslist)
    // 非视频列表。「分类」下面挂站点分类菜单全量（名称照站点；逐一实测 200 且有内容）。
    // 「Curious wife no panties」只有 2 条（近无资源）未上；「所有標簽」是标签索引
    // （非视频列表）未上。「最新」= 站点首页那份列表（不在菜单里，我留作分类默认项）。
    // 「最佳影片」子分类 = 免费月份条（照站点：八月 2026 起往回 24 个月，快照；
    // 站点每月出新月份，需要时更新此处；收费的 RED（/best-of-red）未上）。
    // 翻页：/c/、/tags/、/trans、/gay、/lang/chinese 第 N 页 = 原路径/{N-1}(0 计)；
    //       /best 特殊（月份路径）、/new 特殊（第1页='/'），见 api.dart _xvList。
    // 頻道/色情明星：索引列表可抓；点进频道/演员的二级内容站点是 JS 异步加载、
    // 静态抓不到——卡片刻意先给提示，二级待另找数据接口。
    categories: [
      SiteTab('/best', '最佳影片', [
        SiteTab('/best/2026-08', '八月 2026'),
        SiteTab('/best/2026-07', '七月 2026'),
        SiteTab('/best/2026-06', '六月 2026'),
        SiteTab('/best/2026-05', '五月 2026'),
        SiteTab('/best/2026-04', '四月 2026'),
        SiteTab('/best/2026-03', '三月 2026'),
        SiteTab('/best/2026-02', '二月 2026'),
        SiteTab('/best/2026-01', '一月 2026'),
        SiteTab('/best/2025-12', '十二月 2025'),
        SiteTab('/best/2025-11', '十一月 2025'),
        SiteTab('/best/2025-10', '十月 2025'),
        SiteTab('/best/2025-09', '九月 2025'),
        SiteTab('/best/2025-08', '八月 2025'),
        SiteTab('/best/2025-07', '七月 2025'),
        SiteTab('/best/2025-06', '六月 2025'),
        SiteTab('/best/2025-05', '五月 2025'),
        SiteTab('/best/2025-04', '四月 2025'),
        SiteTab('/best/2025-03', '三月 2025'),
        SiteTab('/best/2025-02', '二月 2025'),
        SiteTab('/best/2025-01', '一月 2025'),
        SiteTab('/best/2024-12', '十二月 2024'),
        SiteTab('/best/2024-11', '十一月 2024'),
        SiteTab('/best/2024-10', '十月 2024'),
        SiteTab('/best/2024-09', '九月 2024'),
      ]),
      SiteTab('/new', '分类', [
        SiteTab('/new', '最新'),
        SiteTab('/lang/chinese', '說中文的色情'),
        SiteTab('/tags/2d', '2d'),
        SiteTab('/tags/3d', '3d'),
        SiteTab('/c/Arab-159', '阿拉伯'),
        SiteTab('/trans', '變性'),
        SiteTab('/c/Mature-38', '成熟'),
        SiteTab('/c/Cuckold-237', '出轨背叛/火辣妻子'),
        SiteTab('/c/Femdom-235', '调教'),
        SiteTab('/tags/anime', '动漫'),
        SiteTab('/c/Anal-12', '肛交'),
        SiteTab('/c/Brunette-25', '褐发'),
        SiteTab('/c/Black_Woman-30', '黑人'),
        SiteTab('/c/Redhead-31', '紅髮'),
        SiteTab('/c/Fucked_Up_Family-81', '家庭乱搞'),
        SiteTab('/c/Blonde-20', '金髮'),
        SiteTab('/c/Big_Cock-34', '巨屌'),
        SiteTab('/c/Big_Tits-23', '巨乳'),
        SiteTab('/c/Big_Ass-24', '巨臀'),
        SiteTab('/c/Blowjob-15', '口交'),
        SiteTab('/c/Latina-16', '拉丁裔'),
        SiteTab('/c/Milf-19', '辣媽'),
        SiteTab('/c/Gapes-167', '裂开'),
        SiteTab('/c/Ass-14', '美臀'),
        SiteTab('/gay', '男同'),
        SiteTab('/c/Lesbian-26', '女同'),
        SiteTab('/c/bbw-51', '胖女'),
        SiteTab('/c/Squirting-56', '喷出'),
        SiteTab('/c/Fisting-165', '拳交'),
        SiteTab('/c/Gangbang-69', '羣交'),
        SiteTab('/c/Teen-13', '少女'),
        SiteTab('/c/Cumshot-18', '射顏'),
        SiteTab('/c/Cam_Porn-58', '摄像頭'),
        SiteTab('/c/Bi_Sexual-62', '雙性戀'),
        SiteTab('/c/Stockings-28', '絲襪'),
        SiteTab('/c/Oiled-22', '塗油'),
        SiteTab('/c/Lingerie-83', '性感内衣'),
        SiteTab('/c/Asian_Woman-32', '亞洲的'),
        SiteTab('/c/Amateur-65', '业余'),
        SiteTab('/c/Interracial-27', '異族'),
        SiteTab('/c/Indian-89', '印度的'),
        SiteTab('/c/Creampie-40', '中出'),
        SiteTab('/c/Solo_and_Masturbation-33', '自慰'),
        SiteTab('/c/AI-239', 'AI（人工智能）'),
        SiteTab('/c/ASMR-229', 'ASMR'),
        SiteTab('/tags/china', 'China'),
        SiteTab('/tags/cosplay', 'Cosplay'),
        SiteTab('/tags/couple', 'Couple'),
        SiteTab('/tags/cute', 'Cute'),
        SiteTab('/tags/doctor', 'Doctor'),
        SiteTab('/tags/furry', 'Furry'),
        SiteTab('/tags/game', 'Game'),
        SiteTab('/tags/hardcore', 'Hardcore'),
        SiteTab('/tags/movie', 'Movie'),
        SiteTab('/tags/orgasm', 'Orgasm'),
        SiteTab('/tags/overwatch', 'Overwatch'),
        SiteTab('/tags/pinay', 'Pinay'),
        SiteTab('/tags/roblox', 'Roblox'),
        SiteTab('/tags/rough', 'Rough'),
        SiteTab('/tags/teacher', 'Teacher'),
        SiteTab('/tags/thai', 'Thai'),
        SiteTab('/gay', '同性視頻'),
        SiteTab('/trans', '变性人色情片'),
      ]),
      SiteTab('/channels-index', '頻道'),
      SiteTab('/pornstars-index', '色情明星'),
    ],
    color: Color(0xFFFF9900),
  ),

  // 快猫（kmsvip.xyz，用户指定）：主分类只要 2 个（热门视频 / 视频广场，照站点
  // #/video_list?type=0|1；用户明确"只需要这两个主分类"）。数据走加密 API：列表
  // 19 条/页（页码 1 起）、详情给 https 播放直链（实测无防盗链）；站点路由里
  // 没有搜索页、也没有标签功能。封面竖版（720x1280，用户要求竖版展示）。
  SiteEntry(
    name: '快猫',
    template: SiteTemplate.kmsvip,
    iconUrl: '/pc/favicon.ico',
    hosts: ['kmsvip.xyz'],
    portraitCovers: true,
    categories: [
      SiteTab('0', '热门视频'),
      SiteTab('1', '视频广场'),
    ],
    color: Color(0xFFFF4D6A),
  ),

  // 麻豆社（madou.club，用户指定）：WordPress + 自研主题 showcase —— 卡片是
  // `article.excerpt`（无 itemscope）、详情正文是玩家 iframe（dash.madou.club 的
  // 分享页），跟上面 5 个 wordpress 站不是一套，所以单列 SiteTemplate.madou。
  // 封面横版；每页 20 张卡（榜单 /likes 100 张）；站点**没有发布时间** → 卡片
  // meta 放观看数（.post-view **原文**"观看(59.26K)"；曾按用户要求只留数字，
  // 随后用户又要求"加回去"，以最终为准）。
  // ⚠️ 卡片上**不显示分类名**（footer 的 rel="category tag"，如"麻豆传媒"）——
  // 用户明确要求去掉（见 api.dart _mdCards 的注释）；详情页的分类/标签照旧。
  // 分类 = 站点导航原顺序：首页 + 3 个主分类（麻豆传媒/番外篇/花絮）+「热门标签」
  // +「其他原创/企划」的 28 个分类 +「筛选」的 3 个榜单。
  SiteEntry(
    name: '麻豆社',
    template: SiteTemplate.madou,
    iconUrl: '/favicon.ico',
    hosts: ['madou.club'],
    portraitCovers: false,
    showRelated: true,
    categories: [
      // 空 key = 站点首页（api.dart 的 category() 里特判走 home 那条路——
      // 不特判就会请求 /category/ → 站点 404）
      SiteTab('', '首页'),
      SiteTab('%e9%ba%bb%e8%b1%86%e4%bc%a0%e5%aa%92', '麻豆传媒'),
      SiteTab('%e9%ba%bb%e8%b1%86%e7%95%aa%e5%a4%96%e7%af%87', '麻豆番外篇'),
      SiteTab('%e9%ba%bb%e8%b1%86%e8%8a%b1%e7%b5%ae', '麻豆花絮'),
      SiteTab('筛选', '其他原创/企划', mdOther),
      // 标签云页 /tags：50 个标签卡，点进去是该标签的列表页（站点没有分页）
      SiteTab('/tags', '热门标签'),
      SiteTab('筛选', '筛选', mdScreens),
    ],
  ),



  // Pornhub（cn.pornhub.com，用户指定）：**中文站是域名自带的**（`<html lang="cn">`，
  // 标题/导航/分类名全中文），按**移动版 DOM** 解析（见 SiteTemplate.pornhub 的注释）。
  //
  // 分类 = **渲染后 DOM 实测的站点顶栏导航**（`li.menu item-1..8`，与用户截图核对过）：
  //   ① 首页 `/`（视频列表）→ 接
  //   ② 视频 `/video` + 9 个子项（探索/推荐/最热门/最多次观看/最高分/热门自制/短片/频道/最新）→ 接
  //   ③ 分类 `/categories` + 19 个热门分类子项（熟女/18-25歲/辣妈/…/潮吹）→ 接
  //   ④ Live Cams `#`、⑥ Virtual Girls `#`（**直播，href 就是 `#` 的异步加载**）→ 不接
  //   ⑤ 色情明星 `/pornstars`（**演员列表，不是视频库**）→ 不接
  //   ⑦ 社区 `/community`、⑧ 照片及动图 `/albums`（**非视频**）→ 不接
  // ⚠️ 踩过的坑（2026-10-02 用户当场指出）：之前把 `li.menu` **下拉里的东西**当成了主分类——
  // 那 12 个（异性恋/男同/精选色情片/LIVE…）其实**全是「分类」下拉里的子项**。
  // 主分类只看**顶栏那 8 个**，别再照着页面里任意一组链接猜。
  SiteEntry(
    name: 'Pornhub',
    template: SiteTemplate.pornhub,
    iconUrl: '/favicon.ico',
    hosts: ['cn.pornhub.com'],
    categories: [
      SiteTab('/', '首页'),
      SiteTab('/video', '视频', [
        SiteTab('/video', '探索视频'),
        SiteTab('/recommended', '推荐视频'),
        SiteTab('/video?o=ht', '最热门'),
        SiteTab('/video?o=mv', '最多次观看'),
        SiteTab('/video?o=tr', '最高分'),
        SiteTab('/video?p=homemade&o=tr', '热门自制'),
        SiteTab('/shorties', '短片'),
        SiteTab('/channels', '频道'),
        SiteTab('/video?o=cm', '最新'),
      ]),
      // ⚠️ 「分类」**是主分类 tab，必须保留**（用户 2026-10-02 指出：首页 / 视频 / 分类 三个都在）——
      // 只是它**不要平铺子项**：站点顶栏那个「分类」是下拉，我们让它进**全部视频**，
      // 再由列表页顶部的「分类」筛选按钮弹窗选那 102 个（见下面的 filters / phCats）。
      SiteTab('/video', '分类'),
      // 色情明星：站点顶栏第 5 项。进去是**演员卡列表**（61 个/页，名字+头像+排名），
      // 点演员 → 演员页（`/pornstar/xxx`、`/model/xxx`）——**那是他的视频列表**，不是视频详情。
      // 筛选（用户 2026-10-02 点名要的）：排序（`?o=`，7 项，见 phStarSorts）
      // + 演员类型（`?performerType=`，见 phStarTypes）+ 时间区段（`?t=`，见 phStarTimes）
      // + 「更多筛选设置」7 组（见 phStarMore，组各自的 URL 参数名已从站点实测确认）。
      SiteTab('/pornstars', '色情明星'),
    ],
    // 「分类」**不做平铺 tab**（站点顶栏那个是下拉、不是列表页）：做成列表页上的
    // 筛选按钮 → 点开**弹窗**选，候选 = /categories 页的 102 个（见 phCats）。
    // 按钮与弹窗标题用 themeLabel 显示成「分类」；**没选时**按钮写「分类选择」
    // （themeEmptyLabel，照模拟器定稿）；durations/sorts 给空列表 → 那两个按钮不画。
    filters: SiteFilters(
      themes: phCats,
      languages: const [],
      durations: const [],
      sorts: const [],
      themeLabel: '分类',
      themeEmptyLabel: '分类选择',
    ),
    color: Color(0xFFFF9000),
  ),
  SiteEntry(
    name: 'xHamster',
    template: SiteTemplate.xhamster,
    // 站点自己的 favicon（sim 的 /icon 会代抓）
    iconUrl: '/favicon.ico',
    hosts: ['tw.xhamster.com'],
    // 相关推荐：移动版页面里**没有 DOM 卡片**（`div.m-related-container` 是"正在載入..."
    // 空壳），但静态 HTML 里有一整段 JSON（Vue props），每条带 pageURL/title/thumbURL/
    // duration → `xhDetail` 直接解析它。（用户 2026-10-02 指出"详情页的推荐视频你没加上"。）
    showRelated: true,
    // 主分类 = 站点顶栏的「影片」tab；全部/高畫質/4K/虛擬實境 是它**下面的子分类**
    // （用户 2026-10-02 纠正过一次：我一开始把四个子分类摆成了主分类）。
    // ⚠️ key 的语义 = **站内路径**（见 lib/api.dart 的 _xhList）：
    //    · 主分类 key 取 `/`（= 不选子分类时的默认，等同「全部」）
    //    · 「全部」= 首页 `/`（用户点击实测确认；站点导航里没有这个链接）
    //    · 其余三个是实测出来的真实路径
    // 翻页是**路径式**：第 N 页 = 该路径 + `/N`（`?page=N` 会被忽略）
    categories: [
      SiteTab('/', '影片', [
        SiteTab('/', '全部'),
        SiteTab('/hd', '高畫質'),
        SiteTab('/4k', '4K'),
        // ⚠️ /vr 与前三个**完全不同**：不是 HLS，是带签名的 mp4 直链 + 会员墙（实测无 m3u8）。
        // 先作为子分类放着，播放这块**待定**（见 DEVLOG 75）。
        SiteTab('/vr', '虛擬實境'),
      ]),
      // 主分类「分类」（用户 2026-10-02 指定）：**主展示** = 18-year-old 这一类的列表；
      // 388 个分类标签从筛选行的「分类」按钮**弹窗选**（照抄 Pornhub 那套选择器，
      // 清单就是下面的 `xhCats` —— 站点 /categories 页 `assignable` JSON 的 13 组）。
      SiteTab('/categories/18-year-old', '分类'),
      // 主分类「色情明星」（用户 2026-10-02 指定）：`/pornstars` 返回的是**演员卡**
      // （DOM 里一张都没有，整页客户端渲染 → 数据在页面 JSON 的 "pornstars":[…] 里，
      //   约 60 条，带 name / pageURL / logoThumbUrl / videoCount）。
      // 点演员卡进**他/她的视频列表**（`/creators/<slug>`），不是详情页。
      SiteTab('/pornstars', '色情明星'),
      // 主分类「短片」（用户 2026-10-02）：**走 JSON 接口** `/api/v1/moments`，不是 HTML
      // （`/shorts` 页本身是纯客户端渲染，静态 HTML 里 0 卡片 ✗）。
      // 实测：无需 cookie、每页 5~6 条、**翻页是 `?page=N`**（不是路径式 ✗，别套 xhListAt 那套）；
      // 每条带 title / pageURL(/shorts/<slug>) / posterUrl / landing.name / sources(H.264)。
      // 展示走**竖版网格**（用户 2026-10-02 定的 A 方案；B 那个抖音式竖屏流先记待办）。
      SiteTab('/shorts', '短片'),
    ],
    // 分类选择器：与 Pornhub 的「分类选择」**同一个机制**（themes = 弹窗里那排 chip，
    // 选中后按该 key 的路径去请求列表，调用的还是 `_xhList` 那套路径分流）。
    // ⚠️ 这里 388 项、是 PH 的近 4 倍，但机制一模一样，**UI 一行都不用改**。
    filters: SiteFilters(
      themes: xhCats,
      languages: const [],
      durations: const [],
      sorts: const [],
      themeLabel: '分类',
      themeEmptyLabel: '分类选择',
    ),
    color: Color(0xFFF5A623),
  ),
];
