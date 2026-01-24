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
      backgroundColor: const Color(0xFFF8F9FB),
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
      ),
      body: Column(
        children: [
          // Filter Chips
          Container(
            color: Colors.white,
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
                    padding: const EdgeInsets.all(12),
                    itemCount: tallyProvider.tallySessions.length,
                    itemBuilder: (context, index) {
                      final tally = tallyProvider.tallySessions[index];
                      return _buildCompactTallyCard(tally);
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
    return GestureDetector(
      onTap: () {
        setState(() {
          _filterStatus = isSelected ? null : status;
        });
        _loadTallies();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF1A1A1A),
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildCompactTallyCard(TallySession tally) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
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
        onLongPress: () => _showTallyOptions(context, tally),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Date, Status, Progress
              Row(
                children: [
                  // Date with year
                  Text(
                    DateFormat('dd MMM yyyy').format(tally.date),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status badge
                  _buildCompactStatusBadge(tally.status),
                  const Spacer(),
                  // Progress
                  Text(
                    '${tally.progress}%',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: tally.progress == 100 
                          ? Colors.green 
                          : AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Description
              Text(
                tally.description,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // Items count
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${tally.scannedItemsCount}/${tally.expectedItems} items',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Metal breakdown - horizontal scrollable cards
              if (tally.metalData.isNotEmpty)
                SizedBox(
                  height: 75,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: tally.metalData.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: EdgeInsets.only(right: index < tally.metalData.length - 1 ? 8 : 0),
                        child: _buildMetalCard(tally.metalData[index]),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactStatusBadge(String status) {
    Color color;
    String label;

    switch (status) {
      case 'active':
        color = Colors.green;
        label = 'Active';
        break;
      case 'locked':
        color = Colors.blue;
        label = 'Locked';
        break;
      case 'force_locked':
        color = Colors.orange;
        label = 'Force';
        break;
      default:
        color = Colors.grey;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 9,
        ),
      ),
    );
  }

  Widget _buildMetalCard(MetalData metal) {
    Color bgColor;
    
    switch (metal.metalType.toLowerCase()) {
      case 'gold':
        bgColor = const Color(0xFFE5B80B);
        break;
      case 'silver':
        bgColor = const Color(0xFF9CA3AF);
        break;
      case 'platinum':
        bgColor = const Color(0xFF6B7280);
        break;
      default:
        bgColor = AppColors.primary;
    }

    final diff = metal.expectedWeight - metal.scannedWeight;
    final isComplete = diff.abs() < 0.01;

    return Container(
      width: 130,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: bgColor.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Circular graphic decoration
          Positioned(
            right: -20,
            bottom: -20,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.1),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Metal type badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        metal.metalType.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    // Completion checkmark or difference indicator
                    if (isComplete)
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 10,
                          color: Colors.white,
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: diff > 0 
                              ? Colors.orange.withOpacity(0.3)
                              : Colors.green.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${diff > 0 ? '-' : '+'}${diff.abs().toStringAsFixed(3)}g',
                          style: const TextStyle(
                            fontSize: 7,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                // Weight and items
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Scanned / Total weight
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          metal.scannedWeight.toStringAsFixed(3),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.1,
                            shadows: [
                              Shadow(
                                color: Colors.black26,
                                offset: Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '/${metal.expectedWeight.toStringAsFixed(3)}g',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.85),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Items count
                    Text(
                      '${metal.scannedItemCount}/${metal.expectedItemCount} items',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showTallyOptions(BuildContext context, TallySession tally) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tally.description,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.open_in_new, color: Colors.blue),
                title: const Text('View Details'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TallyDetailsScreen(tallyId: tally.id),
                    ),
                  ).then((_) => _loadTallies());
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDelete(context, tally);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, TallySession tally) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Tally Session?'),
        content: Text(
          'Are you sure you want to permanently delete "${tally.description}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final provider = Provider.of<TallyProvider>(context, listen: false);
              final success = await provider.deleteTallySession(tally.id);
              
              if (mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tally session deleted successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _loadTallies();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(provider.error ?? 'Failed to delete'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
