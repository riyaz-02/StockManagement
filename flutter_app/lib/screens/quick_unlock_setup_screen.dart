import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../services/app_lock_service.dart';
import '../services/biometric_auth_service.dart';
import '../widgets/pin_pad.dart';

enum _Step { create, confirm, finger }

/// Set (or change) the 4-digit passcode, then offer the fingerprint. Pops `true` when a passcode was saved.
/// [forgot] = the person just signed in again after "Forgot passcode": the words say they are choosing a new one.
class QuickUnlockSetupScreen extends StatefulWidget {
  const QuickUnlockSetupScreen({super.key, this.forgot = false, this.canSkip = true, this.then});
  final bool forgot;
  final bool canSkip;

  /// Where to go when done (the screen replaces itself with it); without it the screen just closes.
  final void Function(BuildContext context)? then;

  @override
  State<QuickUnlockSetupScreen> createState() => _QuickUnlockSetupScreenState();
}

class _QuickUnlockSetupScreenState extends State<QuickUnlockSetupScreen> {
  static const _brand = Color(0xFFC63A55);
  final _pad = GlobalKey<PinPadState>();
  _Step _step = _Step.create;
  String _first = '';
  String _typed = '';
  String? _message;
  bool _busy = false;
  bool _fingerOn = false;
  FingerprintState _fpState = FingerprintState.unsupported;

  bool get _bn => Provider.of<LanguageProvider>(context, listen: false).currentLanguage == 'bn';
  String _t(String en, String bn) => _bn ? bn : en;

  void _finish(bool saved) {
    if (widget.then != null) {
      widget.then!(context);
    } else {
      Navigator.of(context).pop(saved);
    }
  }

  Future<void> _next() async {
    if (_typed.length != AppLockService.pinLength) return;
    if (_step == _Step.create) {
      if (AppLockService.isWeakPin(_typed)) {
        setState(() => _message = _t('Too easy to guess (like 1111 or 1234). Choose another.', 'খুব সহজ (যেমন 1111 বা 1234)। অন্য একটি দিন।'));
        _pad.currentState?.shake();
        return;
      }
      setState(() {
        _first = _typed;
        _typed = '';
        _message = null;
        _step = _Step.confirm;
      });
      _pad.currentState?.clear();
    } else if (_step == _Step.confirm) {
      if (_typed != _first) {
        setState(() => _message = _t('The two passcodes are not the same. Try again.', 'দুটি পাসকোড মেলেনি। আবার দিন।'));
        _pad.currentState?.shake();
        return;
      }
      setState(() => _busy = true);
      try {
        await Provider.of<AuthProvider>(context, listen: false).setPasscode(_typed);
      } catch (_) {
        if (mounted) setState(() { _busy = false; _message = _t('Could not save the passcode on this phone. Try again.', 'এই ফোনে পাসকোড সেভ হয়নি। আবার চেষ্টা করুন।'); });
        return;
      }
      _fpState = await BiometricAuthService().state();
      if (!mounted) return;
      if (_fpState == FingerprintState.unsupported) {
        _finish(true);
        return;
      }
      setState(() {
        _busy = false;
        _step = _Step.finger;
        _message = null;
      });
    }
  }

