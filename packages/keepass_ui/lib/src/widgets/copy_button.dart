import 'dart:async';

import 'package:flutter/material.dart';

import '../state/clipboard_manager.dart';

class CopyButton extends StatefulWidget {
  final String? value;
  final Future<String> Function()? fetchValue;
  final ClipboardManager clipboardManager;
  final IconData icon;
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
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not copy to clipboard. Your browser may not support this feature.',
            ),
            duration: Duration(seconds: 2),
          ),
        );
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
        SnackBar(
          content: Text(widget.clipboardManager.lastSuccessMessage),
          duration: const Duration(seconds: 2),
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
