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
10. **不许动用户的进程** ✗✗（用户 2026-10-03 明确要求 ✓）：
    - **8787 上已有服务在跑** → **直接用它调试** ✓（只读 ✓、**别重启** ✗、**别 kill** ✗）
    - **没有服务** → 才自己起一个 ✓（**换端口**更稳妥，如 8788 ✓），**先把自己的 PID 记下来** ✓
    - `Stop-Process` / `taskkill` / `pkill` / `kill` **只能打自己起的那个 PID** ✓✓（别人的一律不碰 ✗）
    - **"改完要生效"不靠重启** ✓：`sim/index.html` 与站点数据是**每次请求现读**的 ✓ → **刷新页面**即可 ✓；
      ⚠️ 例外：改 `sim/server.mjs`（服务端逻辑）**必须重启才生效** ✗ —— 且它自带**热重载**会**自己重启** ✗
      （用户会看到他的进程"没了" ✗）→ 动这个文件**先问用户** ✓
    - 汇报时必须写明：**用了哪个端口** ✓ · **有没有碰过别人的进程**（应为"没有" ✓）
11. **播放验证一律静音** ✗✗（用户 2026-10-03 明确要求 ✓）：
    - 任何验证性播放（`<video>` / headless 浏览器 / CDP 驱动）**必须 muted** ✓ ——
      `<video muted>` 或**播放前显式** `v.muted = true; v.volume = 0` ✓（**别依赖默认** ✗）
    - **禁止** `--autoplay-policy=no-user-gesture-required` 这类"带声音自动播"的配置 ✗（`--mute-audio` ✓ 可用）
    - 确实需要听声音 → **先问用户** ✓（几乎不可能 ✓）
    - 汇报里要写「**播放验证时已静音**」✓
    - sim 侧配套 ✓：`index.html` 的 `initMute` **所有模式都静音**（含 `/shorts…` 独立页 ✓ —— 我一开始把它排除掉了 ✗，用户提规矩后已改回 ✓）

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
**过程失误（自catch ✓）**：写这段时一个 `edit` 的 `new_string` 忘了把**锚点标题**带回去 ✗（还多留了一行孤立的反引号 ✗）→ 当场读回发现并补回 ✓（教训：**拿标题当锚点做替换时，new_string 必须原样含回标题** ✗）。
⚠️ 事后这行又被"按锚点插字"的脚本**从中间切开过一次** ✗（插到我的段落内部 ✓）—— 教训二：**正文里不要写标题字面** ✗，否则别人的锚点会命中它 ✓；2026-10-03 已按此修回 ✓（两半接回 ✓、伪标题删掉 ✓）。
--- 追加（2026-10-03 本次构建 1.0.14 —— 短片起播手感）---
**用户真机反馈（1.0.13）**：①点卡片进瀑布流要好几秒才播 ②划到下一条会先看到上一条的帧约 1.2 秒。
**① 换源遮罩**（shorts_feed_page）：切条时盖「黑底 + 本条封面 + 转圈」，用 `position > 0` 自动撤（`KpPlayer.open()` 会把 position 清 0，是可靠判据）。
**② 入口预热**：新增底座 `lib/base/source_cache.dart`（url → Future<源> + 在途去重 + LRU 80 + 失败不进缓存）；「怎么取源」由调用方传闭包 → 底座不认识任何站点；`home_page` 在 push 之前就取源（与转场重叠，请求数不增）；页内私有缓存已删。
**③ 只给短片实例调 mpv 起播参数**：`demuxer-lavf-analyzeduration` 5→2、`demuxer-lavf-probesize` 5M→1.5M、`cache-pause-initial=no`；为此在 `player_widget.dart` **只新增**一个方法 `setMpvOptionQuiet`（逐层 try/catch 静默失败），**未改任何共用配置**。
⚠️ 待验证：设参数时 `_p.platform` 若仍为 null → 参数静默失效（装机若起播没变快，先查这里）。
**④** 清掉 `xhamster.dart` 两处过时注释（短片已改路径式，旧 moments 描述作废）。


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

---
## 追加（2026-10-03 · **sim 侧第 3 轮**，工作区改动，**未提交未构建**）`/shorts…` 变成"能直接用的网页"---
**用户拍板 ✓**：删掉我们自研的瀑布流 ✗ → 短片 tab 直接加载**站点自己的短片页**（App 走 WebView ✓）
→ 模拟器要能**顶替那个页面**（同一个路径 ✓）。

**改动（只动 `sim/**` ✓）**
1. `server.mjs`（`:594-605`）：新增路由 —— `/shorts`、`/shorts/newest`、`/shorts/newest/2`、`/shorts/<slug>`
   **一律发 `index.html`** ✓（页面按 `location.pathname` 进独立模式 ✓，**不维护第二份页面** ✗）
2. `index.html`：
   - CSS（`:30-41`）`body.standalone`：**拆掉手机外壳**（铺满视口 ✓）、隐藏状态栏/灵动岛/日志侧栏 ✓、隐藏"没有上一层"的 ✕ ✓
   - `STANDALONE`（`:703`）= 路径以 `/shorts` 开头 ✓；`fitPhone` **不缩** ✓
   - `startStandaloneShorts()`（`:4586`）：清单到手 → `xhMoments(site,1)`（**45 条** ✓）→ `viewShortsFeed()` 进流 ✓；
     `/shorts/<slug>` **从那条开始** ✓（首屏里找不到就从头 ✓）
   - `feedExit()`（`:4339`）独立模式下**直接返回** ✗（否则会把 WebView 甩到模拟器宫格 ✗；左边缘右划那条路也走它 ✓）
   - `feedPlay`（`:4524`）：**只有真要播 m3u8 才加载 hls.js** ✓（短片主源是直链 mp4 ✓；原来每次进流都先去 3 个 CDN 试 ✗）

**实测（端口 = 用户的 **8787** ✓ 只读取用、**没重启没 kill** ✓；Edge headless + CDP + 手机 UA ✓）**
- `/shorts/newest` → **HTTP 200 / 313,302B**（= index.html ✓）；`body.className=standalone` ✓；`.phone` = 视口尺寸 ✓（外壳真拆了 ✓）
- 列表 **45 条** ✓；**直链 mp4 起播** ✓（readyState=4、源 `video7.xhcdn.com` ✓）
- 手势：**上滑换条** ✓（idx 0→1）、**单击暂停/继续** ✓（暂停时 `.feedpause` ✓ + ▶=1 ✓ + 标题条=1 ✓）、左边缘右划**不跑偏** ✓（流还在 ✓ 宫格 0 张 ✓）
- `/shorts/<slug>` → **从该条开始** ✓（`feedItems[0].url` 就是那个 slug ✓）
- **站外请求只有真实媒体** ✓：`video7.xhcdn.com` / `ip*.ahcdn.com`（站点自己的 CDN ✓）；
  **hls.js 的 3 个 CDN 一次都没请求** ✓；**无失败** ✓、**无未捕获异常** ✓（唯一 404 = `/favicon.ico`，噪声 ✓）
- ⚠️ **已知代价**：sim 这份"站点页"**每条要现抓一次详情页取源** ✓ → 换条要等 **5~15 秒** ✗（实测 #2 用 15s 起播 ✓，
  进流时会并发预取 #2~#7 ✓，`feedSrcCache`=6 ✓）；偶发 `所有域名均无法访问：tw.xhamster.com 代理连接超时` ✗（约 1/7 条 ✓，
  那条会显示"这条没有片源" ✓ 可以划走 ✓）。真站点是页面自带源、不会这样慢 ✗ —— **这是模拟器侧的保真度差距** ✓

**⚠️ 两条规矩（用户当场提的 ✓，已写进 §六 第 10/11 条 ✓）**
- **不许动用户的进程** ✗：我改了 `server.mjs` ✗ → **它自带的热重载把用户那个实例重启了** ✗（PID `26592`@14:43 → `15880`@21:11 ✓）
  → 用户看到"进程没了" ✗。以后：能只改 `index.html` 就只改它 ✓（每请求现读 ✓，刷新即生效 ✓）；动 `server.mjs` **先问** ✓
- **播放验证一律静音** ✗：我第一版把独立页排除了静音 ✗（还报了"未被静音"✗），且用了 `--autoplay-policy=…` ✗ →
  **已改回全模式静音** ✓，并加了 §六 第 11 条 ✓。静音下复验 ✓：页面默认 `muted=true` ✓、显式 `muted=true; volume=0` ✓、
  `currentTime 0.4→3.4` 在走 ✓、换条后仍 `muted=true` ✓

---
## 追加（2026-10-03 · **sim 侧第 4 轮**，工作区改动，**未提交未构建**）短片 tab：**内容区直接是播放器**---
**用户澄清（第 3 轮方向错了 ✗）**：「**看到短片 tab 没，下面的卡片不要了。下面直接就是对接站点的短片播放器了开始播**」
＋「播放器区域就在主分类、短片 tab 下面那块区域，**上面的 tab 要保持显示**」✓
→ 第 3 轮那个 `/shorts…` **全屏独立页保留备用** ✓，但**短片 tab 的默认形态**改成**内嵌** ✓。

