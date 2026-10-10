/// KPXX · **Windows 桌面开发入口**（☠ **不是发布入口** —— 发布仍是 `lib/main.dart` ✓）
///
/// 用途（用户 2026-10-09 方向 ✓）：在**桌面上**改界面 / 调布局 / 试手势，省掉"每次出 ipa 上真机" ✓。
/// ⚠️ iOS 侧的一切**一个字不动** ✗：发布入口还是 `lib/main.dart`，CI 也照旧只打 `main.dart` ✓；
///   本文件只在**显式指定** `-t lib/main_win_dev.dart` 时才会被编译 ✓（Dart 按入口可达性编译 ✓）。
///
/// ★ 跑法（本机**没把 flutter 加进 PATH** ✓ 约束 ⇒ 用全路径 ✓）：
///   `G:\flutter\bin\flutter.bat run -d windows -t lib/main_win_dev.dart`
///
/// ★★ device_preview 的用法**逐条照 3.0.0 的源码/README** ✓（☠ 不能凭记忆：**3.x 换过 API**）：
///   - **老 API** 是 `DevicePreview(builder: …)` 包一层 widget ✗ —— **3.0.0 里根本没有这个构造器**
///     （照记忆写 ⇒ 编译不过 ⇒ 白跑一轮 CI ☠）。
///   - **现 API** = `DevicePreview.enable()` → **装 binding** ✓（`src/binding/binding.dart:601` 原文签名：
///     `static WidgetsBinding enable({bool? enabled, EdgeInsets padding = EdgeInsets.zero,`
///     `  Decoration? backgroundDecoration = const DotGridDecoration()})` ✓）；
///     它**顶替** `WidgetsFlutterBinding.ensureInitialized()` ✓ —— 文档原文（同文件 `:556-557`）：
///     "Enables device simulation, then initializes (once) and returns the ambient binding."
///     / "Call this before `runApp`." ✓
///   - **起始设备**：文档原文（`:597-599`）"To start from a given simulation before the first frame …
///     apply it through the controller right after enabling" ✓
///     ⇒ `applyPreset(DevicePresets.iPhone16ProMax)` ✓
///     （preset 常量出处：`lib/src/presets.g.dart:926` `static const DevicePreset iPhone16ProMax` ✓，
///      由 `package:device_preview/presets.dart` 里的 `part 'src/presets.g.dart';` 带进来 ✓
///      ⇒ 必须 **单独 import `presets.dart`** ✓ —— 它**不在** `device_preview.dart` 的导出里 ✓）。
///   - **`maybeController`** ✗ 不是 `controller` ✓：release 构建里仿真**整个关掉**
///     ⇒ `controller` 会抛 `StateError` ☠（文档 `:622-633` ✓），`maybeController` 才是 null 版 ✓。
library;

import 'dart:async'; // Timer（⑥ 探针用）/ unawaited ✓
import 'dart:convert'; // jsonEncode（照 AppBg 的索引形状写 ✓）
import 'dart:io'; // File / Directory / Platform ✓
import 'dart:typed_data'; // Uint8List ✓
import 'dart:ui' as ui; // PictureRecorder / ImageByteFormat.png（现画现编 ✓ 零外部素材 ✓）

import 'package:device_preview/device_preview.dart';
import 'package:device_preview/presets.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart'; // 与 AppBg 同源的 documents 目录 ✓
import 'package:shared_preferences/shared_preferences.dart'; // 写图集索引 ✓
import 'package:video_player/video_player.dart'; // ★ 只给 ⑥ 的 dev 探针读 `VideoPlayerController.value` ✓

import 'app_bg.dart';
import 'config.dart'; // ★ Site.devClientOverride（h2 通道挂载点 ✓ 只有本入口会写 ✓）+ Site.ua（探针要照房间页带 UA ✓）
import 'favorites.dart'; // ★ 收藏（与发布入口同一份存储 ✅ 不读出来就会被"保存"覆盖掉 ☠）
import 'main.dart'
    show KpxxApp; // ★ 复用发布入口**同一个**根 widget ✓（☠ 绝不复制一份 UI 树 —— 复制必然走样 ✓）
import 'main_win_dev_h2.dart'; // ★ dev 专用 h2 通道（只给 hanime1.me ✓）
import 'main_win_dev_soak.dart'; // ★ 内存泄漏补测探针（dev-only，`KPXX_SOAK` 驱动 ✓ 见下方 ⑥z）
import 'main_win_dev_video.dart'; // ★ dev 专用 video_player 平台实现（media_kit / libmpv ✓ 见下方 ⓪c）
import 'player_widget.dart'; // ★ KpPlayer.startupVolumeOverride（桌面 dev 静音挂载点 ✓）
import 'sites/xhamsterlive.dart'
    show LiveRoomPage; // ★ 只给下面的「直开直播间」探针用 ✓（**不改它一个字** ✓）
