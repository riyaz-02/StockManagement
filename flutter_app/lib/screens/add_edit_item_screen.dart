import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import '../providers/item_provider.dart';
import '../providers/language_provider.dart';
import '../providers/container_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/app_constants.dart';
import '../utils/app_colors.dart';
import '../services/api_service.dart';

class AddEditItemScreen extends StatefulWidget {
  final String? itemId;
  final String? initialContainerId;
  final int? initialSlotNumber;
  
  const AddEditItemScreen({
    super.key, 
    this.itemId, 
    this.initialContainerId, 
    this.initialSlotNumber,
  });

  @override
  State<AddEditItemScreen> createState() => _AddEditItemScreenState();
}

class _AddEditItemScreenState extends State<AddEditItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _weightController = TextEditingController();
  final _huidController = TextEditingController();
  
  String _selectedItemType = '';
  String _selectedMetalType = '';
  String _selectedPurity = '';
  String? _selectedContainerId;
  int? _selectedSlotNumber;
  bool _isHallmarked = false;
  String _generatedBarcode = '';
  bool _isLoadingContainers = false;
  List<Map<String, dynamic>> _recommendedContainers = [];

  @override
  void initState() {
    super.initState();
    _generateBarcode();
    _weightController.addListener(_onSpecsChanged);
    
    // Set initial values from widget arguments
    if (widget.initialContainerId != null) {
      _selectedContainerId = widget.initialContainerId;
    }
    if (widget.initialSlotNumber != null) {
      _selectedSlotNumber = widget.initialSlotNumber;
    }

    // Fetch settings on init and set default values
    Future.microtask(() async {
      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      await settingsProvider.fetchItemSettings();
      
      // Always fetch containers to ensure dropdown is populated
      await Provider.of<ContainerProvider>(context, listen: false).fetchContainers();
      
      // Set default values after settings are loaded
      if (mounted) {
        setState(() {
          _selectedItemType = settingsProvider.itemTypes.isNotEmpty 
              ? settingsProvider.itemTypes.first.toLowerCase() 
              : 'ring';
          _selectedMetalType = settingsProvider.metalTypes.isNotEmpty 
              ? settingsProvider.metalTypes.first.toLowerCase() 
              : 'gold';
          _selectedPurity = settingsProvider.purityOptions.isNotEmpty 
              ? settingsProvider.purityOptions.first 
              : '916';
        });

        // Trigger analysis to populate recommendations initially
        _analyzeContainer();
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _barcodeController.dispose();
    _weightController.dispose();
    _huidController.dispose();
    super.dispose();
  }

  void _generateBarcode() {
    // Generate random 5-digit barcode
    final random = DateTime.now().millisecondsSinceEpoch % 90000 + 10000;
    setState(() {
      _generatedBarcode = random.toString();
      _barcodeController.text = _generatedBarcode;
    });
  }

  void _onSpecsChanged() {
    // Trigger container recommendation when specs change
    if (_weightController.text.isNotEmpty) {
      _analyzeContainer();
    }
  }

  Future<void> _analyzeContainer() async {
    // Determine Weight Category
    double weight = double.tryParse(_weightController.text) ?? 0.0;
    String weightCategory = 'Light';
    if (weight > 100) {
      weightCategory = 'Heavy';
    } else if (weight > 10) {
      weightCategory = 'Medium';
    }

    setState(() => _isLoadingContainers = true);
    
    try {
      final containerProvider = Provider.of<ContainerProvider>(context, listen: false);
      // Ensure we have latest data
      if (containerProvider.containers.isEmpty) {
        await containerProvider.fetchContainers();
      }
      
      final containers = containerProvider.containers;
      final recommended = containers.map((container) {
        // Validation Logic
        bool typeMatch = container.allowedItemTypes.map((e) => e.toLowerCase()).contains(_selectedItemType.toLowerCase());
        bool weightMatch = container.weightCategory.toLowerCase() == weightCategory.toLowerCase();
        bool hasSpace = container.availableSlots > 0;
        
        // Score: 3 = Perfect, 2 = Type+Space, 1 = Space only, 0 = No space
        int score = 0;
        if (hasSpace) {
            score += 1;
            if (typeMatch) score += 2; // Prioritize type matching
            if (weightMatch) score += 1;
        }

        return {
          'id': container.id,
          'name': container.name,
          'available': hasSpace,
          'availableSlots': container.availableSlots,
          'score': score,
          'matchReason': typeMatch ? 'Matches Type' : (hasSpace ? 'Has Space' : 'Full'),
        };
      }).toList();
      
      // Sort: Highest score first
      recommended.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
      
      setState(() {
        _recommendedContainers = recommended;
        _isLoadingContainers = false;
        
        // Auto-select best match if none selected
        if (_selectedContainerId == null && recommended.isNotEmpty) {
           final best = recommended.first;
           if ((best['score'] as int) > 1) { // Only auto-select if it's at least a decent match
             _selectedContainerId = best['id'] as String;
           }
        }
      });
    } catch (e) {
      setState(() => _isLoadingContainers = false);
    }
  }

  Future<void> _scanBarcode() async {
    try {
      final barcode = await FlutterBarcodeScanner.scanBarcode(
        '#ff6666',
        'Cancel',
        true,
        ScanMode.BARCODE,
      );
      
      if (barcode != '-1' && barcode.isNotEmpty) {
        // Check if barcode exists
        await _checkBarcodeExists(barcode);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _checkBarcodeExists(String barcode) async {
    try {
      final apiService = ApiService();
      final response = await apiService.getItems(queryParams: {'barcode': barcode});
      
      if (response['success'] && response['data'] != null && (response['data'] as List).isNotEmpty) {
        // Barcode exists
        final existingItem = response['data'][0];
        if (mounted) {
          _showBarcodeExistsDialog(existingItem);
        }
      } else {
        // Barcode is unique
        setState(() {
          _barcodeController.text = barcode;
          _generatedBarcode = barcode;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Barcode assigned successfully'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking barcode: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showBarcodeExistsDialog(Map<String, dynamic> existingItem) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Barcode Already Exists'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This barcode is already assigned to:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Name: ${existingItem['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Type: ${existingItem['itemType']}'),
                  Text('Metal: ${existingItem['metalType']}'),
                  Text('Weight: ${existingItem['netWeight']}g'),
                ],
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
              Navigator.pop(context);
              _generateBarcode();
            },
            child: const Text('Generate New'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveItem() async {
    if (_formKey.currentState!.validate()) {
      final itemProvider = Provider.of<ItemProvider>(context, listen: false);
      
      final itemData = {
        'name': _nameController.text,
        'barcode': _barcodeController.text,
        'itemType': _selectedItemType,
        'metalType': _selectedMetalType,
        'purity': _selectedPurity,
        'netWeight': double.parse(_weightController.text),
        'huid': _isHallmarked ? _huidController.text : '',
        'description': '',
        'containerId': _selectedContainerId,
        'slotNumber': _selectedSlotNumber,
      };

      final success = await itemProvider.createItem(itemData);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Item created successfully'), backgroundColor: Colors.green),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(itemProvider.error ?? 'Failed to create item'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
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
        title: Text(
          widget.itemId == null ? 'Add New Item' : 'Edit Item',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: _selectedItemType.isEmpty || _selectedMetalType.isEmpty || _selectedPurity.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // Basic Information Section
            _buildSectionCard(
              title: 'Basic Info',
              icon: Icons.info_outline,
              children: [
                _buildTextField(
                  controller: _nameController,
                  label: 'Item Name',
                  icon: Icons.label_outline,
                  required: true,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildDropdown(
                        value: _selectedItemType,
                        label: 'Type',
                        icon: Icons.category_outlined,
                        items: Provider.of<SettingsProvider>(context).itemTypes.isNotEmpty
                            ? Provider.of<SettingsProvider>(context).itemTypes
                            : ['ring'],
                        onChanged: (value) {
                          setState(() => _selectedItemType = value!);
                          _onSpecsChanged();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDropdown(
                        value: _selectedMetalType,
                        label: 'Metal',
                        icon: Icons.diamond_outlined,
                        items: Provider.of<SettingsProvider>(context).metalTypes.isNotEmpty
                            ? Provider.of<SettingsProvider>(context).metalTypes
                            : ['gold'],
                        onChanged: (value) {
                          setState(() => _selectedMetalType = value!);
                          _onSpecsChanged();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildDropdown(
                        value: _selectedPurity,
                        label: 'Purity',
                        icon: Icons.verified_outlined,
                        items: Provider.of<SettingsProvider>(context).purityOptions.isNotEmpty
                            ? Provider.of<SettingsProvider>(context).purityOptions
                            : ['916'],
                        onChanged: (value) {
                          setState(() => _selectedPurity = value!);
                          _onSpecsChanged();
                        },
                        translate: false,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        controller: _weightController,
                        label: 'Weight',
                        icon: Icons.scale_outlined,
                        required: true,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}')),
                        ],
                        suffix: 'g',
                        hint: '10.210',
                        validator: (value) {
                          if (value?.isEmpty ?? true) return 'Required';
                          if (double.tryParse(value!) == null) return 'Invalid';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Hallmark & HUID Section
            _buildSectionCard(
              title: 'Hallmark',
              icon: Icons.verified,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.verified, color: AppColors.primary, size: 20),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Hallmarked', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                      Switch(
                        value: _isHallmarked,
                        onChanged: (value) {
                          setState(() {
                            _isHallmarked = value;
                            if (!value) _huidController.clear();
                          });
                        },
                        activeColor: AppColors.primary,
                      ),
                    ],
                  ),
                ),
                if (_isHallmarked) ...[
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _huidController,
                    label: 'HUID Number',
                    icon: Icons.fingerprint,
                    required: false,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // Storage & Barcode Section
            _buildSectionCard(
              title: 'Storage & ID',
              icon: Icons.inventory_2_outlined,
              children: [
                if (_isLoadingContainers)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ))
                else if (_recommendedContainers.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange[700], size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Enter specs to see containers',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  _buildContainerDropdown(),
                const SizedBox(height: 12),
                _buildBarcodeSection(),
              ],
            ),
            const SizedBox(height: 16),

            // Save Button
            Consumer<ItemProvider>(
              builder: (context, provider, child) {
                return SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: provider.isLoading ? null : _saveItem,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: provider.isLoading
                        ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                        : const Text('Save Item', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.7),
                Colors.white.withOpacity(0.3),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool required = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? suffix,
    String? hint,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label + (required ? ' *' : ''),
        hintText: hint,
        suffixText: suffix,
        prefixIcon: Icon(icon, color: AppColors.primary),
        filled: true,
        fillColor: Colors.white.withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      validator: validator ?? (required ? (value) => value?.isEmpty ?? true ? 'Required' : null : null),
    );
  }

  // Helper function to format text for display
  String _formatText(String text) {
    // Handle special cases for purity (keep as-is if it's a number or contains numbers)
    if (RegExp(r'^\d').hasMatch(text)) {
      return text.toUpperCase(); // 916, 22k, etc.
    }
    
    // Replace hyphens and underscores with spaces, then capitalize each word
    return text
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  Widget _buildDropdown({
    required String value,
    required String label,
    required IconData icon,
    required List<String> items,
    required void Function(String?) onChanged,
    bool translate = true,
  }) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: '$label *',
        prefixIcon: Icon(icon, color: AppColors.primary),
        filled: true,
        fillColor: Colors.white.withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      items: items.map((item) {
        return DropdownMenuItem(
          value: item,
          child: Text(
            translate 
                ? languageProvider.translate(item) 
                : _formatText(item),
          ),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildContainerDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedContainerId,
      decoration: InputDecoration(
        labelText: 'Select Container (Optional)',
        prefixIcon: Icon(Icons.inventory_2_outlined, color: AppColors.primary),
        filled: true,
        fillColor: Colors.white.withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      items: _recommendedContainers.map((container) {
        final isAvailable = container['available'] as bool;
        final availableSlots = container['availableSlots'] as int;
        
        return DropdownMenuItem(
          value: container['id'] as String,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isAvailable ? Icons.check_circle : Icons.cancel,
                color: isAvailable ? Colors.green : Colors.red,
                size: 18,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${container['name']} - ${isAvailable ? "$availableSlots slots" : "Full"}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isAvailable ? Colors.black : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) {
        setState(() => _selectedContainerId = value);
      },
    );
  }

  Widget _buildBarcodeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Generated Barcode',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _generatedBarcode,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              children: [
                IconButton(
                  onPressed: _generateBarcode,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Generate New',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    foregroundColor: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                IconButton(
                  onPressed: _scanBarcode,
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Scan Barcode',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.orange.withOpacity(0.1),
                    foregroundColor: Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Tap refresh to generate new or scan to use existing barcode',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }
}
