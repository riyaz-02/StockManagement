import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/storage_service.dart';

class LanguageProvider with ChangeNotifier {
  final StorageService _storage = StorageService();
  
  String _currentLanguage = 'en';
  Map<String, dynamic> _translations = {};

  String get currentLanguage => _currentLanguage;
  Map<String, dynamic> get translations => _translations;

  // Initialize language
  Future<void> initialize() async {
    _currentLanguage = await _storage.getLanguage();
    await _loadTranslations();
    notifyListeners();
  }

  // Load translations from JSON
  Future<void> _loadTranslations() async {
    try {
      final String jsonString = await DefaultAssetBundle.of(
        // This will be set from context
        NavigatorKey.currentContext!,
      ).loadString('lib/l10n/$_currentLanguage.json');
      _translations = json.decode(jsonString);
    } catch (e) {
      print('Error loading translations: $e');
      _translations = {};
    }
  }

  // Change language
  Future<void> changeLanguage(String language) async {
    if (language != _currentLanguage) {
      _currentLanguage = language;
      await _storage.saveLanguage(language);
      await _loadTranslations();
      notifyListeners();
    }
  }

  // Get translated string
  String translate(String key) {
    return _translations[key] ?? key;
  }

  // Shorthand
  String t(String key) => translate(key);
}

// Global navigator key for accessing context
class NavigatorKey {
  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();
  static BuildContext? get currentContext => key.currentContext;
}
