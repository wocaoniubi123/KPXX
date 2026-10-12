// =============================================================================
// 站点管理（★ 2026-10-12 用户新需求 ✅）
//
// 【用户原话（两遍口径一致）】"底栏tab长按点播进入站点管理界面，站点用列表显示，点播分组，直播分组。
//   站点后面加个开关（开显示站点按钮入口，关隐藏按钮入口）长按列表站点可以在分组内上下移动，
//   必须要灵敏。改完站点管理首页实时生效"
//
// 【本文件 = 唯一的"站点展示清单"读取口】首页宫格（`main.dart` 的 `ModuleGridPage`）与
//   直播宫格（`LiveGridPage`）**只调** [visibleSitesOf] ✅ —— 不在页面里各读各的；
//   "改完实时生效" = `AppSettings.i`（`ChangeNotifier`）+ 那两页的 `ListenableBuilder` ✅。
//
// 【分组口径（🛢️ 实锤，不是猜）】看 `SiteEntry.group`：
//   · 默认 = `SiteGroup.module`（点播）—— `lib/sites.dart:203`（构造默认值）
//   · 直播站写 `group: SiteGroup.live` —— `lib/sites.dart:30-36`（enum）+ `:323-325`（`kSiteLive` 的注释）
//   · 原来的两个消费点：`main.dart:285`（`.group == SiteGroup.module`）/ `:339`（`== SiteGroup.live`）
//     ⇒ 本次把这两处**换成** [visibleSitesOf] ✅（其它地方一个不动 ☑️）
//
// 【隐藏语义（用户口径）】开关只藏**入口按钮** ✅ —— 不动站点数据、不动收藏、不动播放记录；
//   隐藏后：收藏页/播放记录/设置页里那条**照样能点进详情** ✅（入口只是不在宫格里出现）。
//
// 【拖拽为什么"灵敏"】见 [_GroupList] 里 `ReorderableDelayedDragStartListener(delay: 150ms)`
//   + 每条列表**满高**（内建边缘自动滚动）的注释 ✅。
// =============================================================================

import 'dart:async';

// ★ 2026-10-12（用户反馈"0.5 秒慢了" ✅）：短延时起拖要用的两个识别器类型 ——
//   `MultiDragGestureRecognizer`（覆写的返回类型）/ `DelayedMultiDragGestureRecognizer`（**可传 delay** ✅）
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'app_bg.dart';
import 'app_background.dart';
import 'settings.dart';
import 'sites.dart';

/// 组内**合并顺序**：先按用户自定义顺序（只认本组、只认还存在的站名），
/// 再把"自定义顺序里没有的"站点（= **新加的站** / 老配置里没记过的）**按 `kSites` 原顺序追加在后** ✅
/// ⇒ 新增站点不会丢、也不会插进中间乱掉 ☑️
List<SiteEntry> orderedSitesOf(SiteGroup group) {
  final all = kSites.where((e) => e.group == group).toList();
  final saved = AppSettings.i.siteOrderOf(group.name);
  if (saved.isEmpty) return all; // 没存过 ⇒ 原顺序 ✅
  final byName = {for (final e in all) e.name: e};
  final out = <SiteEntry>[];
  final used = <String>{};
  for (final n in saved) {
    final e = byName[n];
    if (e != null && used.add(n)) out.add(e);
  }
  for (final e in all) {
    if (used.add(e.name)) out.add(e);
  }
  return out;
}

/// ★★ **统一读取口**：某个宫格"该显示哪些站点、按什么顺序" ——
/// = [orderedSitesOf] 去掉**被隐藏**的（`AppSettings.i.isSiteHidden` ✅）
///
/// ⚠️ 2026-10-12：原先这里记着"**柚子短剧默认隐藏**"的特例 —— 该特例已随**柚子站点整体删除**
///   一起去掉 ✅（`settings.dart` 里那段一次性种子逻辑已删）；现在**没有任何默认隐藏**：
///   隐藏只来自用户在管理页的手动开关 ✅。
List<SiteEntry> visibleSitesOf(SiteGroup group) =>
    orderedSitesOf(group).where((e) => !AppSettings.i.isSiteHidden(e.name)).toList();

