// 离线下载 —— isolate 工作进程（每集一个，跑完即退）。
//
// 为什么要把整集下载搬进 isolate：
// AES-128 解密是**同步纯 Dart 计算**（≈32MB/s）：1MB 片 ≈31ms，4 片并发串行解密
// ⇒ 主 isolate 一次被卡 120~250ms（用户实测"点下载卡 UI"）。放到独立 isolate 后，
// 主线程只收 `[done,total]` 进度消息，解密/写盘全在后台，界面不掉帧。
//
// 约定：
// · 每集**一个** isolate，下载结束（成功/失败/被杀）就退出 ⇒ 不做线程池；
// · isolate 里**不用** `Site.httpClient`（iOS 是 cupertino_http，isolate 内初始化有风险），
//   固定用 `package:http` 的纯 `http.Client()`（dart:io 实现）；
// · 请求头（UA/Referer/Cookie）由主 isolate 备好，这里原样传给引擎；
// · 取消 = **消息驱动**：主 isolate 发 `true` 给 worker ⇒ 引擎在检查点抛 `DownloadCancelled`
//   ⇒ catch 里 `raf.close()` 释放 `.part` 句柄 ⇒ 返回 cancelled。
//   ⚠️ **不能**直接 `Isolate.kill(immediate)`（旧做法）：kill 跳过 catch/finally，
//   `.part` 的文件句柄留在进程里 ⇒ 同一进程继续下载，写完 rename 会报
//   errno 32「另一个程序正在使用此文件」（用户实测 91porna 集 0 就栽在这）。
//   极端卡死（worker 5 秒没响应）才 kill 兜底。

import 'dart:async';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'download_engine.dart';

/// 一次下载的结局（取消单独一类，管理器据此标 paused 而不是 failed）。
enum DownloadWorkerStatus { ok, cancelled, error }

class DownloadWorkerResult {
  final DownloadWorkerStatus status;

  /// 成功时的本地文件路径
  final String path;

  /// 失败原因（人话）
  final String error;

  const DownloadWorkerResult._(this.status, this.path, this.error);

  const DownloadWorkerResult.ok(String path)
      : this._(DownloadWorkerStatus.ok, path, '');

  const DownloadWorkerResult.cancelled()
      : this._(DownloadWorkerStatus.cancelled, '', '');

  const DownloadWorkerResult.error(String msg)
      : this._(DownloadWorkerStatus.error, '', msg);
}

/// 主 isolate 手里的句柄：`future` 拿结果，`cancel()` 杀 isolate。
class DownloadWorkerHandle {
  final Future<DownloadWorkerResult> future;
  final void Function() _cancel;

  DownloadWorkerHandle._(this.future, this._cancel);

  /// 取消（幂等）：给 worker 发取消消息 ⇒ 引擎自己在检查点收尾（关文件句柄）；
  /// 5 秒无响应才 `Isolate.kill` 兜底。结果在 worker 收尾后由 future 给出。
  void cancel() => _cancel();
}

class DownloadWorker {
  DownloadWorker._();

