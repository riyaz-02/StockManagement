import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../services/api_service.dart';
import '../utils/app_toast.dart';
import '../widgets/bill_ui.dart';

const _red = Color(0xFFB91C1C);
final _inr = NumberFormat('#,##,##0.00', 'en_IN');
String _s(dynamic v) => (v ?? '').toString();
double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse(_s(v)) ?? 0;
String _m(dynamic v) => '₹${_inr.format(_n(v))}';

const _reasons = {'sales_return': 'Goods returned', 'price_adjustment': 'Price adjustment / part refund', 'quality_issue': 'Quality / deficiency', 'exchange': 'Exchange', 'other': 'Other'};

/// Return / refund / part refund of a GST invoice as a credit note (CGST Act s.34). Pick the lines (whole, or a smaller
/// amount for a part refund), the reason and how the refund is paid; the server works out the tax and numbers the note.
class CreditNoteScreen extends StatefulWidget {
  const CreditNoteScreen({super.key, required this.invoiceId, required this.invoiceNumber});
  final String invoiceId, invoiceNumber;

  @override
  State<CreditNoteScreen> createState() => _CreditNoteScreenState();
}

class _CreditNoteScreenState extends State<CreditNoteScreen> {
  final _api = ApiService();
  Map<String, dynamic> _state = {};
  final Set<int> _sel = {};
  final Map<int, TextEditingController> _amt = {};
  final _note = TextEditingController();
  final _refund = TextEditingController();
  String _reason = 'sales_return';
  String _mode = 'Cash';
  Map<String, dynamic>? _prev;
  bool _loading = true, _saving = false;
  String? _error;
  final String _rid = 'cn-${Random().nextInt(1 << 30)}-${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    _refund.dispose();
    for (final c in _amt.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await _api.creditNoteState(widget.invoiceId);
      if (!mounted) return;
      setState(() {
        _state = Map<String, dynamic>.from(r['data'] as Map);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<Map<String, dynamic>> get _lines => (_state['lines'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  List<Map<String, dynamic>> _asked() => [
        for (final i in _sel)
          {
            'index': i,
            if ((_amt[i]?.text.trim() ?? '').isNotEmpty) 'taxable': double.tryParse(_amt[i]!.text.trim()),
          }
      ];

  Future<void> _refresh() async {
    if (_sel.isEmpty) {
      setState(() => _prev = null);
      return;
    }
    final r = await _api.creditNotePreview({'invoiceId': widget.invoiceId, 'lines': _asked()});
    if (!mounted) return;
    setState(() {
      _prev = r['success'] == true ? Map<String, dynamic>.from(r['data'] as Map) : {'error': _s(r['message'])};
      if (r['success'] == true) {
        // refund defaults to the whole note
        _refund.text = _n(_prev!['maxRefund'] ?? _prev!['total']).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
      }
    });
  }

  String? get _blocker {
    if (_sel.isEmpty) return 'Choose the item(s) to credit';
    if (_prev == null || _prev!['error'] != null) return _prev == null ? 'Working out the tax…' : _s(_prev!['error']);
    final ref = double.tryParse(_refund.text.trim()) ?? 0;
    if (ref > _n(_prev!['total']) + 0.005) return 'The refund cannot be more than the credit note';
    if (ref > _n(_prev!['maxRefund'] ?? _prev!['total']) + 0.005) return 'The refund cannot be more than what the customer paid';
    return null;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ref = double.tryParse(_refund.text.trim()) ?? 0;
    final r = await _api.creditNoteCreate({
      'requestId': _rid,
      'invoiceId': widget.invoiceId,
      'lines': _asked(),
      'reason': _reason,
      'note': _note.text.trim(),
      'refundAmount': ref,
      if (ref > 0) 'refundMode': _mode,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      final note = Map<String, dynamic>.from((r['data'] as Map)['note'] as Map);
      showAppSnackBar(context, SnackBar(content: Text('Credit note ${note['number']} issued'), backgroundColor: Colors.green));
      await creditNotePdf(note);
      if (mounted) Navigator.pop(context, true);
    } else {
      showAppSnackBar(context, SnackBar(content: Text(_s(r['message']).isEmpty ? 'Could not issue the credit note' : _s(r['message'])), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocker = _blocker;
    final p = _prev;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(title: Text('Return / credit note · ${widget.invoiceNumber}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), backgroundColor: Colors.white, foregroundColor: Colors.black87, elevation: 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.red))))
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
                  BillCard(
                    title: 'What is returned / refunded',
                    icon: Icons.assignment_return_outlined,
                    color: _red,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final l in _lines) _lineTile(l),
                      const Padding(padding: EdgeInsets.only(top: 4), child: Text('Tick a line to return it whole. Change the amount for a part refund or a price adjustment (before GST).', style: TextStyle(fontSize: 11.5, color: Colors.black54))),
                    ]),
                  ),
                  BillCard(
                    title: 'Reason & refund',
                    icon: Icons.payments_outlined,
                    color: _red,
                    child: Column(children: [
                      DropdownButtonFormField<String>(value: _reason, isExpanded: true, style: const TextStyle(fontSize: 13.5, color: Colors.black87), decoration: billDec('Reason', _red), items: [for (final e in _reasons.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => setState(() => _reason = v ?? _reason)),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: TextField(controller: _refund, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))], onChanged: (_) => setState(() {}), style: const TextStyle(fontSize: 13.5), decoration: billDec('Refund paid now ₹', _red))),
                        const SizedBox(width: 8),
                        Expanded(child: DropdownButtonFormField<String>(value: _mode, isExpanded: true, style: const TextStyle(fontSize: 13.5, color: Colors.black87), decoration: billDec('Paid by', _red), items: [for (final m in const ['Cash', 'Card', 'Online', 'Cheque']) DropdownMenuItem(value: m, child: Text(m))], onChanged: (v) => setState(() => _mode = v ?? _mode))),
                      ]),
                      const SizedBox(height: 10),
                      TextField(controller: _note, style: const TextStyle(fontSize: 13.5), decoration: billDec('Note (why, condition of the goods)', _red)),
                    ]),
                  ),
                  if (p != null && p['error'] == null)
                    BillCard(
                      title: 'Credit note',
                      icon: Icons.receipt_long_outlined,
                      color: _red,
                      trailing: p['reducesTax'] == true ? null : const StatusPill('TAX NOT REDUCED', Colors.orange),
                      child: Column(children: [
                        MoneyRow('Taxable value', _m(p['taxable'])),
                        if (_n(p['igst']) > 0) MoneyRow('IGST 3%', _m(p['igst'])) else ...[MoneyRow('CGST 1.5%', _m(p['cgst'])), MoneyRow('SGST 1.5%', _m(p['sgst']))],
                        const Divider(height: 12),
                        MoneyRow('Credit note total', _m(p['total']), big: true),
                        if (p['reducesTax'] != true) Padding(padding: const EdgeInsets.only(top: 6), child: Text('This bill\'s financial year closed for tax reduction on ${_s(p['deadline'])} (CGST Act s.34(2)). The note is valid with the customer, but the tax on it cannot be reduced in the GST return: ask your CA.', style: const TextStyle(fontSize: 11.5, color: Colors.deepOrange))),
                      ]),
                    ),
                  const SizedBox(height: 4),
                  if (blocker != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Center(child: Text(blocker, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w700, fontSize: 12.5)))),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _red, minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: blocker == null && !_saving ? _save : null,
                    child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Issue credit note', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ]),
    );
  }

  Widget _lineTile(Map<String, dynamic> l) {
    final i = (l['index'] as num).toInt();
    final left = _n(l['left']);
    final gone = left <= 0.004;
    final on = _sel.contains(i);
    final ctl = _amt.putIfAbsent(i, () => TextEditingController());
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 6),
      decoration: BoxDecoration(color: on ? _red.withValues(alpha: 0.05) : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: on ? _red : Colors.black12)),
      child: Column(children: [
        CheckboxListTile(
          dense: true,
          enabled: !gone,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: on,
          onChanged: (v) {
            setState(() {
              v == true ? _sel.add(i) : _sel.remove(i);
              if (v != true) ctl.clear();
            });
            _refresh();
          },
          title: Text(_s(l['particulars']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          subtitle: Text(gone ? 'Already credited in full' : 'Taxable ${_m(l['taxable'])}${_n(l['credited']) > 0 ? '  ·  credited ${_m(l['credited'])}' : ''}  ·  left ${_m(left)}', style: TextStyle(fontSize: 11.5, color: gone ? Colors.green : Colors.black54)),
        ),
        if (on)
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 2),
            child: TextField(controller: ctl, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))], onChanged: (_) => _refresh(), style: const TextStyle(fontSize: 13), decoration: billDec('Amount to credit (blank = all left)', _red, prefixText: '₹ ')),
          ),
      ]),
    );
  }
}

