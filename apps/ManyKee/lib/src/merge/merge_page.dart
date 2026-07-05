import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:manyui/manyui.dart';

import '../state/unlock_error_mapper.dart';
import 'merge_service.dart';

/// Pushes [MergeDatabasesPage] onto the navigator.
///
/// Gated to an already-open vault: only reachable from `vault_page.dart`,
/// never from the unlock page. [currentFilePath] is the currently-open
/// vault's file, the merge always uses it as database A (re-proved via
/// its own independent password entry, not silently trusted), and only
/// prompts the user to pick database B (a divergent copy of the same
/// database, e.g. synced from another device, see `preview()`'s
/// doc comment on what the Rust merge engine actually supports).
Future<void> showMergeDatabasesPage(
  BuildContext context, {
  required String currentFilePath,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      pageBuilder: (context, _, __) =>
          MergeDatabasesPage(currentFilePath: currentFilePath),
    ),
  );
}

enum _MergeStep { openA, openB, confirm, done }

/// Safe merge-databases flow.
///
/// Required safety shape (see ROADMAP.md's ManyKee "Merge-databases UI"
/// item, do not simplify away any of these steps):
///  1. Open source database A (the currently-open vault's own file) through
///     a full independent unlock and reject the whole operation if it fails
///     to open/decrypt: never trust the already-open vault's in-memory
///     state as proof the file on disk still opens.
///  2. Do the same for source database B, independently.
///  3. Only once both are confirmed openable, show a merge preview (counts
///     from the `MergeResult` the Rust layer returns) and require explicit
///     confirmation.
///  4. Only then merge and write the result, to a *new* file the user
///     picks, since `saveDatabase`/in-place editing isn't implemented yet
///     (see `ManyKeeVaultState`).
class MergeDatabasesPage extends HookConsumerWidget {
  const MergeDatabasesPage({super.key, required this.currentFilePath});

  final String currentFilePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = MTheme.of(context);
    final service = useMemoized(createMergeService);
    useEffect(() => service.dispose, <Object?>[service]);

    final step = useState(_MergeStep.openA);
    final mergeResult = useState<MergeServiceResult?>(null);
    final errorMessage = useState<String?>(null);

