# KPXX 开发日志

> 只保留**当前最新的流程与现状** ✓（2026-10-03 重写）。历史逐轮记录（1429 行）已归档到 **`DEVLOG_archive.md`** ✓。

---

## ⛔⛔ 显示规范（**开发新站点必走的流程** ✗ —— 每加/改一个站点先照这个来）

### 一、点播站点
1. **入口** — 静态图标 + 站名（抓不到 → 首字色块）
2. **站点页** — 顶部 tab 照真站；分类 / 多级标签**展开 + 横滑**
3. **卡片** — 封面 + 标题 + 发布时间（标题下方）；封面角标：**时长 ＞ 集数 ＞ 播放量**
4. **布局** — 竖版站 3 列 / 横版站双列（按封面形状）
5. **列表细节** — 排序行间距 `top6 / left2 / right2 / bottom3`
6. **详情页**
   - 播放器固定顶部，下方信息单独滚动
   - 标题 · 发布时间 · 集数 · 时长
   - 选集（吃瓜竖排 / 剧集横排 + 自适应换行；多页并发；失败可重试）
   - 清晰度 — 按站点默认分辨率（第一条）；两种源形态都可见；手选过的档跟随该视频记忆
   - 简介 · 剧照（横滑；点开查看器）· 分类标签（可点）
   - **推荐视频** — 标题取真站叫法；没有则整块不显示；**布局照真站**（竖排单列 / 横版封面一行 2 列 / 竖版封面一行 3 列）
7. **图集** — 卡片进详情；图集弹窗 = 遮罩 `black45` · 点空白关 · 圆角 10
8. **搜索** — 有则显示（AppBar 右侧）
9. **点击** — 一律进详情
10. **取图 / 取源** — 图片带站点请求头（`FetchedImage`）+ 失败有占位；条目自带源优先（0 网络）

### 二、短片
1. **列表** — 2 列（3:4）；点卡片进竖屏瀑布流
2. **播放器** — 自带控制条关掉
3. **流内** — 播放中隐藏；暂停显示「一条标题 + 一个 X（圆底）+ 一个 ▶」
4. **换源** — 盖「黑底 + 封面 + 转圈」+ `IgnorePointer`
5. **手势** — 「↑/↓ 下一条」保留；「▶/◀ N 秒」不要
6. **三态** — 续拉失败 ↻ 重试；「到底 / 失败 / 空」分开

### 三、直播
1. **入口** — 站点宫格（与点播同套）
2. **站点页** — 下划线 tab + 筛选按钮；不带底栏
3. **房间列表** — 2 列竖版卡（3:4 · 主播名 · 观看数 · LIVE；直播中=清晰图 / 非直播=模糊图；跳过付费房；空态专文案；底部「上滑加载更多」）；主 tab 下拉刷新
4. **房间页** — 铺满整屏；只一个 X + 一行状态字；点屏幕 toggle X；X **76×76 · 图标 32 · 左距 5**；零控件；最左 24px 不响应点屏
5. **播放** — 取最高档

### 四、三类通用
- 缺则隐藏；空则省略；骨架；失败写原因；文字黑白自适应；**所有文案照真站**；有接口走接口 / 无接口预热
- **筛选弹窗** — `SimpleDialog`（标题 16 · 选项 14 · 选中橙 + 勾）；遮罩 / 圆角 / 尺寸用系统默认

### 五、逐站差异（**部分用户指定，仅作参考**）
| 站点 | 卡片额外元素 | 覆写的站点事实 |
|---|---|---|
| 黄果短剧 | badge · 集数 · 合集 · 加密接口 | 自己解析播放源 |
| Pektino | coverAspect · badge · 集数 · 加密接口 | （默认） |
| Pornhub | coverAspect · badge · 集数 | 点卡片去向 · 筛选行 · 明星 tab |
| xHamster | coverAspect · badge · 集数 · 加密接口 | 短片路径 · 筛选行 · 明星 tab |
| XVideos | badge · 集数 · 加密接口 | 点卡片去向 |
| 快猫 / 91porna / 51吃瓜系 | badge · 集数 · 加密接口 | （默认） |
| 麻豆社 / Hanime1 | badge · 集数 | （默认） |

### 六、改过多次的项（**只留终值，用户指定，仅作参考**）
- **房间页 X** — 左距 5 · 图标 32 · 方块 76×76
- **控制条** — 短片=关掉自带；房间页=零控件
- **卡片时间** — 标题下方
- **清晰度** — 站点默认（只有直播取最高）
- **日志页导出** — 直接分享源文件

### 七、日志（**全量定义，仅 APP 端行为**）
- **全量 = 不管大小、不管重要性，全部输出**（成功路径也打，不只错误）
- 覆盖**所有站点 × 所有页面 × 所有分支**（列表/翻页/搜索/分类/筛选/详情/选集/取源/播放/短片/图集/直播…每次请求、每次解析、每个分支的进入·退出·失败）
- **没有静默路径**：任何 `return` / 提前返回 / `catch` 都要有对应日志
- **不采样、不节流、不省略、不截断**；每条含：站点名 · 位置（文件:函数/分支）· 关键输入（URL）· 结果（条数/命中/耗时 ms/错误原文）
- **唯一例外（安全）**：`pkey` / `token` / `auth_key` / 查询串密钥**必须脱敏**
- **两处输出**：控制台（开关在设置页「错误日志」上方）+ 出错进「设置 → 诊断 → 错误日志」文件
- **关着时零开销**（字符串都不拼）；打开后**复现一次即拿到完整一份**

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
**约定：每次构建 +1** ✓（当前 **1.2.1**）
（规则："每段 0~9、满 9 进位" ✓ 见 `lib/app_version.dart` ✓；CI 用"去点"当 `--build-number` ⇒ 1.2.0⇒120 ✓）

## 四、构建流程（唯一验证手段 ✓）
`checkout → Setup Flutter 3.24.5 → flutter create → 证书 → 改 iOS 工程 → ExportOptions →`
`→ 代码检查 (flutter analyze lib)   ← 一次列出【全部】Dart 错误 ✓`
`→ Flutter build IPA → 按版本号重命名 IPA → 上传 artifact → 发布 Releases → 列出产物`

- **为什么要 analyze**：CFE 每轮只抛第一条错误 ✗（曾熬 15+ 轮）；analyze 一次给全（实测一次 **87 条 error** ✓）
  带 `--no-fatal-infos --no-fatal-warnings` → 只有 error 拦构建 ✓；**只查 `lib`** ✓（`test/` 是 flutter create 的模板，与仓库无关 ✗）
- **产物三处** ✓：Actions artifact（名固定 `kpxx-ipa` ✓）· **Releases**（ipa 直下 ✓，tag `v<日期>-<时分>` ✓）·
  **桌面** `C:\Users\Administrator\Desktop\kpxx-<版本>.ipa`（**文件名必须带版本号** ✓ —— 用户 2026-10-06 明确要求 ✓；
  ⚠️ 早先写的"桌面 `kpxx.ipa`（文件名固定）"**是错的** ✗，2026-10-06 已改 ✗）

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
**事实**：`shorts_feed_page.dart:175` 的 `srcs.isEmpty` 仍是**静默返回**（现状：未改） ✗ —— 应改为给用户提示（体验项 ✓，本轮未动 ✗）。


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

### 报告（app 侧问题 / sim 侧无改动）
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
--- 追加（2026-10-03 · 工作区改动，**未提交未构建**）短片体验两处：换源遮罩（已做 ✓）+ 入口预热（现状：未实施）---
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
**② 入口预热（现状：未实施）**（在"点卡片那一刻"就开始抓详情页）—— **只给方案，未动代码** ✓：
- 现状：`home_page.dart:1161` 只传 `items: <Article>[article]`（1 条 ✓）→ 进页面 `initState` → `_open(0)`
  → **才**开始 `_sourcesOf(0)` 抓详情页（1~2 秒 ✓）→ 再 `kp.open()` 开始下媒体 ✗ → 累计几秒 ✓
- 方案：网格的短片分支（`home_page.dart:1154-1167` ✓）在 push 前**预热** `api.detail(article.url)` ✓；
  ⚠️ 但页面里的 `_srcCache` 是**页内私有** ✗ → 要落地需一个**共享的 detail→sources 缓存**（跨 3 个文件 ≈15 行 ✗）
  → 属"动到别处"，**先不动** ✗ 等用户拍板 ✓。收益 ≈ 与 push 动画重叠的 **0.5~1.5 秒** ✓；**请求数不增加** ✓（页面本来也要发这一次 ✓）。
- **明确不需要做** ✗：把预下载窗口**含当前条** —— 当前条的**源还没解析出来** ✗，而 mpv 在 `open()` 之后**本来就在下** ✓
  → 预下载它只会**重复占带宽** ✗（`_primeWindow` 显式排除当前条是对的 ✓）。
- 另一条可选（**未动** ✗，属共享播放器 ✗）：用 `NativePlayer.setProperty` 调 mpv 的起播参数
  （如 `demuxer-readahead-secs` / `cache-pause-initial` ✓）能再挤掉一点初始缓冲 ✓ —— 但那动的是 `player_widget.dart`（详情页/全屏共用 ✗）→ 等拍板 ✓。
**过程失误（自catch ✓）**：写这段时一个 `edit` 的 `new_string` 忘了把**锚点标题**带回去 ✗（还多留了一行孤立的反引号 ✗）→ 当场读回发现并补回 ✓（教训：**拿标题当锚点做替换时，new_string 必须原样含回标题** ✗）。
⚠️ 事后这行又被"按锚点插字"的脚本**从中间切开过一次** ✗（插到我的段落内部 ✓）—— 教训二：**正文里不要写标题字面** ✗，否则别人的锚点会命中它 ✓；2026-10-03 已按此修回 ✓（两半接回 ✓、伪标题删掉 ✓）。


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
**没验证的** ❓：三个 mpv 参数在**真机 libmpv** 上是否真被接受、实际省几秒（本机无 Flutter SDK/无真机 ✗）→ 装机看"起播是否更快"即可；**就算某个名字不认也不会坏** ✓（静默忽略 ✓ 播放不受影响 ✗）

---
---
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
  sim 侧已无更多提速手段 ✗；**严格 ≤2s** 只有这两条可行路径 —— ① 每条**整文件预下载**（代价：流量大 ✗）② **server 端带 Range 的缓存**（代价：要改 `server.mjs` ⇒ 触发热重载 ⇒ 按 §六-10 需先问 ✓）
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

**没验证的** ❓：编译（本机无 SDK ✗）与真机表现（tab 行压得住 / 静音 / 返回键 / keepAlive ✓）→ **只能真机验** ✓；模拟器只覆盖"布局 + 本地替身" ✓
**第 2 步（删 ≈950 行）** ✗ **未做** ✓ —— 两步走：先构建真机验过 ✓ 再删 ✓（清单已列：`shorts_feed_page.dart` 603 ✓ / `base/video_cache.dart` ✓ / `base/source_cache.dart` ✓ / `home_page` 的 push 分支与 `:152-173` 随机化 hack ✓ / `xhamster` 的 `_xhMoments*` 家族 ✓ / `site_ui` 的 `isShortsPath`+`resetShortsRandom` ✓）



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
⚠️ 新增 import `package:webview_flutter_wkwebview/...` ✓（随 `webview_flutter` 一起装的 **iOS 实现包** ✓）；
`depend_on_referenced_packages` 可能报一条 **info** ✓ **不拦构建** ✗（要消掉就往 pubspec 里显式加一行 ✓）。
**没验证的** ❓：编译（本机无 SDK ✗）；真机三件事 —— ① 内联播放、不再弹系统全屏 ✓ ② 上滑换条能自动播 ✓
③ 静音仍生效 ✓；⚠️ 若**站点自己在别处**强行全屏（或用了 iOS 不允许的 API ✓），兜底也可能压不住 ❓。



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
**#2（`_primeWindow` 并行）—— 实测后判断：**不是问题** ✗**：`_precache()` 已经**不 await** 地把窗口 6 条的 `_sourcesOf(j)` 全都发出去 ✓（`shorts_feed_page.dart:250-255` ✓ "并发跑，不 await" ✓）→ 请求本来就是并发的 ✓；`_primeWindow` 的 `await` 只是**收集已发出去的 Future** ✓ → 没有"串行等待"这个瓶颈 ✓ → **建议不改** ✗（改反而会变成"重复发起" ✓）

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

--- 追加（2026-10-03 · 工作区改动，**未提交未构建**）**#9 两份缓存合一**（用户："重复肯定要删一份" ✓）---
**留哪份** ✓：留 `lib/base/source_cache.dart`（底座 ✓ 唯一与站点无关 ✓）；删 `api.dart` 的两张静态表（`_lazyCache` 60 条 FIFO + `_lazyInflight` ✓）。
**三条契约怎么保住的** ✓
1. **出错要抛** ✓ → `SourceCache.get()` 加 `rethrowOnError`（默认 `false` ✓ = **短片路一字不变** ✓；详情路传 `true` ✓ = **原样抛** ✓，播放器 `player_widget.dart:789` 的"起播失败→重抓"照旧 ✓）
2. **空结果不缓存** ✓ → `source_cache.dart:50` 里 `if (out.isEmpty && rethrowOnError) _map.remove(url)` ✓（与旧 `if (out.isNotEmpty)` 才写缓存**逐字等价** ✓；短片路照旧缓存空 ✓ **不变** ✗）
3. **key 命名空间** ✓ → 详情 `'d|url'`（`api.dart:222-226` ✓）· 短片 `'s|url'`（`home_page.dart:1155` / `shorts_feed_page.dart:189` ✓）
   —— 两条取名策略不同（`sourcesFromHtml`/dplayer vs `api.detail` 的站点解析 ✓）→ 同 url 结果可能不同 ✗ → **绝不能共用 key** ✗
**站点分叉留在 `api.dart`** ✓：`_fetchSourcesAt`（`:229-247` ✓）里的 `_ui?.sourcesFromHtml(html)`（黄果 ✓，`huangguo.dart:35` ✓）＋通用 `.dplayer` 兜底**一个字没动** ✓（底座不认识站点 ✓ 写死规则一 ✓）
**行为差异清单（改前 → 改后）✓**：正常 ✓ 同 ｜ 空 ✓ 同（不缓存）｜ 出错 ✓ 同（抛）｜ 并发同 url ✓ 同（共享同一个 Future ✓）｜ ⚠️ **仅一处不同** ✗：容量 **60 FIFO → 80 LRU** ✓（只会在极端情况下"记得更多、更准" ✓ 不会更差 ✓）

---

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




--- 追加（2026-10-04 本次构建 1.0.19 —— 短片左右滑改成进度条式反馈 + 清最后 warning）---
**① 清最后 1 条 warning**：settings.dart:335 第二个 ! 去掉（同表达式内提升有效、跨语句无效）。
**② 短片左右滑算法（用户拍板改回我们自己的快进快退）**：改前一屏 120 秒 + 18pt 死区 => 右滑 9 秒起步；改后一屏 30 秒（_kSeekSecondsPerScreen）、先减 18pt 死区、竖向为主整个不 seek（|dy|>=|dx|）。
**③ 反馈改进度条式（用户拍板）**：删掉 _toast（▶/◀ N 秒 SnackBar），改成拖动时贴底进度条跟手（_seekPreview + LinearProgressIndicator，对齐详情页 _SwipeSeek 观感），松手才 seekExact。算法一行未动。
**待真机调**：_kSeekSecondsPerScreen 30（嫌快慢改一个数）；预览条观感（shorts_feed_page.dart:559-596）；_seekTargetFor 与 _seekEnd 是两份同值算法（可合并）。


--- 追加（2026-10-04 本次构建 1.0.20 —— 短片两条进度条并一条）---
**问题**：上一版拖动时出现两条进度条（新加的 _seekPreview 细条 bottom:6 + 原 Slider bottom:14）。
**修**：删掉新加的 Positioned 整块（LinearProgressIndicator，全库 0 次）；原 Slider 外包 ValueListenableBuilder<Duration?>(_seekPreview)，`pos = pv ?? s.position`，Slider value 与右边时间都吃 pos → 拖动时原 Slider 跟手滚、松手 seekExact。Slider.onChanged（直接拖拇指）保留。净 -68 行。
**待真机调**：_kSeekSecondsPerScreen 30；_seekTargetFor 与 _seekEnd 两份同值算法可合并。

---
## 追加（2026-10-03 · **sim 侧第 7 轮**）把 sim 对齐到 App 1.0.20 形态（**只改 `sim/index.html` ✓，未提交** ✗）---
**背景** ✓：App 早就回退 WebView、回到自研瀑布流（1.0.17 起 ✓），而上一轮我把 sim 短片 tab 做成了"直接内嵌播放器" ✗ → 对不上 ✗。

**改了什么（3 处，全在 `sim/index.html` ✓）**
1. **短片 tab 回到 2 列卡片网格** ✓（`viewList` ✗→✓）：删掉那段"提前 return + `mountShortsFeed`"的短路 ✗
   → 走回**现成的通用卡片路**（`renderCards` ✓，`shortsTab` 那套 `portrait`/`.shorts` 2 列样式本来就在 ✓）
   → **点卡片**才进瀑布流 ✓（老接线也在：`renderCards` 里 `a.url.startsWith('/shorts/')` → `viewShortsFeed` ✓）
   ⚠️ `mountShortsFeed`/`unmountShortsFeed` 函数**留着**（`/shorts…` 独立页仍用 ✓），只是**不再挂到这个 tab** ✗
2. **卡片数据改走预热池** ✓（`fetchList` 的短片分支 ✗→✓）：第 1 页 = `shortsPool`/`shortsFirstP`（**moments 条目：自带封面 + 片源** ✓）
   → 卡片点开就是"设上 src 出画" ✓（**0 网络** ✓ 保留）；第 2 页起照旧走 `/api/v1/moments?page=N` ✓
   ⚠️ 以前第 1 页走页面 JSON 那 45 条 ✗：**有封面但没片源** ✗ → 点开要逐条抓详情页（5~15s ✗）
   ⚠️ 副作用（可接受 ✓）：`loadMore` 有"首屏够 8 张才一次画完"的规则（短片阈值 8 ✓），池子第 1 页 5~6 条 →
   会**自动补 1~2 页**再画（实测约 3~5 秒 ✗ 才出网格）；换来的是**每张卡点开即播** ✓
3. **左右滑 = 快进/快退按 App 1.0.20 口径重做** ✓（手势块 ✗→✓）：
   ① **先减 18pt 死区** ✓ ② **一屏 = 30 秒** ✓（不再是"整条时长"✗）③ **按距离成比例** ✓
   ④ **拖动时跟手**：进度条 + 时间跟着手指走 ✓、**不写 `currentTime`** ✓ → **松手才跳** ✓
   ⑤ **删掉「▶/◀ N 秒」提示** ✗（App 已删 ✓ → sim 照删 ✓；上下滑的「↑/↓ 下一条」提示保留 ✓）
   ⚠️ 修了一个真 bug ✓：视频此时还在播 → `ontimeupdate` 每秒 4 次会把跟手画的进度条/时间**拽回去** ✗
   （实测 `ptime` 一直是 `00:00 / 00:16` ✗）→ `upd()` 开头加 `if (window.__feedScrub) return;` ✓ 修好 ✓

**保留 ✓**：`getHtml` 20 秒超时 ✓ · 条目自带源 0 网络 ✓ · 滚动 preconnect ✓ · 预热收紧（3 页 / 第 1 页立刻 / 其余 2 并发 ✓）· **静音** ✓

