import 'package:flutter/services.dart';

class PinResult {
  const PinResult({required this.ok, required this.lockMs, required this.left, this.dev = false});
  final bool ok;
  final bool dev;
  final int lockMs;
  final int left;
}

class DeleteResult {
  const DeleteResult(this.status, this.message);

  /// deleted | cancelled | failed | unsupported
  final String status;
  final String? message;
}

/// Thin typed wrapper over the Kotlin side (crypto, storage, pickers, sharing).
class Native {
  static const MethodChannel _ch = MethodChannel('com.lucenq.tictactoe/native');
  static void Function()? onShared;

  static void init() {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'shared') onShared?.call();
      return null;
    });
  }

  // ---- PIN / settings / index ----
  static Future<bool> hasPin() async => (await _ch.invokeMethod<bool>('hasPin')) ?? false;

  static Future<void> setPin(String pin) => _ch.invokeMethod<void>('setPin', {'pin': pin});

  static Future<PinResult> verifyPin(String pin, {bool dev = false}) async {
    final m = await _ch.invokeMapMethod<String, dynamic>('verifyPin', {'pin': pin, 'dev': dev});
    return PinResult(
      ok: m?['ok'] == true,
      lockMs: (m?['lockMs'] as num?)?.toInt() ?? 0,
      left: (m?['left'] as num?)?.toInt() ?? 0,
      dev: m?['dev'] == true,
    );
  }

  static Future<String?> getSettings() => _ch.invokeMethod<String>('getSettings');
  static Future<void> saveSettings(String json) => _ch.invokeMethod<void>('saveSettings', {'json': json});
  static Future<String?> loadIndex() => _ch.invokeMethod<String>('loadIndex');
  static Future<void> saveIndex(String json) => _ch.invokeMethod<void>('saveIndex', {'json': json});
  static Future<void> cleanupOrphans(List<String> ids) => _ch.invokeMethod<void>('cleanupOrphans', {'ids': ids});
  static Future<void> deleteBlobs(List<String> ids) => _ch.invokeMethod<void>('deleteBlobs', {'ids': ids});
  static Future<void> wipeAll() => _ch.invokeMethod<void>('wipeAll');

  // ---- media ----
  static Future<Uint8List?> getThumb(String id) => _ch.invokeMethod<Uint8List>('getThumb', {'id': id});

  static Future<Uint8List?> getPhoto(String id, String mime, int maxSide) =>
      _ch.invokeMethod<Uint8List>('getPhoto', {'id': id, 'mime': mime, 'maxSide': maxSide});

  static Future<List<String>> pick(String kind) async =>
      (await _ch.invokeListMethod<String>('pick', {'kind': kind})) ?? <String>[];

  static Future<String?> capture(String kind) => _ch.invokeMethod<String>('capture', {'kind': kind});
  static Future<void> purgeCapture() => _ch.invokeMethod<void>('purgeCapture');

  static Future<List<Map<dynamic, dynamic>>> importUris(List<String> uris, List<String> known) async =>
      (await _ch.invokeListMethod<Map<dynamic, dynamic>>('importUris', {'uris': uris, 'known': known})) ??
      <Map<dynamic, dynamic>>[];

  static Future<DeleteResult> deleteOriginals(List<String> uris) async {
    final m = await _ch.invokeMapMethod<String, dynamic>('deleteOriginals', {'uris': uris});
    return DeleteResult((m?['status'] as String?) ?? 'failed', m?['message'] as String?);
  }

  static Future<List<String>> restore(List<Map<String, String>> items) async =>
      (await _ch.invokeListMethod<String>('restore', {'items': items})) ?? <String>[];

  static Future<void> share(List<Map<String, String>> items) => _ch.invokeMethod<void>('share', {'items': items});
  static Future<void> clearShareCache() => _ch.invokeMethod<void>('clearShareCache');
  static Future<void> setSecure(bool on) => _ch.invokeMethod<void>('setSecure', {'on': on});

  static Future<List<String>> takeShared() async =>
      (await _ch.invokeListMethod<String>('takeShared')) ?? <String>[];
}

/// Small in-memory LRU for decrypted thumbnails. Cleared whenever the vault locks.
class ThumbCache {
  static final Map<String, Uint8List?> _map = <String, Uint8List?>{};
  static final Map<String, Future<Uint8List?>> _pending = <String, Future<Uint8List?>>{};

  static bool has(String id) => _map.containsKey(id);
  static Uint8List? peek(String id) => _map[id];

  static Future<Uint8List?> load(String id) {
    final p = _pending[id];
    if (p != null) return p;
    final f = Native.getThumb(id).then<Uint8List?>((v) {
      _map[id] = v;
      if (_map.length > 400) _map.remove(_map.keys.first);
      _pending.remove(id);
      return v;
    }).catchError((Object _) {
      _pending.remove(id);
      return null;
    });
    _pending[id] = f;
    return f;
  }

  static void clear() {
    _map.clear();
    _pending.clear();
  }
}
