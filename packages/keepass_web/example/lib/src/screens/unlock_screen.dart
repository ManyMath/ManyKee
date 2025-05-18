import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:keepass_ui/keepass_ui.dart';
import 'package:keepass_web/keepass_web.dart';

import '../state/web_vault_state.dart';
import '../widgets/file_picker_button.dart';

/// Unlock screen with responsive layout (single card or wizard steps).
class UnlockScreen extends StatefulWidget {
 final WebVaultState vaultState;

 /// When true, shows "Vault Locked" heading and pre-filled filename.
 final bool isLockScreen;

 const UnlockScreen({
 super.key,
 required this.vaultState,
 this.isLockScreen = false,
 });

 @override
 State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
 Uint8List? _dbBytes;
 String? _dbFilename;
 final _passwordController = TextEditingController();
 Uint8List? _keyFileBytes;
 String? _keyFilename;
 bool _showKeyFile = false;
 bool _isDecrypting = false;
 bool _obscurePassword = true;
 JSObject? _yubiKeyDevice;
 String? _yubiKeyName;

 /// Mobile wizard step: 0=file, 1=credentials, 2=decrypting.
 int _wizardStep = 0;

 final _passwordFocusNode = FocusNode();

@override
 void initState() {
 super.initState();
 if (widget.isLockScreen && widget.vaultState.lastFilename != null) {
 _dbFilename = widget.vaultState.lastFilename;
 _dbBytes = widget.vaultState.lastDbBytes;
 _wizardStep = 1;
 }
 if (widget.isLockScreen) {
 WidgetsBinding.instance.addPostFrameCallback((_) {
 _passwordFocusNode.requestFocus();
 });
 }
 }

 @override
 void dispose() {
 _passwordController.dispose();
 _passwordFocusNode.dispose();
 super.dispose();
 }

 bool get _canUnlock =>
 _dbBytes != null &&
 _passwordController.text.isNotEmpty;

