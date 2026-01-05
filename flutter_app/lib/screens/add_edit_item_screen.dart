import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:provider/provider.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import '../models/item_model.dart';
import '../providers/item_provider.dart';
import '../providers/language_provider.dart';
import '../providers/container_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/app_constants.dart';
import '../utils/app_colors.dart';
import '../services/api_service.dart';

class AddEditItemScreen extends StatefulWidget {
  final Item? item; // Add this
  final String? itemId;
  final String? initialContainerId;
  final int? initialSlotNumber;
  
  const AddEditItemScreen({
    super.key, 
    this.item, // Add this
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
  
  String _selectedItemType = 'ring';
  String _selectedMetalType = 'gold';
  String _selectedPurity = '916';
  String _selectedWeightCategory = 'Light'; // Default
  String? _selectedContainerId;
  int? _selectedSlotNumber;
  bool _isHallmarked = false;
  String _generatedBarcode = '';
  bool _isLoadingContainers = false;

  List<Map<String, dynamic>> _recommendedContainers = [];
  final List<XFile> _selectedImages = [];
  List<String> _existingImages = []; // Manage existing URLs
  final ImagePicker _picker = ImagePicker();

  @override
  @override
  void initState() {
    super.initState();
    _weightController.addListener(_onWeightChanged);

    // Initialize with item data if provided (Edit Mode)
    if (widget.item != null) {
      final item = widget.item!;
      _nameController.text = item.name;
      _barcodeController.text = item.barcode;
      _generatedBarcode = item.barcode;
      _weightController.text = item.netWeight.toString();
      _huidController.text = item.huid;
      
      _selectedItemType = item.itemType;
      _selectedMetalType = item.metalType;
      _selectedPurity = item.purity;
      _selectedWeightCategory = item.weightCategory;
      _isHallmarked = item.huid.isNotEmpty;
      
      // Handle Container & Slot
      _selectedContainerId = item.containerId;
      _selectedSlotNumber = item.slotNumber;
      
      // Initialize existing images
      _existingImages = List.from(item.images);
    } else {
      // Create Mode Defaults
      _generateBarcode();
      // Use widget args for container/slot defaults if provided (e.g. adding from Container Details)
      if (widget.initialContainerId != null) {
        _selectedContainerId = widget.initialContainerId;
      }
      if (widget.initialSlotNumber != null) {
        _selectedSlotNumber = widget.initialSlotNumber;
      }
    }

    // Fetch settings on init and set default values IF NOT EDITING
    Future.microtask(() async {
      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      await settingsProvider.fetchItemSettings();
      
      // Always fetch containers to ensure dropdown is populated
      await Provider.of<ContainerProvider>(context, listen: false).fetchContainers();
      
      if (mounted) {
        // Only set defaults if NEW item
        if (widget.item == null) {
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
        }

        // Trigger analysis to populate recommendations
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
    // Always trigger analysis when specs change, regardless of weight
    _analyzeContainer();
  }

  void _onWeightChanged() {
     // Weight category is now manually selected by user, not auto-calculated
     // Only trigger container analysis when weight changes
     _analyzeContainer();
  }

  Future<void> _analyzeContainer() async {
    // Force async execution to avoid "setState during build" and race conditions
    await Future.delayed(Duration.zero);
    
    // Determine Weight Category
    double weight = double.tryParse(_weightController.text) ?? 0.0;
    
    // Auto-set category if user hasn't manually overridden (or just update logical variable)
    // For now, let's keep it simple: Calculate it for recommendation, but also update the UI dropdown if needed?
    // User asked for "optional" field. Let's make the dropdown control the logic.
    
    // If we want auto-calculation to update the dropdown:
    String calculatedCategory = 'Light';
    if (weight > 100) {
      calculatedCategory = 'Heavy';
    } else if (weight > 10) {
      calculatedCategory = 'Medium';
    }
    
    // Use the selected category for logic, defaulting to calculated if not set (but we initialized it)
    // Actually, user might want auto-calc to update the dropdown. Let's do that in _onSpecsChanged listener instead?
    // For now, let's just use _selectedWeightCategory for the logic.
    String weightCategory = _selectedWeightCategory;

    try {
      final containerProvider = Provider.of<ContainerProvider>(context, listen: false);
      
      // Only show loading if we need to fetch data
      if (containerProvider.containers.isEmpty) {
        setState(() => _isLoadingContainers = true);
        await containerProvider.fetchContainers();
      }
      
      final containers = containerProvider.containers;
      final recommended = containers.map((container) {
        // Advanced Scoring Algorithm
        int score = 0;
        
        // 1. Metal Type Match (Highest Priority)
        bool metalMatch = container.metalType.any((m) => m.toLowerCase() == _selectedMetalType.toLowerCase());
        if (metalMatch) score += 10;
        
        // 2. Item Type Match
        bool typeMatch = container.allowedItemTypes.any((t) => t.toLowerCase() == _selectedItemType.toLowerCase());
        if (typeMatch) score += 5;
        
        // 3. Status checks
        bool isLocked = container.isLocked;
        bool isActive = container.isActive;
        bool hasSpace = container.availableSlots > 0;
        
        if (!isActive) score -= 100; // Dead container
        if (isLocked) score -= 50;   // Locked container
        if (!hasSpace) score -= 20;  // Full container
        
        // 4. Weight Category Preference (Bonus)
        if (container.weightCategory.toLowerCase() == weightCategory.toLowerCase()) {
          score += 2;
        }

        // Determine usability
        bool isAssignable = isActive && !isLocked && hasSpace && metalMatch && typeMatch;

        return {
          'id': container.id,
          'name': container.name,
          'code': container.qrCode ?? container.id.substring(0, 4),
          'availableSlots': container.availableSlots,
          'totalSlots': container.capacity,
          'score': score,
          'isAssignable': isAssignable,
          'status': isLocked ? 'Locked' : (!isActive ? 'Inactive' : (!hasSpace ? 'Full' : 'Active')),
          'metalMatch': metalMatch,
          'typeMatch': typeMatch,
        };
      }).toList();
      
      // Sort: Highest score first, then by available slots (most empty first)
      recommended.sort((a, b) {
        int scoreComp = (b['score'] as int).compareTo(a['score'] as int);
        if (scoreComp != 0) return scoreComp;
        return (b['availableSlots'] as int).compareTo(a['availableSlots'] as int);
      });
      
      setState(() {
        _recommendedContainers = recommended;
        _isLoadingContainers = false;
        
        // Auto-select logic: Always pick the best match based on current specs
        // This ensures that changing weight/type immediately updates to the best container
        final best = recommended.firstOrNull;
        if (best != null && (best['isAssignable'] as bool)) {
          _selectedContainerId = best['id'] as String;
        } else {
          _selectedContainerId = null;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingContainers = false);
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

  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(images);
        });
      }
    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking images: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
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
        'weightCategory': _selectedWeightCategory,
        'huid': _isHallmarked ? _huidController.text : '',
        'description': '',
        'containerId': _selectedContainerId,
        'slotNumber': _selectedSlotNumber,
        if (widget.item != null) 'keptImages': jsonEncode(_existingImages), // Send kept images
      };

      bool success;
      if (widget.item != null) {
        success = await itemProvider.updateItem(widget.item!.id, itemData, _selectedImages);
      } else {
        success = await itemProvider.createItem(itemData, _selectedImages);
      }

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.item != null ? 'Item updated successfully' : 'Item created successfully'),
              backgroundColor: Colors.green
            ),
          );
          Navigator.pop(context, true); // Return true to signal refresh
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(itemProvider.error ?? 'Failed to save item'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteItem() async {
     bool confirm = await showDialog(
       context: context, 
       builder: (ctx) => AlertDialog(
         title: const Text('Delete Item?'),
         content: const Text('Are you sure you want to delete this item? This cannot be undone.'),
         actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true), 
              child: const Text('Delete')
            ),
         ],
       )
     ) ?? false;

     if (confirm) {
        final itemProvider = Provider.of<ItemProvider>(context, listen: false);
        final success = await itemProvider.deleteItem(widget.item!.id);
        if (mounted) {
          if (success) {
            Navigator.pop(context); // Close screen
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Item deleted successfully'), backgroundColor: Colors.green),
            );
          } else {
             ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(itemProvider.error ?? 'Failed to delete'), backgroundColor: Colors.red),
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
          widget.item == null ? 'Add New Item' : 'Edit Item',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (widget.item != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteItem,
              tooltip: 'Delete Item',
            ),
        ],
      ),
      body: _selectedItemType.isEmpty || _selectedMetalType.isEmpty || _selectedPurity.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Item Name (Full Width)
              _buildTextField(
                controller: _nameController,
                label: 'Item Name',
                icon: Icons.label_outline,
                required: true,
              ),
              const SizedBox(height: 16),
              
