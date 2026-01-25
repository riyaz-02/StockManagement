import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/item_model.dart';

/// Local SQLite database for offline tally operations
class TallyDatabase {
  static final TallyDatabase _instance = TallyDatabase._internal();
  factory TallyDatabase() => _instance;
  TallyDatabase._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'tally_offline.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Tally items table - stores all items for active tally
    await db.execute('''
      CREATE TABLE tally_items (
        id TEXT PRIMARY KEY,
        tally_id TEXT NOT NULL,
        barcode TEXT NOT NULL,
        item_name TEXT,
        category TEXT,
        net_weight REAL,
        purity TEXT,
        gross_weight REAL,
        container_name TEXT,
        scan_status TEXT DEFAULT 'not_scanned',
        scanned_at TEXT,
        synced INTEGER DEFAULT 0,
        created_at TEXT
      )
    ''');

    // Create indexes for fast lookups
    await db.execute('CREATE INDEX idx_barcode ON tally_items(barcode)');
    await db.execute('CREATE INDEX idx_tally_id ON tally_items(tally_id)');
    await db.execute('CREATE INDEX idx_scan_status ON tally_items(scan_status)');
    await db.execute('CREATE INDEX idx_synced ON tally_items(synced)');

    // Sync queue table - tracks pending updates to server
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tally_id TEXT NOT NULL,
        item_id TEXT NOT NULL,
        barcode TEXT NOT NULL,
        action TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        synced INTEGER DEFAULT 0,
        retry_count INTEGER DEFAULT 0,
        error TEXT
      )
    ''');

    // Tally metadata table - tracks tally download/sync status
    await db.execute('''
      CREATE TABLE tally_metadata (
        tally_id TEXT PRIMARY KEY,
        status TEXT NOT NULL,
        total_items INTEGER DEFAULT 0,
        scanned_items INTEGER DEFAULT 0,
        downloaded_at TEXT,
        last_sync_at TEXT
      )
    ''');
  }

  // ==================== TALLY INITIALIZATION ====================

  /// Download all tally items from server and store locally
  Future<void> downloadTallyItems(String tallyId, List<Item> items) async {
    final db = await database;

    await db.transaction((txn) async {
      // Clear existing data for this tally
      await txn.delete('tally_items', where: 'tally_id = ?', whereArgs: [tallyId]);
      await txn.delete('sync_queue', where: 'tally_id = ?', whereArgs: [tallyId]);

      // Insert all items
      for (final item in items) {
        await txn.insert('tally_items', {
          'id': item.id,
          'tally_id': tallyId,
          'barcode': item.barcode ?? '',
          'item_name': item.name,
          'category': item.category,
          'net_weight': item.netWeight,
          'purity': item.purity,
          'gross_weight': item.grossWeight,
          'container_name': item.containerName,
          'scan_status': 'not_scanned',
          'scanned_at': null,
          'synced': 1, // Initial download is synced
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      // Update metadata
      await txn.insert(
        'tally_metadata',
        {
          'tally_id': tallyId,
          'status': 'ready',
          'total_items': items.length,
          'scanned_items': 0,
          'downloaded_at': DateTime.now().toIso8601String(),
          'last_sync_at': null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  // ==================== OFFLINE SCANNING ====================

  /// Scan barcode offline - instant lookup from local database
  Future<Map<String, dynamic>?> scanBarcodeOffline(String tallyId, String barcode) async {
    final db = await database;

    // Find item by barcode
    final results = await db.query(
      'tally_items',
      where: 'tally_id = ? AND barcode = ?',
      whereArgs: [tallyId, barcode],
    );

    if (results.isEmpty) {
      return null; // Item not found
    }

    final item = results.first;
    final itemId = item['id'] as String;
    final currentStatus = item['scan_status'] as String;

    // Check if already scanned
    if (currentStatus == 'scanned') {
      return {
        'success': false,
        'message': 'Item already scanned',
        'item': item,
      };
    }

    // Update scan status locally
    await db.update(
      'tally_items',
      {
        'scan_status': 'scanned',
        'scanned_at': DateTime.now().toIso8601String(),
        'synced': 0, // Mark as not synced
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );

    // Add to sync queue
    await db.insert('sync_queue', {
      'tally_id': tallyId,
      'item_id': itemId,
      'barcode': barcode,
      'action': 'scan',
      'timestamp': DateTime.now().toIso8601String(),
      'synced': 0,
      'retry_count': 0,
    });

    // Update scanned count in metadata
    await db.rawUpdate('''
      UPDATE tally_metadata 
      SET scanned_items = scanned_items + 1 
      WHERE tally_id = ?
    ''', [tallyId]);

    // Get updated item
    final updatedResults = await db.query(
      'tally_items',
      where: 'id = ?',
      whereArgs: [itemId],
    );

    return {
      'success': true,
      'message': 'Item scanned successfully',
      'item': updatedResults.first,
    };
  }

  // ==================== SYNC OPERATIONS ====================

  /// Get pending scans that need to be synced to server
  Future<List<Map<String, dynamic>>> getPendingScans() async {
    final db = await database;
    return await db.query(
      'sync_queue',
      where: 'synced = 0',
      orderBy: 'timestamp ASC',
    );
  }

  /// Mark scan as synced
  Future<void> markScanAsSynced(int syncId) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [syncId],
    );

    // Also update the item as synced
    final syncRecord = await db.query(
      'sync_queue',
      where: 'id = ?',
      whereArgs: [syncId],
    );

    if (syncRecord.isNotEmpty) {
      final itemId = syncRecord.first['item_id'];
      await db.update(
        'tally_items',
        {'synced': 1},
        where: 'id = ?',
        whereArgs: [itemId],
      );
    }
  }

  /// Mark scan as failed and increment retry count
  Future<void> markScanAsFailed(int syncId, String error) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE sync_queue 
      SET retry_count = retry_count + 1, error = ? 
      WHERE id = ?
    ''', [error, syncId]);
  }

  // ==================== TALLY STATUS ====================

  /// Get tally statistics
  Future<Map<String, dynamic>?> getTallyStats(String tallyId) async {
    final db = await database;

    final metadata = await db.query(
      'tally_metadata',
      where: 'tally_id = ?',
      whereArgs: [tallyId],
    );

    if (metadata.isEmpty) return null;

    final scannedCount = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM tally_items WHERE tally_id = ? AND scan_status = ?',
        [tallyId, 'scanned'],
      ),
    ) ?? 0;

    final notScannedCount = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM tally_items WHERE tally_id = ? AND scan_status = ?',
        [tallyId, 'not_scanned'],
      ),
    ) ?? 0;

    final pendingSyncCount = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM sync_queue WHERE tally_id = ? AND synced = 0',
        [tallyId],
      ),
    ) ?? 0;

    return {
      ...metadata.first,
      'scanned_count': scannedCount,
      'not_scanned_count': notScannedCount,
      'pending_sync_count': pendingSyncCount,
    };
  }

  /// Get all items for a tally with their scan status
  Future<List<Map<String, dynamic>>> getTallyItems(String tallyId, {String? scanStatus}) async {
    final db = await database;

    if (scanStatus != null) {
      return await db.query(
        'tally_items',
        where: 'tally_id = ? AND scan_status = ?',
        whereArgs: [tallyId, scanStatus],
        orderBy: 'item_name ASC',
      );
    }

    return await db.query(
      'tally_items',
      where: 'tally_id = ?',
      whereArgs: [tallyId],
      orderBy: 'item_name ASC',
    );
  }

  // ==================== CLEANUP ====================

  /// Clear all data for a tally (after successful lock)
  Future<void> clearTally(String tallyId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('tally_items', where: 'tally_id = ?', whereArgs: [tallyId]);
      await txn.delete('sync_queue', where: 'tally_id = ?', whereArgs: [tallyId]);
      await txn.delete('tally_metadata', where: 'tally_id = ?', whereArgs: [tallyId]);
    });
  }

  /// Clear all database data (for testing/reset)
  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('tally_items');
      await txn.delete('sync_queue');
      await txn.delete('tally_metadata');
    });
  }

  /// Close database connection
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
