@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:keepass_web/keepass_web.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

const _handlers = '''
self.onmessage = (e) => {
  const { id, method, params } = e.data;
  switch (method) {
    case 'echo':
      self.postMessage({ id, result: JSON.stringify(params) });
      break;
    case 'fail':
      self.postMessage({ id, error: { code: 'BOOM', message: 'boom' } });
      break;
    case 'progress':
      self.postMessage({ type: 'progress', percent: 42 });
      self.postMessage({ id, result: '{}' });
      break;
    case 'crash':
      setTimeout(() => { throw new Error('crashed'); }, 0);
      break;
    default:
      // Never answer: simulates a request that gets stuck.
      break;
  }
};
''';

const _readyNow = "$_handlers\nself.postMessage({ type: 'ready' });\n";
const _readySlow =
    "$_handlers\nsetTimeout(() => self.postMessage({ type: 'ready' }), 200);\n";
const _initFails = "$_handlers\n"
    "self.postMessage({ type: 'error', error: { code: 'INIT_FAILED', "
    "message: 'wasm missing' } });\n";
const _throwsOnLoad = "throw new Error('script exploded');\n";

String _blobUrl(String script) {
  final blob = web.Blob(
    <JSAny>[script.toJS].toJS,
    web.BlobPropertyBag(type: 'text/javascript'),
  );
  return web.URL.createObjectURL(blob);
}

/// Builds a [WorkerFactory] that serves [scripts] in order (repeating the
/// last one) and counts how many workers it created.
class _ScriptedFactory {
  _ScriptedFactory(this.scripts);

  final List<String> scripts;
  int created = 0;

  web.Worker call(String workerUrl) {
    final script =
        scripts[created < scripts.length ? created : scripts.length - 1];
    created++;
    return web.Worker(
      _blobUrl(script).toJS,
      web.WorkerOptions(type: 'module'),
    );
  }
}

Matcher _isWebError(String code, [Object? messageMatcher]) {
  var matcher = isA<KeePassWebError>().having((e) => e.code, 'code', code);
  if (messageMatcher != null) {
    matcher = matcher.having((e) => e.message, 'message', messageMatcher);
  }
  return matcher;
}

void main() {
  test('init shares one worker across concurrent and repeated calls', () async {
    final factory = _ScriptedFactory([_readySlow]);
    final bridge = WorkerBridge(workerFactory: factory.call);
    addTearDown(bridge.dispose);

    final first = bridge.init(workerUrl: 'ignored.js');
    final second = bridge.init(workerUrl: 'ignored.js');
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);
    expect(factory.created, 1);

    // Simulates the second unlock attempt: must not spawn a fresh worker.
    await bridge.init(workerUrl: 'ignored.js');
    expect(factory.created, 1);
    expect(bridge.isReady, isTrue);

    expect(await bridge.call('echo', [1, 'a']), '[1,"a"]');
  });

  test('a failed init is retried by the next init call', () async {
    final factory = _ScriptedFactory([_initFails, _readyNow]);
    final bridge = WorkerBridge(workerFactory: factory.call);
    addTearDown(bridge.dispose);

    await expectLater(
      bridge.init(),
      throwsA(_isWebError('INIT_FAILED', 'wasm missing')),
    );
    expect(bridge.isReady, isFalse);

    await bridge.init();
    expect(factory.created, 2);
    expect(await bridge.call('echo', const []), '[]');
  });

  test('a worker that fails to load surfaces WORKER_ERROR', () async {
    final factory = _ScriptedFactory([_throwsOnLoad]);
    final bridge = WorkerBridge(workerFactory: factory.call);
    addTearDown(bridge.dispose);

    await expectLater(bridge.init(), throwsA(_isWebError('WORKER_ERROR')));
  });

  test('call before init throws StateError', () {
    final bridge =
        WorkerBridge(workerFactory: _ScriptedFactory([_readyNow]).call);
    addTearDown(bridge.dispose);
    expect(() => bridge.call('echo', const []), throwsStateError);
  });

  test('worker errors map to KeePassWebError with the worker code', () async {
    final bridge =
        WorkerBridge(workerFactory: _ScriptedFactory([_readyNow]).call);
    addTearDown(bridge.dispose);
    await bridge.init();

    await expectLater(
      bridge.call('fail', const []),
      throwsA(_isWebError('BOOM', 'boom')),
    );
  });

  test('progress messages are delivered as ints', () async {
    final bridge =
        WorkerBridge(workerFactory: _ScriptedFactory([_readyNow]).call);
    addTearDown(bridge.dispose);
    await bridge.init();

    final progress = bridge.progress.first;
    await bridge.call('progress', const []);
    final percent = await progress;
    expect(percent, isA<int>());
    expect(percent, 42);
  });

  test('a worker-level error fails every pending call', () async {
    final bridge =
        WorkerBridge(workerFactory: _ScriptedFactory([_readyNow]).call);
    addTearDown(bridge.dispose);
    await bridge.init();

    final stuck = bridge.call('hang', const []);
    final crashing = bridge.call('crash', const []);

    await expectLater(
      stuck,
      throwsA(_isWebError('WORKER_ERROR', contains('crashed'))),
    );
    await expectLater(crashing, throwsA(_isWebError('WORKER_ERROR')));

    // The worker itself is still alive, so new calls keep working.
    expect(await bridge.call('echo', [2]), '[2]');
  });

  test('unsendable params fail the call instead of leaking it', () async {
    final bridge =
        WorkerBridge(workerFactory: _ScriptedFactory([_readyNow]).call);
    addTearDown(bridge.dispose);
    await bridge.init();

    await expectLater(
      // Functions cannot be structured-cloned.
      bridge.call('echo', [() {}]),
      throwsA(_isWebError('WORKER_ERROR', contains('echo'))),
    );
    expect(await bridge.call('echo', [3]), '[3]');
  });

  test('dispose fails pending calls and tears the bridge down', () async {
    final factory = _ScriptedFactory([_readyNow]);
    final bridge = WorkerBridge(workerFactory: factory.call);
    await bridge.init();

    final stuck = bridge.call('hang', const []);
    bridge.dispose();

    await expectLater(stuck, throwsA(_isWebError('DISPOSED')));
    expect(bridge.isReady, isFalse);
    expect(() => bridge.init(), throwsStateError);
    expect(() => bridge.call('echo', const []), throwsStateError);
    expect(factory.created, 1);
  });
}
