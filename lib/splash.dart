import 'package:flutter/material.dart';

import 'game/game_screen.dart';
import 'game/logic.dart';
import 'game/painters.dart';
import 'ui.dart';
import 'vault/vault_flow.dart';

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0).toDouble();

const String _title = 'Tic Tac Toe';

/// ~2 s intro: the grid opens from the centre, a perfect game plays itself in 3D X/O (X wins the diagonal),
/// a shock ring pulses and the title spells itself out. Then it fades straight into the game.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        Navigator.of(context).pushReplacement(fadeRoute<void>(const GameScreen()));
      }
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final board = (w * 0.6).clamp(160.0, 260.0).toDouble();
    final letters = _title.split('');
    return Scaffold(
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final push = 1.07 - 0.07 * Curves.easeOutCubic.transform(_seg(t, 0.0, 0.8));
            final lift = -16 * Curves.easeInOut.transform(_seg(t, 0.78, 1.0));
            final tag = Curves.easeOut.transform(_seg(t, 0.9, 1.0));
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.translate(
                  offset: Offset(0, lift),
                  child: Transform.scale(
                    scale: push,
                    child: GlassPanel(
                      radius: 36,
                      padding: const EdgeInsets.all(18),
                      child: SizedBox(
                        width: board,
                        height: board,
                        child: CustomPaint(painter: _SplashBoardPainter(t)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < letters.length; i++)
                        _letter(letters[i], Curves.easeOutCubic.transform(_seg(t, 0.8 + 0.12 * i / letters.length, 0.9 + 0.1 * i / letters.length))),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Opacity(
                  opacity: tag,
                  child: const Text(
                    'PLAY  ·  THINK  ·  WIN',
                    style: TextStyle(fontSize: 11, letterSpacing: 3, color: kSub),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _letter(String ch, double p) => Opacity(
        opacity: p,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - p)),
          child: Text(
            ch == ' ' ? '\u00A0' : ch,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w300, letterSpacing: 1.5, color: kInk),
          ),
        ),
      );
}

class _SplashBoardPainter extends CustomPainter {
  const _SplashBoardPainter(this.t);

  final double t;

  static const List<int> _cells = <int>[4, 2, 0, 6, 8];
  static const List<Mark> _marks = <Mark>[Mark.x, Mark.o, Mark.x, Mark.o, Mark.x];
  static const List<double> _starts = <double>[0.18, 0.30, 0.42, 0.54, 0.64];

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 3;
    final centre = size.center(Offset.zero);

    // 1) the grid opens from the centre
    final g = Curves.easeOutCubic.transform(_seg(t, 0.0, 0.22));
    if (g > 0) {
      final s = size.width * g;
      canvas.save();
      canvas.clipRect(Rect.fromCenter(center: centre, width: s, height: s));
      const BoardPainter().paint(canvas, size);
      canvas.restore();
    }

    // 2) a perfect game plays itself: X centre, O top-right, X top-left, O bottom-left, X bottom-right
    for (var i = 0; i < _cells.length; i++) {
      final p = _seg(t, _starts[i], _starts[i] + 0.12);
      if (p <= 0) continue;
      final c = _cells[i];
      canvas.save();
      canvas.translate((c % 3) * cell, (c ~/ 3) * cell);
      MarkPainter(_marks[i], Curves.easeOutCubic.transform(p)).paint(canvas, Size(cell, cell));
      canvas.restore();
    }

    // 3) X wins the diagonal
    final w = _seg(t, 0.76, 0.88);
    if (w > 0) WinLinePainter(const <int>[0, 4, 8], w).paint(canvas, size);

    // 4) shock ring
    final r = _seg(t, 0.78, 0.97);
    if (r > 0 && r < 1) {
      canvas.drawCircle(
        centre,
        size.width * (0.2 + 0.7 * Curves.easeOut.transform(r)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Color.fromRGBO(0, 0, 0, 0.22 * (1 - r)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplashBoardPainter old) => old.t != t;
}
