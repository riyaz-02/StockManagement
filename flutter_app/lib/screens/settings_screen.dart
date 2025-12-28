import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../utils/app_colors.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Item Settings
  List<String> itemTypes = ['ring', 'necklace', 'earring', 'bracelet', 'pendant', 'chain', 'bangle'];
  List<String> metalTypes = ['gold', 'silver', 'mixed', 'gold-coated', 'platinum'];
  List<String> purityOptions = ['916', '22k', '18k', '14k', 'silver925', 'silver999', 'platinum950'];

  // Container Settings
  List<String> containerTypes = ['drawer', 'shelf', 'box', 'tray', 'custom'];
  List<String> weightCategories = ['light', 'medium', 'heavy', 'mixed'];
  List<String> layoutTypes = ['grid', 'linear', 'custom'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    
    // Check if user is admin
    if (authProvider.user?.role != 'admin') {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Admin Access Required',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Only administrators can access settings',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

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
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w600)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.inventory), text: 'Item Settings'),
            Tab(icon: Icon(Icons.inventory_2), text: 'Container Settings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildItemSettings(),
          _buildContainerSettings(),
        ],
      ),
    );
  }

  Widget _buildItemSettings() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildSettingSection(
          title: 'Item Types',
          icon: Icons.category_outlined,
          items: itemTypes,
          onAdd: () => _showAddDialog('Item Type', (value) {
            setState(() => itemTypes.add(value));
          }),
          onEdit: (index) => _showEditDialog('Item Type', itemTypes[index], (value) {
            setState(() => itemTypes[index] = value);
          }),
          onDelete: (index) => _showDeleteDialog(itemTypes[index], () {
            setState(() => itemTypes.removeAt(index));
          }),
        ),
        const SizedBox(height: 12),
        _buildSettingSection(
          title: 'Metal Types',
          icon: Icons.diamond_outlined,
          items: metalTypes,
          onAdd: () => _showAddDialog('Metal Type', (value) {
            setState(() => metalTypes.add(value));
          }),
          onEdit: (index) => _showEditDialog('Metal Type', metalTypes[index], (value) {
            setState(() => metalTypes[index] = value);
          }),
          onDelete: (index) => _showDeleteDialog(metalTypes[index], () {
            setState(() => metalTypes.removeAt(index));
          }),
        ),
        const SizedBox(height: 12),
        _buildSettingSection(
          title: 'Purity Options',
          icon: Icons.verified_outlined,
          items: purityOptions,
          onAdd: () => _showAddDialog('Purity Option', (value) {
            setState(() => purityOptions.add(value));
          }),
          onEdit: (index) => _showEditDialog('Purity Option', purityOptions[index], (value) {
            setState(() => purityOptions[index] = value);
          }),
          onDelete: (index) => _showDeleteDialog(purityOptions[index], () {
            setState(() => purityOptions.removeAt(index));
          }),
        ),
      ],
    );
  }

  Widget _buildContainerSettings() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildSettingSection(
          title: 'Container Types',
          icon: Icons.inventory_2_outlined,
          items: containerTypes,
          onAdd: () => _showAddDialog('Container Type', (value) {
            setState(() => containerTypes.add(value));
          }),
          onEdit: (index) => _showEditDialog('Container Type', containerTypes[index], (value) {
            setState(() => containerTypes[index] = value);
          }),
          onDelete: (index) => _showDeleteDialog(containerTypes[index], () {
            setState(() => containerTypes.removeAt(index));
          }),
        ),
        const SizedBox(height: 12),
        _buildSettingSection(
          title: 'Weight Categories',
          icon: Icons.scale_outlined,
          items: weightCategories,
          onAdd: () => _showAddDialog('Weight Category', (value) {
            setState(() => weightCategories.add(value));
          }),
          onEdit: (index) => _showEditDialog('Weight Category', weightCategories[index], (value) {
            setState(() => weightCategories[index] = value);
          }),
          onDelete: (index) => _showDeleteDialog(weightCategories[index], () {
            setState(() => weightCategories.removeAt(index));
          }),
        ),
        const SizedBox(height: 12),
        _buildSettingSection(
          title: 'Layout Types',
          icon: Icons.view_module_outlined,
          items: layoutTypes,
          onAdd: () => _showAddDialog('Layout Type', (value) {
            setState(() => layoutTypes.add(value));
          }),
          onEdit: (index) => _showEditDialog('Layout Type', layoutTypes[index], (value) {
            setState(() => layoutTypes[index] = value);
          }),
          onDelete: (index) => _showDeleteDialog(layoutTypes[index], () {
            setState(() => layoutTypes.removeAt(index));
          }),
        ),
      ],
    );
  }

  Widget _buildSettingSection({
    required String title,
    required IconData icon,
    required List<String> items,
    required VoidCallback onAdd,
    required void Function(int) onEdit,
    required void Function(int) onDelete,
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: items.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  return Chip(
                    label: Text(
                      item[0].toUpperCase() + item.substring(1).replaceAll('-', ' '),
                      style: const TextStyle(fontSize: 13),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () => onDelete(index),
                    backgroundColor: Colors.white.withOpacity(0.7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey[300]!),
                    ),
                    avatar: IconButton(
                      icon: const Icon(Icons.edit, size: 16),
                      onPressed: () => onEdit(index),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
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

  void _showAddDialog(String itemName, void Function(String) onAdd) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                onAdd(controller.text.trim().toLowerCase().replaceAll(' ', '-'));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$itemName added successfully'), backgroundColor: Colors.green),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(String itemName, String currentValue, void Function(String) onEdit) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Edit $itemName'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: itemName,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                onEdit(controller.text.trim().toLowerCase().replaceAll(' ', '-'));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$itemName updated successfully'), backgroundColor: Colors.green),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(String item, VoidCallback onDelete) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Confirm Delete'),
          ],
        ),
        content: Text('Are you sure you want to delete "$item"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              onDelete();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Deleted successfully'), backgroundColor: Colors.red),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
