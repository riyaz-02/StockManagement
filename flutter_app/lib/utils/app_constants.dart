import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class AppConstants {
  // API Configuration - Auto-detects platform
  static String get baseUrl {
    if (kIsWeb) {
      // For Web: Use localhost
      return 'http://localhost:5000/api';
    } else if (Platform.isAndroid) {
      // For Android PHYSICAL DEVICE over Wi-Fi
      const String physicalDeviceIP = '192.168.0.116';
      return 'http://$physicalDeviceIP:5000/api';
      
      // For Android with USB debugging (ADB reverse):
      // Run: adb reverse tcp:5000 tcp:5000
      // return 'http://localhost:5000/api';
      
      // For Android EMULATOR:
      // return 'http://10.0.2.2:5000/api';
    } else if (Platform.isIOS) {
      // For iOS: Use localhost (works on simulator)
      return 'http://localhost:5000/api';
    } else {
      // For Desktop (Windows/Mac/Linux): Use localhost
      return 'http://localhost:5000/api';
    }
  }
  
  static const int connectionTimeout = 30000; // 30 seconds
  static const int receiveTimeout = 30000;
  
  // Storage Keys
  static const String keyToken = 'auth_token';
  static const String keyUser = 'user_data';
  static const String keyLanguage = 'app_language';
  
  // Item Types
  static const List<String> itemTypes = [
    'ring',
    'necklace',
    'earring',
    'bracelet',
    'pendant',
    'chain',
    'bangle',
  ];
  
  // Metal Types
  static const List<String> metalTypes = [
    'gold',
    'silver',
    'mixed',
    'gold-coated',
    'platinum',
  ];
  
  // Purity Options
  static const List<String> purityOptions = [
    '916',
    '22k',
    '18k',
    '14k',
    'silver925',
    'silver999',
    'platinum950',
  ];
  
  // Item Status
  static const List<String> itemStatuses = [
    'active',
    'booked',
    'in_repair',
    'temporarily_removed',
    'sold',
  ];
  
  // Container Types
  static const List<String> containerTypes = [
    'ring_box',
    'necklace_tray',
    'earring_tray',
    'hand_model',
    'custom',
  ];
  
  // Weight Categories
  static const List<String> weightCategories = [
    'Light',
    'Medium',
    'Heavy',
    'Mixed',
  ];
  
  // Layout Types
  static const List<String> layoutTypes = [
    'grid',
    'linear',
    'hand_model',
  ];
  
  // Pagination
  static const int itemsPerPage = 20;
  
  // Image
  static const int maxImageSize = 5 * 1024 * 1024; // 5MB
  static const List<String> allowedImageFormats = ['jpg', 'jpeg', 'png'];
}
