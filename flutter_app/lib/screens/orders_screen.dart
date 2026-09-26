import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';
import '../widgets/bill_ui.dart';
import '../widgets/customer_field.dart';
import 'create_invoice_screen.dart';

String _s(dynamic v) => (v ?? '').toString();
double _n(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(_s(v)) ?? 0;
String _ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
const _c = Color(0xFF0E7490);

Color _statusColor(String s, bool overdue) => overdue ? Colors.red.shade700 : {'new': Colors.blue.shade700, 'making': Colors.orange.shade800, 'ready': const Color(0xFF15803D), 'delivered': Colors.grey.shade700, 'cancelled': Colors.grey.shade600}[s] ?? Colors.grey;
String _statusText(String s, bool overdue) => overdue ? 'OVERDUE' : {'new': 'NEW', 'making': 'BEING MADE', 'ready': 'READY', 'delivered': 'DELIVERED', 'cancelled': 'CANCELLED'}[s] ?? s.toUpperCase();

/// Made-to-order pieces: what the customer asked for, the advance, who is making it, and when it is due.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _api = ApiService();
  final _q = TextEditingController();
  String _tab = 'active';
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _counts = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.orders(q: _q.text.trim(), status: _tab);
      if (!mounted) return;
      setState(() {
        _rows = (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _counts = Map<String, dynamic>.from(r['counts'] as Map? ?? {});
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
    final id = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const OrderFormScreen()));
    if (id != null && mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(id: id)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = context.watch<AuthProvider>().can('orders.create');
    final tabs = [('active', 'Active', _counts['active']), ('overdue', 'Overdue', _counts['overdue']), ('ready', 'Ready', _counts['ready']), ('delivered', 'Delivered', null), ('cancelled', 'Cancelled', null)];
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(title: const Text('Customer orders', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)), backgroundColor: const Color(0xFFF4F5F8), foregroundColor: const Color(0xFF1A1A1A), elevation: 0),
      floatingActionButton: canCreate ? FloatingActionButton.extended(backgroundColor: _c, foregroundColor: Colors.white, onPressed: _new, icon: const Icon(Icons.add), label: const Text('New order')) : null,
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 2, 12, 4), child: TextField(controller: _q, onSubmitted: (_) => _load(), decoration: billDec('Search name, mobile, number or item', _c, suffix: IconButton(icon: const Icon(Icons.search), onPressed: _load)))),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final t in tabs)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('${t.$2}${t.$3 != null && _n(t.$3) > 0 ? '  ${_n(t.$3).toInt()}' : ''}'),
                  selected: _tab == t.$1,
                  selectedColor: (t.$1 == 'overdue' ? Colors.red : _c).withOpacity(0.18),
                  onSelected: (_) {
                    setState(() => _tab = t.$1);
                    _load();
                  },
                ),
              ),
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
                            ? [const Padding(padding: EdgeInsets.only(top: 90), child: Text('No orders here.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)))]
                            : [for (final o in _rows) _card(o)],
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> o) {
    final overdue = o['overdue'] == true;
    final active = ['new', 'making', 'ready'].contains(_s(o['status']));
    final left = o['daysLeft'];
    final due = !active ? _s(o['deliveryDate']) : (overdue ? '${-(left as int)} day${left == -1 ? '' : 's'} late' : (left == 0 ? 'due today' : 'in $left day${left == 1 ? '' : 's'}'));
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(id: _s(o['id']))));
          _load();
        },
        title: Row(children: [Expanded(child: Text(_s(o['customerName']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))), StatusPill(_statusText(_s(o['status']), overdue), _statusColor(_s(o['status']), overdue))]),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text('${_s(o['description'])}\n${_s(o['number'])}  ·  ${active ? 'delivery $due' : due}${_n(o['advancePaid']) > 0 ? '  ·  advance ${inr(_n(o['advancePaid']))}' : ''}', style: const TextStyle(fontSize: 12)),
        ),
        isThreeLine: true,
      ),
    );
  }
}

/// Take an order: the customer, what to make, when it is due and the advance.
class OrderFormScreen extends StatefulWidget {
  const OrderFormScreen({super.key});
  @override
  State<OrderFormScreen> createState() => _OrderFormScreenState();
}

