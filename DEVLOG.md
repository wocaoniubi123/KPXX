# KPXX 开发日志

> 只保留**当前最新的流程与现状** ✓（2026-10-03 重写）。历史逐轮记录（1429 行）已归档到 **`DEVLOG_archive.md`** ✓。

---

## ⛔⛔ 写死的规则（**不可协商** ✗ —— 每回合开工先看这一条）

# **每个站点必须是独立的。不要写公共的站点函数。**

- 站点相关的一切 —— **分类表 / 子分类 / URL 拼接 / 解析 / 筛选 / 清单 / 选中状态 / 弹窗** ——
  **只能写在它自己的 `lib/sites/<站>.dart`** ✓
- **禁止**为站点逻辑写"公共函数 / 共用工具 / 按模板 if 分叉" ✗
  **哪怕两个站长得一模一样，也各写一份** ✓（复制一份比共用一处更符合本项目的规矩 ✓）
- **底座 `lib/base/` 只放与站点无关的东西** ✓：
  网络层 / 文本工具（fmt） / 模型 / 播放器 / 图片 / 背景 / 设置 / 播放记录 / 卡片网格 ✓
- **判断标准（三秒钟）**：这段代码**会不会因为换站而不同** ❓
  **会 → 站点文件** ✓ ｜ **不会 → 底座** ✓
- **允许的"公共"只有一处** ✓：`api.dart` 的 `ui` getter（**唯一**"模板 → 实例"的选择点 ✓）
  —— 那里是"接线"✓，**不许**在它里面塞任何站点逻辑 ✗
- ⚠️ **违反的后果（本项目真发生过 ✗）**：
  ① 底座里按模板 if 分叉 → 站点逻辑又散回公共层 ✗
  ② 公共页面里塞单站弹窗/单站状态 ✗
  ③ 搬站时漏改 `_f.` 前缀 → 编译错误连炸十几轮 ✗
  ④ 私有成员跨文件复用 → 报"未定义" ✗（正解是**各站各放一份副本** ✓）

---

## ⛔⛔ 第二条写死的规则（**不可协商** ✗）

# **用户问「能不能办到 / 能不能改」时 —— 先把代码实地查一遍，再给结论。**

- ❌ **禁止**在回答里夹「待查询 / 我需要再看看 / 要不要我去查」✗ —— **先查完，再回答** ✓
- **查什么（四样）** ✓：
  ① 相关函数**实际怎么写的**（读原文 ✓）
  ② **什么时候被调用**（定时器？事件？回调链路 ✓）
  ③ **参数从哪来** ✓
  ④ **有没有现成机制可复用** ✓
- **回答格式（四段）** ✓：
  ① **能不能办**（能 / 不能 ✓）
  ② **依据**（「文件:行号」+ 关键原文 ✓）
  ③ **要改哪里、改多大** ✓
  ④ **前提与限制**（哪些情况仍不生效 ✗ ✓）
- 确实查不到的，要**明说「我没查到」** ✓ —— 而不是把问题推回给用户 ✗
- ✅ 正例：用户问「点进度条会记录吗」→ 去读 player_widget.dart 的进度上报定时器 →
  查到它是 **10 秒一次 + 变化 ≥5 秒** ✗，而看门狗 **9 秒**就重试 ✗ → **直接给结论 + 说清根因 + 当场改掉** ✓
- ❌ 反例：「这套依赖 X，但我没核实过 X，要不要我去查？」✗

---

## 一、项目概况

自用内容聚合 iOS App（Flutter）· **13 个站 / 10 个 `SiteTemplate`** · 仓库 `wocaoniubi123/KPXX`（**PUBLIC**）·
App **直连**（不走代理）；本机所有网络操作走系统代理 `127.0.0.1:7890`（`gh` 需前置 `HTTPS_PROXY`/`HTTP_PROXY`）。
⚠️ **本机没有 Flutter SDK** ✗ → **"能编译"的唯一判据是 CI 绿** ✓。

站点文件：`sites/wordpress.dart`（5 站：51吃瓜/每日大赛/91吃瓜/911爆料网/51fans1）· `sites/porna.dart`（4 站：91porna/蜜桃/黑料…）·
`sites/xhamster.dart` · `pornhub.dart` · `hanime1.dart` · `pektino.dart` · `xvideos.dart` · `madou.dart` · `kmsvip.dart` · `huangguo.dart`

## 二、架构（现状：站点独立 ✓）
> **站点自己的事 → 全在各站点文件；软件基础设施 → 公用。**

**站点文件自己拥有** ✓：分类/子分类/多级分类表 · 标签选择器 UI · 重置 · 选中状态 · 数据获取与解析 ·
站点专属清单（`xhStarNav`/`xhCatGroups`/`phStarSorts`/`pkThemes`/`mdScreens`/`hgSorts`…）· 站点档案 `kSite01~kSite14` ·
筛选状态控制器 `HnFilterController`/`PhStarController`/`XhStarController`
→ ✅ `api.dart` 里**已无任何 `case SiteTemplate.*`** ✓（分发全走接口 ✓）

**底座 `lib/base/` 只有 3 个文件** ✓：
| 文件 | 内容 |
|---|---|
| `fetch.dart` | `SiteFetcher`：抓文本/域名轮换/5xx 重试/8s 超时 + `hlsVariants`/`secClock` + 错误日志挂载点 |
| `fmt.dart` | `metaDate`/`seriesPrefix`/`cleanSubTitle`/`videoOrdinal` |
| `site_ui.dart` | `SiteUi`：站点事实 13 条 + 5 个分发方法（并集签名）+ `sourcesFromHtml` |

**不可拆的基础设施**：网络层 · 播放器 · 播放记录 · 设置 · 图片 · 背景 · 模型 · `RowsGrid` · `ArticleCard`（已确认无站点逻辑 ✓）

**规模基线**：`api.dart` ~297 · `sites.dart` ~272 · `home_page.dart` ~1474 · `detail_page.dart` ~949 · `player_widget.dart` ~1883

## 三、版本号（唯一来源 ✓）
改 **`lib/app_version.dart` 的 `kAppVersion`** 一个常量 ✓ → **包名 / Release 附件名 / 设置页显示三处自动一致** ✓
（CI 用 `sed` 读它 → ipa 改名 `kpxx-<版本>.ipa`；App **设置页最底下**显示「版本 <版本>」✓）
**约定：每次构建 +1** ✓（当前 **1.0.2**）

## 四、构建流程（唯一验证手段 ✓）
`checkout → Setup Flutter 3.24.5 → flutter create → 证书 → 改 iOS 工程 → ExportOptions →`
`→ 代码检查 (flutter analyze lib)   ← 一次列出【全部】Dart 错误 ✓`
`→ Flutter build IPA → 按版本号重命名 IPA → 上传 artifact → 发布 Releases → 列出产物`

- **为什么要 analyze**：CFE 每轮只抛第一条错误 ✗（曾熬 15+ 轮）；analyze 一次给全（实测一次 **87 条 error** ✓）
  带 `--no-fatal-infos --no-fatal-warnings` → 只有 error 拦构建 ✓；**只查 `lib`** ✓（`test/` 是 flutter create 的模板，与仓库无关 ✗）
- **产物三处** ✓：Actions artifact（名固定 `kpxx-ipa` ✓）· **Releases**（ipa 直下 ✓，tag `v<日期>-<时分>` ✓）· **桌面** `C:\Users\Administrator\Desktop\kpxx.ipa`（文件名固定 ✓）

## 五、公共错误日志（2026-10-03 加 ✓）
- `lib/site_error_log.dart` → 沙盒 `kpxx_error.log` 追加 `[时间] [站点名] 错误信息` + 3 层堆栈 ✓
- 挂在 **`SiteFetcher` 的 3 个 catch**（所有站点取数唯一入口 ✓）→ 任何站出错自动带站名 ✓
- 保护：**绝不抛错** ✓ · 512KB 上限截断 ✓ · `read()/path()/clear()` ✓
- 入口：**设置 → 诊断 → 错误日志** ✓（看/刷新/复制全部/清空 ✓）—— iOS 沙盒 Documents 默认不可见，必须有 App 内入口 ✓

## 六、协作规矩
1. **不推不构建** ✗ —— 只有用户说「**构建**」才 `git push` + 跑 CI ✓（「构建」= 推送 → CI → ipa 下到桌面 ✓）
2. **提问期间只回答** ✓ —— 不改文件、不跑命令、不动任何东西 ✓
3. **每回合先读本日志** ✓；**改完 / 报错 / 构建结果都写进来** ✓
4. **重大改动前先确认** ✓
5. **盯构建派子智能体**（`build-watch`）并**设超时** ✗（禁止无反馈挂着 ✓）
6. **改动核对 `git diff --numstat` 行数变化**是否合理 ✓
7. 临时文件放工作目录、**用完即删** ✓；不动无关文件 ✓
8. **站点必须独立** ✓ —— **不写公共的站点函数** ✗（详见顶部「写死的规则」✓）
9. **被问「能不能办到/能不能改」时，先实地查代码再答** ✗ —— 不许给「待查询」式的回答 ✓（详见顶部规则 ✓）