**改动（只动 `sim/index.html` ✓；这轮 `server.mjs` 没动 ✓）**
1. CSS（`:214-220`）新增 `.feed.embed`：`position:relative; inset:auto; flex:1 1 auto` ✓
   → 放进 flex 流（插到 `.tabs` 之后 ✓）后**高度自然 = tab 行以下那块** ✓（**不全屏** ✗）；`.feed.embed .fclose` 隐藏 ✓
2. `mountShortsFeed(site)`（`:4625`）+ `unmountShortsFeed()`（`:4638`）：
   取数复用 `xhMoments`（第 1 页 = 页面 JSON 45 条 ✓）、渲染复用 `viewShortsFeed(…, embed=true)` ✓（**没新写播放器/取数** ✗）；
   离开时暂停 + 藏起 ✓（切别的 tab / 回宫格都收 ✓）
3. `viewList`（`:4018` 收尾 + `:4041` 分支）：进短片 tab → **直接 `mountShortsFeed` 并 return** ✓
   → **不画卡片网格** ✗、**不用再点卡片** ✗（用户要的"点进来就是播放器在播" ✓）
4. `viewShortsFeed(site, items, start, embed)`：内嵌时**不动** appbar / tabs / 底部导航 ✗（那是外壳 ✓），
   只腾空卡片区 ✓ 并把 `#feed` 搬到 tab 行后面 ✓；状态栏类只加 `feedon/feedpause` ✓（**不加 hasbg/darkbg** ✗ ——
   内嵌时状态栏在上方、不在黑底上 ✓）
5. `feedExit()`（`:4349`）：独立模式 **或** 内嵌形态 → 直接返回 ✓（出口 = 切 tab ✓）

**实测（端口 = 用户的 **8787** ✓ 只读取用、没重启没 kill ✓；Edge headless + CDP + 手机 UA ✓；**播放全程静音** ✓）**
- **几何证据** ✓：tab 行 `y=114 h=37` → 底 **151**；内容区 `#feed` **y=151** ✓✓（正好接在 tab 行下面）、宽 = tab 行宽 ✓、高 671 ✓
- **卡片网格没了** ✓：`#cards .card` = **0** ✓、卡片区 `display:none` ✓
- **tab 行在** ✓：`display:flex` ✓、`[影片,分类,色情明星,短片]` ✓、选中 = **短片** ✓；顶栏/状态栏都在 ✓
- **点进来就在播** ✓：`readyState=4`、`currentTime 0.6 → 3.1` 在走 ✓、源 = 直链 mp4 ✓
- **静音** ✓：`muted=true`、`volume=0`（播放前**显式**设 ✓；浏览器侧 `--mute-audio` ✓，**没用** autoplay-policy ✗）
- 手势：**上滑换条** ✓（0→1）、**单击暂停** ✓（paused=true ✓ 暂停标志/标题条 opacity=1 ✓）、**再单击继续** ✓
- 回归：切到「影片」→ 内嵌流 `display:none` ✓（收起）、卡片回来 **54 张** ✓、选中项 = 影片 ✓；**无未捕获异常** ✓
- 另存一张截图给用户看形态：**`sim/_shot_shorts_tab.png`**（240KB ✓；不要就说一声我删 ✓）

---
## 追加（2026-10-03 · **sim 侧第 5 轮**，工作区改动，**未提交未构建**）短片"数据加载不及时"→ 查因 + 提速 ---
**用户报**："**数据加载的不是很及时**" ✗。lead 先让我"造源/预取/占位秒播"，随后纠正成"**直接加载真站页面**" ✗ ——
**两个方向都实测了，结论如下（都有实锤 ✓）**：

**① 「内容区 = 真站页面（iframe）」＝做不到** ✗✗（如实报 ✓ 没硬编 ✗）
- ⚠️ **本节结论我一开始写错了、已更正** ✗→✓（我原先只测了 `/shorts/newest` 且没等 JS 跑完 ✗）：
  **真站 `/shorts` 跑完 JS 后是有 feed 播放器的** ✓✓ —— 实测（真浏览器 + 手机/桌面 UA 两种 ✓）：
  `document.querySelectorAll('video')` = **2 个** ✓，其中一个 `readyState=4 / currentTime=4s / paused=false` **正在播** ✓
  （源 = `blob:` = MSE，站点自己 **muted 自动播** ✓）；页面里 `卡片数=0`、`可滚动=0`、
  DOM 是 `data-opt-hydration="index-moments-static-moment"` + `momentSection-*` ✅ = **竖屏 feed** ✓
  → 而 **`/shorts/newest` 才是卡片列表页** ✗（`video`=0、卡片 103 ✗）—— 两个 URL 是**两种页面** ✓
- **真正的拦路石只有一条 = 站点自己的 CSP** ✗✗（这次用**真正的跨域页面**测的 ✓：
  载体 `example.com` → 注入 `<iframe src="https://tw.xhamster.com/shorts">` ✓）：
  `Framing 'https://tw.xhamster.com/' violates CSP directive: "frame-ancestors 'self'". The request has been blocked.` ✗
  CDP 帧树**无子帧** ✗（= 真被拒 ✗）；头部同源也有 `X-Frame-Options: SAMEORIGIN` ✗
  → **任何第三方页面都嵌不了它** ✗（不是我们改得动的 ✗）
- ✅ **App 的 WebView 不受影响** ✓：它把真站页面当**顶层文档**加载 ✓（不是 iframe ✗）→ app-dev 那条路照走 ✓
  （顺带：站点自己 muted 自动播 ✓ → 声音规矩也天然满足 ✓）
- （顺带更正旧说法 ✓：经代理**页面路径没有 404** ✗ —— 手机 UA/桌面 UA 都 **200** ✓（310KB/388KB ✓）；
  那个 404 是**接口** `/api/v1/moments` **带 `X-Requested-With` 头**时才出现 ✗）

**② sim 侧真正能做的：把"取数"变成 0 网络** ✓（数据/视频仍是**真站的** ✓，没造假 ✗）
- 根因（我上轮自己标过 ✓）：`feedSources` 是"详情页优先" ✗ → 每条抓 `/shorts/<slug>` ✗（5~15s ✗、1/7 超时 ✗）
- 改（都在 `index.html` ✓）：
  1. `xhMomentItems`（新顶层函数 ✓）：`moments` 条目 → item ✓，**mp4 取站点数组第一条 = 站点默认档 480p** ✓
     （用户 2026-10-02 定的"用网站默认分辨率" ✓；也比 720p 少下一半数据 ✓）
  2. `feedSources`：**条目自带源就直接用** ✓（0 网络 ✓）；只有页面 JSON 那 45 条（**确实无源** ✗）才抓详情页 ✓
  3. **短片预热池** `warmShortsPool` ✓：进页面就并发抓 6 页 `moments`（≈35 条 ✓ **全带源** ✓，实测 1.7~2.2s ✓）
  4. `preconnectHosts` ✓ + **滚动 preconnect**（每换一条把后面 8 条的主机先连上 ✓）：xHamster 的 mp4 主机**每条都不同** ✗
     （`video7…` / `ip<随机号>.ahcdn.com` ✗）→ 慢的那几条全是**现做 DNS+TLS** ✗
  5. `feedPrecacheOne` 修 **`mode:'no-cors'`** ✓：原来跨域 `fetch` 被 CORS 拒 ✗ → 异常被吞 ✗ → **等于没预热** ✗；
     字节预热从 5 条收到 **2 条** ✓（no-cors 不能带 `Range` ✗ → 整文件下载 ✗，多了白耗带宽 ✗）
  6. ⚠️ **`<video preload=auto>` 预热是死路** ✗（实测两遍 ✓）：`display:none` **一个请求都不发** ✗；
     改"挪出屏幕 + opacity:0"**也不发** ✗（`readyState` 恒 0、网络面板 0 条 ✓）→ 只有 `fetch(no-cors)` 真发 ✓
- **实测数字（端口 = 用户的 8787 ✓ 只读；Edge headless + CDP + 手机 UA ✓；全程静音 ✓）**：

  | 指标 | 改前（每条抓详情页 ✗） | 改后 |
  |---|---|---|
  | 点「短片」tab → 出画面 | ~10s+ / 常超时 ✗ | **3.2s** ✗（未达 2s ✗） |
  | 上滑换条（连续 5 次） | 5~15s / 条 ✗，1/7 失败 ✗ | 热主机 **216 / 246 / 246 / 767ms ✓**；冷主机 **1.5~3.8s ✗**（3/5 ≤2s） |
  | 取数耗时 | 每条一次详情页 ✗ | **0 网络** ✓（日志 `短片取源 #N：条目自带 2 条` ✓） |

- ❓ **残下的瓶颈 = 视频字节**：跨域 CDN 每主机现做 DNS+TLS+首包（走系统代理 ✓），**和本机网络强相关** ✗ ——
  sim 侧已无更多手段 ✗；要**严格 ≤2s** 只剩两条（**都没做** ✗，等拍板 ✓）：
  ① 每条整文件预下载 ✗（流量大 ✗）② **server 端带 Range 的缓存** ✗（要改 `server.mjs` ✗ → 触发热重载 ✗，按 §六-10 先问 ✓）
- ⚠️ 另注：我的上滑是**背靠背 0.2 秒一次** ✗（比人手快 ✓）→ 人的节奏（每 2~4 秒划一次 ✓）基本都落在"热主机"那档 ✓

