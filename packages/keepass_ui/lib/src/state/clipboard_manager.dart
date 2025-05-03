import 'dart:async';

import 'package:flutter/services.dart';

class ClipboardManager {
 Timer? _clearTimer;

 Future<bool> copyWithAutoClear(String value) async {
 try {
 await Clipboard.setData(ClipboardData(text: value));
 _clearTimer?.cancel();
 _clearTimer = Timer(const Duration(seconds: 30), () {
 Clipboard.setData(const ClipboardData(text: ''));
 });
 return true;
 } catch (_) {
 return false;
 }
 }

 void dispose() {
 _clearTimer?.cancel();
 }
}
