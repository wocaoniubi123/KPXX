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
  template: SiteTemplate.wordpress,     // 默认值，可不写
  iconUrl: '/favicon.ico',             // 以 / 开头 = 用该站第一个域名拼
  hosts: ['真站域名.com', '备用域名.com'],
  categories: [
    SiteTab('mrds', '每日大赛'),        // key => tab 显示名
    SiteTab('ztds', '主题大赛'),
    // ⚠️ 顺序必须照抄站点导航（首页那几个入口组）的原顺序，别自己按"重要程度"排
    // （51fans 就被排错过一次：把「吃瓜黑料」提到第一位、把「热门/今日更新」挪到了最后）
    // 分类下有子分类就写第三参（会显示成第二行小胶囊）：
    // SiteTab('cat', '分类名', [SiteTab('sub1', '子1'), SiteTab('sub2', '子2')]),
  ],
  color: Color(0xFFFF6B6B),            // 没有 iconUrl 时的首字色块底色
)
```

**`hosts` 只放"能直接出内容"的真站域名** ⚠️：这类站的很多域名只是**跳转入口**，
只有根路径 `/` 会跳到真站，`/category/...`、`/archives/...` 这类内容路径直接 **404**。
把入口域名放前面，每个请求都要白等一轮超时。

`categories` 的 key 从站点首页导航栏的 `a[href^="/category/"]` 里取（页面上能看到中文名）；
要是列表页不在 `/category/{key}/` 下（如 51fans1 的 `/order/hot/`），key 直接写**站内路径**
（以 `/` 开头，翻页按 `/order/hot/2/` 拼）。

### 情况 B：不是这套模板的站

1. 先看能不能加个模板（`SiteEntry.template`），解析都集中在 `lib/api.dart`：
   - `SiteTemplate.huangguo`：列表走 JSON 接口、详情页内嵌 JSON（见 README §8.4 黄果短剧）
   - `SiteTemplate.porna`：列表 `div.video-item`、详情要再请求一个接口换 m3u8
2. 实在抓不动（页面纯 JS 渲染、接口要签名/登录）就退到 WebView：

```dart
SiteEntry(name: '站点名', kind: SiteKind.web, url: 'https://xxx.com'),
```

点开就是应用内 WebView（`web_page.dart`，已伪装手机 Safari UA、带进度条和错误重试）。

**新站上线前必须做的 3 项检查**：① 各分类逐条跑一遍（有内容）② **搜索实测有结果**（站点没有搜索功能的跳过，记进 §6）③ 详情页能拿到视频源。

**加新模板时记得两处同步**：`lib/api.dart`（App）+ `sim/index.html` 的
`parseArticles`/`parseDetail`/`fetchList`（模拟器），两边规则要一致，
先在模拟器验数据，再推 CI 构建。

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

### 5.1.1 站点把播放地址藏在"打包 JS"里（Dean Edwards packer）

91porna 的换源接口（`/index/detail_play`、`/index/melon_detail_play.js`）返回的不是明文地址，
而是 `eval(function(p,a,c,k,e,d){…}('…',a,c,'k1|k2|…'.split('|'),0,{}))` 这种**打包 JS**：
m3u8 被拆成字典碎片。`api.dart` 里 `_unpackJs()`（模拟器里是同名 `unpackPacker()`）自己做解包：
还原 p 文本的字符串转义 → 按 base-a 生成 token → 从高位到低位替换字典。
明文响应直接正则抠 m3u8，打包响应先解包再抠（`_playUrlFromScript` 两条路都走）。

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
9. **新站的搜索/分区限制（2026-09-30 实测）**：
   - 51fans1：搜索走 `/search/{kw}/`（**可用**，实测"吃瓜"出 20 条）。
     ⚠️ 2026-09-30 曾误判为"搜索不可用"——当时是站点/代理抽风返回空，后来复测正常。
     它的搜索结果卡片标题是 `<div>`（分类页是 `<h3>`），都带 `xqbj-list-rows-image-title` 类，选择器通用。
   - 黄果短剧：只接了 4 个视频频道（AI成人短剧/漫剧、AI换脸、AI魔改）+ 搜索 + 标签；
     `/topics/`、`/ranks/hot/`、`/chigua/` 是另一套页面结构，暂未接入
   - 91porna：接了 **8 个**顶层分类（91视频 / 91短视频 / 黑料吃瓜 / AI成人 / 日本AV / 91动漫 / 精选合集 / 色情小说）。
     还差 1 个：`/comic/index/links?key=ppxx`（91品牌，外链导航页）。
     精选合集=`a.ms-card` 合集卡（点开是该合集的视频列表）；色情小说=文字卡（没封面）+ 详情正文 `article.markdown-body`。
     91视频是**三级结构**：一级子 = 站点下拉菜单那 14 个；其中「热门排行榜」再带 12 个二级子（那排排序）。
     `SiteTab` 的第三参可以再套 `SiteTab`，UI 会多渲染一行小胶囊（App/sim 都支持三级）。
     91porna 的播放地址有个额外步骤：请求 `/index/detail_play?img=封面路径&u=页面内嵌160位hex&t=时间戳/2100`
     才换回带签名的 m3u8（前端 JS 就是这么拼的，照抄）。
10. **新站图片加密同一套 AES**（key/iv 与 51吃瓜 相同，实测 `pic.wirqed.cn`、`pic.ndhixj.cn` 都能解）
   → `fetched_image.dart` 不用改。

---

## 7. 调试与诊断

- **播放器出错**：界面上的错误提示会带上 mpv 的 `error`/`fatal` 原文（例如
  `Failed to recognize file format`、`No render context set`），把那句话发出来就能定位。
- **构建失败**：`gh run view <id> --log-failed` 直接看失败步骤；版本类问题优先怀疑第 1 节的"钉版本"表。
- **域名是否可用**：浏览器打开 `https://<域名>/category/<slug>/`，看是否 404
  （跳转入口域名会 404）。
