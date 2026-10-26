// ★ 2026-10-27（用户要求）：**PandaTV 直播页**（排序 + 双列房间列表 + 全屏播放）
//
// 协议/实测事实见 `sites/panda_live.dart` 文件头 ✅
//
// 🛢️ 用户 2026-10-27 口径：**取消顶栏分类 tab，显示全部**（保留 3 个排序档）——
//   依据实测：密码房 2 个 / 粉丝房 7 个在 `list.m3u` 里**都没有流地址**
//   ⇒ 那两个筛选栏点进去必然空 ⇒ 直接撤掉筛选 ✅
//
// 🛢️ 两个必须做对的点（实测出来的，别改）：
//   ① 播放时必须带 **Referer + Origin** 两个头 —— 只带 Referer 清单也 403；
//      分片缺 Origin 会返回 `403 origin required`（15 字节响应体）
//   ② `liveType == 'rec'` 的房间是**回放**，不是实时 ⇒ UI 上必须标出「回放」，
//      否则用户会以为"这直播怎么像录屏"（用户 2026-10-27 的原话）

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:media_kit_video/media_kit_video.dart';

import 'app_background.dart'; // kTxt / kTxtSub / kStatusOverlay / kLiveLoadingText
import 'app_bg.dart'; // AppBg（明暗）
import 'fetched_image.dart'; // FetchedImage
import 'player_widget.dart'; // KpPlayer
import 'settings.dart'; // AppSettings
import 'sites.dart'; // SiteEntry
import 'sites/panda_live.dart';

/// 底栏「直播」→「PandaTV」点进来 = 这个页面
class PandaLivePage extends StatefulWidget {
  const PandaLivePage({super.key, this.site});

  final SiteEntry? site;

  @override
  State<PandaLivePage> createState() => _PandaLivePageState();
}

class _PandaLivePageState extends State<PandaLivePage> {
  final PandaApi _api = PandaApi();

  PandaCatalog? _cat;
  String _err = '';
  int _sort = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _cat = null;
      _err = '';
    });
    try {
      final c = await _api.fetch();
      if (!mounted) return;
      setState(() => _cat = c);
      if (AppSettings.i.logConsole) {
        debugPrint('[PANDA] 目录 json=${c.total} 有流=${c.playable} 可播=${c.rooms.length} '
            '回放=${c.rooms.where((r) => r.isRec).length}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    }
  }

  /// 排序后的列表（★ 取消分类 tab ⇒ 全部房间都显示 ✅）
  List<PandaRoom> get _shown {
    final c = _cat;
    if (c == null) return const <PandaRoom>[];
    final v = kPandaSorts[_sort].value;
    return c.rooms.toList()..sort((a, b) => v(b) - v(a));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppBg.i,
      builder: (context, _) => _page(context),
    );
  }

  Widget _page(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        systemOverlayStyle: kStatusOverlay,
        title: Text(widget.site?.name ?? 'PandaTV'),
        centerTitle: true,
        foregroundColor: kTxt,
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _cat == null && _err.isEmpty ? null : _load,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(38),
          child: _sortRow(),
        ),
      ),
      body: _body(),
    );
  }

  // 排序行（3 个胶囊，右对齐）—— ★ 用户 2026-10-27：**保留这三个排序，分类 tab 撤掉** ✅
  Widget _sortRow() {
    return SizedBox(
      height: 38,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (var i = 0; i < kPandaSorts.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _sort = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _sort == i
                        ? const Color(0xFFE8590C).withValues(alpha: 0.16)
                        : (AppBg.i.isDark
                            ? const Color(0xFF2A2A2A)
                            : const Color(0xFFF2F2F2)),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _sort == i
                          ? const Color(0xFFE8590C)
                          : const Color(0x223C3C3C),
                    ),
                  ),
                  child: Text(
                    kPandaSorts[i].label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: _sort == i ? FontWeight.w700 : FontWeight.w400,
                      color: _sort == i ? const Color(0xFFE8590C) : kTxtSub,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_err.isNotEmpty) {
      return _msg('PandaTV 打不开\n$_err', retry: _load);
    }
    if (_cat == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final list = _shown;
    if (list.isEmpty) return _msg('暂时没有可播的直播');
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 3 / 4,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) => _RoomCard(
        room: list[i],
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PandaRoomPage(room: list[i]),
            settings: const RouteSettings(name: 'PandaTV 房间'),
          ),
        ),
      ),
    );
  }

  Widget _msg(String text, {VoidCallback? retry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: kTxtSub),
            ),
            if (retry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: retry, child: const Text('重试')),
            ],
          ],
        ),
      ),
    );
  }
}

