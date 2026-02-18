import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/container_model.dart';

/// Generates a PDF of container barcode tags.
///
/// Tag size: 1.5" wide × 0.5" tall — black & white only.
/// Layout per tag:
///   Left 58%  → Code128 barcode + code number text
///   Right 42% → Container name (small) + Container code (large, bold)
class ContainerTagPdfGenerator {
  // ── Tag dimensions ────────────────────────────────────────────────────────
  static const double tagWidth  = 1.5 * PdfPageFormat.inch;
  static const double tagHeight = 0.5 * PdfPageFormat.inch;

  // ── A4 page layout ────────────────────────────────────────────────────────
  static const double pageMargin    = 0.4 * PdfPageFormat.inch;
  static const double colGap        = 4.0; // pts between columns
  static const double rowGap        = 3.0; // pts between rows

  // Available width on A4: 8.27" − 2×0.4" = 7.47"
  // Tags per row: floor(7.47" / 1.5") = 4  (with small gaps)
  static const int tagsPerRow    = 4;
  // Available height on A4: 11.69" − 2×0.4" = 10.89"
  // Tags per column: floor(10.89" / 0.5") = 21
  static const int tagsPerColumn = 21;
  static const int tagsPerPage   = tagsPerRow * tagsPerColumn; // 84

  // ── Proportions inside a tag ──────────────────────────────────────────────
  static const double _barcodeRatio = 0.58; // left section width fraction
  static const double _infoRatio    = 0.42; // right section width fraction

  // ── Padding ───────────────────────────────────────────────────────────────
  static const double _padH = 3.0; // horizontal inner padding (pts)
  static const double _padV = 2.0; // vertical inner padding (pts)

  /// Generate and return a [pw.Document] for the given [containers].
  static Future<pw.Document> generateTags(
    List<ItemContainer> containers,
  ) async {
    final pdf = pw.Document();

    // Load a clean monospace-friendly font
    final font      = await PdfGoogleFonts.robotoRegular();
    final fontBold  = await PdfGoogleFonts.robotoBold();

    // Split into pages
    for (int page = 0;
        page < (containers.length / tagsPerPage).ceil();
        page++) {
      final start    = page * tagsPerPage;
      final end      = (start + tagsPerPage).clamp(0, containers.length);
      final pageContainers = containers.sublist(start, end);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(pageMargin),
          build: (ctx) =>
              _buildPage(pageContainers, font, fontBold),
        ),
      );
    }

    return pdf;
  }

  // ── Page builder ──────────────────────────────────────────────────────────

  static pw.Widget _buildPage(
    List<ItemContainer> containers,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final rows = <pw.Widget>[];

    for (int row = 0; row < tagsPerColumn; row++) {
      final rowWidgets = <pw.Widget>[];

      for (int col = 0; col < tagsPerRow; col++) {
        final idx = row * tagsPerRow + col;

        if (idx < containers.length) {
          rowWidgets.add(_buildTag(containers[idx], font, fontBold));
        } else {
          // Empty placeholder keeps grid aligned
          rowWidgets.add(
            pw.SizedBox(width: tagWidth, height: tagHeight),
          );
        }

        if (col < tagsPerRow - 1) {
          rowWidgets.add(pw.SizedBox(width: colGap));
        }
      }

      rows.add(
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          children: rowWidgets,
        ),
      );

      if (row < tagsPerColumn - 1) {
        rows.add(pw.SizedBox(height: rowGap));
      }
    }

    return pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.start,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: rows,
    );
  }

  // ── Single tag builder ────────────────────────────────────────────────────

  static pw.Widget _buildTag(
    ItemContainer container,
    pw.Font font,
    pw.Font fontBold,
  ) {
    // The barcode data is the container's qrCode (unique code like "SR-A-001").
    // Fall back to the container id if qrCode is absent.
    final code    = (container.qrCode?.isNotEmpty == true)
        ? container.qrCode!
        : container.id.substring(0, 8);
    final name    = container.name;

    final barcodeWidth = tagWidth * _barcodeRatio;
    final infoWidth    = tagWidth * _infoRatio;
    final innerH       = tagHeight - 2 * _padV;

    return pw.Container(
      width: tagWidth,
      height: tagHeight,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColors.black, width: 0.5),
      ),
      child: pw.Row(
        children: [
          // ── LEFT: barcode + code number ──────────────────────────────
          pw.Container(
            width: barcodeWidth,
            height: tagHeight,
            padding: pw.EdgeInsets.symmetric(
              horizontal: _padH,
              vertical: _padV,
            ),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Barcode graphic
                pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),
                  data: code,
                  width: barcodeWidth - 2 * _padH,
                  height: innerH * 0.62,
                  drawText: false,
                  color: PdfColors.black,
                ),
                pw.SizedBox(height: 1),
                // Code number below barcode
                pw.Text(
                  code,
                  style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 5.5,
                    color: PdfColors.black,
                    letterSpacing: 0.5,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ],
            ),
          ),

          // Thin vertical divider
          pw.Container(
            width: 0.5,
            height: tagHeight,
            color: PdfColors.grey400,
          ),

          // ── RIGHT: name + code (bold, large) ─────────────────────────
          pw.Container(
            width: infoWidth - 0.5, // subtract divider width
            height: tagHeight,
            padding: pw.EdgeInsets.symmetric(
              horizontal: _padH,
              vertical: _padV,
            ),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Container name — small, fits in one line
                pw.Text(
                  name,
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 5.5,
                    color: PdfColors.grey700,
                  ),
                  maxLines: 2,
                  overflow: pw.TextOverflow.clip,
                ),
                pw.SizedBox(height: 1.5),
                // Container code — large, bold, most prominent
                pw.Text(
                  code,
                  style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 16.0,
                    color: PdfColors.black,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// How many pages will be needed for [containerCount] containers.
  static int calculatePageCount(int containerCount) =>
      (containerCount / tagsPerPage).ceil();
}
