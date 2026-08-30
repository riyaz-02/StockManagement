import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/store_provider.dart';

class ReconciliationTab extends StatelessWidget {
  const ReconciliationTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<StoreProvider>(
      builder: (context, store, _) {
        return RefreshIndicator(
          onRefresh: store.fetchReconciliation,
          child: store.isReconcileLoading
              ? const Center(child: CircularProgressIndicator())
              : store.reconciliation.isEmpty
                  ? _buildEmpty(store)
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Global alert banner
                        if (store.hasReconcileAlert)
                          _alertBanner(
                              '⚠️ Stock discrepancy detected! Review the details below immediately.',
                              Colors.red),

                        if (!store.hasReconcileAlert)
                          _alertBanner(
                              '✅ All stock figures are within the acceptable threshold (±1g).',
                              Colors.green),

                        const SizedBox(height: 16),

                        // Per-metal reconciliation cards
                        ...store.reconciliation.entries.map((entry) {
                          return _buildMetalCard(
                              context, entry.key, entry.value as Map);
                        }),

                        const SizedBox(height: 12),
                        // Info box
                        _infoBox(),
                      ],
                    ),
        );
      },
    );
  }

  Widget _alertBanner(String msg, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(msg,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }

  Widget _buildMetalCard(BuildContext context, String metal, Map reconcile) {
    final hasAlert = reconcile['hasAlert'] == true;
    final discrepancy = (reconcile['discrepancy'] as num?)?.toDouble() ?? 0;
    final alertMsg = reconcile['alertMessage'] as String?;
    final cardBorderColor = hasAlert ? Colors.red : Colors.green;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorderColor.withOpacity(0.4), width: 1.5),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: cardBorderColor.withOpacity(0.08),
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
            // Header
            Row(
              children: [
                Text(
                  '${metal[0].toUpperCase()}${metal.substring(1)}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cardBorderColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cardBorderColor.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        hasAlert
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                        color: cardBorderColor,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        hasAlert ? 'Alert' : 'OK',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cardBorderColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (alertMsg != null) ...[
              const SizedBox(height: 8),
              Text(alertMsg,
                  style: const TextStyle(fontSize: 12, color: Colors.red)),
            ],

            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // Formula rows
            _row('Total Purchased', reconcile['totalPurchased'], 'g'),
            _row(
              'Adjusted Purchase (×${(reconcile['multiplierUsed'] as num).toStringAsFixed(2)})',
              reconcile['adjustedPurchase'],
              'g',
              highlight: true,
            ),
            const Divider(height: 16),
            _row('Ledger Credit (In)', reconcile['ledgerCredit'], 'g',
                color: Colors.green),
            _row('Ledger Debit (Out)', reconcile['ledgerDebit'], 'g',
                color: Colors.red),
            _row('Net Ledger', reconcile['ledgerTotal'], 'g'),
            const Divider(height: 16),
            _row('Total Sold', reconcile['totalSold'], 'g',
                color: Colors.orange),
            _row('Total Wastage', reconcile['totalWastage'], 'g',
                color: Colors.orange),
            const Divider(height: 16),
            _row('Expected Debit', reconcile['expectedDebit'], 'g'),
            _row(
              'Discrepancy',
              discrepancy,
              'g',
              color: hasAlert ? Colors.red : Colors.green,
              highlight: true,
              bold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, dynamic value, String unit,
      {Color? color, bool highlight = false, bool bold = false}) {
    final val = (value as num?)?.toDouble() ?? 0;
    final textColor = color ?? const Color(0xFF1A1A1A);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: bold ? textColor : Colors.grey[700],
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: highlight
                ? const EdgeInsets.symmetric(horizontal: 10, vertical: 3)
                : EdgeInsets.zero,
            decoration: highlight
                ? BoxDecoration(
                    color: (color ?? Colors.blueGrey).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  )
                : null,
            child: Text(
              '${val.abs().toStringAsFixed(3)} $unit',
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ℹ️ How reconciliation works',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Colors.blue)),
          SizedBox(height: 8),
          Text(
            '• Adjusted Purchase = Purchased Grams × 1.10 (Gold) or ×1.20 (Silver)\n'
            '• Expected Debit = Adjusted Purchase − Net Ledger\n'
            '• Discrepancy = Expected Debit − Sold − Wastage\n'
            '• Alert triggers if |Discrepancy| > 1g\n\n'
            'A non-zero discrepancy may indicate material leakage, weighing errors, or unrecorded transactions.',
            style: TextStyle(fontSize: 11, color: Colors.blueGrey, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(StoreProvider store) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.balance_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('Run Reconciliation',
              style: TextStyle(fontSize: 15, color: Colors.grey)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: store.fetchReconciliation,
            icon: const Icon(Icons.refresh),
            label: const Text('Generate Report'),
          ),
        ],
      ),
    );
  }
}
