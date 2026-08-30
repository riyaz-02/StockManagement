import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:jewellery_stock_app/providers/auth_provider.dart';
import 'package:jewellery_stock_app/providers/language_provider.dart';
import 'package:jewellery_stock_app/screens/login_screen.dart';
import 'package:jewellery_stock_app/screens/main_navigation_screen.dart';
import 'package:jewellery_stock_app/screens/server_startup_screen.dart';
import 'package:jewellery_stock_app/services/api_service.dart';
import 'package:jewellery_stock_app/models/app_version_model.dart';
import 'package:jewellery_stock_app/widgets/update_dialog.dart';
import 'package:jewellery_stock_app/utils/app_constants.dart';

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
      duration: const Duration(milliseconds: 1200),
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

  /// Returns true if the server is reachable (any HTTP response code < 500).
  Future<bool> _isServerOnline() async {
    try {
      final response = await http
          .get(Uri.parse(AppConstants.healthCheckUrl))
          .timeout(const Duration(seconds: 5));
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadAppVersionText() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersionText = 'Version ${packageInfo.version}');
      }
    } catch (_) {
      // Keep the blank fallback — non-critical display text.
    }
  }

  /// Checks the backend-controlled app version and shows the update dialog
  /// if a newer build is available. Never throws — a failed check should
  /// never block someone from using the app.
  Future<void> _checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

      final response = await ApiService().getAppVersion();
      if (response['success'] != true) return;

      final config = AppVersionConfig.fromJson(response['data']['appVersion']);
      if (config.latestVersionCode > currentBuildNumber && mounted) {
        await showUpdateDialog(context, config);
      }
    } catch (_) {
      // Ignore — update check is best-effort.
    }
  }

  Future<void> _initialize() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final languageProvider =
        Provider.of<LanguageProvider>(context, listen: false);

    // Initialize language (local, fast) and check server in parallel with splash delay
    await languageProvider.initialize();
    unawaited(_loadAppVersionText());

    final results = await Future.wait([
      _isServerOnline(),
      Future.delayed(const Duration(milliseconds: 1500)),
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

    // Server is online — check for a mandatory/optional update before
    // letting the user any further into the app.
    await _checkForUpdate();
    if (!mounted) return;

    // Server is online — check auth token
    await authProvider.initialize();
    if (!mounted) return;

    if (authProvider.isAuthenticated) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
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
