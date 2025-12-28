import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';

class RepairScreen extends StatefulWidget {
  const RepairScreen({super.key});

  @override
  State<RepairScreen> createState() => _RepairScreenState();
}

class _RepairScreenState extends State<RepairScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _repairItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRepairItems();
  }

  Future<void> _loadRepairItems() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.getRepairItems();
      if (response['success'] == true) {
        setState(() {
          _repairItems = response['data']['repairLogs'];
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
        title: Text(languageProvider.translate('repair_items')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRepairItems,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _repairItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.build_circle, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'No items in repair',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _repairItems.length,
                  itemBuilder: (context, index) {
                    final repair = _repairItems[index];
                    final item = repair['itemId'];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.statusRepair,
                          child: const Icon(Icons.build, color: Colors.white),
                        ),
                        title: Text(item['name'] ?? 'Unknown Item'),
                        subtitle: Text(
                          '${languageProvider.translate(repair['repairType'])} • ${repair['sentTo']}',
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDetailRow(
                                  'Barcode',
                                  item['barcode'] ?? '',
                                ),
                                _buildDetailRow(
                                  'Weight',
                                  '${item['netWeight']}g',
                                ),
                                _buildDetailRow(
                                  'Sent Date',
                                  _formatDate(repair['sentDate']),
                                ),
                                _buildDetailRow(
                                  'Expected Return',
                                  _formatDate(repair['expectedReturnDate']),
                                ),
                                _buildDetailRow(
                                  'Slot Reserved',
                                  repair['slotReserved'] ? 'Yes' : 'No',
                                ),
                                if (repair['remarks'] != null &&
                                    repair['remarks'].isNotEmpty)
                                  _buildDetailRow(
                                    'Remarks',
                                    repair['remarks'],
                                  ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.check_circle),
                                    label: const Text('Mark as Returned'),
                                    onPressed: () => _returnFromRepair(repair['_id']),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  Future<void> _returnFromRepair(String repairLogId) async {
    try {
      final response = await _apiService.returnFromRepair(repairLogId);
      if (response['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Item returned from repair successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadRepairItems();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
