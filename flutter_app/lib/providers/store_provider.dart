import 'package:flutter/material.dart';
import '../models/stock_summary_models.dart';
import '../services/api_service.dart';
import '../models/purchase_model.dart';
import '../models/store_models.dart';

class StoreProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  // ── Stock Dashboard State ────────────────────────────────────────────────
  Map<String, dynamic> _barcodedStock = {};
  List<BulkWeight> _bulkWeights = [];
  Map<String, double> _totalStock = {};
  bool _isDashboardLoading = false;
  String? _dashboardError;

  Map<String, dynamic> get barcodedStock => _barcodedStock;
  List<BulkWeight> get bulkWeights => _bulkWeights;
  Map<String, double> get totalStock => _totalStock;
  bool get isDashboardLoading => _isDashboardLoading;
  String? get dashboardError => _dashboardError;

  // ── Purchases State ──────────────────────────────────────────────────────
  List<Purchase> _purchases = [];
  bool _isPurchasesLoading = false;
  String? _purchasesError;
  int _purchasesTotal = 0;
  Map<String, dynamic> _metalTotals = {};
  String _purchaseSort = 'date_desc';

  List<Purchase> get purchases => _purchases;
  bool get isPurchasesLoading => _isPurchasesLoading;
  String? get purchasesError => _purchasesError;
  int get purchasesTotal => _purchasesTotal;
  Map<String, dynamic> get metalTotals => _metalTotals;
  String get purchaseSort => _purchaseSort;

  // ── ITC Summary State ────────────────────────────────────────────────────
  Map<String, dynamic>? _itcSummary;
  bool _isItcLoading = false;
  String? _itcError;
  String _selectedFy = '';

  Map<String, dynamic>? get itcSummary => _itcSummary;
  bool get isItcLoading => _isItcLoading;
  String? get itcError => _itcError;
  String get selectedFy => _selectedFy;

  // ── GST Config State ─────────────────────────────────────────────────────
  GstConfig? _gstConfig;
  bool _isGstLoading = false;
  String? _gstError;

  GstConfig? get gstConfig => _gstConfig;
  bool get isGstLoading => _isGstLoading;
  String? get gstError => _gstError;

  // ── Daily Summary State ──────────────────────────────────────────────────
  Map<String, dynamic> _dailySummary = {};
  bool _isSummaryLoading = false;

  Map<String, dynamic> get dailySummary => _dailySummary;
  bool get isSummaryLoading => _isSummaryLoading;

  // ── Reconciliation State ─────────────────────────────────────────────────
  Map<String, dynamic> _reconciliation = {};
  bool _isReconcileLoading = false;
  bool _hasReconcileAlert = false;

  Map<String, dynamic> get reconciliation => _reconciliation;
  bool get isReconcileLoading => _isReconcileLoading;
  bool get hasReconcileAlert => _hasReconcileAlert;

  // ── Stock Summary (the metal balance), history, wastage ───────────────
  StockSummary? _summary;
  bool _isSummaryBusy = false;
  String? _summaryError;
  StockSummary? get summary => _summary;
  bool get isSummaryBusy => _isSummaryBusy;
  String? get summaryError => _summaryError;

  StockHistory? _history;
  bool _isHistoryLoading = false;
  StockHistory? get history => _history;
  bool get isHistoryLoading => _isHistoryLoading;

  // ────────────────────────────────────────────────────────────────────────
  // ITC SUMMARY
  // ────────────────────────────────────────────────────────────────────────

  Future<void> fetchItcSummary({String? fy}) async {
    _isItcLoading = true;
    _itcError = null;
    notifyListeners();
    try {
      final resp = await _api.getItcSummary(fy: fy);
      if (resp['success'] == true) {
        _itcSummary = Map<String, dynamic>.from(resp['data'] ?? {});
        _selectedFy = _itcSummary?['fy'] ?? fy ?? '';
      } else {
        _itcError = resp['message'] ?? 'Failed to load ITC summary';
      }
    } catch (e) {
      _itcError = e.toString();
    } finally {
      _isItcLoading = false;
      notifyListeners();
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // STOCK DASHBOARD
  // ────────────────────────────────────────────────────────────────────────

  Future<void> fetchStockDashboard() async {
    _isDashboardLoading = true;
    _dashboardError = null;
    notifyListeners();

    try {
      final resp = await _api.getStockDashboard();
      if (resp['success'] == true) {
        final data = resp['data'] as Map<String, dynamic>;
        _barcodedStock = Map<String, dynamic>.from(data['barcodedStock'] ?? {});

        final rawBulk = data['bulkWeights'] as List? ?? [];
        _bulkWeights = rawBulk.map((e) => BulkWeight.fromJson(e)).toList();

        _totalStock = {};
        (data['totalStock'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
          _totalStock[k] = (v as num).toDouble();
        });
      } else {
        _dashboardError = resp['message'] ?? 'Failed to load dashboard';
      }
    } catch (e) {
      _dashboardError = e.toString();
    } finally {
      _isDashboardLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addBulkWeight({
    required String metalType,
    required double weightGrams,
    required String description,
    String category = 'other',
    String purity = '',
    int? pieces,
  }) async {
    try {
      final resp = await _api.addBulkWeight({
        'metalType': metalType,
        'weightGrams': weightGrams,
        'description': description,
        'category': category,
        if (purity.isNotEmpty) 'purity': purity,
        if (pieces != null) 'pieces': pieces,
      });
      if (resp['success'] == true) {
        await fetchStockDashboard();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateBulkWeight(
      String id, double weightGrams, String description,
      {String? category, String? purity, int? pieces}) async {
    try {
      final resp = await _api.updateBulkWeight(id, {
        'weightGrams': weightGrams,
        'description': description,
        if (category != null) 'category': category,
        if (purity != null) 'purity': purity,
        if (pieces != null) 'pieces': pieces,
      });
      if (resp['success'] == true) {
        await fetchStockDashboard();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteBulkWeight(String id) async {
    try {
      final resp = await _api.deleteBulkWeight(id);
      if (resp['success'] == true) {
        await fetchStockDashboard();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // PURCHASES
  // ────────────────────────────────────────────────────────────────────────

  Future<void> fetchPurchases({
    String? metalType,
    String? biller,
    String? startDate,
    String? endDate,
    int page = 1,
    String? sort,
  }) async {
    _isPurchasesLoading = true;
    _purchasesError = null;
    if (sort != null) _purchaseSort = sort;
    notifyListeners();

    try {
      final resp = await _api.getPurchases(
        metalType: metalType,
        biller: biller,
        startDate: startDate,
        endDate: endDate,
        page: page,
        sort: _purchaseSort,
      );
      if (resp['success'] == true) {
        final data = resp['data'] as Map<String, dynamic>;
        final list = data['purchases'] as List? ?? [];
        _purchases = list.map((e) => Purchase.fromJson(e)).toList();
        _purchasesTotal = (data['pagination']?['total'] as int?) ?? 0;
        _metalTotals = Map<String, dynamic>.from(
            data['metalTotals'] as Map? ?? {});
      } else {
        _purchasesError = resp['message'] ?? 'Failed to load purchases';
      }
    } catch (e) {
      _purchasesError = e.toString();
    } finally {
      _isPurchasesLoading = false;
      notifyListeners();
    }
  }

  /// Returns error message string on failure, null on success
  Future<String?> createPurchase(Map<String, dynamic> data) async {
    try {
      final resp = await _api.createPurchase(data);
      if (resp['success'] == true) {
        await fetchPurchases();
        return null;
      }
      return resp['message'] ?? 'Failed to create purchase';
    } catch (e) {
      return e.toString();
    }
  }

  /// Returns error message string on failure, null on success
  Future<String?> updatePurchase(String id, Map<String, dynamic> data) async {
    try {
      final resp = await _api.updatePurchase(id, data);
      if (resp['success'] == true) {
        await fetchPurchases();
        return null;
      }
      return resp['message'] ?? 'Failed to update purchase';
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> deletePurchase(String id) async {
    try {
      final resp = await _api.deletePurchase(id);
      if (resp['success'] == true) {
        await fetchPurchases();
        return null;
      }
      return resp['message'] ?? 'Failed to delete purchase';
    } catch (e) {
      return e.toString();
    }
  }

  // ── Purchase Bill Attachment Upload ─────────────────────────────────────

  /// Uploads a file to Cloudinary via the backend.
  /// Returns the attachment meta map {url, publicId, originalName, format} or null on failure.
  Future<Map<String, dynamic>?> uploadPurchaseBill({
    required String filePath,
    required String mimeType,
    required String originalName,
  }) async {
    try {
      final resp = await _api.uploadPurchaseBill(
        filePath: filePath,
        mimeType: mimeType,
        originalName: originalName,
      );
      if (resp['success'] == true) {
        return Map<String, dynamic>.from(resp['data'] as Map);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> deletePurchaseBillAttachment(String publicId) async {
    try {
      final resp = await _api.deletePurchaseBillAttachment(publicId);
      return resp['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // GST CONFIG
  // ────────────────────────────────────────────────────────────────────────

  Future<void> fetchGstConfig() async {
    _isGstLoading = true;
    _gstError = null;
    notifyListeners();

    try {
      final resp = await _api.getGstConfig();
      if (resp['success'] == true) {
        _gstConfig = GstConfig.fromJson(resp['data']['config']);
      } else {
        _gstError = resp['message'];
      }
    } catch (e) {
      _gstError = e.toString();
    } finally {
      _isGstLoading = false;
      notifyListeners();
    }
  }

  Future<String?> updateGstConfig(Map<String, dynamic> data) async {
    try {
      final resp = await _api.updateGstConfig(data);
      if (resp['success'] == true) {
        _gstConfig = GstConfig.fromJson(resp['data']['config']);
        notifyListeners();
        return null;
      }
      return resp['message'] ?? 'Failed to update GST config';
    } catch (e) {
      return e.toString();
    }
  }

  Future<GstCalculation?> calculateGst({
    required double baseAmount,
    String transactionType = 'intra-state',
  }) async {
    try {
      final resp = await _api.calculateGst(
          baseAmount: baseAmount, transactionType: transactionType);
      if (resp['success'] == true) {
        return GstCalculation.fromJson(resp['data']);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Validates a GSTIN string via the backend regex check.
  /// Returns true if valid, false if invalid, null on network error.
  Future<bool?> checkGstin(String gstin) async {
    try {
      final resp = await _api.validateGstin(gstin);
      return resp['data']?['valid'] == true;
    } catch (_) {
      return null;
    }
  }

  /// Validates a PAN string via the backend regex check.
  /// Returns true if valid, false if invalid, null on network error.
  Future<bool?> checkPan(String pan) async {
    try {
      final resp = await _api.validatePan(pan);
      return resp['data']?['valid'] == true;
    } catch (_) {
      return null;
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // DAILY SUMMARY
  // ────────────────────────────────────────────────────────────────────────

  Future<void> fetchDailySummary({
    String? startDate,
    String? endDate,
    String? metalType,
  }) async {
    _isSummaryLoading = true;
    notifyListeners();

    try {
      final resp = await _api.getStockDailySummary(
        startDate: startDate,
        endDate: endDate,
        metalType: metalType,
      );
      if (resp['success'] == true) {
        _dailySummary = Map<String, dynamic>.from(
            resp['data']['summary'] as Map? ?? {});
      }
    } catch (_) {
      _dailySummary = {};
    } finally {
      _isSummaryLoading = false;
      notifyListeners();
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // RECONCILIATION
  // ────────────────────────────────────────────────────────────────────────

  /// Kept by its old name (the Store screen calls it): it now loads the whole Summary.
  Future<void> fetchReconciliation() => fetchSummary();

  /// The Summary: balance, data checks, insights, movements. The server works everything out.
  Future<void> fetchSummary() async {
    _isReconcileLoading = true;
    _summaryError = null;
    notifyListeners();
    try {
      final resp = await _api.getStockSummary();
      if (resp['success'] == true) {
        _summary = StockSummary.fromJson(Map<String, dynamic>.from(resp['data'] as Map));
        _hasReconcileAlert = _summary!.anyAlert || _summary!.confidenceLevel == 'fix';
      }
    } catch (e) {
      _summaryError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isReconcileLoading = false;
      notifyListeners();
    }
  }

  Future<List<Movement>> fetchMovements({int limit = 30}) async {
    try {
      final resp = await _api.getSummaryMovements(limit: limit);
      if (resp['success'] == true) {
        return (resp['data']['movements'] as List? ?? [])
            .map((e) => Movement.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Save today's snapshot (built by the server). Returns a message to show.
  Future<String> saveSnapshot() async {
    _isSummaryBusy = true;
    notifyListeners();
    try {
      final resp = await _api.saveStockSnapshot();
      await fetchSummary();
      return (resp['message'] ?? 'Snapshot saved').toString();
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isSummaryBusy = false;
      notifyListeners();
    }
  }

  Future<void> fetchHistory({String view = 'daily', String? from, String? to}) async {
    _isHistoryLoading = true;
    notifyListeners();
    try {
      final resp = await _api.getSummaryHistory(view: view, from: from, to: to);
      if (resp['success'] == true) {
        _history = StockHistory.fromJson(Map<String, dynamic>.from(resp['data'] as Map));
      }
    } catch (_) {
      _history = const StockHistory([], false, false, {});
    } finally {
      _isHistoryLoading = false;
      notifyListeners();
    }
  }

  // ── wastage reports ─────────────────────────────────────────────────────

  Future<({List<WastageReport> reports, Map<String, dynamic> totals})> fetchWastage({String? status, String? metal}) async {
    try {
      final resp = await _api.getWastageReports(status: status, metal: metal, limit: 100);
      if (resp['success'] == true) {
        final d = Map<String, dynamic>.from(resp['data'] as Map);
        return (
          reports: (d['reports'] as List? ?? []).map((e) => WastageReport.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
          totals: Map<String, dynamic>.from(d['totals'] as Map? ?? {}),
        );
      }
    } catch (_) {}
    return (reports: <WastageReport>[], totals: <String, dynamic>{});
  }

  /// null = done; otherwise the message to show (the server's own words).
  Future<String?> reportWastage(Map<String, dynamic> body, {String? editId}) async {
    try {
      if (editId == null) {
        await _api.createWastage(body);
      } else {
        await _api.updateWastage(editId, body);
      }
      await fetchSummary();
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  Future<String?> decideWastage(String id, {required bool approve, String comment = ''}) async {
    try {
      if (approve) {
        await _api.approveWastage(id, comment);
      } else {
        await _api.rejectWastage(id, comment);
      }
      await fetchSummary();
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }
}
