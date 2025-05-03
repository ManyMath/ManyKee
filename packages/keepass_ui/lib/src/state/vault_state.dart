import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/vault_entry.dart';
import '../models/vault_group.dart';

abstract class VaultState extends ChangeNotifier {
 int? _handle;
 List<VaultGroup> _groups = [];
 List<VaultEntry> _entries = [];
 List<VaultEntry> _allEntries = [];
 bool _allEntriesCached = false;
 VaultGroup? _selectedGroup;
 VaultEntry? _selectedEntry;
 String _searchQuery = '';
 bool _isLocked = true;
 String? _lastFilename;
 String? _errorMessage;
 String? _errorCode;

 int? get handle => _handle;
 List<VaultGroup> get groups => _groups;
 List<VaultEntry> get entries => _entries;
 bool get allEntriesCached => _allEntriesCached;
 VaultGroup? get selectedGroup => _selectedGroup;
 VaultEntry? get selectedEntry => _selectedEntry;
 String get searchQuery => _searchQuery;
 bool get isLocked => _isLocked;
 String? get lastFilename => _lastFilename;
 String? get errorMessage => _errorMessage;
 String? get errorCode => _errorCode;

 Stream<int> get progress;

 @protected
 set handleValue(int? v) {
 _handle = v;
 }

 @protected
 set groupsValue(List<VaultGroup> v) {
 _groups = v;
 }

 @protected
 set entriesValue(List<VaultEntry> v) {
 _entries = v;
 }

 @protected
 set allEntriesValue(List<VaultEntry> v) {
 _allEntries = v;
 }

 @protected
 set allEntriesCachedValue(bool v) {
 _allEntriesCached = v;
 }

 @protected
 set selectedGroupValue(VaultGroup? v) {
 _selectedGroup = v;
 }

 @protected
 set selectedEntryValue(VaultEntry? v) {
 _selectedEntry = v;
 }

 @protected
 set isLockedValue(bool v) {
 _isLocked = v;
 }

 @protected
 set lastFilenameValue(String? v) {
 _lastFilename = v;
 }

 Future<void> unlock({
 Uint8List? dbBytes,
 String? filePath,
 required String password,
 Uint8List? keyFileBytes,
 String? challengeResponseHex,
 String? filename,
 });

 Future<void> lock();
 Future<void> selectGroup(VaultGroup group);
 Future<Map<String, dynamic>> readEntryFields(String entryUuid);

 void selectEntry(VaultEntry entry) {
 _selectedEntry = entry;
 notifyListeners();
 }

 void search(String query) {
 _searchQuery = query;
 notifyListeners();
 }

 List<VaultEntry> get searchResults {
 if (_searchQuery.length < 2 || !_allEntriesCached) return [];
 final q = _searchQuery.toLowerCase();
 return _allEntries
 .where((e) =>
 e.title.toLowerCase().contains(q) ||
 e.username.toLowerCase().contains(q) ||
 e.url.toLowerCase().contains(q))
 .toList();
 }

 void clearSearch() {
 _searchQuery = '';
 notifyListeners();
 }

 void setError(String code, String message) {
 _errorCode = code;
 _errorMessage = message;
 notifyListeners();
 }

 void clearError() {
 _errorCode = null;
 _errorMessage = null;
 }

 @protected
 void resetBrowsingState() {
 _handle = null;
 _groups = [];
 _entries = [];
 _allEntries = [];
 _allEntriesCached = false;
 _selectedGroup = null;
 _selectedEntry = null;
 _searchQuery = '';
 _isLocked = true;
 notifyListeners();
 }

 @protected
 Future<void> loadRootGroupsUsing(
 Future<List<Map<String, dynamic>>> Function(int handle, String groupUuid)
 listGroups,
 ) async {
 final rootChildren = await listGroups(_handle!, '');
 _groups = await Future.wait(
 rootChildren.map((m) => _buildGroupTree(m, listGroups)),
 );
 }

 Future<VaultGroup> _buildGroupTree(
 Map<String, dynamic> map,
 Future<List<Map<String, dynamic>>> Function(int handle, String groupUuid)
 listGroups,
 ) async {
 final uuid = map['uuid'] as String? ?? '';
 final childMaps = await listGroups(_handle!, uuid);
 final children = await Future.wait(
 childMaps.map((m) => _buildGroupTree(m, listGroups)),
 );
 return VaultGroup.fromMap(map, children: children);
 }

 @protected
 Future<void> cacheAllEntriesUsing(
 Future<List<Map<String, dynamic>>> Function(int handle, String groupUuid)
 listGroups,
 Future<List<Map<String, dynamic>>> Function(int handle, String groupUuid)
 listEntries,
 ) async {
 final entries = <VaultEntry>[];
 await _walkGroups(_handle!, '', 'Root', <String>[], entries, listGroups, listEntries);
 _allEntries = entries;
 _allEntriesCached = true;
 notifyListeners();
 }

 Future<void> _walkGroups(
 int handle,
 String groupUuid,
 String groupName,
 List<String> path,
 List<VaultEntry> out,
 Future<List<Map<String, dynamic>>> Function(int handle, String groupUuid)
 listGroups,
 Future<List<Map<String, dynamic>>> Function(int handle, String groupUuid)
 listEntries,
 ) async {
 final currentPath = [...path, groupName];
 final breadcrumb = currentPath.join(' > ');

 final entryMaps = await listEntries(handle, groupUuid);
 for (final m in entryMaps) {
 out.add(VaultEntry.fromMap(m, breadcrumb: breadcrumb));
 }

 final childGroups = await listGroups(handle, groupUuid);
 for (final child in childGroups) {
 final childName = child['name'] as String? ?? '';
 final childUuid = child['uuid'] as String? ?? '';
 await _walkGroups(handle, childUuid, childName, currentPath, out, listGroups, listEntries);
 }
 }
}
