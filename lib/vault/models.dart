class VaultItem {
  VaultItem({
    required this.id,
    required this.name,
    required this.mime,
    required this.isVideo,
    required this.size,
    required this.hash,
    required this.added,
    this.folder,
    this.durMs = 0,
  });

  final String id;
  String name;
  final String mime;
  final bool isVideo;
  final int size;
  final String hash;
  final int added;
  final int durMs;
  String? folder;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'mime': mime,
        'video': isVideo,
        'size': size,
        'hash': hash,
        'added': added,
        'folder': folder,
        'dur': durMs,
      };

  factory VaultItem.fromJson(Map<String, dynamic> j) => VaultItem(
        id: j['id'] as String,
        name: j['name'] as String,
        mime: j['mime'] as String,
        isVideo: j['video'] as bool,
        size: (j['size'] as num).toInt(),
        hash: j['hash'] as String,
        added: (j['added'] as num).toInt(),
        folder: j['folder'] as String?,
        durMs: (j['dur'] as num?)?.toInt() ?? 0,
      );
}

class VaultFolder {
  VaultFolder({required this.id, required this.name, required this.created});

  final String id;
  String name;
  final int created;

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'name': name, 'created': created};

  factory VaultFolder.fromJson(Map<String, dynamic> j) => VaultFolder(
        id: j['id'] as String,
        name: j['name'] as String,
        created: (j['created'] as num?)?.toInt() ?? 0,
      );
}

class ImportReport {
  int imported = 0;
  int duplicates = 0;
  final List<String> errors = <String>[];

  /// Source URIs whose private copy was verified (size + SHA-256 of the decrypted blob).
  final List<String> verifiedSources = <String>[];

  String summary() {
    final parts = <String>[];
    if (imported > 0) parts.add('Imported $imported');
    if (duplicates > 0) parts.add('$duplicates already in vault');
    if (errors.isNotEmpty) parts.add('${errors.length} failed');
    return parts.isEmpty ? 'Nothing imported' : parts.join(' · ');
  }
}

/// Built-in folders. Imports are filed here automatically (photos/GIFs -> Pictures, videos -> Videos).
const String kPicturesFolder = 'pictures';
const String kVideosFolder = 'videos';

bool isBuiltinFolder(String id) => id == kPicturesFolder || id == kVideosFolder;
