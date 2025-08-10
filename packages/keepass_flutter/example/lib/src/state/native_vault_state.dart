import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:keepass/keepass.dart';
import 'package:keepass_ui/keepass_ui.dart';

/// Native VaultState that uses [KeePassNativeApi] (FFI).
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
 _lastFilePath = filePath;

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

unawaited(cacheAllEntriesUsing(_api.listGroups, _api.listEntries));
 }

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
