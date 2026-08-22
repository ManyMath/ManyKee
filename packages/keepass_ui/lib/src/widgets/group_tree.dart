import 'dart:async';

import 'package:flutter/material.dart';

import '../models/vault_group.dart';
import '../state/vault_state.dart';
import '../theme/spacing.dart';
import 'search_bar.dart';

class GroupTree extends StatefulWidget {
  final List<VaultGroup> groups;
  final VaultGroup? selectedGroup;
  final FutureOr<void> Function(VaultGroup) onGroupSelected;
  final VaultState vaultState;

  const GroupTree({
    super.key,
    required this.groups,
    this.selectedGroup,
    required this.onGroupSelected,
    required this.vaultState,
  });

  @override
  State<GroupTree> createState() => _GroupTreeState();
}

class _GroupTreeState extends State<GroupTree> {
  final Set<String> _expanded = <String>{};
  String? _mutatingGroupUuid;

  @override
  void initState() {
    super.initState();
    _expandGroupsWithChildren(_visibleGroups);
  }

  @override
  void didUpdateWidget(GroupTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    _expandGroupsWithChildren(_visibleGroups);
    final selectedGroup = widget.selectedGroup;
    if (selectedGroup != null) {
      _expanded.addAll(_pathToGroup(selectedGroup.uuid, _visibleGroups));
    }
  }

  List<VaultGroup> get _visibleGroups => _filterVisibleGroups(widget.groups);

  List<_FlatGroupNode> _flatten(List<VaultGroup> groups, int depth) {
    final result = <_FlatGroupNode>[];
    for (final group in groups) {
      result.add(_FlatGroupNode(group: group, depth: depth));
      if (_expanded.contains(group.uuid) && group.children.isNotEmpty) {
        result.addAll(_flatten(group.children, depth + 1));
      }
    }
    return result;
  }

  void _expandGroupsWithChildren(List<VaultGroup> groups) {
    for (final group in groups) {
      if (group.children.isNotEmpty) {
        _expanded.add(group.uuid);
        _expandGroupsWithChildren(group.children);
      }
    }
  }

  void _toggleExpanded(VaultGroup group) {
    setState(() {
      if (_expanded.contains(group.uuid)) {
        _expanded.remove(group.uuid);
      } else {
        _expanded.add(group.uuid);
      }
    });
  }

  List<VaultGroup> _filterVisibleGroups(List<VaultGroup> groups) {
    return groups
        .where((group) => !_isRecycleBin(group))
        .map(
          (group) => VaultGroup(
            uuid: group.uuid,
            name: group.name,
            children: _filterVisibleGroups(group.children),
          ),
        )
        .toList();
  }

  bool _isRecycleBin(VaultGroup group) =>
      group.name.trim().toLowerCase() == 'recycle bin';

  List<String> _pathToGroup(String groupUuid, List<VaultGroup> groups) {
    for (final group in groups) {
      if (group.uuid == groupUuid) {
        return <String>[group.uuid];
      }

      final childPath = _pathToGroup(groupUuid, group.children);
      if (childPath.isNotEmpty) {
        return <String>[group.uuid, ...childPath];
      }
    }
    return const <String>[];
  }

  VaultGroup? _findGroupByUuid(String groupUuid, List<VaultGroup> groups) {
    for (final group in groups) {
      if (group.uuid == groupUuid) {
        return group;
      }
      final childMatch = _findGroupByUuid(groupUuid, group.children);
      if (childMatch != null) {
        return childMatch;
      }
    }
    return null;
  }

  Set<String> _collectDescendantUuids(VaultGroup group) {
    final uuids = <String>{group.uuid};
    for (final child in group.children) {
      uuids.addAll(_collectDescendantUuids(child));
    }
    return uuids;
  }

  Future<void> _setMutatingGroup(String? groupUuid) async {
    if (!mounted) {
      return;
    }
    setState(() => _mutatingGroupUuid = groupUuid);
  }

  Future<void> _handleAction(_GroupAction action, VaultGroup group) async {
    switch (action) {
      case _GroupAction.create:
        await _createGroup(group);
        return;
      case _GroupAction.rename:
        await _renameGroup(group);
        return;
      case _GroupAction.move:
        await _moveGroup(group);
        return;
      case _GroupAction.delete:
        await _deleteGroup(group);
        return;
    }
  }

  Future<void> _createGroup(VaultGroup parentGroup) async {
    final name = await showGroupNameDialog(
      context,
      title: 'Create Group',
      submitLabel: 'Create Group',
      label: 'Group name',
    );
    if (name == null) {
      return;
    }

    await _setMutatingGroup(parentGroup.uuid);
    try {
      final groupUuid = await widget.vaultState.createGroup(
        parentGroup.uuid,
        name,
      );
      final createdGroup =
          _findGroupByUuid(groupUuid, widget.vaultState.groups);
      final path = _pathToGroup(groupUuid, _visibleGroups);
      if (mounted) {
        setState(() {
          _expanded.add(parentGroup.uuid);
          _expanded.addAll(path);
        });
      }
      if (createdGroup != null) {
        await widget.onGroupSelected(createdGroup);
      }
    } catch (error) {
      _showMutationError(error);
    } finally {
      await _setMutatingGroup(null);
    }
  }

