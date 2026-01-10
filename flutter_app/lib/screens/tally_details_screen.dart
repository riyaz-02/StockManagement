import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/tally_provider.dart';
import '../models/tally_model.dart';
import '../services/api_service.dart';
import 'live_scanner_screen.dart';
import '../utils/app_colors.dart';
import '../utils/app_constants.dart';
import 'package:intl/intl.dart';

class TallyDetailsScreen extends StatefulWidget {
  final String tallyId;

  const TallyDetailsScreen({super.key, required this.tallyId});

  @override
  State<TallyDetailsScreen> createState() => _TallyDetailsScreenState();
}

class _TallyDetailsScreenState extends State<TallyDetailsScreen> {
  TallySession? _tally;
  bool _isLoading = true;
  bool _isItemsExpanded = false;
  String _selectedFilter = 'All';
  final _barcodeController = TextEditingController();
  final _focusNode = FocusNode();
  
  // Dynamic metal types
  List<String> _metalTypes = [];

  @override
  void initState() {
    super.initState();
    _loadMetalTypesAndTally();
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadMetalTypesAndTally() async {
    setState(() => _isLoading = true);
    
    try {
      final apiService = ApiService();
      
      // Fetch metal types from settings
      final settingsResponse = await apiService.getSettings('item');
      if (settingsResponse['success'] == true) {
        final Map<String, dynamic> settingsData = settingsResponse['data'] ?? {};
        
        // Check if metalTypes exists in the map
        if (settingsData.containsKey('metalTypes')) {
          final List<dynamic> values = settingsData['metalTypes'] ?? [];
          _metalTypes = values.map((v) => v.toString().trim()).toList();
        }
      }

      // If no metal types found, use defaults
      if (_metalTypes.isEmpty) {
        _metalTypes = ['gold', 'silver'];
      }
      
      // Load tally data
      await _loadTally();
    } catch (e) {
      print('Error loading metal types: $e');
      _metalTypes = ['Gold', 'Silver'];
      await _loadTally();
    }
  }

  Future<void> _loadTally() async {
    setState(() => _isLoading = true);
    final tallyProvider = Provider.of<TallyProvider>(context, listen: false);
    final tally = await tallyProvider.fetchTallySession(widget.tallyId);
    setState(() {
      _tally = tally;
      _isLoading = false;
    });
    
    // Log to verify data is loaded
    print('[TALLY DETAILS] Loaded tally: ${_tally?.scannedItemsCount}/${_tally?.expectedItems}');
    print('[TALLY DETAILS] Gold: ${_tally?.scannedGoldWeight}g, Silver: ${_tally?.scannedSilverWeight}g');
    print('[TALLY DETAILS] MetalData count: ${_tally?.metalData?.length}');
    if (_tally?.metalData != null && _tally!.metalData.isNotEmpty) {
      for (var md in _tally!.metalData) {
        print('[TALLY DETAILS]   ${md.metalType}: ${md.scannedWeight}/${md.expectedWeight}g');
      }
    }
  }

  Future<void> _processScan(String barcode) async {
    if (barcode.isEmpty) return;

    final tallyProvider = Provider.of<TallyProvider>(context, listen: false);
    final result = await tallyProvider.scanItem(widget.tallyId, barcode);

    if (mounted) {
      if (result != null) {
        final isOutOfStock = result['isOutOfStock'] ?? false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isOutOfStock ? '⚠️ Out of stock - weight excluded' : '✓ Item scanned',
            ),
            backgroundColor: isOutOfStock ? Colors.orange : Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
        _barcodeController.clear();
        _focusNode.requestFocus();
        await _loadTally();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tallyProvider.error ?? 'Scan failed'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _lockTally() async {
    if (_tally == null) return;

    final itemsLeft = _tally!.itemsLeft;
    String? remarks;

    if (itemsLeft > 0) {
      final result = await showDialog<String>(
        context: context,
        builder: (context) => _buildForceLockDialog(itemsLeft),
      );
      
      if (result == null) return;
      remarks = result;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Lock Tally?'),
          content: const Text('All items scanned. Lock this tally?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Lock'),
            ),
          ],
        ),
      );
      
      if (confirmed != true) return;
    }

