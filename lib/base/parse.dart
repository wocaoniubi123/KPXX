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
}
