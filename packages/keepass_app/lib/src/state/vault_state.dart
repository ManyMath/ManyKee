import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:keepass_web/src/keepass_web_api.dart';

import '../models/vault_entry.dart';
import '../models/vault_group.dart';

/// Central state manager for the vault lifecycle.
///
/// Wraps [KeePassWebApi] and exposes typed models for the UI.
/// Notifies listeners on every state change (unlock, group selection,
/// entry selection, search, lock).
class VaultState extends ChangeNotifier {
  final KeePassWebApi _api = KeePassWebApi();

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
  Uint8List? _lastDbBytes;
  String? _errorMessage;
  String? _errorCode;

  // -- Public getters --

  int? get handle => _handle;
  List<VaultGroup> get groups => _groups;
  List<VaultEntry> get entries => _entries;
  bool get allEntriesCached => _allEntriesCached;
  VaultGroup? get selectedGroup => _selectedGroup;
  VaultEntry? get selectedEntry => _selectedEntry;
  String get searchQuery => _searchQuery;
  bool get isLocked => _isLocked;
  String? get lastFilename => _lastFilename;
  Uint8List? get lastDbBytes => _lastDbBytes;
  String? get errorMessage => _errorMessage;
  String? get errorCode => _errorCode;

  /// Stream of progress updates from the WASM worker (-1 = indeterminate).
  Stream<int> get progress => _api.progress;

  // -- Vault lifecycle --

  /// Unlock a KDBX database.
  ///
  /// Initializes the WASM worker, opens the database, loads root groups,
  /// and starts caching all entries in the background for search.
  Future<void> unlock(
    Uint8List dbBytes,
    String password, {
    Uint8List? keyFileBytes,
    String? challengeResponseHex,
    String? filename,
  }) async {
    await _api.init();

    if (challengeResponseHex != null) {
      _handle = await _api.openDatabaseWithChallengeResponse(
        dbBytes,
        password: password,
        challengeResponseHex: challengeResponseHex,
      );
    } else if (keyFileBytes != null) {
      _handle = await _api.openDatabaseWithKeyFile(
        dbBytes,
        password: password,
        keyFileBytes: keyFileBytes,
      );
    } else {
      _handle = await _api.openDatabase(dbBytes, password: password);
    }

    _lastFilename = filename;
    _lastDbBytes = dbBytes;
    await _loadRootGroups();

    // Select root group by default (D-05).
    if (_groups.isNotEmpty) {
      await selectGroup(_groups.first);
    }

    _isLocked = false;
    clearError();
    notifyListeners();

    // Cache all entries for search in the background (pitfall 6).
    unawaited(_cacheAllEntries());
  }

  /// Lock the vault: close the database and clear all state.
  ///
  /// Keeps [_lastFilename] for the lock screen (UI-SPEC Screen 3).
  Future<void> lock() async {
    if (_handle != null) {
      await _api.closeDatabase(_handle!);
    }
    _handle = null;
    _groups = [];
    _entries = [];
    _allEntries = [];
    _allEntriesCached = false;
    _selectedGroup = null;
    _selectedEntry = null;
    _searchQuery = '';
    _isLocked = true;
    // Keep _lastFilename for re-lock screen.
    notifyListeners();
  }

  // -- Browsing --

  /// Select a group and load its entries.
  Future<void> selectGroup(VaultGroup group) async {
    _selectedGroup = group;
    _selectedEntry = null;
    final maps = await _api.listEntries(_handle!, group.uuid);
    _entries = maps.map((m) => VaultEntry.fromMap(m)).toList();
    notifyListeners();
  }

  /// Select an entry for detail view.
  void selectEntry(VaultEntry entry) {
    _selectedEntry = entry;
    notifyListeners();
  }

  /// Read all fields of an entry (including password, notes, custom fields).
  Future<Map<String, dynamic>> readEntryFields(String entryUuid) async {
    return _api.readEntryFields(_handle!, entryUuid);
  }

  // -- Search --

  /// Set the search query and notify listeners.
  void search(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Search results filtered from the cached entry list.
  ///
  /// Returns empty if query is shorter than 2 characters or cache not ready.
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

  /// Clear the search query.
  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }

  // -- Challenge extraction (YubiKey) --

  /// Extract the KDF seed (YubiKey challenge) from a KDBX file header.
  ///
  /// Returns hex-encoded challenge bytes. Requires WASM worker to be
  /// initialized ([init] must have been called or [unlock] will call it).
  Future<String> extractChallenge(Uint8List dbBytes) async {
    await _api.init();
    return _api.extractChallenge(dbBytes);
  }

  // -- Error handling --

  /// Set an error to display in the UI.
  void setError(String code, String message) {
    _errorCode = code;
    _errorMessage = message;
    notifyListeners();
  }

  /// Clear any displayed error.
  void clearError() {
    _errorCode = null;
    _errorMessage = null;
  }

  // -- Internal --

  /// Load root-level groups and build the full group tree recursively.
  Future<void> _loadRootGroups() async {
    final rootChildren = await _api.listGroups(_handle!, '');
    _groups = await Future.wait(
      rootChildren.map((m) => _buildGroupTree(m)),
    );
  }

  /// Recursively build a [VaultGroup] tree node.
  Future<VaultGroup> _buildGroupTree(Map<String, dynamic> map) async {
    final uuid = map['uuid'] as String? ?? '';
    final childMaps = await _api.listGroups(_handle!, uuid);
    final children = await Future.wait(
      childMaps.map((m) => _buildGroupTree(m)),
    );
    return VaultGroup.fromMap(map, children: children);
  }

  /// Walk all groups and cache every entry with breadcrumb paths for search.
  Future<void> _cacheAllEntries() async {
    final entries = <VaultEntry>[];
    await _walkGroups(_handle!, '', 'Root', <String>[], entries);
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
  ) async {
    final currentPath = [...path, groupName];
    final breadcrumb = currentPath.join(' > ');

    final entryMaps = await _api.listEntries(handle, groupUuid);
    for (final m in entryMaps) {
      out.add(VaultEntry.fromMap(m, breadcrumb: breadcrumb));
    }

    final childGroups = await _api.listGroups(handle, groupUuid);
    for (final child in childGroups) {
      final childName = child['name'] as String? ?? '';
      final childUuid = child['uuid'] as String? ?? '';
      await _walkGroups(handle, childUuid, childName, currentPath, out);
    }
  }
}
