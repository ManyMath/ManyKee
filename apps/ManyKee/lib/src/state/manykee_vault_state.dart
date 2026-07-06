import 'package:keepass_ui/keepass_ui.dart' show VaultState;

/// App-facing vault state contract for ManyKee.
///
/// Extends the UI-agnostic [VaultState] from `package:keepass_ui` with the
/// small surface the ManyKee pages need beyond browsing: the last-opened
/// file path (for the re-unlock view) and path-based unlocking.
///
/// Mutation methods throw here by default; [NativeVaultState] overrides them
/// with the real FFI-backed implementation, while [WebVaultState] still has
/// no unlock path at all yet and so inherits these throws.
abstract class ManyKeeVaultState extends VaultState {
  String? _errorDetail;

  /// Raw error text behind the friendly [errorMessage], if any, for a muted
  /// detail line on the unlock page. Set via [setErrorWithDetail] on unlock
  /// failure; cleared with [clearError].
  String? get errorDetail => _errorDetail;

  /// Like [setError], additionally recording the raw [detail] behind the
  /// friendly [message].
  void setErrorWithDetail(String code, String message, {String? detail}) {
    _errorDetail = detail;
    setError(code, message);
  }

  @override
  void clearError() {
    _errorDetail = null;
    super.clearError();
  }

  /// Path of the most recently unlocked database, if any. Survives [lock] so
  /// the lock screen can offer a quick re-unlock.
  String? get lastFilePath;

  /// YubiKey slot remembered from the last successful unlock, if any. Lets
  /// the re-unlock view show the same touch-prompt hint as the full form.
  String? get lastYubiKeySlot => null;

  /// Opens and unlocks the database at [filePath].
  ///
  /// Does not throw on failure: errors are mapped to friendly messages via
  /// [VaultState.setError] and the vault stays locked.
  Future<void> unlockFromPath({
    required String filePath,
    required String password,
    String? keyFilePath,
    String? filename,
    String? yubiKeySlot,
  });

  /// Connected YubiKeys usable for challenge-response unlock, as raw
  /// descriptor maps from the keepass core. Empty on platforms without
  /// YubiKey support (web) or when none are plugged in.
  Future<List<Map<String, dynamic>>> listYubiKeys();

  /// Creates a new database, saves it at [filePath], and opens it as the
  /// current vault.
  ///
  /// Password-only creation is the first app UI slice. Key-file/YubiKey
  /// creation can build on this once combined-credential creation is designed.
  Future<void> createDatabaseAtPath({
    required String filePath,
    required String password,
    String? filename,
  }) => throw UnimplementedError('database creation lands in a later phase');

  /// Forgets [lastFilePath] and any remembered key file so the unlock page
  /// returns to the full "choose a database" view.
  void openDifferentFile();

  // TODO(manykee): web support (see WebVaultState).

  @override
  Future<String> createEntry(String groupUuid) =>
      throw UnimplementedError('editing lands in a later phase');

  @override
  Future<void> updateEntry(
    String entryUuid,
    Map<String, String?> fields, {
    Set<String> protectedFields = const <String>{},
  }) => throw UnimplementedError('editing lands in a later phase');

  @override
  Future<void> deleteEntry(String entryUuid) =>
      throw UnimplementedError('editing lands in a later phase');

  @override
  Future<void> moveEntry(String entryUuid, String targetGroupUuid) =>
      throw UnimplementedError('editing lands in a later phase');

  @override
  Future<String> createGroup(String parentGroupUuid, String name) =>
      throw UnimplementedError('editing lands in a later phase');

  @override
  Future<void> renameGroup(String groupUuid, String name) =>
      throw UnimplementedError('editing lands in a later phase');

  @override
  Future<void> deleteGroup(String groupUuid) =>
      throw UnimplementedError('editing lands in a later phase');

  @override
  Future<void> moveGroup(String groupUuid, String targetParentUuid) =>
      throw UnimplementedError('editing lands in a later phase');

  @override
  Future<List<int>> saveDatabase({
    required String password,
    List<int>? keyFileBytes,
  }) => throw UnimplementedError('saving lands in a later phase');
}
