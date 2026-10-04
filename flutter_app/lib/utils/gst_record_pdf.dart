import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' show NumberFormat;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// The monthly "GST INVOICE RECORD": the website's layout (logo + GSTIN header, one bordered block per invoice, a tinted
/// tax row, "Amount in Words / Total Payable", then the "Comprehensive GST Monthly Summary") on A4 LANDSCAPE, with the
/// detail an audit or a customer query needs: purity, gross and net weight, product code, HUID, stones and other
/// extras, hallmark charge, making charge, the discount, every payment received, who billed it and when.
///
/// EVERY invoice of the month is listed (cancelled / void / deleted too, stamped as such); only Active, Revised,
/// Pending and Delivered invoices count in the totals.
///
/// Space: an invoice is a compact block (info strip, item rows, one totals row, one payments line), so 4-6 invoices
/// fit on a landscape page. Every table uses fixed point widths that add up to the page width, so columns line up.

String _s(dynamic v) => (v ?? '').toString();
double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse(_s(v)) ?? 0;
Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _l(dynamic v) => v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
String _clip(String t, int n) => t.length <= n ? t : '${t.substring(0, n - 1)}…';

const _brown = PdfColor.fromInt(0xFF8B4513);
const _grey = PdfColor.fromInt(0xFF666666);
const _line = PdfColor.fromInt(0xFF999999);
const _head = PdfColor.fromInt(0xFFF5F5F5);
const _gstRow = PdfColor.fromInt(0xFFFFF3CD);
const _blue = PdfColor.fromInt(0xFF1976D2);
const _green = PdfColor.fromInt(0xFF2E7D32);
const _red = PdfColor.fromInt(0xFFDC3545);

// Compact block (points; A4 landscape less 23pt margins = 795):
//   strip:  No | Date | Customer | State / place | Billed | Status
//   items:  Particulars | Metal | Gross | Net | Rate | Metal value | Making | Stones | Hallmark | Taxable
//   totals: Taxable | Additional | CGST | SGST (or IGST) | Discount | Round off | Total payable
const _strip = <double>[62, 92, 246, 140, 185, 70];
const _items = <double>[290, 50, 52, 52, 58, 68, 58, 52, 50, 65];
const _total = 795.0;
const _blockBudget = 330.0; // points of item rows per block (a landscape page has ~538 usable; a block adds ~110 of its own)

Future<Uint8List> buildMonthlyRecordPdf(Map<String, dynamic> data) async {
  pw.Font? base, bold, bengali;
  try {
    base = await PdfGoogleFonts.notoSansRegular();
    bold = await PdfGoogleFonts.notoSansBold();
    bengali = await PdfGoogleFonts.notoSansBengaliRegular();
  } catch (_) {/* offline: the standard font is used (Rs. instead of the rupee sign, English words only) */}
  // Offline, PdfGoogleFonts quietly hands back a built-in font that cannot draw the rupee sign or Bengali: detect it.
  final fonts = base is pw.TtfFont && bold is pw.TtfFont;
  final bnOk = bengali is pw.TtfFont;
  final rupee = fonts ? '₹' : 'Rs.';
  String words(dynamic v) {
    final t = _s(v);
    return (!bnOk && RegExp(r'[^\x00-\x7F]').hasMatch(t)) ? t.replaceAll(RegExp(r'\s*\(.*\)\s*$'), '') : t;
  }

  pw.MemoryImage? logo;
  try {
    final bytes = await rootBundle.load('assets/images/lgp_logo_red.png');
    logo = pw.MemoryImage(bytes.buffer.asUint8List());
  } catch (_) {/* text header instead */}

  final f2 = NumberFormat('#,##,##0.00', 'en_IN');
  final f0 = NumberFormat('#,##,##0', 'en_IN');
  String m2(dynamic v) => f2.format(_n(v));
  String m(dynamic v) => '$rupee${f2.format(_n(v))}';
  String w3(dynamic v) => _n(v) > 0 ? _n(v).toStringAsFixed(3) : '-';
  String d(dynamic v) {
    final p = DateTime.tryParse(_s(v));
    return p == null ? '' : '${p.day.toString().padLeft(2, '0')}-${p.month.toString().padLeft(2, '0')}-${p.year}';
  }

  /// "dd-mm-yyyy hh:mm" in India time from an ISO stamp
  String dt(dynamic v) {
    final p = DateTime.tryParse(_s(v));
    if (p == null) return '';
    final ist = p.toUtc().add(const Duration(hours: 5, minutes: 30));
    return '${ist.day.toString().padLeft(2, '0')}-${ist.month.toString().padLeft(2, '0')}-${ist.year} ${ist.hour.toString().padLeft(2, '0')}:${ist.minute.toString().padLeft(2, '0')}';
  }

  final period = _m(data['period']);
  final monthName = _s(period['monthName']);
  final year = _s(period['year']);
  final titleMonth = '${monthName.toUpperCase()} $year';
  final seller = _m(data['seller']);
  final scope = _m(data['scope']);
  final invoices = _l(data['invoices']);
  final totals = _m(data['totals']);
  final tr = _m(data['tracking']);
  final bd = _m(data['breakdown']);
  final docId = _s(data['documentId']);
  final generatedAt = _s(data['generatedAt']);
  final partial = data['partial'] == true;
  final scopeLabel = _s(scope['label']);

  final theme = fonts ? pw.ThemeData.withFont(base: base, bold: bold, fontFallback: [if (bnOk) bengali]) : pw.ThemeData();

  // ── small building blocks ──
  pw.Widget txt(String t, {double size = 7.2, bool b = false, PdfColor? color, pw.TextAlign align = pw.TextAlign.left}) =>
      pw.Text(t, textAlign: align, style: pw.TextStyle(fontSize: size, fontWeight: b ? pw.FontWeight.bold : pw.FontWeight.normal, color: color));

  // A bordered table cell. (No `alignment` on the Container: an aligned Container grows to the space left on the page while
  // the table measures its rows, which squashed and overlapped the header rows of the last blocks on a page. Text
  // alignment is done with textAlign instead.)
  pw.Widget tc(pw.Widget child, {PdfColor? bg, pw.Alignment? align, bool border = true, double pad = 3}) => pw.Container(
        padding: pw.EdgeInsets.all(pad),
        decoration: pw.BoxDecoration(color: bg, border: border ? pw.Border.all(color: _line, width: 0.3) : null),
        child: child,
      );

  // one table row with fixed column widths (all tables of a block share these, which is what keeps them aligned)
  pw.Table grid(List<double> widths, List<pw.Widget> cells) => pw.Table(
        columnWidths: {for (var i = 0; i < widths.length; i++) i: pw.FixedColumnWidth(widths[i])},
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
        children: [pw.TableRow(children: cells)],
      );

  pw.Widget kv(String k, String v, {double size = 6.8}) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 0.7),
      child: pw.RichText(text: pw.TextSpan(children: [pw.TextSpan(text: '$k ', style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold)), pw.TextSpan(text: v, style: pw.TextStyle(fontSize: size))])));

  pw.Widget sub(String t, {PdfColor color = _grey}) => txt(t, size: 6.1, color: color);

  // A NEW widget for every use: a pw.Table keeps layout state, so one instance shared by many blocks corrupts itself
  // (rows collapsed and overlapped, and a whole page went missing in an earlier version).
  const heads = ['Particulars (HSN) / Code / HUID', 'Metal', 'Gross (g)', 'Net (g)', 'Rate / g', 'Metal Value', 'Making', 'Stones', 'Hallmark', 'Taxable Amt'];
  pw.Widget headerRow() => grid(_items, [for (var i = 0; i < heads.length; i++) tc(txt(heads[i], size: 6.4, b: true, align: i == 0 ? pw.TextAlign.left : pw.TextAlign.center), bg: _head, pad: 2.2)]);

  String extrasText(Map<String, dynamic> e) {
    final unit = const ['Stone', 'Diamond', 'Pearl'].contains(_s(e['kind'])) ? 'ct' : 'g';
    final wt = _n(e['weight']) > 0 ? ' ${_n(e['weight']).toStringAsFixed(2)}$unit' : '';
    return '${_s(e['name']).isEmpty ? _s(e['kind']) : _s(e['name'])}$wt ${m2(e['amount'])}';
  }

  // ── one invoice block ──
  List<pw.Widget> invoiceBlock(Map<String, dynamic> inv) {
    final status = _s(inv['status']);
    final counted = inv['counted'] == true;
    final igst = _s(inv['gstType']) == 'IGST';
    final cust = _m(inv['customer']);
    final items = _l(inv['items']);
    final tds = inv['tds'] is Map ? _m(inv['tds']) : null;
    final payments = _l(inv['payments']);
    final ink = counted ? null : const PdfColor.fromInt(0xFF888888);
    final stampColor = counted ? _green : _red;

    // Item rows are grouped so one block always fits on a page: each row's height is estimated and added up until the
    // budget is reached, then a "(contd.)" block starts.
    double rowHeight(Map<String, dynamic> it) {
      final nameLines = ((_s(it['name']).length + 4) / 52).ceil().clamp(1, 6);
      final hasSub = _s(it['code']).isNotEmpty || _s(it['huid']).isNotEmpty || _s(it['certification']).isNotEmpty;
      return (nameLines + (hasSub ? 0.8 : 0) + _l(it['extras']).length * 0.8 + (_n(it['discount']) > 0 ? 0.8 : 0)) * 8.6 + 6;
    }

    final chunks = <List<Map<String, dynamic>>>[];
    var cur = <Map<String, dynamic>>[];
    var used = 0.0;
    for (final it in items) {
      final h = rowHeight(it);
      if (cur.isNotEmpty && used + h > _blockBudget) {
        chunks.add(cur);
        cur = <Map<String, dynamic>>[];
        used = 0;
      }
      cur.add(it);
      used += h;
    }
    chunks.add(cur); // (an invoice without items still gets its block)

    pw.Widget particulars(Map<String, dynamic> it) {
      final ids = <String>[
        if (_s(it['code']).isNotEmpty) 'Code ${_s(it['code'])}',
        if (_s(it['huid']).isNotEmpty) 'HUID ${_s(it['huid'])}' else if (_s(it['certification']).isNotEmpty) 'Hallmarked',
        if (_s(it['purity']).isNotEmpty) 'Purity ${_s(it['purity'])}',
        for (final e in _l(it['extras'])) '+ ${extrasText(e)}',
      ];
      final shownName = _s(it['itemName']).isNotEmpty ? _s(it['itemName']) : _s(it['name']);
      // one RichText (not a Column): the second line of a Column inside a table cell was silently dropped
      return pw.RichText(
        text: pw.TextSpan(children: [
          pw.TextSpan(text: '${words(shownName)} (${_s(it['hsn'])})', style: pw.TextStyle(fontSize: 7.2, fontWeight: pw.FontWeight.bold, color: ink)),
          if (ids.isNotEmpty) pw.TextSpan(text: '\n${ids.join('  |  ')}', style: const pw.TextStyle(fontSize: 6.1, color: _grey)),
        ]),
      );
    }

    pw.Widget num(String t, {Map<String, dynamic>? it, bool bold = false, String? under}) => pw.Column(mainAxisSize: pw.MainAxisSize.min, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          txt(t, b: bold, color: ink, align: pw.TextAlign.right),
          if (under != null) sub(under),
        ]);

    // strip: who / when / where, on two or three lines
    pw.Widget strip(bool cont) => grid(_strip, [
          tc(pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [txt(_s(inv['number']), size: _s(inv['number']).length > 6 ? 7.6 : 9.2, b: true, color: ink, align: pw.TextAlign.center), if (cont) sub('(contd.)')]), bg: _head, pad: 2.5),
          tc(cont ? txt('') : pw.Column(mainAxisSize: pw.MainAxisSize.min, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                txt(d(inv['date']), size: 8.2, b: true, color: ink),
                if (_s(inv['delivery']).isNotEmpty && _s(inv['delivery']) != _s(inv['date'])) kv('Delivery:', d(inv['delivery']), size: 6.3) else txt(_s(inv['terms']), size: 6.3, color: _grey),
              ]), bg: _head, pad: 2.5),
          tc(cont ? txt('') : pw.Column(mainAxisSize: pw.MainAxisSize.min, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                txt('${words(cust['name'])}${_s(cust['mobile']).isEmpty ? '' : '  |  ${_s(cust['mobile'])}'}', size: 7.6, b: true, color: ink),
                if (_s(cust['address']).isNotEmpty) txt(_clip(_s(cust['address']), 110), size: 6.5, color: _grey),
              ]), bg: _head, pad: 2.5),
          tc(cont ? txt('') : pw.Column(mainAxisSize: pw.MainAxisSize.min, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                kv('POS:', _s(inv['placeOfSupply']), size: 6.5),
                kv(_s(cust['pan']).isNotEmpty ? 'PAN:' : 'Rev. charge:', _s(cust['pan']).isNotEmpty ? '${_s(cust['pan'])}${_s(inv['reverseCharge']) == 'Yes' ? '  (Reverse charge)' : ''}' : _s(inv['reverseCharge']), size: 6.5),
              ]), bg: _head, pad: 2.5),
          tc(cont ? txt('') : pw.Column(mainAxisSize: pw.MainAxisSize.min, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                kv('Billed:', [if (_s(inv['branch']).isNotEmpty) _s(inv['branch']), if (_s(inv['createdBy']).isNotEmpty) _s(inv['createdBy'])].join(' | '), size: 6.3),
                txt([dt(inv['createdAt']), if (_n(inv['goldRate']) > 0 || _n(inv['silverRate']) > 0) 'Au ${f0.format(_n(inv['goldRate']))} Ag ${_n(inv['silverRate'])}'].where((e) => e.isNotEmpty).join(' | '), size: 6.3, color: _grey),
              ]), bg: _head, pad: 2.5),
          tc(pw.Center(child: pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1.5), decoration: pw.BoxDecoration(border: pw.Border.all(color: stampColor, width: 0.9), borderRadius: pw.BorderRadius.circular(2)), child: txt(status.toUpperCase(), size: 6.8, b: true, color: stampColor))), bg: _head, pad: 2.5),
        ]);

    pw.Widget itemRows(List<Map<String, dynamic>> rows) => pw.Table(
          columnWidths: {for (var i = 0; i < _items.length; i++) i: pw.FixedColumnWidth(_items[i])},
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
          children: [
            for (final it in rows)
              pw.TableRow(children: [
                tc(particulars(it), pad: 2.4),
                tc(pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [txt(_s(it['metal']), color: ink, align: pw.TextAlign.center)]), pad: 2.4),
                tc(num(w3(it['grossWt'])), pad: 2.4),
                tc(num(w3(it['netWt'])), pad: 2.4),
                tc(num(m2(it['rate'])), pad: 2.4),
                tc(num(m2(it['metalValue'])), pad: 2.4),
                tc(num('${m2(it['making'])}${it['makingDerived'] == true ? '*' : ''}'), pad: 2.4),
                tc(num(_n(it['stone']) > 0 ? m2(it['stone']) : '-'), pad: 2.4),
                tc(num(_n(it['hallmark']) > 0 ? '${m2(it['hallmark'])}${it['hallmarkTaxed'] == false ? ' ^' : ''}' : '-'), pad: 2.4),
                tc(num(m2(it['amount']), bold: true, under: _n(it['discount']) > 0 ? 'after disc. ${m2(it['discount'])}' : null), pad: 2.4),
              ]),
            if (rows.isEmpty) pw.TableRow(children: [tc(txt('No items recorded', color: ink), pad: 2.4), for (var i = 1; i < _items.length; i++) tc(txt(''), pad: 2.4)]),
          ],
        );

    // ONE totals row: label above value in each cell (tinted like the website's tax row)
    pw.Widget totalsRow() {
      final cells = <(String, String, double)>[
        ('Taxable value', m2(inv['taxable']), 132),
        ('Additional charges${_n(inv['additionalChargesGst']) > 0 ? ' (GST ${m2(inv['additionalChargesGst'])})' : ''}', m2(inv['additionalCharges']), 130),
        if (igst) ('IGST 3%', m2(inv['igst']), 250) else ...[('CGST 1.5%', m2(inv['cgst']), 125), ('SGST 1.5%', m2(inv['sgst']), 125)],
        (inv['discountBeforeGst'] == true && _n(inv['discount']) > 0 ? 'Discount (before GST)' : 'Discount', m2(inv['discount']), 110),
        ('Round off', '${_n(inv['roundOff']) >= 0 ? '+' : ''}${m2(inv['roundOff'])}', 68),
        ('TOTAL PAYABLE', m2(inv['totalPayable']), 795 - 132 - 130 - 250 - 110 - 68),
      ];
      return grid([for (final c in cells) c.$3], [
        for (var i = 0; i < cells.length; i++)
          tc(pw.Column(mainAxisSize: pw.MainAxisSize.min, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            txt(cells[i].$1, size: 6.1, color: _grey, align: pw.TextAlign.right),
            txt(cells[i].$2, size: i == cells.length - 1 ? 9 : 7.6, b: true, color: ink, align: pw.TextAlign.right),
          ]), bg: i == cells.length - 1 ? const PdfColor.fromInt(0xFFFFE9A8) : _gstRow, pad: 2.2),
      ]);
    }

    // ONE payments line (left) and the amount in words (right)
    pw.Widget footRow() {
      final pay = payments.take(4).map((p) => '${d(p['date'])} ${_s(p['mode'])} ${m2(p['amount'])}${_s(p['reference']).isEmpty || _s(p['reference']).startsWith('Initial payment') ? '' : ' (${_clip(_s(p['reference']), 20)})'}').join('   |   ');
      final more = payments.length > 4 ? '   + ${payments.length - 4} more' : '';
      final facts = <String>[
        'Paid ${m2(inv['paid'])}',
        if (_n(inv['due']) > 0) 'DUE ${m2(inv['due'])}',
        if (_n(inv['advance']) > 0) 'Advance ${m2(inv['advance'])}',
        if (tds != null) 'TDS ${_s(tds['rate'])}% $rupee${m2(tds['amount'])}',
        if (_s(inv['revisionId']).isNotEmpty) 'Revision of ${_s(inv['revisionId'])}',
      ].join('  |  ');
      final note = [if (_s(inv['note']).isNotEmpty) 'Note: ${_clip(_s(inv['note']), 90)}', if (_s(inv['reference']).isNotEmpty) 'Ref: ${_s(inv['reference'])}'].join('   ');
      return grid([345, 450], [
        tc(pw.Column(mainAxisSize: pw.MainAxisSize.min, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          txt('Payment: ${_s(inv['paymentMode'])}   $facts', size: 6.7, b: true, color: ink),
          if (pay.isNotEmpty) txt('$pay$more', size: 6.2, color: _grey),
          if (note.isNotEmpty) txt(note, size: 6.2, color: _grey),
        ]), pad: 2.2),
        tc(pw.RichText(text: pw.TextSpan(children: [pw.TextSpan(text: 'In words: ', style: pw.TextStyle(fontSize: 6.7, fontWeight: pw.FontWeight.bold)), pw.TextSpan(text: words(inv['amountInWords']).isEmpty ? 'N/A' : words(inv['amountInWords']), style: const pw.TextStyle(fontSize: 6.7))])), pad: 2.2),
      ]);
    }

    final blocks = <pw.Widget>[];
    for (var c = 0; c < chunks.length; c++) {
      final isLast = c == chunks.length - 1;
      // A one-row Table cannot be split between pages, so a whole invoice block moves to the next page together.
      blocks.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3.5),
        child: pw.Table(columnWidths: {0: pw.FixedColumnWidth(_total)}, children: [
          pw.TableRow(children: [pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [strip(c > 0), headerRow(), itemRows(chunks[c]), if (isLast) totalsRow(), if (isLast) footRow()])]),
        ]),
      ));
    }
    return blocks;
  }

  // ── summary sections ──
  pw.Widget lbl(String t) => pw.Container(padding: const pw.EdgeInsets.all(3.6), decoration: pw.BoxDecoration(color: _head, border: pw.Border.all(color: _line, width: 0.4)), child: txt(t, size: 7.8, b: true));
  pw.Widget val(String t, {PdfColor? color, double size = 8}) => pw.Container(padding: const pw.EdgeInsets.all(3.6), alignment: pw.Alignment.centerRight, decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.4)), child: txt(t, size: size, b: true, color: color, align: pw.TextAlign.right));
  pw.Widget band(String t, PdfColor bg, {PdfColor fg = PdfColors.white, double size = 8.4}) => pw.Container(width: double.infinity, color: bg, padding: const pw.EdgeInsets.all(4), child: txt(t, size: size, b: true, color: fg, align: pw.TextAlign.center));
  pw.TableRow row6(List<String> t, {Map<int, PdfColor> colors = const {}}) => pw.TableRow(children: [
        for (var i = 0; i < 3; i++) ...[t[i * 2].isEmpty ? pw.SizedBox() : lbl(t[i * 2]), t[i * 2].isEmpty ? pw.SizedBox() : val(t[i * 2 + 1], color: colors[i])],
      ]);
  pw.Table six(List<pw.TableRow> rows) => pw.Table(columnWidths: const {0: pw.FlexColumnWidth(1.25), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1.25), 3: pw.FlexColumnWidth(1), 4: pw.FlexColumnWidth(1.25), 5: pw.FlexColumnWidth(1)}, children: rows);

  final valid = _n(tr['valid']);
  final summary = pw.Container(
    margin: const pw.EdgeInsets.only(top: 12),
    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey800, width: 1.4), borderRadius: pw.BorderRadius.circular(6)),
    child: pw.Column(children: [
      band('COMPREHENSIVE GST MONTHLY SUMMARY - $titleMonth', _blue, size: 10.5),
      pw.Container(
        width: double.infinity,
        color: const PdfColor.fromInt(0xFFE3F2FD),
        padding: const pw.EdgeInsets.all(5),
        child: pw.RichText(
          textAlign: pw.TextAlign.center,
          text: pw.TextSpan(style: const pw.TextStyle(fontSize: 8, color: _blue), children: [
            pw.TextSpan(text: 'Period Summary: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.TextSpan(text: '${f0.format(valid)} Valid Transactions | $rupee${f0.format(_n(totals['amount']))} Total Revenue | ${_n(tr['gstRate']).toStringAsFixed(1)}% Effective GST Rate'),
          ]),
        ),
      ),
      band('INVOICE TRACKING & AUDIT TRAIL', _blue, size: 8),
      six([
        row6(['Starting Invoice No:', f0.format(_n(tr['start'])), 'Ending Invoice No:', f0.format(_n(tr['end'])), 'Total Invoices (All):', f0.format(_n(tr['total']))], colors: {0: _blue, 1: _blue}),
        for (final b in _l(tr['branchSeries'])) row6(['Branch series ${_s(b['name'])}:', '${_s(b['from'])} to ${_s(b['to'])}', 'Invoices in series:', f0.format(_n(b['count'])), '', '']),
        row6(['Valid/Active Invoices:', f0.format(valid), 'Cancelled/Void/Deleted:', f0.format(_n(tr['cancelledVoidDeleted'])), 'Average Invoice Value:', '$rupee${f0.format(_n(tr['avgInvoice']))}'], colors: {0: _green, 1: _red}),
      ]),
      band('FINANCIAL SUMMARY & TAX BREAKDOWN', _head, fg: PdfColors.grey900, size: 8),
      six([
        row6(['Taxable Amount:', m(totals['taxable']), 'CGST @ ${_n(tr['cgstRate']).toStringAsFixed(1)}%:', m(totals['cgst']), 'Total Amount (Incl. Tax):', m(totals['amount'])]),
        row6(['Additional Charges:', m(totals['additional']), 'SGST @ ${_n(tr['sgstRate']).toStringAsFixed(1)}%:', m(totals['sgst']), 'Total GST Collected:', m(totals['gst'])]),
        row6(['Discount Given:', m(totals['discount']), 'IGST @ ${_n(tr['igstRate']).toStringAsFixed(1)}%:', m(totals['igst']), 'Net GST Liability:', m(totals['gst'])], colors: {2: const PdfColor.fromInt(0xFFD32F2F)}),
      ]),
      band('INVENTORY MOVEMENT', _head, fg: PdfColors.grey900, size: 8),
      six([
        row6(['Gold Sold (net):', '${_n(totals['goldWeight']).toStringAsFixed(2)} gm', 'Silver Sold (net):', '${_n(totals['silverWeight']).toStringAsFixed(2)} gm', 'Gross Weight:', '${_n(totals['grossWeight']).toStringAsFixed(2)} gm']),
        row6(['Metal Value:', m(totals['metalValue']), 'Making Charges:', m(totals['making']), 'Stones + Hallmark:', m(_n(totals['stone']) + _n(totals['hallmark']))]),
      ]),
      band('GST RETURN FILING READY DATA', _green, size: 8),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.green, width: 0.5), columnWidths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth(), 2: pw.FlexColumnWidth(), 3: pw.FlexColumnWidth()}, children: [
        pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8F5E8)), children: [
          pw.Padding(padding: const pw.EdgeInsets.all(4), child: txt('GSTR-1 OUTWARD', size: 8, b: true, align: pw.TextAlign.center)),
          pw.Padding(padding: const pw.EdgeInsets.all(4), child: txt(m(totals['amount']), size: 10.5, b: true, color: const PdfColor.fromInt(0xFF1B5E20), align: pw.TextAlign.center)),
          pw.Padding(padding: const pw.EdgeInsets.all(4), child: txt('GSTR-3B TAX', size: 8, b: true, align: pw.TextAlign.center)),
          pw.Padding(padding: const pw.EdgeInsets.all(4), child: txt(m(totals['gst']), size: 10.5, b: true, color: const PdfColor.fromInt(0xFF1B5E20), align: pw.TextAlign.center)),
        ]),
      ]),
      pw.Container(
        margin: const pw.EdgeInsets.all(6),
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFFFF9C4), border: pw.Border.all(color: const PdfColor.fromInt(0xFFFBC02D), width: 0.7), borderRadius: pw.BorderRadius.circular(3)),
        child: pw.Column(mainAxisSize: pw.MainAxisSize.min, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Center(child: txt('IMPORTANT NOTES', size: 8.4, b: true, color: const PdfColor.fromInt(0xFFF57C00))),
          pw.SizedBox(height: 3),
          _note('Invoice Coverage: ', 'This report includes ALL invoices (Active, Revised, Pending, Delivered, Cancelled, Void, Deleted) for a complete audit trail.'),
          _note('Financial Totals: ', 'Only Active, Revised, Pending and Delivered invoices are included in the GST calculations and financial totals.'),
          _note('GST Filing: ', 'Amounts shown are based on outward supplies only. Final GST liability may vary due to ITC, RCM and other adjustments.', red: true),
          _note('Discounts: ', 'On invoices made in the app, a discount is deducted BEFORE GST (item amounts are already net); older invoices took it off after GST.'),
          _note('Making charge: ', 'A figure marked * is derived (taxable amount less metal, stones and hallmark) because the taxable amount was typed in by hand.'),
          _note('Hallmark fee: ', 'A figure marked ^ is a hallmark / HUID fee passed on after the tax: it is not part of the Taxable Amt and carries no GST. Older invoices had it inside the taxable amount.'),
          if (partial) _note('Scope: ', 'This record covers only the branch of the person who generated it, not the whole firm.', red: true),
        ]),
      ),
      pw.Container(
        width: double.infinity,
        decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFF263238), borderRadius: const pw.BorderRadius.only(bottomLeft: pw.Radius.circular(6), bottomRight: pw.Radius.circular(6))),
        padding: const pw.EdgeInsets.all(6),
        child: txt('This report contains ${f0.format(_n(tr['total']))} total invoices (${f0.format(valid)} valid for GST, ${f0.format(_n(tr['cancelledVoidDeleted']))} cancelled/void/deleted) for $monthName $year.', size: 7.2, color: PdfColors.white, align: pw.TextAlign.center),
      ),
    ]),
  );

  // "breakdown for audit": what was sold (metal x purity), how it was paid, and by which shop
  pw.Widget breakdownTable(String title, List<String> head, List<List<String>> rows, List<double> flex) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Column(mainAxisSize: pw.MainAxisSize.min, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(width: double.infinity, color: _blue, padding: const pw.EdgeInsets.all(3.5), child: txt(title, size: 8, b: true, color: PdfColors.white)),
          pw.Table(
            border: pw.TableBorder.all(color: _line, width: 0.3),
            columnWidths: {for (var i = 0; i < flex.length; i++) i: pw.FlexColumnWidth(flex[i])},
            children: [
              pw.TableRow(decoration: const pw.BoxDecoration(color: _head), children: [for (var i = 0; i < head.length; i++) pw.Padding(padding: const pw.EdgeInsets.all(3), child: txt(head[i], size: 7, b: true, align: i == 0 ? pw.TextAlign.left : pw.TextAlign.right))]),
              for (final r in rows) pw.TableRow(children: [for (var i = 0; i < r.length; i++) pw.Padding(padding: const pw.EdgeInsets.all(3), child: txt(r[i], size: 7.2, align: i == 0 ? pw.TextAlign.left : pw.TextAlign.right))]),
            ],
          ),
        ]),
      );

  final metals = _l(bd['metals']);
  final pays = _l(bd['payments']);
  final branches = _l(bd['branches']);
  final breakdown = pw.Container(
    margin: const pw.EdgeInsets.only(top: 12),
    child: pw.Column(mainAxisSize: pw.MainAxisSize.min, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Center(child: txt('AUDIT BREAKDOWN - $titleMonth  (counted invoices only)', size: 10, b: true)),
      pw.SizedBox(height: 6),
      if (metals.isNotEmpty)
        breakdownTable('SOLD BY METAL AND PURITY', ['Metal / purity', 'Pieces', 'Gross wt (g)', 'Net wt (g)', 'Taxable value'],
            [for (final e in metals) ['${_s(e['metal'])} ${_s(e['purity'])}'.trim(), f0.format(_n(e['pieces'])), _n(e['grossWt']).toStringAsFixed(3), _n(e['netWt']).toStringAsFixed(3), m(e['taxable'])]], [3, 1, 1.4, 1.4, 1.8]),
      if (pays.isNotEmpty) breakdownTable('RECEIVED BY PAYMENT MODE (as recorded on the invoices)', ['Mode', 'Receipts', 'Amount'], [for (final e in pays) [_s(e['mode']), f0.format(_n(e['count'])), m(e['amount'])]], [3, 1, 2]),
      if (branches.length > 1) breakdownTable('BY BRANCH', ['Branch', 'Invoices', 'Taxable value', 'GST', 'Invoice value'], [for (final e in branches) [_s(e['branch']), f0.format(_n(e['invoices'])), m(e['taxable']), m(e['gst']), m(e['amount'])]], [3, 1, 2, 2, 2]),
    ]),
  );

  // ── the document ──
  final doc = pw.Document(theme: theme, title: 'GST Invoice Record - $monthName $year', author: _s(seller['firmName']));
  doc.addPage(pw.MultiPage(
    maxPages: 3000, // a busy month can run to hundreds of pages
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.fromLTRB(23, 18, 23, 28),
    footer: (ctx) => ctx.pageNumber > 1
        ? pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            txt('Generated: $generatedAt | Doc ID: $docId', size: 6.6, color: _grey),
            txt('CERTIFIED TRUE COPY - GST RECORD $titleMonth', size: 6.8, b: true, color: PdfColors.grey800),
            txt('Page ${ctx.pageNumber} of ${ctx.pagesCount}', size: 7.4, color: _grey),
          ])
        : pw.Align(alignment: pw.Alignment.centerRight, child: txt('Page ${ctx.pageNumber} of ${ctx.pagesCount}', size: 7.4, color: _grey)),
    build: (ctx) => [
      pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(bottom: 6),
        padding: const pw.EdgeInsets.only(bottom: 4),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1.6, color: PdfColors.grey800))),
        child: pw.Column(children: [
          if (logo != null) pw.SizedBox(height: 34, child: pw.Image(logo, fit: pw.BoxFit.contain)) else txt(_s(seller['firmName']).isEmpty ? 'LGP JEWELLERY' : _s(seller['firmName']), size: 16, b: true, color: _brown),
          pw.SizedBox(height: 2),
          txt('GSTIN: ${_s(seller['gstin'])}', size: 10, b: true, color: _brown),
          if (scopeLabel.isNotEmpty) txt('Covers: $scopeLabel', size: 7.6, color: _grey),
          pw.SizedBox(height: 3),
          txt('GST INVOICE RECORD - $titleMonth', size: 12, b: true),
        ]),
      ),
      for (final inv in invoices) ...invoiceBlock(inv),
      // one-row Tables: a summary is never split between two pages
      pw.Table(columnWidths: {0: pw.FixedColumnWidth(_total)}, children: [pw.TableRow(children: [summary])]),
      if (metals.isNotEmpty || pays.isNotEmpty) pw.Table(columnWidths: {0: pw.FixedColumnWidth(_total)}, children: [pw.TableRow(children: [breakdown])]),
    ],
  ));
  return doc.save();
}

pw.Widget _note(String head, String body, {bool red = false}) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2.5),
      child: pw.RichText(
        text: pw.TextSpan(style: const pw.TextStyle(fontSize: 7.2, lineSpacing: 1.4), children: [
          pw.TextSpan(text: '- $head', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.2)),
          pw.TextSpan(text: body, style: pw.TextStyle(fontSize: 7.2, color: red ? const PdfColor.fromInt(0xFFD32F2F) : null, fontWeight: red ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ]),
      ),
    );
