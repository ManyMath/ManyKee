import 'package:flutter/widgets.dart';
import 'package:manyui/manyui.dart';

enum UnsavedChangesAction { save, discard }

/// Asks how to proceed when an operation would drop unsaved vault changes.
Future<UnsavedChangesAction?> showUnsavedChangesDialog(BuildContext context) {
  return showMDialog<UnsavedChangesAction>(
    context,
    semanticLabel: 'Unsaved changes',
    builder: (BuildContext ctx) {
      return MDialogContent(
        title: 'Unsaved changes',
        description:
            'Save your changes before locking, or discard them and return '
            'to the lock screen.',
        actions: <Widget>[
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
            onPressed: () => Navigator.of(ctx).pop(UnsavedChangesAction.save),
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}
