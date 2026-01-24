import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';

/// Extension to make translations easier to use in widgets
extension TranslationExtension on BuildContext {
  /// Get translation for a key
  String tr(String key) {
    return Provider.of<LanguageProvider>(this, listen: false).t(key);
  }
  
  /// Get LanguageProvider
  LanguageProvider get lang => Provider.of<LanguageProvider>(this, listen: false);
}
