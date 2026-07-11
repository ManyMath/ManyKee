import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:manyui/manyui.dart';

/// Fields collected by [showEntryFormDialog], ready for `VaultState.updateEntry`.
class EntryFormResult {
  const EntryFormResult({
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.notes,
  });

  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;

  Map<String, String?> toFields() => <String, String?>{
    'Title': title,
    'UserName': username,
    'Password': password,
    'URL': url,
    'Notes': notes,
  };

  Set<String> get protectedFields => const <String>{'Password'};
}

/// Shows a create/edit form for one entry's standard fields.
///
/// Returns null if the user cancels, otherwise an [EntryFormResult] ready to
/// pass to `VaultState.updateEntry`.
Future<EntryFormResult?> showEntryFormDialog(
  BuildContext context, {
  required String title,
  required String submitLabel,
  Map<String, dynamic> initialFields = const <String, dynamic>{},
}) {
  return showMDialog<EntryFormResult>(
    context,
    builder: (BuildContext ctx) => _EntryFormDialogContent(
      title: title,
      submitLabel: submitLabel,
      initialFields: initialFields,
    ),
  );
}

class _EntryFormDialogContent extends HookWidget {
  const _EntryFormDialogContent({
    required this.title,
    required this.submitLabel,
    required this.initialFields,
  });

  final String title;
  final String submitLabel;
  final Map<String, dynamic> initialFields;

  @override
  Widget build(BuildContext context) {
    final titleValue = (initialFields['Title'] as String?) ?? '';
    final usernameValue = (initialFields['UserName'] as String?) ?? '';
    final passwordValue = (initialFields['Password'] as String?) ?? '';
    final urlValue = (initialFields['URL'] as String?) ?? '';
    final notesValue = (initialFields['Notes'] as String?) ?? '';

    final titleField = useState(titleValue);
    final usernameField = useState(usernameValue);
    final passwordField = useState(passwordValue);
    final urlField = useState(urlValue);
    final notesField = useState(notesValue);
    final revealPassword = useState(false);
    final titleFocus = useFocusNode();
    final usernameFocus = useFocusNode();
    final passwordFocus = useFocusNode();
    final urlFocus = useFocusNode();
    final notesFocus = useFocusNode();

    void submit() {
      if (titleField.value.trim().isEmpty) return;
      Navigator.of(context).pop(
        EntryFormResult(
          title: titleField.value.trim(),
          username: usernameField.value,
          password: passwordField.value,
          url: urlField.value,
          notes: notesField.value,
        ),
      );
    }

    return MDialogContent(
      title: title,
      maxWidth: 420,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MField(
            label: 'Title',
            focusNode: titleFocus,
            spacing: 4,
            child: MTextField(
              focusNode: titleFocus,
              initialValue: titleValue,
              placeholder: 'Title',
              semanticLabel: 'Title',
              autofocus: true,
              onChanged: (v) => titleField.value = v,
              onSubmitted: (_) => submit(),
            ),
          ),
          const SizedBox(height: 12),
          MField(
            label: 'Username',
            focusNode: usernameFocus,
            spacing: 4,
            child: MTextField(
              focusNode: usernameFocus,
              initialValue: usernameValue,
              placeholder: 'Username',
              semanticLabel: 'Username',
              onChanged: (v) => usernameField.value = v,
              onSubmitted: (_) => submit(),
            ),
          ),
          const SizedBox(height: 12),
          MField(
            label: 'Password',
            focusNode: passwordFocus,
            spacing: 4,
            child: MTextField(
              focusNode: passwordFocus,
              initialValue: passwordValue,
              placeholder: 'Password',
              semanticLabel: 'Password',
              obscureText: !revealPassword.value,
              onChanged: (v) => passwordField.value = v,
              onSubmitted: (_) => submit(),
              trailing: MButton(
                variant: MButtonVariant.ghost,
                size: MButtonSize.sm,
                onPressed: () => revealPassword.value = !revealPassword.value,
                child: Text(revealPassword.value ? 'Hide' : 'Reveal'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          MField(
            label: 'URL',
            focusNode: urlFocus,
            spacing: 4,
            child: MTextField(
              focusNode: urlFocus,
              initialValue: urlValue,
              placeholder: 'https://example.com',
              semanticLabel: 'URL',
              onChanged: (v) => urlField.value = v,
              onSubmitted: (_) => submit(),
            ),
          ),
          const SizedBox(height: 12),
          MField(
            label: 'Notes',
            focusNode: notesFocus,
            spacing: 4,
            child: MTextField(
              focusNode: notesFocus,
              initialValue: notesValue,
              placeholder: 'Notes',
              semanticLabel: 'Notes',
              maxLines: 4,
              minLines: 2,
              onChanged: (v) => notesField.value = v,
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
          onPressed: titleField.value.trim().isEmpty ? null : submit,
          child: Text(submitLabel),
        ),
      ],
    );
  }
}
