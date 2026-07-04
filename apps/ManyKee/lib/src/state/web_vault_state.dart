import 'dart:async';
import 'dart:typed_data';

import 'package:keepass_ui/keepass_ui.dart';

import 'manykee_vault_state.dart';

ManyKeeVaultState createVaultState() => WebVaultState();

/// Placeholder vault state so the web target compiles.
// TODO(manykee): phase B — real web vault state via keepass_web (WASM worker).
class WebVaultState extends ManyKeeVaultState {
  static Never _unsupported() =>
      throw UnimplementedError('web unlock lands in a later phase');

  @override
  String? get lastFilePath => null;

  @override
  Stream<int> get progress => const Stream<int>.empty();

  @override
  Future<void> unlock({
    Uint8List? dbBytes,
    String? filePath,
    required String password,
    Uint8List? keyFileBytes,
    String? challengeResponseHex,
    String? filename,
  }) async {
    _unsupported();
  }

  @override
  Future<void> unlockFromPath({
    required String filePath,
    required String password,
    String? keyFilePath,
    String? filename,
    String? yubiKeySlot,
  }) async {
    _unsupported();
  }

  @override
  Future<List<Map<String, dynamic>>> listYubiKeys() async =>
      const <Map<String, dynamic>>[];

  @override
  void openDifferentFile() {}

  @override
  Future<void> lock() async {
    resetBrowsingState();
  }

  @override
  Future<void> selectGroup(VaultGroup group) async => _unsupported();

  @override
  Future<Map<String, dynamic>> readEntryFields(String entryUuid) async =>
      _unsupported();

  @override
  Future<String?> readEntryField(String entryUuid, String fieldName) async =>
      _unsupported();

  @override
  Future<Map<String, dynamic>?> getTotpCode(String entryUuid) async =>
      _unsupported();
}
