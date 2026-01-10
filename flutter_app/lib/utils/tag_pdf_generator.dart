import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:barcode_widget/barcode_widget.dart' as bw;
import '../models/item_model.dart';

class TagPdfGenerator {
  // Tag dimensions in inches
  static const double tagWidth = 1.5 * PdfPageFormat.inch;
  static const double tagHeight = 2.0 * PdfPageFormat.inch;
  static const double halfTagHeight = 1.0 * PdfPageFormat.inch;
  
  // A4 page settings
  static const double pageMargin = 0.5 * PdfPageFormat.inch;
  
  // Calculate tags per page
  static const int tagsPerRow = 4; // (8.27" - 1" margins) / 1.5" ≈ 4
  static const int tagsPerColumn = 5; // (11.69" - 1" margins) / 2" ≈ 5
  static const int tagsPerPage = 20; // 4 × 5

  /// Generate PDF document with barcode tags
  static Future<pw.Document> generateTags(List<Item> items) async {
    final pdf = pw.Document();
    
    // Split items into pages
    for (int page = 0; page < (items.length / tagsPerPage).ceil(); page++) {
      final pageItems = items
          .skip(page * tagsPerPage)
          .take(tagsPerPage)
          .toList();
      
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(pageMargin),
          build: (context) => _buildTagPage(pageItems),
        ),
      );
    }
    
    return pdf;
  }

  /// Build a page of tags
  static pw.Widget _buildTagPage(List<Item> items) {
    // Create grid of tags
    final rows = <pw.Widget>[];
    
    for (int row = 0; row < tagsPerColumn; row++) {
      final rowItems = <pw.Widget>[];
      
      for (int col = 0; col < tagsPerRow; col++) {
        final index = row * tagsPerRow + col;
        if (index < items.length) {
          rowItems.add(_buildTag(items[index]));
        } else {
          // Empty placeholder
          rowItems.add(pw.SizedBox(width: tagWidth, height: tagHeight));
        }
        
        // Add spacing between tags
        if (col < tagsPerRow - 1) {
          rowItems.add(pw.SizedBox(width: 4));
        }
      }
      
      rows.add(
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          children: rowItems,
        ),
      );
      
      // Add spacing between rows
      if (row < tagsPerColumn - 1) {
        rows.add(pw.SizedBox(height: 4));
      }
    }
    
    return pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.start,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: rows,
    );
  }

  /// Build a single foldable tag (front and back side by side)
  static pw.Widget _buildTag(Item item) {
    final hasHallmark = item.huid.isNotEmpty;
    
    // Color coding
    final bgColor = hasHallmark
        ? PdfColor.fromHex('#FFD700') // Golden for hallmark
        : PdfColor.fromHex('#ADD8E6'); // Light blue for non-hallmark
    
    final accentColor = hasHallmark
        ? PdfColor.fromHex('#DAA520') // Goldenrod
        : PdfColor.fromHex('#4682B4'); // Steel blue
    
    final textColor = PdfColors.black;
    
    return pw.Container(
      width: tagWidth,
      height: tagHeight,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
      ),
      child: pw.Column(
        children: [
          // FRONT SIDE (Top half - 1.5" × 1")
          pw.Container(
            width: tagWidth,
            height: halfTagHeight,
            color: bgColor,
            padding: const pw.EdgeInsets.all(6),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                // Barcode with protective white background
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                  ),
                  child: pw.Column(
                    children: [
                      // Barcode
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.code128(),
                        data: item.barcode,
                        width: tagWidth * 0.65,
                        height: 24,
                        drawText: false,
                      ),
                      pw.SizedBox(height: 1),
                      // Barcode text
                      pw.Text(
                        item.barcode,
                        style: pw.TextStyle(
                          fontSize: 6,
                          fontWeight: pw.FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      pw.SizedBox(height: 1),
                      // Weight below barcode (small)
                      pw.Text(
                        '${item.netWeight.toStringAsFixed(3)} g',
                        style: pw.TextStyle(
                          fontSize: 6,
                          fontWeight: pw.FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Fold line indicator
          pw.Container(
            width: tagWidth,
            height: 1,
            decoration: pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(
                  color: PdfColors.grey600,
                  width: 0.5,
                  style: pw.BorderStyle.dashed,
                ),
              ),
            ),
          ),
          
          // BACK SIDE (Bottom half - 1.5" × 1")
          pw.Container(
            width: tagWidth,
            height: halfTagHeight - 1,
            color: bgColor,
            padding: const pw.EdgeInsets.all(5),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Item name
                pw.Container(
                  width: tagWidth * 0.9,
                  child: pw.Text(
                    item.name,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: textColor,
                    ),
                    maxLines: 2,
                    overflow: pw.TextOverflow.clip,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 3),
                
                // Divider
                pw.Container(
                  width: tagWidth * 0.5,
                  height: 0.5,
                  color: accentColor,
                ),
                
                pw.SizedBox(height: 3),
                
                // Weight (big, in white box)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    border: pw.Border.all(color: accentColor, width: 0.8),
                  ),
                  child: pw.Text(
                    '${item.netWeight.toStringAsFixed(3)} g',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
                
                pw.SizedBox(height: 3),
                
                // Purity (below weight)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: pw.BoxDecoration(
                    color: accentColor,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  child: pw.Text(
                    item.purity,
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
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

  /// Get total number of pages needed
  static int calculatePageCount(int itemCount) {
    return (itemCount / tagsPerPage).ceil();
  }

  /// Get tags layout info
  static Map<String, int> getLayoutInfo() {
    return {
      'tagsPerRow': tagsPerRow,
      'tagsPerColumn': tagsPerColumn,
      'tagsPerPage': tagsPerPage,
    };
  }
}