## 七、踩过的坑（当约定用 ✓）
**脚本类**：① "插入"写成"替换" ✗（曾顶掉 `settings_page._card`）→ 写 `anchor + 新内容` ✓
② 锚点正则太宽 ✗（`class X {…非贪婪…}` 曾把 `xhamster.dart` 尾部插重复 3 份 + 两行截断）→ 别跨类匹配 ✓
③ "括号总数平衡" ≠ 结构正确 ✗ → 看「**列 0 声明是否出现在余额 ≠ 0 处**」✓
④ 猜缩进 ✗ → 用 `\n(\s*)` 捕获 ✓；⑤ 猜块收尾 ✗ → **括号深度计数** + **校验后面是不是 `);`/`}`** ✓
⑥ PowerShell `>` 重定向写 UTF-16 ✗ → 让 Node `execSync('git show …')` ✓；⑦ grep 大小写敏感 ✗ → 加 `-i` ✓
⑧ commit message 含英文双引号会截断 PS 参数 ✗ → 用「」✓

**Dart/站点文件**：`implements` 不继承默认实现 ✗→用 `extends` ✓ · `static` 不能用实例调 ✗→类名调 ✓ ·
私有成员跨库不可见 ✗→**各站放副本**（`_hnSorts`/`filterBtn`/`pickOptionDialog` ✓）· 被别的类裸调的顶层函数要放**文件顶层** ✓ ·
**站点文件别 import material** ✗ → 只要 `Color` 就 `import 'dart:ui' show Color;` ✓（material 会带 `Element`/`Text`/`Key` 撞名 ✗）·
html/dom 要 `as dom` ✓ · `const` 里不能用 getter（`kTxtSub` ✓）· 要记日志写 `catch (e, st)` ✓

**行为验证**：⚠️ **编译过 ≠ 行为对** ✗ —— 筛选/播放/置顶这类必须**真机点一遍** ✓


--- 追加（2026-10-03 本次构建 1.0.3）---
✅ **详情页播放器置顶**：播放器固定顶部 + 下方信息单独滚动（用括号深度计数定位 ListView 收尾 + 校验后面是 `);`/`}` ✓）
✅ **播放器诊断日志**（用户要求：慢站 seek 失败排查 ✓）：5 处写进错误日志（标签 `[播放器]` ✓）——
`open` 记源与 Referer · `seek` 记「想跳→实际跳」与 duration/position/buffering · `seekExact` · **看门狗判缓冲超时**记卡了多久 · error 流 ✓
→ 用法：设置 → 诊断 → 错误日志 → **复制全部** 发回来 ✓（不用再猜 ✓）


--- 追加（2026-10-03 本次构建 1.0.4 —— 播放/续播一轮修复）---
**根因链（实锤 ✓）**：用户报「跳进度后自动重试又从头开始」→ 查到三层：
① `player_widget.dart` 进度上报 **10 秒一次 + 变化 ≥5 秒** ✗，而看门狗 **9 秒**就判卡住重试 ✗ → 跳变还没上报就重试了 ✓
② `settings.dart` 落盘节流 **10 秒** ✗；③ 跳变没有强制落盘的通道 ✗
**修** ✓：① 上报 **2 秒 / 变化 ≥1 秒** ✓ ② 节流 **2 秒** ✓ ③ `touch(..., force:)` 跳变时**绕过节流** ✓

**续播（用户 2026-10-03 定的规则 ✓）**：
- **不管从哪进来**（卡片/搜索/记录页），只要记录里有这条视频就续播 ✓
- **续到上次看的那一集** ✓（`PlayRecord.videoIndex` ✓，建 switcher 时就应用 → **不闪第 1 集** ✓）
- 不续三种情况：没记录 ✓ 已播完 ✓ **剩 ≤5 秒** ✓
- **清晰度跟着这条视频记**（A 方案 ✓）：`PlayRecord` 加 `quality` 字段 ✓（老记录缺省 null ✓ 行为不变 ✓）；
  进页面读它 ✓、选完**立刻落盘** ✓；没选过 → **跟随站点默认** ✓

**Pornhub 两处** ✓：
- 档位识别：`_qualityOf` 原来只取**文件名** ✗ → Pornhub 的 `.../720P_4000K_x.mp4/master.m3u8` 认不出 ✗ → **选择器整块消失** ✗；改成**整路径匹配** ✓（仍排除 query ✓）
- **不再替站点选默认档** ✗：删掉「按 height 高→低 ✗ + 720P 提前 ✗」，**站点给哪个就播哪个** ✓（xHamster/XVideos 本来就没重排 ✓）
**撤** ✓：播放器那 5 处诊断日志已撤（用户不要 ✗）


--- 追加（2026-10-03 本次构建 1.0.5）---
**1.0.4 已装、用户确认「APP 端没啥问题了」** ✓（1.0.4 = 跳进度不从头 + 续播三项 + 清晰度跟视频记 + Pornhub 档位/去重排 ✓）

**① 模拟器修复** ✓：`sim/server.mjs` 原来只读 `lib/sites.dart` ✗（站点档案/清单已下放各站点文件 ✗）→ 改为**合并 `sites.dart` + `lib/sites/*.dart` 再解析** ✓，顺序仍按 `kSites` 引用顺序 ✓；`node --check` 通过 ✓（⚠️ 起服务验证因本机 `NO_PROXY` 冲突没做成 ✗，用户重启后自验 ✓）

**② 短片加载诊断日志**（用户提的做法 ✓）：xHamster 短片在模拟器能出 ✓、App 出不来 ✗ → 先埋点定位 ✓
- `api.dart` 的 `Api.category` 包一层：记 `key/k/page → 拿到 N 条` ✓，抛错记异常+堆栈 ✓（标签 `[列表]` ✓）
- `shorts_feed_page.dart` 翻页处同样记 ✓（标签 `[短片]` ✓）
- 判读法：**0 条** = 请求通但结构/解析不对 ✗；**抛错** = 网络或解析异常 ✗


--- 追加（2026-10-03 本次构建 1.0.6）---
**短片定位进展**：1.0.5 实测 `category key=/shorts → 45 条 ✓`（列表取数正常、零异常 ✓）；
用户截图显示短片页只有**背景图 + 转圈**（**连封面都没画** ✗）→ 卡在**取播放源**之前 ✓（起播前必须等 `_sourcesOf(i)` ✓）。
**1.0.5 埋点不足** ✗：[短片] 只挂在**翻页**那条路 ✗，第一页/取源没埋 ✗ → 当时「没有 [短片] 行」什么也证明不了 ✓。
**1.0.6 补** ✓：`shorts_feed_page.dart:149` 加「取源诊断」= `取源 #i url → videos=N srcs=M 首条=…`；
判读：videos=0 解析不出 ✗ ｜ srcs=0 源字段空 ✗ ｜ **一行都没有** 请求卡住 ✗（且**取源无超时** ✗ 是待修 bug ✓）。
**日志收紧**（用户要求 ✓）：`Api.category` 埋点只在 key/k 含 shorts 时记 ✗ —— 点别的主分类不再进日志 ✓。


--- 追加（2026-10-03 本次构建 1.0.7 —— 短片页两处真修复）---
**修 ❶ 封面**：`shorts_feed_page.dart:331` 原来用 `Image.network` —— 它**不附带任何请求头**，而 xHamster 封面需要站点请求头；且它加载失败时**不画任何东西**（该页也没有失败占位）→ 屏上只剩背景 + 转圈。改用项目自带、带请求头的 `FetchedImage` ✓（首页/详情页一直用它）
**修 ❷ 取源超时**：`_sourcesOf(i)` 原来**没有超时** → 卡住就无限转圈。现加 `timeout(20s)`，超时记日志并当空处理 → 交给上层走取不到源的分支 ✓
**查证（不该改的三条）**：列表**已**走 `Api.category(/shorts)`（45 条即它返回）✓；取源**已**走 `widget.api.detail(url)`（与详情页同一入口）✓；播放用的是**同一个 KpPlayer（mpv）** ✓ —— 只是没套 PlayerWidget 那层壳 ✓
**诊断**：取源处三态日志（发出前 / 成功带耗时 / 超时）；`Api.category` 埋点仅记 shorts
**教训**：改版本号/写日志的脚本里**禁止出现英文双引号**（已被截断两次导致版本号没升/DEVLOG 没写）


--- 追加（2026-10-03 本次构建 1.0.8 —— 短片 tab 一直转圈的真根因）---
**根因（事实链，非推断）**：
1) `home_page.dart:165` 切到短片 tab 时 `_feeds.removeWhere(...)` 把该分类的 feed **从缓存删掉**；
2) 之后新建的 feed **是空的**（`items` 空、`_done=false`）；
3) 渲染条件是 `feed.items.isEmpty ? (三态) : RowsGrid`（`:893`）→ 空 → 走转圈分支；
4) 而**没有代码**让这个新 feed 去加载 → **永远转圈**。
（用户日志里 `category /shorts → 45 条` 是**旧实例**拉的 → 「有数据却转圈」由此而来）
**修**：清缓存后拿到新 feed，`if (!fresh._started) fresh.ensureMore();` 立刻拉一次（`:170`）。
**顺带**：这是公共路径，凡「切 tab 清缓存」的分类一并治好，不是给短片打补丁。
**过程教训**：改代码前必须核对被调函数的**真实签名** —— 我一度按 4 参写 `_feedFor`，实际是 `_feedFor(SiteTab c)`（`:241`），当场改正。