/// 房间卡（2 列竖版）
class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room, required this.onTap});

  final PandaRoom room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 角标：回放 > 密码房 > 19+（回放最重要，必须先看到）
    final badge = room.isRec
        ? '回放'
        : (room.isPw ? '密码房' : (room.isAdult ? '19+' : ''));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (room.cover.isEmpty)
              Container(color: const Color(0x223C3C3C))
            else
              FetchedImage(url: room.cover, memWidth: 480),
            // 左上角角标
            if (badge.isNotEmpty)
              Positioned(
                left: 5,
                top: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: room.isRec
                        ? const Color(0xCC607D8B) // 回放 = 蓝灰（区别于直播的红）
                        : const Color(0xCCE8590C),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            // 底部名字 + 人数
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                color: const Color(0x99000000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      room.nick,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                    Text(
                      '👤 ${room.userCnt}',
                      maxLines: 1,
                      style: const TextStyle(fontSize: 10, color: Color(0xCCFFFFFF)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 播放页（全屏 + 右上角一个 X，照全站直播房同一套 ✅）
class PandaRoomPage extends StatefulWidget {
  const PandaRoomPage({super.key, required this.room});

  final PandaRoom room;

  @override
  State<PandaRoomPage> createState() => _PandaRoomPageState();
}

class _PandaRoomPageState extends State<PandaRoomPage> {
  KpPlayer? _kp;

  /// 等待文案（★ 2026-10-27 用户要求：三个直播站统一改成「正在鸡速加载中…」）
  ///
  /// 🛢️ 旧实现的坑：`open()` 一返回就 `_err = ''` ⇒ 文案消失，但那时**画面还没出来**
  ///   （mpv 的 open 只是"指令收下了"）⇒ 用户看到黑屏干等。
  ///   ⇒ 现在只在 **position > 0（真出画面）** 时清掉；`open()` 返回不动它。
  String _err = kLiveLoadingText;

  /// ★ 2026-10-27（用户实测：**只有 PandaTV 会断**，提示「直播流打不开」）：
  ///   自动重开次数（最多 3 次）。断流是这站 AWS IVS 的常态，重开一次基本就回来了。
  int _retry = 0;
  static const int _kMaxRetry = 3;

  /// 重开进行中（⚠️ 必须有：`_onTick` 在一次 error 状态下会被回调**几十次**
  ///   ⇒ 没有这个闸门，`_retry` 会在毫秒内烧完 3 次，等于没重试 ☠）
  bool _reopening = false;

  final ValueNotifier<bool> _showX = ValueNotifier<bool>(false);
  Timer? _hideX;

  void _toggleX() {
    _showX.value = !_showX.value;
    _hideX?.cancel();
    if (_showX.value) {
      _hideX = Timer(const Duration(seconds: 3), () {
        if (mounted) _showX.value = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _hideX?.cancel();
    _showX.dispose();
    _kp?.removeListener(_onTick);
    _kp?.shutdown();
    _kp = null;
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    final s = _kp?.value;
    if (s == null) return;
    // ★ 真出画面（position > 0）才清掉等待文案，并重置重试计数
    if (s.position > Duration.zero) {
      if (_err.isNotEmpty) setState(() => _err = '');
      _retry = 0;
      _reopening = false;
      return;
    }
    // ★ 出错（断流/403）⇒ 自动重开，而不是直接判死
    if (s.error) {
      if (_reopening) return; // 重开中：忽略重复的 error 回调（否则计数会被瞬间烧完）
      if (_retry < _kMaxRetry) {
        _retry++;
        _reopening = true;
        if (AppSettings.i.logConsole) {
          debugPrint('[PANDA] 断流重开 第$_retry/$_kMaxRetry 次');
        }
        setState(() => _err = kLiveLoadingText);
        unawaited(_reopen());
        return;
      }
      if (_err.isEmpty) setState(() => _err = '直播流打不开');
    }
  }

  /// 重开（复用同一个 KpPlayer ⇒ 不重建纹理、不闪黑）
  Future<void> _reopen() async {
    final kp = _kp;
    if (kp == null) {
      _reopening = false;
      return;
    }
    try {
      _pinHeaders(kp); // 重开前再钉一次头（断流多半就是头丢了）
      await kp.open(widget.room.url);
    } catch (_) {
    } finally {
      // 给 3 秒观察窗：这期间若出画面，`_onTick` 会清 `_reopening`；
      // 若仍无画面、仍是 error，下一次回调才能再触发重试 ✅
      await Future<void>.delayed(const Duration(seconds: 3));
      _reopening = false;
    }
  }

  /// 🛢️ 把请求头写成 mpv 的 `http-header-fields` 属性，并**撤掉点播专用参数**
  ///
  /// 依据（本轮实测，逐条 curl 对照）：
  ///
  /// ① 这个 CDN（AWS IVS）**只认 `Origin`**：
  ///    `Origin` 在 ⇒ 200/206；`Origin` 缺（哪怕 Referer 在）⇒ **403 + 响应体 `origin required`**
  ///
  /// ② 🛢️ **卡顿的真正病根：`tuneStartupQuiet` 那套 reconnect 是为点播长文件设计的**
  ///    （`player_widget.dart:771-775`，注释原文 "不要加 reconnect_at_eof（点播正常结束会被当成断流）"）
  ///    但这里下发的是 `reconnect=1,reconnect_streamed=1`：
  ///      · FFmpeg 文档：`reconnect=1` = "Reconnect automatically when disconnected **BEFORE EOF**"
  ///      · `reconnect_streamed=1` = "even streamed/non seekable streams will be reconnected on errors"
  ///    **HLS 直播是"几百个独立 HTTP 请求"**，每个分片读完就是一次 EOF/连接结束
  ///    ⇒ 播放器日志实测就是被这套参数搅成：
  ///      `Will reconnect at 0 in 1 second(s), error=End of file.`
  ///      `Will reconnect at 0 in 3 second(s), error=End of file.`
  ///      → `HTTP error 403 Forbidden`（重连时头丢了）→ 判死 → 再重连 → **几秒一卡**
  ///    ⇒ 而**脚本 `panda直播.js` 一个 mpv 参数都不传**（实测 grep：全文件无 mpv/reconnect/cache），
  ///      全用播放器默认 ⇒ 在支持它的软件里流畅 ✅
  ///    ⇒ 这里**恢复成默认**（下发空串覆盖掉父级的设置）
  ///
  /// ③ `cache-pause-initial` / `demuxer-lavf-*` 保留（那三个只影响"起播探测耗时"，对直播无害）
  void _pinHeaders(KpPlayer kp) {
    final fields = <String>[
      'User-Agent: $kPandaUA',
      'Referer: https://www.pandalive.co.kr/',
      'Origin: https://www.pandalive.co.kr',
    ].join(',');
    kp.setMpvOptionQuiet('http-header-fields', fields);
    // 与 Origin 保持同一口径（原来全局 `referrer` 会被设成分片自身域名，两边矛盾）
    kp.setMpvOptionQuiet('referrer', 'https://www.pandalive.co.kr/');
    // ★ 撤掉点播专用的重连参数（见上面 ② ⇒ 直播 HLS 上它是卡顿来源）
    kp.setMpvOptionQuiet('stream-lavf-o', '');
    // ⚠️ mpv 手册明写「Unknown or misspelled options are silently ignored」
    //   ⇒ 静默失效无法从"没报错"判断 ⇒ 这里**读回自证一次**（只在控制台日志开时）
    if (AppSettings.i.logConsole) {
      unawaited(_verifyPinned(kp, fields));
    }
  }

  /// 读回刚钉的属性值（只读、失败静默；用于确认没被静默忽略）
  Future<void> _verifyPinned(KpPlayer kp, String expectHeaders) async {
    try {
      final h = await kp.debugMpvProperty('http-header-fields');
      final r = await kp.debugMpvProperty('referrer');
      final s = await kp.debugMpvProperty('stream-lavf-o');
      debugPrint('[PANDA] 头读数 期望头=$expectHeaders');
      debugPrint('[PANDA] 读回 http-header-fields=${h.length > 120 ? '${h.substring(0, 120)}…' : h}');
      debugPrint('[PANDA] 读回 referrer=$r  stream-lavf-o=[$s]');
    } catch (_) {}
  }

  Future<void> _open() async {
    final kp = KpPlayer(bufferMb: 64);
    _kp = kp;
    kp.addListener(_onTick);
    KpPlayer.tuneStartupQuiet(kp);
    _pinHeaders(kp); // ★ 必须在 open 之前钉（mpv 打开流时才读这些属性）
    if (!mounted) return;
    setState(() {});
    try {
      // ⚠️ 这里不再传 httpHeaders：改为上面的 `http-header-fields` 属性，
      //   避免"Media 头"与"属性头"两套并存时竞争（实测断流就出在这里）
      await kp.open(widget.room.url);
      // ⚠️ 这里**不再清** `_err`（open 返回 ≠ 出画面，交给 `_onTick` 的 position 判断）
      if (AppSettings.i.logConsole) {
        debugPrint('[PANDA] 开播 主播=${widget.room.nick} 回放=${widget.room.isRec}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '直播流打不开：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final kp = _kp;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (kp != null)
              Positioned.fill(
                child: Video(
                  controller: kp.videoController,
                  fit: BoxFit.contain,
                  controls: NoVideoControls,
                  fill: Colors.black,
                ),
              )
            else
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            // ★ 2026-10-27（用户要求）：文案要**屏幕居中**（原来我放在 bottom:40 是错的）
            if (_err.isNotEmpty)
              Positioned.fill(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _err,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: Color(0xFFB0B4BA)),
                    ),
                  ),
                ),
              ),
            // 点屏幕显示/隐藏 X（左边缘 24 让给 iOS 侧滑返回）
            Positioned.fill(
              left: 24,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleX,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: _showX,
                builder: (_, show, __) => !show
                    ? const SizedBox.shrink()
                    : SafeArea(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                                12, math.max(0.0, kToolbarHeight / 2 - 38), 5, 12),
                            child: Material(
                              color: Colors.transparent,
                              shape: const CircleBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => Navigator.of(context).pop(),
                                child: const SizedBox(
                                  width: 76,
                                  height: 76,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: SizedBox(
                                      width: 36,
                                      height: 36,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Color(0x73000000),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Icon(Icons.close,
                                              color: Colors.white, size: 32),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
