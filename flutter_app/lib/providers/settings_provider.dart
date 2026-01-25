import 'package:flutter/material.dart';
import '../services/api_service.dart';

class SettingsProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  // Item settings
  List<String> _itemTypes = [];
  List<String> _metalTypes = [];
  List<String> _purityOptions = [];

  // Container settings
  List<String> _containerTypes = [];
  List<String> _weightCategories = [];
  List<String> _layoutTypes = [];

  bool _isLoading = false;
  String? _error;

  // Getters
  List<String> get itemTypes => _itemTypes;
  List<String> get metalTypes => _metalTypes;
  List<String> get purityOptions => _purityOptions;
  List<String> get containerTypes => _containerTypes;
  List<String> get weightCategories => _weightCategories;
  List<String> get layoutTypes => _layoutTypes;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Fetch all item settings
  Future<void> fetchItemSettings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getSettings('item');
      if (response['success'] == true) {
        final data = response['data'];
        _itemTypes = List<String>.from(data['itemTypes'] ?? []);
        _metalTypes = List<String>.from(data['metalTypes'] ?? []);
        _purityOptions = List<String>.from(data['purityOptions'] ?? []);
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      print('Item settings fetch error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // Fetch all container settings
  Future<void> fetchContainerSettings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getSettings('container');
      if (response['success'] == true) {
        final data = response['data'];
        _containerTypes = List<String>.from(data['containerTypes'] ?? []);
        _weightCategories = List<String>.from(data['weightCategories'] ?? []);
        _layoutTypes = List<String>.from(data['layoutTypes'] ?? []);
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      print('Container settings fetch error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // Fetch all settings
  Future<void> fetchAllSettings() async {
    await Future.wait([
      fetchItemSettings(),
      fetchContainerSettings(),
    ]);
  }

  // Add value to setting
  Future<bool> addValue(String category, String type, String value) async {
    try {
      final response = await _apiService.addSettingValue(category, type, value);
      if (response['success'] == true) {
        // Refresh settings
        if (category == 'item') {
          await fetchItemSettings();
        } else {
          await fetchContainerSettings();
        }
        return true;
      }
      return false;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  // Update setting values
  Future<bool> updateSetting(String category, String type, List<String> values) async {
    try {
      final response = await _apiService.updateSetting(category, type, values);
      if (response['success'] == true) {
        // Refresh settings
        if (category == 'item') {
          await fetchItemSettings();
        } else {
          await fetchContainerSettings();
        }
        return true;
      }
      return false;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  // Delete value from setting
  Future<bool> deleteValue(String category, String type, String value) async {
    try {
      final response = await _apiService.deleteSettingValue(category, type, value);
      if (response['success'] == true) {
        // Refresh settings
        if (category == 'item') {
          await fetchItemSettings();
        } else {
          await fetchContainerSettings();
        }
        return true;
      }
      return false;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  // Initialize settings (admin only)
  Future<bool> initializeSettings() async {
    try {
      final response = await _apiService.initializeSettings();
      if (response['success'] == true) {
        await fetchAllSettings();
        return true;
      }
      return false;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  // Tag Settings
  Future<Map<String, dynamic>?> getTagSettings() async {
    try {
      final response = await _apiService.getTagSettings();
      return response;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateTagSettings({
    required double tagWidth,
    required double tagHeight,
    required List<Map<String, String>> purityColors,
  }) async {
    try {
      final response = await _apiService.updateTagSettings({
        'tagWidth': tagWidth,
        'tagHeight': tagHeight,
        'purityColors': purityColors,
      });
      return response['message'] != null;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
