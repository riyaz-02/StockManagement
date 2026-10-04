import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../services/app_lock_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/login_slides_service.dart';
import '../utils/app_toast.dart';
import '../widgets/app_version_text.dart';
import '../widgets/pin_pad.dart';
import 'main_navigation_screen.dart';
import 'quick_unlock_setup_screen.dart';

enum _Mode { pin, password }

/// The first screen of the app.
///  - A person is remembered on this phone and has a passcode: the pictures on top, the passcode boxes below (or the
///    fingerprint, when it is on). "Forgot passcode?" opens the mobile + password form.
///  - Nobody is remembered (first time, or after signing out): the mobile + password form.
/// After a password sign-in the phone remembers the person (see AuthProvider) and offers to set a passcode.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _brand = Color(0xFFC63A55);
  final _formKey = GlobalKey<FormState>();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pad = GlobalKey<PinPadState>();
  _Mode _mode = _Mode.password;
  bool _forgot = false; // came through "Forgot passcode?": choose a new one after signing in
  bool _obscurePassword = true;
  bool _busy = false;
  bool _fingerprint = false;
  String _pin = '';
  String? _message;

  bool get _bn => Provider.of<LanguageProvider>(context, listen: false).currentLanguage == 'bn';
  String _t(String en, String bn) => _bn ? bn : en;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.isLocked) _mode = _Mode.pin;
    unawaited(LoginSlidesService.instance.cached().then((_) => LoginSlidesService.instance.refresh()));
    if (_mode == _Mode.pin) WidgetsBinding.instance.addPostFrameCallback((_) => _prepareFingerprint());
  }

  @override
  void dispose() {
    _mobileController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── passcode / fingerprint ────────────────────────────────────────────────────────────────────────

  Future<void> _prepareFingerprint() async {
    final on = await AppLockService.instance.fingerprintOn();
    final ready = on && (await BiometricAuthService().state()) == FingerprintState.ready;
    if (!mounted) return;
    setState(() => _fingerprint = ready);
    if (ready) await _useFingerprint(auto: true);
  }

  Future<void> _useFingerprint({bool auto = false}) async {
    if (_busy) return;
    final r = await BiometricAuthService().scan(reason: _t('Touch the fingerprint sensor to open the app', 'অ্যাপ খুলতে ফিঙ্গারপ্রিন্ট সেন্সরে আঙুল রাখুন'));
    if (!mounted) return;
    if (r == FingerprintResult.success) {
      await _afterUnlock();
    } else if (!auto && r != FingerprintResult.cancelled) {
      setState(() => _message = r == FingerprintResult.lockedOut
          ? _t('Fingerprint is locked for a while. Use your passcode.', 'ফিঙ্গারপ্রিন্ট কিছুক্ষণ বন্ধ। পাসকোড ব্যবহার করুন।')
          : _t('The fingerprint did not work. Use your passcode.', 'ফিঙ্গারপ্রিন্ট কাজ করেনি। পাসকোড ব্যবহার করুন।'));
    }
  }

  Future<void> _submitPin() async {
    if (_pin.length != AppLockService.pinLength || _busy) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    setState(() { _busy = true; _message = null; });
    final r = await auth.lock.verifyPin(_pin);
    if (!mounted) return;
    switch (r.check) {
      case PinCheck.ok:
        await _afterUnlock();
        return;
      case PinCheck.wrong:
        setState(() { _busy = false; _message = _t('Wrong passcode. ${r.triesLeft} ${r.triesLeft == 1 ? 'try' : 'tries'} left.', 'ভুল পাসকোড। আর ${r.triesLeft} বার চেষ্টা করতে পারবেন।'); });
        _pad.currentState?.shake();
        return;
      case PinCheck.tooMany:
        setState(() {
          _busy = false;
          _forgot = true;
          _mode = _Mode.password;
          _message = _t('Too many wrong tries. Please sign in with your password.', 'অনেকবার ভুল হয়েছে। পাসওয়ার্ড দিয়ে লগইন করুন।');
        });
        return;
      case PinCheck.notSet:
        setState(() { _busy = false; _forgot = true; _mode = _Mode.password; });
        return;
    }
  }

  Future<void> _afterUnlock() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    setState(() => _busy = true);
    final s = await auth.refreshSession();
    if (!mounted) return;
    if (s == 'expired') {
      // the server no longer accepts this phone's session (a long time unused, or the account was turned off)
      await auth.logout();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _mode = _Mode.password;
        _message = _t('Your session has ended. Please sign in again.', 'আপনার সেশন শেষ হয়েছে। আবার লগইন করুন।');
      });
      return;
    }
    auth.unlock();
    _goToHome();
  }

  // ── password sign-in ─────────────────────────────────────────────────────────────────────────────

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    setState(() { _busy = true; _message = null; });
    final ok = await auth.login(_mobileController.text.trim(), _passwordController.text);
    if (!mounted) return;
    if (!ok) {
      setState(() => _busy = false);
      showAppSnackBar(
        context,
        SnackBar(content: Text(auth.error ?? 'Login failed'), backgroundColor: _brand, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      );
      return;
    }
    await _offerQuickUnlock(auth);
    if (mounted) _goToHome();
  }

  /// After a password sign-in: choose a (new) passcode. Asked again at most once if the person skipped it; Account settings
  /// always has it.
  Future<void> _offerQuickUnlock(AuthProvider auth) async {
    if (_forgot) await auth.removePasscode();
    final has = await auth.hasLock();
    final skips = await AppLockService.instance.setupSkips();
    if (has || skips >= 2 || !mounted) return;
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => QuickUnlockSetupScreen(forgot: _forgot)));
  }

  void _goToHome() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainNavigationScreen()));
  }

  // ── build ───────────────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final bn = lang.currentLanguage == 'bn';
    final keyboard = MediaQuery.of(context).viewInsets.bottom > 0;
    final h = MediaQuery.of(context).size.height;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFFFF4DE),
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFE6B8), Color(0xFFFFF4DE), Color(0xFFFFFBF3)])),
        child: Column(children: [
          Expanded(
            child: keyboard
                ? SafeArea(bottom: false, child: Align(alignment: Alignment.center, child: Padding(padding: const EdgeInsets.only(top: 8), child: _logo(34))))
                : ValueListenableBuilder<List<LoginSlide>>(
                    valueListenable: LoginSlidesService.instance.slides,
                    builder: (_, slides, __) => _Hero(slides: slides, bn: bn, logo: _logo),
                  ),
          ),
          Flexible(flex: 0, child: _sheet(lang, bn, h < 700)),
        ]),
      ),
    );
  }

  Widget _logo(double height) => Image.asset(
        'assets/images/lgp_logo_red.png',
        height: height,
        errorBuilder: (_, __, ___) => Icon(Icons.diamond, color: _brand, size: height),
      );

  Widget _sheet(LanguageProvider lang, bool bn, bool small) {
    final pin = _mode == _Mode.pin;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 22, offset: Offset(0, -6))],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Column(
              key: ValueKey(_mode),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: pin ? _pinChildren(small) : _passwordChildren(lang, bn),
            ),
          ),
        ),
      ),
    );
  }

  // The passcode window.
  List<Widget> _pinChildren(bool small) {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    final name = (user?.name ?? '').trim();
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final ready = _pin.length == AppLockService.pinLength && !_busy;
    return [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: const Color(0xFFFDEBD0),
          backgroundImage: (user?.profileImage ?? '').startsWith('http') ? CachedNetworkImageProvider(user!.profileImage!) : null,
          child: (user?.profileImage ?? '').startsWith('http') ? null : Text(initial, style: const TextStyle(color: _brand, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 10),
        Flexible(child: Text(name.isEmpty ? _t('Welcome back', 'আবার স্বাগতম') : '${_t('Welcome back', 'আবার স্বাগতম')}, $name', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, color: Color(0xFF6B5B4B)))),
      ]),
      SizedBox(height: small ? 6 : 10),
      Text(_t('Enter passcode', 'পাসকোড দিন'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF2B2118))),
      SizedBox(height: small ? 10 : 14),
      PinPad(key: _pad, keyHeight: small ? 40 : 46, onFingerprint: _fingerprint ? () => _useFingerprint() : null, onChanged: (v) => setState(() { _pin = v; if (v.isNotEmpty) _message = null; })),
      // a fixed line: a message appearing must not move the keys under the person's finger
      SizedBox(height: 26, child: Center(child: Text(_message ?? '', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13.5)))),
      _LoginButton(label: _t('Login', 'লগইন'), busy: _busy, onTap: ready ? _submitPin : null),
      TextButton(
        onPressed: _busy ? null : () => setState(() { _forgot = true; _mode = _Mode.password; _message = null; }),
        child: Text(_t('Forgot passcode?', 'পাসকোড ভুলে গেছেন?'), style: const TextStyle(color: Color(0xFFE53935), fontSize: 15, fontWeight: FontWeight.w500)),
      ),
      const AppVersionText(style: TextStyle(color: Color(0xFFB0A596), fontSize: 11.5)),
    ];
  }

  // The mobile + password form.
  List<Widget> _passwordChildren(LanguageProvider lang, bool bn) {
    final canGoBack = Provider.of<AuthProvider>(context, listen: false).isLocked;
    InputDecoration deco(String label, IconData icon, {Widget? suffix}) => InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF7A6B5B), fontSize: 14),
          prefixIcon: Icon(icon, color: _brand, size: 21),
          suffixIcon: suffix,
          filled: true,
          fillColor: const Color(0xFFF8F4EC),
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _brand, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDC2626))),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5)),
        );
    return [
      Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(lang.t('welcome_back'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: Color(0xFF2B2118)))),
            _LangChip(label: 'বাংলা', on: bn, onTap: () => lang.changeLanguage('bn')),
            const SizedBox(width: 6),
            _LangChip(label: 'EN', on: !bn, onTap: () => lang.changeLanguage('en')),
          ]),
          const SizedBox(height: 2),
          Text(_forgot ? _t('Sign in with your password, then choose a new passcode.', 'পাসওয়ার্ড দিয়ে লগইন করুন, তারপর নতুন পাসকোড বেছে নিন।') : lang.t('login_to_continue'), style: const TextStyle(fontSize: 13, color: Color(0xFF7A6B5B))),
          const SizedBox(height: 14),
          if (_message != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_message!, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13.5))),
          TextFormField(
            controller: _mobileController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 15),
            decoration: deco(lang.t('mobile_number'), Icons.phone_rounded),
            validator: (v) => (v == null || v.trim().isEmpty) ? lang.t('mobile_number') : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _handleLogin(),
            style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 15),
            decoration: deco(lang.t('password'), Icons.lock_rounded, suffix: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey[600], size: 20), onPressed: () => setState(() => _obscurePassword = !_obscurePassword))),
            validator: (v) => (v == null || v.isEmpty) ? lang.t('password') : null,
          ),
          const SizedBox(height: 16),
          _LoginButton(label: _t('Login', 'লগইন'), busy: _busy, onTap: _busy ? null : _handleLogin),
        ]),
      ),
      if (canGoBack)
        TextButton(
          onPressed: _busy ? null : () => setState(() { _mode = _Mode.pin; _forgot = false; _message = null; }),
          child: Text(_t('Back to passcode', 'পাসকোডে ফিরুন'), style: const TextStyle(color: _brand, fontSize: 14.5)),
        )
      else
        const SizedBox(height: 6),
      const AppVersionText(style: TextStyle(color: Color(0xFFB0A596), fontSize: 11.5)),
    ];
  }
}

