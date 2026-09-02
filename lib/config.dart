/// 站点与分类配置。
/// 网站会频繁换域名（回退链来自官网页脚"永久地址"），分类 slug 从首页导航抓取确认。
class Site {
  static const String ua =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  /// 按优先级排列，抓取时逐个尝试
  static const List<String> hosts = [
    '51cg1.com',
    '51cgo13.com',
    'cg51.com',
    'chigua.com',
    'cgwz1.com',
    'cgwz2.com',
  ];

  /// 首页导航分类（slug => 名称），顺序即 App 里 tab 顺序
  static const List<MapEntry<String, String>> categories = [
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
  ];
}
