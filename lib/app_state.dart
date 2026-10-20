import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'native.dart';
import 'vault/vault_controller.dart';

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

/// Plain settings + game stats, stored sealed by the Android Keystore.
class AppSettings extends ChangeNotifier {
  int autoLockSec = 0; // 0 = as soon as the app leaves the foreground
  String mode = 'ai'; // ai | two
  String difficulty = 'hard'; // easy | normal | hard
  int wins = 0;
  int losses = 0;
  int draws = 0;

  static Future<AppSettings> load() async {
    final s = AppSettings();
    try {
      final raw = await Native.getSettings();
      if (raw != null && raw.isNotEmpty) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        s.autoLockSec = (m['autoLock'] as num?)?.toInt() ?? 0;
        s.mode = (m['mode'] as String?) ?? 'ai';
        s.difficulty = (m['difficulty'] as String?) ?? 'hard';
        s.wins = (m['wins'] as num?)?.toInt() ?? 0;
        s.losses = (m['losses'] as num?)?.toInt() ?? 0;
        s.draws = (m['draws'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {
      // fall back to defaults
    }
    return s;
  }

  Future<void> save() async {
    notifyListeners();
    try {
      await Native.saveSettings(jsonEncode(<String, dynamic>{
        'autoLock': autoLockSec,
        'mode': mode,
        'difficulty': difficulty,
        'wins': wins,
        'losses': losses,
        'draws': draws,
      }));
    } catch (_) {
      // non-fatal
    }
  }
}

late VaultSession session;

/// Owns the vault state and locks it when the app is backgrounded.
class VaultSession with WidgetsBindingObserver {
  VaultSession(this.settings);

  final AppSettings settings;
  final VaultController vault = VaultController();

  int _busy = 0;
  DateTime _graceUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _pausedAt;
  Timer? _timer;

  bool get unlocked => vault.unlocked;

  /// Wrap anything that opens another Android screen (pickers, camera, delete dialog) so it doesn't trigger a lock.
  Future<T> external<T>(Future<T> Function() f) async {
    _busy++;
    try {
      return await f();
    } finally {
      _busy--;
      _graceUntil = DateTime.now().add(const Duration(seconds: 2));
    }
  }

  /// For hand-offs we can't await (the share sheet).
  void suppressFor(Duration d) => _graceUntil = DateTime.now().add(d);

  void lock() {
    _timer?.cancel();
    _pausedAt = null;
    vault.lock();
    navKey.currentState?.popUntil((r) => r.isFirst);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (!unlocked) return;
      final now = DateTime.now();
      if (_busy > 0) {
        _pausedAt = null;
        return;
      }
      _timer?.cancel();
      final base = now.isBefore(_graceUntil) ? _graceUntil : now;
      _pausedAt = base;
      final wait = base.difference(now) + Duration(seconds: settings.autoLockSec);
      if (wait <= Duration.zero) {
        lock();
      } else {
        _timer = Timer(wait, () {
          if (_pausedAt != null && unlocked) lock();
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      _timer?.cancel();
      final p = _pausedAt;
      _pausedAt = null;
      if (unlocked && p != null) {
        final away = DateTime.now().difference(p);
        if (away >= Duration(seconds: settings.autoLockSec)) lock();
      }
    } else if (state == AppLifecycleState.detached) {
      if (unlocked) lock();
    }
  }
}
