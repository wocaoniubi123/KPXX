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
const List<SiteTab> _hgSorts = [
  SiteTab('latest', '最新更新'),
  SiteTab('hot', '当前热播'),
  SiteTab('original', '独家原创'),
  SiteTab('random', '随机推荐'),
];

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
const List<SiteTab> _pkThemes = [
  SiteTab('shirouto', '业余'),
  SiteTab('kyonyu', '丰胸'),
  SiteTab('masturbation', '自我表达'),
  SiteTab('jk', '女高中生'),
  SiteTab('anime', '动漫 / 二次元'),
  SiteTab('female-teacher', '女教师'),
  SiteTab('nurse', '护士'),
  SiteTab('female-pervert', '大胆女性'),
  SiteTab('married-woman', '已婚女性'),
  SiteTab('beautiful-girl', '美少女'),
  SiteTab('big-sister', '姐姐'),
  SiteTab('gal', '时尚女孩'),
  SiteTab('shaved', '光滑风格'),
  SiteTab('small-breasts', '小胸'),
  SiteTab('lolita', '少女系'),
  SiteTab('swimsuit', '泳装'),
  SiteTab('sm', 'SM 题材'),
  SiteTab('special-feature', '企划'),
  SiteTab('incest', '家庭主题'),
  SiteTab('rape', '冲突主题'),
  SiteTab('molestation', '骚扰主题'),
  SiteTab('voyeur', '隐藏拍摄'),
  SiteTab('pickup', '邂逅'),
  SiteTab('massage', '按摩'),
  SiteTab('outdoor', '户外场景'),
  SiteTab('orgy', '群体场景'),
  SiteTab('anal', '背面主题'),
  SiteTab('deep-throat', '深层表达'),
  SiteTab('facial', '面部艺术'),
  SiteTab('cum-swallowing', '吞咽主题'),
  SiteTab('handjob', '手部表演'),
  SiteTab('creampie', '内部主题'),
  SiteTab('titjob', '胸部表演'),
  SiteTab('fellatio', '口部艺术'),
  SiteTab('bukkake', '泼洒艺术'),
  SiteTab('hamedori', '自摄'),
  SiteTab('personal-filming', '私人拍摄'),
  SiteTab('uncensored', '未修饰'),
  SiteTab('gay', '男同性恋・男娘'),
  SiteTab('cosplay', '角色扮演'),
];

/// Pektino 的 10 个语言标签（/api/tags 里 is_language=true 的那批）
const List<SiteTab> _pkLangs = [
  SiteTab('ja', '日本'),
  SiteTab('zh-CN', '中国'),
  SiteTab('th', '泰国'),
  SiteTab('en', '英语'),
  SiteTab('zh-TW', '繁体中文'),
  SiteTab('ko', '韩语'),
  SiteTab('id', '印尼语'),
  SiteTab('pt', '葡萄牙语'),
  SiteTab('fr', '法语'),
  SiteTab('de', '德语'),
];

/// Pektino 时长档：value = 接口的 "min,max"（秒；"0,0" = 全部，不带参数）
const List<MapEntry<String, String>> _pkDurations = [
  MapEntry('0,0', '全部'),
  MapEntry('0,300', '0-5分钟'),
  MapEntry('300,900', '5-15分钟'),
  MapEntry('900,1800', '15-30分钟'),
  MapEntry('1800,3600', '30分钟-1小时'),
  MapEntry('3600,0', '1小时以上'),
];

/// Pektino 排序档（接口的 sort 值；默认按点赞）
const List<MapEntry<String, String>> _pkSorts = [
  MapEntry('favorite', '按点赞'),
  MapEntry('pv', '按观看数'),
  MapEntry('time', '按时长'),
  MapEntry('created', '最近添加'),
];

/// 麻豆社「其他原创/企划」的 28 个分类（照站点导航原顺序、原名）。
/// key = 站点链接里那段**已编码的 slug**，逐字照抄站点导航（别自己重新编码）。
/// ⚠️ 模拟器（sim/server.mjs）用正则解析本文件：子分类只能是①内联字面量数组、
/// ②顶层 `const List<SiteTab> _xxx = [...]`，所以这里是顶层常量（同 _hgSorts）。
const List<SiteTab> _mdOther = [
  SiteTab('hongkongdoll', 'HongKongDoll'),
  SiteTab('psychoporntw', 'PsychopornTW'),
  SiteTab('91%e5%88%b6%e7%89%87%e5%8e%82', '91制片厂'),
  SiteTab('%e6%9e%9c%e5%86%bb%e4%bc%a0%e5%aa%92', '果冻传媒'),
  SiteTab('%e8%9c%9c%e6%a1%83%e5%bd%b1%e5%83%8f', '蜜桃影像'),
  SiteTab('%e5%a4%a9%e7%be%8e%e4%bc%a0%e5%aa%92', '天美传媒'),
  SiteTab('%e7%9a%87%e5%ae%b6%e5%8d%8e%e4%ba%ba', '皇家华人'),
  SiteTab('%e5%85%94%e5%ad%90%e5%85%88%e7%94%9f', '兔子先生'),
  SiteTab('%e6%98%9f%e7%a9%ba%e6%97%a0%e9%99%90%e4%bc%a0%e5%aa%92', '星空无限传媒'),
  SiteTab('%e7%88%b1%e8%b1%86', '爱豆'),
  SiteTab('%e9%ba%bb%e8%b1%86%e5%af%bc%e6%bc%94%e7%b3%bb%e5%88%97', '麻豆导演系列'),
  SiteTab('%e5%a4%a7%e8%b1%a1%e4%bc%a0%e5%aa%92', '大象传媒'),
  SiteTab('%e7%8c%ab%e7%88%aa%e5%bd%b1%e5%83%8f', '猫爪影像'),
  SiteTab('%e7%b2%be%e4%b8%9c%e5%bd%b1%e4%b8%9a', '精东影业'),
  SiteTab('%e6%9d%8f%e5%90%a7', '杏吧'),
  SiteTab('%e4%b9%90%e6%92%ad%e4%bc%a0%e5%aa%92', '乐播传媒'),
  SiteTab('%e8%8d%89%e8%8e%93', '草莓'),
  SiteTab('%e6%8a%96%e9%98%b4', '抖阴'),
  SiteTab('sa%e5%9b%bd%e9%99%85%e4%bc%a0%e5%aa%92', 'SA国际传媒'),
  SiteTab('%e8%b5%b7%e7%82%b9%e4%bc%a0%e5%aa%92-%e6%80%a7%e8%a7%86%e7%95%8c%e4%bc%a0%e5%aa%92',
      '起点传媒/性视界传媒'),
  SiteTab('%e5%a4%a7%e9%b8%9f%e5%8d%81%e5%85%ab', '大鸟十八'),
  SiteTab('%e5%b0%8f%e9%b9%8f%e5%a5%87%e5%95%aa%e8%a1%8c', '小鹏奇啪行'),
  SiteTab('%e5%a5%b3%e4%bc%98%e6%b7%ab%e5%a8%83%e5%9f%b9%e8%ae%ad%e8%90%a5', '女优淫娃培训营'),
  SiteTab('%e6%b7%ab%e6%ac%b2%e6%b8%b8%e6%88%8f%e7%8e%8b', '淫欲游戏王'),
  SiteTab('%e5%a5%b3%e7%a5%9e%e7%be%9e%e7%be%9e%e7%a0%94%e7%a9%b6%e6%89%80', '女神羞羞研究所'),
  SiteTab('%e7%aa%81%e8%a2%ad%e5%a5%b3%e4%bc%98%e5%ae%b6', '突袭女优家'),
  SiteTab('%e6%83%85%e8%b6%a3k%e6%ad%8c%e6%88%bf', '情趣K歌房'),
  SiteTab('kiss%e7%b3%96%e6%9e%9c%e5%b1%8b', 'KISS糖果屋'),
];

