import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';
import '../utils/stock_valuation.dart';
import '../widgets/bill_ui.dart';
import '../widgets/customer_field.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

const _amber = Color(0xFFD97706);

/// Old metal / URD received from customers, and raw metal bought. A list with totals and filters, and a one-page form
/// that values the metal with the Stock Setting > Old Metal rules (same engine as the server).
class OldMetalScreen extends StatefulWidget {
  const OldMetalScreen({super.key});

  @override
  State<OldMetalScreen> createState() => _OldMetalScreenState();
}

class _OldMetalScreenState extends State<OldMetalScreen> {
  final _api = ApiService();
  final _inr = NumberFormat('#,##,##0.00', 'en_IN');
  String _kind = ''; // '' | old | raw
  String _state = ''; // '' | available | adjusted | cancelled
  final _searchC = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _totals = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _api.oldMetalList(kind: _kind, q: _searchC.text.trim(), used: _state == 'adjusted' ? 'yes' : (_state == 'available' ? 'no' : ''), status: _state == 'cancelled' ? 'cancelled' : '');
      final d = Map<String, dynamic>.from(r['data'] as Map);
      if (!mounted) return;
      setState(() {
        _rows = (d['rows'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _totals = Map<String, dynamic>.from(d['totals'] as Map);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _add(String kind) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => OldMetalFormScreen(kind: kind)));
    if (ok == true) _load();
  }

  Future<void> _cancel(Map<String, dynamic> r) async {
    final yes = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Cancel this entry?'),
            content: const Text('The weight leaves the stock ledger again.'),
            actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cancel entry'))],
          ),
        ) ??
        false;
    if (!yes) return;
    final res = await _api.oldMetalCancel('${r['_id']}');
    if (!mounted) return;
    if (res['success'] != true) showAppSnackBar(context, SnackBar(content: Text('${res['message'] ?? 'Could not cancel'}'), backgroundColor: Colors.red));
    _load();
  }

  /// Details of one entry, with a printable / shareable receipt for the customer.
  void _detail(Map<String, dynamic> r) {
    String m(dynamic v) => '₹${_inr.format((v as num?) ?? 0)}';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(r['kind'] == 'raw' ? 'Raw metal purchase' : 'Old metal received', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            for (final row in [
              if ('${r['customerName'] ?? ''}'.isNotEmpty) ('Customer', '${r['customerName']}${'${r['customerMobile'] ?? ''}'.isEmpty ? '' : '  ·  ${r['customerMobile']}'}'),
              ('Date', _date(r['date'])),
              ('Metal / purity', '${r['metalType']} ${r['purity']}'),
              ('Gross / less / net', '${r['gross']} / ${r['less']} / ${r['net']} g'),
              ('Deduction', '${r['deduction']} %'),
              ('Fine / final fine', '${r['fine']} / ${r['finalFine']} g'),
              ('Valued on', '${r['basis']} wt ${r['valuationWt']} g @ ₹${r['rate']}'),
              ('Value', m(r['amount'])),
              if ('${r['note'] ?? ''}'.isNotEmpty) ('Note', '${r['note']}'),
              ('Received by', '${r['createdByName'] ?? ''}'),
              if ('${r['usedOnInvoice'] ?? ''}'.isNotEmpty) ('Adjusted on bill', '${r['usedOnInvoice']}'),
            ])
              Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 120, child: Text(row.$1, style: const TextStyle(fontSize: 12, color: Colors.black54))), Expanded(child: Text(row.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)))])),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: () => _receipt(r), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Receipt (PDF)'), style: FilledButton.styleFrom(backgroundColor: _amber, minimumSize: const Size.fromHeight(46))),
          ]),
        ),
      ),
    );
  }

  Future<void> _receipt(Map<String, dynamic> r) async {
    final doc = pw.Document();
    String m(dynamic v) => 'Rs. ${_inr.format((v as num?) ?? 0)}';
    pw.Widget line(String a, String b, {bool bold = false}) => pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Row(children: [pw.SizedBox(width: 130, child: pw.Text(a, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700))), pw.Expanded(child: pw.Text(b, style: pw.TextStyle(fontSize: bold ? 14 : 11.5, fontWeight: pw.FontWeight.bold)))]));
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Center(child: pw.Text(r['kind'] == 'raw' ? 'RAW METAL PURCHASE' : 'OLD METAL RECEIPT', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
        pw.Divider(),
        if ('${r['customerName'] ?? ''}'.isNotEmpty) line('Customer', '${r['customerName']}  ${r['customerMobile'] ?? ''}'),
        line('Date', _date(r['date'])),
        line('Metal / purity', '${r['metalType']} ${r['purity']}'),
        line('Gross weight', '${r['gross']} g'),
        line('Less', '${r['less']} g'),
        line('Net weight', '${r['net']} g'),
        line('Deduction', '${r['deduction']} %'),
        line('Fine weight', '${r['fine']} g'),
        line('Rate', 'Rs. ${r['rate']} / g'),
        pw.Divider(),
        line('Value', m(r['amount']), bold: true),
        if ('${r['note'] ?? ''}'.isNotEmpty) line('Note', '${r['note']}'),
        pw.Spacer(),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Customer signature', style: const pw.TextStyle(fontSize: 10)), pw.Text('Authorised signature', style: const pw.TextStyle(fontSize: 10))]),
      ]),
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'OldMetal_${'${r['_id']}'.substring(18)}.pdf');
  }

  String _date(dynamic v) {
    final d = DateTime.tryParse('$v')?.toLocal();
    return d == null ? '' : DateFormat('dd MMM yyyy').format(d);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = context.watch<AuthProvider>().can('oldMetal.create');
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(title: const Text('Old Metal', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)), backgroundColor: Colors.white, foregroundColor: Colors.black87, elevation: 0),
      floatingActionButton: canCreate
          ? PopupMenuButton<String>(
              onSelected: _add,
              itemBuilder: (_) => const [PopupMenuItem(value: 'old', child: Text('Receive old metal (URD)')), PopupMenuItem(value: 'raw', child: Text('Buy raw metal'))],
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), decoration: BoxDecoration(color: _amber, borderRadius: BorderRadius.circular(30), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))]), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add, color: Colors.white), SizedBox(width: 6), Text('New entry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))])),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
          children: [
            Row(children: [
              for (final k in const [('', 'All'), ('old', 'Old metal'), ('raw', 'Raw metal')])
                Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(k.$2, style: TextStyle(fontSize: 12.5, fontWeight: _kind == k.$1 ? FontWeight.w800 : FontWeight.w500)), selected: _kind == k.$1, selectedColor: _amber.withValues(alpha: 0.18), onSelected: (_) {
                      setState(() => _kind = k.$1);
                      _load();
                    })),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _searchC,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), _load);
              },
              style: const TextStyle(fontSize: 13.5),
              decoration: billDec('Search name, mobile or note', _amber, suffix: const Icon(Icons.search, size: 20)),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final k in const [('', 'Any status'), ('available', 'Not adjusted'), ('adjusted', 'Adjusted on a bill'), ('cancelled', 'Cancelled')])
                  Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(visualDensity: VisualDensity.compact, label: Text(k.$2, style: TextStyle(fontSize: 12, fontWeight: _state == k.$1 ? FontWeight.w800 : FontWeight.w500)), selected: _state == k.$1, selectedColor: _amber.withValues(alpha: 0.18), onSelected: (_) {
                        setState(() => _state = k.$1);
                        _load();
                      })),
              ]),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _amber.withValues(alpha: 0.3))),
              child: Row(children: [
                _kpi('Entries', '${_totals['count'] ?? 0}'),
                _kpi('Net wt', '${_totals['net'] ?? 0} g'),
                _kpi('Fine wt', '${_totals['fine'] ?? 0} g'),
                _kpi('Value', '₹${_inr.format((_totals['amount'] as num?) ?? 0)}'),
              ]),
            ),
            const SizedBox(height: 8),
            if (_loading) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
            if (_error != null) Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style: const TextStyle(color: Colors.red))),
            if (!_loading && _error == null && _rows.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('No old metal entries yet', style: TextStyle(color: Colors.black45)))),
            for (final r in _rows) _card(r, canCreate),
          ],
        ),
      ),
    );
  }

  Widget _kpi(String l, String v) => Expanded(child: Column(children: [Text(l, style: const TextStyle(fontSize: 10.5, color: Colors.black45)), const SizedBox(height: 2), Text(v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800), textAlign: TextAlign.center)]));

  Widget _card(Map<String, dynamic> r, bool canCancel) {
    final cancelled = r['status'] == 'cancelled';
    final raw = r['kind'] == 'raw';
    final used = '${r['usedOnInvoice'] ?? ''}'.isNotEmpty;
    return Opacity(
      opacity: cancelled ? 0.5 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _detail(r),
        child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            StatusPill(raw ? 'RAW' : 'OLD', raw ? Colors.blueGrey : _amber),
            const SizedBox(width: 8),
            Expanded(child: Text(raw ? 'Raw ${r['metalType']}' : '${r['customerName']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
            Text(_date(r['date']), style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
          ]),
          const SizedBox(height: 6),
          Text('${r['metalType']} ${r['purity']}  ·  net ${r['net']} g  ·  fine ${r['fine']} g  ·  @ ₹${r['rate']}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
          if ('${r['note'] ?? ''}'.isNotEmpty) Text('${r['note']}', style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
          const SizedBox(height: 6),
          Row(children: [
            Text('₹${_inr.format((r['amount'] as num?) ?? 0)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _amber)),
            const Spacer(),
            if (cancelled) const StatusPill('CANCELLED', Colors.red),
            if (!cancelled && used) StatusPill('ADJUSTED · ${r['usedOnInvoice']}'.replaceFirst('req:', ''), Colors.green),
            if (!cancelled && !used && !raw) const StatusPill('NOT ADJUSTED', _amber),
            if (!cancelled && canCancel && !used) TextButton(onPressed: () => _cancel(r), child: const Text('Cancel', style: TextStyle(color: Colors.red))),
          ]),
        ]),
      ),
      ),
    );
  }
}

