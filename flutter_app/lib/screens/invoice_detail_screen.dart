import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';
import '../utils/bilingual.dart';
import '../utils/invoice_pdf.dart';
import '../widgets/bill_ui.dart';
import 'credit_note_screen.dart';

String _s(dynamic v) => (v ?? '').toString();
double _n(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(_s(v)) ?? 0;

String _newRequestId() {
  final r = Random.secure();
  return 'pay-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-'
      '${List.generate(10, (_) => r.nextInt(36).toRadixString(36)).join()}';
}

/// One invoice: totals, items, payments received, and the actions on it
/// (receive a payment, share / print the PDF).
class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId, this.justCreated = false, this.initialAction});
  final String invoiceId;
  final bool justCreated;

  /// Runs once the invoice has loaded: 'share', 'print', 'pay' or 'return' (from the long-press menu).
  final String? initialAction;

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _inv;
  Map<String, dynamic> _seller = {};
  List<String> _terms = [];
  String _declaration = '';
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _actionDone = false;

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (!mounted || _actionDone || _inv == null) return;
      _actionDone = true;
      switch (widget.initialAction) {
        case 'share':
          _pdf(print: false);
        case 'print':
          _pdf(print: true);
        case 'pay':
          _receivePayment();
        case 'return':
          _openCreditNote();
      }
    });
  }

  Future<void> _openCreditNote() async {
    final done = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => CreditNoteScreen(invoiceId: widget.invoiceId, invoiceNumber: _s(_inv!['invoiceNumber']))));
    if (done == true) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.billingInvoice(widget.invoiceId);
      if (!mounted) return;
      setState(() {
        _inv = Map<String, dynamic>.from(res['data']);
        _seller = Map<String, dynamic>.from(res['seller'] ?? {});
        _terms = List<String>.from((res['terms'] as List? ?? []).map(_s));
        _declaration = _s(res['declaration']);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
            _loading = false;
            _error = e.toString().replaceFirst('Exception: ', '');
          });
    }
  }

  void _toast(String m, {bool error = true}) => showAppSnackBar(
      context, SnackBar(content: Text(m, style: const TextStyle(fontSize: 13)), backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700));

  Future<void> _pdf({required bool print}) async {
    if (_inv == null || _busy) return;
    setState(() => _busy = true);
    try {
      // Counted on the server (same counter as the website): first print = ORIGINAL, later ones = DUPLICATE.
      var copy = 'DUPLICATE';
      try {
        final r = await _api.billingPrint(_s(_inv!['_id']));
        copy = _s((r['data'] as Map?)?['printType']).isEmpty ? 'DUPLICATE' : _s((r['data'] as Map)['printType']);
        if (mounted) setState(() => _inv!['printStatus'] = (r['data'] as Map?)?['printStatus'] ?? _inv!['printStatus']);
      } catch (_) {/* could not count the print: mark it as a duplicate to be safe */}
      final bytes = await buildInvoicePdf(inv: _inv!, seller: _seller, terms: _terms, declaration: _declaration, copyType: copy);
      final name = 'Invoice_${_s(_inv!['invoiceNumber'])}.pdf';
      if (print) {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: name);
      }
    } catch (e) {
      if (mounted) _toast('Could not create the PDF: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _receivePayment() async {
    final inv = _inv!;
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _PaymentSheet(invoice: inv),
    );
    if (done == true) {
      _toast('Payment recorded', error: false);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>().currentLanguage;
    final canPay = context.watch<AuthProvider>().can('billing.receivePayment');
    final inv = _inv;
    final due = _n(inv?['dueAmount']);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        toolbarHeight: 46,
        backgroundColor: const Color(0xFFF4F5F8),
        foregroundColor: const Color(0xFF1A1A1A),
        title: Text(inv == null ? 'Invoice' : 'Invoice ${_s(inv['invoiceNumber'])}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          if (inv != null) ...[
            IconButton(tooltip: 'Share PDF', icon: const Icon(Icons.share_outlined, size: 20), onPressed: _busy ? null : () => _pdf(print: false)),
            IconButton(tooltip: 'Print', icon: const Icon(Icons.print_outlined, size: 20), onPressed: _busy ? null : () => _pdf(print: true)),
            if (context.read<AuthProvider>().can('billing.creditNote') && _s(inv['status']) != 'cancelled')
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) async {
                  if (v == 'return') {
                    final done = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => CreditNoteScreen(invoiceId: widget.invoiceId, invoiceNumber: _s(inv['invoiceNumber']))));
                    if (done == true) _load();
                  }
                },
                itemBuilder: (_) => const [PopupMenuItem(value: 'return', child: Text('Return / refund (credit note)'))],
              ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, style: const TextStyle(color: Colors.red)), TextButton(onPressed: _load, child: const Text('Retry'))])))
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: RefreshIndicator(onRefresh: _load, child: _body(inv!, lang)),
                  ),
                ),
      bottomNavigationBar: (inv != null && due > 0 && canPay)
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.black12))),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: const Color(0xFF16A34A)),
                  onPressed: _receivePayment,
                  icon: const Icon(Icons.payments_outlined, size: 20),
                  label: Text('Receive payment · ${inr(due)} due', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            )
          : null,
    );
  }

  Widget _body(Map<String, dynamic> inv, String lang) {
    final items = (inv['items'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
    final pays = (inv['paymentHistory'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList().reversed.toList();
    final gst = Map<String, dynamic>.from(inv['gstSummary'] ?? {});
    final due = _n(inv['dueAmount']);
    final adv = _n(inv['advanceAmount']);
    final date = DateTime.tryParse(_s(inv['createdAt']).isNotEmpty ? _s(inv['createdAt']) : _s(inv['invoiceDate']))?.toLocal();
    final name = bilingualName(_s(inv['customerName']), _s(inv['customerNameBn']), lang);
    final status = _s(inv['status']);
    final statusColor = due > 0 ? Colors.red.shade700 : const Color(0xFF16A34A);
    final tds = Map<String, dynamic>.from(inv['tds'] is Map ? inv['tds'] : {});
    final igst = _s(inv['gstType']) == 'IGST';
    final v2 = _s(inv['discountMode']) == 'before_gst'; // discount taken off before GST

    return ListView(padding: const EdgeInsets.fromLTRB(10, 6, 10, 24), children: [
      if (widget.justCreated)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFF16A34A).withOpacity(0.10), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF16A34A).withOpacity(0.5))),
          child: Row(children: const [
            Icon(Icons.check_circle, color: Color(0xFF16A34A)),
            SizedBox(width: 8),
            Expanded(child: Text('Invoice saved. Use Share or Print above.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          ]),
        ),
      BillCard(
        title: 'Customer',
        icon: Icons.person_outline,
        color: const Color(0xFF2563EB),
        trailing: StatusPill(status == 'cancelled' ? 'Cancelled' : (due > 0 ? 'Due ${inr(due)}' : (adv > 0 ? 'Advance ${inr(adv)}' : 'Paid')), status == 'cancelled' ? Colors.grey.shade700 : statusColor),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            if (inv['walkIn'] == true) StatusPill('Walk-in', Colors.orange.shade800),
          ]),
          if (_s(inv['Customer_ID']).isNotEmpty) Text(_s(inv['Customer_ID']), style: const TextStyle(fontSize: 12, color: Colors.black54)),
          if (_s(inv['customerMobile']).isNotEmpty) Text(_s(inv['customerMobile']), style: const TextStyle(fontSize: 12.5)),
          if (_s(inv['customerPan']).isNotEmpty) Text('PAN ${_s(inv['customerPan'])}', style: const TextStyle(fontSize: 12.5)),
          if (_s(inv['placeOfSupply']).isNotEmpty) Text('Supply: ${_s(inv['placeOfSupply']).replaceFirst(RegExp(r'^\d+-'), '')} · ${igst ? 'IGST' : 'CGST+SGST'}', style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
          if (_s(inv['customerAddress']).isNotEmpty) Text(_s(inv['customerAddress']), style: const TextStyle(fontSize: 12.5, color: Colors.black87)),
          const SizedBox(height: 6),
          Text('${date == null ? '' : DateFormat('dd MMM yyyy, hh:mm a').format(date)}  ·  ${_s(inv['branchName'])}  ·  by ${_s(inv['createdBy'])}', style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
        ]),
      ),
      BillCard(
        title: 'Items',
        icon: Icons.diamond_outlined,
        color: const Color(0xFFD97706),
        child: Column(children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i + 1}. ', style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_s(items[i]['particular']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text('${_s(items[i]['metalType'])}${_s(items[i]['hsnCode']).isEmpty ? '' : ' · HSN ${_s(items[i]['hsnCode'])}'} · ${grams(_n(items[i]['netWt']))} g × ${inr(_n(items[i]['rate']))}${_n(items[i]['makingCharge']) > 0 ? ' + making ${inr(_n(items[i]['makingCharge']))}' : ''}', style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                    if (_s(items[i]['purity']).isNotEmpty || _n(items[i]['grossWt']) > 0 || _s(items[i]['productCode']).isNotEmpty)
                      Text([
                        if (_s(items[i]['purity']).isNotEmpty) _s(items[i]['purity']),
                        if (_n(items[i]['grossWt']) > 0) 'gross ${grams(_n(items[i]['grossWt']))} g',
                        if (_s(items[i]['productCode']).isNotEmpty) 'code ${_s(items[i]['productCode'])}',
                      ].join(' · '), style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                    if (_n(items[i]['hallmarkCharge']) > 0)
                      Text('✓ Hallmark · ${inr(_n(items[i]['hallmarkCharge']))}', style: const TextStyle(fontSize: 11.5, color: Color(0xFF0F766E))),
                    for (final e in (items[i]['extras'] as List? ?? []))
                      Text('◆ ${_s(e['name']).isEmpty ? _s(e['kind']) : _s(e['name'])}${_n(e['weight']) > 0 ? ' ${grams(_n(e['weight']))} g' : ''}${_n(e['amount']) > 0 ? ' · ${inr(_n(e['amount']))}' : ''}', style: const TextStyle(fontSize: 11.5, color: Color(0xFF7C3AED))),
                    Text(igst ? 'Taxable ${inr(_n(items[i]['taxableAmount']))} · IGST ${inr(_n(items[i]['igst']))}' : 'Taxable ${inr(_n(items[i]['taxableAmount']))} · CGST ${inr(_n(items[i]['cgst']))} · SGST ${inr(_n(items[i]['sgst']))}', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                  ]),
                ),
                Text(inr(_n(items[i]['total'])), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
      ),
      BillCard(
        title: 'Amount',
        icon: Icons.receipt_long_outlined,
        color: const Color(0xFF4F46E5),
        child: Column(children: [
          if (v2) MoneyRow('Total amount', inr(_n(inv['grossTaxable']))),
          if (v2 && _n(inv['additionalCharges']) > 0) MoneyRow('Extra charges', '+ ${inr(_n(inv['additionalCharges']))}'),
          if (v2 && _n(inv['discountBeforeGst']) > 0) MoneyRow('Discount', '− ${inr(_n(inv['discountBeforeGst']))}', color: Colors.red.shade700),
          MoneyRow(v2 ? 'Taxable amount' : 'Taxable value', inr(_n(gst['taxableValue']))),
          if (igst)
            MoneyRow('IGST 3%', inr(_n(gst['igst'])))
          else ...[
            MoneyRow('CGST 1.5%', inr(_n(gst['cgst']))),
            MoneyRow('SGST 1.5%', inr(_n(gst['sgst']))),
          ],
          if (!v2 && _n(inv['additionalCharges']) > 0) MoneyRow('Additional charges', '+ ${inr(_n(inv['additionalCharges']))}'),
          if (_n(inv['discount']) > 0) MoneyRow('Discount', '− ${inr(_n(inv['discount']))}', color: Colors.red.shade700),
          MoneyRow('Round off', (_n(inv['roundOff']) >= 0 ? '' : '−') + inr(_n(inv['roundOff']).abs())),
          const Divider(height: 12),
          MoneyRow('Total payable', inr(_n(inv['totalPayableAmount'])), big: true),
          if (_n(tds['amount']) > 0) MoneyRow('TDS ${_s(tds['rate'])}% (deducted by buyer)', inr(_n(tds['amount'])), color: Colors.orange.shade800),
          const SizedBox(height: 4),
          MoneyRow('Paid', inr(_n(inv['paidAmount'])), color: const Color(0xFF16A34A)),
          if (due > 0) MoneyRow('Due', inr(due), bold: true, color: Colors.red.shade700),
          if (adv > 0) MoneyRow('Advance', inr(adv), bold: true, color: const Color(0xFF16A34A)),
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerLeft, child: Text(_s(inv['amountInWords']), style: const TextStyle(fontSize: 11.5, color: Colors.black54))),
        ]),
      ),
      if ((inv['oldMetal'] as List? ?? const []).isNotEmpty)
        BillCard(
          title: 'Old metal adjusted',
          icon: Icons.recycling_rounded,
          color: const Color(0xFFD97706),
          trailing: StatusPill('− ${inr(_n(inv['oldMetalAmount']))}', const Color(0xFFD97706)),
          child: Column(children: [
            for (final o in (inv['oldMetal'] as List))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text('${_s(o['metal'])} ${_s(o['purity'])}  ·  net ${grams(_n(o['net']))} g  ·  fine ${grams(_n(o['fine']))} g  ·  @ ${inr(_n(o['rate']))}', style: const TextStyle(fontSize: 12.5))),
                  Text(inr(_n(o['amount'])), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                ]),
              ),
          ]),
        ),
      FutureBuilder<Map<String, dynamic>>(
        future: _api.creditNoteState(widget.invoiceId),
        builder: (context, snap) {
          final notes = (snap.data?['data'] is Map ? (snap.data!['data'] as Map)['notes'] : null) as List? ?? const [];
          if (notes.isEmpty) return const SizedBox.shrink();
          return BillCard(
            title: 'Credit notes (returns / refunds)',
            icon: Icons.assignment_return_outlined,
            color: const Color(0xFFB91C1C),
            child: Column(children: [
              for (final n in notes)
                InkWell(
                  onTap: () => creditNotePdf(Map<String, dynamic>.from(n as Map)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Expanded(child: Text('${_s(n['number'])}  ·  ${_s(n['date'])}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
                      Text('− ${inr(_n(n['total']))}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.red.shade700)),
                      const SizedBox(width: 6),
                      const Icon(Icons.picture_as_pdf_outlined, size: 16, color: Colors.black38),
                    ]),
                  ),
                ),
            ]),
          );
        },
      ),
      BillCard(
        title: 'Payments',
        icon: Icons.payments_outlined,
        color: const Color(0xFF16A34A),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (pays.isEmpty) const Text('No payment recorded yet.', style: TextStyle(fontSize: 12.5, color: Colors.black54)),
          for (final p in pays) _paymentRow(p),
        ]),
      ),
      if (inv['reconcile'] == true)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange)),
          child: const Text('The customer balance for this invoice needs a manual check.', style: TextStyle(fontSize: 12.5)),
        ),
    ]);
  }

  Widget _paymentRow(Map<String, dynamic> p) {
    final amt = _n(p['amount']);
    final dt = DateTime.tryParse(_s(p['date']))?.toLocal();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        const Icon(Icons.subdirectory_arrow_right, size: 16, color: Colors.black38),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_s(p['description']).startsWith('Initial') || _s(p['description']).startsWith('Payment at the time') ? 'At billing' : 'Received'} · ${_s(p['mode']).replaceAll('_', ' ')}${_s(p['reference']).isNotEmpty && !_s(p['reference']).startsWith('Initial payment') ? ' · ref ${_s(p['reference'])}' : ''}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            Text('${dt == null ? '' : DateFormat('dd MMM yyyy, hh:mm a').format(dt)}${_s(p['receivedBy']).isEmpty ? '' : ' · ${_s(p['receivedBy'])}'}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ]),
        ),
        Text(inr(amt), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
      ]),
    );
  }
}