/// 麻豆社「筛选」的 3 个榜单（照站点导航：/likes /week /month）。
/// 都以 / 开头 = 站内路径；**没有翻页**（/week /month 站点目前就是空的，
/// 解析出 0 条 = 空列表，不是错）。
const List<SiteTab> _mdScreens = [
  SiteTab('/likes', '点赞排行'),
  SiteTab('/week', '7天热门'),
  SiteTab('/month', '30天热门'),
];

/// Pornhub 的**全部分类**（102 个）——用户 2026-10-02 要求「分类」做成**弹窗选择**，
/// 内容照站点 `/categories` 页（「热门色情片类型」+「所有色情片类型」）**原序原名**。
/// ⚠️ 顶栏「分类」下拉里只有它推荐的十几个热门项，**不是**这个清单；
/// ⚠️ 也不要再往里塞「性取向 / 视频内语言」的筛选项（异性恋 / 男同 / 跨性别 / 女女萨福系 / chinese）
/// —— 用户点名去掉过。key 直接是站内路径，列表按它请求（`/video?c=NN`、少数是 `/categories/xxx`
/// 或 `/vr` `/hd` `/sfw` `/interactive` 这类特殊入口）。
const List<SiteTab> _phCats = [
  SiteTab('/video?c=17', '黑人女'),
  SiteTab('/video?c=6', '大号美女'),
  SiteTab('/video?c=492', '女性自慰'),
  SiteTab('/video?c=7', '巨屌'),
  SiteTab('/video?c=22', '手淫'),
  SiteTab('/transgender', '跨性别'),
  SiteTab('/categories/pornstar', '色情明星'),
  SiteTab('/video?c=115', '独家'),
  SiteTab('/video?c=25', '跨种族'),
  SiteTab('/video?c=59', '贫乳'),
  SiteTab('/categories/teen', '18-25歲'),
  SiteTab('/video?c=65', '3P'),
  SiteTab('/video?c=105', '60帧'),
  SiteTab('/video?c=241', 'Cosplay'),
  SiteTab('/sfw', '上班时观赏'),
  SiteTab('/video?c=2', '乱交群欢'),
  SiteTab('/video?c=1', '亚洲人'),
  SiteTab('/interactive', '交互式'),
  SiteTab('/video?c=542', '佩戴式阳具'),
  SiteTab('/video?c=99', '俄国人'),
  SiteTab('/video?c=24', '公众野战'),
  SiteTab('/video?c=15', '内射中出'),
  SiteTab('/video?c=732', '内嵌字幕'),
  SiteTab('/video?c=21', '劲爆重口味'),
  SiteTab('/video?c=86', '卡通'),
  SiteTab('/video?c=101', '印度人'),
  SiteTab('/video?c=76', '双性恋男'),
  SiteTab('/video?c=72', '双龙入洞'),
  SiteTab('/video?c=13', '口交'),
  SiteTab('/video?c=43', '古典派'),
  SiteTab('/video?c=57', '合集'),
  SiteTab('/video?c=12', '名人'),
  SiteTab('/categories/college', '大学'),
  SiteTab('/video?c=27', '女同'),
  SiteTab('/popularwithwomen', '女性之选'),
  SiteTab('/video?c=502', '女性高潮'),
  SiteTab('/video?c=242', '娇妻偷吃'),
  SiteTab('/video?c=16', '射精'),
  SiteTab('/video?c=8', '巨乳'),
  SiteTab('/video?c=482', '已认证情侣'),
  SiteTab('/video?c=139', '已认证模特'),
  SiteTab('/video?c=138', '已认证素人'),
  SiteTab('/video?c=102', '巴西人'),
  SiteTab('/video?c=95', '德国人'),
  SiteTab('/video?c=23', '性玩具'),
  SiteTab('/video?c=18', '恋物癖'),
  SiteTab('/video?c=93', '恋足'),
  SiteTab('/video?c=97', '意大利人'),
  SiteTab('/video?c=20', '手交'),
  SiteTab('/video?c=91', '抽烟'),
  SiteTab('/video?c=26', '拉丁裔美女'),
  SiteTab('/video?c=19', '拳交'),
  SiteTab('/video?c=592', '指交'),
  SiteTab('/video?c=78', '按摩'),
  SiteTab('/video?c=10', '捆绑'),
  SiteTab('/video?c=100', '捷克人'),
  SiteTab('/video?c=32', '搞笑'),
  SiteTab('/video?c=211', '撒尿'),
  SiteTab('/video?c=891', '播客'),
  SiteTab('/video?c=111', '日本人'),
  SiteTab('/video?c=88', '校园'),
  SiteTab('/video?c=55', '欧洲人'),
  SiteTab('/video?c=94', '法国人'),
  SiteTab('/video?c=522', '浪漫'),
  SiteTab('/video?c=11', '深发女'),
  SiteTab('/video?c=201', '滑稽模仿'),
  SiteTab('/video?c=69', '潮吹'),
  SiteTab('/video?c=89', '火辣保姆'),
  SiteTab('/video?c=28', '熟女'),
  SiteTab('/video?c=35', '爆菊'),
  SiteTab('/video?c=141', '片场直击'),
  SiteTab('/video?c=92', '男性自慰'),
  SiteTab('/video?c=31', '真人实拍'),
  SiteTab('/video?c=41', '第一视角'),
  SiteTab('/video?c=67', '粗暴性爱'),
  SiteTab('/video?c=3', '素人'),
  SiteTab('/video?c=42', '红毛'),
  SiteTab('/video?c=562', '纹身女'),
  SiteTab('/video?c=444', '继家庭幻想'),
  SiteTab('/video?c=181', '老少欢'),
  SiteTab('/video?c=53', '聚会'),
  SiteTab('/video?c=512', '肌肉男'),
  SiteTab('/video?c=4', '肥臀'),
  SiteTab('/video?c=33', '脱衣舞'),
  SiteTab('/described-video', '自述视频'),
  SiteTab('/video?c=131', '舔屄'),
  SiteTab('/categories/hentai', '色情日漫'),
  SiteTab('/video?c=96', '英国人'),
  SiteTab('/vr', '虚拟现实'),
  SiteTab('/video?c=61', '视频激情'),
  SiteTab('/video?c=81', '角色扮演'),
  SiteTab('/video?c=90', '试镜'),
  SiteTab('/video?c=881', '赌博'),
  SiteTab('/video?c=80', '轮交'),
  SiteTab('/video?c=29', '辣妈'),
  SiteTab('/video?c=9', '金发女'),
  SiteTab('/video?c=98', '阿拉伯人'),
  SiteTab('/video?c=14', '集体颜射'),
  SiteTab('/video?c=103', '韩国人'),
  SiteTab('/video?c=121', '音乐'),
  SiteTab('/categories/babe', '风情少女'),
  SiteTab('/hd', '高清色情片'),
];

