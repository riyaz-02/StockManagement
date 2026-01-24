import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/tally_model.dart';

class TallyProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  // State
  List<TallySession> _tallySessions = [];
  TallySession? _currentTally;
  bool _isLoading = false;
  String? _error;

  // Getters
  List<TallySession> get tallySessions => _tallySessions;
  TallySession? get currentTally => _currentTally;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasTallySessions => _tallySessions.isNotEmpty;

  // Get active tally
  TallySession? get activeTally {
    try {
      return _tallySessions.firstWhere((t) => t.status == 'active');
    } catch (e) {
      return null;
    }
  }

  // Fetch all tally sessions
  Future<void> fetchTallySessions({String? status}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getTallySessions(status: status);
      if (response['success'] == true) {
        final List<dynamic> tallyData = response['data']['tallySessions'] ?? [];
        _tallySessions = tallyData.map((json) => TallySession.fromJson(json)).toList();
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    }

    _isLoading = false;
    notifyListeners();
  }

  // Fetch single tally session
  Future<TallySession?> fetchTallySession(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getTallySession(id);
      if (response['success'] == true) {
        final tally = TallySession.fromJson(response['data']['tallySession']);
        _currentTally = tally;
        
        // Update in list if exists
        final index = _tallySessions.indexWhere((t) => t.id == id);
        if (index != -1) {
          _tallySessions[index] = tally;
        }
        
        _isLoading = false;
        notifyListeners();
        return tally;
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    }

    _isLoading = false;
    notifyListeners();
    return null;
  }


  // Create new tally
  Future<TallySession?> createTally({
    required String description,
    required int expectedItems,
    required int expectedContainers,
    required double expectedGoldWeight,
    required double expectedSilverWeight,
    DateTime? date,
    List<Map<String, dynamic>>? metalData, // NEW: Optional metal data array
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final requestBody = {
        'date': (date ?? DateTime.now()).toIso8601String(),
        'description': description,
        'expectedItems': expectedItems,
        'expectedContainers': expectedContainers,
        'expectedGoldWeight': expectedGoldWeight,
        'expectedSilverWeight': expectedSilverWeight,
      };
      
      // Add metalData if provided
      if (metalData != null && metalData.isNotEmpty) {
        requestBody['metalData'] = metalData;
      }
      
      final response = await _apiService.createTally(requestBody);

      if (response['success'] == true) {
        final tally = TallySession.fromJson(response['data']['tallySession']);
        _tallySessions.insert(0, tally); // Add to beginning
        _currentTally = tally;
        _isLoading = false;
        notifyListeners();
        return tally;
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    }

    _isLoading = false;
    notifyListeners();
    return null;
  }


  // Scan item in tally
  Future<Map<String, dynamic>?> scanItem(String tallyId, String barcode) async {
    _error = null;
    notifyListeners();

    try {
      print('[PROVIDER] 📡 Calling API scanItemInTally for barcode: $barcode');
      final response = await _apiService.scanItemInTally(tallyId, barcode);
      
      print('[PROVIDER] 📥 API Response: $response');
      print('[PROVIDER] 🔍 Response success: ${response['success']}');
      print('[PROVIDER] 🔍 Response requiresWeightVerification: ${response['requiresWeightVerification']}');
      
      if (response['success'] == true) {
        // Check if weight verification is required
        if (response['requiresWeightVerification'] == true) {
          print('[PROVIDER] ⚖️ WEIGHT VERIFICATION REQUIRED - returning full response');
          // Don't refresh tally yet - wait for weight verification
          return response; // Return full response with requiresWeightVerification flag
        }
        
        print('[PROVIDER] ✅ Normal scan - refreshing tally');
        // For normal scans, refresh tally to get updated counts
        await fetchTallySession(tallyId);
        return response;
      } else {
        print('[PROVIDER] ❌ API returned success=false');
      }
    } catch (e) {
      print('[PROVIDER] ❌ Exception: $e');
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
    }

    return null;
  }

  // Verify weight for approx/bulk items during tally
  Future<bool> verifyTallyWeight(String tallyId, String itemId, double verifiedWeight) async {
    _error = null;
    notifyListeners();

    try {
      print('[PROVIDER] 📡 Calling verifyTallyWeight for item: $itemId, weight: $verifiedWeight');
      final response = await _apiService.verifyTallyWeight(tallyId, itemId, verifiedWeight);
      
      print('[PROVIDER] 📥 Verify weight response: $response');
      
      if (response['success'] == true) {
        print('[PROVIDER] ✅ Weight verified successfully');
        // Refresh tally to get updated data
        await fetchTallySession(tallyId);
        return true;
      } else {
        print('[PROVIDER] ❌ Weight verification failed');
        _error = response['message'] ?? 'Failed to verify weight';
        notifyListeners();
      }
    } catch (e) {
      print('[PROVIDER] ❌ Exception during weight verification: $e');
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
    }

    return false;
  }

  // Lock tally
  Future<bool> lockTally(String tallyId, {String? remarks}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.lockTally(tallyId, remarks: remarks);
      
      if (response['success'] == true) {
        // Refresh tally to get locked status
        await fetchTallySession(tallyId);
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

  // Get tally report
  Future<Map<String, dynamic>?> getTallyReport(String tallyId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getTallyReport(tallyId);
      
      if (response['success'] == true) {
        _isLoading = false;
        notifyListeners();
        return response['data']['report'];
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    }

    _isLoading = false;
    notifyListeners();
    return null;
  }

  // Set current tally
  void setCurrentTally(TallySession tally) {
    _currentTally = tally;
    notifyListeners();
  }

  // Clear current tally
  void clearCurrentTally() {
    _currentTally = null;
    notifyListeners();
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Reset all
  void reset() {
    _tallySessions = [];
    _currentTally = null;
    _error = null;
    notifyListeners();
  }

  // Delete tally session
  Future<bool> deleteTallySession(String id) async {
    _error = null;
    
    try {
      final response = await _apiService.deleteTallySession(id);
      if (response['success'] == true) {
        // Remove from local list
        _tallySessions.removeWhere((t) => t.id == id);
        
        // Clear current tally if it was deleted
        if (_currentTally?.id == id) {
          _currentTally = null;
        }
        
        notifyListeners();
        return true;
      }
      _error = response['message'] ?? 'Failed to delete tally session';
      return false;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }
}