/// The printable credit note (Rule 53: supplier, note no. and date, the original invoice, recipient name / address / state,
/// items with HSN, taxable value and tax).
Future<void> creditNotePdf(Map<String, dynamic> n) async {
  pw.Font? base, bold;
  try {
    base = await PdfGoogleFonts.notoSansRegular();
    bold = await PdfGoogleFonts.notoSansBold();
  } catch (_) {}
  final ok = base is pw.TtfFont && bold is pw.TtfFont;
  final rs = ok ? '₹' : 'Rs. ';
  String m(dynamic v) => '$rs${_inr.format(_n(v))}';
  final igst = _s(n['gstType']) == 'IGST';
  final doc = pw.Document(theme: ok ? pw.ThemeData.withFont(base: base, bold: bold) : pw.ThemeData());
  pw.Widget kv(String a, String b) => pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 1.5), child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.SizedBox(width: 110, child: pw.Text(a, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))), pw.Expanded(child: pw.Text(b, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)))]));
  final lines = (n['lines'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(30),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Center(child: pw.Text('CREDIT NOTE', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
      pw.Center(child: pw.Text('(issued under section 34 of the CGST Act, 2017)', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700))),
      pw.SizedBox(height: 10),
      pw.Divider(),
      kv('Credit note no.', _s(n['number'])),
      kv('Date', _s(n['date'])),
      kv('Supplier GSTIN', _s(n['sellerGstin'])),
      kv('Original invoice', '${_s(n['invoiceNumber'])} dated ${_s(n['invoiceDate'])}'),
      pw.Divider(),
      kv('Recipient', _s(n['customerName'])),
      if (_s(n['customerAddress']).isNotEmpty) kv('Address', _s(n['customerAddress'])),
      kv('State', '${_s(n['customerState'])} ${_s(n['customerStateCode'])}'),
      if (_s(n['customerMobile']).isNotEmpty) kv('Mobile', _s(n['customerMobile'])),
      pw.SizedBox(height: 8),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
        columnWidths: {0: const pw.FlexColumnWidth(4), 1: const pw.FlexColumnWidth(1.2), 2: const pw.FlexColumnWidth(1.6), 3: const pw.FlexColumnWidth(1.6), 4: const pw.FlexColumnWidth(1.6)},
        children: [
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [for (final h in ['Description', 'HSN', 'Taxable value', igst ? 'IGST 3%' : 'CGST+SGST 3%', 'Total']) pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(h, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)))]),
          for (final l in lines)
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${_s(l['particulars'])}${_n(l['netWt']) > 0 ? '  (${_n(l['netWt']).toStringAsFixed(3)} g ${_s(l['purity'])})' : ''}${l['fullReturn'] == true ? '  - returned' : '  - part'}', style: const pw.TextStyle(fontSize: 9))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(_s(l['hsn']), style: const pw.TextStyle(fontSize: 9))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(m(l['taxable']), style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(m(_n(l['cgst']) + _n(l['sgst']) + _n(l['igst'])), style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(m(l['total']), style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right)),
            ]),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Align(alignment: pw.Alignment.centerRight, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Text('Taxable value: ${m(n['taxable'])}', style: const pw.TextStyle(fontSize: 10)),
        if (igst) pw.Text('IGST: ${m(n['igst'])}', style: const pw.TextStyle(fontSize: 10)) else ...[pw.Text('CGST: ${m(n['cgst'])}', style: const pw.TextStyle(fontSize: 10)), pw.Text('SGST: ${m(n['sgst'])}', style: const pw.TextStyle(fontSize: 10))],
        pw.SizedBox(height: 3),
        pw.Text('Credit note total: ${m(n['total'])}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      ])),
      pw.SizedBox(height: 8),
      kv('Reason', _reasons[_s(n['reason'])] ?? _s(n['reason'])),
      if (_s(n['note']).isNotEmpty) kv('Note', _s(n['note'])),
      if (_n(n['refundAmount']) > 0) kv('Refund paid', '${m(n['refundAmount'])} by ${_s(n['refundMode'])}'),
      pw.Spacer(),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Recipient signature', style: const pw.TextStyle(fontSize: 9)), pw.Text('Authorised signatory', style: const pw.TextStyle(fontSize: 9))]),
    ]),
  ));
  await Printing.sharePdf(bytes: await doc.save(), filename: 'CreditNote_${_s(n['number'])}.pdf');
}
