import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';

class ContainerSettingsScreen extends StatefulWidget {
  const ContainerSettingsScreen({super.key});

  @override
  State<ContainerSettingsScreen> createState() => _ContainerSettingsScreenState();
}

class _ContainerSettingsScreenState extends State<ContainerSettingsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      Provider.of<SettingsProvider>(context, listen: false).fetchContainerSettings();
    });
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
        title: const Text('Container Settings', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _buildSettingSection(
                context,
                title: 'Container Types',
                icon: Icons.inventory_2_outlined,
                items: provider.containerTypes,
                onAdd: () => _showAddDialog(context, 'Container Type', 'container', 'containerTypes'),
                onDelete: (value) => _deleteValue(context, 'container', 'containerTypes', value),
              ),
              const SizedBox(height: 12),
              _buildSettingSection(
                context,
                title: 'Weight Categories',
                icon: Icons.scale_outlined,
                items: provider.weightCategories,
                onAdd: () => _showAddDialog(context, 'Weight Category', 'container', 'weightCategories'),
                onDelete: (value) => _deleteValue(context, 'container', 'weightCategories', value),
              ),
              const SizedBox(height: 12),
              _buildSettingSection(
                context,
                title: 'Layout Types',
                icon: Icons.view_module_outlined,
                items: provider.layoutTypes,
                onAdd: () => _showAddDialog(context, 'Layout Type', 'container', 'layoutTypes'),
                onDelete: (value) => _deleteValue(context, 'container', 'layoutTypes', value),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSettingSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<String> items,
    required VoidCallback onAdd,
    required void Function(String) onDelete,
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
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    color: AppColors.primary,
                    onPressed: onAdd,
                    tooltip: 'Add new',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'No items yet. Tap + to add.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: items.map((item) {
                    return Chip(
                      label: Text(
                        item[0].toUpperCase() + item.substring(1).replaceAll('-', ' '),
                        style: const TextStyle(fontSize: 13),
                      ),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () => onDelete(item),
                      backgroundColor: Colors.white.withOpacity(0.7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context, String itemName, String category, String type) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Add $itemName'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: itemName,
            hintText: 'Enter ${itemName.toLowerCase()}',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext);
                final value = controller.text.trim().toLowerCase().replaceAll(' ', '-');
                final provider = Provider.of<SettingsProvider>(context, listen: false);
                final success = await provider.addValue(category, type, value);
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? '$itemName added successfully' : 'Failed to add $itemName'),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _deleteValue(BuildContext context, String category, String type, String value) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Confirm Delete'),
          ],
        ),
        content: Text('Are you sure you want to delete "$value"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dialogContext);
              final provider = Provider.of<SettingsProvider>(context, listen: false);
              final success = await provider.deleteValue(category, type, value);
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? 'Deleted successfully' : 'Failed to delete'),
                    backgroundColor: success ? Colors.red : Colors.grey,
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
