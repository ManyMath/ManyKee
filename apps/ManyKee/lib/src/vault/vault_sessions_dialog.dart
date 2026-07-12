import 'package:flutter/widgets.dart';
import 'package:manyui/manyui.dart';

import '../state/vault_sessions.dart';
import 'save_password_dialog.dart';
import 'unsaved_changes_dialog.dart';

Future<void> showVaultSessionsDialog(
  BuildContext context,
  VaultSessionsController controller,
) {
  return showMDialog<void>(
    context,
    semanticLabel: 'Databases',
    builder: (BuildContext ctx) => _VaultSessionsDialog(controller: controller),
  );
}

class _VaultSessionsDialog extends StatelessWidget {
  const _VaultSessionsDialog({required this.controller});

  final VaultSessionsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = MTheme.of(context);
    final sessions = controller.sessions;
    return MDialogContent(
      title: 'Databases',
      maxWidth: 460,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final session in sessions)
            MListTile(
              selected: session.isActive,
              title: Text(session.label, overflow: TextOverflow.ellipsis),
              subtitle: session.subtitle == null
                  ? null
                  : Text(session.subtitle!, overflow: TextOverflow.ellipsis),
              semanticLabel: session.label,
              onTap: session.isActive
                  ? null
                  : () {
                      controller.switchToSession(session.id);
                      Navigator.of(context).pop();
                    },
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (session.isActive)
                    Text(
                      'Current',
                      style: theme.typography.caption.copyWith(
                        color: theme.colors.mutedForeground,
                      ),
                    ),
                  MIconButton(
                    icon: MIconData.close,
                    label: 'Close ${session.label}',
                    onPressed: () => _closeSession(context, session),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: <Widget>[
        MButton(
          variant: MButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        MButton(
          onPressed: () {
            controller.openNewSession();
            Navigator.of(context).pop();
          },
          child: const Text('Open another database'),
        ),
      ],
    );
  }

  Future<void> _closeSession(
    BuildContext context,
    VaultSessionSummary session,
  ) async {
    var discardDirty = false;
    if (session.isDirty) {
      controller.switchToSession(session.id);
      final action = await showUnsavedChangesDialog(context);
      if (action == null || !context.mounted) return;
      switch (action) {
        case UnsavedChangesAction.save:
          final password = await showSavePasswordDialog(context);
          if (password == null || !context.mounted) return;
          try {
            await controller.saveDatabase(password: password);
          } catch (error) {
            if (context.mounted) {
              showMToast(
                context,
                builder: (_) => Text('Could not save database: $error'),
              );
            }
            return;
          }
          break;
        case UnsavedChangesAction.discard:
          discardDirty = true;
          break;
      }
    }
    await controller.closeSession(session.id, discardDirty: discardDirty);
    if (context.mounted) Navigator.of(context).pop();
  }
}
