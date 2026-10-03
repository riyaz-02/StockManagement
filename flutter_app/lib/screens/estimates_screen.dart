import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';
import '../utils/billing_calc.dart';
import '../widgets/bill_ui.dart';
import '../widgets/customer_field.dart';
import 'create_invoice_screen.dart';
import 'invoice_item_sheet.dart';
import '../widgets/live_refresh.dart';

String _s(dynamic v) => (v ?? '').toString();
double _n(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(_s(v)) ?? 0;
const _c = Color(0xFF7C3AED);
final _inrPdf = NumberFormat('#,##,##0.00', 'en_IN');

/// Price quotations: what a customer is told before buying. Not a tax invoice: nothing is sold or paid. Turn one into a bill later.
class EstimatesScreen extends StatefulWidget {
  const EstimatesScreen({super.key});
  @override
  State<EstimatesScreen> createState() => _EstimatesScreenState();
}

class _EstimatesScreenState extends State<EstimatesScreen> with LiveRefresh<EstimatesScreen> {
  @override
  List<String> get liveModules => ['estimates'];

  @override
  void onLiveChange() => _load();

  final _api = ApiService();
  final _q = TextEditingController();
  String _status = 'open';
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    initLive();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    disposeLive();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.estimates(q: _q.text.trim(), status: _status);
      if (!mounted) return;
      setState(() {
        _rows = (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
            _loading = false;
            _error = e.toString().replaceFirst('Exception: ', '');
          });
    }
  }

  Future<void> _new() async {
    final id = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const EstimateFormScreen()));
    if (id != null && mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => EstimateDetailScreen(id: id)));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(title: const Text('Estimates', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)), backgroundColor: const Color(0xFFF4F5F8), foregroundColor: const Color(0xFF1A1A1A), elevation: 0),
      floatingActionButton: FloatingActionButton.extended(backgroundColor: _c, foregroundColor: Colors.white, onPressed: _new, icon: const Icon(Icons.add), label: const Text('New estimate')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
          child: TextField(controller: _q, onSubmitted: (_) => _load(), decoration: billDec('Search name, mobile or number', _c, suffix: IconButton(icon: const Icon(Icons.search), onPressed: _load))),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final c in const [('open', 'Open'), ('converted', 'Billed'), ('expired', 'Expired'), ('cancelled', 'Cancelled')])
              Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(c.$2), selected: _status == c.$1, selectedColor: _c.withOpacity(0.18), onSelected: (_) {
                setState(() => _status = c.$1);
                _load();
              })),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                        children: _rows.isEmpty
                            ? [const Padding(padding: EdgeInsets.only(top: 90), child: Text('No estimates here.\nTap "New estimate" to quote a price.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)))]
                            : [
                                for (final e in _rows)
                                  Card(
                                    elevation: 0,
                                    margin: const EdgeInsets.only(bottom: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    child: ListTile(
                                      onTap: () async {
                                        await Navigator.push(context, MaterialPageRoute(builder: (_) => EstimateDetailScreen(id: _s(e['id']))));
                                        _load();
                                      },
                                      title: Text(_s(e['customerName']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                      subtitle: Text('${_s(e['number'])}  ·  ${_s(e['date'])}  ·  valid till ${_s(e['validTill'])}', style: const TextStyle(fontSize: 11.5)),
                                      trailing: Text(inr(_n((e['totals'] as Map?)?['payable'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                                    ),
                                  ),
                              ],
                      ),
                    ),
        ),
      ]),
    );
  }
}

/// Quote a price: customer, the items (same sheet as billing), an optional discount, how long it holds.
class EstimateFormScreen extends StatefulWidget {
  const EstimateFormScreen({super.key});
  @override
  State<EstimateFormScreen> createState() => _EstimateFormScreenState();
}

class _EstimateFormScreenState extends State<EstimateFormScreen> {
  final _api = ApiService();
  final _name = TextEditingController(), _mobile = TextEditingController(), _discount = TextEditingController(), _note = TextEditingController();
  final _gold = TextEditingController(), _silver = TextEditingController();
  final List<BillItem> _items = [];
  String _customerId = '';
  int _days = 7;
  Map<String, dynamic> _meta = {};
  bool _busy = false;
  final String _requestId = 'est-${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(9999)}';

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void dispose() {
    for (final c in [_name, _mobile, _discount, _note, _gold, _silver]) {
      c.dispose();
    }
    super.dispose();
  }

  double _d(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;
  List<String> get _hsn {
    final l = ((_meta['hsnCodes'] as List?) ?? const ['7113']).map((h) => (h is Map ? h['code'] : h).toString()).toList();
    return l.isEmpty ? ['7113'] : l;
  }

  Future<void> _loadMeta() async {
    try {
      final d = Map<String, dynamic>.from((await _api.billingMeta())['data'] as Map);
      if (!mounted) return;
      setState(() {
        _meta = d;
        if (_n(d['goldRate']) > 0) _gold.text = _n(d['goldRate']).toString().replaceFirst(RegExp(r'\.0$'), '');
        if (_n(d['silverRate']) > 0) _silver.text = _n(d['silverRate']).toString().replaceFirst(RegExp(r'\.0$'), '');
      });
    } catch (_) {/* rates can be typed */}
  }

  BillTotals get _t => BillingCalc.compute(items: _items, goldRate: _d(_gold), silverRate: _d(_silver), additional: 0, discount: _d(_discount), interstate: false);

  Future<void> _editItem([int? index]) async {
    final r = await showItemSheet(context, item: index != null ? _items[index] : null, goldRate: _d(_gold), silverRate: _d(_silver), interstate: false, hsnCodes: _hsn);
    if (r == null || !mounted) return;
    setState(() => index != null ? _items[index] = r.item : _items.add(r.item));
    if (r.addNext) _editItem();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final res = await _api.estimateCreate({
        'requestId': _requestId, 'customerId': _customerId, 'customerName': _name.text.trim(), 'customerMobile': _mobile.text.trim(),
        'items': _items.map((i) => i.toJson()).toList(), 'goldRate': _d(_gold), 'silverRate': _d(_silver), 'discount': _d(_discount), 'validDays': _days, 'note': _note.text.trim(),
      });
      if (!mounted) return;
      if (res['success'] == true) {
        Navigator.pop(context, _s((res['data'] as Map)['id']));
        return;
      }
      showAppSnackBar(context, SnackBar(content: Text(_s(res['message'])), backgroundColor: Colors.red.shade700));
    } catch (_) {
      if (mounted) showAppSnackBar(context, SnackBar(content: const Text('Connection problem. Tap Save again: no duplicate will be made.'), backgroundColor: Colors.red.shade700));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final ok = _name.text.trim().length >= 2 && _items.isNotEmpty;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(title: const Text('New estimate', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)), backgroundColor: const Color(0xFFF4F5F8), foregroundColor: const Color(0xFF1A1A1A), elevation: 0),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
        BillCard(title: 'Customer', icon: Icons.person_outline, color: _c, child: Column(children: [
          CustomerField(name: _name, mobile: _mobile, initialId: _customerId, label: 'Customer name *', decoration: (l) => billDec(l, _c), onChanged: (id, n, m) => setState(() => _customerId = id)),
          const SizedBox(height: 10),
          TextField(controller: _mobile, keyboardType: TextInputType.phone, decoration: billDec('Mobile', _c)),
        ])),
        BillCard(
          title: 'Items',
          icon: Icons.diamond_outlined,
          color: _c,
          trailing: TextButton.icon(onPressed: () => _editItem(), icon: const Icon(Icons.add, size: 18), label: const Text('Add')),
          child: Column(children: [
            Row(children: [
              Expanded(child: TextField(controller: _gold, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: billDec('Gold ₹/g', _c))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _silver, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: billDec('Silver ₹/g', _c))),
            ]),
            if (_items.isEmpty) const Padding(padding: EdgeInsets.all(14), child: Text('No items yet. Tap Add.', style: TextStyle(color: Colors.black54))),
            for (var i = 0; i < _items.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                onTap: () => _editItem(i),
                title: Text(_items[i].displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                subtitle: Text('${_items[i].netWt} g ${_items[i].purity}', style: const TextStyle(fontSize: 12)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(inr(i < t.lines.length ? t.lines[i].total : 0), style: const TextStyle(fontWeight: FontWeight.w800)), IconButton(icon: Icon(Icons.close, size: 18, color: Colors.red.shade400), onPressed: () => setState(() => _items.removeAt(i)))]),
              ),
          ]),
        ),
        BillCard(title: 'Price', icon: Icons.sell_outlined, color: _c, child: Column(children: [
          Row(children: [
            Expanded(child: TextField(controller: _discount, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: billDec('Discount ₹ (off making)', _c))),
            const SizedBox(width: 8),
            Expanded(child: DropdownButtonFormField<int>(value: _days, isExpanded: true, decoration: billDec('Valid for', _c), items: [for (final d in const [3, 7, 15, 30]) DropdownMenuItem(value: d, child: Text('$d days'))], onChanged: (v) => setState(() => _days = v ?? 7))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: _note, decoration: billDec('Note (optional)', _c)),
          const Divider(height: 22),
          Row(children: [const Expanded(child: Text('Estimated total (with GST)', style: TextStyle(fontWeight: FontWeight.w700))), Text(inr(t.payable), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: _c))]),
        ])),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: _c),
          onPressed: ok && !_busy ? _save : null,
          child: Text(_busy ? 'Saving...' : (ok ? 'Save estimate' : 'Add the customer and an item')),
        ),
      ]),
    );
  }

  double _n(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(_s(v)) ?? 0;
}

