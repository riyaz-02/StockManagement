class TallySession {
  final String id;
  final DateTime date;
  final String description;
  final String createdBy;
  final String? createdByName;
  final String status; // 'active', 'locked', 'force_locked'
  
  // Initial Setup
  final int expectedItems;
  final int expectedContainers;
  final double expectedGoldWeight;
  final double expectedSilverWeight;
  
  // Real-time Counters
  final int scannedItemsCount;
  final double scannedGoldWeight;
  final double scannedSilverWeight;
  final int outOfStockCount;
  
  // NEW: Dynamic Metal Data
  final List<MetalData> metalData;
  
  // NEW: Items with scan status
  final List<TallyItem> items;
  
  // Lock Details
  final DateTime? lockedAt;
  final String? lockedBy;
  final String? lockedByName;
  final String? lockRemarks;
  final bool isForceLocked;

  // Inventory Snapshot
  final bool inventoryUpdated;
  final DateTime? inventoryUpdatedAt;
  final String? inventorySnapshotId;

  // Timestamps
  final DateTime createdAt;
  final DateTime updatedAt;

  TallySession({
    required this.id,
    required this.date,
    required this.description,
    required this.createdBy,
    this.createdByName,
    required this.status,
    required this.expectedItems,
    required this.expectedContainers,
    required this.expectedGoldWeight,
    required this.expectedSilverWeight,
    this.scannedItemsCount = 0,
    this.scannedGoldWeight = 0.0,
    this.scannedSilverWeight = 0.0,
    this.outOfStockCount = 0,
    this.metalData = const [],
    this.items = const [],
    this.lockedAt,
    this.lockedBy,
    this.lockedByName,
    this.lockRemarks,
    this.isForceLocked = false,
    this.inventoryUpdated = false,
    this.inventoryUpdatedAt,
    this.inventorySnapshotId,
    required this.createdAt,
    required this.updatedAt,
  });

  // Calculate progress percentage
  int get progress {
    if (expectedItems == 0) return 0;
    return ((scannedItemsCount / expectedItems) * 100).round();
  }

  // Items left to scan
  int get itemsLeft => expectedItems - scannedItemsCount;

  // Gold weight difference
  double get goldWeightDifference => expectedGoldWeight - scannedGoldWeight;

  // Silver weight difference
  double get silverWeightDifference => expectedSilverWeight - scannedSilverWeight;

  // Total weight difference
  double get totalWeightDifference => goldWeightDifference + silverWeightDifference;

  // Is locked (any type)
  bool get isLocked => status == 'locked' || status == 'force_locked';

  // Is active
  bool get isActive => status == 'active';
  
  // Get metal data by type
  MetalData? getMetalData(String metalType) {
    try {
      return metalData.firstWhere(
        (m) => m.metalType.toLowerCase() == metalType.toLowerCase(),
      );
    } catch (e) {
      return null;
    }
  }

  factory TallySession.fromJson(Map<String, dynamic> json) {
    // Parse metalData array
    List<MetalData> metalDataList = [];
    if (json['metalData'] != null) {
      metalDataList = (json['metalData'] as List)
          .map((m) => MetalData.fromJson(m))
          .toList();
    }
    
    // Parse items array
    List<TallyItem> itemsList = [];
    if (json['items'] != null) {
      itemsList = (json['items'] as List)
          .map((i) => TallyItem.fromJson(i))
          .toList();
    }
    
    return TallySession(
      id: json['_id'] ?? '',
      date: json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
      description: json['description'] ?? '',
      createdBy: json['createdBy'] is String 
          ? json['createdBy'] 
          : (json['createdBy']?['_id'] ?? ''),
      createdByName: (json['createdBy'] is Map) ? (json['createdBy'] as Map)['name'] as String? : null,
      status: json['status'] ?? 'active',
      expectedItems: json['expectedItems'] ?? 0,
      expectedContainers: json['expectedContainers'] ?? 0,
      expectedGoldWeight: (json['expectedGoldWeight'] ?? 0).toDouble(),
      expectedSilverWeight: (json['expectedSilverWeight'] ?? 0).toDouble(),
      scannedItemsCount: json['scannedItemsCount'] ?? 0,
      scannedGoldWeight: (json['scannedGoldWeight'] ?? 0).toDouble(),
      scannedSilverWeight: (json['scannedSilverWeight'] ?? 0).toDouble(),
      outOfStockCount: json['outOfStockCount'] ?? 0,
      metalData: metalDataList,
      items: itemsList,
      lockedAt: json['lockedAt'] != null ? DateTime.parse(json['lockedAt']) : null,
      lockedBy: json['lockedBy'] is String 
          ? json['lockedBy'] 
          : (json['lockedBy']?['_id']),
      lockedByName: (json['lockedBy'] is Map) ? (json['lockedBy'] as Map)['name'] as String? : null,
      lockRemarks: json['lockRemarks'],
      isForceLocked: json['isForceLocked'] ?? false,
      inventoryUpdated: json['inventoryUpdated'] ?? false,
      inventoryUpdatedAt: json['inventoryUpdatedAt'] != null
          ? DateTime.parse(json['inventoryUpdatedAt'])
          : null,
      inventorySnapshotId: json['inventorySnapshotId'] is String
          ? json['inventorySnapshotId']
          : (json['inventorySnapshotId']?['_id']),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt']) 
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null 
          ? DateTime.parse(json['updatedAt']) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'date': date.toIso8601String(),
      'description': description,
      'createdBy': createdBy,
      'status': status,
      'expectedItems': expectedItems,
      'expectedContainers': expectedContainers,
      'expectedGoldWeight': expectedGoldWeight,
      'expectedSilverWeight': expectedSilverWeight,
      'scannedItemsCount': scannedItemsCount,
      'scannedGoldWeight': scannedGoldWeight,
      'scannedSilverWeight': scannedSilverWeight,
      'outOfStockCount': outOfStockCount,
      'metalData': metalData.map((m) => m.toJson()).toList(),
      'items': items.map((i) => i.toJson()).toList(),
      'lockedAt': lockedAt?.toIso8601String(),
      'lockedBy': lockedBy,
      'lockRemarks': lockRemarks,
      'isForceLocked': isForceLocked,
      'inventoryUpdated': inventoryUpdated,
      'inventoryUpdatedAt': inventoryUpdatedAt?.toIso8601String(),
      'inventorySnapshotId': inventorySnapshotId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

// NEW: Metal Data Model
class MetalData {
  final String metalType;
  final double expectedWeight;
  final int expectedItemCount;
  final double scannedWeight;
  final int scannedItemCount;

  MetalData({
    required this.metalType,
    required this.expectedWeight,
    required this.expectedItemCount,
    this.scannedWeight = 0.0,
    this.scannedItemCount = 0,
  });

  factory MetalData.fromJson(Map<String, dynamic> json) {
    return MetalData(
      metalType: json['metalType'] ?? '',
      expectedWeight: (json['expectedWeight'] ?? 0).toDouble(),
      expectedItemCount: json['expectedItemCount'] ?? 0,
      scannedWeight: (json['scannedWeight'] ?? 0).toDouble(),
      scannedItemCount: json['scannedItemCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'metalType': metalType,
      'expectedWeight': expectedWeight,
      'expectedItemCount': expectedItemCount,
      'scannedWeight': scannedWeight,
      'scannedItemCount': scannedItemCount,
    };
  }
}

// NEW: Tally Item Model
class TallyItem {
  final String itemId;
  final String barcode;
  final String metalType;
  final double weight;
  final bool isScanned;
  final String status;
  final DateTime? scannedAt;
  final String? scannedBy;

  TallyItem({
    required this.itemId,
    required this.barcode,
    required this.metalType,
    required this.weight,
    this.isScanned = false,
    this.status = 'in_stock',
    this.scannedAt,
    this.scannedBy,
  });

  // Removed from stock (soft-deleted) during this tally's cleanup
  bool get isRemoved => status == 'removed';

  factory TallyItem.fromJson(Map<String, dynamic> json) {
    return TallyItem(
      itemId: json['itemId'] is String 
          ? json['itemId'] 
          : (json['itemId']?['_id'] ?? ''),
      barcode: json['barcode'] ?? '',
      metalType: json['metalType'] ?? '',
      weight: (json['weight'] ?? 0).toDouble(),
      isScanned: json['isScanned'] ?? false,
      status: json['status'] ?? 'in_stock',
      scannedAt: json['scannedAt'] != null 
          ? DateTime.parse(json['scannedAt']) 
          : null,
      scannedBy: json['scannedBy'] is String 
          ? json['scannedBy'] 
          : (json['scannedBy']?['_id']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'itemId': itemId,
      'barcode': barcode,
      'metalType': metalType,
      'weight': weight,
      'isScanned': isScanned,
      'status': status,
      'scannedAt': scannedAt?.toIso8601String(),
      'scannedBy': scannedBy,
    };
  }
}

class ScannedItemDetail {
  final String itemId;
  final DateTime scannedAt;
  final String scannedBy;
  final String status; // 'in_stock' or 'out_of_stock'
  final double weight;
  final String metalType;

  ScannedItemDetail({
    required this.itemId,
    required this.scannedAt,
    required this.scannedBy,
    required this.status,
    required this.weight,
    required this.metalType,
  });

  factory ScannedItemDetail.fromJson(Map<String, dynamic> json) {
    return ScannedItemDetail(
      itemId: json['itemId'] is String 
          ? json['itemId'] 
          : (json['itemId']?['_id'] ?? ''),
      scannedAt: json['scannedAt'] != null 
          ? DateTime.parse(json['scannedAt']) 
          : DateTime.now(),
      scannedBy: json['scannedBy'] is String 
          ? json['scannedBy'] 
          : (json['scannedBy']?['_id'] ?? ''),
      status: json['status'] ?? 'in_stock',
      weight: (json['weight'] ?? 0).toDouble(),
      metalType: json['metalType'] ?? '',
    );
  }
}
