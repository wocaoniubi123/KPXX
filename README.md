# KPXX — 自用入口聚合 App

Flutter 写的自用 App：首页是站点宫格，点进去看内容（原生抓取或内置浏览器），
内置 libmpv 播放器（缓存可配、滑动跳转、亮度/音量手势）。

> **改这个项目前请先读第 3、4 节**：里面写了几个"改错就会崩"的硬约束，都是踩过的坑。

---

## 1. 快速开始

### 构建 / 发布（本机没有 Flutter，构建全在云端）

本仓库**不含 iOS/Android 工程目录**（`ios/` 是构建时用 `flutter create` 现生成的），
也**不装本地 Flutter**。发布流程就是：**改代码 → push 到 main → GitHub Actions 出包 → 下载 ipa**。

```bash
# 推送（会触发 .github/workflows/ios.yml）
git push origin main

# 看构建结果
gh run list --limit 1
gh run watch <run-id> --exit-status
gh run view <run-id> --log-failed        # 失败时看日志

# 下载产物（--dir 直接落到桌面，别放文件夹）
gh run download <run-id> --name kpxx-ipa --dir "C:/Users/Administrator/Desktop"
```

CI 关键配置（`.github/workflows/ios.yml`）：

| 项 | 值 |
|---|---|
| Runner | `macos-14`，Flutter **3.24.5** |
| Bundle ID | `ysc.tool6041.sign` |
| Team ID | `Z8J7VYHQZF` |
| 签名 | 手动签名 + Ad-hoc 导出 |
| 证书来源 | Secrets：`P12_BASE64` / `PROFILE_BASE64` / `P12_PASSWORD`（`cert/` 目录**不入库**）|
| 产物 | artifact 名 `kpxx-ipa` |
| 额外步骤 | 部署目标提到 **iOS 13.0**（libmpv 需要），改 Podfile + pbxproj |

### 依赖为什么这么钉版本

Flutter 只有 **3.24.5**（Dart 3.5.4），比这新的包要求更高 SDK，**必须钉住**：

| 包 | 钉的区间 | 为什么 |
|---|---|---|
| `media_kit` | `>=1.1.11 <1.2.0` | 见下条 |
| `media_kit_video` | `>=1.2.5 <1.3.0` | 1.3.x 会拉 `volume_controller ^3.0.2`，那个用了 Flutter 3.29+ 的 `FlutterSceneLifeCycleDelegate`，3.24 **编译不过** |
| `volume_controller` | `>=2.0.7 <3.0.0` | 同上（与 media_kit_video 的约束保持一致）|
| `shared_preferences` | `>=2.3.5 <2.5.4` | 2.5.4+ 要求 Flutter 3.35 |
| `screen_brightness` | `>=0.2.2+1 <0.3.0` | 0.2.2 是 Dart 2 的；`+1` 才支持 Dart 3。与 media_kit_video 一致 |
| `image` | `^4.2.0` | 纯 Dart，用来把 ICO 解码成 PNG（见 4.3）|
| `webview_flutter` | `>=4.7.0 <5.0.0` | 更新版要求更高 SDK |

---

## 2. 项目结构

```
lib/
  main.dart           入口 + 底部导航（模块/设置）+ 宫格首页 + 设置页      250 行
  sites.dart          ★ 站点清单：加站点只改这个文件                     100 行
  config.dart         各站共用的 UA                                    7 行
  models.dart         数据模型（Article / ArticleVideo / ArticleDetail） 56 行
  api.dart            抓取解析层：分类列表 / 搜索 / 详情 / 多视频          261 行
  home_page.dart      单个站点的内容页：分类 tab + 双列列表 + 搜索页       372 行
  detail_page.dart    详情页：播放器 + 多视频切换 + 简介 + 选集 + 剧照     418 行
  player_widget.dart  ★ 播放器：KpPlayer / VideoSwitcher / 控制条 / 手势  1323 行
  fetched_image.dart  图片：下载 → AES 解密 → ICO 转 PNG → 内存缓存       215 行
  web_page.dart       应用内 WebView（kind=web 的站点走这个）             104 行
  settings.dart       设置项（双击秒数 / 缓冲大小 / 自动下一集）            95 行
```

