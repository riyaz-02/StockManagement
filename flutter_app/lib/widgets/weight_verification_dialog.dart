import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WeightVerificationDialog extends StatefulWidget {
  final Map<String, dynamic> itemData;
  final Function(double) onVerified;

  const WeightVerificationDialog({
    Key? key,
    required this.itemData,
    required this.onVerified,
  }) : super(key: key);

  @override
  State<WeightVerificationDialog> createState() => _WeightVerificationDialogState();
}

class _WeightVerificationDialogState extends State<WeightVerificationDialog> {
  final TextEditingController _weightController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill weight for approx items
    final weightAccuracy = widget.itemData['weightAccuracy'] ?? 'approx';
    if (weightAccuracy == 'approx') {
      final previousWeight = widget.itemData['netWeight'] ?? widget.itemData['lastVerifiedWeight'] ?? 0.0;
      if (previousWeight > 0) {
        _weightController.text = previousWeight.toStringAsFixed(3);
      }
    }
  }

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  void _handleProceed() {
    if (_formKey.currentState!.validate()) {
      final weight = double.parse(_weightController.text);
      setState(() => _isSubmitting = true);
      widget.onVerified(weight);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemName = widget.itemData['name'] ?? 'Unknown Item';
    final previousWeight = widget.itemData['netWeight'] ?? widget.itemData['lastVerifiedWeight'] ?? 0.0;
    final weightAccuracy = widget.itemData['weightAccuracy'] ?? 'approx';
    final isBulk = weightAccuracy == 'bulk';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    isBulk ? Icons.inventory_2 : Icons.scale_outlined,
                    color: Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isBulk ? 'Verify Bulk Weight' : 'Verify Weight',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          itemName,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Previous Weight Info
              if (previousWeight > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 12, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        'Previous: ${previousWeight.toStringAsFixed(3)} g',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),

              // Weight Input
              TextFormField(
                controller: _weightController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}')),
                ],
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  labelText: 'Weight (g)',
                  labelStyle: const TextStyle(fontSize: 12),
                  hintText: '0.000',
                  hintStyle: const TextStyle(fontSize: 14),
                  prefixIcon: const Icon(Icons.scale, size: 18),
                  suffixText: 'g',
                  suffixStyle: const TextStyle(fontSize: 12),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Colors.orange, width: 2),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Required';
                  }
                  final weight = double.tryParse(value);
                  if (weight == null || weight <= 0) {
                    return 'Must be > 0';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _handleProceed(),
              ),
              const SizedBox(height: 12),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _handleProceed,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        backgroundColor: Colors.orange,
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 14,
                              width: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Confirm',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
