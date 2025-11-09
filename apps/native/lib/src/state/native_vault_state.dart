import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:keepass/keepass.dart';
import 'package:keepass_ui/keepass_ui.dart';

class NativeVaultState extends VaultState {
  final KeePassNativeApi _api = KeePassNativeApi();

  String? _lastFilePath;
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
    int handle;
    if (yubiKeySlot != null) {
      handle = await _api.openFromPathWithYubiKey(
        filePath,
        password: password,
        slot: yubiKeySlot,
      );
    } else if (keyFilePath != null) {
      handle = await _api.openFromPathWithKeyFile(
        filePath,
        password: password,
        keyFilePath: keyFilePath,
      );
    } else {
      handle = await _api.openFromPath(filePath, password: password);
    }

    _lastFilePath = filePath;
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
    clearError();
    notifyListeners();

    unawaited(cacheAllEntriesUsing(_api.listGroups, _api.listEntries));
  }

  @override
  Future<void> lock() async {
    if (handle != null) {
      await _api.closeDatabase(handle!);
    }
    resetBrowsingState();
  }

  void openDifferentFile() {
    _lastFilePath = null;
    lastFilenameValue = null;
    clearError();
    notifyListeners();
  }

  @override
  Future<void> selectGroup(VaultGroup group) async {
    selectedGroupValue = group;
    selectedEntryValue = null;
    final maps = await _api.listEntries(handle!, group.uuid);
    entriesValue = maps.map((m) => VaultEntry.fromMap(m)).toList();
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> readEntryFields(String entryUuid) async {
    return _api.readEntryFields(handle!, entryUuid);
  }
}
