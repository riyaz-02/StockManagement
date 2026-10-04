import '../services/server_health.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../utils/app_constants.dart';
import 'login_screen.dart';
import 'main_navigation_screen.dart';

enum _ServerState { idle, starting, online, error }

class ServerStartupScreen extends StatefulWidget {
  const ServerStartupScreen({super.key});

  @override
  State<ServerStartupScreen> createState() => _ServerStartupScreenState();
}

class _ServerStartupScreenState extends State<ServerStartupScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  _ServerState _state = _ServerState.idle;
  String _statusMessage = 'অ্যাপ ব্যবহার করতে সার্ভার চালু করুন';
  int _pollCount = 0;
  static const int _maxPolls = 48; // 48 × 5s = 4 minutes max
  Timer? _pollTimer;
  bool _checkingServer = false;
  bool _navigating = false;
  String _appVersionText = '';

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const Color _primary = Color(0xFFE94560);
  static const Color _bgLight = Color(0xFFFFF5F7);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadAppVersionText();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startPassiveMonitoring());
    });
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_tick());
    }
  }

  // ── Check if server is reachable ──────────────────────────────────────────
  // One shared checker (services/server_health.dart): retries, understands "starting", remembers a working address.
  ServerState _last = ServerState.offline;

  Future<bool> _isServerOnline({int attempts = 1}) async {
    _last = await ServerHealth.check(attempts: attempts);
    return _last == ServerState.online;
  }

  // ONE timer drives everything: it checks every few seconds, never two checks at once, and never a second timer.
  void _restartTimer(Duration every) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(every, (_) => unawaited(_tick()));
  }

  Future<void> _startPassiveMonitoring() async {
    // The server may already be up (or started by someone else): check straight away, with retries, then keep watching.
    if (await _isServerOnline(attempts: 3)) {
      await _continueWhenOnline();
      return;
    }
    if (!mounted || _navigating) return;
    if (_last == ServerState.starting) _showStarting();
    _restartTimer(const Duration(seconds: 5));
  }

  void _showStarting() {
    if (!mounted || _navigating) return;
    setState(() {
      _state = _ServerState.starting;
      _statusMessage = 'সার্ভার চালু হচ্ছে...\nঅনুগ্রহ করে অপেক্ষা করুন';
    });
  }

  Future<void> _tick() async {
    if (!mounted || _checkingServer || _navigating) return;
    _checkingServer = true;
    try {
      final online = await _isServerOnline();
      if (!mounted) return;
      if (online) {
        await _continueWhenOnline();
        return;
      }
      if (_state != _ServerState.starting && _state != _ServerState.error) {
        // passive watching: nothing to show, keep waiting for the user to tap Start (or for the server to appear)
        if (_last == ServerState.starting) _showStarting();
        return;
      }
      _pollCount++;
      if (_pollCount >= _maxPolls) {
        _pollTimer?.cancel();
        setState(() {
          _state = _ServerState.error;
          _statusMessage = 'সার্ভার চালু করতে ব্যর্থ হয়েছে। পুনরায় চেষ্টা করুন।';
        });
      } else {
        final secondsWaited = _pollCount * 5;
        setState(() {
          _statusMessage = _last == ServerState.starting
              ? 'সার্ভার প্রায় তৈরি... ($secondsWaited সেকেন্ড হয়েছে)'
              : 'সার্ভার চালু হচ্ছে... ($secondsWaited সেকেন্ড হয়েছে)';
        });
      }
    } finally {
      _checkingServer = false;
    }
  }

  Future<void> _continueWhenOnline() async {
    if (!mounted || _navigating) return;

    _navigating = true;
    _pollTimer?.cancel();
    setState(() {
      _state = _ServerState.online;
      _statusMessage = 'সার্ভার চালু হয়েছে! এগিয়ে যাচ্ছি...';
    });
    await Future.delayed(const Duration(milliseconds: 400));
    await _navigateNext();
  }

  // ── Start polling loop (after the wake request) ───────────────────────────
  void _startPolling() {
    _pollCount = 0;
    _restartTimer(const Duration(seconds: 5));
  }

  void _applyLambdaBackendUrl(http.Response response) {
    if (AppConstants.isLocal) return;
    if (response.body.trim().isEmpty) return;

    try {
      final body = json.decode(response.body);
      if (body is! Map<String, dynamic>) return;

      final apiUrl = body['apiUrl'] ?? body['baseUrl'] ?? body['backendUrl'];
      if (apiUrl is String && apiUrl.trim().isNotEmpty) {
        unawaited(ServerHealth.remember(apiUrl));
      }
    } catch (_) {
      // Older Lambda versions may return plain text. Startup polling still works.
    }
  }

  // ── Call Lambda to start EC2 ──────────────────────────────────────────────
  Future<void> _startServer() async {
    if (_navigating) return;

    setState(() {
      _state = _ServerState.starting;
      _statusMessage = 'সার্ভার চালু করার অনুরোধ পাঠানো হচ্ছে...';
      _pollCount = 0;
    });

    // The server may have been started outside the app. In that case there is
    // no reason to invoke Lambda or wait for the first polling interval.
    if (await _isServerOnline(attempts: 2)) {
      await _continueWhenOnline();
      return;
    }

    try {
      // Local-dev builds never wake (or otherwise contact) production.
      if (!AppConstants.isLocal) {
        final response = await http
            .get(Uri.parse(AppConstants.lambdaStartUrl))
            .timeout(const Duration(seconds: 35));
        _applyLambdaBackendUrl(response);
      }
    } catch (_) {
      // Ignore — Lambda may time out before EC2 finishes starting
    }

    setState(() {
      _statusMessage = 'সার্ভার চালু হচ্ছে...\nঅনুগ্রহ করে অপেক্ষা করুন';
    });

    _startPolling();
  }

  // ── After server is online, route based on auth ───────────────────────────
  Future<void> _navigateNext() async {
    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.initialize();
    var openHome = authProvider.isAuthenticated && !authProvider.isLocked;
    if (openHome && await authProvider.refreshSession() == 'expired') {
      await authProvider.logout();
      openHome = false;
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => openHome ? const MainNavigationScreen() : const LoginScreen(),
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ── Background decorations (matching splash screen) ──
          Positioned(
            right: -100,
            top: -100,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _primary.withOpacity(0.10),
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
                color: const Color(0xFF667EEA).withOpacity(0.08),
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
                color: const Color(0xFFFF6B9D).withOpacity(0.08),
              ),
            ),
          ),

          // ── Main content ──
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Logo
                FractionallySizedBox(
                  widthFactor: 0.6,
                  child: Image.asset(
                    'assets/images/lgp_logo_red.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.diamond,
                      color: _primary,
                      size: 90,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Status card ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 24),
                        decoration: BoxDecoration(
                          color: _bgLight.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _stateColor().withOpacity(0.3),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Status icon / spinner
                            _buildStatusIcon(),
                            const SizedBox(height: 16),

                            // Bengali status text
                            Text(
                              _statusMessage,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                                height: 1.5,
                              ),
                            ),

                            // Hint when idle
                            if (_state == _ServerState.idle) ...[
                              const SizedBox(height: 8),
                              Text(
                                'চালু হতে ১-২ মিনিট সময় লাগবে',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Action button ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: _buildActionButton(),
                ),

                const Spacer(flex: 3),

                // Footer
                Text(
                  '© Laltu Guinea Palace',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
                if (_appVersionText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _appVersionText,
                    style: TextStyle(fontSize: 11, color: Colors.grey[300]),
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _stateColor() {
    switch (_state) {
      case _ServerState.idle:
        return _primary;
      case _ServerState.starting:
        return const Color(0xFFFF9800); // orange — in progress
      case _ServerState.online:
        return const Color(0xFF4CAF50); // green — success
      case _ServerState.error:
        return const Color(0xFFF44336); // red — error
    }
  }

  Widget _buildStatusIcon() {
    switch (_state) {
      case _ServerState.idle:
        return ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _primary.withOpacity(0.12),
            ),
            child:
                const Icon(Icons.cloud_off_rounded, color: _primary, size: 32),
          ),
        );

      case _ServerState.starting:
        return SizedBox(
          width: 64,
          height: 64,
          child: CircularProgressIndicator(
            strokeWidth: 4,
            valueColor: AlwaysStoppedAnimation<Color>(_stateColor()),
          ),
        );

      case _ServerState.online:
        return Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF4CAF50).withOpacity(0.12),
          ),
          child: const Icon(Icons.check_circle_rounded,
              color: Color(0xFF4CAF50), size: 38),
        );

      case _ServerState.error:
        return Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFF44336).withOpacity(0.12),
          ),
          child: const Icon(Icons.error_rounded,
              color: Color(0xFFF44336), size: 38),
        );
    }
  }

  Widget _buildActionButton() {
    switch (_state) {
      case _ServerState.idle:
        return SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _startServer,
            icon: const Icon(Icons.power_settings_new_rounded),
            label: const Text(
              'Start',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 3,
            ),
          ),
        );

      case _ServerState.starting:
        return SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: null, // disabled while starting
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[300],
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(
              'চালু হচ্ছে...',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600]),
            ),
          ),
        );

      case _ServerState.online:
        return SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text(
              'সংযুক্ত হচ্ছে...',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
            ),
          ),
        );

      case _ServerState.error:
        return SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _startServer,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(
              'পুনরায় চেষ্টা করুন',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF44336),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        );
    }
  }
}
