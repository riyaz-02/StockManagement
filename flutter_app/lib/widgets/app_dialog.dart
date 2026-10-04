import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_colors.dart';

/// A modern pop-up: soft card, gradient icon badge, clear title, full-width buttons, a gentle spring-in.
/// Use [showModernDialog] with a [ModernDialogCard]; for a plain yes / no see [confirmModern].
Future<T?> showModernDialog<T>(
  BuildContext context, {
  required Widget child,
  bool dismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withOpacity(0.32),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, __) => PopScope(
      canPop: dismissible,
      child: SafeArea(child: Center(child: Material(type: MaterialType.transparency, child: child))),
    ),
    transitionBuilder: (ctx, anim, _, w) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(scale: Tween<double>(begin: 0.9, end: 1).animate(curved), child: w),
      );
    },
  );
}

class ModernDialogCard extends StatelessWidget {
  const ModernDialogCard({
    super.key,
    required this.icon,
    required this.title,
    this.accent = AppColors.primary,
    this.message,
    this.pill,
    this.body,
    this.primary,
    this.secondary,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String? message;

  /// A small label under the title, e.g. "v1.4.0  →  v1.5.0".
  final String? pill;

  /// Extra content between the message and the buttons.
  final Widget? body;
  final Widget? primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    // Frosted glass: the page behind is blurred and tinted, the card is a thin translucent sheet with a light edge.
    return Container(
      width: (w - 64).clamp(250.0, 340.0),
      margin: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 30, offset: const Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withOpacity(0.78), Colors.white.withOpacity(0.58)]),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withOpacity(0.75), width: 1.2),
            ),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [accent, Color.lerp(accent, Colors.black, 0.22)!]),
                      boxShadow: [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A), height: 1.2)),
                      if (pill != null) ...[
                        const SizedBox(height: 3),
                        Text(pill!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent)),
                      ],
                    ]),
                  ),
                ]),
                if (message != null && message!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(message!, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 1.35, color: Colors.grey.shade800)),
                ],
                if (body != null) ...[const SizedBox(height: 10), body!],
                if (primary != null || secondary != null) const SizedBox(height: 14),
                if (primary != null) primary!,
                if (secondary != null) ...[const SizedBox(height: 2), secondary!],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The big rounded button of a modern dialog.
class ModernDialogButton extends StatelessWidget {
  const ModernDialogButton.primary(this.label, {super.key, required this.onPressed, this.icon, this.color = AppColors.primary, this.busy = false}) : filled = true;
  const ModernDialogButton.text(this.label, {super.key, required this.onPressed, this.icon, this.color = AppColors.primary, this.busy = false}) : filled = false;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final bool filled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: filled ? Colors.white : color))
        : Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          ]);
    final action = busy ? null : () {
      HapticFeedback.selectionClick();
      onPressed?.call();
    };
    if (filled) {
      return SizedBox(
        height: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.2)!]),
            boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: ElevatedButton(
            onPressed: action,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: child,
          ),
        ),
      );
    }
    return SizedBox(
      height: 36,
      child: TextButton(
        onPressed: action,
        style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        child: child,
      ),
    );
  }
}

/// A modern yes / no question. Returns true (confirmed), false (declined) or null (dismissed).
Future<bool?> confirmModern(
  BuildContext context, {
  required String title,
  String? message,
  IconData icon = Icons.help_outline_rounded,
  Color accent = AppColors.primary,
  String confirmLabel = 'Yes',
  String cancelLabel = 'Cancel',
  bool danger = false,
}) {
  final color = danger ? const Color(0xFFD32F2F) : accent;
  return showModernDialog<bool>(
    context,
    child: Builder(
      builder: (ctx) => ModernDialogCard(
        icon: icon,
        accent: color,
        title: title,
        message: message,
        primary: ModernDialogButton.primary(confirmLabel, color: color, onPressed: () => Navigator.of(ctx).pop(true)),
        secondary: ModernDialogButton.text(cancelLabel, onPressed: () => Navigator.of(ctx).pop(false)),
      ),
    ),
  );
}
