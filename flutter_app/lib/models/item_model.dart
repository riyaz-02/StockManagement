class Item {
  final String id;
  final String barcode;
  final String name;
  final String description;
  final String itemType;
  final String metalType;
  final String purity;
  final double netWeight;
  final String weightCategory;
  final String weightAccuracy;
  final double? lastVerifiedWeight;
  final DateTime? lastVerifiedAt;
  final String certificationType; // 'none', 'hallmarked', 'huid'
  final String? huidNumber; // Only for HUID certified items
  final List<String> images;
  final String status;
  final String? containerName; 
  final String? containerCode;
  final String? containerId;
  final int? slotNumber;
  final int numberOfPieces;
  final bool slotReserved;
  final bool tagsPrinted;
  final DateTime? lastTagPrintedAt;
  final int tagPrintCount;
  final String? lastPrintedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  Item({
    required this.id,
    required this.barcode,
    required this.name,
    this.description = '',
    required this.itemType,
    required this.metalType,
    required this.purity,
    required this.netWeight,
    this.weightCategory = 'Light',
    this.weightAccuracy = 'exact',
    this.lastVerifiedWeight,
    this.lastVerifiedAt,
    this.certificationType = 'none',
    this.huidNumber,
    this.images = const [],
    this.status = 'active',
    this.containerId,
    this.containerName,
    this.containerCode,
    this.slotNumber,
    this.numberOfPieces = 1,
    this.slotReserved = false,
    this.tagsPrinted = false,
    this.lastTagPrintedAt,
    this.tagPrintCount = 0,
    this.lastPrintedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      id: json['_id'] ?? json['id'] ?? '',
      barcode: json['barcode'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      itemType: json['itemType'] ?? '',
      metalType: json['metalType'] ?? '',
      purity: json['purity'] ?? '',
      netWeight: (json['netWeight'] ?? 0).toDouble(),
      weightCategory: json['weightCategory'] ?? 'Light',
      weightAccuracy: json['weightAccuracy'] ?? 'exact',
      lastVerifiedWeight: json['lastVerifiedWeight']?.toDouble(),
      lastVerifiedAt: json['lastVerifiedAt'] != null
          ? DateTime.parse(json['lastVerifiedAt'])
          : null,
      certificationType: json['certificationType'] ?? 
          ((json['huid'] != null && json['huid'].toString().isNotEmpty) ? 'huid' : 'none'),
      huidNumber: json['huidNumber'] ?? json['huid'],
      images: List<String>.from(json['images'] ?? []),
      status: json['status'] ?? 'active',
      containerId: json['containerId'] is String 
          ? json['containerId'] 
          : json['containerId']?['_id'],
      containerName: json['containerId'] is Map 
          ? json['containerId']['name'] 
          : null,
      containerCode: json['containerId'] is Map 
          ? json['containerId']['qrCode'] 
          : null,
      slotNumber: json['slotNumber'],
      numberOfPieces: json['numberOfPieces'] ?? 1,
      slotReserved: json['slotReserved'] == true || json['slotReserved'] == 'true',
      tagsPrinted: json['tagsPrinted'] == true || json['tagsPrinted'] == 'true',
      lastTagPrintedAt: json['lastTagPrintedAt'] != null
          ? DateTime.parse(json['lastTagPrintedAt'])
          : null,
      tagPrintCount: json['tagPrintCount'] ?? 0,
      lastPrintedBy: json['lastPrintedBy'] is String
          ? json['lastPrintedBy']
          : json['lastPrintedBy']?['_id'],
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
      'barcode': barcode,
      'name': name,
      'description': description,
      'itemType': itemType,
      'metalType': metalType,
      'purity': purity,
      'netWeight': netWeight,
      'weightCategory': weightCategory,
      'weightAccuracy': weightAccuracy,
      'lastVerifiedWeight': lastVerifiedWeight,
      'lastVerifiedAt': lastVerifiedAt?.toIso8601String(),
      'certificationType': certificationType,
      'huidNumber': huidNumber,
      'images': images,
      'status': status,
      'containerId': containerId,
      'slotNumber': slotNumber,
      'numberOfPieces': numberOfPieces,
      'slotReserved': slotReserved,
      'tagsPrinted': tagsPrinted,
      'lastTagPrintedAt': lastTagPrintedAt?.toIso8601String(),
      'tagPrintCount': tagPrintCount,
      'lastPrintedBy': lastPrintedBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  bool get isActive => status == 'active';
  bool get isBooked => status == 'booked';
  bool get isInRepair => status == 'in_repair';
  bool get isTemporarilyRemoved => status == 'temporarily_removed';
  bool get isSold => status == 'sold';
  bool get isInStock => status == 'active' || status == 'booked';
  bool get isInTally => status == 'active' || status == 'booked';
  bool get isActionNeeded => status == 'action_needed';

  Item copyWith({
    String? id,
    String? barcode,
    String? name,
    String? description,
    String? itemType,
    String? metalType,
    String? purity,
    double? netWeight,
    String? weightCategory,
    String? certificationType,
    String? huidNumber,
    List<String>? images,
    String? status,
    String? containerId,
    int? slotNumber,
    bool? slotReserved,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Item(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      description: description ?? this.description,
      itemType: itemType ?? this.itemType,
      metalType: metalType ?? this.metalType,
      purity: purity ?? this.purity,
      netWeight: netWeight ?? this.netWeight,
      weightCategory: weightCategory ?? this.weightCategory,
      certificationType: certificationType ?? this.certificationType,
      huidNumber: huidNumber ?? this.huidNumber,
      images: images ?? this.images,
      status: status ?? this.status,
      containerId: containerId ?? this.containerId,
      slotNumber: slotNumber ?? this.slotNumber,
      slotReserved: slotReserved ?? this.slotReserved,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
