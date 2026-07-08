import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:keepass_ui/keepass_ui.dart' show VaultEntry, VaultGroup;

import 'manykee_vault_state.dart';

typedef VaultStateFactory = ManyKeeVaultState Function();

class VaultSessionSummary {
  const VaultSessionSummary({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.isActive,
    required this.isLocked,
    required this.isDirty,
  });

  final String id;
  final String label;
  final String? subtitle;
  final bool isActive;
  final bool isLocked;
  final bool isDirty;
}

class _VaultSession {
  _VaultSession({required this.id, required this.vault});

  final String id;
  final ManyKeeVaultState vault;
}

/// Owns all currently-open vault sessions and delegates the legacy
/// [ManyKeeVaultState] contract to the active session.
class VaultSessionsController extends ManyKeeVaultState {
  VaultSessionsController(this._createVault) {
    final initial = _newSession();
    _sessions.add(initial);
    _activeSessionId = initial.id;
  }

  final VaultStateFactory _createVault;
  final List<_VaultSession> _sessions = <_VaultSession>[];
  final Map<String, VoidCallback> _listeners = <String, VoidCallback>{};
  int _nextId = 1;
  late String _activeSessionId;

  List<VaultSessionSummary> get sessions {
    return List<VaultSessionSummary>.unmodifiable(
      _sessions.map((session) {
        final vault = session.vault;
        return VaultSessionSummary(
          id: session.id,
          label: _sessionLabel(vault),
          subtitle: _sessionSubtitle(vault),
          isActive: session.id == _activeSessionId,
          isLocked: vault.isLocked,
          isDirty: vault.isDirty,
        );
      }),
    );
  }

  int get sessionCount => _sessions.length;

  bool get hasUnlockedSessions =>
      _sessions.any((session) => !session.vault.isLocked);

  bool get hasUnlockedCleanSessions => _sessions.any(
    (session) => !session.vault.isLocked && !session.vault.isDirty,
  );

  ManyKeeVaultState get activeVault => _activeSession.vault;

  String get activeSessionId => _activeSessionId;

  void openNewSession() {
    if (activeVault.isLocked &&
        activeVault.lastFilePath == null &&
        activeVault.errorCode == null) {
      return;
    }
    final session = _newSession();
    _sessions.add(session);
    _activeSessionId = session.id;
    notifyListeners();
  }

  void switchToSession(String id) {
    if (id == _activeSessionId) return;
    _activeSessionById(id);
    _activeSessionId = id;
    notifyListeners();
  }

  Future<void> lockCleanSessions() async {
    for (final session in _sessions) {
      final vault = session.vault;
      if (!vault.isLocked && !vault.isDirty) {
        await vault.lock();
      }
    }
    notifyListeners();
  }

  @override
  int? get handle => activeVault.handle;

  @override
  List<VaultGroup> get groups => activeVault.groups;

  @override
  List<VaultEntry> get entries => activeVault.entries;

  @override
  bool get allEntriesCached => activeVault.allEntriesCached;

  @override
  VaultGroup? get selectedGroup => activeVault.selectedGroup;

  @override
  VaultEntry? get selectedEntry => activeVault.selectedEntry;

  @override
  String get searchQuery => activeVault.searchQuery;

  @override
  bool get isLocked => activeVault.isLocked;

  @override
  bool get isDirty => activeVault.isDirty;

  @override
  String? get lastFilename => activeVault.lastFilename;

  @override
  String? get errorMessage => activeVault.errorMessage;

  @override
  String? get errorCode => activeVault.errorCode;

  @override
  String? get errorDetail => activeVault.errorDetail;

  @override
  String? get lastFilePath => activeVault.lastFilePath;

  @override
  String? get lastYubiKeySlot => activeVault.lastYubiKeySlot;

  @override
  Stream<int> get progress => activeVault.progress;

  @override
  List<VaultEntry> get searchResults => activeVault.searchResults;

