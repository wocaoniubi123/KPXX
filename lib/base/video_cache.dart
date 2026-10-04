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
/// 1. **接"直链 mp4" 与 "m3u8"** ✓ —— 后者走 `_downloadHls` ✓（#1 ✓ 2026-10-03 用户拍板 ✓，
///    `sim-dev` 实测：**无 `#EXT-X-KEY`** ✗、**不是短时效** ✓、一条 ≈0.35~1.19MB ✓）
///    转成"**分段落盘 + 本地清单**" ✓；**解析不出来（加密/byterange/嵌套 master）就放弃** ✗
///    → 那种源仍旧在线播放 ✓（与今天完全一样 ✓）。
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
  /// 单文件上限：超过就不预下 ✓（⚠️ B 项：`sim-dev` 实测 `Content-Length` 未到前**别改死** ✗ ——
  /// 首条源是 `…/720p.h264.mp4` ✓，32MB 是旧实现带来的值 ✓（是否放宽 → B 项，等实测数据 ✗））
  static const int maxFileBytes = 32 * 1024 * 1024;
  /// 目录总量上限（LRU 清到它以下 ✓）—— 320 → 640 → 300 → **200MB**（用户 2026-10-03 最终拍板 ✓）
  ///
  /// ⚠️ **两个上限"谁先撞线听谁"** ✓（见 `_prune()` ✓）：从**最新**往旧走 → 累计字节 > 200MB **或** 已留够
  ///    `maxFiles` 个 → **从这里起全部删掉** ✓
  ///    → **实际留下 = min(maxFiles, 累计不超 200MB 的条数)** ✓
  /// 算式（拿 `sim-dev` 2026-10-03 的实测中位数算 ✓）：
  ///   · 全部中位 **2.65MB** → `200 ÷ 2.65 ≈ 75` ✓ → **条数先撞线** → 留 **70 个 ≈ 186MB**（93% ✓）
  ///   · 720p 中位 **4.40MB** → `200 ÷ 4.40 ≈ 45` ✓ → **容量先撞线** → 留 **45 个 ≈ 198MB**
  ///   · 最坏（实测最大 **5.10MB**）→ `200 ÷ 5.10 ≈ 39` ✓ → **至少也留 39 条** ✓
  /// 实测依据 ✓（sim-dev 2026-10-04）：短片单条 **0.35 / 0.82 / 1.19MB**（7 条 m3u8-only 分段实测，
  /// 码率 54~72KB/s）→ 200MB ≈ 最多存 250 条短片，绰绰有余 ✓。
  /// 🔍 推算：39.2s 那条按实测码率 ≈66KB/s 外推 ≈2.53MB（**非实测** ✗）
  static const int maxTotalBytes = 200 * 1024 * 1024;
  /// 最多保留的文件个数（LRU ✓）—— 24 → **70** ✓（就按上面那个算式算的 ✓）
  /// 为什么是 70 而不是 75 ✗：75 是"全部等于中位数"的理想值 ✓，取 70 = **留约 7% 余量** ✓。
  /// 它的作用是"**防一堆小文件把条数撑爆**"的闸 ✓ —— 文件偏大时轮不到它管 ✓（容量会先撞线 ✓）。
  static const int maxFiles = 70;
  /// 并发下载条数：**5** ✓（用户 2026-10-03 拍板"**并发改成 5 试试**" ✓）
  /// ⚠️ 真机若发现**播放变卡** ✗ → **就改这一行**回 1~2 ✓（缓/卡时另有一层"让路" ✓ 见 `pause()` ✓）
  static const int concurrent = 5;
  /// 半截 `.part` 的最长存活时间（App 被杀掉留下的残渣 ✓）
  static const Duration partTtl = Duration(hours: 1);

  Directory? _dir;
  final Map<String, File> _ready = {}; // url → 已经下完的文件 ✓
  final Set<String> _want = {}; // 当前窗口想要的 url ✓
  final Set<String> _running = {}; // 正在下 ✓
  final List<String> _queue = []; // 待下（按窗口顺序 ✓）
  bool _pumping = false;
  /// C ✓：播放器在缓冲时**让路**（停止消费响应流 ✓、进度保留 ✓）
  bool _paused = false;

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
    await _prune();
  }

  /// **下完的**本地文件（没有/没下完 → null ✓）。**同步**：`_open` 里要用 ✓
  /// ⚠️ #1（2026-10-03 用户拍板 ✓）：**mp4 直链**与 **m3u8 转本地**都**只从这一个出口**给 ✓
  /// —— 上层**不分叉** ✗（`_open()` 拿到的永远是"能直接播的本地文件" ✓）。
  File? ready(String url) {
    final hit = _ready[url];
    if (hit != null && hit.existsSync()) return hit;
    final dir = _dir;
    if (dir == null) return null;
    for (final ext in const ['mp4', 'm3u8']) {
      final f = File('${dir.path}/${_keyOf(url)}.$ext');
      if (f.existsSync()) {
        _ready[url] = f;
        return f;
      }
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
      if (!_isDirectMp4(u) && !_isM3u8(u)) continue; // 只接 **mp4 直链** 与 **m3u8**（其余跳过 ✗）
      _queue.add(u);
    }
    _pump();
  }

  void _pump() {
    if (_pumping) return;
    _pumping = true;
    Future(() async {
      try {
        while (!_paused &&
            _queue.isNotEmpty &&
            _running.length < concurrent) {
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

  /// **暂停预下载** ✓（用户 2026-10-03 拍板 C ✓）：播放器在缓冲时调 → 带宽全让给"正在播的那条" ✗。
  /// 做法是**停止消费响应流**（不新起任务 ✓ + 在下的那些在循环里等 ✓）—— TCP 背压会让服务端慢下来 ✓，
  /// 且**不丢进度** ✓（恢复后从原地继续 ✓）。
  void pause() => _paused = true;

  /// 恢复（在下的继续 ✓、待下的接着起 ✓）
  void resume() {
    if (!_paused) return;
    _paused = false;
    _pump();
  }

  /// **放弃某一条** ✓（A 项用 ✓）：`_open()` 发现本地还没就绪、要**在线播**了 ✗ →
  /// 把它从"想要"里摘掉 ✓ → 在下的 `_download` 会走既有的中止分支（删 `.part` ✓）→ 不跟播放抢流量 ✓。
  /// ⚠️ 已经下好的不动 ✓（`_ready` 里的留着 ✓）
  void drop(String url) {
    _want.remove(url);
    _queue.remove(url);
  }

  Future<void> _download(String url) async {
    final dir = _dir;
    if (dir == null) return;
    if (_isM3u8(url)) return _downloadHls(url); // ⚠️ #1：HLS 走另一条路 ✓（下面 mp4 那条**一字不动** ✗）
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
      if (len > maxFileBytes) return; // 太大 → 不预下 ✓（B 项待实测后调 ✓）
      final out = part.openWrite();
      var got = 0;
      var aborted = false;
      try {
        await for (final chunk in resp.stream) {
          // ⚠️ C：被暂停（播放器在缓冲 ✓）→ **不消费**、原地等 ✓（背压生效 ✓、进度不丢 ✓）
          while (_paused && _want.contains(url)) {
            await Future.delayed(const Duration(milliseconds: 400));
          }
          if (!_want.contains(url) || got + chunk.length > maxFileBytes) {
            aborted = true; // 已被划走 / 被 drop / 超上限 → 不再收 ✓
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
      await _prune();
    } catch (_) {
      // 静默 ✓：失败=没有预缓冲，播放照旧走在线 ✓
      try {
        await part.delete();
      } catch (_) {}
    }
  }

  /// LRU：清过期 `.part` + 按"最后修改时间"新→旧留，超条数/超总量就删尾 ✓
  Future<void> _prune() async {
    final dir = _dir;
    if (dir == null) return;
    try {
      final entries = <MapEntry<File, DateTime>>[];
      final now = DateTime.now();
      for (final e in await dir.list().toList()) {
        DateTime m;
        try {
          m = (await e.stat()).modified;
        } catch (_) {
          continue;
        }
        // ⚠️ #1：HLS 的目录形态也要清 ✗（否则 `*.hls` / `*.hls.part` 永远留着 ✗）
        if (e is Directory) {
          if (e.path.endsWith('.part') && now.difference(m) > partTtl) {
            try {
              await e.delete(recursive: true);
            } catch (_) {}
          }
          continue;
        }
        if (e is! File) continue;
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
        // ⚠️ #5 ✓（2026-10-03 用户拍板）：**HLS 分段目录的字节也要计入** ✗ —— 原来只算清单文件
        //（几 KB ✓）→ "200MB 上限"名不副实 ✗。目录与清单同名配对（`x.m3u8` ↔ `x.hls` ✓）
        if (f.path.endsWith('.m3u8')) {
          try {
            final d = Directory('${f.path.substring(0, f.path.length - 5)}.hls');
            if (await d.exists()) {
              for (final g in await d.list().toList()) {
                if (g is File) {
                  try {
                    len += await g.length();
                  } catch (_) {}
                }
              }
            }
          } catch (_) {}
        }
        total += len;
        if (n >= maxFiles || total > maxTotalBytes) {
          try {
            await f.delete();
          } catch (_) {}
          // ⚠️ #1：删到 HLS 清单时，**连它的分段目录一起删** ✓（否则 `*.hls` 永远清不掉 ✗）
          if (f.path.endsWith('.m3u8')) {
            try {
              final d = Directory('${f.path.substring(0, f.path.length - 5)}.hls');
              if (await d.exists()) await d.delete(recursive: true);
            } catch (_) {}
          }
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

  /// m3u8（HLS）✓ —— #1（2026-10-03 用户拍板 ✓）：**不再跳过** ✗，转成本地可播形态 ✓
  static bool _isM3u8(String url) {
    final p = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return p.endsWith('.m3u8');
  }

  /// **m3u8 → 本地可播** ✓（#1 ✓）
  ///
  /// 依据（`sim-dev` 实测 ✓）：① **无 `#EXT-X-KEY`** ✗（7 条样本 0 条加密 ✓）② **不是短时效** ✓
  /// （签名在**路径票据**里 ✓ 约 3.5 小时 ✓；+6 分钟复测同分段仍 200 ✓）③ 体量小 ✓
  /// （分段 3~20、单段 88~180KB、一条 ≈0.35~1.19MB ✓）→ **不用为它放大上限** ✓。
  ///
  /// 流程 ✓：master（`#EXT-X-STREAM-INF`）→ **跟一层**变体 ✓ → 媒体清单 → **逐段下** ✓ →
  /// 写本地清单（分段走**相对路径** `${key}.hls/xxx` ✓，mpv 按清单所在目录解析 ✓）→
  /// 分段目录先 rename ✓、**清单最后 rename** ✓ → **全部下完才算就绪** ✗（`ready()` 只认改名后的 `.m3u8` ✓）。
  /// ⚠️ **不做**：解密 ✗、鉴权重放 ✗（探测证明不需要 ✓）。遇到 `#EXT-X-KEY` / `#EXT-X-BYTERANGE` /
  /// 嵌套 master（变体里还是 `#EXT-X-STREAM-INF` ✓）→ **直接放弃** ✗（= 没预下载，回落在线播 ✓，与今天一样 ✓）。
  /// 分段目录字节**已计入** `maxTotalBytes` ✓（#5 ✓ 2026-10-04：`_prune` 里 `x.m3u8` ↔ `x.hls` 配对求和 ✓）—— 单条实测 0.35~1.19MB ✓
  /// 估最坏多占 ≤200MB ✓；真要精算再给 `_prune` 加目录求和 ✓。
  Future<void> _downloadHls(String url) async {
    final dir = _dir;
    if (dir == null) return;
    final key = _keyOf(url);
    final partDir = Directory('${dir.path}/$key.hls.part');
    final doneDir = Directory('${dir.path}/$key.hls');
    final partPl = File('${dir.path}/$key.m3u8.part');
    final donePl = File('${dir.path}/$key.m3u8');
    try {
      if (await donePl.exists()) return;
      final master = await _hlsText(url);
      if (master == null) return;
      var mediaUrl = url;
      var media = master;
      if (master.contains('#EXT-X-STREAM-INF')) {
        final v = _hlsFirstUri(master);
        if (v == null) return;
        mediaUrl = Uri.parse(url).resolve(v).toString();
        final t = await _hlsText(mediaUrl);
        if (t == null) return;
        media = t;
      }
      if (media.contains('#EXT-X-KEY') || media.contains('#EXT-X-BYTERANGE')) return; // 放弃 ✗
      final segs = _hlsSegmentUris(media);
      if (segs.isEmpty) return; // 嵌套 master / 解析不出 → 放弃 ✗
      if (await partDir.exists()) await partDir.delete(recursive: true);
      await partDir.create(recursive: true);
      var total = 0;
      final names = <String>[];
      for (var i = 0; i < segs.length; i++) {
        // ⚠️ 与 mp4 那条**同款**让路/放弃检查 ✓（C 项 ✓ 请求数不变 ✗）
        while (_paused && _want.contains(url)) {
          await Future.delayed(const Duration(milliseconds: 400));
        }
        if (!_want.contains(url)) return;
        final segUrl = Uri.parse(mediaUrl).resolve(segs[i]).toString();
        final r = await Site.httpClient
            .get(Uri.parse(segUrl))
            .timeout(const Duration(seconds: 20));
        if (r.statusCode != 200 || r.bodyBytes.isEmpty) return;
        total += r.bodyBytes.length;
        if (total > maxFileBytes) return; // 超单文件上限 → 放弃 ✓（与 mp4 同款口径 ✓）
        final name = 'seg_${i.toString().padLeft(4, '0')}.ts';
        await File('${partDir.path}/$name').writeAsBytes(r.bodyBytes, flush: true);
        names.add(name);
      }
      await partPl.writeAsString(
          '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:10\n#EXT-X-MEDIA-SEQUENCE:0\n'
          '${names.map((n) => '#EXTINF:10.0,\n$key.hls/$n\n').join()}'
          '#EXT-X-ENDLIST\n',
          flush: true);
      if (await doneDir.exists()) await doneDir.delete(recursive: true);
      await partDir.rename(doneDir.path); // ① 先搬分段 ✓
      await partPl.rename(donePl.path); // ② 清单最后 → 此刻起 `ready()` 才认 ✓
      _ready[url] = donePl;
      await _prune();
    } catch (_) {
      // 静默 ✓：没预下成 = 回落在线播 ✓（与今天行为一致 ✓）
    } finally {
      try {
        if (await partDir.exists()) await partDir.delete(recursive: true);
      } catch (_) {}
      try {
        if (await partPl.exists()) await partPl.delete();
      } catch (_) {}
    }
  }

  Future<String?> _hlsText(String url) async {
    final r =
        await Site.httpClient.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }

  /// master 里的**第一条变体 URI** ✓（`#EXT-X-STREAM-INF` 之后第一条非注释非空行 ✓）
  static String? _hlsFirstUri(String text) {
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].trim().startsWith('#EXT-X-STREAM-INF')) continue;
      for (var j = i + 1; j < lines.length; j++) {
        final t = lines[j].trim();
        if (t.isEmpty || t.startsWith('#')) continue;
        return t;
      }
      return null;
    }
    return null;
  }

  /// 媒体清单里的**分段 URI** ✓（`#EXTINF` 之后第一条非注释非空行 ✓）；
  /// ⚠️ 一看到 `#EXT-X-STREAM-INF`（= 这其实是 master ✗）就返回空 → 上层放弃 ✓
  static List<String> _hlsSegmentUris(String text) {
    final out = <String>[];
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final t0 = lines[i].trim();
      if (t0.startsWith('#EXT-X-STREAM-INF')) return const [];
      if (!t0.startsWith('#EXTINF')) continue;
      for (var j = i + 1; j < lines.length; j++) {
        final t = lines[j].trim();
        if (t.isEmpty || t.startsWith('#')) continue;
        out.add(t);
        break;
      }
    }
    return out;
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
