import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final ApiService _apiService = ApiService();
  Map<String, dynamic>? _dailySummary;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDailySummary();
  }

  Future<void> _loadDailySummary() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.getDailySummary();
      if (response['success'] == true) {
        setState(() {
          _dailySummary = response['data'];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(languageProvider.translate('reports')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDailySummary,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _dailySummary == null
              ? const Center(child: Text('No data available'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Summary Card
                    Card(
                      color: AppColors.primary.withOpacity(0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Daily Summary',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildSummaryRow(
                              'Total Items',
                              _dailySummary!['totalItems'].toString(),
                              Icons.inventory,
                            ),
                            _buildSummaryRow(
                              'Active Items',
                              _dailySummary!['activeItems'].toString(),
                              Icons.check_circle,
                            ),
                            _buildSummaryRow(
                              'Booked Items',
                              _dailySummary!['bookedItems'].toString(),
                              Icons.bookmark,
                            ),
                            _buildSummaryRow(
                              'In Repair',
                              _dailySummary!['inRepair'].toString(),
                              Icons.build,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Weight by Metal
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Weight by Metal Type',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_dailySummary!['weightByMetal'] != null)
                              ..._buildWeightRows(
                                  _dailySummary!['weightByMetal']),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Container Stats
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Container Statistics',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildSummaryRow(
                              'Total Containers',
                              _dailySummary!['totalContainers'].toString(),
                              Icons.inventory_2,
                            ),
                            _buildSummaryRow(
                              'Occupied Slots',
                              _dailySummary!['occupiedSlots'].toString(),
                              Icons.check_box,
                            ),
                            _buildSummaryRow(
                              'Available Slots',
                              _dailySummary!['availableSlots'].toString(),
                              Icons.check_box_outline_blank,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSummaryRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildWeightRows(Map<String, dynamic> weightByMetal) {
    return weightByMetal.entries.map((entry) {
      return _buildSummaryRow(
        entry.key.toUpperCase(),
        '${entry.value.toStringAsFixed(2)}g',
        Icons.scale,
      );
    }).toList();
  }
}
