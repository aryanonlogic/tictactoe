// UI audit. Runs as part of `flutter test` (and tool/check.sh).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tictactoe/app_state.dart';
import 'package:tictactoe/game/game_screen.dart';
import 'package:tictactoe/game/painters.dart';
import 'package:tictactoe/splash.dart';
import 'package:tictactoe/ui.dart';
import 'package:tictactoe/vault/models.dart';
import 'package:tictactoe/vault/pin_screen.dart';
import 'package:tictactoe/vault/settings_screen.dart';
import 'package:tictactoe/vault/vault_screen.dart';
import 'package:tictactoe/vault/viewer.dart';

const MethodChannel _native = MethodChannel('com.lucenq.tictactoe/native');

void _mockChannels() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(_native, (call) async {
    switch (call.method) {
      case 'takeShared':
      case 'pick':
      case 'restore':
        return <Object?>[];
      case 'hasPin':
        return false;
      case 'verifyPin':
        final args = call.arguments as Map<Object?, Object?>;
        if (args['dev'] == true && args['pin'] == '920000') {
          return <String, Object?>{'ok': true, 'dev': true, 'lockMs': 0, 'left': 0};
        }
        return <String, Object?>{'ok': false, 'lockMs': 0, 'left': 4};
      default:
        return null;
    }
  });
  m.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
}

void _seed() {
  session = VaultSession(AppSettings());
  session.vault.items = <VaultItem>[
    for (var i = 0; i < 7; i++)
      VaultItem(
        id: i.toRadixString(16).padLeft(32, 'a'),
        name: 'IMG_$i.jpg',
        mime: 'image/jpeg',
        isVideo: false,
        size: 1000 + i,
        hash: 'hash$i',
        added: i,
        folder: i == 0 ? 'f1' : 'pictures',
      ),
  ];
  session.vault.folders = <VaultFolder>[
    VaultFolder(id: 'pictures', name: 'Pictures', created: 0),
    VaultFolder(id: 'videos', name: 'Videos', created: 0),
    VaultFolder(id: 'f1', name: 'A very long folder name that must be ellipsized properly on narrow phones', created: 0),
  ];
}

Widget _app(Widget home, double textScale) {
  return MaterialApp(
    theme: buildTheme(),
    navigatorKey: navKey,
    home: home,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
  );
}

void _size(WidgetTester t, Size s) {
  t.view.physicalSize = s;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Rect _boardRect(WidgetTester t) =>
    t.getRect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BoardPainter));

Offset _cell(Rect r, int i) =>
    Offset(r.left + (i % 3 + 0.5) * r.width / 3, r.top + (i ~/ 3 + 0.5) * r.height / 3);

Finder get _marks => find.byWidgetPredicate((w) => w is CustomPaint && w.painter is MarkPainter);

int _spread(int argb) {
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  final hi = r > g ? (r > b ? r : b) : (g > b ? g : b);
  final lo = r < g ? (r < b ? r : b) : (g < b ? g : b);
  return hi - lo;
}

