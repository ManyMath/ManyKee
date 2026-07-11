import 'package:flutter/widgets.dart';
import 'package:manyui/manyui.dart';

import '../state/vault_sessions.dart';

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
              trailing: session.isActive
                  ? Text(
                      'Current',
                      style: theme.typography.caption.copyWith(
                        color: theme.colors.mutedForeground,
                      ),
                    )
                  : null,
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
}