class _OrderFormScreenState extends State<OrderFormScreen> {
  final _api = ApiService();
  final _name = TextEditingController(), _mobile = TextEditingController(), _desc = TextEditingController(), _weight = TextEditingController();
  final _price = TextEditingController(), _adv = TextEditingController(), _karigar = TextEditingController(), _note = TextEditingController();
  String _customerId = '', _metal = 'gold', _purity = '22K', _mode = 'Cash';
  DateTime _delivery = DateTime.now().add(const Duration(days: 15));
  bool _busy = false;
  final String _requestId = 'ord-${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(9999)}';

  @override
  void dispose() {
    for (final c in [_name, _mobile, _desc, _weight, _price, _adv, _karigar, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  double _d(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;
  List<String> get _purities => _metal == 'silver' ? ['999', '925', '800'] : ['24K', '22K', '18K', '14K'];

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _delivery, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d != null) setState(() => _delivery = d);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final r = await _api.orderCreate({
        'requestId': _requestId, 'customerId': _customerId, 'customerName': _name.text.trim(), 'customerMobile': _mobile.text.trim(), 'description': _desc.text.trim(),
        'metalType': _metal, 'purity': _purity, 'approxWeight': _d(_weight), 'estimatedPrice': _d(_price), 'deliveryDate': _ymd(_delivery),
        'advanceAmount': _d(_adv), 'advanceMode': _mode, 'karigar': _karigar.text.trim(), 'note': _note.text.trim(),
      });
      if (!mounted) return;
      if (r['success'] == true) {
        Navigator.pop(context, _s((r['data'] as Map)['id']));
        return;
      }
      showAppSnackBar(context, SnackBar(content: Text(_s(r['message'])), backgroundColor: Colors.red.shade700));
    } catch (_) {
      if (mounted) showAppSnackBar(context, SnackBar(content: const Text('Connection problem. Tap Save again: no duplicate order will be made.'), backgroundColor: Colors.red.shade700));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tf(TextEditingController c, String label, {bool num = false, int lines = 1, String? prefix}) => TextField(
        controller: c,
        maxLines: lines,
        onChanged: (_) => setState(() {}),
        keyboardType: num ? const TextInputType.numberWithOptions(decimal: true) : (lines > 1 ? TextInputType.multiline : TextInputType.text),
        inputFormatters: num ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))] : null,
        textCapitalization: num ? TextCapitalization.none : TextCapitalization.sentences,
        decoration: billDec(label, _c, prefixText: prefix),
      );

