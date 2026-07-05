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
      rows.add(MTreeListTile(
        title: Text(group.name, overflow: TextOverflow.ellipsis),
        depth: depth,
        selected: group.uuid == selectedUuid,
        expanded: !collapsed.value.contains(group.uuid),
        semanticLabel: group.name,
        onTap: () => onSelect(group),
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
