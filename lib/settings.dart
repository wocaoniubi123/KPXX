import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置（目前一项：双击快进/快退的秒数）。
/// 单例 + ChangeNotifier：设置页改完，播放器下次双击就能取到新值。
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings i = AppSettings._();

  /// 可选档位（默认 10 秒）
  static const List<int> stepOptions = [5, 10, 15];
  static const int defaultStep = 10;
  static const String _kStep = 'seek_step';

  int _step = defaultStep;
  int get step => _step;

  /// 启动时读一次；读不到就用默认值
  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v = sp.getInt(_kStep);
      if (v != null && stepOptions.contains(v) && v != _step) {
        _step = v;
        notifyListeners();
      }
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
}
