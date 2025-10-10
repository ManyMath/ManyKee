import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:keepass_ui/keepass_ui.dart';
import 'package:keepass_web/keepass_web.dart';

class WebVaultState extends VaultState {
  final KeePassWebApi _api = KeePassWebApi();

  Uint8List? _lastDbBytes;

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
    await loadRootGroupsUsing(_api.listGroups);

    if (groups.isNotEmpty) {
      await selectGroup(groups.first);
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

  Future<String> extractChallenge(Uint8List dbBytes) async {
    await _api.init();
    return _api.extractChallenge(dbBytes);
  }
}
