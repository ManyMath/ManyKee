import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:manykee/src/merge/merge_page.dart';
import 'package:manykee/src/merge/merge_service.dart';
import 'package:manykee/src/theme.dart';
import 'package:manyui/manyui.dart';

const _pathA = '/vaults/a.kdbx';
const _pathB = '/vaults/b.kdbx';
const _openAButton = 'Open database A (your open vault)';

class _FakeMergeService implements MergeService {
  static const acceptedPassword = 'correct';

  String? openedA;
  String? openedB;
  String? savedTo;

  @override
  bool get bothOpen => openedA != null && openedB != null;

  @override
  Future<void> openA({
    required String filePath,
    required String password,
  }) async {
    if (password != acceptedPassword) {
      throw Exception('invalid credentials or corrupt database');
    }
    openedA = filePath;
  }

  @override
  Future<void> openB({
    required String filePath,
    required String password,
  }) async {
    if (password != acceptedPassword) {
      throw Exception('invalid credentials or corrupt database');
    }
    openedB = filePath;
  }

  @override
  MergeResult preview() => MergeResult(
    entriesAdded: 0,
    entriesUpdated: 0,
    entriesDeleted: 0,
    entriesRelocated: 0,
    groupsAdded: 0,
    groupsUpdated: 0,
    groupsDeleted: 0,
    groupsRelocated: 0,
    totalChanges: 0,
    conflictsCount: 0,
    warningsCount: 0,
    warnings: const <String>[],
  );

  @override
  bool isSourcePath(String path) => path == openedA || path == openedB;

  @override
  MergeServiceResult saveMergedCopy({
    required String outputPath,
    required String outputPassword,
  }) {
    if (isSourcePath(outputPath)) {
      throw ArgumentError.value(outputPath, 'outputPath');
    }
    savedTo = outputPath;
    return MergeServiceResult(mergeResult: preview(), outputPath: outputPath);
  }

  @override
  void dispose() {}
}

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker({this.pickPath, this.savePath});

  final String? pickPath;
  final String? savePath;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    final path = pickPath;
    if (path == null) return null;
    return FilePickerResult(<PlatformFile>[
      PlatformFile(path: path, name: path.split('/').last, size: 0),
    ]);
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    return savePath;
  }
}

Widget _harness(MergeService service) {
  return ProviderScope(
    child: MWidgetsApp(
      theme: manyKeeLightTheme,
      debugShowCheckedModeBanner: false,
      home: MergeDatabasesPage(
        currentFilePath: _pathA,
        createService: () => service,
      ),
    ),
  );
}

Future<void> _enterPasswordAndOpen(
  WidgetTester tester,
  String password,
  String buttonLabel,
) async {
  await tester.tap(find.byType(MTextField));
  await tester.pump();
  await tester.enterText(find.byType(EditableText), password);
  await tester.pump();
  await tester.ensureVisible(find.widgetWithText(MButton, buttonLabel));
  await tester.pump();
  await tester.tap(find.widgetWithText(MButton, buttonLabel));
  await tester.pump();
  await tester.pump();
}

Future<void> _reachConfirmStep(
  WidgetTester tester,
  _FakeMergeService service,
) async {
  await tester.pumpWidget(_harness(service));
  await _enterPasswordAndOpen(tester, 'correct', _openAButton);
  expect(service.openedA, _pathA);

  await tester.tap(find.widgetWithText(MButton, 'Choose file…'));
  await tester.pump();
  await tester.pump();
  expect(find.text('b.kdbx'), findsOneWidget);
  await _enterPasswordAndOpen(tester, 'correct', 'Open database B');
  expect(service.openedB, _pathB);
  expect(find.text('Review merge'), findsOneWidget);
}

void main() {
  tearDown(() => FilePicker.platform = _FakeFilePicker());

  testWidgets('a failed open shows the friendly message, not the raw error', (
    tester,
  ) async {
    final service = _FakeMergeService();
    await tester.pumpWidget(_harness(service));

    await _enterPasswordAndOpen(tester, 'wrong', _openAButton);

    expect(find.text('Incorrect password. Please try again.'), findsOneWidget);
    expect(find.textContaining('invalid credentials'), findsNothing);
    expect(service.openedA, isNull);
    // Still on step A.
    expect(find.text(_openAButton), findsWidgets);
  });

  testWidgets('refuses to save the merged copy over database A', (
    tester,
  ) async {
    FilePicker.platform = _FakeFilePicker(pickPath: _pathB, savePath: _pathA);
    final service = _FakeMergeService();
    await _reachConfirmStep(tester, service);

    await tester.ensureVisible(
      find.widgetWithText(MButton, 'Choose destination…'),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(MButton, 'Choose destination…'));
    await tester.pump();

    expect(find.textContaining('cannot overwrite database A'), findsOneWidget);
    expect(find.text('Choose destination…'), findsOneWidget);
    expect(find.text(_pathA), findsNothing);
  });

  testWidgets('refuses to save the merged copy over database B', (
    tester,
  ) async {
    FilePicker.platform = _FakeFilePicker(pickPath: _pathB, savePath: _pathB);
    final service = _FakeMergeService();
    await _reachConfirmStep(tester, service);

    await tester.ensureVisible(
      find.widgetWithText(MButton, 'Choose destination…'),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(MButton, 'Choose destination…'));
    await tester.pump();

    expect(find.textContaining('cannot overwrite database A'), findsOneWidget);
    expect(find.text('Choose destination…'), findsOneWidget);
  });

  testWidgets('saves the merged copy to a new file', (tester) async {
    FilePicker.platform = _FakeFilePicker(
      pickPath: _pathB,
      savePath: '/vaults/merged.kdbx',
    );
    final service = _FakeMergeService();
    await _reachConfirmStep(tester, service);

    await tester.ensureVisible(
      find.widgetWithText(MButton, 'Choose destination…'),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(MButton, 'Choose destination…'));
    await tester.pump();
    expect(find.text('/vaults/merged.kdbx'), findsOneWidget);

    await tester.tap(find.byType(MTextField));
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'new-password');
    await tester.pump();
    await tester.ensureVisible(
      find.widgetWithText(MButton, 'Confirm & save merge'),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(MButton, 'Confirm & save merge'));
    await tester.pump();
    await tester.pump();

    expect(service.savedTo, '/vaults/merged.kdbx');
    expect(find.text('Merge complete'), findsOneWidget);
  });
}
