import 'package:flutter/material.dart';

/// A page route that fades in quickly (and slides up a little): used between the sign-in, passcode and Home screens so the
/// change reads as one flow, not a jump. 180 ms.
Route<T> fastRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(opacity: c, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.025), end: Offset.zero).animate(c), child: child));
      },
    );