### 数据流

```
宫格首页(kSites)
 ├─ kind=native → HomePage(site)
 │     Api.category(slug, page) → List<Article> → 双列卡片
 │        └─ DetailPage(site, url)
 │              Api.detail(url) → ArticleDetail{ videos[], images[], intro, … }
 │                 ├─ videos[i] → KpPlayer(media_kit) → 播放 / 切换 / 自动下一集
 │                 └─ images[]  → FetchedImage（下载 + AES 解密）
 └─ kind=web → WebPage（应用内 WebView）
```

---

## 3. 怎么加站点（最常见操作）

只改 **`lib/sites.dart`** 的 `kSites`，其他文件不用动。

### 情况 A：这个站和 51吃瓜 用同一套模板（WordPress + DPlayer）

```dart
SiteEntry(
  name: '站点名',                       // 方块下面显示的名字
  kind: SiteKind.native,
  iconUrl: '/favicon.ico',             // 以 / 开头 = 用该站第一个域名拼
  hosts: ['真站域名.com', '备用域名.com'],
  categories: [
    MapEntry('mrds', '每日大赛'),       // slug => tab 显示名，顺序即 tab 顺序
    MapEntry('ztds', '主题大赛'),
  ],
  color: Color(0xFFFF6B6B),            // 没有 iconUrl 时的首字色块底色
)
```

**`hosts` 只放"能直接出内容"的真站域名** ⚠️：这类站的很多域名只是**跳转入口**，
只有根路径 `/` 会跳到真站，`/category/...`、`/archives/...` 这类内容路径直接 **404**。
把入口域名放前面，每个请求都要白等一轮超时。

`categories` 的 slug 从站点首页导航栏的 `a[href^="/category/"]` 里取（页面上能看到中文名）。

### 情况 B：不是这套模板的站

```dart
SiteEntry(name: '站点名', kind: SiteKind.web, url: 'https://xxx.com'),
```

点开就是应用内 WebView（`web_page.dart`，已伪装手机 Safari UA、带进度条和错误重试）。

### 图标怎么来的

`iconUrl` 用站点自己的 `/favicon.ico`（运行时下载 + app 内解码，**不打包进 ipa**）。
留空则用名字首字画色块。以 `/` 开头会自动拼 `hosts.first`，换域名时不用改图标。

---

## 4. 硬约束（改错就崩，都是踩过的坑）

### 4.1 播放器引擎：media_kit(libmpv)，不要换回 AVPlayer

原来用 `video_player`（iOS 原生 AVPlayer），有两个**改不掉的**毛病：

- AVPlayer 的**缓冲策略不可配**，跳转后要等系统把缓冲填满才恢复播放 → 长视频（20 分钟以上、
  分段加密的 HLS）拖动后能一直转圈不出来
- 插件的 `seekTo` 用 `kCMTimeZero` **精确 seek**，HLS 上要精确到那一帧 → 跨分段极慢

现在用 **media_kit**（libmpv/FFmpeg）：`PlayerConfiguration(bufferSize: N)` 直接就是 mpv 的
`demuxer-max-bytes` / `demuxer-max-back-bytes`，缓冲可配、HLS 由 FFmpeg 处理。

### 4.2 `VideoController` 必须在 `player.open()` 之前建好 ⚠️

否则 iOS 上 mpv 打不开 `vo/libmpv`，报 `No render context set`，
表现是**只有声音、画面全黑**（media-kit issue #1192）。

```dart
KpPlayer() : _p = Player(...), super(const KpState()) {
  _vc = VideoController(_p);   // ← 必须在这里，不能 late final 懒加载
  ...
}
```

### 4.3 图片是 AES 密文，favicon 是 ICO

