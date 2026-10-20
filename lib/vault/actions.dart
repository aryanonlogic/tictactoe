import 'package:flutter/material.dart';

import '../app_state.dart';
import '../native.dart';
import '../ui.dart';
import 'models.dart';

VaultItemCountLabel _label(int n) => VaultItemCountLabel(n);

class VaultItemCountLabel {
  const VaultItemCountLabel(this.n);
  final int n;
  String get files => n == 1 ? '1 file' : '$n files';
}

// ---------------------------------------------------------------- add / import

Future<void> addFlow(BuildContext context, {String? folderId}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Add to Vault', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
            ),
            _sheetRow(ctx, Icons.image_outlined, 'Import Photos', 'photos'),
            _sheetRow(ctx, Icons.video_library_outlined, 'Import Videos', 'videos'),
            _sheetRow(ctx, Icons.folder_open_outlined, 'From Files', 'files'),
            _sheetRow(ctx, Icons.photo_camera_outlined, 'Take Photo', 'camera_photo'),
            _sheetRow(ctx, Icons.videocam_outlined, 'Record Video', 'camera_video'),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  try {
    if (choice.startsWith('camera')) {
      final uri = await session.external(() => Native.capture(choice == 'camera_video' ? 'video' : 'image'));
      if (uri == null || !context.mounted) return;
      await importFlow(context, <String>[uri], folderId: folderId, fromCamera: true);
    } else {
      final kind = switch (choice) { 'photos' => 'image', 'videos' => 'video', _ => 'files' };
      final uris = await session.external(() => Native.pick(kind));
      if (uris.isEmpty || !context.mounted) return;
      await importFlow(context, uris, folderId: folderId);
    }
  } catch (e) {
    if (context.mounted) snack(context, 'Couldn’t add files: ${_clean(e)}');
  }
}

Widget _sheetRow(BuildContext ctx, IconData icon, String label, String value) {
  return InkWell(
    onTap: () => Navigator.pop(ctx, value),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
      child: Row(
        children: [
          Icon(icon, size: 24),
          const SizedBox(width: 18),
          Text(label, style: const TextStyle(fontSize: 16)),
        ],
      ),
    ),
  );
}

String _clean(Object e) => e.toString().replaceFirst('PlatformException', '').replaceAll(RegExp(r'^\(|\)$'), '');

/// Imports [uris], verifies the private copies, then offers to delete the originals.
Future<void> importFlow(
  BuildContext context,
  List<String> uris, {
  String? folderId,
  bool fromCamera = false,
}) async {
  final vault = session.vault;
  ImportReport report;
  try {
    report = await vault.importUris(uris, folderId: folderId);
  } catch (e) {
    if (context.mounted) snack(context, 'Import failed: ${_clean(e)}');
    return;
  }
  if (fromCamera) {
    // camera temp file lives in our cache only; it never touched the public gallery
    await Native.purgeCapture();
  }
  if (!context.mounted) return;

  if (report.errors.isNotEmpty) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Some files failed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        content: SingleChildScrollView(child: Text(report.errors.join('\n'))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
    if (!context.mounted) return;
  }
  snack(context, report.summary());

  if (fromCamera || report.verifiedSources.isEmpty) return;

  final n = _label(report.verifiedSources.length).files;
  final del = await confirmDialog(
    context,
    title: 'Delete originals?',
    body: '$n copied to the vault and verified. Remove the originals from your gallery? '
        'Android will ask you to confirm.',
    confirm: 'Delete originals',
    cancel: 'Keep',
  );
  if (!del || !context.mounted) return;

  try {
    final r = await session.external(() => Native.deleteOriginals(report.verifiedSources));
    if (!context.mounted) return;
    switch (r.status) {
      case 'deleted':
        snack(context, 'Originals deleted');
      case 'cancelled':
        snack(context, 'Originals kept');
      default:
        snack(context, r.message ?? 'Couldn’t delete the originals. Remove them from your gallery app.');
    }
  } catch (e) {
    if (context.mounted) snack(context, 'Couldn’t delete the originals: ${_clean(e)}');
  }
}