--- 追加（2026-10-03 本次构建 1.0.9 —— 1.0.8 只补了一半）---
**1.0.8 实测仍是转圈** ✗（用户回报 B）。查下来缺的这一环：
`_FeedViewState` 带 `AutomaticKeepAliveClientMixin`（wantKeepAlive=true）→ **切走再回来 State 不重建**；
而 feed 实例**会被换掉**（切短片 tab 时 removeWhere 清缓存）→ 新实例**没人挂监听**（`initState` 不重跑、**也没有 `didUpdateWidget`**）→ 它的 notifyListeners 没人听 → 界面永不刷新 → 停在空列表的转圈分支。
⚠️ 这个坑 `home_page.dart:683` 的注释里**早就写着**（「key 不变 → State 被复用，而 _FeedViewState 没有 didUpdateWidget ✗」）—— **记了但一直没补** ✗。
**修**：`_FeedViewState.didUpdateWidget` → `!identical(oldWidget.feed, widget.feed)` 时 摘旧监听 + 挂新监听 + `ensureMore()`（自带守卫）。
**教训（写死）**：带 keepAlive 的 State 里，**凡是持有可被替换的对象（feed/model），必须实现 didUpdateWidget** ✗。


--- 追加（2026-10-03 本次构建 1.0.10 —— 短片能播了）---
**1.0.9 实测** ✓：卡片列表、翻页、取源链路**全部打通**（日志有 page=2 → 45 条、翻页 ✓、取源成功带耗时 ✓）；
剩下：多数短片 `videos=0 srcs=0` → `_open` 里 `srcs.isEmpty` 静默返回 → 点进去一直转圈 ✗。
**根因（抓页面实测 ✓，非推断）**：`xhamster.dart:737` 原来**只认** `.m3u8` ✗：
  `RegExp(r'https://[^"\s\\]+\.m3u8[^"\s\\]*')`
而短片页给的是页面 JSON 里的**直链 mp4**（且斜杠是**转义**的 ✗）：
  `"h264":[{"url":"https:\/\/video7.xhcdn.com\/…\/480p.h264.mp4","quality":"480p"}]`
→ 匹配不上 → 0 条 → 无限转圈 ✓。（能播的那两条是另一种形态：`media=hls2/multi=…/…_TPL_.h264.mp4.m3u8` ✓）
**修** ✓（`xhamster.dart`，插在原 m3u8 那行**之前**）：先按
  `"url":"(https?:\\?/\\?/[^"]+?\.mp4[^"]*)"[^}]*?"quality":"(\d{3,4})p"` 抓直链 mp4 ✓
  按 quality 高→低返回 ✓；`replaceAll(r'\/', '/')` 还原转义 ✓；**没命中就回落原来的 m3u8 路径** ✓（原逻辑一行未动 ✓）。
**复查记录**：正则的转义容错是我第一版写错（写死 `https://` ✗）当场发现并改正 ✓；返回类型经核对 ✓（紧随其后是 `var srcs = <String>[];`）。
**待办**：`shorts_feed_page.dart:175` 的 `srcs.isEmpty` **静默返回** ✗ —— 应改为给用户提示（体验项 ✓，本轮未动 ✗）。


--- 追加（2026-10-03 本次构建 1.0.11 —— 短片页 UI 两处）---
**1.0.10 实测：短片能播了** ✓（画面出来 ✓，解析修复生效 ✓）。用户随即报两个 UI 问题：
① **底部两个进度条**：`shorts_feed_page.dart:324` 的 Video(controller: …) **没传 controls** → media_kit_video **自带一条控制条**；
   且**自带控制条的手势层会吃掉竖滑** → 上划下划换条失灵。修：controls: NoVideoControls（一改两治 ✓）。
② **暂停时应显示 X 与标题条、播放中隐藏**：原来 X/标题只画在「非当前页」那个分支里，播放分支完全没有覆盖层；
   修：把播放层包进 Stack，用 if (!(_kp?.value.playing ?? false)) 才显示 X（maybePop）与标题；显隐靠 _onTick 的 setState 自动刷新。
**过程教训**：改多层嵌套 widget 树时锚点要先用行号加缩进打印确认（本次连试三次：缩进约束过严、收尾行多跨一行、PowerShell 的 -notmatch 对数组会返回不匹配元素而误判）。

--- 追加（2026-10-03 · 工作区改动，**未提交未构建**）短片页只留一个 X + ▶ 补守卫 + 「单实例预缓冲 5 条」查证 ---
**① 用户实测 1.0.11「左上角两个 X 重叠」✗ → 已修 ✓**
根因（实锤）：**同一个「暂停态」画了两层 X** ✗ —— `shorts_feed_page.dart:337-340`（在播放层里，**无圆底**的关闭图标按钮）+ 外层 `if (!_playing)` 的 `_RoundBtn`；两者坐标只差 (10,8) → 暂停时完全重叠 ✓（两处都只在暂停时出现 ✓，所以用户只在暂停态看到 ✓）。
修：按用户要求（一个 X / 暂停才显示 / **带圆底**）**删掉无圆底那个** ✓，圆底 X 保留（今 `:374-381`，`Icons.close` **只剩 `:379` 一处** ✓）。
**①b ▶ 暂停标志补守卫 ✓**（lead 2026-10-03 确认后改）：原来**无条件常画** ✗ → 播放中画面正中也挂着一个 96px 半透明 ▶ ✗；现补 `if (!_playing)` ✓（今 `:365-373`，`play_arrow_rounded` **1 处** ✓），与同层的圆底 X 一致（都只在暂停时出现 ✓）
**①c 删掉「播放层里多画的那一层」✓**（lead 2026-10-03 定论：那层 `if (!(_kp?.value.playing ?? false)) ...[` **连同里面的不加粗标题都是他较早抄进去的** ✗ —— 用户报的「两个 X」与「两条标题」正是这一处重复的两个症状 ✓）：
  删整层 ✓（`:334-337` 现为说明注释）；⚠️ **▶ 不在这一层里** ✓（删完确认 ▶ 仍在 `:365-373` ✓）
**② 暂停时只剩一条标题 ✓**（lead 定论：删 A 留 B ✓）：贴底信息栏（**页面原有** ✓，今 `:384` 起）= **加粗标题**（`:395`）+ meta（`if (art.meta.isNotEmpty)`，`:403-406`）+ 进度条与时间（`:412+`）；被删那层的**不加粗标题副本**（原 `bottom:120`）已去 ✗
  · meta 是什么：`models.dart:11` 注释「卡片标题下面那行（本站只放时间；黄果没有就是空串）」；**xh 短片**这条构造里写死 `meta: ''`（`xhamster.dart:288`，`_xhMomentsFromHtml` 内；短片路由见 `:162`）→ 短片页贴底那条**没有 meta 行** ✓，实际就是「加粗标题 + 进度条/时间」✓
  · **目标核对 ✓**：暂停时 = **一条标题**（`:395`）+ **一个 X**（`:379`）+ **一个 ▶**（`:370`）✓
**符号核对（lead 要的三条 ✓）**：`Icons.close` **1 处**（`:379`）· `play_arrow_rounded` **1 处**（`:370`）· 标题 Text **只剩贴底那一处**（`art.title` 仅 `:395`；`art?.title` **0 处** ✓）
**符号净账 ✓**：`git diff --numstat` = **`16/12`**（全是这一层的增删 ✓）· `()` **227/227**（HEAD 232 **−** 删行合计 **11 对** **+** 增行合计 **6 对** = 227 ✓；删行 11/11、增行 6/6 **各自都平衡** ✓）· `{}` **68/68** 不变 ✓ · `[]` 20 → **19/19**（删掉的 `...[` 与 `]` ✓）· 括号深度余额 **0** ✓、无「余额≠0 处却有列 0/2 声明」✓

**② 用户要的「**单实例**预缓冲 5 条」→ 查证结论：引擎侧做不到 ✗（依据全是上游原文/官方 issue，非推断 ✓）**
- **media_kit 侧确实有口子** ✓：`Player.platform`（`PlatformPlayer?`）→ 转 `NativePlayer` 后可 `setProperty(属性, 值)` / `command([...])`，
  `setProperty` 的实现就是直接调 `mpv_set_property_string`（media_kit 源码 `lib/src/player/native/player/real.dart` ✓）；
  ⚠️ 但 `PlayerConfiguration` **没有**任何「附加 mpv 选项」入口 ✓（字段只有 vo/osc/pitch/title/muted/async/libass/logLevel/**bufferSize**/protocolWhitelist）
- **mpv 侧唯一相关的开关是 `--prefetch-playlist`（默认 no）** ✓，官方手册原文：
  「Prefetch next playlist entry while playback of the current entry is ending. **This merely opens the URL of the next playlist entry as soon as the current URL is fully read.**」
  → ① **只预取「下一条」**（结构上就到不了 5 条 ✗）② **要等当前 URL 完全读完才开始** ✗（用户随手 2-5 秒划走 → 根本还没开始）
  ③ **对 HLS/.m3u8 无效** ✗（mpv 把 HLS 当**单个**媒体项；HLS 的预取只由解复用器缓存决定）④ 官方自述「可能偶尔做出错误的预取判定：**它不能预测你是否回退**，并假定你不会编辑播放列表」✓
- **上游态度**：mpv issue **#5940「Parallel prefetch」已 Closed ✗**（2018 开，诉求正是抱怨"要等当前下完才开始"）；**#6437「Buffer next videos in the playlist」仍 Open ✗**（2019 开，诉求=5 条预缓冲）；官方还一度把该选项默认改成 yes，随后 **revert 回 'no'** ✓（Releases/版本历史）
→ **结论：单实例 + 媒体级 5 条预缓冲 = 做不到** ✗。能做的最多是「1 条、当前读完才启动、HLS 无效」，与用户诉求差距太大 → **不硬编** ✗，本轮**未改任何播放代码** ✓
→ 唯一能真做到「5 条内容都在本地」且**仍是单实例**的路子（**用户已拍板 ✗ → 见下方本轮 B：已实现 ✓**）：App 侧按源 URL **预下载**（mp4 直链可行 ✓；m3u8 要逐段下载 ✗；部分 mp4 的 `moov` 在文件尾部 → 只下前半段会「播到一半断」✗ —— 本轮 B 的解法是**只播整份下完的文件** ✓）