/// 站点管理页（**长按底栏「设置」进** ✅ —— 用户 2026-10-12 更正：长按的是「设置」那一格，
///   不是「点播」；入口挂在 `main.dart` 的底栏长按层 ✅）：**点播 / 直播 两个分组**，每组一条列表 ✅
class SiteManagePage extends StatelessWidget {
  const SiteManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent, // 与全 App 一致：让根层背景图透出来 ✅
        appBar: AppBar(
          systemOverlayStyle: kStatusOverlay,
          title: const Text('站点管理'),
          centerTitle: true,
          foregroundColor: kTxt,
          bottom: const TabBar(
            indicatorColor: Color(0xFFE8590C),
            dividerColor: Colors.transparent,
            labelColor: Color(0xFFE8590C),
            unselectedLabelColor: Color(0xFF3A3A3A),
            tabs: [Tab(text: '点播'), Tab(text: '直播')],
          ),
        ),
        // ⚠️ 两个分组 = **两个 tab**（各自一条**满高**的 ReorderableListView）——理由：
        //   ① `ReorderableListView` 的"拖到边缘带动滚动"是它内建在拖拽手势里的（`EdgeDraggingAutoScroller` ✓）
        //      ⇒ **满高列表**才有自动滚动；把两条 `shrinkWrap` 列表塞进一个 ScrollView 会让它失效 ☠，
        //      而用户要求里"必须要灵敏"的关键就是这条 ✅；
        //   ② 每组站点约 16 / 1 条 ⇒ 同屏两段会很挤 ✅（分组口径本身由 TabBar 表达清楚了 ✅）。
        body: const TabBarView(
          children: [
            _GroupList(group: SiteGroup.module),
            _GroupList(group: SiteGroup.live),
          ],
        ),
      ),
    );
  }
}

/// ★ 起拖阈值（毫秒）—— **用户 2026-10-12 反馈"0.5 秒确实慢了一点"** ⇒ 定 **180ms**（区间 150~200 ✅）
///   ⚠️ 以后再调**只改这一个常量** ✅；不建议低于 ~120ms（再短就与"滚动起手"抢手势了 ☑️）
const int _kDragDelayMs = 180;

