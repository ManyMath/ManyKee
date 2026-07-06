import 'package:flutter/widgets.dart';
import 'package:manyui/manyui.dart';

enum UnsavedChangesAction { save, discard }

/// Asks how to proceed when an operation would drop unsaved vault changes.
Future<UnsavedChangesAction?> showUnsavedChangesDialog(BuildContext context) {
  return showMDialog<UnsavedChangesAction>(
    context,
    semanticLabel: 'Unsaved changes',
    builder: (BuildContext ctx) {
      final theme = MTheme.of(ctx);
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Unsaved changes', style: theme.typography.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Save your changes before locking, or discard them and return '
              'to the lock screen.',
              style: theme.typography.bodySmall.copyWith(
                color: theme.colors.mutedForeground,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                MButton(
                  variant: MButtonVariant.ghost,
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                MButton(
                  variant: MButtonVariant.destructive,
                  onPressed: () =>
                      Navigator.of(ctx).pop(UnsavedChangesAction.discard),
                  child: const Text('Discard'),
                ),
                MButton(
                  onPressed: () =>
                      Navigator.of(ctx).pop(UnsavedChangesAction.save),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
