import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:keepass_flutter/keepass_flutter.dart';
import 'package:keepass_ui/keepass_ui.dart';

import 'local_file_storage_provider.dart';
import 'manykee_vault_state.dart';
import 'unlock_error_mapper.dart';

ManyKeeVaultState createVaultState() => NativeVaultState();

/// Vault state backed by [KeePassNativeApi] (FFI + worker isolate) and the
/// local filesystem. Adapted from the reference apps/native implementation
/// and extended with ManyKee's unlock, editing, and creation flows.
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
  Future<void> createDatabaseAtPath({
    required String filePath,
    required String password,
    String? filename,
  }) async {
    clearError();
    if (password.isEmpty) {
      setError(
        'MISSING_PASSWORD',
        'Choose a master password before creating a database.',
      );
      return;
    }

    int? createdHandle;
    try {
      createdHandle = await _api.createDatabase();
      _lastFilePath = filePath;
      _lastKeyFilePath = null;
      _lastYubiKeySlot = null;
      _storageProvider = LocalFileStorageProvider(initialPath: filePath);
      handleValue = createdHandle;
      lastFilenameValue = filename ?? _filenameForPath(filePath);
      await loadRootGroupsUsing(_api.listGroups);

      selectedGroupValue = null;
      selectedEntryValue = null;
      final maps = await _api.listEntries(createdHandle, '');
      entriesValue = maps.map((m) => VaultEntry.fromMap(m)).toList();
      isLockedValue = false;
      clearDirtyFlag();
      await saveDatabase(password: password);
      notifyListeners();

      _scheduleCacheRefresh();
    } catch (e) {
      final handleToClose = createdHandle;
      if (handleToClose != null) {
        try {
          await _api.closeDatabase(handleToClose);
        } catch (_) {}
      }
      _lastFilePath = null;
      _lastKeyFilePath = null;
      _lastYubiKeySlot = null;
      _storageProvider = LocalFileStorageProvider();
      lastFilenameValue = null;
      resetBrowsingState();
      setErrorWithDetail(
        'CREATE_DATABASE_FAILED',
        'Could not create the database. Please try again.',
        detail: truncateErrorDetail(e.toString()),
      );
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
      if (effectiveYubiKeySlot != null && effectiveKeyFilePath != null) {
        handle = await _api.openFromPathWithKeyFileAndYubiKey(
          filePath,
          password: password,
          keyFilePath: effectiveKeyFilePath,
          slot: effectiveYubiKeySlot,
        );
      } else if (effectiveYubiKeySlot != null) {
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
    if (_lastYubiKeySlot != null) {
      throw UnsupportedError(
        'Saving YubiKey-protected databases is not supported yet.',
      );
    }
    if (password.isEmpty) {
      throw StateError('A master password is required to save');
    }
    final bytes = await _api.saveDatabase(
      _requireHandle(),
      password: password,
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

  @override
  Future<void> saveCopyAs({
    required String filePath,
    required String password,
  }) async {
    if (_lastYubiKeySlot != null) {
      throw UnsupportedError(
        'Copying YubiKey-protected databases is not supported yet.',
      );
    }
    if (password.isEmpty) {
      throw StateError('A master password is required to save');
    }
    final bytes = await _api.saveDatabase(
      _requireHandle(),
      password: password,
      keyFileBytes: await _loadRememberedKeyFileBytes(),
    );
    await File(filePath).writeAsBytes(bytes, flush: true);
  }

  int _requireHandle() {
    final currentHandle = handle;
    if (currentHandle == null) {
      throw StateError('Vault is locked');
    }
    return currentHandle;
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

  String _filenameForPath(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty || parts.last.isEmpty ? path : parts.last;
  }
}
