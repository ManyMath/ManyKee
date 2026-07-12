// Web stub: `package:keepass`'s `Database` (and its `MergeResult`) are
// reached through `dart:ffi`-based bindings, so this file must not import
// `package:keepass/keepass.dart` at all: that would pull `dart:ffi` into
// the web build. `MergeResult` is duplicated here as a plain-Dart value
// type with the same shape as `package:keepass`'s, purely so
// `merge_page.dart` (shared across platforms) type-checks against whichever
// `MergeService` this platform seam resolves to. It is never actually
// populated on web: every method below throws before returning one.
class MergeResult {
  MergeResult({
    this.entriesAdded = 0,
    this.entriesUpdated = 0,
    this.entriesDeleted = 0,
    this.entriesRelocated = 0,
    this.groupsAdded = 0,
    this.groupsUpdated = 0,
    this.groupsDeleted = 0,
    this.groupsRelocated = 0,
    this.totalChanges = 0,
    this.conflictsCount = 0,
    this.warningsCount = 0,
    this.warnings = const <String>[],
  });

  final int entriesAdded;
  final int entriesUpdated;
  final int entriesDeleted;
  final int entriesRelocated;
  final int groupsAdded;
  final int groupsUpdated;
  final int groupsDeleted;
  final int groupsRelocated;
  final int totalChanges;
  final int conflictsCount;
  final int warningsCount;
  final List<String> warnings;
}

MergeService createMergeService() => _WebMergeService();

class MergeServiceResult {
  MergeServiceResult({required this.mergeResult, required this.outputPath});

  final MergeResult mergeResult;
  final String outputPath;
}

abstract class MergeService {
  Future<void> openA({required String filePath, required String password});
  Future<void> openB({required String filePath, required String password});
  bool get bothOpen;
  MergeResult preview();
  MergeServiceResult saveMergedCopy({
    required String outputPath,
    required String outputPassword,
  });
  void dispose();
}

/// Placeholder so the web target compiles.
// TODO(manykee): phase B, real web merge via keepass_web (WASM worker),
// alongside real web unlock (see WebVaultState).
class _WebMergeService implements MergeService {
  static Never _unsupported() => throw UnimplementedError(
    'merging databases is not supported on web yet.',
  );

  @override
  Future<void> openA({required String filePath, required String password}) =>
      _unsupported();

  @override
  Future<void> openB({required String filePath, required String password}) =>
      _unsupported();

  @override
  bool get bothOpen => false;

  @override
  MergeResult preview() => _unsupported();

  @override
  MergeServiceResult saveMergedCopy({
    required String outputPath,
    required String outputPassword,
  }) => _unsupported();

  @override
  void dispose() {}
}
