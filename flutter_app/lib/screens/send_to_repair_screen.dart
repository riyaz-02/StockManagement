import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/item_model.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';

class SendToRepairScreen extends StatefulWidget {
  final Item item;

  const SendToRepairScreen({super.key, required this.item});

  @override
  State<SendToRepairScreen> createState() => _SendToRepairScreenState();
}

class _SendToRepairScreenState extends State<SendToRepairScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sentToController = TextEditingController();
  final _remarksController = TextEditingController();
  
  String _repairType = 'polishing';
  bool _slotReserved = true;
  DateTime _expectedReturnDate = DateTime.now().add(const Duration(days: 7));
  bool _isLoading = false;

  final List<String> _repairTypes = [
    'polishing',
    'stone_fixing',
    'resizing',
    'chain_repair',
    'other',
  ];

  @override
  void dispose() {
    _sentToController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _sendToRepair() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        final apiService = ApiService();
        final response = await apiService.sendToRepair({
          'itemId': widget.item.id,
          'repairType': _repairType,
          'sentTo': _sentToController.text,
          'expectedReturnDate': _expectedReturnDate.toIso8601String(),
          'slotReserved': _slotReserved,
          'remarks': _remarksController.text,
        });

        if (mounted && response['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Item sent to repair. Slot ${_slotReserved ? 'reserved' : 'freed'}.',
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
          Navigator.pop(context);
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
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(languageProvider.translate('send_to_repair')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Item Info Card
            Card(
              color: AppColors.statusRepair.withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Barcode: ${widget.item.barcode}'),
                    Text('Weight: ${widget.item.netWeight}g'),
                    if (widget.item.containerId != null)
                      Text('Current Slot: ${widget.item.slotNumber}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Repair Type
            DropdownButtonFormField<String>(
              value: _repairType,
              decoration: InputDecoration(
                labelText: languageProvider.translate('repair_type'),
                prefixIcon: const Icon(Icons.build),
              ),
              items: _repairTypes.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(languageProvider.translate(type)),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _repairType = value!);
              },
            ),
            const SizedBox(height: 16),

            // Sent To
            TextFormField(
              controller: _sentToController,
              decoration: InputDecoration(
                labelText: languageProvider.translate('sent_to'),
                prefixIcon: const Icon(Icons.business),
                hintText: 'Workshop/Vendor name',
              ),
              validator: (value) =>
                  value?.isEmpty ?? true ? languageProvider.translate('required_field') : null,
            ),
            const SizedBox(height: 16),

            // Expected Return Date
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(languageProvider.translate('expected_return_date')),
                subtitle: Text(
                  '${_expectedReturnDate.day}/${_expectedReturnDate.month}/${_expectedReturnDate.year}',
                ),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _expectedReturnDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    setState(() => _expectedReturnDate = date);
                  }
                },
              ),
            ),
            const SizedBox(height: 16),

            // Slot Reservation
            Card(
              child: SwitchListTile(
                title: Text(languageProvider.translate('reserve_slot')),
                subtitle: Text(
                  _slotReserved
                      ? 'Slot will be reserved for this item'
                      : 'Slot will be freed for other items',
                  style: TextStyle(fontSize: 12),
                ),
                value: _slotReserved,
                onChanged: (value) {
                  setState(() => _slotReserved = value);
                },
                secondary: Icon(
                  _slotReserved ? Icons.lock : Icons.lock_open,
                  color: _slotReserved ? AppColors.warning : AppColors.success,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Remarks
            TextFormField(
              controller: _remarksController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Remarks',
                hintText: 'Repair details, issues, etc.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 32),

            // Submit Button
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _sendToRepair,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.statusRepair,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        languageProvider.translate('send_to_repair'),
                        style: const TextStyle(fontSize: 18),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
