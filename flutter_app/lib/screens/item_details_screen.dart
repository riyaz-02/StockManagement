import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../models/item_model.dart';
import '../providers/language_provider.dart';
import '../providers/container_provider.dart';
import '../utils/app_colors.dart';
import '../utils/app_constants.dart';
import 'create_booking_screen.dart';
import 'send_to_repair_screen.dart';
import 'quick_add_item_screen.dart';
import 'container_view_screen.dart';

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
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: Text(
          _item.name,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              // Navigate to edit screen
              final shouldRefresh = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QuickAddItemScreen(item: _item),
                ),
              );
              
              if (shouldRefresh == true && mounted) {
                // Refresh item data to show updated values
                _refreshData();
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
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${_item.netWeight.toStringAsFixed(3)}g',
                                  style: const TextStyle(
                                    color: Colors.white, 
                                    fontWeight: FontWeight.bold, 
                                    fontSize: 11
                                  ),
                                ),
                                if (_item.weightAccuracy != 'exact') ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    '(${_item.weightAccuracy == 'approx' ? 'Approx' : 'Bulk'})',
                                    style: TextStyle(
                                      color: Colors.orange.shade300,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ],
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
                                  _formatText(_item.itemType),
                                  Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildCompactBox(
                                  Icons.diamond_outlined,
                                  'Metal',
                                  _formatText(_item.metalType),
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
                                  _item.purity,
                                  Colors.green,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildCompactBox(
                                  Icons.scale_outlined,
                                  'Weight',
                                  '${_item.netWeight.toStringAsFixed(3)}g${_item.weightAccuracy != 'exact' ? ' (${_item.weightAccuracy == 'approx' ? 'Approx' : 'Bulk'})' : ''}',
                                  Colors.purple,
                                ),
                              ),
                            ],
                          ),
                          
                          // Row 3: Pieces & Weight Category
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              // Number of Pieces
                              Expanded(
                                child: _buildCompactBox(
                                  Icons.numbers,
                                  'Pieces',
                                  '${_item.numberOfPieces}',
                                  Colors.orange,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Weight Category
                              Expanded(
                                child: _buildCompactBox(
                                  Icons.fitness_center, 
                                  'Weight Category', 
                                  _item.weightCategory.isNotEmpty ? _item.weightCategory : 'N/A', 
                                  Colors.teal
                                ),
                              ),
                            ],
                          ),
                          
                          // Row 4: HUID
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: _buildCompactBox(
                              Icons.verified,
                              'Certification',
                              widget.item.certificationType == 'huid' 
                                  ? 'HUID: ${widget.item.huidNumber ?? "N/A"}'
                                  : widget.item.certificationType == 'hallmarked'
                                      ? 'Hallmarked'
                                      : 'Not Certified',
                              widget.item.certificationType == 'huid' 
                                  ? Colors.pink 
                                  : widget.item.certificationType == 'hallmarked'
                                      ? Colors.amber
                                      : Colors.grey,
                            ),
                          ),

                          // Row 5: Location (Container) - Tappable
                          if (widget.item.containerId != null) ...[
                             const SizedBox(height: 8),
                             InkWell(
                               onTap: () async {
                                 // Fetch container and navigate to container details
                                 try {
                                   final containerProvider = Provider.of<ContainerProvider>(context, listen: false);
                                   await containerProvider.fetchContainer(widget.item.containerId!);
                                   
                                   if (containerProvider.selectedContainer != null && mounted) {
                                     Navigator.push(
                                       context,
                                       MaterialPageRoute(
                                         builder: (context) => ContainerViewScreen(
                                           container: containerProvider.selectedContainer!,
                                         ),
                                       ),
                                     );
                                   }
                                 } catch (e) {
                                   if (mounted) {
                                     ScaffoldMessenger.of(context).showSnackBar(
                                       SnackBar(
                                         content: Text('Error loading container: $e'),
                                         backgroundColor: Colors.red,
                                       ),
                                     );
                                   }
                                 }
                               },
                               child: Container(
                                 width: double.infinity,
                                 padding: const EdgeInsets.all(10),
                                 decoration: BoxDecoration(
                                   color: AppColors.primary.withOpacity(0.05),
                                   borderRadius: BorderRadius.circular(8),
                                   border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                                 ),
                                 child: Row(
                                   children: [
                                     Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.primary),
                                     const SizedBox(width: 8),
                                     Expanded(
                                       child: Column(
                                         crossAxisAlignment: CrossAxisAlignment.start,
                                         children: [
                                           Text(
                                             'Location',
                                             style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[600]),
                                           ),
                                           const SizedBox(height: 2),
                                           Text(
                                             widget.item.containerName != null 
                                                 ? '${widget.item.containerName}${widget.item.containerCode != null ? " - ${widget.item.containerCode}" : ""} - Slot ${widget.item.slotNumber}' 
                                                 : 'Slot ${widget.item.slotNumber}',
                                             style: TextStyle(fontSize: 13, color: Colors.grey[800], fontWeight: FontWeight.w500),
                                           ),
                                         ],
                                       ),
                                     ),
                                     Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.primary),
                                   ],
                                 ),
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
                          Icons.output_outlined,
                          'Move Out',
                          Colors.orange,
                          () => _showMoveOutBottomSheet(),
                        ),
                        _buildIconButton(
                          Icons.block,
                          'No Sell',
                          Colors.red,
                          () => _showMarkAsNoSellConfirmation(context),
                        ),
                        _buildIconButton(
                          Icons.delete_outline,
                          'Delete',
                          Colors.red.shade700,
                          () => _showDeleteConfirmation(context),
                        ),
                      ],
                    ),

                  // Mark as Active button for no_sell items
                  if (_item.status == 'no_sell')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ElevatedButton.icon(
                        onPressed: () => _showMarkAsActiveConfirmation(context),
                        icon: const Icon(Icons.check_circle),
                        label: const Text('Mark as Active'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),

                  // Restore/Permanent Delete buttons for deleted items
                  if (_item.status == 'deleted')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _showRestoreConfirmation(context),
                              icon: const Icon(Icons.restore_from_trash),
                              label: const Text('Restore'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _showPermanentDeleteConfirmation(context),
                              icon: const Icon(Icons.delete_forever),
                              label: const Text('Delete Forever'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Movement Details Box for moved-out items
                  if (['UNDER_REPAIR', 'WITH_CUSTOMER', 'WITH_AGENT'].contains(_item.status))
                    FutureBuilder(
                      future: _apiService.getItemMovements(_item.id),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        
                        if (snapshot.hasData && snapshot.data!['success'] == true) {
                          final movements = snapshot.data!['data']['movements'] as List;
                          final activeMovement = movements.firstWhere(
                            (m) => m['status'] == 'OUT',
                            orElse: () => null,
                          );
                          
                          if (activeMovement != null) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      activeMovement['movementType'] == 'REPAIR' ? Colors.orange.shade50 :
                                      activeMovement['movementType'] == 'CUSTOMER_TRIAL' ? Colors.blue.shade50 :
                                      Colors.purple.shade50,
                                      Colors.white,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: activeMovement['movementType'] == 'REPAIR' ? Colors.orange :
                                           activeMovement['movementType'] == 'CUSTOMER_TRIAL' ? Colors.blue :
                                           Colors.purple,
                                    width: 2,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            activeMovement['movementType'] == 'REPAIR' ? Icons.build :
                                            activeMovement['movementType'] == 'CUSTOMER_TRIAL' ? Icons.person :
                                            Icons.store,
                                            color: activeMovement['movementType'] == 'REPAIR' ? Colors.orange :
                                                   activeMovement['movementType'] == 'CUSTOMER_TRIAL' ? Colors.blue :
                                                   Colors.purple,
                                            size: 24,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              activeMovement['movementType'] == 'REPAIR' ? 'Under Repair/Maintenance' :
                                              activeMovement['movementType'] == 'CUSTOMER_TRIAL' ? 'With Customer (Trial)' :
                                              'With Agent/Shop',
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 24),
                                      
                                      // Movement details
                                      _buildMovementDetailRow('Out Date', activeMovement['outDate']?.toString().split('T')[0] ?? 'N/A'),
                                      
                                      // Repair-specific
                                      if (activeMovement['givenTo'] != null)
                                        _buildMovementDetailRow('Given To', activeMovement['givenTo']),
                                      if (activeMovement['repairType'] != null && activeMovement['repairType'].toString().isNotEmpty)
                                        _buildMovementDetailRow('Repair Type', activeMovement['repairType']),
                                      if (activeMovement['jobCardNumber'] != null && activeMovement['jobCardNumber'].toString().isNotEmpty)
                                        _buildMovementDetailRow('Job Card', activeMovement['jobCardNumber']),
                                      
                                      // Customer trial specific
                                      if (activeMovement['customerName'] != null)
                                        _buildMovementDetailRow('Customer', activeMovement['customerName']),
                                      if (activeMovement['customerMobile'] != null)
                                        _buildMovementDetailRow('Mobile', activeMovement['customerMobile']),
                                      if (activeMovement['idProofType'] != null && activeMovement['idProofType'].toString().isNotEmpty)
                                        _buildMovementDetailRow('ID Proof', activeMovement['idProofType']),
                                      
                                      // Agent consignment specific
                                      if (activeMovement['partyName'] != null)
                                        _buildMovementDetailRow('Party', activeMovement['partyName']),
                                      if (activeMovement['partyType'] != null)
                                        _buildMovementDetailRow('Party Type', activeMovement['partyType']),
                                      if (activeMovement['gstin'] != null && activeMovement['gstin'].toString().isNotEmpty)
                                        _buildMovementDetailRow('GSTIN', activeMovement['gstin']),
                                      if (activeMovement['challanNumber'] != null && activeMovement['challanNumber'].toString().isNotEmpty)
                                        _buildMovementDetailRow('Challan', activeMovement['challanNumber']),
                                      
                                      // Common fields
                                      if (activeMovement['expectedReturnDate'] != null)
                                        _buildMovementDetailRow('Expected Return', activeMovement['expectedReturnDate']?.toString().split('T')[0] ?? 'N/A'),
                                      if (activeMovement['remarks'] != null && activeMovement['remarks'].toString().isNotEmpty)
                                        _buildMovementDetailRow('Remarks', activeMovement['remarks'], isRemark: true),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                        }
                        
                        return const SizedBox.shrink();
                      },
                    ),

                  // Return to Stock button for moved-out items
                  if (['UNDER_REPAIR', 'WITH_CUSTOMER', 'WITH_AGENT'].contains(_item.status))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ElevatedButton.icon(
                        onPressed: () => _showReturnToStockConfirmation(context),
                        icon: const Icon(Icons.inventory),
                        label: const Text('Return'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
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
      case 'no_sell': return Icons.block;
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
      case 'no_sell': return Colors.red;
      default: return Colors.grey;
    }
  }

  // Sell Bottom Sheet
  void _showSellBottomSheet() {
    final nameController = TextEditingController();
    final mobileController = TextEditingController();
    final addressController = TextEditingController();
    final amountController = TextEditingController();
    bool isSelling = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
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
                     style: ElevatedButton.styleFrom(
                       backgroundColor: isSelling ? Colors.grey : AppColors.success,
                       padding: const EdgeInsets.symmetric(vertical: 14),
                     ),
                     onPressed: isSelling ? null : () async {
                       if (mobileController.text.isEmpty || nameController.text.isEmpty) {
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and Mobile are required')));
                         return;
                       }
                       setSheetState(() => isSelling = true);
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
                           setSheetState(() => isSelling = false);
                           throw response['message'] ?? 'Failed';
                         }
                       } catch (e) {
                         setSheetState(() => isSelling = false);
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                       }
                     },
                     child: isSelling
                         ? const SizedBox(
                             height: 20,
                             width: 20,
                             child: CircularProgressIndicator(
                               strokeWidth: 2,
                               valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                             ),
                           )
                         : const Text('Confirm Sale', style: TextStyle(fontSize: 16)),
                   ),
                   const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
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
    bool isRepairing = false;

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
                   style: ElevatedButton.styleFrom(
                     backgroundColor: isRepairing ? Colors.grey : Colors.orange,
                     padding: const EdgeInsets.symmetric(vertical: 14),
                   ),
                   onPressed: isRepairing ? null : () async {
                     if (vendorController.text.isEmpty || typeController.text.isEmpty) {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vendor and Type are required')));
                       return;
                     }
                     setSheetState(() => isRepairing = true);
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
                         setSheetState(() => isRepairing = false);
                         throw response['message'] ?? 'Failed';
                       }
                     } catch (e) {
                       setSheetState(() => isRepairing = false);
                       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                     }
                   },
                   child: isRepairing
                       ? const SizedBox(
                           height: 20,
                           width: 20,
                           child: CircularProgressIndicator(
                             strokeWidth: 2,
                             valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                           ),
                         )
                       : const Text('Confirm Repair', style: TextStyle(fontSize: 16)),
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

  // Note: Item restore functionality has been moved to the Recycle Bin screen
  // with proper container validation. Restore is no longer available from item details.
  void _showRestoreConfirmation(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please restore items from the Recycle Bin screen'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _showPermanentDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Permanent Delete?'),
          ],
        ),
        content: const Text('This action cannot be undone. The item will be permanently deleted from the database.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await _apiService.permanentDeleteItem(_item.id);
                Navigator.pop(context); // Close dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Item permanently deleted')),
                );
                Navigator.pop(context, true); // Go back to recycle bin
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );
  }

  void _showMarkAsNoSellConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.block, color: Colors.red),
            SizedBox(width: 8),
            Text('Mark as No Sell?'),
          ],
        ),
        content: const Text('This item will be marked as not available for sale. You can change it back to active later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              try {
                await _apiService.markItemAsNoSell(_item.id);
                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Item marked as no sell'), backgroundColor: Colors.green),
                  );
                  _refreshData();
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Mark as No Sell'),
          ),
        ],
      ),
    );
  }

  void _showMarkAsActiveConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Mark as Active?'),
          ],
        ),
        content: const Text('This item will be marked as active and available for sale again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              try {
                await _apiService.markItemAsActive(_item.id);
                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Item marked as active'), backgroundColor: Colors.green),
                  );
                  _refreshData();
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Mark as Active'),
          ),
        ],
      ),
    );
  }


  void _showReturnToStockConfirmation(BuildContext context) async {
    // First, get the movement record for this item
    try {
      final movementsResponse = await _apiService.getItemMovements(_item.id);
      
      if (movementsResponse['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not fetch movement records')),
        );
        return;
      }

      final movements = movementsResponse['data']['movements'] as List;
      
      // Find the active OUT movement
      final activeMovement = movements.firstWhere(
        (m) => m['status'] == 'OUT',
        orElse: () => null,
      );

      if (activeMovement == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active movement found')),
        );
        return;
      }

      // Initialize controllers with current values
      final netWeightController = TextEditingController(text: _item.netWeight.toString());
      final purityController = TextEditingController(text: _item.purity);
      final remarksController = TextEditingController();
      final originalWeight = _item.netWeight;
      final isReturningNotifier = ValueNotifier<bool>(false);

      // Show bottom sheet with editable fields
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) => StatefulBuilder(
          builder: (context, setSheetState) {
            final currentWeight = double.tryParse(netWeightController.text) ?? originalWeight;
            final weightChange = currentWeight - originalWeight;
            final isReturning = isReturningNotifier.value;
            
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.inventory, color: Colors.blue, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Return to Stock', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              Text('Update item details if changed', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Movement Info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                activeMovement['movementType'] == 'REPAIR' ? Icons.build :
                                activeMovement['movementType'] == 'CUSTOMER_TRIAL' ? Icons.person :
                                Icons.store,
                                size: 16,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                activeMovement['movementType'] == 'REPAIR' ? 'Repair/Maintenance' :
                                activeMovement['movementType'] == 'CUSTOMER_TRIAL' ? 'Customer Trial' :
                                'Agent Consignment',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('Out Date: ${activeMovement['outDate']?.toString().split('T')[0] ?? 'N/A'}', style: const TextStyle(fontSize: 12)),
                          
                          // Repair-specific details
                          if (activeMovement['givenTo'] != null)
                            Text('Given To: ${activeMovement['givenTo']}', style: const TextStyle(fontSize: 12)),
                          if (activeMovement['repairType'] != null && activeMovement['repairType'].toString().isNotEmpty)
                            Text('Repair Type: ${activeMovement['repairType']}', style: const TextStyle(fontSize: 12)),
                          if (activeMovement['jobCardNumber'] != null && activeMovement['jobCardNumber'].toString().isNotEmpty)
                            Text('Job Card: ${activeMovement['jobCardNumber']}', style: const TextStyle(fontSize: 12)),
                          
                          // Customer trial details
                          if (activeMovement['customerName'] != null)
                            Text('Customer: ${activeMovement['customerName']}', style: const TextStyle(fontSize: 12)),
                          if (activeMovement['customerMobile'] != null)
                            Text('Mobile: ${activeMovement['customerMobile']}', style: const TextStyle(fontSize: 12)),
                          if (activeMovement['idProofType'] != null && activeMovement['idProofType'].toString().isNotEmpty)
                            Text('ID Proof: ${activeMovement['idProofType']}', style: const TextStyle(fontSize: 12)),
                          
                          // Agent consignment details
                          if (activeMovement['partyName'] != null)
                            Text('Party: ${activeMovement['partyName']}', style: const TextStyle(fontSize: 12)),
                          if (activeMovement['partyType'] != null)
                            Text('Party Type: ${activeMovement['partyType']}', style: const TextStyle(fontSize: 12)),
                          if (activeMovement['gstin'] != null && activeMovement['gstin'].toString().isNotEmpty)
                            Text('GSTIN: ${activeMovement['gstin']}', style: const TextStyle(fontSize: 12)),
                          if (activeMovement['challanNumber'] != null && activeMovement['challanNumber'].toString().isNotEmpty)
                            Text('Challan: ${activeMovement['challanNumber']}', style: const TextStyle(fontSize: 12)),
                          
                          // Common fields
                          if (activeMovement['expectedReturnDate'] != null)
                            Text('Expected Return: ${activeMovement['expectedReturnDate']?.toString().split('T')[0] ?? 'N/A'}', style: const TextStyle(fontSize: 12)),
                          if (activeMovement['remarks'] != null && activeMovement['remarks'].toString().isNotEmpty)
                            Text('Remarks: ${activeMovement['remarks']}', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    const Text('Item Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    
                    // Net Weight with change indicator
                    TextField(
                      controller: netWeightController,
                      decoration: InputDecoration(
                        labelText: 'Net Weight (g) *',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.scale),
                        suffixIcon: weightChange != 0 ? Tooltip(
                          message: weightChange > 0 ? 'Weight increased' : 'Weight decreased',
                          child: Icon(
                            weightChange > 0 ? Icons.trending_up : Icons.trending_down,
                            color: weightChange > 0 ? Colors.green : Colors.orange,
                          ),
                        ) : null,
                        helperText: weightChange != 0 
                            ? 'Change: ${weightChange > 0 ? '+' : ''}${weightChange.toStringAsFixed(3)}g'
                            : null,
                        helperStyle: TextStyle(
                          color: weightChange > 0 ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) => setSheetState(() {}),
                    ),
                    const SizedBox(height: 12),
                    
                    // Purity
                    TextField(
                      controller: purityController,
                      decoration: const InputDecoration(
                        labelText: 'Purity *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.diamond),
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Return Remarks
                    TextField(
                      controller: remarksController,
                      decoration: const InputDecoration(
                        labelText: 'Return Remarks (Optional)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.note),
                        hintText: 'e.g., Weight loss due to polishing',
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 20),
                    
                    // Return Button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isReturning ? Colors.grey : Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: isReturning ? null : () async {
                        // Validation
                        if (netWeightController.text.isEmpty || double.tryParse(netWeightController.text) == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter valid net weight')),
                          );
                          return;
                        }
                        
                        if (double.parse(netWeightController.text) <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Net weight must be greater than 0')),
                          );
                          return;
                        }

                        // Set loading state
                        isReturningNotifier.value = true;
                        setSheetState(() {});

                        try {
                          // Prepare update data
                          final updateData = {
                            'netWeight': double.parse(netWeightController.text),
                            'purity': purityController.text,
                            if (remarksController.text.isNotEmpty)
                              'returnRemarks': remarksController.text,
                          };
                          
                          // Call return API with updates
                          final response = await _apiService.returnItem(activeMovement['_id']);
                          
                          // Update item details if weight or purity changed
                          if (weightChange != 0 || purityController.text != _item.purity) {
                            await _apiService.updateItem(_item.id, updateData);
                          }
                          
                          Navigator.pop(context); // Close bottom sheet
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                weightChange != 0 
                                    ? 'Item returned. Weight ${weightChange > 0 ? 'increased' : 'decreased'} by ${weightChange.abs().toStringAsFixed(3)}g'
                                    : 'Item returned to stock successfully'
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                          _refreshData(); // Refresh item details
                        } catch (e) {
                          isReturningNotifier.value = false;
                          setSheetState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      },
                      child: isReturning
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Return', style: TextStyle(fontSize: 16)),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  // Wishlist Bottom Sheet
  void _showWishlistBottomSheet() {
    final nameController = TextEditingController();
    final mobileController = TextEditingController();
    final addressController = TextEditingController();
    bool isAddingToWishlist = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
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
    bool isBooking = false;

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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
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

  // Move Out Bottom Sheet - Smart Multi-Type Outward Movement
  void _showMoveOutBottomSheet() {
    String? selectedMovementType;
    final givenToController = TextEditingController(text: 'Workshop/Karigar');
    String? selectedRepairType;
    final customerNameController = TextEditingController();
    final customerMobileController = TextEditingController();
    final partyNameController = TextEditingController();
    String? selectedPartyType;
    final remarksController = TextEditingController();
    DateTime? expectedReturnDate;
    DateTime outDate = DateTime.now();
    bool isSubmitting = false;

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
                Text(
                  'Move Out of Stock',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Item Preview
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      if (_item.images.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            _item.images.first.startsWith('http')
                                ? _item.images.first
                                : '${AppConstants.baseUrl}/${_item.images.first.replaceAll('\\', '/')}',
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.diamond, size: 50),
                          ),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text('Barcode: ${_item.barcode}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                
                // Warning Banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Item will not be counted in saleable stock until returned',
                          style: TextStyle(fontSize: 12, color: Colors.orange[900]),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Movement Type Dropdown
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Movement Type *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category),
                  ),
                  value: selectedMovementType,
                  items: const [
                    DropdownMenuItem(
                      value: 'REPAIR',
                      child: Row(
                        children: [
                          Icon(Icons.build, size: 18),
                          SizedBox(width: 8),
                          Text('Repair / Maintenance'),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'CUSTOMER_TRIAL',
                      child: Row(
                        children: [
                          Icon(Icons.person, size: 18),
                          SizedBox(width: 8),
                          Text('Given to Customer (Trial)'),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'AGENT_CONSIGNMENT',
                      child: Row(
                        children: [
                          Icon(Icons.store, size: 18),
                          SizedBox(width: 8),
                          Text('Given to Shop / Agent'),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setSheetState(() {
                      selectedMovementType = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                
                // Conditional Fields
                if (selectedMovementType == 'REPAIR') ...[
                  TextField(
                    controller: givenToController,
                    decoration: const InputDecoration(labelText: 'Given To *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Repair Type',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.build_circle_outlined),
                    ),
                    value: selectedRepairType,
                    items: const [
                      DropdownMenuItem(value: 'Polish', child: Text('Polish')),
                      DropdownMenuItem(value: 'Resize', child: Text('Resize')),
                      DropdownMenuItem(value: 'Stone Setting', child: Text('Stone Setting')),
                      DropdownMenuItem(value: 'Chain Repair', child: Text('Chain Repair')),
                      DropdownMenuItem(value: 'Clasp Repair', child: Text('Clasp Repair')),
                      DropdownMenuItem(value: 'Engraving', child: Text('Engraving')),
                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                    ],
                    onChanged: (value) {
                      setSheetState(() {
                        selectedRepairType = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                
                if (selectedMovementType == 'CUSTOMER_TRIAL') ...[
                  TextField(
                    controller: customerNameController,
                    decoration: const InputDecoration(labelText: 'Customer Name *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: customerMobileController,
                    decoration: const InputDecoration(labelText: 'Mobile Number *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)),
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                  ),
                  const SizedBox(height: 12),
                ],
                
                if (selectedMovementType == 'AGENT_CONSIGNMENT') ...[
                  TextField(
                    controller: partyNameController,
                    decoration: const InputDecoration(labelText: 'Party Name *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.business)),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Party Type *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.category)),
                    value: selectedPartyType,
                    items: const [
                      DropdownMenuItem(value: 'SHOP', child: Text('Shop')),
                      DropdownMenuItem(value: 'AGENT', child: Text('Agent')),
                      DropdownMenuItem(value: 'WHOLESALER', child: Text('Wholesaler')),
                    ],
                    onChanged: (value) {
                      setSheetState(() {
                        selectedPartyType = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                
                // Expected Return Date
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: expectedReturnDate ?? DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) setSheetState(() => expectedReturnDate = date);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Expected Return Date', border: OutlineInputBorder(), prefixIcon: Icon(Icons.calendar_today)),
                    child: Text(expectedReturnDate != null ? expectedReturnDate!.toIso8601String().split('T')[0] : 'Select Date'),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Remarks
                TextField(
                  controller: remarksController,
                  decoration: const InputDecoration(labelText: 'Remarks (Optional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.note)),
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                
                // Submit Button
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSubmitting ? Colors.grey : Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: isSubmitting ? null : () async {
                    // Validation
                    if (selectedMovementType == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select movement type')));
                      return;
                    }
                    

                    
                    if (selectedMovementType == 'REPAIR' && givenToController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Given To is required for repair')));
                      return;
                    }
                    
                    if (selectedMovementType == 'CUSTOMER_TRIAL') {
                      if (customerNameController.text.isEmpty || customerMobileController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer name and mobile are required')));
                        return;
                      }
                      if (customerMobileController.text.length != 10) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mobile number must be 10 digits')));
                        return;
                      }
                    }
                    
                    if (selectedMovementType == 'AGENT_CONSIGNMENT') {
                      if (partyNameController.text.isEmpty || selectedPartyType == null) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Party name and type are required')));
                        return;
                      }
                    }
                    
                    // Set loading state
                    setSheetState(() => isSubmitting = true);
                    
                    try {
                      final data = {
                        'itemId': _item.id,
                        'movementType': selectedMovementType,
                        'grossWeight': _item.netWeight,
                        'purity': _item.purity,
                        'outDate': outDate.toIso8601String(),
                        'expectedReturnDate': expectedReturnDate?.toIso8601String(),
                        'remarks': remarksController.text,
                        if (selectedMovementType == 'REPAIR') ...{
                          'givenTo': givenToController.text,
                          'repairType': selectedRepairType ?? '',
                        },
                        if (selectedMovementType == 'CUSTOMER_TRIAL') ...{
                          'customerName': customerNameController.text,
                          'customerMobile': customerMobileController.text,
                        },
                        if (selectedMovementType == 'AGENT_CONSIGNMENT') ...{
                          'partyName': partyNameController.text,
                          'partyType': selectedPartyType,
                        },
                      };
                      
                      final response = await _apiService.createOutwardMovement(data);
                      
                      if (response['success'] == true) {
                        Navigator.pop(context);
                        _showMoveOutSuccessDialog(response['data']['movement']);
                        _refreshData();
                      } else {
                        setSheetState(() => isSubmitting = false);
                        throw response['message'] ?? 'Failed';
                      }
                    } catch (e) {
                      setSheetState(() => isSubmitting = false);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  child: isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Move Out', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMoveOutSuccessDialog(Map<String, dynamic> movement) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.all(20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Item Moved Out',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'ID: #${movement['_id']?.substring(0, 8) ?? 'N/A'}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Challan generation coming soon')),
                    );
                  },
                  child: const Text('Challan', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovementDetailRow(String label, String value, {bool isRemark = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: Colors.black87,
                fontStyle: isRemark ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

