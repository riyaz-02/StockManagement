import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/api_service.dart';
import '../services/tally_database.dart';

/// Background sync service for uploading pending scans to server
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final TallyDatabase _db = TallyDatabase();
  final ApiService _api = ApiService();
  final Connectivity _connectivity = Connectivity();

  Timer? _syncTimer;
  StreamSubscription? _connectivitySubscription;
  bool _isSyncing = false;
  
  // Callbacks for sync status updates
  Function(int pending, int failed)? onSyncStatusChanged;
  Function(String message)? onSyncError;
  Function()? onSyncComplete;

  // ==================== SYNC CONTROL ====================

  /// Start periodic background sync (every 5 seconds)
  void startPeriodicSync() {
    // Cancel existing timer if any
    stopPeriodicSync();

    // Start periodic sync
    _syncTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => syncPendingScans(),
    );

    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        // Network reconnected - sync immediately
        syncPendingScans();
      }
    });

    // Initial sync
    syncPendingScans();
  }

  /// Stop periodic sync
  void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  // ==================== SYNC OPERATIONS ====================

  /// Sync all pending scans to server
  Future<void> syncPendingScans() async {
    // Prevent concurrent syncs
    if (_isSyncing) return;

    _isSyncing = true;

    try {
      // Check network connectivity
      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        _isSyncing = false;
        return; // No network, skip sync
      }

      // Get pending scans
      final pendingScans = await _db.getPendingScans();

      if (pendingScans.isEmpty) {
        onSyncComplete?.call();
        _isSyncing = false;
        return;
      }

      int successCount = 0;
      int failCount = 0;

      // Sync each pending scan
      for (final scan in pendingScans) {
        final syncId = scan['id'] as int;
        final tallyId = scan['tally_id'] as String;
        final itemId = scan['item_id'] as String;
        final barcode = scan['barcode'] as String;
        final action = scan['action'] as String;

        try {
          if (action == 'scan') {
            // Upload scan to server
            final response = await _api.scanBarcode(barcode);

            if (response['success'] == true) {
              // Mark as synced
              await _db.markScanAsSynced(syncId);
              successCount++;
            } else {
              throw Exception(response['message'] ?? 'Scan failed');
            }
          }
        } catch (e) {
          // Mark as failed and increment retry count
          await _db.markScanAsFailed(syncId, e.toString());
          failCount++;

          // Notify error
          onSyncError?.call('Failed to sync scan: ${e.toString()}');
        }
      }

      // Notify status change
      final remainingPending = await _db.getPendingScans();
      onSyncStatusChanged?.call(remainingPending.length, failCount);

      if (remainingPending.isEmpty) {
        onSyncComplete?.call();
      }
    } catch (e) {
      onSyncError?.call('Sync error: ${e.toString()}');
    } finally {
      _isSyncing = false;
    }
  }

  /// Force sync all pending scans and wait for completion
  Future<bool> syncAllAndWait({Duration timeout = const Duration(seconds: 30)}) async {
    final completer = Completer<bool>();
    Timer? timeoutTimer;

    // Set up completion callback
    void onComplete() {
      if (!completer.isCompleted) {
        timeoutTimer?.cancel();
        completer.complete(true);
      }
    }

    // Set up timeout
    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });

    // Temporarily set completion callback
    final originalCallback = onSyncComplete;
    onSyncComplete = onComplete;

    // Start syncing
    await syncPendingScans();

    // Wait for completion or timeout
    final result = await completer.future;

    // Restore original callback
    onSyncComplete = originalCallback;

    return result;
  }

  /// Get current sync status
  Future<Map<String, dynamic>> getSyncStatus() async {
    final pendingScans = await _db.getPendingScans();
    
    int failedCount = 0;
    for (final scan in pendingScans) {
      if ((scan['retry_count'] as int) > 0) {
        failedCount++;
      }
    }

    return {
      'is_syncing': _isSyncing,
      'pending_count': pendingScans.length,
      'failed_count': failedCount,
      'has_network': await _hasNetworkConnection(),
    };
  }

  /// Check if device has network connection
  Future<bool> _hasNetworkConnection() async {
    final connectivityResult = await _connectivity.checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  // ==================== CLEANUP ====================

  /// Dispose resources
  void dispose() {
    stopPeriodicSync();
    onSyncStatusChanged = null;
    onSyncError = null;
    onSyncComplete = null;
  }
}