- **图片**：站点图床返回的是 `binary/octet-stream` 密文（首字节不是任何图片魔数、长度整除 16），
  密钥/IV 是站点网页端 JS 里的**公开常量**（两站同一套）。`fetched_image.dart` 里：
  下载 → 判魔数（是图片直接用）→ 不是就 AES-128-CBC 解密 → **丢到后台 isolate**
  （纯 Dart 解密很吃 CPU，在 UI 线程解会让整页卡死：视频还在动、界面点不动）→ 内存缓存。
- **favicon**：站点的 `favicon.ico` 是 **ICO 容器、内嵌 BMP**，Flutter 的解码器**不认识 ICO**。
  用纯 Dart 的 `image` 包 `decodeIco()` 解出来再 `encodePng()` 交给 Flutter。

### 4.4 视频地址带 auth_key 时效签名

形如 `…m3u8?auth_key=1790668581-6abb6f2503c18-0-…`。**过期后**：

| 请求 | 服务器返回 |
|---|---|
| 正常签名 | `200` + 正文 `#EXTM3U…`（合法播放列表） |
| 失效签名 | **`400 Bad Request`** + 纯文本 `Bad Request` |

播放器拿到的不是播放列表 → FFmpeg 报 `Failed to recognize file format`。
所以起播失败时**要重新抓详情页拿新链接**，这就是 `onRefreshSources` 的用途。

### 4.5 Material 3 的 `IconButton` 有 48px 最小点击区

`constraints: BoxConstraints(minHeight: 28)` 压不掉它（`tapTargetSize` 机制），
整排会一直是 48 高。播放器底部那排按钮和进度条都是**自绘**的，别改回 IconButton / Slider
（Slider 另有一层上下留白，压不到最底）。

### 4.6 其它小坑

- `ValueListenable` **不在** `material.dart` 的导出里，要单独
  `import 'package:flutter/foundation.dart' show ValueListenable;`
- `Duration` 没有 `clamp`，自己写了 `_clampDur`
- `clamp()` 的返回值可能被推断成 `num`，传给 `double` 形参要 `.toDouble()`
- 详情页播放器要 `AutomaticKeepAliveClientMixin` 保活，否则往下翻看剧照会把播放器销毁，
  翻回来视频从头开始
- 拖动手势里**不要**每帧去 seek（会把长视频搞死），只在松手时跳转

---

## 5. 关键实现说明

### 5.1 抓取解析（`api.dart`）

- 列表页：`article[itemscope]`（排除 `.ad-item`）内的 `a[href^="/archives/"]` +
  `.post-card-title`；封面在 `<script>` 的 `loadBannerDirect('url'…`
- 详情页：`.post-title`、`meta[itemprop=datePublished]`；简介取 `meta[name=description]`
- **剧照**：只认 `data-xkrkllgl`（同一 img 的 `data-src`/`src` 常被站内推广图、主题占位图占用）
- **多视频**：正文里可能有多块 `.dplayer[data-config]`（一篇挂 7 个视频那种）。
  每个视频就近往上取短文本：`视频一：` 解析序号（中文数字也认），紧邻的 `blockquote` 当标题；
  解析不到编号就按出现顺序编号。**按序号排序**后交给详情页做「视频（N）」列表。

### 5.2 播放器（`player_widget.dart`）

| 组件 | 作用 |
|---|---|
| `KpPlayer` | 引擎封装，`ValueNotifier<KpState>`；UI 只认 `KpState`（位置/时长/播放中/缓冲中/已缓冲时间戳/是否播完/音量） |
| `VideoSwitcher` | 篇内视频切换状态，**详情页/内嵌播放器/全屏页共用同一份**（避免全屏页拿到旧序号） |
| `_SwipeSeek` | 左右滑动：按**距离**跳转（滑满一屏 120 秒），拖动只走预览、**松手才 seek** |
| `_BrightnessVolume` | 竖向手势：左半屏调亮度、右半屏调音量，带指示条 |
| `_SeekBar` | 自绘进度条（底轨 / 已缓冲 / 已播 + 圆点） |

