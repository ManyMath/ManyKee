import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_ui/keepass_ui.dart';

void main() {
  testWidgets('protected custom field is obscured until revealed',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showEntryFormDialog(
              context,
              title: 'Edit Entry',
              submitLabel: 'Save Entry',
              customFields: const {'PIN': '1234'},
              protectedCustomFields: const {'PIN'},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('1234'), findsNothing);
    expect(find.text('•' * 4), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Show value'));
    await tester.tap(find.byTooltip('Show value'));
    await tester.pumpAndSettle();

    expect(find.text('1234'), findsOneWidget);
    expect(find.byTooltip('Hide value'), findsOneWidget);
  });

  testWidgets('unprotected custom field is shown in plain text',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showEntryFormDialog(
              context,
              title: 'Edit Entry',
              submitLabel: 'Save Entry',
              customFields: const {'Security Question': 'first pet'},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('first pet'), findsOneWidget);
  });
}