import 'settings.dart';

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// ★ 2026-10-09（用户拍板 **B 方案** ✓）：给**桌面 dev** 播种两张纯色背景（纯黑 / 纯白）
//   —— 用户口径原文：**只碰 Windows 桌面端、共享代码不许动** ✓；要的是"**图集里默认就有**" ✓
//      （**不是**走相册上传那条路 ✓ —— 那条要用户手动点选择器 ✓ 达不到"自带" ✓）。
//
// ☠ **为什么必须自己写文件 + 自己写索引**（而不是调 `AppBg` 的公开口）：读遍 `app_bg.dart` 的公开面，
//   **没有任何"把字节加进图集"的入口** ✗ —— 唯一进图集的公开路是 `addFromGallery()`（系统相册选择器 ✓
//   需用户交互 ☠）；`useDirectImage()` 的文档明写"**立即应用，但不进图集**" ☠（`app_bg.dart:365` ✓）
//   ⇒ 想让"图集里默认就有"，只能**照它现有的存储契约**自己写一份 ✓（= B 方案 ✓）。
//
// 【契约逐条照抄 `AppBg`（**不是自创结构** ✓，每条都给了出处）】
//   · 索引键   = `'bg_album'`            ← `app_bg.dart:61` `static const String _kAlbum = 'bg_album';`
//   · 索引形状 = `[{"file":…,"t":…}]`    ← `app_bg.dart:592-596` `sp.setString(_kAlbum, jsonEncode([{'file': it.file, 't': it.t}]))`
//   · 目录     = `documents/bg_album/`   ← `app_bg.dart:64` `_albumDirName = 'bg_album'` + `:554-555` 目录创建
//   · 名字**必须以 `.jpg` 结尾**          ← `app_bg.dart:577` `if (rel.isEmpty || !rel.endsWith('.jpg')) continue;`
//        ☠ 所以：**内容是 PNG、文件名仍是 `.jpg`** ✓ —— Flutter 的 `FileImage` **按内容解码** ✓
//        （用户要求"格式必须 PNG、不能 AVIF" ✓ —— AVIF 桌面上还解不了、会红叉 ✓）
//   · 名字以 `bg_` 开头                   ← `app_bg.dart:249` 清扫孤儿图时**只动** `bg_*.jpg`（在索引里 ⇒ 永不被删 ✓）
//   · 上限 20                            ← `app_bg.dart:59` `static const int maxAlbum = 20;`
//   · 相对路径分隔符一律 `/`              ← `app_bg.dart:65` `_sep = '/'`（跨平台无歧义 ✓）
//
// ☠ **B 方案的代价（已回报 ✓）**：这是**私有契约的复制** ✗ —— `AppBg` 将来若改存储结构，
//   这里会**静默失效**（不报错、图集里就是没有那两张 ✓）。**排查时先怀疑这里** ✓。
// ═══════════════════════════════════════════════════════════════════════════════════════════════
const String _kAlbumKey = 'bg_album'; // = AppBg._kAlbum（契约复制 ☠ 见上）
const String _kAlbumDirName = 'bg_album'; // = AppBg._albumDirName
const int _kAlbumMax = 20; // = AppBg.maxAlbum

/// 播种条目的**可辨认名字**（用户要求"在 t 或文件名上能辨认" ✓）：一眼看出是播种的、不是用户加的 ✓。
///   ⚠️ 刻意**不带** `_<10位以上数字>.jpg` 尾巴 ⇒ `AppBg._stampFromName` 解析为 null ✓
///      （它的调用方对 null 有兜底"改用文件 mtime" ✓ `app_bg.dart:222-227` ✓ ⇒ 安全 ✓）。
const String _kSeedBlackName = 'bg_seed_black.jpg';
const String _kSeedWhiteName = 'bg_seed_white.jpg';

/// 播种条目的时间戳：**固定值** ✓ —— 幂等好判 ✓、且**不会每次启动生成新 t 把图集灌满** ✓
///   （2020-01-01 UTC，远早于任何真实用图 ✓）；我们**append 在末尾** ⇒ 也**不会插到用户自己的图前面** ✓。
const int _kSeedT = 1577836800000;

/// 现画一张 64×64 纯色图并编成 **PNG** 字节（`dart:ui` ✓ —— 与本仓 `online_album_common.dart:_cropPng`
///   同一套做法：`PictureRecorder → Canvas.drawRect → toImage → toByteData(png)` ✓）。
///   ⚠️ 尺寸 64 的依据：纯色图**任意尺寸**全屏拉满都一样 ✓；而 `app_bg.dart:118` 那条"取 32px 判明暗"
///   的路径对 64×64 就是缩到 32 再算 ✓ 不会崩 ✓（用 1×1 也能跑，但 64 更"正常"、肉眼也看不出差别 ✓）。
Future<Uint8List> _solidPng(Color color, int n) async {
  final rec = ui.PictureRecorder();
  final cv = Canvas(rec, Rect.fromLTWH(0, 0, n.toDouble(), n.toDouble()));
  cv.drawRect(
      Rect.fromLTWH(0, 0, n.toDouble(), n.toDouble()),
      Paint()
        ..color = color
        ..isAntiAlias = false);
  final img = await rec.endRecording().toImage(n, n);
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return bd!.buffer.asUint8List();
}

