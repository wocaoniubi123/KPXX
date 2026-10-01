import 'dart:io';

import 'package:flutter/material.dart';

import 'app_background.dart';
import 'app_bg.dart';

/// 背景图集（设置页「背景图集 N 张 ›」进来）。照模拟器 `viewAlbum()` 定稿的样子：
/// - 行**全透明**（背景图从行间透出来）、**没有分割线**，行与行靠间距分开
/// - 左 = 竖版缩略图 64×110 / 圆角 9 / cover；右 = 加入时间（年月日时）
/// - **当前应用那条**：淡橙底 + 左侧 3px 橙条 + 右侧橙色 ✓
/// - 点一条 = **立即应用**（不跳页）；**左滑**露出红色「删除」（不二次确认）
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
          ? _note('图集是空的 —— 点右上角「＋」添加背景（从相册多选，选完直接进图集）')
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              // 末项固定是底部说明（同模拟器图集页列表下面那行小字）
              itemCount: album.length + 1,
              itemBuilder: (context, i) => i == album.length
                  ? _note('点一下立即应用；左滑一行露出「删除」—— '
                      '删掉当前在用的那张会切回内置默认图')
                  : _row(context, i, album[i]),
            ),
    );
  }

  /// 一行：缩略图 + 加入时间（+ 当前那条的 ✓）
  Widget _row(BuildContext context, int i, BgItem it) {
    final on = AppBg.i.currentPath == it.path;
    return Dismissible(
      key: ValueKey(it.path), // 路径唯一（每次换图都写新文件名）
      direction: DismissDirection.endToStart, // 只允许左滑
      background: Container(
        // 模拟器 .bgal-del：红底白字「删除」，垫在行底下（行透明，滑开才露出来）
        color: const Color(0xFFE5484D),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: const Text('删除',
            style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ),
      onDismissed: (_) => _del(context, i),
      child: InkWell(
        onTap: () => AppBg.i.applyAlbum(i),
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
                          image: ResizeImage(FileImage(File(it.path)), width: 200),
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
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('选图失败：$e')));
    }
  }

  /// 左滑删除（不二次确认）；删掉当前在用的那张会切回内置默认图
  Future<void> _del(BuildContext context, int i) async {
    final messenger = ScaffoldMessenger.of(context);
    final wasCurrent = await AppBg.i.removeAlbum(i);
    if (wasCurrent) {
      messenger.showSnackBar(
          const SnackBar(content: Text('删的是当前这张背景 → 已切回内置默认图')));
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
