import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tictactoe/game/logic.dart';

/// Same, but the AI replies with its real [bestMove] instead of exploring every reply.
bool humanBeatsPerfectAi(List<Mark> b) {
  final w = winningLine(b);
  if (w != null) return b[w[0]] == Mark.x;
  if (boardFull(b)) return false;
  // human moves anywhere
  for (var i = 0; i < 9; i++) {
    if (b[i] != Mark.none) continue;
    b[i] = Mark.x;
    bool win;
    final w2 = winningLine(b);
    if (w2 != null) {
      win = true;
    } else if (boardFull(b)) {
      win = false;
    } else {
      final m = bestMove(b, Mark.o);
      b[m] = Mark.o;
      win = humanBeatsPerfectAi(b);
      b[m] = Mark.none;
    }
    b[i] = Mark.none;
    if (win) return true;
  }
  return false;
}

void main() {
  group('winningLine', () {
    test('detects rows, columns and diagonals', () {
      for (final l in kLines) {
        final b = List<Mark>.filled(9, Mark.none);
        for (final i in l) {
          b[i] = Mark.o;
        }
        expect(winningLine(b), l);
      }
    });

    test('empty and mixed boards have no winner', () {
      expect(winningLine(List<Mark>.filled(9, Mark.none)), isNull);
      final b = <Mark>[
        Mark.x, Mark.o, Mark.x,
        Mark.x, Mark.o, Mark.o,
        Mark.o, Mark.x, Mark.x,
      ];
      expect(winningLine(b), isNull);
      expect(boardFull(b), isTrue);
    });
  });

  group('AI', () {
    test('takes an immediate win', () {
      final b = <Mark>[
        Mark.o, Mark.o, Mark.none,
        Mark.x, Mark.x, Mark.none,
        Mark.none, Mark.none, Mark.none,
      ];
      expect(bestMove(b, Mark.o), 2);
    });

    test('blocks an immediate loss', () {
      final b = <Mark>[
        Mark.x, Mark.x, Mark.none,
        Mark.none, Mark.o, Mark.none,
        Mark.none, Mark.none, Mark.none,
      ];
      expect(bestMove(b, Mark.o), 2);
    });

    test('hard AI can never be beaten (exhaustive over every human line)', () {
      expect(humanBeatsPerfectAi(List<Mark>.filled(9, Mark.none)), isFalse);
    });

    test('easy AI always returns a legal move', () {
      final rnd = Random(7);
      for (var n = 0; n < 200; n++) {
        final b = List<Mark>.filled(9, Mark.none);
        b[rnd.nextInt(9)] = Mark.x;
        final m = aiMove(b, Mark.o, 'easy', rnd);
        expect(m, inInclusiveRange(0, 8));
        expect(b[m], Mark.none);
      }
    });
  });
}
