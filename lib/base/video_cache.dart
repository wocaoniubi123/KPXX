import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';

/// **预下载缓存**（用户 2026-10-03 定："**单实例 + 缓冲五条**" ✓）
///
/// 为什么要它：
/// - mpv 只把**当前这一条**缓进内存（demux cache ✓），**不读**我们 App 的 HTTP 缓存 ✗；
/// - 用第二个 mpv 实例做预缓冲被用户明确否掉 ✗（"多实例更费资源" ✓）。
/// → 所以走**预下载到本地文件** ✓：后台把后面几条的 **mp4 直链**拉到沙盒里，
///   划到它时把 `file://` 交给**同一个** mpv ✓（mpv 读本地文件没有任何问题 ✓）。
///
/// ⚠️ 三条边界（都有意为之）：
/// 1. **只接直链 mp4** ✓ —— m3u8（HLS）是分段播放列表，要逐段下再合并 ✗ → 直接**跳过** ✗，
///    那种源仍旧在线播放 ✓（行为与今天完全一样 ✓）。
/// 2. **只有"下完的"才给播放器用** ✓ —— 下到一半的文件，如果 mp4 的 `moov` 在**文件尾部** ✗，
///    mpv 会播到一半断掉 ✗（`sim-dev` 提过这个风险 ✓）。下载先写 `.part`，整份下完才**改名**成
///    `.mp4` ✓；`ready()` 只认 `.mp4` ✓ —— 没下完就回落 `http` 直连 ✓（后台继续下 ✓）。
///    这样**不需要**去探测 moov 位置 ✓（探测只能覆盖"恰好 faststart"的文件 ✗）。
/// 3. **静默** ✓ —— 下载失败/超限一律不抛错、不打扰界面 ✓（顶多没预缓冲，播放照旧 ✓）。
class VideoCache {
  VideoCache._();

  /// 单例（全局只有一个窗口/一份目录 ✓）
  static final VideoCache i = VideoCache._();

  // ---- 上限（都是有意定的值 ✓）----
  /// 单文件上限：超过就不预下 ✓（短片不该有这么大 ✗，别为一个源把带宽/磁盘吃光 ✗）
  static const int maxFileBytes = 32 * 1024 * 1024;
  /// 目录总量上限（LRU 清到它以下 ✓）
  static const int maxTotalBytes = 320 * 1024 * 1024;
  /// 最多保留的文件个数（LRU ✓）
  static const int maxFiles = 24;
  /// 并发下载条数：**2** ✓ —— 留带宽给"正在播的那条" ✗（抢带宽反而更卡 ✗）
  static const int concurrent = 2;
  /// 半截 `.part` 的最长存活时间（App 被杀掉留下的残渣 ✓）
  static const Duration partTtl = Duration(hours: 1);

  Directory? _dir;
  final Map<String, File> _ready = {}; // url → 已经下完的文件 ✓
  final Set<String> _want = {}; // 当前窗口想要的 url ✓
  final Set<String> _running = {}; // 正在下 ✓
  final List<String> _queue = []; // 待下（按窗口顺序 ✓）
  bool _pumping = false;

  /// 建目录 + 清一次 LRU ✓（进短片页时调一次即可；重复调只会再清一次 ✓）
  Future<void> init() async {
    if (_dir == null) {
      try {
        final t = await getTemporaryDirectory();
        final d = Directory('${t.path}/kpxx_video_cache');
        if (!await d.exists()) await d.create(recursive: true);
        _dir = d;
      } catch (_) {
        _dir = null; // 拿不到目录 → 整个缓存功能静默失效 ✓
      }
    }
    await prune();
  }

  /// **下完的**本地文件（没有/没下完 → null ✓）。**同步**：`_open` 里要用 ✓
  File? ready(String url) {
    final hit = _ready[url];
    if (hit != null && hit.existsSync()) return hit;
    final dir = _dir;
    if (dir == null) return null;
    final f = File('${dir.path}/${_keyOf(url)}.mp4');
    if (f.existsSync()) {
      _ready[url] = f;
      return f;
    }
    return null;
  }

