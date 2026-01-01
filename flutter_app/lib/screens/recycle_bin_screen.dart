import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/container_provider.dart';
import '../models/container_model.dart' as models;
import '../providers/language_provider.dart';
import 'container_view_screen.dart';
import '../services/api_service.dart';
import '../models/item_model.dart'; // Ensure Item model is imported if needed, or use Map

class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  late Future<List<models.ItemContainer>> _deletedContainersFuture;
  late Future<Map<String, dynamic>> _deletedItemsFuture;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _deletedContainersFuture = Provider.of<ContainerProvider>(context, listen: false).fetchDeletedContainers();
      _deletedItemsFuture = _apiService.getDeletedItems();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Recycle Bin'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Containers', icon: Icon(Icons.inventory_2_outlined)),
              Tab(text: 'Items', icon: Icon(Icons.category_outlined)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildContainerList(),
            _buildItemList(),
          ],
        ),
      ),
    );
  }

  Widget _buildContainerList() {
    return FutureBuilder<List<models.ItemContainer>>(
      future: _deletedContainersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final deletedContainers = snapshot.data ?? [];

        if (deletedContainers.isEmpty) {
          return const Center(child: Text('No deleted containers'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: deletedContainers.length,
          itemBuilder: (context, index) {
            final container = deletedContainers[index];
            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
                title: Text(container.name),
                subtitle: Text('${container.capacity} slots'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                   Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ContainerViewScreen(container: container),
                    ),
                  ).then((_) => _loadData());
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildItemList() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _deletedItemsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final response = snapshot.data;
        final List items = response?['data'] ?? [];

        if (items.isEmpty) {
          return const Center(child: Text('No deleted items'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.red, child: Icon(Icons.delete_outline, color: Colors.white)),
                title: Text(item['name'] ?? 'Unnamed Item'),
                subtitle: Text('SKU: ${item['sku'] ?? 'N/A'}\nDeleted: ${item['updatedAt']?.toString().split('T')[0] ?? ''}'),
                isThreeLine: true,
                // Add Restore functionality later if requested
              ),
            );
          },
        );
      },
    );
  }
}
