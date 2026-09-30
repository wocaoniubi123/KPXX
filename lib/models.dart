/// 卡片里可点的分类标签：key = 打开列表要用的 slug（huangguo 是拼音 slug，
/// porna 是关键词，空串 = 只展示不可点，如 JSON 接口只给了名字没给链接）
/// value = 显示名
typedef ArticleTag = MapEntry<String, String>;

/// 数据模型（自用最小集合）
class Article {
  final String title;
  final String url; // 站内相对路径如 /archives/273630/
  final String cover;
  final String meta; // 卡片标题下面那行（本站只放时间；黄果没有就是空串）

  /// 封面右下角角标：一般是视频时长（1:00:39 / 3:34）；
  /// 黄果短剧按站点习惯显示**集数**（更新至5集 / 全集5集）。没有就空。
  final String badge;

  /// 卡片上的小字简介（黄果有，其它站一般空）
  final String desc;

  /// 卡片上的分类标签（可点 → 该标签的列表页）
  final List<ArticleTag> tags;

  Article({
    required this.title,
    required this.url,
    required this.cover,
    required this.meta,
    this.badge = '',
    this.desc = '',
    this.tags = const [],
  });
}

/// 文章里的一个视频。
/// 一篇文章可能有多个视频（如"主题大赛"类合集文），每个视频自己带序号和标题。
class ArticleVideo {
  /// 展示名：就近抓到的标题；抓不到用"视频 N"
  final String label;

  /// 集数/序号：从"视频一："这类文字解析；解析不到用出现顺序（1 起）
  final int ordinal;

  /// 播放源，按优先级排列（h264 主源在前，h265 兜底），可能为空。
  /// 合集类条目这里是空的——真正取源要按需去 [lazyUrl]。
  final List<String> sources;

  /// 合集类（正文只有子文章链接）专用：这一集要去哪个子文章页面取源。
  /// 自带视频的条目为 null，逻辑完全不变。
  final String? lazyUrl;

  ArticleVideo({
    required this.label,
    required this.ordinal,
    required this.sources,
    this.lazyUrl,
  });
}

class ArticleDetail {
  final String title;
  final String time; // 2026-09-01T14:57:00+00:00
  final List<String> categories; // 分类 slug
  final List<String> images; // 正文图（详情页当"剧照"展示）
  final String intro; // 简介（文章页 meta description），可能为空

  /// 文章里的视频，按集数排序（可能为空 = 无视频）
  final List<ArticleVideo> videos;

  /// 标签（站点 /tag/xxx/ 那类），可点击跳转到该标签的列表
  final List<MapEntry<String, String>> tags; // slug => 名称

  /// 相关推荐（详情页尾部推荐区），显示在「剧照」下方
  final List<Article> related;

  /// 视频时长（站点有就显示在详情页标题下面，如 3:34 / 1:00:39），没有就空
  final String duration;

  final String seriesPrefix; // 系列前缀（如"良子重生绑定系统"），非系列文章为空

  ArticleDetail({
    required this.title,
    required this.time,
    required this.categories,
    required this.images,
    required this.intro,
    required this.videos,
    this.tags = const [],
    this.related = const [],
    this.duration = '',
    required this.seriesPrefix,
  });
}
