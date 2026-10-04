import 'dart:async';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/secure_credential_storage.dart';
import '../services/app_lock_service.dart';
import '../services/live_service.dart';
import '../services/presence_service.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final StorageService _storage = StorageService();
  final SecureCredentialStorage _credentialStorage = SecureCredentialStorage();
  final AppLockService _lock = AppLockService.instance;

  User? _user;
  String? _token;
  bool _isLoading = false;
  bool _locked = false;
  String? _error;
  Map<String, bool> _permissions = {};
  StreamSubscription<LiveEvent>? _liveSub;

  /// Keep the live channel in step with the login: open it when signed in, close it on sign-out, and re-read this
  /// person's access when an admin changes it (on the website or another phone).
  void _syncLive() {
    if (_token != null && _user != null) {
      LiveService.instance.start(_token!);
      PresenceService.instance.start();
      _liveSub ??= LiveService.instance.events.listen((e) async {
        if (e.type == 'permissions.changed') {
          await _fetchPermissions();
          notifyListeners();
        }
      });
    } else {
      LiveService.instance.stop();
      PresenceService.instance.stop();
    }
  }

  User? get user => _user;
  String? get token => _token;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null && _token != null;

  /// A person is remembered on this phone (a saved session) but the screen is still guarded by their passcode / fingerprint.
  bool get isLocked => _locked && isAuthenticated;

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
          // Admin/Owner bypass the permission map entirely (see can()), so there is nothing to fetch for them — that
          // saves a network round trip on every app start. Everyone else's fetch runs alongside restoring the branch
          // choice (a local read) instead of after it, since neither depends on the other.
          await Future.wait([
            if (!_user!.hasFullAccess) _fetchPermissions(),
            _restoreBranch(),
          ]);
          _locked = await _lockApplies();
        }
      }
      // an older version kept the password itself for its fingerprint shortcut: it is no longer needed, so it is wiped
      await _credentialStorage.clearCredentials();
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    _syncLive();
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
        _locked = false;
        // a passcode belongs to one person: signing in as somebody else must not keep the previous person's
        if (await _lock.hasPin() && (await _lock.owner()) != _user!.id) await _lock.removePin();

        // Save to storage
        await _storage.saveToken(_token!);
        await _storage.saveUser(response['data']['user']);
        await _fetchPermissions();

        _isLoading = false;
        _syncLive();
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
    _syncLive();
    _locked = false;
    await _storage.clearAll();
    // The passcode and fingerprint belong to the person who signed out: this phone may be shared, so signing out must not
    // leave a shortcut into their account.
    await _lock.clearAll();
    await _credentialStorage.clearCredentials();
    notifyListeners();
  }

  // ── Passcode / fingerprint (the lock of a phone that stays signed in) ─────────────────────────────

  AppLockService get lock => _lock;

  /// Is there a passcode that belongs to the person whose session this is?
  Future<bool> _lockApplies() async {
    if (!await _lock.hasPin()) return false;
    final owner = await _lock.owner();
    if (owner != null && _user != null && owner != _user!.id) {
      await _lock.removePin(); // somebody else's passcode must never guard this session
      return false;
    }
    return true;
  }

  Future<bool> hasLock() => _lock.hasPin();

  /// The screen has been unlocked (right passcode, or a recognised fingerprint).
  void unlock() {
    _locked = false;
    notifyListeners();
  }

  /// Sets or changes the passcode of the signed-in person.
  Future<void> setPasscode(String pin) async {
    if (_user == null) return;
    await _lock.setPin(pin, owner: _user!.id);
    await _lock.clearSetupSkips();
  }

  /// Takes the passcode (and the fingerprint with it) off this phone. The person stays signed in.
  Future<void> removePasscode() => _lock.removePin();

  /// Renews the saved session. 'expired' = the server no longer accepts it (a fresh sign-in is needed); 'offline' keeps the
  /// phone usable as it is (a shop with a weak connection must still be able to open the app).
  Future<String> refreshSession() async {
    if (_token == null) return 'expired';
    final code = await _apiService.refreshToken();
    if (code == 200) {
      _token = await _storage.getToken();
      return 'ok';
    }
    if (code == 401 || code == 403) return 'expired';
    return 'offline';
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
