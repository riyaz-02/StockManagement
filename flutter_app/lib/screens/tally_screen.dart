import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import '../providers/tally_provider.dart';
import '../providers/language_provider.dart';
import '../utils/app_colors.dart';

class TallyScreen extends StatefulWidget {
  const TallyScreen({super.key});

  @override
  State<TallyScreen> createState() => _TallyScreenState();
}

class _TallyScreenState extends State<TallyScreen> {
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _startTally() async {
    final tallyProvider = Provider.of<TallyProvider>(context, listen: false);
    final success = await tallyProvider.startTally(_descriptionController.text);

    if (mounted && success) {
      setState(() {});
    }
  }

  Future<void> _scanItem() async {
    try {
      final barcode = await FlutterBarcodeScanner.scanBarcode(
        '#${AppColors.primary.value.toRadixString(16)}',
        'Cancel',
        true,
        ScanMode.BARCODE,
      );

      if (barcode != '-1' && mounted) {
        final tallyProvider = Provider.of<TallyProvider>(context, listen: false);
        final result = await tallyProvider.scanItem(barcode);

        if (mounted && result != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Scanned: ${result['item']['name']}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _lockTally() async {
    final tallyProvider = Provider.of<TallyProvider>(context, listen: false);
    final result = await tallyProvider.lockTally();

    if (mounted && result != null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Tally Completed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Scanned: ${result['tallySession']['scannedItemIds'].length} items'),
              Text('Weight: ${result['tallySession']['totalScannedWeight']}g'),
              Text('Mismatch: ${result['mismatchDetected'] ? 'YES' : 'NO'}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final tallyProvider = Provider.of<TallyProvider>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: Text(
          languageProvider.translate('start_tally'),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: tallyProvider.isTallyActive
            ? _buildActiveTally(languageProvider, tallyProvider)
            : _buildStartTally(languageProvider),
      ),
    );
  }

  Widget _buildStartTally(LanguageProvider languageProvider) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextField(
          controller: _descriptionController,
          decoration: InputDecoration(
            labelText: languageProvider.translate('description'),
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _startTally,
            child: Text(languageProvider.translate('start_tally')),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveTally(LanguageProvider languageProvider, TallyProvider tallyProvider) {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  '${tallyProvider.scannedCount} / ${tallyProvider.expectedCount}',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: tallyProvider.progress / 100),
                const SizedBox(height: 16),
                Text('Weight: ${tallyProvider.scannedWeight.toStringAsFixed(2)}g'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan Item'),
            onPressed: _scanItem,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: _lockTally,
            child: Text(languageProvider.translate('lock_tally')),
          ),
        ),
      ],
    );
  }
}