    return MScaffold(
      header: Row(
        children: <Widget>[
          MButton(
            variant: MButtonVariant.ghost,
            onPressed: () => Navigator.of(context).maybePop(),
            semanticLabel: 'Back',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                MIcon(MIconData.chevronLeft, size: 14),
                const SizedBox(width: 4),
                const Text('Back'),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('Merge databases', style: theme.typography.title),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: MCard(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: switch (step.value) {
                  _MergeStep.openA => _OpenSourceStep(
                      label: 'A (your open vault)',
                      description:
                          'This is the vault you currently have open, at '
                          '$currentFilePath. Enter its password again to '
                          'independently prove it still opens before '
                          'anything else happens.',
                      fixedFilePath: currentFilePath,
                      onOpened: (filePath, password) async {
                        errorMessage.value = null;
                        try {
                          await service.openA(
                              filePath: filePath, password: password);
                          step.value = _MergeStep.openB;
                        } catch (e) {
                          errorMessage.value = _friendlyMessage(e, filePath);
                          rethrow;
                        }
                      },
                    ),
                  _MergeStep.openB => _OpenSourceStep(
                      label: 'B',
                      description:
                          'Choose the other copy of this database (e.g. '
                          'synced from another device). It must also open '
                          'on its own, independently of database A, '
                          'before the merge preview is shown. The merge '
                          'engine can only merge divergent copies of the '
                          'same original database, not two unrelated '
                          'databases.',
                      onOpened: (filePath, password) async {
                        errorMessage.value = null;
                        try {
                          await service.openB(
                              filePath: filePath, password: password);
                          step.value = _MergeStep.confirm;
                        } catch (e) {
                          errorMessage.value = _friendlyMessage(e, filePath);
                          rethrow;
                        }
                      },
                    ),
                  _MergeStep.confirm => _ConfirmStep(
                      service: service,
                      onCancel: () => Navigator.of(context).maybePop(),
                      onMerged: (result) {
                        mergeResult.value = result;
                        step.value = _MergeStep.done;
                      },
                    ),
                  _MergeStep.done => _DoneStep(result: mergeResult.value!),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _friendlyMessage(Object error, String filePath) {
  final mapped = mapUnlockError(error.toString(), filePath: filePath);
  return mapped.message;
}

/// Step 1 or 2: pick a file, optionally a key file, enter the password, and
/// attempt to open it. Only calls [onOpened], which advances the wizard,
/// after the service call inside it has succeeded; a thrown error stays on
/// this step with a friendly message.
class _OpenSourceStep extends HookWidget {
  const _OpenSourceStep({
    required this.label,
    required this.description,
    required this.onOpened,
    this.fixedFilePath,
  });

  final String label;
  final String description;
  final Future<void> Function(String filePath, String password) onOpened;

  /// When set, this step uses this exact file (no picker shown), used for
  /// database A, which is always the currently-open vault's own file.
  final String? fixedFilePath;

  @override
  Widget build(BuildContext context) {
    final theme = MTheme.of(context);
    final filePath = useState<String?>(fixedFilePath);
    final filename = useState<String?>(fixedFilePath);
    final password = useState('');
    final passwordController = useMemoized(() => MController<String>(''));
    useEffect(() => passwordController.dispose, <Object?>[passwordController]);
    final opening = useState(false);
    final error = useState<String?>(null);

    final canOpen =
        filePath.value != null && password.value.isNotEmpty && !opening.value;

    Future<void> pickDatabase() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['kdbx'],
        dialogTitle: 'Choose Database $label',
      );
      if (result != null && result.files.isNotEmpty) {
        filePath.value = result.files.single.path;
        filename.value = result.files.single.name;
      }
    }

    Future<void> open() async {
      if (!canOpen) return;
      opening.value = true;
      error.value = null;
      try {
        await onOpened(filePath.value!, passwordController.value);
      } catch (e) {
        error.value = e.toString();
      }
      opening.value = false;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Open database $label', style: theme.typography.headlineSmall),
        const SizedBox(height: 8),
        Text(
          description,
          style: theme.typography.bodySmall
              .copyWith(color: theme.colors.mutedForeground),
        ),
        const SizedBox(height: 24),
        MLabel('Database $label'),
        const SizedBox(height: 8),
        if (fixedFilePath != null)
          Text(fixedFilePath!, overflow: TextOverflow.ellipsis)
        else
          MButton(
            variant: MButtonVariant.outline,
            onPressed: opening.value ? null : pickDatabase,
            child: Text(
              filename.value ?? 'Choose file…',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const SizedBox(height: 16),
        const MLabel('Master password'),
        const SizedBox(height: 8),
        MTextField(
          controller: passwordController,
          obscureText: true,
          placeholder: 'Password',
          semanticLabel: 'Master password for database $label',
          enabled: !opening.value,
          onChanged: (value) => password.value = value,
          onSubmitted: (_) => open(),
        ),
        if (error.value != null && !opening.value) ...[
          const SizedBox(height: 12),
          Text(
            error.value!,
            style: theme.typography.bodySmall
                .copyWith(color: theme.colors.destructive),
          ),
        ],
        if (opening.value) ...[
          const SizedBox(height: 16),
          const MProgress.indeterminate(semanticLabel: 'Opening'),
        ],
        const SizedBox(height: 24),
        MButton(
          onPressed: canOpen ? open : null,
          child: Text(opening.value ? 'Opening…' : 'Open database $label'),
        ),
      ],
    );
  }
}

/// Step 3: both source databases are confirmed openable. Shows the
/// `MergeResult` preview (computed but not yet written to disk) and
/// requires the user to pick a destination file before merging for real.
class _ConfirmStep extends HookWidget {
  const _ConfirmStep({
    required this.service,
    required this.onCancel,
    required this.onMerged,
  });

  final MergeService service;
  final VoidCallback onCancel;
  final void Function(MergeServiceResult result) onMerged;

  @override
  Widget build(BuildContext context) {
    final theme = MTheme.of(context);
    final preview = useMemoized(service.preview);

    final outputPath = useState<String?>(null);
    final outputPassword = useState('');
    final outputPasswordController =
        useMemoized(() => MController<String>(''));
    useEffect(
      () => outputPasswordController.dispose,
      <Object?>[outputPasswordController],
    );
    final saving = useState(false);
    final error = useState<String?>(null);

    final canSave = outputPath.value != null &&
        outputPassword.value.isNotEmpty &&
        !saving.value;

    Future<void> pickOutputPath() async {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save merged database as…',
        fileName: 'merged.kdbx',
        type: FileType.custom,
        allowedExtensions: const <String>['kdbx'],
      );
      if (path != null) {
        outputPath.value = path.endsWith('.kdbx') ? path : '$path.kdbx';
      }
    }

    Future<void> confirmAndSave() async {
      if (!canSave) return;
      saving.value = true;
      error.value = null;
      try {
        final result = service.saveMergedCopy(
          outputPath: outputPath.value!,
          outputPassword: outputPasswordController.value,
        );
        onMerged(result);
      } catch (e) {
        error.value = e.toString();
      }
      saving.value = false;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Review merge', style: theme.typography.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Both databases opened successfully. Nothing has been written to '
          'disk yet: review the changes below, then choose where to save '
          'the merged copy.',
          style: theme.typography.bodySmall
              .copyWith(color: theme.colors.mutedForeground),
        ),
        const SizedBox(height: 20),
        _MergePreviewCard(preview: preview),
        const SizedBox(height: 20),
        const MLabel('Save merged copy as'),
        const SizedBox(height: 8),
        MButton(
          variant: MButtonVariant.outline,
          onPressed: saving.value ? null : pickOutputPath,
          child: Text(
            outputPath.value ?? 'Choose destination…',
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 16),
        const MLabel('Master password for merged copy'),
        const SizedBox(height: 8),
        MTextField(
          controller: outputPasswordController,
          obscureText: true,
          placeholder: 'Password',
          semanticLabel: 'Master password for the merged copy',
          enabled: !saving.value,
          onChanged: (value) => outputPassword.value = value,
          onSubmitted: (_) => confirmAndSave(),
        ),
        if (error.value != null && !saving.value) ...[
          const SizedBox(height: 12),
          Text(
            error.value!,
            style: theme.typography.bodySmall
                .copyWith(color: theme.colors.destructive),
          ),
        ],
        if (saving.value) ...[
          const SizedBox(height: 16),
          const MProgress.indeterminate(semanticLabel: 'Merging'),
        ],
        const SizedBox(height: 24),
        Row(
          children: <Widget>[
            Expanded(
              child: MButton(
                variant: MButtonVariant.outline,
                onPressed: saving.value ? null : onCancel,
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MButton(
                onPressed: canSave ? confirmAndSave : null,
                child:
                    Text(saving.value ? 'Merging…' : 'Confirm & save merge'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MergePreviewCard extends StatelessWidget {
  const _MergePreviewCard({required this.preview});

  final MergeResult preview;

  @override
  Widget build(BuildContext context) {
    final theme = MTheme.of(context);
    final rows = <MapEntry<String, int>>[
      MapEntry('Entries added', preview.entriesAdded),
      MapEntry('Entries updated', preview.entriesUpdated),
      MapEntry('Entries deleted', preview.entriesDeleted),
      MapEntry('Entries relocated', preview.entriesRelocated),
      MapEntry('Groups added', preview.groupsAdded),
      MapEntry('Groups updated', preview.groupsUpdated),
      MapEntry('Groups deleted', preview.groupsDeleted),
      MapEntry('Groups relocated', preview.groupsRelocated),
    ].where((e) => e.value > 0).toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colors.muted,
        borderRadius: BorderRadius.circular(theme.radius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Total changes: ${preview.totalChanges}',
              style: theme.typography.bodySmall
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            if (rows.isEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'No differences found.',
                style: theme.typography.bodySmall
                    .copyWith(color: theme.colors.mutedForeground),
              ),
            ],
            for (final row in rows) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(row.key, style: theme.typography.bodySmall),
                  Text('${row.value}', style: theme.typography.bodySmall),
                ],
              ),
            ],
            if (preview.conflictsCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${preview.conflictsCount} conflict(s) resolved.',
                style: theme.typography.bodySmall
                    .copyWith(color: theme.colors.destructive),
              ),
            ],
            if (preview.warningsCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${preview.warningsCount} warning(s):',
                style: theme.typography.bodySmall
                    .copyWith(color: theme.colors.destructive),
              ),
              for (final warning in preview.warnings)
                Text(
                  '• $warning',
                  style: theme.typography.caption
                      .copyWith(color: theme.colors.mutedForeground),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DoneStep extends StatelessWidget {
  const _DoneStep({required this.result});

  final MergeServiceResult result;

  @override
  Widget build(BuildContext context) {
    final theme = MTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Merge complete', style: theme.typography.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'The merged database was saved to:',
          style: theme.typography.bodySmall
              .copyWith(color: theme.colors.mutedForeground),
        ),
        const SizedBox(height: 4),
        Text(result.outputPath, style: theme.typography.bodySmall),
        const SizedBox(height: 20),
        _MergePreviewCard(preview: result.mergeResult),
        const SizedBox(height: 24),
        MButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
