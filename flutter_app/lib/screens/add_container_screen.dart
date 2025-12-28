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
  
  String _selectedType = 'drawer';
  String _selectedWeightCategory = 'light';
  String _selectedLayoutType = 'grid';
  List<String> _selectedItemTypes = [];
  
  // Image picker state
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  
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
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _selectedImageBytes = bytes;
          _selectedImageName = image.name;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImageBytes = null;
      _selectedImageName = null;
    });
  }

  void _generateBarcode() {
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
        'layoutType': _selectedLayoutType,
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
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Add Container'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.background,
              Colors.white,
            ],
          ),
        ),
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
                        ? const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          )
                        : const Text(
                            'Create Container',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
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
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1.5,
            ),
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
              if (title.isNotEmpty) ...[
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
              ],
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
          child: Text(item[0].toUpperCase() + item.substring(1)),
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
      child: _selectedImageBytes != null
          ? Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(
                    _selectedImageBytes!,
                    height: 60,
                    width: 60,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedImageName ?? 'Image',
                    style: const TextStyle(fontSize: 13),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          BarcodeWidget(
            barcode: Barcode.code128(),
            data: _generatedBarcode,
            width: 200,
            height: 60,
            drawText: false,
          ),
          const SizedBox(height: 8),
          Text(
            _generatedBarcode,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  String _formatText(String text) {
    return text[0].toUpperCase() + text.substring(1);
  }
}
