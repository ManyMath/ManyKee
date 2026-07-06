/// Riverpod state for recently-opened databases: a persisted list of file
/// paths the user has unlocked before, so the unlock page can offer a
/// one-tap re-open instead of always re-browsing via the file picker.
library;

import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsRecentsKey = 'manykee.recentDatabases';
const _maxRecents = 8;

/// One previously-opened database, identified by its file path (paths are
/// already stable/unique identifiers here, unlike ManyTier's host/port
/// tuples, no separate id needed).
class RecentDatabase {
  const RecentDatabase({
    required this.path,
    required this.label,
    required this.lastOpened,
  });

  /// Full filesystem path to the .kdbx file.
  final String path;

  /// Display name (the filename, usually).
  final String label;

  /// When this database was last unlocked, used to keep the list ordered
  /// most-recent-first.
  final DateTime lastOpened;

  RecentDatabase copyWith({String? label, DateTime? lastOpened}) {
    return RecentDatabase(
      path: path,
      label: label ?? this.label,
      lastOpened: lastOpened ?? this.lastOpened,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        'label': label,
        'lastOpened': lastOpened.toIso8601String(),
      };

  factory RecentDatabase.fromJson(Map<String, Object?> json) {
    return RecentDatabase(
      path: json['path']! as String,
      label: json['label']! as String,
      lastOpened: DateTime.parse(json['lastOpened']! as String),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecentDatabase &&
        other.path == path &&
        other.label == label &&
        other.lastOpened == lastOpened;
  }

  @override
  int get hashCode => Object.hash(path, label, lastOpened);
}

/// All remembered databases, most-recently-opened first. Empty until
/// [recentDatabasesLoaderProvider] runs (or forever, if none have been
/// opened yet: unlike ManyTier's connections there's no seeded default,
/// since "no recents" correctly means "show the full open-file form".
final recentDatabasesProvider =
    StateProvider<List<RecentDatabase>>((ref) => const <RecentDatabase>[]);

/// Loads previously persisted recents, if any, and seeds
/// [recentDatabasesProvider] exactly once. `app.dart` watches this so the
/// load kicks off at startup; the `AsyncValue` itself is discarded, only the
/// one-time side effect of populating the provider above matters.
final recentDatabasesLoaderProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final String? raw = prefs.getString(_prefsRecentsKey);
  List<RecentDatabase> recents = <RecentDatabase>[];
  if (raw != null) {
    try {
      final List<Object?> decoded = jsonDecode(raw) as List<Object?>;
      recents = decoded
          .map((Object? e) =>
              RecentDatabase.fromJson(e! as Map<String, Object?>))
          .toList();
    } catch (_) {
      // Corrupt prefs value (e.g. from a future format), start with an
      // empty list rather than crashing at startup.
      recents = <RecentDatabase>[];
    }
  }
  ref.read(recentDatabasesProvider.notifier).state = recents;
});

/// Persists the recents list on every change.
final recentDatabasesPersistenceProvider = Provider<void>((ref) {
  ref.listen<List<RecentDatabase>>(recentDatabasesProvider,
      (previous, next) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsRecentsKey,
      jsonEncode(next.map((r) => r.toJson()).toList()),
    );
  }, fireImmediately: false);
});

/// Mutations over the recent-databases list.
class RecentDatabasesController {
  RecentDatabasesController(this._ref);

  final Ref _ref;

  /// Records that [path] (displayed as [label]) was just opened: moves it
  /// to the front if already present (refreshing its timestamp), otherwise
  /// inserts it, then truncates to [_maxRecents].
  void recordOpened(String path, String label) {
    final now = DateTime.now();
    final existing = _ref.read(recentDatabasesProvider);
    final withoutPath = existing.where((r) => r.path != path).toList();
    final next = <RecentDatabase>[
      RecentDatabase(path: path, label: label, lastOpened: now),
      ...withoutPath,
    ];
    _ref.read(recentDatabasesProvider.notifier).state =
        next.take(_maxRecents).toList();
  }

  /// Removes [path] from the recents list.
  void forget(String path) {
    final remaining = _ref
        .read(recentDatabasesProvider)
        .where((r) => r.path != path)
        .toList();
    _ref.read(recentDatabasesProvider.notifier).state = remaining;
  }
}

final recentDatabasesControllerProvider =
    Provider<RecentDatabasesController>((ref) {
  return RecentDatabasesController(ref);
});