  Future<void> _renameGroup(VaultGroup group) async {
    final name = await showGroupNameDialog(
      context,
      title: 'Rename Group',
      submitLabel: 'Save Group',
      label: 'Group name',
      initialValue: group.name,
    );
    if (name == null || name == group.name) {
      return;
    }

    await _setMutatingGroup(group.uuid);
    try {
      await widget.vaultState.renameGroup(group.uuid, name);
      final refreshedGroup =
          _findGroupByUuid(group.uuid, widget.vaultState.groups);
      if (refreshedGroup != null && widget.selectedGroup?.uuid == group.uuid) {
        await widget.onGroupSelected(refreshedGroup);
      }
    } catch (error) {
      _showMutationError(error);
    } finally {
      await _setMutatingGroup(null);
    }
  }

  Future<void> _moveGroup(VaultGroup group) async {
    final forbiddenUuids = _collectDescendantUuids(group);
    final targetGroupUuid = await showGroupMoveDialog(
      context,
      groups: _visibleGroups,
      groupUuid: group.uuid,
      initialParentUuid: null,
      forbiddenUuids: forbiddenUuids,
    );
    if (targetGroupUuid == null) {
      return;
    }

    await _setMutatingGroup(group.uuid);
    try {
      await widget.vaultState.moveGroup(group.uuid, targetGroupUuid);
      final path = _pathToGroup(group.uuid, _visibleGroups);
      final movedGroup = _findGroupByUuid(group.uuid, widget.vaultState.groups);
      if (mounted) {
        setState(() => _expanded.addAll(path));
      }
      if (movedGroup != null) {
        await widget.onGroupSelected(movedGroup);
      }
    } catch (error) {
      _showMutationError(error);
    } finally {
      await _setMutatingGroup(null);
    }
  }

  Future<void> _deleteGroup(VaultGroup group) async {
    final confirmed = await showGroupDeleteConfirmation(context);
    if (!confirmed) {
      return;
    }

    await _setMutatingGroup(group.uuid);
    try {
      await widget.vaultState.deleteGroup(group.uuid);
      final removedUuids = _collectDescendantUuids(group);
      if (mounted) {
        setState(() => _expanded.removeAll(removedUuids));
      }
    } catch (error) {
      _showMutationError(error);
    } finally {
      await _setMutatingGroup(null);
    }
  }

  void _showMutationError(Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not complete group action: $error')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _flatten(_visibleGroups, 0);

    return Column(
      children: [
        VaultSearchBar(
          vaultState: widget.vaultState,
          enabled: widget.vaultState.allEntriesCached,
        ),
        Expanded(
          child: ListView.builder(
            itemCount: nodes.length,
            itemBuilder: (context, index) {
              final node = nodes[index];
              return _GroupTile(
                group: node.group,
                depth: node.depth,
                isSelected: widget.selectedGroup?.uuid == node.group.uuid,
                isExpanded: _expanded.contains(node.group.uuid),
                hasChildren: node.group.children.isNotEmpty,
                isMutating: _mutatingGroupUuid == node.group.uuid,
                onTap: () => widget.onGroupSelected(node.group),
                onToggleExpand: () => _toggleExpanded(node.group),
                onActionSelected: (action) => _handleAction(action, node.group),
              );
            },
          ),
        ),
      ],
    );
  }
}

Future<String?> showGroupNameDialog(
  BuildContext context, {
  required String title,
  required String submitLabel,
  required String label,
  String initialValue = '',
}) {
  final controller = TextEditingController(text: initialValue);
  final formKey = GlobalKey<FormState>();

  Widget buildContent(BuildContext dialogContext) {
    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: Spacing.lg,
        bottom: Spacing.lg + MediaQuery.viewInsetsOf(dialogContext).bottom,
      ),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(dialogContext).textTheme.titleLarge),
            const SizedBox(height: Spacing.lg),
            TextFormField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(labelText: label),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Group name is required';
                }
                return null;
              },
              onFieldSubmitted: (_) {
                if (formKey.currentState!.validate()) {
                  Navigator.of(dialogContext).pop(controller.text.trim());
                }
              },
            ),
            const SizedBox(height: Spacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: Spacing.sm),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.of(dialogContext).pop(controller.text.trim());
                    }
                  },
                  child: Text(submitLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  final isMobile = MediaQuery.sizeOf(context).width < 600;
  if (isMobile) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: buildContent(sheetContext)),
    );
  }

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: buildContent(dialogContext),
      ),
    ),
  );
}

