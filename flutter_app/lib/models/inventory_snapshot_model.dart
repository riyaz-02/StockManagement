class InventorySnapshotSummary {
  final String id;
  final DateTime date;
  final String? createdByName;
  final String? tallyDescription;
  final int totalItems;
  final int totalContainers;
  final List<MetalTotal> byMetal;
  final DateTime createdAt;

  InventorySnapshotSummary({
    required this.id,
    required this.date,
    this.createdByName,
    this.tallyDescription,
    required this.totalItems,
    required this.totalContainers,
    required this.byMetal,
    required this.createdAt,
  });

  factory InventorySnapshotSummary.fromJson(Map<String, dynamic> json) {
    return InventorySnapshotSummary(
      id: json['_id'] ?? '',
      date: json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
      createdByName: (json['createdBy'] is Map) ? json['createdBy']['name'] as String? : null,
      tallyDescription: (json['tallySessionId'] is Map) ? json['tallySessionId']['description'] as String? : null,
      totalItems: json['totalItems'] ?? 0,
      totalContainers: json['totalContainers'] ?? 0,
      byMetal: json['byMetal'] != null
          ? (json['byMetal'] as List).map((m) => MetalTotal.fromJson(m)).toList()
          : [],
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
    );
  }
}

class InventorySnapshot extends InventorySnapshotSummary {
  final List<InventorySnapshotItem> items;

  InventorySnapshot({
    required super.id,
    required super.date,
    super.createdByName,
    super.tallyDescription,
    required super.totalItems,
    required super.totalContainers,
    required super.byMetal,
    required super.createdAt,
    required this.items,
  });

  factory InventorySnapshot.fromJson(Map<String, dynamic> json) {
    final summary = InventorySnapshotSummary.fromJson(json);
    return InventorySnapshot(
      id: summary.id,
      date: summary.date,
      createdByName: summary.createdByName,
      tallyDescription: summary.tallyDescription,
      totalItems: summary.totalItems,
      totalContainers: summary.totalContainers,
      byMetal: summary.byMetal,
      createdAt: summary.createdAt,
      items: json['items'] != null
          ? (json['items'] as List).map((i) => InventorySnapshotItem.fromJson(i)).toList()
          : [],
    );
  }
}

class MetalTotal {
  final String metalType;
  final double totalWeight;
  final int itemCount;

  MetalTotal({
    required this.metalType,
    required this.totalWeight,
    required this.itemCount,
  });

  factory MetalTotal.fromJson(Map<String, dynamic> json) {
    return MetalTotal(
      metalType: json['metalType'] ?? '',
      totalWeight: (json['totalWeight'] ?? 0).toDouble(),
      itemCount: json['itemCount'] ?? 0,
    );
  }
}

class InventorySnapshotItem {
  final String itemId;
  final String barcode;
  final String? name;
  final String metalType;
  final double netWeight;
  final String? containerName;
  final int? slotNumber;
  final String status;

  InventorySnapshotItem({
    required this.itemId,
    required this.barcode,
    this.name,
    required this.metalType,
    required this.netWeight,
    this.containerName,
    this.slotNumber,
    required this.status,
  });

  factory InventorySnapshotItem.fromJson(Map<String, dynamic> json) {
    return InventorySnapshotItem(
      itemId: json['itemId'] ?? '',
      barcode: json['barcode'] ?? '',
      name: json['name'],
      metalType: json['metalType'] ?? '',
      netWeight: (json['netWeight'] ?? 0).toDouble(),
      containerName: json['containerName'],
      slotNumber: json['slotNumber'],
      status: json['status'] ?? '',
    );
  }
}