class EstimateDetailScreen extends StatefulWidget {
  const EstimateDetailScreen({super.key, required this.id});
  final String id;
  @override
  State<EstimateDetailScreen> createState() => _EstimateDetailScreenState();
}

class _EstimateDetailScreenState extends State<EstimateDetailScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _e;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.estimate(widget.id);
      if (mounted) setState(() => _e = Map<String, dynamic>.from(r['data'] as Map));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _makeInvoice() async {
    final invId = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => CreateInvoiceScreen(estimate: _e)));
    if (invId != null && mounted) Navigator.pop(context);
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Cancel this estimate?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel estimate'))]));
    if (ok != true) return;
    await _api.estimateCancel(widget.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final e = _e;
    final open = e != null && (_s(e['status']) == 'open' || _s(e['status']) == 'expired');
    final t = Map<String, dynamic>.from((e?['totals'] as Map?) ?? {});
    final items = (e?['items'] as List? ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(
        title: Text(e == null ? 'Estimate' : _s(e['number']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        backgroundColor: const Color(0xFFF4F5F8),
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        actions: [if (e != null) IconButton(tooltip: 'Share PDF', icon: const Icon(Icons.share_outlined), onPressed: () => estimatePdf(e))],
      ),
      body: e == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
              BillCard(title: _s(e['customerName']), icon: Icons.person_outline, color: _c, trailing: StatusPill(_s(e['status']).toUpperCase(), _s(e['status']) == 'open' ? const Color(0xFF16A34A) : Colors.grey.shade700), child: Text('${_s(e['customerMobile'])}\nDated ${_s(e['date'])}  ·  valid till ${_s(e['validTill'])}${_s(e['convertedInvoice']).isEmpty ? '' : '\nBilled as ${_s(e['convertedInvoice'])}'}', style: const TextStyle(fontSize: 12.5, color: Colors.black54))),
              BillCard(title: 'Items', icon: Icons.diamond_outlined, color: _c, child: Column(children: [
                for (final l in items)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
                    Expanded(child: Text('${_s(l['particulars'])}  ${_n(l['net_wt']).toStringAsFixed(3)} g ${_s(l['purity'])}', style: const TextStyle(fontSize: 13))),
                    Text(inr(_n(l['total'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ])),
                const Divider(height: 18),
                _kv('Taxable', inr(_n(t['taxable']))),
                _kv('GST 3%', inr(_n(t['gst']))),
                if (_n(t['discount']) > 0) _kv('Discount given', '− ${inr(_n(t['discount']))}'),
                _kv('Estimated total', inr(_n(t['payable'])), bold: true),
              ])),
              const Padding(padding: EdgeInsets.all(6), child: Text('This is a price estimate, not a tax invoice. Nothing is sold or reserved until it is billed.', style: TextStyle(fontSize: 11.5, color: Colors.black45))),
              if (open) ...[
                FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: _c), onPressed: _makeInvoice, icon: const Icon(Icons.receipt_long), label: const Text('Make invoice from this')),
                TextButton(onPressed: _cancel, child: Text('Cancel estimate', style: TextStyle(color: Colors.red.shade700))),
              ],
            ]),
    );
  }

  Widget _kv(String a, String b, {bool bold = false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [Expanded(child: Text(a, style: const TextStyle(fontSize: 13, color: Colors.black54))), Text(b, style: TextStyle(fontSize: bold ? 16 : 13.5, fontWeight: bold ? FontWeight.w900 : FontWeight.w600))]));
}

