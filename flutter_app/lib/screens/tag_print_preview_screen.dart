import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../models/item_model.dart';
import '../services/api_service.dart';

class TagPrintPreviewScreen extends StatefulWidget {
  final List<Item> items;

  const TagPrintPreviewScreen({super.key, required this.items});

  @override
  State<TagPrintPreviewScreen> createState() => _TagPrintPreviewScreenState();
}

class _TagPrintPreviewScreenState extends State<TagPrintPreviewScreen> {
  final ApiService _apiService = ApiService();
  bool _isRecording = false;

  Future<void> _recordPrintAndPrint() async {
    setState(() => _isRecording = true);

    try {
      // Record print event and generate PDF from backend
      final itemIds = widget.items.map((item) => item.id).toList();
      
      // Generate PDF from backend
      final pdfBytes = await _apiService.generateTagsPDF(itemIds);
      
      // Record print event
      await _apiService.recordTagPrint(itemIds);
      
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print recorded for ${widget.items.length} items'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Return to selection screen
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRecording = false);
      }
    }
  }

  Future<void> _sharePdf() async {
    try {
      final itemIds = widget.items.map((item) => item.id).toList();
      final pdfBytes = await _apiService.generateTagsPDF(itemIds);
      
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'barcode_tags_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Print Preview',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _sharePdf,
            tooltip: 'Share PDF',
          ),
        ],
      ),
      body: Column(
        children: [
          // Info Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Print Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInfoRow('Total Tags:', '${widget.items.length}'),
                _buildInfoRow('Tags per Page:', '100'),
                _buildInfoRow('Layout:', '10 × 10'),
                _buildInfoRow('Tag Size:', '0.7" × 1" (foldable)'),
                _buildInfoRow('Paper:', 'A4'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline, color: Colors.amber[800], size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Fold each tag at the center line to create front and back sides',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // PDF Preview
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: PdfPreview(
                  build: (format) async {
                    try {
                      print('[PDF Preview] Fetching PDF from backend...');
                      final itemIds = widget.items.map((item) => item.id).toList();
                      print('[PDF Preview] Item IDs: $itemIds');
                      
                      final pdfBytes = await _apiService.generateTagsPDF(itemIds);
                      print('[PDF Preview] Received PDF: ${pdfBytes.length} bytes');
                      
                      if (pdfBytes.isEmpty) {
                        print('[PDF Preview] ERROR: Empty PDF bytes received');
                        throw Exception('Empty PDF received from server');
                      }
                      
                      // Validate PDF header
                      if (pdfBytes.length < 4 || 
                          pdfBytes[0] != 0x25 || pdfBytes[1] != 0x50 || 
                          pdfBytes[2] != 0x44 || pdfBytes[3] != 0x46) {
                        print('[PDF Preview] ERROR: Invalid PDF header');
                        print('[PDF Preview] First 10 bytes: ${pdfBytes.take(10).toList()}');
                        throw Exception('Invalid PDF format');
                      }
                      
                      print('[PDF Preview] PDF validation passed');
                      return pdfBytes;
                    } catch (e, stackTrace) {
                      print('[PDF Preview] ERROR: $e');
                      print('[PDF Preview] Stack trace: $stackTrace');
                      rethrow;
                    }
                  },
                  allowPrinting: false,
                  allowSharing: false,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  pdfFileName: 'barcode_tags.pdf',
                ),
              ),
            ),
          ),

          // Action Buttons
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
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFFE94560)),
                      foregroundColor: const Color(0xFFE94560),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isRecording ? null : _recordPrintAndPrint,
                    icon: _isRecording
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.print),
                    label: Text(_isRecording ? 'Recording...' : 'Print Tags'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE94560),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 2,
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