  /// 设置**预下载窗口**（调用方按播放顺序传后面的几条 ✓）。
  /// 窗口外的东西会被**中止** ✓（用户快速连划时省带宽 ✓）；窗口内的继续下 ✓。
  Future<void> window(List<String> urls) async {
    await init();
    _want
      ..clear()
      ..addAll(urls.where((u) => u.isNotEmpty));
    _queue.removeWhere((u) => !_want.contains(u));
    for (final u in _want) {
      if (_ready.containsKey(u) || _running.contains(u) || _queue.contains(u)) {
        continue;
      }
      if (!_isDirectMp4(u)) continue; // m3u8/HLS 跳过 ✗（见类注释 ✓）
      _queue.add(u);
    }
    _pump();
  }

  void _pump() {
    if (_pumping) return;
    _pumping = true;
    Future(() async {
      try {
        while (_queue.isNotEmpty && _running.length < concurrent) {
          final u = _queue.removeAt(0);
          if (!_want.contains(u)) continue;
          _running.add(u);
          _download(u).whenComplete(() {
            _running.remove(u);
            _pump(); // 空出并发位 → 继续下一个 ✓
          });
        }
      } finally {
        _pumping = false;
      }
    });
  }

  Future<void> _download(String url) async {
    final dir = _dir;
    if (dir == null) return;
    final part = File('${dir.path}/${_keyOf(url)}.part');
    final done = File('${dir.path}/${_keyOf(url)}.mp4');
    try {
      if (await done.exists()) {
        _ready[url] = done;
        return;
      }
      final resp = await Site.httpClient
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return;
      final len = resp.contentLength ?? 0;
      if (len > maxFileBytes) return; // 太大 → 不预下 ✓
      final out = part.openWrite();
      var got = 0;
      var aborted = false;
      try {
        await for (final chunk in resp.stream) {
          if (!_want.contains(url) || got + chunk.length > maxFileBytes) {
            aborted = true; // 已被划走 / 超上限 → 不再收 ✓
            break;
          }
          got += chunk.length;
          out.add(chunk);
        }
      } finally {
        await out.close();
      }
      if (aborted) {
        try {
          await part.delete();
        } catch (_) {}
        return;
      }
      await part.rename(done.path); // 整份下完才"变成"可播文件 ✓
      _ready[url] = done;
      await prune();
    } catch (_) {
      // 静默 ✓：失败=没有预缓冲，播放照旧走在线 ✓
      try {
        await part.delete();
      } catch (_) {}
    }
  }

  /// LRU：清过期 `.part` + 按"最后修改时间"新→旧留，超条数/超总量就删尾 ✓
  Future<void> prune() async {
    final dir = _dir;
    if (dir == null) return;
    try {
      final entries = <MapEntry<File, DateTime>>[];
      final now = DateTime.now();
      for (final e in await dir.list().toList()) {
        if (e is! File) continue;
        DateTime m;
        try {
          m = await e.lastModified();
        } catch (_) {
          continue;
        }
        if (e.path.endsWith('.part')) {
          if (now.difference(m) > partTtl) {
            try {
              await e.delete();
            } catch (_) {}
          }
          continue;
        }
        entries.add(MapEntry<File, DateTime>(e, m));
      }
      entries.sort((a, b) => b.value.compareTo(a.value)); // 新 → 旧 ✓
      var total = 0;
      for (var n = 0; n < entries.length; n++) {
        final f = entries[n].key;
        var len = 0;
        try {
          len = await f.length();
        } catch (_) {}
        total += len;
        if (n >= maxFiles || total > maxTotalBytes) {
          try {
            await f.delete();
          } catch (_) {}
          _ready.removeWhere((_, v) => v.path == f.path);
        }
      }
    } catch (_) {}
  }

  /// 只认**直链 mp4** ✓（去掉 query 再看后缀 ✓）
  static bool _isDirectMp4(String url) {
    final p = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return p.endsWith('.mp4');
  }

  /// url → 稳定文件名（FNV-1a ✓：不依赖 `String.hashCode` 的进程内实现 ✓，无需额外依赖 ✓）
  static String _keyOf(String url) {
    var h = 0x811c9dc5;
    for (final c in utf8.encode(url)) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}
