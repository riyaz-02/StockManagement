import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/item_model.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_toast.dart';

class CreateBookingScreen extends StatefulWidget {
  final Item item;

  const CreateBookingScreen({super.key, required this.item});

  @override
  State<CreateBookingScreen> createState() => _CreateBookingScreenState();
}

class _CreateBookingScreenState extends State<CreateBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _advanceController = TextEditingController();
  final _remarksController = TextEditingController();
  DateTime _expiryDate = DateTime.now().add(const Duration(days: 7));
  bool _isLoading = false;

  @override
  void dispose() {
    _customerNameController.dispose();
    _mobileController.dispose();
    _advanceController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _createBooking() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        final apiService = ApiService();
        final response = await apiService.createBooking({
          'itemId': widget.item.id,
          'customerName': _customerNameController.text,
          'mobile': _mobileController.text,
          'advanceAmount': double.parse(_advanceController.text),
          'expiryDate': _expiryDate.toIso8601String(),
          'remarks': _remarksController.text,
        });

        if (mounted && response['success'] == true) {
          showAppSnackBar(
            context,
            const SnackBar(
              content: Text('Booking created successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
          Navigator.pop(context); // Go back to previous screen
        }
      } catch (e) {
        if (mounted) {
          showAppSnackBar(
            context,
            SnackBar(
              content:
                  Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
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
        title: Text(languageProvider.translate('book')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Item Info Card
            Card(
              color: AppColors.primary.withOpacity(0.1),
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Customer Name
            TextFormField(
              controller: _customerNameController,
              decoration: InputDecoration(
                labelText: languageProvider.translate('customer_name'),
                prefixIcon: const Icon(Icons.person),
              ),
              validator: (value) => value?.isEmpty ?? true
                  ? languageProvider.translate('required_field')
                  : null,
            ),
            const SizedBox(height: 16),

            // Mobile Number
            TextFormField(
              controller: _mobileController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: languageProvider.translate('customer_mobile'),
                prefixIcon: const Icon(Icons.phone),
              ),
              validator: (value) {
                if (value?.isEmpty ?? true) {
                  return languageProvider.translate('required_field');
                }
                if (value!.length < 10) {
                  return languageProvider.translate('invalid_mobile');
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Advance Amount
            TextFormField(
              controller: _advanceController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: languageProvider.translate('advance_amount'),
                prefixIcon: const Icon(Icons.currency_rupee),
              ),
              validator: (value) {
                if (value?.isEmpty ?? true) {
                  return languageProvider.translate('required_field');
                }
                if (double.tryParse(value!) == null) {
                  return 'Invalid amount';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Expiry Date
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(languageProvider.translate('booking_date')),
                subtitle: Text(
                  '${_expiryDate.day}/${_expiryDate.month}/${_expiryDate.year}',
                ),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _expiryDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    setState(() => _expiryDate = date);
                  }
                },
              ),
            ),
            const SizedBox(height: 16),

            // Remarks
            TextFormField(
              controller: _remarksController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Remarks (Optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 32),

            // Submit Button
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _createBooking,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        languageProvider.translate('confirm'),
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
