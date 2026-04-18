import 'package:flutter/material.dart';
import '../models/item_model.dart';
import '../services/api_service.dart';
import 'quick_add_item_screen.dart';

class ActionNeededItemsScreen extends StatefulWidget {
  const ActionNeededItemsScreen({super.key});

  @override
  State<ActionNeededItemsScreen> createState() => _ActionNeededItemsScreenState();
}

class _ActionNeededItemsScreenState extends State<ActionNeededItemsScreen> {
  static const Color _orange = Color(0xFFFF6B35);
  static const Color _primary = Color(0xFFE94560);

  final ApiService _api = ApiService();

  bool _loading = true;
  String? _error;
  List<Item> _items = [];

  @override
  void initState() {
    super.initState();
    _fetchItems();
  }

  Future<void> _fetchItems() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _api.getItems(queryParams: {'status': 'action_needed'});
      if (response['success'] == true) {
        final rawItems = (response['data']['items'] as List?) ?? [];
        setState(() {
          _items = rawItems.map((j) => Item.fromJson(j as Map<String, dynamic>)).toList();
          _loading = false;
        });
      } else {
        setState(() {
          _error = response['message'] ?? 'Failed to load items';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openItemEditor(Item item) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => QuickAddItemScreen(item: item)),
    );
    // Refresh list if item was edited
    if (result == true) _fetchItems();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FC),
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Action Needed',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            if (_items.isNotEmpty) ...[
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _orange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_items.length}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade200, height: 1),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchItems,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 56, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _fetchItems,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 72, color: Colors.green.shade300),
            const SizedBox(height: 16),
            const Text('All clear!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('No items need attention right now.',
                style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Info banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: _orange.withOpacity(0.10),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: _orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'These items were added via quick-scan. Tap to complete details (container, name, etc.) and set status to Active.',
                  style: TextStyle(fontSize: 12, color: _orange),
                ),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchItems,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _ItemCard(
                item: _items[i],
                onTap: () => _openItemEditor(_items[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Item card ──────────────────────────────────────────────────────────────
class _ItemCard extends StatelessWidget {
  final Item item;
  final VoidCallback onTap;

  const _ItemCard({required this.item, required this.onTap});

  static const _orange = Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context) {
    final hasImage = item.images.isNotEmpty;
    final timeAgo = _formatTimeAgo(item.createdAt);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Image or placeholder
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: hasImage
                    ? Image.network(
                        item.images.first,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _imagePlaceholder(),
                      )
                    : _imagePlaceholder(),
              ),

              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Barcode + badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.barcode,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _orange.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Needs Review',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Metal + Purity + Weight
                    Text(
                      '${item.metalType.toUpperCase()}  •  ${item.purity.toUpperCase()}  •  ${item.netWeight}g',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Item type + time
                    Row(
                      children: [
                        Icon(Icons.category_outlined,
                            size: 12, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Text(
                          item.itemType[0].toUpperCase() +
                              item.itemType.substring(1),
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                        const Spacer(),
                        Icon(Icons.access_time_rounded,
                            size: 12, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Text(
                          timeAgo,
                          style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),
              Icon(Icons.edit_rounded, size: 20, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.image_not_supported_outlined,
          color: Colors.grey.shade400, size: 24),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
