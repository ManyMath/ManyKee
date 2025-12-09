import 'package:keepass_ui/keepass_ui.dart';

/// Test double for VaultState that provides canned data without FFI.
class FakeVaultState extends VaultState {
  final Map<String, List<VaultEntry>> _entriesByGroup =
      <String, List<VaultEntry>>{};
  final Map<String, Map<String, dynamic>> _fieldsByEntry =
      <String, Map<String, dynamic>>{};
  final Map<String, String> _entryGroup = <String, String>{};

  late final _FakeGroupNode _recycleBin;
  late final List<_FakeGroupNode> _rootGroups;

  int _nextEntryId = 3;
  int _nextGroupId = 4;

  FakeVaultState() {
    _recycleBin = _FakeGroupNode(uuid: 'bin', name: 'Recycle Bin');
    _rootGroups = <_FakeGroupNode>[
      _FakeGroupNode(
        uuid: 'g1',
        name: 'General',
        children: <_FakeGroupNode>[
          _FakeGroupNode(uuid: 'g1a', name: 'Subgroup'),
        ],
      ),
      _FakeGroupNode(uuid: 'g2', name: 'Email'),
      _FakeGroupNode(uuid: 'g3', name: 'Finance'),
      _recycleBin,
    ];

    _entriesByGroup['g1'] = <VaultEntry>[
      VaultEntry(
        uuid: 'e1',
        title: 'Sample Entry',
        username: 'User Name',
        url: 'http://keepass.info/',
      ),
    ];
    _entriesByGroup['g2'] = <VaultEntry>[
      VaultEntry(
        uuid: 'e2',
        title: 'Another Entry',
        username: 'admin',
        url: 'https://example.com',
      ),
    ];
    _fieldsByEntry['e1'] = <String, dynamic>{
      'Title': 'Sample Entry',
      'UserName': 'User Name',
      'Password': 'secret123',
      'URL': 'http://keepass.info/',
      'Notes': 'Test notes',
      'custom_data': <String, dynamic>{'otp': 'otpauth://totp/sample'},
    };
    _fieldsByEntry['e2'] = <String, dynamic>{
      'Title': 'Another Entry',
      'UserName': 'admin',
      'Password': 'password456',
      'URL': 'https://example.com',
      'Notes': '',
      'custom_data': <String, dynamic>{},
    };
    _entryGroup['e1'] = 'g1';
    _entryGroup['e2'] = 'g2';

    _refreshGroupsSnapshot();
    entriesValue = List<VaultEntry>.from(_entriesByGroup['g1']!);
    selectedGroupValue = _findVaultGroup('g1');
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
    final refreshedGroup = _findVaultGroup(group.uuid);
    selectedGroupValue = refreshedGroup ?? group;
    selectedEntryValue = null;
    entriesValue = List<VaultEntry>.from(
        _entriesByGroup[group.uuid] ?? const <VaultEntry>[]);
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> readEntryFields(String entryUuid) async {
    return Map<String, dynamic>.from(_fieldsByEntry[entryUuid] ?? const {});
  }

  @override
  Future<Map<String, dynamic>?> getTotpCode(String entryUuid) async {
    if (entryUuid != 'e1') {
      return null;
    }
    return <String, dynamic>{
      'code': '806863',
      'valid_for': 26,
      'period': 30,
    };
  }

  @override
  Future<String> createEntry(String groupUuid) async {
    final entryUuid = 'e${_nextEntryId++}';
    final entry = VaultEntry(
      uuid: entryUuid,
      title: 'New Entry',
      username: '',
      url: '',
    );
    final targetGroup =
        groupUuid.isEmpty ? (selectedGroup?.uuid ?? 'g1') : groupUuid;
    _entriesByGroup.putIfAbsent(targetGroup, () => <VaultEntry>[]).add(entry);
    _fieldsByEntry[entryUuid] = <String, dynamic>{
      'Title': entry.title,
      'UserName': '',
      'Password': '',
      'URL': '',
      'Notes': '',
      'custom_data': <String, dynamic>{},
    };
    _entryGroup[entryUuid] = targetGroup;
    if (selectedGroup?.uuid == targetGroup) {
      entriesValue = List<VaultEntry>.from(_entriesByGroup[targetGroup]!);
      selectedEntryValue = entry;
      notifyListeners();
    }
    return entryUuid;
  }

  @override
  Future<void> updateEntry(
    String entryUuid,
    Map<String, String?> fields, {
    Set<String> protectedFields = const <String>{},
  }) async {
    final stored =
        Map<String, dynamic>.from(_fieldsByEntry[entryUuid] ?? const {});
    stored.addAll(fields);
    _fieldsByEntry[entryUuid] = stored;

    final groupUuid = _entryGroup[entryUuid];
    if (groupUuid != null) {
      final entries =
          List<VaultEntry>.from(_entriesByGroup[groupUuid] ?? const []);
      final index = entries.indexWhere((entry) => entry.uuid == entryUuid);
      if (index >= 0) {
        entries[index] = VaultEntry(
          uuid: entryUuid,
          title: stored['Title'] as String? ?? '',
          username: stored['UserName'] as String? ?? '',
          url: stored['URL'] as String? ?? '',
        );
        _entriesByGroup[groupUuid] = entries;
        if (selectedGroup?.uuid == groupUuid) {
          entriesValue = entries;
          selectedEntryValue = entries[index];
        }
      }
    }
    notifyListeners();
  }

  @override
  Future<void> deleteEntry(String entryUuid) async {
    final groupUuid = _entryGroup.remove(entryUuid);
    _fieldsByEntry.remove(entryUuid);
    if (groupUuid != null) {
      final entries =
          List<VaultEntry>.from(_entriesByGroup[groupUuid] ?? const []);
      entries.removeWhere((entry) => entry.uuid == entryUuid);
      _entriesByGroup[groupUuid] = entries;
      if (selectedGroup?.uuid == groupUuid) {
        entriesValue = entries;
        selectedEntryValue = null;
      }
    }
    notifyListeners();
  }

  @override
  Future<void> moveEntry(String entryUuid, String targetGroupUuid) async {
    final sourceGroupUuid = _entryGroup[entryUuid];
    if (sourceGroupUuid == null || sourceGroupUuid == targetGroupUuid) {
      return;
    }

    final sourceEntries =
        List<VaultEntry>.from(_entriesByGroup[sourceGroupUuid] ?? const []);
    final index = sourceEntries.indexWhere((entry) => entry.uuid == entryUuid);
    if (index < 0) {
      return;
    }

    final entry = sourceEntries.removeAt(index);
    _entriesByGroup[sourceGroupUuid] = sourceEntries;
    _entriesByGroup
        .putIfAbsent(targetGroupUuid, () => <VaultEntry>[])
        .add(entry);
    _entryGroup[entryUuid] = targetGroupUuid;

    if (selectedGroup?.uuid == sourceGroupUuid) {
      entriesValue = sourceEntries;
      selectedEntryValue = null;
    }
    notifyListeners();
  }

  @override
  Future<String> createGroup(String parentGroupUuid, String name) async {
    final group = _FakeGroupNode(
      uuid: 'g${_nextGroupId++}',
      name: name,
    );

    if (parentGroupUuid.isEmpty) {
      _rootGroups.insert(_rootGroups.length - 1, group);
    } else {
      final parent = _findNode(parentGroupUuid);
      parent?.children.add(group);
    }

    await _syncGroups(preferredGroupUuid: group.uuid);
    return group.uuid;
  }

  @override
  Future<void> renameGroup(String groupUuid, String name) async {
    final group = _findNode(groupUuid);
    if (group == null) {
      return;
    }
    group.name = name;
    await _syncGroups(preferredGroupUuid: groupUuid);
  }

  @override
  Future<void> deleteGroup(String groupUuid) async {
    final removed = _removeNode(groupUuid, _rootGroups);
    if (removed == null || removed == _recycleBin) {
      return;
    }
    _recycleBin.children.add(removed);
    await _syncGroups(
      preferredGroupUuid: _containsGroupUuid(selectedGroup?.uuid)
          ? selectedGroup?.uuid
          : _firstVisibleGroupUuid(),
    );
  }

  @override
  Future<void> moveGroup(String groupUuid, String targetParentUuid) async {
    if (groupUuid == targetParentUuid) {
      return;
    }

    final group = _removeNode(groupUuid, _rootGroups);
    if (group == null || group == _recycleBin) {
      return;
    }

    final targetParent = _findNode(targetParentUuid);
    if (targetParent == null) {
      _rootGroups.insert(_rootGroups.length - 1, group);
    } else {
      targetParent.children.add(group);
    }

    await _syncGroups(preferredGroupUuid: groupUuid);
  }

  @override
  Future<List<int>> saveDatabase({
    required String password,
    List<int>? keyFileBytes,
  }) {
    throw UnimplementedError('FakeVaultState does not implement saveDatabase');
  }

  String? parentOfGroup(String groupUuid) =>
      _parentOfGroup(groupUuid, _rootGroups);

  Future<void> _syncGroups({String? preferredGroupUuid}) async {
    _refreshGroupsSnapshot();
    final nextGroup =
        preferredGroupUuid == null ? null : _findVaultGroup(preferredGroupUuid);
    final fallbackGroup = _findVaultGroup(_firstVisibleGroupUuid());

    selectedGroupValue = nextGroup ?? fallbackGroup;
    selectedEntryValue = null;
    entriesValue = List<VaultEntry>.from(
      _entriesByGroup[selectedGroup?.uuid] ?? const <VaultEntry>[],
    );
    notifyListeners();
  }

  void _refreshGroupsSnapshot() {
    groupsValue = _rootGroups.map((group) => group.toVaultGroup()).toList();
  }

  _FakeGroupNode? _findNode(String? groupUuid, [_FakeGroupNode? current]) {
    if (groupUuid == null) {
      return null;
    }

    if (current != null) {
      if (current.uuid == groupUuid) {
        return current;
      }
      for (final child in current.children) {
        final match = _findNode(groupUuid, child);
        if (match != null) {
          return match;
        }
      }
      return null;
    }

    for (final root in _rootGroups) {
      final match = _findNode(groupUuid, root);
      if (match != null) {
        return match;
      }
    }
    return null;
  }

  _FakeGroupNode? _removeNode(String groupUuid, List<_FakeGroupNode> groups) {
    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      if (group.uuid == groupUuid) {
        return groups.removeAt(i);
      }

      final removed = _removeNode(groupUuid, group.children);
      if (removed != null) {
        return removed;
      }
    }
    return null;
  }

