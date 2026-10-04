import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
// ⚠️ iOS 的 WebView 创建参数在这个包里 ✓（webview_flutter 的 iOS 实现 ✓、随它一起装 ✓；
//    官方文档给的写法就是引这个包 ✓ —— `depend_on_referenced_packages` 可能会报一条 info ✓ 不拦构建 ✗）
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

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
///
/// ⚠️ **内联播放**（2026-10-03 用户实测 ✗）：iOS 的 WKWebView **默认不允许** `<video>` 内联播 ✓
/// （`allowsInlineMediaPlayback=false` ✓，官方文档 ✓）→ 一点播放就弹**系统全屏播放器** ✗、且**回不到列表** ✗
/// （用户把那套 UI 当成了 Safari ✗）→ 主修在创建参数（`initState` 里的 `allowsInlineMediaPlayback: true` ✓），
/// JS 里再给每个 `<video>` 补 `playsInline` + `playsinline`/`webkit-playsinline` 兜底 ✓。
class WebEmbed extends StatefulWidget {
  const WebEmbed({
    super.key,
    required this.url,
    this.mute = true,
    this.onCreated,
    this.ua = _ua,
    this.extraJs = '',
    this.toggleX = false,
  });

  final String url;

  /// 一律静音 ✓（模拟器与真机同 ✓）
  final bool mute;

  /// 把控制器交出去（宿主用它判断"网页能不能后退" ✓）
  final void Function(WebViewController ctl)? onCreated;

  /// 伪装手机 Safari：部分站点会按 UA 拦 WebView ✓（原 `web_page.dart` 同款 ✓）
  final String ua;

  /// **站点专属注入** ✓（留空 = 不注入 ✓）：每次页面加载完（`onPageFinished` ✓）在**静音守护之后**
  /// 跑一次 ✓，全程 try/catch ✓、失败绝不影响浏览 ✗。
  /// ⚠️ 站点相关的东西**写在站点自己文件里** ✓ 不写进这个共用件 ✗（这里只提供通用能力 ✓）；
  ///   JS 里请自己防重入（同一个页面可能被跑不止一次 ✓）。
  final String extraJs;

  /// 点屏幕 = 切 X 显隐（默认关 ✗；直播房间页开 ✓ —— 它没有控制栏，只能用单击 ✓）；
  /// 关着的时候由宿主自己**吞掉点击** ✗，别让点击漏到网页里 ✓。
  final bool toggleX;

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
    // ⚠️ 2026-10-03 修（用户实测 ✗）：**iOS 必须允许"内联播放"** —— 否则 WKWebView 的默认是
    //    `allowsInlineMediaPlayback = false` ✓（官方文档原文 ✓）→ 站点页里的 `<video>` 一播就被顶到
    //    **系统全屏播放器** ✗（左上 X / AirPlay / 画中画那一套 ✓、**回不到列表** ✗ —— 用户还以为是 Safari ✗）。
    // ⚠️ 顺带把"需要用户手势才能播"清空 ✓：站点自己就是**静音自动播** ✓，不清空的话每换一条都要点一下 ✗
    //    （`mediaTypesRequiringUserAction` 默认 `{audio, video}` ✓）；静音由 `_guardJs` 全程压着 ✓。
    // ⚠️ 这两个开关**只能在创建时**给 ✓（对应 `WKWebViewConfiguration` 的创建期只读项 ✗）→ 走 iOS 创建参数 ✓。
    PlatformWebViewControllerCreationParams params =
        const PlatformWebViewControllerCreationParams();
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params =
          WebKitWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
        params,
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    }
    _ctl = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(widget.ua)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p / 100);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _progress = 1);
            _applyGuard();
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

  /// 每次页面加载后注入：先 `_guardJs`（静音/内联播放/系统全屏兜底 ✓），
  /// 再 `widget.extraJs`（站点专属 ✓，没有就不跑 ✓）。两边都**独立 try/catch** ✓：
  /// 一个失败不影响另一个 ✓、也不影响浏览 ✓。
  Future<void> _applyGuard() async {
    if (widget.mute) {
      try {
        await _ctl.runJavaScript(_guardJs);
      } catch (_) {
        // 页面里没有 video / JS 被拦 → 静默 ✓（绝不弹错、绝不影响浏览 ✗）
      }
    }
    if (widget.extraJs.isNotEmpty) {
      try {
        await _ctl.runJavaScript(widget.extraJs);
      } catch (_) {
        // 站点注入失败 → 保持原样 ✓（站点页面照常显示 ✓，绝不弹错 ✗）
      }
    }
  }

  /// ① 静音：立刻扫一遍 `<video>` ✓ + 捕获式 `play` 监听 ✓（用户手点也压得住 ✓）+ 每 2 秒兜一次 ✓
  /// ② **内联播放兜底** ✓：`playsInline` + `playsinline`/`webkit-playsinline` 属性
  ///    （主修是 controller 的 `allowsInlineMediaPlayback` ✓，这里是保底 ✗）
  /// ③ **系统全屏兜底** ✓：万一站点自己喊 `webkitEnterFullscreen()` ✗ → 立刻退出来 ✓（能不拦就不拦 ✓）
  static const String _guardJs = r'''
(function () {
  function fix(v) {
    try {
      v.playsInline = true;
      v.setAttribute('playsinline', '');
      v.setAttribute('webkit-playsinline', '');
      v.muted = true; v.volume = 0; v.setAttribute('muted', 'muted');
    } catch (e) {}
  }
  function sweep() { try { document.querySelectorAll('video').forEach(fix); } catch (e) {} }
  sweep();
  if (!window.__kpxxFix) {
    window.__kpxxFix = true;
    document.addEventListener('play', function (e) {
      try { if (e && e.target && e.target.tagName === 'VIDEO') fix(e.target); } catch (err) {}
    }, true);
    document.addEventListener('webkitbeginfullscreen', function (e) {
      try { var v = e.target; if (v && v.webkitExitFullscreen) v.webkitExitFullscreen(); } catch (err) {}
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
