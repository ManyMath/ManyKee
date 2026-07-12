import 'dart:async';
import 'dart:typed_data';

import 'package:keepass_ui/keepass_ui.dart';
import 'package:keepass_web/keepass_web.dart';

import 'manykee_vault_state.dart';
import 'unlock_error_mapper.dart';
import 'web_file_storage_provider.dart';

ManyKeeVaultState createVaultState() => WebVaultState();

/// Browser vault state backed by the keepass_web WASM worker.
///
/// Browsers cannot reopen arbitrary local paths, so this state keeps the
/// selected database bytes in memory for the current session and saves by
/// generating a download.
class WebVaultState extends ManyKeeVaultState {
  WebVaultState({KeePassWebApi? api, WebFileStorageProvider? storageProvider})
    : _api = api ?? KeePassWebApi(),
      _storageProvider = storageProvider ?? WebFileStorageProvider();

  final KeePassWebApi _api;
  final WebFileStorageProvider _storageProvider;

  Uint8List? _lastDbBytes;
  Uint8List? _lastKeyFileBytes;
  String? _lastFilePath;
  bool _disposed = false;

  Uint8List? get lastDbBytes => _lastDbBytes;

  @override
  String? get lastFilePath => _lastFilePath;

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
    clearError();
    final bytes = dbBytes ?? _lastDbBytes;
    if (bytes == null) {
      setError('MISSING_DATABASE', 'Choose a database file before unlocking.');
      return;
    }

    final int handle;
    try {
      await _api.init();
      if (challengeResponseHex != null) {
        handle = await _api.openDatabaseWithChallengeResponse(
          bytes,
          password: password,
          challengeResponseHex: challengeResponseHex,
        );
      } else if (keyFileBytes != null) {
        handle = await _api.openDatabaseWithKeyFile(
          bytes,
          password: password,
          keyFileBytes: keyFileBytes,
        );
      } else {
        handle = await _api.openDatabase(bytes, password: password);
      }
    } on KeePassWebError catch (e) {
      final mapped = mapUnlockError(e.message, filePath: filename ?? filePath);
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

    _lastDbBytes = Uint8List.fromList(bytes);
    _lastKeyFileBytes = keyFileBytes == null
        ? null
        : Uint8List.fromList(keyFileBytes);
    _lastFilePath = filename ?? filePath;
    _storageProvider.rememberName(filename ?? filePath);
    handleValue = handle;
    lastFilenameValue = filename ?? filePath;
    await loadRootGroupsUsing(_api.listGroups);

    if (groups.isNotEmpty) {
      await selectGroup(groups.first);
    } else {
      await _loadRootEntries();
    }

    isLockedValue = false;
    clearDirtyFlag();
    notifyListeners();

    _scheduleCacheRefresh();
  }

  @override
  Future<void> unlockFromPath({
    required String filePath,
    required String password,
    String? keyFilePath,
    String? filename,
    String? yubiKeySlot,
  }) async {
    await unlock(
      filePath: filePath,
      password: password,
      filename: filename ?? filePath,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> listYubiKeys() async =>
      const <Map<String, dynamic>>[];

  @override
  void openDifferentFile() {
    _lastDbBytes?.fillRange(0, _lastDbBytes!.length, 0);
    _lastKeyFileBytes?.fillRange(0, _lastKeyFileBytes!.length, 0);
    _lastDbBytes = null;
    _lastKeyFileBytes = null;
    _lastFilePath = null;
    lastFilenameValue = null;
    clearError();
    notifyListeners();
  }

  @override
  Future<void> lock() async {
    if (handle != null) {
      await _api.closeDatabase(handle!);
    }
    _lastKeyFileBytes?.fillRange(0, _lastKeyFileBytes!.length, 0);
    _lastKeyFileBytes = null;
    resetBrowsingState();
  }

  @override
  Future<void> selectGroup(VaultGroup group) async {
    selectedGroupValue = group;
    selectedEntryValue = null;
    final generation = beginGroupSelection();
    final maps = await _api.listEntries(_requireHandle(), group.uuid);
    if (!isCurrentGroupSelection(generation)) {
      return;
    }
    entriesValue = maps
        .map((m) => VaultEntry.fromMap(m, groupUuid: group.uuid))
        .toList();
    notifyListeners();
  }

  @override
  Future<void> selectRoot() async {
    selectedGroupValue = null;
    selectedEntryValue = null;
    await _loadRootEntries();
  }

  @override
  Future<Map<String, dynamic>> readEntryFields(String entryUuid) async =>
      _api.readEntryFields(_requireHandle(), entryUuid);

  @override
  Future<String?> readEntryField(String entryUuid, String fieldName) async =>
      _api.readEntryField(_requireHandle(), entryUuid, fieldName);

  @override
  Future<Map<String, dynamic>?> getTotpCode(String entryUuid) async =>
      _api.getTotpCode(_requireHandle(), entryUuid);

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
    await _storageProvider.save(Uint8List.fromList(bytes), name: saveName);
    _storageProvider.rememberName(saveName);
    lastFilenameValue = saveName;
    _lastFilePath = saveName;
    _lastDbBytes = Uint8List.fromList(bytes);
    clearDirtyFlag();
    return bytes;
  }

  @override
  Future<void> saveCopyAs({
    required String filePath,
    required String password,
  }) async {
    if (password.isEmpty) {
      throw StateError('A master password is required to save');
    }

    final bytes = await _api.saveDatabase(
      _requireHandle(),
      password: password,
      keyFileBytes: _lastKeyFileBytes,
    );
    await _storageProvider.save(Uint8List.fromList(bytes), name: filePath);
  }

  int _requireHandle() {
    final currentHandle = handle;
    if (currentHandle == null) {
      throw StateError('Vault is locked');
    }
    return currentHandle;
  }

  Future<void> _loadRootEntries() async {
    final generation = beginGroupSelection();
    final maps = await _api.listEntries(_requireHandle(), '');
    if (!isCurrentGroupSelection(generation)) {
      return;
    }
    selectedEntryValue = null;
    entriesValue = maps
        .map((m) => VaultEntry.fromMap(m, groupUuid: ''))
        .toList();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _lastDbBytes?.fillRange(0, _lastDbBytes!.length, 0);
    _lastKeyFileBytes?.fillRange(0, _lastKeyFileBytes!.length, 0);
    _lastDbBytes = null;
    _lastKeyFileBytes = null;
    unawaited(_api.dispose());
    super.dispose();
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
        if (!_disposed && !isLocked) rethrow;
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