- **视频地址是否有效**：把 m3u8 的 `auth_key` 改坏再访问，返回 `400 Bad Request` 即符合预期。

---

## 8. 列表卡片 / 详情页 必备元素（从 Forward 模块规范提取，按本 App 形态落地）

> 来源：Forward 模块开发规范的「铁律 A / A2」。已剔除 Forward 专有协议
> （WidgetMetadata、link 夹带封面、cover_type 参数、**封面代理** —— 这些我们都不用）。
> **原则：站点页面上有的元素，一个都不能少；站点没有的落空，不能显示成空白。**
> 图片一律由 App 自己下载 + 解密（`fetched_image.dart`），数据里存**原始 URL**。

### 8.1 列表卡片（每站都要）

| # | 元素 | 取值规则 | 现状 |
|---|------|---------|------|
| 1 | 详情链接 | 卡片内指向详情的链接，id 唯一（去重用） | ✅ 已有 |
| 2 | 封面 | 懒加载属性优先级 `data-src` → `data-original` → `data-bg` → `srcset` → `src`；`data:` 占位图丢弃 | ⚠️ 只认各站实际用的（`data-src` / `data-xkrkllgl` / `z-image-loader-url`），其余属性未遇到 |
| 3 | 标题 | 卡片标题元素；取不到就整卡跳过 | ✅ 已有 |
| 4 | **封面右下角角标** | 站点在封面右下角显示什么就显示什么：**一般站=视频时长**（91porna/91短视频）；**黄果短剧=集数**（更新至5集/全集5集，站点自己就是这么显示的） | ✅ 已有（`Article.badge`） |
| 5 | 发布时间 | 卡片时间元素；"28分钟前"这类相对时间原样显示 | ✅ 已有（`Article.meta`，居中一行；黄果卡片没有时间→不显示） |
| 6 | 封面方向 | 默认横屏；**站点可配竖屏**（`SiteEntry.portraitCovers`，黄果=3:4） | ✅ 已有 |
| 7 | **小字简介** | 站点卡片有简介就显示（2 行截断） | ✅ 已有（`Article.desc`，目前只有黄果的卡片有） |
| 8 | **分类标签（可点）** | 站点卡片上的标签能点，我们也能点（进该标签的列表）：黄果=`/tag/slug/`，91porna=关键词搜索 | ✅ 已有（`Article.tags`；站点只给名字没给链接时只展示不可点，如黄果 JSON 接口卡片——站点自己那套卡片也是不可点的 `<span>`） |
| 9 | 卡片高度 | 卡片按内容高度显示，**内容少的不要留一大片白** | ✅ 已有（App 用 `Align(top)` + 调宽高比；sim 用 `align-items:start`） |

