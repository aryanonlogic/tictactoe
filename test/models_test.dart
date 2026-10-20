import 'package:flutter_test/flutter_test.dart';
import 'package:tictactoe/format.dart';
import 'package:tictactoe/vault/models.dart';

void main() {
  test('VaultItem survives a JSON round trip', () {
    final it = VaultItem(
      id: 'a' * 32,
      name: 'IMG_0001.jpg',
      mime: 'image/jpeg',
      isVideo: false,
      size: 1234,
      hash: 'b' * 64,
      added: 42,
      folder: 'f1',
      durMs: 0,
    );
    final back = VaultItem.fromJson(it.toJson());
    expect(back.id, it.id);
    expect(back.name, it.name);
    expect(back.folder, 'f1');
    expect(back.isVideo, isFalse);
    expect(back.hash, it.hash);
  });

  test('VaultFolder round trip', () {
    final f = VaultFolder(id: 'f1', name: 'Trips', created: 7);
    final back = VaultFolder.fromJson(f.toJson());
    expect(back.name, 'Trips');
    expect(back.created, 7);
  });

  test('ImportReport summary', () {
    final r = ImportReport()
      ..imported = 2
      ..duplicates = 1;
    r.errors.add('x');
    expect(r.summary(), 'Imported 2 · 1 already in vault · 1 failed');
    expect(ImportReport().summary(), 'Nothing imported');
  });

  test('formatters', () {
    expect(fmtSize(512), '512 B');
    expect(fmtSize(2 * 1024 * 1024), '2.0 MB');
    expect(fmtDur(134000), '2:14');
    expect(fmtDur(28000), '0:28');
  });
}
