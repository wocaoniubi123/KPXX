import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// **公共错误日志** ✓（用户 2026-10-03 要求）
///
/// 每次站点出错，就往 App 沙盒里的 `kpxx_error.log` **追加一行**：
/// ```
/// [时间] [站点名] 错误信息
/// ```
/// 目的：出问题时**一眼看出是哪个站挂了、什么时候挂的** ✓（此前错误只在 UI 上闪一下 ✗）。
///
/// ⚠️ 设计约束：
/// - **绝不抛错** ✓ —— 记日志本身失败就静默忽略 ✓（否则会把主流程带崩 ✗）
/// - **不阻塞 UI** ✓ —— 调用方 `await` 即可，写入很快；失败也不影响取数 ✓
/// - 文件超过 [maxBytes] ⇒ **只保留末尾 [keepBytes]** ✓（**用户 2026-10-05 拍板**：
///   原来是"整篇清空" ✗ —— 一旦被灌大就变成"**反复清空**"，用户看到的是"什么日志都没有" ✗）
class SiteErrorLog {
  SiteErrorLog._();

  /// 单文件上限：**5 MB** ✓（**用户 2026-10-05 拍板**："改成 5mb 吧，也影响不了什么" ✓ 原话）
  /// —— 原是 512 KB ✗；超限就**裁成末尾 [keepBytes]** ✓（不再整篇清空 ✗）
  static const int maxBytes = 5 * 1024 * 1024;

  /// 超限时保留的末尾长度：**约一半（≈2.5 MB）** ✓（用户拍板 ✓ —— 留下最新那半段 ✓ 够看最近的复现 ✓）
  static const int keepBytes = maxBytes ~/ 2;

  /// ★ 2026-10-22（用户实测"开日志进出站点有几率卡"）：
  ///   `_file()` 原来**每次都调** `getApplicationDocumentsDirectory()`（Platform Channel + 平台实现），
  ///   而 Windows 上这个目录一直取不到（日志文件从未落盘，实测 4 个常见路径都没有）⇒ 每次都在**抛异常/等待**。
  ///   批量写之后每 400ms 就会调一次 ⇒ 表现为"开了日志就偶发卡"。
  ///   ⇒ 缓存结果：**成功 ⇒ 记住路径；失败 ⇒ 记住"不可用"（以后一次都不再试）**。
  static String? _cachedPath; // null = 还没查过；'' = 确认不可用

  static Future<File?> _file() async {
    final c = _cachedPath;
    if (c != null) return c.isEmpty ? null : File(c);
    try {
      final dir = await getApplicationDocumentsDirectory();
      _cachedPath = '${dir.path}/kpxx_error.log';
      return File(_cachedPath!);
    } catch (_) {
      _cachedPath = ''; // 不可用 ⇒ 以后不再调用平台通道
      return null;
    }
  }

  /// 超限时：把文件裁成"**末尾 [keepBytes]**" ✓（用户 2026-10-05 拍板；原来是整篇清空 ✗）
  ///
  /// **算法（从哪裁、怎么不切中文）**：
  /// 1. 按**字节**读末尾 `keepBytes`（`RandomAccessFile` ✓ 不整篇读进内存 ✗）；
  /// 2. 从这段字节的**头往后**扫到**第一个换行**（`0x0A`）✓ —— UTF-8 里 `0x0A` **只可能是换行本身**
  ///    （多字节序列的每个字节都 ≥ `0x80` ⇒ **绝不会出现在一个汉字的中间** ✓）⇒ 从换行**之后**开始取 ✓
  ///    ⇒ 只要不是"整段一个换行都没有"（**现在读的是 `keepBytes`，即 `maxBytes ~/ 2` ≈ 2.5MB**
  ///    ✓ 见 `:24` `maxBytes = 5 * 1024 * 1024` 与 `:27 keepBytes = maxBytes ~/ 2` ⇒ 这么大的段里不可能没有换行 ✗
  ///    —— 保留段越大越安全 ✓），结果一定**从完整的一行开头**起 ✓ 不会切到半个字 ✓；
  /// 3. 再 `utf8.decode(..., allowMalformed: true)` ✓（多一层保险：万一有残字节也只是替换成 � ✗ 不会抛 ✓）；
  /// 4. `writeAsString(tail, flush: true)` **覆写** ✓ ⇒ 之后 `log()` 继续用 `FileMode.append` 追加 ✓ 逻辑不变 ✓。
  ///
  /// ⚠️ 整段失败就**什么都不做** ✓：宁可这次不裁（下次超限再试 ✓），也**绝不整篇清空** ✗、绝不把主流程带崩 ✓。
  static Future<void> _trimTail(File f) async {
    try {
      final len = await f.length();
      if (len <= keepBytes) return;
      final raf = await f.open();
      try {
        await raf.setPosition(len - keepBytes);
        final bytes = await raf.read(keepBytes); // 读不到满额也照用 ✓
        var start = 0;
        while (start < bytes.length && bytes[start] != 0x0A) {
          start++;
        }
        if (start >= bytes.length) return; // 这段里没有换行（**≈2.5MB 的 `keepBytes` 上不可能** ✗ 见 `:44`）→ 这次不裁 ✓
        final tail = utf8.decode(bytes.sublist(start + 1), allowMalformed: true);
        await f.writeAsString(tail, flush: true);
      } finally {
        await raf.close();
      }
    } catch (_) {
      // 裁失败 = 不动文件 ✓（**不再有"清空"这条路径** ✗）
    }
  }

