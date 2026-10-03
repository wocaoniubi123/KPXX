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
/// 清洗副标题（多站共用）✓ —— ⚠️ 2026-10-03 从 `api.dart` 上移：
/// wordpress 系等站点用到 ✗，而它们已拆成独立文件 → 跨文件调不到 ✗，故上移并公开 ✓。
/// 合集的"详情帖"链接文字 → 当选集标题：
/// "👉点我查看详情帖 越南爆乳福利姬 xxx 【第5弹】" → "越南爆乳福利姬 xxx 【第5弹】"
String cleanSubTitle(String raw) {
  var t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  t = t.replaceAll('点我查看详情帖', ' ');
  t = t.replaceAll(RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true), ' ');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.isEmpty ? '视频' : t;
}

/// 从标题里取"第几集/第几部"的序号（多站共用）✓ —— 同上，上移并公开 ✓。
/// "视频一：" → 1；"视频12：" → 12；没有编号返回 0
int videoOrdinal(String s) {
  final m = RegExp(r'视频\s*([0-9一二三四五六七八九十百]+)').firstMatch(s);
  if (m == null) return 0;
  final t = m.group(1)!;
  if (RegExp(r'^[0-9]+$').hasMatch(t)) return int.parse(t);
  const cn = {
    '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
    '六': 6, '七': 7, '八': 8, '九': 9,
  };
  if (t == '十') return 10;
  if (t.startsWith('十')) return 10 + (cn[t.substring(1)] ?? 0);
  if (t.contains('十')) {
    final parts = t.split('十');
    return (cn[parts[0]] ?? 0) * 10 +
        (parts.length > 1 ? (cn[parts[1]] ?? 0) : 0);
  }
  return cn[t] ?? 0;
}
