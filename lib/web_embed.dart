import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_background.dart';

/// **可嵌入的站内网页** ✓（用户 2026-10-03 拍板 A 方案：短片 tab 直接嵌站点自己的页面 ✓）
///
/// ⚠️ 与 `web_page.dart`（整页版 ✓）**共用这一套实现** ✗ 不能写两份 ✓ ——
/// 那个文件现在只是给这里包一层 `Scaffold` + 标题栏 + 返回处理 ✓。
///
/// ⚠️ 我们用的是**顶层加载** ✓：站点那套 `X-Frame-Options` / CSP `frame-ancestors 'self'`
/// 只禁**跨域 iframe** ✗ → 对顶层 WebView **无效** ✓（模拟器嵌不了真站正是 iframe 那条 ✗，与 App 无关 ✓）。
///
/// ⚠️ **静音保底** ✓（要求：一律静音 ✗）：站点自己就是 muted 自动播 ✓，但用户手点后可能带声 ✗ →
/// 这里在 `document` 上挂**捕获式** `play` 监听 ✓ + 定时扫一遍 `<video>` ✓，把 `muted/volume` 压住 ✓
/// （平台层没有静音开关 ✗，只能走 JS ✓）；**全程 try/catch，静音失败绝不影响浏览** ✗。
class WebEmbed extends StatefulWidget {
  const WebEmbed({
    super.key,
    required this.url,
    this.mute = true,
    this.onCreated,
    this.ua = _ua,
  });

  final String url;

  /// 一律静音 ✓（模拟器与真机同 ✓）
  final bool mute;

  /// 把控制器交出去（宿主用它判断"网页能不能后退" ✓）
  final void Function(WebViewController ctl)? onCreated;

  /// 伪装手机 Safari：部分站点会按 UA 拦 WebView ✓（原 `web_page.dart` 同款 ✓）
  final String ua;

  static const String _ua =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  @override
  State<WebEmbed> createState() => WebEmbedState();
}

class WebEmbedState extends State<WebEmbed> with AutomaticKeepAliveClientMixin {
  late final WebViewController _ctl;
  double _progress = 0;
  String? _error;

  /// ⚠️ 切到别的 tab 再回来**不重载** ✓（站点自己的 feed 有滚动位置/正在播的那条 ✓）；
  /// 之前短片 tab 那种"每次切回来重新随机"是**自研列表**的行为 ✗，现在归站点 ✓。
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _ctl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(widget.ua)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p / 100);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _progress = 1);
            _applyMute();
          },
          onWebResourceError: (e) {
            // 只处理主文档失败，子资源（图/广告）失败不打扰用户 ✓（原 web_page.dart 同款 ✓）
            if (e.isForMainFrame == true && mounted) {
              setState(() => _error = e.description);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
    widget.onCreated?.call(_ctl);
  }

  /// 静音：① 立刻扫一遍已有 `<video>` ✓ ② 挂**捕获式** `play` 监听 ✓（用户手点播放也一样压得住 ✓）
  /// ③ 每 2 秒兜一次 ✓（站点自己的"取消静音"按钮也压回来 ✓ —— 用户要求"一律静音" ✗）。
  Future<void> _applyMute() async {
    if (!widget.mute) return;
    try {
      await _ctl.runJavaScript(_muteJs);
    } catch (_) {
      // 页面里没有 video / JS 被拦 → 静默 ✓（绝不弹错、绝不影响浏览 ✗）
    }
  }

  static const String _muteJs = r'''
(function () {
  function m(v) { try { v.muted = true; v.volume = 0; v.setAttribute('muted', 'muted'); } catch (e) {} }
  function sweep() { try { document.querySelectorAll('video').forEach(m); } catch (e) {} }
  sweep();
  if (!window.__kpxxMute) {
    window.__kpxxMute = true;
    document.addEventListener('play', function (e) {
      try { if (e && e.target && e.target.tagName === 'VIDEO') m(e.target); } catch (err) {}
    }, true);
    setInterval(sweep, 2000);
  }
})();
''';

  void _reload() {
    setState(() {
      _error = null;
      _progress = 0;
    });
    _ctl.loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // keepAlive 必需 ✓
    return Stack(
      children: [
        if (_error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('打开失败：$_error',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kTxtSub)),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _reload, child: const Text('重试')),
                ],
              ),
            ),
          )
        else
          WebViewWidget(controller: _ctl),
        // 进度条压在网页顶部 ✓（原 web_page.dart 是挂在 AppBar 底下 ✓ —— 挪进来两边共用 ✓）
        if (_error == null && _progress < 1)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(
              value: _progress == 0 ? null : _progress,
              minHeight: 2,
            ),
          ),
      ],
    );
  }
}
