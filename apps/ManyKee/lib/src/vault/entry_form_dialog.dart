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
    required this.includedFields,
    required this.protectedFields,
  });

  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final Set<String> includedFields;
  final Set<String> protectedFields;

  Map<String, String?> toFields() => <String, String?>{
    if (includedFields.contains('Title')) 'Title': title,
    if (includedFields.contains('UserName')) 'UserName': username,
    if (includedFields.contains('Password')) 'Password': password,
    if (includedFields.contains('URL')) 'URL': url,
    if (includedFields.contains('Notes')) 'Notes': notes,
  };
}

typedef EntryFieldLoader = Future<String?> Function(String fieldName);

/// Shows a create/edit form for one entry's standard fields.
///
/// Returns null if the user cancels, otherwise an [EntryFormResult] ready to
/// pass to `VaultState.updateEntry`.
Future<EntryFormResult?> showEntryFormDialog(
  BuildContext context, {
  required String title,
  required String submitLabel,
  Map<String, dynamic> initialFields = const <String, dynamic>{},
  EntryFieldLoader? loadProtectedField,
}) {
  return showMDialog<EntryFormResult>(
    context,
    builder: (BuildContext ctx) => _EntryFormDialogContent(
      title: title,
      submitLabel: submitLabel,
      initialFields: initialFields,
      loadProtectedField: loadProtectedField,
    ),
  );
}

class _EntryFormDialogContent extends HookWidget {
  const _EntryFormDialogContent({
    required this.title,
    required this.submitLabel,
    required this.initialFields,
    required this.loadProtectedField,
  });

  final String title;
  final String submitLabel;
  final Map<String, dynamic> initialFields;
  final EntryFieldLoader? loadProtectedField;