/// A simple one-page PDF of the estimate to show or send to the customer.
Future<void> estimatePdf(Map<String, dynamic> e) async {
  pw.Font? base, bold;
  try {
    base = await PdfGoogleFonts.notoSansRegular();
    bold = await PdfGoogleFonts.notoSansBold();
  } catch (_) {}
  final ok = base is pw.TtfFont && bold is pw.TtfFont;
  final rs = ok ? '₹' : 'Rs. ';
  String m(dynamic v) => '$rs${_inrPdf.format(_n(v))}';
  final t = Map<String, dynamic>.from((e['totals'] as Map?) ?? {});
  final items = (e['items'] as List? ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
  final doc = pw.Document(theme: ok ? pw.ThemeData.withFont(base: base, bold: bold) : pw.ThemeData());
  pw.Widget cell(String s, {bool right = false, bool head = false}) => pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(s, textAlign: right ? pw.TextAlign.right : pw.TextAlign.left, style: pw.TextStyle(fontSize: 9, fontWeight: head ? pw.FontWeight.bold : pw.FontWeight.normal)));
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(30),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Center(child: pw.Text('ESTIMATE', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
      pw.Center(child: pw.Text('Price quotation: not a tax invoice', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
      pw.SizedBox(height: 10),
      pw.Divider(),
      pw.Text('No. ${_s(e['number'])}    Date ${_s(e['date'])}    Valid till ${_s(e['validTill'])}', style: const pw.TextStyle(fontSize: 10)),
      pw.SizedBox(height: 4),
      pw.Text('For: ${_s(e['customerName'])}${_s(e['customerMobile']).isEmpty ? '' : '   ${_s(e['customerMobile'])}'}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.Text('Rates used: gold ${rs}${_s(e['goldRate'])}/g, silver ${rs}${_s(e['silverRate'])}/g', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      pw.SizedBox(height: 8),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
        columnWidths: {0: const pw.FlexColumnWidth(4), 1: const pw.FlexColumnWidth(1.3), 2: const pw.FlexColumnWidth(1.6), 3: const pw.FlexColumnWidth(1.6)},
        children: [
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [cell('Item', head: true), cell('Weight', right: true, head: true), cell('Amount', right: true, head: true), cell('With GST', right: true, head: true)]),
          for (final l in items) pw.TableRow(children: [cell('${_s(l['particulars'])} ${_s(l['purity'])}'), cell('${_n(l['net_wt']).toStringAsFixed(3)} g', right: true), cell(m(l['taxable_amount']), right: true), cell(m(l['total']), right: true)]),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Align(alignment: pw.Alignment.centerRight, child: pw.SizedBox(width: 230, child: pw.Column(children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('GST 3%', style: const pw.TextStyle(fontSize: 10)), pw.Text(m(t['gst']), style: const pw.TextStyle(fontSize: 10))]),
        if (_n(t['discount']) > 0) pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Discount', style: const pw.TextStyle(fontSize: 10)), pw.Text('- ${m(t['discount'])}', style: const pw.TextStyle(fontSize: 10))]),
        pw.Divider(),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Estimated total', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)), pw.Text(m(t['payable']), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))]),
      ]))),
      if (_s(e['note']).isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 8), child: pw.Text('Note: ${_s(e['note'])}', style: const pw.TextStyle(fontSize: 9))),
      pw.Spacer(),
      pw.Text('The final price depends on the rate and the exact weight on the day of purchase. This estimate holds until ${_s(e['validTill'])}.', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
    ]),
  ));
  await Printing.sharePdf(bytes: await doc.save(), filename: 'Estimate_${_s(e['number'])}.pdf');
}
