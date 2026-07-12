import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:manykee/src/state/recent_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('recentDatabasesLoaderProvider', () {
    test('starts empty on first launch', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(recentDatabasesLoaderProvider.future);

      expect(container.read(recentDatabasesProvider), isEmpty);
    });

    test('restores a previously persisted list', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'manykee.recentDatabases':
            '[{"path":"/a/one.kdbx","label":"one.kdbx",'
            '"lastOpened":"2026-01-01T00:00:00.000",'
            '"securityScopedBookmark":"bookmark-data"}]',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(recentDatabasesLoaderProvider.future);

      final recents = container.read(recentDatabasesProvider);
      expect(recents, hasLength(1));
      expect(recents.single.path, '/a/one.kdbx');
      expect(recents.single.label, 'one.kdbx');
      expect(recents.single.securityScopedBookmark, 'bookmark-data');
    });

    test('falls back to an empty list on corrupt persisted JSON', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'manykee.recentDatabases': 'not valid json',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(recentDatabasesLoaderProvider.future);

      expect(container.read(recentDatabasesProvider), isEmpty);
    });
  });

  group('RecentDatabasesController', () {
    test('recordOpened inserts a new entry at the front', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(recentDatabasesLoaderProvider.future);

      container
          .read(recentDatabasesControllerProvider)
          .recordOpened(
            '/a/one.kdbx',
            'one.kdbx',
            securityScopedBookmark: 'bookmark-data',
          );

      final recents = container.read(recentDatabasesProvider);
      expect(recents, hasLength(1));
      expect(recents.single.path, '/a/one.kdbx');
      expect(recents.single.securityScopedBookmark, 'bookmark-data');
    });

    test(
      'recordOpened moves an existing entry to the front and refreshes it',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(recentDatabasesLoaderProvider.future);
        final controller = container.read(recentDatabasesControllerProvider);

        controller.recordOpened(
          '/a/one.kdbx',
          'one.kdbx',
          securityScopedBookmark: 'bookmark-data',
        );
        controller.recordOpened('/b/two.kdbx', 'two.kdbx');
        controller.recordOpened('/a/one.kdbx', 'one.kdbx');

        final recents = container.read(recentDatabasesProvider);
        expect(recents, hasLength(2));
        expect(recents.first.path, '/a/one.kdbx');
        expect(recents.first.securityScopedBookmark, 'bookmark-data');
        expect(recents.last.path, '/b/two.kdbx');
      },
    );

    test('recordOpened truncates to the max recents count', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(recentDatabasesLoaderProvider.future);
      final controller = container.read(recentDatabasesControllerProvider);

      for (var i = 0; i < 10; i++) {
        controller.recordOpened('/db$i.kdbx', 'db$i.kdbx');
      }

      final recents = container.read(recentDatabasesProvider);
      expect(recents, hasLength(8));
      expect(recents.first.path, '/db9.kdbx');
    });

    test('recordOpened migrates a resolved bookmark path in place', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(recentDatabasesLoaderProvider.future);
      final controller = container.read(recentDatabasesControllerProvider);
      controller.recordOpened(
        '/old/vault.kdbx',
        'vault.kdbx',
        securityScopedBookmark: 'bookmark-data',
      );

      controller.recordOpened(
        '/resolved/vault.kdbx',
        'vault.kdbx',
        previousPath: '/old/vault.kdbx',
      );

      final recents = container.read(recentDatabasesProvider);
      expect(recents, hasLength(1));
      expect(recents.single.path, '/resolved/vault.kdbx');
      expect(recents.single.securityScopedBookmark, 'bookmark-data');
    });

    test('forget removes the matching entry', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(recentDatabasesLoaderProvider.future);
      final controller = container.read(recentDatabasesControllerProvider);
      controller.recordOpened('/a/one.kdbx', 'one.kdbx');
      controller.recordOpened('/b/two.kdbx', 'two.kdbx');

      controller.forget('/a/one.kdbx');

      final recents = container.read(recentDatabasesProvider);
      expect(recents, hasLength(1));
      expect(recents.single.path, '/b/two.kdbx');
    });
  });

  group('RecentDatabase JSON round-trip', () {
    test('toJson/fromJson preserves all fields', () {
      final original = RecentDatabase(
        path: '/x/y.kdbx',
        label: 'y.kdbx',
        lastOpened: DateTime.utc(2026, 3, 4, 5, 6, 7),
        securityScopedBookmark: 'bookmark-data',
      );

      final restored = RecentDatabase.fromJson(original.toJson());

      expect(restored.path, original.path);
      expect(restored.label, original.label);
      expect(restored.lastOpened, original.lastOpened);
      expect(restored.securityScopedBookmark, original.securityScopedBookmark);
    });
  });
}
