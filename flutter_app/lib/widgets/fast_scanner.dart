import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// The one camera scanner every scan screen uses (Scan Stock, Tally, assigning a tag).
///
/// Why it is fast:
///  * the camera runs at 1080p (the plugin's default is 480x640, too blurry for a small jewellery tag);
///  * only the barcode types the shop uses are searched for;
///  * the whole frame is searched (no tiny cut-out the code has to sit inside);
///  * a new code is reported at once; only the SAME code is held back for [sameCodeCooldown].
/// It also zooms (pinch the preview, double-tap, or the slider) and has a torch.
class FastScanner extends StatefulWidget {
  const FastScanner({
    super.key,
    required this.onCode,
    this.paused = false,
    this.success = false,
    this.sameCodeCooldown = const Duration(milliseconds: 2500),
    this.guideCenterY = 0.42,
    this.torchTop = 16,
    this.torchRight = 16,
  });

  /// Called for every accepted code (already trimmed, never empty).
  final void Function(String code) onCode;

  /// While true, detections are ignored (a dialog is open, a result is being shown).
  final bool paused;

  /// Paints the frame green (something was just captured).
  final bool success;

  /// The same code is not reported again within this time; a different code is reported immediately.
  final Duration sameCodeCooldown;

  /// Where the torch icon sits (from the top safe area / the right edge).
  final double torchTop;
  final double torchRight;

  /// Vertical position of the frame, as a fraction of the height.
  final double guideCenterY;

  @override
  State<FastScanner> createState() => FastScannerState();
}

class FastScannerState extends State<FastScanner> {
  late final MobileScannerController _ctl = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 120,
    cameraResolution: const Size(1080, 1920),
    formats: const [
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.codabar,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.itf,
      BarcodeFormat.qrCode,
      BarcodeFormat.dataMatrix,
    ],
  );

  double _zoom = 0; // 0 = no zoom, 1 = the camera's maximum
  double _zoomAtStart = 0;
  bool _torch = false;
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> start() async {
    try {
      await _ctl.start();
      if (_zoom > 0) await _ctl.setZoomScale(_zoom);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _ctl.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (widget.paused) return;
    for (final b in capture.barcodes) {
      final v = (b.rawValue ?? '').trim();
      if (v.isEmpty) continue;
      final now = DateTime.now();
      if (v == _lastCode && now.difference(_lastAt) < widget.sameCodeCooldown) continue;
      _lastCode = v;
      _lastAt = now;
      widget.onCode(v);
      break;
    }
  }

  void _setZoom(double z) {
    final v = z.clamp(0.0, 1.0);
    if ((v - _zoom).abs() < 0.004) return;
    setState(() => _zoom = v);
    _ctl.setZoomScale(v).catchError((_) {});
  }

  Future<void> _toggleTorch() async {
    try {
      await _ctl.toggleTorch();
      setState(() => _torch = !_torch);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final gw = (w - 40).clamp(200.0, 380.0);
      final gh = (h * 0.26).clamp(150.0, 230.0);
      final guide = Rect.fromCenter(center: Offset(w / 2, h * widget.guideCenterY), width: gw, height: gh);
      return Stack(children: [
        // pinch to zoom, double-tap to jump between 1x and a closer view
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (_) => _zoomAtStart = _zoom,
          onScaleUpdate: (d) {
            if (d.pointerCount >= 2) _setZoom(_zoomAtStart + (d.scale - 1) * 0.6);
          },
          onDoubleTap: () => _setZoom(_zoom < 0.25 ? 0.5 : 0),
          child: MobileScanner(controller: _ctl, onDetect: _onDetect),
        ),
        IgnorePointer(child: CustomPaint(size: Size.infinite, painter: _GuidePainter(guide, widget.success))),
        // just the torch, top right, where it always was (pinch or double-tap still zooms)
        Positioned(
          top: MediaQuery.of(context).padding.top + widget.torchTop,
          right: widget.torchRight,
          child: IconButton(
            tooltip: 'Torch',
            icon: Icon(_torch ? Icons.flash_on : Icons.flash_off, color: _torch ? Colors.yellow : Colors.white),
            onPressed: _toggleTorch,
          ),
        ),
      ]);
    });
  }
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(this.guide, this.success);
  final Rect guide;
  final bool success;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(guide, const Radius.circular(18));
    // soft dim outside the frame (the whole picture is still being read)
    canvas.drawPath(
      Path()
        ..addRect(Offset.zero & size)
        ..addRRect(rr)
        ..fillType = PathFillType.evenOdd,
      Paint()..color = const Color(0x66000000),
    );
    final col = success ? const Color(0xFF4CAF50) : Colors.white;
    if (success) canvas.drawRRect(rr, Paint()..color = const Color(0x334CAF50));
    final p = Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    const arm = 30.0, r = 18.0;
    final l = guide.left, t = guide.top, ri = guide.right, b = guide.bottom;
    // four corner brackets
    canvas.drawPath(Path()..moveTo(l, t + arm)..lineTo(l, t + r)..arcToPoint(Offset(l + r, t), radius: const Radius.circular(r))..lineTo(l + arm, t), p);
    canvas.drawPath(Path()..moveTo(ri - arm, t)..lineTo(ri - r, t)..arcToPoint(Offset(ri, t + r), radius: const Radius.circular(r))..lineTo(ri, t + arm), p);
    canvas.drawPath(Path()..moveTo(l, b - arm)..lineTo(l, b - r)..arcToPoint(Offset(l + r, b), radius: const Radius.circular(r), clockwise: false)..lineTo(l + arm, b), p);
    canvas.drawPath(Path()..moveTo(ri - arm, b)..lineTo(ri - r, b)..arcToPoint(Offset(ri, b - r), radius: const Radius.circular(r), clockwise: false)..lineTo(ri, b - arm), p);
  }

  @override
  bool shouldRepaint(_GuidePainter o) => o.guide != guide || o.success != success;
}