Future<String?> showGroupMoveDialog(
  BuildContext context, {
  required List<VaultGroup> groups,
  required String groupUuid,
  required Set<String> forbiddenUuids,
  String? initialParentUuid,
}) {
  final options = _flattenGroups(
    groups,
    forbiddenUuids: forbiddenUuids,
  );
  if (options.isEmpty) {
    return Future<String?>.value(null);
  }

  final content = _MoveGroupDialog(
    options: options,
    groupUuid: groupUuid,
    initialParentUuid: initialParentUuid,
  );
  final isMobile = MediaQuery.sizeOf(context).width < 600;
  if (isMobile) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(child: content),
    );
  }

  return showDialog<String>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: content,
      ),
    ),
  );
}

Future<bool> showGroupDeleteConfirmation(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Delete this group?'),
        content: const Text(
          'The group will be removed from the main tree. '
          'It moves to the recycle bin if one is available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Delete Group'),
          ),
        ],
      );
    },
  );

  return result ?? false;
}

class _MoveGroupDialog extends StatefulWidget {
  const _MoveGroupDialog({
    required this.options,
    required this.groupUuid,
    this.initialParentUuid,
  });

  final List<_GroupOption> options;
  final String groupUuid;
  final String? initialParentUuid;

  @override
  State<_MoveGroupDialog> createState() => _MoveGroupDialogState();
}

class _MoveGroupDialogState extends State<_MoveGroupDialog> {
  late String _selectedGroupUuid;

  @override
  void initState() {
    super.initState();
    _selectedGroupUuid =
        widget.initialParentUuid ?? widget.options.first.group.uuid;
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleLarge;
    return Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Move Group', style: titleStyle),
          const SizedBox(height: Spacing.lg),
          DropdownButtonFormField<String>(
            initialValue: _selectedGroupUuid,
            items: widget.options
                .map(
                  (option) => DropdownMenuItem<String>(
                    value: option.group.uuid,
                    child: Text(
                      '${'  ' * option.depth}${option.group.name}',
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedGroupUuid = value);
              }
            },
            decoration: const InputDecoration(labelText: 'New parent'),
          ),
          const SizedBox(height: Spacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: Spacing.sm),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_selectedGroupUuid),
                child: const Text('Move Group'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlatGroupNode {
  final VaultGroup group;
  final int depth;

  _FlatGroupNode({required this.group, required this.depth});
}

class _GroupOption {
  final VaultGroup group;
  final int depth;

  const _GroupOption({
    required this.group,
    required this.depth,
  });
}

class _GroupTile extends StatelessWidget {
  final VaultGroup group;
  final int depth;
  final bool isSelected;
  final bool isExpanded;
  final bool hasChildren;
  final bool isMutating;
  final VoidCallback onTap;
  final VoidCallback onToggleExpand;
  final Future<void> Function(_GroupAction action) onActionSelected;

  const _GroupTile({
    required this.group,
    required this.depth,
    required this.isSelected,
    required this.isExpanded,
    required this.hasChildren,
    required this.isMutating,
    required this.onTap,
    required this.onToggleExpand,
    required this.onActionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final indent = Spacing.lg * depth;

    return Material(
      color: isSelected
          ? colorScheme.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: EdgeInsets.only(
            left: Spacing.md + indent,
            right: Spacing.xs,
            top: Spacing.sm,
            bottom: Spacing.sm,
          ),
          child: Row(
            children: [
              if (hasChildren)
                GestureDetector(
                  onTap: onToggleExpand,
                  child: Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 20,
                    color: colorScheme.onSurface,
                  ),
                )
              else
                const SizedBox(width: 20),
              const SizedBox(width: Spacing.xs),
              Icon(
                Icons.folder,
                size: 20,
                color: isSelected ? colorScheme.primary : colorScheme.onSurface,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  group.name,
                  style: textTheme.titleMedium?.copyWith(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isMutating)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                PopupMenuButton<_GroupAction>(
                  tooltip: 'Group actions',
                  onSelected: (action) {
                    unawaited(onActionSelected(action));
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<_GroupAction>(
                      value: _GroupAction.create,
                      child: Text('New Subgroup'),
                    ),
                    PopupMenuItem<_GroupAction>(
                      value: _GroupAction.rename,
                      child: Text('Rename Group'),
                    ),
                    PopupMenuItem<_GroupAction>(
                      value: _GroupAction.move,
                      child: Text('Move Group'),
                    ),
                    PopupMenuItem<_GroupAction>(
                      value: _GroupAction.delete,
                      child: Text('Delete Group'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _GroupAction { create, rename, move, delete }

List<_GroupOption> _flattenGroups(
  List<VaultGroup> groups, {
  Set<String> forbiddenUuids = const <String>{},
  int depth = 0,
}) {
  final result = <_GroupOption>[];
  for (final group in groups) {
    if (!forbiddenUuids.contains(group.uuid)) {
      result.add(_GroupOption(group: group, depth: depth));
    }
    result.addAll(
      _flattenGroups(
        group.children,
        forbiddenUuids: forbiddenUuids,
        depth: depth + 1,
      ),
    );
  }
  return result;
}
