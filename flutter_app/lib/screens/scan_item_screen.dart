import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/item_provider.dart';
import '../providers/language_provider.dart';
import '../utils/app_colors.dart';
import 'item_details_screen.dart';

class ScanItemScreen extends StatefulWidget {
  const ScanItemScreen({super.key});

  @override
  State<ScanItemScreen> createState() => _ScanItemScreenState();
}

class _ScanItemScreenState extends State<ScanItemScreen> {
  final _barcodeController = TextEditingController();

  @override
  void dispose() {
    _barcodeController.dispose();
    super.dispose();
  }

  Future<void> _searchItem(String barcode) async {
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    final item = await itemProvider.scanBarcode(barcode);

    if (mounted) {
      if (item != null) {
        _showItemDetails(item);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Item not found'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _showItemDetails(item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemDetailsScreen(item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Scan Item',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.qr_code_scanner,
              size: 120,
              color: AppColors.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 40),
            
            const Text(
              'Enter Barcode Manually',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            
            // Manual Entry
            TextField(
              controller: _barcodeController,
              decoration: InputDecoration(
                labelText: languageProvider.translate('enter_manually'),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    if (_barcodeController.text.isNotEmpty) {
                      _searchItem(_barcodeController.text);
                    }
                  },
                ),
              ),
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  _searchItem(value);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
