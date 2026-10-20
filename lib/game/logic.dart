import 'dart:math';

enum Mark { none, x, o }

const List<List<int>> kLines = <List<int>>[
  [0, 1, 2], [3, 4, 5], [6, 7, 8], // rows
  [0, 3, 6], [1, 4, 7], [2, 5, 8], // columns
  [0, 4, 8], [2, 4, 6], // diagonals
];

Mark otherMark(Mark m) => m == Mark.x ? Mark.o : Mark.x;

List<int>? winningLine(List<Mark> b) {
  for (final l in kLines) {
    final m = b[l[0]];
    if (m != Mark.none && m == b[l[1]] && m == b[l[2]]) return l;
  }
  return null;
}

bool boardFull(List<Mark> b) => !b.contains(Mark.none);

const List<int> _order = <int>[4, 0, 2, 6, 8, 1, 3, 5, 7];

/// Perfect play (minimax). Never loses.
int bestMove(List<Mark> board, Mark ai) {
  final b = List<Mark>.of(board);
  var best = -1000;
  var move = -1;
  for (final i in _order) {
    if (b[i] != Mark.none) continue;
    b[i] = ai;
    final s = _minimax(b, false, ai, 1);
    b[i] = Mark.none;
    if (s > best) {
      best = s;
      move = i;
    }
  }
  return move;
}

int _minimax(List<Mark> b, bool aiTurn, Mark ai, int depth) {
  final w = winningLine(b);
  if (w != null) return b[w[0]] == ai ? 10 - depth : depth - 10;
  if (boardFull(b)) return 0;
  var best = aiTurn ? -1000 : 1000;
  for (var i = 0; i < 9; i++) {
    if (b[i] != Mark.none) continue;
    b[i] = aiTurn ? ai : otherMark(ai);
    final s = _minimax(b, !aiTurn, ai, depth + 1);
    b[i] = Mark.none;
    best = aiTurn ? max(best, s) : min(best, s);
  }
  return best;
}

int randomMove(List<Mark> b, Random r) {
  final empty = <int>[for (var i = 0; i < 9; i++) if (b[i] == Mark.none) i];
  return empty[r.nextInt(empty.length)];
}

/// easy: mostly random, normal: sometimes random, hard: perfect.
int aiMove(List<Mark> board, Mark ai, String difficulty, Random rnd) {
  final mistake = switch (difficulty) {
    'easy' => 0.65,
    'normal' => 0.25,
    _ => 0.0,
  };
  if (mistake > 0 && rnd.nextDouble() < mistake) return randomMove(board, rnd);
  return bestMove(board, ai);
}