/// ★ 2026-10-12：**短延时起拖的站名区**（替代框架默认 ≈500ms 的长按起拖 ✅）
///
/// 【为什么走"子类 + 只换识别器"这条（依据 = **SDK 源码**，不是记忆 🛢️）】
///   `flutter/lib/src/widgets/reorderable_list.dart`：
///   · `ReorderableDragStartListener`（:1408）= `StatelessWidget`，`build` 是
///     `Listener(onPointerDown: … _startDragging)` ⇒ `_startDragging()`（:1452-1460）⇒
///     `SliverReorderableList.maybeOf(context)?.startItemDragReorder(index:, event:, recognizer: createRecognizer()…)` ✅
///   · `createRecognizer()` 是**公开且可覆写**的（:1447-1450，`@protected`，文档原文
///     *"subclasses can use this to customize the drag start gesture"*）⇒ **子类只改这一处** ✅
///   · `ReorderableDelayedDragStartListener`（:1477-1493）只是把它换成
///     `DelayedMultiDragGestureRecognizer(debugOwner: this)` —— **不带 delay** ⇒ 用默认
///     `kLongPressTimeout`（≈500ms，正是用户嫌慢的那个 ☠）
///   ⇒ 我们**不碰任何内部/私有 API**（私有 `_DragInfo`、`startItemDragReorder` 都不用自己调 ✅），
///     只换成**带 180ms 延时**的同款识别器 ✅
///
/// 【滚动为什么不受影响（依据 = SDK `gestures/multidrag.dart` 🛢️）】
///   ① `DelayedMultiDragGestureRecognizer`（:583-592）构造里有 `this.delay = kLongPressTimeout`
///      ⇒ **可传自定义延时** ✅（这是我们能做的前提）；
///   ② 它的指针状态 `_DelayedPointerState.checkForResolutionAfterMove()`（:532-547）：
///      **计时器还没到点时，指针位移一旦超过 `computeHitSlop`（kTouchSlop）就 `resolve(rejected)`
///      并停表** ⇒ **起手就是滚动**，不会被吃掉 ✅；
///   ③ 到点那一刻还有断言兜底（:502-505 `assert(pendingDelta.distance <= hitSlop)`）⇒ 只有"没怎么动"
///      才真起拖 ✅；
///      抬手（普通点击）⇒ 由手势竞技场按点击判定，不会起拖 ✅（**这条未做运行时验证**，见回报 ☑️）
///   ④ 我**没有**把整行改成"立即起拖"（那才会吃掉滚动 ☠ —— 备选 2 的代价：要么留窄条才能滚 ☹，要么滚不动）
class _ShortDelayDragStartListener extends ReorderableDelayedDragStartListener {
  const _ShortDelayDragStartListener({
    required super.index,
    required super.child,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() =>
      DelayedMultiDragGestureRecognizer(
        delay: const Duration(milliseconds: _kDragDelayMs), // ★ 180ms ✅
        debugOwner: this,
      );
}

/// 一个分组 = 一条可拖拽列表（每行 = 图标 + 站名 + 行尾开关 ✅）
class _GroupList extends StatelessWidget {
  const _GroupList({required this.group});

  final SiteGroup group;

  /// 拖完一次 ⇒ 存**整组**的新顺序（`AppSettings` 先改内存 + notify ⇒ 首页立刻生效 ✅）
  ///
  /// ⚠️ 用 **`onReorderItem`**（不是已废弃的 `onReorder` ☠ —— `flutter analyze` 在本版 Flutter 上
  ///   实测 `onReorder` 报 `deprecated_member_use`（after v3.41.0）⇒ 换新回调 ✅）。
  ///   两者**下标语义不同**（搞错就错位 ☠）：
  ///   · `onReorder` = "插到该位置**之前**" ⇒ 传统写法要 `if (newIndex > oldIndex) newIndex -= 1`；
  ///   · **`onReorderItem` 已经把"被移走那一项"扣掉了**（回调文档原文：*adjusts the newIndex parameter
  ///     for a removed item at the oldIndex*）⇒ **这里绝不能减 1** ✅。
  void _move(List<SiteEntry> list, int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final names = <String>[for (final e in list) e.name];
    final moved = names.removeAt(oldIndex);
    names.insert(newIndex.clamp(0, names.length), moved); // 越界保护：clamp 到 [0, length] ✅
    if (AppSettings.i.logConsole) {
      // ⚠️ 只打组名 + 下标 + 名字长度（不打完整名单 ☠ 与全项目日志口径一致）
      debugPrint('[SITE] 拖动 组=${group.name} $oldIndex→$newIndex 名长=${moved.length}');
    }
    unawaited(AppSettings.i.setSiteOrder(group.name, names));
  }

  /// 站点图标：与首页宫格 `_SiteTile`（`main.dart:384-410`）**同一套观感**（小一号 ✅）
  Widget _icon(SiteEntry e) {
    return Container(
      width: 40,
      height: 40,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // ★ 2026-10-12（用户口径 ✅）：图标**只走内置资源**（`assetIcon` ⇒ `Image.asset`，**零网络** ✅）；
        //   没有内置图标 ⇒ 走**既有**的"名字首字色块"兜底（不新增逻辑，同 `main.dart` 的 `_SiteTile` ✅）
        color: e.assetIcon.isEmpty ? e.color : Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: e.assetIcon.isEmpty
          ? Center(
              child: Text(
                e.name.isEmpty ? '?' : e.name.substring(0, 1),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(6),
              // 本地资源、零网络 ✅（与宫格同一份 `assets/site_icons/xxx.png` ✅）
              child: Image.asset(e.assetIcon, fit: BoxFit.contain),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ★ 监听 `AppSettings.i`（开关/拖动都会 notify ⇒ 列表跟随 ✅）+ `AppBg.i`（文字跟明暗 ✅）
    return ListenableBuilder(
      listenable: Listenable.merge([AppSettings.i, AppBg.i]),
      builder: (context, _) {
        // ⚠️ 管理页**不按隐藏过滤**（藏起来的站也要能再打开 ✅）——只有顺序走 `orderedSitesOf` ✅
        final list = orderedSitesOf(group);
        if (list.isEmpty) {
          return Center(
            child: Text('这一组还没有站点',
                style: TextStyle(color: kTxtSub, fontSize: 13)),
          );
        }
        return ReorderableListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          // ★ 关掉系统默认拖拽手柄（默认手柄主要给桌面、手机上没有 ☠）⇒ 整行自己做启动区 ✅
          buildDefaultDragHandles: false,
          itemCount: list.length,
          onReorderItem: (o, n) => _move(list, o, n),
          itemBuilder: (context, i) {
            final e = list[i];
            final shown = !AppSettings.i.isSiteHidden(e.name);
            return Padding(
              // 稳定身份（拖拽/增删都不串行）
              key: ValueKey('${group.name}|${e.name}'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                children: [
                  // ★ 拖拽启动区 = **整行主体**（图标 + 站名），**不含**右侧 Switch ⇒
                  //   ① 图标 = 立即起拖（见下面 ①，对应用户"灵敏" ✅）；站名区 = 长按起拖（见 ②）；
                  //   ② 点右侧 Switch 只切开关，**不会**被拖拽抢走（两者在 Row 里是并列的兄弟节点 ✅，
                  //      Switch 自己吃掉点击手势 ✅ —— 谁都不抢谁 ☑️）。
                  Expanded(
                    child: Row(
                      children: [
                        // ★ ① 图标 = **立即拖拽手柄**（不用等长按 ⇒ 对应用户"必须要灵敏" ✅）：
                        //   `ReorderableDragStartListener` 走 `ImmediateMultiDragGestureRecognizer` ⇒
                        //   按住图标稍微一挪就起拖 ✅；范围只有 40×40 ⇒ **不会抢走"上下滑动列表"**
                        //   （在别处滑动照样滚 ✅）。
                        ReorderableDragStartListener(index: i, child: _icon(e)),
                        const SizedBox(width: 12),
                        // ★ ② 站名区 = **180ms 短延时起拖**（用户 2026-10-12："0.5 秒慢了" ✅）——
                        //   用的是**自己的** [_ShortDelayDragStartListener]（只把识别器换成带 delay 的那款 ✅）:
                        //   · 起拖比框架默认快 ≈320ms（500 → **180ms**，见 `_kDragDelayMs` ✅）；
                        //   · 指针一动超过 `kTouchSlop` ⇒ 识别器自动放弃 ⇒ **上下滚动照旧** ✅（依据见该类注释）。
                        Expanded(
                          child: _ShortDelayDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                e.name.isEmpty ? e.hosts.join('/') : e.name,
                                style: TextStyle(
                                    color: kTxt,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ★ 开关（**位置未动**）：开 = 显示入口；关 = 隐藏入口（只影响宫格入口 ✅ 不动数据 ✅）
                  // ★ 2026-10-12（**用户口径**："按钮颜色改成设置页按钮的颜色" ✅）：与设置页的开关**同款同色** ——
                  //   依据：`settings_page.dart:28` `static const Color _orange = Color(0xFFE8590C); // 主色（开关、主按钮）`
                  //   + 那边三处开关都是 `Switch.adaptive(…, activeTrackColor: _orange, …)`
                  //     （`settings_page.dart:144-146` / `:202-204` / `:447-449` ✅）。
                  //   ⚠️ 那个常量是 `settings_page.dart` 的**私有**字段 ⇒ 这里按全仓既有做法**内联同值** ✅
                  //     （全仓主色一直是内联使用、没有共享常量 ☑️）；**只改颜色**，开关语义/拖拽区/布局一字未动 ✅。
                  Switch.adaptive(
                    value: shown,
                    activeTrackColor: const Color(0xFFE8590C), // ★ 与 settings_page.dart 的 _orange 同值
                    onChanged: (v) =>
                        unawaited(AppSettings.i.setSiteHidden(e.name, !v)),
                  ),
                  // ★★ 2026-10-12（**用户要求 + 两处纠正** ✅）：
                  //   · 原话："站点管理的列表后面加一个可移动的那种图标，让人一眼能看出是可移动的"；
                  //   · 纠正 ①："**加在按钮后面**"⇒ 位置 = **整行的最后一个元素**（在 `Switch` **之后** ✅，
                  //     开关本身位置没动 ✅）；行内顺序 = `[站点图标] [站名] [Switch] [≡]` ✅；
                  //   · 纠正 ②："你这个图标也不对啊，应该是那种**很多横条的图标**"——`Icons.drag_handle`
                  //     只有**两条**横线 ⇒ 换成 **`Icons.reorder`（三条横线，"排序"语义）** ✅；
                  //     （同为三条横线的候选：`Icons.menu`（语义是"菜单"）/ `Icons.dehaze`（三条且中间一条偏短）
                  //      —— 若实机看更喜欢哪一个，**只改这一行的图标名**即可 ☑️）
                  //   · 其余不变：本体 20、次要色 `kTxtSub`（`app_background.dart:56` 的 getter ✅，**不 const**）、
                  //     命中区 34×34（≥32 ✅）、**立即起拖**（与站点图标同款 ✅）。
                  //   ⚠️ 与 `Switch` 在 `Row` 里仍是**并列兄弟**（≡ 在开关**之后**、互不嵌套 ✅）
                  //     ⇒ 点开关依旧只切开关、不会被拖拽抢 ✅。
                  ReorderableDragStartListener(
                    index: i,
                    child: SizedBox(
                      // ⚠️ 这里**不能**写 `const`：`kTxtSub` 是 **getter**（随背景明暗切换 ✅）⇒ 非常量表达式 ☠
                      width: 34,
                      height: 34,
                      child: Icon(Icons.reorder, size: 20, color: kTxtSub),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
