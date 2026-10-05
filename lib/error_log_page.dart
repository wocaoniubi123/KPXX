import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'base/site_ui.dart';
import 'app_bg.dart';
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

  /// ⚠️ 2026-10-05 修（用户报"日志一大会卡"）✓：正文超过这个长度就**只渲染末尾一段** ✗ ——
  /// `SelectableText` 是**整篇一次性排版** ✗，而日志上限是 5MB ✗ ⇒ 一次排版 5MB 要等很久 ✓。
  /// ⚠️ 这里按**字符数**算 ✓（`String.length` = UTF-16 单元 ✓，不额外做一遍 UTF-8 编码 ✗）
  /// —— 200K 字符对这个用途足够 ✓（真按字节算也不过差一倍 ✓）。
  static const int _maxRender = 200 * 1024;

  /// 只渲染 `_text` 的**末尾**：返回"从第几个字符开始显示" ✓（没超长就是 0 ✓）。
  /// ⚠️ 起点**从末尾往前找最近的换行** ✓：不把某一行劈半 ✗（日志是"一行一条" ✓）；找不到就整段从末尾切 ✓。
  int get _cut {
    if (_text.length <= _maxRender) return 0;
    final s = _text.length - _maxRender;
    final nl = _text.indexOf('\n', s);
    return nl < 0 ? s : nl + 1;
  }

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
    // 2026-10-05 用户报：本页文字与图标没做黑白自适应。根因 = 原来没挂监听
    //   （app_background.dart:51-52 原文：读 kTxt/kTxtSub 的控件要挂在 AppBg.i 上才会随明暗刷新）
    //   => 照抄现有页面同款 ListenableBuilder(listenable: AppBg.i)；页面结构不动。
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('错误日志'),   // 与另两页一致（颜色由 foregroundColor: kTxt 给 ✓）
        systemOverlayStyle: kStatusOverlay,   // 与另两页一致（play_history_page.dart:29 / bg_album_page.dart:35 ✓）
        // ③ 2026-10-05 用户报：**返回箭头也要黑白自适应** ✓ —— 原来只给标题/正文/右上 3 按钮上了 kTxt，
        //   leading 的返回箭头漏了 ✗ ⇒ 这里补 AppBar 的 foregroundColor（照 xhamsterlive.dart:382 既有写法 ✓）。
        // ④ 2026-10-05 用户报：进页时左上角会"闪一下 ‹ 设置"再只剩 ‹（框架自动返回按钮取上一页标题 ✗）
        //   ⇒ 用户要求**干脆不显示"设置"** ✓：显式给 leading ⇒ 只画箭头 ✓ 颜色跟随 kTxt ✓
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          color: kTxt,
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        foregroundColor: kTxt,
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: Icon(Icons.refresh, color: kTxt),
            onPressed: _load,
          ),
          IconButton(
            tooltip: '复制全部',
            icon: Icon(Icons.copy_all_outlined, color: kTxt),
            onPressed: _copy,
          ),
          IconButton(
            tooltip: '清空',
            icon: Icon(Icons.delete_outline, color: kTxt),
            onPressed: _text.isEmpty
                ? null
                : () async {
                    final ok = await confirmClear(
                      context: context,
                      title: '清空错误日志？',
                      content: '清空后无法恢复。');
                    if (ok == true) await _clear();
                  },
          ),
        ],
      ),
      body: Column(
          children: [
            // ⚠️ 2026-10-05（用户拍板把上限改成 5MB）：**把上限写清楚** ✓ ——
            //   免得再有人问"为什么显示 512KB / 到底多大" ✓
            //   （数值的**单一出处** = `SiteErrorLog.maxBytes` / `.keepBytes` ✓ 界面这行是给人看的说明 ✓）
            // ⚠️ 2026-10-05 构建修复 #1：**这里不能加 `const`** ✗ —— `kTxtSub` 是**运行期 getter**
            //   （`lib/app_background.dart:56`，非 const ✓）⇒ `const Padding(...)` 会报
            //   `Invalid constant value / invalid_constant`（CI 原文指的就是这一行 ✓）
            //   ⇒ **外层 Padding 不能加 const** ✗ —— 它的 Text 里含**运行期 getter** kTxtSub ✓；
            //   而内层 EdgeInsets.fromLTRB 可以 const ✓（analyzer 的 prefer_const_constructors 指的就是它 ✓）。
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
              child: Text(
                '上限 5MB，超限保留末尾约 2.5MB（只留最新的一段，不会整篇清空）',
                style: TextStyle(fontSize: 12, color: kTxtSub),
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
    ));
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
          : Column(
              children: [
                // ⚠️ 2026-10-05 修：正文超长时**只渲染末尾一段** ✓（下面 `SelectableText` 拿到的就是 `_text` 的尾巴 ✓）——
                //    提示固定挂在**滚动区之上** ✓（不会滚走 ✓）；右上角「复制全部」拿到的仍是**全文** ✓。
                if (_cut > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '仅显示最近部分 ✓（全文点右上角「复制全部」）',
                        style: TextStyle(fontSize: 12, color: kTxtSub),
                      ),
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      _text.substring(_cut),
                      // ⚠️ 2026-10-05 用户点 2：**日志正文也要跟随主题** ✓
                      //   —— 原来 `const TextStyle(...)` 没给颜色 ✗ ⇒ 走默认色（深色背景上是黑的 ✗ 看不见 ✓）
                      //   ⚠️ 必须去掉 `const` ✗：`kTxt` 是运行期 getter（app_background.dart:53 ✓）
                      style: TextStyle(fontSize: 12, height: 1.45, color: kTxt),
                    ),
                  ),
                ),
              ],
            );
}
