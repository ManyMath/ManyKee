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
    super.key,
  });

  final List<VaultGroup> groups;
  final String? selectedUuid;
  final ValueChanged<VaultGroup> onSelect;

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
        onSelect: () => onSelect(group),
        onToggle: group.children.isEmpty ? null : () => toggle(group.uuid),
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

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: rows,
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.depth,
    required this.selected,
    required this.expanded,
    required this.onSelect,
    required this.onToggle,
  });

  final VaultGroup group;
  final int depth;
  final bool selected;
  final bool expanded;
  final VoidCallback onSelect;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = MTheme.of(context);
    final foreground =
        selected ? theme.colors.accentForeground : theme.colors.foreground;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSelect,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: EdgeInsets.only(left: 8.0 + depth * 16, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: selected ? theme.colors.accent : null,
          borderRadius: BorderRadius.circular(theme.radius),
        ),
        child: Row(
          children: <Widget>[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: SizedBox(
                width: 20,
                child: onToggle == null
                    ? null
                    : Center(
                        child: MIcon(
                          expanded ? MIconData.chevronDown : MIconData.chevronRight,
                          size: 14,
                          color: theme.colors.mutedForeground,
                        ),
                      ),
              ),
            ),
            Expanded(
              child: Text(
                group.name,
                style: theme.typography.body.copyWith(color: foreground),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