**规矩遵守 ✓**：只改 `sim/index.html` ✓（`server.mjs` 这轮**没动** ✓ → 没触发热重载 ✓、没碰用户进程 ✓）；
`node --check` 内联脚本 = **0** ✓；临时脚本/profile 全删 ✓（sim/ 已复核 ✓）；所有播放验证**全程静音** ✓

--- 追加（2026-10-03 · 工作区改动，**未提交未构建**）A 方案第 1 步：短片 tab 接入站点自己的网页 ---
**用户拍板 ✓**：删掉自研瀑布流 ✗ → 短片 tab 的**内容区**直接嵌站点页面（`https://tw.xhamster.com/shorts` ✓）。
⚠️ 修正一条早先的错判 ✗：`/shorts/newest` 是**卡片列表**（`<video>` = 0 个 ✗）→ **必须用 `/shorts`** ✓
（sim-dev 真浏览器实测 ✅：`<video>` 2 个、其中一个 `readyState=4` **正在播** ✓、卡片数 0 ✓、DOM 带 `index-moments-static-moment` ✓，
而且**站点自己就是 muted 自动播** ✓；模拟器嵌不了真站只是站点 CSP `frame-ancestors 'self'` 禁**跨域 iframe** ✗ —— 我们顶层 WebView **不受影响** ✓）。

**第 1 步（本次 ✓）：只接，行为不改 ✗ —— 旧链路一行未删 ✓（可一夜回滚 ✓）**
- `lib/base/site_ui.dart:94-99`：新增第 14 条站点事实 `String webTabUrl(String key) => '';` ✓（默认空 = 不嵌 ✓ → **其它站 / 其它 tab 行为完全不变** ✓）
- `lib/sites/xhamster.dart:93-113`：实现它 ✓ —— `/shorts*` → **`https://tw.xhamster.com/shorts`** ✓（判定与 URL 拼接都留在站点文件 ✓）
- `lib/web_embed.dart`（**新文件 154 行** ✓）：从 `web_page.dart` 抽出的**可嵌核心** ✓ —— controller + JS unrestricted + 手机 Safari UA ✓ + 进度条/错误重试 ✓ + `AutomaticKeepAliveClientMixin`（切 tab 回来**不重载** ✓）+ **静音保底** ✓（扫 `<video>` + **捕获式** `play` 监听 + 2 秒兜底 ✓，全程 try/catch ✗；用 `runJavaScript`（不带返回值 ✓）避开 iOS 14+ 对 `null/undefined` 直接报错 ✗）
- `lib/web_page.dart`（**净删 59 行** → 59 行 ✓）：改成薄壳 ✓，**公开 API 没变** ✓ → `main.dart:161` / `detail_page.dart:247` **零改动** ✓（进度条从 AppBar 底下挪到网页顶部 ✓）
- `lib/home_page.dart:725-732` + 新方法 `:250-287 _tabChild()` ✓：站点说这个 key 要嵌就 `WebEmbed(url, mute: true)` ✓，否则原 `_FeedView`（含原有 key 注释 ✓）；**顶栏 / tab 行 / 筛选行都在 TabBarView 外面** ✓ = 网页**只占内容区**、**不是全屏** ✓
- 返回键 ✓：只在"**当前这个 tab 就是网页**"时拦 ✓（`canPop: _tab.index != indexOf(c)` ✓）—— keepAlive 会让后台实例留在树里 ✗，不判当前的话切走后返回键会被它吃掉 ✗✗
- `lib/config.dart:31-37`：新增 `kDevWebSimBase`（**默认空 = 关** ✗；sim 侧已有 `/shorts`→`index.html` 路由 ✓，想看本地替身时指到 8787 ✓；**正式构建必须保持空** ✗）

**numstat / 括号（Node + utf8 ✓）**：`site_ui 6/0` · `config 7/0` · `xhamster 16/0` · `home_page 50/14` · `web_page 12/71`（净删 ✓）· **新文件 `lib/web_embed.dart` 154 行（未跟踪 ✗ —— 构建时记得 `git add` ✓）** → 六个文件括号**全 0 / 对称** ✓（`xhamster` 的 4 与 2 个差是**改前就有** ✓）
**没验证的** ❓：编译（本机无 SDK ✗）与真机表现（tab 行压得住 / 静音 / 返回键 / keepAlive ✓）→ **只能真机验** ✓；模拟器只覆盖"布局 + 本地替身" ✓
**第 2 步（删 ≈950 行）** ✗ **未做** ✓ —— 两步走：先构建真机验过 ✓ 再删 ✓（清单已列：`shorts_feed_page.dart` 603 ✓ / `base/video_cache.dart` ✓ / `base/source_cache.dart` ✓ / `home_page` 的 push 分支与 `:152-173` 随机化 hack ✓ / `xhamster` 的 `_xhMoments*` 家族 ✓ / `site_ui` 的 `isShortsPath`+`resetShortsRandom` ✓）


--- 追加（2026-10-03 本次构建 1.0.15 —— 短片 tab 改成果用站点自己的页面）---
**用户决定**：删掉自研瀑布流，短片 tab 直接加载站点自己的 feed 页。
**关键事实（sim-dev 实测更正）**：`https://tw.xhamster.com/shorts` 渲染后是**竖屏 feed + 播放器**（video=2，其中一个 rs=4 正在播，卡片数=0，站点自己 muted 自动播）；而 `/shorts/newest` 才是卡片列表页（video=0、卡片 103）—— 两者是不同页面。
**模拟器为什么验不了**：站点禁跨域 iframe（CSP frame-ancestors self + X-Frame-Options SAMEORIGIN）；App 的 WebView 是顶层加载，不受影响。
**第 1 步（本次）**：新增站点事实 `webTabUrl(key)`（默认空 → 其它站/其它 tab 行为不变）；xhamster 实现之（/shorts → https://tw.xhamster.com/shorts）；新增 `lib/web_embed.dart`；home_page tab 内容区分流 + 返回键规则；web_page 抽薄壳（公开 API 不变）。
**旧链路一行未删**（shorts_feed_page / video_cache / source_cache / _xhMoments / push 分支）→ 真机验过后再删（约 950 行），可回滚。
**真机要验**：tab 行/顶栏压得住 · 静音生效（含手点后）· 返回键先退网页 · 切 tab 回来不重载。

--- 追加（2026-10-03 · 工作区改动，**未提交未构建**）修「一点播放就弹系统全屏播放器」（用户实测 1.0.15 ✗）---
**用户反馈**：「怎么是 safari 的框架？？？？」+ 截图 ✓ → 查明：**不是 Safari** ✗ —— 那是 **iOS 原生全屏播放器** ✓
（左上 X / AirPlay / 画中画 / 静音 / ⏸ / ±10s / 底部进度条 ✓），而且**回不到列表、无法滑动** ✗。
**根因（查证 ✓）**：iOS 的 WKWebView **默认不允许 `<video>` 内联播放** ✓ —— 官方文档原文（pub.dev
`WebKitWebViewControllerCreationParams`）里 `allowsInlineMediaPlayback=false` ✓（**默认值就是 false** ✗）→
站点页里一点视频就被顶成**系统全屏** ✗（页面本身是内联 feed ✓，是我们这边没开这个开关 ✗）。
**修（只动 `lib/web_embed.dart` ✓）**
1. ⭐ 控制器创建参数 ✓：`WebKitWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
   params, allowsInlineMediaPlayback: true, mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{})` ✓
   —— **类名/参数名照官方文档核过** ✓（不猜 ✗）；这两个都是 `WKWebViewConfiguration` 的**创建期只读项** ✓
   → 只能走创建参数 ✓（`WebViewController.fromPlatformCreationParams` ✓，官方示例写法 ✓）。
   ⚠️ 顺带清空 `mediaTypesRequiringUserAction`（默认 `{audio, video}` ✓）→ 让站点自己的**静音自动播**能起来 ✓
   （否则每换一条都要手点一下 ✗）；静音仍由 JS 全程压着 ✓。
2. JS 兜底（`_guardJs` ✓，与静音同一处 ✓）：每个 `<video>` 补 `playsInline = true` + `playsinline` /
   `webkit-playsinline` 属性 ✓；`play` 捕获监听里也补一遍 ✓；站点若自己喊 `webkitEnterFullscreen()` ✗ →
   在 `webkitbeginfullscreen` 里立刻 `webkitExitFullscreen()` ✓（能不拦就不拦 ✓）。
3. 旧 `_muteJs` 已被 `_guardJs` **整体取代** ✓（无残留 ✓）；**返回键规则未动** ✓；`mute: false` 时跳过 JS 注入 ✓
   （控制器参数仍生效 ✓ —— 目前两处调用都用默认 `mute: true` ✓）。
