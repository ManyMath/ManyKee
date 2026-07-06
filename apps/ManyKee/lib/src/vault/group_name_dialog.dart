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
    final theme = MTheme.of(context);
    final name = useState(initialValue);

    void submit() {
      final trimmed = name.value.trim();
      if (trimmed.isEmpty) return;
      Navigator.of(context).pop(trimmed);
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.typography.headlineSmall),
          const SizedBox(height: 16),
          const MLabel('Name'),
          const SizedBox(height: 4),
          MTextField(
            initialValue: initialValue,
            placeholder: 'Group name',
            semanticLabel: 'Group name',
            autofocus: true,
            onChanged: (v) => name.value = v,
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
                onPressed: name.value.trim().isEmpty ? null : submit,
                child: Text(submitLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