  /// **写日志串行队列**（⚠️ 2026-10-05 加：修"半截行" ✗）
  /// 做法：所有**落盘**串到一条 `Future` 链上 ⇒ 写入之间天然互斥 ✅；`_trimTail` 也在链内 ✅。
  static Future<void> _q = Future<void>.value();

  /// ★ 2026-10-22（用户实测："我都不敢开日志了，卡死"）：
  ///   **根因**：原来**每条**日志都做 `_file()` + `exists()` + `length()` + `writeAsString(flush: true)`,
  ///   即 **4 次系统调用 + 强制同步落盘**；`[IMG]/[LIST]/[PLAY]` 一开就是每秒几十上百条 ⇒ UI 卡死 ☠。
  ///   **改法**：
  ///     · 日志先进内存缓冲（[_buf]），**攒满 [_flushEvery] 条 或 过了 [_flushDelay] 才一次性 append**
  ///       （`flush: false`，交给系统刷盘，不阻塞）；
  ///     · 裁剪检查（`exists()+length()`）**每 [_trimEvery] 批才做一次**，不再每条都查；
  ///     · `read()` / `clear()` 前先 `await _flush()`，保证看到的是最新内容 ✅。
  ///   代价：进程被强杀时最多丢 400ms / 16 条日志（可接受 ✅）。
  static final StringBuffer _buf = StringBuffer();
  static int _bufCount = 0;
  static bool _flushScheduled = false;
  static int _sinceTrimCheck = 0;
  static const int _flushEvery = 16;
  static const int _trimEvery = 200;
  static const Duration _flushDelay = Duration(milliseconds: 400);

  /// 写一条（**入内存缓冲 ⇒ 批量落盘** ✓ 见上面 2026-10-22 说明 ✓）
  static Future<void> log(String siteName, Object error, [StackTrace? st]) {
    try {
      final t = DateTime.now();
      final ts = '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
      final first = st?.toString().split('\n').take(3).join(' <- ') ?? '';
      _buf.write(
          '[$ts] [$siteName] $error${first.isEmpty ? '' : '\n    $first'}\n');
      _bufCount++;
    } catch (_) {
      return Future<void>.value();
    }
    if (_bufCount >= _flushEvery) {
      return _flush();
    }
    if (!_flushScheduled) {
      _flushScheduled = true;
      Future<void>.delayed(_flushDelay, _flush); // 到点异步刷（不 await）
    }
    return Future<void>.value();
  }

  /// 把缓冲一次性追加到文件（走 [_q] 串行链，与裁剪互斥）
  static Future<void> _flush() async {
    _flushScheduled = false;
    if (_buf.isEmpty) return;
    final text = _buf.toString();
    _buf.clear();
    _bufCount = 0;
    final next = _q.then((_) => _append(text)).catchError((Object _) {});
    _q = next;
    await next;
  }

  static Future<void> _append(String text) async {
    try {
      final f = await _file();
      if (f == null) return;
      // 裁剪检查：每 [_trimEvery] 批才查一次（原来每条都 exists+length ☠）
      if (_sinceTrimCheck <= 0) {
        _sinceTrimCheck = _trimEvery;
        if (await f.exists() && await f.length() > maxBytes) {
          await _trimTail(f);
        }
      }
      _sinceTrimCheck--;
      // flush: false ⇒ 不强制落盘（交给系统缓冲）⇒ 不再阻塞 UI
      await f.writeAsString(text, mode: FileMode.append, flush: false);
    } catch (_) {
      // 记日志失败**不影响主流程** ✓
    }
  }

  /// 读回来（给"设置页/调试"或用户手动查看用 ✓）
  /// ⚠️ 2026-10-05（用户实测真相反转：**日志一直在写、是"读不出来"** ✗）：
  ///   文件里有 **3 个坏字节**（含一行开头被切掉 ⇒ 整个文件不是合法 UTF-8 ✗）⇒ 原来这里的
  ///   `f.readAsString()` 是**严格 UTF-8** ⇒ 直接抛 ⇒ 页面**整页空白** ✗✗（看着像"没有日志"）。
  ///   ⇒ 现在：**按字节读 + `utf8.decode(allowMalformed: true)`** ✓（坏字节显示成 `�` ✓ 绝不整页空白 ✓）；
  ///   并且**失败要说出来** ✗：拿不到目录 / 读失败都返回一句看得懂的提示 ✓（只有"真的还没写过"才返回空 ✓）。
  static Future<String> read() async {
    await _flush(); // ★ 2026-10-22：先把内存缓冲落盘，读到的才是最新内容
    try {
      final f = await _file();
      if (f == null) return '（读日志失败：拿不到 App 文档目录 ✗）';
      if (!await f.exists()) return ''; // 真的还没写过 ⇒ 空态 ✓（与"读失败"分清 ✓）
      final bytes = await f.readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      return '（读日志失败：$e ✗）';
    }
  }

  /// 日志文件在沙盒里的**绝对路径**（方便用户去"文件"App 里找 ✓）
  static Future<String> path() async => (await _file())?.path ?? '(不可用)';

  /// 清空
  static Future<void> clear() async {
    // ★ 2026-10-22：先落盘再清，并清掉内存缓冲（否则清空后缓冲里那批又会被写回去）
    await _flush();
    _buf.clear();
    _bufCount = 0;
    try {
      final f = await _file();
      if (f != null && await f.exists()) await f.writeAsString('', flush: true);
    } catch (_) {}
  }
}
