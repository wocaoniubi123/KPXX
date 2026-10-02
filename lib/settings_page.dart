import 'package:flutter/material.dart';

import 'app_background.dart';
import 'app_bg.dart';
import 'bg_album_page.dart';
import 'detail_page.dart';
import 'play_history_page.dart';
import 'play_record_tile.dart';
import 'settings.dart';
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
              onTapTrailing: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PageBg(child: PlayHistoryPage())),
              ),
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
          _row(
            title: '快进 / 快退',
            sub: '双击画面左侧后退、右侧快进，一次跳转的时长',
          ),
          _seg(
            values: AppSettings.stepOptions,
            selected: AppSettings.i.step,
            label: (v) => '$v 秒',
            onPick: (v) => AppSettings.i.setStep(v),
          ),
          _divider(),
          _row(
            title: '自动播放下一集',
            sub: '一篇里有多个视频时，播完自动切下一个',
            trailing: Switch.adaptive(
              value: AppSettings.i.autoNext,
              activeColor: _orange,
              onChanged: (v) => AppSettings.i.setAutoNext(v),
            ),
          ),
          _divider(),
          _row(
            title: '播放缓冲大小',
            sub: '越大越抗卡、拖动越顺，但更吃内存',
          ),
          _seg(
            values: AppSettings.bufferOptions,
            selected: AppSettings.i.bufferMb,
            label: AppSettings.bufferLabel,
            onPick: (v) => AppSettings.i.setBufferMb(v),
          ),
          _note('改完重进视频生效；1G 在低内存机型上可能被杀进程'),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: _button(
                    label: '从相册选择',
                    onTap: () => _pickBg(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _button(
                    label: '恢复默认',
                    onTap: custom ? () => AppBg.i.clear() : null,
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
        MaterialPageRoute(builder: (_) => const PageBg(child: BgAlbumPage())),
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

  /// 卡片：**没有背景色**，只有子节点的内边距（背景图直接透出来）。
  /// 卡片间距由 ListView 里的 SizedBox(height: 14) 给（同模拟器 .scard 的 margin-bottom）
  Widget _card({required Widget child}) => child;

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
      messenger.showSnackBar(SnackBar(content: Text('选图失败：$e')));
    }
  }

  /// 点一条记录 = 回该篇详情续播（和 PlayHistoryPage._open 同一套逻辑）
  void _open(BuildContext context, PlayRecord r) {
    // 站点名反查 SiteEntry（记录按站点名存）；站点改名/下线就提示
    final hit = kSites.where((s) => s.name == r.site).toList();
    if (hit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('找不到站点「${r.site}」，这条记录打不开了')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
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
