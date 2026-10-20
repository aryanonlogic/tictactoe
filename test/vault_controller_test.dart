import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tictactoe/vault/models.dart';
import 'package:tictactoe/vault/vault_controller.dart';

const MethodChannel _ch = MethodChannel('com.lucenq.tictactoe/native');

Map<String, Object?> _item(String c, {required bool video, String? folder}) => <String, Object?>{
      'id': c * 32,
      'name': '$c.file',
      'mime': video ? 'video/mp4' : 'image/jpeg',
      'video': video,
      'size': 1,
      'hash': 'h$c',
      'added': 1,
      'folder': folder,
      'dur': 0,
    };

Map<String, Object?> _imp(String c, String type) => <String, Object?>{
      'ok': true,
      'uri': 'u-$c',
      'name': '$c.file',
      'id': c * 32,
      'mime': type == 'video' ? 'video/mp4' : 'image/jpeg',
      'type': type,
      'size': 10,
      'hash': 'h$c',
      'dur': 0,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String? index;
  String? saved;
  List<Object?> importResult = <Object?>[];

  setUp(() {
    index = null;
    saved = null;
    importResult = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_ch, (call) async {
      switch (call.method) {
        case 'loadIndex':
          return index;
        case 'saveIndex':
          saved = (call.arguments as Map<Object?, Object?>)['json'] as String;
          index = saved;
          return true;
        case 'importUris':
          return importResult;
        default:
          return null;
      }
    });
  });

  test('an empty vault gets the two default folders', () async {
    final v = VaultController();
    await v.unlock();
    expect(v.folders.map((f) => f.id).toList(), <String>[kPicturesFolder, kVideosFolder]);
    expect(saved, isNotNull);
  });

  test('items without a folder are filed by type', () async {
    index = jsonEncode(<String, Object?>{
      'v': 1,
      'folders': <Object?>[],
      'items': <Object?>[_item('a', video: false), _item('b', video: true)],
    });
    final v = VaultController();
    await v.unlock();
    expect(v.byId('a' * 32)!.folder, kPicturesFolder);
    expect(v.byId('b' * 32)!.folder, kVideosFolder);
  });

  test('imports land in Pictures / Videos unless a folder is given', () async {
    final v = VaultController();
    await v.unlock();
    importResult = <Object?>[_imp('c', 'photo'), _imp('d', 'video')];
    await v.importUris(<String>['u1', 'u2']);
    expect(v.byId('c' * 32)!.folder, kPicturesFolder);
    expect(v.byId('d' * 32)!.folder, kVideosFolder);
    final f = await v.createFolder('Trips');
    importResult = <Object?>[_imp('e', 'photo')];
    await v.importUris(<String>['u3'], folderId: f.id);
    expect(v.byId('e' * 32)!.folder, f.id);
  });

  test('built-in folders are protected; deleting a custom folder files its items back by type', () async {
    final v = VaultController();
    await v.unlock();
    await v.deleteFolder(kPicturesFolder, deleteFiles: true);
    await v.renameFolder(kPicturesFolder, 'Nope');
    expect(v.folderById(kPicturesFolder)!.name, 'Pictures');
    final f = await v.createFolder('Trips');
    importResult = <Object?>[_imp('c', 'photo'), _imp('d', 'video')];
    await v.importUris(<String>['u1', 'u2'], folderId: f.id);
    await v.deleteFolder(f.id, deleteFiles: false);
    expect(v.byId('c' * 32)!.folder, kPicturesFolder);
    expect(v.byId('d' * 32)!.folder, kVideosFolder);
    expect(v.folderById(f.id), isNull);
  });
}
