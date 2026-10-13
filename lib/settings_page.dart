import 'dart:ui' show ImageFilter; // ★ 玻璃卡片：BackdropFilter 的模糊（material 不导出它，必须显式 import）
import 'package:flutter/material.dart';
import 'app_version.dart';
import 'error_log_page.dart';

import 'app_background.dart';
import 'app_bg.dart';
import 'bg_album_page.dart';
import 'detail_page.dart';
import 'online_album2_page.dart';
import 'online_album_page.dart';
import 'play_history_page.dart';
import 'play_record_tile.dart';
import 'settings.dart';
import 'site_error_log.dart'; // ★ 选图失败写公共错误日志 ✅（弹给用户的只有友好文案 ✅）
import 'sites.dart';

/// 设置页（改版：卡片分组 + 分段控件 + 开关 + 播放记录预览）。
///
/// 1:1 照模拟器 `viewSettings()`（sim/index.html）翻译。几个刻意一致的点：
/// - 卡片**没有白底**（透明）——背景图直接透出来，可读性靠**按背景明暗自适应
///   黑白字**（app_background.dart 的 kTxt/kTxtSub），**不加描边/光晕**
/// - 分段控件自绘（模拟器 `.seg` 的样子），不用 ChoiceChip
/// - 整页透明：外层 `AppBackground` 铺背景图，不透明底色会把它挡掉
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const Color _orange = Color(0xFFE8590C); // 主色（开关、主按钮）
  static const Color _deep = Color(0xFFD1550F); // 分段控件选中字色

  /// 本页依赖的三份状态。**必须建一次复用**：写在 build 里会每次重建都新建一个
  /// merged Listenable（旧监听被摘/新监听挂上），配合下面的 key 一起，
  /// 才不会在跳转那一帧把记录行整行重建（用户反馈「进全部记录时设置页闪一下」）。
  /// PlayHistory.i 也要听：看完视频回来，预览的进度/条数得是新的。
  static final Listenable _deps =
      Listenable.merge([AppSettings.i, AppBg.i, PlayHistory.i]);

  @override
  Widget build(BuildContext context) {
    // 整页跟着背景明暗重建：body 那层本来就在听 _deps，但**顶栏在 Scaffold 上**
    // （foregroundColor: kTxt），外面不再包一层的话标题不会跟着刷。
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => _pageView(context),
    );
  }

  Widget _pageView(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        systemOverlayStyle: kStatusOverlay,
        title: const Text('设置'),
        centerTitle: true,
        foregroundColor: kTxt, // 标题直接压在图上 → 跟明暗
      ),
      body: ListenableBuilder(
        listenable: _deps,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 22),
          children: [
            _recordsCard(context),
            const SizedBox(height: 14),
            _playCard(context),
            const SizedBox(height: 14),
            _bgCard(context),
            const SizedBox(height: 14),
            _logCard(context),
            const SizedBox(height: 18),
            // ✅ 版本号（用户 2026-10-03 要求：方便核对手机上是哪一版 ✓）
            Center(
              child: Text(
                '版本 $kAppVersion',
                style: TextStyle(fontSize: 12, color: kTxtSub),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  // ---------------- 卡片① 播放记录 ----------------

  Widget _recordsCard(BuildContext context) {
    final list = PlayHistory.i.records;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (list.isEmpty)
            // 一条都没有：整块只留这行小字（不显示头行的"0 条"）
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
              child: Text(
                '还没有播放记录',
                style: TextStyle(fontSize: 12, color: kTxtSub),
              ),
            )
          else ...[
            _head(
              icon: Icons.history,
              title: '播放记录',
              trailing: '${list.length} 条 ›',
              onTapTrailing: () {
                // 看：设置页入口被点（配合 [NAV] 路由日志确认页面确实开了）。
                if (AppSettings.i.logConsole) debugPrint('[UI] 进入 播放记录');
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PageBg(child: PlayHistoryPage()), settings: const RouteSettings(name: '播放历史')),
                );
              },
            ),
            // 预览只显示前 3 条；点「N 条 ›」进整页。
            // key 用记录去重键：列表内容变了也只做增量重建，封面不会被重挂载（闪一下的来源）
            for (final r in list.take(3))
              PlayRecordTile(
                key: ValueKey(r.key),
                record: r,
                onTap: () => _open(context, r),
              ),
          ],
        ],
      ),
    );
  }

  // ---------------- 卡片② 播放 ----------------

  Widget _playCard(BuildContext context) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _head(icon: Icons.play_circle_outline, title: '播放'),
          // ★ 2026-10-11（**用户拍板**）：切集"销毁重建 ⇄ 复用引擎"开关 —— 与下面那条**同款**（`_row` +
          //   `Switch.adaptive` + `_orange`），不加大按钮、不醒目化 ✅
          //   ★ 2026-10-11 改默认值：**默认 = 关（复用引擎）**（用户口径"切集时重建播放引擎设置默认关闭"）
          //     ⇒ 副标题同步改为如实口径（把"默认"挪到"关=复用"那一侧）；**标题/控件/样式/位置/间距/玻璃卡片一字未动** ✅
          //   ⚠️ 盘上已存的值优先：老用户手动开过 ⇒ 开关显示与播放行为仍按他存的那个走 ✅
          // ★ 2026-10-11（用户要求：**只调顺序**）：本条 = "播放"分组**第一个**（其下依次：硬件解码、播放缓冲大小）✅
          _row(
            title: '切集时重建播放引擎',
            // ★ 2026-10-12（**用户要求，照原文**）：
            //   `关=复用引擎、切集更快(默认)` / `开=销毁重建、更稳但是更慢`（第一行**去掉行尾分号** ✅）
            sub: '关=复用引擎、切集更快(默认)\n开=销毁重建、更稳但是更慢',
            trailing: Switch.adaptive(
              value: AppSettings.i.switchRebuildEngine,
              activeTrackColor: _orange,
              onChanged: (v) {
                if (AppSettings.i.logConsole) debugPrint('[UI] 切集重建引擎=${v ? "on" : "off"}');
                AppSettings.i.setSwitchRebuildEngine(v);
              },
            ),
          ),
          _divider(),
          // ⚠️ 用户 2026-10-05 拍板：**解码方式**三选一 ✓（改的是**播放器的硬件解码** ✓ 影响**所有站点** ✓）
          _row(
            title: '硬件解码',
            sub: '播放器的硬件解码方式（影响所有站点）',
          ),
          _seg(
            values: AppSettings.hwdecOptions,
            selected: AppSettings.i.hwdec,
            label: (v) => AppSettings.hwdecLabels[v],
            onPick: (v) {
              if (AppSettings.i.logConsole) debugPrint('[UI] 硬解=$v'); // ★ 诊断（出处 `settings_page.dart:172` ✓）
              AppSettings.i.setHwdec(v);
            },
          ),
          _note('自动＝按引擎默认；硬解失败会自动回落软解；软解最兼容、最吃 CPU。改完重进视频生效'),
          _divider(),
          _row(
            title: '播放缓冲大小',
            sub: '越大越抗卡、拖动越顺，但更吃内存',
          ),
          _seg(
            values: AppSettings.bufferOptions,
            selected: AppSettings.i.bufferMb,
            label: AppSettings.bufferLabel,
            onPick: (v) {
              if (AppSettings.i.logConsole) debugPrint('[UI] 缓冲=$v'); // ★ 诊断（出处 `settings_page.dart:159` ✓）
              AppSettings.i.setBufferMb(v);
            },
          ),
          _note('改完重进视频生效；1G 在低内存机型上可能被杀进程'),
          _divider(),
          _row(
            title: '快进 / 快退',
            sub: '双击画面左侧后退、右侧快进，一次跳转的时长',
          ),
          _seg(
            values: AppSettings.stepOptions,
            selected: AppSettings.i.step,
            label: (v) => '$v 秒',
            onPick: (v) {
              if (AppSettings.i.logConsole) debugPrint('[UI] 双击档=$v'); // ★ 诊断（只加打印 ✓ 不改逻辑 ✓）—— 出处 `settings_page.dart:138` ✓
              AppSettings.i.setStep(v);
            },
          ),
          _divider(),
          _row(
            title: '自动播放下一集',
            sub: '一篇里有多个视频时，播完自动切下一个',
            trailing: Switch.adaptive(
              value: AppSettings.i.autoNext,
              activeTrackColor: _orange,
              onChanged: (v) {
                if (AppSettings.i.logConsole) debugPrint('[UI] 自动下一集=${v ? "on" : "off"}'); // ★ 诊断（出处 `settings_page.dart:147` ✓）
                AppSettings.i.setAutoNext(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- 卡片③ 背景图 ----------------

  Widget _bgCard(BuildContext context) {
    final custom = AppBg.i.isCustom;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _head(icon: Icons.image_outlined, title: '背景图'),
          _albumEntry(context),

          // ★ 2026-10-05 用户要求：在「从相册选择 / 恢复默认」上方**加两个按钮** ✓
          //   ✅ 现状：两个按钮**都已接线** ✓ —— 分别打开 在线图集1 / 在线图集2 ✓（各自带 `PageBg` ✓）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: _button(
                    label: '在线图集1',
                    // ★ 2026-10-05：接线 ✓（推送时**必须包 PageBg** ✓ —— 本页其它 push 点同款 ✓）
                    onTap: () {
                      // 看：设置页入口被点（配合 [NAV] 路由日志确认页面确实开了）。
                      if (AppSettings.i.logConsole) debugPrint('[UI] 进入 图集1');
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          // ★ 2026-10-05【⑥ 页面起名】只加 `settings:` ✓（builder/PageBg 一字未动 ☠）
                          settings: const RouteSettings(name: '图集1'),
                          builder: (_) => const PageBg(child: OnlineAlbumPage()),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _button(
                    label: '在线图集2',
                    // ★ 2026-10-05：接线 ✓（照本页既有 push 写法 ✓ **必须包 PageBg** ✓）
                    onTap: () {
                      // 看：设置页入口被点（配合 [NAV] 路由日志确认页面确实开了）。
                      if (AppSettings.i.logConsole) debugPrint('[UI] 进入 图集2');
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          // ★ 2026-10-05【⑥ 页面起名】只加 `settings:` ✓（builder/PageBg 一字未动 ☠）
                          settings: const RouteSettings(name: '图集2'),
                          builder: (_) => const PageBg(child: OnlineAlbum2Page()),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: _button(
                    label: '从相册选择',
                    onTap: () {
                      if (AppSettings.i.logConsole) debugPrint('[UI] 选背景图'); // ★ 诊断（出处 `settings_page.dart:231` ✓）
                      _pickBg(context);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _button(
                    label: '恢复默认',
                    onTap: custom
                        ? () {
                            if (AppSettings.i.logConsole) debugPrint('[UI] 清背景'); // ★ 诊断（出处 `settings_page.dart:238` ✓ `custom` 判断未变 ✓）
                            AppBg.i.clear();
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ),
          _note('从相册选择背景不保存在图集，想储存用就在图集里添加'),
        ],
      ),
    );
  }

  /// 图集入口行（整行可点 → 图集页）。照模拟器 `.srec.bgentry` 定稿的样子：
  /// 左 = **当前背景**的竖版缩略图（内置默认/单选/图集图，谁在用显示谁），
  /// 右 = 「背景图集」+「当前：… / N 张 ›」两行；文字块与缩略图**垂直居中**，
  /// 两行文字在文字列内**居中**，和缩略图间距 16（比播放记录行的 10 宽）。
  Widget _albumEntry(BuildContext context) {
    final sub = TextStyle(fontSize: 11, color: kTxtSub); // 同模拟器 .srec .meta
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PageBg(child: BgAlbumPage()), settings: const RouteSettings(name: '背景相册')),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: SizedBox(
                width: 64,
                height: 110,
                child: Container(
                  color: const Color(0xFFECEFF3), // 没解码完时的底（同模拟器）
                  child: Image(
                    // ⚠️ 裸 Image(image:) 构造器**没有** cacheWidth 参数（只有 .file/.asset/.network
                    // 那些便捷构造器才有）—— CI 实测报 "No named parameter with the name 'cacheWidth'"。
                    // 等价写法是 ResizeImage 包一层 provider（cacheWidth 内部也是这么做的），
                    // 缓存键会带上尺寸，跟整页大图各自解码、互不影响。
                    image: ResizeImage(AppBg.i.image, width: 200),
                    fit: BoxFit.cover,
                    gaplessPlayback: true, // 换图时别闪白
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('背景图集',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: kTxt)),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('当前：${AppBg.i.isDefault ? '内置默认' : '自选图片'}',
                          style: sub),
                      const SizedBox(width: 8),
                      Text('${AppBg.i.album.length} 张 ›', style: sub),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 复用的小零件 ----------------

  /// 卡片：**iOS「inset grouped」分组框 + 玻璃质感**（用户 2026-10-11 要求："① 玻璃质感半透明（毛玻璃模糊）
  ///   ② 圆角再大一点"）。
  ///   ✅ **结构 = 只"包住"内容**：`ClipRRect > BackdropFilter > DecoratedBox > child`
  ///      —— **绝不引入覆盖层**、**绝不**成为上层兄弟层；`_head` 仍留在各组 children 首位（**无 `head:` 参数**）✅
  ///   ✅ **命中测试不变（三个 widget 都 `hitTestSelf == false`，不吃点击）**，依据：
  ///        · `ClipRRect`  → `RenderClipRRect` 是 **`RenderProxyBox`** 系（只裁剪绘制，不 opaque）
  ///        · `BackdropFilter` → `RenderBackdropFilter` 同属 **`RenderProxyBox`** 系（只影响绘制/合成）
  ///        · `DecoratedBox` → `RenderDecoratedBox` 同属 **`RenderProxyBox`**（对比：`ColoredBox` 用的是
  ///          `RenderProxyBoxWithHitTestBehavior(behavior: opaque)` ⇒ **它才吃点击** ☠ —— 本卡片**没用**它）
  ///      ⇒ 子节点的 `GestureDetector`/`Switch`/`_seg` 命中区**逐字不变** ✅
  ///   ✅ **不加 margin / padding**（守"间距细节不动"）；**圆角 18**（12 → 18：玻璃卡片比实心卡片更适合大圆角；
  ///      18 与 iOS inset-grouped 的观感一致，20 会显得偏"药丸"⇒ 取 18）
  ///   ✅ 颜色（**都从本页既有色系取，只改透明度**，未自造新色号）：
  ///        · 半透明白底 `Colors.white` @ **0.38**（介于 0.3~0.5 档中段：既能透出背景/模糊，又不糊字）
  ///        · 浅色半透明细边 `Colors.white` @ **0.35**、0.5px（玻璃感的关键；**不再用** 黑 0.1）
  ///        · 模糊 `ImageFilter.blur(sigmaX: 14, sigmaY: 14)`（12~18 档取中）
  ///   ⚠️ 顺序调整（切集重建 → 硬件解码 → 播放缓冲大小 → 快进/快退 → 自动播放下一集）**保留** ✅
  Widget _card({required Widget child}) {
    // ★ 用户 2026-10-12："边框可以加阴影吗。现在纯白背景都看不出框了"
    //   ⇒ 阴影必须画在 **ClipRRect 外面**（否则会被裁剪掉）⇒ 最外层再套一个 DecoratedBox 专门画阴影
    //   ⇒ 纯白底上靠这圈阴影就能看出卡片边界；深色/照片底上仍靠里面那圈白边 ✅
    //   ⚠️ 外层也是 `DecoratedBox`（`hitTestSelf == false`，不吃点击）✅
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26), // ★ 用户"再圆一点"：18 → 26（必须包住 BackdropFilter，否则圆角外也会被糊）
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4), // ★ 用户"毛玻璃再低一点"：8 → 4（之前"有点糊"）
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12), // ★ 用户"让卡片有点存在感"：0.00 → 0.12（淡淡的底）
              borderRadius: BorderRadius.circular(26), // ★ 与 ClipRRect 保持一致（18 → 26）
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5), // ★ 用户"白边加一点"：0.28 → 0.5（深色底上靠它定边界）
                width: 0.5,
              ),
            ),
            // ★ 用户 2026-10-12："分组的底部距离跟分组标题的顶部距离设置一样"
            //   ⇒ 标题上方的间距 = `_head` 自己的 `fromLTRB(16, 14, 16, 2)` 的 **14**
            //   ⇒ 卡片底部补一个 **14** 的底部内边距（此前是 0 ⇒ 末行文字贴着卡片底边/圆角，"文字快被挡住"）
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: child, // ★ 只包住：命中测试照旧落在子节点上（四个 widget 都不吃点击）
            ),
          ),
        ),
      ),
    );
  }

  /// 诊断入口：**错误日志**（用户 2026-10-03 要求 ✓ —— 点开就能看 / 能清 / 能复制 ✓）
  Widget _logCard(BuildContext context) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _head(icon: Icons.bug_report_outlined, title: '诊断'),
          // ★ 2026-10-05（用户拍板"加个开关"✓）：**记录控制台日志（调试用）** —— 默认关 ✓
          //   ⚠️ 位置（2026-10-05 用户口径）：**开关在「错误日志」按钮上方** ✓（先开关、再去看日志 ✓）
          //   ⚠️ 形态（2026-10-05 用户口径）：**与上面「自动播放下一集」那行一模一样** ✓ —— 用本页的 `_row`
          //      （`title` + `sub` + `trailing`，样式由 `_row` 自己给 ⇒ **这里不写 TextStyle** ✓）；
          //      开关配色同款 `activeColor: _orange` ✓。原来那套系统标准件 `SwitchListTile`（自带缩进/系统默认色）已撤 ✓。
          //   ⚠️ 状态 + 持久化都在 `AppSettings` 里（`logConsole` / `setLogConsole` ✓ 走 SharedPreferences ✓ 已在别处落好 ✓）；
          //   本页能自动刷新 ✓ 依据 = `:34 Listenable.merge([AppSettings.i, …])` ✓ ⇒ 一拨开关这里就重建 ✓
          _row(
            title: '记录控制台日志（调试用）',
            sub: '打开后控制台打印会记进错误日志页（默认关）',
            trailing: Switch.adaptive(
              value: AppSettings.i.logConsole,
              activeTrackColor: _orange,
              onChanged: (v) {
                // ★ 2026-10-05（本次修 ✓）：**先落状态、再打日志** ✗ —— `setLogConsole` 的 `_logConsole = v` 是
                //   **同步**赋值（`settings.dart:122` ✓，首次 `await` 在 `:125` 之后 ✓）⇒ 紧接着这行 debugPrint
                //   看到的就是**新值** ✓：**打开那一下这行必定进日志** ✓（原来先打后设 ⇒ 打开时按旧值 `false` 被吞 ✗）。
                //   ⚠️ 代价：**关闭那一下这行不会留下** ✗（关掉后 debugPrint 第一句就 return ✓）—— 这是开关语义本身 ✓，不是漏 ✓。
                AppSettings.i.setLogConsole(v);
                if (AppSettings.i.logConsole) debugPrint('[UI] 控制台日志=${v ? "on" : "off"}（本条只在打开那下可见 ✓）');
              },
            ),
          ),
          // ★ 2026-10-05（用户口径 ✓）：**宽度 ≈ 现在的一半 + 居中** ✗ —— 原来这个按钮挂在
          //   `Column(crossAxisAlignment: CrossAxisAlignment.stretch)` 下 ⇒ 被**拉满整行** ☠（用户："太长"✓）；
          //   ⚠️ **只动宽度 + 对齐** ✓（高度 / 文案「错误日志」/ 点击行为 / 字号**一个字没动** ☠；
          //      上方那个开关行也没碰 ✓ 它仍整行 ✓）。用现成件 `FractionallySizedBox` ✓ 不自造 ✗。
          //   （2026-10-05 用户口径：**按钮在开关下方** ✓）
          FractionallySizedBox(
            widthFactor: 0.5, // 宽度 = 现在的 50% ✓
            alignment: Alignment.center, // ★ 居中（**不是 centerLeft** ☠）
            child: _button(
              label: '错误日志',
              onTap: () {
                // 看：设置页入口被点（配合 [NAV] 路由日志确认页面确实开了）。
                if (AppSettings.i.logConsole) debugPrint('[UI] 进入 错误日志');
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PageBg(child: ErrorLogPage()), settings: const RouteSettings(name: '错误日志')),
                );
              },
            ),
          ),
          _note('出错时先打开上面的开关、再复现一次即可看到输出（关着时不记录）'),
        ],
      ),
    );
  }


  /// 标题行：浅橙圆角方块 + 图标 + 标题（右侧可选一个可点的小字）
  Widget _head({
    required IconData icon,
    required String title,
    String? trailing,
    VoidCallback? onTapTrailing,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFFDEDE6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: _deep),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: kTxt),
            ),
          ),
          if (trailing != null)
            GestureDetector(
              onTap: onTapTrailing,
              child: Text(
                trailing,
                style: TextStyle(fontSize: 12, color: kTxtSub),
              ),
            ),
        ],
      ),
    );
  }

  /// 一行设置项：标题 + 说明（右侧可选控件，如开关）
  Widget _row({
    required String title,
    required String sub,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 15, color: kTxt)),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 12,
                    color: kTxtSub,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing,
          ],
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      height: 1,
      color: const Color(0x1F000000),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    );
  }

  Widget _note(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: kTxtSub, height: 1.5),
      ),
    );
  }

  /// 分段控件（自绘）：灰底圆角条 + 等分项，选中项白底、深橙字、w600
  Widget _seg({
    required List<int> values,
    required int selected,
    required String Function(int v) label,
    required void Function(int v) onPick,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F2F5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            for (final v in values)
              Expanded(
                child: GestureDetector(
                  onTap: () => onPick(v),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    alignment: Alignment.center,
                    decoration: v == selected
                        ? BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x1F111827),
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ],
                          )
                        : null,
                    child: Text(
                      label(v),
                      style: TextStyle(
                        fontSize: 13,
                        color: v == selected ? _deep : const Color(0xFF4B5563),
                        fontWeight:
                            v == selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 按钮：主按钮橙底白字 / 次按钮浅灰底；`onTap == null` = 置灰不可点
  Widget _button({required String label, VoidCallback? onTap}) {
    final on = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? _orange : const Color(0xFFEDEEF2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: on ? Colors.white : const Color(0x8A000000),
          ),
        ),
      ),
    );
  }

  // ---------------- 动作 ----------------

  /// 从相册换背景图；取消什么都不做，失败提示
  Future<void> _pickBg(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AppBg.i.pickFromGallery();
    } catch (e) {
      // ★ 2026-10-08（用户批准 ✅）：**别把英文异常原文弹给用户** ☑️ —— 原文进错误日志 ✅
      await SiteErrorLog.log('选图', e);
      messenger.showSnackBar(const SnackBar(
          duration: Duration(seconds: 1), // ★ 2026-10-10（用户批准）：默认 4 秒 → 1 秒
          content: Text('选图失败，请再试一次')));
    }
  }

  /// 点一条记录 = 回该篇详情续播（和 PlayHistoryPage._open 同一套逻辑）
  void _open(BuildContext context, PlayRecord r) {
    // 站点名反查 SiteEntry（记录按站点名存）；站点改名/下线就提示
    final hit = kSites.where((s) => s.name == r.site).toList();
    if (hit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            duration: const Duration(seconds: 1), // ★ 2026-10-10（用户批准）：默认 4 秒 → 1 秒
            content: Text('找不到站点「${r.site}」，这条记录打不开了')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '详情页'),
        builder: (_) => PageBg(child: DetailPage(
          site: hit.first,
          baseUrl: r.url,
          listCover: r.cover,
          // 看完的从头播：否则跳到结尾会立刻又"看完"，等于看不了
          initialPosition: r.finished ? null : r.position,
          initialVideoIndex: r.videoIndex,
        )),
      ),
    );
  }
}
