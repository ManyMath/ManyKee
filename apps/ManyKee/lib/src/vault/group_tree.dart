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
    this.rootSelected = false,
    this.onSelectRoot,
    this.onAddGroup,
    this.onRenameGroup,
    this.onMoveGroup,
    this.onDeleteGroup,
    super.key,
  });

  final List<VaultGroup> groups;
  final String? selectedUuid;
  final ValueChanged<VaultGroup> onSelect;
  final bool rootSelected;
  final VoidCallback? onSelectRoot;

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
      rows.add(
        _GroupRow(
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
        ),
      );
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
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Groups',
                  style: MTheme.of(context).typography.title,
                ),
              ),
              if (onAddGroup != null)
                MIconButton(
                  icon: MIconData.plus,
                  label: 'New group',
                  size: MButtonSize.sm,
                  onPressed: () => onAddGroup!(null),
                ),
            ],
          ),
        ),
        const MDivider(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: <Widget>[
              if (onSelectRoot != null)
                MListTile(
                  leading: const MIcon(MIconData.home, size: 16),
                  title: const Text('Vault root'),
                  selected: rootSelected,
                  semanticLabel: 'Vault root',
                  onTap: onSelectRoot,
                ),
              ...rows,
            ],
          ),
        ),
      ],
    );
  }
}

class _GroupRow extends HookWidget {
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
          const MIcon(MIconData.folder, size: 15),
          const SizedBox(width: 7),
          Expanded(child: Text(group.name, overflow: TextOverflow.ellipsis)),
          if (onAddSubgroup != null)
            MIconButton(
              icon: MIconData.plus,
              label: 'New subgroup in ${group.name}',
              size: MButtonSize.xs,
              onPressed: onAddSubgroup,
            ),
          if (onRename != null || onMove != null || onDelete != null)
            _GroupOverflowButton(
              groupName: group.name,
              onRename: onRename,
              onMove: onMove,
              onDelete: onDelete,
            ),
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

class _GroupOverflowButton extends HookWidget {
  const _GroupOverflowButton({
    required this.groupName,
    required this.onRename,
    required this.onMove,
    required this.onDelete,
  });

  final String groupName;
  final VoidCallback? onRename;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final controller = useMemoized(MPopoverController.new);
    useEffect(() => controller.dispose, const <Object?>[]);

    return MPopover(
      controller: controller,
      semanticLabel: 'Actions for $groupName',
      popoverBuilder: (context, close) => SizedBox(
        width: 190,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (onRename != null)
              _MenuAction(
                icon: MIconData.edit,
                label: 'Rename group',
                onPressed: () {
                  close();
                  onRename!();
                },
              ),
            if (onMove != null)
              _MenuAction(
                icon: MIconData.arrowRight,
                label: 'Move group',
                onPressed: () {
                  close();
                  onMove!();
                },
              ),
            if (onDelete != null)
              _MenuAction(
                icon: MIconData.trash,
                label: 'Delete group',
                destructive: true,
                onPressed: () {
                  close();
                  onDelete!();
                },
              ),
          ],
        ),
      ),
      child: MIconButton(
        icon: MIconData.moreHorizontal,
        label: 'Actions for $groupName',
        size: MButtonSize.xs,
        onPressed: controller.toggle,
      ),
    );
  }
}

class _MenuAction extends StatelessWidget {
  const _MenuAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final MIconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return MButton(
      variant: destructive ? MButtonVariant.destructive : MButtonVariant.ghost,
      onPressed: onPressed,
      child: Row(
        children: <Widget>[
          MIcon(icon, size: 15),
          const SizedBox(width: 8),
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