---
## 追加（2026-10-03 · **sim 侧第 1 轮**，工作区改动，**未提交未构建**）模拟器实测 + 与 App 现状对齐 ---

### 任务① 实测「模拟器现在到底能不能用」→ **能** ✓（这次真跑起来了 ✓）
- 起服务：8787 被用户实例占着 → 我另起 **8788**（`Remove-Item Env:NO_PROXY` + `KPXX_PORT=8788` ✓，
  不再踩 `Start-Process` 那次 `NO_PROXY` 冲突 ✓）；自检出站代理 = `127.0.0.1:7890` ✓（`server.mjs` 的 detectProxy 生效 ✓）
- 浏览器实测：**Edge `--headless=new` + CDP 驱动**（Node 24 自带 `WebSocket`，零依赖临时脚本 ✓，用完已删 ✓）
- 结果（四个验证点全过 ✓）：
  ① 首页 **14 站宫格** ✓（顺序 = `kSites` 引用顺序 ✓）
  ② xHamster「短片」tab **12 卡** ✓、`#cards` 类 = `cards portrait shorts`（2 列竖版 ✓）；51吃瓜「学生校园」**25 卡** ✓
  ③ tabs 切换 ✓（xHamster `[影片,分类,色情明星,短片]`，影片默认 **54 卡** ✓）
  ④ **无**「没在 lib/sites.dart 里找到 kSites」✗ —— 页面日志是「站点清单来自 lib/sites.dart」+ 14 站全名 ✓；
     `/sites` HTTP 200、`error` 字段空、**14/14 站点**、`kSite01~kSite14` 全命中 ✓；**无未捕获 JS 异常** ✓
- 遗留噪音（**非本次引入** ✓）：`/favicon.ico` 404 · 偶发一张封面 `/proxy` 500 · hls.js 首个 CDN 不通时回退 unpkg ✓（已有兜底）

### 任务② 与 App 现状对齐 → 抓真页面取一手事实，**sim 改 3 处** ✓
**一手事实（`/site?name=xHamster&path=…` ✓，全部实测）**：
- 片源**两种形态**（`/shorts/<slug>` 的 `sources.standard.h264`）：
  ① 直链 mp4（**斜杠转义**）`"url":"https:\/\/video7.xhcdn.com\/…\/480p.h264.mp4","quality":"480p"`（同类还有 720p）✓
  ② m3u8 = `…/031/175/220/**_TPL_.h264.mp4.m3u8` —— `_TPL_` 是站点自己的**模板字面量**（不是占位符 ✓，实测原文在页面里就这么写）
  → App 1.0.10 那条正则（**原样**）在真页面**命中 4 条**（480p/720p 各出现 2 次）✓ —— App 侧解析是对的 ✓；
    sim 原来**只认未转义 m3u8** ✗（两种形态只覆盖了一种 ✗）
- 列表页 `/shorts/newest`：`<script id='initials-script'>window.initials={…}`（**单引号** ✓ —— CSS 选择器照样命中，
  App 的 `querySelector('script#initials-script')` 没问题 ✓）；`layoutPage.videoListProps.videoThumbProps` = **45 条** ✓（与 App 注释一致）；
  首条键 `id,title,thumbId,thumbInRotation,trailerURL,landing,thumbURL,imageURL,pageURL,views,icon` → **无 sources** ✓（所以必须逐条抓详情页 ✓）

**`sim/index.html` 改动（`server.mjs` 一行未动 ✓）**
1. `xhDetail`：新增**直链 mp4** 形态（转义容错 `replaceAll('\\/','/')`、按 quality 高→低），排在 m3u8 **之前** ✓；
   短片 `/shorts/…` 的 m3u8**不展开档位**（App 同款 ✓）；⚠️ 有意差别：**m3u8 也保留**（App 有 mp4 时会丢掉 ✗）——
   详情页清晰度行要能同时看见两种形态；**默认播的仍是第一条 = App 的 `srcs.first`** ✓
2. 瀑布流取源：新增 `feedSources()` —— **逐条抓详情页**（与 `ShortsFeedPage._sourcesOf` 同语义 ✓）+ 在途去重 + 抢答保护
   （等源中途划走不覆盖新条 ✓）+ 列表接口那份源**只当兜底**（日志写明这条用的是详情页还是兜底 ✓）；
   `feedPrecacheSources()` 预取接下来 5 条（App 同款 ✓）；`feedPreload` 改为预取**详情页第一条**的字节（原来预热列表源 = 错地址 ✗）
3. 暂停覆盖层：新增 `.fpause`（正中偏上 96px 白 70% ▶）+ `.fmeta` 标题条 → 两者**只在 `.screen.feedpause` 显示** ✓
   （App 1.0.11 / 未提交那轮同款 ✓）。实测：进流 1/1 ✓ 播放中 0/0 ✓ 暂停 1/1 ✓ 恢复 0/0 ✓

**改后复跑证据 ✓**：`短片取源 #1：详情页 3 条（首条 …/506/720p.h264.mp4）` → 起播 `readyState=4`、
`v.src = https://video7.xhcdn.com/key=…`（**直链 mp4** = App 播的那条 ✓）；#2 换条同样成功 ✓；#3~#6 预取 ✓；无异常 ✓。
普通影片详情页**回归** ✓：源 = HLS 5 档（1080→144，照常 `readyState=4` 起播 ✓）——
⚠️ 我实测的这条页面本身没有 mp4 形态 🔍（所以是 no-op ✓，别的页面若有 mp4 会变成 mp4 优先，与 App 一致 ✓）。

**语法复验**：把 `index.html` 内联脚本抽出来跑 `node --check` —— **经典脚本 & ESM 都过** ✓（219,079 字符，退出码 0）；
`sim/server.mjs` 同样 ✓（退出码 0）。

### ❗报告（**app 侧问题 / sim 侧没动** ✗，等拍板 ✓）
- **`/shorts/newest?page=N` 翻页无效** ✗ —— **破缓存重测**（page=1/2/3 + 随机参数）：45 条 **hash 完全相同** ✗。
  → `xhamster.dart` 的 `_xhMoments(p>1)` 和 `ShortsFeedPage._loadMore` 拿到的**还是同一批 45 条** → 去重后 `fresh` 为空 → `_done=true`
  → 用户要的「划到尾部自动续拉」**实际拿不到新内容** ✗（只能拿到同一批的洗牌）。
  对照：`/api/v1/moments?page=N` 翻页**有效** ✓（5 条/页，sim 现在仍用它做列表）
- `xhamster.dart` 的 `_xhShortsFrom` / `resetShortsRandom` 已**没人读** 🔍（`_xhMoments` 改走页面后不再用；`home_page.dart:164` 仍在调）
- 非短片详情页也走「mp4 优先」🔍（同一条 `srcs = _mp4` 逻辑）→ 若某页 HLS 有 1080p 而 mp4 只到 720p，会**降档**（仅提示，未核实到实例）
- `sim/tmp_xv1.html`（2026-10-01，**不是我建的** ✗）还留在 sim/ —— 要清我等指令 ✓

