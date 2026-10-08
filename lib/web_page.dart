import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_bg.dart';
import 'app_background.dart';
import 'settings.dart';
import 'web_embed.dart';

/// 应用内浏览器（**整页**版 ✓）：宫格里 kind=web 的站点用它打开，不跳出 App。
///
/// ⚠️ 实现已抽到 [WebEmbed] ✓（用户 2026-10-03：短片 tab 要在**内容区嵌入**同一个东西 ✓
/// —— 不能写成两份 ✗）→ 这里只包一层 `Scaffold` + 标题栏 + "先退网页历史、退到底才关页" ✓。
class WebPage extends StatefulWidget {
  final String title;
  final String url;

  const WebPage({super.key, required this.title, required this.url});

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  WebViewController? _ctl;

  // ★【常驻诊断】本页进/出（只含日志的两个钩子：super + 一条 debugPrint，不动任何既有逻辑 ✓）
  //   原文件没有 initState/dispose ⇒ 这两条在"用网页播放器打开"这条路上原本完全看不见 ✓
  @override
  void initState() {
    super.initState();
    if (AppSettings.i.logConsole) debugPrint('[WEB] 整页版进 title=${widget.title} ${webLoc(widget.url)}');
  }

  @override
  void dispose() {
    // ⚠️ 只记日志：**不**在这里 dispose 控制器（原来就没有，行为一字不动 ✓）
    if (AppSettings.i.logConsole) debugPrint('[WEB] 整页版出（dispose）title=${widget.title} ${webLoc(widget.url)}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 整页跟着背景明暗重建（顶栏标题/图标都读 kTxt）
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => _pageView(context),
    );
  }

  Widget _pageView(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // ★【常驻诊断】返回手势/返回键落到本页（PopScope 拦着：先退网页历史，退到底才关页 ✓）
        if (AppSettings.i.logConsole) debugPrint('[WEB] 返回动作 ctl=${_ctl == null ? '(还没建好)' : '有'} ${webLoc(widget.url)}');
        // 先回退网页历史，退到底了才关页面
        final ctl = _ctl;
        if (ctl != null && await ctl.canGoBack()) {
          // ★【常驻诊断】还有网页历史 ⇒ 只后退、不关页（App 内不跳出 ✓）
          if (AppSettings.i.logConsole) debugPrint('[WEB] 返回 ⇒ 还有网页历史：goBack()（不关页）');
          ctl.goBack();
        } else if (context.mounted) {
          // ⚠️ 用 `context.mounted` 而不是 `mounted`：analyze 报
          //    `use_build_context_synchronously`（`mounted` 在它看来是"不相关的检查" ✗）
          //    —— 语义相同 ✓，只是把守卫挂在真正要用的那个 context 上 ✓
          // ★【常驻诊断】退到底 ⇒ 关这一页（回到宿主页 ✓）
          if (AppSettings.i.logConsole) debugPrint('[WEB] 返回 ⇒ 已退到底：Navigator.pop() 关页');
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          systemOverlayStyle: kStatusOverlay,
          title: Text(widget.title, style: const TextStyle(fontSize: 16)),
          foregroundColor: kTxt, // 标题/图标直接压在图上 → 跟明暗
        ),
        // 进度条 / 错误重试 / 静音都在 WebEmbed 里 ✓（两边共用同一套 ✓）
        body: WebEmbed(
          url: widget.url,
          onCreated: (c) {
            // 控制器创建（宿主拿到 WebView 控制器，用于网页历史后退）
            if (AppSettings.i.logConsole) debugPrint('[WEB] 控制器创建 ${webLoc(widget.url)}');
            _ctl = c;
          },
        ),
      ),
    );
  }
}
