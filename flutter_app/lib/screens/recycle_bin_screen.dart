import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/container_provider.dart';
import '../models/container_model.dart' as models;
import '../providers/language_provider.dart';
import '../utils/app_colors.dart';
import '../utils/app_constants.dart';
import 'container_view_screen.dart';
import 'item_details_screen.dart';
import '../services/api_service.dart';
import '../models/item_model.dart';

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
        backgroundColor: Colors.grey[100],
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
            return _buildContainerCard(container);
          },
        );
      },
    );
  }

  Widget _buildContainerCard(models.ItemContainer container) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ContainerViewScreen(container: container),
            ),
          ).then((_) => _loadData());
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Container Icon
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: const Icon(Icons.inventory_2_outlined, color: Colors.red, size: 30),
              ),
              const SizedBox(width: 16),
              
              // Container Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      container.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${container.type} • ${container.capacity} slots',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'QR: ${container.qrCode}',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              
              // Deleted Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.red.withOpacity(0.5)),
                ),
                child: const Text(
                  'Deleted',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
        
        // The API returns { success: true, data: { items: [...] } }
        final List items = (response?['data'] is Map) 
            ? (response?['data']['items'] as List?) ?? []
            : [];

        if (items.isEmpty) {
          return const Center(child: Text('No deleted items'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final itemData = items[index];
            final item = Item.fromJson(itemData);
            return _buildItemCard(item);
          },
        );
      },
    );
  }

  Widget _buildItemCard(Item item) {
    // Construct Image URL
    String? imageUrl;
    if (item.images.isNotEmpty) {
      final path = item.images.first;
      if (path.startsWith('http')) {
        imageUrl = path;
      } else {
        String cleanPath = path.replaceAll('\\', '/');
        imageUrl = '${AppConstants.baseUrl}/$cleanPath'; 
      }
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ItemDetailsScreen(item: item),
            ),
          ).then((_) => _loadData());
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Item Image
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: ClipRRect(
                   borderRadius: BorderRadius.circular(12),
                   child: imageUrl != null 
                       ? Image.network(
                           imageUrl, 
                           fit: BoxFit.cover,
                           errorBuilder: (_,__,___) => const Icon(Icons.broken_image, color: Colors.red),
                         )
                       : const Icon(Icons.diamond_outlined, size: 30, color: Colors.red),
                ),
              ),
              const SizedBox(width: 16),

              // Details Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name & Badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.barcode,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Deleted Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.red.withOpacity(0.5)),
                          ),
                          child: const Text(
                            'Deleted',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Specs Grid
                    Row(
                      children: [
                        _buildCompactSpec(Icons.scale, '${item.netWeight}g'),
                        const SizedBox(width: 12),
                        _buildCompactSpec(Icons.category, _formatText(item.itemType)),
                        const SizedBox(width: 12),
                        _buildCompactSpec(Icons.diamond, _formatText(item.metalType)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactSpec(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 11, color: Colors.grey[700]),
        ),
      ],
    );
  }

  String _formatText(String text) {
    if (text.isEmpty) return text;
    return text.split('_').map((word) => 
      word[0].toUpperCase() + word.substring(1).toLowerCase()
    ).join(' ');
  }
}
