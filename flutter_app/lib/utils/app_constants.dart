import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class AppConstants {
  // Production API URL
  static const String baseUrl = 'https://stockmanagement-production-0bff.up.railway.app/api';
  
  // Development URLs (uncomment for local development)
  // static String get baseUrl {
  //   if (kIsWeb) {
  //     return 'http://localhost:5000/api';
  //   } else if (Platform.isAndroid) {
  //     const String physicalDeviceIP = '192.168.0.116';
  //     return 'http://$physicalDeviceIP:5000/api';
  //   } else if (Platform.isIOS) {
  //     return 'http://localhost:5000/api';
  //   } else {
  //     return 'http://localhost:5000/api';
  //   }
  // }
  
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
