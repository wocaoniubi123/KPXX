/// 数据模型（自用最小集合）
class Article {
  final String title;
  final String url; // 站内相对路径如 /archives/273630/
  final String cover;
  final String meta; // "瓜妹 • 2026 年 09 月 02 日 • 分类"

  Article({
    required this.title,
    required this.url,
    required this.cover,
    required this.meta,
  });
}

class ArticleDetail {
  final String title;
  final String time; // 2026-09-01T14:57:00+00:00
  final List<String> categories; // 分类 slug
  final List<String> images; // 正文图片
  final String videoUrl; // 标准 hls（H264），可能为空字符串
  final String videoUrlH265; // H265 备选源，可能为空字符串
  final String seriesPrefix; // 系列前缀（如"良子重生绑定系统"），非系列文章为空

  ArticleDetail({
    required this.title,
    required this.time,
    required this.categories,
    required this.images,
    required this.videoUrl,
    required this.videoUrlH265,
    required this.seriesPrefix,
  });
}
