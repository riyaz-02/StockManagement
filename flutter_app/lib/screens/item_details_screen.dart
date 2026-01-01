import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../models/item_model.dart';
import '../providers/language_provider.dart';
import '../utils/app_colors.dart';
import '../utils/app_constants.dart';
import 'create_booking_screen.dart';
import 'send_to_repair_screen.dart';

import '../services/api_service.dart';

class ItemDetailsScreen extends StatefulWidget {
  final Item item;

  const ItemDetailsScreen({super.key, required this.item});

  @override
  State<ItemDetailsScreen> createState() => _ItemDetailsScreenState();
}

class _ItemDetailsScreenState extends State<ItemDetailsScreen> {
  int _currentImageIndex = 0;
  final PageController _pageController = PageController();
  late Item _item;
  final ApiService _apiService = ApiService();
  
  Map<String, List<dynamic>> _interactions = {
    'wishlistedBy': [],
    'bookedBy': []
  };
  bool _isLoadingInteractions = true;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _refreshData();
  }

  Future<void> _refreshData() async {
    await Future.wait([
      _fetchItemDetails(),
      _fetchInteractions(),
    ]);
  }

  Future<void> _fetchItemDetails() async {
    try {
      final response = await _apiService.getItem(widget.item.id);
      if (response['success'] == true) {
        setState(() {
          _item = Item.fromJson(response['data']['item']);
        });
      }
    } catch (e) {
      print('Error fetching item details: $e');
    }
  }

  Future<void> _fetchInteractions() async {
    try {
      final response = await _apiService.getItemInteractions(widget.item.id);
      if (response['success'] == true) {
        setState(() {
          _interactions = {
            'wishlistedBy': List.from(response['data']['wishlistedBy']),
            'bookedBy': List.from(response['data']['bookedBy']),
          };
          _isLoadingInteractions = false;
        });
      }
    } catch (e) {
      print('Error fetching interactions: $e');
      setState(() => _isLoadingInteractions = false);
    }
  }

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
        title: Text(_item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              // Navigate to edit screen
              final shouldRefresh = await Navigator.pushNamed(
                context,
                '/add_item',
                arguments: _item,
              );
              
              if (shouldRefresh == true && mounted) {
                Navigator.pop(context, true);
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Image Carousel + Barcode Row
            // Image Carousel + Barcode Row
            SizedBox(
              height: 160,
              child: Row(
                children: [
                   // Image Carousel Section (70%)
                   Expanded(
                    flex: 6,
                    child: Stack(
                      children: [
                        // Image PageView for multiple images
                        GestureDetector(
                          onTap: () {
                            if (_item.images.isNotEmpty) {
                              _showFullScreenImage(context, _item.images);
                            }
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.primary.withOpacity(0.1), Colors.grey[50]!],
                              ),
                            ),
                            child: _item.images.isNotEmpty
                                ? Stack(
                                  children: [
                                    PageView.builder(
                                      controller: _pageController,
                                      onPageChanged: (index) {
                                        setState(() {
                                          _currentImageIndex = index;
                                        });
                                      },
                                      itemCount: _item.images.length,
                                      itemBuilder: (context, index) {
                                        String path = _item.images[index];
                                        String imageUrl;
                                        if (path.startsWith('http')) {
                                          imageUrl = path;
                                        } else {
                                          imageUrl = '${AppConstants.baseUrl}/${path.replaceAll('\\', '/')}';
                                        }

                                        return Center(
                                          child: Image.network(
                                            imageUrl,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
                                          ),
                                        );
                                      },
                                    ),
                                    // Arrows for Web/Desktop
                                    if (_item.images.length > 1) ...[
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: IconButton(
                                          icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black54),
                                          onPressed: () {
                                            _pageController.previousPage(
                                              duration: const Duration(milliseconds: 300),
                                              curve: Curves.easeInOut,
                                            );
                                          },
                                        ),
                                      ),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: IconButton(
                                          icon: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black54),
                                          onPressed: () {
                                            _pageController.nextPage(
                                              duration: const Duration(milliseconds: 300),
                                              curve: Curves.easeInOut,
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                                )
                                : _buildImagePlaceholder(),
                          ),
                        ),
                        // Status Badge Overlay
                        Positioned(
                          top: 12,
                          left: 12,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(_item.status).withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(12),
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
                                    Icon(_getStatusIcon(_item.status), color: Colors.white, size: 12),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatText(_item.status),
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Weight Badge
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                            ),
                            child: Text(
                              '${_item.netWeight.toStringAsFixed(3)}g',
                              style: const TextStyle(
                                color: Colors.white, 
                                fontWeight: FontWeight.bold, 
                                fontSize: 11
                              ),
                            ),
                          ),
                        ),

                        // Dots
                        if (_item.images.length > 1)
                          Positioned(
                            bottom: 8,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                _item.images.length,
                                (index) => AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  width: _currentImageIndex == index ? 12 : 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(3),
                                    color: _currentImageIndex == index ? AppColors.primary : Colors.white.withOpacity(0.7),
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
                  // Barcode Section (30%)
                  Expanded(
                    flex: 4,
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                      child: Center(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: BarcodeWidget(
                            barcode: Barcode.code128(),
                            data: _item.barcode,
                            width: 140,
                            height: 60,
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
                                  _formatText(widget.item.itemType),
                                  Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildCompactBox(
                                  Icons.diamond_outlined,
                                  'Metal',
                                  _formatText(widget.item.metalType),
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
                                  widget.item.purity,
                                  Colors.green,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildCompactBox(
                                  Icons.scale_outlined,
                                  'Weight',
                                  '${widget.item.netWeight.toStringAsFixed(3)}g',
                                  Colors.purple,
                                ),
                              ),
                            ],
                          ),
                          
                          // Row 3: Weight Category & HUID
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              // Weight Category
                              Expanded(
                                child: _buildCompactBox(
                                  Icons.fitness_center, 
                                  'Weight Category', 
                                  widget.item.weightCategory.isNotEmpty ? widget.item.weightCategory : 'N/A', 
                                  Colors.teal
                                ),
                              ),
                              const SizedBox(width: 8),
                              
                              // HUID / Hallmark Status
                              Expanded(
                                child: _buildCompactBox(
                                  Icons.fingerprint, 
                                  'Hallmark', 
                                  widget.item.huid.isNotEmpty ? widget.item.huid : 'Non-Hallmarked', 
                                  widget.item.huid.isNotEmpty ? Colors.pink : Colors.grey
                                ),
                              ),
                            ],
                          ),

                          // Row 4: Location (Container)
                          if (widget.item.containerId != null) ...[
                             const SizedBox(height: 8),
                             SizedBox(
                               width: double.infinity,
                               child: _buildInfoChip(
                                  Icons.inventory_2_outlined, 
                                  'Location', 
                                  widget.item.containerName != null 
                                      ? '${widget.item.containerName}${widget.item.containerCode != null ? " - ${widget.item.containerCode}" : ""} - Slot ${widget.item.slotNumber}' 
                                      : 'Slot ${widget.item.slotNumber}',
                                ),
                             ),
                          ],
                          
                          // Description
                          if (widget.item.description.isNotEmpty) ...[
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
                                        Text(widget.item.description, style: TextStyle(fontSize: 13, color: Colors.grey[800])),
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
                  if (_item.isActive || _item.isBooked)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (_item.isActive)
                          _buildIconButton(
                            Icons.bookmark_add_outlined,
                            'Book',
                            AppColors.primary,
                            () => _showBookingBottomSheet(),
                          ),
                        _buildIconButton(
                          Icons.favorite_border,
                          'Wishlist',
                          Colors.pink,
                          () => _showWishlistBottomSheet(),
                        ),
                        _buildIconButton(
                          Icons.sell_outlined,
                          'Sell',
                          AppColors.success,
                          () => _showSellBottomSheet(),
                        ),
                        _buildIconButton(
                          Icons.build_outlined,
                          'Repair',
                          Colors.orange,
                          () => _showRepairBottomSheet(),
                        ),
                        _buildIconButton(
                          Icons.delete_outline,
                          'Delete',
                          Colors.red,
                          () => _showDeleteConfirmation(context),
                        ),
                      ],
                    ),
                  
                  const SizedBox(height: 16),
                  _buildCustomerInteractions(),
                  const SizedBox(height: 12),
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

  // Sell Bottom Sheet
  void _showSellBottomSheet() {
    final nameController = TextEditingController();
    final mobileController = TextEditingController();
    final addressController = TextEditingController();
    final amountController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
               Text('Sell Item', style: Theme.of(context).textTheme.headlineSmall),
               const SizedBox(height: 16),
               TextField(controller: mobileController, decoration: const InputDecoration(labelText: 'Mobile Number', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone))),
               const SizedBox(height: 12),
               TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Customer Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
               const SizedBox(height: 12),
               TextField(controller: addressController, decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder(), prefixIcon: Icon(Icons.home))),
                const SizedBox(height: 12),
               TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sale Amount', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money))),
               const SizedBox(height: 20),
               ElevatedButton(
                 style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, padding: const EdgeInsets.symmetric(vertical: 14)),
                 onPressed: () async {
                   if (mobileController.text.isEmpty || nameController.text.isEmpty) {
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and Mobile are required')));
                     return;
                   }
                   try {
                     final data = {
                       'mobile': mobileController.text,
                       'customerName': nameController.text,
                       'address': addressController.text,
                       'amount': double.tryParse(amountController.text),
                     };
                     
                     final response = await _apiService.sellItem(_item.id, data);
                     
                     if (response['success'] == true) {
                       Navigator.pop(context);
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item marked as Sold')));
                       Navigator.pop(context, true); // Go back to list
                     } else {
                       throw response['message'] ?? 'Failed';
                     }
                   } catch (e) {
                     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                   }
                 },
                 child: const Text('Confirm Sale', style: TextStyle(fontSize: 16)),
               ),
               const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // Repair Bottom Sheet
  void _showRepairBottomSheet() {
    final vendorController = TextEditingController();
    final typeController = TextEditingController();
    final remarksController = TextEditingController();
    DateTime? expectedDate = DateTime.now().add(const Duration(days: 7));
    bool slotReserved = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                 Text('Send to Repair', style: Theme.of(context).textTheme.headlineSmall),
                 const SizedBox(height: 16),
                 TextField(controller: vendorController, decoration: const InputDecoration(labelText: 'Repair Center / Vendor', border: OutlineInputBorder(), prefixIcon: Icon(Icons.store))),
                 const SizedBox(height: 12),
                 TextField(controller: typeController, decoration: const InputDecoration(labelText: 'Repair Type (e.g. Polish, Stone Fix)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.build))),
                 const SizedBox(height: 12),
                 InkWell(
                   onTap: () async {
                     final date = await showDatePicker(context: context, initialDate: expectedDate ?? DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                     if (date != null) setSheetState(() => expectedDate = date);
                   },
                   child: InputDecorator(
                     decoration: const InputDecoration(labelText: 'Expected Return Date', border: OutlineInputBorder(), prefixIcon: Icon(Icons.calendar_today)),
                     child: Text(expectedDate != null ? expectedDate!.toIso8601String().split('T')[0] : 'Select Date'),
                   ),
                 ),
                 const SizedBox(height: 12),
                 TextField(controller: remarksController, decoration: const InputDecoration(labelText: 'Remarks', border: OutlineInputBorder(), prefixIcon: Icon(Icons.note))),
                 const SizedBox(height: 12),
                 SwitchListTile(
                   title: const Text('Reserve Slot?'),
                   value: slotReserved,
                   onChanged: (val) => setSheetState(() => slotReserved = val),
                 ),
                 const SizedBox(height: 20),
                 ElevatedButton(
                   style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, padding: const EdgeInsets.symmetric(vertical: 14)),
                   onPressed: () async {
                     if (vendorController.text.isEmpty || typeController.text.isEmpty) {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vendor and Type are required')));
                       return;
                     }
                     try {
                       final data = {
                         'itemId': _item.id,
                         'sentTo': vendorController.text,
                         'repairType': typeController.text,
                         'expectedReturnDate': expectedDate?.toIso8601String(),
                         'remarks': remarksController.text,
                         'slotReserved': slotReserved,
                       };
                       
                       final response = await _apiService.sendToRepair(data);
                       
                       if (response['success'] == true) {
                         Navigator.pop(context); // Close sheet
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sent to Repair')));
                         Navigator.pop(context, true); // Go back
                       } else {
                         throw response['message'] ?? 'Failed';
                       }
                     } catch (e) {
                       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                     }
                   },
                   child: const Text('Confirm Repair', style: TextStyle(fontSize: 16)),
                 ),
                 const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Item?'),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await _apiService.deleteItem(_item.id);
                Navigator.pop(context); // Close dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Item moved to Recycle Bin')),
                );
                Navigator.pop(context, true); // Go back
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Wishlist Bottom Sheet
  void _showWishlistBottomSheet() {
    final nameController = TextEditingController();
    final mobileController = TextEditingController();
    final addressController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
             Text('Add to Wishlist', style: Theme.of(context).textTheme.headlineSmall),
             const SizedBox(height: 16),
             TextField(controller: mobileController, decoration: const InputDecoration(labelText: 'Mobile Number', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone))),
             const SizedBox(height: 12),
             TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Customer Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
             const SizedBox(height: 12),
             TextField(controller: addressController, decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder(), prefixIcon: Icon(Icons.home))),
             const SizedBox(height: 20),
             ElevatedButton(
               style: ElevatedButton.styleFrom(backgroundColor: Colors.pink, padding: const EdgeInsets.symmetric(vertical: 14)),
               onPressed: () async {
                 if (mobileController.text.isEmpty) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mobile number is required')));
                   return;
                 }
                 try {
                   final data = {
                     'itemId': widget.item.id,
                     'mobile': mobileController.text,
                     'name': nameController.text,
                     'address': addressController.text,
                   };
                   await _apiService.addToWishlist(data);
                   Navigator.pop(context);
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to wishlist')));
                   _fetchInteractions();
                 } catch (e) {
                   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                 }
               },
               child: const Text('Add to Wishlist', style: TextStyle(fontSize: 16)),
             ),
             const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // Booking Bottom Sheet
  void _showBookingBottomSheet({Map<String, dynamic>? initialData, String? bookingId, bool viewOnly = false}) {
    final nameController = TextEditingController(text: initialData?['name'] ?? initialData?['customerName']);
    final mobileController = TextEditingController(text: initialData?['mobile']);
    final addressController = TextEditingController(text: initialData?['address']);
    final advanceController = TextEditingController(text: initialData?['advance']?.toString() ?? initialData?['advanceAmount']?.toString());
    final remarksController = TextEditingController(text: initialData?['remarks']);
    
    DateTime? selectedDate = initialData?['expiryDate'] != null ? DateTime.tryParse(initialData!['expiryDate']) : null;
    
    final isEditing = bookingId != null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                 Text(viewOnly ? 'Booking Details' : (isEditing ? 'Update Booking' : 'Book Item'), style: Theme.of(context).textTheme.headlineSmall),
                 const SizedBox(height: 16),
                 TextField(enabled: !viewOnly, controller: mobileController, decoration: const InputDecoration(labelText: 'Mobile Number', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone))),
                 const SizedBox(height: 12),
                 TextField(enabled: !viewOnly, controller: nameController, decoration: const InputDecoration(labelText: 'Customer Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
                 const SizedBox(height: 12),
                 TextField(enabled: !viewOnly, controller: addressController, decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder(), prefixIcon: Icon(Icons.home))),
                 const SizedBox(height: 12),
                 // Date Picker
                 InkWell(
                   onTap: viewOnly ? null : () async {
                     final date = await showDatePicker(context: context, initialDate: selectedDate ?? DateTime.now().add(const Duration(days: 7)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                     if (date != null) setSheetState(() => selectedDate = date);
                   },
                   child: InputDecorator(
                     decoration: const InputDecoration(labelText: 'Delivery Date', border: OutlineInputBorder(), prefixIcon: Icon(Icons.calendar_today)),
                     child: Text(selectedDate != null ? selectedDate!.toIso8601String().split('T')[0] : 'Select Date'),
                   ),
                 ),
                 const SizedBox(height: 12),
                 TextField(enabled: !viewOnly, controller: advanceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Advance Amount', border: OutlineInputBorder(), prefixIcon: Icon(Icons.money))),
                 const SizedBox(height: 12),
                 TextField(enabled: !viewOnly, controller: remarksController, decoration: const InputDecoration(labelText: 'Remarks', border: OutlineInputBorder(), prefixIcon: Icon(Icons.note))),
                 const SizedBox(height: 20),
                 if (!viewOnly)
                   ElevatedButton(
                     style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                     onPressed: () async {
                       if (mobileController.text.isEmpty || nameController.text.isEmpty) {
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and Mobile are required')));
                         return;
                       }
                       try {
                         final data = {
                           'itemId': _item.id,
                           'mobile': mobileController.text,
                           'customerName': nameController.text,
                           'address': addressController.text,
                           'expiryDate': selectedDate?.toIso8601String(),
                           'advanceAmount': double.tryParse(advanceController.text),
                           'remarks': remarksController.text,
                         };
                         
                         Map<String, dynamic> response;
                         if (isEditing) {
                           response = await _apiService.updateBooking(bookingId, data);
                         } else {
                           response = await _apiService.createBooking(data);
                         }
                         
                         if(response['success'] == true) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEditing ? 'Booking Updated' : 'Booking Created')));
                              _refreshData(); // Refresh all data
                          } else {
                              throw response['message'] ?? 'Failed to processed';
                          }
                       } catch (e) {
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                       }
                     },
                     child: Text(isEditing ? 'Update Booking' : 'Confirm Booking', style: const TextStyle(fontSize: 16)),
                   ),
                 const SizedBox(height: 20),
              ],
            ),
          ),
        ),
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
                String path = images[index];
                String imageUrl;
                if (path.startsWith('http')) {
                  imageUrl = path;
                } else {
                  imageUrl = '${AppConstants.baseUrl}/${path.replaceAll('\\', '/')}';
                }

                return InteractiveViewer(
                  child: Center(
                    child: Image.network(
                      imageUrl,
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

  Widget _buildCustomerInteractions() {
    if (_isLoadingInteractions) {
      return const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(strokeWidth: 2)));
    }
    
    final wishlisted = _interactions['wishlistedBy'] ?? [];
    final booked = _interactions['bookedBy'] ?? [];

    if (wishlisted.isEmpty && booked.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0.5,
        child: ExpansionTile(
          shape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          leading: const Icon(Icons.people_alt_outlined, color: AppColors.primary, size: 20),
          title: const Text('Customer Activity', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          children: [
            if (booked.isNotEmpty) ...[
               const Padding(padding: EdgeInsets.only(left: 16, top: 4, bottom: 4), child: Align(alignment: Alignment.centerLeft, child: Text("Bookings", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 12)))),
               ...booked.map((b) => ListTile(
                 contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                 dense: true,
                 leading: const Icon(Icons.bookmark, size: 18, color: AppColors.primary),
                 title: Text(b['name'] ?? 'Unknown', style: const TextStyle(fontSize: 13)),
                 subtitle: Text("${b['mobile']}\nStatus: ${b['status'] ?? 'active'}", style: const TextStyle(fontSize: 11)),
                 isThreeLine: true,
                 trailing: Row(
                   mainAxisSize: MainAxisSize.min,
                   children: [
                     Text(b['bookingDate']?.toString().split('T')[0] ?? '', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                     PopupMenuButton<String>(
                       padding: EdgeInsets.zero,
                       icon: const Icon(Icons.more_vert, size: 18),
                       onSelected: (value) {
                         if (value == 'cancel') _cancelBooking(b['id']);
                         if (value == 'modify') _showBookingBottomSheet(initialData: b, bookingId: b['id']);
                         if (value == 'order_given') _updateBookingStatus(b['id'], 'manufacturing');
                         if (value == 'view') _showBookingBottomSheet(initialData: b, viewOnly: true);
                       },
                       itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                         const PopupMenuItem<String>(
                           value: 'view',
                           child: Text('View Details'),
                         ),
                         const PopupMenuItem<String>(
                           value: 'order_given',
                           child: Text('Manufacturing'),
                         ),
                         const PopupMenuItem<String>(
                           value: 'modify',
                           child: Text('Modify'),
                         ),
                         const PopupMenuItem<String>(
                           value: 'cancel',
                           child: Text('Cancel Booking', style: TextStyle(color: Colors.red)),
                         ),
                       ],
                     ),
                   ],
                 ),
               )),
            ],
             if (wishlisted.isNotEmpty) ...[
               const Padding(padding: EdgeInsets.only(left: 16, top: 8, bottom: 4), child: Align(alignment: Alignment.centerLeft, child: Text("Wishlisted By", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.pink, fontSize: 12)))),
               ...wishlisted.map((w) => ListTile(
                 contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                 dense: true,
                 leading: const Icon(Icons.favorite, size: 18, color: Colors.pink),
                 title: Text(w['name'] ?? 'Unknown', style: const TextStyle(fontSize: 13)),
                 subtitle: Text(w['mobile'] ?? '', style: const TextStyle(fontSize: 11)),
                 trailing: Row(
                   mainAxisSize: MainAxisSize.min,
                   children: [
                     Text(w['date']?.toString().split('T')[0] ?? '', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                     const SizedBox(width: 8),
                     InkWell(
                       onTap: () => _removeFromWishlist(w['mobile']),
                       child: const Padding(
                         padding: EdgeInsets.all(4.0),
                         child: Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                       ),
                     ),
                   ],
                 ),
               )),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _updateBookingStatus(String id, String status) async {
    try {
      await _apiService.updateBooking(id, {'status': status});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status Updated')));
      _refreshData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _removeFromWishlist(String mobile) async {
    try {
      await _apiService.removeFromWishlist(mobile, _item.id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed from wishlist')));
      _refreshData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _cancelBooking(String bookingId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Booking?'),
        content: const Text('Are you sure you want to cancel?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _apiService.cancelBooking(bookingId);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking Cancelled')));
      _refreshData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
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
