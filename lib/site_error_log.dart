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
/// - 文件超过 [maxBytes] 就**截断重来** ✓（防止无限增长撑爆沙盒 ✗）
class SiteErrorLog {
  SiteErrorLog._();

  /// 单文件上限（512 KB ✓）—— 超了就清空重写 ✓
  static const int maxBytes = 512 * 1024;

  static Future<File?> _file() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/kpxx_error.log');
    } catch (_) {
      return null;
    }
  }

  /// 写一条：**时间 + 站点名 + 错误信息**（+ 可选堆栈 ✓）
  static Future<void> log(String siteName, Object error, [StackTrace? st]) async {
    try {
      final f = await _file();
      if (f == null) return;
      if (await f.exists() && await f.length() > maxBytes) {
        await f.writeAsString('', flush: true); // 截断 ✓
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
  static Future<String> read() async {
    try {
      final f = await _file();
      if (f == null || !await f.exists()) return '';
      return await f.readAsString();
    } catch (_) {
      return '';
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
