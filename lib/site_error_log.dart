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

  static Future<File?> _file() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/kpxx_error.log');
    } catch (_) {
      return null;
    }
  }

  /// 超限时：把文件裁成"**末尾 [keepBytes]**" ✓（用户 2026-10-05 拍板；原来是整篇清空 ✗）
  ///
  /// **算法（从哪裁、怎么不切中文）**：
  /// 1. 按**字节**读末尾 `keepBytes`（`RandomAccessFile` ✓ 不整篇读进内存 ✗）；
  /// 2. 从这段字节的**头往后**扫到**第一个换行**（`0x0A`）✓ —— UTF-8 里 `0x0A` **只可能是换行本身**
  ///    （多字节序列的每个字节都 ≥ `0x80` ⇒ **绝不会出现在一个汉字的中间** ✓）⇒ 从换行**之后**开始取 ✓
  ///    ⇒ 只要不是"整段一个换行都没有"（256KB 不可能 ✗），结果一定**从完整的一行开头**起 ✓ 不会切到半个字 ✓；
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
        if (start >= bytes.length) return; // 这段里没有换行（不可能发生在 256KB 上 ✗）→ 这次不裁 ✓
        final tail = utf8.decode(bytes.sublist(start + 1), allowMalformed: true);
        await f.writeAsString(tail, flush: true);
      } finally {
        await raf.close();
      }
    } catch (_) {
      // 裁失败 = 不动文件 ✓（**不再有"清空"这条路径** ✗）
    }
  }

  /// **写日志串行队列**（⚠️ 2026-10-05 加：修"半截行" ✗）——
  /// `log()` 原来是 `exists()` + `length()` + `append` 的**读改写** ✓，**并发调用会交错/丢行** ✗
  /// （用户给的日志里就有一行**只剩半截**、还带 3 个坏字节 ⇒ 文件不再是合法 UTF-8 ⇒ 页面读不出来 ✗✗）。
  /// 做法：所有写入**串到一条 `Future` 链上** ✓（前一次写完才跑下一次 ✓）⇒ 写入之间天然互斥 ✓；
  ///   而 `_trimTail` 是在 `_write()` **内部**调的 ✓ ⇒ **裁剪与追加也互斥** ✓（不会"边裁边追加" ✗）。
  /// ⚠️ 绝不引入新依赖 ✓；任何一段抛错都被兜住 ✓（链子不会断 ✓）。
  static Future<void> _q = Future<void>.value();

  /// 写一条（**排队** ✓ 见 [_q] 说明 ✓）
  static Future<void> log(String siteName, Object error, [StackTrace? st]) {
    final next = _q.then((_) => _write(siteName, error, st)).catchError((Object _) {});
    _q = next;
    return next;
  }

  static Future<void> _write(String siteName, Object error, [StackTrace? st]) async {
    try {
      final f = await _file();
      if (f == null) return;
      if (await f.exists() && await f.length() > maxBytes) {
        await _trimTail(f); // ★ 2026-10-05：超限 → **保留末尾 256KB** ✓（原来这里是 `writeAsString('')` 整篇清空 ✗）
      }
      final t = DateTime.now();
      final ts = '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
      final first = st?.toString().split('\n').take(3).join(' <- ') ?? '';
      await f.writeAsString(
        '[$ts] [$siteName] $error${first.isEmpty ? '' : '\n    $first'}\n',
        mode: FileMode.append,
        flush: true,
      );
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
    try {
      final f = await _file();
      if (f != null && await f.exists()) await f.writeAsString('', flush: true);
    } catch (_) {}
  }
}
