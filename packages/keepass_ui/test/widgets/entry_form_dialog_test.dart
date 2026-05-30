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
    expect(find.text('••••••••'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Show value'));
    await tester.tap(find.byTooltip('Show value'));
    await tester.pumpAndSettle();

    expect(find.text('1234'), findsOneWidget);
    expect(find.byTooltip('Hide value'), findsOneWidget);
  });

  testWidgets(
      'reveals a protected custom field by fetching it on demand when the '
      'backend scrubbed its value', (tester) async {
    final fetched = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showEntryFormDialog(
              context,
              title: 'Edit Entry',
              submitLabel: 'Save Entry',
              // Scrubbed, as the web/WASM backend returns for a protected
              // field it never sent plaintext for.
              customFields: const {'PIN': ''},
              protectedCustomFields: const {'PIN'},
              fetchFieldValue: (key) async {
                fetched.add(key);
                return key == 'PIN' ? '1234' : null;
              },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('••••••••'), findsOneWidget);
    expect(fetched, isEmpty);

    await tester.ensureVisible(find.byTooltip('Show value'));
    await tester.tap(find.byTooltip('Show value'));
    await tester.pumpAndSettle();

    expect(fetched, ['PIN']);
    expect(find.text('1234'), findsOneWidget);
  });

  testWidgets(
      'reveals the password field by fetching it on demand when the '
      'backend scrubbed its value', (tester) async {
    final fetched = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showEntryFormDialog(
              context,
              title: 'Edit Entry',
              submitLabel: 'Save Entry',
              // No 'Password' key at all -- as scrubbed by the web/WASM
              // backend.
              initialFields: const {'Title': 'Example'},
              fetchFieldValue: (key) async {
                fetched.add(key);
                return key == 'Password' ? 'hunter2' : null;
              },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(fetched, isEmpty);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();

    expect(fetched, ['Password']);
    expect(find.text('hunter2'), findsOneWidget);

    // Hiding and re-revealing doesn't re-fetch.
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();

    expect(fetched, ['Password']);
  });

  testWidgets(
      'does not overwrite a password the user already started typing',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showEntryFormDialog(
              context,
              title: 'Edit Entry',
              submitLabel: 'Save Entry',
              initialFields: const {'Title': 'Example'},
              fetchFieldValue: (key) async => 'fetched-value',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'typed-by-user');
    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();

    expect(find.text('typed-by-user'), findsOneWidget);
    expect(find.text('fetched-value'), findsNothing);
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
