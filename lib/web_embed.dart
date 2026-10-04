import 'dart:async'; // `Timer`（页面就绪前的深色占位保险丝 ✓）—— 2026-10-25 构建失败就栽在漏了它 ✗

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
    this.darkShell = false,
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

  /// **深色外壳**（默认关 ✗ —— 不改任何现有调用方的观感 ✓；用户 2026-10-05 拍板：只房间页开 ✓）：
  /// 打开时三件事一起生效 ✓ ——
  ///   ① 控制器设**黑底**（`setBackgroundColor` ✓，WKWebView 默认白底 ✗）；
  ///   ② 页面就绪前**盖一层黑 + 「正在加载…」**（含 10 秒保险丝 ✓）；
  ///   ③ `Stack` 最底再铺一层黑（兜住任何缝隙 ✓）。
  /// 关着 = **与加这个开关之前一模一样**：不设底色、不铺盖 ✓。
  /// ⚠️ 目前只有**直播房间页**（`xhamsterlive.dart` 的 `LiveRoomPage` ✓）传 true ✓；
  ///   `web_page.dart`（详情页"打开原页"/"网页"型站点 ✓）**不传** → 永远是 false ✓。
  final bool darkShell;

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

  /// 本次导航是否已做过"进度过半"那次注入 ✓（`onPageStarted` 时重置 ✓）——
  /// 进度事件很密 ✗ 每次都注入等于白烧 JS ✓（注入本身是幂等的 ✓ 但没必要 ✗）
  bool _mid = false;

  /// 页面是否**已经可以露出来**了 ✓（见 build 里那层深色占位 ✓）：
  /// 就绪前 WebView 是**白的** ✗（WKWebView 默认白底 ✓），必须先拿深色盖住 ✓。
  bool _ready = false;

  /// 保险丝：万一 `onPageFinished` 不来（页面卡住/被拦 ✓），也别让深色占位**永远**盖着 ✗
  Timer? _readyFuse;

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
            // ⚠️ 2026-10-05：**多挂一个注入点**（幂等 ✓）—— 页面过半就先注入一次：
            //    站点若在 SPA 里改文档/整棵重渲染，越早把样式挂上越保险 ✓；
            //    ⚠️ 每次导航**只做一次** ✗（进度事件很密 ✓ 每次都调 = 白烧 JS ✗）
            if (!_mid && p >= 0.5) {
              _mid = true;
              _inject();
            }
            if (p >= 1) _markReady(); // 页面加载完 → 可以露出来了 ✓（与 onPageFinished 双保险 ✓）
          },
          onPageStarted: (_) {
            _mid = false; // 新导航 → 允许再一次"过半注入" ✓
            _inject(); // 越早越好：DOM 一有这些元素就该被藏掉 ✓（幂等的，重复执行无副作用 ✓）
            _coverAgain(); // 新导航 → 重新盖上深色占位 ✓（否则又露一次白 ✗）
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _progress = 1);
            _inject();
            _markReady(); // 页面就绪 → 撤掉深色占位 ✓
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
    // ⚠️ 2026-10-05（用户报"点直播间先出现一整屏白"）—— **黑底只在 [darkShell] 打开时设** ✓：
    //    WKWebView 默认 `opaque=true` + 滚动视图白底 ✗ → 页面首帧之前**整屏白** ✗（根因 ✓）。
    //    iOS 侧这个 API 的实现（`webview_flutter_wkwebview` 3.18.0
    //    `webkit_webview_controller.dart:556-563` ✓）是：webView 设透明 + **scrollView 刷成这个色** ✓
    //    → 传**黑色**得到的是"黑底"而不是"透明露白" ✓（用户担心的那条正是它要避开的 ✓）。
    //    ⚠️ 默认关：**其它调用方（详情页"打开原页"/"网页"型站点）行为与以前逐字相同** ✗ 不设底色 ✓。
    if (widget.darkShell) {
      _ctl.setBackgroundColor(const Color(0xFF000000));
    }
    widget.onCreated?.call(_ctl);
  }

  /// 注入一次（`onPageStarted` / 进度过半 / `onPageFinished` 都会调 ✓ —— **幂等**，重复跑没关系 ✓）：
  /// ① `_guardJs`（静音/内联播放/系统全屏兜底 ✓）；② `widget.extraJs`（站点专属 ✓，没有就不跑 ✓）。
  ///
  /// ⚠️ 2026-10-05 修（房间页"注入没生效"排查发现）—— **两段之间不许 await** ✗：
  ///    原来是 `await _guardJs` 之后再跑 `extraJs` ✗ → 前一次 `runJavaScript` 只要**不回调**
  ///    （WKWebView 在文档被替换/进程切换时可能不回 ✓），后一段就**永远不跑** ✗ 且两处 catch 都是空的
  ///    → 现场零现象 ✗。现在两段**各自独立**（见 [_runQuiet] ✓）：谁挂了都不连坐 ✓。
  void _inject() {
    if (widget.mute) _runQuiet(_guardJs);
    if (widget.extraJs.isNotEmpty) _runQuiet(widget.extraJs);
  }

  /// 跑一段 JS：**发出去就不管** ✓（不 await ✗ —— 见 [_inject] 的说明 ✓）；
  /// 所有失败一律**静默** ✓（页面里没有 video / JS 被拦 / 引擎不回调 → 绝不影响浏览 ✗、绝不弹错 ✗）
  void _runQuiet(String js) {
    try {
      _ctl.runJavaScript(js).catchError((Object _) {});
    } catch (_) {
      // 同步抛（控制器已释放等）→ 同样静默 ✓
    }
  }

  /// 页面就绪 → **撤掉深色占位** ✓（露 WebView ✓）；顺手把保险丝撤了 ✓
  /// ⚠️ [darkShell] 关着 → 直接返回 ✓（那套 `_ready`/保险丝一个都不跑 ✗，与加开关前逐字相同 ✓）
  void _markReady() {
    if (!widget.darkShell) return;
    _readyFuse?.cancel();
    _readyFuse = null;
    if (mounted && !_ready) setState(() => _ready = true);
  }

  /// 新导航 → **重新盖上深色占位** ✓（WebView 会白一下 ✗），并重挂保险丝 ✓
  /// ⚠️ [darkShell] 关着 → 直接返回 ✓（不铺盖、不起定时器 ✓）
  void _coverAgain() {
    if (!widget.darkShell) return;
    _readyFuse?.cancel();
    _readyFuse = Timer(const Duration(seconds: 10), () {
      // ⚠️ 保险丝：`onPageFinished` 万一不来（页面卡死/被拦 ✓），10 秒后也得露出来 ✗
      //    —— 一直盖着黑比白屏更糟 ✗（用户会以为死了 ✓）
      if (mounted) setState(() => _ready = true);
    });
    if (mounted && _ready) setState(() => _ready = false);
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

  @override
  void dispose() {
    _readyFuse?.cancel(); // 保险丝别在页面销毁后还 setState ✓
    super.dispose();
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
    super.build(context); // keepAlive 必需 ✓
    return Stack(
      children: [
        // ⚠️ 2026-10-05（用户报"点进去先出现一整屏白"）：**最底那层先铺深色** ✓ ——
        //    WebView 就绪前会露出它自己的白底 ✗（根因见 initState 里 `setBackgroundColor` 那段 ✓）
        //    ⚠️ **只在 [darkShell] 打开时铺** ✗ —— 默认关 = 与加这个开关之前**一模一样** ✓
        if (widget.darkShell)
          const Positioned.fill(child: ColoredBox(color: Color(0xFF000000))),
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
        // ⚠️ 页面就绪前**盖住 WebView** ✓（用户要"极简"：一块深色 + 一行小字 ✓，别花哨 ✗）
        //    —— 光设底色还不够：站点自己的白底页面在解析出来之前也会闪一下 ✓
        //    ⚠️ 同样**只在 [darkShell] 打开时**铺 ✓（`_ready` 关着时永远是 false ✗ 不会误盖 ✓）
        if (widget.darkShell && _error == null && !_ready)
          Positioned.fill(child: _loadingCover()),
      ],
    );
  }

  /// 页面就绪前的深色占位 ✓（黑底 + 一行最小提示；与房间页的黑背景一致 ✓）
  Widget _loadingCover() => const ColoredBox(
        color: Color(0xFF000000),
        child: Center(
          child: Text('正在加载…',
              style: TextStyle(color: Color(0xFF8A8F98), fontSize: 13)),
        ),
      );
}