// ---------------------------------------------------------------- item actions

Future<bool> deleteItemsFlow(BuildContext context, List<String> ids) async {
  final ok = await confirmDialog(
    context,
    title: 'Delete ${_label(ids.length).files}?',
    body: 'This permanently removes them from the vault. It can’t be undone.',
    confirm: 'Delete',
  );
  if (!ok || !context.mounted) return false;
  try {
    await session.vault.deleteItems(ids);
    return true;
  } catch (e) {
    if (context.mounted) snack(context, 'Delete failed: ${_clean(e)}');
    return false;
  }
}

Future<bool> restoreItemsFlow(BuildContext context, List<String> ids) async {
  final ok = await confirmDialog(
    context,
    title: 'Restore ${_label(ids.length).files}?',
    body: 'They’ll be saved to your gallery (Pictures/Restored or Movies/Restored) and removed from the vault '
        'only after the copy is verified.',
    confirm: 'Restore',
  );
  if (!ok || !context.mounted) return false;
  try {
    final n = await session.vault.restoreItems(ids);
    if (!context.mounted) return n > 0;
    if (n == ids.length) {
      snack(context, 'Restored ${_label(n).files} to your gallery');
    } else if (n > 0) {
      snack(context, 'Restored $n of ${ids.length}. The rest stay in the vault.');
    } else {
      snack(context, 'Couldn’t restore. Files stay in the vault.');
    }
    return n > 0;
  } catch (e) {
    if (context.mounted) snack(context, 'Restore failed: ${_clean(e)}');
    return false;
  }
}

Future<void> shareItemsFlow(BuildContext context, List<String> ids) async {
  session.suppressFor(const Duration(seconds: 90));
  try {
    await session.vault.shareItems(ids);
  } catch (e) {
    if (context.mounted) snack(context, 'Share failed: ${_clean(e)}');
  }
}

class FolderChoice {
  const FolderChoice(this.id);
  final String? id; // null = library (no folder)
}

Future<FolderChoice?> pickFolder(BuildContext context) {
  return showModalBottomSheet<FolderChoice>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final folders = session.vault.folders;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text('Move to', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              for (final f in folders) _sheetRow2(ctx, Icons.folder_outlined, f.name, FolderChoice(f.id)),
              InkWell(
                onTap: () async {
                  final name = await promptText(ctx, title: 'New folder', hint: 'Folder name', confirm: 'Create');
                  if (name == null || !ctx.mounted) return;
                  final err = session.vault.validateFolderName(name);
                  if (err != null) {
                    snack(ctx, err);
                    return;
                  }
                  final f = await session.vault.createFolder(name);
                  if (ctx.mounted) Navigator.pop(ctx, FolderChoice(f.id));
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 15),
                  child: Row(
                    children: [
                      Icon(Icons.create_new_folder_outlined, size: 24),
                      SizedBox(width: 18),
                      Text('New folder…', style: TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _sheetRow2(BuildContext ctx, IconData icon, String label, FolderChoice value) {
  return InkWell(
    onTap: () => Navigator.pop(ctx, value),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
      child: Row(
        children: [
          Icon(icon, size: 24),
          const SizedBox(width: 18),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 16), overflow: TextOverflow.ellipsis)),
        ],
      ),
    ),
  );
}

Future<bool> moveItemsFlow(BuildContext context, List<String> ids) async {
  final dest = await pickFolder(context);
  if (dest == null || !context.mounted) return false;
  try {
    await session.vault.moveItems(ids, dest.id);
    if (context.mounted) {
      final name = session.vault.folderById(dest.id)?.name ?? 'Library';
      snack(context, 'Moved ${_label(ids.length).files} to $name');
    }
    return true;
  } catch (e) {
    if (context.mounted) snack(context, 'Move failed: ${_clean(e)}');
    return false;
  }
}
