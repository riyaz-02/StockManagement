import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../services/app_lock_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/login_slides_service.dart';
import '../utils/app_toast.dart';
import '../utils/fast_route.dart';
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
  final _poster = PageController();
  final _page = ValueNotifier<int>(0);
  Timer? _timer;

  bool get _bn => Provider.of<LanguageProvider>(context, listen: false).currentLanguage == 'bn';
  String _t(String en, String bn) => _bn ? bn : en;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.isLocked) _mode = _Mode.pin;
    unawaited(LoginSlidesService.instance.cached().then((_) => LoginSlidesService.instance.refresh()));
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      final n = LoginSlidesService.instance.slides.value.length;
      if (!mounted || n < 2 || !_poster.hasClients) return;
      _poster.animateToPage((_page.value + 1) % n, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    });
    if (_mode == _Mode.pin) WidgetsBinding.instance.addPostFrameCallback((_) => _prepareFingerprint());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _poster.dispose();
    _page.dispose();
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

  /// Right passcode / fingerprint: Home opens at once. The saved session is renewed in the background; if the server no longer
  /// accepts it (a long time unused, or the account was turned off) the person is taken back to the password form.
  Future<void> _afterUnlock() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    auth.unlock();
    _goToHome();
    unawaited(auth.refreshSession().then((s) async {
      if (s != 'expired') return;
      await auth.logout();
      appNavigatorKey.currentState?.pushAndRemoveUntil(fastRoute(const LoginScreen()), (_) => false);
    }));
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

  /// After a password sign-in: choose a (new) passcode.
  Future<void> _offerQuickUnlock(AuthProvider auth) async {
    if (_forgot) await auth.removePasscode();
    final has = await auth.hasLock();
    if (has || !mounted) return;
    // every open of the app asks for the passcode, so choosing one is not optional (the fingerprint on top is)
    await Navigator.of(context).push<bool>(fastRoute(QuickUnlockSetupScreen(forgot: _forgot, canSkip: false)));
  }

  void _goToHome() {
    Navigator.of(context).pushReplacement(fastRoute(const MainNavigationScreen()));
  }

  // ── build ───────────────────────────────────────────────────────────────────────────────────────

  /// The strip under the status bar that holds the shop logo in the password form: always the same, on plain white. The
  /// picture starts below it, so nothing of a picture is ever hidden behind the logo.
  static const double _headerH = 62;

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final bn = lang.currentLanguage == 'bn';
    final mq = MediaQuery.of(context);
    final h = mq.size.height;
    final kb = mq.viewInsets.bottom;
    final top = mq.padding.top;
    final posterTop = top + _headerH;

    // Both screens (passcode and password) look the same: the logo on a white strip at the top, the picture filling the rest
    // of the screen behind everything (the keyboard never resizes it), and the form in white on a dark shade that lies
    // over the lower part of the picture and rises with the form when the keyboard opens.
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
        child: Stack(children: [
          Positioned(
            top: posterTop,
            left: 0,
            right: 0,
            bottom: 0,
            child: ValueListenableBuilder<List<LoginSlide>>(
              valueListenable: LoginSlidesService.instance.slides,
              builder: (_, slides, __) => _Posters(slides: slides, controller: _poster, onPage: (i) => _page.value = i),
            ),
          ),
          // a soft white fade: the picture does not start with a hard edge
          Positioned(top: posterTop, left: 0, right: 0, height: 64, child: const IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, Color(0xCCFFFFFF), Color(0x00FFFFFF)], stops: [0, 0.35, 1]))))),
          // the logo of the shop: always here, on plain white
          Positioned(top: 0, left: 0, right: 0, height: posterTop, child: Container(color: Colors.white, padding: EdgeInsets.only(top: top), child: Center(child: _logo(40)))),
          Positioned(
            left: 0,
            right: 0,
            bottom: kb,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: h - kb - posterTop),
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xBF000000), Color(0xF2000000)], stops: [0, 0.2, 0.5])),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _caption(bn),
                  Flexible(child: _sheet(lang, bn, h < 700)),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _logo(double height) => Image.asset(
        'assets/images/lgp_logo_red.png',
        height: height,
        errorBuilder: (_, __, ___) => Icon(Icons.diamond, color: _brand, size: height),
      );

  /// The words of the picture that is showing (no dots: the pictures just change by themselves).
  Widget _caption(bool bn) {
    return ValueListenableBuilder<List<LoginSlide>>(
      valueListenable: LoginSlidesService.instance.slides,
      builder: (_, slides, __) => ValueListenableBuilder<int>(
        valueListenable: _page,
        builder: (_, page, __) {
          final cap = slides.isEmpty ? '' : slides[page.clamp(0, slides.length - 1)].caption(bn);
          if (cap.isEmpty) return const SizedBox(width: double.infinity, height: 56);
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 56, 24, 4),
            child: Text(cap, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, height: 1.25, shadows: [Shadow(color: Color(0x99000000), blurRadius: 10)])),
          );
        },
      ),
    );
  }

  // The form. Passcode: straight on the dark veil of the picture. Password: on a light veil that lets the picture show through.
  Widget _sheet(LanguageProvider lang, bool bn, bool small) {
    final pin = _mode == _Mode.pin;
    return Container(
      width: double.infinity,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 170),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero).animate(anim), child: child)),
            child: Column(
              key: ValueKey(_mode),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: pin ? _pinChildren(small) : _passwordChildren(lang, bn),
            ),
          ),
          ),
        ),
      ),
    );
  }

  // The passcode window (white on the dark veil).
  List<Widget> _pinChildren(bool small) {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    final name = (user?.name ?? '').trim();
    return [
      Text(name.isEmpty ? _t('Welcome back', 'আবার স্বাগতম') : '${_t('Welcome back', 'আবার স্বাগতম')}, $name', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, color: Color(0xE6FFFFFF), shadows: [Shadow(color: Color(0x99000000), blurRadius: 8)])),
      SizedBox(height: small ? 2 : 4),
      Text(_t('Enter your passcode', 'পাসকোড দিন'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.2)),
      SizedBox(height: small ? 4 : 6),
      PinPad(key: _pad, dark: true, keyHeight: small ? 42 : 46, onFingerprint: _fingerprint ? () => _useFingerprint() : null, onChanged: (v) {
        setState(() { _pin = v; if (v.isNotEmpty) _message = null; });
        if (v.length == AppLockService.pinLength) _submitPin();   // checked at the 4th digit
      }),
      // a fixed line: a message appearing must not move the keys under the finger of the person
      SizedBox(height: 28, child: Center(child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white)) : Text(_message ?? '', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFFFB4BC), fontSize: 13.5, fontWeight: FontWeight.w600)))),
      TextButton(
        onPressed: _busy ? null : () => setState(() { _forgot = true; _mode = _Mode.password; _message = null; }),
        child: Text(_t('Forgot passcode?', 'পাসকোড ভুলে গেছেন?'), style: const TextStyle(color: Color(0xFFFFD1D6), fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    ];
  }

  // The mobile + password form.
  List<Widget> _passwordChildren(LanguageProvider lang, bool bn) {
    final canGoBack = Provider.of<AuthProvider>(context, listen: false).isLocked;
    InputDecoration deco(String label, IconData icon, {Widget? suffix}) => InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF8A7B69), fontSize: 14.5),
          floatingLabelStyle: const TextStyle(color: _brand, fontWeight: FontWeight.w600),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 10, right: 6),
            child: Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFFFDE8EC), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: _brand, size: 17),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 46),
          suffixIcon: suffix,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFEDE3D2))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFEDE3D2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _brand, width: 1.6)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFDC2626))),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.6)),
        );
    Widget lifted(Widget field) => Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 14, offset: Offset(0, 5))]),
          child: field,
        );
    return [
      Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(lang.t('welcome_back'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1, shadows: [Shadow(color: Color(0x99000000), blurRadius: 8)])),
                const SizedBox(height: 3),
                Text(_forgot ? _t('Sign in with your password, then choose a new passcode.', 'পাসওয়ার্ড দিয়ে লগইন করুন, তারপর নতুন পাসকোড বেছে নিন।') : lang.t('login_to_continue'), style: const TextStyle(fontSize: 13, color: Color(0xE6FFFFFF), shadows: [Shadow(color: Color(0x99000000), blurRadius: 8)])),
              ]),
            ),
            const SizedBox(width: 8),
            _LangSwitch(bn: bn, onBn: () => lang.changeLanguage('bn'), onEn: () => lang.changeLanguage('en')),
          ]),
          const SizedBox(height: 16),
          if (_message != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_message!, style: const TextStyle(color: Color(0xFFFFB4BC), fontSize: 13.5, fontWeight: FontWeight.w600))),
          lifted(TextFormField(
            controller: _mobileController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 16, fontWeight: FontWeight.w500),
            decoration: deco(lang.t('mobile_number'), Icons.phone_iphone_rounded),
            validator: (v) => (v == null || v.trim().isEmpty) ? lang.t('mobile_number') : null,
          )),
          const SizedBox(height: 10),
          lifted(TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _handleLogin(),
            style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 16, fontWeight: FontWeight.w500),
            decoration: deco(lang.t('password'), Icons.lock_rounded, suffix: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey[600], size: 21), onPressed: () => setState(() => _obscurePassword = !_obscurePassword))),
            validator: (v) => (v == null || v.isEmpty) ? lang.t('password') : null,
          )),
          const SizedBox(height: 14),
          _LoginButton(label: _t('Login', 'লগইন'), busy: _busy, onTap: _busy ? null : _handleLogin, onDark: true),
        ]),
      ),
      if (canGoBack)
        TextButton(
          onPressed: _busy ? null : () => setState(() { _mode = _Mode.pin; _forgot = false; _message = null; }),
          child: Text(_t('Back to passcode', 'পাসকোডে ফিরুন'), style: const TextStyle(color: Color(0xFFFFD1D6), fontSize: 15, fontWeight: FontWeight.w700)),
        )
      else
        const SizedBox(height: 6),
      const AppVersionText(style: TextStyle(color: Color(0x99FFFFFF), fontSize: 11.5)),
    ];
  }
}

