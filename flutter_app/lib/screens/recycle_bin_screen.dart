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

  Future<void> _handleRestoreItem(Item item) async {
    try {
      // Fetch all containers to check if previous container is valid
      final containerProvider = Provider.of<ContainerProvider>(context, listen: false);
      await containerProvider.fetchContainers();
      
      final containers = containerProvider.containers;
      
      // Check if item has a previous container
      if (item.containerId != null && item.containerId!.isNotEmpty) {
        // Find the previous container
        final previousContainer = containers.where((c) => c.id == item.containerId).firstOrNull;
        
        if (previousContainer != null && 
            previousContainer.isActive && 
            !previousContainer.isLocked && 
            previousContainer.availableSlots > 0) {
          // Previous container is valid, restore directly
          await _restoreItemToContainer(item, item.containerId!, item.slotNumber);
          return;
        }
      }
      
      // Previous container is invalid or doesn't exist, show container selection dialog
      await _showContainerSelectionDialog(item);
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking containers: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showContainerSelectionDialog(Item item) async {
    final containerProvider = Provider.of<ContainerProvider>(context, listen: false);
    final containers = containerProvider.containers;
    
    // Filter assignable containers for this item
    final assignableContainers = containers.where((c) {
      return c.isActive && 
             !c.isLocked && 
             c.availableSlots > 0 &&
             c.metalType.any((m) => m.toLowerCase() == item.metalType.toLowerCase()) &&
             c.allowedItemTypes.any((t) => t.toLowerCase() == item.itemType.toLowerCase());
    }).toList();
    
    if (assignableContainers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No valid containers available for this item. Please create or unlock a suitable container first.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }
    
    // Show dialog to select container
    String? selectedContainerId;
    int? selectedSlotNumber;
    
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Select Container'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Previous container is not available. Please select a new container for "${item.name}".',
                style: TextStyle(color: Colors.grey[700], fontSize: 14),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Container',
                  border: OutlineInputBorder(),
                ),
                items: assignableContainers.map((container) {
                  return DropdownMenuItem(
                    value: container.id,
                    child: Text(
                      '${container.name} (${container.availableSlots}/${container.capacity} slots)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  selectedContainerId = value;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Slot Number (Optional)',
                  border: OutlineInputBorder(),
                  hintText: 'Leave empty for auto-assign',
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  selectedSlotNumber = int.tryParse(value);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (selectedContainerId != null) {
                _restoreItemToContainer(item, selectedContainerId!, selectedSlotNumber);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreItemToContainer(Item item, String containerId, int? slotNumber) async {
    try {
      final response = await _apiService.restoreItem(item.id, containerId, slotNumber);
      
      if (mounted) {
        if (response['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${item.name} restored successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData(); // Refresh the list
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Failed to restore item'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error restoring item: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'Recycle Bin',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
          bottom: const TabBar(
            labelColor: Color(0xFFE94560),
            unselectedLabelColor: Colors.grey,
            indicatorColor: Color(0xFFE94560),
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
                    const SizedBox(height: 8),
                    
                    // Restore Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _handleRestoreItem(item),
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('Restore Item'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
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