/// 播种（**幂等** ✓ / **不删不挤**用户条目 ✓ / 必须在 `AppBg.i.load()` **之前**跑 ✓）：
///   ① 读现有索引（**原样保留** ✓ —— 只 append ✓，绝不重写/排序用户条目 ✓）
///   ② 逐张：文件不在 ⇒ 补写（索引在、文件丢 ⇒ 自愈 ✓）；索引里没有 ⇒ 登记 ✓
///   ③ 图集**已满 20** ⇒ **宁可少这两张，也不挤掉用户自己的图** ✓（只打日志 ✓）
Future<void> _seedDesktopAlbum() async {
  final docs =
      await getApplicationDocumentsDirectory(); // 与 AppBg.load() 同一个 base ✓
  final dir = Directory('${docs.path}${Platform.pathSeparator}$_kAlbumDirName');
  if (!await dir.exists()) await dir.create(recursive: true);
  final sp = await SharedPreferences.getInstance();

  // ① 原样读出现在的索引（只认 `file`/`path` 两种键 ✓ 与 AppBg._parseAlbum 同口径 ✓）
  final list = <Map<String, Object>>[];
  final raw = sp.getString(_kAlbumKey);
  if (raw != null && raw.isNotEmpty) {
    final j = jsonDecode(raw);
    if (j is List) {
      for (final e in j) {
        if (e is Map) {
          final f = e['file'] ?? e['path'];
          if (f is String && f.isNotEmpty) {
            final t = e['t'];
            list.add({'file': f, 't': t is int ? t : 0});
          }
        }
      }
    }
  }
  var changed = false;

  // ② 两张种子（顺序：先黑后白 ✓ —— 图集是"新加的排最前"，我们 append 在末尾 ⇒ 显示顺序即黑、白 ✓）
  //
  // ⚠️ 2026-10-09 的**一段教训**（留着防回退 ☠）：共享代码 `app_bg.dart:_sweepOrphans()` 原来是
  //   `keep = {for (final it in _album) _abs(it.file)}`（`_abs = '$_root$_sep$rel'`、`_sep='/'`）
  //   与目录枚举拿到的 `e.path`（Windows 上全反斜杠 ✓）**做字符串比较** ⇒ **恒不相等** ⇒
  //   图集目录里**每个** `bg_*.jpg` 都会被当孤儿删掉 ☠（本入口第一次播种就这样被删光 ☠ 实测 ✓）。
  //   ⇒ 那处已在共享侧修好（**两边都过 `_norm()` 规范化分隔符** ✓ 见 `app_bg.dart` 里 `_norm` 的注释 ✓，
  //     对 iOS 是 no-op ✓）⇒ 本入口**按仓里惯用的 `/` 形态存**（与 `addFromGallery` 同形 ✓）就能存活 ✓。
  //   ☠ **若哪天那处修复被回退** ⇒ 这两张会再次在下次启动被删 ⇒ **先怀疑 `app_bg.dart:_norm`** ✓
  //     （另外：那种情况下**用户自己加的图集图片也会被删** ✓ 不是本入口的问题 ✗）。
  //   另：下面按 basename 找旧条目并改写成规范形态 ✓（自愈早期用平台分隔符写下的那条 ✓）；
  //      判重也按 basename ✓（否则同一张会被加两遍、把 20 上限吃掉 ☠）。
  String baseName(String p) => p.split(RegExp(r'[/\\]')).last;
  final seeds = <({String name, Color color})>[
    (name: _kSeedBlackName, color: const Color(0xFF000000)),
    (name: _kSeedWhiteName, color: const Color(0xFFFFFFFF)),
  ];
  for (final s in seeds) {
    final f = File('${dir.path}${Platform.pathSeparator}${s.name}');
    if (!await f.exists()) {
      final bytes = await _solidPng(s.color, 64);
      await f.writeAsBytes(bytes, flush: true);
      debugPrint('[WIN-DEV] 播种背景：写文件 ${s.name}（${bytes.length}B PNG）✓');
    }
    final want =
        '$_kAlbumDirName/${s.name}'; // ★ 规范形态（与 AppBg.addFromGallery 一致 ✓）
    // 先看有没有"同名但形态不同"的旧条目 ⇒ 就地改写成规范形态 ✓
    final at = list.indexWhere((e) => baseName(e['file'] as String) == s.name);
    if (at >= 0) {
      if (list[at]['file'] != want) {
        list[at] = {'file': want, 't': _kSeedT};
        changed = true;
        debugPrint('[WIN-DEV] 播种背景：改写旧条目 ${s.name} → $want ✓');
      } else {
        debugPrint('[WIN-DEV] 播种背景：已在图集里（跳过）${s.name} ✓');
      }
      continue; // 幂等：一张不加 ✓
    }
    if (list.length >= _kAlbumMax) {
      debugPrint('[WIN-DEV] 播种背景：图集已满 ${list.length}/$_kAlbumMax ⇒ 跳过 ${s.name}'
          '（**不挤掉用户自己的图** ✓）');
      continue;
    }
    list.add({'file': want, 't': _kSeedT});
    changed = true;
    debugPrint('[WIN-DEV] 播种背景：登记 ${s.name} ✓');
  }

  if (changed) await sp.setString(_kAlbumKey, jsonEncode(list));

  // ③ 「当前背景」若正是这两张之一 ⇒ 也规范化成同一形态 ✓ ——
  //    否则图集页那句 `currentPath == it.file` 的**选中标记**会对不上 ☠（`_abs()` 仍能解析 ⇒ 背景照旧显示 ✓）。
  //    ⚠️ 必须也跑在 `AppBg.i.load()` **之前** ✓（`load()` 里那句 `File(_abs(cur)).existsSync()` 读的就是它 ✓）。
  final cur = sp.getString('bg_current') ?? '';
  if (cur.isNotEmpty) {
    final b = baseName(cur);
    for (final s in seeds) {
      if (s.name == b) {
        final wantCur = '$_kAlbumDirName/${s.name}';
        if (cur != wantCur) {
          await sp.setString('bg_current', wantCur);
          debugPrint('[WIN-DEV] 播种背景：规范当前背景条目 → $wantCur ✓');
        }
        break;
      }
    }
  }

  debugPrint(
      '[WIN-DEV] 播种背景：完成（索引 ${list.length}/$_kAlbumMax 条，本次改动=$changed）');
}