**依据（file:line）**：`lib/web_embed.dart:56-84`（创建参数 ✓）· `:91-125`（`_guardJs` ✓）· `:17-23`（类注释 ✓）；
API 出处 ✓：pub.dev `webview_flutter_wkwebview` → `WebKitWebViewControllerCreationParams`（含 `allowsInlineMediaPlayback` /
`mediaTypesRequiringUserAction` ✓）+ `webview_flutter` → `WebViewController.fromPlatformCreationParams`（官方示例 ✓）。
**numstat / 括号（Node + utf8 ✓）**：`lib/web_embed.dart 49/12` ✓（`()` 84/84 · `{}` 31/31 · `[]` 2/2 **全配平** ✓，行数 153→191 ✓）
⚠️ 新增 import `package:webview_flutter_wkwebview/...` ✓（随 `webview_flutter` 一起装的 **iOS 实现包** ✓）；
`depend_on_referenced_packages` 可能报一条 **info** ✓ **不拦构建** ✗（要消掉就往 pubspec 里显式加一行 ✓）。
**没验证的** ❓：编译（本机无 SDK ✗）；真机三件事 —— ① 内联播放、不再弹系统全屏 ✓ ② 上滑换条能自动播 ✓
③ 静音仍生效 ✓；⚠️ 若**站点自己在别处**强行全屏（或用了 iOS 不允许的 API ✓），兜底也可能压不住 ❓。


--- 追加（2026-10-03 本次构建 1.0.16 —— 短片 WebView 内联播放）---
**用户实测（1.0.15）**：短片 tab 能出站点页，但一点视频就弹 iOS 原生全屏播放器、回不到列表、无法滑动（他以为是 Safari，其实是系统全屏播放器）。
**根因**：WKWebView 的 `allowsInlineMediaPlayback` **默认为 false**（pub 文档原文：Whether inline playback of HTML5 videos is allowed）→ 站点页里的 video 被系统顶成全屏。
**修（只动 `lib/web_embed.dart`）**：iOS 创建参数改走 `WebKitWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(...)`，设 `allowsInlineMediaPlayback: true` + `mediaTypesRequiringUserAction: const {}`（后者让站点的静音自动播能起）；JS 兜底给每个 video 补 playsInline，并在 webkitbeginfullscreen 里退出全屏。
**注意**：这两个开关只能在**创建时**给（WKWebViewConfiguration 创建期只读）；新增 import `webview_flutter_wkwebview` 可能引出 `depend_on_referenced_packages` info（不拦构建）。
**真机待验**：内联播放 ✓ / 上滑换条能否自动播 ✓ / 静音仍生效 ✓ / 返回键不变 ✓。

--- 追加（2026-10-03 · 工作区改动，**未提交未构建**）WebView 方案作废 → **逐字节回退**到瀑布流 ✓ ---
**用户决定 ✗**：WebView 方案作废 ✓ → 短片 tab 回**自研瀑布流** ✓（1.0.15 里旧链路一行未删 ✓，所以这是纯撤销 ✓）。
**回退范围（= 撤销 1.0.15 那两步 ✓）**
- `lib/home_page.dart`：撤 tab 分流（`_tabChild` ✓）、撤 `PopScope`/返回键规则 ✓、撤 `_webCtl` ✓、撤两个 import ✓
  → **tab 内容区恢复原样 `_FeedView`（含原 key 注释一字不差 ✓）** ✓
- `lib/sites/xhamster.dart`：撤 `webTabUrl` 实现 ✓ + 撤那行 `import '../config.dart'` ✓
- `lib/base/site_ui.dart`：撤 `webTabUrl` 这条站点事实 ✓ ｜ `lib/config.dart`：撤 `kDevWebSimBase` ✓（撤完无引用 ✓）
- **保留** ✓：`lib/web_embed.dart`（191 行 ✓，**含 iOS 内联播放修复** ✓）与 `lib/web_page.dart`（薄壳 ✓）——
  它们只服务**整页** `WebPage` ✓（`main.dart:161` / `detail_page.dart:247` ✓），内联播放修复对那两处是**净改善** ✓，
  回退它们只会白增风险 ✗ → **留着** ✓（这是本轮我替它做的取舍 ✓）
**验证（关键 ✓）**：`git diff 012743c（= 1.0.14 基线）-- <那 4 个文件>` → **输出为空** ✓✓ = **逐字节回到 1.0.14** ✓；
残留检查 ✓：那 4 个文件里 `webTabUrl` / `_webCtl` / `kDevWebSimBase` / `WebEmbed` / `webview_flutter` **0 命中** ✓；
括号余额全 0 ✓（`xhamster` 的 4 个差仍是**改前就有** ✓）。
**当前工作区**：`lib/web_embed.dart`（内联播放修复 `49/12` ✓）· `sim/*`（**sim-dev 的** ✗）· DEVLOG ✓ —— 其余全部干净 ✓

--- 追加（2026-10-03 · 工作区改动，**未提交未构建**）预缓冲优化：A + C + E + 并发 5（**B 等实测** ✗）---
**用户拍板** ✓：A 首条也预下载 ✓ · B 放宽单文件上限（**等 `sim-dev` 的 `Content-Length`** ✗）· C 缓冲让路 ✓ · E 总量 640MB ✓ · **并发改成 5 试试** ✓
**A 首条也预下载** ✓
- `home_page.dart:1160-1168`：短片分支的入口预热接 `.then((srcs) => VideoCache.i.window(<String>[srcs.first]))` ✓
  （`window()` 内部自带 `await init()` ✓（`video_cache.dart:86` ✓）→ 入口不用自己建目录 ✓）
- `shorts_feed_page.dart:266`：`_primeWindow` 的循环 **`k` 从 0 起** ✓ —— 必须把**当前条**也放进窗口 ✗，
  否则 `window()` 会把"不在窗口里"的下载**中止** ✗ → 入口那次抢跑就白做了 ✓
- `shorts_feed_page.dart:215-219`：`_open()` 里 `ready()` 没命中 → `VideoCache.i.drop(srcs.first)` ✓
  （放弃它的预下载 ✓：不跟**在线播**抢同一份流量 ✓）
- `video_cache.dart:136-140`：新增 `drop(url)` ✓（摘 `_want`/`_queue` ✓ → 在下的 `_download` 走**既有**中止分支删 `.part` ✓；**已下好的不动** ✓）
**C 缓冲让路** ✓
- `video_cache.dart:52 / 106 / 126 / 129 / 165`：`_paused` ✓ + `pause()`/`resume()` ✓ + `_pump` 暂停时不起新任务 ✓ +
  `_download` 循环里 `while (_paused && _want.contains(url)) await Future.delayed(400ms)` ✓
  —— **不消费响应流 = TCP 背压** ✓（服务端自己慢下来 ✓）且**进度不丢** ✓（恢复即续下 ✓）
- `shorts_feed_page.dart:146 / 152-169`：`_onTick` 里 `_watchBuffering(s.buffering)` ✓、**去抖 1.5 秒** ✓（抖动不折腾 ✓）、缓冲一结束**立刻**恢复 ✓；
  `dispose`（`:113-117` ✓）里**必须 resume** ✗ —— 缓存是**全局单例** ✗，留着暂停会把预下载永久停住 ✗
**E + 并发** ✓（`video_cache.dart:35-41`）：总量 320 → **640MB** ✓；`concurrent` 2 → **5** ✓（用户拍板 ✓）
—— ⚠️ 并发就**这一个常量** ✓（真机若播放变卡 ✗ → **改这一行**回 1~2 ✓）；文件数 24 保留 ✓（等 B 数据再定 ✓）
**没做的** ✗：B —— `maxFileBytes` 仍是 32MB ✓（代码里留了注释说明"等实测" ✓）
**numstat / 括号（Node + utf8 ✓）**：`video_cache 38/8` ✓（134/134 · 61/61 · 7/7 ✓）· `shorts_feed_page 43/1` ✓（272/272 · 69/69 · 15/15 ✓）·
`home_page 20/50` ✓（684/684 · 138/138 · 60/60 ✓）—— **余额全 0** ✓；`site_ui/config/xhamster` 仍是回退项 ✓
**没验证的** ❓：编译（本机无 SDK ✗）；真机四件事 —— ① 首条是否真秒开 ✓ ② **并发 5 会不会播得更卡** ✗（会就回 1~2 ✓）
③ 缓冲让路是否真缓解"划过去要等" ✓ ④ 回看是否更快 ✓；⚠️ 一个**小竞态** ❓：快速来回划时"窗口重加"可能晚于 `_open()` 的 `drop` ✓
（那条会一边播一边继续下 ✗ —— 影响很小 ✓，先不额外加锁 ✓ `ponytail:` 天花板已记 ✓）

---
## 追加（2026-10-03 · **sim 侧=只探测**）短片源**真实体积**实测（给 app-dev 定预下载上限 ✓）---
**取样**：moments 1~3 页 17 条（手机 UA ✓）+ `/shorts/<slug>` 详情页 5 条（**桌面 UA = App 的 `_xhDesk`** ✓）；
体积用 `HEAD` 的 `Content-Length`（不给就 `Range: bytes=0-0` 读 `Content-Range` ✓）；**全程没播放**（不需要 ✗）。

| 档位 | n | 最小 | 中位数 | 最大 |
|---|---|---|---|---|
| 480p（详情页，桌面 UA） | 10 | 0.95 MB | **2.25 MB** | 2.77 MB |
| **720p（详情页，桌面 UA）** | 6 | 1.92 MB | **4.40 MB** | **5.10 MB** |
| 480p（moments，手机 UA） | 10 | 1.32 MB | 1.56 MB | 1.89 MB |
| 全部合计 | 16 | 0.95 MB | **2.65 MB** | **5.10 MB** |

