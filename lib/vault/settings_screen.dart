import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../ui.dart';
import 'busy_overlay.dart';
import 'pin_screen.dart';
import 'vault_flow.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Map<int, String> _autoLockOptions = <int, String>{
    0: 'Immediately',
    30: 'After 30 seconds',
    60: 'After 1 minute',
    300: 'After 5 minutes',
  };

  AppSettings get _s => session.settings;

  Future<void> _changePin() async {
    final nav = Navigator.of(context);
    final ok = await nav.push<bool>(fadeRoute<bool>(const PinScreen(mode: PinMode.verify, heading: 'Current PIN')));
    if (ok != true || !mounted) return;
    final done = await nav.push<bool>(fadeRoute<bool>(const PinScreen(mode: PinMode.setup, heading: 'New PIN')));
    if (done == true && mounted) snack(context, 'PIN changed');
  }

  Future<void> _autoLock() async {
    final v = await showGlassSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Auto Lock', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
            ),
            for (final e in _autoLockOptions.entries)
              ListTile(
                title: Text(e.value),
                trailing: e.key == _s.autoLockSec ? const Icon(Icons.check, color: kInk) : null,
                onTap: () => Navigator.pop(ctx, e.key),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Text(
                'How long the vault stays open after you leave the app. The vault also locks right away if the app closes.',
                style: TextStyle(color: kSub, fontSize: 12.5, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
    if (v == null) return;
    _s.autoLockSec = v;
    unawaited(_s.save());
    if (mounted) setState(() {});
  }

  Future<void> _restoreAll() async {
    final nav = Navigator.of(context);
    final n = session.vault.items.length;
    if (n == 0) {
      snack(context, 'The vault is empty');
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Restore all $n ${n == 1 ? 'file' : 'files'}?',
      body: 'Everything is saved to your gallery (Pictures/Restored and Movies/Restored) and removed from the vault, '
          'in small batches, only after each copy is verified. Keep the app open until it finishes.',
      confirm: 'Restore all',
    );
    if (!ok || !mounted) return;
    final pinOk = await nav.push<bool>(fadeRoute<bool>(const PinScreen(mode: PinMode.verify, heading: 'Confirm with PIN')));
    if (pinOk != true || !mounted) return;
    try {
      final r = await session.vault.restoreAll();
      if (!mounted) return;
      snack(
        context,
        r.failed == 0
            ? 'Restored ${r.restored} to your gallery'
            : 'Restored ${r.restored}. ${r.failed} couldn’t be restored and stay in the vault.',
      );
    } catch (e) {
      if (mounted) snack(context, 'Restore failed: $e');
    }
  }

  Future<void> _clear() async {
    final nav = Navigator.of(context);
    final ok = await confirmDialog(
      context,
      title: 'Clear vault data?',
      body: 'Every photo, video and folder in the vault will be permanently deleted. Your PIN and gesture stay.',
      confirm: 'Continue',
    );
    if (!ok || !mounted) return;
    final pinOk = await nav.push<bool>(fadeRoute<bool>(const PinScreen(mode: PinMode.verify, heading: 'Confirm with PIN')));
    if (pinOk != true || !mounted) return;
    try {
      await session.vault.wipe();
      if (mounted) snack(context, 'Vault cleared');
    } catch (e) {
      if (mounted) snack(context, 'Couldn’t clear the vault: $e');
    }
  }

  void _about() {
    showGlassDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Tic Tac Toe', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        content: const Text(
          'Version 1.0.0\n\nEverything stays on this device. The app has no internet access and no analytics.',
          style: TextStyle(color: kSub, height: 1.4),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text('Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  RowTile(icon: Icons.lock_outline, title: 'Change PIN', onTap: _changePin),
                  const Divider(indent: 58),
                  RowTile(
                    icon: Icons.timer_outlined,
                    title: 'Auto Lock',
                    subtitle: _autoLockOptions[_s.autoLockSec] ?? 'Immediately',
                    onTap: _autoLock,
                  ),
                  const Divider(indent: 58),
                  RowTile(
                    icon: Icons.unarchive_outlined,
                    title: 'Restore All to Gallery',
                    subtitle: 'Move every photo and video back to your gallery',
                    onTap: _restoreAll,
                  ),
                  const Divider(indent: 58),
                  RowTile(icon: Icons.delete_sweep_outlined, title: 'Clear Vault Data', onTap: _clear),
                  const Divider(indent: 58),
                  RowTile(icon: Icons.info_outline, title: 'About', onTap: _about),
                ],
              ),
            ),
          ],
        ),
      ),
          const BusyOverlay(),
        ],
      ),
    );
  }
}
