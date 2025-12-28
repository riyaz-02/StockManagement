import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';

class BookingListScreen extends StatefulWidget {
  const BookingListScreen({super.key});

  @override
  State<BookingListScreen> createState() => _BookingListScreenState();
}

class _BookingListScreenState extends State<BookingListScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _bookings = [];
  bool _isLoading = true;
  String _filter = 'active'; // active, expired, completed, all

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.getBookings(status: _filter == 'all' ? null : _filter);
      if (response['success'] == true) {
        setState(() {
          _bookings = response['data']['bookings'];
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
        title: Text(languageProvider.translate('bookings')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBookings,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildFilterChip('Active', 'active'),
                const SizedBox(width: 8),
                _buildFilterChip('Expired', 'expired'),
                const SizedBox(width: 8),
                _buildFilterChip('Completed', 'completed'),
                const SizedBox(width: 8),
                _buildFilterChip('All', 'all'),
              ],
            ),
          ),
          
          // Bookings List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _bookings.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.bookmark_border, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(
                              'No bookings found',
                              style: TextStyle(fontSize: 18, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _bookings.length,
                        itemBuilder: (context, index) {
                          final booking = _bookings[index];
                          return _buildBookingCard(booking);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filter = value;
          _loadBookings();
        });
      },
      selectedColor: AppColors.primary.withOpacity(0.3),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    final item = booking['itemId'];
    final status = booking['status'];
    final isExpired = status == 'expired';
    final isActive = status == 'active';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: isExpired ? AppColors.error : AppColors.statusBooked,
          child: Icon(
            isExpired ? Icons.warning : Icons.bookmark,
            color: Colors.white,
          ),
        ),
        title: Text(item['name'] ?? 'Unknown Item'),
        subtitle: Text(
          '${booking['customerName']} • ${booking['mobile']}',
        ),
        trailing: Chip(
          label: Text(
            status.toUpperCase(),
            style: const TextStyle(fontSize: 10, color: Colors.white),
          ),
          backgroundColor: _getStatusColor(status),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('Barcode', item['barcode'] ?? ''),
                _buildDetailRow('Weight', '${item['netWeight']}g'),
                _buildDetailRow('Advance Amount', '₹${booking['advanceAmount']}'),
                _buildDetailRow('Booking Date', _formatDate(booking['bookingDate'])),
                _buildDetailRow('Expiry Date', _formatDate(booking['expiryDate'])),
                if (booking['remarks'] != null && booking['remarks'].isNotEmpty)
                  _buildDetailRow('Remarks', booking['remarks']),
                const SizedBox(height: 16),
                
                // Action Buttons
                if (isActive)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.cancel),
                          label: const Text('Cancel'),
                          onPressed: () => _cancelBooking(booking['_id']),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check_circle),
                          label: const Text('Complete'),
                          onPressed: () => _completeBooking(booking['_id']),
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active':
        return AppColors.statusBooked;
      case 'expired':
        return AppColors.error;
      case 'completed':
        return AppColors.success;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
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

  Future<void> _cancelBooking(String bookingId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: const Text('Are you sure you want to cancel this booking?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final response = await _apiService.cancelBooking(bookingId);
        if (response['success'] == true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Booking cancelled successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _loadBookings();
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

  Future<void> _completeBooking(String bookingId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Booking'),
        content: const Text('This will mark the item as sold. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Complete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final response = await _apiService.completeBooking(bookingId);
        if (response['success'] == true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Booking completed. Item marked as sold.'),
              backgroundColor: Colors.green,
            ),
          );
          _loadBookings();
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
}
