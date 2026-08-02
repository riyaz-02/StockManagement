import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/tally_provider.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';

class CreateTallyScreen extends StatefulWidget {
  const CreateTallyScreen({super.key});

  @override
  State<CreateTallyScreen> createState() => _CreateTallyScreenState();
}

class _CreateTallyScreenState extends State<CreateTallyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _expectedItemsController = TextEditingController();
  final _expectedContainersController = TextEditingController();
  
  DateTime _selectedDate = DateTime.now();
  bool _isCalculating = false;
  bool _hasCalculated = false;
  
  // Dynamic metal types with weight and count
  List<String> _metalTypes = [];
  Map<String, TextEditingController> _metalWeightControllers = {};
  Map<String, TextEditingController> _metalItemControllers = {};
  Map<String, bool> _metalEditable = {};
  
  // Track which fields are editable
  bool _itemsEditable = false;
  bool _containersEditable = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasCalculated) {
      _hasCalculated = true;
      _loadMetalTypesAndCalculate();
    }
  }

  Future<void> _loadMetalTypesAndCalculate() async {
    setState(() => _isCalculating = true);

    try {
      final apiService = ApiService();
      
      // Fetch metal types from settings
      print('=== FETCHING METAL TYPES ===');
      final settingsResponse = await apiService.getSettings('item');
      print('Settings API Response:');
      print('  success: ${settingsResponse['success']}');
      print('  data type: ${settingsResponse['data'].runtimeType}');
      print('  data: ${settingsResponse['data']}');
      
      if (settingsResponse['success'] == true) {
        final Map<String, dynamic> settingsData = settingsResponse['data'] ?? {};
        print('  settings keys: ${settingsData.keys.toList()}');
        
        // Check if metalTypes exists in the map
        if (settingsData.containsKey('metalTypes')) {
          final List<dynamic> values = settingsData['metalTypes'] ?? [];
          _metalTypes = values.map((v) => v.toString().trim()).toList();
          print('  ✓ FOUND metalTypes: $_metalTypes');
        } else {
          print('  ⚠ metalTypes key not found in settings data');
        }
      }

      // If no metal types found, use defaults
      if (_metalTypes.isEmpty) {
        print('  ⚠ No metal types found in settings, using defaults');
        _metalTypes = ['gold', 'silver'];
      } else {
        print('  ✓ Using metal types from database: $_metalTypes');
      }

      // Create controllers for each metal type
      for (var metal in _metalTypes) {
        _metalWeightControllers[metal] = TextEditingController();
        _metalItemControllers[metal] = TextEditingController();
        _metalEditable[metal] = false;
      }

      // Fetch all items that are physically in the rack
      final response = await apiService.getItems(queryParams: {'status': 'active,action_needed,in_stock,booked,wishlisted'});

      if (response['success'] == true) {
        final List<dynamic> items = response['data']['items'] ?? [];
        
        print('[CREATE TALLY] Fetched ${items.length} items for tally');
        
        // Calculate totals
        int totalItems = items.length;
        Map<String, double> metalWeights = {};
        Map<String, int> metalItemCounts = {};
        Set<String> uniqueContainers = {};

        // Initialize metal weights and counts
        for (var metal in _metalTypes) {
          metalWeights[metal] = 0.0;
          metalItemCounts[metal] = 0;
        }

        for (var item in items) {
          final metalType = (item['metalType'] ?? '').toString();
          final weight = (item['netWeight'] ?? 0).toDouble();
          
          // Add weight and count to corresponding metal type
          if (metalWeights.containsKey(metalType)) {
            metalWeights[metalType] = (metalWeights[metalType] ?? 0) + weight;
            metalItemCounts[metalType] = (metalItemCounts[metalType] ?? 0) + 1;
          }

          // Track unique containers
          if (item['containerId'] != null) {
            uniqueContainers.add(item['containerId'].toString());
          }
        }

        // Count all containers (not just unique from items)
        final containersResponse = await apiService.getContainers();
        int totalContainers = 0;
        if (containersResponse['success'] == true) {
          final containerData = containersResponse['data'];
          if (containerData is List) {
            totalContainers = containerData.length;
          } else if (containerData is Map && containerData.containsKey('containers')) {
            totalContainers = (containerData['containers'] as List).length;
          }
        }

        // Pre-fill the form
        if (mounted) {
          setState(() {
            _expectedItemsController.text = totalItems.toString();
            _expectedContainersController.text = totalContainers.toString();
            
            // Fill metal weights and counts
            for (var metal in _metalTypes) {
              _metalWeightControllers[metal]?.text = (metalWeights[metal] ?? 0).toStringAsFixed(3);
              _metalItemControllers[metal]?.text = (metalItemCounts[metal] ?? 0).toString();
            }
          });
        }
      }
    } catch (e) {
      print('Error loading data: $e');
      // Ensure defaults are set even on error
      if (_metalTypes.isEmpty) {
        _metalTypes = ['Gold', 'Silver'];
        for (var metal in _metalTypes) {
          _metalWeightControllers[metal] = TextEditingController(text: '0.000');
          _metalItemControllers[metal] = TextEditingController(text: '0');
          _metalEditable[metal] = false;
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isCalculating = false);
      }
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _expectedItemsController.dispose();
    _expectedContainersController.dispose();
    for (var controller in _metalWeightControllers.values) {
      controller.dispose();
    }
    for (var controller in _metalItemControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _createTally() async {
    if (!_formKey.currentState!.validate()) return;

    final tallyProvider = Provider.of<TallyProvider>(context, listen: false);

    // Prepare metalData array for all metal types
    List<Map<String, dynamic>> metalDataArray = [];
    
    for (var metal in _metalTypes) {
      final weight = double.tryParse(_metalWeightControllers[metal]?.text ?? '0') ?? 0.0;
      final itemCount = int.tryParse(_metalItemControllers[metal]?.text ?? '0') ?? 0;
      
      metalDataArray.add({
        'metalType': metal.toLowerCase(),
        'expectedWeight': weight,
        'expectedItemCount': itemCount,
        'scannedWeight': 0.0,
        'scannedItemCount': 0
      });
    }

    // Find Gold and Silver for legacy fields
    double goldWeight = 0.0;
    double silverWeight = 0.0;
    
    for (var metal in _metalTypes) {
      if (metal.toLowerCase() == 'gold') {
        goldWeight = double.tryParse(_metalWeightControllers[metal]?.text ?? '0') ?? 0.0;
      } else if (metal.toLowerCase() == 'silver') {
        silverWeight = double.tryParse(_metalWeightControllers[metal]?.text ?? '0') ?? 0.0;
      }
    }

    final tally = await tallyProvider.createTally(
      date: _selectedDate,
      description: _descriptionController.text,
      expectedItems: int.parse(_expectedItemsController.text),
      expectedContainers: int.parse(_expectedContainersController.text),
      expectedGoldWeight: goldWeight,
      expectedSilverWeight: silverWeight,
      metalData: metalDataArray, // NEW: Send metal data array
    );

    if (mounted) {
      if (tally != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tally created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tallyProvider.error ?? 'Failed to create tally'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Create Tally',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: _isCalculating
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Row 1: Date
                  _buildDateRow(),
                  const SizedBox(height: 12),

                  // Row 2: Description
                  _buildDescriptionRow(),
                  const SizedBox(height: 12),

                  // Row 3: Containers & Items
                  _buildContainersItemsRow(),
                  const SizedBox(height: 12),

                  // Row 4+: Metal Types (dynamic)
                  ..._buildMetalRows(),
                  const SizedBox(height: 20),

                  // Create Button
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _createTally,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text(
                        'START TALLY',
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
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDateRow() {
    return InkWell(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (date != null) {
          setState(() => _selectedDate = date);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: AppColors.primary, size: 20),
            const SizedBox(width: 12),
            const Text(
              'Date:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Text(
              '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionRow() {
    return TextFormField(
      controller: _descriptionController,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: 'Description',
        hintText: 'e.g., Monthly Stock Audit',
        labelStyle: const TextStyle(fontSize: 13),
        hintStyle: const TextStyle(fontSize: 12),
        prefixIcon: const Icon(Icons.description_outlined, color: AppColors.primary, size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
    );
  }

  Widget _buildContainersItemsRow() {
    return Row(
      children: [
        // Containers
        Expanded(
          child: TextFormField(
            controller: _expectedContainersController,
            readOnly: !_containersEditable,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onTap: _containersEditable ? null : () {
              FocusScope.of(context).unfocus();
              _showContainersModal();
            },
            style: TextStyle(
              fontSize: 14,
              color: _containersEditable ? Colors.black : Colors.grey[700],
            ),
            decoration: InputDecoration(
              labelText: 'Containers',
              labelStyle: const TextStyle(fontSize: 13),
              prefixIcon: const Icon(Icons.inbox_outlined, color: AppColors.primary, size: 20),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_containersEditable)
                    IconButton(
                      icon: const Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                      onPressed: () => _showContainersModal(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  if (_containersEditable)
                    Icon(Icons.edit, size: 16, color: Colors.grey[400])
                  else
                    GestureDetector(
                      onDoubleTap: () => setState(() => _containersEditable = true),
                      child: Icon(Icons.lock_outline, size: 16, color: Colors.grey[400]),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
              filled: true,
              fillColor: _containersEditable ? Colors.white : Colors.grey[50],
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              floatingLabelBehavior: FloatingLabelBehavior.auto,
            ),
            validator: (value) {
              if (value?.isEmpty ?? true) return 'Required';
              if (int.tryParse(value!) == null) return 'Invalid';
              return null;
            },
          ),
        ),
        const SizedBox(width: 12),
        // Items
        Expanded(
          child: TextFormField(
            controller: _expectedItemsController,
            readOnly: !_itemsEditable,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onTap: _itemsEditable ? null : () {
              FocusScope.of(context).unfocus();
              _showItemsModal();
            },
            style: TextStyle(
              fontSize: 14,
              color: _itemsEditable ? Colors.black : Colors.grey[700],
            ),
            decoration: InputDecoration(
              labelText: 'Items',
              labelStyle: const TextStyle(fontSize: 13),
              prefixIcon: const Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 20),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_itemsEditable)
                    IconButton(
                      icon: const Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                      onPressed: () => _showItemsModal(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  if (_itemsEditable)
                    Icon(Icons.edit, size: 16, color: Colors.grey[400])
                  else
                    GestureDetector(
                      onDoubleTap: () => setState(() => _itemsEditable = true),
                      child: Icon(Icons.lock_outline, size: 16, color: Colors.grey[400]),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
              filled: true,
              fillColor: _itemsEditable ? Colors.white : Colors.grey[50],
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              floatingLabelBehavior: FloatingLabelBehavior.auto,
            ),
            validator: (value) {
              if (value?.isEmpty ?? true) return 'Required';
              if (int.tryParse(value!) == null) return 'Invalid';
              return null;
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _buildMetalRows() {
    return _metalTypes.map((metal) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _buildMetalRow(metal),
    )).toList();
  }

  Widget _buildMetalRow(String metal) {
    final weightController = _metalWeightControllers[metal]!;
    final itemController = _metalItemControllers[metal]!;
    final isEditable = _metalEditable[metal] ?? false;
    
    // Capitalize first letter for display
    final displayName = metal[0].toUpperCase() + metal.substring(1);
    
    // Determine color based on metal type
    Color color;
    IconData icon;
    switch (metal.toLowerCase()) {
      case 'gold':
        color = Colors.amber;
        icon = Icons.diamond_outlined;
        break;
      case 'silver':
        color = Colors.grey;
        icon = Icons.circle_outlined;
        break;
      case 'platinum':
        color = Colors.blueGrey;
        icon = Icons.stars_outlined;
        break;
      case 'mixed':
        color = Colors.purple;
        icon = Icons.merge_outlined;
        break;
      default:
        color = AppColors.primary;
        icon = Icons.category_outlined;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          // Column 1: Metal Name (30%)
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          
          // Column 2: Weight (40%)
          Expanded(
            flex: 4,
            child: GestureDetector(
              onDoubleTap: () => setState(() => _metalEditable[metal] = true),
              child: TextFormField(
                controller: weightController,
                readOnly: !isEditable,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}')),
                ],
                style: TextStyle(
                  fontSize: 14,
                  color: isEditable ? Colors.black : Colors.grey[700],
                ),
                decoration: InputDecoration(
                  labelText: 'Weight (g)',
                  labelStyle: const TextStyle(fontSize: 12),
                  suffixIcon: isEditable 
                      ? null 
                      : Icon(Icons.lock_outline, size: 14, color: Colors.grey[400]),
                  filled: true,
                  fillColor: isEditable ? Colors.white : color.withOpacity(0.05),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: color, width: 1.5),
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  isDense: true,
                ),
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (double.tryParse(value!) == null) return 'Invalid';
                  return null;
                },
              ),
            ),
          ),
          
          const SizedBox(width: 10),
          
          // Column 3: Items Count (30%)
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: itemController,
              readOnly: true,
              keyboardType: TextInputType.number,
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              decoration: InputDecoration(
                labelText: 'Items',
                labelStyle: const TextStyle(fontSize: 12),
                suffixIcon: Icon(Icons.lock_outline, size: 14, color: Colors.grey[400]),
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                floatingLabelBehavior: FloatingLabelBehavior.auto,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Show items modal
  void _showItemsModal() async {
    final apiService = ApiService();
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.98,
          height: MediaQuery.of(context).size.height * 0.80,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.diamond, color: AppColors.primary),
                  const SizedBox(width: 12),
                  const Text(
                    'All Items',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder(
                  future: apiService.getItems(queryParams: {}), // Fetch ALL items
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    
                    if (!snapshot.hasData || snapshot.data?['success'] != true) {
                      return const Center(child: Text('Failed to load items'));
                    }
                    
                    final allItems = snapshot.data?['data']['items'] as List? ?? [];
                    
                    // Separate included and excluded items
                    final includedStatuses = ['active', 'in_stock', 'booked', 'wishlisted'];
                    final includedItems = allItems.where((item) => 
                      includedStatuses.contains(item['status']?.toString().toLowerCase())
                    ).toList();
                    final excludedItems = allItems.where((item) => 
                      !includedStatuses.contains(item['status']?.toString().toLowerCase())
                    ).toList();
                    
                    return ListView(
                      children: [
                        // Included Items Section
                        if (includedItems.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Included in Tally (${includedItems.length})',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ),
                          ...includedItems.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 4),
                              child: ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.primary.withOpacity(0.1),
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  item['name'] ?? 'Unnamed Item',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 2),
                                    Text('Barcode: ${item['barcode'] ?? 'N/A'}', style: const TextStyle(fontSize: 11)),
                                    Text('Metal: ${item['metalType'] ?? 'N/A'}', style: const TextStyle(fontSize: 11)),
                                  ],
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(item['status']),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    item['status'] ?? 'N/A',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                        
                        // Excluded Items Section
                        if (excludedItems.isNotEmpty) ...[
                          const Divider(height: 24, thickness: 2),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Excluded from Tally (${excludedItems.length})',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ),
                          ...excludedItems.map((item) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 4),
                              color: Colors.grey[100],
                              child: ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                leading: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                                title: Text(
                                  item['name'] ?? 'Unnamed Item',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey[700]),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 2),
                                    Text('Barcode: ${item['barcode'] ?? 'N/A'}', style: const TextStyle(fontSize: 11)),
                                    Text('Metal: ${item['metalType'] ?? 'N/A'}', style: const TextStyle(fontSize: 11)),
                                  ],
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[600],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    item['status'] ?? 'N/A',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Show containers modal
  void _showContainersModal() async {
    final apiService = ApiService();
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.98,
          height: MediaQuery.of(context).size.height * 0.80,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.inventory_2, color: AppColors.primary),
                  const SizedBox(width: 12),
                  const Text(
                    'All Containers',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder(
                  future: Future.wait([
                    apiService.getContainers(), // Active containers
                    apiService.getContainers(queryParams: {'isDeleted': 'true'}), // Deleted containers
                  ]),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    
                    if (!snapshot.hasData) {
                      return const Center(child: Text('Failed to load containers'));
                    }
                    
                    // Extract active and deleted containers
                    final activeResponse = snapshot.data![0];
                    final deletedResponse = snapshot.data![1];
                    
                    List<dynamic> activeContainers = [];
                    List<dynamic> deletedContainers = [];
                    
                    if (activeResponse['success'] == true) {
                      final data = activeResponse['data'];
                      if (data is List) {
                        activeContainers = data;
                      } else if (data is Map && data.containsKey('containers')) {
                        activeContainers = data['containers'] as List? ?? [];
                      }
                    }
                    
                    if (deletedResponse['success'] == true) {
                      final data = deletedResponse['data'];
                      if (data is List) {
                        deletedContainers = data;
                      } else if (data is Map && data.containsKey('containers')) {
                        deletedContainers = data['containers'] as List? ?? [];
                      }
                    }
                    
                    print('[CONTAINER MODAL] Active: ${activeContainers.length}, Deleted: ${deletedContainers.length}');
                    
                    return ListView(
                      children: [
                        // Active Containers Section
                        if (activeContainers.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Included in Tally (${activeContainers.length})',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ),
                          ...activeContainers.asMap().entries.map((entry) {
                            final index = entry.key;
                            final container = entry.value;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 4),
                              child: ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.primary.withOpacity(0.1),
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  container['name'] ?? 'Unnamed Container',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 2),
                                    Text('QR Code: ${container['qrCode'] ?? 'N/A'}', style: const TextStyle(fontSize: 11)),
                                    Text('Type: ${container['type'] ?? 'N/A'}', style: const TextStyle(fontSize: 11)),
                                  ],
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (container["isActive"] == true) ? Colors.green : Colors.orange,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    (container["isActive"] == true) ? "active" : (container["isLocked"] == true) ? "locked" : "inactive",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                        
                        // Deleted Containers Section
                        if (deletedContainers.isNotEmpty) ...[
                          const Divider(height: 24, thickness: 2),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Excluded from Tally (${deletedContainers.length})',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ),
                          ...deletedContainers.map((container) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 4),
                              color: Colors.grey[100],
                              child: ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                leading: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                title: Text(
                                  container['name'] ?? 'Unnamed Container',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey[700]),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 2),
                                    Text('QR Code: ${container['qrCode'] ?? 'N/A'}', style: const TextStyle(fontSize: 11)),
                                    Text('Type: ${container['type'] ?? 'N/A'}', style: const TextStyle(fontSize: 11)),
                                  ],
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[600],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'deleted',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper to get status color
  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'active':
      case 'in_stock':
        return Colors.green;
      case 'booked':
        return Colors.orange;
      case 'wishlisted':
        return Colors.blue;
      case 'sold':
        return Colors.red;
      case 'repair':
      case 'with_customer':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
}