### 8.2 详情页（站点有就必须有，一个都不能少）

| # | 元素 | 落地要求 | 现状 |
|---|------|---------|------|
| 1 | 标题 | | ✅ 已有 |
| 2 | 简介 | 正文描述优先，退化 `meta[name=description]` | ✅ 已有 |
| 3 | 发布时间 · 时长 | 合成一行显示（日期 · 集数 · 时长） | ✅ 已有（站点带时分秒就一起显示） |
| 4 | **视频时长** | 详情页同样显示 | ✅ 已有（91porna 的 `PT1H39S`、黄果的 3:34） |
| 5 | **标签 / 分类** | 全部提取，且**点击可跳转**到该标签的列表 | ✅ 已有（横向单行，放在「剧照」下方） |
| 6 | **演员 / 人物** | 有则提取，可点击跳转 | ⚠️ 站点都把作者做成了"主页/合集"（不是标签体系），暂不做 |
| 7 | **推荐 / 相关视频** | **必须显示在「剧照」下方** | ✅ 已有（51系站=尾部「热门新闻」文字链；黄果=「猜你喜欢」卡片；91porna=相关卡片） |
| 8 | 剧照 | 有则全部提取（横滑 + 点开大图）；没有则用封面兜底，不留空白 | ✅ 已有（黄果/91porna 站点本身没有剧照 → 不显示该区块） |
| 9 | 海报 | **用列表封面**（列表已加载，零等待；不重新扫详情页找图） | ⚠️ 现在用的是正文首图，暂未改（列表封面要跨页传参） |
| 10 | **子分类** | 分类 tab 下若有子分类，**全部显示出来** | ✅ 已有（黄果=4 个排序；91porna=11/6/4/5 个子频道） |
| 11 | 视频源 | m3u8 / mp4，多源兜底 + 过期重取 | ✅ 已有（91porna 额外走 `/index/detail_play` 换播放地址，过期同样重取） |

### 8.2.1 用户明确提过的要求（逐条对照，别再犯）

> 这些都是这一轮里用户逐条提的，改过的地方按这里核对；新加站点/新加元素时也照这个来。

