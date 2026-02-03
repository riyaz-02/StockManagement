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
import '../services/api_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_constants.dart';

class AddContainerScreen extends StatefulWidget {
  const AddContainerScreen({super.key});

  @override
  State<AddContainerScreen> createState() => _AddContainerScreenState();
}

class _AddContainerScreenState extends State<AddContainerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _capacityController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final ApiService _apiService = ApiService();
  
  String _selectedType = 'drawer';
  String _selectedWeightCategory = 'light';

  List<String> _selectedMetalTypes = [];
  List<String> _selectedPurity = [];
  String _selectedLayoutType = 'grid';
  List<String> _selectedItemTypes = [];
  
  // Image upload state
  String? _uploadedImageUrl;
  bool _isUploadingImage = false;
  
  // Barcode state
  String _generatedBarcode = '';
  int _barcodeSerial = 1;

  @override
  void initState() {
    super.initState();
    // Fetch settings and set defaults
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      await Future.wait([
        settingsProvider.fetchContainerSettings(),
        settingsProvider.fetchItemSettings(),
      ]);
      
      if (mounted) {
        setState(() {
          // Update selected values to match loaded settings
          if (settingsProvider.containerTypes.isNotEmpty) {
            _selectedType = settingsProvider.containerTypes.first;
          }
          if (settingsProvider.weightCategories.isNotEmpty) {
            _selectedWeightCategory = settingsProvider.weightCategories.first;
          }
          if (settingsProvider.layoutTypes.isNotEmpty) {
            _selectedLayoutType = settingsProvider.layoutTypes.first;
          }
          if (settingsProvider.metalTypes.isNotEmpty) {
            _selectedMetalTypes = [settingsProvider.metalTypes.first];
          }
          _selectedPurity = ['all'];
        });
      }
    });
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
              leading: const Icon(Icons.photo_library, color: AppColors.primary),
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
        final result = await _apiService.uploadImage(image, folder: 'containers');
        
        if (result['success'] == true) {
          final imageUrl = result['data']['url'];
          setState(() {
            _uploadedImageUrl = imageUrl;
            _isUploadingImage = false;
          });
          print('[UPLOAD] ✅ Uploaded: $imageUrl');
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Image uploaded successfully'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          throw Exception('Upload failed');
        }
      } catch (e) {
        setState(() => _isUploadingImage = false);
        print('[UPLOAD] ❌ Failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to upload image: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isUploadingImage = false);
    }
  }

  void _removeImage() {
    setState(() {
      _uploadedImageUrl = null;
    });
  }

  Future<void> _generateBarcode() async {
    if (_selectedItemTypes.isEmpty) {
      setState(() {
        _generatedBarcode = '';
      });
      return;
    }

    String prefix;
    if (_selectedItemTypes.length == 1) {
      final type = _selectedItemTypes.first.toUpperCase();
      prefix = type.substring(0, 1);
    } else {
      prefix = 'M';
    }

    final containerProvider = Provider.of<ContainerProvider>(context, listen: false);
    _barcodeSerial = await containerProvider.getNextSerial(prefix);

    setState(() {
      _generatedBarcode = '$prefix$_barcodeSerial';
    });
  }

  Future<void> _saveContainer() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedItemTypes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select at least one item type'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final containerProvider = Provider.of<ContainerProvider>(context, listen: false);

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
        if (_uploadedImageUrl != null) 'image': _uploadedImageUrl,
      };

      final success = await containerProvider.createContainer(containerData);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Container created successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(containerProvider.error ?? 'Failed to create container'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    
    // Wait for settings to load before showing form
    if (settingsProvider.containerTypes.isEmpty || 
        settingsProvider.weightCategories.isEmpty || 
        settingsProvider.layoutTypes.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add Container')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Add Container',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
      body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
            // All fields in single section (no title/icon)
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
                          final items = Provider.of<SettingsProvider>(context).containerTypes.isNotEmpty
                              ? Provider.of<SettingsProvider>(context).containerTypes
                              : ['drawer'];
                          // Ensure value exists in items
                          final value = items.contains(_selectedType) ? _selectedType : items.first;
                          return _buildDropdown(
                            value: value,
                            label: 'Type',
                            icon: Icons.category_outlined,
                            items: items,
                            onChanged: (val) => setState(() => _selectedType = val!),
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
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                // Metal and Purity Row
                const SizedBox(height: 12),
                
                // Metal Type Section
                const Text('Metal Type', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: (Provider.of<SettingsProvider>(context).metalTypes.isEmpty 
                      ? ['gold'] 
                      : Provider.of<SettingsProvider>(context).metalTypes).map((type) {
                    final isSelected = _selectedMetalTypes.contains(type);
                    return FilterChip(
                      label: Text(
                        type[0].toUpperCase() + type.substring(1),
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[700],
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
                            if (_selectedMetalTypes.length > 1) { // Prevent empty selection
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
                          color: isSelected ? AppColors.primary : Colors.grey[300]!,
                          width: 1.5,
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 12),

                // Purity Section
                const Text('Purity (Optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: (['all', ...Provider.of<SettingsProvider>(context).purityOptions.isEmpty 
                      ? ['916'] 
                      : Provider.of<SettingsProvider>(context).purityOptions]).map((type) {
                    final isSelected = _selectedPurity.contains(type);
                    return FilterChip(
                      label: Text(
                        type == 'all' ? 'All' : type,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[700],
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
                            if (_selectedPurity.length > 1) { // Prevent empty selection
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
                          color: isSelected ? AppColors.primary : Colors.grey[300]!,
                          width: 1.5,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final items = Provider.of<SettingsProvider>(context).weightCategories.isNotEmpty
                              ? Provider.of<SettingsProvider>(context).weightCategories
                              : ['light'];
                          final value = items.contains(_selectedWeightCategory) ? _selectedWeightCategory : items.first;
                          return _buildDropdown(
                            value: value,
                            label: 'Weight Category',
                            icon: Icons.scale_outlined,
                            items: items,
                            onChanged: (val) => setState(() => _selectedWeightCategory = val!),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final items = Provider.of<SettingsProvider>(context).layoutTypes.isNotEmpty
                              ? Provider.of<SettingsProvider>(context).layoutTypes
                              : ['grid'];
                          final value = items.contains(_selectedLayoutType) ? _selectedLayoutType : items.first;
                          return _buildDropdown(
                            value: value,
                            label: 'Layout Type',
                            icon: Icons.view_module_outlined,
                            items: items,
                            onChanged: (val) => setState(() => _selectedLayoutType = val!),
                          );
                        },
                      ),
                    ),
                  ],
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
                  children: (Provider.of<SettingsProvider>(context).itemTypes.isNotEmpty
                      ? Provider.of<SettingsProvider>(context).itemTypes
                      : ['ring']).map((type) {
                    final isSelected = _selectedItemTypes.contains(type);
                    return FilterChip(
                      label: Text(
                        _formatText(type),
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[700],
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
                          _generateBarcode();
                        });
                      },
                      selectedColor: AppColors.primary,
                      checkmarkColor: Colors.white,
                      backgroundColor: Colors.white.withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: isSelected ? AppColors.primary : Colors.grey[300]!,
                          width: 1.5,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Image Upload Section
            _buildImagePickerSection(),
            const SizedBox(height: 12),
            
            // Barcode Display Section
            if (_generatedBarcode.isNotEmpty) _buildBarcodeSection(),
            const SizedBox(height: 16),

            // Save Button
            Consumer<ContainerProvider>(
              builder: (context, provider, child) {
                return SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: provider.isLoading ? null : _saveContainer,
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
                              Icon(Icons.add_circle_outline, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Create Container',
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
          ],
        ),
      ),
      ),
    );
  }

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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      items: items.map((item) {
        return DropdownMenuItem(
          value: item,
          child: Text(
            translate ? item[0].toUpperCase() + item.substring(1) : item.toUpperCase(), 
          ),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildImagePickerSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: _isUploadingImage
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          : _uploadedImageUrl != null
              ? Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        _uploadedImageUrl!,
                        height: 60,
                        width: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Image uploaded',
                        style: TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: _removeImage,
                      color: Colors.red,
                      tooltip: 'Remove',
                    ),
                  ],
                )
              : InkWell(
                  onTap: _pickImage,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate, color: AppColors.primary, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          'Add Image',
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
    );
  }

  Widget _buildBarcodeSection() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: AnimatedOpacity(
        opacity: _generatedBarcode.isNotEmpty ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
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
                    data: _generatedBarcode,
                    width: 150,
                    height: 50,
                    drawText: false,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _generatedBarcode,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatText(String text) {
    return text[0].toUpperCase() + text.substring(1);
  }
}
