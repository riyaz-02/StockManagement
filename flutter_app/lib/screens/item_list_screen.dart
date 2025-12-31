import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/item_provider.dart';
import '../providers/language_provider.dart';
import '../utils/app_colors.dart';
import 'item_details_screen.dart';
import 'add_edit_item_screen.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: Text(languageProvider.translate('items')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadItems,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddEditItemScreen()),
          ).then((_) => _loadItems());
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
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
                : itemProvider.items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(
                              languageProvider.translate('no_data') == 'no_data' 
                                  ? 'No items found' 
                                  : languageProvider.translate('no_data'),
                              style: TextStyle(fontSize: 18, color: Colors.grey),
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
                                  MaterialPageRoute(
                                    builder: (_) => const AddEditItemScreen(),
                                  ),
                                ).then((_) => _loadItems());
                              },
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: itemProvider.items.length,
                        itemBuilder: (context, index) {
                          final item = itemProvider.items[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getStatusColor(item.status),
                                child: Icon(
                                  _getStatusIcon(item.status),
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(item.name),
                              subtitle: Text(
                                '${item.barcode} • ${item.netWeight}g • ${languageProvider.translate(item.metalType)}',
                              ),
                              trailing: Chip(
                                label: Text(
                                  languageProvider.translate(item.status),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                  ),
                                ),
                                backgroundColor: _getStatusColor(item.status),
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ItemDetailsScreen(item: item),
                                  ),
                                ).then((_) => _loadItems());
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _statusFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _statusFilter = value;
          _loadItems();
        });
      },
      selectedColor: AppColors.primary.withOpacity(0.3),
    );
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
