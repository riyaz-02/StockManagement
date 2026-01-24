import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart' as material;
import 'dart:ui' as ui;
import 'dart:typed_data';
import '../models/item_model.dart';

class TagPdfGenerator {
  // Tag dimensions in inches - Extra compact design
  static const double tagWidth = 0.7 * PdfPageFormat.inch; // Width: 0.7"
  static const double tagHeight = 1.2 * PdfPageFormat.inch; // Total height: 1.2" (0.6" per side)
  static const double halfTagHeight = 0.6 * PdfPageFormat.inch; // Each side is 0.6"
  
  // A4 page settings
  static const double pageMargin = 0.5 * PdfPageFormat.inch;
  
  // Calculate tags per page with new dimensions
  static const int tagsPerRow = 10; // (8.27" - 1" margins) / 0.7" ≈ 10
  static const int tagsPerColumn = 8; // (11.69" - 1" margins) / 1.2" ≈ 8
  static const int tagsPerPage = 80; // 10 × 8

  /// Render Bengali text as image for proper display
  static Future<Uint8List> _renderTextAsImage(
    String text, {
    double maxFontSize = 12,
    material.Color color = material.Colors.black,
    material.FontWeight fontWeight = material.FontWeight.bold,
    double maxWidth = 100,
    int maxLines = 3,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = material.Canvas(recorder);
    
    // Start with max font size and reduce if needed to fit
    double fontSize = maxFontSize;
    material.TextPainter? textPainter;
    
    // Try to fit text with decreasing font sizes
    for (int i = 0; i < 5; i++) {
      final textStyle = material.TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontFamily: GoogleFonts.roboto().fontFamily,
        height: 1.1, // Line height multiplier
      );
      
      final textSpan = material.TextSpan(text: text, style: textStyle);
      textPainter = material.TextPainter(
        text: textSpan,
        textDirection: material.TextDirection.ltr,
        maxLines: maxLines,
        textAlign: material.TextAlign.center,
      );
      
      textPainter.layout(maxWidth: maxWidth);
      
      // If text fits, break
      if (textPainter.didExceedMaxLines == false) {
        break;
      }
      
      // Reduce font size and try again
      fontSize = fontSize * 0.85;
    }
    
    // Paint the text
    textPainter!.paint(canvas, material.Offset.zero);
    
    final picture = recorder.endRecording();
    final img = await picture.toImage(
      textPainter.width.ceil().clamp(1, 1000),
      textPainter.height.ceil().clamp(1, 1000),
    );
    
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Generate PDF document with barcode tags
  static Future<pw.Document> generateTags(List<Item> items) async {
    final pdf = pw.Document();
    
    // Load font - Roboto for clean numbers and text
    final bengaliFont = await PdfGoogleFonts.robotoRegular();
    
    // Pre-render ALL Bengali names as images first
    final allNameImages = <pw.MemoryImage?>[];
    for (final item in items) {
      try {
        final imageBytes = await _renderTextAsImage(
          item.name,
          maxFontSize: 11, // Maximum font size, will fit 2-3 lines
          maxWidth: tagWidth * 0.95 * 72, // Convert inches to points
          maxLines: 3,
        );
        allNameImages.add(pw.MemoryImage(imageBytes));
      } catch (e) {
        print('Error rendering Bengali text for ${item.name}: $e');
        allNameImages.add(null);
      }
    }
    
    // Split items into pages
    for (int page = 0; page < (items.length / tagsPerPage).ceil(); page++) {
      final startIndex = page * tagsPerPage;
      final endIndex = (startIndex + tagsPerPage).clamp(0, items.length);
      
      final pageItems = items.sublist(startIndex, endIndex);
      final pageNameImages = allNameImages.sublist(startIndex, endIndex);
      
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(pageMargin),
          build: (context) => _buildTagPage(pageItems, bengaliFont, pageNameImages),
        ),
      );
    }
    
