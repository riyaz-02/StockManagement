import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/secure_credential_storage.dart';
import '../services/biometric_auth_service.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final StorageService _storage = StorageService();
  final SecureCredentialStorage _credentialStorage = SecureCredentialStorage();

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

  /// May switch between branches (sees the whole firm by default).
  bool get canSwitchBranch => can('branches.viewAll') || can('billing.viewAllBranches');

  String _branchName = '';

  /// Name of the branch switched to, or '' for the whole firm.
  String get activeBranchName => _branchName;

  /// Work as one branch ('' = whole firm). Screens opened afterwards load that branch's stock and invoices; new records
  /// (invoices, items) are filed under it.
  Future<void> setActiveBranch(String id, String name) async {
    ApiService.activeBranch = id;
    _branchName = id.isEmpty ? '' : name;
    await _storage.saveBranch(id, _branchName);
    notifyListeners();
  }

  Future<void> _restoreBranch() async {
    if (!canSwitchBranch) {
      ApiService.activeBranch = '';
      _branchName = '';
      return;
    }
    final (id, name) = await _storage.getBranch();
    ApiService.activeBranch = id;
    _branchName = id.isEmpty ? '' : name;
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
          await _restoreBranch();
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
    ApiService.activeBranch = '';
    ApiService.activeGstin = '';
    _branchName = '';
    await _storage.clearAll();
    // Forget saved fingerprint-login credentials — this device may be
    // shared by other staff, so a logout shouldn't leave a shortcut that
    // logs the next person straight back into this account.
    await _credentialStorage.clearCredentials();
    notifyListeners();
  }

  // ── Biometric login ──────────────────────────────────────────────────
  Future<bool> isBiometricAvailable() => BiometricAuthService().isDeviceSupported();

  Future<bool> hasSavedBiometricCredentials() => _credentialStorage.hasCredentials();

  Future<void> saveBiometricCredentials(String mobile, String password) =>
      _credentialStorage.saveCredentials(mobile, password);

  Future<bool> biometricPromptWasDismissed() => _credentialStorage.wasPromptDismissed();

  Future<void> setBiometricPromptDismissed() =>
      _credentialStorage.setPromptDismissed(true);

  Future<void> forgetBiometricCredentials() => _credentialStorage.clearCredentials();

  /// Prompts the fingerprint/face sensor, then logs in with the stored
  /// credentials. Returns 'success', 'biometric_failed', 'no_credentials',
  /// 'invalid_credentials' (stored password no longer works — cleared), or
  /// 'network_error' (kept, since that's not the stored password's fault).
  Future<String> loginWithBiometrics() async {
    final creds = await _credentialStorage.getCredentials();
    if (creds == null) return 'no_credentials';

    final authenticated = await BiometricAuthService().authenticate();
    if (!authenticated) return 'biometric_failed';

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.login(creds['mobile']!, creds['password']!);

      if (response['success'] == true) {
        _token = response['data']['token'];
        _user = User.fromJson(response['data']['user']);
        await _storage.saveToken(_token!);
        await _storage.saveUser(response['data']['user']);
        await _fetchPermissions();
        _isLoading = false;
        notifyListeners();
        return 'success';
      } else {
        // Server rejected the stored credentials (password changed, account
        // deactivated, etc.) — forget them so we stop offering a fingerprint
        // shortcut that can no longer work.
        await _credentialStorage.clearCredentials();
        _error = response['message'] ?? 'Login failed';
        _isLoading = false;
        notifyListeners();
        return 'invalid_credentials';
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return 'network_error';
    }
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
