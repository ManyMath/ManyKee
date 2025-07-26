import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:keepass/keepass.dart';
import 'package:keepass_ui/keepass_ui.dart';

/// Native VaultState that uses [KeePassNativeApi] (FFI).
///
/// Extends the abstract [VaultState] from keepass_ui, implementing all
/// platform-specific operations: unlock, lock, selectGroup, readEntryFields.
/// Uses [KeePassNativeApi.openFromPath] for direct file path access
/// (no temp file roundtrip needed on native).
class NativeVaultState extends VaultState {
  final KeePassNativeApi _api = KeePassNativeApi();

  /// Last opened file path, preserved across lock for re-lock flow (D-05).
  String? _lastFilePath;
  String? get lastFilePath => _lastFilePath;

  /// Stream of progress updates from the FFI API (-1 = indeterminate).
  @override
  Stream<int> get progress => _api.progress;

  // -- Vault lifecycle --

  /// Unlock a KDBX database via native FFI (generic interface).
  ///
  /// Delegates to [unlockNative]. The generic [VaultState.unlock] signature
  /// is preserved for KeePassApi compatibility.
  @override
  Future<void> unlock({
    Uint8List? dbBytes,
    String? filePath,
    required String password,
    Uint8List? keyFileBytes,
    String? challengeResponseHex,
    String? filename,
  }) async {
    await unlockNative(
      filePath: filePath!,
      password: password,
      filename: filename,
    );
  }

  /// Unlock with optional key file path (native-specific).
  ///
  /// Uses [KeePassNativeApi.openFromPathWithKeyFile] when [keyFilePath] is
  /// provided, otherwise [KeePassNativeApi.openFromPath]. Stores [filePath]
  /// for re-lock support (D-05).
  Future<void> unlockNative({
    required String filePath,
    required String password,
    String? keyFilePath,
    String? filename,
  }) async {
    _lastFilePath = filePath;

    int handle;
    if (keyFilePath != null) {
      handle = await _api.openFromPathWithKeyFile(
        filePath,
        password: password,
        keyFilePath: keyFilePath,
      );
    } else {
      handle = await _api.openFromPath(filePath, password: password);
    }

    handleValue = handle;
    lastFilenameValue = filename ?? filePath;
    await loadRootGroupsUsing(_api.listGroups);

    // Select first group by default.
    if (groups.isNotEmpty) {
      await selectGroup(groups.first);
    }

    isLockedValue = false;
    clearError();
    notifyListeners();

    // Cache all entries for search in the background.
    unawaited(cacheAllEntriesUsing(_api.listGroups, _api.listEntries));
  }

  /// Lock the vault: close the database and clear browsing state.
  ///
  /// Preserves [_lastFilePath] and [lastFilename] across lock for the
  /// re-lock screen (D-05).
  @override
  Future<void> lock() async {
    if (handle != null) {
      await _api.closeDatabase(handle!);
    }
    resetBrowsingState();
    // _lastFilePath and lastFilename survive for re-lock screen
  }

  /// Clear stored file path to return to fresh unlock screen.
  void openDifferentFile() {
    _lastFilePath = null;
    lastFilenameValue = null;
    clearError();
    notifyListeners();
  }

  // -- Browsing --

  /// Select a group and load its entries.
  @override
  Future<void> selectGroup(VaultGroup group) async {
    selectedGroupValue = group;
    selectedEntryValue = null;
    final maps = await _api.listEntries(handle!, group.uuid);
    entriesValue = maps.map((m) => VaultEntry.fromMap(m)).toList();
    notifyListeners();
  }

  /// Read all fields of an entry (including password, notes, custom fields).
  @override
  Future<Map<String, dynamic>> readEntryFields(String entryUuid) async {
    return _api.readEntryFields(handle!, entryUuid);
  }
}
