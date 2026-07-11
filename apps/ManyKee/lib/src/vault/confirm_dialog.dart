import 'package:flutter/widgets.dart';
import 'package:manyui/manyui.dart';

/// Shows a destructive-action confirmation. Returns true if confirmed.
Future<bool> showDeleteConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String submitLabel = 'Delete',
}) async {
  return showMConfirmDialog(
    context,
    title: title,
    message: message,
    confirmLabel: submitLabel,
    confirmVariant: MButtonVariant.destructive,
    maxWidth: 360,
  );
}
