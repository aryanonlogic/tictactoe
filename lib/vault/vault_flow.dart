import 'package:flutter/material.dart';

import '../app_state.dart';
import '../native.dart';
import '../ui.dart';
import 'pin_screen.dart';
import 'vault_screen.dart';

Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
      opaque: true,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
    );

/// Entry point to the vault (secret gesture or share-sheet import).
/// First run: create a PIN. Afterwards: ask for it. Then open the vault.
Future<void> openVault(BuildContext context, {List<String> pendingImport = const <String>[]}) async {
  final nav = Navigator.of(context);
  if (!session.vault.unlocked) {
    bool has;
    try {
      has = await Native.hasPin();
    } catch (_) {
      return;
    }
    if (!nav.mounted) return;
    final ok = await nav.push<bool>(fadeRoute<bool>(PinScreen(mode: has ? PinMode.unlock : PinMode.setup)));
    if (ok != true || !nav.mounted) return;
    try {
      await session.vault.unlock();
    } catch (e) {
      if (context.mounted) snack(context, 'Couldn’t open the vault: $e');
      return;
    }
    if (!nav.mounted) return;
  }
  await nav.push<void>(fadeRoute<void>(VaultScreen(pendingImport: pendingImport)));
}
