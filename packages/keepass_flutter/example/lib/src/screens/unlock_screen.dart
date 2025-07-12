import 'package:flutter/material.dart';
import 'package:keepass/keepass.dart';
import 'package:keepass_ui/keepass_ui.dart' show Spacing;

import '../state/native_vault_state.dart';

/// Minimal native unlock screen with file path input and master password.
///
/// Desktop-only for Phase 8 scaffold. No key file, no YubiKey, no mobile
/// wizard -- those are Phase 9.
class NativeUnlockScreen extends StatefulWidget {
  final NativeVaultState vaultState;

  const NativeUnlockScreen({
    super.key,
    required this.vaultState,
  });

  @override
  State<NativeUnlockScreen> createState() => _NativeUnlockScreenState();
}

class _NativeUnlockScreenState extends State<NativeUnlockScreen> {
  final _filePathController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isDecrypting = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _filePathController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canUnlock =>
      _filePathController.text.isNotEmpty &&
      _passwordController.text.isNotEmpty;

  Future<void> _unlock() async {
    setState(() {
      _isDecrypting = true;
    });
    widget.vaultState.clearError();

    try {
      await widget.vaultState.unlock(
        filePath: _filePathController.text,
        password: _passwordController.text,
      );
    } on KeePassError catch (e) {
      final message = e.message.toLowerCase();
      if (message.contains('password') || message.contains('key')) {
        widget.vaultState.setError(
          'WRONG_PASSWORD',
          'Incorrect password. Please try again.',
        );
        _passwordController.clear();
      } else if (message.contains('no such file') ||
          message.contains('not found') ||
          message.contains('cannot open')) {
        widget.vaultState.setError(
          'FILE_NOT_FOUND',
          'File not found. Check the path and try again.',
        );
      } else {
        widget.vaultState.setError(
          'PARSE_ERROR',
          'This file could not be read. It may be corrupted or not a KDBX 4.x database.',
        );
      }
    } catch (e) {
      widget.vaultState.setError('UNKNOWN', e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isDecrypting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

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
                // Heading.
                Text(
                  'ManyKee',
                  style: textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Spacing.xxl),

                // File path input.
                TextField(
                  controller: _filePathController,
                  decoration: const InputDecoration(
                    labelText: 'KDBX File Path',
                    hintText: '/path/to/database.kdbx',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: Spacing.lg),

                // Master password.
                TextField(
                  controller: _passwordController,
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
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (_canUnlock && !_isDecrypting) _unlock();
                  },
                ),

                // Error display.
                if (widget.vaultState.errorMessage != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: Text(
                      widget.vaultState.errorMessage!,
                      style: TextStyle(
                        color: colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: Spacing.lg),

                // Unlock button.
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
