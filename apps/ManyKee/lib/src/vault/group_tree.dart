import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:keepass_ui/keepass_ui.dart' show VaultGroup;
import 'package:manyui/manyui.dart';

/// Indented, expandable group tree built from [VaultGroup]s.
class GroupTree extends HookWidget {
  const GroupTree({
    required this.groups,
    required this.selectedUuid,
    required this.onSelect,
    this.onAddGroup,
    this.onRenameGroup,
    this.onMoveGroup,
    this.onDeleteGroup,
    super.key,
  });

  final List<VaultGroup> groups;
  final String? selectedUuid;
  final ValueChanged<VaultGroup> onSelect;

  /// Called with the group under which a new child group should be created,
  /// or null to add a top-level group.
  final ValueChanged<VaultGroup?>? onAddGroup;
  final ValueChanged<VaultGroup>? onRenameGroup;
  final ValueChanged<VaultGroup>? onMoveGroup;
  final ValueChanged<VaultGroup>? onDeleteGroup;

  @override
  Widget build(BuildContext context) {
    final collapsed = useState(const <String>{});

    void toggle(String uuid) {
      final next = Set<String>.of(collapsed.value);
      if (!next.remove(uuid)) {
        next.add(uuid);
      }
      collapsed.value = next;
    }

    final rows = <Widget>[];
    void addGroup(VaultGroup group, int depth) {
      rows.add(_GroupRow(
        group: group,
        depth: depth,
        selected: group.uuid == selectedUuid,
        expanded: !collapsed.value.contains(group.uuid),
        onTap: () => onSelect(group),
        onToggle: group.children.isEmpty ? null : () => toggle(group.uuid),
        onAddSubgroup: onAddGroup == null ? null : () => onAddGroup!(group),
        onRename: onRenameGroup == null ? null : () => onRenameGroup!(group),
        onMove: onMoveGroup == null ? null : () => onMoveGroup!(group),
        onDelete: onDeleteGroup == null ? null : () => onDeleteGroup!(group),
      ));
      if (!collapsed.value.contains(group.uuid)) {
        for (final child in group.children) {
          addGroup(child, depth + 1);
        }
      }
    }

    for (final group in groups) {
      addGroup(group, 0);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: rows,
          ),
        ),
        if (onAddGroup != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: MButton(
              variant: MButtonVariant.outline,
              onPressed: () => onAddGroup!(null),
              child: const Text('New group'),
            ),
          ),
      ],
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.depth,
    required this.selected,
    required this.expanded,
    required this.onTap,
    required this.onToggle,
    this.onAddSubgroup,
    this.onRename,
    this.onMove,
    this.onDelete,
  });

  final VaultGroup group;
  final int depth;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback? onToggle;
  final VoidCallback? onAddSubgroup;
  final VoidCallback? onRename;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;

  bool get _hasActions =>
      onAddSubgroup != null ||
      onRename != null ||
      onMove != null ||
      onDelete != null;

  @override
  Widget build(BuildContext context) {
    if (!_hasActions) {
      return MTreeListTile(
        title: Text(group.name, overflow: TextOverflow.ellipsis),
        depth: depth,
        selected: selected,
        expanded: expanded,
        semanticLabel: group.name,
        onTap: onTap,
        onToggle: onToggle,
      );
    }

    return MTreeListTile(
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(group.name, overflow: TextOverflow.ellipsis),
          ),
          if (onAddSubgroup != null)
            _ActionButton(label: '+', tooltip: 'New subgroup', onPressed: onAddSubgroup),
          if (onRename != null)
            _ActionButton(label: 'Rename', onPressed: onRename),
          if (onMove != null)
            _ActionButton(label: 'Move', onPressed: onMove),
          if (onDelete != null)
            _ActionButton(label: 'Delete', onPressed: onDelete),
        ],
      ),
      depth: depth,
      selected: selected,
      expanded: expanded,
      semanticLabel: group.name,
      onTap: onTap,
      onToggle: onToggle,
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, this.tooltip, this.onPressed});

  final String label;
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: MButton(
        variant: MButtonVariant.ghost,
        size: MButtonSize.xs,
        semanticLabel: tooltip ?? label,
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}