| # | 要求（用户原话的意思） | 落地 | 现状 |
|---|----------------------|------|------|
| 1 | 卡片**标题必须居中** | App/sim 卡片标题一律 `center`（不是只有竖屏站） | ✅ |
| 2 | 卡片**时间那行**也居中，且**只要时间**（作者、分类都不要） | `Article.meta` 只放时间，居中显示 | ✅ |
| 3 | 站点时间带时分秒就一起显示 | `_metaDate` 支持 `HH:MM(:SS)`；详情页 `_fmtTime` 同理 | ✅ |
| 4 | 卡片封面**右下角**：站点有视频时长就显示时长 | `Article.badge`（91porna/91短视频=时长） | ✅ |
| 5 | **黄果短剧**的封面右下角要显示**集数**（不是时长） | 黄果卡片 badge = `更新至N集` / `全集N集` | ✅ |
| 6 | 卡片要有**标题 + 小字简介**（分类标签**只做在能看的地方**） | `Article.desc`；卡片标签能力保留但黄果**不显示**（2026-09-30 用户嫌难看，取消） | ✅ |
| 7 | 站点卡片上的标签**能点**，我们也要能点 | 卡片标签点击 → 该标签列表（**详情页**标签仍在，可点）；**卡片上不再显示标签**（黄果按用户要求去掉，91porna 本来就没加） | ✅ |
| 8 | **元素少就自动缩短**，别留一大片空白；**一行里卡片高度必须一致**（不能一高一低）；**标题能一行就一行**（不特意占两行） | 卡片**填满格子/拉伸到行高**（App 不贴顶收缩；sim `align-items:stretch`）→ 同行等高；标题与简介都只 `maxLines: 2`、**不预留第二行高度**（能一行就一行）；纯文字页不渲染空播放器。实测：黄果 3 列每行 221/221/221（标题 1~2 行混排仍齐）、51吃瓜 160、91porna 141 | ✅ |
| 9 | **别加没让加的东西**（如 91porna 卡片上的关键词标签） | 已去掉，保持和站点一致 | ✅ |
| 10 | 分类/子分类**顺序必须照站点导航原顺序** | 逐站核对过（51吃瓜 27 个、每日大赛 20、91吃瓜 23、911爆料网 26、51fans 14、黄果 9、91porna 8） | ✅ |
| 11 | 分类下面的**子分类选项通通要显示**（多级也要） | `SiteTab` 可嵌套；App/sim 渲染多行胶囊（91porna 三级：91视频→14 项→热门排行榜下 12 项） | ✅ |
| 12 | 标签**横向单行**显示，放在**剧照下面** | 详情页顺序：视频→标题→时间/集数/时长→简介→选集→剧照→标签→相关推荐 | ✅ |
| 13 | **有推荐视频就必须显示在剧照下方** | 相关推荐区（黄果=猜你喜欢；91porna=相关卡） | ✅ （**51吃瓜 例外**：用户要求详情页不显示相关推荐 → `SiteEntry.showRelated: false`） |
| 14 | **封面默认横屏**，个别站竖屏（黄果 3:4）；**竖屏封面站一行 3 个卡片**（横屏站一行 2 个） | `SiteEntry.portraitCovers` → App 三处网格（列表/搜索/标签列表）+ 模拟器 `.cards.portrait` 全按它走 | ✅ |
| 15 | 详情页**集数**=本篇视频数（不是同系列文章数） | `videos.length` | ✅ |
| 16 | 图文帖没有视频就**别显示"0 集"** | 无视频时不显示集数那行 | ✅ |
| 17 | 专题/合集卡点开的是**它下面那批视频的列表**，不是详情 | `/topics/`、`/moviesets/` 路由到列表页 | ✅ |
| 18 | **搜索数据要和原网页一致** | 7 个站搜索逐站核对（见 §8.4 与审计记录） | ✅ |
| 19 | 模拟器要**方便测**（用户是手机远控电脑，没有滚轮）：横条能**按住左右拖** | 三条横条 + 标签行/剧照行支持 pointer 拖动（拖>8px 吞掉随后的 click，防误切） | ✅ |
| 20 | 流程：**只在模拟器上测**；没得到允许**不推送、不构建** | 见文首流程约定 | ✅ |
| 21 | 详情页**跳走前必须停掉本页播放器**（点标签/相关推荐/网页播放器/切集）——否则原页压在栈下标继续放，新页也在放 → **多个视频同时出声** | `VideoSwitcher.pauseTick`（自增信号）→ 播放器监听即 `pause()`；**不销毁实例**（全屏页共用它，销毁会黑屏）。App-only（模拟器本来就会 destroy） | ✅ |
| 22 | 站点**本来就没有封面**的（91porna 小说）→ **卡片不渲染封面框**（不是灰块占位） | 卡片 `cover.isNotEmpty` 才渲染封面区 | ✅ |
| 23 | 我在**内置浏览器测试时一律静音**（视频一 play 就 muted+volume=0），别吵到用户 | 测试脚本里挂 `play` 捕获监听 + MutationObserver | ✅ |
| 25 | **合集文章**（正文里没有播放器、只有一串指向子文章的链接）→ **要把子文章的视频提取出来**，做成篇内视频（选集里能切）。⚠️ 用户要求：**不要认文字（👉/「详情帖」这类名字），要按结构规律判**——否则会出现「有些提取了、有些没提取」 | **结构规律（5 篇样本、2 个站实测对齐）**：真·子文章链接 = `.post-content` 的**直接子 `<p>`** 里的 `<a>`，且 href ≠ 本页。噪音全被挡：吃瓜爆料推广在 `th<tr<thead`；上一篇/下一篇在 `span.prev/next<nav<div.post-near`；相关文章在 `div.link-list<nav<div.hot-news-content`；版权行是 `p.content-copyright`（href 就是本页）；内容标签页那个是 `p<div.content-tab-content`（父级虽为 p，但 p 的爹不是 .post-content → 第二道判定挡掉）。命中后**只收「标题 + 子文章地址」**放进选集（**不预抓**）；label 去掉 emoji 和「点我查看详情帖」；最多 20 篇。**播放源按需取**：选手到哪一集，播放器才去那一篇的子文章页取 dplayer 源（`ArticleVideo.lazyUrl` + `Api.videoSourcesAt()`，取过的内存缓存 60 篇）——这样详情页首屏仍是 1 个请求。取不到就显示「这一集已失效」（**失效的子文章只有点到才知道**，用户确认接受）。实测：合集首屏 1.1~2.1s（改之前预抓 8 篇要 3~5s）、点一集取源+起播 **1.2s**、普通文章（自带视频）解析 0.9s、`lazyUrl` 全为空 → **逻辑完全不受影响**；91吃瓜 124178（TOP10）→ 10 条、51吃瓜 277232 → 8 条、推广页 139810/187826 → 0 条（无误报） | ✅ |
| 24 | **做站点时搜索功能必须实测能用**（新站上线前跑一遍）；**站点本身没有搜索功能的可以跳过**（记进 §6 已知限制） | 2026-09-30 实测 7 站搜索全部有结果：51吃瓜 25 / 每日大赛 28 / 91吃瓜 30 / 911爆料网 30 / 51fans 3（站点自己就 3 条）/ 黄果短剧 5 / 91porna 24 | ✅ |
| 26 | **黄果短剧选集要列全**：站点显示 21 集就得是 21 条（之前只出 2 条） | 根因：`epPlaySrcs` 只是**当前集附近的 2~3 集滑动窗口**（第1集页给 {1,2}、第21集页给 {20,21}）；页面上 `/video/{id}/`、`/video/{id}/ep-{n}/` 的选集链接才是完整的 → 按链接列全，窗口内有源的直接播、其余留 `lazyUrl` **点哪集抓哪集**（复用合集那套按需取源，`videoSourcesAt` 黄果分支取该集页的 `epPlaySrcs[本集号]`）。实测（sim）：神瞳觉醒 第一季 21 集全列出（第 1/2 集带源、其余 19 集 lazyUrl），点第 3 集（ep-3）/第 21 集（ep-21）各 ~1s 取源并起播 | ✅ |
| 27 | **黄果短剧的选集横向显示、按宽度自动换行**（横向**仅限黄果**这类竖屏封面站） | `portraitCovers` 站：App 用 `Wrap` 胶囊（选中橙 `0xFFE8590C`/未选灰）、sim 用 `.vchips{display:flex;flex-wrap:wrap}`；其它站保持竖排 `.vrow`（标题可能很长）。实测（sim）：331px 宽排成 5 行；51吃瓜合集仍为竖排 5 条（分支没串到别的站） | ✅ |
| 28 | **搜索必须能翻页**：网站搜"女"有 1548 页，App 却只有第一页（25 条）+ 拉到底空转圈 | ① **WordPress 系 5 站搜索有分页**：`/search/{kw}/{序号}/`（页面「下一页」链接实锤，非猜测；实测 51吃瓜第 2/3 页各 25 条、91吃瓜第 2 页 30 条、porna 第 2 页 24 条，均与前一页 0 重复）——2026-09-30 修正：**之前误判「站点无搜索分页」，只取了第 1 页**；② 黄果搜索单页（页面上没有分页入口）；③ **到底要明说**：App 搜索页 + 分类列表页、sim 搜索页，到底后显示「没有更多了」，不再永久空转圈；④ **sim 串台 bug**：搜索页没清上一个页面的滚动监听 → 滚到底会把那个分类的下一页渲染进搜索页（"看起来搜索能翻页、内容其实被替换"）→ 进搜索页/换关键词前 `onscroll=null`。实测（sim）：搜索滚到底依次加载第 2/3 页（标题不被替换、无分类日志混入）；黄果 9 条自动到底显示「没有更多了」 | ✅ |

