import 'dart:async';

import 'package:flutter/material.dart';

import '../state/clipboard_manager.dart';

/// A button that copies a value to the clipboard with visual feedback.
///
/// Shows a checkmark icon for 1.5 seconds after copying, and displays
/// a snackbar confirming the copy with auto-clear notice.
class CopyButton extends StatefulWidget {
  /// The value to copy. If null, [fetchValue] is called on press.
  final String? value;

  /// Lazy fetch for the value (e.g. password fetched on-demand).
  final Future<String> Function()? fetchValue;

  /// Clipboard manager with auto-clear support.
  final ClipboardManager clipboardManager;

  /// Icon to display (defaults to [Icons.copy]).
  final IconData icon;

  /// Tooltip text for the button.
  final String tooltip;

  const CopyButton({
    super.key,
    this.value,
    this.fetchValue,
    required this.clipboardManager,
    this.icon = Icons.copy,
    this.tooltip = 'Copy',
  });

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _showCheck = false;
  bool _loading = false;
  Timer? _checkTimer;

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }

  Future<void> _onPressed() async {
    if (_loading) return;

    String? valueToCopy = widget.value;
    if (valueToCopy == null && widget.fetchValue != null) {
      setState(() => _loading = true);
      try {
        valueToCopy = await widget.fetchValue!();
      } catch (_) {
        setState(() => _loading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not copy to clipboard. Your browser may not support this feature.',
              ),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() => _loading = false);
    }

    if (valueToCopy == null) return;

    final success =
        await widget.clipboardManager.copyWithAutoClear(valueToCopy);

    if (!mounted) return;

    if (success) {
      setState(() => _showCheck = true);
      _checkTimer?.cancel();
      _checkTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() => _showCheck = false);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard (clears in 30s)'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not copy to clipboard. Your browser may not support this feature.',
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return IconButton(
      icon: _loading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            )
          : Icon(
              _showCheck ? Icons.check : widget.icon,
              color: _showCheck ? colorScheme.primary : null,
            ),
      tooltip: widget.tooltip,
      onPressed: _onPressed,
      iconSize: 20,
      splashRadius: 20,
    );
  }
}