  @override
  Widget build(BuildContext context) {
    final rawProtected = initialFields['protected'];
    final initiallyProtected = rawProtected is Map
        ? rawProtected.entries
              .where((entry) => entry.value == true)
              .map((entry) => entry.key.toString())
              .toSet()
        : <String>{};
    final editing = loadProtectedField != null;
    String initialValue(String fieldName) =>
        editing && initiallyProtected.contains(fieldName)
        ? ''
        : (initialFields[fieldName] as String?) ?? '';

    final titleValue = initialValue('Title');
    final usernameValue = initialValue('UserName');
    final passwordValue = initialValue('Password');
    final urlValue = initialValue('URL');
    final notesValue = initialValue('Notes');

    final titleField = useState(titleValue);
    final usernameField = useState(usernameValue);
    final passwordField = useState(passwordValue);
    final urlField = useState(urlValue);
    final notesField = useState(notesValue);
    final revealPassword = useState(false);
    final titleTouched = useState(false);
    final usernameTouched = useState(false);
    final passwordTouched = useState(false);
    final urlTouched = useState(false);
    final notesTouched = useState(false);
    final passwordLoading = useState(false);
    final passwordController = useMemoized(
      () => MController<String>(passwordValue),
    );
    final titleFocus = useFocusNode();
    final usernameFocus = useFocusNode();
    final passwordFocus = useFocusNode();
    final urlFocus = useFocusNode();
    final notesFocus = useFocusNode();

    useEffect(() => passwordController.dispose, const <Object?>[]);

    bool wasProtected(String fieldName) =>
        editing && initiallyProtected.contains(fieldName);

    final titleWasProtected = wasProtected('Title');
    final usernameWasProtected = wasProtected('UserName');
    final passwordWasProtected = wasProtected('Password');
    final urlWasProtected = wasProtected('URL');
    final notesWasProtected = wasProtected('Notes');

    bool includeField(bool scrubbed, bool touched) => !scrubbed || touched;

    String? unchangedDescription(bool scrubbed, bool touched) =>
        scrubbed && !touched
        ? 'Leave this field unchanged to keep the saved value.'
        : null;

    Future<void> toggleReveal() async {
      if (revealPassword.value) {
        revealPassword.value = false;
        return;
      }
      if (passwordWasProtected &&
          passwordController.value.isEmpty &&
          !passwordTouched.value) {
        passwordLoading.value = true;
        try {
          final loaded = await loadProtectedField!('Password');
          if (context.mounted && loaded != null) {
            passwordController.value = loaded;
            passwordField.value = loaded;
          }
        } catch (_) {
          if (context.mounted) {
            showMToast(
              context,
              builder: (_) => const Text('Password could not be revealed.'),
              duration: const Duration(seconds: 2),
            );
          }
          return;
        } finally {
          if (context.mounted) passwordLoading.value = false;
        }
      }
      if (context.mounted) revealPassword.value = true;
    }

    void submit() {
      final includedFields = <String>{
        if (includeField(titleWasProtected, titleTouched.value)) 'Title',
        if (includeField(usernameWasProtected, usernameTouched.value))
          'UserName',
        if (includeField(passwordWasProtected, passwordTouched.value))
          'Password',
        if (includeField(urlWasProtected, urlTouched.value)) 'URL',
        if (includeField(notesWasProtected, notesTouched.value)) 'Notes',
      };
      if (includedFields.contains('Title') && titleField.value.trim().isEmpty) {
        return;
      }
      Navigator.of(context).pop(
        EntryFormResult(
          title: titleField.value.trim(),
          username: usernameField.value,
          password: passwordField.value,
          url: urlField.value,
          notes: notesField.value,
          includedFields: includedFields,
          protectedFields: <String>{
            for (final fieldName in includedFields)
              if (initiallyProtected.contains(fieldName) ||
                  (fieldName == 'Password' && loadProtectedField == null))
                fieldName,
          },
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
            description: unchangedDescription(
              titleWasProtected,
              titleTouched.value,
            ),
            focusNode: titleFocus,
            spacing: 4,
            child: MTextField(
              focusNode: titleFocus,
              initialValue: titleValue,
              placeholder: 'Title',
              semanticLabel: 'Title',
              autofocus: true,
              onChanged: (v) {
                titleField.value = v;
                titleTouched.value = true;
              },
            ),
          ),
          const SizedBox(height: 12),
          MField(
            label: 'Username',
            description: unchangedDescription(
              usernameWasProtected,
              usernameTouched.value,
            ),
            focusNode: usernameFocus,
            spacing: 4,
            child: MTextField(
              focusNode: usernameFocus,
              initialValue: usernameValue,
              placeholder: 'Username',
              semanticLabel: 'Username',
              onChanged: (v) {
                usernameField.value = v;
                usernameTouched.value = true;
              },
            ),
          ),
          const SizedBox(height: 12),
          MField(
            label: 'Password',
            description: unchangedDescription(
              passwordWasProtected,
              passwordTouched.value,
            ),
            focusNode: passwordFocus,
            spacing: 4,
            child: MTextField(
              controller: passwordController,
              focusNode: passwordFocus,
              placeholder: 'Password',
              semanticLabel: 'Password',
              obscureText: !revealPassword.value,
              enabled: !passwordLoading.value,
              onChanged: (v) {
                passwordField.value = v;
                passwordTouched.value = true;
              },
              trailing: MIconButton(
                icon: revealPassword.value ? MIconData.eyeOff : MIconData.eye,
                label: passwordLoading.value
                    ? 'Loading password'
                    : revealPassword.value
                    ? 'Hide password'
                    : 'Reveal password',
                size: MButtonSize.sm,
                onPressed: passwordLoading.value ? null : toggleReveal,
              ),
            ),
          ),
          const SizedBox(height: 12),
          MField(
            label: 'URL',
            description: unchangedDescription(
              urlWasProtected,
              urlTouched.value,
            ),
            focusNode: urlFocus,
            spacing: 4,
            child: MTextField(
              focusNode: urlFocus,
              initialValue: urlValue,
              placeholder: 'https://example.com',
              semanticLabel: 'URL',
              onChanged: (v) {
                urlField.value = v;
                urlTouched.value = true;
              },
            ),
          ),
          const SizedBox(height: 12),
          MField(
            label: 'Notes',
            description: unchangedDescription(
              notesWasProtected,
              notesTouched.value,
            ),
            focusNode: notesFocus,
            spacing: 4,
            child: MTextField(
              focusNode: notesFocus,
              initialValue: notesValue,
              placeholder: 'Notes',
              semanticLabel: 'Notes',
              maxLines: 4,
              minLines: 2,
              onChanged: (v) {
                notesField.value = v;
                notesTouched.value = true;
              },
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
          onPressed:
              titleField.value.trim().isEmpty &&
                  (!titleWasProtected || titleTouched.value)
              ? null
              : submit,
          child: Text(submitLabel),
        ),
      ],
    );
  }
}
