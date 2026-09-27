import 'package:flutter/widgets.dart';
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

  test(
    'closing a dirty session requires discard and releases its access',
    () async {
      final releasedOwners = <String>[];
      final created = <FakeVaultState>[];
      final controller = VaultSessionsController(() {
        final state = FakeVaultState();
        created.add(state);
        return state;
      }, releaseAccessForOwner: (owner) async => releasedOwners.add(owner));
      addTearDown(controller.dispose);
      await controller.unlockFromPath(
        filePath: '/tmp/dirty.kdbx',
        password: 'correct',
      );
      created.single.makeDirty();
      final id = controller.activeSessionId;

      expect(await controller.closeSession(id), isFalse);
      expect(created.single.disposed, isFalse);
      expect(releasedOwners, isEmpty);

      expect(await controller.closeSession(id, discardDirty: true), isTrue);
      expect(created.first.disposed, isTrue);
      expect(releasedOwners, <String>[id]);
      expect(controller.sessions, hasLength(1));
      expect(controller.isLocked, isTrue);
    },
  );

  test('locking a session releases its security-scoped access', () async {
    final releasedOwners = <String>[];
    final controller = VaultSessionsController(
      () => FakeVaultState(),
      releaseAccessForOwner: (owner) async => releasedOwners.add(owner),
    );
    addTearDown(controller.dispose);
    await controller.unlockFromPath(
      filePath: '/tmp/one.kdbx',
      password: 'correct',
    );
    final id = controller.activeSessionId;

    await controller.lock();

    expect(releasedOwners, <String>[id]);
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

    await tester.tap(find.bySemanticsLabel('Vault actions').first);
    await tester.pump();
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

  group('closing a dirty background session from the databases dialog', () {
    late List<FakeVaultState> created;
    late VaultSessionsController controller;
    late String backgroundId;
    late String activeId;

    Future<void> pumpAndOpenClose(WidgetTester tester) async {
      created = <FakeVaultState>[];
      controller = VaultSessionsController(() {
        final state = FakeVaultState();
        created.add(state);
        return state;
      });
      await controller.unlockFromPath(
        filePath: '/tmp/first.kdbx',
        password: 'correct',
        filename: 'first.kdbx',
      );
      created.first.makeDirty();
      backgroundId = controller.activeSessionId;
      controller.openNewSession();
      activeId = controller.activeSessionId;

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            vaultStateProvider.overrideWith((ref) => controller),
          ],
          child: const ManyKeeApp(),
        ),
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(MButton, 'Databases'));
      await tester.pump();
      expect(find.text('Databases'), findsWidgets);
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is MIconButton && w.label == 'Close first.kdbx',
        ),
      );
      await tester.pump();
      expect(find.text('Unsaved changes'), findsOneWidget);
    }

    testWidgets('does not switch sessions before the user confirms', (
      tester,
    ) async {
      await pumpAndOpenClose(tester);
      expect(controller.activeSessionId, activeId);

      // The unsaved-changes dialog is the newest route, so its Cancel is
      // the last one in the tree (the databases dialog has one too).
      await tester.tap(find.widgetWithText(MButton, 'Cancel').last);
      await tester.pump();

      expect(controller.activeSessionId, activeId);
      expect(controller.sessions, hasLength(2));
      expect(created.first.isDirty, isTrue);
    });

    testWidgets('saving closes it and keeps the current session active', (
      tester,
    ) async {
      await pumpAndOpenClose(tester);

      await tester.tap(find.widgetWithText(MButton, 'Save'));
      await tester.pump();
      expect(controller.activeSessionId, activeId);
      await tester.enterText(find.byType(EditableText).last, 'correct');
      await tester.pump();
      await tester.tap(find.widgetWithText(MButton, 'Save').last);
      await tester.pump();
      await tester.pump();

      expect(created.first.savedPasswords, <String>['correct']);
      expect(
        controller.sessions.map((s) => s.id),
        isNot(contains(backgroundId)),
      );
      expect(controller.activeSessionId, activeId);
    });
  });

  testWidgets('same entry UUID reloads when the active vault changes', (
    tester,
  ) async {
    final created = <FakeVaultState>[];
    final fields = <Map<String, dynamic>>[
      const <String, dynamic>{
        'Title': 'First vault secret',
        'UserName': 'alice',
        'URL': '',
        'Notes': '',
      },
      const <String, dynamic>{
        'Title': 'Second vault secret',
        'UserName': 'bob',
        'URL': '',
        'Notes': '',
      },
    ];
    final controller = VaultSessionsController(() {
      final state = FakeVaultState(entryFields: fields[created.length]);
      created.add(state);
      return state;
    });

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
    await tester.tap(find.text('Example'));
    await tester.pump();
    await tester.pump();
    expect(find.text('First vault secret'), findsOneWidget);

    controller.openNewSession();
    await controller.unlockFromPath(
      filePath: '/tmp/second.kdbx',
      password: 'correct',
      filename: 'second.kdbx',
    );
    await tester.pump();
    await tester.tap(find.text('Example'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Second vault secret'), findsOneWidget);
    expect(find.text('First vault secret'), findsNothing);
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