  @override
  Future<void> unlock({
    Uint8List? dbBytes,
    String? filePath,
    required String password,
    Uint8List? keyFileBytes,
    String? challengeResponseHex,
    String? filename,
  }) {
    return activeVault.unlock(
      dbBytes: dbBytes,
      filePath: filePath,
      password: password,
      keyFileBytes: keyFileBytes,
      challengeResponseHex: challengeResponseHex,
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
  }) {
    return activeVault.unlockFromPath(
      filePath: filePath,
      password: password,
      keyFilePath: keyFilePath,
      filename: filename,
      yubiKeySlot: yubiKeySlot,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> listYubiKeys() {
    return activeVault.listYubiKeys();
  }

  @override
  Future<void> createDatabaseAtPath({
    required String filePath,
    required String password,
    String? filename,
  }) {
    return activeVault.createDatabaseAtPath(
      filePath: filePath,
      password: password,
      filename: filename,
    );
  }

  @override
  void openDifferentFile() {
    activeVault.openDifferentFile();
  }

  @override
  Future<void> lock() {
    return activeVault.lock();
  }

  @override
  Future<void> selectGroup(VaultGroup group) {
    return activeVault.selectGroup(group);
  }

  @override
  void selectEntry(VaultEntry entry) {
    activeVault.selectEntry(entry);
  }

  @override
  void search(String query) {
    activeVault.search(query);
  }

  @override
  void clearSearch() {
    activeVault.clearSearch();
  }

  @override
  void setError(String code, String message) {
    activeVault.setError(code, message);
  }

  @override
  void setErrorWithDetail(String code, String message, {String? detail}) {
    activeVault.setErrorWithDetail(code, message, detail: detail);
  }

  @override
  void clearError() {
    activeVault.clearError();
  }

  @override
  Future<Map<String, dynamic>> readEntryFields(String entryUuid) {
    return activeVault.readEntryFields(entryUuid);
  }

  @override
  Future<String?> readEntryField(String entryUuid, String fieldName) {
    return activeVault.readEntryField(entryUuid, fieldName);
  }

  @override
  Future<Map<String, dynamic>?> getTotpCode(String entryUuid) {
    return activeVault.getTotpCode(entryUuid);
  }

  @override
  Future<String> createEntry(String groupUuid) {
    return activeVault.createEntry(groupUuid);
  }

  @override
  Future<void> updateEntry(
    String entryUuid,
    Map<String, String?> fields, {
    Set<String> protectedFields = const <String>{},
  }) {
    return activeVault.updateEntry(
      entryUuid,
      fields,
      protectedFields: protectedFields,
    );
  }

  @override
  Future<void> deleteEntry(String entryUuid) {
    return activeVault.deleteEntry(entryUuid);
  }

  @override
  Future<void> moveEntry(String entryUuid, String targetGroupUuid) {
    return activeVault.moveEntry(entryUuid, targetGroupUuid);
  }

  @override
  Future<String> createGroup(String parentGroupUuid, String name) {
    return activeVault.createGroup(parentGroupUuid, name);
  }

  @override
  Future<void> renameGroup(String groupUuid, String name) {
    return activeVault.renameGroup(groupUuid, name);
  }

  @override
  Future<void> deleteGroup(String groupUuid) {
    return activeVault.deleteGroup(groupUuid);
  }

  @override
  Future<void> moveGroup(String groupUuid, String targetParentUuid) {
    return activeVault.moveGroup(groupUuid, targetParentUuid);
  }

  @override
  Future<List<int>> saveDatabase({
    required String password,
    List<int>? keyFileBytes,
  }) {
    return activeVault.saveDatabase(
      password: password,
      keyFileBytes: keyFileBytes,
    );
  }

  @override
  Future<void> saveCopyAs({
    required String filePath,
    required String password,
  }) {
    return activeVault.saveCopyAs(filePath: filePath, password: password);
  }

  @override
  void dispose() {
    for (final session in _sessions) {
      final listener = _listeners.remove(session.id);
      if (listener != null) {
        session.vault.removeListener(listener);
      }
      session.vault.dispose();
    }
    _sessions.clear();
    super.dispose();
  }

  _VaultSession get _activeSession => _activeSessionById(_activeSessionId);

  _VaultSession _activeSessionById(String id) {
    for (final session in _sessions) {
      if (session.id == id) return session;
    }
    throw StateError('Unknown vault session: $id');
  }

  _VaultSession _newSession() {
    final id = 'vault-${_nextId++}';
    final vault = _createVault();
    late VoidCallback listener;
    listener = () => notifyListeners();
    vault.addListener(listener);
    _listeners[id] = listener;
    return _VaultSession(id: id, vault: vault);
  }

  String _sessionLabel(ManyKeeVaultState vault) {
    final filename = vault.lastFilename;
    if (filename != null && filename.trim().isNotEmpty) {
      return filename.split(RegExp(r'[/\\]')).last;
    }
    final filePath = vault.lastFilePath;
    if (filePath != null && filePath.trim().isNotEmpty) {
      return filePath.split(RegExp(r'[/\\]')).last;
    }
    return vault.isLocked ? 'Locked database' : 'Untitled database';
  }

  String? _sessionSubtitle(ManyKeeVaultState vault) {
    final parts = <String>[
      vault.isLocked ? 'Locked' : 'Open',
      if (vault.isDirty) 'Unsaved changes',
    ];
    final path = vault.lastFilePath;
    if (path != null && path.trim().isNotEmpty) {
      parts.add(path);
    }
    return parts.join(' · ');
  }
}