 Future<void> _unlock() async {
 setState(() {
 _isDecrypting = true;
 });
 widget.vaultState.clearError();

try {
 String? crHex;
 if (_yubiKeyDevice != null) {
 final challengeHex =
 await widget.vaultState.extractChallenge(_dbBytes!);
 final challengeBytes = _hexDecode(challengeHex);
 crHex = await yubikeyChallengeResponse(
 _yubiKeyDevice!,
 challengeBytes,
 );
 }
 await widget.vaultState.unlock(
 dbBytes: _dbBytes!,
 password: _passwordController.text,
 keyFileBytes: _keyFileBytes,
 challengeResponseHex: crHex,
 filename: _dbFilename,
 );
 } on KeePassWebError catch (e) {
 widget.vaultState.setError(e.code, e.message);
 if (e.code == 'WRONG_PASSWORD') {
 _passwordController.clear();
 _passwordFocusNode.requestFocus();
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
 return Scaffold(
 backgroundColor: Theme.of(context).colorScheme.surface,
 body: Center(
 child: LayoutBuilder(
 builder: (context, constraints) {
 if (constraints.maxWidth >= 720) {
 return _buildDesktopLayout(context);
 } else {
 return _buildMobileLayout(context);
 }
 },
 ),
 ),
 );
 }

Widget _buildDesktopLayout(BuildContext context) {
 return SingleChildScrollView(
 padding: const EdgeInsets.symmetric(
 horizontal: Spacing.xl,
 vertical: Spacing.xxxl,
 ),
 child: Center(
 child: ConstrainedBox(
 constraints: const BoxConstraints(maxWidth: 420),
 child: Column(
 mainAxisSize: MainAxisSize.min,
 children: [
 _buildHeading(context),
 const SizedBox(height: Spacing.xxl),
 _buildFilePicker(context),
 const SizedBox(height: Spacing.lg),
 _buildPasswordField(context),
 _buildErrorDisplay(context),
 const SizedBox(height: Spacing.md),
 _buildKeyFileSection(context),
 _buildYubiKeySection(context),
 const SizedBox(height: Spacing.lg),
 _buildUnlockButton(context),
 if (_isDecrypting) ...[
 const SizedBox(height: Spacing.md),
 _buildProgressBar(context),
 ],
 ],
 ),
 ),
 ),
 );
 }

Widget _buildMobileLayout(BuildContext context) {
 return SingleChildScrollView(
 padding: const EdgeInsets.symmetric(
 horizontal: Spacing.xl,
 vertical: Spacing.xxxl,
 ),
 child: Center(
 child: ConstrainedBox(
 constraints: const BoxConstraints(maxWidth: 420),
 child: Column(
 mainAxisSize: MainAxisSize.min,
 children: [
 _buildHeading(context),
 const SizedBox(height: Spacing.xxl),
 if (_wizardStep == 0) ...[
 _buildFilePicker(context),
 const SizedBox(height: Spacing.lg),
 SizedBox(
 width: double.infinity,
 child: FilledButton(
 onPressed: _dbBytes != null
 ? () => setState(() => _wizardStep = 1)
 : null,
 child: const Text('Continue to Credentials'),
 ),
 ),
 ],
 if (_wizardStep == 1) ...[
 _buildPasswordField(context),
 _buildErrorDisplay(context),
 const SizedBox(height: Spacing.md),
 _buildKeyFileSection(context),
 _buildYubiKeySection(context),
 const SizedBox(height: Spacing.lg),
 _buildUnlockButton(context),
 ],
 if (_wizardStep == 2) ...[
 _buildProgressBar(context),
 const SizedBox(height: Spacing.md),
 Text(
 'Decrypting...',
 style: Theme.of(context).textTheme.bodyMedium,
 ),
 ],
 ],
 ),
 ),
 ),
 );
 }

Widget _buildHeading(BuildContext context) {
 final theme = Theme.of(context);
 if (widget.isLockScreen) {
 return Column(
 children: [
 Text(
 'Vault Locked',
 style: theme.textTheme.titleLarge,
 textAlign: TextAlign.center,
 ),
 const SizedBox(height: Spacing.sm),
 Text(
 'Session expired. Enter your password to continue.',
 style: theme.textTheme.labelSmall,
 textAlign: TextAlign.center,
 ),
 ],
 );
 }
 return Text(
 'ManyKee',
 style: theme.textTheme.titleLarge,
 textAlign: TextAlign.center,
 );
 }

Widget _buildFilePicker(BuildContext context) {
 if (widget.isLockScreen && _dbFilename != null) {
 return SizedBox(
 width: double.infinity,
 child: OutlinedButton.icon(
 onPressed: null,
 icon: const Icon(Icons.description),
 label: Text(
 _dbFilename!.length > 30
 ? '${_dbFilename!.substring(0, 27)}...'
 : _dbFilename!,
 overflow: TextOverflow.ellipsis,
 ),
 ),
 );
 }

 return FilePickerButton(
 label: 'Choose KDBX File',
 accept: '.kdbx',
 selectedFilename: _dbFilename,
 onFilePicked: (filename, bytes) {
 setState(() {
 _dbFilename = filename;
 _dbBytes = bytes;
 });
 widget.vaultState.clearError();
 },
 );
 }

 Widget _buildPasswordField(BuildContext context) {
 return TextField(
 controller: _passwordController,
 focusNode: _passwordFocusNode,
 obscureText: _obscurePassword,
 decoration: InputDecoration(
 labelText: 'Master Password',
 border: const OutlineInputBorder(),
 suffixIcon: IconButton(
 icon: Icon(
 _obscurePassword ? Icons.visibility_off : Icons.visibility,
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
 );
 }

 Widget _buildErrorDisplay(BuildContext context) {
 final errorCode = widget.vaultState.errorCode;
 final errorMessage = widget.vaultState.errorMessage;
 if (errorMessage == null) return const SizedBox.shrink();

 String displayMessage;
 if (errorCode == 'WRONG_PASSWORD') {
 displayMessage = 'Incorrect password. Please try again.';
 } else if (errorCode == 'CORRUPT_FILE' || errorCode == 'PARSE_ERROR') {
 displayMessage =
 'This file could not be read. It may be corrupted or not a KDBX 4.x database.';
 } else {
 displayMessage = errorMessage;
 }

 return Padding(
 padding: const EdgeInsets.only(top: Spacing.sm),
 child: Text(
 displayMessage,
 style: TextStyle(
 color: Theme.of(context).colorScheme.error,
 fontSize: 12,
 ),
 ),
 );
 }

 Widget _buildKeyFileSection(BuildContext context) {
 if (!_showKeyFile) {
 return Align(
 alignment: Alignment.centerLeft,
 child: TextButton(
 onPressed: () => setState(() => _showKeyFile = true),
 child: const Text('Add Key File'),
 ),
 );
 }

 return Column(
 crossAxisAlignment: CrossAxisAlignment.start,
 children: [
 FilePickerButton(
 label: 'Choose Key File',
 accept: '.key,.keyx,.xml',
 selectedFilename: _keyFilename,
 onFilePicked: (filename, bytes) {
 setState(() {
 _keyFilename = filename;
 _keyFileBytes = bytes;
 });
 },
 ),
 const SizedBox(height: Spacing.sm),
 ],
 );
 }

 Widget _buildYubiKeySection(BuildContext context) {
 if (!isWebUsbAvailable) return const SizedBox.shrink();

 if (_yubiKeyName != null) {
 return Padding(
 padding: const EdgeInsets.only(bottom: Spacing.sm),
 child: Row(
 children: [
 const Icon(Icons.key, size: 18),
 const SizedBox(width: Spacing.xs),
 Text(
 'YubiKey connected: $_yubiKeyName',
 style: Theme.of(context).textTheme.bodyMedium,
 ),
 ],
 ),
 );
 }

 return Align(
 alignment: Alignment.centerLeft,
 child: TextButton.icon(
 onPressed: _requestYubiKey,
 icon: const Icon(Icons.key),
 label: const Text('Use YubiKey'),
 ),
 );
 }

 Future<void> _requestYubiKey() async {
 try {
 final device = await requestYubiKey();
 if (device != null) {
 setState(() {
 _yubiKeyDevice = device;
 _yubiKeyName = 'YubiKey';
 });
 }
 } catch (e) {
 widget.vaultState.setError(
 'WEBUSB_DENIED',
 'YubiKey access was denied. Please allow USB device access and try again.',
 );
 setState(() {});
 }
 }

 Widget _buildUnlockButton(BuildContext context) {
 return SizedBox(
 width: double.infinity,
 child: FilledButton(
 onPressed: _canUnlock && !_isDecrypting
 ? () async {
 // On mobile, show progress step.
 if (MediaQuery.of(context).size.width < 720) {
 setState(() => _wizardStep = 2);
 }
 await _unlock();
 }
 : null,
 child: _isDecrypting
 ? const Text('Decrypting...')
 : const Text('Unlock Vault'),
 ),
 );
 }

 Widget _buildProgressBar(BuildContext context) {
 return const LinearProgressIndicator();
 }

 static Uint8List _hexDecode(String hex) {
 final bytes = Uint8List(hex.length ~/ 2);
 for (var i = 0; i < bytes.length; i++) {
 bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
 }
 return bytes;
 }
}
