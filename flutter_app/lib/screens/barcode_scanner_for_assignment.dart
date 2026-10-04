import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/fast_scanner.dart';

/// A focused single-scan screen that returns one scanned barcode value to the caller.
/// The caller is responsible for validating the barcode (e.g. duplicate check).
class BarcodeScannerForAssignment extends StatefulWidget {
  const BarcodeScannerForAssignment({super.key});

  @override
  State<BarcodeScannerForAssignment> createState() => _BarcodeScannerForAssignmentState();
}

class _BarcodeScannerForAssignmentState extends State<BarcodeScannerForAssignment> {
  final TextEditingController _manualController = TextEditingController();
  final FocusNode _manualFocusNode = FocusNode();

  bool _scanned = false; // prevent multiple pops

  @override
  void dispose() {
    _manualController.dispose();
    _manualFocusNode.dispose();
    super.dispose();
  }

  void _returnBarcode(String value) {
    if (_scanned) return;
    setState(() => _scanned = true);
    HapticFeedback.mediumImpact();
    // a short beat so the green frame is seen, then back to the caller
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) Navigator.of(context).pop(value.trim());
    });
  }

  void _submitManual() {
    final value = _manualController.text.trim();
    if (value.isEmpty) return;
    _returnBarcode(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: FastScanner(
              onCode: _returnBarcode,
              paused: _scanned,
              success: _scanned,
              torchTop: 4,
              torchRight: 8,
            ),
          ),

          // ── Top bar ─────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.85), Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Cancel',
                    ),
                    const Expanded(
                      child: Text(
                        'Scan Barcode Tag',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom: manual entry ────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.9), Colors.transparent],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Or enter barcode manually', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withOpacity(0.3)),
                            ),
                            child: TextField(
                              controller: _manualController,
                              focusNode: _manualFocusNode,
                              style: const TextStyle(color: Colors.white, fontSize: 15),
                              decoration: const InputDecoration(
                                hintText: 'Enter barcode number',
                                hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                              ),
                              keyboardType: TextInputType.text,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submitManual(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _submitManual,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE94560),
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: const Color(0xFFE94560).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 3))],
                            ),
                            child: const Icon(Icons.check, color: Colors.white, size: 22),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