  @override
  Widget build(BuildContext context) {
    final ok = _name.text.trim().length >= 2 && _mobile.text.trim().length >= 10 && _desc.text.trim().length >= 3;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(title: const Text('New order', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)), backgroundColor: const Color(0xFFF4F5F8), foregroundColor: const Color(0xFF1A1A1A), elevation: 0),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
        BillCard(title: 'Customer', icon: Icons.person_outline, color: _c, child: Column(children: [
          CustomerField(name: _name, mobile: _mobile, initialId: _customerId, label: 'Customer name *', decoration: (l) => billDec(l, _c), onChanged: (id, n, m) => setState(() => _customerId = id)),
          const SizedBox(height: 10),
          _tf(_mobile, 'Mobile * (to call when it is ready)', num: true),
        ])),
        BillCard(title: 'What to make', icon: Icons.diamond_outlined, color: _c, child: Column(children: [
          _tf(_desc, 'Describe it * (type, size, pattern)', lines: 2),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(value: _metal, isExpanded: true, decoration: billDec('Metal', _c), items: const [DropdownMenuItem(value: 'gold', child: Text('Gold')), DropdownMenuItem(value: 'silver', child: Text('Silver'))], onChanged: (v) => setState(() {
                  _metal = v ?? 'gold';
                  _purity = _purities.contains('22K') && _metal == 'gold' ? '22K' : _purities.first;
                }))),
            const SizedBox(width: 8),
            Expanded(child: DropdownButtonFormField<String>(key: ValueKey('p$_metal'), value: _purity, isExpanded: true, decoration: billDec('Purity', _c), items: [for (final p in _purities) DropdownMenuItem(value: p, child: Text(p))], onChanged: (v) => setState(() => _purity = v ?? _purity))),
          ]),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: _tf(_weight, 'About weight (g)', num: true)), const SizedBox(width: 8), Expanded(child: _tf(_karigar, 'Karigar (optional)'))]),
        ])),
        BillCard(title: 'Price, date and advance', icon: Icons.event_available_outlined, color: _c, child: Column(children: [
          Row(children: [
            Expanded(child: _tf(_price, 'Price told ₹', num: true, prefix: '₹ ')),
            const SizedBox(width: 8),
            Expanded(child: InkWell(onTap: _pickDate, child: InputDecorator(decoration: billDec('Delivery date *', _c, suffix: const Icon(Icons.calendar_today, size: 18)), child: Text(DateFormat('dd MMM yyyy').format(_delivery))))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _tf(_adv, 'Advance ₹', num: true, prefix: '₹ ')),
            const SizedBox(width: 8),
            Expanded(child: DropdownButtonFormField<String>(value: _mode, isExpanded: true, decoration: billDec('Paid by', _c), items: [for (final m in const ['Cash', 'Online', 'Card', 'Cheque']) DropdownMenuItem(value: m, child: Text(m))], onChanged: (v) => setState(() => _mode = v ?? 'Cash'))),
          ]),
          const SizedBox(height: 10),
          _tf(_note, 'Note (optional)'),
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('No GST now: an advance carries none. GST comes on the bill when the piece is delivered, and the advance is taken off it.', style: TextStyle(fontSize: 11.5, color: Colors.black54))),
        ])),
        FilledButton(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: _c), onPressed: ok && !_busy ? _save : null, child: Text(_busy ? 'Saving...' : (ok ? 'Save order' : 'Fill the customer, mobile and what to make'))),
      ]),
    );
  }
}

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.id});
  final String id;
  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _o;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.order(widget.id);
      if (mounted) setState(() => _o = Map<String, dynamic>.from(r['data'] as Map));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _toast(String m, {bool error = true}) => showAppSnackBar(context, SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700));

  Future<void> _call(Future<Map<String, dynamic>> Function() f, {String? ok}) async {
    try {
      final r = await f();
      if (r['success'] == false) {
        _toast(_s(r['message']));
        return;
      }
      if (ok != null) _toast(ok, error: false);
      _load();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _addAdvance() async {
    final amt = TextEditingController();
    var mode = 'Cash';
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Take more advance'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: amt, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount ₹', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(value: mode, decoration: const InputDecoration(labelText: 'Paid by', border: OutlineInputBorder()), items: [for (final m in const ['Cash', 'Online', 'Card', 'Cheque']) DropdownMenuItem(value: m, child: Text(m))], onChanged: (v) => set(() => mode = v ?? 'Cash')),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))],
        ),
      ),
    );
    if (go == true) await _call(() => _api.orderAdvance(widget.id, {'amount': amt.text.trim(), 'mode': mode}), ok: 'Advance saved');
  }

  Future<void> _cancel() async {
    final o = _o!;
    final paid = _n(o['advancePaid']);
    final refund = TextEditingController(text: paid > 0 ? paid.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '') : '');
    final why = TextEditingController();
    var mode = 'Cash';
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Cancel this order?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (paid > 0) ...[
              Text('Advance taken: ${inr(paid)}. Pay it back:', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              TextField(controller: refund, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount to return ₹', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(value: mode, decoration: const InputDecoration(labelText: 'Returned by', border: OutlineInputBorder()), items: [for (final m in const ['Cash', 'Online', 'Card', 'Cheque']) DropdownMenuItem(value: m, child: Text(m))], onChanged: (v) => set(() => mode = v ?? 'Cash')),
              const SizedBox(height: 8),
              TextField(controller: why, decoration: const InputDecoration(labelText: 'Reason (needed if you keep some)', border: OutlineInputBorder())),
            ] else
              const Text('No advance was taken.'),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700), onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel order'))],
        ),
      ),
    );
    if (go == true) await _call(() => _api.orderCancel(widget.id, {'refundMode': mode, if (paid > 0) 'refundAmount': refund.text.trim(), 'reason': why.text.trim()}), ok: 'Order cancelled');
  }

  Future<void> _deliver() async {
    final invId = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => CreateInvoiceScreen(order: _o)));
    if (invId != null && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final o = _o;
    final st = _s(o?['status']);
    final active = ['new', 'making', 'ready'].contains(st);
    final overdue = o?['overdue'] == true;
    final mobile = _s(o?['customerMobile']);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(title: Text(o == null ? 'Order' : _s(o['number']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)), backgroundColor: const Color(0xFFF4F5F8), foregroundColor: const Color(0xFF1A1A1A), elevation: 0),
      body: o == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
              BillCard(
                title: _s(o['customerName']),
                icon: Icons.person_outline,
                color: _c,
                trailing: StatusPill(_statusText(st, overdue), _statusColor(st, overdue)),
                child: Row(children: [
                  Expanded(child: Text('$mobile\nOrdered ${_s(o['date'])}', style: const TextStyle(fontSize: 12.5, color: Colors.black54))),
                  if (mobile.length >= 10) IconButton(icon: const Icon(Icons.call, color: Color(0xFF15803D)), onPressed: () => launchUrl(Uri.parse('tel:$mobile'))),
                ]),
              ),
              BillCard(title: 'What to make', icon: Icons.diamond_outlined, color: _c, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_s(o['description']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('${_s(o['metalType'])} ${_s(o['purity'])}${_n(o['approxWeight']) > 0 ? '  ·  about ${_n(o['approxWeight'])} g' : ''}${_s(o['karigar']).isEmpty ? '' : '  ·  karigar ${_s(o['karigar'])}'}', style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
                if (_s(o['note']).isNotEmpty) Text(_s(o['note']), style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
                const Divider(height: 18),
                _kv('Delivery', '${DateFormat('dd MMM yyyy').format(DateTime.parse(_s(o['deliveryDate'])))}${active ? (overdue ? '  (${-(o['daysLeft'] as int)} days late)' : '  (${o['daysLeft']} days left)') : ''}', c: overdue ? Colors.red.shade700 : null),
                _kv('Price told', _n(o['estimatedPrice']) > 0 ? inr(_n(o['estimatedPrice'])) : 'not fixed'),
                _kv('Advance taken', inr(_n(o['advancePaid'])), c: const Color(0xFF15803D)),
                if (active && _n(o['estimatedPrice']) > 0) _kv('Balance (before final weight and GST)', inr(_n(o['balanceEstimate']))),
                if (_s(o['invoiceNumber']).isNotEmpty) _kv('Billed as', _s(o['invoiceNumber'])),
              ])),
              if ((o['advances'] as List).isNotEmpty || (o['refunds'] as List).isNotEmpty)
                BillCard(title: 'Money', icon: Icons.payments_outlined, color: _c, child: Column(children: [
                  for (final a in (o['advances'] as List)) _kv('${_s((a as Map)['date'])}  advance (${_s(a['mode'])})', inr(_n(a['amount'])), c: const Color(0xFF15803D)),
                  for (final r in (o['refunds'] as List)) _kv('${_s((r as Map)['date'])}  returned (${_s(r['mode'])})', '− ${inr(_n(r['amount']))}', c: Colors.red.shade700),
                ])),
              if (active && auth.can('orders.create')) ...[
                if (st == 'new') FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: Colors.orange.shade800), onPressed: () => _call(() => _api.orderStatus(widget.id, {'status': 'making'}), ok: 'Marked as being made'), icon: const Icon(Icons.hardware), label: const Text('Given to karigar / being made')),
                if (st != 'ready') Padding(padding: const EdgeInsets.only(top: 8), child: FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: const Color(0xFF15803D)), onPressed: () => _call(() => _api.orderStatus(widget.id, {'status': 'ready'}), ok: 'Marked ready: call the customer'), icon: const Icon(Icons.check_circle_outline), label: const Text('Piece is ready'))),
                Padding(padding: const EdgeInsets.only(top: 8), child: OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)), onPressed: _addAdvance, icon: const Icon(Icons.add), label: const Text('Take more advance'))),
                if (auth.can('billing.create')) Padding(padding: const EdgeInsets.only(top: 8), child: FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: _c), onPressed: _deliver, icon: const Icon(Icons.receipt_long), label: const Text('Deliver and make the bill'))),
              ],
              if (active && auth.can('orders.cancel')) TextButton(onPressed: _cancel, child: Text('Cancel order', style: TextStyle(color: Colors.red.shade700))),
            ]),
    );
  }

  Widget _kv(String a, String b, {Color? c}) => Padding(padding: const EdgeInsets.symmetric(vertical: 2.5), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: Text(a, style: const TextStyle(fontSize: 13, color: Colors.black54))), const SizedBox(width: 8), Text(b, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c))]));
}