void main() {
  setUp(() {
    _mockChannels();
    _seed();
  });

  group('static audit', () {
    test('palette is strictly black / white / neutral grey', () {
      final bad = <String>[];
      final hex = RegExp(r'Color\(0x([0-9A-Fa-f]{8})\)');
      final named = RegExp(r'Colors\.([A-Za-z]+[0-9]*)');
      final allowedNamed = RegExp(r'^(white|black)[0-9]*$|^transparent$|^grey$');
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final f in files) {
        final s = f.readAsStringSync();
        for (final m in hex.allMatches(s)) {
          final v = int.parse(m.group(1)!, radix: 16);
          if (_spread(v) > 6) bad.add('${f.path}: ${m.group(0)} is not neutral');
        }
        for (final m in named.allMatches(s)) {
          if (!allowedNamed.hasMatch(m.group(1)!)) bad.add('${f.path}: ${m.group(0)}');
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });

    test('release manifest has no internet permission', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest.contains('android.permission.INTERNET'), isFalse);
    });

    test('no dependencies beyond Flutter itself', () {
      final pub = File('pubspec.yaml').readAsStringSync();
      final block = pub.split('dev_dependencies:').first.split('dependencies:').last;
      final keys = RegExp(r'^  ([a-z_0-9]+):', multiLine: true).allMatches(block).map((m) => m.group(1)!).toList();
      expect(keys, <String>['flutter']);
    });
  });

  final screens = <String, Widget Function()>{
    'splash': () => const SplashScreen(),
    'game': () => const GameScreen(),
    'pin-setup': () => const PinScreen(mode: PinMode.setup),
    'pin-unlock': () => const PinScreen(mode: PinMode.unlock),
    'settings': () => const SettingsScreen(),
    'vault': () => const VaultScreen(),
    'viewer': () => ViewerScreen(items: session.vault.items.take(3).toList(), index: 0),
  };
  const sizes = <Size>[Size(320, 568), Size(360, 740), Size(411, 891)];

  group('layout audit', () {
    for (final e in screens.entries) {
      for (final size in sizes) {
        for (final scale in <double>[1.0, 1.5]) {
          testWidgets('${e.key} @ ${size.width.toInt()}x${size.height.toInt()} text x$scale', (tester) async {
            _size(tester, size);
            await tester.pumpWidget(_app(e.value(), scale));
            await tester.pump(const Duration(milliseconds: 1600));
            await tester.pump(const Duration(milliseconds: 600));
            expect(tester.takeException(), isNull, reason: 'overflow or exception on ${e.key}');

            for (final b in tester.widgetList<IconButton>(find.byType(IconButton))) {
              final s = tester.getSize(find.byWidget(b));
              expect(s.width >= 44 && s.height >= 44, isTrue, reason: 'tap target ${s.width}x${s.height} on ${e.key}');
            }
            for (final t in tester.widgetList<Text>(find.byType(Text))) {
              final fs = t.style?.fontSize ?? 14;
              expect(fs >= 11, isTrue, reason: 'font $fs too small on ${e.key}: ${t.data}');
            }
          });
        }
      }
    }
  });

  group('functional audit', () {
    testWidgets('tap places X and the AI answers', (tester) async {
      _size(tester, const Size(360, 740));
      await tester.pumpWidget(_app(const GameScreen(), 1));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(_cell(_boardRect(tester), 4));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(tester.takeException(), isNull);
      expect(_marks, findsNWidgets(2));
      expect(find.text('Your move'), findsOneWidget);
    });

    testWidgets('2-player win shows result overlay; Restart clears the board', (tester) async {
      _size(tester, const Size(360, 740));
      session.settings.mode = 'two';
      await tester.pumpWidget(_app(const GameScreen(), 1));
      await tester.pump(const Duration(milliseconds: 100));
      final r = _boardRect(tester);
      for (final c in <int>[0, 3, 1, 4, 2]) {
        await tester.tapAt(_cell(r, c));
        await tester.pump(const Duration(milliseconds: 450));
      }
      await tester.pump(const Duration(milliseconds: 3000));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(tester.takeException(), isNull);
      expect(find.text('Restart'), findsOneWidget);
      await tester.tap(find.text('Restart'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Restart'), findsNothing);
      expect(_marks, findsNothing);
    });

    testWidgets('3-second hold on the center square opens the PIN screen', (tester) async {
      _size(tester, const Size(360, 740));
      await tester.pumpWidget(_app(const GameScreen(), 1));
      await tester.pump(const Duration(milliseconds: 100));
      final g = await tester.startGesture(_cell(_boardRect(tester), 4));
      await tester.pump(const Duration(milliseconds: 3100));
      await g.up();
      await tester.pumpAndSettle();
      expect(find.text('Create a PIN'), findsOneWidget);
    });

    testWidgets('a 2-second hold on the center square does not open the vault', (tester) async {
      _size(tester, const Size(360, 740));
      await tester.pumpWidget(_app(const GameScreen(), 1));
      await tester.pump(const Duration(milliseconds: 100));
      final g = await tester.startGesture(_cell(_boardRect(tester), 4));
      await tester.pump(const Duration(milliseconds: 2000));
      await g.up();
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('Create a PIN'), findsNothing);
    });

    testWidgets('920000 on the normal PIN screen is just a wrong PIN', (tester) async {
      _size(tester, const Size(360, 740));
      await tester.pumpWidget(_app(const PinScreen(mode: PinMode.unlock), 1));
      for (final d in '920000'.split('')) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Wrong PIN · 4 tries left'), findsOneWidget);
      expect(find.text('Developer PIN accepted'), findsNothing);
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('Forgot PIN -> developer PIN -> option to create a new PIN', (tester) async {
      _size(tester, const Size(360, 740));
      await tester.pumpWidget(_app(const PinScreen(mode: PinMode.unlock), 1));
      await tester.tap(find.text('Forgot PIN?'));
      await tester.pumpAndSettle();
      expect(find.text('Enter developer PIN'), findsOneWidget);
      await tester.tap(find.text('Enter developer PIN'));
      await tester.pumpAndSettle();
      expect(find.text('Developer PIN'), findsOneWidget);
      for (final d in '920000'.split('')) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Developer PIN accepted'), findsOneWidget);
      expect(find.text('Create new PIN'), findsOneWidget);
    });

    testWidgets('the developer PIN cannot be chosen as a user PIN', (tester) async {
      _size(tester, const Size(360, 740));
      await tester.pumpWidget(_app(const PinScreen(mode: PinMode.setup), 1));
      for (final d in '920000'.split('')) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Choose a less obvious PIN'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('PIN setup rejects an obvious PIN', (tester) async {
      _size(tester, const Size(360, 740));
      await tester.pumpWidget(_app(const PinScreen(mode: PinMode.setup), 1));
      for (var i = 0; i < kPinLength; i++) {
        await tester.tap(find.text('1'));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Choose a less obvious PIN'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    });
  });
}
