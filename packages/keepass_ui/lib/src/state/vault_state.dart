import 'dart:async';
import 'dart:typed_data';

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
  bool _isDirty = false;
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
  bool get isDirty => _isDirty;
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
  set isDirtyValue(bool v) {
    _isDirty = v;
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
  Future<Map<String, dynamic>?> getTotpCode(String entryUuid);
  Future<String> createEntry(String groupUuid);
  Future<void> updateEntry(
    String entryUuid,
    Map<String, String?> fields, {
    Set<String> protectedFields = const <String>{},
  });
  Future<void> deleteEntry(String entryUuid);
  Future<void> moveEntry(String entryUuid, String targetGroupUuid);
  Future<String> createGroup(String parentGroupUuid, String name);
  Future<void> renameGroup(String groupUuid, String name);
  Future<void> deleteGroup(String groupUuid);
  Future<void> moveGroup(String groupUuid, String targetParentUuid);
  Future<List<int>> saveDatabase({
    required String password,
    List<int>? keyFileBytes,
  });

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
    _isDirty = false;
    notifyListeners();
  }

  @protected
  void markDirty() {
    _isDirty = true;
    notifyListeners();
  }

  @protected
  void clearDirtyFlag() {
    _isDirty = false;
    notifyListeners();
  }

  @protected
  Future<void> refreshSelectedGroupUsing(
    Future<void> Function(VaultGroup group) selectGroup, {
    Future<void> Function()? loadRootEntries,
  }) async {
    _allEntriesCached = false;
    if (_selectedGroup != null) {
      await selectGroup(_selectedGroup!);
    } else if (loadRootEntries != null) {
      await loadRootEntries();
    } else {
      notifyListeners();
    }
  }

  @protected
  Future<void> refreshGroupTreeUsing(
    Future<List<Map<String, dynamic>>> Function(int handle, String groupUuid)
        listGroups,
    Future<void> Function(VaultGroup group) selectGroup, {
    Future<void> Function()? loadRootEntries,
  }) async {
    final previousGroupUuid = _selectedGroup?.uuid;
    await loadRootGroupsUsing(listGroups);
    _allEntriesCached = false;

    if (previousGroupUuid == null) {
      notifyListeners();
      return;
    }

    final refreshedGroup = _findGroupByUuid(_groups, previousGroupUuid);
    if (refreshedGroup != null) {
      await selectGroup(refreshedGroup);
    } else if (_groups.isNotEmpty) {
      await selectGroup(_groups.first);
    } else if (loadRootEntries != null) {
      _selectedGroup = null;
      await loadRootEntries();
    } else {
      _entries = [];
      _selectedGroup = null;
      notifyListeners();
    }
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
    await _walkGroups(
        _handle!, '', 'Root', <String>[], entries, listGroups, listEntries);
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
      await _walkGroups(handle, childUuid, childName, currentPath, out,
          listGroups, listEntries);
    }
  }

  VaultGroup? _findGroupByUuid(List<VaultGroup> groups, String uuid) {
    for (final group in groups) {
      if (group.uuid == uuid) {
        return group;
      }
      final found = _findGroupByUuid(group.children, uuid);
      if (found != null) {
        return found;
      }
    }
    return null;
  }
}
