import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../models/item_model.dart';
import '../providers/language_provider.dart';
import '../utils/app_colors.dart';
import 'create_booking_screen.dart';
import 'send_to_repair_screen.dart';

class ItemDetailsScreen extends StatelessWidget {
  final Item item;

  const ItemDetailsScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);

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
        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () {
              // Navigate to edit screen
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Image Carousel + Barcode Row
            SizedBox(
              height: 160,
              child: Row(
                children: [
                  // Image Carousel Section (70%)
                  Expanded(
                    flex: 7,
                    child: Stack(
                      children: [
                        // Image PageView for multiple images
                        GestureDetector(
                          onTap: () {
                            if (item.images.isNotEmpty) {
                              _showFullScreenImage(context, item.images);
                            }
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.primary.withOpacity(0.1), Colors.grey[50]!],
                              ),
                            ),
                            child: item.images.isNotEmpty
                                ? PageView.builder(
                                    itemCount: item.images.length,
                                    itemBuilder: (context, index) {
                                      return Center(
                                        child: Image.network(
                                          item.images[index],
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
                                        ),
                                      );
                                    },
                                  )
                                : _buildImagePlaceholder(),
                          ),
                        ),
                        // Status Badge Overlay with Glassmorphism
                        Positioned(
                          top: 12,
                          left: 12,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(item.status).withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.2),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(_getStatusIcon(item.status), color: Colors.white, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatText(item.status),
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Image indicator dots if multiple images
                        if (item.images.length > 1)
                          Positioned(
                            bottom: 8,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                item.images.length,
                                (index) => Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withOpacity(0.7),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 2,
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
                  // Barcode Section (30%) - Vertical, no label
                  Expanded(
                    flex: 3,
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                      child: Center(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: BarcodeWidget(
                            barcode: Barcode.code128(),
                            data: item.barcode,
                            width: 120,
                            height: 80,
                            drawText: true,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // Main Info Card with Glassmorphism
                  _buildGlassCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        children: [
                          // Row 1: Type & Metal
                          Row(
                            children: [
                              Expanded(
                                child: _buildCompactBox(
                                  Icons.category_outlined,
                                  'Type',
                                  _formatText(item.itemType),
                                  Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildCompactBox(
                                  Icons.diamond_outlined,
                                  'Metal',
                                  _formatText(item.metalType),
                                  Colors.amber,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          
                          // Row 2: Purity & Weight
                          Row(
                            children: [
                              Expanded(
                                child: _buildCompactBox(
                                  Icons.verified_outlined,
                                  'Purity',
                                  item.purity,
                                  Colors.green,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildCompactBox(
                                  Icons.scale_outlined,
                                  'Weight',
                                  '${item.netWeight}g',
                                  Colors.purple,
                                ),
                              ),
                            ],
                          ),
                          
                          // HUID & Container
                          if (item.huid.isNotEmpty || item.containerId != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (item.huid.isNotEmpty)
                                  Expanded(
                                    child: _buildInfoChip(Icons.fingerprint, 'HUID', item.huid),
                                  ),
                                if (item.huid.isNotEmpty && item.containerId != null)
                                  const SizedBox(width: 8),
                                if (item.containerId != null)
                                  Expanded(
                                    child: _buildInfoChip(Icons.inventory_2_outlined, 'Location', 'Slot ${item.slotNumber}'),
                                  ),
                              ],
                            ),
                          ],
                          
                          // Description
                          if (item.description.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.description_outlined, size: 16, color: AppColors.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Description',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[600]),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(item.description, style: TextStyle(fontSize: 13, color: Colors.grey[800])),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          ],
                        ),
                      ),
                  const SizedBox(height: 12),

                  // Icon-only Action Buttons
                  if (item.isActive || item.isBooked)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (item.isActive)
                          _buildIconButton(
                            Icons.bookmark_add_outlined,
                            'Book',
                            AppColors.primary,
                            () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreateBookingScreen(item: item))),
                          ),
                        _buildIconButton(
                          Icons.favorite_border,
                          'Wishlist',
                          Colors.pink,
                          () {
                            // TODO: Add to wishlist
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Added to wishlist')),
                            );
                          },
                        ),
                        _buildIconButton(
                          Icons.sell_outlined,
                          'Sell',
                          AppColors.success,
                          () => _showSellConfirmation(context),
                        ),
                        _buildIconButton(
                          Icons.build_outlined,
                          'Repair',
                          Colors.orange,
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => SendToRepairScreen(item: item))),
                        ),
                        _buildIconButton(
                          Icons.delete_outline,
                          'Delete',
                          Colors.red,
                          () => _showDeleteConfirmation(context),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.grey[300]!, Colors.grey[200]!]),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, size: 60, color: Colors.grey[400]),
          const SizedBox(height: 6),
          Text('No Image', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildCompactBox(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey[800])),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[800])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, String label, Color color, VoidCallback onPressed) {
    return Tooltip(
      message: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withOpacity(0.15),
                      color.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(icon, color: color, size: 24),
                  onPressed: onPressed,
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String _formatText(String text) {
    return text
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'active': return Icons.check_circle;
      case 'booked': return Icons.bookmark;
      case 'repair':
      case 'in_repair': return Icons.build;
      case 'sold': return Icons.sell;
      default: return Icons.inventory;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active': return AppColors.statusActive;
      case 'booked': return AppColors.statusBooked;
      case 'repair':
      case 'in_repair': return AppColors.statusRepair;
      case 'sold': return AppColors.statusSold;
      default: return Colors.grey;
    }
  }

  void _showSellConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.sell, color: Colors.green),
            SizedBox(width: 8),
            Text('Confirm Sale'),
          ],
        ),
        content: const Text('Mark this item as sold?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Item'),
          ],
        ),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Item deleted'), backgroundColor: Colors.red),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Full Screen Image Viewer
  void _showFullScreenImage(BuildContext context, List<String> images) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            // Image PageView
            PageView.builder(
              itemCount: images.length,
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  child: Center(
                    child: Image.network(
                      images[index],
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image,
                        size: 100,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
            // Close button
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

  // Glassmorphism Helper Widget
  Widget _buildGlassCard({required Widget child, EdgeInsets? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
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
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
