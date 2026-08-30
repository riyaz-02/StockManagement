import 'dart:ui';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../providers/container_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';
import '../models/container_model.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';

class EditContainerScreen extends StatefulWidget {
  final ItemContainer container;

  const EditContainerScreen({
    super.key,
    required this.container,
  });

  @override
  State<EditContainerScreen> createState() => _EditContainerScreenState();
}

class _EditContainerScreenState extends State<EditContainerScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _capacityController;
  final ImagePicker _imagePicker = ImagePicker();
  final ApiService _apiService = ApiService();

  late String _selectedType;
  late String _selectedWeightCategory;

  late List<String> _selectedMetalTypes;
  late List<String> _selectedPurity;
  late String _selectedLayoutType;
  late List<String> _selectedItemTypes;

  // Image state - Cloudinary approach
  String? _existingImageUrl; // Existing Cloudinary URL
  String? _uploadedImageUrl; // Newly uploaded Cloudinary URL
  bool _isUploadingImage = false;
  bool _isDeletingImage = false;

  // Barcode state
  late String _generatedBarcode;
  int _barcodeSerial = 1;

  @override
  void initState() {
    super.initState();
    // Initialize controllers with existing data
    _nameController = TextEditingController(text: widget.container.name);
    _capacityController =
        TextEditingController(text: widget.container.capacity.toString());

    // Initialize state with existing data
    _selectedType = widget.container.type;
    _selectedWeightCategory = widget.container.weightCategory;

    _selectedMetalTypes = List.from(widget.container.metalType);
    _selectedPurity = List.from(widget.container.purity);
    _selectedLayoutType = widget.container.layoutType;
    _selectedItemTypes = List.from(widget.container.allowedItemTypes);
    _generatedBarcode = widget.container.qrCode ?? '';

    // Initialize existing image URL
    _existingImageUrl = widget.container.image;

    // Attempt to extract serial from barcode if possible, or just default to 1
    // Logic: if barcode is "R12", serial is 12.
    _extractSerialFromBarcode();

    // Fetch settings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settingsProvider =
          Provider.of<SettingsProvider>(context, listen: false);
      settingsProvider.fetchContainerSettings();
      settingsProvider.fetchItemSettings();
    });
  }

  void _extractSerialFromBarcode() {
    try {
      // Remove letters
      final numberString = _generatedBarcode.replaceAll(RegExp(r'[^0-9]'), '');
      if (numberString.isNotEmpty) {
        _barcodeSerial = int.parse(numberString);
      }
    } catch (e) {
      // Ignore error, keep default
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    // Show bottom sheet to choose between camera and gallery
    final source = await showModalBottomSheet<ImageSource>(
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
              'Add Photo',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.primary),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() => _isUploadingImage = true);

      try {
        print('[UPLOAD] Uploading container image to Cloudinary...');
        final result =
            await _apiService.uploadImage(image, folder: 'containers');

        if (result['success'] == true) {
          final imageUrl = result['data']['url'];
          setState(() {
            _uploadedImageUrl = imageUrl;
            _isUploadingImage = false;
          });
          print('[UPLOAD] ✅ Uploaded: $imageUrl');

          if (mounted) {
            ScaffoldMessenger.of(context).showMaterialBanner(
              MaterialBanner(
                content: const Text('Image uploaded successfully'),
                backgroundColor: Colors.green.shade100,
                leading: const Icon(Icons.check_circle, color: Colors.green),
                actions: [
                  TextButton(
                    onPressed: () => ScaffoldMessenger.of(context)
                        .hideCurrentMaterialBanner(),
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
          throw Exception('Upload failed');
        }
      } catch (e) {
        setState(() => _isUploadingImage = false);
        print('[UPLOAD] ❌ Failed: $e');
      }
    } catch (e) {
      setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _removeImage({bool isExisting = false}) async {
    if (_isDeletingImage) return; // Prevent double-click

    setState(() => _isDeletingImage = true);

    final imageUrl = isExisting ? _existingImageUrl : _uploadedImageUrl;
    if (imageUrl == null) {
      setState(() => _isDeletingImage = false);
      return;
    }

    try {
      final deleted = await _apiService.deleteImage(imageUrl);

      if (deleted) {
        setState(() {
          if (isExisting) {
            _existingImageUrl = null;
          } else {
            _uploadedImageUrl = null;
          }
          _isDeletingImage = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showMaterialBanner(
            MaterialBanner(
              content: const Text('Image deleted successfully'),
              backgroundColor: Colors.orange.shade100,
              leading: const Icon(Icons.delete_outline, color: Colors.orange),
              actions: [
                TextButton(
                  onPressed: () =>
                      ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
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
      }
    } catch (e) {
      print('[DELETE] Error: $e');
      setState(() => _isDeletingImage = false);
    }
  }

  Future<void> _generateBarcode() async {
    if (_selectedItemTypes.isEmpty) {
      showAppSnackBar(
        context,
        const SnackBar(content: Text('Select item types first')),
      );
      return;
    }

    String prefix;
    if (_selectedItemTypes.length == 1) {
      final type = _selectedItemTypes.first.toUpperCase();
      prefix = type.substring(0, 1);
    } else {
      prefix = 'M';
    }

    final containerProvider =
        Provider.of<ContainerProvider>(context, listen: false);
    _barcodeSerial = await containerProvider.getNextSerial(prefix);

    setState(() {
      _generatedBarcode = '$prefix$_barcodeSerial';
    });
  }

  Future<void> _updateContainer() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedItemTypes.isEmpty) {
        showAppSnackBar(
          context,
          const SnackBar(
            content: Text('Please select at least one item type'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final containerProvider =
          Provider.of<ContainerProvider>(context, listen: false);

      // Use uploaded image URL or existing image URL
      final imageUrl = _uploadedImageUrl ?? _existingImageUrl;

      final containerData = {
        'name': _nameController.text,
        'type': _selectedType,
        'capacity': int.parse(_capacityController.text),
        'allowedItemTypes': _selectedItemTypes,
        'weightCategory': _selectedWeightCategory,
        'metalType': _selectedMetalTypes,
        'purity': _selectedPurity,
        'layoutType': _selectedLayoutType,
        'qrCode': _generatedBarcode,
        if (imageUrl != null) 'image': imageUrl,
      };

      final success = await containerProvider.updateContainer(
          widget.container.id, containerData);

      if (mounted) {
        if (success) {
          showAppSnackBar(
            context,
            const SnackBar(
              content: Text('Container updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        } else {
          showAppSnackBar(
            context,
            SnackBar(
              content:
                  Text(containerProvider.error ?? 'Failed to update container'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _formatText(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);

    // Don't block UI on edit, just use defaults if settings not loaded yet
    // because we already have the container data to show

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Edit Container',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
      body: Container(
        color: Colors.white,
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _buildSectionCard(
                  title: '',
                  icon: Icons.abc,
                  children: [
                    _buildTextField(
                      controller: _nameController,
                      label: 'Container Name',
                      icon: Icons.label_outline,
                      hint: 'e.g., Gold Ring Drawer 1',
                      required: true,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final items =
                                  settingsProvider.containerTypes.isNotEmpty
                                      ? settingsProvider.containerTypes
                                      : ['drawer'];
                              // If current selection isn't in list (e.g. data from DB but setting removed), add it temporarily or default
                              // For now, assume data integrity or fallback
                              final currentItems = items.contains(_selectedType)
                                  ? items
                                  : [...items, _selectedType];

                              return _buildDropdown(
                                value: _selectedType,
                                label: 'Type',
                                icon: Icons.category_outlined,
                                items: currentItems,
                                onChanged: (val) =>
                                    setState(() => _selectedType = val!),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            controller: _capacityController,
                            label: 'Capacity',
                            icon: Icons.grid_3x3,
                            hint: 'Slots',
                            required: true,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            validator: (value) {
                              if (value?.isEmpty ?? true) return 'Required';
                              final num = int.tryParse(value!);
                              if (num == null || num < 1) return 'Invalid';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final items =
                                  settingsProvider.weightCategories.isNotEmpty
                                      ? settingsProvider.weightCategories
                                      : ['light'];
                              final currentItems =
                                  items.contains(_selectedWeightCategory)
                                      ? items
                                      : [...items, _selectedWeightCategory];

                              return _buildDropdown(
                                value: _selectedWeightCategory,
                                label: 'Weight Category',
                                icon: Icons.scale_outlined,
                                items: currentItems,
                                onChanged: (val) => setState(
                                    () => _selectedWeightCategory = val!),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final items =
                                  settingsProvider.layoutTypes.isNotEmpty
                                      ? settingsProvider.layoutTypes
                                      : ['grid'];
                              final currentItems =
                                  items.contains(_selectedLayoutType)
                                      ? items
                                      : [...items, _selectedLayoutType];

                              return _buildDropdown(
                                value: _selectedLayoutType,
                                label: 'Layout Type',
                                icon: Icons.view_module_outlined,
                                items: currentItems,
                                onChanged: (val) =>
                                    setState(() => _selectedLayoutType = val!),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Metal and Purity
                    const SizedBox(height: 12),

                    // Metal Type Section
                    const Text('Metal Type',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: (settingsProvider.metalTypes.isEmpty
                              ? ['gold']
                              : settingsProvider.metalTypes)
                          .map((type) {
                        final isSelected = _selectedMetalTypes.contains(type);
                        return FilterChip(
                          label: Text(
                            _formatText(type),
                            style: TextStyle(
                              color:
                                  isSelected ? Colors.white : Colors.grey[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          selected: isSelected,
                          showCheckmark: false,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedMetalTypes.add(type);
                              } else {
                                if (_selectedMetalTypes.length > 1) {
                                  // Prevent empty selection
                                  _selectedMetalTypes.remove(type);
                                }
                              }
                            });
                          },
                          selectedColor: AppColors.primary,
                          checkmarkColor: Colors.white,
                          backgroundColor: Colors.white.withOpacity(0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.grey[300]!,
                              width: 1.5,
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 12),

                    // Purity Section
                    const Text('Purity (Optional)',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ([
                        'all',
                        ...settingsProvider.purityOptions.isEmpty
                            ? ['916']
                            : settingsProvider.purityOptions
                      ]).map((type) {
                        final isSelected = _selectedPurity.contains(type);
                        return FilterChip(
                          label: Text(
                            type == 'all' ? 'All' : type,
                            style: TextStyle(
                              color:
                                  isSelected ? Colors.white : Colors.grey[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          selected: isSelected,
                          showCheckmark: false,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedPurity.add(type);
                              } else {
                                if (_selectedPurity.length > 1) {
                                  // Prevent empty selection
                                  _selectedPurity.remove(type);
                                }
                              }
                            });
                          },
                          selectedColor: AppColors.primary,
                          checkmarkColor: Colors.white,
                          backgroundColor: Colors.white.withOpacity(0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.grey[300]!,
                              width: 1.5,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Allowed Item Types',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: (settingsProvider.itemTypes.isNotEmpty
                              ? settingsProvider.itemTypes
                              : ['ring'])
                          .map((type) {
                        final isSelected = _selectedItemTypes.contains(type);
                        return FilterChip(
                          label: Text(
                            _formatText(type),
                            style: TextStyle(
                              color:
                                  isSelected ? Colors.white : Colors.grey[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          selected: isSelected,
                          showCheckmark: false,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedItemTypes.add(type);
                              } else {
                                _selectedItemTypes.remove(type);
                              }
                              // NOT calling _generateBarcode() here as per user request
                            });
                          },
                          selectedColor: AppColors.primary,
                          checkmarkColor: Colors.white,
                          backgroundColor: Colors.white.withOpacity(0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.grey[300]!,
                              width: 1.5,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Image Upload Section (can modify to show existing image if url exists, but for now reuse logic)
                _buildImagePickerSection(),
                const SizedBox(height: 12),

                // Barcode Display Section
                _buildBarcodeSection(),
                const SizedBox(height: 16),

                // Save Button
                Consumer<ContainerProvider>(
                  builder: (context, provider, child) {
                    return SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: provider.isLoading ? null : _updateContainer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: provider.isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.save, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Update Container',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Delete Button
                SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _deleteContainer,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.delete_outline, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Delete Container',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteContainer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Container'),
        content: const Text(
            'Are you sure you want to delete this container? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final containerProvider =
          Provider.of<ContainerProvider>(context, listen: false);
      final success =
          await containerProvider.deleteContainer(widget.container.id);

      if (mounted) {
        if (success) {
          showAppSnackBar(
            context,
            const SnackBar(content: Text('Container deleted successfully')),
          );
          // Pop twice to go back to list (once for dialog which is handled, once for screen)
          // Actually nav pop passed true/false. We need to pop screen.
          Navigator.pop(context); // Pop edit screen
          if (Navigator.canPop(context))
            Navigator.pop(context); // Pop detail screen if we came from there
        } else {
          showAppSnackBar(
            context,
            SnackBar(
              content:
                  Text(containerProvider.error ?? 'Failed to delete container'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildBarcodeSection() {
    final showCustom = _generatedBarcode.isNotEmpty;
    final barcodeData = showCustom ? _generatedBarcode : widget.container.id;
    final isDefaultId = !showCustom;

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.grey[200]!,
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: BarcodeWidget(
                      barcode: Barcode.code128(),
                      data: barcodeData,
                      width: 150,
                      height: 50,
                      drawText: false,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isDefaultId
                        ? '${barcodeData.length > 8 ? barcodeData.substring(barcodeData.length - 8) : barcodeData} (Default)'
                        : barcodeData,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDefaultId ? Colors.grey : Colors.black,
                      letterSpacing: 2,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Manual change button
        OutlinedButton.icon(
          onPressed: _generateBarcode,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Change Barcode'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: BorderSide(color: AppColors.primary),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  // ... (keeping _buildSectionCard, _buildTextField, _buildDropdown, _buildImagePickerSection as is)
  // Re-declare them here if needed to assume context, but replacing from _buildBarcodeSection down to end of class is risky if I miss helpers.
  // I will target the build method specifically where buttons are to add delete, and replace _buildBarcodeSection separately or in same chunk if possible.

  // This replacement block is getting too complex to merge perfectly with context unless I include everything.
  // Strategy: Add _deleteContainer method at top of class (or before build), modify build to include button, modify _buildBarcodeSection.

  // Let's do partial replacements.

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey[200]!,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty) ...[
              Row(
                children: [
                  Icon(icon, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    bool required = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label + (required ? ' *' : ''),
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.primary),
        filled: true,
        fillColor: Colors.grey[50], // Slightly different for text fields
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      validator: validator ??
          (required
              ? (value) => value?.isEmpty ?? true ? 'Required' : null
              : null),
    );
  }

  Widget _buildDropdown({
    required String value,
    required String label,
    required IconData icon,
    required List<String> items,
    required void Function(String?) onChanged,
    bool translate = true,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: '$label *',
        prefixIcon: Icon(icon, color: AppColors.primary),
        filled: true,
        fillColor: Colors.grey[50],
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      items: items.map((item) {
        return DropdownMenuItem(
          value: item,
          child: Text(
            translate ? _formatText(item) : item.toUpperCase(),
            style: const TextStyle(fontSize: 14),
          ),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildImagePickerSection() {
    final hasExistingImage = _existingImageUrl != null;
    final hasUploadedImage = _uploadedImageUrl != null;
    final hasAnyImage = hasExistingImage || hasUploadedImage;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          // Show existing image
          if (hasExistingImage && !hasUploadedImage)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    _existingImageUrl!,
                    height: 100,
                    width: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 100,
                      width: 100,
                      color: Colors.grey[200],
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                ),
                if (_isDeletingImage)
                  Container(
                    height: 100,
                    width: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
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
                  right: 4,
                  child: GestureDetector(
                    onTap: _isDeletingImage
                        ? null
                        : () => _removeImage(isExisting: true),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _isDeletingImage ? Colors.grey : Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),

          // Show uploaded image
          if (hasUploadedImage)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    _uploadedImageUrl!,
                    height: 100,
                    width: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 100,
                      width: 100,
                      color: Colors.grey[200],
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                ),
                if (_isDeletingImage)
                  Container(
                    height: 100,
                    width: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
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
                  right: 4,
                  child: GestureDetector(
                    onTap: _isDeletingImage
                        ? null
                        : () => _removeImage(isExisting: false),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _isDeletingImage ? Colors.grey : Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),

          // Show upload progress
          if (_isUploadingImage)
            Container(
              height: 100,
              width: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.withOpacity(0.5)),
                color: Colors.blue.withOpacity(0.1),
              ),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),

          // Show add/replace button
          if (!_isUploadingImage)
            InkWell(
              onTap: _pickImage,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate,
                        color: AppColors.primary, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      hasAnyImage ? 'Replace Image' : 'Add Image',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
