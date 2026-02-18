import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../providers/container_provider.dart';
import '../models/container_model.dart' as models;
import '../models/item_model.dart';
import '../providers/language_provider.dart';
import '../providers/item_provider.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';
import 'item_details_screen.dart';
import 'edit_container_screen.dart';
import 'add_edit_item_screen.dart';
import '../utils/app_constants.dart';

class ContainerViewScreen extends StatefulWidget {
  final models.ItemContainer container;

  const ContainerViewScreen({super.key, required this.container});

  @override
  State<ContainerViewScreen> createState() => _ContainerViewScreenState();
}

class _ContainerViewScreenState extends State<ContainerViewScreen> {
  int _currentImageIndex = 0;

  @override
  void initState() {
    super.initState();
    // Force fetch fresh container data to get updated slot information with images
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ContainerProvider>(context, listen: false).fetchContainer(widget.container.id);
    });
  }

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
  Color _getCapacityColor(double percent) {
    if (percent >= 0.9) return Colors.red;
    if (percent >= 0.7) return Colors.orange;
    return AppColors.statusActive; // Or green
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[50], // Very subtle bg
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: Colors.grey[700]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatText(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    // Use container from provider if available (updated version), otherwise widget.container
    final containerProvider = Provider.of<ContainerProvider>(context);
    final container = (containerProvider.selectedContainer != null && 
                       containerProvider.selectedContainer!.id == widget.container.id)
        ? containerProvider.selectedContainer!
        : widget.container;
        
    final List<String> images = (container.image != null && container.image!.isNotEmpty)
        ? [container.image!.startsWith('http') 
            ? container.image! 
            : '${AppConstants.baseUrl}${container.image}']
        : [];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: Text(
          container.name,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        actions: [
          if (!container.isDeleted)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditContainerScreen(container: container),
                  ),
                );
                // Refresh container data on return
                if (mounted) {
                  Provider.of<ContainerProvider>(context, listen: false).fetchContainer(widget.container.id);
                }
              },
            ),
        ],
      ),
      bottomNavigationBar: container.isDeleted 
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -5)),
                ],
              ),
              child: Row(
                children: [
                   Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.restore),
                      label: const Text('RESTORE'),
                      onPressed: () async {
                        final provider = Provider.of<ContainerProvider>(context, listen: false);
                        final success = await provider.restoreContainer(container.id);
                        if (success && mounted) {
                           Navigator.pop(context); // Go back to Recycle Bin list
                           ScaffoldMessenger.of(context).showSnackBar(
                             SnackBar(content: Text('Restored ${container.name}')),
                           );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('DELETE'),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Forever?'),
                              content: Text('Permanently delete "${container.name}"? This cannot be undone.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete')),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            final provider = Provider.of<ContainerProvider>(context, listen: false);
                            await provider.deleteContainerPermanently(container.id);
                            if (mounted) Navigator.pop(context);
                          }
                      },
                    ),
                  ),
                ],
              ),
            )
          : null,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Compact Image and Barcode Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                                      (container.isDeleted ? Colors.red : (container.isActive ? AppColors.statusActive : Colors.grey)).withOpacity(0.9),
                                      (container.isDeleted ? Colors.red : (container.isActive ? AppColors.statusActive : Colors.grey)).withOpacity(0.7),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                                ),
                                child: Text(
                                  container.isDeleted ? 'DELETED' : (container.isActive ? 'ACTIVE' : 'INACTIVE'),
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
                          height: 160,
                          padding: const EdgeInsets.all(6),
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
                                  container.qrCode?.isNotEmpty == true 
                                      ? container.qrCode!
                                      : (container.id.length > 8 
                                          ? container.id.substring(container.id.length - 8)
                                          : container.id),
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
                                    data: container.qrCode?.isNotEmpty == true
                                        ? container.qrCode!
                                        : container.id,
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

            // Deleted Notice Bar
            if (container.isDeleted)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline, color: Colors.red),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This container is in the Recycle Bin. Restore it to edit or view full details.',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),

            // Info and Stats Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey[200]!),
                ),
                color: Colors.white,
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    initiallyExpanded: true,
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Container Details',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        // Compact percentage chip in title
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getCapacityColor(container.occupiedSlots / container.capacity).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${container.occupiedSlots}/${container.capacity}  (${((container.occupiedSlots / container.capacity) * 100).toInt()}%)',
                            style: TextStyle(
                              color: _getCapacityColor(container.occupiedSlots / container.capacity),
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    childrenPadding: const EdgeInsets.all(12),
                    children: [
                       // Progress Bar
                       ClipRRect(
                         borderRadius: BorderRadius.circular(8),
                         child: LinearProgressIndicator(
                           value: container.occupiedSlots / container.capacity,
                           backgroundColor: Colors.grey[100],
                           color: _getCapacityColor(container.occupiedSlots / container.capacity),
                           minHeight: 8,
                         ),
                       ),
                       const SizedBox(height: 16),
                       // Details Grid
                       GridView.count(
                         shrinkWrap: true,
                         physics: const NeverScrollableScrollPhysics(),
                         crossAxisCount: 2,
                         childAspectRatio: 3,
                         mainAxisSpacing: 8,
                         crossAxisSpacing: 8,
                         children: [
                           _buildDetailItem(Icons.category_outlined, 'Type', container.type),
                           _buildDetailItem(Icons.scale_outlined, 'Weight', container.weightCategory),
                           _buildDetailItem(Icons.diamond_outlined, 'Metal', container.metalType.join(', ')),
                           _buildDetailItem(Icons.verified_outlined, 'Purity', container.purity.join(', ')),
                           _buildDetailItem(Icons.grid_view, 'Layout', container.layoutType),
                           _buildDetailItem(Icons.check_circle_outline, 'Allowed', container.allowedItemTypes.join(', ')),
                         ],
                       ),
                    ],
                  ),
                ),
              ),
            ),
            // Slots Section
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Slots Layout',
                    style: TextStyle(
                        fontSize: 14, 
                        fontWeight: FontWeight.bold,
                        color: Colors.black87
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Legend
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _buildLegendItem('Empty', AppColors.slotEmpty),
                      _buildLegendItem('Occupied', AppColors.slotOccupied),
                      _buildLegendItem('Reserved', AppColors.slotReserved),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey[200]!)
                    ),
                    color: Colors.white,
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _buildSlotsGrid(container)
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.grey)),
      ],
    );
  }

  Widget _buildSlotsGrid(models.ItemContainer container) {
    final columns = container.layoutType == 'linear' ? 3 : 4;
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: container.slots.length,
      itemBuilder: (context, index) {
        final slot = container.slots[index];
        return _buildSlotItem(slot, container);
      },
    );
  }

  Widget _buildSlotItem(models.ContainerSlot slot, models.ItemContainer container) {
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
      onTap: () async {
        if (slot.isOccupied) {
          // Fetch item details and navigate
          try {
            String? itemId;
            final dynamic rawItemId = slot.itemId;
            if (rawItemId == null) return;
            
            if (rawItemId is String) {
               if (rawItemId.startsWith('{')) {
                 final idMatch = RegExp(r'_id:\s*([a-f0-9]+)').firstMatch(rawItemId);
                 itemId = idMatch?.group(1);
               } else {
                 itemId = rawItemId;
               }
            } else if (rawItemId is Map) {
               if (rawItemId.containsKey('_id')) itemId = rawItemId['_id'].toString();
               else if (rawItemId.containsKey('id')) itemId = rawItemId['id'].toString();
            }

            if (itemId != null && itemId.isNotEmpty && itemId != 'null') {
                final apiService = ApiService();
                final response = await apiService.getItem(itemId);
                if (mounted && response['success'] == true) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ItemDetailsScreen(item: Item.fromJson(response['data']['item']))));
                }
            }
          } catch (e) { print(e); }
        } else {
          // Empty Slot Tap
          if (container.isLocked) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Container is LOCKED. unlock to add items.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 2),
              ),
            );
          } else {
            // Navigate to Add Item
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddEditItemScreen(
                  initialContainerId: container.id,
                  initialSlotNumber: slot.slotNumber,
                ),
              ),
            );
            // Refresh container on return
            if (mounted) {
              Provider.of<ContainerProvider>(context, listen: false).fetchContainer(container.id);
            }
          }
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background - Item photo for occupied slots
              if (slot.isOccupied && slot.itemImage != null && slot.itemImage!.isNotEmpty)
                Image.network(
                  slot.itemImage!.startsWith('http') 
                      ? slot.itemImage! 
                      : '${AppConstants.baseUrl}${slot.itemImage}',
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            slotColor.withOpacity(0.3),
                            slotColor.withOpacity(0.1),
                          ],
                        ),
                      ),
                      child: Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                              : null,
                          color: Colors.white.withOpacity(0.8),
                          strokeWidth: 2.5,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    print('Error loading image for slot ${slot.slotNumber}: $error');
                    print('Image URL: ${slot.itemImage}');
                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            slotColor.withOpacity(0.3),
                            slotColor.withOpacity(0.1),
                          ],
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.inventory_2_outlined,
                          color: Colors.white.withOpacity(0.6),
                          size: 36,
                        ),
                      ),
                    );
                  },
                )
              else
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        slotColor.withOpacity(0.3),
                        slotColor.withOpacity(0.1),
                      ],
                    ),
                  ),
                ),
              
              // Subtle overlay for occupied slots to ensure text readability
              if (slot.isOccupied && slot.itemImage != null && slot.itemImage!.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.05),
                        Colors.black.withOpacity(0.25),
                      ],
                    ),
                  ),
                ),
              
              // Border
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: slot.isOccupied 
                        ? Colors.white.withOpacity(0.4) 
                        : slotColor.withOpacity(0.4),
                    width: 2,
                  ),
                ),
              ),
              
              // Content
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top: Slot number badge
                    Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: slot.isOccupied 
                              ? Colors.white.withOpacity(0.95)
                              : Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          slot.slotNumber.toString(),
                          style: TextStyle(
                            color: slot.isOccupied ? Colors.black87 : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    
                    // Center: Icon and status for empty/reserved
                    if (!slot.isOccupied)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (icon != null)
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.9),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    icon,
                                    color: slotColor,
                                    size: 28,
                                  ),
                                ),
                              if (icon != null) const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  slot.isReserved ? 'Reserved' : 'Add Item',
                                  style: TextStyle(
                                    color: slotColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    
                    // Bottom: Weight for occupied slots
                    if (slot.isOccupied && slot.itemWeight != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          '${slot.itemWeight!.toStringAsFixed(2)}g',
                          style: const TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
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
