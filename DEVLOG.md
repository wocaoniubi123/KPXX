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
**约定：每次构建 +1** ✓（当前 **1.2.7**）
（规则："每段 0~9、满 9 进位" ✓ 见 `lib/app_version.dart` ✓；CI 用"去点"当 `--build-number` ⇒ 1.2.0⇒120 ✓）

## 四、构建流程（唯一验证手段 ✓）
`checkout → Setup Flutter 3.47.6 → flutter create → 证书 → 改 iOS 工程 → ExportOptions →`
`→ 代码检查 (flutter analyze lib)   ← 一次列出【全部】Dart 错误 ✓`
`→ Flutter build IPA → 按版本号重命名 IPA → 上传 artifact → 发布 Releases → 列出产物`

> ⚠️ **Flutter 版本以 `.github/workflows/ios.yml` 为准** ✓ —— 现在是 **3.47.6**（Dart 3.13.5 ✓，2026-10-06 从 3.27.4 升上来 ✓）；
> 本行早先写的 `3.24.5` 是**过时的** ✗（已改 ✓）。升级原因与欠账教训见「事实归档 · 工具链」✓。

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

---

## 八、播放器：两套引擎 + 起播硬事实（从已归档的流水里提炼 ✓）

**两套引擎，分工是硬性的** ✓：
- **直播房间页** = `video_player`（iOS 上是 **AVPlayer**）✓ —— 单站独用（`lib/sites/xhamsterlive.dart`）✓
- **其它全部**（详情页 / 短片 / 全屏）= `KpPlayer`（media_kit / libmpv，`player_widget.dart`）✓
- 为什么直播要换掉 mpv：**mpv 每个分片请求都新建 TCP 连接**（经代理每次 CONNECT+TLS ≈0.44~0.48s，4 次串行 ≈1.8s）⇒ 首帧 2.9s（真机 5.5s）✗；
  AVPlayer **复用热连接** ⇒ ~2s ✓（依据：本地 mpv 时间轴 + hls.js 同机同房同 URL 对照 1775/2034ms ✓）
- ⚠️ 设置里的「硬件解码」**只对内置播放器（mpv）生效** ✗ —— 直播走 AVPlayer，不吃它 ✓
- ⚠️ `hwdec` 的「自动」= **不下发**（mpv 手册：硬解默认不开）⇒ 实际很可能等于软解（真机未查证 ❓）

**起播硬事实（本地 mpv A/B 实测 ✓）**：
- ☠ **喂 master 清单 = ffmpeg 逐档探测**：它会把**每一档都打开、各取一条首段**（每档 ≈0.5~2s）⇒ 这就是"十几秒才出画面"的主因 ✗（不是网络、不是解码器、不是缓冲参数）
- ✅ **单档变体 URL 比 master 快 10.3 秒**（13,229ms → 2,929ms）⇒ 校验可以看 master ✓，但**交给播放器的用变体** ✓
- ✅ 三项保留的提速：`hwdec=no` −2.6s · 起播参数（`demuxer-lavf-analyzeduration` / `demuxer-lavf-probesize` / `cache-pause-initial`）−1.7s
- ⚠️ `probesize` **别往小调**（500k / 50k 实测**更慢** ✗）
- ⚠️ `demuxer-max-bytes` 8MiB vs 200MiB **几乎无差异** ⇒ 「200MB 缓冲拖慢起播」已被实测**否掉** ✓
- 2.9s 的构成 = **4 次串行 HTTPS 往返(≈1.8s) + 进程/解码初始化(≈1.1s)**；mpv 参数只占 0.1s ⇒ 想再快只能**减少串行往返**（未做 ✓）
- ⚠️ **拿 mpv 直接开"裸分片 URL"必失败**（缺 init / `ftyp` 上下文）⇒ 看到 `avformat_open_input() failed` 先想"URL 过期或裸分片"，别先怪网络 ✓

**直播取流的最终形态（1.0.05 → 1.0.36 演变后的现状 ✓）**：
- 让页面走 **iPhone（无 MSE）分支** ⇒ 站点给的是**明文** `<id>_auto.m3u8` + **站点级硬编码 `pkey`** ✓
  （不带 pkey 拿到的是**广告清单** `#EXT-X-MOUFLON-ADVERT` ⇒ 开播前必须校验，**绝不播广告** ✓）
