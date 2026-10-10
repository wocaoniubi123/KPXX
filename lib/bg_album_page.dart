import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import 'app_background.dart';
import 'app_bg.dart';
import 'site_error_log.dart'; // ★ 选图失败写公共错误日志 ✅（弹给用户的只有友好文案 ✅）

/// 背景图集（设置页「背景图集 N 张 ›」进来）。照模拟器 `viewAlbum()` 定稿的样子：
/// - 行**全透明**（背景图从行间透出来）、**没有分割线**，行与行靠间距分开
/// - 左 = 竖版缩略图 64×110 / 圆角 9 / cover；右 = 加入时间（年月日时）
/// - **当前应用那条**：淡橙底 + 左侧 3px 橙条 + 右侧橙色 ✓
/// - 点一条 = **立即应用**（不跳页）；**左滑露出「导出 / 删除」两个按钮**，
///   点按钮才生效（用户明确要求：左滑不能直接删，要有余地）
/// - 导出 = 存进系统相册（`gal`；模拟器那边没有相册，用浏览器下载代替）
/// - 删掉当前在用的那张 → 切回内置默认图（提示一句）
/// - 文字色走 [kTxt] / [kTxtSub]（深色图白字 / 浅色图深字）
class BgAlbumPage extends StatelessWidget {
  const BgAlbumPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 整页跟着背景明暗重建（文字色读 kTxt/kTxtSub；应用/删除后也要重画）
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => _pageView(context),
    );
  }

  Widget _pageView(BuildContext context) {
    final album = AppBg.i.album;
    return Scaffold(
      backgroundColor: Colors.transparent, // 外层 PageBg 已铺背景图，别挡掉
      appBar: AppBar(
        systemOverlayStyle: kStatusOverlay,
        title: const Text('背景图集'),
        centerTitle: true,
        foregroundColor: kTxt, // 返回键 / ＋ / 标题都跟着背景明暗
        actions: [
          IconButton(
            tooltip: '添加背景',
            icon: const Icon(Icons.add),
            onPressed: () => _add(context),
          ),
        ],
      ),
      body: album.isEmpty
          ? _note('图集是空的 —— 点右上角「＋」添加背景（从相册多选，选完直接进图集）\n\n'
              '[诊断] ${AppBg.i.diagnose()}')
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              // 末项固定是底部说明（同模拟器图集页列表下面那行小字）
              itemCount: album.length + 1,
              itemBuilder: (context, i) => i == album.length
                  ? _note('点一下立即应用；左滑一行露出「导出 / 删除」—— '
                      '导出是存进系统相册；删掉当前在用的那张会切回内置默认图')
                  : _row(context, i, album[i]),
            ),
    );
  }

  /// 一行：缩略图 + 加入时间（+ 当前那条的 ✓）。
  /// 左滑的位移/吸附由 [_SwipeRow] 管，这里只负责内容和三个动作。
  Widget _row(BuildContext context, int i, BgItem it) {
    final on = AppBg.i.currentPath == it.file;
    return _SwipeRow(
      // 文件名唯一（每次换图都写新文件名）→ 删掉一行时别把它滑开的状态留给下一行
      key: ValueKey(it.file),
      onTap: () => AppBg.i.applyAlbum(i),
      onExport: () => _export(context, it),
      onDelete: () => _del(context, i),
      child: Container(
        // 当前项：淡橙底（模拟器 rgba(232,89,12,.12)）
        color: on ? const Color(0x1FE8590C) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Stack(
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    width: 64,
                    height: 110,
                    child: Container(
                      // 没解码完/图裂了时的底（模拟器 .bgal-th 的 #eceff3）
                      color: const Color(0xFFECEFF3),
                      child: Image(
                        // ⚠️ 裸 Image(image:) 构造器没有 cacheWidth（CI 报过 "No named parameter"）→
                        // 用 ResizeImage 包一层 provider：竖版小图别按原图解码
                        // （1440 宽 ≈ 10MB/张，20 行会爆内存）
                        image: ResizeImage(
                            FileImage(File(AppBg.i.fileOf(it))), width: 200),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_stamp(it.t),
                      style: TextStyle(fontSize: 12, color: kTxtSub)),
                ),
                if (on)
                  const Text('✓',
                      style: TextStyle(
                          color: Color(0xFFE8590C),
                          fontWeight: FontWeight.bold)),
              ],
            ),
            // 左侧橙条 3px：用叠的，不占布局（模拟器是 inset box-shadow）
            if (on)
              const Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: ColoredBox(color: Color(0xFFE8590C)),
              ),
          ],
        ),
      ),
    );
  }

  /// 右上角「＋」：相册多选 → 进图集（不自动应用）。到上限/失败都给一句提示
  Future<void> _add(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await AppBg.i.addFromGallery();
      if (r.added == 0 && r.full == 0) return; // 用户取消（或一张都没选）
      final msg = r.added == 0
          ? '图集上限 ${AppBg.maxAlbum} 张，先删几张再加'
          : '已加入 ${r.added} 张（共 ${AppBg.i.album.length}/${AppBg.maxAlbum}）'
              '${r.full > 0 ? '；另有 ${r.full} 张到上限没加' : ''}';
      messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 1), // ★ 2026-10-10（用户批准）：默认 4 秒 → 1 秒
          content: Text(msg)));
    } catch (e) {
      // ★ 2026-10-08（用户批准 ✅）：**别把英文异常原文弹给用户** ☑️ —— 原文进错误日志 ✅
      await SiteErrorLog.log('选图', e);
      messenger.showSnackBar(const SnackBar(
          duration: Duration(seconds: 1), // ★ 2026-10-10（用户批准）：默认 4 秒 → 1 秒
          content: Text('选图失败，请再试一次')));
    }
  }

  /// 导出到**系统相册**（用户明确要的；模拟器那边没有相册，用浏览器下载代替）。
  /// 权限没给/写失败都提示一句，不静默 —— 失败一律走 gal 抛的异常。
  Future<void> _export(BuildContext context, BgItem it) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) {
          messenger.showSnackBar(const SnackBar(
              duration: Duration(seconds: 2), // ★ 2026-10-10（用户批准）：默认 4 秒 → 2 秒（长文案放宽 ✅）
              content: Text('没有相册权限，导不出去 —— 去「设置 → 隐私 → 照片」里给 KPXX 打开')));
          return;
        }
      }
      await Gal.putImage(AppBg.i.fileOf(it));
      messenger.showSnackBar(const SnackBar(
          duration: Duration(seconds: 1), // ★ 2026-10-10（用户批准）：默认 4 秒 → 1 秒
          content: Text('已导出到相册')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 2), // ★ 2026-10-10（用户批准）：默认 4 秒 → 2 秒（长文案放宽 ✅）
          content: Text('导出失败：$e')));
    }
  }

  /// 点「删除」（不二次确认）；删掉当前在用的那张会切回内置默认图
  Future<void> _del(BuildContext context, int i) async {
    final messenger = ScaffoldMessenger.of(context);
    final wasCurrent = await AppBg.i.removeAlbum(i);
    if (wasCurrent) {
      messenger.showSnackBar(const SnackBar(
          duration: Duration(seconds: 1), // ★ 2026-10-10（用户批准）：默认 4 秒 → 1 秒
          content: Text('删的是当前这张背景 → 已切回内置默认图')));
    }
  }

  /// 小字说明（同模拟器 .snote：11px / 行高 1.5 / kTxtSub）
  Widget _note(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
        child: Text(text,
            style: TextStyle(fontSize: 11, color: kTxtSub, height: 1.5)),
      );

  /// 加入时间：用户明确要**年月日时**（不要"刚刚 / N分钟前"）→ 2026-10-01 18:53
  static String _stamp(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(
        ms > 0 ? ms : DateTime.now().millisecondsSinceEpoch);
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }
}

