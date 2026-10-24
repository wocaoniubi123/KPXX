// ★ 2026-10-24（用户要求）：**直播聚合站点档案** —— 独立站点文件 ✅
//
// 用户口径：站点必须独立文件管理（`lib/sites/` 下一个站一个文件）✅
// 本文件只放 `SiteEntry` 档案；数据层在同目录 `live_zhibo.dart`、UI 在 `lib/live_zhibo_page.dart`

import 'package:flutter/material.dart';

import '../sites.dart';

/// 直播聚合站（api.hclyz.com：136 个平台 / FLV 直链）
///
/// 🛢️ 事实（2026-10-24 实测）：
///   · 目录接口 `http://api.hclyz.com:81/mf/json.txt` ⇒ 136 个平台
///   · 每个平台 `json<名字>.txt` ⇒ 主播列表（`zhubo` 数组）
///   · 主播的 `address` = **FLV 直链，已带 `wsSecret`/`wsTime` 签名**（无需自己算 ✅）
///   · 备用域名 `api.maiyoux.com:81`（实测同样 200、同样 136 个平台）✅
///
/// ⚠️ `hosts` 保留接口主域名（给日志/显示用）；**真正的取数在 `ZhiboApi` 里做**
///   （那个底座 `SiteFetcher` 只拼 `https://<host><path>`，装不下这里的 `http://ip:81/mf/xxx.txt`
///    ⇒ 不能复用它 ✅）
const SiteEntry kSiteLiveZhibo = SiteEntry(
  name: '直播聚合',
  template: SiteTemplate.wordpress, // 占位（本页自管整页，不走 api.dart 那套解析）
  hosts: ['api.hclyz.com'],
  iconUrl: '/favicon.ico',
  // ★ 2026-10-24（用户要求）：图标 = **黑底 + 白色文字 LIVE** ✅
  //   实现走 `SiteEntry.iconText`（通用能力，不写死站名）；黑底用 `color: Colors.black` ✅
  iconText: 'LIVE',
  assetIcon: '',
  color: Color(0xFF000000),
  group: SiteGroup.live, // 只进底栏「直播」宫格 ✅
);
