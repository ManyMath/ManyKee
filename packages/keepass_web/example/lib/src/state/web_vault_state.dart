import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:keepass_ui/keepass_ui.dart';
import 'package:keepass_web/keepass_web.dart';

import 'web_file_storage_provider.dart';

/// Web-specific VaultState that uses [KeePassWebApi] (WASM worker).
class WebVaultState extends VaultState {
  final KeePassWebApi _api = KeePassWebApi();
  final WebFileStorageProvider _storageProvider = WebFileStorageProvider();

  Uint8List? _lastDbBytes;
  // Retained for the unlocked session so saveDatabase() can re-save without
  // re-prompting for the keyfile (there's no filesystem path to re-read from
  // on web, unlike NativeVaultState). Zeroized and cleared on lock().
  Uint8List? _lastKeyFileBytes;

  Uint8List? get lastDbBytes => _lastDbBytes;

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
    await _api.init();

    int handle;
    if (challengeResponseHex != null) {
      handle = await _api.openDatabaseWithChallengeResponse(
        dbBytes!,
        password: password,
        challengeResponseHex: challengeResponseHex,
      );
    } else if (keyFileBytes != null) {
      handle = await _api.openDatabaseWithKeyFile(
        dbBytes!,
        password: password,
        keyFileBytes: keyFileBytes,
      );
    } else {
      handle = await _api.openDatabase(dbBytes!, password: password);
    }

    handleValue = handle;
    lastFilenameValue = filename;
    _lastDbBytes = dbBytes;
    _lastKeyFileBytes = keyFileBytes;
    _storageProvider.rememberName(filename);
    await loadRootGroupsUsing(_api.listGroups);

    // Select the first group when present; otherwise expose root-level entries.
    if (groups.isNotEmpty) {
      await selectGroup(groups.first);
    } else {
      final maps = await _api.listEntries(handle, '');
      entriesValue = maps.map((m) => VaultEntry.fromMap(m)).toList();
    }

    isLockedValue = false;
    clearDirtyFlag();
    clearError();
    notifyListeners();

    unawaited(cacheAllEntriesUsing(_api.listGroups, _api.listEntries));
  }

  @override
  Future<void> lock() async {
    if (handle != null) {
      await _api.closeDatabase(handle!);
    }
    _lastKeyFileBytes?.fillRange(0, _lastKeyFileBytes!.length, 0);
    _lastKeyFileBytes = null;
    resetBrowsingState();
    // _lastDbBytes is kept for re-lock screen.
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
  Future<String?> readEntryField(String entryUuid, String fieldName) async {
    return _api.readEntryField(handle!, entryUuid, fieldName);
  }

  @override
  Future<Map<String, dynamic>?> getTotpCode(String entryUuid) async {
    return _api.getTotpCode(_requireHandle(), entryUuid);
  }

  @override
  Future<String> createEntry(String groupUuid) async {
    final entryUuid = await _api.createEntry(_requireHandle(), groupUuid);
    await refreshSelectedGroupUsing(
      selectGroup,
      loadRootEntries: _loadRootEntries,
    );
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
    await refreshSelectedGroupUsing(
      selectGroup,
      loadRootEntries: _loadRootEntries,
    );
    _selectEntryIfVisible(entryUuid);
    _scheduleCacheRefresh();
    markDirty();
  }

  @override
  Future<void> deleteEntry(String entryUuid) async {
    await _api.deleteEntry(_requireHandle(), entryUuid);
    await refreshSelectedGroupUsing(
      selectGroup,
      loadRootEntries: _loadRootEntries,
    );
    _scheduleCacheRefresh();
    markDirty();
  }

  @override
  Future<void> moveEntry(String entryUuid, String targetGroupUuid) async {
    await _api.moveEntry(_requireHandle(), entryUuid, targetGroupUuid);
    await refreshSelectedGroupUsing(
      selectGroup,
      loadRootEntries: _loadRootEntries,
    );
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
    await refreshGroupTreeUsing(
      _api.listGroups,
      selectGroup,
      loadRootEntries: _loadRootEntries,
    );
    _scheduleCacheRefresh();
    markDirty();
    return groupUuid;
  }

  @override
  Future<void> renameGroup(String groupUuid, String name) async {
    await _api.renameGroup(_requireHandle(), groupUuid, name);
    await refreshGroupTreeUsing(
      _api.listGroups,
      selectGroup,
      loadRootEntries: _loadRootEntries,
    );
    _scheduleCacheRefresh();
    markDirty();
  }

  @override
  Future<void> deleteGroup(String groupUuid) async {
    await _api.deleteGroup(_requireHandle(), groupUuid);
    await refreshGroupTreeUsing(
      _api.listGroups,
      selectGroup,
      loadRootEntries: _loadRootEntries,
    );
    _scheduleCacheRefresh();
    markDirty();
  }

  @override
  Future<void> moveGroup(String groupUuid, String targetParentUuid) async {
    await _api.moveGroup(_requireHandle(), groupUuid, targetParentUuid);
    await refreshGroupTreeUsing(
      _api.listGroups,
      selectGroup,
      loadRootEntries: _loadRootEntries,
    );
    _scheduleCacheRefresh();
    markDirty();
  }

  @override
  Future<List<int>> saveDatabase({
    required String password,
    List<int>? keyFileBytes,
  }) async {
    if (password.isEmpty) {
      throw StateError('A master password is required to save');
    }

    final bytes = await _api.saveDatabase(
      _requireHandle(),
      password: password,
      keyFileBytes: keyFileBytes ?? _lastKeyFileBytes,
    );
    final saveName = _resolvedSaveName();
    await _storageProvider.save(
      Uint8List.fromList(bytes),
      name: saveName,
    );
    _storageProvider.rememberName(saveName);
    lastFilenameValue = saveName;
    _lastDbBytes = Uint8List.fromList(bytes);
    clearDirtyFlag();
    return bytes;
  }

  Future<String> extractChallenge(Uint8List dbBytes) async {
    await _api.init();
    return _api.extractChallenge(dbBytes);
  }

  int _requireHandle() {
    final currentHandle = handle;
    if (currentHandle == null) {
      throw StateError('Vault is locked');
    }
    return currentHandle;
  }

  Future<void> _loadRootEntries() async {
    final maps = await _api.listEntries(_requireHandle(), '');
    entriesValue = maps.map((m) => VaultEntry.fromMap(m)).toList();
    notifyListeners();
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

  String _resolvedSaveName() {
    final currentName = lastFilename ?? _storageProvider.currentName;
    if (currentName == null || currentName.isEmpty) {
      return 'vault.kdbx';
    }
    return currentName;
  }
}