/// xHamster「分类」清单：站点 `/categories` 页里 `assignable` JSON 的 **13 组 × 388 个标签**。
/// ⚠️ 这 388 个标签**不在 DOM 里**（页面只渲染了「製作」那一组，其余要点了锚点才 JS 加载），
/// 完整数据藏在页面的 Vue props JSON（`assignable`）里 → 这一份是**离线抄下来硬编码**的
/// （跟 `_phCats` 同一套路数：站点加了新标签得手动更新）。
/// 分组顺序照站点：製作 → 行動 → 戀物癖 → 指示 → 年齡 → 種族 → 身體 → 頭髮 → 人數 → 性玩具 → 服飾 → 設想 → 位置
/// xHamster「色情明星」tab **自己那套**筛选清单（用户 2026-10-02 明确要求：
/// "色情明星的分类选择要显示正确的明星"）。
/// ⚠️ **跟 `_xhCats` 那 388 个视频分类是两回事** —— 用户为这个混用发过火 ✗：
/// 388 个是「分类」tab 的**视频分类**；这里是**演员分类**（站点演员页自己的 40 个 chip，
/// 逐条实测 slug 可用 ✓）。两个清单的路径前缀都不一样：
///   视频分类  `/categories/<slug>`
///   演员分类  `/pornstars/all/categories/<slug>`
/// 榜單三项（色情明星 / 在US受歡迎 / 按國家）与站点顶部导航一致 ✓。
const List<SiteTab> xhStarNav = [
  SiteTab('/pornstars', '色情明星'),
  SiteTab('/pornstars/top/us', '在US受歡迎'),
  SiteTab('/pornstars/all/countries', '按國家'),
];

/// 演员分类 40 个（站点演员页 chip 的原顺序，逐条实测 slug 可用 ✓）。
/// 名字取自 `_xhCats` 同一张表；german/japanese/french/british 四个表里没有，
/// 照站点 chip 写死（sim 的 `XH_STAR_CATS` 同源）。
const List<SiteTab> xhStarCats = [
  SiteTab('/pornstars/all/categories/creampie', '中出'),
  SiteTab('/pornstars/all/categories/asian', '亞洲'),
  SiteTab('/pornstars/all/categories/dildo', '假雞巴'),
  SiteTab('/pornstars/all/categories/cartoon', '卡通'),
  SiteTab('/pornstars/all/categories/blowjob', '口交'),
  SiteTab('/pornstars/all/categories/celebrity', '名人'),
  SiteTab('/pornstars/all/categories/bbw', '大美人'),
  SiteTab('/pornstars/all/categories/femdom', '女主導'),
  SiteTab('/pornstars/all/categories/lesbian', '女同性戀'),
  SiteTab('/pornstars/all/categories/milf', '媽媽我想做愛'),
  SiteTab('/pornstars/all/categories/cumshot', '射精畫面'),
  SiteTab('/pornstars/all/categories/vintage', '復古'),
  SiteTab('/pornstars/all/categories/german', '德國'),
  SiteTab('/pornstars/all/categories/mature', '成熟'),
  SiteTab('/pornstars/all/categories/cuckold', '戴綠帽'),
  SiteTab('/pornstars/all/categories/handjob', '手淫'),
  SiteTab('/pornstars/all/categories/massage', '按摩'),
  SiteTab('/pornstars/all/categories/swingers', '換妻者'),
  SiteTab('/pornstars/all/categories/japanese', '日本'),
  SiteTab('/pornstars/all/categories/amateur', '業餘'),
  SiteTab('/pornstars/all/categories/hairy', '毛茸茸'),
  SiteTab('/pornstars/all/categories/beach', '沙灘'),
  SiteTab('/pornstars/all/categories/french', '法式'),
  SiteTab('/pornstars/all/categories/squirting', '潮吹'),
  SiteTab('/pornstars/all/categories/hardcore', '硬核'),
  SiteTab('/pornstars/all/categories/cfnm', '穿衣女與裸體男'),
  SiteTab('/pornstars/all/categories/bdsm', '綁縛與調教'),
  SiteTab('/pornstars/all/categories/webcam', '網絡攝像頭'),
  SiteTab('/pornstars/all/categories/granny', '老奶奶'),
  SiteTab('/pornstars/all/categories/old-young', '老少配'),
  SiteTab('/pornstars/all/categories/anal', '肛交'),
  SiteTab('/pornstars/all/categories/footjob', '腳交'),
  SiteTab('/pornstars/all/categories/british', '英國佬'),
  SiteTab('/pornstars/all/categories/hentai', '變態'),
  SiteTab('/pornstars/all/categories/interracial', '跨種族'),
  SiteTab('/pornstars/all/categories/gangbang', '輪姦'),
  SiteTab('/pornstars/all/categories/casting', '選角'),
  SiteTab('/pornstars/all/categories/arab', '阿拉伯風情'),
  SiteTab('/pornstars/all/categories/bisexual', '雙性戀'),
  SiteTab('/pornstars/all/categories/teen', '青少年'),
];