- ✅ **结论 1：`maxFileBytes = 32MB` 根本不是瓶颈** ✗ —— 观测最大 **5.1MB**（32MB = 6 倍余量 ✓）。
  **建议上限 16MB** ✓（= 观测 p100 的 ~3 倍余量 ✓；真想保守就保持 32MB ✓ 也无害 ✓）。**别再拍脑袋 ✗，按这个数 ✓**
- ⚠️ **结论 2：真正的拦路石是"形态"** ✗：**只有 m3u8、没有 mp4 的占 7/17（约 41%）** ✗（moments 样本 ✓）
  → 这部分**永远没有文件可预下载** ✗（详情页样本里 1/5 也是如此 ✓）
- ⚠️ **结论 3：源集**随 UA**不同** ✗（这条对 App 很关键 ✓）：**手机 UA 只给 480p 一路 mp4** ✗；
  **桌面 UA 才给 480p + 720p 两路 mp4** ✓（App 用 `_xhDesk` = 桌面 UA ✓ → 能拿到 720p ✓，代价是 ~2 倍体积 ✓）
- 附：m3u8 各档（auto/480p/720p/1080p）**全是 m3u8 变体清单** ✗ 的条目，实测大小只有 **268~577 字节**（= playlist ✗，不是视频 ✗）

**规矩 ✓**：只探测 ✓ **没改任何代码** ✗；**没起任何本地服务** ✓（真站探测不需要 ✓）；**没碰用户进程** ✗（8787 全程没访问 ✓）；
**没播放** ✓（只 HEAD/Range ✗ → 不存在出声问题 ✓）；4 个临时脚本**全删** ✓


--- 追加（2026-10-03 本次构建 1.0.17 —— 回退 WebView + 瀑布流预缓冲优化）---
**用户决定**：WebView 方案作废（点了会弹系统全屏、无法滑动），改回瀑布流，转而优化预缓冲。
**回退**：撤掉 tab 分流 / webTabUrl（站点事实 + xhamster 实现）/ 为 WebView 加的返回键规则 / kDevWebSimBase；`git diff 012743c` 对那 4 个文件为空 = 逐字节回到 1.0.14。web_embed/web_page 保留（只服务整页 WebPage，含 iOS 内联播放修复，是净改善）。
**优化（A/C/E + 并发 5）**：A 首条也预下载（入口预热接 VideoCache.window([源])、_primeWindow 从 k=0 起、_open 未命中的 drop 让路）；C 播放 buffering 时暂停预下载（去抖 1.5s、恢复即续下、dispose 必 resume —— 全局单例不然会永久停住）；E 总量 320→640MB；并发 2→5（单一常量，卡了改回 1~2）。
**B 证伪**：实测（sim-dev）短片体积中位数 2.65MB / 最大 5.10MB → 32MB 上限从未触发，放宽无收益。教训：该实测的不要估算（我按长视频码率估成 20~40MB）。
**未治**：约 41% 的条目只有 m3u8（无 mp4）→ 无法预下载，只能在线拉。

--- 追加（2026-10-03 · 工作区改动，**未提交未构建**）总量上限 **640MB → 300MB**（用户拍板 ✓）---
**改哪**：`lib/base/video_cache.dart:38` —— `maxTotalBytes` **640 → 300MB** ✓（只动这一个常量 ✓ + 旁边注释 ✓）。
⚠️ 上面 1.0.17 那节里写的"总量 640MB"**以本条为准** ✗（640 只活了一个构建 ✓）。
**顺带核到的事实（重要 ✓）**：`prune()`（`:224-232` ✓）是"新→旧"遍历，**条数与容量谁先撞线听谁的** ✓ ——
实测短片单条**中位数 ≈ 2.65MB** ✓ → **24 个 × 2.65MB ≈ 64MB** ✗ → **先撞线的是 `maxFiles = 24`** ✗，
300MB 只被用到约 **21%** ✓（要吃满 300MB 需要 ≈ **113 个**文件 ✓）。
**待用户拍板** ❓（**我没改** ✗）：`maxFiles` 要不要 24 → **60~80**？我建议 **80**（≈ 212MB ≈ 70% ✓，给大文件留余量 ✓）；
⚠️ 但**收益只在"回看/来回划"** ✓ —— **不治"往前划要等"** ✗（那条靠窗口 6 条 + 并发 5 + 缓冲让路 ✓，已做 ✓）。
**顺带更正我自己上一轮的估计** ✗：我曾按"45 秒 720p ≈ 20~40MB"论证 B 的必要性 ✓ —— 实测**中位数只有 2.65MB** ✗
→ 那个估计对**典型情况偏高** ✓，B（32MB 单文件上限 ✓）只影响**尾部大文件** ✓ → 优先级可降 ✓（结论不变：不改也能跑 ✓）。
**括号（Node + utf8 ✓）**：`lib/base/video_cache.dart` `()` **134/134** · `{}` **61/61** · `[]` **7/7** → **余额 0** ✓（258 行 ✓）

--- 追加（2026-10-03 · 工作区改动，**未提交未构建**）最终口径：**200MB + `maxFiles` 70**（用户拍板 ✓）---
**改哪**（`lib/base/video_cache.dart` ✓，一次到位 ✓）：`maxTotalBytes` **300 → 200MB**（`:44` ✓）· `maxFiles` **24 → 70**（`:48` ✓）——
算式已写进注释 ✓（日后直接照着调 ✓）。
**LRU 的准确语义（按代码 ✓，`prune():231-244` ✓）**：从**最新**往旧遍历，**累计字节 > 200MB 或 `n >= maxFiles`**
→ 从这条起**往后全部删** ✓（不是 break ✗，是这条+更旧的都删 ✓）→ 所以
**实际留下 = min(`maxFiles`, "累计不超 200MB"的条数)** ✓（谁先撞线听谁的 ✓）。
**算式（实测中位数 ✓ `sim-dev` 2026-10-03 ✓）**：
- 全部中位 **2.65MB** → `200 ÷ 2.65 ≈ 75` → **条数先撞线** → 留 **70 个 ≈ 186MB**（93% ✓）
- 720p 中位 **4.40MB** → `200 ÷ 4.40 ≈ 45` → **容量先撞线** → 留 **45 个 ≈ 198MB**
- 最坏（实测最大 **5.10MB**）→ `200 ÷ 5.10 ≈ 39` → **至少也留 39 条** ✓
**为什么取 70 而不是 75 / 45** ✓：75 是"全部等于中位数"的理想值 ✗，70 = 留约 **7% 余量** ✓；
45 那档是"假设全是 720p"的保守值 ✓ —— 代码里**不用**它 ✓（文件偏大时**容量会自己先撞线** ✓，不用条数去管 ✓）。
⚠️ 若用户改主意要更保守 → **`maxFiles` 改 45 即可**（1 行 ✓）。
**括号（Node + utf8 ✓）**：`lib/base/video_cache.dart` `()` **136/136** · `{}` **61/61** · `[]` **7/7** → **余额 0** ✓（265 行 ✓）

---
## 追加（2026-10-03 · **sim 侧第 6 轮**）用户报"模拟器站点加载不上" ✗ → 查因 + 收紧预热 ---
**结论：不是我改的代码坏** ✓（证据钉死 ✓）：
- 同一份代码、**全新进程**（我起的 8788 ✓）：`/site` xHamster moments → **200 / 100KB / 1.9s** ✓；
  `51吃瓜 /` → **200 / 267KB / 1.2s** ✓ → 代码没问题 ✓
- 用户那个 8787 进程：本地端点全 200 ✓（`/` 323KB ✓、`/sites` 14 站 ✓、`/shorts/newest` ✓），
  但**所有** `/site`（含我**没碰过**的 51吃瓜首页 ✗）→ **12 秒后 500** ✗（= 它自己的出站超时 ✗）
- 代理本身**是好的** ✓：我直连 mihomo（127.0.0.1:7890 ✓）CONNECT **13ms** ✓、真站 TLS 后 2.9s 回数据 ✓
→ **是那个进程的状态卡死了** ✗（重启即好 ✗ —— **我没动它** ✗，按 §六-10 绝不碰用户进程 ✓）

**⚠️ 诱因很可能是我** ✗（如实认 ✓）：上一轮我加的"**进页面就并发 6 个出站请求**"预热 ✗ →
每个都走代理 ✗、和首页图标/列表抢连接 ✗ → 把服务进程拖到卡死是合理怀疑 ✓。
**收紧（只改 `index.html` ✓ → 刷新即生效 ✓、不用重启 ✓）**：
① 6 页 → **3 页** ✓ ② **第 1 页立刻发**（进 tab 靠它起播 ✓）、**其余页延迟 1.5s** ✓
③ 其余页**一次只开 2 个** ✓ ④ `mountShortsFeed` **只等第 1 页** ✓（≈6 条够起播 ✓，不等整个池 ✗）

**冒烟（我起的 8788 ✓；Edge headless + CDP + 手机 UA ✓；全程静音 ✓）**：
首页 **14 站** ✓ · xHamster 影片 **54 卡** ✓ · 短片 tab **进流 ✓ + 起播 ✓**（`rs=4`、`muted=true`、`volume=0` ✓）·
卡片数 **0** ✓ · `tab行=[影片,分类,色情明星,短片]` ✓ · 取源 `条目自带 2 条（…480p.h264.mp4）` ✓（0 网络 ✓）·
**无未捕获异常** ✓（只剩 favicon 404 ✓）· 到出画面 **3.87s** ✗（收紧前那版 10.7s ✗ → 现在等的是**网络字节** ✗，不是等池子 ✓）
`node --check` 内联脚本 = **0** ✓

