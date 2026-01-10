import 'package:flutter/material.dart';
import '../models/item_model.dart';
import '../services/api_service.dart';
import 'tag_print_preview_screen.dart';

class TagPrintingScreen extends StatefulWidget {
  const TagPrintingScreen({super.key});

  @override
  State<TagPrintingScreen> createState() => _TagPrintingScreenState();
}

class _TagPrintingScreenState extends State<TagPrintingScreen> {
  final ApiService _apiService = ApiService();
  List<Item> _allItems = [];
  List<Item> _filteredItems = [];
  Set<String> _selectedItemIds = {};
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterType = 'all'; // all, hallmark, non-hallmark, not-printed

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    try {
      final itemsData = await _apiService.getItemsForTagPrinting();
      final items = itemsData.map((json) => Item.fromJson(json)).toList();
      setState(() {
        _allItems = items;
        _filteredItems = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading items: $e')),
        );
      }
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredItems = _allItems.where((item) {
        // Search filter
        final matchesSearch = _searchQuery.isEmpty ||
            item.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            item.barcode.toLowerCase().contains(_searchQuery.toLowerCase());

        // Type filter
        bool matchesType = true;
        switch (_filterType) {
          case 'hallmark':
            matchesType = item.huid.isNotEmpty;
            break;
          case 'non-hallmark':
            matchesType = item.huid.isEmpty;
            break;
          case 'not-printed':
            matchesType = !item.tagsPrinted;
            break;
        }

        return matchesSearch && matchesType;
      }).toList();
    });
  }

  void _toggleSelection(String itemId) {
    setState(() {
      if (_selectedItemIds.contains(itemId)) {
        _selectedItemIds.remove(itemId);
      } else {
        _selectedItemIds.add(itemId);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedItemIds = _filteredItems.map((item) => item.id).toSet();
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedItemIds.clear();
    });
  }

  void _navigateToPrintPreview() {
    final selectedItems = _allItems
        .where((item) => _selectedItemIds.contains(item.id))
        .toList();

    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one item')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TagPrintPreviewScreen(items: selectedItems),
      ),
    ).then((_) => _loadItems()); // Reload after returning
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Tag Printing',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        actions: [
          if (_selectedItemIds.isNotEmpty)
            TextButton.icon(
              onPressed: _clearSelection,
              icon: const Icon(Icons.clear, size: 18),
              label: Text('Clear (${_selectedItemIds.length})'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search and Filter Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Column(
              children: [
                // Search Bar
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by name or barcode...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                    _applyFilters();
                  },
                ),
                const SizedBox(height: 12),
                // Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All', 'all'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Hallmark', 'hallmark'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Non-Hallmark', 'non-hallmark'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Not Printed', 'not-printed'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Items List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No items found',
                              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredItems.length,
                        padding: const EdgeInsets.all(8),
                        itemBuilder: (context, index) {
                          final item = _filteredItems[index];
                          final isSelected = _selectedItemIds.contains(item.id);
                          final hasHallmark = item.huid.isNotEmpty;

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            elevation: isSelected ? 4 : 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isSelected
                                    ? const Color(0xFFE94560)
                                    : Colors.grey[200]!,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: CheckboxListTile(
                              value: isSelected,
                              onChanged: (_) => _toggleSelection(item.id),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              title: Row(
                                children: [
                                  // Barcode
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item.barcode,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Item Name
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  children: [
                                    // Weight
                                    _buildInfoChip(
                                      '${item.netWeight}g',
                                      Icons.scale,
                                      Colors.blue,
                                    ),
                                    const SizedBox(width: 8),
                                    // Purity
                                    _buildInfoChip(
                                      item.purity,
                                      Icons.diamond,
                                      Colors.purple,
                                    ),
                                    const SizedBox(width: 8),
                                    // Hallmark Badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: hasHallmark
                                            ? const Color(0xFFFFD700).withOpacity(0.2)
                                            : const Color(0xFFADD8E6).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: hasHallmark
                                              ? const Color(0xFFFFD700)
                                              : const Color(0xFFADD8E6),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            hasHallmark ? Icons.verified : Icons.info_outline,
                                            size: 14,
                                            color: hasHallmark
                                                ? const Color(0xFFB8860B)
                                                : const Color(0xFF4682B4),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            hasHallmark ? 'Hallmark' : 'Non-HM',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: hasHallmark
                                                  ? const Color(0xFFB8860B)
                                                  : const Color(0xFF4682B4),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    // Tag Printed Status
                                    if (item.tagsPrinted)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green[50],
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.green),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.print,
                                              size: 12,
                                              color: Colors.green,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '×${item.tagPrintCount}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.green,
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
                        },
                      ),
          ),

          // Bottom Action Bar
          if (_selectedItemIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _selectAll,
                    icon: const Icon(Icons.select_all),
                    label: const Text('Select All'),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _navigateToPrintPreview,
                    icon: const Icon(Icons.print),
                    label: Text('Print ${_selectedItemIds.length} Tags'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE94560),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterType == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _filterType = value);
        _applyFilters();
      },
      selectedColor: const Color(0xFFE94560).withOpacity(0.2),
      checkmarkColor: const Color(0xFFE94560),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFFE94560) : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _buildInfoChip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
