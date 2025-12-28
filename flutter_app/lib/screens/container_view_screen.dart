import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../models/container_model.dart' as models;
import '../models/item_model.dart';
import '../providers/language_provider.dart';
import '../providers/item_provider.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';
import 'item_details_screen.dart';

class ContainerViewScreen extends StatefulWidget {
  final models.ItemContainer container;

  const ContainerViewScreen({super.key, required this.container});

  @override
  State<ContainerViewScreen> createState() => _ContainerViewScreenState();
}

class _ContainerViewScreenState extends State<ContainerViewScreen> {
  int _currentImageIndex = 0;

  // Format text helper
  String _formatText(String text) {
    if (RegExp(r'^\d').hasMatch(text)) {
      return text.toUpperCase();
    }
    return text
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final images = ['https://via.placeholder.com/400x300?text=Container+Image']; // Placeholder

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.8),
                    AppColors.primary.withOpacity(0.6),
                  ],
                ),
              ),
            ),
          ),
        ),
        title: Text(widget.container.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              // TODO: Navigate to edit container
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Edit container - Coming soon!')),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Compact Image and Barcode Section
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image Section
                  Expanded(
                    flex: 3,
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            height: 180,
                            child: PageView.builder(
                              itemCount: images.length,
                              onPageChanged: (index) => setState(() => _currentImageIndex = index),
                              itemBuilder: (context, index) {
                                return GestureDetector(
                                  onTap: () => _showFullScreenImage(context, images),
                                  child: Container(
                                    color: Colors.grey[200],
                                    child: Image.network(
                                      images[index],
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Center(
                                        child: Icon(Icons.inventory_2, size: 60, color: Colors.grey[400]),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        // Status Badge
                        Positioned(
                          top: 8,
                          right: 8,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.statusActive.withOpacity(0.9),
                                      AppColors.statusActive.withOpacity(0.7),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                                ),
                                child: Text(
                                  widget.container.isActive ? 'ACTIVE' : 'INACTIVE',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Image Indicators
                        if (images.length > 1)
                          Positioned(
                            bottom: 8,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(images.length, (index) {
                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  width: _currentImageIndex == index ? 16 : 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: _currentImageIndex == index
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                );
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Barcode Section (Vertical)
                  Expanded(
                    flex: 2,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          height: 180,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withOpacity(0.7),
                                Colors.white.withOpacity(0.3),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Vertical text beside barcode
                              RotatedBox(
                                quarterTurns: 3,
                                child: Text(
                                  widget.container.id.length > 8 
                                      ? widget.container.id.substring(widget.container.id.length - 8)
                                      : widget.container.id,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              // Vertical barcode
                              Flexible(
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: BarcodeWidget(
                                    barcode: Barcode.code128(),
                                    data: widget.container.id,
                                    width: 130,
                                    height: 45,
                                    drawText: false,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Compact Info Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withOpacity(0.7),
                          Colors.white.withOpacity(0.3),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Container Name
                        Text(
                          widget.container.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Stats Row (Compact)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildCompactStatChip('Occupied', widget.container.occupiedSlots.toString(), AppColors.slotOccupied),
                            _buildCompactStatChip('Available', widget.container.availableSlots.toString(), AppColors.slotEmpty),
                            _buildCompactStatChip('Reserved', widget.container.reservedSlots.toString(), AppColors.slotReserved),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Details (Compact)
                        _buildCompactDetailRow(Icons.category_outlined, 'Type', _formatText(widget.container.type)),
                        _buildCompactDetailRow(Icons.grid_3x3, 'Capacity', '${widget.container.capacity} slots'),
                        _buildCompactDetailRow(Icons.scale_outlined, 'Weight', _formatText(widget.container.weightCategory)),
                        _buildCompactDetailRow(Icons.view_module_outlined, 'Layout', _formatText(widget.container.layoutType)),
                        
                        // Allowed Item Types (Compact)
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_circle_outline, color: AppColors.primary, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Allowed Items',
                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: widget.container.allowedItemTypes.map((type) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                                        ),
                                        child: Text(
                                          _formatText(type),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Slots Section (Compact)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Slots Layout',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      // Compact Legend
                      Row(
                        children: [
                          _buildCompactLegendItem('Empty', AppColors.slotEmpty),
                          const SizedBox(width: 8),
                          _buildCompactLegendItem('Occupied', AppColors.slotOccupied),
                          const SizedBox(width: 8),
                          _buildCompactLegendItem('Reserved', AppColors.slotReserved),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildSlotsGrid(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactStatChip(String label, String value, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildCompactDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  value,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color.withOpacity(0.5), width: 1),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  Widget _buildSlotsGrid() {
    final columns = widget.container.layoutType == 'linear' ? 5 : 6;
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemCount: widget.container.slots.length,
      itemBuilder: (context, index) {
        final slot = widget.container.slots[index];
        return _buildSlotItem(slot);
      },
    );
  }

  Widget _buildSlotItem(models.ContainerSlot slot) {
    Color slotColor;
    IconData? icon;
    
    if (slot.isReserved) {
      slotColor = AppColors.slotReserved;
      icon = Icons.lock;
    } else if (slot.isOccupied) {
      slotColor = AppColors.slotOccupied;
      icon = Icons.inventory;
    } else {
      slotColor = AppColors.slotEmpty;
      icon = null;
    }

    return GestureDetector(
      onTap: slot.isOccupied
          ? () async {
              // Fetch item details and navigate
              try {
                // Extract item ID (handle both string and object cases)
                String? itemId;
                
                print('DEBUG: slot.itemId type: ${slot.itemId.runtimeType}');
                print('DEBUG: slot.itemId value: ${slot.itemId}');
                
                if (slot.itemId == null) {
                  throw Exception('Item ID is null');
                }
                
                // Handle different types - cast to dynamic to avoid type issues
                final dynamic rawItemId = slot.itemId;
                
                if (rawItemId is String) {
                  // Check if it's a stringified object (starts with '{')
                  if (rawItemId.startsWith('{')) {
                    print('DEBUG: itemId is a stringified object, parsing...');
                    // Extract _id or id from the string
                    // Format: {_id: 6950c8e68e491143101cd9f5, barcode: ..., id: 6950c8e68e491143101cd9f5}
                    final idMatch = RegExp(r'_id:\s*([a-f0-9]+)').firstMatch(rawItemId);
                    if (idMatch != null) {
                      itemId = idMatch.group(1);
                      print('DEBUG: Extracted ID from stringified object: $itemId');
                    } else {
                      // Try to extract 'id' field
                      final idMatch2 = RegExp(r'id:\s*([a-f0-9]+)').firstMatch(rawItemId);
                      if (idMatch2 != null) {
                        itemId = idMatch2.group(1);
                        print('DEBUG: Extracted ID from id field: $itemId');
                      }
                    }
                  } else {
                    itemId = rawItemId;
                    print('DEBUG: itemId is plain String: $itemId');
                  }
                } else if (rawItemId is Map) {
                  // Try to extract ID from Map
                  final Map itemMap = rawItemId as Map;
                  print('DEBUG: itemId is Map with keys: ${itemMap.keys}');
                  
                  // Try different ID field names
                  if (itemMap.containsKey('_id')) {
                    final idValue = itemMap['_id'];
                    if (idValue is String) {
                      itemId = idValue;
                    } else if (idValue is Map && idValue.containsKey('\$oid')) {
                      itemId = idValue['\$oid'].toString();
                    } else {
                      itemId = idValue.toString();
                    }
                  } else if (itemMap.containsKey('id')) {
                    itemId = itemMap['id'].toString();
                  }
                  
                  print('DEBUG: Extracted itemId from Map: $itemId');
                  
                  // If we have the full item data, use it directly
                  if (itemId != null && itemMap.containsKey('barcode') && itemMap.containsKey('name')) {
                    print('DEBUG: Using full item data from slot');
                    final item = Item.fromJson(Map<String, dynamic>.from(itemMap));
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ItemDetailsScreen(item: item),
                      ),
                    );
                    return;
                  }
                } else {
                  itemId = rawItemId.toString();
                  print('DEBUG: itemId converted to string: $itemId');
                }
                
                if (itemId == null || itemId.isEmpty || itemId == 'null') {
                  throw Exception('Could not extract valid item ID');
                }
                
                print('DEBUG: Fetching item with ID: $itemId');
                
                final apiService = ApiService();
                final response = await apiService.getItem(itemId);
                
                print('DEBUG: API response: ${response['success']}');
                
                if (mounted && response['success'] == true) {
                  final itemData = response['data']['item'];
                  final item = Item.fromJson(itemData);
                  
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ItemDetailsScreen(item: item),
                    ),
                  );
                } else {
                  throw Exception(response['message'] ?? 'Failed to fetch item');
                }
              } catch (e) {
                print('DEBUG: Error in slot tap: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${e.toString()}'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
            }
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  slotColor.withOpacity(0.8),
                  slotColor.withOpacity(0.6),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: slot.isOccupied ? Colors.white.withOpacity(0.4) : slotColor.withOpacity(0.3),
                width: 2,
              ),
              boxShadow: slot.isOccupied
                  ? [
                      BoxShadow(
                        color: slotColor.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null)
                    Icon(
                      icon,
                      color: Colors.white,
                      size: 20,
                    ),
                  if (icon != null) const SizedBox(height: 2),
                  Text(
                    slot.slotNumber.toString(),
                    style: TextStyle(
                      color: slot.isEmpty ? Colors.black54 : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, List<String> images) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            PageView.builder(
              itemCount: images.length,
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  child: Center(
                    child: Image.network(
                      images[index],
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.inventory_2,
                        size: 100,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 40,
              right: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