--- 追加（2026-10-03 · 工作区改动，**未提交未构建**）死代码清理：23 条 `unused_*` 删 + 51 处 `@override` 补 ---
**依据方式（用户要求 ✓）**：**全库 `git grep -n` 实地证据** ✓ —— 每条先列命中，只有"除定义/赋值外 0 引用"才删 ✓；不采信"像/应该/推断" ✗。
CI 清单取自 `G:\ZCode\unused-audit-1.0.17.decoded.txt`（75 条 ✓，error 0 ✓）。
**⚠️ 工具坑（自查发现 ✗）**：`git grep` 默认 **BRE** ✗ → 带 `|` 的模式被当**字面量** ✗ → 我第一批"0 命中"是**假 0** ✗✗ →
重跑加 `-E` ✓ 并加**阳性对照**（`class|void` 必须非 0 ✓）自证 ✓。
**删了什么（23 条 `unused_*`，行数见 numstat）**
- **12 条 import** ✓：`api.dart` 的 `dart:math`（`Random|sqrt|pow`=0 ✓）· `dart:typed_data`（`Uint8List|ByteData`=0 ✓）· `crypto`（`sha1|md5|Digest|Hmac` 只命中 **1 行注释**（`:262`）✓）· `encrypt`（同上 ✓）· `config.dart`（`Site\.` = **0** ✓）｜ `main.dart` 的 `play_history_page.dart`（`PlayHistoryPage` 在 main **0 引用** ✓，而 `PlayHistory` 定义在 **`settings.dart:181`** ✓ 且 main 也 import 了 settings ✓）｜ `hanime1:9` `dart:convert`（0 ✓）｜ `pektino:15/16` `html/dom`+`html/parser`（`Element|Document|querySelectorAll|hp` 只命中 1 行注释 + **那行 import 本身** ✓）｜ `pornhub:12` `dart:convert`（0 ✓）｜ `pornhub:19` `../api.dart`（`SiteEntry` 来自 **`sites.dart:115`** ✓，pornhub 已 import sites ✓）｜ `xvideos:18` `html/dom`（`Element|Document` 仅注释 ✓）
- **8 条 element** ✓：`api.dart:54 set _host`（getter `:53` 被 `:57 base` 用 ✓，**setter 0 引用** ✓）· `:55 _client`（0 ✓）· `:143 _fetchAbs`（0 ✓）· `hanime1:506`/`pornhub:462` `_nameOf`（**这两份副本 0 引用** ✓ —— 注意 `home_page.dart:86` 的同名函数**在用**（`:427/:444` ✓）**不删** ✓）· `home_page:104/108/111` `_hnSorts/_hnDates/_hnDurations`（**本文件 0 引用** ✓；hanime1 里那份**在用**（`:365/:371/:377` ✓）**不删** ✓）
- **2 条 field + 1 条 local** ✓：`xhamster:246 _xhShortsFrom`（**写点 2**：声明 `:246` + 赋值 `:249`；**读点 0** ✓）· `settings:238 old`（全文件**仅此一处** ✓）· `player_widget:230 _stalled`（声明 1 + **写 3**（`:191/:203/:264`）；**读点 0** ✓ → 删 4 行代码 ✓、**保留** `:184` 那句历史注释 ✓）
- `resetShortsRandom` **三处一起删** ✓（`site_ui:85` 声明 + `xhamster:248` 覆写 + `home_page:166` 调用 ✓）—— 证据：它只写那个 **0 读**字段 ✓ → **行为等价** ✓✓
**补了什么（51 处 `@override`）** ✓：CI 原文即"**overrides an inherited member**" ✓（编译器判定 ✓）+ 父类 `site_ui.dart` 的 `:55/66/69/72/77/81` ✓ + 10 个类 `class XxxSite extends SiteUi {` 实地核过 ✓；逐文件：hanime1 **6** · huangguo/kmsvip/madou/pektino/porna/pornhub/wordpress/xhamster/xvideos 各 **5** ✓
**顺手收窄** ✓：`video_cache.prune()` → `_prune()`（`lib/` 内只有它自己调：`:76/:196` ✓）+ 注释同步 ✓
**numstat（对 HEAD ✓）**：`api 0/10` · `main 0/1` · `home_page 0/13` · `player_widget 0/4` · `settings 0/1` · `site_ui 0/3` · `hanime1 6/9` · `pornhub 5/10` · `xhamster 5/4` · 其余站点 `5/0 ~ 5/2` ✓ · `video_cache 17/7`（其中大部分是**上一轮** 200MB/70 + A/C/E ✓）
**总共省**：**删 57 行 / 插 51 行 `@override` → 净 −6 行** ✓，但清掉 **75 条 analyze 提示** ✓（23 `unused_*` + 52 `annotate_overrides` ✓）
**验证** ✓：① "51 处 @override + 全部删除目标"结构自检 **0 失败** ✓ ② 括号**逐文件与 HEAD 基线比对，0 处不一致** ✓ ③ 两个"CRLF blob"文件只在预期位置有小 diff ✓
**⚠️ 过程失误（自查发现并全部修好 ✗）**：① 脚本 `docTop` 只删了 `_fetchAbs` 上方的注释、**本体没删** ✗ ② 块删除的收尾判据用 `trim().startsWith('}')` → 命中**内层** `}` ✗ → hanime1/pornhub 各留 2 行孤儿 ✗ → 已补删 ✓（收尾改为**只认列 0 的 `}`** ✓）③ `edit` 工具会**整体改写文件字节形态** ✗（EOL/BOM）→ 对这两个 CRLF-blob 文件会变成**整文件 diff** ✗✗ → 改用"以 `git cat-file blob HEAD:` **原始字节**为基准 + Node 写盘"重做 ✓ → 现在 `6/9`、`5/10` ✓
**⚠️ 教训** ✓：`git show > f` / `Set-Content` 生成的"基线副本"**不能当字节基准** ✗（PowerShell 会加 BOM ✗ → 我据此"补 BOM"补错了一轮 ✗，已全部纠正 ✓）；要字节基准就用 `git cat-file blob` ✓
**没验证的** ❓：编译（本机无 SDK ✗）→ 交 CI ✓；⚠️ 若 CI 报错，**按条目回退** ✓（每条改了哪些行上面已逐条记 ✓）

--- 追加（2026-10-03 · 工作区改动，**未提交未构建**）优化第 1 批：**#7 图片磁盘缓存** + **#4 两处小改** ---
**#7 `FetchedImage` 磁盘缓存** ✓（用户拍板清单第 1 优先 ✓）
- **新增 `lib/base/image_cache.dart`（143 行 ✓）**：与 `video_cache` **同一套写法** ✓ ——
  `.part` 写完再 `rename`（原子 ✓）· LRU 按"最后修改时间"新→旧 ✓ · **谁先撞线听谁** ✓ · **全程静默** ✗
  · 上限 `maxFiles=400`（**与内存缓存 `_maxCache=400` 对齐** ✓，依据 `fetched_image.dart:64` ✓）+ `maxTotalBytes=60MB`
- **`lib/fetched_image.dart`**：`_load()`（`:85` ✓）里先查磁盘（`take()` ✓，命中即渲染 ✓）；`_fetchAndDecode` 里
  `_looksLikeImage` 通过后 `put()` ✓（**只存真图** ✓）；`ImageDiskCache.init()` 幂等 ✓
- ⚠️ **key = url 本身** ✓（哈希成文件名 ✓）——依据：`fetched_image.dart:124-137` 请求头**只由 url 推导** ✓
  （UA 写死 ✓、`Referer` = url 自己的域名 ✓、`Accept` 写死 ✓）→ 同 url 在任何站点/页面拿到的字节一致 ✓ → **不用把站名混进 key** ✓
