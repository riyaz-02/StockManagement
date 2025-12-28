import 'package:flutter/material.dart';

class AppColors {
  // Primary Colors
  static const Color primary = Color(0xFF6B4CE6);
  static const Color primaryDark = Color(0xFF5538D9);
  static const Color primaryLight = Color(0xFF8B6FF2);
  
  // Secondary Colors
  static const Color secondary = Color(0xFFFF6B6B);
  static const Color secondaryDark = Color(0xFFE85555);
  static const Color secondaryLight = Color(0xFFFF8787);
  
  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);
  
  // Item Status Colors
  static const Color statusActive = Color(0xFF4CAF50);      // Green
  static const Color statusBooked = Color(0xFFFFC107);      // Yellow
  static const Color statusRepair = Color(0xFF9E9E9E);      // Gray
  static const Color statusRemoved = Color(0xFFF44336);     // Red
  static const Color statusSold = Color(0xFF2196F3);        // Blue
  
  // Container Slot Colors
  static const Color slotEmpty = Color(0xFFE0E0E0);         // Light Gray
  static const Color slotOccupied = Color(0xFF4CAF50);      // Green
  static const Color slotBooked = Color(0xFFFFC107);        // Yellow
  static const Color slotReserved = Color(0xFF9E9E9E);      // Gray
  
  // Neutral Colors
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color divider = Color(0xFFBDBDBD);
  
  // Gradient
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
