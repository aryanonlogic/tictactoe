
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../format.dart';
import '../native.dart';
import '../ui.dart';
import 'actions.dart';
import 'models.dart';

/// Full-screen viewer. Photos: pinch-zoom. Videos: native Media3 ExoPlayer decrypting on the fly.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.items, required this.index});

  final List<VaultItem> items;
  final int index;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late final List<VaultItem> _items = List<VaultItem>.of(widget.items);
  late int _i = widget.index;
  late final PageController _pc = PageController(initialPage: widget.index);

  bool get _video => _items.isNotEmpty && _items[_i].isVideo;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _afterRemove() {
    if (_items.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      if (_i >= _items.length) _i = _items.length - 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pc.hasClients) _pc.jumpToPage(_i);
    });
  }

  Future<void> _delete() async {
    final it = _items[_i];
    final ok = await deleteItemsFlow(context, <String>[it.id]);
    if (!mounted || !ok) return;
    _items.removeAt(_i);
    _afterRemove();
  }

  Future<void> _restore() async {
    final it = _items[_i];
    final ok = await restoreItemsFlow(context, <String>[it.id]);
    if (!mounted || !ok) return;
    _items.removeAt(_i);
    _afterRemove();
  }

  Future<void> _rename() async {
    final it = _items[_i];
    final name = await promptText(context, title: 'Rename', initial: it.name);
    if (name == null || !mounted) return;
    await session.vault.renameItem(it.id, name);
    if (mounted) setState(() {});
  }

  void _details() {
    final it = _items[_i];
    showGlassSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              _kv('Name', it.name),
              _kv('Type', it.mime),
              _kv('Size', fmtSize(it.size)),
              if (it.isVideo) _kv('Duration', fmtDur(it.durMs)),
              _kv('Added', fmtDate(it.added)),
              _kv('Folder', session.vault.folderById(it.folder)?.name ?? 'Library'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 90, child: Text(k, style: const TextStyle(color: kSub))),
            Expanded(child: Text(v)),
          ],
        ),
      );

  void _more() {
    showGlassSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RowTile(
              icon: Icons.unarchive_outlined,
              title: 'Restore to gallery',
              trailing: const SizedBox.shrink(),
              onTap: () {
                Navigator.pop(ctx);
                _restore();
              },
            ),
            RowTile(
              icon: Icons.edit_outlined,
              title: 'Rename',
              trailing: const SizedBox.shrink(),
              onTap: () {
                Navigator.pop(ctx);
                _rename();
              },
            ),
            RowTile(
              icon: Icons.info_outline,
              title: 'Details',
              trailing: const SizedBox.shrink(),
              onTap: () {
                Navigator.pop(ctx);
                _details();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const Scaffold();
    final dark = _video;
    final fg = dark ? Colors.white : kInk;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: dark ? Colors.black : Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back_ios_new, size: 20, color: fg),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_video)
                          IconButton(
                            onPressed: _i > 0
                                ? () => _pc.animateToPage(_i - 1,
                                    duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
                                : null,
                            icon: Icon(Icons.chevron_left, color: _i > 0 ? fg : Colors.white24),
                          ),
                        Text('${_i + 1} / ${_items.length}', style: TextStyle(color: fg, fontSize: 15)),
                        if (_video)
                          IconButton(
                            onPressed: _i < _items.length - 1
                                ? () => _pc.animateToPage(_i + 1,
                                    duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
                                : null,
                            icon: Icon(Icons.chevron_right, color: _i < _items.length - 1 ? fg : Colors.white24),
                          ),
                      ],
                    ),
                  ),
                  IconButton(onPressed: _more, icon: Icon(Icons.more_vert, color: fg)),
                ],
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pc,
                  physics: _video ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
                  itemCount: _items.length,
                  onPageChanged: (i) => setState(() => _i = i),
                  itemBuilder: (context, i) {
                    final it = _items[i];
                    if (it.isVideo) {
                      return i == _i ? VideoSurface(key: ValueKey(it.id), id: it.id) : const SizedBox.shrink();
                    }
                    return PhotoPage(key: ValueKey(it.id), item: it);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: GlassPanel(
                  radius: 28,
                  blur: 18,
                  dark: dark,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _bar(Icons.delete_outline, 'Delete', fg, _delete),
                    _bar(Icons.drive_file_move_outlined, 'Move', fg, () => moveItemsFlow(context, <String>[_items[_i].id])),
                    _bar(Icons.ios_share, 'Share', fg, () => shareItemsFlow(context, <String>[_items[_i].id])),
                    _bar(Icons.more_horiz, 'More', fg, _more),
                  ],
                ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(IconData icon, String label, Color fg, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg, size: 24),
            const SizedBox(height: 3),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 11)),
          ],
        ),
      ),
    ),
    );
  }
}

class PhotoPage extends StatefulWidget {
  const PhotoPage({super.key, required this.item});

  final VaultItem item;

  @override
  State<PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<PhotoPage> {
  late final Future<Uint8List?> _f = Native.getPhoto(widget.item.id, widget.item.mime, 2048);
  final TransformationController _tc = TransformationController();
  bool _zoomed = false;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _onScale() {
    final z = _tc.value.getMaxScaleOnAxis() > 1.02;
    if (z != _zoomed) setState(() => _zoomed = z);
  }

  void _doubleTap(Size size) {
    if (_zoomed) {
      _tc.value = Matrix4.identity();
    } else {
      const z = 2.5;
      final m = Matrix4.diagonal3Values(z, z, 1);
      m.setTranslationRaw(-size.width * (z - 1) / 2, -size.height * (z - 1) / 2, 0);
      _tc.value = m;
    }
    _onScale();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: kInk)),
          );
        }
        final bytes = snap.data;
        if (bytes == null) {
          return const Center(child: Icon(Icons.broken_image_outlined, size: 40, color: kSub));
        }
        return LayoutBuilder(
          builder: (context, c) => GestureDetector(
            onDoubleTap: () => _doubleTap(Size(c.maxWidth, c.maxHeight)),
            child: InteractiveViewer(
              transformationController: _tc,
              minScale: 1,
              maxScale: 5,
              panEnabled: _zoomed,
              onInteractionEnd: (_) => _onScale(),
              child: SizedBox(
                width: c.maxWidth,
                height: c.maxHeight,
                child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Native Media3 PlayerView (see VideoViewFactory.kt).
class VideoSurface extends StatelessWidget {
  const VideoSurface({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: 'ttt/video',
      creationParams: <String, dynamic>{'id': id},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