**CDP 冒烟（端口 = **我自己的 8788** ✓，Edge headless + 手机 UA ✓，**全程静音** ✓，`--mute-audio` ✓）**
```
短片 tab   ：卡片 11 张 · 封面 11 · 标题 11 · **列数 2** ✓ · 内嵌播放器未挂起 ✓ · tab 行 [影片/分类/色情明星/短片] ✓
点卡片     ：进流 ✓ 起播 ✓（readyState=4 · muted=true · volume=0 ✓）**到出画面 2248ms** ✓ · **进度条只有 1 条** ✓
右滑 100px ：拖动中 currentTime 未动 ✓（松手才跳 ✓）· **时间跟手 ✓**（拖动中显示 00:06 / 00:16 ✓）
             松手增量 **+7.17s**（按公式 (100−18)/370×30 = **6.65s** → 误差 0.52s = 拖动期间片子自己在走 ✓）→ **成比例 ✓**
左滑 60px  ：**−2.85s**（公式 −3.40s，同量级 ✓）
12px 小划  ：**不 seek** ✓（死区 18pt 生效 ✓）
上滑       ：换条 ✓（0→1 ✓，静音 ✓）· 单击：暂停 ✓（muted=true, volume=0 ✓）
提示       ：`#fhint` 空且隐藏 ✓（**没有「▶/◀」** ✓）· **无未捕获异常** ✓
日志       ：`短片取源 #1：条目自带 2 条（…480p.h264.mp4）` ✓ · `短片预热：17 条（带源 17 条）用时 4543ms` ✓
```
**约束 ✓**：只改 `sim/index.html` ✓（`server.mjs` 本轮**没动** ✓）；`lib/**` 一格没碰 ✗；**没 commit 没 push** ✗；
临时脚本/Edge profile 全删 ✓；**我自己的 8788 实例已停**（PID 15384 ✓，是**我**起的 ✓）；用户进程全程没碰 ✗（8787 无人在跑 ✓）


--- 追加（2026-10-04 本次构建 1.0.21 —— Top5 优化 + 实测依据注释）---
**Top5 全部落地**：#1 图片内存缓存 LRU（命中挪尾）+ #2 字节上限 64MB（硬上界，从队头逐张砍到合规）；#5 .hls 分段字节计入 200MB 总量；#4 预取补两处（搜索列表 warm + 短片封面 warm）；#13 _seekTargetFor/_seekEnd 合一（公式只剩一份）；#7 详情页 _SwipeSeek 松手立即清（去掉 600ms，与短片一致）。
**实测依据（sim-dev 2026-10-04）**：封面 13 张多站样本 中位 52.1KB / p90 425.3KB / 最大 464.8KB -> 64MB=400x164KB=中位3倍余量；短片 m3u8 分段实测 0.35/0.82/1.19MB（码率 54~72KB/s）-> 200MB≈250 条。唯一推算值 2.53MB 标 🔍非实测。
**#7 副作用（有据）**：松手立即清 -> 进度条在 seek 落地前会短暂回跳一帧（几十 ms，原来 600ms 就是避免这个）。回退 = 恢复 600ms（字段 _swipeHoldTimer 未删）。
**全库模糊词（可能/应该/估计/大约/推测/预计）复检 0 命中。**


--- 追加（2026-10-04 本次构建 1.0.22 —— 左右滑 seek 松手不回跳）---
**问题**：1.0.21 详情页 #7 改成松手立即清 preview 后，进度条会在 seek 落地前短暂回跳一帧（用户真机看着难受）。
**修（详情页 + 短片页都上 A 方案）**：松手后扛预览 + 事件驱动清 —— 每 50ms 查引擎位置，离目标 <=500ms 就清；兜底 600ms 强制清（原 1 秒，用户拍板 600）。
**短片页另加**：_seekStart 里 1 行 _seekSettle?.cancel()（按下杀旧 timer，消除快速连划时旧 timer 误清新预览的边界）。
**未动**：seek 算法（竖向否决/18pt 死区/30 秒屏/seekExact）一字未改；500ms 阈值未动。

---
## 追加（2026-10-03 · **sim 侧第 8 轮**）底栏加「直播」入口（**空壳页** ✓，只改 `sim/index.html` ✓ 未提交 ✗）---
**用户拍板** ✓：底栏顺序 = **模块 → 直播 → 设置** ✓；这步**只加入口页** ✗（站点入口等以后再放 ✓）；
先模拟器跑通、再复刻到 App ✓。**对齐 App 的导航结构** ✓（App = `IndexedStack` + `BottomNavigationBar`，`lib/main.dart:127-146` ✓）。

**改了 4 处（全在 `sim/index.html` ✓）**
1. **底栏 markup**（原 2 项之间插一项 ✓）：`<div class="item" data-nav="live">` + 直播语义图标（**电视框 + 天线** 的内联 SVG ✓，
   与原有 `grid_view`（实心）/`settings`（描边 1.8）同一套画法 ✓）+ `<span>直播</span>` ✓
2. **点击接线**（`$('nav')…forEach` 里 ✓）：原来是 **两路** `if (grid) viewGrid(); else viewSettings();` ✗ →
   改成 **三路** ✓（`grid`/`live`/`settings` ✓，仍带 `stack = []` ✓）
3. **新增 `viewLive()`** ✓（照 `viewSettings()` 的壳写法 ✓）：`showNav(true)` ✓ · `tabs` 隐藏 ✓ ·
   appbar 标题「直播」✓（占位不返回 ✓，与「模块/设置」一致 ✓）· `applyBg()` ✓ ·
   内容 = 一张 `.scard`：`▶ 直播` + **「直播站点入口即将上线」** + 说明句 ✓（无任何站点 ✗）
4. **`?nav=live` 直达** ✓（照 `?nav=settings` 那套 ✓，截图/调试方便 ✓）

**CDP 冒烟（端口 = **我自己的 8788** ✓，Edge headless + 手机 UA ✓，`--mute-audio` ✓；本轮**没有任何播放** ✗）**
```
1_底栏   ：项数 3 ✓ 文案「模块/直播/设置」✓ 选中=模块 ✓ 图标 3 个 ✓
2_点直播 ：选中=直播 ✓ 标题=直播 ✓ 占位文案在 ✓ tabs 隐藏 ✓ 底栏仍可见 ✓
           body 开头「▶直播 直播站点入口即将上线 这里先占位：底栏结构已与 App 对齐 ✓（模块 → 直播 → …」
3_点模块 ：选中=模块 ✓ 站点 14 个 ✓（正常回宫格 ✓）
4_点设置 ：选中=设置 ✓ 标题=设置 ✓ 「播放记录」卡在 ✓
5_再回直播：选中=直播 ✓ 标题=直播 ✓ 占位文案在 ✓（来回切都正常 ✓）
6_无未捕获异常 ✓；页面上正在播放的 <video> 数 = 0 ✓（本轮不涉及播放）
```
`node --check` 内联脚本 = **0** ✓
**约束 ✓**：只改 `sim/index.html` ✓（`server.mjs` 本轮**没动** ✓）；`lib/**` 一格没碰 ✗；**没 commit 没 push** ✗；
临时脚本/Edge profile 全删 ✓；**我自己的 8788 已停**（PID 10700 ✓）；**用户那个 8787 全程没碰**（现 PID 18744，用户自己起的 ✓）

---

---
## 追加（2026-10-03 · **sim 侧第 10 轮**）直播页**重做成三级结构**（站点宫格 → 站点页 → 筛选弹窗 ✓，只改 `sim/index.html` ✓ 未提交 ✗）---
**用户拍板的新方案** ✓（**推翻**第 9 轮的"全页铺开" ✗）：
```
底栏「直播」= 直播区 → 站点按钮宫格（照模块页 ✓，目前 1 个「xHamster直播」✓）
   └─ 点进去 = 站点页（照 **Pektino 布局** ✓）→ 顶部 4 主分类 tab + 一条「筛选」→ 弹窗按组列出当前 tab 的子分类
```
**改了 3 处（全在 `sim/index.html` ✓）**
1. **直播区 `viewLive()`** ✓：改成**站点宫格** —— 直接复用模块页那套 `.grid/.tile`（图标走现成的 `/icon?name=xHamster` ✓ + `iconFallback` 兜底 ✓），
   点 tile → `viewLiveSite()` ✓；清单 `LIVE_SITES`（1 个 ✓，以后加站点就加一行 ✓）
2. **站点页**（新 ✓ `viewLiveSite()` + `renderLiveSite()`）：appbar「xHamster直播」+ 返回 ‹ ✓ ·
   **顶部 4 主分类 tab**（`.lv-tabs/.lv-tab` ✓ 沿用第 9 轮那套）· 下面**照 Pektino 的筛选行**（复用 `.pkbar` + `<button>` ✓）
   一个「筛选」按钮 ✓（选中后显示「筛选：<名字>」+「重置」✓）· 正文只留说明与"将打开：<URL>"✓ —— 子分类**不铺开** ✗
3. **筛选弹窗 `openLiveFilter()`** ✓：复用**通用** `phChipDlg` ✓（它本来就支持 sections 多组 ✓）——
   `sections` = 当前主分类的 groups（`label` = 组名做分组标题 ✓，`items` = `[path, 名字]` ✓，`current` = 已选项 ✓）
   → 点一个 = **模拟跳转** ✓（把 `https://zh.xhamsterlive.com<path>` 摆到页面上 + 写日志 ✓，**不加载、不播放** ✗）
   旧的 `openLiveCat()` 保留但只做同一件事 ✓（不再有整页铺开 ✗）；`renderLiveCat()` 与其铺开样式**已删干净** ✓（扫过无残留 ✓）
   **数据一个字没动** ✓：`LIVE_MAIN` 211 条照用（女主播58 / 情侣36 / 男主播60 / 跨性別57 ✓）
   ⚠️ 两个坑照旧避开 ✓：「全部分类」= `/tags/<main>` ✓；无 `/<main>/best` ✓

**CDP 冒烟（端口 = **我自己的 8788** ✓，Edge headless + 手机 UA ✓，`--mute-audio` ✓；本轮**无任何播放** ✗）**
```
1_直播区 ：站点按钮 **1 个** ✓ 名称「xHamster直播」✓ 底栏「模块/直播/设置」✓
2_站点页 ：标题「xHamster直播」✓ 主分类 tab「女主播/情侣/男主播/跨性別」✓ 选中=女主播 ✓ 有「筛选」按钮 ✓
           **页面里铺开的子分类按钮数 = 0** ✓（确实不铺开 ✓）
3_筛选弹窗：打开 ✓ 标题「xHamster直播 · 女主播」✓ **组标题命中 7 个** ✓（特别/年龄/种族/体型/头发/私秀表演/最受欢迎）
           **芯片数 58** ✓（= 女主播转录总数 ✓）
4_选全部分类：弹窗关闭 ✓ 页面出现「将打开：**https://zh.xhamsterlive.com/tags/girls**」✓ 按钮变「筛选：全部分类」✓
5_男主播筛选：切 tab 后 **芯片数 60** ✓ 且弹窗里有**「性取向」组** ✓（该主分类独有 ✓）
6_选直男 ：**https://zh.xhamsterlive.com/men/straight** ✓ 按钮变「筛选：直男」✓
7_返回   ：左上 ‹ 回直播区 ✓（1 个站点按钮 ✓ 标题「直播」✓）
8_其他   ：正在播的 <video> = 0 ✓（本轮无播放 ✓）· **无未捕获异常** ✓
```
`node --check` 内联脚本 = **0** ✓；`.lv-btn/.lv-group/.lv-back` 等旧铺开样式**零残留** ✓（grep 复核过 ✓）
**约束 ✓**：只改 `sim/index.html` ✓（`server.mjs` 本轮没动 ✓）；`lib/**` 一格没碰 ✗；**没 commit 没 push** ✗；
临时脚本/Edge profile 全删 ✓；**我自己的 8788 已停**（PID 19040 ✓）；**用户那个 8787 全程没碰**（现 PID 18744 ✓）

---
## 追加（2026-10-03 · **sim 侧第 11 轮**）直播页**接房间列表**（接口 B ✓，只改 `sim/index.html` ✓ 未提交 ✗，**没动 `server.mjs`** ✓）---
**用户拍板** ✓：直播站点页下面接**房间列表**（**先不做播放** ✗）。

**代理怎么走的（关键 ✓，按你的要求没擅自动服务端 ✓）**
- 现成的 **`/proxy?url=<绝对URL>`** 就是**通用转发**（`server.mjs` 里 `fetchUrl(target)` 原样回 body ✓）→
  **直接用** ✓，**不需要改 `server.mjs`** ✓（该文件本轮 **0 改动** ✓ —— 它那 `+11` 是很早以前加的 `/shorts` 路由 ✓）
- UA ✓：`/proxy` 用的正是模块级 `UA` = **iPhone UA** ✓（= 用户 recon 说"iPhone UA 可以 ✓"的那套 ✓）；无 cookie ✓
- 浏览器直连会被 CORS 拦 ✗ → 走本机 `/proxy` 就没有跨域问题 ✓（同源 ✓）

**改了 1 个文件 4 处（全在 `sim/index.html` ✓）**
1. **接口调用** ✓：`liveFetch(tag, offset)` → `GET /proxy?url=` + `https://zh.xhamsterlive.com/api/front/models?limit=60&offset=N&primaryTag=<tag>` ✓
   （`LIVE_PAGE=60`、`LIVE_MAX=1000` ✓ 照 recon ✓）；4 主分类 → tag 用**名字映射** `LIVE_TAG_OF` ✓（`女主播→girls / 情侣→couples / 男主播→men / 跨性別→trans` ✓，
   不按下标 ✗ 免得以后加 tab 错位 ✗）
2. **列表状态 + 翻页** ✓：`liveRooms{tag,offset,items,loading,done}` ✓；`#body` 滚到距底 240px → `offset += 60` ✓；
   到底三条判据（这页空 / 已到 `filteredCount` / 撞 1000 ✓）✓；换主分类才重拉 ✓（同一 tag 有数据就复用 ✓ 不白拉 ✗）
3. **2 列竖版房间卡** ✓（新样式 `.lv-rooms/.lv-room` ✓）：封面 3:4 + 主播名 + 观看数 + 在线标 ✓ ——
   `username` / `viewersCount` / `isLive` / `isOnline` ✓；封面 = `img.doppiocdn.net/<snapshot|snapshot_blurred>/<id>/<snapshotTimestamp>` ✓，
   **我定的规则**（可改 ✓）：**直播中 → 清晰图 ✓；非直播 → 模糊图 ✓**，`onerror` 再退回另一张 ✓；图**也走 `/proxy`** ✓
4. **点卡片 → 房间页占位** ✓：摆出 `https://zh.xhamsterlive.com/<username>` ✓ + 明写"不加载/不播放" ✓ + 返回列表 ✓
   ⚠️ **子分类筛选仍未接列表** ✗（按你说的"暂不接"✓ —— 筛选按钮/弹窗**保留原样** ✓，只在页面上写明"还没接" ✓ 免得误判 ✓）

**CDP 冒烟（端口 = **我自己的 8788** ✓，Edge headless + 手机 UA ✓，`--mute-audio` ✓；本轮**无任何播放** ✗）**
```
1_女主播列表：**60 张卡** ✓ 首卡 名=winter11 ✓ 有封面 ✓ 封面走 /proxy ✓
              封面地址 = https://img.doppiocdn.net/snapshot/197467228/1791088650 ✓（与 recon 形态一致 ✓）
              观看数「3651 人」✓ 在线标「LIVE」✓ LIVE 标 60 个 ✓
              日志：`直播列表：primaryTag=girls offset=0 → 60 条（累计 60 / 1000）` ✓
2_切情侣   ：**换了** ✓（首条 Citymup，与女主播首条不同 ✓）日志 `primaryTag=couples offset=0 → 60 条（累计 60 / 479）` ✓
3_切男主播 ：换了 ✓（Mrwangjjkk ✓）日志 `primaryTag=men …（累计 60 / 1000）` ✓
4_切跨性別 ：换了 ✓（KeenMazikeen69 ✓）日志 `primaryTag=trans …（累计 60 / 648）` ✓
5_房间占位 ：名字在页上 ✓ 含 `https://zh.xhamsterlive.com/<username>` ✓ 明写不播放 ✓ 有返回 ✓
6_回列表   ：卡片仍在（60 ✓）
7_翻页     ：滚到底 → **60 → 120 张** ✓ 提示「上滑加载更多」✓ 日志 `offset=60 → 60 条（累计 120 / 648）` ✓
8_其他     ：正在播 <video> = 0 ✓ · 底栏「模块/直播/设置」✓ · **无未捕获异常** ✓
```
`node --check` 内联脚本 = **0** ✓
**约束 ✓**：只改 `sim/index.html` ✓；**`server.mjs` 本轮 0 改动** ✓；`lib/**` 一格没碰 ✗；**没 commit 没 push** ✗；
临时脚本/Edge profile 全删 ✓；**我自己的 8788 已停**（PID 19080 ✓）；**用户那个 8787 全程没碰**（现 PID 18744 ✓）

---
## 追加（2026-10-03 · **sim 侧第 12 轮**）点主播卡片 → **竖版全屏真实流**（只改 `sim/index.html` ✓ 未提交 ✗，**`server.mjs` 0 改动** ✓）---
**用户原话** ✓：① 点卡片**直接进竖版全屏**（不是占位 ✗）② **只有左上角一个 X**（不要多按钮 ✗）
③ **点屏幕显示/隐藏 X**（toggle ✓）④ **直接放真实流** ✓；**静音** ✗ 没得商量 ✓

**⚠️ HLS 直连 vs proxy 的结论（实测 ✓）**：**直连就行，不用过 `/proxy`** ✓✓
- 实测 `edge-hls.doppiocdn.media` 的 master 清单：HTTP 200 + `application/vnd.apple.mpegurl` + **`ACAO: *`** ✓；
  变体 URL 回 **302**（跳到 `media-hls.doppiocdn.media` ✓）且**响应也带 `ACAO: *`** ✓ → **hls.js 能跨域直连** ✓
- 所以**没有**用 `/proxy` 包 HLS ✓ → **也就不存在"分段路径要重写"** 的问题 ✓（那条路 sim 里本来有 `hlsProxy`/`/vproxy` 备着 ✓，这次**没用上** ✗）
- （冒烟里那 14 条经 `/proxy` 的 doppiocdn 资源是**房间封面图** `img.doppiocdn.net` ✓ —— 封面本来就是设计成走 proxy 的 ✓，不是 HLS ✓）

**改了 1 个文件 2 处（全在 `sim/index.html` ✓）**
1. **`viewLiveRoom(username)` 重写** ✓（原来是"房间页占位"✗）：从 `liveRooms.items` 按 `username` 找 model ✓ →
   在 `.screen` 上盖一层 `.lv-player`（`position:absolute; inset:0; z-index:70` ✓ = **铺满整个手机屏，含 appbar 与底栏** ✓）；
   播放用列表里的 **`hlsPlaylist`** ✓（**直连** ✓）；`ensureHls()` 懒加载 hls.js ✓（放不了 HLS 的环境退回原生 `canPlayType` ✓）；
   **静音** ✓（`muted` 属性 + `muted=true; volume=0` ✓）
2. **UI 极简** ✓：层里**只有**一个 X（`#lvx` ✗ 默认 `display:none` ✓）+ 一行状态字（加载中/缓冲中/出错 ✓，播放中为空 ✓）——
   点层 = `toggle('on')` ✓（显示→隐藏→显示 ✓，实测三下 = `true → false → true` ✓）；点 X = 关闭 ✓（`stopPropagation` ✓）
   **关闭 = 只 remove 浮层** ✓（列表 DOM 与 `liveRooms` 一个字没动 ✓）→ **回列表不重拉** ✓✓
   ⚠️ 顺带删了第 11 轮那个"房间页占位"实现与 `liveRoomUser` 变量 ✓（不铺旧路 ✗）

**CDP 冒烟（端口 = **我自己的 8788** ✓，Edge headless + 手机 UA ✓，`--mute-audio` ✓，播放**全程静音** ✓）**
```
1_全屏层 ：有层 ✓ **铺满手机屏**（370x804 = 屏的 370x804 ✓）z-index=70 ✓ **X 初始隐藏** ✓ **X 只有 1 个** ✓（另 1 个 div 是空状态文字 ✓）
2_起播   ：**起播 ✓（3885ms）** readyState=4 ✓ currentTime 在走 ✓ `muted=true volume=0` ✓
           hls 资源直连 CDN 18 条 ✓（hlsPlaylist 原样直连 ✓ 没走 /proxy ✓）
3_X显隐  ：点一下 显示 ✓ → 再点 隐藏 ✓ → 第三下 显示 ✓（true → false → true ✓ 完全符合要求 ✓）
4_关闭   ：X 关掉 → **层没了 ✓ 卡片还在 60 张 ✓ 与关前一致 ✓ 且**关后**没有再拉列表 ✓✓（状态保留 ✓）
           列表首卡仍是 winter11 ✓（就是关掉的那条 ✓）
5_其他   ：关掉后在播的 <video> = 0 ✓（流停了 ✓）· 底栏「模块/直播/设置」✓
           日志：`直播房间：winter11 · 1080×1440 · hls=https://edge-hls.doppiocdn.media/hls/197467228/m…` ✓（1080×1440 = 竖版 ✓）
**无未捕获异常** ✓
```
`node --check` 内联脚本 = **0** ✓
**约束 ✓**：只改 `sim/index.html` ✓；**`server.mjs` 本轮 0 改动** ✓（它那 `+11` 是很早以前加的 `/shorts` 路由 ✓）；
`lib/**` 一格没碰 ✗；**没 commit 没 push** ✗；临时脚本/Edge profile 全删 ✓；
**我自己的 8788 已停**（PID 9336 ✓）；**用户那个 8787 全程没碰**（现 PID 18744 ✓）

---
## 追加（2026-10-03 · **sim 侧第 13 轮**）直播**筛选真正接上**（用户："筛选点了没反应" ✗ → 修好 ✓；只改 `sim/index.html` ✓ 未提交 ✗，**`server.mjs` 0 改动** ✓）---
**用户给的 recon 映射** ✓ **原样照抄** ✗（不自己猜 ✗）；**未映射**的标出来不下手 ✗。

**改了 1 个文件 5 处（全在 `sim/index.html` ✓）**
1. **`LIVE_TAG_MAP`**（新 ✓ 硬编码表，**71 条** ✓）：slug → 站点筛选 tag，**逐条照抄 recon** ✓（特别/年龄/种族/体型/头发/私秀/最受欢迎 4 分类共用/男主播专属/情侣专属 ✓）
   ⚠️ **我没把 tag 塞进 `LIVE_MAIN` 的 211 条里** ✗→✓ —— 改成**同一张硬编码表 + 路径末段取值** ✓（`liveSlug()`/`liveTagOf()` ✓）：
   效果一样、**少改 211 处**（不易抄错 ✓）；要按你原话塞进 item 里也可以 ✓ 说一句我就挪 ✓（1 行的事 ✓）
2. **`liveFetch(tag, offset, filterTag)`** ✓：不带筛选 = **和上一轮跑通的那条一模一样的 URL** ✓ 别乱加参数 ✗；
   带筛选才追加 `&filterGroupTags=[["<TAG>"]]&parentTag=<TAG>` + **recon 原样尾巴** ✓（`sortBy=stripRanking` ✓ + 那串开关 ✓ + `specialEventTagIds=["oktoberfest"]` ✓）
3. **`liveRooms` 加 `filter` 字段** ✓；选中 = `filter=tag` + **offset 归 0** + 清空 + 立刻重拉 ✓；**翻页照旧带 filter** ✓（见下实测 ✓）
4. **弹窗 `openLiveFilter()`** ✓：**未映射的芯片标「（未映射）」** ✓（女主播 2 个：Oktoberfest Party / 全部分类 ✓；男主播 8 个、跨性別 6 个 ✓）；
   点**已映射** → 真筛选 ✓；点**未映射** → **不筛选、不硬猜** ✗（只写一条日志 ✓ 并把站点页地址摆出来 ✓）；"已选"高亮改成按 **filter tag** 回标 ✓
5. **重置** ✓：清 `filter` + offset 归 0 + 回默认热门 ✓（按钮文案回「筛选」✓）；页面说明改成"已筛选/未筛选" ✓（不再写"还没接"✗）

**映射复验（脚本跑的 ✓ 不是眼看 ✓）**：表 **71 条** ✓；211 条子分类里 **193 已映射 / 18 未映射** ✓；
未映射清单 = `oktoberfest-party`、`/tags/<main>`（4 个"全部分类"✓）、男主播的 `big-nipples/hairy-armpits/fingering/creampie/big-cocks/shower` ✗、跨性別的 `big-clit/big-nipples/hairy-armpits/fingering` ✗
（**正是你标了 ⚠️ 的那批 ✓** —— 全部按"标记不猜"处理 ✓）；抽查 `milfs=ageMilf · straight=orientationStraight · doggy-style=doDoggyStyle · 69-position=do69Position · cam2cam=autoTagP2P` ✓

**CDP 冒烟（端口 = **我自己的 8788** ✓，Edge headless + 手机 UA ✓，`--mute-audio` ✓；本轮**无任何播放** ✗）**
```
1_默认    ：60 张卡 ✓ 前 3 = winter11 / Citymup / saozi666 ✓ 按钮「筛选」✓ 说明「未筛选」✓
            日志 `primaryTag=girls offset=0 → 60 条（累计 60 / 1000）` ✓（**不带** filterGroupTags ✓）
2_弹窗    ：芯片 **58** 个 ✓（= 女主播子分类数 ✓）**未映射标记 2 个** ✓
3_选熟女  ：**切到了 ✓**（日志出现 `filterGroupTags=[[ageMilf]]` ✓）60 张 ✓ **首条变了** ✓（winter11 → saozi666 ✓）
            按钮「筛选：熟女」✓ 说明「已筛选 ✓ ageMilf」✓ 日志 `filterGroupTags=[[ageMilf]] offset=0 → 60 条（累计 60 / 1000）` ✓
4_筛选下翻页：滚到底 **60 → 120 张** ✓；**实锤那行**（含前缀 ✓）：
            `直播列表：primaryTag=girls **filterGroupTags=[[ageMilf]]** offset=60 → 60 条（累计 120 / 1000）` ✓✓
5_重置    ：生效 ✓ 60 张 ✓ 按钮回「筛选」✓ 说明回「未筛选」✓ 日志 `primaryTag=girls offset=0 …` ✓（**不带**筛选 ✓）
6_未映射  ：点「大屌（未映射）」→ **没有再拉列表 ✓**（请求计数前后一致 ✓）卡片数不变 ✓
            日志 `直播筛选：这条还没映射 tag ✗（大屌）→ 站点页：https://zh.xhamsterlive.com/men/big-cocks` ✓
7_其他    ：正在播 <video> = 0 ✓ · **无未捕获异常** ✓
```
`node --check` 内联脚本 = **0** ✓
**约束 ✓**：只改 `sim/index.html` ✓；**`server.mjs` 本轮 0 改动** ✓；`lib/**` 一格没碰 ✗；**没 commit 没 push** ✗；
临时脚本/Edge profile 全删 ✓；**我自己的 8788 已停**（PID 11808 ✓）；**用户那个 8787 全程没碰**（现 PID 18744 ✓）

---
## 追加（2026-10-03 · **sim 侧第 14 轮**）① 查"真·直播流到底在哪"（**用户是对的** ✓）② X 降到状态栏以下（只改 `sim/index.html` ✓ 未提交 ✗，**`server.mjs` 0 改动** ✓）---
### ① 直播流结论：**`hlsPlaylist` 那套全是"固定预览片"，不是直播** ✗✗（实测 ✓ 用户没错 ✓）
**A. `hlsPlaylist` 及其各档 = `#EXT-X-PLAYLIST-TYPE:VOD` + `#EXT-X-ENDLIST`** ✗
- `.media` / `.net` 两个主机 × `playlistType=standard/lowLatency` × `960p/480p/240p/160p_blurred` ——
  **全部 200 但全是同一份 6 段 VOD 预览** ✗：`ENDLIST=有` ✓、`MEDIA-SEQUENCE:0` ✓、首段都是 `…/cpa/v2/chunk_000.m4s` ✓
- **等 18~20 秒复测：`seq` 与分段列表一动不动** ✗ → **不是活流** ✗（分辨率 720x960/360x480/180x240 只是**同一段预览的不同编码** ✗）
**B. 真站自己的播放器打的确实是"活"的 LL-HLS** ✓ —— 网络实证（headless 打开房间页 ✓ **静音** ✓ 抓 Network ✓）：
- `https://media-hls.doppiocdn.net/b-hls-20/197467228/…_160p_blurred.m3u8?playlistType=lowLatency&preferredVideoCodec=…` ✓
- 分片名带**会话**信息：`…_h264_<seq>_<TOKEN>_<ts>_part0..3.m4s` ✓，序列 `2075 → 2080` **一路在走** ✓ → **活直播** ✓
- 但**同一形状我裸取**（两种主机/两种 playlistType/各档 ✓ 都试了 ✓）拿到的**还是那份 VOD 预览** ✗
  → ⇒ **需要会话/令牌**（guest 会话那条也**只是打码档** 160p_blurred ✓，站点页面上 `<video>` 实测 `120x160` ✓）
**C. 所以结论** ✓：**sim 里用 HLS 裸 URL 拿不到真实直播画面** ✗ —— 要真画面得
① 复刻站点的**会话/令牌**流程（更大的 recon ✗，且 guest 本身只有打码档 ✗）② 或上 **WebRTC**
（⚠️ 我这次**只确认了页面里搜不到 `whep`/`whip` 字样** ✓；WebSocket/信令那段我的输出**被截断了 ✗ 未确认** ✓ 不瞎说 ✓）。
**本轮我**没改**取流逻辑** ✗（lead 说"先别急着改"✓）—— 上一轮那个"960p→480p→240p"选档仍保留 ✓，
但它现在只是**给预览片挑更清晰的编码** ✓（例：Room Citymup 实测取到 `480p`、解码 640x480 ✓）。**等你定方向再动** ✓。

### ② X 位置（已改 ✓ + 实测 ✓）
- 状态栏 `.status` 高 **62px**（含 21px 上内边距 ✓）→ X 从 `top:10px` 改到 **`top:70px`** ✓（留 8px 缝 ✓）
- 实测（手机壳有缩放 ✓ 所以看**相对关系** ✓）：X `top=77 / bottom=105` · 状态栏 `bottom=70` ✓ → **不压状态栏 = true** ✓✓
- toggle 未受影响：点一下显示 → 再点隐藏 → 第三下显示 ✓

### CDP 冒烟（端口 = **我自己的 8788** ✓，Edge headless + 手机 UA ✓，`--mute-audio` ✓，**播放静音** ✓）
```
0_房间   ：Citymup（列表每次不同 ✓）
1_起播   ：起播 ✓ 4157ms · readyState=4 ✓ muted=true volume=0 ✓ 解码 640x480 ✓
           取流日志 `直播取流：480p` ✓（选档器工作正常 ✓）
2_X位置  ：显示 ✓ X top=77/bottom=105 · 状态栏 bottom=70/height=52 → **不压状态栏 ✓**
3_toggle ：true → false → true ✓
4_其他   ：正在播 video = 1 ✓（关掉会停 ✓ 见上一轮）· **无未捕获异常** ✓
```
`node --check` 内联脚本 = **0** ✓
**约束 ✓**：只改 `sim/index.html` ✓；**`server.mjs` 本轮 0 改动** ✓；`lib/**` 一格没碰 ✗；**没 commit 没 push** ✗；
临时脚本（6 个）/Edge profile 全删 ✓；**我自己的 8788 已停**（PID 19104 ✓）；**用户那个 8787 全程没碰**（现 PID 18744 ✓）

---
## 追加（2026-10-03 · **sim 侧第 15 轮**）复刻站点"会话/令牌流程" → **结论：复刻不了** ✗（实测两道墙 ✓），只把 sim 的话**说明白** ✓（未提交 ✗，**`server.mjs` 0 改动** ✓）---
**用户要求** ✓：复刻站点会话/令牌流程，让 sim 放**真·直播画面** ✓（我按访客那条公开路径走 ✓ 没去绕账号权限 ✗）。

### 先摸清"真画面"在哪 ✓（实测 ✓）
| 结论 | 证据 |
|---|---|
| `hlsPlaylist` 那套 = **固定预览片** ✗ | `.media`/`.net` × `standard/lowLatency` × 各档 **全是 6 段 VOD** ✓（`#EXT-X-ENDLIST` ✓、`MEDIA-SEQUENCE:0` ✓、18~20 秒复测**纹丝不动** ✗） |
| **真·活流确实存在** ✓ | headless 打开房间页抓包 ✓：`mmp.doppiocdn.com/player/mmp/v2.13.0/*.js`（站点**自研播放器** ✓）→ `edge-hls…net/hls/<streamName>/master/<streamName>_**auto**.m3u8?playlistType=lowLatency` ✓ → `media-hls…net/b-hls-**30**/<sn>/<sn>.m3u8?playlistType=lowLatency&preferredVideoCodec=h264&**psch=v2&pkey=<16位>**` ✓ → LL-HLS 分片 `<sn>_<seq>_<TOKEN>_<ts>_part0..7.mp4` ✓；<br>页面 `<video>` 实测 `readyState=4 / currentTime=364s / **1280×720** / 访客身份` ✓ = **访客也能看清晰活流** ✓（不需要登录 ✓） |
| 裸取也能拿到**活清单** ✓（关键 ✓） | 带上真站那个 `pkey` 直取 → **200 + 真·直播** ✓（`#EXT-X-SERVER-CONTROL` ✓、20 个 `#EXT-X-PART` ✓、`MEDIA-SEQUENCE 144→150` 15 秒内**在走** ✓）；**漏 pkey 或改一个字符 → 302** ✗ |

### 但两道墙，实测过不去 ✗✗
1. **`pkey` 不可得** ✗：把本次会话里**所有**同源 API 正文（22 个 ✓）、`localStorage`/`sessionStorage`/`document.cookie`/页面 HTML ✓、
   **WebSocket 帧**（Centrifugo `connect`/`subscribe` ✓）全搜了一遍 → **一处都没有** ✗ → 它只存在于**站点自研播放器 mmp 内部** ✓
   （也试过：拿抓到的 pkey 去开**别的**模型 → 200 但**只有 689B** ✗ 不是活清单 → 说明**按模型/会话绑定** ✗ 不能一把钥匙通吃 ✓）
2. **清单是 mmp 私有混淆格式** ✗：20 个 `#EXT-X-PART` 的 `URI` 全是占位 `…/b-hls-30/media.mp4` ✗，
   真分段藏在 `#EXT-X-MOUFLON:URI:` 扩展里 ✓、还配 `#EXT-X-MOUFLON:EXT-REF:<b64 令牌>` ✓；
   我按 4 种 query 带法直取那些分段 → **全 404** ✗ → 只有 mmp 能按扩展语义**现算**出可用的分段 URL ✓

### ⇒ 结论 + 建议（等你拍板 ✓）
- **sim 里用 HLS 放真画面：做不到** ✗（要做得先逆向 mmp 播放器 bundle + MOUFLON/PSCH 语义 + pkey 生成 ✗ = 独立 RE 项目 ✗，不是"补个 token" ✓）
- ✅ **最省事且已验证可行**：**App 侧 WebView 直接加载房间页** ✓ —— 站点自己的播放器会以**访客**身份放出 **1280×720 的清晰活流** ✓✓（我实测到的就是这个 ✓）
- 本轮 sim 只做一件事 ✓：全屏播放层上加一行**明说** ✓「站点预览片 · 不是真直播 ✗（真画面只有站点自己的播放器放得出 ✓）」——
  不再让人以为在看直播 ✗（样式 `.lv-player .tag` ✓；取流逻辑**一个字没改** ✗）
- `node --check` 内联脚本 = **0** ✓；**约束** ✓：只改 `sim/index.html` ✓、`server.mjs` 0 改动 ✓、`lib/**` 没碰 ✗、没 commit/push ✗、
  临时脚本（6 个）/Edge profile 全删 ✓、**8788 我起过又停了** ✓（现无监听 ✓）、**用户 8787 全程没碰**（现 PID 18744 ✓）

---
## 追加（2026-10-03 · **sim 侧第 16 轮**）用户问的"**A 方案**"（真流能不能脱离站点播放器播）→ **实测结论：✗ 不通**（只探测 ✗，`sim/**` 一个字没改 ✓，未提交 ✗）---
**A 方案的问法** ✓：「自绘 UI + 直连站点真流」能不能成立 —— 即 App 用**自己的播放器**放那条活流 ✗，不用 WebView 顶着网页壳 ✓。
**实测三面（全做完 ✓）**：

**① 抓新鲜样本** ✓：`winter11`（streamName `197467228`）→ 活清单
`…/b-hls-30/197467228/197467228_960p60.m3u8?playlistType=lowLatency&preferredVideoCodec=h264&psch=v2&pkey=NTK9aqcLmNFMWrpQ` ✓（HTTP 200 / 4958B / `MEDIA-SEQUENCE:328` ✓ 活的 ✓）；房间 cookie 717B（只有 AB 测试键 ✓）

**② 分段取法矩阵（Node 侧，8 种会话上下文全试）** ✗✗
| 组合 | 结果 |
|---|---|
| ① 裸取 · ② 只带 Referer · ③ Referer+Origin · ④ ③+cookie · ⑤ 只 cookie · ⑥ cookie+Origin · ⑦ ④+Range · ⑧ ④+自定义 psch 头 | **8/8 全 HTTP 404（10B, `video/mp4`）** ✗ |
（⚠️ 清单里的 `#EXT-X-MOUFLON:URI:` 行**看着就是真分段名** ✓（`…328_QKdIaC8lLO7yLchdT69u0b_1791091692_part0.mp4` ✓）但**就是 404** ✗；
**具体为什么 404 没定死** ❓（可能：分段按会话/令牌绑定 ✗、短时效 ✗（LL-HLS 窗口只几秒 ✗）、或播放器另有一套算法 ✓）—— 但"**我们构造不出来**"这点是实锤 ✓）

**③ 浏览器端到端（sim 页面里 ✓ 静音 ✓）** ✗
- 经 `/proxy` 拿活清单 → 200 ✓（5170B ✓）；把 MOUFLON 行改写成标准 HLS ✓ → **喂 hls.js** ✓（hls.js 加载成功 ✓、`isSupported=true` ✓、确实向 `b-hls-30` 发了 6 个请求 ✓）
- **结果：`readyState=0 / currentTime=0 / videoWidth=0`** ✗ = **放不出来** ✗（分段拿不到，播放器只能空转 ✓）

**⇒ A 的答案：✗ 不成立** ✓ —— 「自绘 UI + 直连真流」在**不改站点播放器**的前提下做不到 ✓。
剩下三条（都已如实告知用户 ✓，等他拍板 ✗）：
① **WebView 加载房间页** ✓（已验证能出 1280×720 访客活流 ✓，代价=顶着站点网页壳 ✗；能不能用注入 CSS 藏干净 ❓**未验证**）
② **逆向 mmp 播放器** ✗（MOUFLON/PSCH 语义 + pkey + `EXT-REF` 那串 base64 令牌的算法 ✓，独立 RE 工程 ❓ 可行性未验证）
③ 不做 ✗（sim 里那行"站点预览片 · 不是真直播"的说明保留 ✓ 不再误导 ✓）

**约束 ✓**：**`sim/**` 本轮 0 改动** ✓（没碰 `index.html`/`server.mjs` ✓）、`lib/**` 没碰 ✗、没 commit/push ✗、
临时脚本/2 个 Edge profile 全删 ✓、**8788 我起过又停了**（PID 19732 ✓）、**用户 8787 全程没碰**（现 PID 18744 ✓）

---
## 追加（2026-10-03 · **sim 侧第 17 轮**）用户拍板"逆向" → mmp 播放器协议**逆到最后一层，卡住** ✗（只探测 ✗，`sim/**` **0 改动** ✓，未提交 ✗）---
### ✅ 打通的部分（可复刻 ✓，全实测）
1. **"发钥匙"的那一步找到了** ✓（我上一轮漏看的）：`GET edge-hls.doppiocdn.net/hls/<streamName>/master/<streamName>_**auto**.m3u8?playlistType=lowLatency`
   → 200，正文里 **11 行 `#EXT-X-MOUFLON:PSCH:v2:<钥匙>`** ✓ + **变体表**：
   `source(1080x1440, 6850k) / 960p60(720x960, 4188k) / 960p(720x960, 2620k) / 480p(360x480, 1375k) / 240p(180x240, 658k)` ✓
2. **带钥匙取变体 → 真·活清单** ✓：`…/b-hls-30/<sn>/<sn>_960p.m3u8?playlistType=lowLatency&preferredVideoCodec=h264&**psch=v2&pkey=<钥匙>**`
   → **200 + 活的** ✓（`MEDIA-SEQUENCE 502 → 515` 在走 ✓、`#EXT-X-SERVER-CONTROL` ✓、无 ENDLIST ✓）
3. **不带钥匙 = 兜底预览** ✓（302 → `cpa/v2/stream.m3u8`，689B ✓ = 我前面一直撞到的那个"预览" ✓，谜题闭环 ✓）
### ✗ 卡住的最后一层：**分片地址取不到**（穷尽过 ✓）
- 清单里 `#EXT-X-MOUFLON:URI:` 给的分片 URI **全 404** ✗：不是编码（`/`→`%2F`、`+`→`%2B` 等 5 种 ✗）、
  不是窗口过期（**639 毫秒内并发取前 6 个**全 404 ✗）、不是会话上下文（cookie/Origin/Referer/Range/自定义头 8 种组合全 404 ✗）、
  也不是"去预设名/拼接 token"的简单修复（5 种猜法全 404 ✗）
- **对照**：同一时刻取 `#EXT-X-MAP`（init 段 `…_h264_init_<token>.mp4`）→ **200 / 1234B** ✓ → 主机可达 ✓，**只有分片 URI 是坏的** ✗
### 🔍 机制定位（读码得的 ✓，不是猜）
- `chunk-3d7c79f25e6a8cbb8748.js`（**他们 fork 的 hls.js** ✓）里有：`#EXT-X-MOUFLON:FILE/PSCH/EXT-REF` 三个 tag 解析 ✓、
  `_manifest.custom.**mmpCorruptionScheme**` ✓、以及关键字段 **`_awaitingFragmentURL`** ✗ ——
  ⇒ **分片地址是"等播放器给"的** ✓（不是客户端拼出来的 ✓），所以"corruption scheme"不是字符串改写 ✓
- `main.js`（352KB，**字符串表混淆** ✗）：有**硬编码 pkey 常量** `B0p93vi8Uj6AYyZb` ✓（与运行时那把不同 ✓）、
  `psch`/`pkey` 字面量被拼成 `ii(526)+ii(516)+"ER_NAME"` 这种 ✗ → 真算法在混淆里 ✓
### 下一步（要继续就在这两条里选 ✓）
① 抓 **WebSocket 二进制帧**（上一轮我只留了**文本帧** ✓ → 可能漏 ✗；页面有 `wss://websocket-v6.xhamsterlive.com/connection/websocket` + JWT ✓）
② 解 `main.js` 的字符串表 + 跟 `_awaitingFragmentURL` 是谁 resolve 的 ✓
⚠️ 代价照实说 ✓：这是**真 RE 工作量** ✓，且播放器**带版本号**（v2.13.0 ✓）→ 站点一升级就要重跟 ✗
### 结论（建议，附前提 ✓）
若目标只是"App 里看真画面" → **WebView 路线仍是性价比最高** ✓（今天就能用 ✓，实测访客 1280×720 ✓）；
**自绘 UI + 直连真流** ⇒ 必须先吃下上面那摊 RE 风险 ✗（本轮**没吃下** ✓）
**约束 ✓**：`sim/**` **本轮 0 改动** ✓、`lib/**` 没碰 ✗、没 commit/push ✗、6 个临时脚本 + Edge profile 全删 ✓、
**8788 我起过又停了**（PID 20988 ✓）、**用户 8787 全程没碰**（现 PID 18744 ✓）


---
## 追加（2026-10-03 · **sim 侧第 19 轮**）用户"先把模拟器跑通，不管用什么办法" → **能跑通的那条已落进 sim** ✓（真画面那条卡在站点私有加载器 ✗，留了入口 ✓）---
### ✅ 落进 sim 的（已改 `index.html` ✓ 未提交 ✗，`server.mjs` 0 改动 ✓）
**直播全屏层新增「看真直播 ▶」按钮** ✓ —— 点它 = 新开 **430×932 手机尺寸窗口**打开 `https://zh.xhamsterlive.com/<主播名>` ✓，
用**站点自己的播放器**放真画面 ✓（这是唯一可行路径 ✓ 实测访客就能看清晰活流 ✓）。
- 位置：`top:118px` 居中（X 在 77~105 ✓ 不打架 ✓）；点屏幕仍只切 X ✓（按钮 `stopPropagation` ✓ 实测不误触 ✓）
- 说明文字同步改成「上面放的是站点预览片 ✗ · 真直播要用站点自己的播放器 ✓（点「看真直播」）」✓
### 冒烟（8788 ✓ headless Edge + 手机 UA ✓ `--mute-audio` ✓ 播放静音 ✓，无未捕获异常 ✓）
```
点底栏「直播」→ 点站点宫格 → 房间列表 60 张 → 点第 1 张 → 进全屏层
 按钮：有 ✓ 文字「看真直播 ▶」✓ 位置 top=117 / 宽 111 ✓
 点它：window.open → https://zh.xhamsterlive.com/winter11 ✓ 窗口名 kpxx_live_winter11 ✓ 尺寸 430×932 ✓
 点屏幕：只切 X（true ✓），**没有**连带触发按钮 ✓
 播放：预览片 rs=4 / t=11.4s / muted=true ✓
 X 位置：**显示后**量 = top 77 / bottom 105 vs 状态栏 bottom 70 → **不压状态栏 ✓**
（⚠️ 上一版冒烟报 false ✗ 是我量了**隐藏状态**的 X ✗（rect 全 0 ✗）→ 已修正量法 ✓）
```
### ✗ 没跑通的那条（真画面进 sim 自己的播放器）—— 本轮推进到什么程度
1. **站点页面怎么起播放器，已挖出契约** ✓（`29242….js`）：
   `const o = new PlayerClass(); o.setVideoElement(v); o.setConfig({playbackStateController:{syncToLiveDelta:0,syncToLiveEdge:false,autoPlay:true,...}}); o.setUrl(url); o.start();`
   —— `url` 由外部传入 ✓、令牌那套在播放器内部 ✓
