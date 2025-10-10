import 'package:keepass_ui/keepass_ui.dart';

/// Test double for VaultState that provides canned data without FFI.
class FakeVaultState extends VaultState {
 FakeVaultState() {
 final testGroups = [
 VaultGroup(uuid: 'g1', name: 'General', children: [
 VaultGroup(uuid: 'g1a', name: 'Subgroup'),
 ]),
 VaultGroup(uuid: 'g2', name: 'Email'),
 VaultGroup(uuid: 'g3', name: 'Finance'),
 ];
 groupsValue = testGroups;
 entriesValue = [
 VaultEntry(
 uuid: 'e1',
 title: 'Sample Entry',
 username: 'User Name',
 url: 'http://keepass.info/',
 ),
 VaultEntry(
 uuid: 'e2',
 title: 'Another Entry',
 username: 'admin',
 url: 'https://example.com',
 ),
 ];
 selectedGroupValue = testGroups[0];
 isLockedValue = false;
 handleValue = 1;
 lastFilenameValue = 'test.kdbx';
 }

 @override
 Stream<int> get progress => Stream<int>.empty();

 @override
 Future<void> unlock({
 dynamic dbBytes,
 String? filePath,
 required String password,
 dynamic keyFileBytes,
 String? challengeResponseHex,
 String? filename,
 }) async {
 isLockedValue = false;
 clearError();
 notifyListeners();
 }

 @override
 Future<void> lock() async {
 resetBrowsingState();
 }

 @override
 Future<void> selectGroup(VaultGroup group) async {
 selectedGroupValue = group;
 selectedEntryValue = null;
 notifyListeners();
 }

 @override
 Future<Map<String, dynamic>> readEntryFields(String entryUuid) async {
 return {
 'Title': 'Sample Entry',
 'UserName': 'User Name',
 'Password': 'secret123',
 'URL': 'http://keepass.info/',
 'Notes': 'Test notes',
 };
 }
}
