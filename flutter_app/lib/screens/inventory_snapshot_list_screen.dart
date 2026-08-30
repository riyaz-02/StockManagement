import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/tally_provider.dart';
import '../models/inventory_snapshot_model.dart';
import '../utils/app_colors.dart';
import 'inventory_snapshot_screen.dart';

class InventorySnapshotListScreen extends StatefulWidget {
  const InventorySnapshotListScreen({super.key});

  @override
  State<InventorySnapshotListScreen> createState() =>
      _InventorySnapshotListScreenState();
}

class _InventorySnapshotListScreenState
    extends State<InventorySnapshotListScreen> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Provider.of<TallyProvider>(context, listen: false)
        .fetchInventorySnapshots();
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
          'Inventory History',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
      ),
      body: Consumer<TallyProvider>(
        builder: (context, provider, child) {
          if (provider.isSnapshotLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.inventorySnapshots.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No inventory snapshots yet',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Snapshots appear here after you hit\n"Update Inventory" on a locked tally',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: provider.inventorySnapshots.length,
              itemBuilder: (context, index) {
                final snapshot = provider.inventorySnapshots[index];
                return _buildCard(snapshot);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildCard(InventorySnapshotSummary snapshot) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    InventorySnapshotScreen(snapshotId: snapshot.id)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    DateFormat('dd MMM yyyy, HH:mm').format(snapshot.date),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600]),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
                ],
              ),
              const SizedBox(height: 6),
              if (snapshot.tallyDescription != null)
                Text(
                  'From: ${snapshot.tallyDescription}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A)),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${snapshot.totalItems} items · ${snapshot.totalContainers} containers',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              if (snapshot.byMetal.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: snapshot.byMetal.map((m) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${m.metalType.toUpperCase()} ${m.totalWeight.toStringAsFixed(3)}g',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
