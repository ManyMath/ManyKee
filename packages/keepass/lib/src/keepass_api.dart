import 'dart:async';

/// Platform-agnostic KeePass API interface.
///
/// Implemented by:
/// - Native: `packages/keepass` Database class (dart:ffi)
///
/// `packages/keepass_web` exposes a `KeePassWebApi` with the same method
/// shape, but does not implement this interface so browser
/// builds never import `dart:ffi`.
///
/// The web implementation communicates with a WASM module via postMessage RPC.
/// All methods are async because the web path involves Worker message passing.
abstract class KeePassApi {
  /// Create a new, empty KDBX4 database in memory (not yet saved anywhere).
  /// Returns a database handle for subsequent operations -- call
  /// [saveDatabase] once the caller has picked a destination and unlock
  /// credentials.
  Future<int> createDatabase();

  /// Open a KDBX database with a password.
  /// Returns a database handle for subsequent operations.
  /// [dbBytes] is the raw KDBX file content.
  Future<int> openDatabase(List<int> dbBytes, {required String password});

  /// Open a KDBX database with password + key file.
  Future<int> openDatabaseWithKeyFile(
    List<int> dbBytes, {
    required String password,
    required List<int> keyFileBytes,
  });

  /// Open a KDBX database with password + pre-computed challenge-response.
  ///
  /// Only the web implementation can consume a response computed outside
  /// the core (e.g. by WebAuthn/WebUSB in the browser). The native
  /// implementation throws [UnsupportedError]: its FFI core performs the
  /// challenge itself against a hardware YubiKey slot or a stored
  /// local-challenge secret, so native callers must use
  /// `KeePassNativeApi.openFromPathWithYubiKey` or
  /// `KeePassNativeApi.openFromPathWithLocalChallenge` instead.
  Future<int> openDatabaseWithChallengeResponse(
    List<int> dbBytes, {
    required String password,
    required String challengeResponseHex,
  });

  /// Close a database and free resources.
  Future<void> closeDatabase(int handle);

  /// List child groups of a group. Pass empty string for root group.
  /// Returns list of maps: [{"uuid": "...", "name": "..."}]
  Future<List<Map<String, dynamic>>> listGroups(int handle, String groupUuid);

  /// List entries in a group. Pass empty string for root group.
  /// Returns list of maps: [{"uuid": "...", "title": "...", "username": "...", "url": "..."}]
  Future<List<Map<String, dynamic>>> listEntries(int handle, String groupUuid);

  /// Read an entry's fields, protection metadata, and tags.
  ///
  /// Protected field values come back as an empty string on every platform.
  /// Only [readEntryField] fetches their plaintext, so it crosses an FFI or
  /// WASM boundary only when a caller needs it (e.g. the user clicked
  /// "reveal" or "copy").
  Future<Map<String, dynamic>> readEntryFields(int handle, String entryUuid);

  /// Read a single field's plaintext value on demand (standard field or
  /// custom data key). Returns null if the entry or field doesn't exist.
  Future<String?> readEntryField(
    int handle,
    String entryUuid,
    String fieldName,
  );

  /// Create a new entry in [groupUuid] and return its UUID.
  Future<String> createEntry(int handle, String groupUuid);

  /// Set a field value on an entry.
  Future<void> setEntryField(
    int handle,
    String entryUuid,
    String field,
    String value, {
    bool isProtected = false,
  });

  /// Soft-delete an entry.
  Future<void> deleteEntry(int handle, String entryUuid);

  /// Move an entry to another group.
  Future<void> moveEntry(int handle, String entryUuid, String targetGroupUuid);

  /// Create a child group and return its UUID.
  Future<String> createGroup(int handle, String parentUuid, String name);

  /// Rename a group.
  Future<void> renameGroup(int handle, String groupUuid, String name);

  /// Soft-delete a group.
  Future<void> deleteGroup(int handle, String groupUuid);

  /// Move a group under another parent group.
  Future<void> moveGroup(int handle, String groupUuid, String targetParentUuid);

  /// Save the open database and return raw KDBX bytes.
  Future<List<int>> saveDatabase(
    int handle, {
    required String password,
    List<int>? keyFileBytes,
    String? yubiKeySlot,
    int yubiKeySerial = 0,
    String? localChallengeHex,
  });

  /// Return a live TOTP payload for an entry when supported.
  Future<Map<String, dynamic>?> getTotpCode(int handle, String entryUuid);

  /// Merge database B into database A.
  /// Returns merge result as map with counts and details.
  Future<Map<String, dynamic>> mergeDatabases(int handleA, int handleB);

  /// Stream of progress updates during long operations (e.g., Argon2 KDF).
  /// Emits percentage (0-100) or -1 for indeterminate.
  Stream<int> get progress;

  /// Initialize the API (load WASM, start Worker, etc.).
  /// No-op for native implementation.
  Future<void> init();

  /// Shut down and release all resources.
  Future<void> dispose();
}
