import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置（双击快进秒数、播放缓冲大小）。
/// 单例 + ChangeNotifier：设置页改完，播放器下次用的时候就能取到新值。
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings i = AppSettings._();

  /// 双击快进/快退档位（默认 10 秒）
  static const List<int> stepOptions = [5, 10, 15];
  static const int defaultStep = 10;
  static const String _kStep = 'seek_step';

  /// 播放缓冲档位（MB，默认 200）
  static const List<int> bufferOptions = [100, 200, 500, 1024];
  static const int defaultBufferMb = 200;
  static const String _kBuffer = 'buffer_mb';

  int _step = defaultStep;
  int get step => _step;

  int _bufferMb = defaultBufferMb;
  int get bufferMb => _bufferMb;

  /// 档位显示名：1024 显示成 1G
  static String bufferLabel(int mb) => mb >= 1024 ? '1G' : '${mb}MB';

  /// 启动时读一次；读不到就用默认值
  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      var changed = false;
      final v = sp.getInt(_kStep);
      if (v != null && stepOptions.contains(v) && v != _step) {
        _step = v;
        changed = true;
      }
      final b = sp.getInt(_kBuffer);
      if (b != null && bufferOptions.contains(b) && b != _bufferMb) {
        _bufferMb = b;
        changed = true;
      }
      if (changed) notifyListeners();
    } catch (_) {
      // 读失败保持默认值
    }
  }

  Future<void> setStep(int v) async {
    if (!stepOptions.contains(v) || v == _step) return;
    _step = v;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_kStep, v);
    } catch (_) {
      // 存失败也不影响本次会话使用
    }
  }

  Future<void> setBufferMb(int v) async {
    if (!bufferOptions.contains(v) || v == _bufferMb) return;
    _bufferMb = v;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_kBuffer, v);
    } catch (_) {
      // 存失败也不影响本次会话使用
    }
  }
}