const List<SiteTab> _xhCats = [
  // ── 製作（24 个）
  SiteTab('/categories/3d', '3D'),
  SiteTab('/categories/pmv', 'PMV'),
  SiteTab('/categories/show', 'Show'),
  SiteTab('/categories/pov', '主觀視角'),
  SiteTab('/categories/interactive', '互動式'),
  SiteTab('/categories/cartoon', '卡通'),
  SiteTab('/categories/behind-the-scenes', '幕後花絮'),
  SiteTab('/categories/vintage', '復古'),
  SiteTab('/categories/retro', '復古'),
  SiteTab('/categories/erotica', '情色文學'),
  SiteTab('/categories/funny', '搞笑'),
  SiteTab('/categories/story', '故事'),
  SiteTab('/categories/jav', '日本AV'),
  SiteTab('/categories/uncensored', '未經審查'),
  SiteTab('/categories/amateur', '業餘'),
  SiteTab('/categories/caption', '標題'),
  SiteTab('/categories/close-up', '特寫'),
  SiteTab('/categories/gonzo', '第一人稱視角'),
  SiteTab('/categories/compilation', '精選集'),
  SiteTab('/categories/webcam', '網絡攝像頭'),
  SiteTab('/categories/homemade', '自製'),
  SiteTab('/categories/pornstar', '色情明星'),
  SiteTab('/categories/hentai', '變態'),
  SiteTab('/categories/softcore', '軟性色情'),
  // ── 行動（58 个）
  SiteTab('/categories/creampie', '中出'),
  SiteTab('/categories/scissoring', '交叉剪刀'),
  SiteTab('/categories/cumswap', '交換精液'),
  SiteTab('/categories/missionary', '傳教士體位'),
  SiteTab('/categories/69', '六九'),
  SiteTab('/categories/shaving', '刮毛'),
  SiteTab('/categories/prostate-massage', '前列腺按摩'),
  SiteTab('/categories/foreplay', '前戲'),
  SiteTab('/categories/cum-in-mouth', '口中射精'),
  SiteTab('/categories/blowjob', '口交'),
  SiteTab('/categories/face-fuck', '口交插入'),
  SiteTab('/categories/eating-pussy', '吃陰戶'),
  SiteTab('/categories/cum-swallowing', '吞精'),
  SiteTab('/categories/moaning', '呻吟'),
  SiteTab('/categories/blowbang', '多人吹'),
  SiteTab('/categories/bukkake', '多人顏射'),
  SiteTab('/categories/gaping', '大開口'),
  SiteTab('/categories/cowgirl', '女上位'),
  SiteTab('/categories/female-masturbation', '女性自慰'),
  SiteTab('/categories/titty-fucking', '奶交'),
  SiteTab('/categories/cum-on-tits', '射在胸上'),
  SiteTab('/categories/cumshot', '射精畫面'),
  SiteTab('/categories/screaming', '尖叫'),
  SiteTab('/categories/humping', '幹砲'),
  SiteTab('/categories/happy-ending', '快樂結局'),
  SiteTab('/categories/fingering', '手指愛撫'),
  SiteTab('/categories/handjob', '手淫'),
  SiteTab('/categories/twerking', '扭臀舞'),
  SiteTab('/categories/fisting', '拳交'),
  SiteTab('/categories/massage', '按摩'),
  SiteTab('/categories/pegging', '掛鉤'),
  SiteTab('/categories/extreme-insertion', '極端插入'),
  SiteTab('/categories/brutal-sex', '殘酷性愛'),
  SiteTab('/categories/deep-throat', '深喉'),
  SiteTab('/categories/squirting', '潮吹'),
  SiteTab('/categories/rough-sex', '激烈性愛'),
  SiteTab('/categories/rough-anal', '激烈肛交'),
  SiteTab('/categories/doggy-style', '狗爬式'),
  SiteTab('/categories/yoga', '瑜伽'),
  SiteTab('/categories/anal', '肛交'),
  SiteTab('/categories/ass-to-mouth', '肛口交'),
  SiteTab('/categories/anal-masturbation', '肛門自慰'),
  SiteTab('/categories/striptease', '脫衣舞'),
  SiteTab('/categories/cum-on-feet', '腳上射精'),
  SiteTab('/categories/footjob', '腳交'),
  SiteTab('/categories/facesitting', '臉坐'),
  SiteTab('/categories/ass-licking', '舔屁股'),
  SiteTab('/categories/rimjob', '舔肛'),
  SiteTab('/categories/cunnilingus', '舔陰'),
  SiteTab('/categories/kissing', '親吻'),
  SiteTab('/categories/edging', '邊緣控制'),
  SiteTab('/categories/dry-humping', '隔衣磨蹭'),
  SiteTab('/categories/double-penetration', '雙重插入'),
  SiteTab('/categories/flashing', '露鳥'),
  SiteTab('/categories/facial', '顏射'),
  SiteTab('/categories/riding', '騎乘'),
  SiteTab('/categories/dirty-talk', '髒話調情'),
  SiteTab('/categories/orgasm', '高潮'),
  // ── 戀物癖（65 个）
  SiteTab('/categories/human-furniture', '人體家具'),
  SiteTab('/categories/human-ashtray', '人體菸灰缸'),
  SiteTab('/categories/condom', '保險套'),
  SiteTab('/categories/mouth-fetish', '口腔癖好'),
  SiteTab('/categories/cei', '吃精指南'),
  SiteTab('/categories/spitting', '吐口水'),
  SiteTab('/categories/predicament-bondage', '困境束縛'),
  SiteTab('/categories/weird', '奇怪'),
  SiteTab('/categories/femdom', '女主導'),
  SiteTab('/categories/lezdom', '女同支配'),
  SiteTab('/categories/sissy', '娘炮'),
  SiteTab('/categories/gyno-fetish', '婦科癖好'),
  SiteTab('/categories/pet-play', '寵物扮演'),
  SiteTab('/categories/small-penis-humiliation', '小陰莖羞辱'),
  SiteTab('/categories/small-penis-encouragement', '小陰莖鼓勵'),
  SiteTab('/categories/kinky', '性變態'),
  SiteTab('/categories/punishment', '懲罰'),
  SiteTab('/categories/suspension-bondage', '懸吊束縛'),
  SiteTab('/categories/fetish', '戀物癖'),
  SiteTab('/categories/dogging', '戶外群交'),
  SiteTab('/categories/hand-fetish', '手癖'),
  SiteTab('/categories/spanking', '打屁股'),
  SiteTab('/categories/futanari', '扶她'),
  SiteTab('/categories/oiled', '抹油'),
  SiteTab('/categories/smoking', '抽菸性愛'),
  SiteTab('/categories/wedgie', '拉內褲'),
  SiteTab('/categories/tickling', '搔癢'),
  SiteTab('/categories/wrestling', '摔跤'),
  SiteTab('/categories/pissing', '撒尿'),
  SiteTab('/categories/domination', '支配'),
  SiteTab('/categories/farting', '放屁'),
  SiteTab('/categories/balloon', '氣球'),
  SiteTab('/categories/lactating', '泌乳'),
  SiteTab('/categories/wet-messy', '濕滑混亂'),
  SiteTab('/categories/milk', '牛奶'),
  SiteTab('/categories/raceplay', '種族扮演'),
  SiteTab('/categories/smothering', '窒息玩法'),
  SiteTab('/categories/mind-control', '精神控制'),
  SiteTab('/categories/hogtied', '綁成豬蹄'),
  SiteTab('/categories/bdsm', '綁縛與調教'),
  SiteTab('/categories/bondage', '綑綁'),
  SiteTab('/categories/shibari', '繩縛'),
  SiteTab('/categories/humiliation', '羞辱'),
  SiteTab('/categories/armpit', '腋下'),
  SiteTab('/categories/foot-worship', '腳部崇拜'),
  SiteTab('/categories/belly-fetish', '腹部癖好'),
  SiteTab('/categories/tape-bondage', '膠帶束縛'),
  SiteTab('/categories/face-fetish', '臉部癖好'),
  SiteTab('/categories/wax-play', '蠟燭調教'),
  SiteTab('/categories/tied-up', '被綁起來'),
  SiteTab('/categories/chastity', '貞操'),
  SiteTab('/categories/foot-fetish', '足控'),
  SiteTab('/categories/pedal-pumping', '踏板泵送'),
  SiteTab('/categories/ballbusting', '踢蛋'),
  SiteTab('/categories/trampling', '踩踏'),
  SiteTab('/categories/body-paint', '身體彩繪'),
  SiteTab('/categories/ahegao', '阿嘿顏'),
  SiteTab('/categories/cbt', '雞巴與蛋蛋折磨'),
  SiteTab('/categories/estim', '電刺激'),
  SiteTab('/categories/whipping', '鞭打'),
  SiteTab('/categories/submissive', '順從者'),
  SiteTab('/categories/food', '食物'),
  SiteTab('/categories/gokkun', '飲精'),
  SiteTab('/categories/body-hair-fetish', '體毛癖'),
  SiteTab('/categories/orgasm-control', '高潮控制'),
  // ── 指示（2 个）
  SiteTab('/categories/lesbian', '女同性戀'),
  SiteTab('/categories/bisexual', '雙性戀'),
  // ── 年齡（10 个）
  SiteTab('/categories/18-year-old', '18歲'),
  SiteTab('/categories/milf', '媽媽我想做愛'),
  SiteTab('/categories/babe', '寶貝'),
  SiteTab('/categories/mature', '成熟'),
  SiteTab('/categories/cougar', '熟女'),
  SiteTab('/categories/gilf', '熟女祖母'),
  SiteTab('/categories/granny', '老奶奶'),
  SiteTab('/categories/old-young', '老少配'),
  SiteTab('/categories/old-man', '老頭子'),
  SiteTab('/categories/teen', '青少年'),
  // ── 種族（12 个）
  SiteTab('/categories/amwf', 'AMWF'),
  SiteTab('/categories/asian', '亞洲'),
  SiteTab('/categories/desi', '南亞裔'),
  SiteTab('/categories/mzansi', '南非'),
  SiteTab('/categories/latina', '拉丁裔'),
  SiteTab('/categories/european', '歐洲'),
  SiteTab('/categories/jewish', '猶太'),
  SiteTab('/categories/american', '美國佬'),
  SiteTab('/categories/interracial', '跨種族'),
  SiteTab('/categories/arab', '阿拉伯風情'),
  SiteTab('/categories/african', '非洲'),
  SiteTab('/categories/black', '黑人'),
  // ── 身體（45 个）
  SiteTab('/categories/bwc', 'BWC'),
  SiteTab('/categories/saggy-tits', '下垂奶'),
  SiteTab('/categories/nipples', '乳頭'),
  SiteTab('/categories/midget', '侏儒'),
  SiteTab('/categories/fake-tits', '假奶'),
  SiteTab('/categories/tattoo', '刺青'),
  SiteTab('/categories/cute', '可愛'),
  SiteTab('/categories/big-natural-tits', '大天然奶'),
  SiteTab('/categories/big-tits', '大奶'),
  SiteTab('/categories/big-nipples', '大奶頭'),
  SiteTab('/categories/big-ass', '大屁股'),
  SiteTab('/categories/pawg', '大屁股白妞'),
  SiteTab('/categories/big-cock', '大屌'),
  SiteTab('/categories/bbw', '大美人'),
  SiteTab('/categories/big-clit', '大陰蒂'),
  SiteTab('/categories/bbc', '大黑屌'),
  SiteTab('/categories/giantess', '女巨人'),
  SiteTab('/categories/fbb', '女性健美者'),
  SiteTab('/categories/tits', '奶子'),
  SiteTab('/categories/petite', '嬌小'),
  SiteTab('/categories/perfect-body', '完美身材'),
  SiteTab('/categories/pussy', '小穴'),
  SiteTab('/categories/small-tits', '小胸'),
  SiteTab('/categories/ass', '屁股'),
  SiteTab('/categories/giant', '巨型'),
  SiteTab('/categories/monster-cock', '巨屌'),
  SiteTab('/categories/pregnant', '懷孕'),
  SiteTab('/categories/amputee', '截肢者'),
  SiteTab('/categories/tan-girl', '曬黑妹'),
  SiteTab('/categories/hairy', '毛茸茸'),
  SiteTab('/categories/exotic', '異國風情'),
  SiteTab('/categories/skinny', '瘦弱'),
  SiteTab('/categories/piercing', '穿孔'),
  SiteTab('/categories/tight-pussy', '緊緻小穴'),
  SiteTab('/categories/beauty', '美女'),
  SiteTab('/categories/legs', '美腿'),
  SiteTab('/categories/muscular-woman', '肌肉女'),
  SiteTab('/categories/puffy-nipples', '膨脹乳頭'),
  SiteTab('/categories/nude', '裸體'),
  SiteTab('/categories/chubby', '豐滿'),
  SiteTab('/categories/ssbbw', '超大碼性感胖女人'),
  SiteTab('/categories/clit', '陰蒂'),
  SiteTab('/categories/hermaphrodite', '雌雄同體'),
  SiteTab('/categories/flexible', '靈活'),
  SiteTab('/categories/cameltoe', '駱駝蹄'),
  // ── 頭髮（6 个）
  SiteTab('/categories/colored-hair', '彩色頭髮'),
  SiteTab('/categories/brunette', '棕髮女郎'),
  SiteTab('/categories/short-hair', '短髮'),
  SiteTab('/categories/redhead', '紅髮妹'),
  SiteTab('/categories/blonde', '金髮'),
  SiteTab('/categories/long-hair', '長髮'),
  // ── 人數（7 个）
  SiteTab('/categories/threesome', '三人行'),
  SiteTab('/categories/foursome', '四人行'),
  SiteTab('/categories/couple', '情侶'),
  SiteTab('/categories/orgy', '狂歡'),
  SiteTab('/categories/solo', '獨自'),
  SiteTab('/categories/group-sex', '群交'),
  SiteTab('/categories/gangbang', '輪姦'),
  // ── 性玩具（14 个）
  SiteTab('/categories/strapon', '假陽具'),
  SiteTab('/categories/dildo', '假雞巴'),
  SiteTab('/categories/ball-gagged', '口球束縛'),
  SiteTab('/categories/fucking-machine', '性愛機器'),
  SiteTab('/categories/sex-toy', '性玩具'),
  SiteTab('/categories/enema', '灌腸'),
  SiteTab('/categories/butt-plug', '肛塞'),
  SiteTab('/categories/anal-beads', '肛門珠'),
  SiteTab('/categories/blindfolded', '蒙眼'),
  SiteTab('/categories/sybian', '西比亞'),
  SiteTab('/categories/pussy-pump', '陰部吸泵'),
  SiteTab('/categories/double-dildo', '雙頭假陽具'),
  SiteTab('/categories/vibrator', '震動棒'),
  SiteTab('/categories/hitachi', '震動玩具'),
  // ── 服飾（23 个）
  SiteTab('/categories/thong', '丁字褲'),
  SiteTab('/categories/latex', '乳膠'),
  SiteTab('/categories/panties', '內褲'),
  SiteTab('/categories/bodystocking', '全身網襪'),
  SiteTab('/categories/uniform', '制服'),
  SiteTab('/categories/nylon', '尼龍'),
  SiteTab('/categories/lingerie', '性感內衣'),
  SiteTab('/categories/gloves', '手套'),
  SiteTab('/categories/school-uniform', '校服'),
  SiteTab('/categories/bikini', '比基尼'),
  SiteTab('/categories/jeans', '牛仔褲'),
  SiteTab('/categories/leather', '皮革'),
  SiteTab('/categories/glasses', '眼鏡'),
  SiteTab('/categories/stockings', '絲襪'),
  SiteTab('/categories/fishnet', '網襪'),
  SiteTab('/categories/leggings', '緊身褲'),
  SiteTab('/categories/bra', '胸罩'),
  SiteTab('/categories/spandex', '萊卡緊身衣'),
  SiteTab('/categories/masked', '蒙面'),
  SiteTab('/categories/skirt', '裙子'),
  SiteTab('/categories/socks', '襪子'),
  SiteTab('/categories/pantyhose', '連褲襪'),
  SiteTab('/categories/high-heels', '高跟鞋'),
  // ── 設想（99 个）
  SiteTab('/categories/asmr', 'ASMR'),
  SiteTab('/categories/medieval', '中世紀'),
  SiteTab('/categories/agent', '代理人'),
  SiteTab('/categories/escort', '伴遊'),
  SiteTab('/categories/babysitter', '保姆'),
  SiteTab('/categories/nun', '修女'),
  SiteTab('/categories/cheating', '偷情'),
  SiteTab('/categories/upskirt', '偷拍裙底'),
  SiteTab('/categories/voyeur', '偷窺者'),
  SiteTab('/categories/princess', '公主'),
  SiteTab('/categories/public-sex', '公開性愛'),
  SiteTab('/categories/public-nudity', '公開裸露'),
  SiteTab('/categories/stuck', '卡住'),
  SiteTab('/categories/reverse-gangbang', '反向群交'),
  SiteTab('/categories/celebrity', '名人'),
  SiteTab('/categories/vampire', '吸血鬼'),
  SiteTab('/categories/gothic', '哥特'),
  SiteTab('/categories/cheerleader', '啦啦隊女孩'),
  SiteTab('/categories/alien', '外星人'),
  SiteTab('/categories/coed', '大學男女混宿'),
  SiteTab('/categories/mistress', '女主人'),
  SiteTab('/categories/maid', '女僕'),
  SiteTab('/categories/catfight', '女子打架'),
  SiteTab('/categories/girlfriend', '女朋友'),
  SiteTab('/categories/slave', '奴隸'),
  SiteTab('/categories/wife-sharing', '妻子共享'),
  SiteTab('/categories/doll', '娃娃'),
  SiteTab('/categories/wedding', '婚禮'),
  SiteTab('/categories/mom', '媽咪'),
  SiteTab('/categories/student', '學生'),
  SiteTab('/categories/housewife', '家庭主婦'),
  SiteTab('/categories/clown', '小丑'),
  SiteTab('/categories/bunny', '小兔子'),
  SiteTab('/categories/fantasy', '幻想'),
  SiteTab('/categories/cook', '廚師'),
  SiteTab('/categories/sex-instruction', '性愛指導'),
  SiteTab('/categories/nympho', '性癮者'),
  SiteTab('/categories/monster', '怪物'),
  SiteTab('/categories/horror', '恐怖'),
  SiteTab('/categories/valentines-day', '情人節'),
  SiteTab('/categories/emo', '情緒搖滾風'),
  SiteTab('/categories/parody', '惡搞'),
  SiteTab('/categories/cuckold', '戴綠帽'),
  SiteTab('/categories/fighting', '打架'),
  SiteTab('/categories/wife-swap', '換妻'),
  SiteTab('/categories/swingers', '換妻者'),
  SiteTab('/categories/pick-up', '搭訕'),
  SiteTab('/categories/morning', '早晨'),
  SiteTab('/categories/time-stop', '時間靜止'),
  SiteTab('/categories/nerd', '書呆子'),
  SiteTab('/categories/waitress', '服務生'),
  SiteTab('/categories/glory-hole', '榮耀洞'),
  SiteTab('/categories/plumber', '水管工'),
  SiteTab('/categories/party', '派對'),
  SiteTab('/categories/romantic', '浪漫'),
  SiteTab('/categories/naughty', '淘氣'),
  SiteTab('/categories/comic', '漫畫'),
  SiteTab('/categories/passionate', '熱情'),
  SiteTab('/categories/daddy', '爹地'),
  SiteTab('/categories/birthday', '生日'),
  SiteTab('/categories/truth-or-dare', '真心話大冒險'),
  SiteTab('/categories/hardcore', '硬核'),
  SiteTab('/categories/taboo', '禁忌'),
  SiteTab('/categories/secretary', '秘書'),
  SiteTab('/categories/cfnm', '穿衣女與裸體男'),
  SiteTab('/categories/cmnf', '穿衣男與裸體女'),
  SiteTab('/categories/first-time', '第一次'),
  SiteTab('/categories/e-girl', '網紅妹'),
  SiteTab('/categories/boss', '老大'),
  SiteTab('/categories/wife', '老婆'),
  SiteTab('/categories/teacher', '老師'),
  SiteTab('/categories/xmas', '聖誕節'),
  SiteTab('/categories/joi', '自慰指導'),
  SiteTab('/categories/halloween', '萬聖節'),
  SiteTab('/categories/virgin', '處女'),
  SiteTab('/categories/nudist', '裸體主義者'),
  SiteTab('/categories/cosplay', '角色扮演'),
  SiteTab('/categories/role-play', '角色扮演'),
  SiteTab('/categories/audition', '試鏡'),
  SiteTab('/categories/seduce', '誘惑'),
  SiteTab('/categories/police', '警察'),
  SiteTab('/categories/nurse', '護士'),
  SiteTab('/categories/ghetto', '貧民窟'),
  SiteTab('/categories/superhero', '超人'),
  SiteTab('/categories/dance', '跳舞'),
  SiteTab('/categories/body-swap', '身體交換'),
  SiteTab('/categories/military', '軍事角色扮演'),
  SiteTab('/categories/baddie', '辣妹'),
  SiteTab('/categories/game', '遊戲'),
  SiteTab('/categories/gamer-girl', '遊戲妹'),
  SiteTab('/categories/sport', '運動'),
  SiteTab('/categories/casting', '選角'),
  SiteTab('/categories/neighbor', '鄰居'),
  SiteTab('/categories/doctor', '醫生'),
  SiteTab('/categories/medical', '醫療'),
  SiteTab('/categories/stranger', '陌生人'),
  SiteTab('/categories/twins', '雙胞胎'),
  SiteTab('/categories/interview', '面試'),
  SiteTab('/categories/surprise', '驚喜'),
  // ── 位置（23 个）
  SiteTab('/categories/sauna', '三溫暖'),
  SiteTab('/categories/fitness', '健身'),
  SiteTab('/categories/gym', '健身房'),
  SiteTab('/categories/jungle', '叢林'),
  SiteTab('/categories/college', '大學'),
  SiteTab('/categories/bus', '巴士'),
  SiteTab('/categories/toilet', '廁所'),
  SiteTab('/categories/kitchen', '廚房'),
  SiteTab('/categories/outdoor', '戶外'),
  SiteTab('/categories/hotel', '旅館'),
  SiteTab('/categories/underwater', '水下'),
  SiteTab('/categories/car', '汽車'),
  SiteTab('/categories/beach', '沙灘'),
  SiteTab('/categories/pool', '泳池'),
  SiteTab('/categories/bathroom', '浴室'),
  SiteTab('/categories/shower', '淋浴'),
  SiteTab('/categories/train', '火車'),
  SiteTab('/categories/prison', '監獄'),
  SiteTab('/categories/taxi', '計程車'),
  SiteTab('/categories/office', '辦公室'),
  SiteTab('/categories/farm', '農場'),
  SiteTab('/categories/village', '鄉村'),
  SiteTab('/categories/hospital', '醫院'),
];

