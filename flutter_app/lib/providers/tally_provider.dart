import 'package:flutter/material.dart';
import '../services/api_service.dart';

class TallyProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  String? _currentTallySessionId;
  int _scannedCount = 0;
  int _expectedCount = 0;
  double _scannedWeight = 0.0;
  double _expectedWeight = 0.0;
  List<String> _scannedItemIds = [];
  bool _isLoading = false;
  String? _error;

  String? get currentTallySessionId => _currentTallySessionId;
  int get scannedCount => _scannedCount;
  int get expectedCount => _expectedCount;
  double get scannedWeight => _scannedWeight;
  double get expectedWeight => _expectedWeight;
  List<String> get scannedItemIds => _scannedItemIds;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isTallyActive => _currentTallySessionId != null;
  double get progress => _expectedCount > 0 ? (_scannedCount / _expectedCount) * 100 : 0;

  // Start tally
  Future<bool> startTally(String description) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.startTally(description);
      if (response['success'] == true) {
        _currentTallySessionId = response['data']['tallySession']['_id'];
        _scannedCount = 0;
        _expectedCount = response['data']['expectedItemCount'] ?? 0;
        _scannedWeight = 0.0;
        _expectedWeight = response['data']['tallySession']['expectedTotalWeight']?.toDouble() ?? 0.0;
        _scannedItemIds = [];
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  // Scan item in tally
  Future<Map<String, dynamic>?> scanItem(String barcode) async {
    if (_currentTallySessionId == null) {
      _error = 'No active tally session';
      notifyListeners();
      return null;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.scanItemInTally(_currentTallySessionId!, barcode);
      if (response['success'] == true) {
        _scannedCount = response['data']['scannedCount'] ?? _scannedCount;
        _scannedWeight = response['data']['totalScannedWeight']?.toDouble() ?? _scannedWeight;
        _scannedItemIds.add(response['data']['item']['_id']);
        _isLoading = false;
        notifyListeners();
        return response['data'];
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    }

    _isLoading = false;
    notifyListeners();
    return null;
  }

  // Lock tally
  Future<Map<String, dynamic>?> lockTally() async {
    if (_currentTallySessionId == null) {
      _error = 'No active tally session';
      notifyListeners();
      return null;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.lockTally(_currentTallySessionId!);
      if (response['success'] == true) {
        final result = response['data'];
        _currentTallySessionId = null;
        _isLoading = false;
        notifyListeners();
        return result;
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    }

    _isLoading = false;
    notifyListeners();
    return null;
  }

  // Reset tally
  void resetTally() {
    _currentTallySessionId = null;
    _scannedCount = 0;
    _expectedCount = 0;
    _scannedWeight = 0.0;
    _expectedWeight = 0.0;
    _scannedItemIds = [];
    _error = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
