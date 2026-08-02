import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class AppConstants {
  // ── Environment Switch ──────────────────────────────────────────────────
  // Set to true for local development, false for production.
  static const bool _useLocalBackend = true;

  // ── Production URL ──────────────────────────────────────────────────────
  // Production API domain. Point api.laltuguineapalace.com to the EC2 public IP
  // from the wake Lambda instead of keeping a paid Elastic IP allocated.
  static const String _productionUrl = 'https://api.laltuguineapalace.com/api';
  static String? _runtimeProductionUrl;

  // Lambda Function URL to wake the EC2 instance when sleeping
  static const String lambdaStartUrl =
      'https://45skg376c6xml6yifrzyct75rm0isktv.lambda-url.ap-south-1.on.aws/';

  // ── Local Development URL ───────────────────────────────────────────────
  // Android physical device: use your PC's LAN IP (run `ipconfig` → Wi-Fi IPv4)
  // Android emulator       : 10.0.2.2 maps to the host machine's localhost
  // iOS simulator / macOS  : localhost works directly
  static String get _localUrl {
    if (kIsWeb) return 'http://localhost:5000/api';
    if (Platform.isAndroid) {
      // Physical device — Wi-Fi IPv4 (run `ipconfig` to refresh if it changes)
      return 'http://192.168.0.114:5000/api';
      // Emulator fallback (uncomment if using Android emulator instead):
      // return 'http://10.0.2.2:5000/api';
    }
    return 'http://localhost:5000/api';
  }

  // ── Active baseUrl ──────────────────────────────────────────────────────
  static String get baseUrl =>
      _useLocalBackend ? _localUrl : (_runtimeProductionUrl ?? _productionUrl);

  static void setRuntimeProductionUrl(String url) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) return;

    _runtimeProductionUrl = trimmedUrl.endsWith('/api')
        ? trimmedUrl
        : '${trimmedUrl.replaceAll(RegExp(r'/+$'), '')}/api';
  }

  // Health-check — same host as baseUrl
  static String get healthCheckUrl => '${baseUrl.replaceAll('/api', '')}/api/auth/me';
  
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
