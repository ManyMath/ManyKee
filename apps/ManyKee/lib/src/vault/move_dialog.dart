import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:keepass_ui/keepass_ui.dart' show VaultGroup;
import 'package:manyui/manyui.dart';

/// Flattened (uuid, indented display name) pair for the move-target picker.
class _GroupOption {
  const _GroupOption(this.uuid, this.label);
  final String uuid;
  final String label;
}

List<_GroupOption> _flattenGroups(
  List<VaultGroup> groups, {
  String? excludeUuid,
  int depth = 0,
}) {
  final options = <_GroupOption>[];
  for (final group in groups) {
    if (group.uuid == excludeUuid) {
      // Skip this group and its whole subtree: it can't become its own
      // descendant.
      continue;
    }
    options.add(_GroupOption(group.uuid, '${'  ' * depth}${group.name}'));
    options.addAll(_flattenGroups(
      group.children,
      excludeUuid: excludeUuid,
      depth: depth + 1,
    ));
  }
  return options;
}

/// Shows a group picker for moving an entry or group. Returns the chosen
/// target group's uuid, or null if the user cancels.
///
/// [excludeUuid] omits a group (and is not descended into further by the
/// caller), used when moving a group itself, so it can't be moved into its
/// own subtree.
Future<String?> showMoveDialog(
  BuildContext context, {
  required String title,
  required List<VaultGroup> groups,
  String? excludeUuid,
  String? initialGroupUuid,
}) {
  final options = _flattenGroups(groups, excludeUuid: excludeUuid);
  if (options.isEmpty) {
    return Future<String?>.value(null);
  }
  return showMDialog<String>(
    context,
    builder: (BuildContext ctx) => _MoveDialogContent(
      title: title,
      options: options,
      initialGroupUuid: initialGroupUuid,
    ),
  );
}

class _MoveDialogContent extends HookWidget {
  const _MoveDialogContent({
    required this.title,
    required this.options,
    required this.initialGroupUuid,
  });

  final String title;
  final List<_GroupOption> options;
  final String? initialGroupUuid;

  @override
  Widget build(BuildContext context) {
    final theme = MTheme.of(context);
    final validInitial =
        options.any((o) => o.uuid == initialGroupUuid) ? initialGroupUuid : null;
    final selected = useState<String?>(validInitial ?? options.first.uuid);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.typography.headlineSmall),
          const SizedBox(height: 16),
          MSelect<String>(
            items: [
              for (final option in options)
                MSelectItem<String>(value: option.uuid, label: option.label),
            ],
            initialValue: selected.value,
            onChanged: (v) => selected.value = v,
            semanticLabel: 'Target group',
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              MButton(
                variant: MButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              MButton(
                onPressed: selected.value == null
                    ? null
                    : () => Navigator.of(context).pop(selected.value),
                child: const Text('Move'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
