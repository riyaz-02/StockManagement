import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:provider/provider.dart';
import '../models/item_model.dart';
import '../providers/item_provider.dart';
import '../providers/item_provider.dart';
import '../providers/language_provider.dart';
import '../providers/container_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/app_constants.dart';
import '../utils/app_colors.dart';
import '../services/api_service.dart';
import 'barcode_scanner_for_assignment.dart';

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
  final _piecesController = TextEditingController(text: '1');
  final _huidController = TextEditingController();
  
  String _selectedItemType = ''; // Start blank
  String _selectedMetalType = ''; // Start blank
  String _selectedPurity = ''; // Start blank
  String _selectedWeightCategory = 'Light';
  String _selectedWeightAccuracy = 'exact'; // Default
  String? _selectedContainerId;
  int? _selectedSlotNumber;
  
  // Certification - Simple checkboxes
  bool _isHallmarked = false;
  bool _isHUID = false;
  
  String _generatedBarcode = '';
  bool _isLoadingContainers = false;
  bool _isUploadingImages = false; // Track upload status
  int? _deletingImageIndex; // Track which image is being deleted
  bool _isDeletingExisting = false; // Track if deleting existing or uploaded image

  List<Map<String, dynamic>> _recommendedContainers = [];
  final List<XFile> _selectedImages = [];
  List<String> _existingImages = []; // Manage existing URLs
  List<String> _uploadedImageUrls = []; // Track uploaded Cloudinary URLs
  final ImagePicker _picker = ImagePicker();
  final ApiService _apiService = ApiService();

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
      _piecesController.text = item.numberOfPieces.toString();
      
      _selectedItemType = item.itemType;
      _selectedMetalType = item.metalType;
      _selectedPurity = item.purity;
      _selectedWeightCategory = item.weightCategory;
      _selectedWeightAccuracy = item.weightAccuracy;
      
      // Load certification data
      _isHallmarked = item.certificationType == 'hallmarked';
      _isHUID = item.certificationType == 'huid';
      if (_isHUID && item.huidNumber != null) {
        _huidController.text = item.huidNumber!;
      }
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
    final containerProvider = Provider.of<ContainerProvider>(context, listen: false);
    await containerProvider.fetchContainers();
    
    // Validate initial container is not locked
    if (widget.initialContainerId != null && mounted) {
      final initialContainer = containerProvider.containers.firstWhere(
        (c) => c.id == widget.initialContainerId,
        orElse: () => containerProvider.containers.first,
      );
      
      // If the initial container is locked, clear the selection and show warning
      if (initialContainer.isLocked) {
        setState(() {
          _selectedContainerId = null;
          _selectedSlotNumber = null;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Container "${initialContainer.name}" is locked. Please select a different container.'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
    
    if (mounted) {
      // Don't auto-fill type/metal/purity - let user choose
      // Only trigger analysis if we have values to analyze
      if (_selectedItemType.isNotEmpty && _selectedMetalType.isNotEmpty && _selectedPurity.isNotEmpty) {
        _analyzeContainer();
      }
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
        
        // Auto-select logic: Only auto-select if no container was pre-selected
        // If user came from container slot, preserve that selection
        if (_selectedContainerId == null || widget.initialContainerId == null) {
          final best = recommended.firstOrNull;
          if (best != null && (best['isAssignable'] as bool)) {
            _selectedContainerId = best['id'] as String;
          } else {
            _selectedContainerId = null;
          }
        }
        // If initialContainerId was set, keep it (don't override)
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingContainers = false);
    }
  }


  /// Checks if [barcode] is already assigned to another item.
  /// In edit mode, [excludeItemId] is the current item's id so its own barcode
  /// is not treated as a duplicate.
  Future<void> _checkBarcodeExists(String barcode, {String? excludeItemId}) async {
    try {
      final apiService = ApiService();
      final response = await apiService.getItems(queryParams: {'barcode': barcode});

      if (response['success'] && response['data'] != null) {
        // API can return data as a List directly OR as a paginated Map {items: [...]}
        List items;
        final data = response['data'];
        if (data is List) {
          items = data;
        } else if (data is Map && data['items'] is List) {
          items = data['items'] as List;
        } else {
          items = [];
        }

        if (items.isNotEmpty) {
          // Filter out the current item itself (edit mode)
          final conflicts = items.where((item) {
            final id = item['_id']?.toString() ?? '';
            return excludeItemId == null || id != excludeItemId;
          }).toList();

          if (conflicts.isNotEmpty) {
            // Barcode belongs to a different item
            if (mounted) _showBarcodeExistsDialog(conflicts[0]);
            return;
          }
        }
      }

      // Barcode is unique (or belongs to this item in edit mode) — assign it
      setState(() {
        _barcodeController.text = barcode;
        _generatedBarcode = barcode;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Barcode assigned successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking barcode: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Opens the barcode scanner and assigns the scanned barcode after
  /// verifying it is not already in use by another item.
  Future<void> _scanBarcode() async {
    if (kIsWeb) {
      // Camera scanning not supported on web — inform user
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera scanning is not supported on web. Please enter the barcode manually.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const BarcodeScannerForAssignment(),
      ),
    );

    if (scanned == null || scanned.isEmpty) return; // user cancelled

    // Check uniqueness — pass current item id in edit mode to allow its own barcode
    await _checkBarcodeExists(
      scanned,
      excludeItemId: widget.item?.id,
    );
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

  Future<void> _showImageSourceDialog() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Add Photos',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFFE94560)),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _captureFromCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFFE94560)),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImages();
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _captureFromCamera() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      
      if (image == null) return;

      setState(() => _isUploadingImages = true);

      try {
        print('[CAMERA] Uploading captured image to Cloudinary...');
        final result = await _apiService.uploadImage(image);
        
        if (result['success'] == true) {
          final imageUrl = result['data']['url'];
          setState(() {
            _uploadedImageUrls.add(imageUrl);
          });
          print('[CAMERA] ✅ Uploaded: $imageUrl');
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Photo captured and uploaded successfully'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          throw Exception('Upload failed');
        }
      } catch (e) {
        print('[CAMERA] ❌ Failed to upload: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to upload photo: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }

      setState(() => _isUploadingImages = false);
    } catch (e) {
      setState(() => _isUploadingImages = false);
      print('[CAMERA] ❌ Camera error: $e');
    }
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isEmpty) return;

      setState(() => _isUploadingImages = true);
      int successCount = 0;
      int failCount = 0;

      // Upload each image immediately to Cloudinary
      for (var image in images) {
        try {
          print('[UPLOAD] Uploading ${image.name} to Cloudinary...');
          final result = await _apiService.uploadImage(image);
          
          if (result['success'] == true) {
            final imageUrl = result['data']['url'];
            setState(() {
              _uploadedImageUrls.add(imageUrl);
            });
            successCount++;
            print('[UPLOAD] ✅ Uploaded: $imageUrl');
          } else {
            failCount++;
            throw Exception('Upload failed');
          }
        } catch (e) {
          failCount++;
          print('[UPLOAD] ❌ Failed to upload ${image.name}: $e');
        }
      }

      setState(() => _isUploadingImages = false);

      // Show result banner at top
      if (mounted && successCount > 0) {
        ScaffoldMessenger.of(context).showMaterialBanner(
          MaterialBanner(
            content: Text('$successCount image(s) uploaded successfully'),
            backgroundColor: Colors.green.shade100,
            leading: const Icon(Icons.check_circle, color: Colors.green),
            actions: [
              TextButton(
                onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
                child: const Text('DISMISS'),
              ),
            ],
          ),
        );
        // Auto-hide after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
          }
        });
      }
    } catch (e) {
      setState(() => _isUploadingImages = false);
    }
  }

  /// Remove uploaded image and delete from Cloudinary
  Future<void> _removeImage(int index, {bool isExisting = false}) async {
    // Prevent double-click
    if (_deletingImageIndex == index && _isDeletingExisting == isExisting) {
      return;
    }

    setState(() {
      _deletingImageIndex = index;
      _isDeletingExisting = isExisting;
    });

    final imageUrl = isExisting ? _existingImages[index] : _uploadedImageUrls[index];
    
    try {
      // Delete from Cloudinary
      final deleted = await _apiService.deleteImage(imageUrl);
      
      if (deleted) {
        setState(() {
          if (isExisting) {
            _existingImages.removeAt(index);
          } else {
            _uploadedImageUrls.removeAt(index);
          }
          _deletingImageIndex = null;
          _isDeletingExisting = false;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showMaterialBanner(
            MaterialBanner(
              content: const Text('Image deleted successfully'),
              backgroundColor: Colors.orange.shade100,
              leading: const Icon(Icons.delete_outline, color: Colors.orange),
              actions: [
                TextButton(
                  onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
                  child: const Text('DISMISS'),
                ),
              ],
            ),
          );
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            }
          });
        }
      } else {
        throw Exception('Failed to delete from Cloudinary');
      }
    } catch (e) {
      print('[DELETE] Error: $e');
      setState(() {
        _deletingImageIndex = null;
        _isDeletingExisting = false;
      });
    }
  }

  Future<void> _saveItem() async {
    if (_formKey.currentState!.validate()) {
      // Validation 1: Ensure a container is selected (only for NEW items)
      if (widget.item == null && (_selectedContainerId == null || _selectedContainerId!.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a valid container before saving the item.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      // Validation 2: Check if selected container is locked (only if container is being changed)
      if (_selectedContainerId != null) {
        Map<String, dynamic>? selectedContainer;
        try {
          selectedContainer = _recommendedContainers.firstWhere(
            (c) => c['id'] == _selectedContainerId,
          );
        } catch (e) {
          selectedContainer = null;
        }
        
        if (selectedContainer != null && selectedContainer['status'] == 'Locked') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot add items to a locked container. Please select a different container.'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
        
        // Validation 3: Check if container is assignable
        if (selectedContainer != null && selectedContainer['isAssignable'] == false) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cannot add items to this container. Status: ${selectedContainer['status']}'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
      }
      
      final itemProvider = Provider.of<ItemProvider>(context, listen: false);
      
      // Determine certification type
      String certificationType = 'none';
      if (_isHallmarked) {
        certificationType = 'hallmarked';
      } else if (_isHUID) {
        certificationType = 'huid';
      }
      
      final itemData = {
        'name': _nameController.text,
        'barcode': _barcodeController.text,
        'itemType': _selectedItemType,
        'metalType': _selectedMetalType,
        'purity': _selectedPurity,
        'netWeight': double.parse(_weightController.text),
        'numberOfPieces': int.parse(_piecesController.text),
        'weightCategory': _selectedWeightCategory,
        'weightAccuracy': _selectedWeightAccuracy,
        'certificationType': certificationType,
        'huidNumber': _isHUID ? _huidController.text : null,
        'description': '',
        'containerId': _selectedContainerId,
        'slotNumber': _selectedSlotNumber,
        // Combine existing and newly uploaded Cloudinary URLs
        'images': jsonEncode([..._existingImages, ..._uploadedImageUrls]),
      };

      bool success;
      if (widget.item != null) {
        // Pass empty list since images are already in Cloudinary
        success = await itemProvider.updateItem(widget.item!.id, itemData, []);
      } else {
        // Pass empty list since images are already in Cloudinary
        success = await itemProvider.createItem(itemData, []);
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: Text(
          widget.item == null ? 'Add New Item' : 'Edit Item',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
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
      body: Form(
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

              // 3.5 Number of Pieces & Weight Category
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _piecesController,
                      label: 'Pieces',
                      icon: Icons.numbers,
                      required: true,
                      keyboardType: TextInputType.number,
                      hint: '1',
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Required';
                        final pieces = int.tryParse(value);
                        if (pieces == null || pieces < 1) return 'Must be >= 1';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDropdown(
                      value: _selectedWeightCategory,
                      label: 'Weight Category',
                      icon: Icons.monitor_weight_outlined,
                      items: ['Light', 'Medium', 'Heavy'],
                      onChanged: (value) {
                        setState(() => _selectedWeightCategory = value!);
                        _analyzeContainer();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 3.75 Weight Accuracy
              _buildDropdown(
                value: _selectedWeightAccuracy,
                label: 'Weight Accuracy',
                icon: Icons.precision_manufacturing_outlined,
                items: const ['exact', 'approx', 'bulk'],
                onChanged: (value) {
                  setState(() => _selectedWeightAccuracy = value!);
                },
                translate: false,
                itemLabels: const {
                  'exact': 'Exact',
                  'approx': 'Approximate',
                  'bulk': 'Bulk',
                },
              ),
              const SizedBox(height: 16),
              
              // 4. Certification Options (in one row)
              Row(
                children: [
                  // Hallmark Option
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _isHallmarked = !_isHallmarked;
                          if (_isHallmarked) {
                            _isHUID = false;
                            _huidController.clear();
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _isHallmarked ? const Color(0xFFB8860B) : Colors.grey[300]!,
                            width: _isHallmarked ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          color: _isHallmarked ? const Color(0xFFFFD700).withOpacity(0.1) : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isHallmarked ? Icons.check_circle : Icons.circle_outlined,
                              color: _isHallmarked ? const Color(0xFFB8860B) : Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Hallmarked',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            if (_isHallmarked) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFD700).withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFFB8860B)),
                                ),
                                child: const Text(
                                  '916',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFB8860B),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // HUID Option
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _isHUID = !_isHUID;
                          if (_isHUID) {
                            _isHallmarked = false;
                          } else {
                            _huidController.clear();
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _isHUID ? const Color(0xFF0D47A1) : Colors.grey[300]!,
                            width: _isHUID ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          color: _isHUID ? const Color(0xFF2196F3).withOpacity(0.1) : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isHUID ? Icons.check_circle : Icons.circle_outlined,
                              color: _isHUID ? const Color(0xFF0D47A1) : Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'HUID',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            if (_isHUID) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2196F3).withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFF0D47A1)),
                                ),
                                child: const Text(
                                  'HUID',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0D47A1),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              // HUID Number Input (shown when HUID is selected)
              if (_isHUID) ...[
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _huidController,
                  label: 'HUID Number',
                  hint: 'Enter HUID number',
                  icon: Icons.qr_code_2,
                  required: false,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]')),
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      return TextEditingValue(
                        text: newValue.text.toUpperCase(),
                        selection: newValue.selection,
                      );
                    }),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              
              // 6. Container Selection
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
                    onPressed: _showImageSourceDialog,
                    icon: const Icon(Icons.add_a_photo),
                    label: const Text('Add Photos'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_existingImages.isNotEmpty || _uploadedImageUrls.isNotEmpty || _isUploadingImages)
                SizedBox(
                  height: 100,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      // Existing Images
                      ..._existingImages.asMap().entries.map((entry) {
                        final index = entry.key;
                        final path = entry.value;
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
                            // Loading overlay during deletion
                            if (_deletingImageIndex == index && _isDeletingExisting)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.black54,
                                ),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            Positioned(
                              top: 4,
                              right: 12,
                              child: GestureDetector(
                                onTap: (_deletingImageIndex == index && _isDeletingExisting) 
                                    ? null 
                                    : () => _removeImage(index, isExisting: true),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: (_deletingImageIndex == index && _isDeletingExisting) 
                                        ? Colors.grey 
                                        : Colors.red,
                                    shape: BoxShape.circle,
                                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                                  ),
                                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                      
                      // Newly Uploaded Images (Cloudinary)
                      ..._uploadedImageUrls.asMap().entries.map((entry) {
                        final index = entry.key;
                        final imageUrl = entry.value;
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
                                child: Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                                ),
                              ),
                            ),
                            // Loading overlay during deletion
                            if (_deletingImageIndex == index && !_isDeletingExisting)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.black54,
                                ),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            Positioned(
                              top: 4,
                              right: 12,
                              child: GestureDetector(
                                onTap: (_deletingImageIndex == index && !_isDeletingExisting) 
                                    ? null 
                                    : () => _removeImage(index, isExisting: false),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: (_deletingImageIndex == index && !_isDeletingExisting) 
                                        ? Colors.grey 
                                        : Colors.red,
                                    shape: BoxShape.circle,
                                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                                  ),
                                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                      
                      // Upload Progress Indicator
                      if (_isUploadingImages)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.withOpacity(0.5)),
                            color: Colors.blue.withOpacity(0.1),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
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
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    // Scan button — hidden on web
                    if (!kIsWeb)
                      IconButton(
                        onPressed: _scanBarcode,
                        icon: const Icon(Icons.qr_code_scanner, color: Color(0xFFE94560)),
                        tooltip: 'Scan blank tag barcode',
                      ),
                    if (!kIsWeb)
                      Container(
                        height: 40,
                        width: 1,
                        color: Colors.grey[300],
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                    IconButton(
                      onPressed: _generateBarcode,
                      icon: const Icon(Icons.refresh, color: Colors.blue),
                      tooltip: 'Generate New Barcode',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
              
              // 9. Save Button
              Consumer<ItemProvider>(
                builder: (context, provider, child) {
                  final bool isDisabled = provider.isLoading || _isUploadingImages;
                  return SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: isDisabled ? null : _saveItem,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isDisabled
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _isUploadingImages ? 'UPLOADING IMAGES...' : 'SAVING...',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ],
                            )
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
          enabled: isAssignable, // Only enable if container is assignable (not locked, active, has space)
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
    TextCapitalization? textCapitalization,
    String? suffix,
    String? hint,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization ?? TextCapitalization.none,
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
    Map<String, String>? itemLabels,
  }) {
    final languageProvider = Provider.of<LanguageProvider>(context);

    // Ensure the current value is in the items list to prevent crash
    final List<String> safeItems = List.from(items);
    if (!safeItems.contains(value) && value.isNotEmpty) {
      safeItems.add(value);
    }
    // Handle empty items list
    if (safeItems.isEmpty) {
      safeItems.add('No options available');
    }
    
    // Allow null value to show hint
    String? safeValue = value.isEmpty ? null : value;
    
    return DropdownButtonFormField<String>(
      value: safeValue,
      hint: Text('Select $label', style: TextStyle(color: Colors.grey[600])),
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
        String displayText;
        if (itemLabels != null && itemLabels.containsKey(item)) {
          displayText = itemLabels[item]!;
        } else if (translate) {
          displayText = _formatText(languageProvider.translate(item));
        } else {
          displayText = _formatText(item);
        }
        
        return DropdownMenuItem(
          value: item,
          child: Text(displayText),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }




}
