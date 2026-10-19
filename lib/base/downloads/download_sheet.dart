// 下载选集弹层 —— **在线详情页 / 离线播放页共用**（用户 2026-10-19 拍板）。
//
// 为什么抽出来：两处需求完全一样（列出全部集、勾选补下载、已下载/下载中/排队置灰），
// 唯一区别是"状态从哪儿查" ⇒ 用 isDone / isBusy / isQueued 三个回调注入
// （弹层不查下载记录；只监听 `DownloadManager` 的通知来触发重绘）。
//
// 行为（与原先 detail_page.dart 里的私有版保持一致）：
// · 底部 Sheet、最高 60% 屏、可滚动；标题「下载选集（共 N 集）」+ 全选/反选；
// · 每行 checkbox + 集名 + 状态：已下载 ✅ / 下载中 ⟳ / 排队「等待中」，后两者都置灰；
// · 底部橙色按钮「下载（已选 N 集）」，N=0 或提交中禁用；
// · 提交时再过滤一次（弹层开着时某集可能刚好下完/开始下）；
// · 部分成功 ⇒ 关弹层并把结果交给调用方提示；全部失败 ⇒ 弹层不关、内部提示失败集。

import 'package:flutter/material.dart';

import 'download_manager.dart';

/// 弹层提交结果：成功入队几集 + 取源失败的集名（调用方负责提示）
class DlSubmitResult {
  final int ok;
  final List<String> failed;
  const DlSubmitResult(this.ok, this.failed);
}

/// 下载选集弹层（在线详情页 / 离线播放页共用）：列出全部集，勾选后提交。
/// [labels] 每集显示名；[isDone]/[isBusy] 决定置灰与勾选态；[onSubmit] 收到选中集下标。
class DownloadSheet extends StatefulWidget {
  /// 每集的显示名（下标 = 集下标，与 isDone/isBusy/onSubmit 同一套）
  final List<String> labels;

  /// 已下载（✅ + 实心勾 + 置灰不可改）
  final bool Function(int i) isDone;

  /// 已加入下载（⟳ 或「等待中」+ 置灰不可选）
  final bool Function(int i) isBusy;

  /// [isBusy] 里属于"排队中"的那些（显示「等待中」而不是 ⟳）；null = 全按 ⟳ 显示。
  final bool Function(int i)? isQueued;

  /// 点「下载」时把选中的下标交给调用方（解析源 + 入队在调用方做）
  final Future<DlSubmitResult> Function(List<int> picked) onSubmit;

  const DownloadSheet({
    super.key,
    required this.labels,
    required this.isDone,
    required this.isBusy,
    this.isQueued,
    required this.onSubmit,
  });

  @override
  State<DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<DownloadSheet> {
  /// 已勾选的集（0-based 下标）
  final Set<int> _selected = <int>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 幂等；读完盘后 ListenableBuilder 会刷新"已下载/下载中"状态
    // （弹层是另一条路由，调用方的 setState 不会重建它 ⇒ 必须自己听管理器）
    DownloadManager.i.load();
  }

  bool _isDone(int i) => widget.isDone(i);

  bool _isBusy(int i) => widget.isBusy(i);

  bool _selectable(int i) => !_isDone(i) && !_isBusy(i);

  void _toggle(int i) {
    if (_busy || !_selectable(i)) return;
    setState(() {
      if (!_selected.remove(i)) _selected.add(i);
    });
  }

  void _selectAll() {
    if (_busy) return;
    setState(() {
      for (var i = 0; i < widget.labels.length; i++) {
        if (_selectable(i)) _selected.add(i);
      }
    });
  }

  void _invert() {
    if (_busy) return;
    setState(() {
      for (var i = 0; i < widget.labels.length; i++) {
        if (!_selectable(i)) continue;
        if (!_selected.remove(i)) _selected.add(i);
      }
    });
  }

  Future<void> _submit() async {
    // 提交时再过滤一遍：弹层开着时某集可能刚好下完了
    final picked = <int>[
      for (final i in _selected)
        if (_selectable(i)) i,
    ]..sort();
    if (picked.isEmpty || _busy) return;
    setState(() => _busy = true);
    final r = await widget.onSubmit(picked);
    if (!mounted) return;
    if (r.ok > 0) {
      Navigator.of(context).pop(r); // 关弹层；提示由调用方在 pop 之后弹
      return;
    }
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content:
          Text(r.failed.isEmpty ? '没有可下载的源' : '取源失败：${r.failed.join('、')}'),
    ));
  }

  Widget _row(int i, ColorScheme cs) {
    final done = _isDone(i);
    final busy = _isBusy(i);
    final queued = busy && (widget.isQueued?.call(i) ?? false);
    // 置灰不可选：已下载 / 已加入下载 / 正在提交
    final disabled = done || busy || _busy;
    final faded = cs.onSurface.withValues(alpha: 0.45);
    return InkWell(
      onTap: disabled ? null : () => _toggle(i),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
        child: Row(
          children: [
            Checkbox(
              // 已下载 = 实心勾（置灰不可改）；其余看手动勾选
              value: done || _selected.contains(i),
              onChanged: disabled ? null : (_) => _toggle(i),
              visualDensity: VisualDensity.compact,
              activeColor: const Color(0xFFE8590C),
            ),
            Expanded(
              child: Text(
                widget.labels[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: disabled ? faded : cs.onSurface,
                ),
              ),
            ),
            if (done)
              Text('✅', style: TextStyle(fontSize: 13, color: faded))
            else if (queued)
              Text('等待中', style: TextStyle(fontSize: 11, color: faded))
            else if (busy)
              Text('⟳', style: TextStyle(fontSize: 15, color: faded)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DownloadManager.i,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        // 实际会提交的集（已下载/下载中的不算）—— 按钮上的 N 与禁用都按它
        final pickCount = _selected.where(_selectable).length;
        return ConstrainedBox(
          // 用户口径：最高 60% 屏；内容少时按内容高（Column mainAxisSize.min）
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.6),
          // 用 Material 而不是纯色 Container：勾选行的水波纹要画在面板底色之上
          child: Material(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '下载选集（共 ${widget.labels.length} 集）',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _selectAll,
                          child: const Text('全选',
                              style: TextStyle(fontSize: 12)),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _invert,
                          child: const Text('反选',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: cs.outlineVariant),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: widget.labels.length,
                      itemBuilder: (_, i) => _row(i, cs),
                    ),
                  ),
                  Divider(height: 1, color: cs.outlineVariant),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: FilledButton(
                        // N = 0 禁用（用户口径）
                        onPressed:
                            (_busy || pickCount == 0) ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFE8590C),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              const Color(0xFFE8590C).withValues(alpha: 0.35),
                          disabledForegroundColor: Colors.white70,
                        ),
                        child: Text(
                          _busy ? '正在加入下载…' : '下载（已选 $pickCount 集）',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
