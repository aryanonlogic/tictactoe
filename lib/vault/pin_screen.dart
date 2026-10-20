import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../native.dart';
import '../ui.dart';
import 'vault_flow.dart';

enum PinMode { unlock, setup, verify, developer }

const int kPinLength = 6;

class PinScreen extends StatefulWidget {
  const PinScreen({super.key, required this.mode, this.heading});

  final PinMode mode;
  final String? heading;

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> with SingleTickerProviderStateMixin {
  String _pin = '';
  String? _first;
  String _msg = '';
  bool _busy = false;
  int _lockLeftSec = 0;
  Timer? _tick;

  late final AnimationController _shake;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _shake.dispose();
    super.dispose();
  }

  String get _title {
    if (widget.mode == PinMode.setup) {
      return _first == null ? (widget.heading ?? 'Create a PIN') : 'Confirm your PIN';
    }
    return widget.heading ?? (widget.mode == PinMode.developer ? 'Developer PIN' : 'Enter PIN');
  }

  bool _weak(String p) {
    if (p == '920000') return true;
    if (RegExp(r'^(\d)\1+$').hasMatch(p)) return true;
    const asc = '0123456789012';
    const desc = '9876543210987';
    return asc.contains(p) || desc.contains(p);
  }

  void _digit(String d) {
    if (_busy || _lockLeftSec > 0 || _pin.length >= kPinLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += d;
      _msg = '';
    });
    if (_pin.length == kPinLength) _submit();
  }

  void _back() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _fail(String msg) async {
    HapticFeedback.heavyImpact();
    setState(() {
      _msg = msg;
      _busy = true;
    });
    await _shake.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _pin = '';
      _busy = false;
    });
  }

  Future<void> _submit() async {
    final pin = _pin;
    setState(() => _busy = true);
    try {
      if (widget.mode == PinMode.setup) {
        if (_first == null) {
          if (_weak(pin)) {
            setState(() => _busy = false);
            await _fail('Choose a less obvious PIN');
            return;
          }
          setState(() {
            _first = pin;
            _pin = '';
            _busy = false;
          });
        } else if (_first == pin) {
          await Native.setPin(pin);
          if (!mounted) return;
          Navigator.of(context).pop(true);
        } else {
          _first = null;
          setState(() => _busy = false);
          await _fail('PINs didn’t match. Start again');
        }
        return;
      }

      final r = await Native.verifyPin(pin, dev: widget.mode == PinMode.developer);
      if (!mounted) return;
      if (r.ok) {
        if (r.dev && widget.mode == PinMode.developer) {
          final create = await confirmDialog(
            context,
            title: 'Developer PIN accepted',
            body: 'Create a new PIN now? Your vault files stay untouched.',
            confirm: 'Create new PIN',
            cancel: 'Not now',
          );
          if (!mounted) return;
          if (create) {
            await Navigator.of(context)
                .push<bool>(fadeRoute<bool>(const PinScreen(mode: PinMode.setup, heading: 'New PIN')));
            if (!mounted) return;
          }
        }
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _busy = false);
      if (r.lockMs > 0) {
        _startLock((r.lockMs / 1000).ceil());
        await _fail('Too many attempts');
      } else {
        await _fail(r.left > 0 ? 'Wrong PIN · ${r.left} ${r.left == 1 ? 'try' : 'tries'} left' : (widget.mode == PinMode.developer ? 'Wrong developer PIN' : 'Wrong PIN'));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pin = '';
        _msg = 'Something went wrong. Try again';
      });
    }
  }

  void _startLock(int seconds) {
    _tick?.cancel();
    setState(() => _lockLeftSec = seconds);
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _lockLeftSec = max(0, _lockLeftSec - 1));
      if (_lockLeftSec == 0) {
        t.cancel();
        setState(() => _msg = '');
      }
    });
  }

  Future<void> _forgot() async {
    final enter = await confirmDialog(
      context,
      title: 'Forgot PIN?',
      body: 'Ask developer for the developer PIN. Enter it on the next screen, then you can create a new PIN.',
      confirm: 'Enter developer PIN',
    );
    if (!enter || !mounted) return;
    final ok = await Navigator.of(context)
        .push<bool>(fadeRoute<bool>(const PinScreen(mode: PinMode.developer)));
    if (ok == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final locked = _lockLeftSec > 0;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              ),
            ),
            const Spacer(flex: 2),
            const Icon(Icons.lock_outline, size: 34),
            const SizedBox(height: 14),
            Text(_title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
            const SizedBox(height: 22),
            AnimatedBuilder(
              animation: _shake,
              builder: (context, child) => Transform.translate(
                offset: Offset(sin(_shake.value * pi * 7) * 11 * (1 - _shake.value), 0),
                child: child,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < kPinLength; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      margin: const EdgeInsets.symmetric(horizontal: 7),
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _pin.length ? kInk : Colors.transparent,
                        border: Border.all(color: i < _pin.length ? kInk : const Color(0xFFBDBDB8), width: 1.3),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 20,
              child: (!locked && _msg.isEmpty && widget.mode == PinMode.unlock)
                  ? GestureDetector(
                      onTap: _forgot,
                      child: const Text('Forgot PIN?', style: TextStyle(color: kSub, fontSize: 13)),
                    )
                  : Text(
                      locked ? 'Try again in ${_lockLeftSec}s' : _msg,
                      style: const TextStyle(color: kSub, fontSize: 13),
                    ),
            ),
            const Spacer(),
            _keypad(),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  Widget _keypad() {
    Widget key(String label) => _Key(label: label, onTap: () => _digit(label));
    Widget row(List<String> l) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: l.map(key).toList()),
        );
    return Column(
      children: [
        row(['1', '2', '3']),
        row(['4', '5', '6']),
        row(['7', '8', '9']),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 100),
              key('0'),
              SizedBox(
                width: 100,
                child: IconButton(onPressed: _back, icon: const Icon(Icons.backspace_outlined, size: 22)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      child: Center(
        child: Material(
          color: kMist,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 68,
              height: 68,
              child: Center(child: Text(label, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w400))),
            ),
          ),
        ),
      ),
    );
  }
}
