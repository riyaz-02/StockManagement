import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class AnalyticsProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _dashboardStats;

  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, dynamic>? get dashboardStats => _dashboardStats;

  // Get individual stats - counts
  int get totalItems => _dashboardStats?['totalItems'] ?? 0;
  int get totalContainers => _dashboardStats?['totalContainers'] ?? 0;
  int get itemsInStock => _dashboardStats?['itemsByStatus']?['active']?['count'] ?? 0;
  int get itemsOutOfStock => _dashboardStats?['itemsByStatus']?['out_of_stock']?['count'] ?? 0;
  int get itemsInRepair => _dashboardStats?['itemsByStatus']?['in_repair']?['count'] ?? 0;
  int get itemsBooked => _dashboardStats?['itemsByStatus']?['booked']?['count'] ?? 0;
  int get totalTallies => _dashboardStats?['totalTallies'] ?? 0;
  int get activeTallies => _dashboardStats?['activeTallies'] ?? 0;
  int get soldItems => _dashboardStats?['soldItems'] ?? 0;
  
  // Get weights
  double get totalWeight => (_dashboardStats?['totalWeight'] ?? 0).toDouble();
  double get inStockWeight => (_dashboardStats?['itemsByStatus']?['active']?['weight'] ?? 0).toDouble();
  double get outOfStockWeight => (_dashboardStats?['itemsByStatus']?['out_of_stock']?['weight'] ?? 0).toDouble();
  double get inRepairWeight => (_dashboardStats?['itemsByStatus']?['in_repair']?['weight'] ?? 0).toDouble();
  double get bookedWeight => (_dashboardStats?['itemsByStatus']?['booked']?['weight'] ?? 0).toDouble();
  
  // Current stock (physically in shop) - excludes items with customers/agents
  List<Map<String, dynamic>> get currentStockMetalBreakdown => 
    (_dashboardStats?['currentStockMetalBreakdown'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
  
  double get currentStockTotalWeight => (_dashboardStats?['currentStockTotalWeight'] ?? 0).toDouble();
  int get currentStockTotalCount => _dashboardStats?['currentStockTotalCount'] ?? 0;
  
  // Detailed breakdown - array of {status, metal, weight, count}
  List<Map<String, dynamic>> get detailedBreakdown => 
    (_dashboardStats?['detailedBreakdown'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
  
  // Helper methods to filter detailed breakdown by status
  List<Map<String, dynamic>> getBreakdownByStatus(String status) {
    return detailedBreakdown.where((item) => item['status'] == status).toList();
  }
  
  List<Map<String, dynamic>> get inRepairBreakdown => getBreakdownByStatus('UNDER_REPAIR')
    ..addAll(getBreakdownByStatus('in_repair'));
  
  List<Map<String, dynamic>> get bookedBreakdown => getBreakdownByStatus('booked');
  
  List<Map<String, dynamic>> get withCustomerBreakdown => getBreakdownByStatus('WITH_CUSTOMER');
  
  List<Map<String, dynamic>> get withAgentBreakdown => getBreakdownByStatus('WITH_AGENT');

  Future<void> fetchDashboardStats() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('📊 [Analytics] Fetching dashboard stats...');
      final response = await _apiService.getDashboardStats();
      
      debugPrint('📊 [Analytics] Response received: ${response.toString()}');
      
      if (response['success'] == true) {
        _dashboardStats = response['data'];
        _error = null;
        
        // Log all stats for debugging
        debugPrint('✅ [Analytics] Stats fetched successfully!');
        debugPrint('   Total Items: ${_dashboardStats?['totalItems']}');
        debugPrint('   Total Weight: ${_dashboardStats?['totalWeight']}g');
        debugPrint('   Total Containers: ${_dashboardStats?['totalContainers']}');
        debugPrint('   Total Tallies: ${_dashboardStats?['totalTallies']}');
        debugPrint('   Active Tallies: ${_dashboardStats?['activeTallies']}');
        debugPrint('   Sold Items: ${_dashboardStats?['soldItems']}');
        debugPrint('   Items by Status: ${_dashboardStats?['itemsByStatus']}');
        debugPrint('   Metal Breakdown: ${_dashboardStats?['metalBreakdown']}');
      } else {
        _error = response['message'] ?? 'Failed to fetch dashboard stats';
        debugPrint('❌ [Analytics] Error: $_error');
      }
    } catch (e) {
      _error = 'Error: ${e.toString()}';
      debugPrint('❌ [Analytics] Exception: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshStats() async {
    await fetchDashboardStats();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
