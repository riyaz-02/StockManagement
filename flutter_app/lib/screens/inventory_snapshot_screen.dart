import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/tally_provider.dart';
import '../models/inventory_snapshot_model.dart';
import '../utils/app_colors.dart';

class InventorySnapshotScreen extends StatefulWidget {
  final String snapshotId;

  const InventorySnapshotScreen({super.key, required this.snapshotId});

  @override
  State<InventorySnapshotScreen> createState() =>
      _InventorySnapshotScreenState();
}

class _InventorySnapshotScreenState extends State<InventorySnapshotScreen> {
  InventorySnapshot? _snapshot;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final snapshot = await Provider.of<TallyProvider>(context, listen: false)
        .fetchInventorySnapshot(widget.snapshotId);
    if (mounted) {
      setState(() {
        _snapshot = snapshot;
        _isLoading = false;
      });
    }
  }

  Color _metalColor(String metal) {
    switch (metal.toLowerCase()) {
      case 'gold':
        return const Color(0xFFE5B80B);
      case 'silver':
        return const Color(0xFF9CA3AF);
      case 'platinum':
        return const Color(0xFF6B7280);
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Inventory Snapshot',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _snapshot == null
              ? const Center(child: Text('Snapshot not found'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        DateFormat('dd MMM yyyy, HH:mm')
                            .format(_snapshot!.date),
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w600),
                      ),
                      if (_snapshot!.tallyDescription != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'From tally: ${_snapshot!.tallyDescription}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                              child: _buildStatCard(
                                  '${_snapshot!.totalItems}', 'Items')),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _buildStatCard(
                                  '${_snapshot!.totalContainers}',
                                  'Containers')),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_snapshot!.byMetal.isNotEmpty) ...[
                        const Text('By Metal',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _snapshot!.byMetal
                              .map((m) => _buildMetalCard(m))
                              .toList(),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        'Items (${_snapshot!.items.length})',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ..._snapshot!.items.map((item) => _buildItemRow(item)),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatCard(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        ],
      ),
    );
  }

  Widget _buildMetalCard(MetalTotal metal) {
    final color = _metalColor(metal.metalType);
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metal.metalType.toUpperCase(),
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.5),
          ),
          const SizedBox(height: 6),
          Text(
            '${metal.totalWeight.toStringAsFixed(3)}g',
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(
            '${metal.itemCount} items',
            style:
                TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.85)),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(InventorySnapshotItem item) {
    final metalColor = _metalColor(item.metalType);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              item.barcode,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: metalColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              item.metalType.isNotEmpty
                  ? item.metalType[0].toUpperCase() +
                      item.metalType.substring(1)
                  : '',
              style: TextStyle(
                  fontSize: 10, color: metalColor, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${item.netWeight.toStringAsFixed(1)}g',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          if (item.containerName != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.slotNumber != null
                    ? '${item.containerName} · Slot ${item.slotNumber}'
                    : item.containerName!,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
