import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/container_provider.dart';
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
  
  String _selectedType = 'drawer';
  String _selectedWeightCategory = 'light';
  String _selectedLayoutType = 'grid';
  List<String> _selectedItemTypes = [];

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
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
        title: const Text(
          'Add New Container',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // Basic Information
            _buildSectionCard(
              title: 'Basic Info',
              icon: Icons.inventory_2_outlined,
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
                      child: _buildDropdown(
                        value: _selectedType,
                        label: 'Type',
                        icon: Icons.category_outlined,
                        items: const ['drawer', 'shelf', 'box', 'tray', 'custom'],
                        onChanged: (value) => setState(() => _selectedType = value!),
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
              ],
            ),
            const SizedBox(height: 12),

            // Configuration
            _buildSectionCard(
              title: 'Configuration',
              icon: Icons.settings_outlined,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildDropdown(
                        value: _selectedWeightCategory,
                        label: 'Weight Category',
                        icon: Icons.scale_outlined,
                        items: const ['light', 'medium', 'heavy', 'mixed'],
                        onChanged: (value) => setState(() => _selectedWeightCategory = value!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDropdown(
                        value: _selectedLayoutType,
                        label: 'Layout',
                        icon: Icons.view_module_outlined,
                        items: const ['grid', 'linear', 'custom'],
                        onChanged: (value) => setState(() => _selectedLayoutType = value!),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Allowed Item Types
            _buildSectionCard(
              title: 'Allowed Item Types',
              icon: Icons.check_circle_outline,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AppConstants.itemTypes.map((type) {
                    final isSelected = _selectedItemTypes.contains(type);
                    return FilterChip(
                      label: Text(
                        type[0].toUpperCase() + type.substring(1),
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedItemTypes.add(type);
                          } else {
                            _selectedItemTypes.remove(type);
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
                const SizedBox(height: 8),
                Text(
                  'Select item types that can be stored in this container',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
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
}
