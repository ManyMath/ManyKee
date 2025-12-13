import 'dart:async';

import 'package:flutter/material.dart';

import '../state/clipboard_manager.dart';
import 'copy_button.dart';

class PasswordField extends StatefulWidget {
  final String value;
  final ClipboardManager clipboardManager;

  const PasswordField({
    super.key,
    required this.value,
    required this.clipboardManager,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _revealed = false;
  Timer? _autoHideTimer;

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    super.dispose();
  }

  void _toggleReveal() {
    setState(() {
      _revealed = !_revealed;
    });
    _autoHideTimer?.cancel();
    if (_revealed) {
      _autoHideTimer = Timer(const Duration(seconds: 10), () {
        if (mounted) {
          setState(() => _revealed = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            _revealed ? widget.value : '\u2022' * widget.value.length,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: _revealed ? 'monospace' : null,
              fontSize: 14,
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            _revealed ? Icons.visibility : Icons.visibility_off,
          ),
          tooltip: _revealed ? 'Hide password' : 'Show password',
          onPressed: _toggleReveal,
          iconSize: 20,
          splashRadius: 20,
        ),
        CopyButton(
          value: widget.value,
          clipboardManager: widget.clipboardManager,
          tooltip: 'Copy password',
        ),
      ],
    );
  }
}
