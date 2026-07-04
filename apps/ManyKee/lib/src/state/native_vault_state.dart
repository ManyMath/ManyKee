import 'dart:async';
import 'dart:typed_data';

import 'package:keepass_flutter/keepass_flutter.dart';
import 'package:keepass_ui/keepass_ui.dart';

import 'local_file_storage_provider.dart';
import 'manykee_vault_state.dart';
import 'unlock_error_mapper.dart';

ManyKeeVaultState createVaultState() => NativeVaultState();

/// Vault state backed by [KeePassNativeApi] (FFI + worker isolate) and the
/// local filesystem. Adapted from the reference apps/native implementation,
/// trimmed to phase A's read-only surface.
class NativeVaultState extends ManyKeeVaultState {
  final KeePassNativeApi _api = KeePassNativeApi();

  LocalFileStorageProvider _storageProvider = LocalFileStorageProvider();
  String? _lastFilePath;
  String? _lastKeyFilePath;
  String? _lastYubiKeySlot;

  @override
  String? get lastFilePath => _lastFilePath;

  @override
  String? get lastYubiKeySlot => _lastYubiKeySlot;

  /// The provider that will back save in phase B; tracks the open file.
  LocalFileStorageProvider get storageProvider => _storageProvider;

  @override
  Stream<int> get progress => _api.progress;

  @override
  Future<List<Map<String, dynamic>>> listYubiKeys() async {
    try {
      return await _api.listYubiKeys();
    } catch (_) {
      // Detection failure (no pcsc, no permission) just means no YubiKey UI.
      return const <Map<String, dynamic>>[];
    }
  }

  @override
  Future<void> unlock({
    Uint8List? dbBytes,
    String? filePath,
    required String password,
    Uint8List? keyFileBytes,
    String? challengeResponseHex,
    String? filename,
  }) {
    return unlockFromPath(
      filePath: filePath!,
      password: password,
      filename: filename,
    );
  }

  @override
  Future<void> unlockFromPath({
    required String filePath,
    required String password,
    String? keyFilePath,
    String? filename,
    String? yubiKeySlot,
  }) async {
    clearError();
    final effectiveKeyFilePath = keyFilePath ?? _lastKeyFilePath;
    final effectiveYubiKeySlot = yubiKeySlot ?? _lastYubiKeySlot;

    final int handle;
    try {
      if (effectiveYubiKeySlot != null) {
        handle = await _api.openFromPathWithYubiKey(
          filePath,
          password: password,
          slot: effectiveYubiKeySlot,
        );
      } else if (effectiveKeyFilePath != null) {
        handle = await _api.openFromPathWithKeyFile(
          filePath,
          password: password,
          keyFilePath: effectiveKeyFilePath,
        );
      } else {
        handle = await _api.openFromPath(filePath, password: password);
      }
    } on KeePassError catch (e) {
      final mapped = mapUnlockError(e.message, filePath: filePath);
      setErrorWithDetail(mapped.code, mapped.message, detail: mapped.detail);
      return;
    } catch (e) {
      setErrorWithDetail(
        'UNKNOWN',
        'Something went wrong while unlocking. Please try again.',
        detail: truncateErrorDetail(e.toString()),
      );
      return;
    }

    _lastFilePath = filePath;
    _lastKeyFilePath = effectiveKeyFilePath;
    _lastYubiKeySlot = effectiveYubiKeySlot;
    _storageProvider = LocalFileStorageProvider(initialPath: filePath);
    handleValue = handle;
    lastFilenameValue = filename ?? filePath;
    await loadRootGroupsUsing(_api.listGroups);

    if (groups.isNotEmpty) {
      await selectGroup(groups.first);
    } else {
      final maps = await _api.listEntries(handle, '');
      entriesValue = maps.map((m) => VaultEntry.fromMap(m)).toList();
    }

    isLockedValue = false;
    clearDirtyFlag();
    notifyListeners();

    _scheduleCacheRefresh();
  }

  @override
  Future<void> lock() async {
    if (handle != null) {
      await _api.closeDatabase(handle!);
    }
    resetBrowsingState();
  }

  @override
  void openDifferentFile() {
    _lastFilePath = null;
    _lastKeyFilePath = null;
    _lastYubiKeySlot = null;
    _storageProvider = LocalFileStorageProvider();
    lastFilenameValue = null;
    clearError();
    notifyListeners();
  }

  @override
  Future<void> selectGroup(VaultGroup group) async {
    selectedGroupValue = group;
    selectedEntryValue = null;
    final generation = beginGroupSelection();
    final maps = await _api.listEntries(handle!, group.uuid);
    if (!isCurrentGroupSelection(generation)) {
      return;
    }
    entriesValue = maps.map((m) => VaultEntry.fromMap(m)).toList();
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> readEntryFields(String entryUuid) {
    return _api.readEntryFields(_requireHandle(), entryUuid);
  }

  @override
  Future<String?> readEntryField(String entryUuid, String fieldName) {
    return _api.readEntryField(_requireHandle(), entryUuid, fieldName);
  }

  @override
  Future<Map<String, dynamic>?> getTotpCode(String entryUuid) {
    return _api.getTotpCode(_requireHandle(), entryUuid);
  }

  int _requireHandle() {
    final currentHandle = handle;
    if (currentHandle == null) {
      throw StateError('Vault is locked');
    }
    return currentHandle;
  }

  void _scheduleCacheRefresh() {
    unawaited(() async {
      try {
        await cacheAllEntriesUsing(_api.listGroups, _api.listEntries);
      } catch (_) {
        if (!isLocked) rethrow;
      }
    }());
  }
}
