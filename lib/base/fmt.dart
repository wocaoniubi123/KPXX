// 底座：**与站点无关**的文本/时间格式化 ✓
//
// ⚠️ 用户 2026-10-03 决策：取消全站共享，站点相关的一切改成站点独立专属 ✓；**底座保持公用** ✓。
// 这两个原先在 `Api` 里，实测 **20+ 处**在用（横跨几乎所有站点 ✓）→ 属于底座 ✓。
// 从 `Api` 里**原样搬**出来（**不重写逻辑** ✓），仅去掉私有前缀 ✓。

/// 卡片时间：站点带时分秒就一起显示；只有月-日（51fans1 列表）也照原样显示。
String metaDate(String raw) {
  final t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return '';
  final cn = RegExp(r'\d{4}\s*年\s*\d{1,2}\s*月\s*\d{1,2}\s*日(?:\s*\d{1,2}:\d{2}(?::\d{2})?)?')
      .firstMatch(t);
  if (cn != null) return cn.group(0)!;
  // 51fans1 的列表卡片只有"9月29日"（没有年）
  final cnMd = RegExp(r'\d{1,2}\s*月\s*\d{1,2}\s*日').firstMatch(t);
  if (cnMd != null) return cnMd.group(0)!;
  final iso = RegExp(r'\d{4}[-/.]\d{1,2}[-/.]\d{1,2}(?:\s*\d{1,2}:\d{2}(?::\d{2})?)?')
      .firstMatch(t);
  if (iso != null) return iso.group(0)!;
  final md = RegExp(r'^\d{1,2}-\d{1,2}$').firstMatch(t);
  if (md != null) return md.group(0)!;
  final rel = RegExp(r'\d{1,2}\s*(?:分钟|小时|天)前').firstMatch(t);
  if (rel != null) return rel.group(0)!;
  return '';
}

/// 标题中含"第 N 集"则提取系列前缀，否则空串。
String seriesPrefix(String title) {
  final m = RegExp(r'第\s*\d+\s*集').firstMatch(title);
  if (m == null) return '';
  return title.substring(0, m.start).trim();
}
