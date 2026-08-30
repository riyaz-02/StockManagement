import 'dart:async';
import 'package:flutter/material.dart';

/// Global navigator key so toasts can be shown from a stable [Overlay],
/// independent of any individual screen's [BuildContext] (and safely
/// usable even right after an `await`, where the calling widget's own
/// context might no longer be mounted).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

OverlayEntry? _currentToastEntry;

/// Drop-in replacement for `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))`.
///
/// Renders the same [SnackBar] (content, backgroundColor, duration, action,
/// shape) but pinned near the top of the screen instead of the bottom, so it
/// never covers bottom-anchored buttons (e.g. Save/Delete bars).
///
/// [context] is accepted for call-site compatibility but not required to be
/// mounted — the toast is inserted into a global overlay via [appNavigatorKey].
void showAppSnackBar(BuildContext context, SnackBar snackBar) {
  final overlay = appNavigatorKey.currentState?.overlay;
  if (overlay == null) return;

  // Only one toast on screen at a time — replace instead of stacking.
  _currentToastEntry?.remove();
  _currentToastEntry = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _TopToast(
      snackBar: snackBar,
      onRemove: () {
        if (entry.mounted) entry.remove();
        if (identical(_currentToastEntry, entry)) _currentToastEntry = null;
      },
    ),
  );

  _currentToastEntry = entry;
  overlay.insert(entry);
}

class _TopToast extends StatefulWidget {
  final SnackBar snackBar;
  final VoidCallback onRemove;

  const _TopToast({required this.snackBar, required this.onRemove});

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  Timer? _timer;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();

    _timer = Timer(widget.snackBar.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    _timer?.cancel();
    await _controller.reverse();
    widget.onRemove();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snackBar = widget.snackBar;
    final theme = Theme.of(context);
    final backgroundColor = snackBar.backgroundColor ??
        theme.snackBarTheme.backgroundColor ??
        const Color(0xFF323232);

    BorderRadius? borderRadius;
    final shape = snackBar.shape;
    if (shape is RoundedRectangleBorder && shape.borderRadius is BorderRadius) {
      borderRadius = shape.borderRadius as BorderRadius;
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: _dismiss,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 46),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: borderRadius ?? BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: DefaultTextStyle(
                            style: (theme.snackBarTheme.contentTextStyle ??
                                    const TextStyle(fontSize: 14))
                                .copyWith(color: Colors.white),
                            child: snackBar.content,
                          ),
                        ),
                        if (snackBar.action != null) ...[
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: () {
                              widget.snackBar.action!.onPressed();
                              _dismiss();
                            },
                            style: TextButton.styleFrom(
                              foregroundColor:
                                  snackBar.action!.textColor ?? Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: const Size(0, 0),
                            ),
                            child: Text(snackBar.action!.label),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
