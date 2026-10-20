import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../native.dart';
import '../ui.dart';
import '../vault/vault_flow.dart';
import 'logic.dart';
import 'painters.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  AppSettings get _s => session.settings;
  final Random _rnd = Random();

  List<Mark> _board = List<Mark>.filled(9, Mark.none);
  Mark _turn = Mark.x;
  final List<int> _history = <int>[];
  List<int>? _winLine;
  Mark? _winner;
  bool _over = false;
  bool _thinking = false;
  int _gameId = 0;

  late final AnimationController _lineC;
  late final AnimationController _resultC;

  // secret hold: press and hold the center square for 3 seconds
  Timer? _long;
  bool _longFired = false;
  Offset _downPos = Offset.zero;
  int? _downCell;
  bool _moved = false;
  double _boardSize = 0;

  bool get _vsAi => _s.mode == 'ai';

  @override
  void initState() {
    super.initState();
    _lineC = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    _resultC = AnimationController(vsync: this, duration: const Duration(milliseconds: 1250));
    Native.onShared = _onShared;
    WidgetsBinding.instance.addPostFrameCallback((_) => _onShared());
  }

  @override
  void dispose() {
    _long?.cancel();
    if (Native.onShared == _onShared) Native.onShared = null;
    _lineC.dispose();
    _resultC.dispose();
    super.dispose();
  }

  // ---------------- incoming share from other apps ----------------
  Future<void> _onShared() async {
    final uris = await Native.takeShared();
    if (uris.isEmpty || !mounted) return;
    navKey.currentState?.popUntil((r) => r.isFirst);
    await openVault(context, pendingImport: uris);
  }

  // ---------------- game flow ----------------
  void _newGame() {
    _gameId++;
    _resultC.reset();
    _lineC.reset();
    setState(() {
      _board = List<Mark>.filled(9, Mark.none);
      _turn = Mark.x;
      _history.clear();
      _winLine = null;
      _winner = null;
      _over = false;
      _thinking = false;
    });
  }

  void _tap(int cell) {
    if (_over || _thinking || _board[cell] != Mark.none) return;
    if (_vsAi && _turn != Mark.x) return;
    HapticFeedback.selectionClick();
    _place(cell, _turn);
  }

  void _place(int cell, Mark m) {
    setState(() {
      _board[cell] = m;
      _history.add(cell);
      _turn = otherMark(m);
    });
    final line = winningLine(_board);
    if (line != null) {
      _finish(winner: m, line: line);
    } else if (boardFull(_board)) {
      _finish(winner: null, line: null);
    } else if (_vsAi && _turn == Mark.o) {
      _aiTurn();
    }
  }

  Future<void> _aiTurn() async {
    final id = _gameId;
    setState(() => _thinking = true);
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted || id != _gameId) return;
    final move = aiMove(_board, Mark.o, _s.difficulty, _rnd);
    setState(() => _thinking = false);
    _place(move, Mark.o);
  }

  Future<void> _finish({required Mark? winner, required List<int>? line}) async {
    final id = _gameId;
    setState(() {
      _over = true;
      _winner = winner;
      _winLine = line;
    });
    if (_vsAi) {
      if (winner == Mark.x) {
        _s.wins++;
      } else if (winner == Mark.o) {
        _s.losses++;
      } else {
        _s.draws++;
      }
      unawaited(_s.save());
    }
    if (line != null) _lineC.forward(from: 0);
    await Future<void>.delayed(Duration(milliseconds: line != null ? 750 : 350));
    if (!mounted || id != _gameId) return;
    _resultC.forward(from: 0);
  }

  void _undo() {
    if (_over || _thinking || _history.isEmpty) return;
    setState(() {
      final n = _vsAi ? min(2, _history.length) : 1;
      for (var i = 0; i < n; i++) {
        _board[_history.removeLast()] = Mark.none;
      }
      _turn = _history.isEmpty
          ? Mark.x
          : otherMark(_board[_history.last]);
    });
  }

  // ---------------- input (taps + secret hold) ----------------
  int? _cellAt(Offset p) {
    final size = _boardSize;
    if (size <= 0 || p.dx < 0 || p.dy < 0 || p.dx > size || p.dy > size) return null;
    final c = (p.dx / (size / 3)).floor().clamp(0, 2);
    final r = (p.dy / (size / 3)).floor().clamp(0, 2);
    return r * 3 + c;
  }

  void _onDown(PointerDownEvent e) {
    _downPos = e.localPosition;
    _downCell = _cellAt(e.localPosition);
    _moved = false;
    _longFired = false;
    _long?.cancel();
    if (_downCell == 4) {
      _long = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        _longFired = true;
        HapticFeedback.mediumImpact();
        openVault(context);
      });
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (!_moved && (e.localPosition - _downPos).distance > 18) {
      _moved = true;
      _long?.cancel();
    }
  }

  void _onUp(PointerUpEvent e) {
    _long?.cancel();
    if (_longFired) {
      // the 3-second hold opened the vault: don't also play a move
      _longFired = false;
      return;
    }
    if (!_moved) {
      final c = _cellAt(e.localPosition);
      if (c != null) _tap(c);
    }
    _moved = false;
  }

  void _onCancel() {
    _long?.cancel();
    _longFired = false;
    _moved = false;
  }

  // ---------------- sheets ----------------
  void _showStats() {
    showGlassSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 4, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Your record', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _stat('Won', _s.wins),
                  _stat('Lost', _s.losses),
                  _stat('Draw', _s.draws),
                ],
              ),
              const SizedBox(height: 10),
              const Text('Games against the computer', style: TextStyle(color: kSub, fontSize: 12.5)),
              const SizedBox(height: 18),
              TextButton(
                onPressed: () {
                  _s.wins = 0;
                  _s.losses = 0;
                  _s.draws = 0;
                  unawaited(_s.save());
                  Navigator.pop(ctx);
                  setState(() {});
                },
                child: const Text('Reset'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, int v) => Column(
        children: [
          Text('$v', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w300)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: kSub, fontSize: 13)),
        ],
      );

  void _showSettings() {
    showGlassSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Game', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 18),
                const Text('Opponent', style: TextStyle(color: kSub, fontSize: 13)),
                const SizedBox(height: 8),
                Segmented<String>(
                  value: _s.mode,
                  options: const {'ai': 'Computer', 'two': '2 Players'},
                  onChanged: (v) {
                    _s.mode = v;
                    unawaited(_s.save());
                    setSheet(() {});
                    _newGame();
                  },
                ),
                if (_s.mode == 'ai') ...[
                  const SizedBox(height: 18),
                  const Text('Difficulty', style: TextStyle(color: kSub, fontSize: 13)),
                  const SizedBox(height: 8),
                  Segmented<String>(
                    value: _s.difficulty,
                    options: const {'easy': 'Easy', 'normal': 'Normal', 'hard': 'Hard'},
                    onChanged: (v) {
                      _s.difficulty = v;
                      unawaited(_s.save());
                      setSheet(() {});
                      _newGame();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              child: Column(
                children: [
                  _header(),
                  Expanded(
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final size = min(c.maxWidth, c.maxHeight);
                          return SizedBox(
                            width: size,
                            height: size,
                            child: GlassPanel(
                              radius: 32,
                              padding: const EdgeInsets.all(14),
                              child: _buildBoard(size - 28),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  _status(),
                  const SizedBox(height: 18),
                  _bottomBar(),
                ],
              ),
            ),
          ),
          if (_over)
            Positioned.fill(
              child: ClipRect(
                child: AnimatedBuilder(
                animation: _resultC,
                builder: (context, child) => BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: _frostSigma(), sigmaY: _frostSigma()),
                  child: child,
                ),
                child: ResultOverlay(
                animation: _resultC,
                text: _resultText(),
                subtitle: _resultSub(),
                win: _winner == null ? null : (!_vsAi || _winner == Mark.x),
                onRestart: _newGame,
              ),
              ),
              ),
            ),
        ],
      ),
    );
  }

  double _frostSigma() => 0.01 + 16 * Curves.easeOut.transform((_resultC.value / 0.3).clamp(0.0, 1.0).toDouble());

  String _resultText() {
    if (_winner == null) return 'DRAW';
    if (_vsAi) return _winner == Mark.x ? 'YOU WON' : 'YOU LOST';
    return _winner == Mark.x ? 'X WINS' : 'O WINS';
  }

  String _resultSub() {
    if (_winner == null) return 'Evenly matched.';
    if (_vsAi) return _winner == Mark.x ? 'Nicely played.' : 'Better luck next round.';
    return 'Well played.';
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tic Tac Toe', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.5)),
              SizedBox(height: 2),
              Text('Play. Think. Win.', style: TextStyle(fontSize: 13, color: kSub)),
            ],
          ),
        ),
        GlassIconButton(onPressed: _showStats, icon: Icons.bar_chart_rounded, tooltip: 'Stats'),
      ],
    );
  }

  Widget _status() {
    final String t;
    if (_over) {
      t = '';
    } else if (_vsAi) {
      t = _thinking ? 'Thinking…' : 'Your move';
    } else {
      t = _turn == Mark.x ? 'X to play' : 'O to play';
    }
    return SizedBox(
      height: 20,
      child: Text(t, style: const TextStyle(color: kSub, fontSize: 13, letterSpacing: 0.3)),
    );
  }

  Widget _bottomBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GlassIconButton(onPressed: _undo, icon: Icons.history, tooltip: 'Undo'),
        PillButton(label: 'New Game', onPressed: _newGame),
        GlassIconButton(onPressed: _showSettings, icon: Icons.settings_outlined, tooltip: 'Game settings'),
      ],
    );
  }

  Widget _buildBoard(double size) {
    _boardSize = size;
    final cell = size / 3;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: (_) => _onCancel(),
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: BoardPainter())),
          for (var i = 0; i < 9; i++)
            if (_board[i] != Mark.none)
              Positioned(
                left: (i % 3) * cell,
                top: (i ~/ 3) * cell,
                width: cell,
                height: cell,
                child: TweenAnimationBuilder<double>(
                  key: ValueKey('$_gameId-$i-${_board[i].index}'),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => CustomPaint(painter: MarkPainter(_board[i], t)),
                ),
              ),
          if (_winLine != null)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _lineC,
                builder: (context, _) => CustomPaint(painter: WinLinePainter(_winLine!, _lineC.value)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Animated "YOU WON" / "YOU LOST" reveal with a Restart button.
class ResultOverlay extends StatelessWidget {
  const ResultOverlay({
    super.key,
    required this.animation,
    required this.text,
    required this.subtitle,
    required this.win,
    required this.onRestart,
  });

  final Animation<double> animation;
  final String text;
  final String subtitle;
  final bool? win; // true = rise, false = sink, null = neutral
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final v = animation.value;
        final scrim = Curves.easeOut.transform((v / 0.3).clamp(0.0, 1.0).toDouble());
        final chars = text.split('');
        final dy = win == false ? -26.0 : 26.0;
        return IgnorePointer(
          ignoring: v < 0.7,
          child: ColoredBox(
            color: Colors.white.withAlpha((scrim * 120).round()),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < chars.length; i++) _letter(chars[i], i, chars.length, v, dy),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Opacity(
                    opacity: Curves.easeOut.transform(((v - 0.55) / 0.25).clamp(0.0, 1.0).toDouble()),
                    child: Text(subtitle, style: const TextStyle(color: kSub, fontSize: 15, letterSpacing: 0.4)),
                  ),
                  const SizedBox(height: 44),
                  Opacity(
                    opacity: Curves.easeOut.transform(((v - 0.7) / 0.3).clamp(0.0, 1.0).toDouble()),
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - ((v - 0.7) / 0.3).clamp(0.0, 1.0).toDouble())),
                      child: PillButton(label: 'Restart', onPressed: onRestart),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _letter(String ch, int i, int n, double v, double dy) {
    final start = 0.12 + 0.4 * (i / max(1, n));
    final t = Curves.easeOutCubic.transform(((v - start) / 0.38).clamp(0.0, 1.0).toDouble());
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, dy * (1 - t)),
        child: Transform.scale(
          scale: 0.9 + 0.1 * t,
          child: Text(
            ch == ' ' ? '\u00A0' : ch,
            style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w700, letterSpacing: 3, color: kInk),
          ),
        ),
      ),
    );
  }
}
