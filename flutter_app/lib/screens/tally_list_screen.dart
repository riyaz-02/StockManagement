import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/tally_provider.dart';
import '../models/tally_model.dart';
import '../utils/app_colors.dart';
import 'create_tally_screen.dart';
import 'tally_details_screen.dart';

class TallyListScreen extends StatefulWidget {
  const TallyListScreen({super.key});

  @override
  State<TallyListScreen> createState() => _TallyListScreenState();
}

class _TallyListScreenState extends State<TallyListScreen> {
  String? _filterStatus;

  @override
  void initState() {
    super.initState();
    _loadTallies();
  }

  Future<void> _loadTallies() async {
    await Provider.of<TallyProvider>(context, listen: false)
        .fetchTallySessions(status: _filterStatus);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Stock Tally / Audit',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTallies,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All', null),
                  const SizedBox(width: 8),
                  _buildFilterChip('Active', 'active'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Locked', 'locked'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Force Locked', 'force_locked'),
                ],
              ),
            ),
          ),

          // Tally List
          Expanded(
            child: Consumer<TallyProvider>(
              builder: (context, tallyProvider, child) {
                if (tallyProvider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (tallyProvider.error != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          tallyProvider.error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadTallies,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                if (!tallyProvider.hasTallySessions) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, 
                             size: 64, 
                             color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No tally sessions found',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create a new tally to start auditing',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _loadTallies,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: tallyProvider.tallySessions.length,
                    itemBuilder: (context, index) {
                      final tally = tallyProvider.tallySessions[index];
                      return _buildTallyCard(tally);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CreateTallyScreen(),
            ),
          );
          if (result == true) {
            _loadTallies();
          }
        },
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add),
        label: const Text('New Tally'),
      ),
    );
  }

  Widget _buildFilterChip(String label, String? status) {
    final isSelected = _filterStatus == status;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filterStatus = selected ? status : null;
        });
        _loadTallies();
      },
      selectedColor: AppColors.primary,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _buildTallyCard(TallySession tally) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TallyDetailsScreen(tallyId: tally.id),
            ),
          );
          _loadTallies();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  // Date Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      DateFormat('dd MMM yyyy').format(tally.date),
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Status Badge
                  _buildStatusBadge(tally.status),
                  const Spacer(),
                  // Progress
                  Text(
                    '${tally.progress}%',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: tally.progress == 100 
                          ? Colors.green 
                          : AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Description
              Text(
                tally.description,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),

              // Created By
              if (tally.createdByName != null)
                Text(
                  'Created by ${tally.createdByName}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              const SizedBox(height: 12),

              // Metrics Grid
              Row(
                children: [
                  Expanded(
                    child: _buildMetric(
                      'Items',
                      '${tally.scannedItemsCount}/${tally.expectedItems}',
                      Icons.inventory_2_outlined,
                      Colors.blue,
                    ),
                  ),
                  Expanded(
                    child: _buildMetric(
                      'Gold',
                      '${tally.scannedGoldWeight.toStringAsFixed(1)}g\n/${tally.expectedGoldWeight.toStringAsFixed(1)}g',
                      Icons.diamond_outlined,
                      Colors.amber,
                    ),
                  ),
                  Expanded(
                    child: _buildMetric(
                      'Silver',
                      '${tally.scannedSilverWeight.toStringAsFixed(1)}g\n/${tally.expectedSilverWeight.toStringAsFixed(1)}g',
                      Icons.circle_outlined,
                      Colors.grey,
                    ),
                  ),
                ],
              ),

              // Out of Stock Count (if any)
              if (tally.outOfStockCount > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.output_outlined, 
                                 size: 16, 
                                 color: Colors.orange),
                      const SizedBox(width: 6),
                      Text(
                        'Out of Stock: ${tally.outOfStockCount}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Action Button
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TallyDetailsScreen(tallyId: tally.id),
                      ),
                    );
                    _loadTallies();
                  },
                  icon: Icon(
                    tally.isLocked ? Icons.visibility : Icons.play_arrow,
                  ),
                  label: Text(
                    tally.isLocked ? 'View Details' : 'Continue Scanning',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tally.isLocked ? Colors.grey[700] : AppColors.primary,
                    side: BorderSide(
                      color: tally.isLocked ? Colors.grey[400]! : AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    IconData icon;
    String label;

    switch (status) {
      case 'active':
        color = Colors.green;
        icon = Icons.play_circle_outline;
        label = 'Active';
        break;
      case 'locked':
        color = Colors.blue;
        icon = Icons.lock_outline;
        label = 'Locked';
        break;
      case 'force_locked':
        color = Colors.orange;
        icon = Icons.lock_clock;
        label = 'Force Locked';
        break;
      default:
        color = Colors.grey;
        icon = Icons.help_outline;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