  Future<void> _enableFingerprint() async {
    setState(() { _busy = true; _message = null; });
    final r = await BiometricAuthService().scan(reason: _t('Touch the fingerprint sensor', 'ফিঙ্গারপ্রিন্ট সেন্সরে আঙুল রাখুন'));
    if (!mounted) return;
    if (r == FingerprintResult.success) {
      await AppLockService.instance.setFingerprint(true);
      if (!mounted) return;
      setState(() { _busy = false; _fingerOn = true; });
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) _finish(true);
      return;
    }
    setState(() {
      _busy = false;
      _message = switch (r) {
        FingerprintResult.notEnrolled => _t('No fingerprint is saved on this phone yet. Add one in the phone Settings, then turn this on in Account settings.', 'এই ফোনে এখনও কোনো ফিঙ্গারপ্রিন্ট নেই। ফোনের Settings-এ যোগ করুন, তারপর Account settings থেকে চালু করুন।'),
        FingerprintResult.lockedOut => _t('Too many tries. Wait a little and try again.', 'অনেকবার চেষ্টা হয়েছে। একটু পরে আবার চেষ্টা করুন।'),
        FingerprintResult.cancelled => _t('Not recognised. Touch the sensor again.', 'চেনা যায়নি। আবার সেন্সরে আঙুল রাখুন।'),
        _ => _t('The fingerprint did not work. You can still use your passcode.', 'ফিঙ্গারপ্রিন্ট কাজ করেনি। পাসকোড দিয়েই খুলতে পারবেন।'),
      };
    });
  }

  Future<void> _skip() async {
    if (_step == _Step.create) {
      await AppLockService.instance.addSetupSkip();
    }
    if (mounted) _finish(_step == _Step.finger);
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final small = h < 700;
    final isFinger = _step == _Step.finger;
    final title = switch (_step) {
      _Step.create => widget.forgot ? _t('Choose a new passcode', 'নতুন পাসকোড বেছে নিন') : _t('Create a 4-digit passcode', '৪ সংখ্যার পাসকোড বানান'),
      _Step.confirm => _t('Type it once more', 'আরেকবার দিন'),
      _Step.finger => _t('Use your fingerprint too?', 'আঙুলের ছাপও চালু করবেন?'),
    };
    final sub = switch (_step) {
      _Step.create => _t('You will type it every time you open the app.', 'অ্যাপ খোলার সময় প্রতিবার এটি দিতে হবে।'),
      _Step.confirm => _t('Once more, to be sure you remember it.', 'আরেকবার, যাতে আপনার মনে থাকে।'),
      _Step.finger => _fpState == FingerprintState.notEnrolled
          ? _t('This phone has no fingerprint saved yet.', 'এই ফোনে এখনও কোনো ফিঙ্গারপ্রিন্ট সেভ নেই।')
          : _t('Open the app with one touch. The passcode still works.', 'এক ছোঁয়ায় অ্যাপ খুলুন। পাসকোডও কাজ করবে।'),
    };

    return PopScope(
      canPop: _step == _Step.create && widget.canSkip,
      onPopInvoked: (didPop) {
        if (!didPop && _step == _Step.confirm) {
          setState(() { _step = _Step.create; _typed = ''; _message = null; });
          _pad.currentState?.clear();
        } else if (!didPop && isFinger) {
          _finish(true);
        }
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFE9BF), Color(0xFFFFF8EA), Colors.white])),
          child: SafeArea(
            child: Column(children: [
              Align(
                alignment: Alignment.centerRight,
                child: (widget.canSkip || isFinger) && !_busy
                    ? TextButton(onPressed: _skip, child: Text(isFinger ? _t('Skip', 'পরে') : _t('Not now', 'এখন নয়'), style: const TextStyle(color: Color(0xFF6B5B4B), fontSize: 15)))
                    : const SizedBox(height: 48),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(children: [
                    SizedBox(height: small ? 0 : 12),
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [Color(0xFFE94560), Color(0xFF9F1239)]), boxShadow: [BoxShadow(color: _brand.withOpacity(0.3), blurRadius: 18, offset: const Offset(0, 8))]),
                      child: Icon(isFinger ? Icons.fingerprint_rounded : Icons.lock_rounded, color: Colors.white, size: 34),
                    ),
                    const SizedBox(height: 16),
                    Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: Color(0xFF2B2118))),
                    const SizedBox(height: 6),
                    Text(sub, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Color(0xFF6B5B4B))),
                    SizedBox(height: small ? 14 : 24),
                    if (!isFinger) PinPad(key: _pad, keyHeight: small ? 44 : 52, onChanged: (v) {
                      setState(() { _typed = v; if (v.isNotEmpty) _message = null; });
                      if (v.length == AppLockService.pinLength && !_busy) Future.microtask(_next);   // taken at the 4th digit
                    }),
                    if (isFinger) ...[
                      const SizedBox(height: 8),
                      Icon(_fingerOn ? Icons.check_circle_rounded : Icons.fingerprint_rounded, size: 96, color: _fingerOn ? const Color(0xFF16A34A) : _brand),
                      if (_fingerOn) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_t('Fingerprint is on', 'আঙুলের ছাপ চালু হয়েছে'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF16A34A)))),
                    ],
                    if (isFinger && _fpState == FingerprintState.notEnrolled && !_fingerOn)
                      Padding(padding: const EdgeInsets.only(top: 6), child: Text(_t('Add one in the phone Settings (Biometrics and security > Fingerprints). Then turn it on here: Settings > Account Settings > App lock.', 'ফোনের Settings-এ যোগ করুন (Biometrics and security > Fingerprints)। তারপর এখানে চালু করুন: Settings > Account Settings > App lock।'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Color(0xFF6B5B4B)))),
                    if (_message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_message!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13.5))),
                    const SizedBox(height: 18),
                    if (!isFinger)
                      SizedBox(height: 52, child: Center(child: _busy ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4, color: _brand)) : null))
                    else if (_fpState == FingerprintState.ready && !_fingerOn)
                      _BigButton(label: _t('Turn on fingerprint', 'আঙুলের ছাপ চালু করুন'), icon: Icons.fingerprint_rounded, onTap: _busy ? null : _enableFingerprint, busy: _busy)
                    else if (!_fingerOn)
                      _BigButton(label: _t('Done', 'ঠিক আছে'), onTap: () => Navigator.of(context).pop(true)),
                    const SizedBox(height: 24),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({required this.label, required this.onTap, this.icon, this.busy = false});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(colors: on ? const [Color(0xFFE94560), Color(0xFFC62828)] : [Colors.grey.shade300, Colors.grey.shade300]),
          boxShadow: on ? [BoxShadow(color: const Color(0xFFE94560).withOpacity(0.32), blurRadius: 14, offset: const Offset(0, 6))] : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Center(
              child: busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      if (icon != null) ...[Icon(icon, color: Colors.white), const SizedBox(width: 8)],
                      Text(label, style: TextStyle(color: on ? Colors.white : Colors.grey.shade600, fontSize: 17, fontWeight: FontWeight.w700)),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}