  bool _containsGroupUuid(String? groupUuid) => _findNode(groupUuid) != null;

  String? _firstVisibleGroupUuid() {
    for (final group in _rootGroups) {
      if (group != _recycleBin) {
        return group.uuid;
      }
    }
    return null;
  }

  VaultGroup? _findVaultGroup(String? groupUuid, [List<VaultGroup>? groups]) {
    if (groupUuid == null) {
      return null;
    }

    for (final group in groups ?? this.groups) {
      if (group.uuid == groupUuid) {
        return group;
      }
      final childMatch = _findVaultGroup(groupUuid, group.children);
      if (childMatch != null) {
        return childMatch;
      }
    }
    return null;
  }

  String? _parentOfGroup(String groupUuid, List<_FakeGroupNode> groups) {
    for (final group in groups) {
      for (final child in group.children) {
        if (child.uuid == groupUuid) {
          return group.uuid;
        }
      }

      final nested = _parentOfGroup(groupUuid, group.children);
      if (nested != null) {
        return nested;
      }
    }
    return null;
  }
}

class _FakeGroupNode {
  _FakeGroupNode({
    required this.uuid,
    required this.name,
    List<_FakeGroupNode>? children,
  }) : children = children ?? <_FakeGroupNode>[];

  final String uuid;
  String name;
  final List<_FakeGroupNode> children;

  VaultGroup toVaultGroup() => VaultGroup(
        uuid: uuid,
        name: name,
        children: children.map((child) => child.toVaultGroup()).toList(),
      );
}
