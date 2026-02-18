import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../models/item_model.dart';
import '../models/container_model.dart';
import '../providers/container_provider.dart';
import '../services/api_service.dart';
import '../utils/container_tag_pdf_generator.dart';
import 'tag_print_preview_screen.dart';
import 'tag_settings_screen.dart';

class TagPrintingScreen extends StatefulWidget {
  const TagPrintingScreen({super.key});

  @override
  State<TagPrintingScreen> createState() => _TagPrintingScreenState();
}

class _TagPrintingScreenState extends State<TagPrintingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Tag Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TagSettingsScreen()),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFE94560),
          unselectedLabelColor: Colors.grey[600],
          indicatorColor: const Color(0xFFE94560),
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          tabs: const [
            Tab(icon: Icon(Icons.label_outline), text: 'Item Tags'),
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Container Tags'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ItemTagsTab(),
          _ContainerTagsTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1 — Item Tags (existing logic, extracted into its own widget)
// ─────────────────────────────────────────────────────────────────────────────

class _ItemTagsTab extends StatefulWidget {
  const _ItemTagsTab();

  @override
  State<_ItemTagsTab> createState() => _ItemTagsTabState();
}

class _ItemTagsTabState extends State<_ItemTagsTab>
    with AutomaticKeepAliveClientMixin {
  final ApiService _apiService = ApiService();
  List<Item> _allItems = [];
  List<Item> _filteredItems = [];
  Set<String> _selectedItemIds = {};
  bool _isLoading = true;
  bool _filtersExpanded = false;

  // Active filter values (null = no filter applied)
  String _searchQuery = '';
  String? _filterItemType;
  String? _filterMetalType;
  String? _filterPurity;
  String? _filterWeightCategory;
  String? _filterCertification;
  String? _filterPrintStatus; // 'printed' | 'not_printed'

  // Dynamic option lists built from loaded items
  List<String> _itemTypes = [];
  List<String> _metalTypes = [];
  List<String> _purities = [];
  List<String> _weightCategories = [];

  @override
  bool get wantKeepAlive => true;

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
        // Build dynamic filter options from data
        _itemTypes = items.map((i) => i.itemType).toSet()
            .where((s) => s.isNotEmpty).toList()..sort();
        _metalTypes = items.map((i) => i.metalType).toSet()
            .where((s) => s.isNotEmpty).toList()..sort();
        _purities = items.map((i) => i.purity).toSet()
            .where((s) => s.isNotEmpty).toList()..sort();
        _weightCategories = items.map((i) => i.weightCategory).toSet()
            .where((s) => s.isNotEmpty).toList()..sort();
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
        // Search
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          if (!item.name.toLowerCase().contains(q) &&
              !item.barcode.toLowerCase().contains(q)) return false;
        }
        // Item Type
        if (_filterItemType != null && item.itemType != _filterItemType) return false;
        // Metal Type
        if (_filterMetalType != null && item.metalType != _filterMetalType) return false;
        // Purity
        if (_filterPurity != null && item.purity != _filterPurity) return false;
        // Weight Category
        if (_filterWeightCategory != null && item.weightCategory != _filterWeightCategory) return false;
        // Certification
        if (_filterCertification != null) {
          if (_filterCertification == 'huid' && item.certificationType != 'huid') return false;
          if (_filterCertification == 'hallmarked' && item.certificationType != 'hallmarked') return false;
          if (_filterCertification == 'none' && item.certificationType != 'none') return false;
        }
        // Print status
        if (_filterPrintStatus == 'printed' && !item.tagsPrinted) return false;
        if (_filterPrintStatus == 'not_printed' && item.tagsPrinted) return false;
        return true;
      }).toList();
    });
  }

  void _resetFilters() {
    setState(() {
      _searchQuery = '';
      _filterItemType = null;
      _filterMetalType = null;
      _filterPurity = null;
      _filterWeightCategory = null;
      _filterCertification = null;
      _filterPrintStatus = null;
    });
    _applyFilters();
  }

  int get _activeFilterCount => [
    _filterItemType, _filterMetalType, _filterPurity,
    _filterWeightCategory, _filterCertification, _filterPrintStatus,
  ].where((f) => f != null).length;

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
    setState(() => _selectedItemIds.clear());
  }

  void _navigateToPrintPreview() {
    final selectedItems =
        _allItems.where((item) => _selectedItemIds.contains(item.id)).toList();

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
    ).then((_) => _loadItems());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // ── Search + Filter header ────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
          ),
          child: Column(
            children: [
              // Search row
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search by name or barcode...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                        ),
                        onChanged: (v) {
                          setState(() => _searchQuery = v);
                          _applyFilters();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Filter toggle button with badge
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          icon: Icon(
                            _filtersExpanded
                                ? Icons.filter_list_off
                                : Icons.filter_list,
                            color: _activeFilterCount > 0
                                ? const Color(0xFFE94560)
                                : Colors.grey[700],
                          ),
                          tooltip: 'Filters',
                          onPressed: () => setState(
                              () => _filtersExpanded = !_filtersExpanded),
                        ),
                        if (_activeFilterCount > 0)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE94560),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '$_activeFilterCount',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (_selectedItemIds.isNotEmpty)
                      TextButton(
                        onPressed: _clearSelection,
                        style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFE94560)),
                        child: Text('Clear (${_selectedItemIds.length})'),
                      ),
                  ],
                ),
              ),

              // Collapsible filter panel
              if (_filtersExpanded)
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      // Row 1: Item Type + Metal Type
                      Row(
                        children: [
                          Expanded(
                            child: _buildDropdown(
                              label: 'Item Type',
                              icon: Icons.category_outlined,
                              value: _filterItemType,
                              items: _itemTypes,
                              onChanged: (v) {
                                setState(() => _filterItemType = v);
                                _applyFilters();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildDropdown(
                              label: 'Metal',
                              icon: Icons.bolt_outlined,
                              value: _filterMetalType,
                              items: _metalTypes,
                              onChanged: (v) {
                                setState(() => _filterMetalType = v);
                                _applyFilters();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Row 2: Purity + Weight Category
                      Row(
                        children: [
                          Expanded(
                            child: _buildDropdown(
                              label: 'Purity',
                              icon: Icons.diamond_outlined,
                              value: _filterPurity,
                              items: _purities,
                              onChanged: (v) {
                                setState(() => _filterPurity = v);
                                _applyFilters();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildDropdown(
                              label: 'Weight Category',
                              icon: Icons.scale_outlined,
                              value: _filterWeightCategory,
                              items: _weightCategories,
                              onChanged: (v) {
                                setState(() => _filterWeightCategory = v);
                                _applyFilters();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Row 3: Certification + Print Status
                      Row(
                        children: [
                          Expanded(
                            child: _buildDropdown(
                              label: 'Certification',
                              icon: Icons.verified_outlined,
                              value: _filterCertification,
                              items: const ['huid', 'hallmarked', 'none'],
                              displayLabels: const {
                                'huid': 'HUID',
                                'hallmarked': 'Hallmarked',
                                'none': 'Non-Hallmarked',
                              },
                              onChanged: (v) {
                                setState(() => _filterCertification = v);
                                _applyFilters();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildDropdown(
                              label: 'Print Status',
                              icon: Icons.print_outlined,
                              value: _filterPrintStatus,
                              items: const ['printed', 'not_printed'],
                              displayLabels: const {
                                'printed': 'Printed',
                                'not_printed': 'Not Printed',
                              },
                              onChanged: (v) {
                                setState(() => _filterPrintStatus = v);
                                _applyFilters();
                              },
                            ),
                          ),
                        ],
                      ),
                      // Reset button
                      if (_activeFilterCount > 0) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _resetFilters,
                            icon: const Icon(Icons.restart_alt, size: 16),
                            label: const Text('Reset all filters'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey[600],
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              // Results count bar
              if (!_isLoading)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    border:
                        Border(bottom: BorderSide(color: Colors.grey[200]!)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${_filteredItems.length} item${_filteredItems.length == 1 ? '' : 's'}'
                        '${_activeFilterCount > 0 ? ' (filtered)' : ''}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600]),
                      ),
                      const Spacer(),
                      if (_filteredItems.isNotEmpty)
                        TextButton(
                          onPressed: _selectAll,
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFE94560),
                            textStyle: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Select All'),
                        ),
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
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredItems.length,
                      padding: const EdgeInsets.all(8),
                      itemBuilder: (context, index) {
                        final item = _filteredItems[index];
                        final isSelected =
                            _selectedItemIds.contains(item.id);
                        final hasHUID = item.certificationType == 'huid';

                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
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
                                horizontal: 12, vertical: 8),
                            title: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
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
                                Expanded(
                                  child: Text(
                                    item.name,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  _buildInfoChip(
                                      '${item.netWeight}g',
                                      Icons.scale,
                                      Colors.blue),
                                  const SizedBox(width: 8),
                                  _buildInfoChip(
                                      item.purity,
                                      Icons.diamond,
                                      Colors.purple),
                                  const SizedBox(width: 8),
                                  // Item type chip
                                  if (item.itemType.isNotEmpty)
                                    _buildInfoChip(
                                      item.itemType,
                                      Icons.style_outlined,
                                      Colors.teal,
                                    ),
                                  // HUID badge — only shown when certified
                                  if (hasHUID) ...[ 
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFD700)
                                            .withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                            color: const Color(0xFFFFD700)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.verified,
                                              size: 14,
                                              color: Color(0xFFB8860B)),
                                          SizedBox(width: 4),
                                          Text(
                                            'HUID',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFFB8860B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const Spacer(),
                                  if (item.tagsPrinted)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green[50],
                                        borderRadius:
                                            BorderRadius.circular(6),
                                        border:
                                            Border.all(color: Colors.green),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.print,
                                              size: 12,
                                              color: Colors.green),
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

        // ── Bottom Action Bar ─────────────────────────────────────────────
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
                Text(
                  '${_selectedItemIds.length} selected',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: _clearSelection,
                  child: const Text('Clear'),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _navigateToPrintPreview,
                  icon: const Icon(Icons.print),
                  label: Text('Print ${_selectedItemIds.length} Tags'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE94560),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Compact dropdown filter widget
  Widget _buildDropdown({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> items,
    Map<String, String>? displayLabels,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 12, color: Colors.grey[600]),
        prefixIcon: Icon(icon, size: 16, color: Colors.grey[500]),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE94560)),
        ),
      ),
      style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A1A)),
      hint: Text('All', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text('All')),
        ...items.map((v) => DropdownMenuItem<String>(
              value: v,
              child: Text(
                displayLabels?[v] ?? v,
                overflow: TextOverflow.ellipsis,
              ),
            )),
      ],
      onChanged: onChanged,
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

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2 — Container Tags (new)
// ─────────────────────────────────────────────────────────────────────────────

class _ContainerTagsTab extends StatefulWidget {
  const _ContainerTagsTab();

  @override
  State<_ContainerTagsTab> createState() => _ContainerTagsTabState();
}

class _ContainerTagsTabState extends State<_ContainerTagsTab>
    with AutomaticKeepAliveClientMixin {
  List<ItemContainer> _allContainers = [];
  List<ItemContainer> _filteredContainers = [];
  Set<String> _selectedIds = {};
  bool _isLoading = true;
  bool _isPrinting = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadContainers();
  }

  Future<void> _loadContainers() async {
    setState(() => _isLoading = true);
    try {
      final provider =
          Provider.of<ContainerProvider>(context, listen: false);
      await provider.fetchContainers();
      if (mounted) {
        setState(() {
          _allContainers =
              provider.containers.where((c) => !c.isDeleted).toList();
          _filteredContainers = List.from(_allContainers);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading containers: $e')),
        );
      }
    }
  }

  void _applySearch(String query) {
    setState(() {
      _filteredContainers = _allContainers.where((c) {
        final q = query.toLowerCase();
        return q.isEmpty ||
            c.name.toLowerCase().contains(q) ||
            (c.qrCode?.toLowerCase().contains(q) ?? false) ||
            c.type.toLowerCase().contains(q);
      }).toList();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds = _filteredContainers.map((c) => c.id).toSet();
    });
  }

  void _clearSelection() => setState(() => _selectedIds.clear());

  Future<void> _printTags() async {
    final selected = _allContainers
        .where((c) => _selectedIds.contains(c.id))
        .toList();

    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one container'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isPrinting = true);

    // Capture messenger before async gap to avoid use_build_context_synchronously
    final messenger = ScaffoldMessenger.of(context);

    try {
      final pdf = await ContainerTagPdfGenerator.generateTags(selected);
      final bytes = await pdf.save();

      if (mounted) {
        await Printing.sharePdf(
          bytes: bytes,
          filename:
              'container-tags-${DateTime.now().millisecondsSinceEpoch}.pdf',
        );
        messenger.showSnackBar(
          SnackBar(
            content: Text('✓ ${selected.length} container tags ready'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // ── Info banner ──────────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Select containers and print tags  •  Tag size: 1.5" × 0.5"',
                  style: TextStyle(color: Colors.blue[900], fontSize: 13),
                ),
              ),
            ],
          ),
        ),

        // ── Search bar ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search containers...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: _applySearch,
          ),
        ),

        // ── Container list ───────────────────────────────────────────────
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredContainers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No containers found',
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      itemCount: _filteredContainers.length,
                      itemBuilder: (context, index) {
                        final c = _filteredContainers[index];
                        final isSelected = _selectedIds.contains(c.id);
                        final code = c.qrCode?.isNotEmpty == true
                            ? c.qrCode!
                            : c.id.substring(0, 8);

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
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
                          child: InkWell(
                            onTap: () => _toggleSelection(c.id),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  // Checkbox
                                  Checkbox(
                                    value: isSelected,
                                    onChanged: (_) =>
                                        _toggleSelection(c.id),
                                    activeColor: const Color(0xFFE94560),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Container icon
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.grey[300]!),
                                    ),
                                    child: Icon(
                                      Icons.inventory_2_outlined,
                                      color: Colors.grey[600],
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Name + code
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c.name,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            // Code badge
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.black,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        5),
                                              ),
                                              child: Text(
                                                code,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight:
                                                      FontWeight.bold,
                                                  color: Colors.white,
                                                  fontFamily: 'monospace',
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // Type chip
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.grey[100],
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        5),
                                                border: Border.all(
                                                    color:
                                                        Colors.grey[300]!),
                                              ),
                                              child: Text(
                                                c.type,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey[700],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // Capacity
                                            Text(
                                              '${c.occupiedSlots}/${c.capacity} slots',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[500],
                                              ),
                                            ),
                                          ],
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

        // ── Bottom action bar ────────────────────────────────────────────
        if (_selectedIds.isNotEmpty || _filteredContainers.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Select All / Clear
                if (_selectedIds.isEmpty)
                  TextButton.icon(
                    onPressed: _selectAll,
                    icon: const Icon(Icons.select_all, size: 18),
                    label: const Text('Select All'),
                  )
                else
                  TextButton.icon(
                    onPressed: _clearSelection,
                    icon: const Icon(Icons.clear, size: 18),
                    label: Text('Clear (${_selectedIds.length})'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey[700],
                    ),
                  ),
                const Spacer(),
                // Print button
                if (_selectedIds.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: _isPrinting ? null : _printTags,
                    icon: _isPrinting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.print),
                    label: Text(
                      _isPrinting
                          ? 'Generating...'
                          : 'Print ${_selectedIds.length} Tags',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE94560),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