/// Bottom sheet: collect a payment against an invoice.
class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.invoice});
  final Map<String, dynamic> invoice;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _api = ApiService();
  final _requestId = _newRequestId(); // one key per opened sheet: a retry never double-collects
  late final TextEditingController _amount;
  final _ref = TextEditingController();
  final _note = TextEditingController();
  String _mode = 'Cash';
  bool _saving = false;
  String? _error;

  double get _due => _n(widget.invoice['dueAmount']);

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: _due.toStringAsFixed(_due == _due.roundToDouble() ? 0 : 2));
  }

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amt = double.tryParse(_amount.text.trim()) ?? 0;
    if (amt <= 0) return setState(() => _error = 'Enter an amount more than 0');
    if (amt > _due + 0.001) return setState(() => _error = 'Only ${inr(_due)} is due');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await _api.billingPay(_s(widget.invoice['_id']), {
        'requestId': _requestId,
        'amount': amt,
        'mode': _mode,
        'reference': _ref.text.trim(),
        'description': _note.text.trim(),
      });
      if (!mounted) return;
      if (res['success'] == true) {
        Navigator.pop(context, true);
      } else {
        setState(() => _error = _s(res['message']).isEmpty ? 'Could not record the payment' : _s(res['message']));
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Connection problem. Tap again: the payment will not be recorded twice.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const c = Color(0xFF16A34A);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Receive payment · Invoice ${_s(widget.invoice['invoiceNumber'])}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          Text('${inr(_due)} due', style: TextStyle(fontSize: 13, color: Colors.red.shade700, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), decoration: billDec('Amount', c, prefixText: '₹ ')),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final m in const ['Cash', 'Card', 'Online', 'Cheque'])
              ChoiceChip(
                label: Text(m, style: const TextStyle(fontSize: 12)),
                selected: _mode == m,
                selectedColor: c.withOpacity(0.18),
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _mode = m),
              ),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _ref, style: const TextStyle(fontSize: 13.5), decoration: billDec('Reference / UTR / cheque no. (optional)', c)),
          const SizedBox(height: 8),
          TextField(controller: _note, style: const TextStyle(fontSize: 13.5), decoration: billDec('Note (optional)', c)),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12.5))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel'))),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: c, minimumSize: const Size.fromHeight(44)),
                onPressed: _saving ? null : _submit,
                icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check, size: 18),
                label: const Text('Record payment'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}


