import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:manyui/manyui.dart';

/// Shows a single-field name prompt for creating or renaming a group.
/// Returns the trimmed name, or null if the user cancels.
Future<String?> showGroupNameDialog(
  BuildContext context, {
  required String title,
  required String submitLabel,
  String initialValue = '',
}) {
  return showMDialog<String>(
    context,
    builder: (BuildContext ctx) => _GroupNameDialogContent(
      title: title,
      submitLabel: submitLabel,
      initialValue: initialValue,
    ),
  );
}

class _GroupNameDialogContent extends HookWidget {
  const _GroupNameDialogContent({
    required this.title,
    required this.submitLabel,
    required this.initialValue,
  });

  final String title;
  final String submitLabel;
  final String initialValue;

  @override
  Widget build(BuildContext context) {
    final name = useState(initialValue);
    final nameFocus = useFocusNode();

    void submit() {
      final trimmed = name.value.trim();
      if (trimmed.isEmpty) return;
      Navigator.of(context).pop(trimmed);
    }

    return MDialogContent(
      title: title,
      maxWidth: 360,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MField(
            label: 'Name',
            focusNode: nameFocus,
            spacing: 4,
            child: MTextField(
              focusNode: nameFocus,
              initialValue: initialValue,
              placeholder: 'Group name',
              semanticLabel: 'Group name',
              autofocus: true,
              onChanged: (v) => name.value = v,
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
          onPressed: name.value.trim().isEmpty ? null : submit,
          child: Text(submitLabel),
        ),
      ],
    );
  }
}
