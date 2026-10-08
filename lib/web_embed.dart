import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
// ⚠️ iOS 的 WebView 创建参数在这个包里 ✓（webview_flutter 的 iOS 实现 ✓、随它一起装 ✓；
//    官方文档给的写法就是引这个包 ✓ —— `depend_on_referenced_packages` 可能会报一条 info ✓ 不拦构建 ✗）
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'app_background.dart';
import 'settings.dart';

/// 日志用：只取 `host=` + `path=`（path 截 80）—— **不打完整 URL** ✓
String webLoc(String url) {
  final u = Uri.tryParse(url);
  final p = u?.path ?? '';
  return 'host=${u?.host ?? '?'} path=${p.length > 80 ? p.substring(0, 80) : p}';
}

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
  /// ★ 2026-10-05（#2 局部化）：进度**只在进度条那一小块**里用 ValueNotifier ✓
  ///   —— 原来写 `double` + 每次 `setState` ⇒ **整页（含 WebViewWidget）重建** ✗，现在不再重建整页 ✓。
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  String? _error;

  /// ⚠️ 切到别的 tab 再回来**不重载** ✓（站点自己的 feed 有滚动位置/正在播的那条 ✓）；
  /// 之前短片 tab 那种"每次切回来重新随机"是**自研列表**的行为 ✗，现在归站点 ✓。
  @override
  bool get wantKeepAlive => true;

  /// ★ 2026-10-05（#2 补漏）：释放局部化的进度 notifier ✓
  ///   ⚠️ 顺序：**先释放子件 ✓ 再 `super.dispose()`** ✓（框架要求 ✓）。
  @override
  void dispose() {
    // ★【常驻诊断】嵌入页销毁（keepAlive ⇒ 切 tab 不会走这里；全页版关页时会走 ✓）
    if (AppSettings.i.logConsole) debugPrint('[WEB] WebEmbed dispose ${webLoc(widget.url)}');
    _progress.dispose();
    super.dispose();
  }

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
    // 加载开始（创建控制器 + 发起首次加载）
    // ★【常驻诊断】实际用哪套创建参数（"内联播放没生效/被顶到系统全屏播放器"先看这条 ✓）
    if (AppSettings.i.logConsole) debugPrint('[WEB] 创建参数 走 iOS 专用=${params is WebKitWebViewControllerCreationParams} 内联播放=${params is WebKitWebViewControllerCreationParams ? '开' : '默认(关)'} 需要手势的媒体类型=${params is WebKitWebViewControllerCreationParams ? '已清空' : '默认{audio,video}'}');
    if (AppSettings.i.logConsole) debugPrint('[WEB] 加载开始 ${webLoc(widget.url)}');
    _ctl = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(widget.ua)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            // ★【常驻诊断】进度**只记关键节点**（首个进度 / 过半 / 100）——**不逐 1% 打** ✓
            //   ⚠️ 用既有 notifier `_progress.value` 当"上一次"的记忆 ✓ 不新增字段、不改这行的赋值语义 ✓
            if (AppSettings.i.logConsole) {
              final prev = _progress.value * 100;
              if (prev <= 0 && p > 0) {
                debugPrint('[WEB] 进度起 ${p.round()}% ${webLoc(widget.url)}');
              } else if (prev < 50 && p >= 50) {
                debugPrint('[WEB] 进度过半 ${p.round()}% ${webLoc(widget.url)}');
              } else if (p >= 100) {
                debugPrint('[WEB] 进度 100% ${webLoc(widget.url)}');
              }
            }
            if (mounted) _progress.value = p / 100; // ★ 不再 setState ✓ 只重建进度条 ✓
          },
          onPageFinished: (_) {
            if (mounted) _progress.value = 1; // ★ 语义不变：置 1 ⇒ 条消失 ✓
            // 加载完成（主文档）
            if (AppSettings.i.logConsole) debugPrint('[WEB] 加载完成 ${webLoc(widget.url)}');
            _applyGuard();
          },
          onWebResourceError: (e) {
            // 只处理主文档失败，子资源（图/广告）失败不打扰用户 ✓（原 web_page.dart 同款 ✓）
            if (e.isForMainFrame == true && mounted) {
              // 加载失败（主文档）
              if (AppSettings.i.logConsole) debugPrint('[WEB] 加载失败 ${webLoc(widget.url)}');
              // ★【常驻诊断】失败原因（错误码 + 描述）——点"重试"之前先看这条 ✓
              if (AppSettings.i.logConsole) debugPrint('[WEB] 失败详情 code=${e.errorCode.toString()} desc=${e.description}');
              setState(() => _error = e.description);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
    widget.onCreated?.call(_ctl);
  }

  /// 每次页面加载后注入 `_guardJs` ✓（静音 ✓ + 内联播放兜底 ✓ + 系统全屏兜底 ✓）
  Future<void> _applyGuard() async {
    if (!widget.mute) return;
    // 加载后注入静音/内联播放保底脚本（mute=false 时上面已返回，这里就是"真注入了"）
    if (AppSettings.i.logConsole) debugPrint('[WEB] 注入保底JS ${webLoc(widget.url)}');
    try {
      await _ctl.runJavaScript(_guardJs);
      // ★【常驻诊断】注入成功（静音 + 内联播放 + 系统全屏兜底都挂上了 ✓）
      if (AppSettings.i.logConsole) debugPrint('[WEB] 注入成功 ${webLoc(widget.url)}');
    } catch (e) {
      // 页面里没有 video / JS 被拦 → 静默 ✓（绝不弹错、绝不影响浏览 ✗）
      // ★【常驻诊断】注入失败也静默，但留痕（截 120 字 ✓）
      if (AppSettings.i.logConsole) {
        final es = '$e';
        debugPrint('[WEB] 注入失败(静默) ${webLoc(widget.url)} ${es.length <= 120 ? es : es.substring(0, 120)}');
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
      _progress.value = 0; // ★ 语义不变：重试 ⇒ 条重现 ✓（外层 setState 保留 ✓ 它同时清 _error ✓）
    });
    // ⚠️ 2026-10-05 修：重试改成**原地刷新** ✓ —— 原来重发的是**入口地址** ✗ ⇒ 站内跳转过的位置
    //    全丢 ✗（用户报的"点重试弹回入口页" ✓）。`reload` 就是 WKWebView 的原地刷新 ✓：
    //    当前 URL / 站内位置都保留 ✓（换的是"重新加载"，不是"重新打开入口" ✓）。
    //    ⚠️ `:102` 的**初次加载**仍走 `loadRequest` + 入口地址 ✓（那里本就该用入口地址 ✓）—— 没动 ✗。
    // ★【常驻诊断】用户点了"重试"（原地刷新：保留站内位置，不是回入口 ✓）
    if (AppSettings.i.logConsole) debugPrint('[WEB] 点重试 ⇒ 原地 reload() ${webLoc(widget.url)}');
    _ctl.reload();
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
        // 2026-10-05 曾因误判"状态栏细条"删除；查明细条来自**背景图顶边**（换图即消失 ✓ 非软件所画 ✓）后还原 ✓
        // ★ 2026-10-05（#2 局部化）：把"进度"这一小块包进 ValueListenableBuilder ✓
        //   ⚠️ 包法**必须是"Positioned 在外、builder 在内"** ✗ —— Positioned 是 ParentDataWidget ✓
        //      塞进 builder 里会报 "Incorrect use of ParentDataWidget" ✗（硬约束 ✓）
        //   ⚠️ 完成时**仍返回同一层 Positioned 外壳** ✗（内部 0 高度 ✓）——
        //      保证本 Stack 的【非定位子层集合】与改前**逐条一致** ✓（"有声无画"那类隐患的守则 ✓）
        if (_error == null)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _progress,
              builder: (_, p, __) => p >= 1
                  ? const SizedBox.shrink()
                  : LinearProgressIndicator(
                      value: p == 0 ? null : p,
                      minHeight: 2,
                    ),
            ),
          ),
      ],
    );
  }
}
