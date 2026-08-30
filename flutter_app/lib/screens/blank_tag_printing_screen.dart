import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';

class BlankTagPrintingScreen extends StatefulWidget {
  const BlankTagPrintingScreen({Key? key}) : super(key: key);

  @override
  State<BlankTagPrintingScreen> createState() => _BlankTagPrintingScreenState();
}

class _BlankTagPrintingScreenState extends State<BlankTagPrintingScreen> {
  final ApiService _apiService = ApiService();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, Color> _purityColors = {};
  List<String> _purities = [];
  bool _isLoading = true;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadPurities();
  }

  Future<void> _loadPurities() async {
    setState(() => _isLoading = true);

    try {
      final settingsProvider =
          Provider.of<SettingsProvider>(context, listen: false);
      final settings = await settingsProvider.getTagSettings();

      if (settings != null && mounted) {
        final purityColors = settings['purityColors'] as List? ?? [];

        setState(() {
          _purities = purityColors.map((pc) => pc['purity'] as String).toList();

          // Initialize controllers and colors
          for (var pc in purityColors) {
            final purity = pc['purity'] as String;
            _controllers[purity] = TextEditingController(text: '0');
            _purityColors[purity] = _hexToColor(pc['color'] as String);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          SnackBar(
              content: Text('Error loading purities: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Color _hexToColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  int _getTotalCount() {
    return _controllers.values
        .map((controller) => int.tryParse(controller.text) ?? 0)
        .fold(0, (sum, count) => sum + count);
  }

  Future<void> _generatePDF() async {
    // Validate that at least one purity has count > 0
    final totalCount = _getTotalCount();
    if (totalCount == 0) {
      showAppSnackBar(
        context,
        const SnackBar(
          content: Text('Please enter at least one tag count'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      // Build purity counts map
      final Map<String, int> purityCounts = {};
      _controllers.forEach((purity, controller) {
        final count = int.tryParse(controller.text) ?? 0;
        if (count > 0) {
          purityCounts[purity] = count;
        }
      });

      print('[Blank Tags] Generating PDF for: $purityCounts');

      // Call API to generate PDF
      final pdfBytes = await _apiService.generateBlankTagsPDF(purityCounts);

      print('[Blank Tags] PDF generated: ${pdfBytes.length} bytes');

      if (mounted) {
        // Share the PDF using Printing package (same as regular tag printing)
        await Printing.sharePdf(
          bytes: pdfBytes,
          filename: 'blank-tags-${DateTime.now().millisecondsSinceEpoch}.pdf',
        );

        showAppSnackBar(
          context,
          SnackBar(
            content: Text('✓ Generated $totalCount blank tags successfully'),
            backgroundColor: Colors.green,
          ),
        );

        // Reset all counts to 0
        _controllers.forEach((key, controller) {
          controller.text = '0';
        });
        setState(() {});
      }
    } catch (e) {
      print('[Blank Tags] Error: $e');
      if (mounted) {
        showAppSnackBar(
          context,
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalCount = _getTotalCount();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Print Blank Tags',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Info Card
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Enter the number of blank tags you want for each purity type',
                          style: TextStyle(
                            color: Colors.blue[900],
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Purity List
                Expanded(
                  child: _purities.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'No purity types found. Please add purities in Tag Settings first.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _purities.length,
                          itemBuilder: (context, index) {
                            final purity = _purities[index];
                            final controller = _controllers[purity]!;
                            final color = _purityColors[purity]!;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    // Color indicator
                                    Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // Purity name
                                    Expanded(
                                      child: Text(
                                        purity,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    // Number input
                                    SizedBox(
                                      width: 100,
                                      child: TextField(
                                        controller: controller,
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        decoration: InputDecoration(
                                          labelText: 'Count',
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Bottom Action Bar
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Total count display
                      if (totalCount > 0)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green[200]!),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.label,
                                  color: Colors.green[700], size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Total: $totalCount tags',
                                style: TextStyle(
                                  color: Colors.green[900],
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Generate button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _isGenerating ? null : _generatePDF,
                          icon: _isGenerating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.print),
                          label: Text(
                            _isGenerating
                                ? 'Generating PDF...'
                                : 'Generate PDF',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _controllers.forEach((key, controller) => controller.dispose());
    super.dispose();
  }
}