Future<void> main() async {
  // ① 装 binding —— 就是发布入口 `main.dart:18` 那行 `WidgetsFlutterBinding.ensureInitialized()` 的等价物 ✓
  //   ⚠️ 顺序**必须**是全场第一句 ☠（`MediaKit` / `AppSettings` 那些都要求 binding 先就位 ✓）。
  DevicePreview.enable();

  // ⓪ ★ 2026-10-10（用户拍板 ✓）：把 `hanime1.me` 的取回通道换成 **HTTP/2**（dev 专用 ✓）——
  //    ⚠️ **必须在这里挂**（`runApp` 之前、App 还没发过任何请求 ✓）：`base/fetch.dart:34` 那个
  //       `static final _client = Site.httpClient;` 是**首次访问时快照**的 ✓ ⇒ 晚一步就挂不上 ✓。
  //    ✅ 其余 host **原样委托**给桌面原 client ✓（`Site.httpClient` 此刻 = `_baseClient` ✓）；
  //    ✅ iOS 侧**没有任何代码**写 `devClientOverride` ⇒ 那边取值与行为逐字节不变 ✓。
  Site.devClientOverride = DevHanimeH2Client(Site.httpClient);

  // ⓪b ★ 2026-10-10（用户拍板 ✓ 长期规则）：**桌面 dev 默认静音** —— 他旁边有人，测试时不许出声 ✓。
  //    ⇒ 给播放器自己的初始音量设 0（✗ 不动系统全局音量 ✓ 那是用户明确禁止的 ✓）。
  //    ⚠️ 必须在 `runApp` 之前设 ✓（`KpPlayer` 构造时读它 ✓）；iOS 同名字段恒为 null ⇒ 那边一字不变 ✓。
  KpPlayer.startupVolumeOverride = 0;

  // ⓪c ★ 2026-10-10（用户拍板 ✓）：**桌面 dev 的直播间播放** —— 把 `video_player` 的平台实现
  //    换成 dev 专用的 **media_kit / libmpv** 版（`lib/main_win_dev_video.dart` ✓）。
  //    ☠ 为什么非补不可：房间页 `sites/xhamsterlive.dart` 用的是 `video_player`，而它在 **Windows 上
  //      没有任何实现** ✗（pub 上没有 `video_player_windows`）⇒ 平台实例恒为包里的 placeholder
  //      ⇒ `initialize()` 抛 `UnimplementedError` ⇒ 房间页只剩一行错误文案（黑屏）✗。
  //    ✅ **接口仍是 `video_player` 的接口** ⇒ `lib/sites/**` **一个字不用改** ✓；
  //    ✅ **iOS 零影响**：发布入口 `lib/main.dart` 里没有这一行、本文件也只在 `-t` 显式指定时才编译 ✓。
  //    ⚠️ 顺序：放在 `KpPlayer.startupVolumeOverride = 0` **之后** ✓ —— 本实现在 `create()` 时读它当初始音量
  //       （桌面 dev 恒静音 ✓，且房间页那句显式 `setVolume(1.0)` 在本实现里会被压回 0 ✓ 见该文件文件头 ✓）。
  installMediaKitVideoPlayerPlatform();

  // ② 播放引擎：★ 2026-10-09（用户要求"Windows 也能播" ✓）已补 **`media_kit_libs_windows_video`**
  //    ⇒ 桌面和 iOS 一样有原生库（`libmpv-2.dll` 由那个包在**构建时**下载并用 CMake 装进产物 ✓）
  //    ⇒ 这一句**应当成功** ✓（成功会打一行 `就绪 ✓`；失败说明那个包没装上/没编进来 ⇒ 见 catch 里的原文 ✓）。
  //    ⚠️ 仍然**包一层 try/catch** ✓：万一用户手工删了依赖、或在别的机器上没装 ⇒ 本入口**不许白屏** ✗
  //      （看界面/调布局这条主用途不能被"播放能力缺失"拖死 ✓）。
  try {
    MediaKit.ensureInitialized();
    debugPrint('[WIN-DEV] 播放引擎（MediaKit / libmpv）就绪 ✓');
  } catch (e) {
    debugPrint(
        '[WIN-DEV] MediaKit.ensureInitialized() 失败（查 media_kit_libs_windows_video 是否装上）：$e');
  }

  // ②b ★ 2026-10-09（用户拍板 **B 方案** ✓）：给桌面 dev 播种纯黑/纯白两张背景 ——
  //    ⚠️ **必须跑在下面 ③ 的 `AppBg.i.load()` 之前** ☠：同一个进程内**先把索引写好**，`load()` 才会
  //       把这两张当成图集里的现成条目读进来 ✓（顺序反了就白播 ✓）。
  //    ⚠️ 自带 try/catch ✓：播种失败**绝不许**挡着看界面 ✗（图集少两张 << 整个入口起不来 ✓）。
  try {
    await _seedDesktopAlbum();
  } catch (e) {
    debugPrint('[WIN-DEV] 播种纯色背景失败（已拦，不影响看界面）：$e');
  }

  // ③ 与发布入口 `main.dart:23/66/70/72` **逐条对齐**的四件加载
  //   （**顺序也照抄** ✅：设置 → 播放记录 → **收藏**（2026-10-10 新增 ✅）→ 背景图 ✅）
  //   ⚠️ 但**各自兜一层** ☠ —— 2026-10-09 桌面冒烟**实测**（不是瞎防 ✓），`PlayHistory.load()` 会抛：
  //      `'package:kpxx/settings.dart': Failed assertion: line 393 pos 12:`
  //      `'messy!.videoIndex == 0 && messy.updatedAt == 0': 非 int 数字退化`
  //      ⇒ 那是 `load()` 开头那句**纯逻辑自检**（`assert(() { _selfCheck(); return true; }())` ✓）在 debug 下被触发：
  //        它要求"`{'ts': 5.0}` 这种非 int 数字**退化到 0**"✗，而 `PlayRecord.fromJson` 的
  //        `int sec(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0)`（`settings.dart:220` ✓）
  //        是**照 `toInt()` 收下的（5.0 ⇒ 5）** ⇒ **自检与实现互相矛盾** ☠。
  //      ⚠️ 这是**发布代码（`lib/settings.dart`）的既有问题** ✗ —— **不归本入口**：
  //        真机跑的是 release（assert 被整段剥掉 ⇒ 从没暴露 ✓），CI 只 `analyze` 不跑 ⇒ 也照不到 ✓；
  //        两种修法**语义不同**（让 `sec()` 对非 int 返 0 ✗ / 还是改自检的期望值 ✓）⇒ 要 lead/用户拍板 ✓。
  //      ⇒ 本入口只负责**别让这行噪音/中断挡着看界面** ✓：接住、把原文打进控制台、继续往下跑 ✓。
  /// ⚠️⚠️ **必须 `await`** ☠（第一版写错了、冒烟实测才发现 ✓）：三个 `load()` 都是 `async`
  ///   （`settings.dart:60/258`、`app_bg.dart:164` ✓）⇒ `async` 函数里抛出的异常会变成
  ///   **"被拒的 Future"** ✗、**不是同步抛** ⇒ 只写 `try { f(); } catch` ⇒ catch 永远不触发 ☠、
  ///   而那个 Future 没人 await ⇒ 引擎照打一行 `Unhandled Exception`（`dart_vm_initializer.cc:40` ✓）。
  ///   ⇒ 加 `await` 才是真接住 ✓（第二版实测：那行 Unhandled Exception 消失 ✓）。
  Future<void> tryLoad(String what, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      debugPrint('[WIN-DEV] $what 加载抛了（已拦，不影响看界面）：$e');
    }
  }

  await tryLoad('设置（AppSettings）', AppSettings.i.load);
  await tryLoad('播放记录（PlayHistory）', PlayHistory.i.load);
  // ★ 2026-10-10（收藏 ✅）：发布入口也加了这一行（`main.dart` 的 `Favorites.i.load()`）⇒ 本入口照抄同序 ✅。
  //   ⚠️ **必须有** ☠：收藏页/详情页那颗星要在 `load()` 之后才能写盘；没读出来就 save ⇒ 会把用户已有收藏覆盖掉。
  await tryLoad('收藏（Favorites）', Favorites.i.load);
  await tryLoad('背景图（AppBg）', AppBg.i.load);

  // ☑️ 这里原来有一段"在 `load()`（= 清扫）之后再补写种子文件 + 重新应用当前背景"的**绕法** ✗ ——
  //    **已删除** ✓：因为共享侧 `_sweepOrphans()` 的分隔符 bug 已修（`app_bg.dart` 的 `_norm` ✓），
  //    种子文件在 `load()` 的清扫里会被正确**保留** ⇒ 绕法没有任何作用了 ✓（留着反而是死代码 ☠）。
  //    ⚠️ 若哪天发现种子又不见了 ⇒ **先看那处修复是否被回退** ✓（判别：用户自己加的图集图片是否也被删 ✓）。
  // ④ 图片缓存预算 —— 与发布入口 `main.dart:73` **同一行同一值** ✓
  //    （⚠️ 不设就吃框架默认 **100MB** ☠；桌面一样按 48MB 走 ⇒ 与真机同口径 ✓）
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20;

  // ⑤ 起始设备 = **iPhone 16 Pro Max**（用户口径 ✓ 与真机同款屏 ✓）——**首帧之前**就位 ✓
  final dp = DevicePreview.maybeController;
  if (dp != null) await dp.applyPreset(DevicePresets.iPhone16ProMax);

  // ⑥z ★ 2026-10-10（**内存泄漏补测轮** ✓ dev-only ✓ 全部代码在新文件 `main_win_dev_soak.dart` 里）：
  //    `KPXX_SOAK=<player|avif|scroll|live>`（**运行时环境变量** ✓ 不用 --dart-define ⇒ 一次编译跑完所有场景 ✓）
  //    ⇒ 起对应探针并 return（不再起正常 UI ✓）；不定义 ⇒ 它第一句就返回 false ⇒ 下面 ⑥ 一字不变 ✓。
  //    ⚠️ 挂钩点在 ④（imageCache 48MB）之后 ✓ —— 项3 要的正是"48MB 上限下缓存怎么收敛" ✓。
  if (await runSoakIfRequested()) return;

  // ⑥ ★ 2026-10-10（**dev 探针** ✓ 只为验证"桌面能播 xHamster 直播"这条链路）：
  //    `--dart-define=KPXX_LIVE_ROOM=<id>[:<username>]` ⇒ 起来后**直接进那个直播间** ✓
  //      （`username` 可省 —— 房间页只用它当 WebView 兜底地址，取流只靠 `id` ✓ `liveMasterUrl` 是纯拼串 ✓）
  //    `--dart-define=KPXX_LIVE_ROOM_EXIT_SECS=<n>`（配上面那个用）⇒ n 秒后**把房间页从树上摘掉** ✓
  //      —— 这条是"退出房间后播放器被释放"那张证据的来源（摘掉 ⇒ 房间页 `dispose()` ⇒ `c.dispose()` ✓）。
  //    ☠ 不定义 `KPXX_LIVE_ROOM` ⇒ **本段整体跳过**、`runApp` 那一行**逐字节不变** ✓；
  //    ☠ 走的是**真页面**（`sites/xhamsterlive.dart` 的 `LiveRoomPage` 本体 ✓）、**业务代码一个字没改** ✓
  //      ⇒ 验的就是真链路（与"从列表页进房"唯一差别只是"谁 push 的" ✓）。
  const roomSpec = String.fromEnvironment('KPXX_LIVE_ROOM');
  // ⑥a 【第三条探针】`--dart-define=KPXX_LIVE_ROOMS=<id1>:<name1>,<id2>:<name2>,…`
  //      + `KPXX_LIVE_ROOM_EXIT_SECS=<每房停留秒数>`：**一个进程里依次进 N 个直播间、逐房释放** ✓
  //      —— 一次跑完就能看出"哪些房间现在真能播"（直播状态随时会变，单房一个进程太慢 ✓）。
  const roomList = String.fromEnvironment('KPXX_LIVE_ROOMS');
  // ⑥b 【第二条探针】`--dart-define=KPXX_HLS_URL=<url>`（配合 `KPXX_LIVE_ROOM_EXIT_SECS`）
  //     直接拿 URL 驱动 **`video_player` 的公开 API**（`VideoPlayerController.networkUrl` ✓）——
  //     这条**完全绕开站点取流链**，量的是"本文件新写的那个平台实现"本身：
  //     有没有 initialized、position 会不会前进、`VideoPlayer` 出不出画、`setVolume` 被不被压 ✓。
  const hlsUrl = String.fromEnvironment('KPXX_HLS_URL');
  if (hlsUrl.isNotEmpty) {
    debugPrint('[WIN-DEV] 探针：直接用 video_player 播 $hlsUrl');
    runApp(MaterialApp(
      title: 'kpxx',
      theme: ThemeData(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: const _HlsProbePage(url: hlsUrl),
    ));
  } else if (roomList.isNotEmpty) {
    debugPrint('[WIN-DEV] 探针：依次进多个直播间 $roomList');
    runApp(MaterialApp(
      title: 'kpxx',
      theme: ThemeData(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: const _LiveRoomProbe(rooms: roomList),
    ));
  } else if (roomSpec.isEmpty) {
    runApp(const KpxxApp()); // ★ 与发布入口**同一个** `KpxxApp` ✓（`main.dart:74` 那个 ✓）
  } else {
    final parts = Uri.decodeComponent(roomSpec).split(':');
    final roomId = int.tryParse(parts.first.trim());
    final roomName = parts.length > 1 ? parts[1].trim() : '';
    if (roomId == null) {
      debugPrint(
          '[WIN-DEV] KPXX_LIVE_ROOM 解析失败（要 <id>[:<username>]）：$roomSpec ✗');
      runApp(const KpxxApp());
    } else {
      debugPrint(
          '[WIN-DEV] 探针：直接进直播间 id=$roomId name=${roomName.isEmpty ? '(空)' : roomName}');
      runApp(MaterialApp(
        title: 'kpxx',
        theme: ThemeData(useMaterial3: true),
        debugShowCheckedModeBanner: false,
        home: const _LiveRoomProbe(rooms: roomSpec),
      ));
    }
  }
}

/// dev 探针壳（**只在 `KPXX_LIVE_ROOM` 定义时才存在** ✓）：装 [LiveRoomPage] 本体 ✓，
/// 并按需在 N 秒后把它**从树上摘掉**（= 等价"退出房间" ✓ ⇒ 房间页 `dispose()` 跑 ⇒ 播放器该被释放 ✓）。
///
/// 顺带打两个自证读数（**不依赖 AppSettings.logConsole** ✓ —— 探针要能自己说清楚有没有在播 ✓）：
///   · `VideoPlayerController` 的 `value.position` / `volume` / `isInitialized` / `errorDescription` ✓
///   · 进程 RSS（`ProcessInfo.currentRss` ✓）—— 给"退出后无残留"当旁证 ✓
class _LiveRoomProbe extends StatefulWidget {
  const _LiveRoomProbe({required this.rooms});

  /// 逗号分隔的 `id:name` 列表（一间也行 ✓）
  final String rooms;

  @override
  State<_LiveRoomProbe> createState() => _LiveRoomProbeState();
}

class _LiveRoomProbeState extends State<_LiveRoomProbe> {
  static const int _exitSecs = int.fromEnvironment('KPXX_LIVE_ROOM_EXIT_SECS');

  /// 待进房间（`id:name` ✓，逗号分隔 ⇒ 支持串行多房 ✓）
  late final List<String> _rooms =
      widget.rooms.split(',').where((e) => e.trim().isNotEmpty).toList();

  int _idx = -1;

  /// 这一间现在**在不在树上**（`false` ⇒ 房间页被摘掉 ⇒ 它 `dispose()` 跑 ⇒ 播放器该被释放 ✓）
  bool _showRoom = false;
  VideoPlayerController? _c;
  Timer? _tick;
  Timer? _exit;
  int _n = 0;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 2), (_) => _sample());
    _advance();
  }

  /// 进下一间（或全部跑完 ⇒ 打收尾读数 ✓）
  void _advance() {
    if (!mounted) return;
    _idx++;
    _c = null;
    if (_idx >= _rooms.length) {
      debugPrint(
          '[WIN-PROBE] ★ 全部房间跑完（${_rooms.length} 间）⇒ 5 秒后读最终 RSS（此时所有播放器都该已释放 ✓）');
      Timer(const Duration(seconds: 5), () {
        debugPrint('[WIN-PROBE] ★ 最终 RSS=${ProcessInfo.currentRss ~/ 1024} KB');
        if (mounted) setState(() {});
      });
      return;
    }
    debugPrint(
        '[WIN-PROBE] ── 进第 ${_idx + 1}/${_rooms.length} 间：${_rooms[_idx].trim()}');
    setState(() => _showRoom = true);
    if (_exitSecs > 0) {
      _exit = Timer(const Duration(seconds: _exitSecs), () {
        if (!mounted) return;
        // ★ 先把房间页**从树上摘掉**（⇒ 它 `dispose()` ⇒ `c.dispose()` ✓），再把读数打出来
        setState(() => _showRoom = false);
        debugPrint(
            '[WIN-PROBE] ★ 退出房间 #$_idx（rss=${ProcessInfo.currentRss ~/ 1024}KB）');
        // 给 media_kit 的收尾留时间（它自己 `Player.dispose()` 里有 5 秒的 terminate 延迟 ✓），再进下一间
        Timer(const Duration(seconds: 8), _advance);
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _exit?.cancel();
    super.dispose();
  }

  /// 每次 tick 从树里捞一次"房间页当前那套 controller" ✓（房间页把 `_c` 私有 ✗，
  /// 所以只能从 `VideoPlayer` 子树里拿 —— **只读观测** ✓ 不碰它的状态机 ✓）。
  void _adoptController() {
    void walk(Element e) {
      if (_c != null) return;
      final w = e.widget;
      if (w is VideoPlayer) {
        final c = w.controller;
        if (!identical(c, _c)) {
          _c = c;
          debugPrint('[WIN-PROBE] 抓到 controller #$_idx ✓（开始每 2 秒读数）');
        }
        return;
      }
      e.visitChildren(walk);
    }

    (context as Element).visitChildren(walk);
  }

  void _sample() {
    _adoptController();
    final c = _c;
    final rss = ProcessInfo.currentRss ~/ 1024;
    final tag = '#$_idx';
    if (c == null) {
      debugPrint(
          '[WIN-PROBE] $tag #${++_n} 还没有 controller（正在取流/未出画）RSS=${rss}KB');
      return;
    }
    final v = c.value;
    debugPrint('[WIN-PROBE] $tag.${++_n} initialized=${v.isInitialized} '
        'size=${v.size.width.toInt()}x${v.size.height.toInt()} '
        'position=${v.position.inMilliseconds}ms duration=${v.duration.inMilliseconds}ms '
        'isPlaying=${v.isPlaying} volume=${v.volume} '
        'err=${v.errorDescription ?? '(无)'} RSS=${rss}KB');
  }

  @override
  Widget build(BuildContext context) {
    if (!_showRoom || _idx < 0 || _idx >= _rooms.length) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('已退房（探针）', style: TextStyle(color: Color(0xFFB0B4BA))),
        ),
      );
    }
    final parts = _rooms[_idx].split(':');
    return LiveRoomPage(
      // ⚠️ 用 Key 逼 Flutter **换一个全新的 State**（否则同一 State 换 id ⇒ 不会重新取流 ✓）
      key: ValueKey<int>(_idx),
      username: parts.length > 1 ? parts[1].trim() : '',
      id: int.tryParse(parts.first.trim()) ?? 0,
    );
  }
}