/// Pornhub「色情明星」页（/pornstars）的筛选 —— 用户 2026-10-02 要求照站点右上角
/// 那四个控件做：最受欢迎 ▾ / 色情明星和模特 ▾ / 每月 ▾ / + 更多筛选设置。
/// 参数形态全部是 URL 查询串（桌面版页面里 `<a href="/pornstars?…">` 实测出来的，
/// **不是猜的**）：`?o=` 排序、`?performerType=` 类型、`?t=` 时间区段。
/// key 空串 = 该控件的默认值（站点默认：最受欢迎 / 色情明星和模特 / 每月）。
const List<SiteTab> phStarSorts = [
  SiteTab('', '最受欢迎'),
  SiteTab('mv', '最多次观看'),
  SiteTab('t', '最热门'),
  SiteTab('ms', '最多订阅'),
  SiteTab('a', '按字母排序'),
  SiteTab('nv', '视频数量'),
  SiteTab('r', '随机'),
];
const List<SiteTab> phStarTypes = [
  SiteTab('', '色情明星和模特'),
  SiteTab('pornstar', '色情明星'),
  SiteTab('amateur', '素人模特'),
];
const List<SiteTab> phStarTimes = [
  SiteTab('w', '每周'),
  SiteTab('', '每月'),
  SiteTab('a', '每年'),
];

