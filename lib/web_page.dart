import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 应用内浏览器：宫格里 kind=web 的站点用它打开，不跳出 App。
class WebPage extends StatefulWidget {
  final String title;
  final String url;

  const WebPage({super.key, required this.title, required this.url});

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  static const _ua =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  late final WebViewController _ctl;
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // 部分站点会按 UA 拦 WebView，伪装成手机 Safari
      ..setUserAgent(_ua)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p / 100);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _progress = 1);
          },
          onWebResourceError: (e) {
            // 只处理主文档失败，子资源（图/广告）失败不打扰用户
            if (e.isForMainFrame == true && mounted) {
              setState(() => _error = e.description);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  void _reload() {
    setState(() {
      _error = null;
      _progress = 0;
    });
    _ctl.loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // 先回退网页历史，退到底了才关页面
        if (await _ctl.canGoBack()) {
          _ctl.goBack();
        } else if (mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title, style: const TextStyle(fontSize: 16)),
          bottom: _progress < 1
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress,
                    minHeight: 2,
                  ),
                )
              : null,
        ),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('打开失败：$_error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black54)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _reload, child: const Text('重试')),
                    ],
                  ),
                ),
              )
            : WebViewWidget(controller: _ctl),
      ),
    );
  }
}