/// ⑥b 的探针页：**绕开站点**，直接驱动 `video_player` 公开 API（`VideoPlayerController.networkUrl` ✓）——
/// 用一段给定的 HLS/mp4 验"平台实现本身"：`initialize()` 能不能成、position 会不会前进、
/// `VideoPlayer` 出不出画、`setVolume(1.0)` 被不被压 ✓（读的都是 controller 自己的 `value` ✓）。
class _HlsProbePage extends StatefulWidget {
  const _HlsProbePage({required this.url});
  final String url;

  @override
  State<_HlsProbePage> createState() => _HlsProbePageState();
}

class _HlsProbePageState extends State<_HlsProbePage> {
  static const int _exitSecs = int.fromEnvironment('KPXX_LIVE_ROOM_EXIT_SECS');

  VideoPlayerController? _c;
  Timer? _tick;
  Timer? _exit;
  int _n = 0;
  String _stage = '建控制器';

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 2), (_) => _sample());
    _boot();
  }

  Future<void> _boot() async {
    try {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        httpHeaders: const <String, String>{'User-Agent': Site.ua},
      );
      _c = c;
      _stage = 'initialize() 中';
      await c.initialize().timeout(const Duration(seconds: 20));
      _stage = 'initialize() 成功 ⇒ setVolume(1.0) + play()';
      // ★ 这里刻意跟**房间页 `xhamsterlive.dart:1026`** 一样要 1.0 —— 用来验证"被 dev 静音压住" ✓
      await c.setVolume(1.0);
      await c.play();
      _stage = '已 play()';
      if (mounted) setState(() {});
      if (_exitSecs > 0) {
        _exit = Timer(const Duration(seconds: _exitSecs), () {
          // ☠ 关键：**必须照房间页 `dispose()` 那套显式收**（`sites/xhamsterlive.dart:890-897` ✓）——
          //    只把 `VideoPlayer` 从树上拿掉**不会**释放（那是 `Video` 自己的 dispose ✓），
          //    `VideoPlayerController` 是 `_HlsProbePageState` 持有的，得有人调它 ✓（第一版漏了这步 ✓）。
          debugPrint(
              '[WIN-PROBE] ★ 摘播放器 —— 照房间页 dispose() 那套：removeListener + c.dispose() ✓');
          final c = _c;
          _c = null;
          if (mounted) setState(() {});
          if (c == null) {
            debugPrint('[WIN-PROBE] ✗ 没有 controller 可释放');
            return;
          }
          c.removeListener(() {});
          unawaited(c
              .dispose()
              .then((_) => debugPrint('[WIN-PROBE] ← c.dispose() 返回 ✓'))
              .catchError((Object e) {
            debugPrint('[WIN-PROBE] ← c.dispose() 抛了：$e');
            return null;
          }));
          Timer(const Duration(seconds: 4), () {
            debugPrint(
                '[WIN-PROBE] ★ 释放 4 秒后 RSS=${ProcessInfo.currentRss ~/ 1024} KB');
          });
        });
      }
    } catch (e) {
      _stage = '失败：$e';
      debugPrint('[WIN-PROBE] 探针 initialize 失败：$e');
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _exit?.cancel();
    final c = _c;
    _c = null;
    if (c != null) {
      // ⚠️ 埋点：`unawaited` 吞的是"结果"不是"是否卡住" —— 这两行用来判 dispose 走到哪一步 ✓
      debugPrint('[WIN-PROBE] → 调 c.dispose()（video_player 公开 API）');
      unawaited(c
          .dispose()
          .then((_) => debugPrint('[WIN-PROBE] ← c.dispose() 返回 ✓'))
          .catchError((Object e) {
        debugPrint('[WIN-PROBE] ← c.dispose() 抛了：$e');
        return null;
      }));
    }
    super.dispose();
  }

  void _sample() {
    final c = _c;
    final rss = ProcessInfo.currentRss ~/ 1024;
    if (c == null) {
      debugPrint('[WIN-PROBE] #${++_n} 已摘掉控制器 RSS=${rss}KB stage=$_stage');
      return;
    }
    final v = c.value;
    debugPrint('[WIN-PROBE] #${++_n} initialized=${v.isInitialized} '
        'size=${v.size.width.toInt()}x${v.size.height.toInt()} '
        'position=${v.position.inMilliseconds}ms duration=${v.duration.inMilliseconds}ms '
        'isPlaying=${v.isPlaying} volume=${v.volume} '
        'err=${v.errorDescription ?? '(无)'} stage=$_stage RSS=${rss}KB');
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: (c != null && c.value.isInitialized)
            ? AspectRatio(
                aspectRatio:
                    c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
                child: VideoPlayer(c),
              )
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_stage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFB0B4BA))),
              ),
      ),
    );
  }
}
