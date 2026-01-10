import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import '../providers/tally_provider.dart';
import '../models/tally_model.dart';
import 'dart:async';

class TallyScanningScreen extends StatefulWidget {
  final String tallyId;
  final VoidCallback onScanComplete;

  const TallyScanningScreen({
    super.key,
    required this.tallyId,
    required this.onScanComplete,
  });

  @override
  State<TallyScanningScreen> createState() => _TallyScanningScreenState();
}

class _TallyScanningScreenState extends State<TallyScanningScreen> {
  TallySession? _tally;
  bool _isScanning = false;
  bool _isProcessing = false;
  
  final Set<String> _scannedBarcodes = {};
  final Map<String, DateTime> _barcodeCooldown = {};
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  Timer? _autoResumeTimer;
  String? _feedbackMessage;
  Color _feedbackColor = Colors.green;
  bool _showFeedback = false;

  @override
  void initState() {
    super.initState();
    _loadTally();
    _startContinuousScanning();
  }

  @override
  void dispose() {
    _autoResumeTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadTally() async {
    final tallyProvider = Provider.of<TallyProvider>(context, listen: false);
    final tally = await tallyProvider.fetchTallySession(widget.tallyId);
    if (mounted) {
      setState(() => _tally = tally);
    }
  }

  Future<void> _playSound(String type) async {
    try {
      // Fallback: Use different durations/pitches for different sounds
      // In production, use actual sound files
      print('Playing sound: $type');
    } catch (e) {
      print('Sound error: $e');
    }
  }

  void _startContinuousScanning() {
    setState(() => _isScanning = true);
    _continuousScan();
  }

  Future<void> _continuousScan() async {
    if (!_isScanning || _isProcessing || !mounted) return;

    try {
      String barcode = await FlutterBarcodeScanner.scanBarcode(
        '#ff6666',
        'Exit Scanner',
        false,
        ScanMode.BARCODE,
      );

      if (barcode == '-1') {
        // User pressed exit
        if (mounted) {
          Navigator.pop(context);
        }
        return;
      }

      if (barcode.isNotEmpty) {
        await _processScan(barcode);
      }

      // Auto-resume after feedback
      if (_isScanning && mounted) {
        _autoResumeTimer?.cancel();
        _autoResumeTimer = Timer(const Duration(milliseconds: 1500), () {
          if (_isScanning && !_isProcessing && mounted) {
            _continuousScan();
          }
        });
      }
    } catch (e) {
      print('Scan error: $e');
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _processScan(String barcode) async {
    if (_isProcessing) return;

    // Check cooldown
    final now = DateTime.now();
    if (_barcodeCooldown.containsKey(barcode)) {
      final lastScan = _barcodeCooldown[barcode]!;
      if (now.difference(lastScan).inMilliseconds < 1500) {
        return; // Skip rapid double scan
      }
    }

    setState(() => _isProcessing = true);

    try {
      final tallyProvider = Provider.of<TallyProvider>(context, listen: false);
      final result = await tallyProvider.scanItem(widget.tallyId, barcode);

      if (result != null) {
        final isOutOfStock = result['isOutOfStock'] ?? false;
        
        _scannedBarcodes.add(barcode);
        _barcodeCooldown[barcode] = now;
        
        if (isOutOfStock) {
          await _playSound('warning');
          _showFeedbackNotification('⚠️ Out of stock - weight excluded', Colors.orange);
        } else {
          await _playSound('success');
          _showFeedbackNotification('✓ Item added', Colors.green);
        }
        
        await _loadTally();
      } else {
        final error = tallyProvider.error ?? 'Scan failed';
        
        if (error.contains('already scanned')) {
          await _playSound('duplicate');
          _showFeedbackNotification('Already scanned', Colors.orange);
        } else if (error.contains('not found')) {
          await _playSound('error');
          _showFeedbackNotification('Item not found', Colors.red);
        } else {
          await _playSound('error');
          _showFeedbackNotification(error, Colors.red);
        }
      }
    } catch (e) {
      await _playSound('error');
      _showFeedbackNotification('Error: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showFeedbackNotification(String message, Color color) {
    setState(() {
      _feedbackMessage = message;
      _feedbackColor = color;
      _showFeedback = true;
    });

    // Hide feedback after 1.5 seconds
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _showFeedback = false);
      }
    });
  }

  Future<void> _showManualEntry() async {
    final controller = TextEditingController();
    
    final barcode = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black87,
        title: const Text('Manual Entry', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter barcode',
            hintStyle: TextStyle(color: Colors.white54),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white54),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (barcode != null && barcode.isNotEmpty) {
      await _processScan(barcode);
      
      // Auto-resume scanning
      if (_isScanning && mounted) {
        _autoResumeTimer?.cancel();
        _autoResumeTimer = Timer(const Duration(milliseconds: 1500), () {
          if (_isScanning && !_isProcessing && mounted) {
            _continuousScan();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _tally?.progress ?? 0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera view placeholder (handled by flutter_barcode_scanner)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.qr_code_scanner,
                    size: 100,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _isProcessing ? 'Processing...' : 'Scan barcode',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),

            // SCAN STATUS OVERLAY (TOP)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatColumn(
                      '${_tally?.scannedItemsCount ?? 0}',
                      'Scanned',
                      Colors.green,
                    ),
                    _buildStatColumn(
                      '${_tally?.itemsLeft ?? 0}',
                      'Left',
                      Colors.orange,
                    ),
                    _buildStatColumn(
                      '$progress%',
                      'Progress',
                      Colors.blue,
                    ),
                  ],
                ),
              ),
            ),

            // NOTIFICATION AREA (BOTTOM CENTER)
            if (_showFeedback && _feedbackMessage != null)
              Positioned(
                bottom: 140,
                left: 20,
                right: 20,
                child: AnimatedOpacity(
                  opacity: _showFeedback ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: _feedbackColor,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      _feedbackMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),

            // BOTTOM CONTROLS
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Manual Entry
                  FloatingActionButton(
                    heroTag: 'manual',
                    onPressed: _showManualEntry,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: const Icon(Icons.keyboard, color: Colors.white),
                  ),
                  
                  // Exit Scanner
                  FloatingActionButton.extended(
                    heroTag: 'exit',
                    onPressed: () {
                      widget.onScanComplete();
                      Navigator.pop(context);
                    },
                    backgroundColor: Colors.red,
                    icon: const Icon(Icons.close),
                    label: const Text('Exit Scanner'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