  /// 起一个 isolate 下载一集。进度通过 [onProgress] 回到**主 isolate**。
  ///
  /// 参数全部 sendable：URL/headers/destDir/baseName 四个字符串/Map + 两个 SendPort。
  static DownloadWorkerHandle start({
    required String url,
    Map<String, String>? headers,
    required String destDir,
    required String baseName,
    required void Function(int done, int total) onProgress,
  }) {
    final progressPort = ReceivePort();
    final resultPort = ReceivePort();
    final exitPort = ReceivePort();
    final errorPort = ReceivePort();
    final done = Completer<DownloadWorkerResult>();
    Isolate? isolate;
    SendPort? cancelTarget; // worker 回传的"取消消息"端口（优雅取消用）
    var cancelled = false;

    void finish(DownloadWorkerResult r) {
      if (!done.isCompleted) done.complete(r);
    }

    // worker 起来后会把"取消端口"回传过来（优雅取消用）
    final ctrlPort = ReceivePort();
    ctrlPort.listen((p) {
      if (p is SendPort) {
        cancelTarget = p;
        if (cancelled) {
          // 取消发生在 worker 报到之前 ⇒ 现在补发（否则只能等 5s 兜底）
          try {
            p.send(true);
          } catch (_) {}
        }
      }
    });

    progressPort.listen((msg) {
      if (cancelled) return;
      if (msg is List && msg.length >= 2) {
        final d = msg[0];
        final t = msg[1];
        if (d is int && t is int) onProgress(d, t);
      }
    });

    resultPort.listen((msg) {
      if (msg is List && msg.isNotEmpty) {
        if (msg[0] == 'ok' && msg.length >= 2 && msg[1] is String) {
          finish(DownloadWorkerResult.ok(msg[1] as String));
        } else if (msg[0] == 'cancelled') {
          // 引擎按取消收尾（已 close 句柄、保留 .part）⇒ 管理器标 paused
          finish(const DownloadWorkerResult.cancelled());
        } else if (msg[0] == 'err') {
          final reason = msg.length >= 2 ? '${msg[1]}' : '未知错误';
          finish(DownloadWorkerResult.error(reason));
        }
      }
    });

    // worker 硬崩（OOM / 未捕获异常）：不能把 manager 永远挂住。
    // onExit 也会在"正常跑完"时触发，而正常结果消息走另一个端口、顺序不保证 ⇒
    // 延迟一点再判，给 result 消息留出投递时间。
    errorPort.listen((msg) {
      finish(DownloadWorkerResult.error('worker 未捕获异常：$msg'));
    });
    exitPort.listen((_) {
      Timer(const Duration(milliseconds: 500), () {
        finish(const DownloadWorkerResult.error('worker 意外退出（没拿到结果）'));
      });
    });

    void cancel() {
      if (cancelled) return;
      cancelled = true;
      // ① 优先"优雅取消"：worker 收到 true ⇒ 引擎在下一个检查点抛 DownloadCancelled
      //    ⇒ catch/finally 里 close `.part` 句柄（Isolate.kill 漏句柄 ⇒ rename errno 32）
      final cp = cancelTarget;
      if (cp != null) {
        try {
          cp.send(true);
        } catch (_) {}
      }
      // ② 兜底：5 秒还没结果（worker 卡在连接/超时里）才强杀，避免永远挂着
      Timer(const Duration(seconds: 5), () {
        if (done.isCompleted) return;
        try {
          isolate?.kill(priority: Isolate.immediate);
        } catch (_) {}
        finish(const DownloadWorkerResult.cancelled());
      });
      // ⚠️ 这里**不立刻 finish** —— 等 worker 自己收尾（正常 <1s）；
      // 管理器 await 的是 future，优雅取消时它会拿到真正的 cancelled 结果。
    }

    // 端口在结果出来（或取消）后关闭；否则会让 isolate 常驻不退出
    done.future.whenComplete(() {
      progressPort.close();
      resultPort.close();
      exitPort.close();
      errorPort.close();
      ctrlPort.close();
    });

    Isolate.spawn(
      _downloadEntry,
      <String, dynamic>{
        'url': url,
        'headers': headers,
        'destDir': destDir,
        'baseName': baseName,
        'progress': progressPort.sendPort,
        'result': resultPort.sendPort,
        'ctrl': ctrlPort.sendPort,
      },
      onExit: exitPort.sendPort,
      onError: errorPort.sendPort,
    ).then((iso) {
      isolate = iso;
      if (cancelled) {
        try {
          iso.kill(priority: Isolate.immediate);
        } catch (_) {}
      }
    }, onError: (Object e, StackTrace _) {
      finish(DownloadWorkerResult.error('isolate 启动失败：$e'));
    });

    return DownloadWorkerHandle._(done.future, cancel);
  }
}

/// isolate 入口：必须是顶层函数（`Isolate.spawn` 的限制）。
Future<void> _downloadEntry(Map<String, dynamic> args) async {
  final progress = args['progress'] as SendPort;
  final result = args['result'] as SendPort;
  final ctrl = args['ctrl'] as SendPort;
  final headers = (args['headers'] as Map?)?.cast<String, String>();
  final client = http.Client(); // 纯 dart:io 客户端；不要在 isolate 里碰 Site.httpClient
  // 取消端口：主 isolate 发 true ⇒ 引擎在检查点抛 DownloadCancelled
  // ⇒ 引擎 catch/finally 里 close `.part`（句柄必须在这里释放，见文件头注释）
  final cancelPort = ReceivePort();
  ctrl.send(cancelPort.sendPort);
  var cancelled = false;
  cancelPort.listen((msg) {
    if (msg == true) cancelled = true;
  });
  try {
    final path = await DownloadEngine.download(
      url: args['url'] as String,
      headers: headers,
      destDir: args['destDir'] as String,
      baseName: args['baseName'] as String,
      client: client,
      onProgress: (d, t) => progress.send(<int>[d, t]),
      isCancelled: () => cancelled,
    );
    if (cancelled) {
      // 取消信号来得比收尾晚：文件其实下完了，但用户已经点了暂停 ⇒ 按取消处理
      result.send(<String>['cancelled']);
    } else {
      result.send(<String>['ok', path]);
    }
  } catch (e) {
    if (e is DownloadCancelled) {
      // 用户主动取消 ⇒ 管理器标 paused（不是 failed）
      result.send(<String>['cancelled']);
    } else {
      // 引擎的 DownloadException.toString() 已经带"下载失败："前缀；
      // 这里只回 reason，管理器再包一次异常，避免日志里出现双重前缀。
      final reason = e is DownloadException ? e.reason : '$e';
      result.send(<String>['err', reason]);
    }
  } finally {
    cancelPort.close();
    try {
      client.close();
    } catch (_) {}
  }
}
