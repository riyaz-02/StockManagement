class ContainerSlot {
  final int slotNumber;
  final String? itemId;
  final bool reserved;

  ContainerSlot({
    required this.slotNumber,
    this.itemId,
    this.reserved = false,
  });

  factory ContainerSlot.fromJson(Map<String, dynamic> json) {
    // Handle MongoDB ObjectId which might be an object
    String? getItemId() {
      final idValue = json['itemId'];
      if (idValue == null) return null;
      if (idValue is String) return idValue;
      if (idValue is Map && idValue.containsKey('\$oid')) {
        return idValue['\$oid'] as String;
      }
      return idValue.toString();
    }

    return ContainerSlot(
      slotNumber: json['slotNumber'] ?? 0,
      itemId: getItemId(),
      reserved: json['reserved'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'slotNumber': slotNumber,
      'itemId': itemId,
      'reserved': reserved,
    };
  }

  bool get isEmpty => itemId == null && !reserved;
  bool get isOccupied => itemId != null;
  bool get isReserved => reserved;
}

class ItemContainer {
  final String id;
  final String name;
  final String type;
  final List<String> allowedItemTypes;
  final int capacity;
  final String weightCategory;
  final String layoutType;
  final List<ContainerSlot> slots;
  final bool isActive;
  final DateTime createdAt;

  ItemContainer({
    required this.id,
    required this.name,
    required this.type,
    required this.allowedItemTypes,
    required this.capacity,
    required this.weightCategory,
    required this.layoutType,
    required this.slots,
    this.isActive = true,
    required this.createdAt,
  });

  factory ItemContainer.fromJson(Map<String, dynamic> json) {
    // Handle MongoDB ObjectId which might be an object
    String getId() {
      final idValue = json['_id'] ?? json['id'];
      if (idValue == null) return '';
      if (idValue is String) return idValue;
      if (idValue is Map && idValue.containsKey('\$oid')) {
        return idValue['\$oid'] as String;
      }
      return idValue.toString();
    }

    return ItemContainer(
      id: getId(),
      name: json['name'] ?? '',
      type: json['type'] ?? 'custom',
      allowedItemTypes: List<String>.from(json['allowedItemTypes'] ?? []),
      capacity: json['capacity'] ?? 0,
      weightCategory: json['weightCategory'] ?? 'mixed',
      layoutType: json['layoutType'] ?? 'grid',
      slots: (json['slots'] as List?)
              ?.map((slot) => ContainerSlot.fromJson(slot))
              .toList() ??
          [],
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'name': name,
      'type': type,
      'allowedItemTypes': allowedItemTypes,
      'capacity': capacity,
      'weightCategory': weightCategory,
      'layoutType': layoutType,
      'slots': slots.map((slot) => slot.toJson()).toList(),
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  int get occupiedSlots => slots.where((s) => s.isOccupied).length;
  int get availableSlots => slots.where((s) => s.isEmpty).length;
  int get reservedSlots => slots.where((s) => s.isReserved).length;
}

