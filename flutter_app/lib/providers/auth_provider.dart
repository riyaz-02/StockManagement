import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final StorageService _storage = StorageService();

  User? _user;
  String? _token;
  bool _isLoading = false;
  String? _error;
  Map<String, bool> _permissions = {};

  User? get user => _user;
  String? get token => _token;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null && _token != null;

  // Admin/Owner always pass; everyone else is checked against the fetched
  // effective permission map (role defaults merged with any per-user
  // overrides, computed server-side by GET /api/permissions/me).
  bool can(String key) {
    if (_user?.hasFullAccess == true) return true;
    return _permissions[key] ?? false;
  }

  Future<void> _fetchPermissions() async {
    try {
      final response = await _apiService.getMyPermissions();
      if (response['success'] == true) {
        final data = response['data'];
        if (data['all'] == true) {
          _permissions = {};
        } else {
          final raw = Map<String, dynamic>.from(data['permissions'] ?? {});
          _permissions = raw.map((k, v) => MapEntry(k, v == true));
        }
      }
    } catch (_) {
      // Non-fatal — admin/owner don't need this, and everyone else just
      // falls back to "no extra permissions" until the next successful fetch.
    }
  }

  // Initialize - check if user is already logged in
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      _token = await _storage.getToken();
      if (_token != null) {
        final userData = await _storage.getUser();
        if (userData != null) {
          _user = User.fromJson(userData);
          await _fetchPermissions();
        }
      }
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  // Login
  Future<bool> login(String mobile, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.login(mobile, password);

      if (response['success'] == true) {
        _token = response['data']['token'];
        _user = User.fromJson(response['data']['user']);

        // Save to storage
        await _storage.saveToken(_token!);
        await _storage.saveUser(response['data']['user']);
        await _fetchPermissions();

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = response['message'] ?? 'Login failed';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Logout
  Future<void> logout() async {
    _user = null;
    _token = null;
    _permissions = {};
    await _storage.clearAll();
    notifyListeners();
  }

  // Update language
  Future<bool> updateLanguage(String language) async {
    try {
      await _apiService.updateLanguage(language);
      if (_user != null) {
        _user = User(
          id: _user!.id,
          name: _user!.name,
          role: _user!.role,
          language: language,
          mobile: _user!.mobile,
          profileImage: _user!.profileImage,
          createdAt: _user!.createdAt,
        );
        await _storage.saveUser(_user!.toJson());
        notifyListeners();
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  // Refresh user data from server
  Future<bool> refreshUser() async {
    if (_user == null) return false;

    try {
      final response = await _apiService.getUser(_user!.id);
      if (response['success'] == true) {
        _user = User.fromJson(response['data']['user']);
        await _storage.saveUser(response['data']['user']);
        await _fetchPermissions();
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