--- 追加（2026-10-03 · 工作区改动，**未提交未构建**）短片续拉换有效接口 + 预下载缓冲 5 条 + 撤诊断日志 ---
**A · 短片「第 2 页起」改走 `/api/v1/moments?page=N`** ✓（用户拍板 ✓；站点逻辑全在 `lib/sites/xhamster.dart` ✓）
- 依据（sim-dev 实测 ✅）：页面路径的 `?page=N` 是**假的** ✗ —— page=1/2/3（带随机参数也一样）返回的 **45 条 hash 完全相同** ✗ → 续拉永远同一批 → 去重为空 → 「划到尾没有新内容」✗；接口**是真翻页** ✓（5~6 条/页 ✓、无需 cookie ✓）
- 改法：`_xhMoments(page)` 拆两路 —— **第 1 页**仍旧页面 JSON（45 条 ✓ 用户已验收 ✓）；**第 2 页起** `'/api/v1/moments?page=$page'` ✓；新增 `_xhMomentsFromJson()` ✓（`items[]` → `pageURL`/`title`/`posterUrl|thumbUrl|imageURL|thumbURL|cover` ✓）—— 解析写法从 **`9806df8~1` 的 `lib/api.dart` 旧实现**恢复 ✓（不猜字段 ✓），旧实现已从工作区删掉 ✗
- **字段对齐（lead 点名要核 ✓）**：两条路产出的 6 项完全一样 → title / url（剥掉域名的站内路径）/ cover / `meta: ''` / `badge: ''` / `coverAspect: 3/4` ✓（`desc`/`tags` 都走默认 ✓）→ **同构 ✓**；⚠️ 历史实现里 `meta` 取 `landing.name`（作者名）✗ —— **故意不取** ✗：第 1 页那 45 条的 `meta` 就是空串 ✓，两批必须一致 ✓（以后要显示作者得两路一起改 ✓）
- 请求头：恢复 `_xhApi`（UA + `Accept: application/json` + `X-Requested-With` + 同源 Referer ✓，同样来自旧实现 ✓）—— 旧注释推断过「只带 UA 会被挡」🔍 ✓
- ❓ **风险（未证实）**：本机探测**不可用** —— 经代理连 `/shorts/newest` 都 **404** ✗（证明是我的出口/客户端被拒 ✗，不能说明接口死活 ✗）；sim 里那条是 **mock** ✗（`sim/index.html:2511`）→ **真机直连通不通只有装机才知道** ❓；不通就退回今天的行为（续拉空批次 → `_done=true` → 「划到尾」✗），不会坏成别的样子 ✓
**B · 单实例 + 预下载缓冲 5 条** ✓（用户拍板方向 ✓；**不做多实例** ✗）
- 新增 `lib/base/video_cache.dart`（**与站点无关** ✓ 所以进底座 ✓）：把窗口内**后面 5 条**的源**整份下到沙盒** ✓（先写 `.part`，整份下完才改名 `.mp4` ✓）→ 播放时把 `file://` 交给**同一个** mpv ✓（接线在 `shorts_feed_page.dart` 的 `_open` ✓）
- 目录 `getTemporaryDirectory()/kpxx_video_cache` ✓（tmp：不进备份、系统可清 ✓）· **单文件上限 32MB**（超了跳过 ✗）· **总量 320MB / 最多 24 个**（LRU，按 mtime ✓）· **过期 `.part` 1 小时**清 ✓ · **并发 2** ✓（留带宽给当前条 ✗）
- 行为：划 1 条 → `_primeWindow(5)` 重设窗口 → 补一条 ✓、划走那条**中止** ✓；**只有整份下完才用本地文件** ✓ → **不用**探 moov 位置 ✓（半截文件若 `moov` 在尾部会播断 ✗，直接回落在线 ✓ 并后台继续下 ✓）
- **只做直链 mp4** ✓（去掉 query 看 `.mp4` ✓）；**m3u8 跳过** ✗（HLS 要逐段下再合并 ✗，仍走在线播放 ✓ = 与今天一致 ✓）
- 全静默 ✓（失败/超限不抛错、不打扰界面 ✓）；代价 ❓：**没有任何诊断输出** —— 真机上「预缓冲有没有生效」只能看观感/流量 ✓
**C · 撤掉短片全量诊断日志** ✓（用户要求 ✓）
- `shorts_feed_page.dart`：删 5 处 `SiteErrorLog.log('短片', …)` ✓ + 只服务日志的局部变量 `_t0` ✓ + 只服务日志的内层 try/catch ✓ + 随之不用的 `import 'site_error_log.dart'` ✓
- `api.dart`：撤 `Api.category` 的 `[列表]` 诊断与 `isShortsCall` ✓，**恢复成直接 `return _ui!.category(...)`** ✓（为记日志加的 try/catch 一并撤 ✗）+ 去掉不再用的 import ✓
- **保留** ✓：`SiteErrorLog` 本类 ✓ · **`lib/base/fetch.dart` 3 个 catch 的公共错误日志** ✓ · 短片取源的 **20 秒 `timeout`** ✓（那是真修复 ✗ 不是日志 ✓）
- 核对：全 `lib/` 里 `SiteErrorLog.log(` **只剩 `lib/base/fetch.dart` 3 处**（77/103/152 ✓）；`error_log_page.dart` 的 `read/clear/path`（设置→诊断→错误日志入口 ✓）与类本身原样 ✓
**本轮 numstat**（`git diff --numstat`）：`lib/api.dart 8/24` · `lib/shorts_feed_page.dart 49/36` · `lib/sites/xhamster.dart 1421/1364` · `lib/base/video_cache.dart` 新文件 203 行（未跟踪 ✓）
**括号核对（Node + utf8 计数 ✓）**：`shorts_feed_page() 230/230 {} 60/60` ✓ · `api() 64/64 {} 34/34` ✓ · `video_cache() 121/121 {} 58/58` ✓ · `xhamster` 相对 HEAD 的**增量** `() +30/+30`、`{} +5/+5`、`[] +9/+9` **全对称** ✓（HEAD 自身 `(` 1090 vs `)` 1086 那 4 个差是**改前就有** ✓，不是本次引入 ✓）
⚠️ **本轮新踩的坑（写死 ✓）**：**`lib/sites/xhamster.dart` 的行尾是 `\r\r\n`（CRCRLF）** ✗ —— ① `edit` 工具**多行锚点会匹配不上** ✓（单行锚点可以 ✓）；② PowerShell 数这个文件的行数/括号**不可信** ✗（同一文件 PS 报 2621 行、Node 报 1421 行；PS 还把它读成乱码 ✗）→ **正解 = 用 Node 脚本改 + utf8 计数核对** ✓（本次 A 就是这么改的 ✓，脚本与临时文件已删 ✓）

---
## 追加（2026-10-03 · **sim 侧第 2 轮 —— 用户拍板后**，工作区改动，**未提交未构建**）短片列表改「两段式」---
**用户拍板 ✓**：模拟器也改 ✓ —— 形态 = **第 1 页 = 页面 JSON（45 条）+ 第 2 页起 = `/api/v1/moments?page=N`（5~6 条 ✓）**
（依据 = 上一轮实测：`/shorts/newest?page=N` 翻页无效 ✗、moments 接口翻页有效 ✓）。

**`sim/index.html` 改动**
1. `xhMoments` 重写成两段式（`:2488`）：`p === 1` → 新增的 `xhShortsFirst()`（`:2544`，抓 `/shorts/newest`，
   解 `<script id='initials-script'>window.initials={…}` → `layoutPage.videoListProps.videoThumbProps`，
   **解不开就抛错** ✗ 不给假数据 ✓）；`p ≥ 2` → moments 接口（沿用原有映射 `parse` ✓）。
   → 列表页（`fetchList` 的短片分支 `:2272`）与瀑布流续拉（`feedLoadMore` `:4325`）共用它 ✓
2. **删掉为"moments-only"服务的整套机制** ✗（现在没必要 ✗）：随机起始页 1~48 · 并发抓 4 页 · 批次缓冲
   `xhMomentsBuf`/`xhMomentsBatchFrom`/`xhMomentsPending`（`viewList` 里那两行清理也跟着删 ✓）。
   「每次进来不一样」现在靠：**每批打乱** ✓ + 翻页换内容 ✓（第 1 页那 45 条本身是站点固定的一份，与 App 一致 ✓）
3. 页码改成**显式计数**：新增 `xhShortsPage`（`:2477`）—— 续拉从它的下一页接 ✓、成功才推进 ✓，
   列表里翻过页也不会重复拉同一页 ✓（旧代码给 `feedLoadMore` 传的是死值 `99` ✗）
4. `window.__shortsItems` 由"每批覆盖"改成「**第 1 页清空 + 之后累加**」✓ ——
   否则列表翻过页再点卡片进流，流里只剩最后一页那 5 条 ✗（旧注释里就写着这个坑 ✗）
5. ⚠️ **顺手修的一个真挂死**（本轮实测撞到 ✓）：`getHtml()`（`:817`）原来**没有超时** ✗ ——
   浏览器 `fetch` 本身不超时 ✗，中转一卡住 Promise 永不 settle → `__feedLoading` 一直 true →
   **本次会话再也续拉不了** ✗（实测撞到一次：续拉 40 秒不回来、日志也无报错行 ✓）。
   现加 **20 秒** AbortController 兜底 ✓（与 App 短片取源的 20 秒超时对齐 ✓）
6. `tmp_xv1.html`（2026-10-01，**不是我建的** ✗）**没动** ✗ —— 用户单独说删才删 ✓

**实测（8788，Edge headless + CDP；用户 8787 全程没碰 ✓）**
- 短片首屏 = **45 卡** ✓（`cards portrait shorts` ✓、`xhShortsPage=1`、缓存 45 ✓）
- 列表翻页（滚到底）：卡片 45 → **51** ✓、页码 → **2** ✓、日志 `短片 第 2 页：6 篇` ✓
- 瀑布流续拉（跳到最后一条触发）：**45 → 51 → 57**（每轮 +6 ✓）、页码 1 → 2 → 3 ✓
- 起播 ✓（`readyState=4`，源 = 详情页的**直链 mp4** `720p.h264.mp4` ✓；取源日志 #1~#4 全是"详情页 3 条" ✓）
- 暂停覆盖层：播放中 `fpause=0 fmeta=0` ✓ ／ 暂停 `1/1` ✓
- **多站回归**（`getHtml` 是全站共用的，必须回归 ✓）：首页 **14 站** ✓ · 51吃瓜 25 卡 ✓ · Pornhub 58 卡 ✓ ·
  XVideos 27 卡 ✓ · xHamster 影片 54 卡 ✓；**无未捕获异常** ✓ · 超时行 0 ✓
- 数据核对（CLI ✓）：moments 各页**互不重叠**（p1~p7 共 41 条全不同 ✓）、与首屏 45 条**零重叠** ✓
  → 续拉每页能真加 6 条 ✓（不会被去重吃掉 ✓）

**语法复验**：内联脚本抽出来 `node --check` → **退出码 0** ✓（经典脚本；`sim/server.mjs` 同样 0 ✓）
**净变化**：`sim/index.html` 本轮 **`+103 / −90`** ✓（第 1 轮 `+111 / −11` → 累计 `+214 / −101` ✓，`git diff --numstat` ✓）


