import 'package:flutter/material.dart';

import 'game/game_screen.dart';
import 'ui.dart';
import 'vault/vault_flow.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  @override
  void initState() {
    super.initState();
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Center(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = Curves.easeOut.transform((_c.value / 0.5).clamp(0.0, 1.0).toDouble());
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, 8 * (1 - t)),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Tic Tac Toe', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w300, letterSpacing: -0.5)),
                        SizedBox(height: 14),
                        Text('PLAY  ·  THINK  ·  WIN', style: TextStyle(fontSize: 11, letterSpacing: 3, color: kSub)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 64,
            child: Center(
              child: SizedBox(
                width: 96,
                height: 2,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => Stack(
                    children: [
                      const Positioned.fill(child: ColoredBox(color: kLine)),
                      FractionallySizedBox(
                        widthFactor: _c.value,
                        child: const ColoredBox(color: kInk, child: SizedBox(height: 2)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
