// 底座：**与站点无关**的共享解析器 ✓
//
// ⚠️ 用户 2026-10-03 决策：取消全站共享，站点相关的一切改成站点独立专属 ✓；**底座保持公用** ✓。
// `dplayerSources` 实测被 **2 站**在用（wordpress 系 + 黄果 ✓）→ 属于底座 ✓。
// 从 `Api` 里**原样搬**出来（**不重写逻辑** ✓），仅去掉私有前缀 ✓。

import 'dart:convert';

import 'package:html/dom.dart';

/// 一块 dplayer 的播放源（h264 主源在前，h265 兜底）；配置坏就返回空
List<String> dplayerSources(Element dp) {
  final sources = <String>[];
  try {
    final cfg = jsonDecode(dp.attributes['data-config']!) as Map<String, dynamic>;
    final video = cfg['video'];
    final h265 = cfg['video_h265'];
    if (video is Map<String, dynamic>) {
      final u = (video['url'] as String?) ?? '';
      if (u.isNotEmpty) sources.add(u);
    }
    if (h265 is Map<String, dynamic>) {
      final u = (h265['url'] as String?) ?? '';
      if (u.isNotEmpty) sources.add(u);
    }
  } catch (_) {
    // 配置坏：视为无源
  }
  return sources;

/// 站内相对路径（把 `https://host/xxx` 剥成 `/xxx`；本来就是相对路径的原样返回）✓
/// ⚠️ 2026-10-03 从 `api.dart` 上移：**麻豆社与 wordpress 系都要用** ✗，
/// 而各站已拆成独立文件 → 跨文件调不到 ✗，所以上移并公开 ✓。
/// 把绝对地址归一化成站内相对路径（详情页只认 /archives/xxx/ 这种）
String toRelPath(String href) {
  if (!href.startsWith('http')) return href;
  final i = href.indexOf('/archives/');
  if (i >= 0) return href.substring(i);
  // 其它形态的绝对地址（如麻豆社的 https://host/xxx.html）：剥掉 scheme+host
  // 只留路径——_fetchText 会自己拼 "https://$host$path"，不剥就会拼出
  // "https://hosthttps://host/xxx.html" 这种废地址。
  final u = Uri.tryParse(href);
  if (u != null && u.path.isNotEmpty) {
    return u.query.isEmpty ? u.path : '${u.path}?${u.query}';
  }
  return href;
}
}
