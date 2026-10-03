import 'dart:developer' as developer;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:keepass/keepass.dart';
import 'package:keepass_ui/keepass_ui.dart' show Spacing;

import '../state/native_vault_state.dart';

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
  String? _filePath;
  String? _filename;
  String? _keyFilePath;
  String? _keyFilename;
  bool _showKeyFile = false;
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _isDecrypting = false;
  bool _obscurePassword = true;

  List<Map<String, dynamic>> _yubiKeys = [];
  bool _useYubiKey = false;
  bool _yubiKeyLoading = true;

  @override
  void initState() {
    super.initState();
    _detectYubiKeys();
  }

  Future<void> _detectYubiKeys() async {
    try {
      final keys = await KeePassNativeApi().listYubiKeys();
      developer.log('YubiKey detection: found ${keys.length} device(s)',
          name: 'ManyKee');
      if (mounted) {
        setState(() {
          _yubiKeys = keys;
          _yubiKeyLoading = false;
        });
      }
    } catch (e, stack) {
      developer.log('YubiKey detection failed: $e',
          name: 'ManyKee', error: e, stackTrace: stack);
      if (mounted) {
        setState(() {
          _yubiKeyLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  bool get _canUnlock =>
      _filePath != null && _passwordController.text.isNotEmpty;

  Future<void> _pickDatabase() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['kdbx'],
      dialogTitle: 'Choose KDBX File',
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _filePath = result.files.single.path;
        _filename = result.files.single.name;
      });
    }
  }

  Future<void> _pickKeyFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['key', 'keyx', 'xml'],
      dialogTitle: 'Choose Key File',
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _keyFilePath = result.files.single.path;
        _keyFilename = result.files.single.name;
      });
    }
  }

  Future<void> _unlock() async {
    setState(() {
      _isDecrypting = true;
    });
    widget.vaultState.clearError();

    try {
      await widget.vaultState.unlockNative(
        filePath: _filePath!,
        password: _passwordController.text,
        keyFilePath: _keyFilePath,
        yubiKeySlot: _useYubiKey ? '2' : null,
        filename: _filename,
      );
    } on KeePassError catch (e, stack) {
      developer.log('Unlock failed: ${e.message}',
          name: 'ManyKee', error: e, stackTrace: stack);
      final message = e.message.toLowerCase();
      if (message.contains('yubikey') || message.contains('challenge')) {
        widget.vaultState.setError(
          'YUBIKEY_ERROR',
          'YubiKey communication failed: ${e.message}',
        );
      } else if (message.contains('disconnect')) {
        widget.vaultState.setError(
          'YUBIKEY_DISCONNECTED',
          'YubiKey was disconnected. Please reconnect and try again.',
        );
      } else if (message.contains('password') ||
          message.contains('key') ||
          message.contains('credentials') ||
          message.contains('unpad') ||
          message.contains('padding')) {
        widget.vaultState.setError(
          'WRONG_PASSWORD',
          'Incorrect password. Please try again.',
        );
        _passwordController.clear();
        _passwordFocusNode.requestFocus();
      } else if (message.contains('no such file') ||
          message.contains('not found') ||
          message.contains('cannot open')) {
        widget.vaultState.setError(
          'FILE_NOT_FOUND',
          'File not found: ${_filePath ?? _filename ?? 'selected file'}\n'
              '${e.message}',
        );
      } else if (message.contains('permission') || message.contains('denied')) {
        widget.vaultState.setError(
          'PERMISSION_DENIED',
          'Permission denied. Check file permissions and try again.',
        );
      } else if (message.contains('locked') || message.contains('in use')) {
        widget.vaultState.setError(
          'FILE_LOCKED',
          'File is locked by another process. Close other applications using '
              'this file and try again.',
        );
      } else if (message.contains('header') || message.contains('corrupt')) {
        widget.vaultState.setError(
          'CORRUPT_HEADER',
          'Database header is corrupted. The file may be damaged.',
        );
      } else if (message.contains('kdbx') &&
          (message.contains('version') ||
              message.contains('format') ||
              message.contains('not a'))) {
        widget.vaultState.setError(
          'NOT_KDBX4',
          'This is not a KDBX 4.x database. ManyKee requires KDBX 4 format.',
        );
      } else if (message.contains('key file') &&
          (message.contains('invalid') ||
              message.contains('read') ||
              message.contains('parse'))) {
        widget.vaultState.setError(
          'KEY_FILE_INVALID',
          'Key file could not be read. Check the file and try again.',
        );
      } else {
        widget.vaultState.setError(
          'PARSE_ERROR',
          'Failed to open database: ${e.message}',
        );
      }
    } catch (e, stack) {
      developer.log('Unlock failed (unexpected): $e',
          name: 'ManyKee', error: e, stackTrace: stack);
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
                Text(
                  'ManyKee',
                  style: textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Spacing.xxl),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isDecrypting ? null : _pickDatabase,
                    icon: const Icon(Icons.folder_open),
                    label: Text(_filename ?? 'Choose KDBX File'),
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _showKeyFile = !_showKeyFile;
                      });
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showKeyFile ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                        ),
                        const SizedBox(width: Spacing.xs),
                        const Text('Key File (optional)'),
                      ],
                    ),
                  ),
                ),
                if (_showKeyFile)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isDecrypting ? null : _pickKeyFile,
                        icon: const Icon(Icons.key),
                        label: Text(_keyFilename ?? 'Choose Key File'),
                      ),
                    ),
                  ),
                if (!_yubiKeyLoading) ...[
                  const SizedBox(height: Spacing.sm),
                  if (_yubiKeys.isNotEmpty)
                    InputChip(
                      avatar: const Icon(Icons.key, size: 18),
                      label: const Text('YubiKey detected'),
                      selected: _useYubiKey,
                      onSelected: _isDecrypting
                          ? null
                          : (v) => setState(() => _useYubiKey = v),
                    )
                  else
                    TextButton.icon(
                      onPressed: _isDecrypting
                          ? null
                          : () => setState(() => _useYubiKey = !_useYubiKey),
                      icon: Icon(
                        _useYubiKey
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 18,
                      ),
                      label: const Text('Use YubiKey'),
                    ),
                ],
                if (widget.vaultState.errorMessage != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: SelectableText(
                      widget.vaultState.errorMessage!,
                      style: TextStyle(
                        color: colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
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
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: const LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
