import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_background.dart';
import 'site_error_log.dart';

/// **错误日志页** ✓（用户 2026-10-03 要求：点开就能看、能清、能复制）
///
/// 内容来自 [SiteErrorLog]（App 沙盒里的 `kpxx_error.log`）✓
/// 每行格式：`[时间] [站点名] 错误信息` ✓ —— 一眼看出**哪个站、什么时候**挂了 ✓
class ErrorLogPage extends StatefulWidget {
  const ErrorLogPage({super.key});

  @override
  State<ErrorLogPage> createState() => _ErrorLogPageState();
}

class _ErrorLogPageState extends State<ErrorLogPage> {
  String _text = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await SiteErrorLog.read();
    if (!mounted) return;
    setState(() {
      _text = t;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    await SiteErrorLog.clear();
    await _load();
  }

  Future<void> _copy() async {
    final p = await SiteErrorLog.path();
    await Clipboard.setData(ClipboardData(text: '文件：$p\n\n$_text'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('错误日志'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
          IconButton(
            tooltip: '复制全部',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _copy,
          ),
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.delete_outline),
            onPressed: _text.isEmpty
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('清空错误日志？'),
                        content: const Text('清空后无法恢复。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('清空'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) await _clear();
                  },
          ),
        ],
      ),
      body: PageBg(
        child: Column(
          children: [
            // ⚠️ 2026-10-05（用户拍板把上限改成 5MB）：**把上限写清楚** ✓ ——
            //   免得再有人问"为什么显示 512KB / 到底多大" ✓
            //   （数值的**单一出处** = `SiteErrorLog.maxBytes` / `.keepBytes` ✓ 界面这行是给人看的说明 ✓）
            // ⚠️ 2026-10-05 构建修复 #1：**这里不能加 `const`** ✗ —— `kTxtSub` 是**运行期 getter**
            //   （`lib/app_background.dart:56`，非 const ✓）⇒ `const Padding(...)` 会报
            //   `Invalid constant value / invalid_constant`（CI 原文指的就是这一行 ✓）
            //   ⇒ **外层去掉 const** ✓（里面的 `EdgeInsets` / `TextStyle` 也都不标 const ✓ 整段保持非 const 上下文 ✓）
            Padding(
              padding: EdgeInsets.fromLTRB(12, 10, 12, 2),
              child: Text(
                '上限 5MB，超限保留末尾约 2.5MB（只留最新的一段，不会整篇清空）',
                style: TextStyle(fontSize: 12, color: kTxtSub),
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() => _loading
      ? const Center(child: CircularProgressIndicator())
      : _text.trim().isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '暂无错误记录 ✓\n\n（有站点出错时，这里会记下「时间 + 站点名 + 错误信息」）',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: kTxtSub),
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _text,
                style: const TextStyle(fontSize: 12, height: 1.45),
              ),
            );
}
