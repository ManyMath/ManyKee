import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_ui/keepass_ui.dart';
import 'package:manykee_native/src/screens/unlock_screen.dart';
import 'package:manykee_native/src/state/native_vault_state.dart';

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.path, this.name);

  final String path;
  final String name;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    return FilePickerResult(<PlatformFile>[
      PlatformFile(name: name, path: path, size: 1024),
    ]);
  }
}

class _DelayedNativeVaultState extends NativeVaultState {
  final Completer<void> unlockCompleter = Completer<void>();

  int unlockCalls = 0;
  String? openedFilePath;

  @override
  Future<void> unlockNative({
    required String filePath,
    required String password,
    String? keyFilePath,
    String? yubiKeySlot,
    String? filename,
  }) async {
    unlockCalls += 1;
    openedFilePath = filePath;
    await unlockCompleter.future;
  }
}

void main() {
  testWidgets(
      'unlock screen shows progress indicators while native unlock is pending',
      (
    tester,
  ) async {
    final vaultState = _DelayedNativeVaultState();
    FilePicker.platform = _FakeFilePicker('/tmp/test_db.kdbx', 'test_db.kdbx');

    await tester.pumpWidget(
      MaterialApp(
        theme: ManyKeeTheme.light(),
        home: NativeUnlockScreen(vaultState: vaultState),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Choose KDBX File'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Master Password'),
      'demopass',
    );
    await tester.pump();

    await tester.tap(find.text('Unlock Vault'));
    await tester.pump();

    expect(vaultState.unlockCalls, 1);
    expect(vaultState.openedFilePath, '/tmp/test_db.kdbx');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    vaultState.unlockCompleter.complete();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