              // 2. Type & Metal
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
              
              // 3. Purity & Weight
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
                      suffix: 'g',
                      hint: '0.000',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 3.5 Weight Category (New Field)
              _buildDropdown(
                value: _selectedWeightCategory,
                label: 'Weight Category',
                icon: Icons.monitor_weight_outlined,
                items: ['Light', 'Medium', 'Heavy'],
                onChanged: (value) {
                  setState(() => _selectedWeightCategory = value!);
                  _analyzeContainer();
                },
              ),
              const SizedBox(height: 16),
              
              // 4. Hallmark Switch
              Row(
                children: [
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
                    const Text('Hallmarked', style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              
              // 5. HUID (Conditional)
              if (_isHallmarked) ...[
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _huidController,
                  label: 'HUID Number',
                  icon: Icons.fingerprint,
                  required: false,
                ),
              ],
              const SizedBox(height: 24),
              
              // 6. Container Selection
              const Text('Assign Container', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_isLoadingContainers)
                const LinearProgressIndicator()
              else
                _buildAdvancedContainerDropdown(),

              const SizedBox(height: 24),

              // 7. Add Images (Combined List: Existing + New)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Item Images', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: _pickImages,
                    icon: const Icon(Icons.add_a_photo),
                    label: const Text('Add Photos'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_existingImages.isNotEmpty || _selectedImages.isNotEmpty)
                SizedBox(
                  height: 100,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      // Existing Images
                      ..._existingImages.map((path) {
                        String imageUrl;
                        if (path.startsWith('http')) {
                          imageUrl = path;
                        } else {
                          imageUrl = '${AppConstants.baseUrl}/${path.replaceAll('\\', '/')}';
                        }
                        
                        return Stack(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 12,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _existingImages.remove(path);
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 2)],
                                  ),
                                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                      
                      // New Selected Images
                      ..._selectedImages.asMap().entries.map((entry) {
                        final index = entry.key;
                        final file = entry.value;
                        return Stack(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.withOpacity(0.5)), // Green border for new
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: kIsWeb 
                                    ? Image.network(file.path, fit: BoxFit.cover) 
                                    : Image.file(File(file.path), fit: BoxFit.cover),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 12,
                              child: GestureDetector(
                                onTap: () => _removeImage(index),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 2)],
                                  ),
                                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                )
              else 
                Container(
                  height: 60,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey[50],
                  ),
                  child: Center(
                     child: Text(
                        'No images added',
                        style: TextStyle(color: Colors.grey[500]),
                     ),
                  ),
                ),

              const SizedBox(height: 32),

              // 8. Barcode Section (Visual & Compact)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    // Code Text & Label
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('BARCODE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text(
                            _generatedBarcode,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Visual Barcode
                    if (_generatedBarcode.isNotEmpty)
                      Expanded(
                        flex: 3,
                        child: Container(
                          height: 50,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: BarcodeWidget(
                            barcode: Barcode.code128(),
                            data: _generatedBarcode,
                            drawText: false,
                            color: Colors.black,
                            height: 50,
                          ),
                        ),
                      ),
                    
                    // Actions
                    Container(
                      height: 40,
                      width: 1,
                      color: Colors.grey[300],
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    IconButton(
                      onPressed: _generateBarcode,
                      icon: const Icon(Icons.refresh, color: Colors.blue),
                      tooltip: 'Generate New',
                    ),
                    IconButton(
                      onPressed: _scanBarcode,
                      icon: const Icon(Icons.qr_code_scanner, color: Colors.orange),
                      tooltip: 'Scan Existing',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
              
              // 9. Save Button
              Consumer<ItemProvider>(
                builder: (context, provider, child) {
                  return SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: provider.isLoading ? null : _saveItem,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: provider.isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('SAVE ITEM', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdvancedContainerDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedContainerId,
      decoration: InputDecoration(
        labelText: 'Select Container',
        prefixIcon: Icon(Icons.inventory_2, color: AppColors.primary),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        helperText: 'Auto-recommended based on criteria',
      ),
      isExpanded: true,
      selectedItemBuilder: (BuildContext context) {
        return _recommendedContainers.map<Widget>((Map<String, dynamic> container) {
          return Text(
            '${container['name']} (${container['code']})',
            overflow: TextOverflow.ellipsis,
             style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          );
        }).toList();
      },
      items: _recommendedContainers.map((container) {
        final bool isAssignable = container['isAssignable'] as bool;
        final String status = container['status'] as String;
        final int available = container['availableSlots'] as int;
        final int total = container['totalSlots'] as int;
        
        return DropdownMenuItem(
          value: container['id'] as String,
          enabled: true,
          child: Opacity(
            opacity: isAssignable ? 1.0 : 0.5,
            child: Row(
              children: [
                Icon(
                   isAssignable ? Icons.check_circle : Icons.error_outline,
                   color: isAssignable ? Colors.green : Colors.grey,
                   size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min, // Fix vertical overflow
                    children: [
                      Text(
                        '${container['name']} (${container['code']})',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        '$available/$total Slots • $status',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: isAssignable ? Colors.grey[700] : Colors.red),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
      onChanged: (value) {
        setState(() => _selectedContainerId = value);
      },
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

    // Ensure the current value is in the items list to prevent crash
    final List<String> safeItems = List.from(items);
    if (!safeItems.contains(value) && value.isNotEmpty) {
      safeItems.add(value);
    }
    // If value is empty and items not empty, default to first (should have been handled in initState, but safety net)
    String? safeValue = value;
    if (value.isEmpty && safeItems.isNotEmpty) {
      safeValue = safeItems.first;
    } else if (safeItems.isEmpty) {
        // Fallback for completely empty lists
        safeItems.add('Default');
        safeValue = 'Default';
    }
    
    return DropdownButtonFormField<String>(
      value: safeValue,
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
      items: safeItems.map((item) {
        return DropdownMenuItem(
          value: item,
          child: Text(
            translate 
                ? _formatText(languageProvider.translate(item)) 
                : _formatText(item),
          ),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }




}
