import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:manykee/src/app.dart';
import 'package:manykee/src/state/vault_state_provider.dart';
import 'package:manykee/src/state/vault_sessions.dart';
import 'package:manyui/manyui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'unlock_page_test.dart' show FakeVaultState;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('controller keeps unlocked sessions while opening another', () async {
    final created = <FakeVaultState>[];
    final controller = VaultSessionsController(() {
      final state = FakeVaultState();
      created.add(state);
      return state;
    });
    addTearDown(controller.dispose);

    await controller.unlockFromPath(
      filePath: '/tmp/first.kdbx',
      password: 'correct',
      filename: 'first.kdbx',
    );

    final firstSessionId = controller.activeSessionId;
    expect(controller.isLocked, isFalse);
    expect(controller.sessions.single.label, 'first.kdbx');

    controller.openNewSession();

    expect(created, hasLength(2));
    expect(controller.activeSessionId, isNot(firstSessionId));
    expect(controller.isLocked, isTrue);
    expect(created.first.isLocked, isFalse);
    expect(controller.sessions.map((s) => s.label), <String>[
      'first.kdbx',
      'Locked database',
    ]);

    controller.switchToSession(firstSessionId);

    expect(controller.isLocked, isFalse);
    expect(controller.lastFilePath, '/tmp/first.kdbx');
    expect(controller.lastFilename, 'first.kdbx');
  });

  test('lockCleanSessions leaves dirty sessions open', () async {
    final created = <FakeVaultState>[];
    final controller = VaultSessionsController(() {
      final state = FakeVaultState();
      created.add(state);
      return state;
    });
    addTearDown(controller.dispose);

    await controller.unlockFromPath(
      filePath: '/tmp/clean.kdbx',
      password: 'correct',
      filename: 'clean.kdbx',
    );
    controller.openNewSession();
    await controller.unlockFromPath(
      filePath: '/tmp/dirty.kdbx',
      password: 'correct',
      filename: 'dirty.kdbx',
    );
    created[1].makeDirty();

    await controller.lockCleanSessions();

    expect(created[0].isLocked, isTrue);
    expect(created[1].isLocked, isFalse);
    expect(created[1].isDirty, isTrue);
    expect(controller.hasUnlockedSessions, isTrue);
    expect(controller.hasUnlockedCleanSessions, isFalse);
  });

  testWidgets('databases dialog opens another session and switches back', (
    tester,
  ) async {
    final controller = VaultSessionsController(() => FakeVaultState());
    await controller.unlockFromPath(
      filePath: '/tmp/first.kdbx',
      password: 'correct',
      filename: 'first.kdbx',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          vaultStateProvider.overrideWith((ref) => controller),
        ],
        child: const ManyKeeApp(),
      ),
    );

    expect(find.text('first.kdbx'), findsOneWidget);
    expect(find.text('Unlock a database'), findsNothing);

    await tester.tap(find.widgetWithText(MButton, 'Databases'));
    await tester.pump();
    await tester.tap(find.text('Open another database'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Unlock a database'), findsOneWidget);
    expect(controller.sessions, hasLength(2));
    expect(controller.sessions.first.isLocked, isFalse);

    await tester.tap(find.widgetWithText(MButton, 'Databases'));
    await tester.pump();
    await tester.tap(find.text('first.kdbx'));
    await tester.pump();
    await tester.pump();

    expect(controller.lastFilename, 'first.kdbx');
    expect(controller.isLocked, isFalse);
    expect(find.text('Unlock a database'), findsNothing);
    expect(find.text('first.kdbx'), findsOneWidget);
  });

  testWidgets('auto-lock locks inactive clean sessions', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'manykee.settings.autoLockMinutes': 1,
    });
    final created = <FakeVaultState>[];
    final controller = VaultSessionsController(() {
      final state = FakeVaultState();
      created.add(state);
      return state;
    });
    await controller.unlockFromPath(
      filePath: '/tmp/first.kdbx',
      password: 'correct',
      filename: 'first.kdbx',
    );
    controller.openNewSession();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          vaultStateProvider.overrideWith((ref) => controller),
        ],
        child: const ManyKeeApp(),
      ),
    );
    await tester.pump();

    expect(created.first.isLocked, isFalse);
    expect(find.text('Unlock a database'), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));
    await tester.pump();

    expect(created.first.isLocked, isTrue);
    expect(controller.hasUnlockedSessions, isFalse);
    expect(find.text('Unlock a database'), findsOneWidget);
  });
}
