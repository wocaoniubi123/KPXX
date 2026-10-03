import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_bg.dart';
import 'app_background.dart';
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
        // 先回退网页历史，退到底了才关页面
        final ctl = _ctl;
        if (ctl != null && await ctl.canGoBack()) {
          ctl.goBack();
        } else if (context.mounted) {
          // ⚠️ 用 `context.mounted` 而不是 `mounted`：analyze 报
          //    `use_build_context_synchronously`（`mounted` 在它看来是"不相关的检查" ✗）
          //    —— 语义相同 ✓，只是把守卫挂在真正要用的那个 context 上 ✓
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
        body: WebEmbed(url: widget.url, onCreated: (c) => _ctl = c),
      ),
    );
  }
}
