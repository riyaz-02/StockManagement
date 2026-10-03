import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/bill_ui.dart';
import 'expenses_screen.dart';
import '../widgets/live_refresh.dart';

String _s(dynamic v) => (v ?? '').toString();
double _n(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(_s(v)) ?? 0;
String _ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
const _green = Color(0xFF15803D);
const _red = Color(0xFFB91C1C);

/// The owner's daily page: how much money came in and went out, by cash / card / online / cheque, and what happened.
class DayBookScreen extends StatefulWidget {
  const DayBookScreen({super.key});
  @override
  State<DayBookScreen> createState() => _DayBookScreenState();
}

class _DayBookScreenState extends State<DayBookScreen> with LiveRefresh<DayBookScreen> {
  @override
  List<String> get liveModules => ['billing', 'expenses', 'orders', 'oldmetal'];

  @override
  void onLiveChange() => _load();

  final _api = ApiService();
  DateTime _from = DateTime.now(), _to = DateTime.now();
  Map<String, dynamic> _d = {};
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
    disposeLive();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.billingDayBook(from: _ymd(_from), to: _ymd(_to));
      if (!mounted) return;
      setState(() {
        _d = Map<String, dynamic>.from(r['data'] as Map);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
            _loading = false;
            _error = e.toString().replaceFirst('Exception: ', '');
          });
    }
  }

  void _quick(int daysBack, {bool month = false}) {
    final now = DateTime.now();
    setState(() {
      if (month) {
        _from = DateTime(now.year, now.month, 1);
        _to = now;
      } else {
        _from = _to = now.subtract(Duration(days: daysBack));
      }
    });
    _load();
  }

  Future<void> _pick() async {
    final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: DateTimeRange(start: _from, end: _to));
    if (r == null) return;
    setState(() {
      _from = r.start;
      _to = r.end;
    });
    _load();
  }

  bool get _isToday => _ymd(_from) == _ymd(DateTime.now()) && _ymd(_to) == _ymd(DateTime.now());
  bool get _isYesterday => _ymd(_from) == _ymd(DateTime.now().subtract(const Duration(days: 1))) && _ymd(_to) == _ymd(_from);
  String get _label => _ymd(_from) == _ymd(_to) ? DateFormat('EEE, dd MMM yyyy').format(_from) : '${DateFormat('dd MMM').format(_from)} – ${DateFormat('dd MMM yyyy').format(_to)}';

  @override
  Widget build(BuildContext context) {
    final canExpense = context.watch<AuthProvider>().can('expenses.create');
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(
        title: const Text('Day Book', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        backgroundColor: const Color(0xFFF4F5F8),
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        actions: [IconButton(tooltip: 'Expenses', icon: const Icon(Icons.receipt_long_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpensesScreen())).then((_) => _load()))],
      ),
      floatingActionButton: canExpense
          ? FloatingActionButton.extended(
              backgroundColor: kBillAccent,
              foregroundColor: Colors.white,
              onPressed: () async {
                if (await showAddExpenseSheet(context) == true) _load();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add expense'))
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              ChoiceChip(label: const Text('Today'), selected: _isToday, selectedColor: kBillAccent.withOpacity(0.18), onSelected: (_) => _quick(0)),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('Yesterday'), selected: _isYesterday, selectedColor: kBillAccent.withOpacity(0.18), onSelected: (_) => _quick(1)),
              const SizedBox(width: 8),
              ActionChip(avatar: const Icon(Icons.calendar_month, size: 16), label: const Text('This month'), onPressed: () => _quick(0, month: true)),
              const SizedBox(width: 8),
              ActionChip(avatar: const Icon(Icons.date_range, size: 16), label: const Text('Pick dates'), onPressed: _pick),
            ]),
          ),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 6), child: Align(alignment: Alignment.centerLeft, child: Text(_label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black54)))),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
                  : RefreshIndicator(onRefresh: _load, child: _body()),
        ),
      ]),
    );
  }

  Widget _body() {
    final modes = (_d['modes'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final t = Map<String, dynamic>.from(_d['totals'] as Map? ?? {});
    final sum = Map<String, dynamic>.from(_d['summary'] as Map? ?? {});
    final lines = (_d['lines'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final cash = modes.firstWhere((m) => m['mode'] == 'Cash', orElse: () => {'net': 0});
    Map<String, dynamic> g(String k) => Map<String, dynamic>.from(sum[k] as Map? ?? {});
    Widget kv(String a, String b, {Color? c, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.5),
          child: Row(children: [Expanded(child: Text(a, style: const TextStyle(fontSize: 13, color: Colors.black54))), Text(b, style: TextStyle(fontSize: 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: c))]),
        );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: const LinearGradient(colors: [Color(0xFFB45309), Color(0xFFF59E0B)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Cash in hand (in − out)', style: TextStyle(color: Colors.white70, fontSize: 12)), Text(inr(_n(cash['net'])), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)), const Text('for this period, before your opening balance', style: TextStyle(color: Colors.white70, fontSize: 10.5))])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('In ${inr(_n(t['in']))}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              Text('Out ${inr(_n(t['out']))}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ]),
        ),
        BillCard(
          title: 'Money by how it was paid',
          icon: Icons.account_balance_wallet_outlined,
          color: kBillAccent,
          child: Table(columnWidths: const {0: FlexColumnWidth(1.3), 1: FlexColumnWidth(1.4), 2: FlexColumnWidth(1.3), 3: FlexColumnWidth(1.4)}, children: [
            const TableRow(children: [Text(''), Text('In', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: Colors.black54)), Text('Out', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: Colors.black54)), Text('Net', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: Colors.black54))]),
            for (final m in modes)
              TableRow(children: [
                Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(_s(m['mode']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                Text(_n(m['in']) == 0 ? '–' : inr(_n(m['in'])), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, color: _green)),
                Text(_n(m['out']) == 0 ? '–' : inr(_n(m['out'])), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, color: _red)),
                Text(inr(_n(m['net'])), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
              ]),
          ]),
        ),
        BillCard(
          title: 'What happened',
          icon: Icons.insights_outlined,
          color: const Color(0xFF4F46E5),
          child: Column(children: [
            kv('Sales (${g('sales')['count'] ?? 0} bills)', inr(_n(g('sales')['amount'])), bold: true),
            kv('   received so far', inr(_n(g('sales')['received']))),
            kv('Refunds / returns (${g('refunds')['count'] ?? 0})', inr(_n(g('refunds')['amount'])), c: _red),
            kv('Expenses (${g('expenses')['count'] ?? 0})', inr(_n(g('expenses')['amount'])), c: _red),
            kv('Purchases (${g('purchases')['count'] ?? 0} bills)', inr(_n(g('purchases')['amount']))),
            kv('Old metal taken (${g('oldMetal')['count'] ?? 0})', '${_n(g('oldMetal')['net'])} g  ·  ${inr(_n(g('oldMetal')['amount']))}'),
            kv('Raw metal bought (${g('rawMetal')['count'] ?? 0})', '${_n(g('rawMetal')['net'])} g  ·  ${inr(_n(g('rawMetal')['amount']))}'),
          ]),
        ),
        BillCard(
          title: 'Every entry (${lines.length})',
          icon: Icons.list_alt_outlined,
          color: const Color(0xFF0F766E),
          child: lines.isEmpty
              ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No money moved in this period.', style: TextStyle(color: Colors.black54)))
              : Column(children: [
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        Icon(l['kind'] == 'receipt' ? Icons.south_west : Icons.north_east, size: 18, color: l['kind'] == 'receipt' ? _green : _red),
                        const SizedBox(width: 8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_s(l['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          Text('${_s(l['at']).length >= 16 ? _s(l['at']).substring(5, 16) : _s(l['at'])}  ·  ${_s(l['mode'])}${_s(l['subtitle']).isEmpty ? '' : '  ·  ${_s(l['subtitle'])}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                        ])),
                        Text('${l['kind'] == 'receipt' ? '+' : '−'} ${inr(_n(l['amount']))}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: l['kind'] == 'receipt' ? _green : _red)),
                      ]),
                    ),
                ]),
        ),
      ],
    );
  }
}
