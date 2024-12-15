import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'worker_error.dart';

class WorkerBridge {
 web.Worker? _worker;
 final _readyCompleter = Completer<void>();
 final _pending = <int, Completer<String>>{};
 final _progressController = StreamController<int>.broadcast();
 int _nextId = 1;

 Stream<int> get progress => _progressController.stream;

 Future<void> init({String workerUrl = 'keepassxc_worker.js'}) async {
 final opts = web.WorkerOptions(type: 'module');
 _worker = web.Worker(workerUrl.toJS, opts);
 _worker!.onmessage = _onMessage.toJS;
 _worker!.onerror = _onError.toJS;
 await _readyCompleter.future;
 }

 void _onMessage(web.MessageEvent event) {
 final data = (event.data as JSAny).dartify();
 if (data is! Map) return;

 final type = data['type'] as String?;

 if (type == 'ready') {
 if (!_readyCompleter.isCompleted) {
 _readyCompleter.complete();
 }
 return;
 }

 if (type == 'progress') {
 final percent = data['percent'] as int? ?? -1;
 _progressController.add(percent);
 return;
 }

 if (type == 'error') {
 final error = data['error'] as Map?;
 final message = error?['message'] ?? 'Worker initialization failed';
 if (!_readyCompleter.isCompleted) {
 _readyCompleter.completeError(
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
 if (!_readyCompleter.isCompleted) {
 _readyCompleter.completeError(
 KeePassWebError('WORKER_ERROR', 'Worker failed to load'),
 );
 }
 }

 Future<String> call(String method, List<Object?> params) {
 final worker = _worker;
 if (worker == null) {
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

 void dispose() {
 _worker?.terminate();
 _worker = null;
 _progressController.close();
 for (final completer in _pending.values) {
 if (!completer.isCompleted) {
 completer.completeError(
 KeePassWebError('DISPOSED', 'WorkerBridge was disposed'),
 );
 }
 }
 _pending.clear();
 }
}