- **多源兜底**：`sources` 按顺序试（h264 → h265），全失败再刷新时效链接重试一轮
- **卡住看门狗**：播放中位置连续 **9 秒**不前进才判卡住并提示（暂停不算）
- **错误提示原则**：起播阶段的失败会提示并触发换源/刷新；**已在播**时的偶发网络错误
  （如 `tcp: ffurl_read returned …`）只记日志、不弹提示
- **自动下一集**：设置里开启后，`completed` 时自动切下一个（走 `VideoSwitcher`）

### 5.3 缓冲显示（mpv 属性语义，别搞错）

| mpv 属性 | 含义 | 用途 |
|---|---|---|
| `demuxer-max-bytes` / `demuxer-max-back-bytes` | 前向 / 后向缓存上限 | 设置里的「缓冲大小」 |
| `demuxer-cache-time` | **已缓存数据的最后时间戳（绝对位置）** | 进度条浅色段 = `它 / 总时长` |

⚠️ 它**不是**"当前位置往后缓冲了多少秒"——拿它加当前位置会把位置算两遍，
表现是浅色段一直跟着播放进度跑。另外 mpv 没有暴露后向缓存的属性，所以只能显示"往后缓冲到哪"。

### 5.4 设置（`settings.dart`，`shared_preferences` 持久化）

| 设置 | 默认 | 说明 |
|---|---|---|
| 快进/快退秒数 | 10 | 双击画面左/右的跳转步长（5/10/15）|
| 播放缓冲大小 | 200MB | 100/200/300/500/1G，**改完重进视频生效**（播放器创建时读取）|
| 自动播放下一集 | 关 | 播完自动切下一个视频 |

---

## 6. 已知限制（都是有意取舍，不是 bug）

1. **亮度是系统级**：iOS 上读写的就是 `UIScreen.main.brightness`（整块屏幕）。退出**全屏**
   会 `resetScreenBrightness()` 还原；**内嵌小窗调完不还原**（想改可以加）。
2. **音量也是系统级**：和手机音量键同一套，改动会留存（不是只影响本播放器）。
3. **进度条只显示前向缓冲**（mpv 没暴露后向缓存）。
4. **内嵌播放器的竖向手势会占掉详情页滚动**：在视频区域内上下拖是调亮度/音量，
   不会滚动页面（详情页其它区域照常滚动）。这是"在视频上调亮度/音量"的必要代价。
5. **大缓冲有内存风险**：`demuxer-max-bytes` 与 `max-back-bytes` 是**两份**上限，
   选 1G 时理论上可到 2G 左右，低内存机型可能被杀进程；日常建议 200~500MB。
6. **图片只有内存缓存**（400 张，满了淘汰最旧 1/4），没有磁盘缓存 → 重进列表/详情会重新下载 + 解密。
7. **域名会轮换**：站点常换域名、图床也会换。域名挂了改 `sites.dart` 的 `hosts`；
   图片不按图床域名过滤（只按魔数），图床换了一般不用改代码。
8. **本机没有 Flutter**：改完只能靠 CI 编译验证，**无法本地运行 / 真机调试**。

---

## 7. 调试与诊断

- **播放器出错**：界面上的错误提示会带上 mpv 的 `error`/`fatal` 原文（例如
  `Failed to recognize file format`、`No render context set`），把那句话发出来就能定位。
- **构建失败**：`gh run view <id> --log-failed` 直接看失败步骤；版本类问题优先怀疑第 1 节的"钉版本"表。
- **域名是否可用**：浏览器打开 `https://<域名>/category/<slug>/`，看是否 404
  （跳转入口域名会 404）。
- **视频地址是否有效**：把 m3u8 的 `auth_key` 改坏再访问，返回 `400 Bad Request` 即符合预期。
