import 'package:flutter/widgets.dart';
import 'package:manyui/manyui.dart';

/// Shows a destructive-action confirmation. Returns true if confirmed.
Future<bool> showDeleteConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String submitLabel = 'Delete',
}) async {
  final confirmed = await showMDialog<bool>(
    context,
    builder: (BuildContext ctx) {
      final theme = MTheme.of(ctx);
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: theme.typography.headlineSmall),
            const SizedBox(height: 8),
            Text(message, style: theme.typography.body),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                MButton(
                  variant: MButtonVariant.ghost,
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                MButton(
                  variant: MButtonVariant.destructive,
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(submitLabel),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  return confirmed ?? false;
}
