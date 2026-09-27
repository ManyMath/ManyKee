import 'dart:async';

import 'package:flutter/material.dart';

import '../state/clipboard_manager.dart';
import 'copy_button.dart';

class PasswordField extends StatefulWidget {
  final String value;
  final ClipboardManager clipboardManager;

  /// Fetches the real value on demand (e.g. via `readEntryField`), for
  /// backends that scrub protected values from the bulk read this widget's
  /// [value] came from. Called at most once, the first time the value is
  /// needed (reveal or copy); if it returns a non-null value, that value is
  /// used in place of [value] from then on.
  final Future<String?> Function()? onFetchValue;

  final String copyTooltip;

  const PasswordField({
    super.key,
    required this.value,
    required this.clipboardManager,
    this.onFetchValue,
    this.copyTooltip = 'Copy password',
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _revealed = false;
  bool _fetchAttempted = false;
  String? _fetchedValue;
  Timer? _autoHideTimer;

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    super.dispose();
  }

  String get _value => _fetchedValue ?? widget.value;

  Future<void> _ensureValueFetched() async {
    final fetch = widget.onFetchValue;
    if (_fetchAttempted || fetch == null) {
      return;
    }
    _fetchAttempted = true;
    final String? value;
    try {
      value = await fetch();
    } catch (_) {
      // Allow a later reveal/copy to retry instead of being stuck with the
      // scrubbed placeholder forever.
      _fetchAttempted = false;
      rethrow;
    }
    if (mounted && value != null) {
      setState(() => _fetchedValue = value);
    }
  }

  Future<void> _toggleReveal() async {
    if (!_revealed) {
      try {
        await _ensureValueFetched();
      } catch (_) {
        // Nothing useful to reveal; the user can try again.
        return;
      }
    }
    if (!mounted) {
      return;
    }
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
            _revealed ? _value : '\u2022' * _value.length,
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
          value: widget.onFetchValue == null ? _value : null,
          fetchValue: widget.onFetchValue == null
              ? null
              : () async {
                  await _ensureValueFetched();
                  return _value;
                },
          clipboardManager: widget.clipboardManager,
          tooltip: widget.copyTooltip,
        ),
      ],
    );
  }
}