/// Long-press menu for an invoice row: the usual things staff do with a bill, one tap each.
Future<void> showInvoiceActions(BuildContext context, Map<String, dynamic> r) async {
  final auth = context.read<AuthProvider>();
  final id = _s(r['_id']);
  final cancelled = _s(r['status']) == 'cancelled';
  final due = _n(r['dueAmount'] ?? r['due']);
  final choice = await showModalBottomSheet<String>(
    context: context,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) {
      Widget tile(IconData icon, String label, String value, {Color? color, String? sub}) => ListTile(
            dense: true,
            leading: Icon(icon, color: color ?? const Color(0xFF4F46E5)),
            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: sub == null ? null : Text(sub, style: const TextStyle(fontSize: 11.5)),
            onTap: () => Navigator.pop(ctx, value),
          );
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Row(children: [
              Expanded(child: Text('Invoice ${_s(r['invoiceNumber'])}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
              Text(inr(_n(r['totalPayableAmount'] ?? r['value'])), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ]),
          ),
          tile(Icons.open_in_new, 'Open', 'open'),
          tile(Icons.share_outlined, 'Share PDF', 'share'),
          tile(Icons.print_outlined, 'Print', 'print'),
          if (!cancelled && due > 0 && auth.can('billing.receivePayment')) tile(Icons.payments_outlined, 'Receive payment', 'pay', color: const Color(0xFF16A34A), sub: 'Due ${inr(due)}'),
          if (!cancelled && auth.can('billing.creditNote')) tile(Icons.assignment_return_outlined, 'Return / refund (credit note)', 'return', color: const Color(0xFFB91C1C)),
          const SizedBox(height: 6),
        ]),
      );
    },
  );
  if (choice == null || !context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id, initialAction: choice == 'open' ? null : choice)));
}
