import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/app_constants.dart';
import '../models/item_model.dart';
import 'item_details_screen.dart';

class MovedOutItemsScreen extends StatefulWidget {
  const MovedOutItemsScreen({Key? key}) : super(key: key);

  @override
  State<MovedOutItemsScreen> createState() => _MovedOutItemsScreenState();
}

class _MovedOutItemsScreenState extends State<MovedOutItemsScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _movements = [];
  bool _isLoading = true;
  String _selectedFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadMovedOutItems();
  }

  Future<void> _loadMovedOutItems() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.getOutwardMovements(status: 'OUT');
      if (response['success'] == true) {
        setState(() {
          _movements = response['data']['movements'] ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading items: $e')),
      );
    }
  }

  List<dynamic> get _filteredMovements {
    if (_selectedFilter == 'ALL') return _movements;
    return _movements.where((m) => m['movementType'] == _selectedFilter).toList();
  }

  List<dynamic> get _repairMovements =>
      _movements.where((m) => m['movementType'] == 'REPAIR').toList();
  
  List<dynamic> get _customerMovements =>
      _movements.where((m) => m['movementType'] == 'CUSTOMER_TRIAL').toList();
  
  List<dynamic> get _agentMovements =>
      _movements.where((m) => m['movementType'] == 'AGENT_CONSIGNMENT').toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Moved Out Items'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMovedOutItems,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _movements.isEmpty
              ? const Center(child: Text('No items currently moved out'))
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Filter Chips
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildFilterChip('ALL', Icons.all_inclusive, _movements.length),
                              const SizedBox(width: 8),
                              _buildFilterChip('REPAIR', Icons.build, _repairMovements.length),
                              const SizedBox(width: 8),
                              _buildFilterChip('CUSTOMER_TRIAL', Icons.person, _customerMovements.length),
                              const SizedBox(width: 8),
                              _buildFilterChip('AGENT_CONSIGNMENT', Icons.store, _agentMovements.length),
                            ],
                          ),
                        ),
                      ),

                      // Categorized Lists
                      if (_selectedFilter == 'ALL') ...[
                        if (_repairMovements.isNotEmpty)
                          _buildCategorySection('🔧 Under Repair', _repairMovements, Colors.orange),
                        if (_customerMovements.isNotEmpty)
                          _buildCategorySection('👤 With Customer', _customerMovements, Colors.blue),
                        if (_agentMovements.isNotEmpty)
                          _buildCategorySection('🏪 With Agent', _agentMovements, Colors.purple),
                      ] else
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: _filteredMovements.map((m) => _buildMovementCard(m)).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildFilterChip(String filter, IconData icon, int count) {
    final isSelected = _selectedFilter == filter;
    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text(filter == 'ALL' ? 'All' : 
               filter == 'REPAIR' ? 'Repair' :
               filter == 'CUSTOMER_TRIAL' ? 'Customer' : 'Agent'),
          const SizedBox(width: 4),
          Text('($count)', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      onSelected: (selected) {
        setState(() => _selectedFilter = filter);
      },
    );
  }

  Widget _buildCategorySection(String title, List<dynamic> movements, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$title (${movements.length})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: movements.map((m) => _buildMovementCard(m)).toList(),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildMovementCard(Map<String, dynamic> movement) {
    final item = movement['itemId'];
    if (item == null) return const SizedBox.shrink();

    final outDate = movement['outDate']?.toString().split('T')[0] ?? 'N/A';
    final expectedReturn = movement['expectedReturnDate']?.toString().split('T')[0] ?? 'N/A';
    
    // Check if overdue
    final isOverdue = movement['expectedReturnDate'] != null &&
        DateTime.parse(movement['expectedReturnDate']).isBefore(DateTime.now());

    // Get who has it
    String whoHasIt = '';
    String contactInfo = '';
    
    if (movement['movementType'] == 'REPAIR') {
      whoHasIt = movement['givenTo'] ?? 'Unknown';
      if (movement['repairType'] != null) contactInfo = movement['repairType'];
    } else if (movement['movementType'] == 'CUSTOMER_TRIAL') {
      whoHasIt = movement['customerName'] ?? 'Unknown';
      contactInfo = movement['customerMobile'] ?? '';
    } else if (movement['movementType'] == 'AGENT_CONSIGNMENT') {
      whoHasIt = movement['partyName'] ?? 'Unknown';
      contactInfo = movement['partyType'] ?? '';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          // Fetch full item data first
          try {
            final itemResponse = await _apiService.getItem(item['_id']);
            if (itemResponse['success'] == true) {
              final itemData = itemResponse['data']['item'];
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ItemDetailsScreen(item: Item.fromJson(itemData)),
                ),
              ).then((_) => _loadMovedOutItems());
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error loading item: $e')),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Item Image
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: item['images'] != null && (item['images'] as List).isNotEmpty
                    ? Image.network(
                        item['images'][0].startsWith('http')
                            ? item['images'][0]
                            : '${AppConstants.baseUrl}/${item['images'][0].replaceAll('\\', '/')}',
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 60,
                          height: 60,
                          color: Colors.grey[300],
                          child: const Icon(Icons.diamond, size: 30),
                        ),
                      )
                    : Container(
                        width: 60,
                        height: 60,
                        color: Colors.grey[300],
                        child: const Icon(Icons.diamond, size: 30),
                      ),
              ),
              const SizedBox(width: 12),
              
              // Item Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['name'] ?? 'Unknown Item',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                        if (isOverdue)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'OVERDUE',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item['netWeight']}g | ${item['metalType'] ?? 'N/A'}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          movement['movementType'] == 'REPAIR' ? Icons.build :
                          movement['movementType'] == 'CUSTOMER_TRIAL' ? Icons.person :
                          Icons.store,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            whoHasIt,
                            style: TextStyle(fontSize: 12, color: Colors.grey[800], fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    if (contactInfo.isNotEmpty)
                      Text(
                        contactInfo,
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Out: $outDate | Return: $expectedReturn',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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
}