/// One page: who / what / weights / rate, with a live valuation card.
class OldMetalFormScreen extends StatefulWidget {
  const OldMetalFormScreen({super.key, required this.kind, this.presetName = '', this.presetMobile = '', this.presetCustomerId = '', this.returnEntry = false});
  final String kind; // old | raw
  final String presetName, presetMobile, presetCustomerId;
  final bool returnEntry; // pop with the saved entry (used from the bill)

  @override
  State<OldMetalFormScreen> createState() => _OldMetalFormScreenState();
}

class _OldMetalFormScreenState extends State<OldMetalFormScreen> {
  final _api = ApiService();
  final _name = TextEditingController(), _mobile = TextEditingController(), _gross = TextEditingController(), _less = TextEditingController(), _net = TextEditingController();
  final _deduction = TextEditingController(), _rate = TextEditingController(), _note = TextEditingController();
  String _metal = 'gold', _purity = '22K';
  String _customerId = '';
  Map<String, dynamic> _rules = {};
  double _gold = 0, _silver = 0;
  bool _saving = false;

  bool get _raw => widget.kind == 'raw';
  static const _purities = {'gold': ['24K', '22K', '18K', '14K', '9K'], 'silver': ['999', '925', '800'], 'platinum': ['950'], 'other': ['100']};