--- 追加（2026-10-03 本次构建 1.0.12 —— 短片：翻页 + 预下载 + 清日志 + 模拟器）---
**A 短片翻页**（app-dev）：`xhamster.dart` 第 1 页仍走页面 JSON（45 条），第 2 页起走 `/api/v1/moments?page=N`；解析从旧版实现恢复；两批 Article 字段核对同构（meta 故意留空）。
**B 单实例预下载 5 条**（app-dev）：新增底座 `lib/base/video_cache.dart`（与站点无关）；播放仍是同一个 mpv，地址换 file://；划 1 补 1、滑走即中止；32MB/文件、320MB/24 个 LRU、并发 2；只做直链 mp4；**整份下完才改名 .mp4、只播完整文件**（因此无需探测 moov）。
**C 撤诊断日志**（app-dev）：短片 [短片] 与 api 的 [列表] 全撤；SiteErrorLog 公共函数与设置入口保留；全 lib 只剩 fetch.dart 3 处站点错误日志；短片 20 秒 timeout 保留。
**D 模拟器两段式**（sim-dev）：首屏 45 条（页面 JSON）+ 翻页 moments；删旧 moments-only 机制；顺手修 getHtml 无超时的真挂死（加 20 秒）。

**新坑（写死）**：`lib/sites/xhamster.dart` 行尾是 **CRCRLF** —— 多行锚点匹配不上、PowerShell 行数/括号不可信 → 改它**只能用 Node + utf8 计数**。
**待验证（已部分回答 ✓ 见下方本轮）**：`/api/v1/moments` 在真机直连下**是通的** ✓（1.0.12 实测 page:2 成功 5~6 条 ✓）；仍待查的是 **page:3 为什么失败/空** ❓

--- 追加（2026-10-03 · 工作区改动，**未提交未构建**）短片「划 5 个就到底」修复 + page:3 归因 ---
**用户实测（1.0.12）**：「一直下滑会触底，划了 5 个左右就划不下去了」✗ —— 现在能定性了 ✓：
- 1.0.12 里 `_page` 从 **1** 起步 ✗（`shorts_feed_page.dart:72`）→ **首次请求就是 `page: 2`** ✗ → 页面 JSON 那批 **45 条永远拿不到** ✗；
  `page:2` 走 moments ✓（5~6 条 ✓，**说明接口在真机直连下是通的** ✓✓）→ 列表 = **1 + 5~6 = 6~7 条** ✓ → 划过就到底 ✓ = 用户说的"5 个左右" ✓✓
- 之后 `page:3` 失败/空 ✗ → `catch (_) { _done = true; }` ✗ → **本次进入永久到底** ✗（瀑布流页没有下拉刷新/重试 ✗；网格有 ✓ `home_page.dart:815` ✓）
**修（三处，都在本轮工作区 ✓）**：
1. `shorts_feed_page.dart:77` `_page = 0` ✓ → 首次请求 **page 1** = 页面 JSON = **45 条** ✓（列表立刻有 45 条可划 ✓，即使后面接口全挂 ✗ 也够用 ✓）
2. `shorts_feed_page.dart:244-251` **"到底"与"失败"分开** ✓：空批次 → `_done` ✓（真到底 ✓）；抛错 → 只标 `_tailFailed` ✓ **不置 `_done`** ✗ → 再滑一下就自动重试 ✓
3. `shorts_feed_page.dart:406-417` 续拉失败时在暂停层多一个 **↻ 重试** 按钮 ✓（复用 `_RoundBtn` ✓，X 右边 `left: 60` ✓，同样只在暂停时可见 ✓）
   站点层配合（**只改站点文件** ✓）：`xhamster.dart:332` 接口**空批次 `return const []`** ✓（交给界面判"到底" ✗）——原来**抛错** ✗ 会被界面当成"可重试" ✗ → 对本来就空的页会**无限重试** ✗；**网络/被挡这类真失败仍由 `_f.text` 抛错** ✓ → 仍可重试 ✓✓（两者分得开 ✓）
**page:3 为什么失败/空 ❓（不加日志 ✗，靠读代码推理 ✓）**：
- ✅ **已排除**：`_page` 记账 ✗（`_page++` 只在成功后 ✓，2→3 正确 ✓）、并发双发 ✗（`_loadingMore` 挡住 ✓）
- ⚠️ 活着三个候选：① **接口第 3 页本来就空**（池子有限 ✓）② **page3 与 page2 内容重叠** ✗ → 去重后 `fresh` 空 ✓ → 外表看就是"到底" ✓ ③ **被限流/被挡** ✗（该接口单次 **2~5s** ✓ 慢 ✓，页面路径偶发失败率也高 ✓）
- ✗ 观测到的**放大器**：不管哪一种，1.0.12 都把它变成"永久到底" ✗（已由修 2 治掉 ✓）
- 待 sim-dev 用**能通的出口**探 3 件事 ✓（**不带日志** ✗）：① `?page=3` 的 status / `items.length` / 首尾 `pageURL` ✓ ② page2 ∩ page3 的 url 重叠 ✓ ③ page2→3→4 连击（<1s 间隔）是否 403/429/空 ✓
**主方案（2026-10-03 晚 · sim-dev 定论后 ✓）—— 翻页改「路径式」** ✓（接上面 1./2./3. ✓）
- 事实（sim-dev ✅[实锤]）：`?page=N` 参数**被站点忽略** ✗（page=1/2/3 返回同批 45 条 ✗）；站点自己在 JSON 里给了分页模板
  `paginationProps.pageLinkTemplate = "…/shorts/newest/{#}"` ✓ → **真翻页是路径式** ✅：`/shorts/newest/2`、`/3` = **HTTP 200** ✓ · **45 条/页** ✓ · `lastPage=100` ✓ · 与第 1 页**零重叠** ✓
- 改法：`xhamster.dart:315-321 _xhMoments()` → page 1 = `/shorts/newest` ✓、page ≥2 = `/shorts/newest/$page` ✓；
  新增 `:323-338 _xhMomentsPage()` 统一"抓 + 解析"（**复用 `_xhMomentsFromHtml`** ✓，两页同一套结构 ✓）；
  `:304 _xhShortsLast` + `:269-272` 从页面 JSON 里抓 `"lastPage":(\d+)` ✓ → `page > last` 直接**返回空** ✓（界面判"到底" ✓，不盲试第 101 页 ✗）
- **头部只用 `_xhDesk`**（桌面 UA ✓）：sim-dev 逐头隔离实测 —— 带 `X-Requested-With: XMLHttpRequest` → **404** ✗、去掉 → 200 ✓
- **撤掉的东西** ✗：整条 moments 路（`_xhMomentsFromJson()` **已删** ✓）+ `_xhApi` 常量（含那个惹 404 的头 ✗）→ 本轮 numstat **净删** ✓
- page:3 的归因 ⇒ **候选 ③（被挡/限流）最像** ✓：同一套头，第 2 页成功 ✗、第 3 页 404/失败 ✓ → 说明站点对 `/api/` 的判定是**条件性/偶发**的 🔍 —— 反正**主方案已不再走那条路** ✓
- 顺带：**这个文件的行尾被 git 往返正常化了** ✓ —— 上轮记的 CRCRLF ✗ 现在已是**普通 CRLF** ✓（`git diff` 那句 LF→CRLF 警告即由此 ✓）；本轮的改动脚本已改成**自动探测行尾** ✓
- ⚠️ 仍要**真机验** ✓：路径式 45 条/页 在真机直连下的稳定性（sim-dev 出口测到 200 ✓；用户网络此前对 `/api/` 有过整段失败 ✗ —— 那条路已撤 ✓）
**numstat / 括号（Node + utf8 ✓）**：`lib/shorts_feed_page.dart 30/4`（`() +10/+10` ✓、`{} +1/+1` ✓；当前 **240/240** · **61/61** · **21/21** 全配平 ✓）· `lib/sites/xhamster.dart **34/63**`（净删 ✓；`()` 1120→1102 = **-18/-18** ✓ 对称 ✓、`[]` 99→89 = -10/-10 ✓、`{}` 62/62 ✓；该文件 `(` 比 `)` 多 4、`[]` 多 2 是 **HEAD 就有** ✓ 与本轮无关 ✓）


--- 追加（2026-10-03 本次构建 1.0.13 —— 短片翻页彻底修好）---
**sim-dev 探测实锤**：站点分页模板是 **路径式**（第 1 页 JSON 的 `paginationProps.pageLinkTemplate = …/shorts/newest/{#}`）；`?page=N` 参数被忽略（返回同批 45 条）；`/shorts/newest/2` = 200、45 条、currentPage=2、lastPage=100、与第 1 页零重叠。
**另一实锤**：`/api/v1/moments` 本身没死，是 **`X-Requested-With: XMLHttpRequest` 这个头把它惹成 404**（逐头隔离：去掉即 200）。
**修（app-dev）**：`xhamster.dart` page≥2 改走 **`/shorts/newest/$page`**（复用 `_xhDesk` 头），**整条 moments 路 + `_xhApi` 已撤**；新增 `_xhShortsLast` 抓 `lastPage` 避免盲试；
`shorts_feed_page.dart`：`_page = 0`（**首次续拉 = page 1，45 条打底**）+ **失败不再置 `_done`（只标 `_tailFailed`）** + 暂停层加 **↻ 重试** 按钮。
**行尾更正**：`lib/sites/xhamster.dart` 经 git 往返后已恢复**普通 CRLF**（不再是 CRCRLF），写它的脚本要**自动探测行尾**。

--- 追加（2026-10-03 · 工作区改动，**未提交未构建**）短片体验两处：换源遮罩（已做 ✓）+ 入口预热（待拍板 ✗）---
**用户实测 1.0.13 报的两条体验问题**（翻页/续拉他这次没抱怨 ✓ = 路径式那套修好了 ✓）：
**① 已做 ✓：换源遮罩**（`shorts_feed_page.dart:355-390`）—— 一层遮罩同时治两个现象 ✓：
- 「划到下一条，先看到**上一条的帧**约 1.2 秒」✗ 的根因：`kp.open()` 换源用的还是**同一个** `Video`/controller ✓
  （**不能重建** ✗ —— 重建会让别处持有的旧实例失效，历史坑 ✓）→ 纹理里**仍是上一帧** ✗；
  查证：`_open()`（`:170-186`）里 **没有任何清画面动作** ✓，`Video` 也是同一个 controller ✓。