2. **加载器链已挖到** ✓：`MMPExternalUnitedSourceOrigin = https://mmp.doppiocdn.com/player/mmp` + `externalVersion=v2.13.0` ✓；
   站点本地模块 = `Promise.all([r.e("38584"),r.e("40017"),r.e("11223")]).then(r.bind(r,74599))` → `module.DoppioPlayer` ✓
3. **在自己页面里挂 CDN 那份** ✗ 卡住：`main.js` 只带 webpack runtime（88 模块 ✓）；
   用 runtime 的 chunk 表（11 个 ✓）**全部加载成功** ✓（103 模块 ✓），但**没有任何模块含 `DoppioPlayer` 字样** ✗
   → CDN 包的导出名是**混淆的** ✗，必须由**站点自己那份加载器**包装（`localModuleLoaderWasUsed` ✓）才能拿到 ✗
   ⇒ 想继续 = 再挖一层站点 loader 的包装逻辑 ✗（又一层 RE ✓ 不保证成 ❓）
### 其它已排除的路（本轮新增，全实测 ✓）
- **iframe 嵌房间页**：响应头 **`X-Frame-Options: deny`** ✗（根页也一样 ✗）→ 物理上死 ✗（比 shorts 那页还狠 ✗）
- 我们自己的 hls.js 播 CDN 直链：分片 token 在混淆 JS 里 ✗（上轮已穷尽 ✗）
**约束 ✓**：`sim/index.html` 只加按钮/文案/CSS ✓、**`server.mjs` 0 改动** ✓、`lib/**` 没碰 ✗、没 commit/push ✗、
临时脚本（6 个）+ 全部 Edge profile 清完 ✓、**8788 我起过又停了**（PID 3408 ✓）、**用户 8787 全程没碰**（现 PID 18744 ✓）

---
## 🎯 追加（2026-10-03 · **sim 侧第 20 轮**）**模拟器打通了 ✓✓✓** —— 直播房间层现在放的是**真·直播画面**（站点自己的播放器 ✓）
### 一句话原理
**不逆向令牌** ✗ —— 直接把**站点自己的播放器**（`MouflonPlayer` ✓，CDN 上的 `main.js` ✓）拉进 sim 的页面里跑 ✓：
它内部自己处理 `psch/pkey` 与每分片令牌 ✓，所以**分片令牌那条死路被彻底绕过** ✓✓。
### 可复现配方（实测 ✓，第三方照做即可）
```js
// ① 全局 modulesrc = CDN 目录（它自己按这个基址拉 chunk ✓）
window.modulesrc = 'https://mmp.doppiocdn.com/player/mmp/v2.13.0/';
// ② 拉 main.js 文本，按它期望的 CommonJS 形态执行 ✓（它末尾是 `module.exports = i` ✓）
const txt = await (await fetch(window.modulesrc + 'main.js')).text();
const jsx = (t, cfg, k) => { const p = Object.assign({}, cfg||{}); if (k!==undefined) p.key = k; return React.createElement(t, p); };
const shim = (n) => n==='react' ? React
  : n==='react-dom' ? ReactDOM
  : n==='react-dom/client' ? { createRoot: ReactDOM.createRoot, hydrateRoot: ReactDOM.hydrateRoot }
  : (n==='react/jsx-runtime'||n==='react/jsx-dev-runtime') ? { jsx, jsxs: jsx, jsxDEV: jsx, Fragment: React.Fragment } : {};
shim.resolve = () => '';
const mod = { exports: {} };
new Function('module','exports','require','modulesrc', txt)(mod, mod.exports, shim, window.modulesrc);
// ③ 渲染它的 React 组件（**必须给 videoElement** ✗ 漏了就不出播放器 ✓ 实测）
const ve = document.createElement('video'); ve.muted = true; ve.volume = 0; ve.playsInline = true;
const ref = React.createRef();
ReactDOM.createRoot(box).render(React.createElement(mod.exports.MouflonPlayer, {
  videoElement: ve, playerType: 'hls', HLSStreamUrl: <真流地址>, playerRef: ref,
  volume: 0, isABREnabled: true, muted: true, autoplay: true,
}));
// ④ 把 ref.current._videoElement 挂进 DOM 就是画面 ✓
```
- 依赖：React/ReactDOM 18 UMD（`unpkg.com/react@18` + `react-dom@18` ✓；⚠️ 本地拿到的是 `18.3.1-next-…` ✗ **没有 `createRoot`** → 代码里已做**降级到 `ReactDOM.render`** ✓ 实测可行 ✓）
- 真流地址：用**选档器挑出的档**（`m.hlsPlaylist` 换成 480p/960p ✓）比接口默认档（240p ✗）清晰 ✓；挑不到就退回接口默认档 ✓
- 导出名：CDN 包导出 `MouflonPlayer / useMouflonPlayer / useMouflonPlayerV2 / getVideoElement / MMP_VERSION(v2.13.0) / E*` 枚举 ✓（站点自己代码里叫它 `DoppioPlayer` ✓ —— **名字不同** ✓ 这就是我前面按名字搜找不到的原因 ✗）
### 验收（8788 ✓ headless Edge + 手机 UA ✓ `--mute-audio` ✓，**播放静音** ✓）
```
底栏「直播」→ 站点宫格 → 房间列表 60 张 → 点第 1 张 → 全屏层
 [0s] 真画面已起 ✓ rs=4 · t=944s 在走 · **854×480** · muted=true volume=0 · paused=false · 在DOM ✓
 标签：「真·直播 ✓（站点自己的播放器 · 静音播放）」✓
 日志：真·直播取档：480p ✓ / React 18.3.1 / ReactDOM 18.3.1-next ✓ / 真·直播已起 ✓ enya- ✓
 真·活分片：70032198_480p_h264_init_….mp4 + _465/_466/_467_….mp4 **序列在推进** ✓✓
 X：显示后 top=77 ≥ 状态栏 bottom=70 → 不压状态栏 ✓ ；无未捕获异常 ✓
```
### sim 里的实现位置（`sim/index.html` ✓ 未提交 ✗）
- 新增 `ensureMmp()`（懒加载 React + mmp 模块 ✓ 一份缓存 ✓）、`mountMmpLive()` / `renderMmp()` ✓
- `viewLiveRoom()` 里**并行**调 `mountMmpLive` ✓：真画面起来就**盖掉预览片** ✓；起不来就保持预览 + 提示 ✓（**不会炸** ✓）
- 预览片（上轮的 hls.js 路径 ✓）**保留**当兜底 ✓；「看真直播 ▶」按钮也保留 ✓（双保险 ✓）
- 静音三件套全程 ✓：`--mute-audio` + `ve.muted=true; ve.volume=0` + `volume:0` prop ✓
**约束 ✓**：只改 `sim/index.html` ✓、**`server.mjs` 0 改动** ✓、`lib/**` 没碰 ✗、没 commit/push ✗、
临时脚本（6 个）+ 全部 Edge profile 清完 ✓、**8788 我起过又停了**（PID 19992 ✓）、**用户 8787 全程没碰**（现 PID 18744 ✓）



