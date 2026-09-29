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
  /// 第一个域名当主域名，按当前实测可用顺序排列（挂掉的别放前面，否则每次白等超时）。
  final List<String> hosts;

  /// kind=native：顶部 tab（slug => 显示名），顺序即 tab 顺序
  final List<MapEntry<String, String>> categories;

  /// kind=web：目标地址
  final String url;

  /// 可选图标地址；留空 = 用名字首字画色块
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
    hosts: [
      'cgwz2.com',
      'cgwz1.com',
      '51cgo13.com',
      '51cg1.com',
      'cg51.com',
      'chigua.com',
    ],
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
];
