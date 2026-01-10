import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../providers/tally_provider.dart';
import '../utils/app_colors.dart';

class LiveScannerScreen extends StatefulWidget {
  final String tallyId;

  const LiveScannerScreen({
    Key? key,
    required this.tallyId,
  }) : super(key: key);

  @override
  State<LiveScannerScreen> createState() => _LiveScannerScreenState();
}

class _LiveScannerScreenState extends State<LiveScannerScreen> {
  MobileScannerController cameraController = MobileScannerController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  
  bool _isProcessing = false;
  int _scannedCount = 0;
  int _totalItems = 0;
  String? _lastScannedBarcode;
  String? _lastResult;
  Color _resultColor = Colors.green;
  
  // Cooldown mechanism to prevent rapid re-scans
  DateTime? _lastScanTime;
  String? _lastProcessedBarcode;
  static const Duration _scanCooldown = Duration(milliseconds: 5000); // 5 second cooldown

  @override
  void initState() {
    super.initState();
    _loadTallyInfo();
  }

  @override
  void dispose() {
    cameraController.dispose();
    _audioPlayer.dispose();
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _playSound(String type) async {
    try {
      String soundFile;
      
      if (type == 'success') {
        soundFile = 'sounds/beep.mp3';  // Use beep for success
      } else if (type == 'error') {
        soundFile = 'sounds/error.mp3';
      } else if (type == 'complete') {
        soundFile = 'sounds/complete.mp3';
      } else {
        return;
      }
      
      await _audioPlayer.play(AssetSource(soundFile), volume: 1.0);
    } catch (e) {
      print('Audio error: $e');
      // Fallback to system sound if audio file fails
      if (type == 'success') {
        SystemSound.play(SystemSoundType.click);
      } else {
        SystemSound.play(SystemSoundType.alert);
      }
    }
  }

  Future<void> _loadTallyInfo() async {
    final tallyProvider = Provider.of<TallyProvider>(context, listen: false);
    await tallyProvider.fetchTallySession(widget.tallyId);
    if (mounted && tallyProvider.currentTally != null) {
      setState(() {
        _totalItems = tallyProvider.currentTally!.expectedItems;
        _scannedCount = tallyProvider.currentTally!.scannedItemsCount;
      });
    }
  }

  Future<void> _processScan(String barcode) async {
    if (barcode.isEmpty || _isProcessing) return;

    // Cooldown check: prevent scanning same barcode within cooldown period
    final now = DateTime.now();
    if (_lastScanTime != null && _lastProcessedBarcode == barcode) {
      final timeSinceLastScan = now.difference(_lastScanTime!);
      if (timeSinceLastScan < _scanCooldown) {
        // Still in cooldown period for this barcode - ignore
        print('Cooldown active: ${_scanCooldown.inMilliseconds - timeSinceLastScan.inMilliseconds}ms remaining');
        return;
      }
    }

    setState(() {
      _isProcessing = true;
      _lastScanTime = now;
      _lastProcessedBarcode = barcode;
    });

    print('[SCAN] Processing barcode: $barcode');
    print('[SCAN] Current count: $_scannedCount/$_totalItems');

    final tallyProvider = Provider.of<TallyProvider>(context, listen: false);
    
    try {
      final result = await tallyProvider.scanItem(widget.tallyId, barcode);

      if (!mounted) return;

      if (result != null) {
        print('[SCAN] ✓ API returned success for barcode: $barcode');
        final isOutOfStock = result['isOutOfStock'] ?? false;
        
        // Play success sound and vibration
        _playSound('success');
        HapticFeedback.lightImpact();
        
        setState(() {
          _lastScannedBarcode = barcode;
          // CRITICAL: Only increment count if item was actually added to tally
          // Don't increment for items not in expected list
          _scannedCount++;
          _lastResult = isOutOfStock 
              ? '⚠️ Out of stock - weight excluded' 
              : '✓ Item scanned successfully';
          _resultColor = isOutOfStock ? Colors.orange : Colors.green;
        });

        // Auto-dismiss alert after 8 seconds
        Future.delayed(const Duration(seconds: 8), () {
          if (mounted && _lastScannedBarcode == barcode) {
            setState(() {
              _lastResult = null;
              _lastScannedBarcode = null;
            });
          }
        });

        // Reload tally info to get updated weights and counts
        print('Reloading tally info after scan...');
        
        // Add delay to ensure database has updated
        await Future.delayed(const Duration(milliseconds: 800));
        
        await _loadTallyInfo();
        
        // Force provider to notify all listeners (updates parent page immediately)
        tallyProvider.notifyListeners();
        print('Tally reloaded: $_scannedCount / $_totalItems');

        // Check if tally is complete
        if (_scannedCount >= _totalItems) {
          _playSound('complete');
          HapticFeedback.heavyImpact();
          if (mounted) {
            _showCompletionDialog();
          }
        }

        // Resume scanning after brief delay (reduced for faster workflow)
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        // API returned error or null
        print('[SCAN] ✗ API returned error/null for barcode: $barcode');
        print('[SCAN] Provider error: ${tallyProvider.error}');
        
        // Check if it's an out-of-stock item (warning) or other error
        final isOutOfStockWarning = tallyProvider.error?.contains('sold') == true ||
                                     tallyProvider.error?.contains('repair') == true ||
                                     tallyProvider.error?.contains('customer') == true ||
                                     tallyProvider.error?.contains('out of stock') == true ||
                                     tallyProvider.error?.contains('deleted') == true;
        
        // Play appropriate sound
        if (isOutOfStockWarning) {
          _playSound('error'); // Could add a separate warning sound
          HapticFeedback.mediumImpact();
        } else {
          _playSound('error');
          HapticFeedback.vibrate();
        }
        
        setState(() {
          _lastScannedBarcode = barcode;
          _lastResult = tallyProvider.error ?? '✗ Scan failed - please try again';
          _resultColor = isOutOfStockWarning ? Colors.orange : Colors.red;
        });

        // Auto-dismiss error after 10 seconds
        Future.delayed(const Duration(seconds: 10), () {
          if (mounted && _lastScannedBarcode == barcode) {
            setState(() {
              _lastResult = null;
              _lastScannedBarcode = null;
            });
          }
        });

        // Show error snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tallyProvider.error ?? 'Failed to save scan. Please try again.'),
              backgroundColor: isOutOfStockWarning ? Colors.orange : Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }

        await Future.delayed(const Duration(milliseconds: 1500));
      }
    } catch (e) {
      print('[SCAN] ✗ EXCEPTION during scan: $e');
      
      // Play error sound and vibration
      _playSound('error');
      HapticFeedback.vibrate();
      
      setState(() {
        _lastScannedBarcode = barcode;
        _lastResult = '✗ Error: ${e.toString()}';
        _resultColor = Colors.red;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      await Future.delayed(const Duration(milliseconds: 1500));
    }

    setState(() => _isProcessing = false);
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🎉 Tally Complete!'),
        content: const Text('All items have been scanned. Would you like to lock the tally?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Continue Scanning'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Close scanner
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _totalItems > 0 ? _scannedCount / _totalItems : 0.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview with scan window restriction
          MobileScanner(
            controller: cameraController,
            scanWindow: Rect.fromCenter(
              center: MediaQuery.of(context).size.center(Offset.zero),
              width: 300,
              height: 300,
            ),
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null && !_isProcessing) {
                  _processScan(barcode.rawValue!);
                  break;
                }
              }
            },
          ),

          // Top bar with progress
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
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
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.search, color: Colors.white.withOpacity(0.8)),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const Expanded(
                          child: Text(
                            'Camera Scanner',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
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
                    const SizedBox(height: 16),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          progress >= 1.0 ? Colors.green : AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Count
                    Text(
                      '$_scannedCount / $_totalItems items scanned',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
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
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.search,
                                onSubmitted: (value) {
                                  if (value.isNotEmpty) {
                                    _processScan(value);
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
                                    _processScan(_barcodeController.text);
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

          // Scanning frame - this is the active detection area
          Center(
            child: Container(
              width: 300,
            ),
          ),

          // Scanner overlay - fixed centered box that doesn't move with keyboard
          Positioned(
            left: (MediaQuery.of(context).size.width - 280) / 2,
            top: (MediaQuery.of(context).size.height - 280) / 2,
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

          // Enhanced scan result feedback at bottom
          if (_lastResult != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _resultColor.withOpacity(0.0),
                      _resultColor.withOpacity(0.95),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _resultColor.withOpacity(0.5),
                      blurRadius: 20,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _resultColor == Colors.green 
                          ? Icons.check_circle 
                          : _resultColor == Colors.orange
                            ? Icons.warning
                            : Icons.error,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Result text
                    Text(
                      _lastResult!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_lastScannedBarcode != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Barcode: $_lastScannedBarcode',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
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
