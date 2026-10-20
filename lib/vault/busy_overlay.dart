import 'package:flutter/material.dart';

import '../app_state.dart';
import '../ui.dart';

/// Blocking scrim with a spinner and a label while the vault runs a long operation. Use as a Stack child.
class BusyOverlay extends StatelessWidget {
  const BusyOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final vault = session.vault;
    return ListenableBuilder(
      listenable: vault,
      builder: (context, _) {
        if (vault.busy == null) return const SizedBox.shrink();
        return Positioned.fill(
          child: AbsorbPointer(
            child: ColoredBox(
              color: const Color(0xD9FFFFFF),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kInk),
                    ),
                    const SizedBox(height: 16),
                    Text(vault.busy!, style: const TextStyle(fontSize: 15)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