---
## 追加（2026-10-03 · **sim 侧第 23 轮**）直播页加**第 5 个主分类 tab「移动端直播」** ✓（lead 派单 + 用户拍板 ✓ 只改 `sim/index.html` ✓ 未提交 ✗，`server.mjs` 0 改动 ✓）
### 改了什么（5 处，全在 `sim/index.html` ✓）
1. **`LIVE_MAIN`** 末尾加第 5 项 ✓：`{ name: '移动端直播', mobile: true, groups: [] }` —— 加在**跨性別右边** ✓（顺序：女主播/情侣/男主播/跨性別/**移动端直播** ✓）；`groups: []` 空 ✓（它是叶子 ✓）
2. **`LIVE_TAG_OF`** 加 `'移动端直播': 'girls'` ✓（默认看**女主播**的移动流 ✓）
3. **`LIVE_FILTER_TAIL` 拆两段** ✓：`LIVE_FILTER_TAIL_BASE`（不含 `specialEventTagIds` ✓）+ `LIVE_FILTER_TAIL = BASE + specialEventTagIds` ✓ —— 移动端 tab 用 BASE ✓（recon 明确它不带 ✓）
4. **`liveFetch(tag, offset, filterTag, mobileMode)`** 加第 4 参 ✓；`loadLiveRooms` 传 `!!liveRooms.mobile` ✓
5. **`renderLiveSite`**：① 该 tab **不渲染**「筛选」那行 ✓（`${m.mobile ? '' : …}` ✓ 整行都不渲染 ✓ 不浪费空间 ✓ 也不会点了没反应 ✓）
   ② 重拉判据加"移动端标记" ✓：`liveRooms.tag !== tag || !!liveRooms.mobile !== wantMobile` ✓
   （⚠️ 坑：移动端 tab 的 `primaryTag` **也是 girls** ✗ —— 只看 tag 会跟「女主播」**串列表** ✗，所以必须比 `mobile` ✓）
### 冒烟（8788 ✓ headless Edge + 手机 UA ✓ `--mute-audio` ✓，**无未捕获异常** ✓，`node --check` = 0 ✓）
```
① tabs：个数 5 ✓ 顺序 [女主播, 情侣, 男主播, 跨性別, 移动端直播] ✓ 当前=女主播 ✓
   横向滚：需要 ✓（.lv-tabs 本来就有 overflow-x:auto ✓ 第 5 个滑得到 ✓）· 筛选按钮：在 ✓ · 房间卡 60 ✓
② 点「移动端直播」→ ③ 当前 tab=移动端直播 ✓ · **筛选按钮/筛选行都没了 ✓** · 房间卡 60 ✓
   首条 = 「LIVE 4293 人 winter11」✓（与 lead 给的预期一致 ✓）
④ 滚到底 → 房间卡 **120** ✓（offset=60 那一页来了 ✓）· 加载更多=「上滑加载更多」✓（没到底 ✓）
⑤ 换回「女主播」→ 筛选按钮回来了 ✓（文字「筛选」= 无筛选 ✓）· 房间卡 60 ✓（已按无筛选重拉 ✓）
### 接口 URL 原样核对（stub fetch 抓全文 ✓，最能说明问题的证据 ✓）
| 场景 | filterGroupTags | parentTag | specialEventTagIds |
|---|---|---|---|
| **移动端 tab** ✓ | `[["mobile"]]` ✓ | `mobile` ✓ | **没有 ✓**（符合 recon ✓） |
| 对照组：同参数但不带 mobileMode ✗ | 有 ✓ | mobile ✓ | 有 ✗（证明去留确实由这个标记控制 ✓） |
| 对照组：普通子分类筛选 `ageMilf` ✓ | 有 ✓ | ageMilf ✓ | 有 ✗（**其余 4 个 tab 行为没变 ✓**） |
### 其余 4 个 tab ✓
行为**照旧** ✗：tab 顺序/筛选行/子分类弹窗/重置/翻页 全未改 ✓（只有新增分支 ✓）
**约束 ✓**：只改 `sim/index.html` ✓、**`server.mjs` 0 改动** ✓、`lib/**` 没碰 ✗、没 commit/push ✗、
临时脚本 + Edge profile 清完 ✓、**8788 我起过又停了**（PID 9728 ✓）、**用户 8787 全程没碰**（现 PID 18744 ✓）

---
## 追加（2026-10-03 · **sim 侧第 24 轮**）查「ReactDOM 不可用」+ **把内嵌播放器的 React 加载做稳** ✓（只改 `sim/index.html` ✓ 未提交 ✗，`server.mjs` 0 改动 ✓）
### ① 根因结论（实测 ✓）
- **那句的充要条件** ✓：`window.React` / `window.ReactDOM` **都是真值** ✓、但**既没有 `createRoot` 也没有 `render`** ✗
  ⇒ 意思是**拿到了一份坏/不完整的 ReactDOM** ✗（不是"没加载上"✗ —— 那走的是**另一句**「React 拉不到 ✗」✓）
- **不是移动端 tab 的代码路径问题** ✓✓：实测「**把移动端 tab 放第一个点**」→ **2 秒就起真画面** ✓（与其它 4 个 tab 完全一致 ✓）→ 它们**同一条代码路径** ✓
- **平时能起、某次报错的真原因（代码缺陷 ✓ 实锤）**：
  ① 老代码是**点卡片才拉** React ✗（冷启动 = 2 个脚本 + 352KB 模块 ✓）→ 网慢/被拦就赶不上 ✗
  ② **失败会被缓存住** ✗ —— `mmpP` 一旦失败就记住 ✗，后面所有房间全废 ✗（读代码 + 断源实验都印证 ✓）
- ⚠️ 用户设备上那份 CDN 具体返回了什么 ✗（stub / 错文件 / 残留副本 ✗）**我无法复现** ✗ —— 只能确定"要出那句，必须是拿到坏副本" ✓，**这个条件现在被拦住了** ✓
### ② 改了什么（8 点 ✓ 都在 `sim/index.html`）
1. **双源链式兜底** ✓：`cdn.jsdelivr.net` 优先（sim 的 hls.js 本来就走它 ✓）+ `unpkg.com` 兜底 ✓
2. **顺序加载** React → ReactDOM ✓（UDM 的 react-dom 执行时需要 `window.React` ✓ 老代码 `Promise.all` 并发会撞 ✗）
3. **加载后验 API** ✓（`createElement` + `createRoot|render` ✓）→ 不合格 = 该源作废 ✗ ✓（用户那种"坏副本"从此会被识别 ✓）
4. **换源前清坏副本** ✓（`delete window.React/ReactDOM` ✓，不清就永远救不回来 ✗）
5. **失败不再缓存** ✓（`mmpP` 失败置空 ✓ → 可重试 ✓）
6. **预热** ✓：一进**站点页**就拉 ✓（实测：**还没点任何卡片**就已「播放器组件：React 18.3.1 … 就绪 ✓（源 jsdelivr）」+「站点播放器已就绪 ✓ v2.13.0」✓）
7. **失败提示 + 重试入口** ✓：改成「播放器组件加载失败 ✗（外部源不通）· 现在放的是预览片 … · **点这里重试 ↻**」✓（点它重跑 ✓ 成功即清掉 ✓；`lvFail/lvOk` 两个小工具 ✓）
8. 日志更清楚 ✓（哪个源 / React 版本 / 缺哪个 API ✓）
❓ **unpkg 裸依赖没完全去掉** ✓ —— 留作兜底 ✓；**"本地打包一份 React 进 sim"做不到** ✗：sim 的静态文件是 `server.mjs` 里的白名单 ✗（只有 `index.html`+几张 jpg ✓），要加本地 js 就得改 `server.mjs` ✗ → 越界 ✓ 不硬来 ✓
### ③ 冒烟（8788 ✓ headless Edge + 手机 UA ✓ `--mute-audio` ✓ 播放静音 ✓ `node --check` = 0 ✓）
```
① 5 个 tab 各开一间房（**移动端 tab 第一个点** ✓）
   tab[4] 移动端直播 2s ✓ 720×960   tab[0] 女主播 2s ✓ 720×960   tab[1] 情侣 2s ✓ 360×480
   tab[2] 男主播 2s ✓ 640×480        tab[3] 跨性別 4s ✓ 426×240    —— 全 muted=true ✓ 标签「真·直播 ✓」
② 断掉两个 CDN → 提示：「播放器组件加载失败 ✗（外部源不通）…· 点这里重试 ↻」✓（有重试入口 ✓）
   恢复网络 → 点提示重试 → **720×960 真画面起来了 ✓**
③ 干净路径**无未捕获异常** ✓（我第一轮看到的那个 SyntaxError 是"屏蔽 CDN"这个测试花招自身产生的 ✗ 不是 sim 的 ✗）
④ React 源命中：cdn.jsdelivr.net（react@18 + react-dom@18 ✓）· unpkg 只在被断时被试过 ✓
```
**约束 ✓**：只改 `sim/index.html` ✓、**`server.mjs` 0 改动** ✓、`lib/**` 没碰 ✗、没 commit/push ✗、
临时脚本 + Edge profile 清完 ✓、**8788 我起过又停了**（PID 14760 ✓）、**用户 8787 全程没碰**（现 PID 18744 ✓）

---
## 追加（2026-10-03 · **sim 侧第 25 轮**）移动端直播 tab 加 **4 个页内过滤器** ✓（lead 派单 + 用户要 ✓ 只改 `sim/index.html` ✓ 未提交 ✗，`server.mjs` 0 改动 ✓）
### 改了什么
1. **`MOBILE_FILTERS`** 数据表 ✓（lead 给的 recon **原文照抄** ✓）：外貌(5 组) / 国家(7 组) / 价格 & 表演类型(1 组) / 可请求提供的表演(1 组) ✓
   - **tagId 只认原文明确给的** ✓；原文没给的（多数国家 ✗）→ `null` = **未映射** ✓（原文说按 `tagLanguage+国家英文名` 拼，
     但样例后缀不统一 ✗（GermanSpeaking / USModels / Nordic ✓）→ 按"拿不准别硬猜"留空 ✓）
2. **已选状态** ✓：`mfSel` 按**子分组**分桶 ✓（`<过滤器>#<子分组>` → tagId 数组 ✓）
   ⚠️ 粒度依据 = lead 实测例子 `mobile+ageTeen+ethnicityAsian+bodyTypePetite+doAnal → 5` ✓
   ⇒ **子分组各自成组** ✓（年龄/种族/体型… 之间 AND ✓、同子分组多值 OR ✓）—— 我一开始按"整个外貌一组"写错了 ✗ 已改 ✓
3. **全屏「筛选器」modal** ✓（`openMobileFilter()` ✓）：标题「筛选器」✓ + 顶部 4 个过滤器切换（带已选数 ✓）+ 子分组 + 多选 chip（选中高亮 ✓）
   + 未映射 chip 灰显 + 点了只提示不过滤 ✓ + 底部「重置」「进行筛选」✓
4. **筛选行** ✓：移动端 tab 渲染 **4 个按钮**（`外貌` / `外貌: 熟女` / `外貌: 熟女 +1` ✓）+ 有选择时多一个红色「重置」✓（`mfAny()` ✓）
   其余 4 个 tab **照旧** ✗（原筛选行分支没动 ✓）
5. **请求** ✓：`filterGroupTags=[["mobile"]]` + **每个有选择的子分组一个内层数组** ✓ + `parentTag=mobile` ✓ + `LIVE_FILTER_TAIL_BASE`（移动端不带 `specialEventTagIds` ✓ 同第 23 轮 ✓）；`.ft`「进行筛选」→ offset 归 0 重拉 ✓
6. 顺手修的**自己的两个 bug** ✗：① 组重复 `[["mobile"],["mobile"]]` ✓（既 push mobile 又把 `filterTag='mobile'` 当筛选 push 了一遍 ✗）
   ② `mfCount(f.key)` 传成字符串 ✗（改成收对象后漏改调用点 ✓）
### 数据计数（页面内实测 ✓）
```
外貌：5 组 / 32 项（有 tagId 32 · 未映射 0）
国家：7 组 / 82 项（有 tagId 18 · 未映射 64）      ← 未映射是按"别硬猜"故意留的 ✓
价格 & 表演类型：1 组 / 7 项（有 tagId 7 · 未映射 0）
可请求提供的表演：1 组 / **61** 项（有 tagId 61 · 未映射 0）   ← ⚠️ lead 邮件写的是 60 ✗ 我落的是 61 ✓（差 1，等你核对 ✓）
合计 182 项（有 tagId 118 · 未映射 64）
```
### 冒烟（8788 ✓ headless Edge + 手机 UA ✓ `--mute-audio` ✓，`node --check` = 0 ✓，**无未捕获异常** ✓）
```
① 女主播 tab：`#lvFilterBtn` 在 ✓ · `.mf-btn` = 0 ✓（4 主 tab 行为没变 ✓）
② 移动端 tab：`#lvFilterBtn` **没了** ✓ · 4 个按钮 = 外貌/国家/价格 & 表演类型/可请求提供的表演 ✓
③ 点「外貌」→ modal：标题「筛选器」✓ · 选项 32 ✓ · 未映射 0 ✓ · 子分组 5 个 ✓ · 顶部切换 4 个 ✓ · 底按钮 重置/进行筛选 ✓
④ 选「熟女」→ 进行筛选：`filteredCount 1000 → **419**` ✓ · 按钮文字变「外貌: 熟女」✓ · 子分组头显示「年龄（已选 1）」✓
⑤ 再叠**跨子分组**的（价格 → 8-12代币）：`**218**` ✓（AND ✓）· 按钮行 = 外貌: 熟女 | 国家 | 价格 & 表演类型: 8-12代币 | 可请求提供的表演 ✓
⑥ 未映射项（国家 → 加拿大人）：灰显 ✓ 点了**不高亮** ✓ → 请求 URL **与上一次一字不差** ✓（计数 218→217 是直播房自然增减 ✓ 不是筛选生效 ✓）
⑦ 重置 → 回基准 **1000** ✓
请求原样（尾巴全看 ✓）：#2 [["mobile"]] → #3 [["mobile"],["ageMilf"]] → #4 [["mobile"],["ageMilf"],["privatePriceEight"]] → #6 回 [["mobile"]] ✓
（⚠️ lead 预期 148 是 `ageTeen` 的值 ✓；我点的是**熟女 ageMilf** → **419** ✓ 不矛盾 ✓）
```
**约束 ✓**：只改 `sim/index.html` ✓、**`server.mjs` 0 改动** ✓、`lib/**` 没碰 ✗、没 commit/push ✗、
临时脚本 + Edge profile 清完 ✓、**8788 我起过又停了**（PID 23048 ✓）、**用户 8787 全程没碰**（现 PID 18744 ✓）

---
## 追加（2026-10-03 · **sim 侧第 26 轮**）移动端筛选弹窗**改成和 `phChipDlg` 同尺寸/同外观** ✓（用户反馈"太大"✗ 只改 `sim/index.html` ✓ 未提交 ✗，`server.mjs` 0 改动 ✓）
### 改了什么
1. **弹窗体对齐 `phChipDlg`** ✓（原来是全屏白底 ✗）：暗底 `rgba(0,0,0,.35)` ✓ + 居中 ✓ + 白底圆角 14 ✓ + `max-width:92% / max-height:76%` ✓ + 同款阴影 ✓
   - 面板 = 新增 `.mf-box`（`display:flex; flex-direction:column` ✓），中间 `.bd` 区滚动 ✓（高度超了内部滚 ✓，不再撑满屏 ✓）
   - 顺手补上 `phChipDlg` 有、我原来没做的**点暗底关闭** ✓
2. **4 个过滤器怎么塞进去** ✓：**顶部切换**（4 个名字 + 已选数 ✓，一次只显示一个过滤器的 chip ✓）+ 底部「重置 / 进行筛选」✓ —— 功能一个没丢 ✓
3. 顺手修：把**内部注解漏进 UI** 的那处删掉 ✗（表演那组的名字原来写着「表演（原文 60 项…）」✗ → 现在就是「表演」✓）
### 实测对比（同一屏、同一时刻量 ✓）
| | 面板宽 | 占屏宽 | 面板高 | 占屏高 | 居中 | 圆角 | max-width | max-height | 内边距 | 底/遮罩 |
|---|---|---|---|---|---|---|---|---|---|---|
| **移动端（外貌）** | 340 | **92%** | 491 | 61% | ✓ | 14px | **92%** | **76%** | 14px 14px 12px | #fff / rgba(0,0,0,.35) |
| 其它 tab（`phChipDlg`） | 340 | **92%** | 611 | 76% | ✓ | 14px | **92%** | **76%** | 14px 14px 12px | #fff / rgba(0,0,0,.35) |
⇒ **同一套弹窗体** ✓（宽都是 92% ✓、约束/圆角/内边距/阴影/遮罩逐项一致 ✓；高度差 = 内容多少不同 ✓ 不是尺寸不同 ✓）
### 冒烟（8788 ✓ headless Edge + 手机 UA ✓ `--mute-audio` ✓ `node --check` = 0 ✓ 无未捕获异常 ✓）
```
① 弹窗尺寸/样式：见上表 ✓
② 4 个过滤器都能开、数量对得上：
   外貌 32 项 / 未映射 0 ✓ · 国家 82 / 64 ✓ · 价格 & 表演类型 7 / 0 ✓ · 可请求提供的表演 61 / 0 ✓
---
## 追加（2026-10-03 · **sim 侧第 27 轮**）直播**站点页不带底栏** ✓（用户要，对齐 App 的 push 全屏页 ✓ 只改 `sim/index.html` ✓ 未提交 ✗，`server.mjs` 0 改动 ✓）
### 改了什么（**一处** ✓）
- `viewLiveSite()`（点「xHamster直播」进的那页 ✓）里 `showNav(true)` → **`showNav(false)`** ✓（+ 注释说明 ✓）
- **底栏恢复不用额外写** ✓：站点页 appbar 的返回箭头是 `onclick="viewLive()"` ✓，而 `viewLive()` 里本来就是 `showNav(true)` ✓ → 返回即恢复 ✓
- 只改这一处 ✓：直播区（站点宫格那页 ✓）仍是 tab → **保留底栏** ✓（`viewLive()` 没动 ✗）；房间全屏层是 `position:absolute; z-index:70` 盖满 ✓ **没动** ✓
### 冒烟（8788 ✓ headless Edge + 手机 UA ✓ `--mute-audio` ✓ `node --check` = 0 ✓ 无未捕获异常 ✓）
```
① 首页/模块页        底栏 display=flex · 可见 · 高 77px ✓
② 直播区（站点宫格）  底栏 flex · 可见 · 77px ✓          ← 它还是 tab ✓ 保留 ✓
③ 直播站点页         底栏 **display=none · 可见=false · 高 0** ✓✓  ← 本次要求 ✓
                     内容没受影响 ✓（tabs=5 · 房间卡 60 · 筛选行在 ✓ · appbar「‹xHamster直播」✓）
④ 点 appbar ‹ 返回    底栏 **flex · 可见 · 77px** ✓✓（自动恢复 ✓）
⑤ 再进站点页         底栏 none ✓
⑥ 开房间→关房间（仍在站点页） 底栏 **仍 none** ✓（房间层不干扰 ✓）
⑦ 回模块页           底栏 flex · 77px ✓
⑧ 设置页（其它 tab）  底栏 flex · 77px ✓（没受影响 ✓）
```
**约束 ✓**：只改 `sim/index.html` ✓、**`server.mjs` 0 改动** ✓、`lib/**` 没碰 ✗、没 commit/push ✗、
临时脚本 + Edge profile 清完 ✓、**8788 我起过又停了**（PID 17056 ✓）、**用户 8787 全程没碰**（现 PID 18744 ✓）


---
## 追加（2026-10-03 · **sim 侧第 29 轮**）lead 纠正：**A 还原过滤器入口** + **B 主分类那排保留下划线 tab** ✓（只改 `sim/index.html` ✓ 未提交 ✗，`server.mjs` 0 改动 ✓）
⚠️ 背景：第 28 轮我把**过滤器入口**改成了"复用 `.lv-tab` 的横排 tab"✗；第 29 轮又按"主分类改下划线"把 `.lv-tab` 整组改了 ✗ → **过滤器被带着一起变** ✗（lead 指出这正是"混在一起"✗）。本轮**拆开** ✓。
### 【A】还原：移动端 4 个过滤器入口 ✓
- 标记改回 **并排按钮** ✓：`<div class="pkbar"><button class="mf-btn" data-mf=…>` ×4 ✓ + 「重置」回到 `.pkbar` 按钮 ✓
- **独立样式类 `.mf-btn`** ✓（**不再复用 `.lv-tab`** ✗ —— 以后改主分类那排**不会**带到它 ✓）
- 恢复 `.pkbar button.mf-btn.on { border-color:#e8590c; color:#e8590c; font-weight:600 }` ✓（= 改动前的选中观感 ✓）
- 绑定选择器从 `.mf-tab[data-mf]` 改回 `.mf-btn[data-mf]` ✓
### 【B】主分类那排（女主播/情侣/男主播/跨性別/移动端直播）✓
- `.lv-tabs/.lv-tab` 改成**经典 tab 栏** ✓：`gap:20px` + 行底部 1px 分隔线 + 文字标签 ✓ + 选中 2px 下划线 ✓ + 选中加粗/橙字 ✓ + 未选灰字 ✓ + **去掉圆角胶囊背景** ✓ + 横向可滚 ✓
### 冒烟（8788 ✓ headless Edge + 手机 UA ✓ `--mute-audio` ✓ `node --check` = 0 ✓ 无未捕获异常 ✓）
```
【B】主分类那排（同一个 `.lv-tab[data-mi]` 量出来的 ✓）
  选中：圆角 **0px** ✓ · 底 **透明** ✓ · 字色橙 rgb(232,89,12) ✓ · 字重 **600** ✓ · 下边框 **1.19px 橙** ✓ · padding 9px 2px ✓
  未选：圆角 0px ✓ · 底透明 ✓ · 字色灰 **rgb(138,144,153)** ✓ · 字重 400 ✓ · 下边框透明 ✓
  行：底部 1.19px rgb(236,238,241) 分隔线 ✓ · overflow-x auto（横向可滚 ✓）
【A】过滤器入口（移动端 tab 里量 ✓）
  4 个 ✓ 且是 **BUTTON 标签** ✓ 容器 `.pkbar` ✓
  未选风格：圆角 **8px** ✓ 透明底 ✓ 边框 1.19px rgba(60,60,60,.35) ✓ 黑字 ✓ padding 5px 10px ✓（= 并排按钮观感 ✓）
  选中风格：「外貌: 熟女」橙字 rgb(232,89,12) ✓（`.mf-btn.on` ✓）
功能回归（都正常 ✓）：切 tab（点第 5 个 → 移动端直播 ✓）· 点过滤器开弹窗（32 项 ✓）
  · 选熟女 → 进行筛选 `→ 60 条（累计 60 / 383）` ✓ · 「重置」→ 回基准（`[[mobile]]` 无筛选 ✓ 按钮文字回裸名 ✓）
  · 回女主播 tab 仍是下划线样式 ✓（没被 A 带跑 ✓）
```
**约束 ✓**：只改 `sim/index.html` ✓、**`server.mjs` 0 改动** ✓、`lib/**` 没碰 ✗、没 commit/push ✗、
临时脚本 + Edge profile 清完 ✓、**8788 我起过又停了**（PID 20092 ✓）、**用户 8787 全程没碰**（现 PID 18744 ✓）

---
## 追加（2026-10-03 · **sim 侧第 30 轮**）主分类 tab **未选字色：灰 → 黑** ✓（用户要 ✓ 只改 `sim/index.html` ✓ 未提交 ✗，`server.mjs` 0 改动 ✓）
### 改了什么（**一行色值** ✓）
- `.lv-tab` 的 `color: #8a9099`（灰 ✗）→ **`color: #111`** ✓（用户说别太突兀 → 用 #111 而不是纯黑 ✓）
- **选中态一个字没动** ✓（`.lv-tab.on { color:#e8590c; font-weight:600; border-bottom-color:#e8590c }` ✓）
- **只动主分类那排** ✓：`.lv-tab` 现在**只被 `data-mi` 那一排使用** ✓（grep 确认 ✓ 共 2 处：CSS + 主分类模板 ✓）；
  移动端 4 个过滤器入口是**独立类 `.mf-btn`** ✓ 不在 `.lv-tab` 里 → **没被带跑** ✓
### 冒烟（8788 ✓ headless Edge + 手机 UA ✓ `--mute-audio` ✓ `node --check` = 0 ✓ 无未捕获异常 ✓）
```
主分类未选（4 个逐个量 ✓）：字色 **rgb(17,17,17)** ✓ 字重 400 ✓ 下边框透明 ✓
主分类选中：字色 **rgb(232,89,12)** ✓ 字重 **600** ✓ 下边框 1.19px 橙 ✓（原样 ✓）
切 tab：女主播→移动端直播→情侣 都正常 ✓（情侣 → `primaryTag=couples` 60 条 ✓），每次重画后未选仍 #111 ✓
过滤器入口（同页对比 ✓）：未选字色 **rgb(0,0,0)** ✓ · 下边框 **rgba(60,60,60,.35)** ✓（= 它自己的按钮边 ✓ **没有**被换成橙色下划线 ✓）
过滤器弹窗照常：点「外貌」→ 32 项 ✓
```
**约束 ✓**：只改 `sim/index.html` ✓、**`server.mjs` 0 改动** ✓、`lib/**` 没碰 ✗、没 commit/push ✗、
临时脚本 + Edge profile 清完 ✓、**8788 我起过又停了**（PID 21300 ✓）、**用户 8787 全程没碰**（现 PID 18744 ✓）

---
## 追加（2026-10-03 · **sim 侧第 31 轮**）① 第 5 个 tab 改名 `移动流` ✓ ② 新增第 6 个 tab `手机版最新` ✓（只改 `sim/index.html` ✓ 未提交 ✗，`server.mjs` 0 改动 ✓）
### ① 实测确认的请求参数（**不是猜的** ✓）
站点页 `/girls/new-mobile` 是 **SSR** ✗（抓不到它自己的客户端请求 ✗）→ 换**最硬的对照**：直接取那份 HTML，看里面出现的是哪个组合的主播名 ✓
```
候选（同一时刻调接口 ✓）：
  A [["mobile"]]                      → filtered=1000  前3 = winter11 / MissY_9 / xiaowan_xx
  B [["autoTagNew"]]                  → filtered=1000  前3 = sultry520 / nooneknowspoppy / Malis_ss
  C [["autoTagNew"],["mobile"]]（AND） → filtered=**292**  前3 = **sultry520 / LINA-LILI / Malis_ss**
  D [["autoTagNew","mobile"]]（同组 OR）→ filtered=1000  前3 = winter11 …（≈ A ✓ 证明 D 就是 OR ✗）
HTML 里逐个数出现次数：sultry520 **5** ✓ · LINA-LILI **5** ✓ · Malis_ss **5** ✓ · winter11 **0** ✗ · MissY_9 0 ✗ · xiaowan_xx 0 ✗ · nooneknowspoppy 0 ✗
⇒ **确认 = C** ✓✓：`primaryTag=girls` + `filterGroupTags=[["autoTagNew"],["mobile"]]`（两组 **AND** ✓）+ `parentTag=mobile`
   （页面 `<title>` 也印证叫法：「手机版最新 和女主播们免费现场性爱视频」✓；侧栏那条叶子叫「移动流」`/girls/mobile` ✓ 与 ①改名一致 ✓）

---
## 追加（2026-10-03 · **sim 侧第 32 轮**）给「手机版最新」tab 补上那 **4 个过滤器** ✓（lead 说 recon 实测它有 ✓ 只改 `sim/index.html` ✓ 未提交 ✗，`server.mjs` 0 改动 ✓）
### 改了哪些位置（4 处 + 1 个关键改造）
1. **⚠️ `mfSel` 改成按 tab 分桶** ✓（`mfSelBy = { mobile: {}, newMobile: {} }` + `mfTab()`/`mfSel()` ✓）
   —— 用户要"两个 tab **互不影响**" ✓，全局一份会串 ✗（在移动流选了熟女 → 切过去也带着 ✗）
2. `renderLiveSite()`：过滤器那行对 **`m.mobile || m.newMobile`** 都渲染 ✓（原来只给 mobile ✗；「筛选」单按钮行仍只给那 4 个主 tab ✓）
3. `loadLiveRooms()`：`mfGroups()` 对这两个 tab 都拼 ✓
4. 日志标明「手机版最新」并把叠加的组也打出来 ✓
5. 「重置」只清**当前 tab** 那份（`mfSelBy[mfTab()] = {}` ✓）；弹窗里的「重置」同理 ✓
### 只说没做（等 lead 问用户 ✓）
- recon 提到的 **22 个 `/girls/new-*` 标签徽章** + 「展开更多」开关 ✗ **没做** ✓（按 lead 指示"先别做" ✓）
**约束 ✓**：只改 `sim/index.html` ✓、**`server.mjs` 0 改动** ✓、`lib/**` 没碰 ✗、没 commit/push ✗、
临时脚本 + Edge profile 清完 ✓、**8788 我起过又停了**（PID 17428 ✓）、**用户 8787 全程没碰**（现 PID 18744 ✓）

---
## 追加（2026-10-03 · **sim 侧第 33 轮**）**直播列表跳过付费房**（6 个 tab 全覆盖 ✓ 用户强调 ✓ 只改 `sim/index.html` ✓ 未提交 ✗，`server.mjs` 0 改动 ✓）
### 改了哪些位置
1. 新增判据函数 **`liveShowable(m)`** ✓（照 lead recon 960 条实测的判据 ✓）：
   `groupShowType` 有值 → 付费房 ✗ 筛掉 ✓；`status` 非 public ✗；`isOnline` 假 ✗；其余显示 ✓
   - ⚠️ **容错**：`groupShowType` 字段**缺失**时按**免费**算 ✓（`!m.groupShowType` ✓）—— 免得字段一没整页被清空 ✗
   - ⚠️ **没用** `doPrivate/doSpy/privateRate/spyRate/publicRecordingsRate` ✗（那是能力标志，85~90% 免费房都带 ✗）
2. **`loadLiveRooms()`** 里逐条筛 ✓（**所有 tab 同一处** ✓ 不存在漏 tab ✗）：`keep = raw.filter(liveShowable)` ✓
   - ⚠️ **计数改用原始条数** ✓（`rawCount` ✓）—— 否则"到底"判据 `items.length >= filteredCount` 永远不成立 ✗
   - 日志变成「原始 60 条 / 显示 51 条（筛掉 9 个付费房 ✓）」✓
3. **`paintLiveMore()`**：这页被筛空时不再留白 ✗ → 「这页没有免费直播间 · 上滑加载更多 ✓」/「没有可显示的免费直播间 ✗」✓
4. 4 处「清零」点加上 `rawCount/skipped` 归零 ✓（子分类筛选重置 ✓、页内过滤器"进行筛选" ✓、弹窗选完 ✓、切 tab 重建 ✓）
### 逐个 tab 验证（用户要"别笼统说已加" ✓ —— 下面是 6 个 tab **每个各自量**的 ✓）
| # | tab | 显示条数 | 其中付费房 | 筛掉 | 原始条数 |
|---|---|---|---|---|---|
| 1 | 女主播 | 51 | **0** ✓ | 9 | 60 |
| 2 | 情侣 | 55 | **0** ✓ | 5 | 60 |
| 3 | 男主播 | 57 | **0** ✓ | 3 | 60 |
| 4 | 跨性別 | 60 | **0** ✓ | 0 | 60 |
| 5 | 移动流 | 52 | **0** ✓ | 8 | 60 |
| 6 | 手机版最新 | 49 | **0** ✓ | 11 | 60 |
```
翻页（女主播连翻 3 页）：显示 221 · 其中付费 **0** ✓ · 原始 240 · 累计筛掉 19 ✓ · offset=240 ✓
判据单测（stub 6 条）：免费公开在线→显示✓ · 门票制→筛掉✓ · 按分钟计费→筛掉✓ · 已预告门票秀(关键)→筛掉✓ · 离线→筛掉✓ · 非公开→筛掉✓
对账（另拉 3 页原始数据数）：原始 180 条里 **15** 个付费房，类型全是 ticket ✓（≥ 同页应筛数 ✓；19 那条是 4 页累计 ✓ 不冲突 ✓）
```
---
## 追加（2026-10-03 · **sim 侧第 34 轮**）**去掉「私秀价格 / 类型」那组过滤器** ✓（用户拍板：付费房都不显示了，它没用了 ✓ 只改 `sim/index.html` ✓）
- `MOBILE_FILTERS` 里那整项（`privateShows`）**删掉** ✓ → 选项数据（`privatePrice*` / `autoTagRecordablePrivate` / `autoTagP2P` / `autoTagSpy`）**一处不剩** ✓
  （页面内实测：`MOBILE_FILTERS` 的 key = `["appearance","countries","activitiesOnRequest"]` ✓、字符串 `privatePrice` 出现 **0** 次 ✓）
- **死状态清掉** ✓：加了一段启动时清理 ✓ —— `mfSelBy` 里键首段已不在 `MOBILE_FILTERS` 的**死键**直接删 ✓
- 计数/重置/请求拼装**自动跟上** ✓（它们都遍历 `MOBILE_FILTERS` ✓）→ 请求里不会再出现 `privatePrice*` 组 ✓
- ⚠️ `LIVE_TAG_MAP` 里那几条 `*-privates` → `privatePrice*` 是**另一套**（4 个主 tab 的子分类筛选 ✓）→ **没动** ✓
```
冒烟：移动流 & 手机版最新 都只剩 3 个（外貌 / 国家 / 可请求提供的表演 ✓ · 弹窗内顶部切换同样 3 个 ✓）
      界面含「价格」= 没有 ✓ · grep `价格 & 表演类型` = 0 ✓
      选「熟女」仍生效 ✓（请求 `[[mobile],[ageMilf]]` ✓，还带着付费房过滤 ✓「筛掉 3 个付费房 ✓」）
      重置 ✓（回 `[[mobile]]`）· 国家弹窗仍 82 项 ✓ · 请求原样里**没有** privatePrice 组 ✓ · 无未捕获异常 ✓
```
**约束 ✓（三轮一致）**：只改 `sim/index.html` ✓、**`server.mjs` 0 改动** ✓、`lib/**` 没碰 ✗、没 commit/push ✗、
临时脚本 + Edge profile 清完 ✓、**8788 我起过又停了**（PID 5548 ✓）、**用户 8787 全程没碰**（现 PID 18744 ✓）

---
## 追加（2026-10-04 · **App 侧 $newVer**）直播功能移植到 App + Pornhub 7 条修复 + 坏子域探测优化

### 一、直播功能移植（模拟器 → App，已跑通后复刻）
- **新独立站点** `lib/sites/xhamsterlive.dart`（1291 行）：6 个 tab —— 女主播/情侣/男主播/跨性別（4 个 primaryTag）+ 移动流（`girls`+`[["mobile"]]`）+ 手机版最新（`girls`+`[["autoTagNew"],["mobile"]]`）
- 列表接口 `/api/front/models`：limit 60 · offset 翻页 · 服务端封顶 `filteredCount`（最大 1000）；UA 要浏览器样（`curl` UA 403）、不需要 cookie
- **跳过付费房**（用户要求，6 个 tab 一视同仁）：`groupShowType == '' && status == 'public' && isOnline`。依据：960 条样本实测 —— `groupShowType` 空=免费 939 / `ticket`=21 / `perMinute`；只判 `status` 会漏"已预告门票秀"（status=public + groupShowType=ticket）；`doPrivate`/`doSpy`/`privateRate` 是**能力标志**（85~90% 免费房都带）不能用
- **底栏加「直播」**（模块和设置之间）；`SiteEntry` 加 `SiteGroup { module, live }` **数据驱动分组**（共用 UI 不认站名）→ 模块宫格仍 14 格
- 站点页：**下划线 tab**（非胶囊按钮）+ 2 列竖版房间卡（封面 3:4 + 主播名 + 观看数 + LIVE 标）+ offset 续拉
- 全屏房间页：**WebView 顶层加载** `zh.xhamsterlive.com/<username>` —— 模拟器那套"内嵌站点播放器（new Function + unpkg React）"是**桌面 hack**（站点在 iPhone 上自己就不走 JS 播放器）→ App 用 WebView；左上角 X + 点屏幕 toggle + 静音 + SafeArea
- **过滤器**（只有移动流 / 手机版最新两个 tab 有）：外貌 5 子分组 / 国家 7 组 82 项（**64 项 tagId 未映射 → 灰显不猜**）/ 可请求提供的表演 61 项 —— 共 13 子组 175 选项。入口下划线 tab、弹窗照 `pornhub.dart` 那套；拼装 `filterGroupTags = [tab 自带..., 每个有选择的子分组一个数组]`（**子分组间 AND、同子分组多值 OR**）；已选**按 tab 分开存**；数据用脚本从 `sim/index.html` 的 `MOBILE_FILTERS` 抽取（**非手抄**）
- ⚠️ `lib/api.dart` **必须**给 `SiteTemplate.xhamsterlive` 加 case（`Api.ui` 是穷尽 switch，不给会**编译报错**）
- ⚠️ 站点常量名用 `kSiteLive` 而非 `kSite15`：`sim/server.mjs` 用 `\b(kSite\d+)\b` 认站，叫 `kSite15` 会让**模拟器**模块宫格白多一格

### 二、Pornhub 7 条修复（用户报"有时取到的只有几秒预览"）
**调查结论**：代码**不会**抓预览 —— 正则 `"height":(\d+)[^}]*?"videoUrl":"...master\.m3u8..."` 拿**真页面原文**跑过，只命中自身正片 4 档；站点侧唯一的"短"视频是 `_fb.mp4`（实测 8.93~9.20 秒，挂在**别的视频**的卡片上做 hover 预览），站点也没给正片下发短源。**真正的随机性是 CDN 子域**。
1. **410 坏子域**：`hm-h.phncdn.com` 命中率 **7/25 = 28%**（recon 实测），对任何 header 组合都 410，且**一次抓取内 4 档同一子域**（无备用档）→ 判定从"认 `hm-h` 字面"改成**按响应码实测**（410/404/403 才算坏；超时/异常**不判坏**），重抓上限 2 → **5**
2. **分片 Referer**：recon n=108 实测 —— 分片**必须带站点域名 Referer**（`www`/`cn` 都行，100% 成功）；不带/外来/CDN 自身 → **100% 404**；而 master/variant **不需要** → 这正是"清单能解析、播几秒就断"的形态特征。做法：保留原 `httpHeaders`，**额外加 mpv `referrer` 属性兜底**
3. **中途恢复**：原本"同一批未刷新 URL 从 0 重开" → 改成**先重抓页面拿新签名、再原地 seek 回原位置**（`_recover()` + 10 秒去重 + 切集作废）
4. **看门狗盲区**：卡顿时 mpv 常报 `playing=false`，原早退条件遇到它就每轮清零、**永远判不出卡住** → 改成看 `_userPaused`（给 `KpPlayer` 加 `onUserPause` 回调，**只有 UI 直接点的暂停才置位**）
5. **`/shorties` 形态**：正则改为 `(?:master|index)\.m3u8`（**保留 `"height":` 护栏**）；实测 `index.m3u8` 那条是**完整 VOD**（32 段 / 138.3 秒 / 有 ENDLIST），不是预览
6. **`#EXTINF` 硬编码**：`video_cache.dart` 原本每段写死 10.0 秒（实际 2.25~4.267 秒，329 段 → 报 3290 秒 vs 真实 1431.7 秒）→ 改成解析源清单的**真实段时长**；**条数对不上就整条放弃**（宁可回落在线播）
7. **画质默认**：优先站点标了 `"defaultQuality":true` 的那档（案例视频 1080 → **720**），取不到退回原顺序
8. **坏子域探测优化**（用户要求）：**只探将要用到的那一档**（依据：同一页 4 档同子域，第一档坏=整页坏）+ 坏域**进程内缓存 10 分钟**（键=子域，上限 8 条）+ 探测用 **HEAD**（实测好坏 host 上 HEAD 与 GET 同结果）。
   请求数：好页 1 GET → **1 HEAD**；坏页最坏 **20 GET → 1 HEAD**；再遇已知坏域 **0 请求**

### 三、状态与边界
- **未编译过**：本机无 Flutter SDK（`dart`/`flutter` 都不存在）→ **编译/analyze 只能等 CI**，本次构建即验证；括号余额与 HEAD 基线逐项一致、行尾形态未翻转（`pornhub.dart` CRLF 729 → 790，孤立 LF = 0）
- ⚠️ `lib/sites/pornhub.dart` 的 `git diff` 会显示**整文件重写**（737/728 量级），**实际改动远小于此**：该文件 HEAD blob 本身是 CRLF，而仓库 `core.autocrlf=true` 且无 `.gitattributes` → 任何编辑都显示整文件；用 `--ignore-cr-at-eol` 才是真实改动量
- **未提交**：`sim/**` 全部改动（模拟器侧，按用户「对齐，不提交」）

---
## 追加（2026-10-04 · **1.0.23 构建修复 #1**）analyze 4 个 error 修掉（CI run 37200822586 失败）

- **失败详情**：`flutter analyze` 报 6 issues（4 error + 2 info），**后续构建步骤全 skipped、无产物**；错误原文已抄回（GitHub 服务端日志脱敏把行号里的数字打成 `***`，按**列号**还原后与本地源码逐行吻合）
- **根因 1（跨类）**：`_userPaused` / `_lastRecoverMs` 的**声明**写在 `class KpPlayer`（原 `:227` / `:229`），而**使用点**在另一个类 `class PlayerWidgetState`（`:981` / `:1111` / `:1112`）→ 3 个 `undefined_identifier` + 2 个 `prefer_final_fields` info（原位置无赋值，故分析器认为可 final）
  → **修**：字段搬家到 `PlayerWidgetState`（`:666-670`）；`KpPlayer` 里的**回调字段** `onUserPause`（`:303`）保留不动。挪完 2 条 info 自然消失
- **根因 2（缺 import）**：`lib/sites/pornhub.dart:214` 用了 `Site.ua`，但该文件没有 config.dart 的 import → `Undefined name 'Site'`
  → **修**：`:21` 补 `import '../config.dart';`（照 `lib/sites/kmsvip.dart:20` 的既有写法；`Site` 定义在 `lib/config.dart:8`）
- **附带修**：`player_widget.dart:981` 上一轮留下的"两行挤一行"笔误（`kp.onUserPause = ...;` 后面紧跟 `kp.addListener(_onTick);` 在同一行）→ 拆成两行
- **自检**：字段声明唯一且在正确类内（`KpPlayer` = 133-342、`PlayerWidgetState` = 635 起，`Select-String` 全量逐条对照）；括号余额三项与 HEAD 基线一致；行尾未翻转（`player_widget.dart` 纯 LF 2016 / `pornhub.dart` CRLF 791、孤立 LF 0）；`git diff --numstat` = player_widget **5/5**、pornhub **1/0**（`--ignore-cr-at-eol` 同样 1/0）
- **版本保持 1.0.23**（本次失败未产生任何产物，不浪费版本号）；**仍未编译过**，本机无 `flutter`/`dart` → 只能等 CI 复验

---
## 追加（2026-10-04 · **1.0.23 构建修复 #2**）`_userPaused` 归位（CI run 37201230173 失败，只剩 1 条 error）

- **失败原文**：`error • Undefined name '_userPaused' • lib/player_widget.dart:196:11`（上轮的 2 条 info 和 pornhub.dart 的 `Site` 都已消失）
- **根因（修复 #1 给错了方向）**：修复 #1 把 `_userPaused` 搬到了 `PlayerWidgetState`，但**读它的看门狗在 `KpPlayer` 里** —— 该字段**两个类都要碰**，只搬声明必然"按下一个葫芦浮起一个瓢"。
  真实类边界（本轮现查，不引用记忆）：`KpPlayer` = **133-343**、`PlayerWidgetState` = **636-1412**；`:196` 在 `KpPlayer` 构造函数体的 `_stallTimer` 看门狗里，`:981` 在 `PlayerWidgetState._attach` 里
- **修法（选 B）**：字段归 `KpPlayer`（`:304`），由它**自己的** `play()`（`:306`）/`pause()`（`:311`）维护；删掉 `PlayerWidgetState` 里上一轮搬过去的声明 + `_attach` 里那条跨类赋值；`onUserPause` 回调字段**已无消费者 → 一并删除**（不留死代码）
  ⚠️ 知识点记档：**Dart 的 `_xxx` 是库级私有、不是类级私有** —— 同文件内 `kp._userPaused = v;` 合法；所以跨类访问不是问题，**问题只在"声明该放哪个类"**
- **自检（这轮做透）**：对本次碰过的每个字段列"声明/使用/所属类"对照表逐条对齐（`_userPaused` / `_lastRecoverMs` / `_stallTimer` / `_lastPos` / `_stuckMs` / `_sources` / `_curIndex` / `_restoreTo` / `_autoRetryTimer` / `_opening` 全部同类）；括号 `{}`=233/233、`[]`=25/25 不变，`()`=893→882 的净减**逐行核对**为"删除行含 11 左 + 11 右括号、新增行 0 括号"；行尾仍纯 LF
- `git diff --numstat`：`lib/player_widget.dart` **6/11**；`pornhub.dart` 本轮未动
- 版本仍 **1.0.23**；**仍未编译过**（本机无 flutter/dart，只有 node）→ 等 CI 复验

---
## 追加（2026-10-05 · **App 侧 $newVer**）黄果吃瓜修复 + 播放加载/重试四条 + 直播页外观 + 房间页去壳（sim 同步）

### 一、黄果吃瓜取不到 —— `detailOf` 死代码（用户报）
- **根因**：`lib/sites/huangguo.dart:49-55` 的 `detailOf`（按路径分流：`/archives/N/` 帖子 → `postDetail`）**定义了但全仓 0 个调用点**；`api.dart` 一直直接调 `_ui!.detail(url)` → 吃瓜帖被当**视频详情页**解析 → `videoInitialData` 找不到 → 视频为空
- **实测证据**：真帖 `/archives/653/` 里 `videoInitialData` **0 次**、`epPlaySrcs` **0 次**，但 `div.post-video-player` 有 `data-src`（现成 m3u8）——站点侧一切正常（3 个吃瓜入口都 SSR 出 13 张卡、选择器与 App 逐条吻合、8 种 header 组合全 200 无拦截）
- **修法**：`SiteUi` 加默认实现 `detailOf(url) => detail(url)`（未覆写的站行为**逐字不变**）→ `api.dart` 改调 `detailOf` → 两家覆写者补 `@override`
- ⚠️ **顺带修了 porna**（同一根因）：`/melonshort/video/`、`/heiliao-chigua/`、`/novels/` 三类也从"被当普通视频解析"变成走各自解析器。**用户对此有疑问，已说明这是原代码写好的分派、只是没接线**（`sim/index.html:1292-1298` 从一开始就是这么分的），代码上只加了 3 行注释 + 1 行 `@override`、**逻辑一字未改**
- **实测**：吃瓜帖取到 m3u8 ✓；porna 短视频取到 m3u8 ✓；porna 黑料图文 token→打包 JS→解包出 m3u8 全链通 ✓；对照页（黄果 `/video/5010/`）仍走原解析器 ✓
- `Api.detail` 的 4 个调用者（详情页 / `_refreshSources` / 短片预热 / 短片流）现在**全经过分派**

### 二、播放加载/重试四条（用户报"加载中就直接重试"+"开播后提示还在、又重载一遍"+"能放也自动重试"）
**诊断要点（全有 `file:line`）**：
- 看门狗**从播放器构造就开始计时**（判据只有 position 有没有前进）→ 加载期 position 恒 0 → 9 秒被判"缓冲超时" → 提前换源；`_everStarted` 只被引擎 error 用，**看门狗没引用它**
- `_autoRetrying` **只有 4 个清除点、没有"恢复就撤"**；中途卡住时 position 早 > 0，"首帧上升沿"不会再出现 → 提示清不掉
- 1.2 秒重试定时器**唯一取消点是首帧上升沿** → 视频自己恢复时不取消 → 到点走 `_recover()` → **重载**
- 引擎 error 流在首帧前**任何** error 都写 `KpState.error`，而 `error` 同时是 `_openAndWait` 的"这条源失败"信号 → 启动期偶发 error = **无谓换源**

**修法（全在 `lib/player_widget.dart`）**：
1. **看门狗首帧门禁**：`_everStarted == false` 时不计 `_stuckMs`、不写 `error`（`_stuckLimitMs = 9000` **未动**）
2. **首帧前长兜底**：具名常量 `_kFirstFrameLimitMs = 12000`（`:285`）—— 只在**已 open 成功**之后计时，12 秒仍无首帧 → 按"这条源不行"处理；与 `_openAndWait` 的 15 秒连接超时**不重叠**
3. **恢复即撤**：`_onTick` 里位置前进 ≥100ms **且确实有排着的重试**时 → cancel 定时器 + 清 `_autoRetrying` + `_autoRetries = 0`
4. **首帧前偶发 error 宽限**：具名常量 `_kStartupErrHoldMs = 3000`（`:332`）+ `_startupErrPending` / `_errHoldMs`；错误流**不再当场写 error**，宽限（复用现成的 1 秒看门狗 tick，**无新定时器**）内仍未 `ready` 才判失败 → 实际生效 **2~3 秒**
5. 加固：`_initPlayer` 开头清 `_autoRetrying`；排重试守卫扩到**整段加载**（`_opening || _fetchingLazy`）；`_recover` 收尾再挡一次并发

**不变量自查（5 条全过）**：加载期不产生 error/重试 · 首帧后真卡住仍 **9 秒**照旧判 · 开播瞬间起提示必撤 · 一次事故最多一次重载 · 其它站 + 短片流行为不变（短片自建 `KpPlayer` 且**从不读 `error`**）

### 三、直播页外观（用户真机反馈）
- **删掉两条行底横线**：主 tab 排 `TabBar.dividerColor` → `Colors.transparent`；过滤器排**连 Container 一起删**（不留 1px 占位盒）
- **6 个主 tab 间距收窄**：`labelPadding` 每侧 **16 → 10**（相邻文字 32px → **20px**）
- **4 个主 tab 补分类选择器**（之前漏做）：脚本抽取 **26 组 / 211 子分类 / 82 项未映射**（未映射灰显不猜）；**单选**（与 sim 一致，`parentTag` = 当前选中的 tag，再点取消）；**6 份已选状态各自分开存**；移动流/手机版最新 那两套多选未被影响


### 五、sim 同步（用户定的新规矩：**app/sim 同步改**）
- 删掉 `.lv-tabs` 的 `border-bottom`（连带删 `margin-bottom:-1px`，避免选中下划线被 `overflow` 裁掉）+ `gap: 20px → 16px` → 实测相邻文字 **20.00px**，与 App 对齐；**分类选择器那排 sim 本来就没有线**（全页扫"宽≥200 的可见横线" = 0 条）
- 更正 **7 处过期注释**（"4 个过滤器"→3 个；"手机版最新不给过滤器"→照给）


---


### 二、4 个主 tab 的筛选映射补齐（用户报"怎么这么多未映射"）
**根因**：生成脚本抽取时**键没 trim** —— `LIVE_TAG_MAP` 里**每行第一个键**带着换行/缩进 → 查不到 → `null`。
**证据**：64 条错的**全在源码行首**（chinese/new/teens/arab/latin/petite/curvy/blondes/redheads/hardcore/fisting/bisexuals/twinks/skinny/goth…），而**同一行后面的键全对**（american/ukrainian/vr/bdsm/young/milfs/asian/ebony/indian/mixed/white…）——"行首全错、行中全对"只有这一个解释
**修法**：重新跑抽取（键一律 `trim()`），**只补 id**（名称/顺序/分组/`single` 语义一律不动）；脚本带**同序同名断言**（Dart 与 sim 逐项比对，不符就报错退出）
**结果**：**211 项 = 193 有 id / 18 真无 / 与 sim 不一致 = 0**；重跑一次显示"本次要改 = 0"（幂等 ✓）。用户截图那几项：中文（4 个 tab 全补）/新主播/少女18+/阿拉伯人/拉丁人 全部补上
**那 18 项真无**（sim 也没有 → 标「未映射」是对的）：`Oktoberfest Party`×4、`全部分类`×4（`/tags/*`）、男主播最受欢迎 6 项、跨性別最受欢迎 4 项
⚠️ 用户截图里的 `混血主播` 与数据不符（`git show 6ecf38b` 核过它一直是 `ethnicityMultiracial`）→ 存疑，疑为截图那行被截断（"（未映射）"属于「拉丁人」）

### 三、筛选入口按钮补边框（用户报"分类选择器怎么没有边框"）
- sim 原文：`.pkbar button { border: 1px solid rgba(60,60,60,.35); border-radius: 8px; padding: 5px 10px }` + 选中态 `.mf-btn.on { border-color:#e8590c; color:#e8590c; font-weight:600 }`
- App 照抄到 `LiveFilterBar`（含「重置」按钮）；**顺手去掉原来那 2px 橙下划线** —— sim 这一排没有下划线（那是**上面主分类 TabBar** 的样式，未动）
- 弹窗里的 chip **本来就跟 sim 逐字段一致**（默认透明边框、选中橙框）→ 没改




## 附 · re-js 逆向报告：xHamsterLive 直播"真分片 URL"（2026-10-04）

**结论一句话**：真分片 URL = 播放器**当场解密**出来的。清单里 `#EXT-X-MOUFLON:URI:` 的 **22 字符 base64 token 是密文**（= 16 字节），
播放器用**硬编码在播放器 JS 里的密钥表**（`ui[keyId]`，keyId 就是 `PSCH` 那个 16 字符 pkey）把它换成 **16 字符真 token** 再去取分片。
—— 所以"补 pkey 拿清单 → 照抄清单里的 URL"这条路**永远 404**：清单里的 token 本来就不是给播放器直接用的。
**已实测拿到当下可播的真分片**（无 Referer / 无 cookie 的 curl → HTTP 206 + fMP4 `sidx` 头）✓


### ② Finding

- **F-1（validated，E-002/E-003/E-008）**：清单 `#EXT-X-MOUFLON:URI:` 的 token 是**密文**；播放器用 `ui[pkey]` 当密钥、逐段解出 16 字符真 token。"照抄清单 URL"**结构性不可行**。
- **F-2（validated，E-009/E-010/E-011）**：真分片 URL **无鉴权**（无 Referer/cookie 也 206），但 **TTL 分钟级** ⇒ App 必须"抓到即用"，不能进缓存池；init 段可长期复用。
- **F-3（candidate，E-003 的反例）**：离线算法**尚未完全还原**。反证：播放器今天选的是 `pkey=NTK9aqcLmNFMWrpQ`，而我抠出的 `ui` 只有 2 项且**不含**它 ⇒ **我抠到的那份 `ui` 不完整/不是运行时真正用的那份**（`oi` 是运行时用字符串拼的多分支表，我只跑通了一支）。**卡点**：要让 webpack 模块 5419 在 Node 里**完整执行**才能拿全；但它在某处"正常结束"就再不到后面的注入点（用参数回调注入、按偏移 bisect 都拿不到，见 E-003 备注）。**下一步**：改用真实 webpack runtime（先跑 main.js 拿到 `__webpack_require__`，再 push chunk）把模块 274 整个跑起来，直接调 `ai.v2` 的 pipeline。
- **F-4（validated，E-006）**：`#EXT-X-MOUFLON:FILE:` 在实测 11 份清单里**一次都没出现** ⇒ 静态路径里"解析器把 `media.mp4` 换成 `xxx_<FILE data>`、再由 `Jr._uriRestore` 还原"这条链**在当前站点形态下不会被触发**——前人把它当主线是走偏了。



**没验（诚实交代）**：
- **逐段解密的精确算法没还原完** —— 卡在 `ui` 表抠不完整（F-3 已给反证与下一步）。所以**纯离线算法版本现在给不出**，只能给"半自动（跑播放器抓）"。
- `#EXT-X-MOUFLON:EXT-REF:`（`encodeTimestampMap`：base64 + 魔数前缀 → 时延估算）**只读了代码，没实测**。
- 没验证"换 IP / 换出口后真 URL 是否还认"（只在本机 + 系统代理下测过）。
- 没验证长时间（>30 分钟）连续播放的 TTL 边界，只测到"几分钟后失效"。

---
## 追加（2026-10-05 · **App 侧 $newVer**）直播改用**我们自己的播放器**（含重大发现）+ 去壳整条路撤除

### 一、⭐ 重大发现：iPhone 分支把直播地址**明文**给出，而且 pkey 是硬编码常量
recon 实测（全部有原文/状态码/字节数）：
- **让页面走 iPhone（无 MSE）分支**（杀掉 `MediaSource`/`ManagedMediaSource`/`WebKitMediaSource`/`SourceBuffer` + iPhone UA + 390×844）后，站点自己的 `<video src>` 是：
  `https://edge-hls.doppiocdn.net/hls/<id>/master/<id>_auto.m3u8?playlistType=standard&pkey=B0p93vi8Uj6AYyZb`
  → **明文 HTTPS 直链**，不是 `blob:`、不是 WebRTC（同机对照：有 MSE 时是 `blob:`）
- **那个 pkey 是页面 JS 里的硬编码常量**：`main.js` 里有它；recon 5 次采样一致、跨 20+ 分钟不变；**9 个不同房间/分桶都接受它**（站点级，不是房间级）
- **这条链是干净的**：master 200 / 1287~1852 字节、**无 `#EXT-X-MOUFLON:URI:` 诱饵**、变体 URL 自带 pkey；变体清单 200 / 730~778 字节、**段地址全是明文**（`EXT-X-PART 0`、`media.mp4 0`、`ADVERT=no`）；分片 **206 + `video/mp4`**（`sidx` 头）、**无 Referer 要求**、支持 Range
- ⚠️ **必须 `playlistType=standard` + 带 pkey**：不带 pkey → 返回**广告清单**（`#EXT-X-MOUFLON-ADVERT`）
- **覆盖面实测**：12 个房间 **9 个全链路可用**；3 个失败中 **2 个是付费场（`groupShow+ticket`）**—— 同一时刻站点自己也被同一堵墙挡着、只发 `_160p_blurred`（284×160 模糊预览），**7 种签名组合全 403，绕不过**；另 1 个是房间当时没在播（同一 URL 稍后即 200）。**而付费房我们列表本来就筛掉**（`groupShowType!=''`/`status!='public'`/`离线`），所以实际点得进去的房间走这条路是通的

### 二、房间页改用我们自己的播放器（用户拍板，**去掉兜底**）
- `lib/sites/xhamsterlive.dart`：加 `const String kLivePkey`（`:1645`）+ `liveMasterUrl(int id)`（`:1652`）—— **都只在站点文件里**（`git grep` 证明零外泄）
- `LiveRoomPage` 收 `username + id`；用**现成的** `KpPlayer` + `media_kit` 的 `Video`（与短片页/详情页同一套，**没新造封装**）；**竖版全屏、点屏幕 toggle X、静音**（UI 一个字没动）
- **直播源直接把 master URL 交给 mpv**（mpv 自己刷清单/选档）
- **校验保留、兜底撤除**（用户拍板）：开播前抓一次 master（8 秒超时），**200 且不含 `MOUFLON-ADVERT` 才播**；否则**报错**（四种情况各有明确文案：没 id / HTTP 非 200 / **拿到广告清单（绝不播）** / 抛错）→ **不白屏、不静默、不放广告**
- 实测（curl 走代理）：2 个真实房间 id 拼出来的 URL → master **200/1852 与 200/1292**、零诱饵；变体 **200/738 与 200/730**；分片 **200 + video/mp4** ✓

### 三、为直播改过的共用件**整数还原**（用户硬规矩：改直播不许动别的站点）
- `lib/web_embed.dart` **整文件还原到直播开始之前**（`0332503`），**blob 哈希逐字一致**（`f9327f5a…`）
- 删掉：`extraJs`/`extraJsList`、`toggleX`、`darkShell`（黑底/黑盖/`_ready`/`_readyFuse`）、注入流水线（`_inject`/`_runQuiet`/三注入点/两段解耦）、那个补的 `import 'dart:async'`
- 保留（本来就有的）：静音守护 `_guardJs`、内联播放、进度条、错误重试
- 零残留：`git grep` 那几个符号 **全空** ✓；实际调用点只剩 `web_page.dart:57`（只传 `url`+`onCreated`，**与直播前逐字一致**）⇒ 详情页「打开原页」与"网页"型站点**回到原样**

### 四、附：JS 逆向结论（re-js，授权 granted，已入档）
- **`#EXT-X-MOUFLON:URI:` 里的 token 是密文**：播放器拿密钥表逐段解密才得到真 token ⇒ **"照抄清单"结构性不可行**（前人 25/25 全 404 是必然）。实测反证：同段号同时间戳，**播放器实取 token ≠ 清单 token**
- 真分片**无鉴权**（无 Referer/cookie 也 206）但 **TTL 只有几分钟**；init 段不受影响
- **纯离线算法未还原完**（密钥表抠出来只有 2 项、不含播放器当时用的 pkey）→ 备选方案 = 隐形跑播放器 + 网络层抓地址（**本轮不实现**，因为裸拼地址这条路已经通了）



---

### ⚠️ 方法论修正（用户批评，认）
用户指出：**"本轮纯 HTTP，没有起播！！！不要只看 200 回复就认为可行"** ✓
⇒ 我们此前一直验"能不能取到"（HTTP 200），**没验"能不能播"** ✗ —— 200 只说明服务器给了数据，不说明播放器能解出画面/声音。**已改为真起播验证** ✓。

### 一、真起播实测（recon，hls.js 1.5.17 + headless，**全程静音**）
用 App 那条 URL 形态（`master/<id>_auto.m3u8?playlistType=<x>&pkey=<常量>`）跑 **4 房 × 2 参数 = 8 次**：
| 判据 | 实测 |
|---|---|
| 画面 | `loadeddata`+`canplay`+`playing` 齐全；`readyState=4`（8 次里 6 次，2 次采到 1/2 是缓冲瞬间）；尺寸非零（720×960 / 1280×720）；解码帧数持续增长 |
| `currentTime` | **8/8 在走**（5 秒间隔 Δ1.98~5.01s） |
| **声音** | **`webkitAudioDecodedByteCount` 8/8 > 0**（25,941~104,451 字节且 5 秒内增长）⇒ **流里有声、且真被解码**（本机是 `--mute-audio` 跑的，"能否听见"不影响该字段） |
| 首帧 | **1,606~5,626 ms** |
| 错误 | **无致命**（`standard` 4/4 **零错误**；`lowLatency` 偶发 `bufferStalledError`，`fatal:false`） |
- **对照**：站点自己的房间页也能播、也解出音频（首帧 3.4~3.7s / 18.8~19.1s 两种口径，含整页 SPA 加载+18+弹窗）
- ⚠️ **未复现**用户报的"几分钟/十几分钟不出来"（本轮最长 5.6 秒）⇒ 仍需真机日志

### 二、流侧活性实测（recon，8 房 16 个变体样本，纯 HTTP）
- **`#EXT-X-MEDIA-SEQUENCE` 20/20 全前进**（24~28 秒内 Δ11~14，与 `TARGETDURATION:2` 完全吻合）⇒ **没找到"死流"**
- `#EXT-X-PROGRAM-DATE-TIME` 只落后 **1.6~4.4 秒**（直播边缘新鲜）；首段/新段 **16/16 全 206 + video/mp4（fMP4 `sidx`）**
- **顺带印证**：`403` = 当时处于 **ticket 付费场**（该房现已转 public，两档都 200 ✓）；`404` = 房间**已下播**（`status=off` ✓）

### 三、四处改动（全在 `lib/sites/xhamsterlive.dart`）
| # | 改动 | 依据 |
|---|---|---|
| 1 | **去掉静音**（删两处 `kp.setVolume(0)`；不设固定音量，走系统默认 100） | **"没有声音"是我的错**：我把**探测阶段的"全程静音"规矩**错写成了产品需求 ✗（探测静音是为了自动化测试不出声 ✓，用户看的播放器当然要出声 ✓）。注释已写明 ⚠️ **只改房间页**，`_guardJs`（WebView 静音守护）与别的播放器**没动** ✓ |
| 2 | **交给播放器的是 master URL**（不是变体） | **站点自己在 iPhone 上给原生 `<video src>` 的就是 master**（recon 实测 ✓）⇒ 我此前为"少一跳"改成交变体，**偏离了站点已验证的做法** ✗ ⇒ 改回 ✓；**变体只用于校验** ✓ |
| 3 | `playlistType` **改回 `standard`**（`:1662` 唯一一处码） | **真起播实测**：standard 首帧 **1,606~2,034ms 且零错误** vs lowLatency **2,296~5,626ms 且偶发 stall** ✗ ⇒ 我此前按"清单更厚 ⇒ 起播更快"换 LL 的决策**被实测推翻** ✓（教训已写进注释：**curl 那点数据推不出起播快慢** ✗） |
| 4 | **起播看门狗**（`_kLiveStartMs = 8000`）：8 秒没出画面 → **重开一次**（只一次）→ 再不行**明确报错停止**（"这条直播一直没出画面，可能主播没有在推流"） | 判据用 `KpState` **仅有的**暴露信号 `position > 0`（`player_widget.dart:103`，实测该状态类只暴露 ready/started/position ✓）；阈值依据 = 本机网络那一段实测 ≈2.5 秒 ⇒ 8 秒给 3 倍余量，**两次合计 ≈16 秒** = 用户要的"最多十几秒"✓ ⇒ **再不会干等几分钟/十几分钟** ✓ |
| 附 | **变体校验**（3 秒超时）：master 过了还要看**第一条变体是否 200** | 实测抓到反例：某房 **master 200 且干净、变体却 403** ⇒ 原校验会放过它 → 播放器黑屏干等 ✗ |
| 附 | **关掉播放器自带控件** `controls: NoVideoControls` | 用户要"**只有画面 + X**"✓；双证据：仓库内**现成同款**（`player_widget.dart`、短片页 ✓）+ 包源码 `const NoVideoControls = null` ✓；**没碰**短片页/详情页的播放器 ✓ |


---
## 追加（2026-10-05 · **App 侧 1.0.28**）X 不显示修复 + live 起播参数（mpv 缓存/预读收紧）


### 一、X 不显示 —— 根因（代码实锤）
改前的 `onTap` **只管关、不管开**：

    onTap: () { if (_showX) setState(() => _showX = false); }

而**能把它打开的那行**（`WebEmbed(toggleX: true)`）**在上一轮"去掉兜底"时被一起删了** ⇒ **再也没有任何代码把它设成 true**（`git grep _showX` 全仓仅三处：声明 / onTap / 渲染）

**改**（`lib/sites/xhamsterlive.dart:1881-1882`）：

    behavior: HitTestBehavior.opaque,                     // 整屏任意位置都归我们
    onTap: () => setState(() => _showX = !_showX),        // 真 toggle：开 ↔ 关

X 层本就在 `Video` 之后（Stack 最上）；位置 / 默认隐藏 / 静音 / master / standard / 看门狗**都没动**

### 二、出画面要 1 分钟 —— mpv 侧参数收紧
**现状原文（`player_widget.dart`，该文件本轮未动）**：`KpPlayer({int bufferMb = 200})` → `bufferSize: bufferMb*1024*1024` = **200MB**；`tuneStartupQuiet` 设 `demuxer-lavf-analyzeduration=2.0` / `demuxer-lavf-probesize=1500000` / `cache-pause-initial=no`

**mpv 官方手册原文**（实测抓 `https://mpv.io/manual/stable/`，http=200 / 1,270,401 字节）：
- `--cache-secs`：「How many seconds … to prefetch … **The default value is set to something very high**, so the actually achieved readahead will usually be limited by the value of the **--demuxer-max-bytes** option.」
- `--cache-pause-initial`：默认 **no**；`--cache-pause-wait` 默认 1

⇒ **推断（有手册依据）**：「1 分钟」最可能 = mpv 按"极高的 cache-secs + 200MB"在起播前猛堆数据（**本机无 mpv ⇒ 未复现**，如实标注）

**改（只加在房间页 `lib/sites/xhamsterlive.dart:1780-1782`，共 3 行）**：

| 参数 | 值 | 依据 | 风险 |
|---|---|---|---|
| `cache-secs` | **2** | 手册：默认极高、实际由 `demuxer-max-bytes` 限住、此选项"通常只用于限制 readahead"；直播分片本身 2 秒 ⇒ 攒够≈1 个分片即可开 | 再小（1s）弱网更易断流（有 8 秒看门狗兜底） |
| `demuxer-max-bytes` | **8388608**（8MB） | 手册明说真正限住 readahead 的是它，而默认给到 200MB；按 2~6 Mbps ⇒ 8MB ≈ 10~30 秒缓冲 | 太小（2MB 级）弱网更易 underrun；真机画面不稳**先回调它** |
| `cache-pause-initial` | `no` | 手册默认即 no，显式钉一次（与 `tuneStartupQuiet` 同值，无害） | 无 |

**明确没设**（不猜）：`hls-bitrate`（会掉画质；哪档更稳**没实测**）、`demuxer-readahead-secs`（`cache-secs` 会覆盖它 ⇒ 不是瓶颈）
**看门狗保留**（`_kLiveStartMs = 8000` 仍在）；**`player_widget.dart` 一个字没动**


---
## 追加（2026-10-05 · **App 侧 1.0.29**）X 放大一倍 + 起播状态字 + 直播全量日志


### 一、X 尺寸翻倍（`lib/sites/xhamsterlive.dart`）
| 项 | 改前 | 改后 |
|---|---|---|
| `padding` | 8 | **12** |
| 触摸区 | 38×38 | **76×76** |
| 图标 `size` | 20 | **40** |
位置（SafeArea + topLeft）、默认隐藏、点击 toggle **都没动**（`git diff` 只有这 4 个数值）

### 二、线索 A（"参数调晚了"）**被排除**
原文行号：参数在 `:1796-1798`（`cache-secs` / `demuxer-max-bytes` / `cache-pause-initial`），`await kp.open(...)` 在 `:1814` ⇒ **参数确实在 open 之前** ⇒ "调晚了所以没生效"不成立
**顺手加的一层防御**：`open()` **之后再钉一次**同样三条（`:1821-1823`，幂等）—— 因为 `KpPlayer` 的 `bufferSize`（默认 **200MB**，`player_widget.dart:134/137`）是 media_kit **在 open 时自己设的**，可能盖掉先设的值
**诚实记录**：mpv 手册原文其实**削弱了**"缓存参数导致等 1 分钟"这个解释（配合 `cache-pause-initial=no`，缓存本该拖不住首帧）⇒ **真机慢的根因仍未定死**（本机无 mpv/libmpv，无法复现）

### 三、起播状态字（屏幕上的一行，**不写文件**）
`_stage` getter `:1716-1724`，判据只用 `KpState` 暴露的三个（`ready`/`started`/`position`）：
- `打开中… Ns` = 校验/连接阶段（`k == null`）
- `连接中… Ns` = 还没 `duration>0`
- `缓冲中… Ns` = `ready` 但 `position == 0`
- 出画面 → 不显示
显示在 `Stack` 底部居中（`bottom: 28`，13px，灰 `0xFFB0B4BA`）；计时 `Timer.periodic(1s)`，出画或销毁即 cancel
⇒ **三种卡点对应三条完全不同的修法** —— 下一轮用户念出这行字即可一击命中，不再试参数

### 四、直播**全量日志**（用户要求；**复用现有设施，未新造**）
**复用的**（这几个文件**一行没动**）：`lib/site_error_log.dart`（写 App 沙盒 `kpxx_error.log`，追加一行 `[时间] [站点名] 内容`，512KB 截断，自带 try/catch）+ `lib/error_log_page.dart`（查看/复制/清空）+ 设置页入口（`settings_page.dart:280`）
**新增（只在站点文件）**：`import '../site_error_log.dart';`；`Stopwatch _sw` + `_log(String)`（站点名 `直播/<username>#<id>`，每条带 **`+NNNms`（从进入页面起算）**，`unawaited` 不等待）；**节流** = 只记里程碑 + `ready`/`started` 跳变 + `position` 每 5 秒一条（**不按 KpState tick 写盘**）
**22 个接点**覆盖：进入页面 → master URL 原文 → 校验 master（HTTP/字节/耗时/是否广告）→ 第一条变体 URL → 校验变体同样三项 → mpv 选项（open 前）→ `kp.open()`（URL+headers+返回耗时+抛错含栈前 4 行）→ mpv 选项（open 后补钉）→ `KpState` 跳变（ready/started/position/duration/error/errorText）→ 看门狗三条 → 每条错误 → 离开页面（存活 ms）
**用户导出步骤**：设置 → 错误日志 → 「复制全部」→ 粘到聊天发我


---
## 追加（2026-10-05 · **App 侧 1.0.30**）接入 **mpv 自己的日志**（定位"起播 28.7 秒"的卡点）

### 真机日志（1.0.29）—— 卡点已定在 mpv 内部
```
+0ms      master URL 原文
+757ms    校验 master → HTTP 200 / 1292 字节 / 耗时 757ms / 广告=false
+1684ms   校验变体 → HTTP 200 / 739 字节 / 耗时 927ms
+1717ms   kp.open() 返回 ✓ 耗时 32ms（无异常）
+6687ms   等待 5s：ready=false started=false position=0 duration=0
+9720ms   看门狗：8s 到 → 重开一次（kp.open() 返回 1ms）
+11687ms  等待 10s：仍无
+16687ms  等待 15s：仍无
+17723ms  看门狗：第二次 8s 也过 → 报错停止
+21686/+26687ms  等待 20s/25s（← 放弃后仍在打，见下"顺手修"）
+28702ms  KpState: ready=true（duration=2482ms）   ← **28.7 秒才拿到时长**
+28721ms  KpState: started=true（出画面，总耗时 28721ms）
+40704ms  离开房间页
```
⇒ **我们这侧（校验 + `open()` 调用）1.7 秒全搞定**；`kp.open()` 是异步立刻返回（32ms）；**mpv 侧从 open 到 ready 约 27 秒** ⇒ 慢在 **mpv 内部**（不是网络、不是我们的代码）

### 一、接入 mpv 日志（**绕开共用件**，`player_widget.dart` 未动）
**API 实证**（包源码，本机下载后查）：
- `media_kit_video-1.2.5/lib/src/video_controller/video_controller.dart:56-58` —— `class VideoController { … final Player player; }`（`player` 是**公开**字段）
- `media_kit-1.1.11/lib/src/models/player_stream.dart:91` —— `final Stream<PlayerLog> log;`
- `media_kit-1.1.11/lib/src/models/player_log.dart:15-23` —— `class PlayerLog { String prefix; String level; String text; }`
⇒ `KpPlayer._p` 虽私有，但 **`kp.videoController.player.stream.log`** 从站点侧就能拿到 ⇒ **无需改共用件**

**实现（只在站点文件）**：
- `_tapMpvLog(KpPlayer kp)`（`:1754`）+ 调用点在 `KpPlayer()` 与 `tuneStartupQuiet()` **之后立刻**（早于 `open()`）
- **过滤**：关键字白名单（`http / tls / dns / hls / demux / cache / buffer / stream / error / fail / timeout / retry / conn / proxy / refused / reset`，大小写不敏感），不命中丢弃
- **限速**：每秒最多 **4** 条、每次打开最多 **200** 条（到顶记一行提示）、单行截 **400** 字符；整段 try/catch（拿不到日志也不影响播放）
- 前缀 `mpv[<秒>s]`，与既有日志同格式（`[时间] [直播/<名>#<id>] +NNNms mpv[Ns] …`），用户仍在 **设置 → 错误日志 → 复制全部** 导出

### 二、顺手修的一个小 bug（真机日志里发现的）
看门狗 `+17723ms` 已"报错停止"，但 `+21686/+26687ms` 的"等待 20s/25s"**还在打** ⇒ 5 秒轮询在放弃后没停
**修**：新增 `bool _gaveUp`（`:1794`）+ `_stage` 开头 `if (_gaveUp) return '';`（`:1797`）+ 轮询守卫加 `|| _gaveUp`（自行 `t.cancel()`）+ 放弃分支真停（`_gaveUp = true; _stageT?.cancel(); _stageT = null;`）

### 三、**没动**的东西（等 mpv 日志再定）
- **8 秒看门狗阈值一个字没动** —— 从现有日志**判不出**"重开有没有重置 mpv 计时"（`kp.open()` 异步立刻返回，不反映 mpv 内部进度）；🔍[推断] 若 mpv 首帧本来就要十几~二十几秒，**8 秒重开反而可能是打断**（候选，待 mpv 日志定）
- 若默认日志级别里 mpv 不给 http/tls 细节 ⇒ 下一步调 `--msg-level`（**先去手册查实选项名与取值，不猜**）


---
## 追加（2026-10-05 · **App 侧 1.0.31**）把 mpv 日志级别提上去（要看清"第一条分片失败"的底层原因）

### 真机日志（1.0.30）—— 病灶已定位到 mpv/ffmpeg
```
+9738ms mpv[9s] ffmpeg/demuxer error hls: Error when loading first segment
        'https://media-hls.doppiocdn.net/b-hls-04/259766185/259766185_480p_h264_2282_BZ6eld5VPStLlBiG_1791134469.mp4'
+9742ms mpv[9s] lavf error avformat_open_input() failed
+25222ms KpState: ready=true        ← 20 多秒后 mpv 自己重试成功
```
⇒ **不是 DNS、不是 TLS、不是我们的代码**：mpv/ffmpeg **加载"清单里第一条分片"失败 → 内部重试 → 20 多秒后才成**。分片时间戳 `1791134469` = 当时（不旧）
⚠️ **一处可疑时序（推断，未实测）**：该错误出现在**看门狗重开之后 67 毫秒**（`+9671ms` 重开 → `+9738ms` 报 `hls: Error when loading first segment` → `avformat_open_input() failed` 是"open 被中止"的典型形态）⇒ **8 秒重开可能打断了它正在做的加载**。**本轮未动阈值**，等更详细日志 + 本地复现再一起改


### 二、"重试/超时"候选选项（**只列未改**，全部手册/文档查实）
| 选项 | 语义（原文摘要） | 备注 |
|---|---|---|
| `--network-timeout=<s>` | mpv 手册：网络超时，**默认 60 秒**；"affects at least HTTP" | 手册警告会破坏 RTSP（我们只播 HLS ⇒ 不受影响） |
| `--hls-bitrate=<no\|min\|max\|rate>` | mpv 手册：**默认 max**（挑最高码率档） | 失败的那条是 `_480p_h264_…`；"最高档恰好坏了"是候选（代价：降画质） |
| `--demuxer-lavf-o=<k>=<v>` | mpv 手册：把 AVOptions 传给 libavformat demuxer | **mpv 侧唯一有文档的入口** |
| `reconnect_on_http_error` | FFmpeg 协议文档：按状态码重连（可写 `4xx`/`5xx`） | 经上一条传入 |
| `reconnect_streamed` | FFmpeg：直播流（非 seekable）也允许重连 | 同上 |
| `reconnect_delay_max` / `reconnect_delay_total_max` / `reconnect_max_retries` / `respect_retry_after` | FFmpeg：重连上限/延迟/尊重 `Retry-After` | 同上 |
| ~~`--stream-lavf-o`~~ / ~~`http_retry`~~ | **查无此项**（手册/FFmpeg 文档均无） | 别写进代码 |
**决定**：**先只上日志级别**，看清失败到底是 403/404/5xx 还是连接超时，**再决定改哪个重试参数**（否则是碰运气）


---
## 追加（2026-10-05 · **App 侧 1.0.32**）日志被冲垮的根因修复 + 看门狗重写 + 日志上限 5MB 保留末尾


### 一、日志被冲垮 —— 两条根因（一条是我加的，一条是先前埋的）
**① `msg-level`（1.0.31 我加的）** ✗
`setMpvOptionQuiet('msg-level', 'ffmpeg/demuxer=debug,ffmpeg=debug')` ⇒ debug 级下 `stream.log` 每秒几千条 ⇒ **事件流压死 Dart 侧**（连我们自己的写盘任务都排不上）⇒ **已删**（`git grep` 证明无该调用，仅剩注释说明；**并写明"以后别走提高 mpv 日志级别这条路"**）
**② `KpState` 监听里 error 分支没去重（先前埋的）** ✗
该监听**每次状态变化都跑**（position/volume 一秒几十次）⇒ 只要 `error` 持久为真，就**按 tick 刷盘**（每条还带 `flush`）+ `SiteErrorLog` **超限整体清空** ⇒ **反复清空 = 整页空白** ✓
**修**：新增 `String _lastErrLog`，**同一条错误文本只记一次**（文本变才再记）
**逐条核过其余 24 个 `_log` 调用点**：`等待 Ns` / `position` 各**每 5 秒 1 条**；`ready`/`started` 各 1 次；其余为一次性路径 ⇒ **稳态最多 ~1.2 条/秒**

### 二、看门狗重写（按实测推翻旧设计）
**依据**：真机日志 `+17673ms` 判"失败"、但 `+25222ms` **它其实出画面了** ⇒ **我们的"失败"是误报**；且那条 `hls: Error when loading first segment` 出现在**我们重开之后 67ms**（`avformat_open_input() failed` = "open 被中止"的典型形态）⇒ **8 秒重开极可能就是报错的制造者**
**改**：
- **删掉"8 秒重开"**（`kp.open()` 全仓只剩首次一处）
- **超时不再判失败**：8 秒起文案变 `仍在加载… Ns`（`kLiveStillMs = 8000`），**播放器照跑**
- **只有真出错**（`KpState.error`）才显示错误；**90 秒**（`kLiveGiveUpMs`）到点只提示一句（**不停播放器**）—— 依据：recon 实测分片地址只活 **~25~28 秒**、清单窗口 3 段（≈6s）+ 真机成功点 **25.2 秒** ⇒ 90 秒 ≈ 3.5 倍余量
- 死代码清理：`_kLiveStartMs` / `_wdRetried` / "正在重试一次…" 全删

### 三、日志上限 5MB + 超限**保留末尾**（用户拍板改共用件）
`lib/site_error_log.dart`：
- `maxBytes = 5 * 1024 * 1024`（**5MB**，原 512KB；用户原话"改成 5mb 吧，也影响不了什么"）
- `keepBytes = maxBytes ~/ 2`（≈2.5MB，与上限联动）
- 超限行为：**裁成末尾 keepBytes**（不再整篇清空）—— 实现 `_trimTail`：按字节读末尾 → **从第一个换行（0x0A）之后取** → `utf8.decode(allowMalformed: true)` → 覆写 ⇒ **从换行边界裁、不切中文** ✓
- ⚠️ 诚实提醒：2.5MB 尾部是**一次性读进内存**（约 2.5MB 字节 + 解码字符串 ≈ **~10MB 级瞬时占用**）；真机若卡顿可把 `keepBytes` 改成 `maxBytes ~/ 4`
`lib/error_log_page.dart`：**新加一行说明**（"上限 5MB，超限保留末尾约 2.5MB（只留最新的一段，不会整篇清空）"）—— 纠正：页面**原来并没有显示上限**；正文三态逻辑抽出 `_body()`（**逻辑一行没变**）


---
## 追加（2026-10-05 · **1.0.32 构建修复 #1**）`error_log_page.dart` 的 `const` 上下文错误

- **失败原文**（CI run `37221433462`，analyze 1 条 error，构建步骤全 skipped、无产物）：
  ```
  error • Invalid constant value • lib/error_log_page.dart:107:55 • invalid_constant
  ```
- **根因**：新加的那行说明外层写了 `const Padding(`，而里面的 `style: TextStyle(fontSize: 12, color: kTxtSub)` 中 **`kTxtSub` 是运行期 getter**（`lib/app_background.dart:56`，非 const）⇒ const 上下文里引用非 const 值 ⇒ `invalid_constant`
- **修**：去掉那个 `const`（`lib/error_log_page.dart:107`）—— 整段改为非 const 上下文；`EdgeInsets.fromLTRB` / `TextStyle` 也**不再标 const**（标了同样会报，因为 `color` 仍非 const）；注释里写明这条防以后再被"顺手加 const"
- **同文件自查**：把所有 `const` 出现点逐行核过 —— 全部只引用字面量/框架 const 构造；运行期符号 `kTxtSub` 只有 2 处（`:111` 现为非 const ✓、`:130` 所在分支本就没标 const ✓）⇒ **无同类坑**
- numstat：`lib/error_log_page.dart` **5/1**（只此一个文件）；括号平衡；行尾纯 LF
- **未编译**（本机无 flutter/dart）⇒ 以 CI 复验；版本仍 **1.0.32**

---
## 追加（2026-10-05 · **App 侧 1.0.33**）日志"读不出来"根因修复 + 写日志串行化 + 试关硬件解码

### 真相：日志一直**在写**，是页面**读不出来**
用户从沙盒里拿出 `kpxx_error.log`（**8562 字节，内容正常**），我实读该文件：
```
size=8562  roundtrip_equal=false  第一个坏字节在偏移 740  U+FFFD 计数=3
坏处形态：…\n�� Player 时设 ✓）\n[2026-10-05 01:35:36] …
```
- 文件里**有内容**（`进入房间页` / `校验` / `kp.open() 返回 耗时 39ms` 等都在）
- 但**混进 3 个坏字节**（含**半截行**）⇒ 整文件**不是合法 UTF-8**
- ⇒ `error_log_page` 走 `SiteErrorLog.read()`，原来用**严格 UTF-8 读** ⇒ **遇坏字节抛错** ⇒ 页面**空态与读失败长得一样** ⇒ 用户看到"全空白" ✗
- ⚠️ 上一轮把它当成"被冲垮/被清空"是**误判**（真因是读失败）；本版按真因修

### 一、容错读（`lib/site_error_log.dart:114-124`）
```dart
static Future<String> read() async {
  try {
    final f = await _file();
    if (f == null) return '（读日志失败：拿不到 App 文档目录 ✗）';
    if (!await f.exists()) return '';                  // 只有"真没写过"才是空
    final bytes = await f.readAsBytes();               // 原来直接 readAsString()（严格 UTF-8）
    return utf8.decode(bytes, allowMalformed: true);    // 坏字节变 �，绝不整页空白
  } catch (e) {
    return '（读日志失败：$e ✗）';                       // 失败显示原因，不再伪装成"没内容"
  }
}
```
**可运行验证（Node，真造坏字节）**：严格读 → **抛错**（= 页面空白）；容错读 → **读出 198 字**、替换字符 3 个、首末行正常 ✓ ⇒ 与用户现象完全对上，且证明修后能看到内容 ✓
（`error_log_page.dart` 本身**不用改** —— 它调的就是 `SiteErrorLog.read()`）

### 二、写日志串行化（`lib/site_error_log.dart:78-87`）
原来每条日志是 `exists → length → (超限则裁) → append` 的**读-改-写**，**并发调用互相搅**（坏字节/半截行的来源）
改为 **Future 串行队列**（`_q = _q.then(...)`），**裁剪在 `_write()` 内部** ⇒ 不可能"边裁边追加"；零新依赖；调用方 `await` 语义不变
**可运行验证（Node 忠实 async 模型）**：起点"刚好不到 5MB 的按行日志"，**200 次并发写入**后 —— **无队列**：5,251,630 字节（**超过上限 ⇒ 裁剪被搅掉**）；**串行**：2,630,060 字节（≈keepBytes+新增，**裁得干净**）✓
⚠️ **诚实交代**：该实验只证明"上限失效/裁剪被搅乱"；**没有复现**用户文件里那种"半截行 + 3 坏字节"的成形过程（需要真机写入时序）⇒ **"以后再也不会产生坏字节"不能保证**；但**"再坏也能读出来"**成立 ✓

### 三、起播慢：试关硬件解码（房间页侧，`lib/sites/xhamsterlive.dart:1908`）
```dart
kp.setMpvOptionQuiet('hwdec', 'no');   // 放在 open() 之前；一行、可回退
```
- **依据**：真机日志原文 `mpv[26s] ffmpeg/video error h264: hardware accelerator failed to decode picture`（硬解已报错）
- **查证**：`git grep hwdec -- lib/` **为空** ⇒ 本仓从没设过 ⇒ 之前用 mpv/media_kit 的默认（会试硬解）；⚠️ media_kit 自身默认**未查证** ❓
- **代价**：CPU 高一些（只播一路 ⇒ 可接受）
- ❓ **效果只能真机验**（本机无 mpv/libmpv）


---
## 追加（2026-10-05 · **App 侧 1.0.34**）⭐ 起播慢的**真正主因**：喂 master 导致 ffmpeg"逐档探测"（本地 mpv 实测）

### 一、怎么测出来的（本地 mpv，用户提议"装个最小的 mpv"）
- **装**：winget 包 `mpv-player.mpv-CI.MSVC` → `mpv v0.41.0-dev-g41f6a6450`（`FFmpeg f853d12`）；**便携解压到 `G:\ZCode\_mpv_tmp\`，跑完全部删除（274.2 MB，`Test-Path=False`）**
- ‼️ 所有调用**静音**（`--ao=null --mute=yes`）‼️
- ⚠️ winget 安装时**往用户 PATH 追加了一项**，recon **立即移除并复核**（`User PATH 含 _mpv_tmp? False`）—— 如实记录

### 二、ffmpeg 时间轴（原文，决定性）
```
[ 0.014s] Opening .../hls/227556210/master/227556210_auto.m3u8
[ 1.125s] hls: Opening '.../227556210/227556210.m3u8' for reading      ← 第 1 档（source）
[ 3.371s] HLS request ..._360_ueUxrYejYiR8miFC_...mp4   (playlist 0)   ← 第 1 档首段
[ 5.165s] HLS request ..._480p_h264_360_...mp4          (playlist 1)   ← 第 2 档首段
[ 7.361s] HLS request ..._240p_h264_362_...mp4          (playlist 2)   ← 第 3 档首段
[ 8.654s] AVIOContext: Statistics: 527710 bytes read
[ 9.246s] mov,mp4,m4a,3gp,3g2,mj2: Found duplicated MOOV Atom. Skipped it
[11.645s] h264: Reinit context to 256x240, pix_fmt: yuv420p            ← 才解码首帧
[11.875s] finished playback, success (reason 0)
```
⇒ **喂 master 时，ffmpeg 会把每一档都打开、各取一条首段**（每档 ≈0.5~2s 的 TLS 往返 + 解析）⇒ 十几秒就是这么攒的 ✗
⇒ **不是网络、不是解码器、不是我们设的缓存参数**

### 三、A/B（同一房间同一 URL，各 2~3 次，墙钟）
| 变量 | 耗时 | 结论 |
|---|---|---|
| **master** | 13,229 ms | 现状 ✗ |
| **★ 单档变体 URL** | **2,929 ms** | **快 10.3 秒** ✓ |
| `hwdec=no` | −2,600 ms | 有收益（保留） |
| 我们那套（analyzeduration/probesize/cache-pause-initial/cache-secs/max-bytes=8MiB） | −1,700 ms | 方向对（保留） |
| `demuxer-max-bytes` 8MiB vs **200MiB** | 几乎无影响 | **"200MB 缓冲拖慢"被否掉** ✗ |
| `--cache=no` | 抖动大、无稳定收益 | 不采用 |

**未复现** `Error when loading first segment`（本地 0 次）✓；另实测：**拿 mpv 直接开"裸分片 URL"必失败**（`exit 2`，缺 init/`ftyp` 上下文）⇒ 真机日志里那条 `avformat_open_input() failed` **更可能是"URL 已过期/裸分片打不开"，与网络断无关** ✓



---


### 三、⚠️ 预期与上限（recon 本地 A/B 结论，必须记录）
**9 组 mpv 配置 A/B（单档变体 URL，各 3 次）：2.90~3.60 秒，差异在噪声级** ⇒ **光调 mpv 参数压不到 2 秒** ✗
**它把 2.9 秒拆开了**（ffmpeg 时间轴原文）：
```
[0.012s] 打开清单
[0.469s] 清单到达             ← 一次 HTTPS 往返 ≈0.45s
[0.914s] init 段开始          ← ≈0.44s
[1.376s] init 到达
[1.858s] 首段请求
[2.334s] 首帧显示             ← 第 4 次往返
```
⇒ **2.9s ≈ 4 次串行 HTTPS 往返(≈1.8s) + 进程/解码初始化(≈1.1s)；参数只占 0.1s**
⇒ **对照：hls.js 同机同房同 URL = 1775 / 2034 ms**（≈用户说的"网页 2 秒"）⇒ 差的 ~0.9s ≈ 2 次多余往返
⇒ **要真进 2 秒，只能减少串行往返（架构改动：App 侧并发预取/连接复用，把数据就近喂给 mpv）** —— 该方案 recon **未测**，本轮**先出 A 包（配置层）**，B 方案待用户拍板
- `probesize` **别动**：实测变小反而更慢（500k=3595ms / 50k=3198ms）✗


---
## 追加（2026-10-05 · **App 侧 1.0.36**）⭐ 直播改用**系统播放器（iOS = AVPlayer）** + 设置新增「硬件解码」

### 一、为什么换播放器（关键决策，有网搜 + 实测依据）
- **一直用内置 mpv/ffmpeg 就是根子上的选错**：本地 mpv 实测的账 —— **每次分片请求都新建 TCP 连接**（经代理每次 CONNECT+TLS ≈0.44~0.48s，4 次串行 ≈1.8s）+ 探测 + 进程/解码初始化 ⇒ 2.9s（真机 5.5s）
- **浏览器（hls.js）同机同房同 URL 只要 1775/2034 ms** —— 因为它复用热连接、不重复握手
- **站点自己在 iPhone 上走的也是原生 `<video>`（= AVPlayer）** ⇒ 这就是它 ~2 秒能出的原因
- 网搜佐证：Flutter 官方 `video_player` **iOS 端 = AVPlayer**、Android = ExoPlayer（"开箱即用效果最好"）；**AVPlayer 在 iOS 14+ 原生支持 LL-HLS**
- 失败的便宜尝试（已排除）：`multiple_requests` / `Connection: keep-alive` / `http_version=1.1` —— 前两者实测无提速（`http_version=1.1` 在 https 上是**无效选项**、会让播放直接失败，已明确禁用）

### 二、直播房间页整块换播放器（`lib/sites/xhamsterlive.dart`，`191 440`，**净删 249 行**）
- **依赖**：`pubspec.yaml` 加 **`video_player: 2.9.5`**（钉版本的依据：它是 `environment.sdk` 允许本仓 **Dart 3.5.4** 的**最新一版**；2.10.0 起要 ^3.6.0、2.12+ 要 ^3.12 —— pub.dev 各版原文为证）
- **渲染**：`VideoPlayerController.networkUrl(url, httpHeaders: {'User-Agent': Site.ua})` → `initialize()` → `VideoPlayer` **等比铺满、零控件** ✓（正合"只要画面 + X"）
- **不静音** ✓（`setVolume(1.0)`）；**X 一个数没动**（76×76 / 图标 40 / SafeArea / 点屏幕 toggle / 默认隐藏）
- **保留**（与播放器无关的公共部分）：**按房间记变体 URL + 跳过 master** ✓、**master 的广告校验**（`MOUFLON-ADVERT`）✓、**交给播放器的是我们挑的单档变体（source/720p，不降画质）** ✓、直拼失败自动回退抓 master 一次 ✓
- **看门狗/状态字/日志改判据**：`isInitialized` / `position` / `isBuffering` / `errorDescription`（8 秒 → "仍在加载…"、90 秒兜底提示、**不重开不误报**）
- **mpv 专属项全清**：`hwdec` 覆盖 / `cache-secs` / `demuxer-max-bytes` / `cache-pause-initial` / `analyzeduration` 覆盖 / mpv 日志通道 —— 零残留（`git grep "KpPlayer\|setMpvOptionQuiet\|hwdec" -- lib/sites/xhamsterlive.dart` = **空**）
- **`player_widget.dart` 一个字没动**（其它站点继续用 mpv）✓

### 三、设置新增「硬件解码：自动 / 硬解 / 软解」（用户拍板）
- `lib/settings.dart`（照 `bufferMb` 那套：`SharedPreferences` + 常量键 + `load()` 校验 + `setHwdec()`）；`lib/settings_page.dart` 播放组加一行（复用现成 `_row/_seg/_note`）
- **映射（mpv 手册原文为依据）**：**自动 = 不设**（手册明写"硬件解码默认不开启"）· **硬解 = `auto`**（手册明写"硬解不可能时回落软解"）· **软解 = `no`**
  - ⚠️ 如实纠正：我提过的 `auto-safe` **不在这版 mpv 手册的值列表里** ⇒ 未采用 ✓
- **生效范围**：**除直播外的所有播放**（4 处建播放器的地方都经过 `tuneStartupQuiet` ⇒ 一处生效 ✓；`git grep` 确认无任何站点另设 `hwdec` ✓）
- ⚠️ **文案待改**：副标题现在写"影响所有站点"，而直播已改系统播放器 ⇒ 应为"仅内置播放器生效"（用户已同意改，本轮未动，下轮一起）

### 四、⚠️ 未验（如实，全部只能真机/CI）
- **AVPlayer 能不能吃这条 HLS（fMP4 + `#EXT-X-MAP` + 自定义 UA）、几秒出画面** —— 只有真机能证 ❓
- `video_player 2.9.5` 的 API 面：**只有 `httpHeaders` 一处是从该版源码 grep 到的**，其余签名**未逐一核对** ❓
- `hwdec` 三个取值在真机上是否被 media_kit 采纳 ❓；**"自动"很可能实际=软解**（mpv 手册：硬解默认不开；media_kit 有无另设默认**未查证** ❓）


---
## 追加（2026-10-05 · **1.0.36 构建修复 #1**）`pubspec.yaml` 缩进错误（依赖被写到顶层）

- **失败原文**（CI run `37227044667`，挂在 `生成 iOS 工程`，analyze/build 全 skipped、无产物）：
  ```
  Error detected in pubspec.yaml:
  Error on line 35, column 3: Expected a key while parsing a block mapping.
    35 │   webview_flutter: '>=4.7.0 <5.0.0'
  ```
- **真因**：新加的 `video_player: 2.9.5` **顶格写在顶层**（缩进 0），而 `dependencies:` 下的兄弟项都是缩进 2 ⇒ YAML 认为 `dependencies` 映射已结束、`video_player` 成了新的顶层 key；下一行开始出现缩进 2 的真实 token 时，父级已是标量 `2.9.5`，不允许子块 ⇒ 报错指向**第一个越界 token（35:3）**，真凶是**第 32 行少 2 个空格**
- **修**：把 `video_player: 2.9.5` 及其上面两行注释一并缩进 2 空格（与 `media_kit*` 兄弟项一致）；**只动空白，版本号与内容不变**
- **验**：逐行量前导空格（`media_kit*` 与 `video_player` 均为 2）；括号/行尾（`pubspec.yaml` 纯 LF）；`git diff --numstat` 只 2 行变动
- **未编译**（本机无 Flutter/Dart）⇒ 以 CI 复验；版本仍 **1.0.36**

---
## 追加（2026-10-05 · **App 侧 1.0.37**）⭐ 直播页收尾 + 全量复检落地（死代码清理 + 体验修复）

### 一、直播页（用户逐条点名）
| 项 | 结果 |
|---|---|
| **去掉状态提示 + 全量日志** | `_stage` 整套（含计时器/`kLiveStillMs`/`kLiveGiveUpMs`/90 秒兜底）与所有 `_log(...)` 调用、`Stopwatch`、import 全删 ✓；**保留 `_err` 错误文案**（失败时得有话说 ✓）；**公共件 `site_log_error`…准确名 `lib/site_error_log.dart` 一字未动** ✓ 别的站点还在用 ✓ |
| **tab ↔ 分类选择器间距** | 先量 **App 端 Pektino 的真实几何**（共用渲染器 `home_page.dart:389` 自带 `EdgeInsets.fromLTRB(10, 6, 10, 0)`）= **6** ✓；我一度改成 10 ✗ ⇒ 用户纠正后**改回 6** ✓（教训：**间距一律照对应页面的既有值，不许自己拍数值**） |
| **播放器"越用越卡"** | 真根因：`await initialize()` 期间退出页面时，`catch` 里**没有 `mounted` 检查** ⇒ 回退分支**又新建一个播放器** ⇒ 僵尸实例累积 ✓ 已修（只收自己那份、绝不重建 ✓） |
| **下拉刷新** | `RefreshIndicator` + **复用现有 `feed.reload()`** ✓；收圈用 `feed.loading` 轮询（80ms 起步 + 12 秒上限兜底 ✓ 不新造加载逻辑 ✓） |
| **删掉"子分类选择器"整排** | 用户拍 **B 案**（6 个 tab 全删 ✓）—— 第一步：删渲染 + 两套弹窗 + 那批筛选数据（`filters` 传空表 ⇒ **"拉列表"请求链行为不变** ✓）；**保留** 6 个主分类 tab / 卡片 / 下拉刷新 / AVPlayer / X-toggle / 缓存直拼 / master 广告校验 ✓ |
| **`A1` 第二步（清那层"已选状态"管道）** | 严格三步：① **先改请求拼装**（`sel.groups()`/`selTag()` 恒为空 ⇒ 删这两个实参 ⇒ **URL 与改前逐字节相同**（依据：`Api.list` 两个具名参数默认值就是空 ✓ + 全仓写入通道 0 处 ✓））② 拆桥（`LiveTabDef.filters` + 4 处空表）③ 删 4 个类 ✓ 文件 **1231 → 1050 行** |
| **错误日志页黑白自适应** | 根因三条：**没挂 `AppBg.i` 监听** ✗、三个图标**没给颜色** ✗、正文 `TextStyle` 是 `const` 且无色 ✗ ⇒ 照 `app_background.dart` 既有模式修（`kTxt`/`kTxtSub` + `ListenableBuilder`）✓ 覆盖**窗口标题 + 正文 + 右上角 3 个按钮** ✓（⚠️ 必须**去掉 `const`** ✓ 上次栽过 `invalid_constant` ✓） |

### 二、全量复检（两路独立：`app-dev` + 一个新开的只读审计员）—— 落地清单
- **A2 去重**：4 处"标签弹窗外壳" + 3 处"筛选按钮"（`home_page` 原版 + `hanime1`/`pornhub` 两份**逐字副本**）+ 2 处手写 chip ⇒ 收敛成 `base/site_ui.dart` 的 `siteTagDialog` / `siteFilterBtn` / `tagChip` / `confirmClear` ✓
  - ⚠️ **所有语义差异参数化保留**（D 的"无 420 上限"与"标题无 style" ✓、C 的三态 content ✓、`pop` 返回三种值 ✓、`InkWell` vs `GestureDetector` 手感 ✓、`home_page._filterChips` 的"透明底+细描边"**明确不合并** ✓）
  - ⚠️ **如实**：A2 是**净增 23 行**（公用件带长注释）⇒ 真实收益是**去重**、不是省行 ✓；注释**不压短** ✓
- **A3 死代码**：12 项删净 ✓（`variantInfoOf`/`btnText`/`_labelOf`/`replaceWith`/`bvApplied`/`KpPlayer.setVolume`/`KpState.volume`/`SiteFetcher.base`/`portraitStarCards`/`hasStarFilterRow`/`SiteKind.web`/`Api.hosts`/`PlayHistory.flush`/`source_cache` 冗余 import ✓）；`_phBadHosts` 存 `DateTime`（"改"非"删"）**按判断跳过** ✓
  - ⚠️ 中途一次**半截状态**（基类 getter 删了、两个子类 `@override` 还在 ⇒ 会编译报错 ✗）已**优先补删**修好 ✓
- **B1 短片永久转圈** → 看得见的错误行 + ↻ 重试（复用本页 `_RoundBtn` ✓）+ 失败时**停掉空转的圈** ✓（邻页封面转圈不受影响 ✓）
- **B2 两处外部回调没超时** → 照同文件既有写法补 **6 秒 `.timeout`** ✓（超时落"这一集已失效/视频加载失败" ✓）
- **B3 详情页**：选集**两页并发**（`Future.wait` ✓ 顺序/错误语义等价 ✓）· **出错不再置 `_done`** ✓ · 尾部"没有更多了"→ **可点"加载失败，点击重试"** ✓ · 空列表失败那条分支也补可点重试 ✓
- **B4 缓存目录反复全扫** → 两处缓存件加"**已在跑就跳过 + 5 秒节流**"薄包装 ✓（**调用点未动** = 覆盖所有入口 ✓）
- **B5 WebView 重试弹回入口页** → `loadRequest(widget.url)` ⇒ **`_ctl.reload()`** ✓（初次加载那处未动 ✓）
- **B6 日志页整篇排版** → 超 **200K 字符**只渲染**末尾一段**（落点**紧跟换行、不劈半行** ✓）+ "仅显示最近部分"提示（固定在滚动区之上 ✓）；**「复制全部」仍是全文** ✓
- **B7**：`bvPrime()` 两个 `await` 之后补 `mounted` 判断 ✓
- **B8**：三条候选**验或否** —— ①两处 LRU **不建议合并**（video 侧语义交错：目录形态、`.m3u8↔.hls` 配对求和、API 也不同 ⇒ 抽象更贵 ✓）②两处确认框**已合并**（`confirmClear`，净约 −16 行 ✓）③`_filterChips` ↔ `tagChip` **明确不合并**（视觉/绑定/数据三处都不同 ✓）

### 三、⚠️ 全部改动**只过了静态检查**、**一次都没编译过**
- 本机无 Flutter/Dart ⇒ 每处只有这四道闸：**唯一锚点（锚点一律从文件取、不手抄）** + **括号逐类等式**（`改后 = 改前 − 删行 + 新加行`，含"被删/新增块自身量"）+ **行尾保持（逐文件测原有 CRLF/LF）** + **零残留 grep** ✓
- ⇒ **第一次编译就是 CI** ✗（可能有 analyze 错，出了按原文修 ✓）
- 过程中两次**真事故**（都是脚手架脚本问题，**文件零损坏** ✗）：一次性脚本**非幂等**被跑两次 ⇒ 状态类被复制 4 份（已 `git checkout` 恢复 ✓）；另几次"手抄锚点"未匹配 ⇒ **都停在写盘之前** ✓（守卫有效 ✓）

### 四、已知边界（本轮查出、**未做** ✓）
- 短片页 `_items` 空着进页面这条路仍无提示（**改前就有** ✗ 非本轮引入）
- "站点成功返回空表"会被 `SourceCache` 缓存住 ⇒ 重试只是再拿到同一空结果（**不动共享缓存** ✓）
- B5 的 `reload()` 在"错误态期间平台 WebView 不在 widget 树上"时**可能空操作** 🔍[推断，只能真机验 ✓ 已按"先不加兜底"处理 ✓]

### 五、状态
- 逐文件 numstat（本轮）：`sites/xhamsterlive.dart` **65/1095** · `base/site_ui.dart` **97/2** · `sites/hanime1.dart` 25/45 · `sites/pornhub.dart` 8/25 · `home_page.dart` 14/23 · `base/image_cache.dart` 18/0 · `base/video_cache.dart` 18/0 · `player_widget.dart` 18/15 · `error_log_page.dart` 19/23(+58/28) · `play_history_page.dart` 5/17 · `detail_page.dart` 45/4 · `shorts_feed_page.dart` 64/11 · `web_embed.dart` 5/1 · 另有 6 个文件各 0/1~4
- `sim/**` 未提交（按惯例只提交 `lib` + `pubspec.yaml` + `DEVLOG.md` ✓）；**顺序依赖**：**App 侧筛选删净 + 真机验证通过后 → 清 sim 的 `MOBILE_FILTERS` / `LIVE_TAG_MAP` 及其 `liveTagOf()/liveSlug()`** ✓（现留在 sim 里当路标 ✓）
- 清理：`%TEMP%` 与工作区临时文件**均为 0** ✓（两路各自实测 ✓）

---
## 追加（2026-10-05 · **1.0.37 构建修复 #1**）`flutter analyze` 10 error —— 全是"跨文件引用的收尾没做全"

- **失败原文**（run `37233563081`，挂在 `代码检查 (flutter analyze)`，耗时 1 分 45 秒，其后 5 步 skipped、无产物）
- **10 error 逐类**：
  1. `lib/base/site_ui.dart:52:1` 与 `:53:1` ⇒ `directive_after_declaration`（**import 写在顶层函数声明之后** ✗）
  2. `lib/error_log_page.dart:73:19` ⇒ `undefined_identifier`（`AppBg` 未定义：**缺 `app_bg.dart` 导入** ✗ —— 注意 `AppBg` 类是 `app_bg.dart` 里的，`app_background.dart` 只是它的使用者之一 ✓ 别搞混）
  3. `lib/home_page.dart` **7 处** `undefined_method`（调用 `siteFilterBtn` 但**缺 `import 'base/site_ui.dart';`** ✗）：`280:15 / 285:17 / 300:25 / 383:17 / 401:19 / 418:19 / 512:25`
- **顺带清掉（不拦构建）**：3 条 `unused_import`（`hanime1.dart:17` / `pornhub.dart:18` 的 `app_background`——**A2 删掉两份筛选按钮副本后 `kChipBorder` 就没人用了**、`xhamsterlive.dart:48` 的 `player_widget`——直播页改用 AVPlayer 后 `KpPlayer` 只剩注释里）；2 条 `prefer_const_constructors`（`error_log_page.dart` 两处 `EdgeInsets` 加 `const` ✓；**外层 `Padding` 不加** —— 内含运行期 getter `kTxtSub`，避开上轮的 `invalid_constant`）
- **教训（已入规矩）**：① **删代码块 = 顺手查 import 是否悬空**（A2 留下的尾巴就是证据 ✓）② **跨文件引用公用件 = import 必须在同一个原子步** ③ 锚点一律**从文件取**（不手抄）④ 注释里**不写裸括号**（会污染计数口径）
- **状态**：修复只经静态复核（锚点 + 括号逐类等式 + 行尾保持 + 零残留 grep）；**能否过 analyze 由 CI 二次确认**

---
## 追加（2026-10-05 · **App 侧 1.0.38**）直播房间页：**左滑返回/单击迟钝的真因 + X 位置与图标**

### 一、真因（用户报"单击显隐 + 左滑返回反应迟钝"，先查因后改 ✓）
| 怀疑 | 结论 | 依据（`lib/sites/xhamsterlive.dart` 原文） |
|---|---|---|
| 点击层铺满全屏、盖住左边缘 | ✅ **是元凶** | 原 `:970 body: GestureDetector(` + `behavior: HitTestBehavior.opaque` **包住整棵 Stack**（含屏幕最左 0~24px）⇒ iOS **原生侧滑返回**必须先等 Flutter 手势竞技场判负 ⇒ **左滑迟钝** |
| 同时挂了 doubleTap / longPress | ❌ 否 | 全文件 `onDoubleTap`/`onLongPress` **各 0 处**；只有 `:973` 一个 `onTap` ⇒ 单击**不会**等双击超时 |
| toggle 用 `setState` 重建整页 | ✅ **是次要嫌疑** | `:973 setState(() => _showX = !_showX)` ⇒ 每次点击重建**整棵子树**（含播放器外那层）；`_c` 未变不会重初始化，但整层 widget 重建 ⇒ 体感"发卡" |
| 播放器层是平台视图吞触摸 | ❓ 未验（不必查 ✓ 上面已能解释） | 仓库侧只见 `:983 child: VideoPlayer(_c!)` |
| 还有别的全屏手势层 | ❌ 否 | `GestureDetector/RawGestureDetector/IgnorePointer/AbsorbPointer` 全文件只有那一处 |

### 二、改法（三项 ✓）
1. **让出左边缘 24px**：点击层从"包住 Stack"⇒ 改为 **Stack 里单独一层** `Positioned.fill(left: 24, child: GestureDetector(behavior: opaque, child: SizedBox.expand()))`（放第一个子层，X 层在其上 ⇒ X 自己的 `InkWell` 仍先命中 ✓）
   - ⚠️ **已知取舍**：屏幕**最左 24px 内点屏幕不再显隐 X** ✓（让给原生侧滑 ✓）
2. **只重建 X 那一小块**：`bool _showX` ⇒ **`ValueNotifier<bool> _showX`**（+ `dispose()` 里补 `_showX.dispose()` ✓）+ X 层用 `ValueListenableBuilder<bool>` ⇒ 实测 `git grep "setState(() => _showX"` = **空** ✓（播放器层不再被它包住 ✓）
3. **X 位置与大小**（用户逐次点名 ✓）：左边距 **12 → 8 → 5px**（`EdgeInsets.fromLTRB(5, 12, 12, 12)` ✓ 只动左边 ✓ 上/右/下 12 保持 ✓ 垂直位置与 `SafeArea` 一字未动 ✓）· 图标 **40 → 32** ✓ · 图标在 76 方块里改为**左对齐 + 垂直居中** ✓（否则 76 的内边距会把"5px"吃掉 ✗）· **命中区 76×76 未动** ✓
   - ⚠️ 如实标注 🔍：`Icons.close` 字形**自带几 px 内边距** ⇒ 视觉左距 ≈ 5px + 该内边距 ✓（真机嫌远给个数再调 ✓ **垂直不动** ✓）


---
## 追加（2026-10-05 · **1.0.38 事故修复 + 全量复查**，随 1.0.39 出包）

### 一、1.0.38 真机事故：**有声音、没画面** ✗（我造成的 ✓ 已定位已修）
**机理（逐行对照两版 + Flutter 的 Stack 尺寸规则）**：
- 旧版 X 层是 `if (_showX) → SafeArea(...)` ⇒ 隐藏时**那一层根本不存在** ⇒ Stack 里只剩"定位型"子层 ⇒ **Stack 撑满父约束** ⇒ 画面层 `Positioned.fill` 有东西可填 ⇒ 有画面 ✓
- 1.0.38 换成 `ValueListenableBuilder`（**非定位型**子层 ✓ 永远存在 ✓）且隐藏时返回 **0×0 的 `SizedBox.shrink()`** ✗ ⇒ **Stack 把自己缩成 0×0** ✗ ⇒ `Positioned.fill` 填了 0×0 ⇒ **画面不可见**；声音照旧（控制器活着）✓ —— 与用户现象完全一致 ✓
- **修法**：把 X 层**position 化**（包一层 `Positioned.fill` ✓）⇒ 不再参与 Stack 尺寸 ✓ 同时**保住**"点 X 只刷那一小块"的收益 ✓
- **新门禁（已入规矩）**：凡动 `Stack`，**必须逐个列出"非定位（非 Positioned）子层"，改前改后必须一致** ✗（这次就是漏了这条）


### 三、全量复查（**两轮、两路独立**：`app-dev` + 独立只读审计员；第二轮按用户"只报实测"的死命令重跑）
**修掉的**
- **功能缺口（1 个，实锤）**：`lib/sites/xhamsterlive.dart` 删筛选行时留下的**早退** `if (!widget.feed.tab.hasFilterRow) return body;` ⇒ `RefreshIndicator` 只覆盖"移动流/手机版最新" ⇒ **4 个主分类 tab 没有下拉刷新** ✗ ⇒ 删早退 ⇒ **6/6 个 tab 都能下拉刷新** ✓
- **真死代码 2 处**：0 调用的 `bool get hasMobileFilters`（直播页面）· 0 调用的 `XhStarController.toggle`（xvideos 侧无需 ✓）
- **死注释 / 悬空文档 13 处**：删筛选后残留的说明文字、提到已删符号名的注释、两段自相矛盾注释（写"故意不 import flutter"而实际 import 了 ✓）、孤儿文档（函数已删、说明还在 ✓）等 —— **逐处打印改前/改后** ✓
- **我自己制造的多余改动 3 处**（复查抓出 ✓）：`app_background` import 被挪位 ✗ / `xhamster.dart` 一条孤儿文档 ✗ / 一个空行偏移 ✗ ⇒ 全部消除 ⇒ **7 个文件的 diff 只剩预期 hunk** ✓（`xhamsterlive.dart` 的 11 条 hunk 逐条列出、无任何 import/空行相关 ✓）

**"无法核实"的（照新规矩写明，不填推断 ✓）**
- **未用 import / 能否编译**：技术障碍 = 本机无 Flutter/Dart SDK ⇒ **权威结论只能来自 CI 的 `flutter analyze`** ✓（复查过程中一版自造符号清单**判错过**：漏了 `Color get kTxt => …` 这种 getter 形式 ⇒ 误删 5 条 import ⇒ **已全部恢复**、其中 2 个文件用 `git checkout` 回到基线 ✓ 新规矩：**未用 import 只认 analyze** ✓）
- **真机行为**：无真机 ⇒ 只能证"代码路径存在"（🔍）✓ 不给"功能正常"结论 ✓

### 四、状态与门禁
- 全量 numstat（7 个文件）＝ `base/fetch.dart 2/2` · `base/site_ui.dart 3/6` · `sites.dart 0/1` · `sites/pornhub.dart 0/3` · `sites/xhamster.dart 1/12` · `sites/xhamsterlive.dart 11/49` · `sites/xvideos.dart 0/4` ✓
- 门禁（每个改动文件）：**括号栈扫描**（mismatch 空 / 剩余未闭合 0 ✓ · 不是只看总数 ✗ 本轮吃过大亏 ✓）+ **增量等式**（`改后 = 改前 − 删块自身 + 新块自身` ✓）+ **行尾逐文件实测**（CRLF/LF 各自原样 ✓ 无一混行 ✓）+ **词边界零残留 grep** ✓
- **未编译**（本机无 SDK ✓）⇒ 第一次编译仍是 CI ✓；`%TEMP%` 与根目录临时文件 **0 残留** ✓

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

---

## 十二、2026-10-05 · 在线图集**转场叠影**修复（1.0.58）+ 一段代价很大的教训

### 现象（用户实测 ✓）
进**在线图集详情**时，转场那一下**旧页面"卡一半"、两页叠影** ☠（设置页/播放记录页那种"文字与进度条双影、像卡半秒+闪一下"）

### 根因（有提交原文 ✅）
`ac1d1b2`（2026-10-01 14:07）为了让**背景图透出来**，把**全 App 的 Scaffold / 页面底色改成透明** ☠
⇒ push 新页面时**新页面盖不住旧页面** ⇒ 转场期间两页同时可见 ⇒ 叠影。
**当年已用同一根因修过一次**：`365d6a4`（2026-10-01 15:23）"修转场重影"——
触发 = **用户截图**（设置页与播放记录页文字/进度条全部双影 ✓）；
做法 = 新增 **`PageBg`**（在页面**最底层**铺一层不透明背景图 ⇒ 转场时"实心"能挡住旧页 ✓）；当时包住 **15 处 push**；
验收原文（当时）：**"上机实测通过，用户：可算是修复好了"** ✓

### 本次修复（`019c97a` = **1.0.58**）
两个在线图集的**详情路由各包一层 `PageBg`** ✓（写法与 `365d6a4` 完全一致 ✓）：
- `lib/online_album_page.dart:460` —— 图集1 卡片 ⇒ 详情 ✓
- `lib/online_album2_page.dart:425` —— 图集2 卡片 ⇒ 详情 ✓

改动面：**只这 2 个文件**，`8 insertions / 3 deletions` ✓（只加一层包装 ✗ 转场类型/路由参数/页面内容一律没碰 ✓）
**用户验收（2026-10-05）**：**"对，就是这个问题。完美修复了"** ✅

### 附带结论（清点 ✓）
全 `lib/` 共 **24 处 `MaterialPageRoute(`** ⇒ 除本次这 2 处外，其余 **22 处本来都已包 `PageBg`** ✓
⇒ 现在**唯一仍未包**的是 `lib/sites/xhamsterlive.dart:615`（进直播间那处 ✓）——
　**用户明确说这次不管它** ✓（**只作记录，不改** ✗；`lib/sites/**` 本次一个字没动 ✓）

### ⚠️ 同期重要教训（务必记住 ✗）
**1.0.55 / 1.0.56 那批"内存/加载修复"**（40MB+LRU 解码缓存 / 离页清本 / 预览预取 / 预热延后 400ms 且只预热 12 张 /
尺寸表换 provider）⇒ **引入了"反复进出图集就闪退"** ☠（无日志 ✓ 典型被系统杀）
⇒ 已在 **1.0.57 全部回滚** ✓（= 回到 1.0.54 基线 + 只重做两件：**框选方案 A** ✓、**左右滑 18px + 快扫** ✓）
⇒ 回滚后用户实测：**"现在好像真不闪退了"** ✅
⇒ **那批改动不要再原样往回加** ☠ —— 要加**就单独加、单独验** ✓

### 流程教训
以后**一包一个改动、一次一个结论** ✓ —— 不要一包塞一堆猜测 ☠（这次就是"打错靶子"两轮，代价很大）

---

## 十三、2026-10-05 · **项目铁律：严禁未经核查修改，禁止捏造数据**（用户原话，逐字引用 ✓）

> 「**严禁未经核查修改，禁止捏造数据。修改必须先实地核查完再改。**」

### 执行方式（每条都可核 ✓）
- **改任何一行前，先读那一行原文** ✓；凡涉及**名字 / 键名 / 字段名 / 类型名 / 方法名**，
  必须带 **`文件:行号` 出处** ✓（例：本节的 `_P18Item` ⇒ `online_album2_page.dart:49` ✓）。
- **查不到就如实写"未查到"或跳过** ✗ —— **绝不猜** ✗ **绝不编造行号 / 计数 / 日志** ✗。
- 报告须贴**实测输出**（`grep` 命中数 ✓ 行号 ✓ 括号 Δ ✓ 行尾实测 ✓）；**出现矛盾就报矛盾** ✓ 不许圆场 ✗。

### 反例记账（本轮真实发生 ✓）
- **`P18Item`**：这是**推断**出来的类型名 ✗（我没读到定义就写进代码）⇒ 实地 `grep` 出真名是 **`_P18Item`**
  （出处：`lib/online_album2_page.dart:49` ✓）⇒ **差一步就把编译错误带进包里** ☠。
- 同批还有一次自查抓到的真 bug：播放层失败分支里把 `$e` 写成了**字符串字面量**再取子串 ⇒ **会越界** ☠
  （已按"先 `final es = '$e';` 再按 120 截"修正 ✓，见 `lib/player_widget.dart` 的 `[PLAY] 起播失败` 那处 ✓）。
⇒ 结论：**先核查、再动手；名字必须有出处；查不到就写"未查到"** ✓ —— 这条高于"赶进度" ✗。

---

## 十四、2026-10-05 · **回答前必须先核查**（用户原话，逐字引用 ✓）

> 「**回答之前请先核查代码或者需要联网查找。再回答我。要有事实依据。**」

### 执行方式
- 凡涉及**事实 / 数值 / 字段 / 行为**的回答 ⇒ **先核查**（读代码 ✓ `git grep` 出**行号出处** ✓ 或联网查证 ✓）**再答** ✓。
- **不许凭记忆、凭注释、凭推断当事实** ✗ —— **注释会过期**（反例见下 ✓）。
- 查不到 ⇒ **如实写「未核实 / 查不到」** ✗ 或反问 ✓ —— **不许猜** ✗。

### 反例记账（实锤 ✓ 队长本人踩的）
- 队长答「日志上限保留 **256KB**」✗ —— 依据是 `lib/site_error_log.dart:92` 的**过期注释**（那句"保留末尾 256KB"✓ 是旧值 ✗）。
- **实地核查后的真相**（本次已复核 ✓）：
  · `lib/site_error_log.dart:24` `static const int maxBytes = 5 * 1024 * 1024;` ⇒ **上限 5MB** ✓
  · `lib/site_error_log.dart:27` `static const int keepBytes = maxBytes ~/ 2;` ⇒ **超限保留末尾 ≈2.5MB** ✓
  · （`:23` 注释也印证"原是 512 KB ✗"的沿革 ✓）
- **教训**：**引用了注释、没看常量** ⇒ 答前必须先核查 ✓；`site_error_log.dart:92` 那句注释**已过期** ⚠️
  （**修正它要等用户点头** ✗ —— 本次只记账，不动代码 ✓）。
  ✅ **本批已订正**（见下一节 ✓）：`git show HEAD:lib/site_error_log.dart` 实测"256KB"出现在 **`:44` / `:61` / `:92`** 三处 ✓ ⇒ 十四 引用的 `:92` **没错** ✓。

---

## 十五、2026-10-06 · **1.1.5（未构建）** · 全量诊断日志补齐 + 三项修复

> 用户口径：「**那就把没加的都加上。争取完美**」+「必须核查，修改要有事实依据，不许胡编乱造」。

### 一、本批性质与规模（**只加打印，不改逻辑** ✓）
`+` 侧含 `debugPrint` 的行共 **133** 行 ✓（`git diff --ignore-cr-at-eol -U0 | Select-String '^\+.*debugPrint\('` 实测 ✓）；
其中 **39 行**是给**既有**打印补 `if (AppSettings.i.logConsole)` 守卫 ✓（不是新打点 ✗）。
逐文件（新增含打印行数 ✓）：`base/video_cache.dart 22` · `sites/xhamsterlive.dart 15` · `player_widget.dart 14` ·
`sites/porna.dart 10` · `fetched_image.dart 7` · `settings_page.dart 7` · `api.dart 6` · `shorts_feed_page.dart 6` ·
`base/fetch.dart 5` · `detail_page.dart 5` · `sites/huangguo.dart 5` · `sites/madou.dart 5` · `online_album2_avif.dart 4` ·
`web_embed.dart 4` · `home_page.dart 2` · `sites/hanime1|kmsvip|pektino|wordpress|xhamster|xvideos` **各 2** ·
`base/image_cache.dart` · `play_history_page.dart` · `sites/pornhub.dart` · `web_page.dart` **各 1**

**新补的链路**（原来 0 条日志的都在本批补上 ✓）：清单层（`api.dart` 6 处：category/home/tag/search/detail/取源）·
首页续拉与搜索 · 详情页（载入/刷新源/预取/选集/列表翻页）· 短片（取源/打开/取不到源/预热/续拉/续拉失败）·
视频磁盘缓存（清理/窗口/下载完成·失败）· 内嵌网页（加载开始/完成/失败/注入保底 JS/控制器创建）·
**9 个站点文件的解析层**（`[LIST]`/`[DETAIL]`/`[SRC]`；站点名统一取 `_f.site.name` ✓ —— 依据 `base/fetch.dart:26/30`、`sites.dart:129/137` ✓）

### 二、三项**真实行为改动**（不是打印 —— 逐条已被只读审计确认 ✓）
1. `lib/error_log_page.dart:33`：`_maxRender` **200K → 500K 字符** ✓（只影响日志页渲染末尾多少字符 ✗ 不影响文件上限/复制 ✓）
2. `lib/online_album2_page.dart:250`：排序行 padding 补 **`bottom: 3`** ✓（修"标签行与卡片贴脸"；top/left/right 与 chip 间距 8 未动 ✓）
3. **路由起名 `RouteSettings(name:)` 共 21 处** ✓：`home_page 7` · `detail_page 5` · `settings_page 4` · `main.dart 2` ·
   `online_album_page 1` · `online_album2_page 1` · `sites/xhamsterlive 1` —— 只喂 `main.dart` 的 `[NAV]` 轨迹 ✓，不参与路由匹配 ✓
4. `lib/site_error_log.dart` 三处过期注释订正 ✓（HEAD `:44/:61/:92` 的"256KB" → `keepBytes` ≈2.5MB ✓ 见 `:24`/`:27`）；
   `lib/main.dart` 同款注释订正 ✓
5. `lib/base/image_cache.dart:5` 补 `import 'package:flutter/foundation.dart' show debugPrint;` ✓
   —— **这是硬伤**：该文件原先只有 `dart:convert/dart:io/dart:typed_data/path_provider` ✗ ⇒ `debugPrint` 无定义 ⇒ **analyze 必挂** ☠

### 三、核查与验收（全部只读、三轮 ✓）
- `base/video_cache.dart` 的 **−16 行逐条对账** ✓：13 条"单行 `if` 展开成块体"（条件表达式一字未改 ✓）、3 条 `catch (_)`→`catch (e)`（只为打印 `$e`；捕获范围/吞异常/无 rethrow 全部照旧 ✓）；`_prune()` 调用点 HEAD `81/206/396/228` → 现 `93/234/476/259` **一一对应** ✓
- 守卫批 **字符串级比对** ✓：剥掉守卫前缀后与 `-` 侧逐字符相同（`xhamsterlive` 10/10 ✓ `player_widget` 3/3 ✓ `settings_page` 6/6 ✓ …）
- `player_widget.dart:435` 的 `if (AppSettings.i.logConsole && name == 'hwdec')` 合并 **语义等价** ✓（原条件仍在 ✓；块体只有一条打印 ✓；`plat.setProperty(...)` 位置未动 ✓）
- 全仓 **27 处 `settings.dart` 引用严格二分** ✓：`lib/` 直下 `'settings.dart'` **13 处** / `lib/base|sites/` 下 `'../settings.dart'` **14 处**
- 括号配平：全部改动文件与 HEAD **余额一致** ✓（`sites/pornhub.dart` 的差是 **HEAD 既有** ✗ 不是本批 ✓）
- 仓库根**无 `analysis_options.yaml`** ⇒ `pubspec.yaml:69` 的 `flutter_lints: ^4.0.0` **实际未启用** ✅ ⇒ 本项目 lint 不拦 CI ✓（**只有 error 拦** ✓）

### 四、已知遗留（**本批故意不动** ✗，等用户定夺 ✓）
1. **13 处既有打印仍未守卫**：`app_bg.dart` 5 · `main.dart:60/65` · `online_album_common.dart` 6 ·
   `online_album_page.dart:384` · `online_album2_page.dart:363` · `settings_page.dart:384` —— 它们**不是本批新增** ✓，
   行为上仍被 `main.dart:30-31` 的全局接管兜住 ✓；按"只改必要部分"**不扩大范围** ✓
2. **4 个站文件 numstat 虚高** ⚠️：`sites/hanime1|xvideos|madou|pektino` 的索引条目是 **`i/-text`** 而 blob 是 **CRLF** ✓
   （字节级取证 ✓：`hanime1` blob 21376B CR=537/LF=536 ✓；对照 `porna` blob 31243B CR=0 ✓）
   ⇒ `core.autocrlf=true` 只归一化**工作区**侧 ⇒ 本地 `git diff` 逐字节比、**整篇算改动** ☠。
   ✅ `app-dev` 实验证明：**把工作区改成 LF 也改不动 numstat** ✗（548/536 一点没变 ✓）
   ⇒ **治本**要 `.gitattributes`（`*.dart text eol=lf`）+ `git add --renormalize`（= 一次整篇行尾提交 ☠）——
   **用户未拍板 ⇒ 本批无改动**（现状）；**对账口径改用 `git diff --ignore-cr-at-eol --numstat`** ✓
3. **sim 与 App 一处数值不同步**（只登记 ✗ 用户说过 sim 不管 ✓）：`sim/index.html:255` 的 `#alb2Sorts` 仍 `padding: 8px 2px 0` ✓，App 侧 `online_album2_page.dart:250` 已是 `top6 + bottom3` ✓

### 五、教训（本批真实发生 ✓）
- **拿推断当事实又踩一次** ☠：我按字节差**推断**"HEAD 是 LF"，被 `app-dev` 的实验推翻 ✗；
  改用**字节级取证**（`cmd /c "git cat-file blob HEAD:<f> > 临时文件"` 再数 CR ✓，绕开 PowerShell 的文本转换 ✓）才定论 ✓。
  ⇒ 复核"行尾/字节"这类事：**必须量原始字节，不许靠管道后的字符串判断** ✓。
- **队员本身是子代理** ✓：`subagent depth 2 exceeds maxDepth 1` ⇒ **队员无法再派子代理** ✗；
  要一次性子代理只能 **Lead 自己拍** ✓（或派给职责对口的 `app-dev` ✓）。
- **专项队员别当通用工用** ☠：让只读侦察/模拟器/构建的队员去改码，既越界又耗它们的额度 ⇒ 派活要**按职责书** ✓。

### 六、1.1.5 首次构建：**CI 挂在 analyze → 已修**（2026-10-06 ✓）
- run **`37450933352`**（headSha `4a55eca`，33 文件 `+2393/−1729`）失败在**「代码检查 (flutter analyze)」**⇒ 后面 `Flutter build IPA` / `上传 IPA 产物` / `发布到 Releases` **全 skipped** ⇒ **无 ipa、桌面未动** ✓
- **唯一 error（原文）**：`A value of type 'List<dynamic>' can't be returned from the method 'category' because it has a return type of 'Future<List<Article>>' • lib/sites/madou.dart:102:14 • return_of_invalid_type`
  - ⚠️ **日志里行号被 secret-masking 打成 `***`**（GitHub 把 `1` 抹成星号 ✓ 实测 `***02:***4` = `102:14` ✓）⇒ 靠"日志顺序 + 本地源码语义"两条证据解出 ✓
- **根因**：本批把 `madou.dart` 的 `return page > 1 ? const [] : cards(…)` 拆成 `final _r = …; 打印; return _r;` ⇒ **表达式脱离了返回上下文** ⇒ 裸 `const []` 被定成 `List<dynamic>`，与 `cards(...)` 的 `List<Article>` 取 LUB ⇒ `_r` 变 `List<dynamic>` ☠
- **修**（净 **3 ↔ 3** 行 ✓）：`:99` → **`const <Article>[]`** ✓；`:92`/`:107` **撤掉本批多加的外层 `await`** ✓（HEAD 是 `tags(await _f.text('/tags'))` / `cards(await _f.text(kk))` ✓ —— 外层 `await` 是本批引入的 ✗，引发 `await_only_futures` ✓）；`:86` 的 `await home!(...)` **保留** ✓（`home` 的类型是 `Future<List<Article>> Function({int page})?` ✓ 见 `site_ui.dart:111`）
- **教训**：把 `return <表达式>;` 拆成 `final x = <表达式>; return x;` ⇒ **类型推断会变** ☠ ⇒ 空集合/条件表达式这类**必须显式标类型或写 `<T>[]`** ✓；另外**别在重构时顺手加 `await`** ✗（只准加计时/打印/`final x =` ✓）
- **info 级不拦 CI** ✓：本批新增的 `no_leading_underscores_for_local_identifiers`（`_sw`/`_r`/`_del` 等局部名 ✓）与 `curly_braces_in_flow_control_structures`（单行 `if (guard) debugPrint(...)` ✓）**都不拦** ✓，且仓库里**既有**同类 info ✓（`base/fetch.dart:76-78` 的 `_qi/_dpath/_q` 在 1.1.4 就有 ✓）⇒ **不为 lint 大改** ✗
- 仓库根**无 `analysis_options.yaml`** ✓ ⇒ `flutter_lints` 未启用 ✓；上述 info 是分析器默认规则 ✓

### 七、桌面产物**命名口径**（用户 2026-10-06 明确纠正 ✓）
> 用户原话（大意）：「放桌面不放完整？？？完整的 ipa 文件名是**带版本号**的！！！这次就算了，下次记住」

⇒ **规矩（下轮起强制 ✓）**：下到桌面的文件名必须是**带版本号的完整名** ⇒ `C:\Users\Administrator\Desktop\kpxx-<版本>.ipa`
（例：本版应是 **`kpxx-1.1.5.ipa`** ✓ —— 与 artifact 内部的文件名同款 ✓ 见 `ios.yml` 的 `按版本号重命名 IPA` 那步 ✓）。
- ⚠️ **旧写法 `kpxx.ipa`（无版本号）算错** ✗ —— 本节 91 行那条已在 2026-10-06 改掉 ✓。
- ✅ 本轮实测：artifact 内文件名就是 `kpxx-1.1.5.ipa` ✓（16,512,150 B ✓），但被我下成了 `kpxx.ipa` ✗
  ⇒ 用户说"**这次就算了**" ✓ ⇒ **本轮不重建/不改名** ✓，**下轮构建起照新口径** ✓。

### 八、报错日志的现状与**用户决定（2026-10-06）**：**先维持现状，不搬** ✓

**用户口径（逐字要点 ✓）**：「**日常报错需要记录错误日志，全量记录的是等控制台日志按钮打开才记录**」⇒ 本来要按此把 18 处报错搬到 `SiteErrorLog` ✓；
但用户当日最终决定：**「先这样吧。回头有问题再改。」** ⇒ **本批不做搬运** ✓（改动前先停下，等将来有需要再派 ✓）。

**现状（已核实 ✓）——真正"永远记录"的只有 3 类 5 个点**：
| 位置 | 记什么 |
|---|---|
| `lib/main.dart:41` | 未捕获的**界面异常**（`FlutterError` ✓） |
| `lib/main.dart:44` | 未捕获的**异步异常**（`PlatformDispatcher` ✓） |
| `lib/base/fetch.dart:90 / :120 / :175` | **站点取数失败**（超时 / HTTP 异常 / 解析异常 ✓，标签 = 站名 ⇒ 13 站共用 ✓） |
（`lib/main.dart:33` 那条**不是报错** ✗ —— 它是"开关打开时把全量 `debugPrint` 写进日志页"的通路（标签 `console` ✓）。

**其余 25 处"内容是失败/报错"的打印 ⇒ 全走 `debugPrint` ⇒ 开关关着时一条都不留** ⚠️（图片取数、图集取图、起播失败、错误流、视频缓存下载失败、短片取不到源、网页加载失败、直播断流、背景图失败、裁剪回落 ✓ 逐条行号见本次会话的 grep 结果 ✓）。

⚠️ **将来要搬时必须先限流 —— 实测有 4 处会刷**（别原样搬 ☠）：
- `lib/fetched_image.dart:235` 取数异常 ⇒ **一张图一条**（一页几十张）
- `lib/online_album2_avif.dart:70` 取图失败（第 N 次）⇒ **每张图每次重试都打**（最多 3 次）
- `lib/online_album2_avif.dart:73` 取图最终失败 ⇒ 与图数同量级
- `lib/player_widget.dart:186` 错误流 ⇒ **最容易刷** ✓：media_kit 会把 FFmpeg **偶发网络错误**也丢进这个流（同文件注释已写"此时视频往往还在正常播" ✓）
建议做法（将来参考 ✓）：**这 4 处留开关**，其余 14 处低频报错搬进 `SiteErrorLog`；全量类里那 11 处无守卫的（`app_bg:132/208/302`、`main:60/65`、`online_album_common:301/577/618/654`、两个图集页的 `diag()`）补守卫 ✓。

---

## 十六、2026-10-06 · **1.1.6：Flutter 3.27.4 → 3.47.6（长期欠账，本批补上）** ☠→✓

### 一、为什么要升（用户当场点破 ✓）
用户原话（大意 ✓）：「**我早就跟你说过了吧，Flutter 让你升最新版你不升。非说现在能用就够了**」——
✅ **他说得对**：当初我以"现在能跑、不折腾"为由没升，结果**卡死了直播间首帧优化的正主** ✓：
`video_player` **2.10.1** 才修掉"HLS 直播要等 `duration != 0` 才算 initialized"这条（改为 `AVPlayerItem.status == readyToPlay` 即发 ✓），
而 **2.10.1 要求 Flutter ≥3.29 / Dart ≥3.7** ✓，我们 CI 钉在 **3.27.4** ⇒ 吃不到 ☠（依据：recon 引官方 tag 源码 diff 核实 ✓）。

### 二、本批改了什么（**只动版本号，别的等 CI 报** ✓）
| 文件 | 改动 |
|---|---|
| `.github/workflows/ios.yml:25` | `flutter-version: '3.27.4'` → **`'3.47.6'`** ✓ |
| `pubspec.yaml:33` | `video_player: 2.10.0` → **`2.10.1`** ✓ |
| `lib/app_version.dart:13` | `1.1.5` → **`1.1.6`** ✓ |
| `lib/settings_page.dart:372` | 标题字色 → **`kTxt`**（黑白自适应 ✓ 用户点名要的；见下条 ✓） |

### 三、版本口径（**已核实** ✓）
**Flutter 3.47.6 = 官方渠道最新 stable** ✓：`releases_windows.json` 的 stable 列表首条 `3.47.6`、**Dart 3.13.5**、`2026-10-01T19:02:49Z` ✓
（往下依次 3.47.5 / 3.47.4 / 3.47.3 ✓）。`pubspec.yaml:7` 的 `sdk: '>=3.3.0 <4.0.0'` 仍覆盖 Dart 3.13.5 ⇒ **不用改** ✓。

### 四、顺带进包的两处（用户要求 ✓）
1. **`settings_page.dart:372` 字色自适应** ✓：「记录控制台日志（调试用）」的 `title` 由**无颜色**（跟主题）改为 **`color: kTxt`** ✓
   —— 并**去掉 `const`** ✓（`kTxt` 是运行时 getter ✓ 见 `lib/app_background.dart:53` ✓；这是本项目踩过的坑 ✓）；
   口径与本页同类标题一致 ✓（`:451 _row` / `:421 _head` 都是 `color: kTxt` ✓）；本页已监听 `AppBg.i` ✓（`:40-43`）⇒ 明暗翻转会自动重绘 ✓。
2. 行尾/报错日志那两条**只记账未改** ✓（见本节八、九 ✓）。

### 五、升级的已知风险（**预判，等 CI 报原文再逐条修** ✓）
- `runs-on: macos-14`（`ios.yml:15`）与 Xcode 版本是否够（3.47 可能要求更新的 Xcode）❓
- iOS 部署目标现为 **13.0**（`ios.yml:84-85` 改写 + `:93/:95` Podfile）❓
- 各插件与**本地插件 `kp_avif`**（`plugins/kp_avif` ✓）的兼容性 ❓
- Dart 3.6 → 3.13.5 期间**被移除的 API 会 error** ✓（warning/info 不拦 ✓ 见 `ios.yml:152-155` 的 `--no-fatal-infos --no-fatal-warnings` ✓）
- 流程：**推一轮 → 抄 CI 失败原文 → 逐条修 → 再推**，直到全绿 ✓（用户已授权"滚到跑通" ✓）。

### 六、教训（本轮真实发生 ✓）
**"现在能跑"不是理由 ⇒ 版本欠账要在"还没卡住"时就还** ☠ —— 这次代价是：一个能省好几秒的播放器修复，被压了整整一个 Flutter 大版本周期 ✓。
⇒ 今后遇到"升级 vs 不折腾"的取舍，**把"将来会被什么卡住"先写出来**再决定 ✓，别只算眼前 ✓。

---

## 十七、2026-10-06 · **1.1.7（待构建）** · 全量日志补齐 + 日常错误取消 + 错误日志导出

> 用户口径（要点 ✓）：「**全量就是让你任何一步都要输出**」「**所有站点都需要**」「**全量输出就是要日志完整，这样才好分析**」；
> 以及「**日常错误输出压根就不需要了**，有错误直接开控制台日志按钮再去查」✓。

### 一、全量打印落地（**只加打印，不动逻辑** ✓）
- **规模**：`+` 侧含 `debugPrint` 的行 **96** 行 ✓；改动 **24** 个文件（其中站点文件 **11** 个 ✓）；全仓现有 `debugPrint` **236** 处 ✓、`logConsole` 守卫 **256** 处 ✓（实测 ✓）。
- **覆盖（按用户动作顺序 ✓）**：站点**入口三件套**（`home`/`tag`/`search` —— 14 个站，`wordpress` 一类 = 5 站共用 ✓）·
  **Pornhub 整站**（列表 + 详情，此前全站仅"换域名复核"一处有输出 ✓）· **中间网络步骤**（91porna 签名换源三段 + 3 子解析器 / madou 分享页 token / kmsvip 加密 API / xHamster 短片 JSON / 黄果 `pageList`·`postDetail` / 51系 `_dplayerSources` / xvideos `profileVideos` / hanime1 `hanimeTags` ✓）·
  **图片四路径**（命内存 / 命磁盘 / 走网络 / 预热 ✓）· **播放器**（播放/暂停/seek/seekExact + 起播/首帧/缓冲/结束/错误流/换源/重试 ✓）·
  **直播真首帧**（`_sinceEnter` 计时 + `_cacheConfirmed` 首帧打点 ✓）· **图集1/2**（翻页/详情/进框选 ✓）· **列表**（首屏/翻页/下拉/上拉 + 切筛选/切子分类 ✓）·
  **设置页**（7 开关 + 4 入口 ✓）· **启动 5 点**（`[BOOT]` ✓ ⚠️ 前 3 条是**接管后补打** —— 只有开关上次就开着才看得到 ✓）·
  **导航**（全仓 23 处路由 **100% 起名** ✓ 补上 `play_history_page.dart` 那处 ✓）· **详情页剧照查看器** ✓。
- **分支级**（第二轮，`recon` 盘出 18 条后按需取 ✓）：给**既有行加字段**（不新增行 ⇒ 零额外刷屏 ✓）——
  `pornhub._phList` 加 `解析器=phStarCards|phCards` ✓（条件提成局部变量 `star`，**判定与打印同源** ✓）、
  `porna.list` **5 个出口**各加 `分支=`/`解析器=`（原来 5 条文案完全相同、分不清走哪 ☠ ✓）、`huangguo.pageList` 加 `源码=json|html` ✓；
  另补两处无痕：`xhamster.specialTap`（**只在非 null 时打** ✓ 高频防刷屏）、`hanime1` 标签弹窗失败分支 ✓；
  调用点 `home_page` 的两处 `specialTap=` **先加、后按"每站单份"撤掉** ✓（与 `xhamster` 站内那条**重复** ✗）⇒ 最终口径 =
  **覆写 `specialTap` 的 3 个站各自在站内打**（`xhamster:107-119` ✓、`xvideos` ✓、`pornhub` ✓；其余 7 站走基类 `site_ui.dart:154` 的 `=> null`、恒不走特殊去向 ⇒ **无覆盖损失** ✓）。
  ⚠️ **这条回退是"先删重复、再发现另两站只有那一份"造成的** ☠（`recon` 点验时自己揪出并认了遗漏 ✓）⇒ **教训：删"重复"前，先确认每个生产者都还有别的出口** ✓。
  **16 个"纯静默解析器"有意不加** ✓（其唯一调用方已有"N 条"日志 ⇒ 加了只会刷重复行 ✓）。
- **口径**：全部 `if (AppSettings.i.logConsole) debugPrint(...)` ✓；**只打 host/path(截 80)/条数/耗时** ✓，**不打完整 URL、不打 query、不打签名串** ✓；
  站点文件**不引 material**（用 `foundation` 的 `debugPrint` ✓）；每处上方一行中文注释说明"对着什么问题看" ✓。

### 二、**取消"日常错误输出"**（用户决定 ✓）
- 删掉 **5 处**"不受开关影响、永远记录"的调用 ✓：`main.dart` 的 `SiteErrorLog.log('flutter'…)`、`PlatformDispatcher.instance.onError` **整块**（**不留 `return true`** —— 那等于静默吞异常 ☠）；
  `base/fetch.dart` 三处站点取数失败日志 ✓（连带：三个 `catch (e, st)` → `catch (_)` ✓、删掉变成未使用的 `import '../site_error_log.dart'` ✓、删 `dart:ui show PlatformDispatcher` ✓）。
- **现状**：**只剩 `console` 一类**进错误日志页 ✓（= 开关打开时的全部输出 ✓）—— 这正是用户要的 ✓。
- ⚠️ **代价（已与用户确认 ✓）**：站点取数失败、Dart 层框架报错、未捕获异步异常，**开关关着时手机上无痕** ⇒ 以后排查**先开开关再复现一次** ✓。
  （注：**"App 崩溃"不算理由** ✗ —— 真崩溃本来就没机会写日志 ✓ 用户当场点破 ✓。）

### 三、设置页两处（用户点名 ✓）
1. **顺序**：控制台日志开关挪到「错误日志」按钮**上方** ✓（`_head('诊断')` → 开关 → 按钮 → `_note` ✓）。
2. **形态**：开关由系统标准件 `SwitchListTile`（缩进 / 字号 14 / 系统默认色）换成 **与「自动播放下一集」一模一样**的 `_row` + `Switch.adaptive(activeColor: _orange)` ✓（用户："怎么不一样？改成一模一样" ✓）。
   `value`/回调**语义未变** ✓（**先 `setLogConsole(v)`、后打印**的顺序保留 ✓ —— 保证"打开那一下"这条日志能留下 ✓）；说明文案改成与新行为一致（"出错时先打开上面的开关、再复现一次" ✓）。

### 四、错误日志页「导出」按钮（**方案 A：引 `share_plus`** ✓ 用户拍板 ✓）
- 依赖：**`share_plus: '>=13.3.1 <13.4.0'`** ✓（`recon` 联网核实：要求 Flutter ≥3.38.1 / Dart ≥3.10 / iOS ≥13.0，我们 **3.47.6 / 3.13.5 / iOS 13.0** 逐条满足 ✓；`pubspec.lock` 被 gitignore ⇒ **钉上界**才稳 ✓）。
- 位置：AppBar **「复制全部」与「清空」之间** ✓；空日志**置灰** ✓。
- 行为：`SiteErrorLog.path()` ⇒ **先判哨兵值 `'(不可用)'`** ✓（`site_error_log.dart:129` ✓ 拿不到时会返回这串字面量 ☠）⇒ 复制**带时间戳的副本**到临时目录 ⇒ `SharePlus.instance.share(ShareParams(files: [XFile(dst)], title:, sharePositionOrigin:))` ✓（**新 API** ✓ 旧的 `Share.shareXFiles` 已废弃 ✗）；
  **原日志一字不动** ✓；**分享后不立刻删副本**（面板交给对方是异步的 ✓）⇒ **下次导出先清旧副本** ✓；失败 `try/catch` 兜住、不抛界面 ✓。
- ⭐ 关键坑（`recon` 从官方源码排掉 ✓）：**`XFile` 由 `share_plus` 自己导出**（`export … show … XFile …` ✓）⇒ **不需要** `import 'package:cross_file/cross_file.dart';`（README 示例那行是冗余 ✓ 照抄反而多余 ✓）。

### 五、核查与验收（全部只读 ✓ 六轮）
- `recon`：**覆盖率盘点 35 条**（发现"首页/标签/搜索全站静默""Pornhub 整站无输出""中间网络步骤大面积静默"✓）→ 逐批验收 → **分支级盘点 18 条** → **导出 API 逐条核实**（含上面那个 `XFile` 关键点 ✓）。
- 逐批结论：站点侧 10 文件**无越界**（删除行全是 4 类等价改写：`=>`→`async`、`if-return`→块体、`if-return`→三元、`return X`→`final v = X` ✓）；括号余额与 HEAD **逐项相同** ✓；**95 处打印 0 缺守卫** ✓。
- 点名修掉的真问题：**`pornhub.dart` 把搜索关键词打进日志** ☠（`k=$path` ⇒ 含 `?search=…`）⇒ 改成只打路径 ✓（与 `search()` 入口的 `kwLen` 口径统一 ✓）。

### 六、教训（本轮真实发生 ✓）
- **"全量"≠"挑关键节点"** ☠：前几轮我做的是"关键步打点"，用户当场点破「**东落西落**」 ⇒ 全量 = **任何一步都要有输出** ✓（这才是可分析的前提 ✓）。
- **我误判一次、被证据纠正** ✓：我说 `main.dart:2` 的空行是"删 import 留下的、该删" ✗，`app-dev` 用**字节级对照**证明那行本来就在 HEAD（是 `dart:` 组与 `package:` 组的分隔行 ✓）⇒ 指令撤回 ✓。**结论要有实锤，别拿推断当事实** ✓。
- **别用"崩溃"当论据** ✗（用户点破：真崩溃本来就来不及记录 ✓）。

---


### 二、逐类怎么改（**只改必要处** ✓）
1. **改名 52 组 / 20 文件** ✓：`_sw→sw`、`_r→res`、`_d→det`、`_u→uri`、`_p→pathOnly`、`_qi→qi`、`_dpath→dpath`、`_q→qs`、`_ap→absPath`、`_del→deleted` ✓
   ⚠️ **两处真冲突，按语义另起** ✓：`detail_page` 里 `sw` 已被 `VideoSwitcher` 占用 ⇒ 用 **`stopwatch`** ✓；`home_page` 的 `_p` 语义是**页码**（不是路径）⇒ 用 **`reqPage`** ✓。
   核对：候选新名先做 `\b新名\b` 全文计数、**必须为 0 才用** ✓；改后**旧名残留 = 0** ✓（`recon` 复核 ✓，并把 `player_widget` 的**成员字段** `_p`、`site_error_log`/`bg_album_page` 里的同名字段**甄别为"非残留"** ✓）。
2. **花括号：先横扫 240 处 → 裁定回退 221 处** ✓（**只留 19**）
   - 起因：`app-dev` 认定"所有单行 `if` 都违规"⇒ 把全仓 240 处守卫**全加括号** ✗；
   - **我否掉**的判据（实测 ✓）：拿 analyze 报的两处去核**被分析的那个提交** `1660c40` 的原文 ——
     `base/fetch.dart:79` 与 `base/video_cache.dart:342` 都是 **`if (…) debugPrint(` 调用跨到下一行** ⇒ **该 lint 只在 body 不同行时报** ✓
     ⇒ 真报点 **19 处**、其余 **221 处是过度改动**（约 500 行无谓 churn、且破坏全仓单行守卫风格 ✓）；
   - 逆变换按**形态**判定 ✓：调用**跨行**的保留花括号（19 ✓）、**单行完整闭合**的合并回一行（221 ✓），字符串与缩进一字未动 ✓；改后全仓扫"`if (…) {` + 单行 + `}`"三行形态 = **0** ✓。
3. **废弃 API**（每条都钉在 **3.47.6 源码**上 ✓ 不是 main 分支）：
   - `withOpacity(x)` → **`withValues(alpha: x)`** **10 处** ✓（数值原样；色值差 ≤0.4/255、视觉不可见 ✓）
   - **`Matrix4`**（⚠️ **不是 `Canvas`** —— `recon` 纠了我的定位错 ✓）的 `..translate(x,y)` → **`..translateByDouble(x, y, 0.0, 1.0)`**、`..scale(s)` → **`..scaleByDouble(s, s, s, 1.0)`** **6 处** ✓
     ⚠️ **不许用 `translationValues`**（它是**覆盖**平移分量、`translate` 是**左乘** ⇒ 语义不同 ✓）
   - `Switch.activeColor` → **`activeTrackColor`** **2 处** ✓（⚠️ **不是** `activeThumbColor`：本页是 `Switch.adaptive` + iOS ⇒ 原色染的是**轨道** ✓ 换错颜色会跑到拇指上、外观就变了 ✓）
   - `player_widget` 的 `'$e'` → **`final es = e;`** **1 处** ✓（依据：`:313 String _lastFatal = '';` 且 `:187 _lastFatal = e;` ⇒ **`e` 必为 `String`** ✓）；⚠️ 另一处 `catch (e)`（`e` 是 `Object`）**保持 `'$e'`** ✓（改了会让 `es.length` 编译失败 ☠）
   - `parseP18List` → **`_parseP18List`** **3 处** ✓（比"公开 `_P18Item`"那条路改得少：3 vs 7 ✓）
   - 多余 `const`：**删 5 处**（父级 `const SnackBar(` ✓）**保留 2 处**（父级 `SnackBar(` 无 const ⇒ 删了破坏常量性 ☠）

### 三、行尾**治本**：`.gitattributes`（用户要求"改" ✓）
- 新建仓库根 **`.gitattributes`** ✓；规则**最终形态** = **`* text=auto eol=lf`** ✓ + 一段说明注释 ✓
  （先写的 `*.dart text eol=lf` ☠ —— `recon` 实测**漏了 4 个非 .dart 文件**（`DEVLOG_archive.md`、`sim/index.html`、`sim/server.mjs`、`启动模拟器.bat` ✓）⇒ 逐条列后缀必然漏 ⇒ 改全量 ✓；`text=auto` 对**二进制自动跳过** ✓（实测 8 个 jpg/png 仍为 `-text` ✓））
- 背景：`sites/hanime1|xvideos|madou|pektino.dart` 的索引条目标记是 **`i/-text`** ⇒ git 逐字节比 ⇒ 本地 `git diff` **整篇虚高**（548/536 那种 ☠）
- ⚠️ **我先前"代价 ≈1600 行一次性行尾变更"的预判——实测错了** ✓：提交后**字节级复核**（`git cat-file blob 1660c40:…` 与 `918a1ec:…`）显示那两个 blob **CR=0**（**本来就是 LF** ✓）⇒ 虚高纯粹来自"索引标 `-text`（逐字节比）+ 工作区是 CRLF"这两件事凑一起 ✓；`.gitattributes` 一生效，git 立刻按归一化口径比较 ⇒ **虚高当场消失、零 churn** ✓（比预期更好 ✓）
- **收益**：`git diff --numstat` 读数**不再虚高** ⇒ 一直用的 `git diff --ignore-cr-at-eol` **退役** ✓（实测：**裸 diff 与带该参数的结果完全相同** ✓）


### 五、教训（本轮真实发生 ✓）
- **"lint 报几处"要看规则语义，别凭直觉放大** ☠：240 vs 19 的差，是靠"拿一个**真被报的样点**去核**被分析的那个提交**的原文"判出来的 ✓ ⇒ **判据必须来自证据** ✓；过度清扫不止浪费时间，还会**破坏既有风格**、把 diff 撑大 ✓。
- **冲突名要按语义起** ✓：`_r→r` 会撞响应变量、`_p` 在 `home_page` 其实是页码 ⇒ **改名也是"读懂再改"** ✓。
- **批量机械改动必须可逆、可核** ✓：这次的逆变换（花括号）用"形态规则"批量判定，改后两边的**数字一致**（19/221 ✓），才敢收 ✓。

---

## 十九、2026-10-06 · **1.1.8（先提交、未构建）**：把"关着 = 零开销"补成真的 + 清掉最后 4 条 info

> 用户追问：「**开关未打开的时候，所有输出前的行为都不执行**」✓；随后指令："**1.补上 2.一起清掉**" ✓、"**先提交，不要构建！**" ✓

### 一、"零开销"的**最后一处漏网**（如实承认 ✓）
- 实情：`lib/main.dart` 的 `_NavLog` 两条 `[NAV] →` / `[NAV] ←` **没有显式守卫** ✗ —— 靠 `:30-35` 的全局 `debugPrint` 接管门控 ⇒ 输出确实没了，但**关着时仍会先拼一次字符串**（再被丢掉）☠ ⇒ 对"输出前的行为都不执行"**不成立** ✓
- 修：两条**前置** `if (AppSettings.i.logConsole)` ✓（**打印内容一字不改** ✓）+ 注释订正成"守卫写在前 ⇒ 连字符串都不拼 ⇒ 真正零开销" ✓
- `app-dev` 顺手扫全仓 ⇒ **又揪出 `lib/app_bg.dart` 5 处同类漏网** ✓：`:134` 暗像素占比、`:138` 判定失败、`:210` 老图迁移成功、`:213` 迁移失败、`:304` 本次加入 N 张（两条是**跨行调用** ⇒ 守卫加在语句最前、续行不动 ✓）—— 这批原是我更早"**先不加**"的既有打印 ✓ ⇒ 按新口径一并补齐 ✓
  - ⚠️ 该文件**原本没有** `settings.dart` import（**我记错了 ⇒ 队员实测纠正** ✓）⇒ 补 `import 'settings.dart';` ✓（`debugPrint` 由 `widgets.dart` 带入 ✓）
- ⇒ 全仓 **250 处 `debugPrint`，"缺显式守卫" = 0** ✓（判据含**复合条件**如 `if (logConsole && name == 'hwdec')` ✓ —— 早先那处"误报"就是这么来的 ✓）

### 二、清掉 analyze 最后 **4 条 info**
1. **`madou.dart` 3 处 `await_only_futures`**：`cards()` 是**同步**函数（定义 `:126 List<Article> cards(String html)` ✓）⇒ 撤掉**外层**多余 `await` ✓（**内层 `await _f.text(...)` 保留** ✓）；语义不变（`await` 作用于非 Future 值只多一次微任务跳转 ✓）。（注：这 3 条**不在** 1.1.6 那 114 条里 ⇒ 是后来几批引入的 ✓）
2. **`error_log_page.dart` 1 条 `use_build_context_synchronously`**：**把"取渲染盒"挪到所有 `await` 之前** ✓（`box` 只是读渲染盒位置、**不依赖任何 await 结果** ⇒ 提前取零副作用 ✓）⇒ `context` 只在**同步段**被用 ⇒ lint 判据不成立 ⇒ 消除 ✓
   - `recon` 又提示"它落到了 `try` **之外** ⇒ 兜底范围缩小" ✓ ⇒ 再挪进 **`try {` 的第一行** ✓（**仍在所有 `await` 之前** ✓ 两全 ✓）
   - 顺带：原那一句因挪动而成无用的 `if (!mounted) return;` 删掉 ✓；**分享后**那条（页面已被 pop 就别弹 SnackBar ✓）**保留** ✓


### 四、教训（本轮真实发生 ✓）
- **"零开销"要按"字符串也会被拼"来验** ☠：只靠"全局接管"拦，输出是没了、**构造还在** ⇒ 判据必须是"**显式守卫写在调用之前**" ✓。
- **我凭记忆出错一次**（以为 `app_bg` 已有 `settings` import）⇒ **队员实测纠正** ✓ ⇒ 再次印证"**先读再改，别凭记忆**" ✓。

---

## 二十、2026-10-06 · **下一版（未构建）**：`[IMG] 预热` 加序号 + 导出改"**直接分享源文件**"

> 用户两条点名：①「`[IMG] 预热` 打点要不要加索引，**加**」✓ ②「我的意思**直接导出 Documents 里的**不行吗？？？」⇒ 定"**直接导出**"✓（并追问"源文件不会被删除吧？" ✓）

### 一、`[IMG] 预热` 加序号（用户实测的痛点 ✓）
- 现象：直播列表页一次性连出 **8 条一模一样的** `[IMG] 预热 host=img.doppiocdn.net` （同一 CDN ⇒ 只打 host 时**分不出是哪张** ✓）
- 根因：打印在**单 URL 的通用函数**里（`fetched_image.dart` 的 `warm(String? url)`）⇒ **函数内根本没有序号可打** ✗；序号只在**调用点**才有（`itemBuilder` 的 `i`）
- 方案（3 选 1 ⇒ 定 **A**）：**给 `warm` 加可选具名参数** `{int? index, int? total}` ✓（**默认 null ⇒ 老调用点行为完全一致** ✓）⇒ 5 个调用点各补两个具名实参 ✓
  - ⚠️ 否掉的两个：**B**（调用点另打一条带序号的日志）⇒ 序号与 path 分两条日志、要对着看，`online_album_common` 那种循环还会刷屏 ✗；**C**（函数内维护静态计数器）⇒ 没有可靠的"批次开始/结束"信号、序号会**跨页面累积、会骗人** ☠
- 落地：`fetched_image.dart` 2 行签名 + 1 处打印（**`path=` 与同文件 `[IMG] 取数` 同款、截 80、无 query** ✓）+ 5 个调用点各 1 行（`xhamsterlive` / `home_page`×2 / `shorts_feed` / `online_album_common` ✓）；**预热逻辑（`_inflight.putIfAbsent`/顺序/并发/入参/返回）一字未动** ✓
- 效果：`[IMG] 预热 9/48 host=img.doppiocdn.net path=https://img.doppiocdn.net/snapshot/208306551/…` ✓ ⇒ 能跟 `[IMG] 取数`、`[LIVE] ①进房 id=208306551` **直接对上** ✓
- 验收（`recon` ✓）：**签名向后兼容** ✓（全仓调用点正好 5 处、无别名调用 ✓）；**序号与"实际预热的那张"同源** ✓（`i+8` 陪 `rooms[i+8]`、`j` 陪 `_items[j]` ✓ 无错位 ✓）；**越界时传 `null` ⇒ 早退不打日志** ✓（不会冒出 `21/20` 超界序号 ✓）；合计 **+25/−9** ✓

### 二、导出改"**直接分享源文件**"（**净减 15 行** ✓）
- 改前：导出 = 复制一份带时间戳的副本到 `Library/Caches/`，分享**副本**（分享后不删、下次导出清旧 ✓）
- **为什么当初复制**（如实回顾 ✓）：① 副本名能带时间戳 ② **日志是"活的"**（分享那刻还在写）③ 个别"就地打开"的目的地可能把**原文件移走/改名** ☠
- 用户拍板：**直接导出** ✓ ⇒ 改成 `files: [XFile(p)]`（`p` = `Documents/kpxx_error.log` ✓）；**删掉整套副本逻辑**（临时目录 / 时间戳命名 / 清旧副本 / `_exported` 字段 / `path_provider` import ✓）⇒ `error_log_page.dart` **净减 14 行**（`+8/−22` ✓）
- 保留 ✓：**哨兵值 `'(不可用)'` 判定必须在 `XFile(p)` 之前** ✓、`src.exists()` 那条"还没有日志文件 ✓（先复现一次再导出）"提示 ✓、`box` **于 `try` 内且在所有 `await` 之前** ✓、`try/catch` 兜底 ✓、`_text.isEmpty` 置灰 ✓
- ⭐ **"源文件会不会被删/丢"的定论**（两方独立核过 ✓）：写日志用 **`FileMode.append`**（`site_error_log.dart:100-104` ✓）⇒ **文件不存在会自动新建** ✓；写入前**没有**"必须先存在"的阻断（`:93` 的 `exists()` 只在"超限才裁"条件里、`&&` 短路 ✓）；路径**每次重新解析**、不缓存（`_file()` 是函数 ✓）⇒ **即便原文件真被某个目的地搬走，App 下一次记日志会在原位置自动新建** ✓ ⇒ **不影响后续写日志** ✓
  - ⚠️ **但要说实话**：**已写的历史内容会随文件一起被移走**（不再有副本 ⇒ 没有第二份 ✓）⇒ 注释措辞按此订正 ✓（`recon` 点出的"不丢数据"说法过满 ✓）
- 验收（`recon` ✓）：顺序无"拿哨兵串构造 `XFile`"路径 ✓；`_exported`/`kpxx_error_`/`src.copy` 全仓 **0 命中** ✓；无未使用 import/字段 ✓；括号余额一致 ✓

### 三、直播**取最高档分辨率**（用户点名"改口" ✓）
> 用户原话：「**直播直接取最高分辨率吧。我受不了了，现在默认档画质给的太模糊了。改为取最高档分辨率**」✓
- ⚠️ **口径边界**：这条**只推翻直播** ✓（其余站点"站点给什么播什么"照旧 ✓ —— 那是 10-02 用户定的 ✓）
- 改前：直播 `④档=自动(master 原样交 AVPlayer)` ⇒ **AVPlayer 自适应挑档**，实机偏模糊 ✗
- 改后：**复用 ③ 校验已经拉下来的那份 master 文本**（**零额外请求** ✓）⇒ 就地解析变体、**先比分辨率高度、同高比带宽**取最高 ⇒ 把**那一档的地址**交给播放器 ✓
  - 解析要点：变体地址 = `#EXT-X-STREAM-INF:` 之后的**第一个非 `#` 行** ✓；地址用 **`Uri.resolve`**（不拼字符串 ✓）；⚠️ `BANDWIDTH=` 正则**必须带边界 `(?:^|[,:])`**，否则会**误命中 `AVERAGE-BANDWIDTH=`**（子串）⇒ 同高时会选错档 ☠
  - **兜底**：解析不出 / 不是多档清单 ⇒ **回落到老行为**（master 原样交播放器 ✓）+ 把**回落原因**打进日志 ✓；只有一个变体 ⇒ 就用它 ✓
- ⭐ **实锤（真请求实测 ✓）**：某房间 master `HTTP 200 / 1852 字节`、**共 5 档**：
  `1080x1440@7.02Mbps(source)` / `720x960@4.19M` / `720x960@2.66M` / `360x480@1.41M` / `180x240@0.68M`
  ⇒ 说明"糊"**不是源的问题**（最高档 1080x1440 明明白白在清单里 ✓）⇒ **钉死最高档**正是用户要的 ✓；变体地址是**绝对地址且自带 `pkey`/`playlistType`** ⇒ `Uri.resolve` 原样返回、**参数不丢** ✓
- ⭐ **保险（我拍板加 ✓）**："钉死单档 = 丢掉 AVPlayer 自己的兜底" ⇒ 加 **"最高档播不了 ⇒ 用 master 再试一次"**：
  - `_triedMaster` 标记：**一处复位**（`_checkAndPlay` 开头 ⇒ 进房/缓存回退都重新可用 ✓）+ **一处置真** + 一处判定 ✓；
  - `url != mu` 判据用**纯函数现算 master 地址**（`liveMasterUrl(id)` ⇒ 同一 id 恒等 ⇒ 字符串比较可靠 ✓、不存字段 ⇒ 少一份状态 ✓）；
  - **恒 `allowFallback: false`** ⇒ 不经过缓存分支 ⇒ **不会成环**（唯一能再进 `_checkAndPlay` 的入口是 `allowFallback: true` 那条 ✓）；
  - 三场景手推 ✓：A 最高档败 ⇒ 试 master ⇒ 再败**不再重试**（**最多两次播放尝试** ✓）；B 解析失败本就播 master ⇒ **不触发**回落、也不打"master 也失败" ✓；C 缓存命中败 ⇒ 复位后再来一轮，仍**不成环** ✓
  - 故意保留的语义：若"回落 master 才播成功" ⇒ 首帧确认时把 **master** 写进缓存 ⇒ 本会话再进这房间直接走 master（能播、不反复试最高档 ✓）
- 验收（`recon` ✓）：解析正确性（含 `AVERAGE-BANDWIDTH` 边界 ✓）/ 老行为不回归（`top == null` 分支**与改前逐字等价** ✓）/ **只回落一次**（`_triedMaster` 全文件 6 处出现、**置真仅 1 处** ✓）/ 状态语义未变（`_variantCache` 3 处写入点未动 ✓）/ **日志无 `pkey`/`.query` 泄漏** ✓ / 站点独立（解析只在 `xhamsterlive.dart` ✓）
- 代价（用户已知情 ✓）：最高档 = **1080x1440@60 / 7 Mbps** ⇒ **起播可能略慢、流量更大**；**不为此改任何缓冲/超时参数** ✗

### 四、教训
- **打点位置决定"能不能说明问题"** ✓：只在通用函数里打、拿不到调用点上下文 ⇒ 日志会同质化、**等于没打** ✓（这次是"只打 host"的典型 ✓）。
- **"简化"也是一种正确** ✓：用户一句"**直接导出不行吗**" ⇒ 结果是**净减代码** ✓ ⇒ 提醒：复杂方案（副本+清理）要**先说清代价与收益**再上，别默认加复杂度 ✓。
- **用户的直觉提问要当"复核信号"** ✓："源文件不会被删除吧？" ⇒ 逼出一条**代码 + 官方文档级**的实锤（`FileMode.append` ⇒ 自动新建 ✓），比我们嘴上保证强得多 ✓。

---

## 二十一、2026-10-06 · **1.1.9 续（本次"提交但不构建"）**：底栏改「点播」+ sim 全量对齐 App

> 用户口径链：「**APP端完美，全量同步到 sim。sim 端需要用 sim 支持的写法改。我用的是 iPhone 16 Pro Max。把分辨率什么的都改成一模一样**」⇒「**按照 APP 对齐，全部按照 APP 的布局。但是日志实际功能不需要**」+ 后续几条点名（版本号对齐 / 选择器做成可选 / 纯白纯黑两张图 / **文字全部黑白自适应**）✓
> ⚠️ **`sim/**` 一律不进提交**（用户明确定过 ✓）—— 注意 `sim/` 是**被 git 跟踪**的（不是 ignore）⇒ 每次提交必须**显式排除** ☠（`git add` 指定文件 ✓）

### 一、`lib/**` 本次改动（**全部未提交 → 本次提交** ✓）
| 文件 | 改动 | 行数 |
|---|---|---|
| `lib/main.dart` | ⭐ **底栏第一项 `模块` → `点播`**（`:192`）+ 5 处注释同步 | +6/−6 |
| `lib/app_bg.dart` | 2 处"跨行 body"的守卫**加花括号** ⇒ analyze 最后 **2 条 info 清零** ✓（**只有花括号+注释，字符串一字未改** ✓） | +11/−4 |
| `lib/sites.dart` / `lib/sites/xhamsterlive.dart` | 注释里「模块」→「点播」各 4 处 ✓ | +4/−4 ×2 |
⇒ **界面可见变化只有 1 行**（底栏文字 ✓），其余是注释与 lint ✓

### 二、`sim` 全量对齐（**只动 `sim/index.html`** ✓ 用户："全部按照 APP 的布局"）
1. **设备参数**：`--dev-w/--dev-h` **393×852 → 440×956** ✓（= iPhone 16 Pro Max 逻辑分辨率 ✓ 物理 1320×2868 @3x ✓）；**写法未退回**被警告过的那种（外壳 `calc(+24px)`+`padding:12px` 未动 ⇒ 屏幕恰好 440 ✓）；安全区上 62 / 下 34 **本来就一致 ⇒ 未动** ✓；顺带发现 `fitPhone()` 目标写死 440×956、而默认值曾是 393 ⇒ **缩放一直偏小**，现在正好对上 ✓
2. **设置页补两处**：新增「诊断」卡（**开关行在上、错误日志按钮在下** ✓ 按钮**宽 50% 居中** ✓ 开关橙 `#E8590C` = App `_orange` **逐值相同** ✓ 文案逐字 ✓ 卡位置 = App 第 4 张 ✓）；另补**整行缺失的「硬件解码」**（自动/硬解/软解 ✓）、缓冲档标签 `100M→100MB` ✓、**初始值全改 App 源码默认**（步长 10 / 缓冲 200MB / 自动下一集关 / 硬解码自动 / 控制台日志关 ✓）
3. **错误日志页**：4 键 = 刷新 / 复制全部 / **导出（方框+上箭头）** / 清空 ✓（⚠️ 我先前口头说"三个键"是**错的** ✗ 以 App 的 4 键为准 ✓）；正文 12px/1.45 非等宽 ✓；**置灰态 + 清空确认框**（文案逐字「清空错误日志？」「清空后无法恢复。」+ 取消/清空 ✓ 判据 = App 的 `_text.isEmpty` ⇒ **只有导出/清空置灰**、刷新/复制永远可点 ✓）；**实际功能不需要** ⇒ 保持 mock ✓
4. **底栏** `模块`→`点播` ✓；**`#alb2Sorts`** `8px 2px 0` → **`6px 2px 3px`** ✓（= App `online_album2_page.dart:251` 的 `EdgeInsets.only(top:6,left:2,right:2,bottom:3)` ✓ **上轮那条 ❓ 闭环** ✓）
5. **默认图集预置「纯白」「纯黑」** ✓（data URI 的 SVG 纯色矩形 —— 背景/缩略图/明暗判定三条链走的都是 `url(...)` ⇒ 用 URL 形态**三条链一行不用改** ✓；`background-image:#fff` 是非法值 ☠）；**只种一次**（localStorage 标记 ⇒ 删了不会自己回来 ✓）；导出时拦掉 data URI（否则拿 `.jpg` 名下载 SVG = 假导出 ✓）
6. **文字全部黑白自适应** ✓：App 机制在 `app_bg.dart`（32px 采样、亮度<0.5 占比>50% ⇒ isDark ✓ 源码自己写着"照 sim 的 bgIsDark"⇒ **两边同口径** ✓）；sim 本次是**补缺口**（`.hint`/`.lv-more`/`.dmeta`/`.intro`/`.site`/`.bgal-ago` + **id 作用域的** tab/chip（id 特异性压过通配 ⇒ 黑底近黑字 ☠）+ 转圈环色 + 4 处内联写死 ⇒ 收进 3 个令牌 ✓）；**自带底色的不动**（白卡/橙按钮/灰按钮/输入框/分段控件/弹层 ✓）、**语义色保住**（红"重置"、绿"已看完" ✓）

### 三、争议项的裁定（**用真机截图做像素测量，不猜** ✓）
`sim-dev` 两处"不敢单方面改"（sim 的数值是 10-02 按"真机截图"定的，与 App 源码打架）⇒ 我拿**用户真机截图**量：
| 项 | 实测 | 结论 |
|---|---|---|
| 品牌条高度 | 橙带 y=224..311 ⇒ **88px ⇒ 30.3pt**（比例 2.909 px/pt） | 与 `KpxxLogo height:30` **吻合** ✓ ⇒ sim 的 **44 是错的** ✗ 改 30 |
| 宫格 | 相邻格**中心距 ≈107pt** | 与源码（横 padding 10 + 列距 8 + 4 列 ⇒ 格宽 99、中心距 107）**吻合** ✓ ⇒ sim 的 `gap:26/10 + padding:16/14` 错 ✗ 改源码值 |
⇒ **教训：sim 里那些"照截图量的"数字不可信 ☠；争议项要用"真机截图 + 源码"双向对** ✓

### 四、验收（**我亲自跑的无头截图 + 脚本实测** ✓ 用户点名"你自己启动模拟器核对"）
- 工具链：**Edge 无头 + CDP**（`--headless=new --remote-debugging-port` + 临时 profile ✓）⇒ 视口 440×956 @3x、按 `.screen` 元素**精确裁切** ⇒ 截图 **1320×2868** ✓ = 16 Pro Max 物理分辨率 ✓；还能**脚本点击**（真窗口里不允许注入鼠标/键盘 ✓）
- 实测数字：品牌条 **30pt** ✓、宫格 **中心距 107 / 格宽 99 / 14 格** ✓、设置页默认**无**「模拟器专用」块（元素计数 **0** ✓）/ 带 `?bgtool=1` 有 **6** ✓、图集前两条 = **纯白 / 纯黑** ✓、**选纯黑 ⇒ 全页白字** ✓ / **选纯白 ⇒ 全页深字** ✓、四键置灰判据（清空后**导出/清空 off=true**、刷新/复制仍可用 ✓）
- ⚠️ **一处我自己的坑**：`document.body.innerHTML.includes('模拟器专用')` 会**命中脚本源码文本** ⇒ 假阳性 ☠（判据要按**元素**查 ✓）；`applyBg(url)` 参数形式不对 ⇒ 真入口是 **`bgPick(url)`**（读源码才知道 ✓）

### 五、教训
- **"看图说话"要落到像素**：两处几何争议，靠"真机截图量 + 源码算"一次定死 ✓（比互相说服快 ✓）。
- **别用 innerHTML 判界面**（会吃到 `<script>` 文本 ✓）；**别猜函数签名**（读源码/读行的 onclick ✓）。
- **无头适合核尺寸与交互、可见窗口适合用户中途预览** ⇒ 两者并用 ✓（用户明确要预览 ⇒ 起了可见窗 + 常驻服务 ✓）。

---

## 事实归档（**从已清理的流水里保留的事实结论** ✓ —— 只留结论，不留过程）

> 口径：如与正文冲突，**以正文为准** ✓。来源 = 2026-10-07 清理时删掉的变更流水（备份 `DEVLOG_backup_2026-10-07.md` ✓）。

### 短片（xHamster）
- 列表取数 = **两段式**：第 1 页走页面 JSON（45 条，站点固定一份）+ 第 2 页起走**路径式** `/shorts/newest/{page}`（`?page=N` 被忽略 ✗ 返回同批）；`lastPage=100`；页间零重叠、每页 +5~6 条 ✓
- `/api/v1/moments` 只要带 `X-Requested-With: XMLHttpRequest` 就 **404** ✓（去掉即 200）⇒ 该接口路已撤 ✓
- 短片卡 `coverAspect 3/4`；`meta` 留空 ✓
- **入口预热** = 底座 `lib/base/source_cache.dart`（url → Future<源> + 在途去重 + LRU 80 + 失败不进缓存 ✓）；网格在 push 前取源（请求数不增 ✓，页内私有缓存已删 ✓）
- **换源遮罩** = 黑底 + 本条封面 + 转圈；判据 `position > Duration.zero`（`KpPlayer.open()` 会清 0 ✓）；两个必需项：**`IgnorePointer`** + **黑底** ✓
- **短片实例专属 mpv 起播参数**：`demuxer-lavf-analyzeduration` 5→2 · `demuxer-lavf-probesize` 5M→1.5M · `cache-pause-initial=no`（走 `setMpvOptionQuiet` ✓ 只给短片实例 ✓）；⚠️ `_p.platform` 为 null 时**静默失效** ✓
- **约 41% 条目只有 m3u8**（无 mp4）⇒ 不能预下载，只能在线拉 ✓
- m3u8-only 实测（7 条）：**无 `#EXT-X-KEY`** ✓；票据在**路径前缀**（到期 ≈3.5h ✓）；分段 3~20 · 单段 88~180KB · 一条 0.35~1.19MB ⇒ **不做解密 / 不做鉴权重放 / 不放大上限** ✓
- 短片源体积：中位数 **2.65MB** / 最大 5.10MB ⇒ 32MB 上限从未触发 ✓（教训：**该实测的不要估算** ✓）
- **视频缓存**：32MB/文件 · **200MB 总量 / `maxFiles` 70 / 并发 5**；只做直链 mp4；**整份下完才改名 `.mp4`、只播完整文件**（无需探测 moov ✓）；播放 buffering 时暂停预下载（去抖 1.5s、dispose 必 resume ✓）；首条也预下载 ✓
- 续拉：失败**不置 `_done`**（只标 `_tailFailed`）+ 暂停层 **↻ 重试**；`_page = 0`（首次续拉 = page 1，45 条打底 ✓）
- sim 侧：`getHtml()` 曾**无超时** ⇒ 中转卡住会**永久卡死续拉** ✓ 已加 **20 秒** AbortController（与 App 短片取源 20s 对齐 ✓）；`window.__shortsItems` = **第 1 页清空 + 之后累加**（否则列表翻页后进流只剩最后一页 ✓）

### 直播（xHamsterLive）
- 站点是**双重反盗链**：清单里所有 `#EXT-X-PART` URI 与 `#EXTINF` 下一行 = 同一占位 `…/media.mp4`（404 ✓）；`#EXT-X-MOUFLON:URI:` 那份"像真 URL"的 **25/25 全 404**（八种姿势全试 ✓）⇒ **mpv/ffmpeg 这类只认标准 m3u8 的播放器播不出来** ✓；"藏外框 + 画面铺满 + 让站点播放器自己放"是唯一可行路 ✓
- **真分片 URL = 播放器自己请求的那条**（无 Referer / 支持 Range / 200-206 ✓）；token 与清单里的不同（逐段算出，钥匙在混淆的 `main.js` 里 ✓）；**真 URL 分钟级 TTL**（init 段不受影响、可复用 ✓）
- 播放器 bundle 可直取（`mmp.doppiocdn.com/player/mmp/v2.13.0/main.js` = 200 / 352240B ✓）；解密器 `get corruptionQueryParams()` 只发 `psch` + `pkey` ✓；**密钥表硬编码**（已抠出 2 项 ✓）
- **房间页注入**：点掉 18+ 弹窗（`#agreement-root`）+ Cookie 条；藏站点外框（顶栏/通知/侧栏/页脚/聊天/相关/标签/**站点自己的控制条** ✓）；铺满目标**必须是 `.video-element-wrapper`**（直接改 `video` 会被站点 JS 每帧打回 ✓）；选择器只用 `data-testid` / 语义 class / 稳定 id（**不用 `#哈希`** ✓）；整段 try/catch **非致命** ✓
- 注入健壮化：**三个注入点**（`onPageStarted` / `onProgress` 过半 / `onPageFinished`）+ **两段解耦**（`_inject` + `_runQuiet` 各自 try/catch ✓）+ 尾部 **MutationObserver 自愈**（50ms 去抖；style 被摘 **400ms 内补回** ✓）；静音守护 `_guardJs` 本就自愈（2 秒一扫 ✓）
- 点卡片**先白屏**：根因 = `WebEmbed` 未设底色（WKWebView 默认白底 ✓）⇒ 修 = **纯黑底** + 就绪前「黑盖 + 正在加载…」+ **10 秒保险丝**；开关 **`darkShell` 默认 false**，只有房间页传 true ✓
- 播放：`hwdec=no` ✓；缓存三选项 `cache-secs=2` / `demuxer-max-bytes=8388608` / `cache-pause-initial=no` ✓；看门狗（不重开不误报 ✓ `kLiveGiveUpMs = 90000` ✓）；**去掉"变体单独校验"**（省一次往返，真机实测曾占 1257ms ✓）；**按房间缓存变体 URL**（6 秒没出画面 → 回退一次并丢缓存；只有真出过画面才算"可用" ✓）；房间页 `analyzeduration` 覆盖 **0.5**（`player_widget.dart` 未动 ✓）；**不许降分辨率** ⇒ 取 master 第一档（多数 `NAME="source"` / 720p ✓）
- 房间页**零控件**：只有画面 + 一行状态字 + 单击显隐的 X；X = 方块 **76×76** · 图标 **32** · 左距 **5**（左对齐 + 垂直居中 ✓）；点击层从"包住整棵 Stack"改成**单独一层并让出左边 24px**（代价：**最左 24px 内点屏幕不显隐 X** ✓ 已知取舍 ✓）；`ValueNotifier<bool>` + `ValueListenableBuilder` **只刷 X** ✓
- sim 直播页：4 主分类（女主播 **58** / 情侣 **36** / 男主播 **60** / 跨性別 **57** 个唯一路径，共 **211** 条 ✓）+ 分组子分类 **3 列按钮宫格**；「全部分类」= `/tags/<main>` ✓（**无** `/<main>/best` ✓）；按钮用 `data-*` 绑定（名字含中文/括号 ⇒ 内联 `onclick` 易踩雷 ✓）；后加第 5/6 tab「移动流」「手机版最新」（`newMobile` 叶子；判据必须带 `newMobile` —— 三个 tab 的 tag 都是 `girls`，只看 tag 会串 ✓）；移动端 4 个过滤器入口 = **横排 tab 栏**（复用 `.lv-tabs/.lv-tab` ✓）；已选显示「外貌: 熟女」+ 高亮 + 「重置」小 tab；⚠️ 坑：主分类 tab 绑定必须限定 **`.lv-tab[data-mi]`**（否则被过滤器 tab 抢走 ✓）；弹窗 = 宽 **92%** / 高按内容 **28%~76%** ✓
- sim 房间层：放站点**预览片**并明写「不是真直播」✓；曾经的「真直播 ↗」兜底按钮**已彻底删掉**（`grep 真直播` / `lvli` = **0** ✓）；降级文案 = 「播放器组件加载失败（外部源不通）· 现在放的是预览片 · 点这里重试 ↻」✓

### 平台与工程坑
- WKWebView `allowsInlineMediaPlayback` **默认 false** ⇒ 点视频弹系统全屏 ✓；修 = 创建参数设 true + `mediaTypesRequiringUserAction: const {}` + JS 补 `playsInline`；⚠️ 这两个开关**只能在创建期**给 ✓
- 站点 CSP `frame-ancestors 'self'` **挡死跨域 iframe** ✓；App 的 WebView 是**顶层加载** ⇒ 不受影响 ✓
- `web_embed.dart` 曾漏 `import 'dart:async'`（`Timer` 属于它）⇒ CI analyze 2 error ✓；教训：新用的符号要 `grep` 定义处确认 import ✓
- **行尾**：`lib/sites/xhamster.dart` 曾是 **CRCRLF**（多行锚点匹配不上、PowerShell 行数不可信 ✓）⇒ 经 git 往返已恢复普通 CRLF ✓；写这类"CRLF blob"文件的脚本**必须自动探测行尾** ✓；看真实改动量用 `--ignore-cr-at-eol` ✓（`.gitattributes` 治本后**裸 diff 与它相同** ⇒ 旧参数退役 ✓）；`porna.dart`/`pornhub.dart` 的裸 diff 会显示**整文件重写**（实际只改几行 ✓）
- **死代码清理的实证规则**：全库 `git grep -n`，只有"除定义/赋值外 **0 引用**"才删 ✓（例：`resetShortsRandom` 三处一起删——它只写 0 读字段 ⇒ **行为等价** ✓）
- **lint 口径**：`use_build_context_synchronously` → 用 `context.mounted` ✓；`withOpacity` → `withValues(alpha:)` ✓；`Matrix4.translate/scale` → `translateByDouble`/`scaleByDouble`（**不许** `translationValues` ✓）；`Switch.activeColor` → **`activeTrackColor`**（**不是** `activeThumbColor` ✓）；`curly_braces_in_flow_control_structures` **只在"body 与条件不同行"时**报（同行 `if (c) stmt;` 是允许的 ✓）
- `webview_flutter_wkwebview` 显式声明 `>=3.0.0 <4.0.0`（锁里已是 3.22.0 ✓）⇒ 消 `depend_on_referenced_packages` ✓
- **图片磁盘缓存** `lib/base/image_cache.dart`：上限 **400 个 / 60MB** ✓ 键 = url ✓ 存明文 ✓
- **用户撤销项**：手动清理缓存**不做** ✓（"200MB 没必要清理" ✓）
- **不要用 `innerHTML` 判界面**（会吃到 `<script>` 源码文本 ⇒ 假阳性 ✓）；判据要按**元素**查 ✓
