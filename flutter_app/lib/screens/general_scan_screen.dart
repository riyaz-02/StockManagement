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

class GeneralScanScreen extends StatefulWidget {
  const GeneralScanScreen({super.key});

  @override
  State<GeneralScanScreen> createState() => _GeneralScanScreenState();
}

class _GeneralScanScreenState extends State<GeneralScanScreen> {
  final MobileScannerController cameraController = MobileScannerController();
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  final ApiService _apiService = ApiService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  DateTime? _lastScanTime;
  String? _lastScannedBarcode;
  String? _feedbackMessage;
  Color _feedbackColor = Colors.green;
  bool _isProcessing = false;

  final Duration _cooldownDuration = const Duration(seconds: 2);

  @override
  void dispose() {
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
        await _audioPlayer.play(AssetSource('sounds/success.mp3'));
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
          _feedbackMessage = type == 'item' ? '✓ Item found' : '✓ Container found';
          _feedbackColor = Colors.green;
        });

        // Navigate to details page
        await Future.delayed(const Duration(milliseconds: 500));

        if (!mounted) return;

        if (type == 'item') {
          // Convert to Item model
          final item = Item.fromJson(data);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ItemDetailsScreen(item: item),
            ),
          );
        } else if (type == 'container') {
          // Convert to Container model
          final container = models.ItemContainer.fromJson(data);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ContainerViewScreen(container: container),
            ),
          );
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

    setState(() {
      _feedbackMessage = message;
      _feedbackColor = Colors.red;
    });

    // Auto-dismiss error after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _feedbackMessage == message) {
        setState(() {
          _feedbackMessage = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(
            controller: cameraController,
            onDetect: _onBarcodeDetected,
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
                          cameraController.torchEnabled ? Icons.flash_on : Icons.flash_off,
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

          // Scanner box overlay
          Center(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _isProcessing ? Colors.green : Colors.white,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(20),
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

          // Feedback overlay
          if (_feedbackMessage != null)
            Positioned(
              bottom: 120,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: _feedbackColor.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _feedbackColor.withOpacity(0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _feedbackColor == Colors.green ? Icons.check_circle : Icons.error,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _feedbackMessage!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
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
