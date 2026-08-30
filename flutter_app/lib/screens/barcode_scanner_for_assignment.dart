import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// A focused single-scan screen that returns one scanned barcode value to the caller.
/// The caller is responsible for validating the barcode (e.g. duplicate check).
class BarcodeScannerForAssignment extends StatefulWidget {
  const BarcodeScannerForAssignment({super.key});

  @override
  State<BarcodeScannerForAssignment> createState() =>
      _BarcodeScannerForAssignmentState();
}

class _BarcodeScannerForAssignmentState
    extends State<BarcodeScannerForAssignment> {
  final MobileScannerController _cameraController = MobileScannerController();
  final TextEditingController _manualController = TextEditingController();
  final FocusNode _manualFocusNode = FocusNode();

  bool _scanned = false; // prevent multiple pops
  bool _torchOn = false;

  @override
  void dispose() {
    _cameraController.dispose();
    _manualController.dispose();
    _manualFocusNode.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        _returnBarcode(value);
        break;
      }
    }
  }

  void _returnBarcode(String value) {
    if (_scanned) return;
    setState(() => _scanned = true);
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(value.trim());
  }

  void _toggleTorch() {
    _cameraController.toggleTorch();
    setState(() => _torchOn = !_torchOn);
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
      body: Stack(
        children: [
          // Camera preview with restricted scan window
          LayoutBuilder(
            builder: (context, constraints) {
              const boxW = 280.0;
              const boxH = 180.0;
              final scanWindow = Rect.fromCenter(
                center:
                    Offset(constraints.maxWidth / 2, constraints.maxHeight / 2),
                width: boxW,
                height: boxH,
              );
              return Stack(children: [
                MobileScanner(
                  controller: _cameraController,
                  scanWindow: scanWindow,
                  onDetect: _onDetect,
                ),
                _AssignScanOverlay(scanWindow: scanWindow, scanned: _scanned),
              ]);
            },
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
                    colors: [
                      Colors.black.withOpacity(0.85),
                      Colors.transparent,
                    ],
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
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // Torch toggle
                    IconButton(
                      icon: Icon(
                        _torchOn ? Icons.flash_on : Icons.flash_off,
                        color: _torchOn ? Colors.yellow : Colors.white,
                      ),
                      onPressed: _toggleTorch,
                      tooltip: 'Toggle torch',
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Hint text below the box
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 200), // push below center
                Text(
                  _scanned ? 'Barcode captured!' : 'Point camera at barcode',
                  style: TextStyle(
                    color: _scanned ? Colors.green : Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom: manual entry ────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.9),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Or enter barcode manually',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                              ),
                            ),
                            child: TextField(
                              controller: _manualController,
                              focusNode: _manualFocusNode,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Enter barcode number',
                                hintStyle: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 14,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
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
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFFE94560).withOpacity(0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 22,
                            ),
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

// ── Scan overlay ──────────────────────────────────────────────────────────────
class _AssignScanOverlay extends StatelessWidget {
  final Rect scanWindow;
  final bool scanned;
  const _AssignScanOverlay({required this.scanWindow, required this.scanned});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.infinite,
        painter: _AssignScanPainter(scanWindow: scanWindow, scanned: scanned),
      );
}

class _AssignScanPainter extends CustomPainter {
  final Rect scanWindow;
  final bool scanned;
  _AssignScanPainter({required this.scanWindow, required this.scanned});

  @override
  void paint(Canvas canvas, Size size) {
    final mask = Paint()..color = const Color(0xBB000000);
    const r = Radius.circular(14);
    final rrect = RRect.fromRectAndRadius(scanWindow, r);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, mask);

    // Show big check inside box when scanned
    if (scanned) {
      final iconPaint = Paint()..color = Colors.green.withValues(alpha: 0.25);
      canvas.drawRRect(rrect, iconPaint);
    }

    final color = scanned ? const Color(0xFF4CAF50) : Colors.white;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    const cl = 24.0;
    const cr = 14.0;
    final l = scanWindow.left;
    final t = scanWindow.top;
    final ri = scanWindow.right;
    final b = scanWindow.bottom;

    canvas.drawLine(Offset(l + cr, t), Offset(l + cr + cl, t), p);
    canvas.drawLine(Offset(l, t + cr), Offset(l, t + cr + cl), p);
    canvas.drawArc(
        Rect.fromLTWH(l, t, cr * 2, cr * 2), 3.14159, 3.14159 / 2, false, p);
    canvas.drawLine(Offset(ri - cr - cl, t), Offset(ri - cr, t), p);
    canvas.drawLine(Offset(ri, t + cr), Offset(ri, t + cr + cl), p);
    canvas.drawArc(Rect.fromLTWH(ri - cr * 2, t, cr * 2, cr * 2), -3.14159 / 2,
        3.14159 / 2, false, p);
    canvas.drawLine(Offset(l + cr, b), Offset(l + cr + cl, b), p);
    canvas.drawLine(Offset(l, b - cr - cl), Offset(l, b - cr), p);
    canvas.drawArc(Rect.fromLTWH(l, b - cr * 2, cr * 2, cr * 2), 3.14159 / 2,
        3.14159 / 2, false, p);
    canvas.drawLine(Offset(ri - cr - cl, b), Offset(ri - cr, b), p);
    canvas.drawLine(Offset(ri, b - cr - cl), Offset(ri, b - cr), p);
    canvas.drawArc(Rect.fromLTWH(ri - cr * 2, b - cr * 2, cr * 2, cr * 2), 0,
        3.14159 / 2, false, p);
  }

  @override
  bool shouldRepaint(_AssignScanPainter old) =>
      old.scanned != scanned || old.scanWindow != scanWindow;
}
