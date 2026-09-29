import 'package:flutter/material.dart';

/// 站点清单 —— 首页宫格里每个方块 = 这里的一条。
/// 加站点：在 kSites 里加一条即可，其他文件都不用动。
enum SiteKind {
  /// 应用内原生页面（同 51 站的 WordPress 模板：抓取解析，见 lib/api.dart 顶部注释）
  native,

  /// 应用内 WebView 直接打开 url
  web,
}

class SiteEntry {
  /// 方块下面显示的名字
  final String name;
  final SiteKind kind;

  /// kind=native：域名列表，抓取时逐个试，跑通的那个会被记住并优先使用。
  /// ⚠️ 这站的很多"域名"只是跳转入口：只有根路径 / 会跳到真站，
  /// /category/... /archives/... 这类内容路径直接 404（cgwz1/cgwz2/51cgo13 实测都是
  /// 404 或跳到死域名）。所以只放能直接出内容的真站域名，否则每个都要白等一轮。
  final List<String> hosts;

  /// kind=native：顶部 tab（slug => 显示名），顺序即 tab 顺序
  final List<MapEntry<String, String>> categories;

  /// kind=web：目标地址
  final String url;

  /// 可选图标地址；以 / 开头 = 用该站第一个域名拼（例：'/favicon.ico'）；
  /// 留空 = 用名字首字画色块。站点 favicon 是 ICO，app 内解码（见 fetched_image.dart）
  final String iconUrl;

  /// 首字色块底色（有 iconUrl 时不用）
  final Color color;

  const SiteEntry({
    required this.name,
    required this.kind,
    this.hosts = const [],
    this.categories = const [],
    this.url = '',
    this.iconUrl = '',
    this.color = const Color(0xFFFF7043),
  });
}

const List<SiteEntry> kSites = [
  SiteEntry(
    name: '51吃瓜',
    kind: SiteKind.native,
    iconUrl: '/favicon.ico',
    // 固定用这个：2026-09-29 实测 /category/wpcz/ 返回 200 + 25 篇文章（真站）
    hosts: ['51cg1.com'],
    categories: [
      MapEntry('wpcz', '今日吃瓜'),
      MapEntry('rdsj', '热门大瓜'),
      MapEntry('whhl', '网红黑料'),
      MapEntry('bkdg', '必看大瓜'),
      MapEntry('mrdg', '吃瓜榜单'),
      MapEntry('ysyl', '看片娱乐'),
      MapEntry('mrds', '每日大赛'),
      MapEntry('whhj', '网黄合集'),
      MapEntry('snsn', '骚男骚女'),
      MapEntry('xsxy', '学生校园'),
      MapEntry('rrcg', '人人吃瓜'),
      MapEntry('hwcg', '海外吃瓜'),
    ],
    color: Color(0xFFFF6B6B),
  ),
  SiteEntry(
    name: '每日大赛',
    kind: SiteKind.native,
    iconUrl: '/favicon.ico',
    hosts: ['www.mrds66.com'],
    categories: [
      MapEntry('mrds', '每日大赛'),
      MapEntry('ztds', '主题大赛'),
      MapEntry('rstt', '热搜吃瓜'),
      MapEntry('xazd', '校园学生'),
      MapEntry('blyp', '必撸大赛'),
      MapEntry('fctg', '反差泄密'),
      MapEntry('mhds', '网红黑料'),
      MapEntry('lqdp', '猎奇重口'),
      MapEntry('jdsj', 'AV看片'),
      MapEntry('mxwh', '明星大赛'),
      MapEntry('smdh', '动漫之家'),
      MapEntry('dypd', '影视国漫'),
      MapEntry('mtds', 'cos写真'),
      MapEntry('ysds', '声控ASMR'),
      MapEntry('czds', '寸止挑战'),
      MapEntry('hjds', '混剪PMV'),
      MapEntry('tgds', '原创投稿'),
      MapEntry('omjp', '欧美精品'),
      MapEntry('qwcs', '全网参赛'),
      MapEntry('aijc', 'AI剧场'),
    ],
    color: Color(0xFF7C4DFF),
  ),
  SiteEntry(
    name: '91吃瓜',
    kind: SiteKind.native,
    iconUrl: '/favicon.ico',
    // 2026-09-29 实测：/category/zxcghl/ 会 302 到 www.91cg1.com 后返回 30 篇文章（同模板站）
    hosts: ['91cg1.com', 'www.91cg1.com'],
    categories: [
      MapEntry('zxcghl', '今日吃瓜'),
      MapEntry('sports-live', '体育直播'),
      MapEntry('dydj', 'AI短剧'),
      MapEntry('rsdg', '最高点击'),
      MapEntry('zdtop', '91周榜'),
      MapEntry('ydtop', '91月榜'),
      MapEntry('bcdg', '必吃大瓜'),
      MapEntry('whhl', '网红黑料'),
      MapEntry('mxhl', '明星黑料'),
      MapEntry('qwys', '社会奇闻'),
      MapEntry('mrds', '每日大赛'),
      MapEntry('sstp', '实时偷拍'),
      MapEntry('lpsd', '深夜撸片'),
      MapEntry('hjll', '海角乱伦'),
      MapEntry('91th', '91探花'),
      MapEntry('crdm', '成人动漫'),
      MapEntry('xsjlb', '师生专栏'),
      MapEntry('fclv', '反差靓女'),
      MapEntry('tgqg', '投稿求瓜'),
      MapEntry('gcwh', '网黄合集'),
      MapEntry('aikj', '明星AI'),
      MapEntry('zptp', '自拍偷拍'),
      MapEntry('lqzk', '猎奇重口'),
    ],
    color: Color(0xFF2F80ED),
  ),
  SiteEntry(
    name: '911爆料网',
    kind: SiteKind.native,
    iconUrl: '/favicon-v4.ico',
    // 2026-09-29 实测：/category/jrgb/ 会跳到 CloudFront 域名后返回 52 篇文章（同模板站）
    hosts: ['911bl.com', 'd3gn4v6ng8b20o.cloudfront.net'],
    categories: [
      MapEntry('jrgb', '今日大瓜'),
      MapEntry('aidj', 'AI短剧'),
      MapEntry('shijiebei', '优先投放区'),
      MapEntry('mrds', '每日大赛'),
      MapEntry('hjsq', '海角社区'),
      MapEntry('crfys', '午夜剧场'),
      MapEntry('dmhv', '动漫天堂'),
      MapEntry('sgpjs', '水果派解说'),
      MapEntry('rmgb', '独家爆料'),
      MapEntry('rlph', '黑料排行'),
      MapEntry('ssdbl', '热点吃瓜'),
      MapEntry('xyss', '校园吃瓜'),
      MapEntry('bgzq', '反差爆料'),
      MapEntry('whbl', '网红黑料'),
      MapEntry('mxhl', '明星吃瓜'),
      MapEntry('blqw', '猎奇吃瓜'),
      MapEntry('tksm', '偷窥泄密'),
      MapEntry('zksr', 'SM专区'),
      MapEntry('ntll', '男男女女'),
      MapEntry('thjx', '探花经典'),
      MapEntry('fljq', '福利视频'),
      MapEntry('crlz', '网黄专辑'),
      MapEntry('slec', '影视床戏'),
      MapEntry('kpzj', '看片专辑'),
      MapEntry('mjmsjb', '世界杯黑料'),
      MapEntry('zqbb', '世界杯宝贝'),
    ],
    color: Color(0xFF27AE60),
  ),
];
