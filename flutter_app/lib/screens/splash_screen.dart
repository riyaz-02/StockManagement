import '../services/server_health.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:jewellery_stock_app/providers/auth_provider.dart';
import 'package:jewellery_stock_app/providers/language_provider.dart';
import 'package:jewellery_stock_app/screens/login_screen.dart';
import 'package:jewellery_stock_app/screens/main_navigation_screen.dart';
import 'package:jewellery_stock_app/screens/server_startup_screen.dart';
import 'package:jewellery_stock_app/services/live_reactions.dart';
import 'package:jewellery_stock_app/services/api_service.dart';
import 'package:jewellery_stock_app/screens/quick_unlock_setup_screen.dart';
import 'package:jewellery_stock_app/utils/fast_route.dart';
import 'package:jewellery_stock_app/services/login_slides_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  String _appVersionText = '';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 900),
      // Fading out only needs to be quick, not match the entrance — the old shared duration made every start-up
      // wait a full extra 1.2s just to leave the splash screen.
      reverseDuration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
    _animationController.forward();
    _initialize();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// Is the server ready? Retries a few times (a slow first connection must not read as "server off").
  Future<bool> _isServerOnline() async => (await ServerHealth.check(attempts: 3)) == ServerState.online;

  Future<void> _loadAppVersionText() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      // kept on every bill made with this app, so it is known which build made it
      ApiService.appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      if (mounted) {
        setState(() => _appVersionText = 'Version ${packageInfo.version}');
      }
    } catch (_) {
      // Keep the blank fallback — non-critical display text.
    }
  }

  Future<void> _initialize() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final languageProvider =
        Provider.of<LanguageProvider>(context, listen: false);

    // Initialize language (local, fast) and check server in parallel with splash delay
    await languageProvider.initialize();
    await ServerHealth.restore();
    unawaited(_loadAppVersionText());

    final results = await Future.wait([
      _isServerOnline(),
      Future.delayed(const Duration(milliseconds: 900)),
    ]);

    final serverOnline = results[0] as bool;

    // Fade out splash
    await _animationController.reverse();

    if (!mounted) return;

    if (!serverOnline) {
      // EC2 is stopped — show Bengali startup screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ServerStartupScreen()),
      );
      return;
    }

    // The update check runs in the background from here on: it must never delay sign-in. A forced update still
    // blocks the app once its popup appears (see update_dialog.dart) — just on the Home/Login screen instead of
    // stalling here on the splash.

    // Server is online — check auth token
    await authProvider.initialize();
    if (!mounted) return;
    // the sign-in screen's pictures: fetched now so they are ready when it opens (the last ones are kept on the phone)
    unawaited(LoginSlidesService.instance.refresh());

    // A remembered person with a passcode / fingerprint goes to the lock screen (LoginScreen). One without goes straight
    // in, after the saved session is renewed: if the server no longer accepts it, they sign in again.
    var openHome = authProvider.isAuthenticated && !authProvider.isLocked;
    if (openHome && await authProvider.refreshSession() == 'expired') {
      await authProvider.logout();
      openHome = false;
    }
    if (!mounted) return;

    if (openHome && !(await authProvider.hasLock())) {
      // a remembered person without a passcode (a phone from before passcodes): the app asks for one first, then opens
      if (!mounted) return;
      Navigator.of(context).pushReplacement(fastRoute(QuickUnlockSetupScreen(canSkip: false, then: (c) => Navigator.of(c).pushReplacement(fastRoute(const MainNavigationScreen())))));
    } else if (openHome) {
      Navigator.of(context).pushReplacement(fastRoute(const MainNavigationScreen()));
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }

    // Only now, once the first real screen is in place: a pop-up opened while the splash was still being replaced was
    // swapped out with it, which is why "Update available" showed only sometimes.
    Future.delayed(const Duration(milliseconds: 1200), () => unawaited(LiveReactions.checkAppUpdate()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // White base
          Container(
            color: Colors.white,
          ),
          // Decorative circles (matching home page)
          Positioned(
            right: -100,
            top: -100,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE94560).withOpacity(0.12),
              ),
            ),
          ),
          Positioned(
            left: -80,
            bottom: -80,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF667EEA).withOpacity(0.1),
              ),
            ),
          ),
          Positioned(
            right: 5,
            top: 5,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF6B9D).withOpacity(0.1),
              ),
            ),
          ),
          // Content with animations
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated Shop Logo - 80% width with auto height
                AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return FadeTransition(
                      opacity: _fadeAnimation,
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        child: FractionallySizedBox(
                          widthFactor: 0.8,
                          child: Image.asset(
                            'assets/images/lgp_logo_red.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.diamond,
                                color: Color(0xFFE94560),
                                size: 120,
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Glassmorphism Loading Card
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.4),
                              Colors.white.withOpacity(0.25),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFE94560).withOpacity(0.3),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  const Color(0xFFE94560),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Text(
                              'Loading...',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Copyright footer
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    children: [
                      Text(
                        '© Laltu Guinea Palace',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                      if (_appVersionText.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _appVersionText,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
