import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';
import '../models/item_model.dart';
import '../models/container_model.dart' as models;
import 'item_details_screen.dart';
import 'container_view_screen.dart';
import 'quick_add_item_screen.dart';
import '../main.dart' show routeObserver;

class GeneralScanScreen extends StatefulWidget {
  const GeneralScanScreen({super.key});

  @override
  State<GeneralScanScreen> createState() => _GeneralScanScreenState();
}

class _GeneralScanScreenState extends State<GeneralScanScreen>
    with WidgetsBindingObserver, RouteAware {
  final MobileScannerController cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
  );
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  final ApiService _apiService = ApiService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  DateTime? _lastScanTime;
  String? _lastScannedBarcode;
  String? _feedbackMessage;
  Color _feedbackColor = Colors.green;
  bool _isProcessing = false;
  String? _unknownBarcode; // Set when a barcode is scanned but not found in DB

  final Duration _cooldownDuration = const Duration(seconds: 2);
  bool _isInitializing = true;
  bool _hasInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Subscribe to route changes so camera stops/starts automatically
      final route = ModalRoute.of(context);
      if (route != null) routeObserver.subscribe(this, route);
      _startCameraWithDelay();
    });
  }

  // Route-aware: this screen is being covered by a new route
  @override
  void didPushNext() {
    _stopCamera();
  }

  // Route-aware: the route on top was popped, we are visible again
  @override
  void didPopNext() {
    _startCamera();
  }

  void _stopCamera() {
    try {
      cameraController.stop();
    } catch (_) {}
  }

  void _startCamera() {
    if (!mounted) return;
    try {
      cameraController.start();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_hasInitialized) {
        _startCameraWithDelay();
      } else {
        _startCamera();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopCamera();
    }
  }

  Future<void> _startCameraWithDelay() async {
    if (_hasInitialized) return;

    setState(() {
      _isInitializing = true;
    });

    // Wait for camera to initialize
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      setState(() {
        _isInitializing = false;
        _hasInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    cameraController.dispose();
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  bool _canScan() {
    if (_lastScanTime == null) return true;
    return DateTime.now().difference(_lastScanTime!) > _cooldownDuration;
  }

  Future<void> _playSound(String type) async {
    try {
      if (type == 'success') {
        await _audioPlayer.play(AssetSource('sounds/beep.mp3'));
      } else {
        await _audioPlayer.play(AssetSource('sounds/error.mp3'));
      }
    } catch (e) {
      print('Error playing sound: $e');
    }
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    _processBarcode(code);
  }

  Future<void> _processBarcode(String barcode) async {
    if (_isProcessing || !_canScan()) {
      print('[SCAN] Cooldown active or already processing');
      return;
    }

    setState(() {
      _isProcessing = true;
      _lastScanTime = DateTime.now();
      _lastScannedBarcode = barcode;
    });

    print('[SCAN] Processing barcode: $barcode');

    try {
      final response = await _apiService.lookupBarcode(barcode);

      if (!mounted) return;

      if (response['success'] == true) {
        final String type = response['type'];
        final Map<String, dynamic> data = response['data'];

        print('[SCAN] ✓ Found $type: ${data['_id']}');

        // Play success sound
        _playSound('success');
        HapticFeedback.lightImpact();

        // Show success feedback
        setState(() {
          _feedbackMessage =
              type == 'item' ? '✓ Item found' : '✓ Container found';
          _feedbackColor = Colors.green;
        });

        // Navigate to details page
        await Future.delayed(const Duration(milliseconds: 500));

        if (!mounted) return;

        if (type == 'item') {
          final item = Item.fromJson(data);
          _stopCamera(); // stop before navigating
          if (!mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ItemDetailsScreen(item: item),
            ),
          );
          // camera restarts via didPopNext
        } else if (type == 'container') {
          final container = models.ItemContainer.fromJson(data);
          _stopCamera(); // stop before navigating
          if (!mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ContainerViewScreen(container: container),
            ),
          );
          // camera restarts via didPopNext
        }
      } else {
        // Not found
        _handleError(response['message'] ?? 'Barcode not found');
      }
    } catch (e) {
      print('[SCAN] ✗ Error: $e');
      _handleError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _handleError(String message) {
    _playSound('error');
    HapticFeedback.vibrate();

    // Detect "not found" responses to offer Add Item
    final isNotFound = message.toLowerCase().contains('not found') ||
        message.toLowerCase().contains('barcode not found');

    setState(() {
      _feedbackMessage =
          isNotFound ? 'No item found for this barcode' : message;
      _feedbackColor = Colors.red;
      _unknownBarcode = isNotFound ? _lastScannedBarcode : null;
    });

    // Auto-dismiss after 8 seconds (longer to give time to tap Add Item)
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && _feedbackMessage != null) {
        setState(() {
          _feedbackMessage = null;
          _unknownBarcode = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Camera preview full-screen
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              const boxSize = 270.0;
              final scanWindow = Rect.fromCenter(
                center: Offset(w / 2, h / 2),
                width: boxSize,
                height: boxSize,
              );
              return Stack(children: [
                MobileScanner(
                  controller: cameraController,
                  scanWindow: scanWindow,
                  onDetect: _onBarcodeDetected,
                ),
                // Dark overlay outside scan box
                _ScanOverlay(
                    scanWindow: scanWindow, isProcessing: _isProcessing),
              ]);
            },
          ),

          // Camera initialization overlay
          if (_isInitializing)
            Container(
              color: Colors.black,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Initializing camera...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),

          // Top bar with gradient
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () {
                          // Navigate to home by triggering back button behavior
                          // which will be caught by WillPopScope in MainNavigationScreen
                          Navigator.of(context).maybePop();
                        },
                      ),
                      const Expanded(
                        child: Text(
                          'Scan Barcode',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          cameraController.torchEnabled
                              ? Icons.flash_on
                              : Icons.flash_off,
                          color: Colors.white,
                        ),
                        onPressed: () => cameraController.toggleTorch(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Manual input at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Redesigned barcode input - pill shape with better styling
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 18),
                              Icon(
                                Icons.qr_code_scanner,
                                color: Colors.white.withOpacity(0.7),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _barcodeController,
                                  focusNode: _barcodeFocusNode,
                                  decoration: InputDecoration(
                                    hintText: 'Enter barcode manually',
                                    hintStyle: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    errorBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                    isDense: true,
                                    filled: false,
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  keyboardType: TextInputType.text,
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (value) {
                                    if (value.isNotEmpty) {
                                      _processBarcode(value);
                                      _barcodeController.clear();
                                    }
                                  },
                                ),
                              ),
                              Container(
                                margin: const EdgeInsets.only(right: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.search,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    if (_barcodeController.text.isNotEmpty) {
                                      _processBarcode(_barcodeController.text);
                                      _barcodeController.clear();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Feedback overlay ─────────────────────────────────────────
          if (_feedbackMessage != null)
            Positioned(
              bottom: 120,
              left: 16,
              right: 16,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: _unknownBarcode != null
                      ? Colors.black.withOpacity(0.88)
                      : _feedbackColor.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: (_unknownBarcode != null
                              ? Colors.black
                              : _feedbackColor)
                          .withOpacity(0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: _unknownBarcode != null
                    // ── Unknown barcode: single Add Item row ──
                    ? InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () async {
                          final barcode = _unknownBarcode!;
                          setState(() {
                            _feedbackMessage = null;
                            _unknownBarcode = null;
                          });
                          // Stop camera to save battery while user fills the form
                          await cameraController.stop();
                          if (!mounted) return;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  QuickAddItemScreen(barcode: barcode),
                            ),
                          );
                          // Restart camera when returning to scanner
                          if (mounted) cameraController.start();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.25),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.search_off_rounded,
                                    color: Colors.redAccent, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'No item exists',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      'Barcode: $_unknownBarcode',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.6),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE94560),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_circle_outline_rounded,
                                        color: Colors.white, size: 16),
                                    SizedBox(width: 6),
                                    Text(
                                      'Add Item',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    // ── Normal success / error chip ──
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _feedbackColor == Colors.green
                                  ? Icons.check_circle
                                  : Icons.error,
                              color: Colors.white,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                _feedbackMessage!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),

          // Processing indicator
          if (_isProcessing)
            const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Scan overlay ──────────────────────────────────────────────────────────────
class _ScanOverlay extends StatelessWidget {
  final Rect scanWindow;
  final bool isProcessing;
  const _ScanOverlay({required this.scanWindow, required this.isProcessing});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _ScanPainter(scanWindow: scanWindow, isProcessing: isProcessing),
    );
  }
}

class _ScanPainter extends CustomPainter {
  final Rect scanWindow;
  final bool isProcessing;
  _ScanPainter({required this.scanWindow, required this.isProcessing});

  @override
  void paint(Canvas canvas, Size size) {
    // Dark mask outside the scan box
    final mask = Paint()..color = const Color(0xBB000000);
    const r = Radius.circular(18);
    final rrect = RRect.fromRectAndRadius(scanWindow, r);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, mask);

    // Corner brackets
    final color = isProcessing ? const Color(0xFF4CAF50) : Colors.white;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    const cl = 26.0; // bracket arm length
    const cr = 16.0; // corner radius
    final l = scanWindow.left;
    final t = scanWindow.top;
    final ri = scanWindow.right;
    final b = scanWindow.bottom;

    // Top-left corner
    canvas.drawLine(Offset(l + cr, t), Offset(l + cr + cl, t), p);
    canvas.drawLine(Offset(l, t + cr), Offset(l, t + cr + cl), p);
    canvas.drawArc(
        Rect.fromLTWH(l, t, cr * 2, cr * 2), 3.14159, 3.14159 / 2, false, p);
    // Top-right corner
    canvas.drawLine(Offset(ri - cr - cl, t), Offset(ri - cr, t), p);
    canvas.drawLine(Offset(ri, t + cr), Offset(ri, t + cr + cl), p);
    canvas.drawArc(Rect.fromLTWH(ri - cr * 2, t, cr * 2, cr * 2), -3.14159 / 2,
        3.14159 / 2, false, p);
    // Bottom-left corner
    canvas.drawLine(Offset(l + cr, b), Offset(l + cr + cl, b), p);
    canvas.drawLine(Offset(l, b - cr - cl), Offset(l, b - cr), p);
    canvas.drawArc(Rect.fromLTWH(l, b - cr * 2, cr * 2, cr * 2), 3.14159 / 2,
        3.14159 / 2, false, p);
    // Bottom-right corner
    canvas.drawLine(Offset(ri - cr - cl, b), Offset(ri - cr, b), p);
    canvas.drawLine(Offset(ri, b - cr - cl), Offset(ri, b - cr), p);
    canvas.drawArc(Rect.fromLTWH(ri - cr * 2, b - cr * 2, cr * 2, cr * 2), 0,
        3.14159 / 2, false, p);
  }

  @override
  bool shouldRepaint(_ScanPainter old) =>
      old.isProcessing != isProcessing || old.scanWindow != scanWindow;
}
