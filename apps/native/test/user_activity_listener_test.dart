import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manykee_native/src/widgets/user_activity_listener.dart';

void main() {
  late int activity;
  late GlobalKey<NavigatorState> navigator;

  Future<void> pumpApp(WidgetTester tester) async {
    activity = 0;
    navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => UserActivityListener(
          onActivity: () => activity++,
          child: child!,
        ),
        home: const Scaffold(body: Text('home')),
      ),
    );
  }

  testWidgets('sees pointer input on a pushed route', (tester) async {
    await pumpApp(tester);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('pushed'))),
      ),
    );
    await tester.pumpAndSettle();

    final before = activity;
    await tester.tap(find.text('pushed'));
    expect(activity, greaterThan(before));
  });

  testWidgets('sees pointer and key input inside a dialog', (tester) async {
    await pumpApp(tester);
    showDialog<void>(
      context: navigator.currentContext!,
      builder: (_) => const AlertDialog(content: TextField(autofocus: true)),
    );
    await tester.pumpAndSettle();

    var before = activity;
    await tester.tap(find.byType(TextField));
    expect(activity, greaterThan(before));

    before = activity;
    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    expect(activity, greaterThan(before));
  });
}
