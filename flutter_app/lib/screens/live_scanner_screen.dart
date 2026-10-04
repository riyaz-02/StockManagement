import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import '../providers/tally_provider.dart';
import '../models/item_model.dart';
import '../utils/app_colors.dart';
import '../utils/app_toast.dart';
import '../widgets/app_dialog.dart';
import '../widgets/fast_scanner.dart';
import '../widgets/weight_verification_dialog.dart';
import 'quick_add_item_screen.dart';

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
  final GlobalKey<FastScannerState> _scanner = GlobalKey<FastScannerState>();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();

  // Scans go into a queue and are worked through one by one, so the camera never waits for the server:
  // the next barcode can be scanned while the previous one is still being saved.
  final List<String> _queue = [];
  bool _draining = false;
  bool _modalOpen = false; // a dialog / form is open: the camera ignores codes until it is closed
  bool _completeShown = false;
  Timer? _refreshTimer;
  int _pending = 0;

  int _scannedCount = 0;
  int _totalItems = 0;
  String? _lastScannedBarcode;
  String? _lastResult;
  Color _resultColor = Colors.green;

  @override
  void initState() {
    super.initState();
    _audioPlayer.setPlayerMode(PlayerMode.lowLatency).catchError((_) {});   // the beep follows the scan at once
    _loadTallyInfo();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _audioPlayer.dispose();
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _playSound(String type) async {
    try {
      String soundFile;

      if (type == 'success') {
        soundFile = 'sounds/beep.mp3'; // Use beep for success
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

  /// A dialog / form is about to open: pause the camera until it is closed.
  Future<T> _modal<T>(Future<T> Function() open) async {
    if (mounted) setState(() => _modalOpen = true);
    try {
      return await open();
    } finally {
      if (mounted) setState(() => _modalOpen = false);
    }
  }

  /// One refresh of the tally a moment after the last scan (instead of one per scan).
  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 700), () async {
      if (!mounted) return;
      await _loadTallyInfo();
      if (!mounted) return;
      Provider.of<TallyProvider>(context, listen: false).notifyListeners();
      if (_totalItems > 0 && _scannedCount >= _totalItems && !_completeShown) {
        _completeShown = true;
        _playSound('complete');
        HapticFeedback.heavyImpact();
        _modal(() => _showCompletionDialog());
      }
    });
  }

  /// Every code (camera or typed) comes here: acknowledged at once, saved in the background.
  void _processScan(String barcode) {
    final code = barcode.trim();
    if (code.isEmpty) return;
    if (_queue.contains(code)) return; // the same code is already waiting
    HapticFeedback.selectionClick();
    _queue.add(code);
    if (mounted) setState(() => _pending = _queue.length + (_draining ? 1 : 0));
    _drain();
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    if (mounted) setState(() {});
    while (_queue.isNotEmpty && mounted) {
      final code = _queue.removeAt(0);
      if (mounted) setState(() => _pending = _queue.length + 1);
      try {
        await _processOne(code);
      } catch (e) {
        print('[SCAN] EXCEPTION during scan: $e');
      }
    }
    _draining = false;
    if (mounted) setState(() => _pending = 0);
  }

  Future<void> _processOne(String barcode) async {
    final tallyProvider = Provider.of<TallyProvider>(context, listen: false);
    try {
      final result = await tallyProvider.scanItem(widget.tallyId, barcode, refresh: false);
      if (!mounted) return;

      if (result != null) {
        // weight verification (approx / bulk pieces)
        final requiresWeightVerification = result['requiresWeightVerification'] ?? false;
        if (requiresWeightVerification) {
          final itemData = result['data']?['item'];
          if (itemData != null) {
            await _modal(() => showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => WeightVerificationDialog(
                    itemData: itemData,
                    onVerified: (verifiedWeight) async {
                      try {
                        final tp = Provider.of<TallyProvider>(context, listen: false);
                        await tp.verifyTallyWeight(widget.tallyId, itemData['_id'], verifiedWeight);
                        if (mounted) Navigator.of(context).pop();
                        _playSound('success');
                        HapticFeedback.lightImpact();
                        _scheduleRefresh();
                      } catch (e) {
                        if (mounted) {
                          showAppSnackBar(context, SnackBar(content: Text('Failed to verify weight: $e'), backgroundColor: Colors.red));
                        }
                      }
                    },
                  ),
                ));
          }
          return;
        }

        final isOutOfStock = result['isOutOfStock'] ?? false;
        final scannedItemData = result['data']?['item'];
        final needsDetails = scannedItemData?['status'] == 'action_needed';

        _playSound('success');
        HapticFeedback.lightImpact();
        if (mounted) {
          setState(() {
            _lastScannedBarcode = barcode;
            _scannedCount++; // shown at once; the true count is read back once the queue is quiet
            _lastResult = isOutOfStock ? '⚠️ Out of stock - weight excluded' : '✓ Item scanned';
            _resultColor = isOutOfStock ? Colors.orange : Colors.green;
          });
        }
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _lastScannedBarcode == barcode) {
            setState(() {
              _lastResult = null;
              _lastScannedBarcode = null;
            });
          }
        });
        _scheduleRefresh();

        // a quick-added piece that still needs its details: offer to finish it right here
        if (needsDetails && scannedItemData != null && mounted) {
          await _modal(() => _offerCompleteDetails(scannedItemData));
        }
      } else {
        final err = (tallyProvider.error ?? '').toLowerCase();
        final isNotFound = err.contains('not found');
        final isOutOfStockWarning = err.contains('sold') || err.contains('repair') || err.contains('customer') || err.contains('out of stock') || err.contains('deleted');

        _playSound('error');
        if (isNotFound || isOutOfStockWarning) {
          HapticFeedback.mediumImpact();
        } else {
          HapticFeedback.vibrate();
        }

        if (mounted) {
          setState(() {
            _lastScannedBarcode = barcode;
            _lastResult = tallyProvider.error ?? '✗ Scan failed - please try again';
            _resultColor = (isOutOfStockWarning || isNotFound) ? Colors.orange : Colors.red;
          });
        }
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && _lastScannedBarcode == barcode) {
            setState(() {
              _lastResult = null;
              _lastScannedBarcode = null;
            });
          }
        });

        if (isNotFound && mounted) {
          // Barcode isn't registered at all: offer to add it on the spot
          await _modal(() => _offerAddMissingItem(barcode));
        }
      }
    } catch (e) {
      print('[SCAN] EXCEPTION during scan: $e');
      _playSound('error');
      HapticFeedback.vibrate();
      if (mounted) {
        setState(() {
          _lastScannedBarcode = barcode;
          _lastResult = '✗ Error: ${e.toString().replaceFirst('Exception: ', '')}';
          _resultColor = Colors.red;
        });
      }
    }
  }

  // ── Barcode not found — offer to add it as a new item ─────────────────────
  Future<void> _offerAddMissingItem(String barcode) async {
    final bn = Provider.of<LanguageProvider>(context, listen: false).currentLanguage == 'bn';
    final shouldAdd = await confirmModern(
      context,
      icon: Icons.search_off_rounded,
      accent: const Color(0xFFF59E0B),
      title: bn ? 'বারকোড পাওয়া যায়নি' : 'Barcode not found',
      message: bn ? '$barcode স্টকে নেই। এখনই যোগ করবেন?' : '$barcode is not in stock. Add it now?',
      confirmLabel: bn ? 'যোগ করুন' : 'Add item',
      cancelLabel: bn ? 'বাদ দিন' : 'Skip',
    );

    if (shouldAdd != true || !mounted) return;

    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (context) => QuickAddItemScreen(barcode: barcode)),
    );

    if (created != true || !mounted) return;

    final tallyProvider = Provider.of<TallyProvider>(context, listen: false);
    final success = await tallyProvider.addItemToTally(widget.tallyId, barcode);

    if (!mounted) return;

    if (success) {
      _playSound('success');
      HapticFeedback.lightImpact();
      setState(() {
        _scannedCount++;
        _lastScannedBarcode = barcode;
        _lastResult = '✓ Item added and counted';
        _resultColor = Colors.green;
      });
      await _loadTallyInfo();
      tallyProvider.notifyListeners();
    } else {
      showAppSnackBar(
        context,
        SnackBar(
          content: Text(tallyProvider.error ??
              'Item created, but failed to add to tally'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ── Scanned item still has pending "action needed" details ────────────────
  Future<void> _offerCompleteDetails(Map<String, dynamic> itemData) async {
    final bn = Provider.of<LanguageProvider>(context, listen: false).currentLanguage == 'bn';
    final shouldEdit = await confirmModern(
      context,
      icon: Icons.edit_note_rounded,
      accent: const Color(0xFF2F6BFF),
      title: bn ? 'বিবরণ বাকি' : 'Details pending',
      message: bn ? '${itemData['barcode'] ?? 'এই আইটেম'}-এর বিবরণ এখন লিখবেন?' : 'Fill in the details of ${itemData['barcode'] ?? 'this item'} now?',
      confirmLabel: bn ? 'এখনই লিখুন' : 'Edit now',
      cancelLabel: bn ? 'পরে' : 'Later',
    );

    if (shouldEdit != true || !mounted) return;

    try {
      final item = Item.fromJson(itemData);
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => QuickAddItemScreen(item: item)),
      );
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          SnackBar(
              content: Text('Could not open item: $e'),
              backgroundColor: Colors.red),
        );
      }
      return;
    }

    if (mounted) await _loadTallyInfo();
  }

  Future<void> _showCompletionDialog() {
    final bn = Provider.of<LanguageProvider>(context, listen: false).currentLanguage == 'bn';
    return showModernDialog<void>(
      context,
      child: Builder(
        builder: (ctx) => ModernDialogCard(
          icon: Icons.verified_rounded,
          accent: const Color(0xFF16A34A),
          title: bn ? 'সব আইটেম স্ক্যান হয়েছে' : 'All items scanned',
          primary: ModernDialogButton.primary(bn ? 'শেষ' : 'Done', color: const Color(0xFF16A34A), onPressed: () {
            Navigator.of(ctx).pop();
            Navigator.of(context).pop(); // close the scanner
          }),
          secondary: ModernDialogButton.text(bn ? 'স্ক্যান চালান' : 'Keep scanning', onPressed: () => Navigator.of(ctx).pop()),
        ),
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
          // Camera: high resolution, whole-frame detection, zoom + torch (see widgets/fast_scanner.dart)
          Positioned.fill(
            child: FastScanner(
              key: _scanner,
              onCode: _processScan,
              paused: _modalOpen,
              success: _lastResult != null && _resultColor == Colors.green,
              sameCodeCooldown: const Duration(milliseconds: 3000),
              guideCenterY: 0.5,
            ),
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
                          icon: Icon(Icons.search,
                              color: Colors.white.withOpacity(0.8)),
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
                        const SizedBox(width: 48),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
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

          // saving in the background: small, never blocks the camera
          if (_pending > 0)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(16)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  const SizedBox(width: 8),
                  Text('Saving $_pending', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
