import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class AppConstants {
  // Production API URL - AWS EC2 Mumbai (Elastic IP - permanent, never changes)
  static const String baseUrl = 'http://13.235.125.127/api';

  // Lambda Function URL to start the EC2 instance (from AWS Lambda → StartShopEC2 → Configuration → Function URL)
  static const String lambdaStartUrl = 'https://45skg376c6xml6yifrzyct75rm0isktv.lambda-url.ap-south-1.on.aws/';

  // Server connectivity check — any 200/401 response means server is up
  static const String healthCheckUrl = 'http://13.235.125.127/api/auth/me';
  
  // Development URL - localhost (uncomment below for local development)
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
    'other',
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
    'no_sell',
    'action_needed',
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
