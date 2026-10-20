import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../format.dart';
import '../native.dart';
import '../ui.dart';
import 'actions.dart';
import 'models.dart';
import 'settings_screen.dart';
import 'vault_flow.dart';
import 'viewer.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key, this.pendingImport = const <String>[]});

  final List<String> pendingImport;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    if (widget.pendingImport.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) importFlow(context, widget.pendingImport);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vault = session.vault;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _tab,
              children: const [LibraryView(), FoldersView()],
            ),
          ),
          ListenableBuilder(
            listenable: vault,
            builder: (context, _) {
              if (vault.busy == null) return const SizedBox.shrink();
              return Positioned.fill(
                child: AbsorbPointer(
                  child: ColoredBox(
                    color: const Color(0xD9FFFFFF),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2, color: kInk),
                          ),
                          const SizedBox(height: 16),
                          Text(vault.busy!, style: const TextStyle(fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          height: 60,
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: kLine))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navIcon(Icons.image_outlined, Icons.image, 0),
              _navIcon(Icons.folder_outlined, Icons.folder, 1),
              IconButton(
                onPressed: () => Navigator.of(context).push<void>(fadeRoute<void>(const SettingsScreen())),
                icon: const Icon(Icons.settings_outlined, color: kSub),
                tooltip: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navIcon(IconData off, IconData on, int i) {
    return IconButton(
      onPressed: () => setState(() => _tab = i),
      icon: Icon(_tab == i ? on : off, color: _tab == i ? kInk : kSub),
    );
  }
}

// =================================================================== Library

/// Photos / Videos grid. With [folder] it shows only that folder.
class LibraryView extends StatefulWidget {
  const LibraryView({super.key, this.folder});

  final VaultFolder? folder;

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  bool _videos = false;
  final Set<String> _sel = <String>{};

  bool get _selecting => _sel.isNotEmpty;

  List<VaultItem> _visible() =>
      session.vault.itemsIn(widget.folder?.id).where((e) => e.isVideo == _videos).toList();

  void _toggle(String id) {
    setState(() {
      if (!_sel.remove(id)) _sel.add(id);
    });
  }

  Future<void> _run(Future<bool> Function(List<String> ids) f) async {
    final ids = _sel.toList();
    final ok = await f(ids);
    if (!mounted) return;
    if (ok) setState(_sel.clear);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session.vault,
      builder: (context, _) {
        final items = _visible();
        _sel.removeWhere((id) => session.vault.byId(id) == null);
        final folder = widget.folder == null ? null : session.vault.folderById(widget.folder!.id);
        final total = session.vault.itemsIn(widget.folder?.id).length;
        return Column(
          children: [
            _selecting ? _selectionBar() : _header(folder, total),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Segmented<bool>(
                value: _videos,
                options: const {false: 'Photos', true: 'Videos'},
                onChanged: (v) => setState(() {
                  _videos = v;
                  _sel.clear();
                }),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Text(
                          _videos ? 'No videos here yet.\nTap + to add some.' : 'No photos here yet.\nTap + to add some.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: kSub, height: 1.4),
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) => _tile(items, i),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _header(VaultFolder? folder, int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
      child: Row(
        children: [
          if (widget.folder != null)
            IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back_ios_new, size: 20))
          else
            const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  folder?.name ?? 'Vault',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  folder == null ? 'Your private space.' : '$total ${total == 1 ? 'item' : 'items'}',
                  style: const TextStyle(fontSize: 13, color: kSub),
                ),
              ],
            ),
          ),
          Material(
            color: kMist,
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: () => addFlow(context, folderId: widget.folder?.id),
              icon: const Icon(Icons.add),
              tooltip: 'Add',
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectionBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 8, 0),
      child: Row(
        children: [
          IconButton(onPressed: () => setState(_sel.clear), icon: const Icon(Icons.close)),
          Expanded(
            child: Text('${_sel.length} selected', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            onPressed: () => _run((ids) => moveItemsFlow(context, ids)),
            icon: const Icon(Icons.drive_file_move_outlined),
            tooltip: 'Move',
          ),
          IconButton(
            onPressed: () async {
              final ids = _sel.toList();
              await shareItemsFlow(context, ids);
            },
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share',
          ),
          IconButton(
            onPressed: () => _run((ids) => restoreItemsFlow(context, ids)),
            icon: const Icon(Icons.unarchive_outlined),
            tooltip: 'Restore to gallery',
          ),
          IconButton(
            onPressed: () => _run((ids) => deleteItemsFlow(context, ids)),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }

  Widget _tile(List<VaultItem> items, int i) {
    final it = items[i];
    final selected = _sel.contains(it.id);
    return GestureDetector(
      key: ValueKey(it.id),
      onTap: () {
        if (_selecting) {
          _toggle(it.id);
        } else {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => ViewerScreen(items: items, index: i)),
          );
        }
      },
      onLongPress: () => _toggle(it.id),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ThumbImage(id: it.id, video: it.isVideo),
            if (it.isVideo)
              Positioned(
                left: 6,
                bottom: 5,
                child: Text(
                  fmtDur(it.durMs),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 4, color: Color(0xAA000000))],
                  ),
                ),
              ),
            if (selected) ...[
              const ColoredBox(color: Color(0x55000000)),
              const Positioned(top: 6, right: 6, child: Icon(Icons.check_circle, color: Colors.white, size: 22)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Decrypted thumbnail with a neutral placeholder.
class ThumbImage extends StatelessWidget {
  const ThumbImage({super.key, required this.id, required this.video});

  final String id;
  final bool video;

  @override
  Widget build(BuildContext context) {
    final cached = ThumbCache.peek(id);
    if (cached != null) return _img(cached);
    return FutureBuilder<Object?>(
      future: ThumbCache.load(id),
      builder: (context, snap) {
        final data = ThumbCache.peek(id);
        if (data != null) return _img(data);
        return ColoredBox(
          color: const Color(0xFFE4E4E1),
          child: video ? const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34)) : null,
        );
      },
    );
  }

  Widget _img(Uint8List bytes) => Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
          if (video) const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34)),
        ],
      );
}

// =================================================================== Folders

class FoldersView extends StatelessWidget {
  const FoldersView({super.key});

  Future<void> _create(BuildContext context) async {
    final name = await promptText(context, title: 'New folder', hint: 'Folder name', confirm: 'Create');
    if (name == null || !context.mounted) return;
    final err = session.vault.validateFolderName(name);
    if (err != null) {
      snack(context, err);
      return;
    }
    await session.vault.createFolder(name);
  }

  Future<void> _rename(BuildContext context, VaultFolder f) async {
    final name = await promptText(context, title: 'Rename folder', initial: f.name);
    if (name == null || !context.mounted) return;
    final err = session.vault.validateFolderName(name, exceptId: f.id);
    if (err != null) {
      snack(context, err);
      return;
    }
    await session.vault.renameFolder(f.id, name);
  }

  Future<void> _delete(BuildContext context, VaultFolder f) async {
    final n = session.vault.countIn(f.id);
    if (n == 0) {
      final ok = await confirmDialog(context, title: 'Delete “${f.name}”?', confirm: 'Delete');
      if (ok) await session.vault.deleteFolder(f.id, deleteFiles: false);
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('Delete “${f.name}”?', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        content: Text('It contains $n ${n == 1 ? 'file' : 'files'}.', style: const TextStyle(color: kSub)),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'keep'), child: const Text('Delete folder, keep files')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: const Text('Delete folder and files', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
    if (choice == null) return;
    await session.vault.deleteFolder(f.id, deleteFiles: choice == 'all');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session.vault,
      builder: (context, _) {
        final folders = List<VaultFolder>.of(session.vault.folders)
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Folders', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.5)),
                  ),
                  Material(
                    color: kMist,
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: () => _create(context),
                      icon: const Icon(Icons.create_new_folder_outlined),
                      tooltip: 'New folder',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: folders.isEmpty
                  ? const Center(
                      child: Text('No folders yet.\nTap the folder button to create one.',
                          textAlign: TextAlign.center, style: TextStyle(color: kSub, height: 1.4)),
                    )
                  : ListView.separated(
                      itemCount: folders.length,
                      separatorBuilder: (context, i) => const Divider(indent: 64),
                      itemBuilder: (context, i) {
                        final f = folders[i];
                        final n = session.vault.countIn(f.id);
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                          leading: const Icon(Icons.folder_outlined, size: 26),
                          title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Text('$n ${n == 1 ? 'item' : 'items'}', style: const TextStyle(color: kSub)),
                          trailing: PopupMenuButton<String>(
                            color: Colors.white,
                            surfaceTintColor: Colors.transparent,
                            icon: const Icon(Icons.more_horiz, color: kSub),
                            onSelected: (v) {
                              if (v == 'rename') _rename(context, f);
                              if (v == 'delete') _delete(context, f);
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'rename', child: Text('Rename')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                          onTap: () => Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(builder: (_) => FolderPage(folder: f)),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class FolderPage extends StatelessWidget {
  const FolderPage({super.key, required this.folder});

  final VaultFolder folder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: LibraryView(folder: folder)),
    );
  }
}
