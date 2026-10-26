// ★ 2026-10-27（用户要求）：**PandaTV 直播站档案** —— 独立站点文件 ✅
//
// 协议与实测事实见同目录 `panda_live.dart` 文件头（🛢️ 全部本机真请求核对过）。

import 'package:flutter/material.dart';

import '../sites.dart';

/// PandaTV 直播（韩国 팬더티비 / 中转 `5721004.xyz` / AWS IVS 实时流）
///
/// ⚠️ `hosts.first` 是**整页分发用的识别位**（`main.dart` 的 `LiveGridPage._open`
///   按它挑 `PandaLivePage`）—— 与直播聚合用 `hclyz` 是同一套写法 ✅
const SiteEntry kSitePandaLive = SiteEntry(
  name: 'PandaTV',
  template: SiteTemplate.wordpress, // 占位（本页自管整页，不走 api.dart 那套解析）
  hosts: ['5721004.xyz'],
  iconText: '🐼',
  assetIcon: '',
  color: Color(0xFF111111), // 黑底 + 图标文字
  group: SiteGroup.live, // 只进底栏「直播」宫格 ✅
);