    return pdf;
  }

  /// Build a page of tags
  static pw.Widget _buildTagPage(List<Item> items, pw.Font bengaliFont, List<pw.MemoryImage?> nameImages) {
    // Create grid of tags
    final rows = <pw.Widget>[];
    
    for (int row = 0; row < tagsPerColumn; row++) {
      final rowItems = <pw.Widget>[];
      
      for (int col = 0; col < tagsPerRow; col++) {
        final index = row * tagsPerRow + col;
        if (index < items.length) {
          rowItems.add(_buildTag(items[index], bengaliFont, nameImages[index]));
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
  static pw.Widget _buildTag(Item item, pw.Font bengaliFont, pw.MemoryImage? nameImage) {
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
        border: pw.Border.all(color: PdfColors.grey400, width: 0.3),
      ),
      child: pw.Column(
        children: [
          // FRONT SIDE (0.7" × 0.8")
          pw.Container(
            width: tagWidth,
            height: halfTagHeight,
            color: bgColor,
            padding: const pw.EdgeInsets.all(2),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                // Barcode with protective white background
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 2.5, vertical: 1.5),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(1)),
                  ),
                  child: pw.Column(
                    children: [
                      // Barcode
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.code128(),
                        data: item.barcode,
                        width: tagWidth * 0.88,
                        height: 14,
                        drawText: false,
                      ),
                      pw.SizedBox(height: 0.5),
                      // Barcode text
                      pw.Text(
                        item.barcode,
                        style: pw.TextStyle(
                          fontSize: 3.5,
                          fontWeight: pw.FontWeight.bold,
                          color: textColor,
                          font: bengaliFont,
                        ),
                      ),
                      pw.SizedBox(height: 0.5),
                      // Weight and Purity on same line: "2.500g - 18K"
                      pw.Text(
                        '${item.netWeight.toStringAsFixed(3)}g - ${item.purity}',
                        style: pw.TextStyle(
                          fontSize: 4,
                          fontWeight: pw.FontWeight.bold,
                          color: textColor,
                          font: bengaliFont,
                        ),
                      ),
                      // HUID on front side if exists
                      if (hasHallmark) ...[
                        pw.SizedBox(height: 0.3),
                        pw.Text(
                          'HUID: ${item.huid}',
                          style: pw.TextStyle(
                            fontSize: 2.8,
                            fontWeight: pw.FontWeight.bold,
                            color: textColor,
                            font: bengaliFont,
                          ),
                          maxLines: 1,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Fold line indicator
          pw.Container(
            width: tagWidth,
            height: 0.5,
            decoration: pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(
                  color: PdfColors.grey600,
                  width: 0.3,
                  style: pw.BorderStyle.dashed,
                ),
              ),
            ),
          ),
          
          // BACK SIDE (0.7" × 0.6")
          pw.Container(
            width: tagWidth,
            height: halfTagHeight - 0.5,
            color: bgColor,
            padding: const pw.EdgeInsets.all(2),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Item name as image - Flexible to accommodate long names
                pw.Expanded(
                  flex: 3,
                  child: pw.Container(
                    width: tagWidth * 0.95,
                    child: pw.Center(
                      child: nameImage != null
                          ? pw.Image(nameImage, fit: pw.BoxFit.contain)
                          : pw.Text(
                              item.name,
                              style: pw.TextStyle(
                                fontSize: item.name.length > 20 ? 4.5 : 5.5,
                                fontWeight: pw.FontWeight.bold,
                                color: textColor,
                                font: bengaliFont,
                              ),
                              maxLines: 3,
                              overflow: pw.TextOverflow.clip,
                              textAlign: pw.TextAlign.center,
                            ),
                    ),
                  ),
                ),
                
                // Weight (in white box)
                pw.Expanded(
                  flex: 2,
                  child: pw.Center(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                        border: pw.Border.all(color: accentColor, width: 0.4),
                      ),
                      child: pw.Text(
                        '${item.netWeight.toStringAsFixed(3)}g',
                        style: pw.TextStyle(
                          fontSize: 6.5,
                          fontWeight: pw.FontWeight.bold,
                          color: textColor,
                          font: bengaliFont,
                        ),
                      ),
                    ),
                  ),
                ),
                
                // Purity
                pw.Expanded(
                  flex: 2,
                  child: pw.Center(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: pw.BoxDecoration(
                        color: accentColor,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                      ),
                      child: pw.Text(
                        item.purity,
                        style: pw.TextStyle(
                          fontSize: 5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                          font: bengaliFont,
                        ),
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
