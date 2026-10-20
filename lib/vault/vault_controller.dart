import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../native.dart';
import 'models.dart';

class VaultController extends ChangeNotifier {
  List<VaultItem> items = <VaultItem>[];
  List<VaultFolder> folders = <VaultFolder>[];
  bool unlocked = false;
  bool _loaded = false;

  /// Non-null while a long operation runs; the UI shows a blocking scrim.
  String? busy;

  // ---------- lifecycle ----------
  Future<void> unlock() async {
    await _load();
    unlocked = true;
    unawaited(Native.setSecure(true));
    unawaited(Native.clearShareCache());
    notifyListeners();
  }

  void lock() {
    if (!unlocked && !_loaded) return;
    unlocked = false;
    _scrub();
    unawaited(Native.setSecure(false));
    notifyListeners();
  }

  void _scrub() {
    _loaded = false;
    items = <VaultItem>[];
    folders = <VaultFolder>[];
    busy = null;
    ThumbCache.clear();
  }

  Future<void> _load() async {
    final raw = await Native.loadIndex();
    var fs = <VaultFolder>[];
    var its = <VaultItem>[];
    if (raw != null && raw.isNotEmpty) {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      fs = ((m['folders'] as List?) ?? <dynamic>[])
          .map((e) => VaultFolder.fromJson(e as Map<String, dynamic>))
          .toList();
      its = ((m['items'] as List?) ?? <dynamic>[])
          .map((e) => VaultItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    var changed = false;
    if (!fs.any((f) => f.id == kPicturesFolder)) {
      fs.add(VaultFolder(id: kPicturesFolder, name: 'Pictures', created: 0));
      changed = true;
    }
    if (!fs.any((f) => f.id == kVideosFolder)) {
      fs.add(VaultFolder(id: kVideosFolder, name: 'Videos', created: 0));
      changed = true;
    }
    for (final it in its) {
      if (it.folder == null || !fs.any((f) => f.id == it.folder)) {
        it.folder = it.isVideo ? kVideosFolder : kPicturesFolder;
        changed = true;
      }
    }
    folders = fs;
    items = its;
    _loaded = true;
    if (changed) await _save();
    // Only ever clean up after an index was read successfully, so a read error can never wipe files.
    if (raw != null) await Native.cleanupOrphans(items.map((e) => e.id).toList());
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded) await _load();
  }

  Future<void> _save() => Native.saveIndex(jsonEncode(<String, dynamic>{
        'v': 1,
        'folders': folders.map((e) => e.toJson()).toList(),
        'items': items.map((e) => e.toJson()).toList(),
      }));

  void _scrubIfLocked() {
    if (!unlocked) _scrub();
  }

  Future<T> _withBusy<T>(String label, Future<T> Function() f) async {
    busy = label;
    notifyListeners();
    try {
      return await f();
    } finally {
      busy = null;
      notifyListeners();
    }
  }

  // ---------- queries ----------
  List<VaultItem> itemsIn(String? folderId) {
    final l = folderId == null ? List<VaultItem>.of(items) : items.where((e) => e.folder == folderId).toList();
    l.sort((a, b) => b.added.compareTo(a.added));
    return l;
  }

  int countIn(String folderId) => items.where((e) => e.folder == folderId).length;

  VaultItem? byId(String id) {
    for (final e in items) {
      if (e.id == id) return e;
    }
    return null;
  }

  VaultFolder? folderById(String? id) {
    if (id == null) return null;
    for (final e in folders) {
      if (e.id == id) return e;
    }
    return null;
  }

  // ---------- import ----------
  Future<ImportReport> importUris(List<String> uris, {String? folderId}) {
    return _withBusy('Importing ${uris.length} file${uris.length == 1 ? '' : 's'}…', () async {
      await _ensureLoaded();
      final report = ImportReport();
      final res = await Native.importUris(uris, items.map((e) => e.hash).toList());
      // The vault may have been locked while Kotlin worked; reload the on-disk index before merging.
      await _ensureLoaded();
      final now = DateTime.now().millisecondsSinceEpoch;
      var n = 0;
      for (final m in res) {
        if (m['ok'] == true) {
          items.add(VaultItem(
            id: m['id'] as String,
            name: (m['name'] as String?) ?? 'file',
            mime: m['mime'] as String,
            isVideo: m['type'] == 'video',
            size: (m['size'] as num).toInt(),
            hash: m['hash'] as String,
            added: now + n++,
            folder: folderId ?? (m['type'] == 'video' ? kVideosFolder : kPicturesFolder),
            durMs: (m['dur'] as num?)?.toInt() ?? 0,
          ));
          report.imported++;
          report.verifiedSources.add(m['uri'] as String);
        } else if (m['dup'] == true) {
          report.duplicates++;
        } else {
          report.errors.add('${m['name'] ?? 'file'}: ${m['error'] ?? 'unknown error'}');
        }
      }
      if (report.imported > 0) await _save();
      _scrubIfLocked();
      return report;
    });
  }

  // ---------- folders ----------
  String? validateFolderName(String name, {String? exceptId}) {
    final t = name.trim();
    if (t.isEmpty) return 'Name can’t be empty';
    final clash = folders.any((f) => f.id != exceptId && f.name.toLowerCase() == t.toLowerCase());
    return clash ? 'A folder with that name already exists' : null;
  }

  Future<VaultFolder> createFolder(String name) async {
    await _ensureLoaded();
    final f = VaultFolder(
      id: 'f${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      created: DateTime.now().millisecondsSinceEpoch,
    );
    folders.add(f);
    await _save();
    notifyListeners();
    return f;
  }

  Future<void> renameFolder(String id, String name) async {
    await _ensureLoaded();
    final f = folderById(id);
    if (f == null || isBuiltinFolder(id)) return;
    f.name = name.trim();
    await _save();
    notifyListeners();
  }

  /// Removes the folder. With [deleteFiles] its files are deleted too, otherwise they move back to the library.
  Future<void> deleteFolder(String id, {required bool deleteFiles}) {
    return _withBusy('Deleting folder…', () async {
      if (isBuiltinFolder(id)) return;
      await _ensureLoaded();
      final inside = items.where((e) => e.folder == id).toList();
      if (deleteFiles) {
        items.removeWhere((e) => e.folder == id);
      } else {
        for (final e in inside) {
          e.folder = e.isVideo ? kVideosFolder : kPicturesFolder;
        }
      }
      folders.removeWhere((f) => f.id == id);
      await _save();
      if (deleteFiles && inside.isNotEmpty) await Native.deleteBlobs(inside.map((e) => e.id).toList());
      _scrubIfLocked();
    });
  }

  // ---------- items ----------
  Future<void> moveItems(List<String> ids, String? folderId) async {
    await _ensureLoaded();
    for (final id in ids) {
      final it = byId(id);
      if (it != null) it.folder = folderId;
    }
    await _save();
    notifyListeners();
  }

  Future<void> renameItem(String id, String name) async {
    await _ensureLoaded();
    final it = byId(id);
    if (it == null) return;
    it.name = name.trim();
    await _save();
    notifyListeners();
  }

  Future<void> deleteItems(List<String> ids) {
    return _withBusy('Deleting…', () async {
      await _ensureLoaded();
      final set = ids.toSet();
      items.removeWhere((e) => set.contains(e.id));
      await _save(); // index first: a crash afterwards only leaves orphan blobs, which are cleaned up
      await Native.deleteBlobs(ids);
      _scrubIfLocked();
    });
  }

  /// Copies items into the public gallery (verified by hash), then removes them from the vault. Returns restored count.
  Future<int> restoreItems(List<String> ids) {
    return _withBusy('Restoring…', () async {
      await _ensureLoaded();
      final payload = <Map<String, String>>[];
      for (final id in ids) {
        final it = byId(id);
        if (it != null) payload.add({'id': it.id, 'name': it.name, 'mime': it.mime, 'hash': it.hash});
      }
      final ok = await Native.restore(payload);
      await _ensureLoaded();
      if (ok.isNotEmpty) {
        final set = ok.toSet();
        items.removeWhere((e) => set.contains(e.id));
        await _save();
        await Native.deleteBlobs(ok);
      }
      _scrubIfLocked();
      return ok.length;
    });
  }

  /// Restores every file to the gallery in batches of 8. Each batch is verified (hash) by the native side,
  /// removed from the vault only if it verified, and the index is saved after every batch, so an interruption
  /// never loses anything.
  Future<({int restored, int failed})> restoreAll() {
    return _withBusy('Restoring…', () async {
      await _ensureLoaded();
      final all = items.map((e) => e.id).toList();
      var restored = 0;
      var failed = 0;
      const chunkSize = 8;
      for (var i = 0; i < all.length; i += chunkSize) {
        final end = i + chunkSize > all.length ? all.length : i + chunkSize;
        final chunk = all.sublist(i, end);
        busy = 'Restoring ${i + 1}–$end of ${all.length}…';
        notifyListeners();
        await _ensureLoaded();
        final payload = <Map<String, String>>[];
        for (final id in chunk) {
          final it = byId(id);
          if (it != null) payload.add({'id': it.id, 'name': it.name, 'mime': it.mime, 'hash': it.hash});
        }
        final ok = await Native.restore(payload);
        await _ensureLoaded();
        if (ok.isNotEmpty) {
          final set = ok.toSet();
          items.removeWhere((e) => set.contains(e.id));
          await _save();
          await Native.deleteBlobs(ok);
        }
        restored += ok.length;
        failed += chunk.length - ok.length;
      }
      _scrubIfLocked();
      return (restored: restored, failed: failed);
    });
  }

  Future<void> shareItems(List<String> ids) {
    return _withBusy('Preparing…', () async {
      final payload = <Map<String, String>>[];
      for (final id in ids) {
        final it = byId(id);
        if (it != null) payload.add({'id': it.id, 'name': it.name, 'mime': it.mime});
      }
      if (payload.isNotEmpty) await Native.share(payload);
    });
  }

  Future<void> wipe() {
    return _withBusy('Clearing vault…', () async {
      await Native.wipeAll();
      items = <VaultItem>[];
      folders = <VaultFolder>[];
      ThumbCache.clear();
    });
  }
}
