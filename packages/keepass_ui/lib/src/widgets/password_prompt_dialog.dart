import 'package:flutter/material.dart';

/// Prompts the user to re-enter the master password, returning it on
/// confirm or `null` if the dialog is dismissed/cancelled.
///
/// Used instead of retaining the master password in memory for the whole
/// unlocked session (see ROADMAP: retained-password secret exposure item).
Future<String?> showPasswordPromptDialog(
  BuildContext context, {
  String title = 'Confirm master password',
  String message = 'Re-enter your master password to continue.',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PasswordPromptDialog(title: title, message: message),
  );
}

class _PasswordPromptDialog extends StatefulWidget {
  final String title;
  final String message;

  const _PasswordPromptDialog({required this.title, required this.message});

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              obscureText: _obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Master password',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (value) =>
                  (value == null || value.isEmpty) ? 'Password is required' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