    final tallyProvider = Provider.of<TallyProvider>(context, listen: false);
    final success = await tallyProvider.lockTally(widget.tallyId, remarks: remarks);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tally locked successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tallyProvider.error ?? 'Failed to lock'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildForceLockDialog(int itemsLeft) {
    final remarksController = TextEditingController();
    
    return AlertDialog(
      title: const Text('Force Lock'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$itemsLeft items not scanned',
            style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: remarksController,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Remarks (required)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (remarksController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Remarks required')),
              );
              return;
            }
            Navigator.pop(context, remarksController.text.trim());
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          child: const Text('Force Lock'),
        ),
      ],
    );
  }


  Future<void> _openFullScreenScanner() async {
    if (_tally?.isLocked ?? true) return;

    print('[TALLY DETAILS] Opening scanner...');
    
    // Navigate to live scanner screen
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LiveScannerScreen(tallyId: widget.tallyId),
        fullscreenDialog: true,
      ),
    );

    // Reload tally after scanner closes to update all data
    print('[TALLY DETAILS] Scanner closed, reloading tally...');
    if (mounted) {
      await _loadTally();
      print('[TALLY DETAILS] Tally reloaded, forcing UI rebuild');
      // Force rebuild to show updated data
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          title: const Text('Loading...'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_tally == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: const Center(child: Text('Tally not found')),
      );
    }

    final isLocked = _tally!.isLocked;
    final progress = _tally!.progress / 100;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _tally!.description,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            Text(
              DateFormat('dd MMM yyyy').format(_tally!.date),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          _buildStatusChip(_tally!.status),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          // STICKY STATUS ROW
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                // Scanned vs Left
                Row(
                  children: [
                    Expanded(
                      child: _buildBigStat(
                        '${_tally!.scannedItemsCount}',
                        'Scanned',
                        Colors.green,
                      ),
                    ),
                    Expanded(
                      child: _buildBigStat(
                        '${_tally!.itemsLeft}',
                        'Left',
                        Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progress >= 0.8 ? Colors.green : (progress >= 0.4 ? Colors.orange : Colors.red),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // SCAN/TYPE INPUT SECTION
          if (!isLocked)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _barcodeController,
                focusNode: _focusNode,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: '🔍 Tap to Scan / Type Barcode',
                  hintStyle: const TextStyle(fontSize: 13),
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner, size: 20),
                    onPressed: _openFullScreenScanner,
                  ),
                ),
                onTap: _openFullScreenScanner,
                readOnly: true,
                onSubmitted: _processScan,
              ),
            ),

          // SCROLLABLE CONTENT
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // METAL SUMMARY CARDS (DYNAMIC)
                  _buildMetalCards(),
                  const SizedBox(height: 8),

                  // COLLAPSIBLE ITEM CONTAINER
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        // Header
                        InkWell(
                          onTap: () => setState(() => _isItemsExpanded = !_isItemsExpanded),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(
                                  _isItemsExpanded ? Icons.expand_less : Icons.expand_more,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Items',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'Tap to ${_isItemsExpanded ? 'Collapse' : 'Expand'}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        // Expanded Content
                        if (_isItemsExpanded) ...[
                          const Divider(height: 1),
                          _buildItemsList(),
                        ],
                      ],
                    ),
                  ),

                  // Lock Info (if locked)
                  if (isLocked) ...[
                    const SizedBox(height: 8),
                    _buildLockInfo(),
                  ],
                ],
              ),
            ),
          ),

          // BOTTOM BUTTONS
          if (!isLocked)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: Column(
                children: [
                  // START SCANNING (PRIMARY)
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _openFullScreenScanner,
                      icon: const Icon(Icons.qr_code_scanner, size: 24),
                      label: const Text(
                        'START SCANNING',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // LOCK TALLY
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: _lockTally,
                      icon: const Icon(Icons.lock, size: 18),
                      label: const Text(
                        'LOCK TALLY',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
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

  Widget _buildStatusChip(String status) {
    Color color;
    IconData icon;
    String label;

    switch (status) {
      case 'active':
        color = Colors.green;
        icon = Icons.play_circle_outline;
        label = 'Active';
        break;
      case 'locked':
        color = Colors.blue;
        icon = Icons.lock_outline;
        label = 'Locked';
        break;
      case 'force_locked':
        color = Colors.orange;
        icon = Icons.lock_clock;
        label = 'Force Locked';
        break;
      default:
        color = Colors.grey;
        icon = Icons.help_outline;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBigStat(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: color,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildMetalCards() {
    // Build cards from metalData array
    List<Widget> cards = [];
    
    // If metalData is available, use it; otherwise fall back to legacy fields
    if (_tally!.metalData.isNotEmpty) {
      for (var metalData in _tally!.metalData) {
        cards.add(
          SizedBox(
            width: (MediaQuery.of(context).size.width - 32) / 2 - 4,
            child: _buildMetalCard(
              metalData.metalType,
              metalData.scannedWeight,
              metalData.expectedWeight,
              _getMetalColor(metalData.metalType),
              _getMetalIcon(metalData.metalType),
            ),
          ),
        );
      }
    } else {
      // Fallback to legacy gold/silver display
      for (var metal in _metalTypes) {
        final scanned = _getMetalWeight(metal, true);
        final expected = _getMetalWeight(metal, false);
        
        cards.add(
          SizedBox(
            width: (MediaQuery.of(context).size.width - 32) / 2 - 4,
            child: _buildMetalCard(
              metal,
              scanned,
              expected,
              _getMetalColor(metal),
              _getMetalIcon(metal),
            ),
          ),
        );
      }
    }
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: cards,
    );
  }
  
  double _getMetalWeight(String metal, bool scanned) {
    // Legacy fallback - only used if metalData is not available
    if (metal.toLowerCase() == 'gold') {
      return scanned ? _tally!.scannedGoldWeight : _tally!.expectedGoldWeight;
    } else if (metal.toLowerCase() == 'silver') {
      return scanned ? _tally!.scannedSilverWeight : _tally!.expectedSilverWeight;
    }
    return 0.0;
  }
  
  Color _getMetalColor(String metal) {
    switch (metal.toLowerCase()) {
      case 'gold':
        return Colors.amber;
      case 'silver':
        return Colors.grey;
      case 'platinum':
        return Colors.blueGrey;
      case 'mixed':
        return Colors.purple;
      default:
        return AppColors.primary;
    }
  }
  
  IconData _getMetalIcon(String metal) {
    switch (metal.toLowerCase()) {
      case 'gold':
        return Icons.diamond_outlined;
      case 'silver':
        return Icons.circle_outlined;
      case 'platinum':
        return Icons.stars_outlined;
      case 'mixed':
        return Icons.merge_outlined;
      default:
        return Icons.category_outlined;
    }
  }

  Widget _buildMetalCard(
    String label,
    double scanned,
    double expected,
    Color color,
    IconData icon,
  ) {
    final diff = expected - scanned;
    final diffColor = diff.abs() < 0.01 ? Colors.green : Colors.red;
    
    // Capitalize first letter for display
    final displayName = label[0].toUpperCase() + label.substring(1);
    
    // Get item counts from metalData
    int scannedItemCount = 0;
    int expectedItemCount = 0;
    
    if (_tally!.metalData.isNotEmpty) {
      final metalData = _tally!.metalData.firstWhere(
        (m) => m.metalType.toLowerCase() == label.toLowerCase(),
        orElse: () => MetalData(metalType: label, expectedWeight: 0, expectedItemCount: 0),
      );
      scannedItemCount = metalData.scannedItemCount;
      expectedItemCount = metalData.expectedItemCount;
    }

    return Container(
      height: 85, // Fixed height for uniformity
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header: Icon + Name
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                displayName,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          
          // Weight: Scanned / Expected
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                scanned.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                ' / ${expected.toStringAsFixed(1)}g',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          
          // Items: Scanned / Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Items: $scannedItemCount/$expectedItemCount',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (diff.abs() > 0.01)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: diffColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '${diff > 0 ? '-' : '+'}${diff.abs().toStringAsFixed(1)}g',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: diffColor,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList() {
    if (_tally!.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'No items in this tally',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    }
    
    // Filter items based on selected filter
    List<TallyItem> filteredItems = _tally!.items;
    
    if (_selectedFilter == 'Scanned') {
      filteredItems = filteredItems.where((i) => i.isScanned).toList();
    } else if (_selectedFilter == 'Not Scanned') {
      filteredItems = filteredItems.where((i) => !i.isScanned).toList();
    } else if (_selectedFilter == 'Out of Stock') {
      filteredItems = filteredItems.where((i) => i.status == 'out_of_stock').toList();
    } else if (_selectedFilter != 'All') {
      // Filter by metal type
      filteredItems = filteredItems.where((i) => 
        i.metalType.toLowerCase() == _selectedFilter.toLowerCase()
      ).toList();
    }
    
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All'),
                _buildFilterChip('Scanned'),
                _buildFilterChip('Not Scanned'),
                _buildFilterChip('Out of Stock'),
                // Add metal type filters from metalData
                ..._tally!.metalData.map((m) => _buildFilterChip(
                  m.metalType[0].toUpperCase() + m.metalType.substring(1)
                )),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Items count
          Text(
            '${filteredItems.length} items',
            style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          // Items list
          ...filteredItems.map((item) => _buildItemRow(item)),
        ],
      ),
    );
  }
  
  Widget _buildItemRow(TallyItem item) {
    final metalColor = _getMetalColor(item.metalType);
    
    return InkWell(
      onTap: () => _showItemDetails(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: item.isScanned ? Colors.green.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: item.isScanned ? Colors.green.withOpacity(0.3) : Colors.grey[300]!,
          ),
        ),
        child: Row(
          children: [
            // Status icon
            Icon(
              item.isScanned ? Icons.check_circle : Icons.circle_outlined,
              size: 16,
              color: item.isScanned ? Colors.green : Colors.grey[400],
            ),
            const SizedBox(width: 8),
            // Barcode
            Expanded(
              flex: 2,
              child: Text(
                item.barcode,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            // Metal type
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: metalColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                item.metalType[0].toUpperCase() + item.metalType.substring(1),
                style: TextStyle(fontSize: 10, color: metalColor, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            // Weight
            Text(
              '${item.weight.toStringAsFixed(1)}g',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
  
  Future<void> _showItemDetails(TallyItem item) async {
    print('=== SHOW ITEM DETAILS ===');
    print('Item ID: ${item.itemId}');
    print('Barcode: ${item.barcode}');
    
    // Fetch full item details from API
    final apiService = ApiService();
    
    try {
      print('Fetching item details from API...');
      final response = await apiService.getItemById(item.itemId);
      
      print('API Response:');
      print('  success: ${response['success']}');
      print('  data type: ${response['data']?.runtimeType}');
      print('  data: ${response['data']}');
      
      if (response['success'] != true) {
        print('ERROR: API returned success = false');
        print('  message: ${response['message']}');
        return;
      }
      
      if (!mounted) {
        print('ERROR: Widget not mounted');
        return;
      }
      
      // IMPORTANT: Item data is nested inside 'item' key
      final itemData = response['data']['item'];
      print('Item Data Fields:');
      print('  barcode: ${itemData['barcode']}');
      print('  name: ${itemData['name']}');
      print('  description: ${itemData['description']}');
      print('  metalType: ${itemData['metalType']}');
      print('  purity: ${itemData['purity']}');
      print('  netWeight: ${itemData['netWeight']}');
      print('  itemType: ${itemData['itemType']}');
      print('  images: ${itemData['images']}');
      print('  containerId: ${itemData['containerId']}');
      print('  slotNumber: ${itemData['slotNumber']}');
      print('  huid: ${itemData['huid']}');
      print('  numberOfPieces: ${itemData['numberOfPieces']}');
      print('  status: ${itemData['status']}');
      
      if (itemData['images'] != null) {
        final images = itemData['images'] as List;
        print('Images array length: ${images.length}');
        if (images.isNotEmpty) {
          print('First image path: ${images[0]}');
          print('Full image URL: ${AppConstants.baseUrl}/${images[0]}');
        }
      }
      
      print('Opening modal...');
      
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: true,
        enableDrag: true,
        builder: (context) {
          print('Building modal sheet...');
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: GestureDetector(
              onTap: () {}, // Prevent taps on the sheet from closing it
              child: DraggableScrollableSheet(
                initialChildSize: 0.7,
                minChildSize: 0.5,
                maxChildSize: 0.95,
                builder: (context, scrollController) => Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Content
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Header with barcode and status
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Item Details',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // Barcode and Status in same row
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.grey[300]!),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.qr_code, size: 14, color: Colors.grey[700]),
                                          const SizedBox(width: 4),
                                          Text(
                                            item.barcode,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey[800],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Status badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: itemData['status'] == 'active' ? Colors.green : Colors.grey,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        itemData['status']?.toString().toUpperCase() ?? 'UNKNOWN',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Scan status badge (right side)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: item.isScanned ? Colors.green : Colors.orange,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  item.isScanned ? Icons.check_circle : Icons.pending,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  item.isScanned ? 'Scanned' : 'Not Scanned',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                        const SizedBox(height: 10),
                        
                        // Split Image Area - Item Image (Left) + Container Image (Right) - No labels
                        Row(
                          children: [
                            // Item Image (Left)
                            Expanded(
                              child: itemData['images'] != null && (itemData['images'] as List).isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        '${AppConstants.baseUrl}/${itemData['images'][0]}',
                                        height: 110,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return Container(
                                            height: 110,
                                            color: Colors.grey[200],
                                            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            height: 110,
                                            decoration: BoxDecoration(
                                              color: Colors.grey[200],
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.image_not_supported, size: 28, color: Colors.grey[400]),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'No image',
                                                  style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    )
                                  : Container(
                                      height: 110,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.image, size: 28, color: Colors.grey[400]),
                                          const SizedBox(height: 4),
                                          Text(
                                            'No image',
                                            style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 10),
                            // Container Image (Right)
                            Expanded(
                              child: itemData['containerId'] != null && 
                                     itemData['containerId']['image'] != null && 
                                     itemData['containerId']['image'].toString().isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        '${AppConstants.baseUrl}${itemData['containerId']['image']}',
                                        height: 110,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return Container(
                                            height: 110,
                                            color: Colors.grey[200],
                                            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            height: 110,
                                            decoration: BoxDecoration(
                                              color: Colors.grey[200],
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.inventory_2, size: 28, color: Colors.grey[400]),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'No image',
                                                  style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    )
                                  : Container(
                                      height: 110,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.inventory_2, size: 28, color: Colors.grey[400]),
                                          const SizedBox(height: 4),
                                          Text(
                                            'No image',
                                            style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        
                        // Location (IMPORTANT) - Container info is already in response
                        if (itemData['containerId'] != null)
                          Container(
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.location_on, color: AppColors.primary, size: 16),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Location',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        itemData['containerId']['name'] ?? 'Unknown',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      if (itemData['slotNumber'] != null)
                                        Text(
                                          'Slot ${itemData['slotNumber']}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        
                        // Details Grid - Ultra compact
                        if (itemData['name'] != null && itemData['name'].toString().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 80,
                                  child: Text(
                                    'Name',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    itemData['name'],
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        
                        // Row 1: Metal Type + Purity
                        Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildCompactDetail('Metal Type', item.metalType[0].toUpperCase() + item.metalType.substring(1)),
                              ),
                              Container(
                                width: 1,
                                height: 26,
                                color: Colors.grey[300],
                              ),
                              Expanded(
                                child: _buildCompactDetail('Purity', itemData['purity'] ?? '-'),
                              ),
                            ],
                          ),
                        ),
                        
                        // Row 2: Net Weight (Highlighted) + Item Type
                        Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Net Weight',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${itemData['netWeight']?.toStringAsFixed(3) ?? '0'}g',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 26,
                                color: Colors.grey[300],
                              ),
                              Expanded(
                                child: _buildCompactDetail('Item Type', itemData['itemType'] ?? '-'),
                              ),
                            ],
                          ),
                        ),
                        
                        // Row 3: Weight Category + Pieces (if available)
                        if (itemData['weightCategory'] != null || itemData['numberOfPieces'] != null)
                          Container(
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: itemData['weightCategory'] != null && itemData['weightCategory'].toString().isNotEmpty
                                      ? _buildCompactDetail('Weight Category', itemData['weightCategory'])
                                      : const SizedBox.shrink(),
                                ),
                                if (itemData['weightCategory'] != null && itemData['numberOfPieces'] != null)
                                  Container(
                                    width: 1,
                                    height: 26,
                                    color: Colors.grey[300],
                                  ),
                                Expanded(
                                  child: itemData['numberOfPieces'] != null
                                      ? _buildCompactDetail('Pieces', itemData['numberOfPieces'].toString())
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ),
                        
                        // Row 4: HUID (if available)
                        if (itemData['huid'] != null && itemData['huid'].toString().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 80,
                                  child: Text(
                                    'HUID',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    itemData['huid'],
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        
                        const SizedBox(height: 10),
                        
                        // Close button
                        SizedBox(
                          width: double.infinity,
                          height: 45,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Close',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
            ),
          );
        },
      );
    } catch (e, stackTrace) {
      print('=== ERROR IN _showItemDetails ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load item details: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<String?> _getContainerName(dynamic containerId) async {
    print('=== GET CONTAINER NAME ===');
    print('Container ID: $containerId');
    print('Container ID type: ${containerId?.runtimeType}');
    
    if (containerId == null) {
      print('Container ID is null');
      return null;
    }
    
    try {
      final apiService = ApiService();
      
      // Handle different ID formats
      String? id;
      if (containerId is String) {
        id = containerId;
      } else if (containerId is Map) {
        id = containerId['\$oid'] ?? containerId['_id'];
      }
      
      print('Extracted ID: $id');
      
      if (id == null) {
        print('Could not extract ID from containerId');
        return 'Unknown Location';
      }
      
      print('Fetching container with ID: $id');
      final response = await apiService.getContainer(id);
      
      print('Container API Response:');
      print('  success: ${response['success']}');
      print('  data: ${response['data']}');
      
      if (response['success'] == true) {
        final containerName = response['data']['name'];
        print('Container name: $containerName');
        return containerName;
      }
    } catch (e, stackTrace) {
      print('ERROR fetching container: $e');
      print('Stack trace: $stackTrace');
    }
    return 'Unknown Location';
  }
  
  Future<String?> _getContainerImage(dynamic containerId) async {
    if (containerId == null) return null;
    
    try {
      final apiService = ApiService();
      
      // Handle different ID formats
      String? id;
      if (containerId is String) {
        id = containerId;
      } else if (containerId is Map) {
        id = containerId['\$oid'] ?? containerId['_id'];
      }
      
      if (id == null) return null;
      
      final response = await apiService.getContainer(id);
      
      if (response['success'] == true && response['data']['image'] != null) {
        return response['data']['image'];
      }
    } catch (e) {
      print('Error fetching container image: $e');
    }
    return null;
  }
  
  Widget _buildCompactDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppColors.primary : Colors.grey[700],
          ),
        ),
        selected: isSelected,
        onSelected: (selected) {
          setState(() => _selectedFilter = label);
        },
        selectedColor: AppColors.primary.withOpacity(0.2),
        showCheckmark: false, // Remove checkmark
        backgroundColor: Colors.white,
        side: BorderSide(
          color: isSelected ? AppColors.primary : Colors.grey[300]!,
          width: isSelected ? 1.5 : 1,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildLockInfo() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock, color: Colors.blue, size: 14),
              const SizedBox(width: 6),
              const Text(
                'Tally Locked',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          if (_tally!.lockedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              DateFormat('dd MMM yyyy, HH:mm').format(_tally!.lockedAt!),
              style: TextStyle(fontSize: 10, color: Colors.grey[700]),
            ),
          ],
          if (_tally!.lockedByName != null)
            Text(
              'By ${_tally!.lockedByName}',
              style: TextStyle(fontSize: 10, color: Colors.grey[700]),
            ),
          if (_tally!.isForceLocked && _tally!.lockRemarks != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Remarks:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _tally!.lockRemarks!,
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
