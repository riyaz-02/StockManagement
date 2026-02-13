import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/item_model.dart';
import '../providers/item_provider.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_constants.dart';
import 'item_details_screen.dart';
import 'add_edit_item_screen.dart';
import 'recycle_bin_screen.dart';
import 'moved_out_items_screen.dart';

class ItemListScreen extends StatefulWidget {
  final String? initialStatus;
  
  const ItemListScreen({super.key, this.initialStatus});

  @override
  State<ItemListScreen> createState() => _ItemListScreenState();
}

class _ItemListScreenState extends State<ItemListScreen> with AutomaticKeepAliveClientMixin {
  String _statusFilter = 'all';
  String _searchQuery = '';
  String? _metalTypeFilter;
  String? _itemTypeFilter;
  String? _purityFilter;
  String? _certificationFilter;
  double? _minWeight;
  double? _maxWeight;
  RangeValues? _weightRange;
  
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Apply initial status filter if provided
    if (widget.initialStatus != null) {
      _statusFilter = widget.initialStatus!;
    }
    // Fetch filter options
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ItemProvider>(context, listen: false).fetchFilterOptions();
    });
    _loadItems();
  }

  void _loadItems() {
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    
    // Build query parameters
    Map<String, String> queryParams = {};
    
    if (_searchQuery.isNotEmpty) {
      queryParams['search'] = _searchQuery;
    }
    if (_metalTypeFilter != null) {
      queryParams['metalType'] = _metalTypeFilter!;
    }
    if (_itemTypeFilter != null) {
      queryParams['itemType'] = _itemTypeFilter!;
    }
    if (_purityFilter != null) {
      queryParams['purity'] = _purityFilter!;
    }
    if (_certificationFilter != null) {
      queryParams['certificationType'] = _certificationFilter!;
    }
    if (_minWeight != null) {
      queryParams['minWeight'] = _minWeight.toString();
    }
    if (_maxWeight != null) {
      queryParams['maxWeight'] = _maxWeight.toString();
    }
    
    // Use existing fetchItems method with status and filters
    itemProvider.fetchItems(
      status: _statusFilter == 'all' ? null : _statusFilter,
      filters: queryParams.isEmpty ? null : queryParams,
    );
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    final languageProvider = Provider.of<LanguageProvider>(context);
    final itemProvider = Provider.of<ItemProvider>(context);
    final items = itemProvider.items;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Pop if we can (navigated here from another screen)
            // Otherwise, the WillPopScope in MainNavigationScreen will handle it
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              // Trigger back button behavior which MainNavigationScreen will catch
              Navigator.maybePop(context);
            }
          },
        ),
        title: Consumer<LanguageProvider>(
          builder: (context, languageProvider, child) => Text(
            languageProvider.t('items'),
            style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filters',
            onPressed: () => _showFilterMenu(context),
          ),
          IconButton(
            icon: const Icon(Icons.output),
            tooltip: 'Moved Out Items',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MovedOutItemsScreen()),
              ).then((_) => _loadItems());
            },
          ),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE94560), Color(0xFFD32F2F)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE94560).withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddEditItemScreen()),
            ).then((_) => _loadItems());
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or barcode...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFFE94560)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                          _loadItems();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE94560), width: 2),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              onChanged: (value) {
                if (_debounce?.isActive ?? false) _debounce!.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  setState(() => _searchQuery = value);
                  _loadItems();
                });
              },
            ),
          ),
          
          // Status Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildFilterChip('All', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('Active', 'active'),
                const SizedBox(width: 8),
                _buildFilterChip('Booked', 'booked'),
                const SizedBox(width: 8),
                _buildFilterChip('In Repair', 'in_repair'),
                const SizedBox(width: 8),
                _buildFilterChip('Sold', 'sold'),
              ],
            ),
          ),
          
          // Additional Filters Row with Clear Button
          if (_metalTypeFilter != null || _itemTypeFilter != null || 
              _purityFilter != null || _certificationFilter != null ||
              _minWeight != null || _maxWeight != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (_metalTypeFilter != null)
                          _buildActiveFilterChip('Metal: $_metalTypeFilter', () {
                            setState(() => _metalTypeFilter = null);
                            _loadItems();
                          }),
                        if (_itemTypeFilter != null)
                          _buildActiveFilterChip('Type: $_itemTypeFilter', () {
                            setState(() => _itemTypeFilter = null);
                            _loadItems();
                          }),
                        if (_purityFilter != null)
                          _buildActiveFilterChip('Purity: $_purityFilter', () {
                            setState(() => _purityFilter = null);
                            _loadItems();
                          }),
                        if (_certificationFilter != null)
                          _buildActiveFilterChip('Cert: $_certificationFilter', () {
                            setState(() => _certificationFilter = null);
                            _loadItems();
                          }),
                        if (_minWeight != null || _maxWeight != null)
                          _buildActiveFilterChip(
                            'Weight: ${_minWeight?.toStringAsFixed(1) ?? '0'}-${_maxWeight?.toStringAsFixed(1) ?? '∞'}g',
                            () {
                              setState(() {
                                _minWeight = null;
                                _maxWeight = null;
                                _weightRange = null;
                              });
                              _loadItems();
                            }
                          ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Clear'),
                    onPressed: () {
                      setState(() {
                        _metalTypeFilter = null;
                        _itemTypeFilter = null;
                        _purityFilter = null;
                        _certificationFilter = null;
                        _minWeight = null;
                        _maxWeight = null;
                        _weightRange = null;
                      });
                      _loadItems();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFE94560),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
            ),

          // Items List
          Expanded(
            child: itemProvider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? _buildEmptyState(languageProvider)
                    : ListView.builder(
                        key: const PageStorageKey<String>('itemsListView'),
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _buildItemCard(context, item, languageProvider);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(LanguageProvider languageProvider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            languageProvider.translate('no_data') == 'no_data' 
                ? 'No items found' 
                : languageProvider.translate('no_data'),
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: Text(
              languageProvider.translate('add_item') == 'add_item'
                  ? 'Add Item'
                  : languageProvider.translate('add_item')
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddEditItemScreen()),
              ).then((_) => _loadItems());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(BuildContext context, dynamic item, LanguageProvider languageProvider) {
    Color statusColor = _getStatusColor(item.status);
    
    // Construct Image URL
    String? imageUrl;
    if (item.images.isNotEmpty) {
      final path = item.images.first;
      if (path.startsWith('http')) {
        imageUrl = path;
      } else {
        String cleanPath = path.replaceAll('\\', '/');
        imageUrl = '${AppConstants.baseUrl}/$cleanPath'; 
      }
    }

    return Stack(
      children: [
        Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ItemDetailsScreen(item: item),
                ),
              ).then((_) => _loadItems());
            },
            onLongPress: () => _showItemOptions(context, item),
            child: Padding(
              padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Item Image (no badge here anymore)
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: ClipRRect(
                   borderRadius: BorderRadius.circular(12),
                   child: imageUrl != null 
                       ? CachedNetworkImage(
                           imageUrl: imageUrl,
                           fit: BoxFit.cover,
                           memCacheWidth: 200,
                           maxWidthDiskCache: 400,
                           placeholder: (context, url) => Center(
                             child: CircularProgressIndicator(
                               strokeWidth: 2,
                               valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                             ),
                           ),
                           errorWidget: (context, url, error) => Icon(
                             Icons.broken_image,
                             color: statusColor,
                           ),
                         )
                       : Icon(Icons.diamond_outlined, size: 30, color: statusColor),
                ),
              ),
              const SizedBox(width: 16),

              // 2. Details Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name & Type
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatText(item.name),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.barcode,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Status Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: statusColor.withOpacity(0.5)),
                          ),
                          child: Text(
                            languageProvider.translate(item.status),
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Specs Grid
                    Row(
                      children: [
                        _buildCompactSpec(Icons.scale, '${item.netWeight}g'),
                        const SizedBox(width: 12),
                        _buildCompactSpec(Icons.category, _formatText(item.itemType)),
                        const SizedBox(width: 12),
                         _buildCompactSpec(Icons.diamond, _formatText(item.metalType)),
                      ],
                    ),
                    
                    if (item.weightCategory != null && item.weightCategory!.isNotEmpty) ...[
                       const SizedBox(height: 6),
                       Container(
                         padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                         decoration: BoxDecoration(
                           color: Colors.grey[100],
                           borderRadius: BorderRadius.circular(4),
                         ),
                         child: Text(
                           item.weightCategory!,
                           style: TextStyle(fontSize: 10, color: Colors.grey[700]),
                         ),
                       ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    // Certification Badge Overlay (positioned absolutely, doesn't take up space)
    if (item.certificationType == 'hallmarked' || item.certificationType == 'huid')
      Positioned(
        top: 46, // More margin below status badge
        right: 8,
        child: Transform.rotate(
          angle: -0.35, // Increased rotation for stamp effect
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: item.certificationType == 'hallmarked'
                  ? const Color(0xFFFFD700).withOpacity(0.18)
                  : const Color(0xFF2196F3).withOpacity(0.18),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: item.certificationType == 'hallmarked'
                    ? const Color(0xFFB8860B).withOpacity(0.35)
                    : const Color(0xFF0D47A1).withOpacity(0.35),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  item.certificationType == 'hallmarked'
                      ? Icons.verified_rounded
                      : Icons.qr_code_2_rounded,
                  size: 16,
                  color: item.certificationType == 'hallmarked'
                      ? const Color(0xFFB8860B).withOpacity(0.75)
                      : const Color(0xFF0D47A1).withOpacity(0.75),
                ),
                const SizedBox(width: 4),
                Text(
                  item.certificationType == 'hallmarked' ? '916' : 'HUID',
                  style: TextStyle(
                    color: item.certificationType == 'hallmarked'
                        ? const Color(0xFFB8860B).withOpacity(0.85)
                        : const Color(0xFF0D47A1).withOpacity(0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
  ],
);
  }

  void _showItemOptions(BuildContext context, dynamic item) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatText(item.name),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                item.barcode,
                style: TextStyle(fontSize: 14, color: Colors.grey[600], fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.open_in_new, color: Colors.blue),
                title: const Text('Open Details'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ItemDetailsScreen(item: item),
                    ),
                  ).then((_) => _loadItems());
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.black87),
                title: const Text('Edit Item'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddEditItemScreen(item: item),
                    ),
                  ).then((_) => _loadItems());
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                   _confirmDelete(context, item);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, dynamic item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item?'),
        content: Text('Are you sure you want to delete "${item.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final provider = Provider.of<ItemProvider>(context, listen: false);
              final success = await provider.deleteItem(item.id);
              if (mounted) {
                if (success) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(content: Text('Item deleted successfully'), backgroundColor: Colors.green),
                   );
                   _loadItems();
                } else {
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text(provider.error ?? 'Failed to delete'), backgroundColor: Colors.red),
                   );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactSpec(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _statusFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _statusFilter = value;
          _loadItems();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFFE94560), Color(0xFFD32F2F)],
                )
              : null,
          color: isSelected ? null : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : Colors.grey.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF1A1A1A),
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  String _formatText(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active':
        return AppColors.statusActive;
      case 'booked':
        return AppColors.statusBooked;
      case 'in_repair':
        return AppColors.statusRepair;
      case 'sold':
        return AppColors.statusSold;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'active':
        return Icons.check_circle;
      case 'booked':
        return Icons.bookmark;
      case 'in_repair':
        return Icons.build;
      case 'sold':
        return Icons.sell;
      default:
        return Icons.inventory;
    }
  }

  Widget _buildActiveFilterChip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE94560).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE94560)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFE94560),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(
              Icons.close,
              size: 14,
              color: Color(0xFFE94560),
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterMenu(BuildContext context) {
    // Get dynamic filter options from provider
    final filterOptions = Provider.of<ItemProvider>(context, listen: false).filterOptions;
    final metalTypes = (filterOptions?['metalTypes'] as List?)?.cast<String>() ?? ['Gold', 'Silver', 'Platinum'];
    final itemTypes = (filterOptions?['itemTypes'] as List?)?.cast<String>() ?? ['Ring', 'Necklace', 'Bracelet', 'Earring', 'Pendant', 'Chain', 'Bangle'];
    final purityOptions = (filterOptions?['purities'] as List?)?.cast<String>() ?? ['18k', '22k', '24k', '916', '999'];
    final weightRange = filterOptions?['weightRange'];
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Filter Items',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(sheetContext),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // Metal Type Filter
                    const Text('Metal Type', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: metalTypes.map((metal) {
                        final isSelected = _metalTypeFilter == metal;
                        return FilterChip(
                          label: Text(metal),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _metalTypeFilter = selected ? metal : null;
                            });
                            setModalState(() {});
                          },
                          selectedColor: const Color(0xFFE94560).withOpacity(0.2),
                          checkmarkColor: const Color(0xFFE94560),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    
                    // Item Type Filter
                    const Text('Item Type', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: itemTypes.map((type) {
                        final isSelected = _itemTypeFilter == type;
                        return FilterChip(
                          label: Text(type),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _itemTypeFilter = selected ? type : null;
                            });
                            setModalState(() {});
                          },
                          selectedColor: const Color(0xFFE94560).withOpacity(0.2),
                          checkmarkColor: const Color(0xFFE94560),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    
                    // Purity Filter
                    const Text('Purity', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: purityOptions.map((purity) {
                        final isSelected = _purityFilter == purity;
                        return FilterChip(
                          label: Text(purity),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _purityFilter = selected ? purity : null;
                            });
                            setModalState(() {});
                          },
                          selectedColor: const Color(0xFFE94560).withOpacity(0.2),
                          checkmarkColor: const Color(0xFFE94560),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    
                    // Certification Filter
                    const Text('Certification', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ['hallmarked', 'huid', 'none'].map((cert) {
                        final isSelected = _certificationFilter == cert;
                        return FilterChip(
                          label: Text(cert == 'none' ? 'Non-certified' : cert.toUpperCase()),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _certificationFilter = selected ? cert : null;
                            });
                            setModalState(() {});
                          },
                          selectedColor: const Color(0xFFE94560).withOpacity(0.2),
                          checkmarkColor: const Color(0xFFE94560),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    
                    // Weight Range Filter
                    if (weightRange != null) ...[
                      const Text('Weight Range (grams)', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      RangeSlider(
                        values: _weightRange ?? RangeValues(
                          (weightRange['minWeight'] ?? 0).toDouble(),
                          (weightRange['maxWeight'] ?? 100).toDouble(),
                        ),
                        min: (weightRange['minWeight'] ?? 0).toDouble(),
                        max: (weightRange['maxWeight'] ?? 100).toDouble(),
                        divisions: 100,
                        labels: RangeLabels(
                          (_weightRange?.start ?? weightRange['minWeight']).toStringAsFixed(2),
                          (_weightRange?.end ?? weightRange['maxWeight']).toStringAsFixed(2),
                        ),
                        activeColor: const Color(0xFFE94560),
                        inactiveColor: const Color(0xFFE94560).withOpacity(0.2),
                        onChanged: (RangeValues values) {
                          setState(() {
                            _weightRange = values;
                            _minWeight = values.start;
                            _maxWeight = values.end;
                          });
                          setModalState(() {});
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_minWeight?.toStringAsFixed(2) ?? weightRange['minWeight']}g',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                            Text(
                              '${_maxWeight?.toStringAsFixed(2) ?? weightRange['maxWeight']}g',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 24),
                    
                    // Apply Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _loadItems();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE94560),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Apply Filters', style: TextStyle(fontSize: 16, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
