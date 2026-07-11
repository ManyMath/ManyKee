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
    final password = useState('');
    final passwordFocus = useFocusNode();

    void submit() {
      if (password.value.isEmpty) return;
      Navigator.of(context).pop(password.value);
    }

    return MDialogContent(
      title: title,
      description: message,
      maxWidth: 380,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MField(
            label: 'Master password',
            focusNode: passwordFocus,
            spacing: 4,
            child: MTextField(
              focusNode: passwordFocus,
              obscureText: true,
              placeholder: 'Password',
              semanticLabel: 'Master password for saving',
              autofocus: true,
              onChanged: (value) => password.value = value,
              onSubmitted: (_) => submit(),
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
          onPressed: password.value.isEmpty ? null : submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
