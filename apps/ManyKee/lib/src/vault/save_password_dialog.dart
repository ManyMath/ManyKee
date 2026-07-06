import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:manyui/manyui.dart';

/// Prompts for the password to use when writing the current database.
Future<String?> showSavePasswordDialog(
  BuildContext context, {
  String title = 'Save changes',
  String message = 'Enter the master password to write this database.',
}) {
  return showMDialog<String>(
    context,
    semanticLabel: title,
    builder: (BuildContext ctx) =>
        _SavePasswordDialogContent(title: title, message: message),
  );
}

class _SavePasswordDialogContent extends HookWidget {
  const _SavePasswordDialogContent({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = MTheme.of(context);
    final password = useState('');

    void submit() {
      if (password.value.isEmpty) return;
      Navigator.of(context).pop(password.value);
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: theme.typography.headlineSmall),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.typography.bodySmall.copyWith(
              color: theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(height: 16),
          const MLabel('Master password'),
          const SizedBox(height: 4),
          MTextField(
            obscureText: true,
            placeholder: 'Password',
            semanticLabel: 'Master password for saving',
            autofocus: true,
            onChanged: (value) => password.value = value,
            onSubmitted: (_) => submit(),
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
                onPressed: password.value.isEmpty ? null : submit,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
