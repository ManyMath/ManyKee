import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:keepass_ui/keepass_ui.dart';
import 'package:keepass_web/keepass_web.dart';

/// Web-specific VaultState that uses [KeePassWebApi] (WASM worker).
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

 // Select the first group when present; otherwise expose root-level entries.
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

Future<String> extractChallenge(Uint8List dbBytes) async {
 await _api.init();
 return _api.extractChallenge(dbBytes);
 }
}