/// The pictures (or, with none uploaded, the shop's logo) above the sheet: they change by themselves every few seconds.
class _Hero extends StatefulWidget {
  const _Hero({required this.slides, required this.bn, required this.logo});
  final List<LoginSlide> slides;
  final bool bn;
  final Widget Function(double) logo;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || widget.slides.length < 2 || !_controller.hasClients) return;
      _controller.animateToPage((_page + 1) % widget.slides.length, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;
    return SafeArea(
      bottom: false,
      child: slides.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(30), child: widget.logo(88)))
          : Column(children: [
              Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: widget.logo(30)),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: slides.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) {
                    final s = slides[i];
                    final cap = s.caption(widget.bn);
                    return Column(children: [
                      if (cap.isNotEmpty)
                        Padding(padding: const EdgeInsets.fromLTRB(24, 10, 24, 0), child: Text(cap, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Color(0xFF2B2118), height: 1.25))),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: CachedNetworkImage(
                            imageUrl: s.imageUrl,
                            fit: BoxFit.contain,
                            fadeInDuration: const Duration(milliseconds: 250),
                            placeholder: (_, __) => const Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFFE9B949)))),
                            errorWidget: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ]);
                  },
                ),
              ),
              if (slides.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, top: 2),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 0; i < slides.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _page ? 26 : 9,
                        height: 9,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: i == _page ? const Color(0xFFE9A21B) : const Color(0xFFFBD98A)),
                      ),
                  ]),
                ),
            ]),
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({required this.label, required this.onTap, this.busy = false});
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return SizedBox(
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(colors: on || busy ? const [Color(0xFFE94560), Color(0xFFC62828)] : [Colors.grey.shade300, Colors.grey.shade300]),
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
                  : Text(label, style: TextStyle(color: on ? Colors.white : Colors.grey.shade600, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            ),
          ),
        ),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFC63A55) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? const Color(0xFFC63A55) : const Color(0xFFE2D8C8)),
        ),
        child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? Colors.white : const Color(0xFF6B5B4B))),
      ),
    );
  }
}
