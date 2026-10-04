import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Four dots and a round number pad: the passcode entry shared by the sign-in screen and the set-up screen.
/// Reports the digits typed so far through [onChanged] (0 to 4 digits); the owner keeps the Login / Next button.
/// Use a GlobalKey<PinPadState> to [PinPadState.clear] it or [PinPadState.shake] it after a wrong passcode.
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.onChanged, this.onFingerprint, this.keyHeight = 54, this.length = 4, this.dark = false});

  final ValueChanged<String> onChanged;

  /// When given, the bottom-left key is a fingerprint button.
  final VoidCallback? onFingerprint;

  /// The size (diameter) of a round key.
  final double keyHeight;
  final int length;

  /// For use on top of a photo: white dots and glass-like keys with white digits.
  final bool dark;

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

  /// A wrong passcode: the dots shake, the phone buzzes, the digits are cleared.
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

  Widget _dot(int i) {
    final filled = i < _pin.length;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      width: filled ? 20 : 18,
      height: filled ? 20 : 18,
      margin: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: filled ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFE94560), Color(0xFFB91C3C)]) : null,
        color: filled ? null : Colors.transparent,
        border: filled ? null : Border.all(color: widget.dark ? const Color(0xB3FFFFFF) : const Color(0xFFD9CDB8), width: 2),
        boxShadow: filled ? [BoxShadow(color: _brand.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 3))] : null,
      ),
    );
  }

  Widget _key({Widget? child, String? digit, VoidCallback? onTap, String? label, bool tinted = false}) {
    final d = widget.keyHeight;
    final empty = child == null && digit == null;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Center(
          child: empty
              ? SizedBox(width: d, height: d)
              : Semantics(
                  button: true,
                  label: label ?? digit,
                  child: Container(
                    width: d,
                    height: d,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.dark ? (tinted ? const Color(0x4DE94560) : const Color(0x2EFFFFFF)) : (tinted ? const Color(0xFFFDE8EC) : Colors.white),
                      border: Border.all(color: widget.dark ? const Color(0x66FFFFFF) : (tinted ? const Color(0xFFF8C9D2) : const Color(0xFFEFE7D8))),
                      boxShadow: widget.dark ? null : const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 4))],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        splashColor: _brand.withOpacity(0.14),
                        onTap: onTap ?? (digit == null ? null : () => _add(digit)),
                        child: Center(child: child ?? Text(digit!, style: TextStyle(fontSize: 25, fontWeight: FontWeight.w500, color: widget.dark ? Colors.white : const Color(0xFF2B2118)))),
                      ),
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
        child: SizedBox(height: 26, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (var i = 0; i < widget.length; i++) _dot(i)])),
      ),
      const SizedBox(height: 10),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Column(children: [
          for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']]) Row(children: [for (final d in row) _key(digit: d)]),
          Row(children: [
            fp != null ? _key(child: Icon(Icons.fingerprint_rounded, size: 30, color: widget.dark ? Colors.white : _brand), onTap: fp, label: 'Fingerprint', tinted: true) : _key(),
            _key(digit: '0'),
            _key(child: Icon(Icons.backspace_outlined, size: 23, color: widget.dark ? Colors.white : const Color(0xFF6B5B4B)), onTap: _back, label: 'Delete'),
          ]),
        ]),
      ),
    ]);
  }
}
