import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:keepass/keepass.dart';
import 'package:keepass_ui/keepass_ui.dart';

import 'local_file_storage_provider.dart';

/// Native VaultState that uses [KeePassNativeApi] (FFI).
class NativeVaultState extends VaultState {
  final KeePassNativeApi _api = KeePassNativeApi();

  LocalFileStorageProvider _storageProvider = LocalFileStorageProvider();
  String? _lastFilePath;
  String? _lastKeyFilePath;
  String? _lastYubiKeySlot;
  String? _retainedPassword;

  String? get lastFilePath => _lastFilePath;
  String? get retainedPassword => _retainedPassword;

  @override
  Stream<int> get progress => _api.progress;

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

  Future<void> unlockNative({
    required String filePath,
    required String password,
    String? keyFilePath,
    String? yubiKeySlot,
    String? filename,
  }) async {
    final effectiveKeyFilePath = keyFilePath ?? _lastKeyFilePath;
    final effectiveYubiKeySlot = yubiKeySlot ?? _lastYubiKeySlot;

    int handle;
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

    _lastFilePath = filePath;
    _lastKeyFilePath = effectiveKeyFilePath;
    _lastYubiKeySlot = effectiveYubiKeySlot;
    _retainedPassword = password;
    _storageProvider = LocalFileStorageProvider(initialPath: filePath);
    handleValue = handle;
    lastFilenameValue = filename ?? filePath;
    await loadRootGroupsUsing(_api.listGroups);

    // Select first group by default.
    if (groups.isNotEmpty) {
      await selectGroup(groups.first);
    }

    isLockedValue = false;
    clearDirtyFlag();
    clearError();
    notifyListeners();

    _scheduleCacheRefresh();
  }

  @override
  Future<void> lock() async {
    if (handle != null) {
      await _api.closeDatabase(handle!);
    }
    _retainedPassword = null;
    resetBrowsingState();
  }

  /// Clear stored file path to return to fresh unlock screen.
  void openDifferentFile() {
    _lastFilePath = null;
    _lastKeyFilePath = null;
    _lastYubiKeySlot = null;
    _retainedPassword = null;
    _storageProvider = LocalFileStorageProvider();
    lastFilenameValue = null;
    clearError();
    notifyListeners();
  }

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

  @override
  Future<Map<String, dynamic>?> getTotpCode(String entryUuid) async {
    return _api.getTotpCode(_requireHandle(), entryUuid);
  }

  @override
  Future<String> createEntry(String groupUuid) async {
    final entryUuid = await _api.createEntry(_requireHandle(), groupUuid);
    await refreshSelectedGroupUsing(selectGroup);
    _selectEntryIfVisible(entryUuid);
    _scheduleCacheRefresh();
    markDirty();
    return entryUuid;
  }

  @override
  Future<void> updateEntry(
    String entryUuid,
    Map<String, String?> fields, {
    Set<String> protectedFields = const <String>{},
  }) async {
    final databaseHandle = _requireHandle();
    for (final field in fields.entries) {
      await _api.setEntryField(
        databaseHandle,
        entryUuid,
        field.key,
        field.value ?? '',
        isProtected: protectedFields.contains(field.key),
      );
    }
    await refreshSelectedGroupUsing(selectGroup);
    _selectEntryIfVisible(entryUuid);
    _scheduleCacheRefresh();
    markDirty();
  }

  @override
  Future<void> deleteEntry(String entryUuid) async {
    await _api.deleteEntry(_requireHandle(), entryUuid);
    await refreshSelectedGroupUsing(selectGroup);
    _scheduleCacheRefresh();
    markDirty();
  }

  @override
  Future<void> moveEntry(String entryUuid, String targetGroupUuid) async {
    await _api.moveEntry(_requireHandle(), entryUuid, targetGroupUuid);
    await refreshSelectedGroupUsing(selectGroup);
    _scheduleCacheRefresh();
    markDirty();
  }

  @override
  Future<String> createGroup(String parentGroupUuid, String name) async {
    final groupUuid = await _api.createGroup(
      _requireHandle(),
      parentGroupUuid,
      name,
    );
    await refreshGroupTreeUsing(_api.listGroups, selectGroup);
    _scheduleCacheRefresh();
    markDirty();
    return groupUuid;
  }

  @override
  Future<void> renameGroup(String groupUuid, String name) async {
    await _api.renameGroup(_requireHandle(), groupUuid, name);
    await refreshGroupTreeUsing(_api.listGroups, selectGroup);
    _scheduleCacheRefresh();
    markDirty();
  }

  @override
  Future<void> deleteGroup(String groupUuid) async {
    await _api.deleteGroup(_requireHandle(), groupUuid);
    await refreshGroupTreeUsing(_api.listGroups, selectGroup);
    _scheduleCacheRefresh();
    markDirty();
  }

  @override
  Future<void> moveGroup(String groupUuid, String targetParentUuid) async {
    await _api.moveGroup(_requireHandle(), groupUuid, targetParentUuid);
    await refreshGroupTreeUsing(_api.listGroups, selectGroup);
    _scheduleCacheRefresh();
    markDirty();
  }

  @override
  Future<List<int>> saveDatabase({
    required String password,
    List<int>? keyFileBytes,
  }) async {
    final bytes = await _api.saveDatabase(
      _requireHandle(),
      password: _resolveSavePassword(password),
      keyFileBytes: keyFileBytes ?? await _loadRememberedKeyFileBytes(),
    );
    _storageProvider.rememberPath(_lastFilePath);
    await _storageProvider.save(
      Uint8List.fromList(bytes),
      name: lastFilename ?? 'vault.kdbx',
    );
    clearDirtyFlag();
    return bytes;
  }

  int _requireHandle() {
    final currentHandle = handle;
    if (currentHandle == null) {
      throw StateError('Vault is locked');
    }
    return currentHandle;
  }

  String _resolveSavePassword(String password) {
    if (password.isNotEmpty) {
      return password;
    }
    final retained = _retainedPassword;
    if (retained == null || retained.isEmpty) {
      throw StateError('No in-memory password is available for save');
    }
    return retained;
  }

  Future<List<int>?> _loadRememberedKeyFileBytes() async {
    final keyFilePath = _lastKeyFilePath;
    if (keyFilePath == null) {
      return null;
    }
    return File(keyFilePath).readAsBytes();
  }

  void _selectEntryIfVisible(String entryUuid) {
    for (final entry in entries) {
      if (entry.uuid == entryUuid) {
        selectedEntryValue = entry;
        return;
      }
    }
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
