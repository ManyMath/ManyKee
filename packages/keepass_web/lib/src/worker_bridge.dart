import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'worker_error.dart';

/// Creates the [web.Worker] that backs a [WorkerBridge].
///
/// The default factory spawns a module worker from the given URL; tests inject
/// their own to observe how many workers get created.
typedef WorkerFactory = web.Worker Function(String workerUrl);

web.Worker _createModuleWorker(String workerUrl) {
  return web.Worker(workerUrl.toJS, web.WorkerOptions(type: 'module'));
}

class WorkerBridge {
  WorkerBridge({WorkerFactory? workerFactory})
      : _workerFactory = workerFactory ?? _createModuleWorker;

  final WorkerFactory _workerFactory;
  web.Worker? _worker;
  Future<void>? _initFuture;
  Completer<void>? _readyCompleter;
  bool _disposed = false;
  final _pending = <int, Completer<String>>{};
  final _progressController = StreamController<int>.broadcast();
  int _nextId = 1;

  Stream<int> get progress => _progressController.stream;

  /// Whether the worker has been created and reported itself ready.
  bool get isReady => _readyCompleter?.isCompleted == true && _worker != null;

  /// Spawns the worker and waits for it to report `ready`.
  ///
  /// Idempotent: concurrent and repeated calls share one worker and return
  /// the same future. A failed initialization is forgotten so the next call
  /// starts a fresh worker.
  Future<void> init({String workerUrl = 'keepassxc_worker.js'}) {
    if (_disposed) {
      throw StateError('WorkerBridge has been disposed');
    }
    return _initFuture ??= _start(workerUrl).then(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        // Runs asynchronously, i.e. after `_initFuture` was assigned above,
        // so the failed attempt is forgotten and the next init() retries.
        _initFuture = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  Future<void> _start(String workerUrl) async {
    final ready = Completer<void>();
    _readyCompleter = ready;
    try {
      final worker = _workerFactory(workerUrl);
      _worker = worker;
      worker.onmessage = _onMessage.toJS;
      worker.onerror = _onError.toJS;
      await ready.future;
    } catch (e) {
      _terminateWorker();
      _readyCompleter = null;
      if (e is KeePassWebError) rethrow;
      throw KeePassWebError('WORKER_ERROR', 'Failed to start worker: $e');
    }
  }

  void _onMessage(web.MessageEvent event) {
    final data = event.data?.dartify();
    if (data is! Map) return;

    final type = data['type'] as String?;

    if (type == 'ready') {
      final ready = _readyCompleter;
      if (ready != null && !ready.isCompleted) {
        ready.complete();
      }
      return;
    }

    if (type == 'progress') {
      final percent = data['percent'] as int? ?? -1;
      if (!_progressController.isClosed) {
        _progressController.add(percent);
      }
      return;
    }

    if (type == 'error') {
      final error = data['error'] as Map?;
      final message = error?['message'] ?? 'Worker initialization failed';
      final ready = _readyCompleter;
      if (ready != null && !ready.isCompleted) {
        ready.completeError(
          KeePassWebError('INIT_FAILED', message.toString()),
        );
      }
      return;
    }

    final id = data['id'] as int?;
    if (id == null) return;

    final completer = _pending.remove(id);
    if (completer == null) return;

    if (data.containsKey('error')) {
      final error = data['error'] as Map;
      final code = error['code']?.toString() ?? 'UNKNOWN';
      final message = error['message']?.toString() ?? 'Unknown error';
      completer.completeError(KeePassWebError(code, message));
    } else {
      final result = data['result'] as String? ?? '{}';
      completer.complete(result);
    }
  }

  void _onError(web.Event event) {
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(
        KeePassWebError('WORKER_ERROR', 'Worker failed to load'),
      );
    }
  }

  Future<String> call(String method, List<Object?> params) {
    final worker = _worker;
    if (worker == null || !isReady) {
      throw StateError('WorkerBridge not initialized. Call init() first.');
    }

    final id = _nextId++;
    final completer = Completer<String>();
    _pending[id] = completer;

    final message = <String, Object?>{
      'id': id,
      'method': method,
      'params': params,
    };
    worker.postMessage(message.jsify());
    return completer.future;
  }

  void _terminateWorker() {
    final worker = _worker;
    _worker = null;
    if (worker == null) return;
    worker.onmessage = null;
    worker.onerror = null;
    worker.terminate();
  }

  void dispose() {
    _disposed = true;
    _terminateWorker();
    _initFuture = null;
    _readyCompleter = null;
    _progressController.close();
    final pending = List<Completer<String>>.from(_pending.values);
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(
          KeePassWebError('DISPOSED', 'WorkerBridge was disposed'),
        );
      }
    }
  }
}
