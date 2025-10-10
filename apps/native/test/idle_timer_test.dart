import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manykee_native/src/state/native_idle_timer.dart';

void main() {
 group('NativeIdleTimer', () {
 test('fires lock callback after timeout', () {
 fakeAsync((async) {
 bool locked = false;
 final timer = NativeIdleTimer(timeout: const Duration(seconds: 5));
 timer.start(() => locked = true);

 async.elapse(const Duration(seconds: 4));
 expect(locked, isFalse);

 async.elapse(const Duration(seconds: 2));
 expect(locked, isTrue);

 timer.dispose();
 });
 });

 test('resets on user activity', () {
 fakeAsync((async) {
 bool locked = false;
 final timer = NativeIdleTimer(timeout: const Duration(seconds: 5));
 timer.start(() => locked = true);

 async.elapse(const Duration(seconds: 3));
 expect(locked, isFalse);

 timer.resetTimer(); // Reset at t=3s

 async.elapse(const Duration(seconds: 4));
 expect(locked, isFalse); // Only 4s since reset, not 5

 async.elapse(const Duration(seconds: 2));
 expect(locked, isTrue); // 6s since reset > 5s timeout

 timer.dispose();
 });
 });

 test('Duration.zero disables auto-lock', () {
 fakeAsync((async) {
 bool locked = false;
 final timer = NativeIdleTimer(timeout: Duration.zero);
 timer.start(() => locked = true);

 async.elapse(const Duration(minutes: 30));
 expect(locked, isFalse);

 timer.dispose();
 });
 });

 test('updateTimeout restarts with new duration', () {
 fakeAsync((async) {
 bool locked = false;
 final timer = NativeIdleTimer(timeout: const Duration(seconds: 10));
 timer.start(() => locked = true);

 async.elapse(const Duration(seconds: 3));
 timer.updateTimeout(const Duration(seconds: 2));

 async.elapse(const Duration(seconds: 1));
 expect(locked, isFalse);

 async.elapse(const Duration(seconds: 2));
 expect(locked, isTrue);

 timer.dispose();
 });
 });

 test('stop prevents callback from firing', () {
 fakeAsync((async) {
 bool locked = false;
 final timer = NativeIdleTimer(timeout: const Duration(seconds: 5));
 timer.start(() => locked = true);

 async.elapse(const Duration(seconds: 3));
 timer.stop();

 async.elapse(const Duration(seconds: 10));
 expect(locked, isFalse);

 timer.dispose();
 });
 });
 });
}