  @override
  void initState() {
    super.initState();
    _name.text = widget.presetName;
    _mobile.text = widget.presetMobile;
    _customerId = widget.presetCustomerId;
    _init();
  }

  Future<void> _init() async {
    try {
      _rules = Map<String, dynamic>.from(((await _api.stockSettings())['data'] as Map)['settings'] as Map);
    } catch (_) {}
    try {
      final m = Map<String, dynamic>.from(((await _api.billingMeta())['data'] ?? {}) as Map);
      _gold = (m['goldRate'] as num?)?.toDouble() ?? 0;
      _silver = (m['silverRate'] as num?)?.toDouble() ?? 0;
    } catch (_) {}
    if (mounted) setState(_suggestRate);
  }

  void _suggestRate() {
    final r = _metal == 'gold' ? _gold : (_metal == 'silver' ? _silver : 0.0);
    if (r > 0) _rate.text = r.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  @override
  void dispose() {
    for (final c in [_name, _mobile, _gross, _less, _net, _deduction, _rate, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _input => {'kind': widget.kind, 'gross': _gross.text, 'less': _less.text, 'net': _net.text.trim(), 'purity': _purity, 'deduction': _deduction.text, 'rate': _rate.text};
  Map<String, dynamic> get _val => computeOldMetal(_input, _rules);

  void _grossLess() {
    final g = double.tryParse(_gross.text) ?? 0, l = double.tryParse(_less.text) ?? 0;
    if (g > 0) {
      final n = g - l;
      _net.text = n > 0 ? n.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '') : '';
    }
    setState(() {});
  }

  String? get _blocker {
    if (!_raw && _name.text.trim().length < 2) return 'Enter the customer name';
    if ((double.tryParse(_net.text) ?? 0) <= 0) return 'Enter the weight';
    if ((double.tryParse(_rate.text) ?? 0) <= 0) return 'Enter the rate';
    return null;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await _api.oldMetalCreate({'kind': widget.kind, 'metalType': _metal, 'customerId': _customerId, 'customerName': _name.text, 'customerMobile': _mobile.text, 'gross': _gross.text, 'less': _less.text, 'net': _net.text, 'purity': _purity, 'deduction': _deduction.text, 'rate': _rate.text, 'note': _note.text});
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      showAppSnackBar(context, const SnackBar(content: Text('Saved'), backgroundColor: Colors.green));
      Navigator.pop<Object?>(context, widget.returnEntry ? Map<String, dynamic>.from((r['data'] as Map)['entry'] as Map) : true);
    } else {
      showAppSnackBar(context, SnackBar(content: Text('${r['message'] ?? 'Could not save'}'), backgroundColor: Colors.red));
    }
  }

  Widget _tf(TextEditingController c, String label, {bool num = false, bool digits = false, ValueChanged<String>? onChanged, int lines = 1}) => TextFormField(
        controller: c,
        maxLines: lines,
        keyboardType: num ? const TextInputType.numberWithOptions(decimal: true) : (digits ? TextInputType.phone : TextInputType.text),
        inputFormatters: [if (num) FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')), if (digits) FilteringTextInputFormatter.digitsOnly, if (digits) LengthLimitingTextInputFormatter(10)],
        onChanged: onChanged ?? (_) => setState(() {}),
        style: const TextStyle(fontSize: 13.5),
        decoration: billDec(label, _amber),
      );

  Widget _two(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 8), Expanded(child: b)]);

  @override
  Widget build(BuildContext context) {
    final v = _val;
    final purities = _purities[_metal]!;
    if (!purities.contains(_purity)) _purity = purities.first;
    final blocker = _blocker;
    const bn = {'finalFine': 'final fine wt', 'fine': 'fine wt', 'net': 'net wt', 'gross': 'gross wt'};
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(title: Text(_raw ? 'Buy raw metal' : 'Receive old metal', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)), backgroundColor: Colors.white, foregroundColor: Colors.black87, elevation: 0),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
        if (!_raw) BillCard(title: 'Customer', icon: Icons.person_outline, color: _amber, child: Column(children: [
          CustomerField(name: _name, mobile: _mobile, initialId: _customerId, label: 'Customer name *', decoration: (l) => billDec(l, _amber), onChanged: (id, n, m) => setState(() => _customerId = id)),
          const SizedBox(height: 10),
          _tf(_mobile, 'Mobile', digits: true),
        ])),
        BillCard(
          title: 'Metal & weight',
          icon: Icons.scale_outlined,
          color: _amber,
          child: Column(children: [
            _two(
              DropdownButtonFormField<String>(value: _metal, isExpanded: true, style: const TextStyle(fontSize: 13.5, color: Colors.black87), decoration: billDec('Metal', _amber), items: [for (final m in _purities.keys) DropdownMenuItem(value: m, child: Text(m[0].toUpperCase() + m.substring(1)))], onChanged: (x) => setState(() {
                    _metal = x ?? _metal;
                    _rate.clear();
                    _purity = _purities[_metal]!.first;
                    _suggestRate();
                  })),
              DropdownButtonFormField<String>(value: _purity, isExpanded: true, style: const TextStyle(fontSize: 13.5, color: Colors.black87), decoration: billDec('Purity', _amber), items: [for (final p in purities) DropdownMenuItem(value: p, child: Text(p))], onChanged: (x) => setState(() => _purity = x ?? _purity)),
            ),
            const SizedBox(height: 10),
            _two(_tf(_gross, 'Gross wt (g)', num: true, onChanged: (_) => _grossLess()), _tf(_less, 'Less (g)', num: true, onChanged: (_) => _grossLess())),
            const SizedBox(height: 10),
            _two(_tf(_net, 'Net wt (g) *', num: true), _tf(_deduction, 'Deduction % (loss)', num: true)),
            const SizedBox(height: 10),
            _two(_tf(_rate, 'Rate ₹ / g *', num: true), const SizedBox.shrink()),
          ]),
        ),
        BillCard(
          title: 'Valuation',
          icon: Icons.calculate_outlined,
          color: _amber,
          child: Column(children: [
            for (final r in [
              ('Purity', '${(v['purityPct'] as num).toStringAsFixed(2)} %'),
              ('Fine wt', '${(v['fine'] as num).toStringAsFixed(3)} g'),
              ('Final fine wt (after deduction)', '${(v['finalFine'] as num).toStringAsFixed(3)} g'),
              ('Valued on ${bn[v['basis']]}', '${(v['valuationWt'] as num).toStringAsFixed(3)} g'),
            ])
              Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [Expanded(child: Text(r.$1, style: const TextStyle(fontSize: 12, color: Colors.black54))), Text(r.$2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))])),
            const Divider(height: 14),
            Row(children: [Expanded(child: Text(_raw ? 'Amount payable' : 'Value of old metal', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _amber))), Text('₹${(v['amount'] as num).toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _amber))]),
          ]),
        ),
        BillCard(title: 'Note', icon: Icons.notes_rounded, color: _amber, child: _tf(_note, 'Note (optional)', lines: 2)),
        if (blocker != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Center(child: Text(blocker, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w700, fontSize: 12.5)))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: blocker == null && !_saving ? _save : null,
          child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
      ]),
    );
  }
}