/// The pictures (4:5, portrait: the same ones the website shows). Each is shown at the full width of the phone, from the top; the
/// rest of the screen below it is filled by a soft blurred copy of the same picture, and the picture melts into it, so a 4:5 picture
/// is never cropped and never leaves an empty band. With none uploaded the page is a wine-coloured background.
class _Posters extends StatelessWidget {
  const _Posters({required this.slides, required this.controller, required this.onPage});
  final List<LoginSlide> slides;
  final PageController controller;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    if (slides.isEmpty) {
      return Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF8E2540), Color(0xFF2B0F18)])),
        child: const Align(alignment: Alignment(0, -0.35), child: Icon(Icons.diamond_outlined, size: 120, color: Color(0x55FFFFFF))),
      );
    }
    return PageView.builder(
      controller: controller,
      itemCount: slides.length,
      onPageChanged: onPage,
      itemBuilder: (_, i) => _Poster(url: slides[i].imageUrl),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    const none = Duration.zero;
    return Stack(fit: StackFit.expand, children: [
      // the soft copy that fills the whole area (a tiny decode, then blurred: cheap)
      ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22, tileMode: TileMode.clamp),
        child: CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, memCacheWidth: 96, fadeInDuration: none, fadeOutDuration: none, placeholder: (_, __) => const ColoredBox(color: Color(0xFF2B0F18)), errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFF2B0F18))),
      ),
      const ColoredBox(color: Color(0x40000000)),
      // the sharp picture at the full width, melting into the soft copy at its foot
      Align(
        alignment: Alignment.topCenter,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, Colors.white, Color(0x00FFFFFF)], stops: [0, 0.78, 1]).createShader(r),
          child: CachedNetworkImage(imageUrl: url, width: double.infinity, fit: BoxFit.fitWidth, alignment: Alignment.topCenter, fadeInDuration: none, fadeOutDuration: none, placeholder: (_, __) => const Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFFE9B949)))), errorWidget: (_, __, ___) => const SizedBox.shrink()),
        ),
      ),
    ]);
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({required this.label, required this.onTap, this.busy = false, this.onDark = false});
  final String label;
  final VoidCallback? onTap;
  final bool busy, onDark;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    final off = onDark ? const Color(0x40FFFFFF) : Colors.grey.shade300;
    return SizedBox(
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: on || busy ? const [Color(0xFFEF4B66), Color(0xFFC62436)] : [off, off]),
          boxShadow: on ? [BoxShadow(color: const Color(0xFFE94560).withOpacity(0.38), blurRadius: 18, offset: const Offset(0, 8))] : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Center(
              child: busy
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(label, style: TextStyle(color: on ? Colors.white : (onDark ? const Color(0xB3FFFFFF) : Colors.grey.shade600), fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                      if (on) ...[const SizedBox(width: 8), const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20)],
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bengali / English as one little switch.
class _LangSwitch extends StatelessWidget {
  const _LangSwitch({required this.bn, required this.onBn, required this.onEn});
  final bool bn;
  final VoidCallback onBn, onEn;

  Widget _seg(String label, bool on, VoidCallback tap) => GestureDetector(
        onTap: tap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: on ? const [BoxShadow(color: Color(0x1F000000), blurRadius: 6, offset: Offset(0, 2))] : null,
          ),
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? const Color(0xFFC63A55) : Colors.white)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0x38FFFFFF), borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0x4DFFFFFF))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [_seg('বাংলা', bn, onBn), _seg('EN', !bn, onEn)]),
    );
  }
}