/// 「+ 更多筛选设置」里那 7 组（照站点筛选面板；组内第一个空 key 都代表"全部"）。
/// ⚠️ 每组的 `key` 是**URL 参数名**（gender/ethnicity/tattoos/hair/piercings/cup/breasttype，
/// 从站点筛选面板的链接实测），`name` 才是中文显示名。
const List<SiteTab> phStarMore = [
  SiteTab('gender', '性别', [
    SiteTab('', '全部'),
    SiteTab('male', '男性'),
    SiteTab('female', '女性'),
    SiteTab('m2f', '变性女'),
    SiteTab('f2m', '变性男'),
  ]),
  SiteTab('ethnicity', '种族', [
    SiteTab('', '全部'),
    SiteTab('asian', 'Asian'),
    SiteTab('black', 'Black'),
    SiteTab('indian', 'Indian'),
    SiteTab('latin', 'Latin'),
    SiteTab('middle+eastern', 'Middle Eastern'),
    SiteTab('mixed', 'Mixed'),
    SiteTab('white', 'White'),
    SiteTab('other', 'Other'),
  ]),
  SiteTab('tattoos', '纹身',
      [SiteTab('', '全部'), SiteTab('yes', 'Yes'), SiteTab('no', 'No')]),
  SiteTab('hair', '发色', [
    SiteTab('', '全部'),
    SiteTab('auburn', 'Auburn'),
    SiteTab('bald', 'Bald'),
    SiteTab('black', 'Black'),
    SiteTab('blonde', 'Blonde'),
    SiteTab('brunette', 'Brunette'),
    SiteTab('grey', 'Grey'),
    SiteTab('red', 'Red'),
    SiteTab('various', 'Various'),
    SiteTab('other', 'Other'),
  ]),
  SiteTab('piercings', '穿环',
      [SiteTab('', '全部'), SiteTab('yes', 'Yes'), SiteTab('no', 'No')]),
  SiteTab('cup', '罩杯', [
    SiteTab('', '全部'),
    SiteTab('a', 'A'),
    SiteTab('b', 'B'),
    SiteTab('c', 'C'),
    SiteTab('d', 'D'),
    SiteTab('e', 'E'),
    SiteTab('f-z', 'F-Z'),
  ]),
  SiteTab('breasttype', '胸型', [
    SiteTab('', '全部'),
    SiteTab('natural', 'Natural'),
    SiteTab('fake', 'Fake'),
  ]),
];

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
      SiteTab('ai-duanju', 'AI成人短剧', _hgSorts),
      SiteTab('ai-manju', 'AI成人漫剧', _hgSorts),
      SiteTab('ai-huanlian', 'AI换脸', _hgSorts),
      SiteTab('ai-mogai', 'AI魔改', _hgSorts),
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
      themes: _pkThemes,
      languages: _pkLangs,
      durations: _pkDurations,
      sorts: _pkSorts,
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
      SiteTab('筛选', '其他原创/企划', _mdOther),
      // 标签云页 /tags：50 个标签卡，点进去是该标签的列表页（站点没有分页）
      SiteTab('/tags', '热门标签'),
      SiteTab('筛选', '筛选', _mdScreens),
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
      // 再由列表页顶部的「分类」筛选按钮弹窗选那 102 个（见下面的 filters / _phCats）。
      SiteTab('/video', '分类'),
      // 色情明星：站点顶栏第 5 项。进去是**演员卡列表**（61 个/页，名字+头像+排名），
      // 点演员 → 演员页（`/pornstar/xxx`、`/model/xxx`）——**那是他的视频列表**，不是视频详情。
      // 筛选（用户 2026-10-02 点名要的）：排序（`?o=`，7 项，见 phStarSorts）
      // + 演员类型（`?performerType=`，见 phStarTypes）+ 时间区段（`?t=`，见 phStarTimes）
      // + 「更多筛选设置」7 组（见 phStarMore，组各自的 URL 参数名已从站点实测确认）。
      SiteTab('/pornstars', '色情明星'),
    ],
    // 「分类」**不做平铺 tab**（站点顶栏那个是下拉、不是列表页）：做成列表页上的
    // 筛选按钮 → 点开**弹窗**选，候选 = /categories 页的 102 个（见 _phCats）。
    // 按钮与弹窗标题用 themeLabel 显示成「分类」；**没选时**按钮写「分类选择」
    // （themeEmptyLabel，照模拟器定稿）；durations/sorts 给空列表 → 那两个按钮不画。
    filters: SiteFilters(
      themes: _phCats,
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
      // 清单就是下面的 `_xhCats` —— 站点 /categories 页 `assignable` JSON 的 13 组）。
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
      themes: _xhCats,
      languages: const [],
      durations: const [],
      sorts: const [],
      themeLabel: '分类',
      themeEmptyLabel: '分类选择',
    ),
    color: Color(0xFFF5A623),
  ),
];