- 「点卡片进瀑布流要等几秒才有画面」✗：就是**同一段等待期**（抓详情页 + mpv 起播）✓。
- 做法：当前页 Stack 里加一层遮罩 ✓ = **黑底 + 本条封面 `FetchedImage` + 转圈** ✓，判据 `position > Duration.zero` ✓
  —— `KpPlayer.open()` 会先把 position 清 0（`player_widget.dart:256-262` ✓），新源真的走起来才 > 0 ✓ → 到点自动撤 ✓。
- ⚠️ 两个**必需项**（缺一个就出事 ✗）：**`IgnorePointer`** ✓（否则遮罩把点击/竖滑全吃掉 ✗）、
  **黑底** ✓（封面图本身也要下载，没有黑底旧帧会从透明处透出来 ✗）。
**② 待拍板 ✗：入口预热**（在"点卡片那一刻"就开始抓详情页）—— **只给方案，未动代码** ✓：
- 现状：`home_page.dart:1161` 只传 `items: <Article>[article]`（1 条 ✓）→ 进页面 `initState` → `_open(0)`
  → **才**开始 `_sourcesOf(0)` 抓详情页（1~2 秒 ✓）→ 再 `kp.open()` 开始下媒体 ✗ → 累计几秒 ✓
- 方案：网格的短片分支（`home_page.dart:1154-1167` ✓）在 push 前**预热** `api.detail(article.url)` ✓；
  ⚠️ 但页面里的 `_srcCache` 是**页内私有** ✗ → 要落地需一个**共享的 detail→sources 缓存**（跨 3 个文件 ≈15 行 ✗）
  → 属"动到别处"，**先不动** ✗ 等用户拍板 ✓。收益 ≈ 与 push 动画重叠的 **0.5~1.5 秒** ✓；**请求数不增加** ✓（页面本来也要发这一次 ✓）。
- **明确不需要做** ✗：把预下载窗口**含当前条** —— 当前条的**源还没解析出来** ✗，而 mpv 在 `open()` 之后**本来就在下** ✓
  → 预下载它只会**重复占带宽** ✗（`_primeWindow` 显式排除当前条是对的 ✓）。
- 另一条可选（**未动** ✗，属共享播放器 ✗）：用 `NativePlayer.setProperty` 调 mpv 的起播参数
  （如 `demuxer-readahead-secs` / `cache-pause-initial` ✓）能再挤掉一点初始缓冲 ✓ —— 但那动的是 `player_widget.dart`（详情页/全屏共用 ✗）→ 等拍板 ✓。
**numstat / 括号（Node + utf8 ✓）**：`lib/shorts_feed_page.dart 36/0` ✓（`()` **256/256** · `{}` **63/63** · `[]` **22/22** 全配平 ✓；行数 559→595 ✓）
**过程失误（自catch ✓）**：写这段时一个 `edit` 的 `new_string` 忘了把锚点 `
--- 追加（2026-10-03 本次构建 1.0.14 —— 短片起播手感）---
**用户真机反馈（1.0.13）**：①点卡片进瀑布流要好几秒才播 ②划到下一条会先看到上一条的帧约 1.2 秒。
**① 换源遮罩**（shorts_feed_page）：切条时盖「黑底 + 本条封面 + 转圈」，用 `position > 0` 自动撤（`KpPlayer.open()` 会把 position 清 0，是可靠判据）。
**② 入口预热**：新增底座 `lib/base/source_cache.dart`（url → Future<源> + 在途去重 + LRU 80 + 失败不进缓存）；「怎么取源」由调用方传闭包 → 底座不认识任何站点；`home_page` 在 push 之前就取源（与转场重叠，请求数不增）；页内私有缓存已删。
**③ 只给短片实例调 mpv 起播参数**：`demuxer-lavf-analyzeduration` 5→2、`demuxer-lavf-probesize` 5M→1.5M、`cache-pause-initial=no`；为此在 `player_widget.dart` **只新增**一个方法 `setMpvOptionQuiet`（逐层 try/catch 静默失败），**未改任何共用配置**。
⚠️ 待验证：设参数时 `_p.platform` 若仍为 null → 参数静默失效（装机若起播没变快，先查这里）。
**④** 清掉 `xhamster.dart` 两处过时注释（短片已改路径式，旧 moments 描述作废）。

## 八、当前待办` 带回去 ✗（还多留了一行孤立的反引号 ✗）→ 当场读回发现并补回 ✓（教训：**替换标题当锚点时，new_string 必须原样含回标题** ✗）。

--- 追加（2026-10-03 · 工作区改动，**未提交未构建**）用户拍板的 ②③④（① 换源遮罩见上一条）---
**② 入口预热** ✓（省 0.5~1.5 秒 ✓、**请求数不增** ✓）
- 新增 `lib/base/source_cache.dart`（**与站点无关** ✓ 底座 ✓，51 行）：`url → Future<List<String>>` + **在途去重** ✓ + LRU 上限 80 ✓ + **失败不进缓存** ✓（失败即清，页面再滑可重试 ✓）；"怎么取源"由调用方传**闭包** ✓（底座不认识任何站点 ✓）
- `home_page.dart:1160-1163`：短片分支 **`push` 之前**就 `SourceCache.i.get(article.url, …)` ✓（与转场动画重叠 ✓）
- `shorts_feed_page.dart:149-158`：`_sourcesOf` 改读共享缓存 ✓；**页内私有 `_srcCache`/`_fetching` 已删** ✓（原 `:65-67`）→ 同一 url 只飞一次 ✓；`_precache` 里那句 `_srcCache.containsKey` 判断**一并删掉** ✓（共享缓存自己判 ✓）
**③ 只给短片实例调 mpv 起播参数** ✓（少等初始缓冲 1~3 秒 ✓）
- 位置：`shorts_feed_page.dart:169-174` 建 `KpPlayer(bufferMb: 64)` 处 → 调新方法 `_tuneMpvStartup(created)` ✓（定义在 `:188-198` ✓）
- 设了什么（都只碰"**起播门槛**"，**没动**解码/硬解/网络层 ✗）：
  · `demuxer-lavf-analyzeduration` = **2.0** ✓（ffmpeg 探测"这是什么流"的最长时间，默认 5 秒 ✗）
  · `demuxer-lavf-probesize` = **1500000** ✓（探测字节数，默认 5000000 ✗）
  · `cache-pause-initial` = **no** ✓（不等缓存填满才开播 ✓；mpv 默认本就是 no ✓，这里显式钉住 ✓）
  → 三个名字**有旁证** ✓：社区"快启动"配置用的正是同一组（`--cache-pause-initial=no` / `--demuxer-lavf-probesize=200000` / `--demuxer-lavf-analyzeduration=1` ✓，见 Reddit mpv config）；**我取值比它保守** ✓（宁可慢一点也别卡 ✗）
- ⚠️ 为此在 `player_widget.dart:268-278` 给 `KpPlayer` **新增**一个方法 `setMpvOptionQuiet(name, value)` ✓（`_p.platform as NativePlayer` → `setProperty` ✓；逐层 try/catch + `catchError` ✓ → **失败静默** ✗）—— **只加方法，没改任何共用配置/行为** ✓；之所以必须动这个文件 ✗：`KpPlayer` 把 media_kit 的 `Player` 藏成**私有** ✗ → 短片页够不到它 ✗
**④ 清过时注释** ✓（`lib/sites/xhamster.dart`）：`:130` 与 `:1358-1364` 那两处「短片走 `/api/v1/moments`」**已改成现状** ✓（页面 JSON ✓ + **路径式** `/shorts/newest/{N}` ✓、45 条/页 ✓、`lastPage=100` ✓、`?page=N` 被站点忽略 ✗、旧接口已整条撤 ✗）；`:234`／`:311` 两处**上轮已改好** ✓（标为"旧路…已撤" ✓）→ 这轮无需再动 ✓
**numstat / 括号（Node + utf8 ✓）**：`home_page.dart 9/0`（677/677 ✓）· `player_widget.dart 12/0`（840/840 ✓）· `shorts_feed_page.dart 65/21`（252/252 ✓）· `lib/base/source_cache.dart` **新文件 51 行**（15/15 ✓）· `xhamster.dart 8/5`（1102/1098 的 4、89/87 的 2 都是**改前就有** ✓）→ 五个文件括号**全部对称/余额 0** ✓
**没验证的** ❓：三个 mpv 参数在**真机 libmpv** 上是否真被接受、实际省几秒（本机无 Flutter SDK/无真机 ✗）→ 装机看"起播是否更快"即可；**就算某个名字不认也不会坏** ✓（静默忽略 ✓ 播放不受影响 ✗）

## 八、当前待办

