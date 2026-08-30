import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_toast.dart';

class SendNotificationScreen extends StatefulWidget {
  const SendNotificationScreen({super.key});

  @override
  State<SendNotificationScreen> createState() => _SendNotificationScreenState();
}

class _SendNotificationScreenState extends State<SendNotificationScreen> {
  final _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  String _target = 'all'; // 'all' or 'role'
  String _targetRole = 'staff';
  bool _isSending = false;

  List<dynamic> _history = [];
  bool _isLoadingHistory = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final response = await _apiService.getNotificationHistory();
      if (response['success'] == true) {
        _history = response['data']['notifications'] ?? [];
      }
    } catch (_) {
      // Non-critical — history is a nice-to-have on this screen.
    }
    if (mounted) setState(() => _isLoadingHistory = false);
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);
    try {
      final response = await _apiService.sendNotification({
        'title': _titleCtrl.text.trim(),
        'body': _bodyCtrl.text.trim(),
        'targetType': _target,
        if (_target == 'role') 'targetRole': _targetRole,
      });

      if (!mounted) return;
      if (response['success'] == true) {
        showAppSnackBar(
            context,
            SnackBar(
                content: Text(response['message'] ?? 'Sent'),
                backgroundColor: Colors.green));
        _titleCtrl.clear();
        _bodyCtrl.clear();
        await _loadHistory();
      } else {
        showAppSnackBar(
            context,
            SnackBar(
                content: Text(response['message'] ?? 'Failed to send'),
                backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context,
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
    if (mounted) setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text('Send Notification',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Form(
            key: _formKey,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _bodyCtrl,
                    decoration: const InputDecoration(labelText: 'Message'),
                    maxLines: 3,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  const Text('Send to',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Everyone'),
                          value: 'all',
                          groupValue: _target,
                          onChanged: (v) => setState(() => _target = v!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('By role'),
                          value: 'role',
                          groupValue: _target,
                          onChanged: (v) => setState(() => _target = v!),
                        ),
                      ),
                    ],
                  ),
                  if (_target == 'role')
                    DropdownButtonFormField<String>(
                      value: _targetRole,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: const [
                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                        DropdownMenuItem(value: 'staff', child: Text('Staff')),
                        DropdownMenuItem(
                            value: 'viewer', child: Text('Viewer')),
                      ],
                      onChanged: (v) => setState(() => _targetRole = v!),
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isSending ? null : _send,
                      icon: const Icon(Icons.send, size: 18),
                      label: Text(_isSending ? 'Sending...' : 'Send'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Recent',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_isLoadingHistory)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator()))
          else if (_history.isEmpty)
            Text('No notifications sent yet',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]))
          else
            ..._history.map((n) => _buildHistoryRow(n)),
        ],
      ),
    );
  }

  Widget _buildHistoryRow(dynamic n) {
    final createdAt =
        n['createdAt'] != null ? DateTime.tryParse(n['createdAt']) : null;
    final target =
        n['targetType'] == 'role' ? 'Role: ${n['targetRole']}' : 'Everyone';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(n['title'] ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              if (createdAt != null)
                Text(
                  DateFormat('dd MMM, HH:mm').format(createdAt),
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(n['body'] ?? '', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(target,
                  style: TextStyle(fontSize: 10, color: Colors.grey[600])),
              const SizedBox(width: 8),
              Text(
                '✓ ${n['successCount'] ?? 0}  ✗ ${n['failureCount'] ?? 0}',
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
              if (n['source'] != null && n['source'] != 'manual') ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('auto: ${n['source']}',
                      style: TextStyle(fontSize: 9, color: AppColors.primary)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