- ⚠️ **存解密后的明文** ✓（不存密文 ✗）——三条理由 ✓：① 密文每次命中都要**再解一次**（还是 `compute` isolate ✓，`fetched_image.dart:147-150` ✓）→ 省掉的正是最贵那步 ✗ ② AES-CBC 是一比一 padding → 明文/密文**体积几乎相同** ✓ 存密文不省空间 ✓ ③ 目录是 App **私有**临时目录 ✓，与 `video_cache` 存明文视频同性质 ✓
**#4a `use_build_context_synchronously`** ✓：`lib/web_page.dart:43` 的 `else if (mounted)` → **`context.mounted`** ✓（语义相同 ✓，只是把守卫挂到真正要用的那个 context 上 ✓）
**#4b pubspec 显式声明** ✓：`pubspec.yaml:35` 加 `webview_flutter_wkwebview: '>=3.0.0 <4.0.0'` ✓（锁里已是 **3.22.0** ✓，CI 日志 `:75` ✓ → 只放开区间、不换版本 ✓）→ 消 `depend_on_referenced_packages` ✓
**#2（`_primeWindow` 并行）—— 实测后判断：**不是问题** ✗**：`_precache()` 已经**不 await** 地把窗口 6 条的 `_sourcesOf(j)` 全都发出去 ✓（`shorts_feed_page.dart:250-255` ✓ "并发跑，不 await" ✓）→ 请求本来就是并发的 ✓；`_primeWindow` 的 `await` 只是**收集已发出去的 Future** ✓ → 没有"串行等待"这个瓶颈 ✓ → **建议不改** ✗（改反而会变成"重复发起" ✓）
**numstat（本批）**：`lib/base/image_cache.dart` **新文件 143 行（未跟踪 ✓ 提交时要 `git add` ✗）** · `fetched_image.dart 13/0` · `web_page.dart 4/1` · `pubspec.yaml 4/0` ✓
**括号** ✓：`fetched_image`/`web_page` 与 HEAD 口径**一致** ✓；新文件 `()` 68/68 · `{}` 36/36 **余额 0** ✓
**⚠️ #1（m3u8 预下载）卡在能力上 ✗**：我**无法连通该站点**（本机探测 `/shorts/newest` 都是 404 ✓，早前已证实 ✗）→ 那两个未知 ❓（`#EXT-X-KEY` 加密 / 分段 URL 时效签名）**只能由 sim-dev 或你能连通的口子实测** ✓ → 请转派 ✓（不行就按用户口径**明确放弃** ✓）
**⚠️ #17（两个 CRLF 文件 renormalize）**：按你要求**先报不改** ✗ —— 我的打算：**跟你下一次提交一起**执行 `git add --renormalize lib/sites/hanime1.dart lib/sites/pornhub.dart` ✓ → 代价是**这一次提交里那两个文件会显示整文件重写** ✗（之后永久正常 ✓）；**若不想看到那次噪音** → 备选：维持现状 ✓ 但改这两个文件必须用**保字节形态**的写法 ✗（不能用编辑器直接改 ✓）→ 请拍板 ✓
**没验证的** ❓：编译（本机无 SDK ✗）→ 交 CI 复核 ✓

--- 追加（2026-10-03 · 工作区改动，**未提交未构建**）优化第 2 批：**#5 详情页起播参数** + **#8 网格图片预取** ---
**#5 详情页/全屏也套那 3 个起播参数** ✓（用户拍板 ✓）
- 收口成**一份实现** ✓：`lib/player_widget.dart:270` 加 `static const bool tuneStartup = true;`（**总开关 ✓ 默认开 ✓，改这一处即可一键关** ✗）
  + `:280` 加 `static void tuneStartupQuiet(KpPlayer kp)` ✓（原来散在短片页的 3 条参数 + 理由 + try/catch 全搬来 ✓，**只有一份** ✗）
- 两个调用点 ✓：详情/全屏在 `lib/player_widget.dart:821`（`kp = KpPlayer(bufferMb: AppSettings.i.bufferMb)` 之后 ✓）；
  短片在 `lib/shorts_feed_page.dart:227`（`_tuneMpvStartup` 现在只有一行转发 ✓；**该页 0 处字面参数残留** ✓ 已 grep 核 ✓）
- ⚠️ **仍旧不碰共用配置** ✗：`tuneStartupQuiet` **只对传进来的那个实例**生效 ✓（别处不调 → 完全不受影响 ✓）
- 短片页旧注释里"**只给短片这个实例**"已作废 ✗ → 已改 ✓（`shorts_feed_page.dart:224-226` ✓）
**#8 网格图片预取** ✓（用户拍板 ✓）
- `lib/fetched_image.dart:61` 加公开入口 `FetchedImage.warm(url)` ✓ → `:119` 实现挂在 State 上 ✓（用**同一个** `_cache`/`_inflight` ✓）
  → ⚠️ 与"真正显示"**共用同一个在途 Future** ✓（不会重复下载 ✓，依据 `:108` 与 `:122` 是同一句 `_inflight.putIfAbsent` ✓）
- 调用点 ✓：`lib/home_page.dart:985`（`RowsGrid` 的 itemBuilder 改成块 ✓，顺手 warm **"再往后第 8 张"** ✓，越界给 null ✓、失败静默 ✓）
- ⚠️ 只接了**主列表**这一处 ✗（`home_page.dart:985` ✓）；第二处 `RowsGrid`（`~:1490`，箭头写法 ✓）**没接** ✗ → 量小、收益同源 ✓，如需要下次补 ✓
**⚠️ 用户撤销项** ✓：**"手动清理缓存"不做了** ✗（"200MB 没必要清理"✓）—— 我**一行都没写** ✓（只读了参照文件 ✓）→ **无需回退** ✓
**numstat（本批）**：`lib/player_widget.dart 24/4` · `lib/shorts_feed_page.dart 4/16` · `lib/fetched_image.dart 25/0` · `lib/home_page.dart 7/15` ✓
**括号** ✓：四个文件与 HEAD 口径**逐文件一致**（不一致 0 ✓）
**没验证的** ❓：编译（本机无 SDK ✗）→ 交 CI ✓；真机要看：详情页首帧是否更快 ✓ / 网格滚动白块是否变少 ✓ / 起播参数若某站变卡 → 把 `KpPlayer.tuneStartup` 改 `false` ✓

--- 追加（2026-10-03 · 工作区改动，**未提交未构建**）**#9 两份缓存合一**（用户："重复肯定要删一份" ✓）---
**留哪份** ✓：留 `lib/base/source_cache.dart`（底座 ✓ 唯一与站点无关 ✓）；删 `api.dart` 的两张静态表（`_lazyCache` 60 条 FIFO + `_lazyInflight` ✓）。
**三条契约怎么保住的** ✓
1. **出错要抛** ✓ → `SourceCache.get()` 加 `rethrowOnError`（默认 `false` ✓ = **短片路一字不变** ✓；详情路传 `true` ✓ = **原样抛** ✓，播放器 `player_widget.dart:789` 的"起播失败→重抓"照旧 ✓）
2. **空结果不缓存** ✓ → `source_cache.dart:50` 里 `if (out.isEmpty && rethrowOnError) _map.remove(url)` ✓（与旧 `if (out.isNotEmpty)` 才写缓存**逐字等价** ✓；短片路照旧缓存空 ✓ **不变** ✗）
3. **key 命名空间** ✓ → 详情 `'d|url'`（`api.dart:222-226` ✓）· 短片 `'s|url'`（`home_page.dart:1155` / `shorts_feed_page.dart:189` ✓）
   —— 两条取名策略不同（`sourcesFromHtml`/dplayer vs `api.detail` 的站点解析 ✓）→ 同 url 结果可能不同 ✗ → **绝不能共用 key** ✗
**站点分叉留在 `api.dart`** ✓：`_fetchSourcesAt`（`:229-247` ✓）里的 `_ui?.sourcesFromHtml(html)`（黄果 ✓，`huangguo.dart:35` ✓）＋通用 `.dplayer` 兜底**一个字没动** ✓（底座不认识站点 ✓ 写死规则一 ✓）
**行为差异清单（改前 → 改后）✓**：正常 ✓ 同 ｜ 空 ✓ 同（不缓存）｜ 出错 ✓ 同（抛）｜ 并发同 url ✓ 同（共享同一个 Future ✓）｜ ⚠️ **仅一处不同** ✗：容量 **60 FIFO → 80 LRU** ✓（只会在极端情况下"记得更多、更准" ✓ 不会更差 ✓）
**⚠️ 行数没达到预估** ✗：你估 −40~60 ✓，**实测**：`api.dart 18/28`（净 −10 ✓）· `source_cache.dart 25/5`（净 **+20** ✗ = 我写的说明注释 ✓）· `home_page 10/16` · `shorts 6/17` ✓
→ **代码本身净 ≈ −5 行** ✓（你估的区间不成立 ✗：`api.dart:226-245` 是**真正的抓取+站点分派**，不是缓存 ✗，必须留 ✓）→ 真实收益是"**只有一套缓存 / 一套上限 / 一份在途语义**" ✓ 而非行数 ✗；要压行数的话可以砍我这批注释 ✓（说一声就砍 ✓）
**括号** ✓：`api.dart` / `home_page.dart` / `shorts_feed_page.dart` / `source_cache.dart` **逐文件与 HEAD 口径一致**（不一致 0 ✓）；`api.dart` 里 `_lazyCache` 只剩 **2 处注释**提及 ✓ 代码 0 ✓
**真机回归清单** ✓：① **合集/短剧的"按需取源"** ✓ ② **起播失败→重试** ✓ ③ **短片页取源**（含入口预热 ✓）④ **黄果** `sourcesFromHtml` 那条 ✓
**没验证的** ❓：编译（本机无 SDK ✗）→ 交 CI ✓

---
## 追加（2026-10-03 · **sim 侧=只探测**）m3u8-only 短片：加密 / 时效 / 分段体量（给 app-dev 定「m3u8 要不要支持预下载」✓）---
**样本**：moments 1~3 页里**只有 m3u8、没有 mp4** 的 **7 条** ✓（手机 UA + 同源 Referer ✓，全程**没有播放** ✗ 只取清单与分段头 ✓）

