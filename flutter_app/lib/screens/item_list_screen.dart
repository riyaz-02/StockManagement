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
          
          // Status Filter Chips + Filter Button
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
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
              ),
              // Filter button — fixed on the right
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _showFilterMenu(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (_metalTypeFilter != null || _itemTypeFilter != null ||
                                  _purityFilter != null || _certificationFilter != null ||
                                  _minWeight != null || _maxWeight != null)
                              ? const Color(0xFFE94560).withOpacity(0.1)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: (_metalTypeFilter != null || _itemTypeFilter != null ||
                                    _purityFilter != null || _certificationFilter != null ||
                                    _minWeight != null || _maxWeight != null)
                                ? const Color(0xFFE94560)
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Icon(
                          Icons.tune,
                          size: 20,
                          color: (_metalTypeFilter != null || _itemTypeFilter != null ||
                                  _purityFilter != null || _certificationFilter != null ||
                                  _minWeight != null || _maxWeight != null)
                              ? const Color(0xFFE94560)
                              : Colors.grey[600],
                        ),
                      ),
                    ),
                    // Active filter count badge
                    if ([_metalTypeFilter, _itemTypeFilter, _purityFilter, _certificationFilter]
                            .where((f) => f != null)
                            .length +
                        (_minWeight != null || _maxWeight != null ? 1 : 0) >
                        0)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE94560),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${[_metalTypeFilter, _itemTypeFilter, _purityFilter, _certificationFilter].where((f) => f != null).length + (_minWeight != null || _maxWeight != null ? 1 : 0)}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
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
    final Color statusColor = _getStatusColor(item.status);
    final double netWeight = item.netWeight;

    // Construct Image URL
    String? imageUrl;
    if (item.images.isNotEmpty) {
      final path = item.images.first;
      if (path.startsWith('http')) {
        imageUrl = path;
      } else {
        final cleanPath = path.replaceAll('\\', '/');
        imageUrl = '${AppConstants.baseUrl}/$cleanPath';
      }
    }

    // Weight colour: gold ≥10g, green 3–10g, blue <3g
    final Color weightColor = netWeight >= 10
        ? const Color(0xFFB8860B)
        : netWeight >= 3
            ? const Color(0xFF2E7D32)
            : const Color(0xFF0277BD);

    return Stack(
      children: [
        Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          shadowColor: statusColor.withOpacity(0.15),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ItemDetailsScreen(item: item)),
              ).then((_) => _loadItems());
            },
            onLongPress: () => _showItemOptions(context, item),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Image ──────────────────────────────────────────────
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withOpacity(0.22), width: 1.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
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
                              errorWidget: (context, url, error) =>
                                  Icon(Icons.broken_image, color: statusColor, size: 30),
                            )
                          : Icon(Icons.diamond_outlined, size: 32, color: statusColor),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // ── Details ────────────────────────────────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Name + status badge
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                _formatText(item.name),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: statusColor.withOpacity(0.35)),
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
                        const SizedBox(height: 2),
                        // Barcode
                        Text(
                          item.barcode ?? '',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 11,
                            fontFamily: 'monospace',
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 6),

                         Wrap(
                          spacing: 4,
                          runSpacing: 3,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // Weight — prominent
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: weightColor.withOpacity(0.09),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: weightColor.withOpacity(0.28)),
                              ),
                              child: Text(
                                '${netWeight.toStringAsFixed(2)}g',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: weightColor,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            _buildSpecPill(_formatText(item.metalType), Colors.purple),
                            _buildSpecPill(_formatText(item.itemType), Colors.teal),
                            _buildSpecPill(_formatText(item.purity), const Color(0xFFB8860B)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Certification stamp (unchanged) ────────────────────────────
        if (item.certificationType == 'hallmarked' || item.certificationType == 'huid')
          Positioned(
            top: 46,
            right: 8,
            child: Transform.rotate(
              angle: -0.35,
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

  Widget _buildSpecPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: color.withOpacity(0.9),
        ),
      ),
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w500),
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
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    final filterOptions = itemProvider.filterOptions;
    final allLoadedItems = itemProvider.items;

    final metalTypes = (filterOptions?['metalTypes'] as List?)?.cast<String>() ?? ['Gold', 'Silver', 'Platinum'];
    final itemTypes = (filterOptions?['itemTypes'] as List?)?.cast<String>() ?? ['Ring', 'Necklace', 'Bracelet', 'Earring', 'Pendant', 'Chain', 'Bangle'];
    final purityOptions = (filterOptions?['purities'] as List?)?.cast<String>() ?? ['18k', '22k', '24k', '916', '999'];
    final globalWeightRange = filterOptions?['weightRange'];

    // Global absolute bounds (never go outside these)
    final globalMin = (globalWeightRange?['minWeight'] ?? 0).toDouble();
    final globalMax = (globalWeightRange?['maxWeight'] ?? 100).toDouble();

    // In-modal filter state (mirrors the screen state, starts from current values)
    String? modalMetal = _metalTypeFilter;
    String? modalItemType = _itemTypeFilter;
    String? modalPurity = _purityFilter;
    String? modalCert = _certificationFilter;
    RangeValues? modalWeightRange = _weightRange;

    /// Compute the weight range for items matching the current in-modal filters.
    /// Returns {min, max} clamped to global bounds.
    Map<String, double> computeDynamicRange(
        String? metal, String? itemType, String? purity) {
      // If no items loaded yet, fall back to global range
      if (allLoadedItems.isEmpty) {
        return {'min': globalMin, 'max': globalMax};
      }

      final matching = allLoadedItems.where((item) {
        if (metal != null &&
            item.metalType.toLowerCase() != metal.toLowerCase()) return false;
        if (itemType != null &&
            item.itemType.toLowerCase() != itemType.toLowerCase()) return false;
        if (purity != null &&
            item.purity.toLowerCase() != purity.toLowerCase()) return false;
        return true;
      }).toList();

      if (matching.isEmpty) {
        return {'min': globalMin, 'max': globalMax};
      }

      final weights = matching.map((i) => i.netWeight).toList();
      return {
        'min': weights.reduce((a, b) => a < b ? a : b),
        'max': weights.reduce((a, b) => a > b ? a : b),
      };
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Compute dynamic weight bounds from in-modal selections
            final dynamic = computeDynamicRange(modalMetal, modalItemType, modalPurity);
            final dynMin = dynamic['min']!;
            final dynMax = dynamic['max']!;

            // Count matching items for the hint label
            final matchCount = allLoadedItems.where((item) {
              if (modalMetal != null &&
                  item.metalType.toLowerCase() != modalMetal!.toLowerCase()) return false;
              if (modalItemType != null &&
                  item.itemType.toLowerCase() != modalItemType!.toLowerCase()) return false;
              if (modalPurity != null &&
                  item.purity.toLowerCase() != modalPurity!.toLowerCase()) return false;
              return true;
            }).length;

            // Clamp current weight range to new dynamic bounds
            final effectiveRange = modalWeightRange == null
                ? RangeValues(dynMin, dynMax)
                : RangeValues(
                    modalWeightRange!.start.clamp(dynMin, dynMax).toDouble(),
                    modalWeightRange!.end.clamp(dynMin, dynMax).toDouble(),
                  );

            // Helper: update a filter and reset weight range to new dynamic bounds
            void updateFilter({
              String? metal,
              String? itemType,
              String? purity,
              bool clearMetal = false,
              bool clearItemType = false,
              bool clearPurity = false,
            }) {
              setModalState(() {
                if (clearMetal) modalMetal = null; else if (metal != null) modalMetal = metal;
                if (clearItemType) modalItemType = null; else if (itemType != null) modalItemType = itemType;
                if (clearPurity) modalPurity = null; else if (purity != null) modalPurity = purity;
                // Reset weight range to the new dynamic bounds
                final newDyn = computeDynamicRange(modalMetal, modalItemType, modalPurity);
                modalWeightRange = RangeValues(newDyn['min']!, newDyn['max']!);
              });
            }

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
                        final isSelected = modalMetal == metal;
                        return FilterChip(
                          label: Text(metal),
                          selected: isSelected,
                          onSelected: (selected) {
                            updateFilter(
                              metal: selected ? metal : null,
                              clearMetal: !selected,
                            );
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
                        final isSelected = modalItemType == type;
                        return FilterChip(
                          label: Text(type),
                          selected: isSelected,
                          onSelected: (selected) {
                            updateFilter(
                              itemType: selected ? type : null,
                              clearItemType: !selected,
                            );
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
                        final isSelected = modalPurity == purity;
                        return FilterChip(
                          label: Text(purity),
                          selected: isSelected,
                          onSelected: (selected) {
                            updateFilter(
                              purity: selected ? purity : null,
                              clearPurity: !selected,
                            );
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
                        final isSelected = modalCert == cert;
                        return FilterChip(
                          label: Text(cert == 'none' ? 'Non-certified' : cert.toUpperCase()),
                          selected: isSelected,
                          onSelected: (selected) {
                            setModalState(() {
                              modalCert = selected ? cert : null;
                            });
                          },
                          selectedColor: const Color(0xFFE94560).withOpacity(0.2),
                          checkmarkColor: const Color(0xFFE94560),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    
                    // Weight Range Filter — dynamic bounds
                    if (globalWeightRange != null || allLoadedItems.isNotEmpty) ...[ 
                      Row(
                        children: [
                          const Text('Weight Range (grams)',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          // Hint: how many items are in this range
                          if (allLoadedItems.isNotEmpty)
                            Text(
                              '$matchCount item${matchCount == 1 ? '' : 's'} in range',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[500]),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Dynamic bounds label
                      if (dynMin != globalMin || dynMax != globalMax)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Icon(Icons.tune, size: 13, color: const Color(0xFFE94560)),
                              const SizedBox(width: 4),
                              Text(
                                'Adjusted for selected filters',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: const Color(0xFFE94560),
                                    fontStyle: FontStyle.italic),
                              ),
                            ],
                          ),
                        ),
                      // Guard: if dynMin == dynMax (only one weight value), skip slider
                      if (dynMin < dynMax)
                        RangeSlider(
                          values: effectiveRange,
                          min: dynMin,
                          max: dynMax,
                          divisions: ((dynMax - dynMin) * 10).round().clamp(1, 200),
                          labels: RangeLabels(
                            '${effectiveRange.start.toStringAsFixed(2)}g',
                            '${effectiveRange.end.toStringAsFixed(2)}g',
                          ),
                          activeColor: const Color(0xFFE94560),
                          inactiveColor: const Color(0xFFE94560).withOpacity(0.2),
                          onChanged: (RangeValues values) {
                            setModalState(() {
                              modalWeightRange = values;
                            });
                          },
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'All items weigh ${dynMin.toStringAsFixed(2)}g',
                            style: TextStyle(color: Colors.grey[600], fontSize: 13),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${effectiveRange.start.toStringAsFixed(2)}g',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                            Text(
                              '${effectiveRange.end.toStringAsFixed(2)}g',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500),
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
                          // Commit modal state back to screen state
                          setState(() {
                            _metalTypeFilter = modalMetal;
                            _itemTypeFilter = modalItemType;
                            _purityFilter = modalPurity;
                            _certificationFilter = modalCert;
                            _weightRange = modalWeightRange;
                            _minWeight = effectiveRange.start == dynMin ? null : effectiveRange.start;
                            _maxWeight = effectiveRange.end == dynMax ? null : effectiveRange.end;
                          });
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
                        child: const Text('Apply Filters',
                            style: TextStyle(fontSize: 16, color: Colors.white)),
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
