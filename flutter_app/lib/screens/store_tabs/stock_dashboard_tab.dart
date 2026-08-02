import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/store_provider.dart';
import '../../models/store_models.dart';
import '../../utils/app_colors.dart';

class StockDashboardTab extends StatelessWidget {
  const StockDashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<StoreProvider>(
      builder: (context, store, _) {
        if (store.isDashboardLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (store.dashboardError != null) {
          return _buildError(context, store.dashboardError!, store);
        }

        final metals = ['gold', 'silver', 'platinum'];

        return RefreshIndicator(
          onRefresh: store.fetchStockDashboard,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Total Stock Cards ────────────────────────────────────────
              _sectionHeader('📦 Total Stock in Shop'),
              const SizedBox(height: 12),
              ...metals
                  .where((m) =>
                      (store.totalStock[m] ?? 0) > 0 ||
                      (store.barcodedStock[m] != null))
                  .map((metal) => _buildMetalSummaryCard(context, metal, store)),

              if (store.totalStock.isEmpty)
                _buildEmptyCard('No stock data available'),

              const SizedBox(height: 24),

              // ── Bulk / Untagged Weight ───────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _sectionHeader('🏷️ Untagged / Bulk Weight'),
                  TextButton.icon(
                    onPressed: () => _showAddBulkWeightDialog(context, store),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (store.bulkWeights.isEmpty)
                _buildEmptyCard('No bulk weight entries yet.\nTap Add to enter raw/reserved gold.'),

              ...store.bulkWeights.map((bw) => _buildBulkWeightCard(context, bw, store)),
            ],
          ),
        );
      },
    );
  }

  // ── Metal Summary Card ─────────────────────────────────────────────────
  Widget _buildMetalSummaryCard(
      BuildContext context, String metal, StoreProvider store) {
    final barcoded = store.barcodedStock[metal];
    final barcodedWeight = (barcoded?['weightGrams'] as num?)?.toDouble() ?? 0;
    final barcodedCount = (barcoded?['count'] as int?) ?? 0;
    final bulkWeight = store.bulkWeights
        .where((b) => b.metalType == metal && b.isActive)
        .fold(0.0, (sum, b) => sum + b.weightGrams);
    final total = store.totalStock[metal] ?? 0;

    final color = _metalColor(metal);
    final icon = _metalIcon(metal);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.08), color.withOpacity(0.02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  metal[0].toUpperCase() + metal.substring(1),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${total.toStringAsFixed(3)} g',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    Text(
                      'Total Stock',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _miniStat(
                    '🏷️ Barcoded',
                    '${barcodedWeight.toStringAsFixed(3)} g',
                    '$barcodedCount items',
                    Colors.teal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _miniStat(
                    '📦 Untagged',
                    '${bulkWeight.toStringAsFixed(3)} g',
                    'manual entries',
                    Colors.amber.shade700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(
      String label, String value, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: color)),
          Text(subtitle,
              style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ],
      ),
    );
  }

  // ── Bulk Weight Card ───────────────────────────────────────────────────
  Widget _buildBulkWeightCard(
      BuildContext context, BulkWeight bw, StoreProvider store) {
    final color = _metalColor(bw.metalType);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(_metalIcon(bw.metalType), color: color, size: 20),
        ),
        title: Text(bw.description,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          '${bw.metalType[0].toUpperCase()}${bw.metalType.substring(1)} • ${bw.weightGrams.toStringAsFixed(3)} g',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () =>
                  _showEditBulkWeightDialog(context, bw, store),
              color: Colors.blueGrey,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _confirmDeleteBulkWeight(context, bw, store),
              color: Colors.red,
            ),
          ],
        ),
      ),
    );
  }

  // ── Dialogs ────────────────────────────────────────────────────────────
  void _showAddBulkWeightDialog(BuildContext context, StoreProvider store) {
    _showBulkWeightDialog(context, store, null);
  }

  void _showEditBulkWeightDialog(
      BuildContext context, BulkWeight bw, StoreProvider store) {
    _showBulkWeightDialog(context, store, bw);
  }

  void _showBulkWeightDialog(
      BuildContext context, StoreProvider store, BulkWeight? existing) {
    final metals = ['gold', 'silver', 'platinum', 'other'];
    String selectedMetal = existing?.metalType ?? 'gold';
    final weightController =
        TextEditingController(text: existing?.weightGrams.toString() ?? '');
    final descController =
        TextEditingController(text: existing?.description ?? '');
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                existing == null ? 'Add Bulk Weight' : 'Edit Bulk Weight',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedMetal,
                decoration: const InputDecoration(labelText: 'Metal Type'),
                items: metals
                    .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(
                            m[0].toUpperCase() + m.substring(1))))
                    .toList(),
                onChanged: (v) => setSheetState(() => selectedMetal = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: weightController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Weight (grams)',
                  suffixText: 'g',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'e.g. Reserved Gold, Raw Silver Bar',
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final w = double.tryParse(weightController.text);
                        if (w == null || w <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Enter a valid weight')));
                          return;
                        }
                        if (descController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Description is required')));
                          return;
                        }
                        setSheetState(() => isSaving = true);
                        bool ok;
                        if (existing == null) {
                          ok = await store.addBulkWeight(
                            metalType: selectedMetal,
                            weightGrams: w,
                            description: descController.text.trim(),
                          );
                        } else {
                          ok = await store.updateBulkWeight(
                            existing.id,
                            w,
                            descController.text.trim(),
                          );
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(ok
                                ? 'Bulk weight ${existing == null ? 'added' : 'updated'}'
                                : 'Failed to save'),
                            backgroundColor: ok ? Colors.green : Colors.red,
                          ));
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child:
                            CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(existing == null ? 'Add' : 'Update'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteBulkWeight(
      BuildContext context, BulkWeight bw, StoreProvider store) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Entry?'),
        content: Text('Remove "${bw.description}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              final ok = await store.deleteBulkWeight(bw.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok ? 'Entry removed' : 'Failed to remove'),
                  backgroundColor: ok ? Colors.green : Colors.red,
                ));
              }
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────
  Widget _sectionHeader(String text) => Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      );

  Widget _buildEmptyCard(String msg) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Text(msg,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500], fontSize: 13)),
      );

  Widget _buildError(
      BuildContext context, String error, StoreProvider store) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 12),
          Text(error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          ElevatedButton(
              onPressed: store.fetchStockDashboard,
              child: const Text('Retry')),
        ],
      ),
    );
  }

  Color _metalColor(String metal) {
    switch (metal.toLowerCase()) {
      case 'gold':
        return const Color(0xFFF59E0B);
      case 'silver':
        return const Color(0xFF6B7280);
      case 'platinum':
        return const Color(0xFF3B82F6);
      default:
        return Colors.teal;
    }
  }

  IconData _metalIcon(String metal) {
    switch (metal.toLowerCase()) {
      case 'gold':
        return Icons.diamond_outlined;
      case 'silver':
        return Icons.circle_outlined;
      case 'platinum':
        return Icons.hexagon_outlined;
      default:
        return Icons.category_outlined;
    }
  }
}
