import 'package:flutter/widgets.dart';
import 'package:keepass_ui/keepass_ui.dart' show VaultEntry;
import 'package:manyui/manyui.dart';

/// Entries of the selected group: title plus muted username.
class EntryList extends StatelessWidget {
  const EntryList({
    required this.entries,
    required this.selectedUuid,
    required this.onSelect,
    super.key,
  });

  final List<VaultEntry> entries;
  final String? selectedUuid;
  final ValueChanged<VaultEntry> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = MTheme.of(context);

    if (entries.isEmpty) {
      return Center(
        child: Text(
          'No entries in this group',
          style: theme.typography.bodySmall
              .copyWith(color: theme.colors.mutedForeground),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final selected = entry.uuid == selectedUuid;
        final title = entry.title.isEmpty ? '(untitled)' : entry.title;

        return MListTile(
          title: Text(title, overflow: TextOverflow.ellipsis),
          subtitle: entry.username.isNotEmpty
              ? Text(entry.username, overflow: TextOverflow.ellipsis)
              : null,
          selected: selected,
          onTap: () => onSelect(entry),
          semanticLabel: title,
        );
      },
    );
  }
}