### 8.3 明确不做（Forward 专有，我们没有）

- ❌ 封面代理（App/sim 自己解密）
- ❌ `WidgetMetadata` / `link` 夹带封面 / `cover_type` 参数协议
- ❌ 在客户端猜密钥（密钥从站点前端 JS 核对）

### 8.4 站点与结构（2026-09-30 实测）

| 站点 | 入口 | 模板 | 封面 | 列表 / 搜索 / 详情 | 备注 |
|---|---|---|---|---|---|
| 51吃瓜 | 51cg1.com | wordpress | 横屏 | `/category/{slug}/`、`/search/{kw}/`、`.dplayer` | 域名只有 `51cg1.com` 能出内容；**27 个分类按站点导航原序**（2026-09-30 补全，之前只收了 12 个还排错） |
| 每日大赛 | www.mrds66.com | wordpress | 横屏 | 同上 | |
| 91吃瓜 | 91cg1.com | wordpress | 横屏 | 同上 | 搜索页链接是**绝对地址**，需归一化 |
| 911爆料网 | 911bl.com + CloudFront | wordpress | 横屏 | 同上 | 两个域名都会 302 到 CloudFront |
| 51fans | 51fans1.com | wordpress（兼容分支）| 横屏 | `/category/{slug}/`、**`/order/hot/`、`/order/today/`**；详情 `.novel-title` + `.tags-group2` + `.defaultimg` | 卡片是 `div.xqbj-list-rows`（另一套主题 `haijiao3`）；搜索 `/search/{kw}/` 可用（结果页标题是 div，分类页是 h3，选择器按类名取即可） |
| 黄果短剧 | huangguoai.com | huangguo | **竖屏 3:4** | ⚠️ **精选推荐/最近上新 必须走 JSON 接口** `/api/videos`（默认排序=站点「热门视频推荐」那份；`sort=new`=最新上传）——**页面 HTML 里那份是站点没更新的静态版**，抓它会拿到另一个顺序，跟用户在站点上看到的对不上（2026-09-30 踩过，排查了一整轮）。三种列表：① 频道走 JSON 接口 `/api/videos/category/{slug}?sort=&page=&size=`；② 路径型 `/recommend`、`/newest`、`/topics/xxx/`（`hg-drama-card`，翻页 `/xxx/2/`）；③ `/ranks/hot/`（`hg-rank-item` TOP20）、`/chigua/`（`hg-post-card`，翻页 `/chigua/page/N/`）。详情：视频页内嵌 `<script id="videoInitialData">`（`epPlaySrcs` 只是**当前集附近 2~3 集**；完整选集看页面上的 `/video/{id}/`、`/video/{id}/ep-{n}/` 链接，**点哪集才去抓哪集**）；吃瓜帖 `/archives/N/` 是图文帖（`.hg-post-detail__body` 图片，无视频）；标签 `/tag/{slug}/` | 9 个 tab 按站点导航原序：精选推荐 / 最近上新 / AI成人短剧 / AI成人漫剧 / AI换脸 / AI魔改（各带 4 个排序）/ 专题 / 排行榜 / 吃瓜黑料。**专题卡点开的是「该专题下的视频列表」**（不是详情，App/sim 都做了这个路由） |
| 91porna | 91porna.com | porna | 横屏 | 三种列表页：`div.video-item`（视频）/ `article.video-card`（91短视频）/ `post-item`（黑料吃瓜）；详情：LD+JSON + **`/index/detail_play` 换 m3u8**（视频；日本AV 的详情是 `/comic/index/avdetail?video_key=`，token 长度不固定——普通视频 160 位、AV 页 352 位，要按候选逐个试）、`script#ms-bootstrap` 内嵌 JSON（91短视频，signed m3u8 + 相关推荐）、`article.ql-editor`（黑料帖：图文 + 正文里的 **`ql-video-mse` 视频**，走 `/index/melon_detail_play.js` 换源） | 9 个顶层导航里接了 **8 个**（91视频 / 91短视频 / 黑料吃瓜 / AI成人 / 日本AV / 91动漫 / 精选合集 / 色情小说，只剩 91品牌）；**支持三级**：91视频 → 一级子 14 个（热门排行榜/国产原创/…三级片）→ 「热门排行榜」自己还有二级子 12 个（正在播放/当前最热/…收藏最多） |
