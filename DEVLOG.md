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

## 八、当前待办
- [ ] **详情页播放器置顶**：代码已改好 ✓（固定顶部 + 下方单独滚动，括号校验通过）**未提交/未推** ✗
- [ ] **桌面 ipa 落后**：桌面是 **1.0.1** ✓；**1.0.2**（含"加载失败提示不消失"修复）**已发 Releases 但未下到桌面** ✗
- [ ] （可选）Actions artifact 名是否带版本 —— 现仍 `kpxx-ipa`，用户未表态
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
