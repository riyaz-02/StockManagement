import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/item_provider.dart';
import '../providers/language_provider.dart';
import '../utils/app_colors.dart';
import '../utils/app_constants.dart';
import 'item_details_screen.dart';
import 'add_edit_item_screen.dart';
import 'recycle_bin_screen.dart';
import 'moved_out_items_screen.dart';

class ItemListScreen extends StatefulWidget {
  const ItemListScreen({super.key});

  @override
  State<ItemListScreen> createState() => _ItemListScreenState();
}

class _ItemListScreenState extends State<ItemListScreen> {
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  void _loadItems() {
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    if (_statusFilter == 'all') {
      itemProvider.fetchItems();
    } else {
      itemProvider.fetchItems(status: _statusFilter);
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final itemProvider = Provider.of<ItemProvider>(context);
    final items = itemProvider.items;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Items',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        actions: [
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
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Recycle Bin',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RecycleBinScreen()),
              ).then((_) => _loadItems());
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadItems,
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
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

          // Items List
          Expanded(
            child: itemProvider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? _buildEmptyState(languageProvider)
                    : ListView.builder(
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

    return Card(
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
              // 1. Item Image
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
                       ? Image.network(
                           imageUrl, 
                           fit: BoxFit.cover,
                           errorBuilder: (_,__,___) => Icon(Icons.broken_image, color: statusColor),
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
}