- [ ] **详情页播放器置顶**：代码已改好 ✓（固定顶部 + 下方单独滚动，括号校验通过）**未提交/未推** ✗
- [ ] **桌面 ipa 落后**：桌面是 **1.0.1** ✓；**1.0.2**（含"加载失败提示不消失"修复）**已发 Releases 但未下到桌面** ✗
- [ ] （可选）Actions artifact 名是否带版本 —— 现仍 `kpxx-ipa`，用户未表态
- [x] ~~**（sim 报）短片翻页拿不到新内容**~~ → **已定方案 ✓**：`/shorts/newest?page=N` 实测返回**同一批 45 条** ✗ →
  改「第 1 页 = 页面 JSON（45 条）+ 第 2 页起 = `/api/v1/moments?page=N`（5~6 条 ✓）」；
  **sim 侧已改完并实测 ✓**（45 → 51 → 57 ✓，见下方 sim 追加）；**App 侧待 app-dev 按同一形态改** ✓
- [ ] （清理）analyze 的 warning/info：`unused_import` ×13 · `unused_element` ×8 · `annotate_overrides` ×52（不拦构建 ✓）

## 九、最近成功构建
`0897af6` 批 2 三站状态机 → success ✓（Release `v2026.10.03-0520`，附件 `kpxx-1.0.1.ipa` ✓）
`f128439` 播放器修复 → success ✓（版本 **1.0.2** ✓）
桌面：`kpxx.ipa` = **1.0.1**（16,369,038 字节 @ 13:21:34）⚠️ 待更新

---

## 十、从探测到显示的完整流程（**通用 SOP** ✓ —— 加新站 / 修老站都照这个走）

> ### ⚠️ 铁律：写代码时，**站点必须是独立的** ✗
> 每个站的**分类表 / URL 拼接 / 解析 / 筛选 / 清单 / 状态**一律写在**它自己的 `lib/sites/<站>.dart`** 里 ✓。
> **不许**把站点逻辑塞进 `api.dart` / `home_page.dart` / 底座 ✗（历史上踩过：底座里按模板 if 分叉、公共页面里塞单站弹窗 ✗）。
> **底座只放"与站点无关"的东西** ✓：网络层 / 文本工具 / 模型 / 播放器 / 图片 / 背景 / 设置 / 记录 / 卡片网格 ✓。

### 第 0 步 · 准备
确定：**目标站** + **内容类型**（视频列表 / 图文帖 / 合集 / 短剧 / 小说）✓

### 第 1 步 · 探测（只读 ✓，派 `recon` 子智能体）
**打开真实页面核实** ✓ —— 每条结论带证据；**禁止凭印象写选择器** ✗。
要摸清：
| 摸什么 | 具体项 |
|---|---|
| 列表页 | URL 形态、分页怎么拼、卡片容器选择器、每张卡的标题/链接/封面/时长/角标取哪个节点 |
| 分类 | 分类 key 与显示名、**是否多级**（子分类）、URL 拼接规则 |
| 筛选器 | 有哪些维度（排序/日期/时长/标签/明星…）、参数怎么进 URL |
| 搜索 | 路径形态、分页规则、是否需要原文本编码 |
| 详情页 | **播放源怎么拿**（`.dplayer[data-config]` / 内嵌 JSON / 加密接口）、**Referer 要求**、多集/合集怎么表示 |
| 反爬 | 特定 UA / Referer / 签名 / AES ✓ |

结论口径：✅[实锤]（看过原文/实测）· 🔍[推断]（附依据）· ❓[未知]（**不许猜着写** ✗）

### 第 2 步 · 定**站点档案**（`SiteEntry`，写在**自己的站点文件**里 ✓）
字段：名字 / `SiteTemplate` / `hosts`（域名，用于轮换与 Referer ✓）/ `categories`（含子分类 ✓）/
`iconUrl` / `color` / `portraitCovers`（竖版封面 ✓）/ `showRelated`（相关文章 ✓）/ `filters`（本站筛选表 ✓）
→ 写成 `const SiteEntry kSiteNN = SiteEntry(…);` ✓（**不要**再往 `sites.dart` 里塞站点数据 ✗）

### 第 3 步 · 写**站点类**（`class XxSite extends SiteUi` ✓）
- **必须实现 5 个分发方法**（并集签名 ✓）：`category` / `home` / `tag` / `search` / `detail`
- 本站专属**清单**（分类表/明星表/筛选表）与**状态控制器**也放这里 ✓
- 只用到 `Color` 时用 `import 'dart:ui' show Color;` ✓（**别 import material** ✗ —— 会带 `Element`/`Text`/`Key` 撞名 ✓）
- html/dom 一律 `as dom` ✓

### 第 4 步 · 覆写**站点事实**（`SiteUi` 的 13 条 ✓）
**只覆写本站有差异的那几条** ✓，其余走默认（**默认 = 无该特性** ✓）。
不知道覆写哪条 → 直接看**页面上的表现**：要不要瀑布流（`masonry`）/ 竖版明星卡（`portraitStarCards`）/ 明星筛选行（`hasStarFilterRow`+`starRowKind`）/ 短片路径（`isShortsPath`）/
点卡片去哪（`specialTap`）/ 分组分类（`hasCatGroups`）/ 筛选行（`hasFilterRow`+`showsFilterRow`）/ 明星 tab（`isStarTabKey`+`hasStarTab`+`starUsesExtra`）/ 自己解析播放源（`sourcesFromHtml`）✓

### 第 5 步 · 接入汇总
1. `sites.dart` 的 `kSites` 里**加一行** `kSiteNN` ✓
2. 若用了**新模板** → 加 `SiteTemplate` 枚举值 ✓ + **`api.dart` 的 `ui` getter 加一个 case** ✓
   ⚠️ 这是**唯一**允许的"模板→实例"选择点 ✓（`api.dart` 里不该再有别的 `case SiteTemplate.*` ✗）

### 第 6 步 · 显示元素（**按第十一节的表 ✓**）
卡片要哪些字段 / 详情页要哪些 / 播放源怎么来 —— 都在第十一节逐站列着 ✓

### 第 7 步 · 验证
`sim`（端口 8787，`?site=N` ✓）验解析 → **真机**验列表 / 搜索 / 详情 / 播放 ✓
⚠️ **选择器写错不会报错** ✗ → 只会"列表空 / 黑屏"；出问题看 **设置 → 诊断 → 错误日志** ✓

### 第 8 步 · 构建
改 `lib/app_version.dart` 的 `kAppVersion` **+1** ✓ → **用户说「构建」** → 推送 → CI → 下到桌面 ✓

### 三秒钟判断"这行代码该写在哪"
- **只有这个站才有**（出现站名 / 站点路径 / 站点字段）→ **站点文件** ✓
- **每个站都要做的通用动作**（联网 / 解析通用格式 / 播放 / 卡片布局）→ **底座** ✓
- 拿不准 → 看它**会不会因为换站而不同** ✓：会 = 站点文件 ✓，不会 = 底座 ✓

## 十一、各站显示元素（**从代码自动抽取，非手工整理** ✓）

> 下表由脚本扫 `lib/sites/*.dart` 生成 ✓：`SiteEntry` 数 = 该文件覆盖几个站；"覆写的站点事实" = 它重写了 `SiteUi` 的哪些方法 ✓（没列的走默认值 = 无该特性 ✓）

| 文件 | 站名 | 模板 | 站点数 | 域名 | 覆写的站点事实 | 卡片额外元素 |
|---|---|---|---|---|---|---|
| `hanime1.dart` | Hanime1 | `hanime1` | 1 | `'hanime1.me'` | （全默认） | badge · series/集数 |
| `huangguo.dart` | 黄果短剧 | `huangguo` | 1 | `'huangguoai.com'` | sourcesFromHtml | badge · series/集数 · lazyUrl(合集) · 加密接口 |
| `kmsvip.dart` | 快猫 | `kmsvip` | 1 | `'kmsvip.xyz'` | （全默认） | badge · series/集数 · 加密接口 |
| `madou.dart` | 麻豆社 | `madou` | 1 | `'madou.club'` | （全默认） | series/集数 |
| `pektino.dart` | Pektino | `pektino` | 1 | `'pektino.com'` | （全默认） | coverAspect · badge · series/集数 · 加密接口 |
| `porna.dart` | 91porna | `porna` | 1 | `'91porna.com'` | （全默认） | badge · series/集数 · 加密接口 |
| `pornhub.dart` | Pornhub | `pornhub` | 1 | `'cn.pornhub.com'` | specialTap · showsFilterRow · isStarTabKey | coverAspect · badge · series/集数 |
| `wordpress.dart` | 51吃瓜 | `wordpress` | 5 | `'51cg1.com'` | （全默认） | series/集数 · lazyUrl(合集) · 加密接口 |
| `xhamster.dart` | xHamster | `xhamster` | 1 | `'tw.xhamster.com'` | isShortsPath · specialTap · showsFilterRow · isStarTabKey | coverAspect · badge · series/集数 · 加密接口 |
| `xvideos.dart` | XVideos | `xvideos` | 1 | `'www.xvideos.com'` | specialTap | badge · series/集数 · 加密接口 |

**字段含义**（`SiteUi` 的 13 条站点事实 ✓）：
`masonry` 瀑布流 · `portraitStarCards` 明星卡用竖版 · `hasStarFilterRow` 明星 tab 有专用筛选行 · 
`starRowKind` 明星 tab 挂哪家的筛选行 · `isShortsPath` 哪些路径算竖屏短片 · `specialTap` 点卡片的去向（list/shorts/详情）· 
`hasCatGroups` 分组分类 · `hasFilterRow` 有筛选行 · `showsFilterRow` 哪类 tab 显示筛选行 · 
`isStarTabKey` 哪个 tab 是"明星" · `hasStarTab` 有明星 tab · `starUsesExtra` 筛选走 `extra` 参数 · 
`sourcesFromHtml` 自己解析播放源（默认 null = 走通用 `.dplayer` ✓）