- 保留：**按房间记变体 URL、跳过 master** ✓ · master 广告校验 ✓ · 直拼失败**回退抓 master 一次** ✓
- 看门狗判据 = `isInitialized` / `position` / `isBuffering` / `errorDescription`（8 秒 → "仍在加载…"；90 秒兜底）✓

---

## 九、已经走过、结论是「做不到」的路（**别再重复试** ✓）

- ☠ **自绘 UI + 直连站点直播真流**（不借站点自己的播放器）：`pkey` 只活在站点自研播放器 **mmp 内部**
  （22 个 API 正文 / localStorage / sessionStorage / cookie / 页面 HTML / WebSocket 文本帧**全搜过 = 0 处** ✓）；
  清单是 mmp **私有混淆格式**（`#EXT-X-MOUFLON:URI:` 里是**密文**，播放器拿密钥表解密 ⇒ "照抄清单"结构性不可行 ✓）；
  **分片地址是"等播放器给"的**（`_awaitingFragmentURL` ✓）⇒ 要做就得先做**独立 RE 工程** ✗
  ⚠️ 但**同一目标的另一条路是通的** ✓：页面走 iPhone(无 MSE) 分支后给出**明文** master + 硬编码 pkey ⇒ **App 直播现在走的就是这条** ✓（见上一节）
- ☠ **iframe 嵌直播房间页**：响应头 **`X-Frame-Options: deny`**（根页也一样）⇒ 物理上死 ✓
- ☠ **单实例 mpv 预缓冲 5 条**：mpv 唯一相关开关 `--prefetch-playlist` 只预取**下一条**、**要等当前 URL 完全读完才启动**、**对 HLS 无效**
  （mpv 把 HLS 当**单个**媒体项）✓；上游 issue **#5940「Parallel prefetch」已 Closed**、#6437 仍 Open ✓ ⇒ 结构上做不到 ✓
  （现行走的是 App 侧按源 URL **预下载** ✓）
- ☠ **1.0.55 / 1.0.56 那批内存优化**（40MB+ LRU 解码缓存 / 离页清本 / 预览预取 / 预热延后 400ms 且只预热 12 张 / 尺寸表换 provider）
  ⇒ 引入「反复进出图集就闪退」（无日志、典型被系统杀）⇒ 1.0.57 **全部回滚** ✓ ⇒ **不要再原样往回加** ✗；要加就**单独加、单独验** ✓

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

---

## 十二、页面转场与 `PageBg`（**必须遵守** ✓）

**全 App 的 Scaffold / 页面底色是透明的** ✓（为了让背景图透出来）⇒ ☠ **任何 push 的新页面，如果不在最底层铺一层 `PageBg`，转场时就会和旧页面叠影**
（现象：文字 / 进度条全部双影、像卡半秒 ✗）。

- 现状：`lib/` 里共 **24 处 `MaterialPageRoute(`**，**除 `lib/sites/xhamsterlive.dart` 进直播间那一处外，其余都已包 `PageBg`** ✓
  （那一处用户明确说先不管 ✓ 只作记录 ✗）
- ⇒ **以后新增任何 push 页面，记得包 `PageBg`** ✓
- 配套教训：**一包一个改动、一次一个结论** ✓ —— 不要一包塞一堆猜测 ☠（1.0.55/1.0.56 就是"打错靶子"两轮，代价很大 ✓）

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

## 事实归档（**从已清理的流水里保留的事实结论** ✓ —— 只留结论，不留过程）

> 口径：如与正文冲突，**以正文为准** ✓。来源 = 2026-10-07 清理时删掉的变更流水（备份 `DEVLOG_backup_2026-10-07.md` ✓）。
> **2026-10-08 二次清理** ✓：10-03～10-06 的逐轮流水（sim 直播逆向 / 播放器起播排查 / 日志系统 / 1.0.x～1.2.x 各批）**原文整体归档**到 **`DEVLOG_archive.md`** ✓
> （备份 `DEVLOG_backup_2026-10-08.md` ✓）；其中**仍生效的结论**已提炼进正文 —— 见「八、播放器」「九、做不到的路」「十二、PageBg」及下方各条 ✓。

### 详情页播放（**用户定的规则** ✓）

