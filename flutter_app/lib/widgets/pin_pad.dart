import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Four boxes and a number pad: the passcode entry shared by the sign-in screen and the set-up screen.
/// Reports the digits typed so far through [onChanged] (0 to 4 digits); the owner keeps the Login / Next button.
/// Use a GlobalKey<PinPadState> to [PinPadState.clear] it or [PinPadState.shake] it after a wrong passcode.
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.onChanged, this.onFingerprint, this.keyHeight = 52, this.length = 4});

  final ValueChanged<String> onChanged;

  /// When given, the bottom-left key is a fingerprint button.
  final VoidCallback? onFingerprint;
  final double keyHeight;
  final int length;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  static const _brand = Color(0xFFC63A55);
  String _pin = '';
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  String get pin => _pin;

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void clear() {
    setState(() => _pin = '');
    widget.onChanged(_pin);
  }

  /// A wrong passcode: the boxes shake, the phone buzzes, the digits are cleared.
  void shake() {
    HapticFeedback.heavyImpact();
    _shake.forward(from: 0).whenComplete(clear);
  }

  void _add(String d) {
    if (_pin.length >= widget.length || _shake.isAnimating) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += d);
    widget.onChanged(_pin);
  }

  void _back() {
    if (_pin.isEmpty || _shake.isAnimating) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
    widget.onChanged(_pin);
  }

  Widget _box(int i) {
    final filled = i < _pin.length;
    final current = i == _pin.length;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 54,
      height: 58,
      margin: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: filled ? Colors.white : const Color(0xFFFDEBD0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: filled || current ? _brand : Colors.transparent, width: filled ? 1.6 : 1.4),
        boxShadow: filled ? [BoxShadow(color: _brand.withOpacity(0.18), blurRadius: 10, offset: const Offset(0, 3))] : null,
      ),
      alignment: Alignment.center,
      child: filled ? const Icon(Icons.circle, size: 15, color: Color(0xFF3B2A1A)) : null,
    );
  }

  Widget _key({Widget? child, String? digit, VoidCallback? onTap, String? label}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Semantics(
          button: true,
          label: label ?? digit,
          child: Material(
            color: digit == null ? Colors.transparent : const Color(0xFFF6F1E9),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap ?? (digit == null ? null : () => _add(digit)),
              child: SizedBox(
                height: widget.keyHeight,
                child: Center(child: child ?? Text(digit ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Color(0xFF2B2118)))),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fp = widget.onFingerprint;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(
        animation: _shake,
        builder: (_, child) => Transform.translate(offset: Offset(math.sin(_shake.value * math.pi * 6) * 10 * (1 - _shake.value), 0), child: child),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (var i = 0; i < widget.length; i++) _box(i)]),
      ),
      const SizedBox(height: 14),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(children: [
          for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']]) Row(children: [for (final d in row) _key(digit: d)]),
          Row(children: [
            fp != null ? _key(child: const Icon(Icons.fingerprint_rounded, size: 30, color: _brand), onTap: fp, label: 'Fingerprint') : _key(),
            _key(digit: '0'),
            _key(child: const Icon(Icons.backspace_outlined, size: 24, color: Color(0xFF6B5B4B)), onTap: _back, label: 'Delete'),
          ]),
        ]),
      ),
    ]);
  }
}
