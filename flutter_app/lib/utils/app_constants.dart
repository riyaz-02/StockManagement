class AppConstants {
  // API Configuration
  // For Web/Desktop: use localhost
  static const String baseUrl = 'http://localhost:5000/api';
  // For Android emulator: use http://10.0.2.2:5000/api
  // For iOS simulator: use http://localhost:5000/api
  // For real device: use http://YOUR_PC_IP:5000/api
  
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
    'light',
    'medium',
    'heavy',
    'mixed',
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
