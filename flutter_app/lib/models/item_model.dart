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
  final String huid;
  final List<String> images;
  final String status;
  final String? containerName; 
  final String? containerCode; // Add containerCode
  final String? containerId;
  final int? slotNumber;
  final int numberOfPieces;
  final bool slotReserved;
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
    this.huid = '',
    this.images = const [],
    this.status = 'active',
    this.containerId,
    this.containerName,
    this.containerCode, // Add to constructor
    this.slotNumber,
    this.numberOfPieces = 1,
    this.slotReserved = false,
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
      huid: json['huid'] ?? '',
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
          : null, // Parse qrCode
      slotNumber: json['slotNumber'],
      numberOfPieces: json['numberOfPieces'] ?? 1,
      slotReserved: json['slotReserved'] ?? false,
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
      'huid': huid,
      'images': images,
      'status': status,
      'containerId': containerId,
      'slotNumber': slotNumber,
      'numberOfPieces': numberOfPieces,
      'slotReserved': slotReserved,
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
    String? huid,
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
      huid: huid ?? this.huid,
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
