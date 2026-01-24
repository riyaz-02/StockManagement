import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/analytics_provider.dart';
import 'item_list_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({Key? key}) : super(key: key);

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        Provider.of<AnalyticsProvider>(context, listen: false).fetchDashboardStats();
      }
    });
  }

  Future<void> _refreshStats() async {
    await Provider.of<AnalyticsProvider>(context, listen: false).refreshStats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.maybePop(context);
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Stock Overview',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: Colors.black87,
              ),
            ),
            Text(
              'Live weight & item summary',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      body: Consumer<AnalyticsProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.dashboardStats == null) {
            return const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF27AE60),
              ),
            );
          }

          if (provider.error != null && provider.dashboardStats == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    provider.error!,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _refreshStats,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF27AE60),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshStats,
            color: const Color(0xFF27AE60),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // IN STOCK SECTION - Prominent with green accent
                  if (provider.currentStockMetalBreakdown.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF27AE60).withOpacity(0.3),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF27AE60).withOpacity(0.1),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF27AE60).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.inventory_2,
                                  color: Color(0xFF27AE60),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'IN STOCK',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF27AE60),
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${provider.currentStockTotalWeight.toStringAsFixed(3)} g • ${provider.currentStockTotalCount} items',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 110,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: provider.currentStockMetalBreakdown.length,
                              itemBuilder: (context, index) {
                                final metal = provider.currentStockMetalBreakdown[index];
                                return _buildMetalCard(
                                  metal: metal['metal']?.toString() ?? 'Unknown',
                                  weight: (metal['weight'] ?? 0).toDouble(),
                                  count: metal['count'] ?? 0,
                                  status: 'active',
                                  isFirst: index == 0,
                                  isLast: index == provider.currentStockMetalBreakdown.length - 1,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // EXCLUDED FROM STOCK - Subtle grey section
                  if (provider.inRepairBreakdown.isNotEmpty ||
                      provider.bookedBreakdown.isNotEmpty ||
                      provider.withCustomerBreakdown.isNotEmpty ||
                      provider.withAgentBreakdown.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.grey[300]!,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.remove_circle_outline,
                                  color: Colors.grey[700],
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'NOT IN STOCK',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.grey[700],
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Items temporarily unavailable',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          
                          // In Repair
                          if (provider.inRepairBreakdown.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _buildSubSection(
                              icon: Icons.build_circle,
                              label: 'In Repair',
                              color: const Color(0xFFF39C12),
                              items: provider.inRepairBreakdown,
                              status: 'in_repair',
                            ),
                          ],

                          // Booked
                          if (provider.bookedBreakdown.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _buildSubSection(
                              icon: Icons.bookmark,
                              label: 'Booked',
                              color: const Color(0xFF3498DB),
                              items: provider.bookedBreakdown,
                              status: 'booked',
                            ),
                          ],

                          // With Customer
                          if (provider.withCustomerBreakdown.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _buildSubSection(
                              icon: Icons.person,
                              label: 'With Customers',
                              color: const Color(0xFF9C27B0),
                              items: provider.withCustomerBreakdown,
                              status: 'WITH_CUSTOMER',
                            ),
                          ],

                          // With Agent
                          if (provider.withAgentBreakdown.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _buildSubSection(
                              icon: Icons.people,
                              label: 'With Agents',
                              color: const Color(0xFFE91E63),
                              items: provider.withAgentBreakdown,
                              status: 'WITH_AGENT',
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSubSection({
    required IconData icon,
    required String label,
    required Color color,
    required List<Map<String, dynamic>> items,
    required String status,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildCompactMetalCard(
                metal: item['metal']?.toString() ?? 'Unknown',
                weight: (item['weight'] ?? 0).toDouble(),
                count: item['count'] ?? 0,
                status: status,
                color: color,
                isFirst: index == 0,
                isLast: index == items.length - 1,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMetalCard({
    required String metal,
    required double weight,
    required int count,
    required String status,
    bool isFirst = false,
    bool isLast = false,
  }) {
    final metalColors = {
      'gold': const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFD4AF37), Color(0xFFB8860B)],
      ),
      'silver': const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF9E9E9E), Color(0xFF616161)],
      ),
      'platinum': const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFBDBDBD), Color(0xFF757575)],
      ),
      'diamond': const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF4FC3F7), Color(0xFF0288D1)],
      ),
      'mixed': const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF9C27B0), Color(0xFF7B1FA2)],
      ),
    };

    final gradient = metalColors[metal.toLowerCase()] ?? metalColors['mixed']!;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ItemListScreen(initialStatus: status),
          ),
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 160,
        margin: EdgeInsets.only(
          left: isFirst ? 0 : 8,
          right: isLast ? 0 : 8,
        ),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -15,
              top: -15,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      metal.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${weight.toStringAsFixed(3)} g',
                        style: const TextStyle(
                          fontSize: 22,
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
                      const SizedBox(height: 3),
                      Text(
                        '$count items',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(
                              color: Colors.black26,
                              offset: Offset(0, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactMetalCard({
    required String metal,
    required double weight,
    required int count,
    required String status,
    required Color color,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ItemListScreen(initialStatus: status),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 140,
        margin: EdgeInsets.only(
          left: isFirst ? 0 : 8,
          right: isLast ? 0 : 8,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                metal.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${weight.toStringAsFixed(3)} g',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[900],
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$count items',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
