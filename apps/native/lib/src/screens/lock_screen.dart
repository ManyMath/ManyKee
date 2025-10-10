import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:keepass/keepass.dart';
import 'package:keepass_ui/keepass_ui.dart' show Spacing;

import '../state/native_vault_state.dart';

class NativeLockScreen extends StatefulWidget {
  final NativeVaultState vaultState;

  const NativeLockScreen({super.key, required this.vaultState});

  @override
  State<NativeLockScreen> createState() => _NativeLockScreenState();
}

class _NativeLockScreenState extends State<NativeLockScreen> {
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _isDecrypting = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _passwordFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  bool get _canUnlock => _passwordController.text.isNotEmpty;

  Future<void> _unlock() async {
    setState(() => _isDecrypting = true);
    widget.vaultState.clearError();

    try {
      await widget.vaultState.unlockNative(
        filePath: widget.vaultState.lastFilePath!,
        password: _passwordController.text,
        filename: widget.vaultState.lastFilename,
      );
    } on KeePassError catch (e, stack) {
      developer.log('Re-unlock failed: ${e.message}', name: 'ManyKee', error: e, stackTrace: stack);
      final message = e.message.toLowerCase();
      if (message.contains('password') ||
          message.contains('key') ||
          message.contains('credentials')) {
        widget.vaultState.setError(
          'WRONG_PASSWORD',
          'Incorrect password. Please try again.',
        );
        _passwordController.clear();
        _passwordFocusNode.requestFocus();
      } else {
        widget.vaultState.setError(
          'PARSE_ERROR',
          'Failed to open database: ${e.message}',
        );
      }
    } catch (e, stack) {
      developer.log('Re-unlock failed (unexpected): $e', name: 'ManyKee', error: e, stackTrace: stack);
      widget.vaultState.setError('UNKNOWN', e.toString());
    } finally {
      if (mounted) setState(() => _isDecrypting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final filename = widget.vaultState.lastFilename ?? 'Unknown';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.xl,
            vertical: Spacing.xxxl,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Vault Locked',
                  style: textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  'Enter your password to continue.',
                  style: textTheme.labelSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Spacing.xxl),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.description),
                    label: Text(filename),
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                TextField(
                  controller: _passwordController,
                  focusNode: _passwordFocusNode,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Master Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (_canUnlock && !_isDecrypting) _unlock();
                  },
                ),
                if (widget.vaultState.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: SelectableText(
                      widget.vaultState.errorMessage!,
                      style: TextStyle(color: colorScheme.error, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: Spacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _canUnlock && !_isDecrypting ? _unlock : null,
                    child: _isDecrypting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Unlock Vault'),
                  ),
                ),
                if (_isDecrypting)
                  const Padding(
                    padding: EdgeInsets.only(top: Spacing.sm),
                    child: LinearProgressIndicator(),
                  ),
                const SizedBox(height: Spacing.md),
                TextButton(
                  onPressed: () => widget.vaultState.openDifferentFile(),
                  child: const Text('Open Different File'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
