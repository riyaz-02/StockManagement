import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../services/storage_service.dart';

class LanguageProvider with ChangeNotifier {
  final StorageService _storage = StorageService();
  
  String _currentLanguage = 'bn';
  Map<String, dynamic> _translations = {};
  bool _isLoaded = false;

  String get currentLanguage => _currentLanguage;
  Map<String, dynamic> get translations => _translations;
  bool get isLoaded => _isLoaded;

  // Initialize language
  Future<void> initialize() async {
    try {
      print('[LanguageProvider] Initializing...');
      _currentLanguage = await _storage.getLanguage();
      print('[LanguageProvider] Loaded language preference: $_currentLanguage');
      await _loadTranslations();
      _isLoaded = true;
      print('[LanguageProvider] Initialization complete');
      notifyListeners();
    } catch (e) {
      print('[LanguageProvider] Initialization error: $e');
      _isLoaded = true;
      notifyListeners();
    }
  }

  // Load translations from JSON
  Future<void> _loadTranslations() async {
    try {
      print('[LanguageProvider] Loading translations for: $_currentLanguage');
      final String jsonString = await rootBundle.loadString('lib/l10n/$_currentLanguage.json');
      print('[LanguageProvider] JSON loaded, length: ${jsonString.length}');
      _translations = json.decode(jsonString);
      print('[LanguageProvider] Translations loaded: ${_translations.length} keys');
      print('[LanguageProvider] Sample keys: ${_translations.keys.take(5).toList()}');
    } catch (e) {
      print('[LanguageProvider] Error loading translations: $e');
      print('[LanguageProvider] Stack trace: ${StackTrace.current}');
      _translations = {};
    }
  }

  // Change language
  Future<void> changeLanguage(String language) async {
    if (language != _currentLanguage) {
      print('[LanguageProvider] Changing language from $_currentLanguage to $language');
      _currentLanguage = language;
      await _storage.saveLanguage(language);
      await _loadTranslations();
      print('[LanguageProvider] Language changed, notifying listeners');
      notifyListeners();
    }
  }

  // Get translated string
  String translate(String key) {
    final translation = _translations[key];
    if (translation == null) {
      print('[LanguageProvider] Missing translation for key: $key');
      return key;
    }
    return translation;
  }

  // Shorthand
  String t(String key) => translate(key);
}
