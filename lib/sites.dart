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
  const SiteFilters({
    required this.themes,
    required this.languages,
    required this.durations,
    required this.sorts,
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
];