/// 一行：**左滑露出「导出 / 删除」两个按钮**，点了按钮才动手。
///
/// 用户要求（2026-10-01）：原来 `Dismissible` 滑到头 = **直接删、没有余地**；
/// 改成滑开固定宽度露出按钮、停顿一下再点（对齐模拟器 `.bgal-acts`）。
///
/// 交互（照模拟器 `bgAlbumSwipe`）：
/// - 横向拖 = 跟手位移（0 ~ -[_total]）；松手过半（或左甩）停在滑开位，否则弹回
/// - 没滑开时点一下 = [onTap]（应用）；**滑开时点一下 = 收回**（不误触应用）
///
/// ⚠️ 不用 `Dismissible`：它只有"滑到底即触发"这一种形态，做不出"停在半路等点按钮"。
class _SwipeRow extends StatefulWidget {
  const _SwipeRow({
    super.key,
    required this.child,
    required this.onTap,
    required this.onExport,
    required this.onDelete,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  State<_SwipeRow> createState() => _SwipeRowState();
}

class _SwipeRowState extends State<_SwipeRow>
    with SingleTickerProviderStateMixin {
  /// 每个按钮宽 64（和模拟器 `.bgal-acts > div` 一致）；滑开位移 = 两个按钮
  static const double _btnW = 64;
  static const double _total = _btnW * 2;

  /// 吸附动画（只用于"松手 / 点一下收回"；拖动中是直接跟手的）。
  ///
  /// ⚠️ 这里**不用** `AnimatedContainer(transform: Matrix4…)`：`Matrix4` 是 vector_math
  /// 的类型，不在 `package:flutter/material.dart` 的导出链上（3.24.5 的 basic.dart /
  /// painting.dart / tween.dart 都查过，没有 re-export）→ 用它有编译不过的风险，而本机
  /// 没有 Flutter、只有 CI 能发现（白跑一轮构建）。`Transform.translate` 收的是 `Offset`，
  /// 配合自管的 AnimationController，全是确定可用的 API。
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(() => setState(() {}));

  /// 目标位移：0 = 合上，-[_total] = 全开（拖动时它就是实时位置）
  double _dx = 0;

  /// 本次吸附的起点（拖到一半松手 → 从当前位置接着走，不跳）
  double _snapFrom = 0;

  /// 跟手期间不走动画
  bool _dragging = false;

  /// 当前实际显示的位移
  double get _offset => _dragging
      ? _dx
      : _snapFrom + (_dx - _snapFrom) * Curves.easeOut.transform(_ac.value);

  bool get _open => _offset != 0;

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails d) {
    _ac.stop(); // 拖起来就打断正在跑的吸附动画（放 setState 外面：它自己会回调 setState）
    setState(() {
      _dragging = true;
      // ⚠️ clamp() 的静态返回类型是 num，直接赋给 double 编译不过（DEVLOG §4.6 踩过）
      _dx = (_dx + d.delta.dx).clamp(-_total, 0.0).toDouble();
    });
  }

  void _settle(DragEndDetails d) {
    // 左甩（速度够快）也算要开 —— 手滑一下不必非要拖过半
    final flung = d.velocity.pixelsPerSecond.dx < -300;
    _snap(open: flung || _dx < -_total / 2);
  }

  /// 吸附到开 / 合（松手、手势被取消、点一下收回，都走这里）
  void _snap({required bool open}) {
    final from = _offset; // setState 之前取：拖到一半松手就从当前位置接着动画
    setState(() {
      _dragging = false;
      _snapFrom = from;
      _dx = open ? -_total : 0;
    });
    _ac.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 按钮层：垫在行**底下**（行是透明的，不滑开就得藏起来 —— 同模拟器的 opacity:0）
        Positioned.fill(
          child: AnimatedOpacity(
            // 滑开 3px 以上才亮出按钮（模拟器 `moved > 3` 同款判定，免得点一下闪一下）
            opacity: _offset < -3 ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch, // 按钮撑满行高
              children: [
                // 点了就收回（同模拟器 `bgAlbumExport` 末尾那次重画）——不然导出完
                // 这行还停在滑开位，看着像没反应
                _btn('导出', const Color(0xFF3C4043), () {
                  _snap(open: false);
                  widget.onExport();
                }),
                _btn('删除', const Color(0xFFE5484D), widget.onDelete),
              ],
            ),
          ),
        ),
        // 内容层：跟手位移。Transform 会连命中区域一起搬走 → 滑开后按钮点得到，
        // 没滑开时内容层盖在上面（透明也能接手势）→ 按钮点不到。
        Transform.translate(
          offset: Offset(_offset, 0),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque, // 行是透明的，不 opaque 空白处收不到手势
            onHorizontalDragUpdate: _update,
            onHorizontalDragEnd: _settle,
            onHorizontalDragCancel: () => _snap(open: _open),
            child: InkWell(
              onTap: _open ? () => _snap(open: false) : widget.onTap,
              child: widget.child,
            ),
          ),
        ),
      ],
    );
  }

  Widget _btn(String text, Color bg, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: _btnW,
          color: bg,
          alignment: Alignment.center,
          child: Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      );
}