- **续播**：**不管从哪个入口进来**（卡片 / 搜索 / 播放记录），只要播放记录里有这条视频就续播 ✓（用户 2026-10-03 定 ✓）
- **续到上次看的那一集** ✓（`PlayRecord.videoIndex`，建 switcher 时就应用 ⇒ 不闪第 1 集 ✓）
- **不续的三种情况**：没记录 ✓ 已播完 ✓ 剩 ≤5 秒 ✓
- **清晰度跟着这条视频记**（`PlayRecord.quality` ✓）：进页面读它 ✓、选完**立刻落盘** ✓、没选过就跟随站点默认 ✓
- **播放记录写法**：详情页是**唯一**归档点 ✓；上报 **2 秒一次 / 位置变化 ≥1 秒** ✓、落盘节流 **2 秒** ✓、
  **跳变（拖 / 点 / 滑进度条）绕过节流立刻落盘** ✓ —— 依据：上报间隔必须**小于**看门狗的 9 秒判卡阈值 ✓，
  否则"跳变还没上报就被判卡住 → 重试 → 从头开始" ✗
- ⚠️ 带 `keepAlive`（`AutomaticKeepAliveClientMixin`）的 State，**凡是持有"可被替换"的对象（feed / model），必须实现 `didUpdateWidget`** ✓
  —— 否则新实例没人挂监听 ⇒ 界面永不刷新 ✗（`home_page.dart` 踩过 ✓）
- 短片页播放器：`controls: NoVideoControls` ✓ —— **一改两治**：既去掉自带控制条，也解除它对手势层的抢占（否则竖滑换条失灵 ✓）

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

### 播放器（详情页 / 短片 / 全屏）

- **「跳走该不该记一笔、回来续播」的判据 = 用户意图，不是引擎状态** ✓ —— 详情页 RouteAware（`didPushNext`）**必须**读 `KpPlayer.userPaused`
  （= 用户自己按过暂停才为 true ✓），☠ **绝不能**读 `kp.value.playing`：那是**引擎**状态，而 **mpv 在缓冲期就会把 `playing` 报成 false** ✓；
  页面被压到栈下面之后引擎自己停掉也一样 ⇒ "用户明明在看"被判成"没在播" ✗ ⇒ 回来**不续播** ☠（用户实报过的 bug ✓）
- ⚠️ 换片（`didUpdateWidget`）/ 换档（`switchSources`）**先**调的那次内部 `pause()` 只为"旧源先停住、别抢声音" ✓ ——
  它会把 `_userPaused` 置成 true ✗ ⇒ 必须在 `KpPlayer.open()` 里**复位**（open 一律 `play: true` 起播 ⇒ 意图就是在播 ✓）
- **红线**：用户**自己**按过暂停（控制条 / 双击中间 / 全屏播放键）⇒ 跳走**不记** ⇒ 回来**仍然暂停** ✓（用户拍板 ⑦ ✓）
- 视频**已经播完**的那次（从没被用户暂停过）**不算"待续播"** ✓（判据里带 `!completed` ✓）

### 工具与流程坑（本机 Windows）

- ⚠️ 本机是 **Windows PowerShell 5.1**（不是 pwsh 7 ✓）：`-Encoding utf8NoBOM` 这类 **7.x 才有的枚举值会直接报错** ✗；
  要写"无 BOM 的 UTF-8"用 `[IO.File]::WriteAllLines($p, $lines, [Text.UTF8Encoding]::new($false))` ✓
- ☠ **`Get-Content -Raw` 默认按 GBK 解码 UTF-8 文件** ⇒ 中文注释会把它**后面紧跟的半角字符吞掉** ⇒ 括号复验会**数出假的不平衡** ✗
  ⇒ **读含中文的源码/文档一律显式 `-Encoding UTF8`** ✓（已踩过：差点把"文件缺一个 `)`"当成真事 ☠）
- ⚠️ PowerShell 里**把 `$(...)` 内联进双引号字符串**、以及**英文双引号嵌套**都容易把命令解析炸掉 ✗ ⇒ 拆开写、优先用单引号 ✓
- `git show HEAD:<file>` 经 PowerShell 管道取出后**按行拼接**，与 `Get-Content -Raw` 的**解码口径不同** ⇒ 两者的括号计数**不可直接比较** ✓

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
