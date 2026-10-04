import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

String _s(dynamic v) => (v ?? '').toString();
double _n(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(_s(v)) ?? 0;

/// Builds the printable TAX INVOICE, laid out like the live website's (LGPManagement)
/// print template: seller header + GSTIN, customer and invoice blocks, item
/// table with HSN and CGST/SGST columns, GST summary, payment info, terms.
///
/// Fonts: Noto Sans (has the rupee sign) and Noto Sans Bengali (for the amount
/// in words) are fetched on first use. If the device is offline the PDF is
/// still produced with the standard font ("Rs." and English words only).
Future<Uint8List> buildInvoicePdf({
  required Map<String, dynamic> inv,
  required Map<String, dynamic> seller,
  required List<String> terms,
  required String declaration,
  String copyType = 'ORIGINAL', // 'ORIGINAL' first time, then 'DUPLICATE' (counted by the server)
}) async {
  pw.Font? base, bold, bengali;
  try {
    base = await PdfGoogleFonts.notoSansRegular();
    bold = await PdfGoogleFonts.notoSansBold();
    bengali = await PdfGoogleFonts.notoSansBengaliRegular();
  } catch (_) {/* offline: fall back below */}
  final haveFonts = base is pw.TtfFont && bold is pw.TtfFont; // offline the package returns a built-in font that cannot draw the rupee sign
  final rupee = haveFonts ? '₹' : 'Rs.';

  final money = NumberFormat('#,##,##0.00', 'en_IN');
  String m(dynamic v) => '$rupee ${money.format(_n(v))}';
  String d(dynamic v) {
    final dt = DateTime.tryParse(_s(v))?.toLocal();
    return dt == null ? '' : DateFormat('dd-MM-yyyy').format(dt);
  }

  final theme = haveFonts
      ? pw.ThemeData.withFont(base: base, bold: bold, fontFallback: [if (bengali is pw.TtfFont) bengali])
      : pw.ThemeData();

  final items = (inv['items'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
  final gst = Map<String, dynamic>.from(inv['gstSummary'] ?? {});
  final payments = (inv['paymentHistory'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
  final due = _n(inv['dueAmount']);
  final advance = _n(inv['advanceAmount']);
  final igst = _s(inv['gstType']) == 'IGST';
  final v2 = _s(inv['discountMode']) == 'before_gst'; // discount taken off before GST

  String detail(Map<String, dynamic> i) {
    final parts = <String>[
      if (_s(i['purity']).isNotEmpty) 'Purity ${_s(i['purity'])}',
      if (_n(i['grossWt']) > 0) 'Gross ${_n(i['grossWt']).toStringAsFixed(3)} g',
      if (_s(i['productCode']).isNotEmpty) 'Code ${_s(i['productCode'])}',
    ];
    final extras = (i['extras'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).map((e) {
      final w = _n(e['weight']);
      final a = _n(e['amount']);
      return '${_s(e['name']).isEmpty ? _s(e['kind']) : _s(e['name'])}${w > 0 ? ' ${w.toStringAsFixed(3)} g' : ''}${a > 0 ? ' $rupee${money.format(a)}' : ''}';
    }).toList();
    // a hallmark fee on a bill made since rule v3 is added after the tax (no GST on it); older bills had it inside the taxable amount
    final hallPassedOn = _n(i['hallmarkCharge']) > 0 && i['hallmarkTaxed'] == false;
    final incl = [if (_n(i['hallmarkCharge']) > 0 && !hallPassedOn) 'Hallmark $rupee${money.format(_n(i['hallmarkCharge']))}', ...extras];
    return [
      if (parts.isNotEmpty) parts.join('  |  '),
      if (incl.isNotEmpty) 'Incl.: ${incl.join(', ')}',
      if (hallPassedOn) 'Hallmark fee $rupee${money.format(_n(i['hallmarkCharge']))} (no GST, added after tax)',
    ].join('\n');
  }

  pw.Widget cell(String t, {bool head = false, pw.TextAlign align = pw.TextAlign.left, bool b = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: pw.Text(t, textAlign: align, style: pw.TextStyle(fontSize: head ? 7.6 : 8, fontWeight: head || b ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );

  pw.Widget kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.2),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 52, child: pw.Text(k, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700))),
          pw.Expanded(child: pw.Text(v, style: pw.TextStyle(fontSize: 8.6, fontWeight: pw.FontWeight.bold))),
        ]),
      );

  pw.Widget box(String title, List<pw.Widget> kids) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey500, width: 0.6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 8.4, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
            pw.Divider(height: 6, thickness: 0.4),
            ...kids,
          ]),
        ),
      );

  final doc = pw.Document(theme: theme, title: 'Invoice ${_s(inv['invoiceNumber'])}');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(24),
    build: (ctx) => [
      pw.Center(child: pw.Text('TAX INVOICE', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold))),
      pw.Center(child: pw.Text('$copyType FOR RECIPIENT', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700))),
      pw.SizedBox(height: 6),
      pw.Center(child: pw.Text(_s(seller['firmName']), style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold))),
      if (_s(seller['address']).isNotEmpty) pw.Center(child: pw.Text(_s(seller['address']), style: const pw.TextStyle(fontSize: 8.5))),
      pw.Center(child: pw.Text([
        if (_s(seller['phone']).isNotEmpty) 'Phone: ${_s(seller['phone'])}',
        if (_s(seller['email']).isNotEmpty) 'Email: ${_s(seller['email'])}',
      ].join('  |  '), style: const pw.TextStyle(fontSize: 8))),
      pw.Center(child: pw.Text('GSTIN: ${_s((inv['seller'] as Map?)?['gstin'] ?? seller['gstin'])}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 8),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        box('Customer Information', [
          kv('Name:', _s(inv['customerName'])),
          if (_s(inv['customerNameBn']).isNotEmpty && _s(inv['customerNameBn']) != _s(inv['customerName'])) kv('', _s(inv['customerNameBn'])),
          kv('Address:', _s(inv['customerAddress'])),
          kv('Mobile:', _s(inv['customerMobile'])),
          if (_s(inv['customerPan']).isNotEmpty) kv('PAN:', _s(inv['customerPan'])),
          if (_s(inv['Customer_ID']).isNotEmpty) kv('Cust. ID:', _s(inv['Customer_ID'])),
        ]),
        pw.SizedBox(width: 6),
        box('Invoice Information', [
          kv('Invoice No:', _s(inv['invoiceNumber'])),
          kv('Date:', d(inv['invoiceDate'])),
          if (_s(inv['deliveryDate']).isNotEmpty) kv('Delivery:', d(inv['deliveryDate'])),
          kv('Rates:', 'Gold $rupee${_n(inv['goldRate']).toStringAsFixed(2)} | Silver $rupee${_n(inv['silverRate']).toStringAsFixed(2)}'),
          kv('Place:', _s(inv['placeOfSupply'])),
          if (_s(inv['reverseCharge']).isNotEmpty) kv('Rev. charge:', _s(inv['reverseCharge'])),
          if (_s(inv['termsOfDelivery']).isNotEmpty) kv('Delivery:', _s(inv['termsOfDelivery'])),
          if (_s(inv['reference']).isNotEmpty) kv('Ref:', _s(inv['reference'])),
        ]),
      ]),
      pw.SizedBox(height: 8),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
        columnWidths: igst
            ? const {
                0: pw.FixedColumnWidth(18), 1: pw.FlexColumnWidth(2.8), 2: pw.FixedColumnWidth(32), 3: pw.FixedColumnWidth(34),
                4: pw.FixedColumnWidth(42), 5: pw.FixedColumnWidth(46), 6: pw.FixedColumnWidth(46), 7: pw.FixedColumnWidth(52),
                8: pw.FixedColumnWidth(50), 9: pw.FixedColumnWidth(56),
              }
            : const {
                0: pw.FixedColumnWidth(18), 1: pw.FlexColumnWidth(2.6), 2: pw.FixedColumnWidth(30), 3: pw.FixedColumnWidth(34),
                4: pw.FixedColumnWidth(40), 5: pw.FixedColumnWidth(44), 6: pw.FixedColumnWidth(44), 7: pw.FixedColumnWidth(48),
                8: pw.FixedColumnWidth(42), 9: pw.FixedColumnWidth(42), 10: pw.FixedColumnWidth(52),
              },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
            children: [
              for (final h in ['Sl', 'Particulars', 'HSN', 'Metal', 'Net Wt (g)', 'Rate', 'Making', 'Taxable', if (igst) 'IGST 3%' else ...['CGST 1.5%', 'SGST 1.5%'], 'Total ($rupee)'])
                cell(h, head: true, align: h == 'Particulars' || h == 'Sl' ? pw.TextAlign.left : pw.TextAlign.right),
            ],
          ),
          for (var i = 0; i < items.length; i++)
            pw.TableRow(children: [
              cell('${i + 1}'),
              cell(_s(items[i]['particular']) + (detail(items[i]).isEmpty ? '' : '\n${detail(items[i])}')),
              cell(_s(items[i]['hsnCode']), align: pw.TextAlign.right),
              cell(_s(items[i]['metalType']), align: pw.TextAlign.right),
              cell(_n(items[i]['netWt']).toStringAsFixed(3), align: pw.TextAlign.right),
              cell(money.format(_n(items[i]['rate'])), align: pw.TextAlign.right),
              cell(money.format(_n(items[i]['makingCharge'])), align: pw.TextAlign.right),
              cell(money.format(_n(items[i]['taxableAmount'])), align: pw.TextAlign.right),
              if (igst)
                cell(money.format(_n(items[i]['igst'])), align: pw.TextAlign.right)
              else ...[
                cell(money.format(_n(items[i]['cgst'])), align: pw.TextAlign.right),
                cell(money.format(_n(items[i]['sgst'])), align: pw.TextAlign.right),
              ],
              cell(money.format(_n(items[i]['total'])), align: pw.TextAlign.right, b: true),
            ]),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          flex: 5,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('GST Summary', style: pw.TextStyle(fontSize: 8.6, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
              children: [
                pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey300), children: [
                  for (final h in ['Description', 'Taxable', if (igst) 'IGST 3%' else ...['CGST 1.5%', 'SGST 1.5%'], 'Total Tax']) cell(h, head: true),
                ]),
                pw.TableRow(children: [
                  cell('Jewelry Items'),
                  cell(m(gst['taxableValue'])),
                  if (igst)
                    cell(m(gst['igst']))
                  else ...[
                    cell(m(gst['cgst'])),
                    cell(m(gst['sgst'])),
                  ],
                  cell(m(gst['totalTax'])),
                ]),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Text('Payment Information', style: pw.TextStyle(fontSize: 8.6, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text('Amount in Words: ${_s(inv['amountInWords'])}', style: const pw.TextStyle(fontSize: 8.2)),
            pw.Text('Payment Mode: ${_s(inv['paymentMode']).replaceAll('_', ' ')}', style: const pw.TextStyle(fontSize: 8.2)),
            if (_s(inv['note']).isNotEmpty) pw.Text('Note: ${_s(inv['note'])}', style: const pw.TextStyle(fontSize: 8.2)),
            if ((inv['oldMetal'] as List? ?? const []).isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text('Old metal adjusted', style: pw.TextStyle(fontSize: 8.2, fontWeight: pw.FontWeight.bold)),
              for (final o in (inv['oldMetal'] as List))
                pw.Text('${_s(o['metal'])} ${_s(o['purity'])}  net ${_n(o['net']).toStringAsFixed(3)} g  fine ${_n(o['fine']).toStringAsFixed(3)} g  @ ${m(o['rate'])}  =  ${m(o['amount'])}', style: const pw.TextStyle(fontSize: 7.8)),
            ],
            if (payments.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text('Payments', style: pw.TextStyle(fontSize: 8.2, fontWeight: pw.FontWeight.bold)),
              for (final p in payments)
                pw.Text('${d(p['date'])}  ${m(p['amount'])}  (${_s(p['mode']).replaceAll('_', ' ')}${_s(p['reference']).isNotEmpty ? ', ref ${_s(p['reference'])}' : ''})', style: const pw.TextStyle(fontSize: 7.8)),
            ],
          ]),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          flex: 3,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey500, width: 0.6)),
            child: pw.Column(children: [
              pw.Text('Amount Summary', style: pw.TextStyle(fontSize: 8.6, fontWeight: pw.FontWeight.bold)),
              pw.Divider(height: 6, thickness: 0.4),
              if (v2) ...[
                _sumRow('Total amount', m(inv['grossTaxable'])),
                if (_n(inv['additionalCharges']) > 0) _sumRow('Extra charges', '+ ${m(inv['additionalCharges'])}'),
                if (_n(inv['discountBeforeGst']) > 0) _sumRow('Discount', '- ${m(inv['discountBeforeGst'])}'),
                _sumRow('Taxable amount', m(gst['taxableValue']), bold: true),
                if (igst) _sumRow('IGST 3%', m(gst['igst'])) else ...[_sumRow('CGST 1.5%', m(gst['cgst'])), _sumRow('SGST 1.5%', m(gst['sgst']))],
                if (_n(inv['hallmarkTotal']) > 0) _sumRow('Hallmark / HUID fee (no GST)', '+ ${m(inv['hallmarkTotal'])}'),
              ] else ...[
                _sumRow('Items total', m(_n(inv['totalAmount']) - _n(inv['additionalCharges']))),
                if (_n(inv['additionalCharges']) > 0) _sumRow('Additional charges', m(inv['additionalCharges'])),
                if (_n(inv['discount']) > 0) _sumRow('Discount', '- ${m(inv['discount'])}'),
              ],
              _sumRow('Round off', (_n(inv['roundOff']) < 0 ? '- ' : '') + m(_n(inv['roundOff']).abs())),
              pw.Divider(height: 6, thickness: 0.4),
              _sumRow('Total payable', m(inv['totalPayableAmount']), bold: true),
              _sumRow('Paid', m(inv['paidAmount'])),
              if (due > 0) _sumRow('Due', m(due), bold: true),
              if (_n((inv['tds'] as Map?)?['amount']) > 0) _sumRow('TDS ${_s((inv['tds'] as Map)['rate'])}% (deducted by buyer)', m((inv['tds'] as Map)['amount'])),
              if (advance > 0) _sumRow('Advance', m(advance), bold: true),
            ]),
          ),
        ),
      ]),
      pw.SizedBox(height: 10),
      pw.Container(
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey500, width: 0.5)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Terms & Conditions', style: pw.TextStyle(fontSize: 8.4, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          for (final t in terms) pw.Text('• $t', style: const pw.TextStyle(fontSize: 7.4)),
          pw.SizedBox(height: 3),
          pw.Text('Declaration: $declaration', style: const pw.TextStyle(fontSize: 7.4)),
        ]),
      ),
      pw.SizedBox(height: 26),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Customer signature', style: const pw.TextStyle(fontSize: 8)),
        pw.Text('For ${_s(seller['firmName'])}\n\nAuthorised signatory', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8)),
      ]),
    ],
  ));
  return doc.save();
}

pw.Widget _sumRow(String k, String v, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.4),
      child: pw.Row(children: [
        pw.Expanded(child: pw.Text(k, style: pw.TextStyle(fontSize: 8.2, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
        pw.Text(v, style: pw.TextStyle(fontSize: 8.4, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ]),
    );
