import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Idle timer that triggers auto-lock on tab switch or inactivity.
class IdleTimer {
 Timer? _timer;
 Duration timeout;
 VoidCallback? _onLock;

 JSFunction? _visibilityHandler;
 JSFunction? _pointerHandler;
 JSFunction? _keyHandler;

 IdleTimer({this.timeout = const Duration(minutes: 5)});

void start(VoidCallback onLock) {
 _onLock = onLock;

 _visibilityHandler = ((web.Event _) {
 if (web.document.hidden) {
 onLock();
 }
 }).toJS;
 web.document.addEventListener('visibilitychange', _visibilityHandler!);

 _pointerHandler = ((web.Event _) {
 _resetTimer();
 }).toJS;
 _keyHandler = ((web.Event _) {
 _resetTimer();
 }).toJS;
 web.document.addEventListener('pointermove', _pointerHandler!);
 web.document.addEventListener('keydown', _keyHandler!);

 _resetTimer();
 }

 void _resetTimer() {
 _timer?.cancel();
 if (_onLock != null) {
 _timer = Timer(timeout, _onLock!);
 }
 }

void updateTimeout(Duration newTimeout) {
 timeout = newTimeout;
 _resetTimer();
 }

void stop() {
 _timer?.cancel();
 _timer = null;
 _onLock = null;

 if (_visibilityHandler != null) {
 web.document.removeEventListener('visibilitychange', _visibilityHandler!);
 _visibilityHandler = null;
 }
 if (_pointerHandler != null) {
 web.document.removeEventListener('pointermove', _pointerHandler!);
 _pointerHandler = null;
 }
 if (_keyHandler != null) {
 web.document.removeEventListener('keydown', _keyHandler!);
 _keyHandler = null;
 }
 }

void dispose() {
 stop();
 }
}