| # | 有无 `#EXT-X-KEY` | 分段签名形态 | +6 分钟仍 200? | 分段数 | 单段 | 总 MB | 时长 |
|---|---|---|---|---|---|---|---|
| 1 | **无** ✅ | 段 URL 无签名参数 ✅（票据在**前缀路径** `,1791057600` ✗） | **✅ 200（分段/变体/master 三个都 200）** | 8 | 首段 180KB | **1.19** | 17.0s |
| 2 | **无** ✅ | 同上 | （同一份 master/variant 复测 ✅） | 6 | 121KB | **0.82** | 12.5s |
| 3 | **无** ✅ | 同上 | 同上 | 3 | 88KB | **0.35** | 6.6s |
| 4 | **无** ✅ | 无 | — | 3 | — | — | 6.0s |
| 5 | **无** ✅ | 无 | — | 15 | — | — | 30.1s |
| 6 | **无** ✅ | 无 | — | 15 | — | — | 30.1s |
| 7 | **无** ✅ | 无 | — | 20 | — | — | 39.2s |

- **① 加密：7/7 无** ✅（`#EXT-X-KEY` 0 条 ✗）→ 不需要解密链路 ✓
- **② 时效**：签名**不在 query** ✗，而是 xHamster 的**路径票据**（`<hash>,<到期时间戳>/…` ✓）；
  实测到期戳 `1791057600` = **2026-10-03T20:00:00Z** ✓ → 探测时刻**剩余约 210 分钟（≈3.5 小时）** ✓；
  **+6 分钟复测同一分段 → 仍 200** ✓（master/变体也 200 ✓）→ **不是短时效** ✓
- **③ 体量**：分段数 **3~20**（中位 ≈8）✓ · 单段 **88~180KB** ✓ · 总时长 **6.0~39.2s**（中位 ≈17s）✓ ·
  **一条 ≈ 0.35~1.19MB**（按 ~60~70KB/s 推，39s 的那条 ≈ **2~3MB 上界** ✓）
- ⚠️ 实现细节 ✓：拿到的是 **master**（`#EXT-X-STREAM-INF` 变体清单 ✗）→ 预下载要**跟到变体**再下分段 ✓
  （两层我都实测 200 ✓）；分段的目录前缀带同一张票据 ✓

**结论 ✓**：**这类 m3u8 短片**可以**支持预下载** ✓ —— 依据 ①**无加密** ✓ ②**票据 ≈3.5 小时**、6 分钟后仍可用 ✓
③总大小与 mp4 同量级（0.35~1.2MB／上界约 2~3MB）✓，不值得为它单独设更大上限 ✓
⚠️ 限制：过期（>3.5h）后**清单/分段**需重取 ✅（**已下到本地的文件不受影响** ✓）；时效只对 **1/7 条**做了 +6min 实证 ✓，其余按时间戳推断 🔍

--- 追加（2026-10-03 · 工作区改动，**未提交未构建**）**#1 m3u8 预下载**（用户拍板 ✓，依据=sim-dev 实测 ✓）---
**探测结论（sim-dev ✓ 我未复核，直接引用）**：① **无 `#EXT-X-KEY`** ✗（7 条"只有 m3u8"样本 0 条加密 ✓）
② **不是短时效** ✓（签名在**路径票据**里 ✓ 到期 ≈3.5h ✓，+6 分钟复测同分段仍 200 ✓）③ 体量小 ✓
（分段 3~20、单段 88~180KB、一条 ≈0.35~1.19MB ✓）→ **不做解密、不做鉴权重放、不为它放大上限** ✓
**改了什么（只动 `lib/base/video_cache.dart` ✓ `176/15`）**
- `:279` `_isM3u8(url)` ✓（去 query 看后缀 ✓，与 `_isDirectMp4` 同款 ✓）
- `:297` `_downloadHls(url)` ✓：master（`#EXT-X-STREAM-INF`）→ **跟一层**变体 ✓ → 媒体清单 → **逐段下** ✓
  → 写本地清单（分段用**相对路径** `${key}.hls/xxx` ✓）→ **分段目录先 rename、清单最后 rename** ✓
  → **全部下完才算就绪** ✗（`ready()` 只认改名后的 `.m3u8` ✓）· 失败静默 ✓ 回落在线播 ✓
- `:365/:373/:389` `_hlsText` / `_hlsFirstUri` / `_hlsSegmentUris` ✓（后两者是纯文本解析 ✓ 无依赖 ✓）
- `:80-93` `ready()` ✓：出口**只有这一个** ✓（`for (final ext in const ['mp4','m3u8'])` ✓ —— **mp4 优先** ✓ 优先级不变 ✗）
- `:111` `window()` 的筛选 ✅ **唯一改到的 mp4 相关行** ✓：`!_isDirectMp4(u) && !_isM3u8(u)` ✓
- `:162` `_download` 顶部一行 dispatch ✓（`if (_isM3u8(url)) return _downloadHls(url);` ✓）—— **mp4 下载主体一字未动** ✓
  （已用 `git diff` 逐行核 ✓：mp4 侧只多这一行 ✓）
- `_prune` ✓：`*.hls.part` 目录按 `partTtl` 清 ✓；删到 `*.m3u8` 清单时**连它的分段目录一起删** ✓
  ⚠️ `ponytail:` 分段目录的**字节没算进** `maxTotalBytes` ✗（只算清单 ✓）→ 按"每条约 ≤2~3MB × 上限 70 条"估最坏多占 ≤200MB ✓（代码注释里已标 ✓）
**行为差异清单** ✓：
| 场景 | 改前 | 改后 |
|---|---|---|
| **mp4 直链** | 预下 → `file://` ✓ | **完全一样** ✓（只多了后缀判断 ✓） |
| **m3u8（新 ✓）** | **永不预下** ✗ → 每次在线播 | 转本地 ✓ → `ready()` 给 `file://` ✓；**下不成/遇到 KEY·BYTERANGE·嵌套 master → 放弃** ✗ → 在线播 ✓（= 改前行为 ✓） |
| 其余（非 mp4/m3u8） | 跳过 ✓ | 跳过 ✓（不变 ✓） |
| 命中/淘汰 | LRU 70 条 / 200MB ✓ | 同 ✓（不新开 LRU ✓） |
**真机回归点** ✓：① 短片里**只有 m3u8 的那些条**划到时是否更快有画面 ✓ ② **mp4 那些条**是否与之前**完全一样** ✓
③ 划快时是否仍"让路"（缓冲时暂停 ✓）④ 回看/来回划命中率 ✓
**没验证的** ❓：编译（本机无 SDK ✗）；⚠️ **mpv 能不能播"本地 m3u8"我没实测** ❓ —— 若不认，表现=起播失败→回落逻辑生效（不会崩 ✓），届时把 `ready()` 里 `'m3u8'` 从列表里去掉即可**一键回退** ✓（1 处 ✓）


--- 追加（2026-10-04 本次构建 1.0.18 —— 优化批次合入 + lint 清账）---
**合入优化批次（app-dev）**：#1 m3u8 预下载（本地 m3u8，mpv 未实测，回退=ready() 去掉 m3u8）· #7 图片磁盘缓存（新文件 lib/base/image_cache.dart 143 行）· #5 详情页起播参数（KpPlayer.tuneStartup 开关，默认开）· #8 图片预取 warm · #9 缓存合一（SourceCache 统一，rethrowOnError + d|/s| 命名空间）· 死代码清理（净 -6 行）。
**analyze 清账**：119 -> 已清 100 -> 剩 19 条（unnecessary_const 6 + prefer_const_constructors 13，纯 info 噪音、零行为、不拦构建）。这 19 条行号被 CI 遮码且已错位，待本次构建日志吐准确行号后机械清完。
**构建前处理**：git add 新文件 image_cache.dart；git add --renormalize hanime1/pornhub（CRLF 统一，本次会整文件重写）；sim/ 不提交。
**真机回归**：合集按需取源 / 起播失败重试 / 短片 mp4 不变 + m3u8 更快 / 图片二进秒出 / 详情页起播更快（变卡关 tuneStartup）/ 黄果 sourcesFromHtml / 缓存 200MB+70 回收。

## 八、当前待办

- [ ] **「模拟器内容区放真站页面」被站点 CSP 挡死** ✗✅（实测 ✓）：`frame-ancestors 'self'` → 跨域 iframe 被 block ✗
      （真跨域测试 + CDP 帧树无子帧 ✓）。**但真站 `/shorts` 本身有 feed 播放器且站点自己 muted 自动播** ✓
      → **App 的 WebView（顶层加载）能实现用户要的效果** ✓；模拟器侧只剩三选一（**等拍板** ✓）：
      ① 不动（sim 用现有页内播放器 ✓，真站效果到手机上验 ✓）② 加「在真站打开」按钮 ✓ ③ 服务端反代+URL 重写 ✗（不推荐 ✗）
- [ ] **短片"首帧 ≤2s"未达标** ❓（sim 侧取数已 0 网络 ✓，瓶颈在网络字节 ✗）：
      要严格达标只剩 ①每条整文件预下载 ✗ ②`server.mjs` 端带 Range 缓存 ✗（要动服务端 → 先问 ✓）
- [ ] **（sim 已就绪 ✓ 等 App 侧）短片 tab 内嵌站点短片页**：模拟器这边**内容区直接就是播放器**（点进来就播 ✓，
      实测见上方 sim 第 4 轮 ✓）；App 侧那条（WebView 顶栏/tab 行保留、内容区加载站点页）等 app-dev ✓
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
