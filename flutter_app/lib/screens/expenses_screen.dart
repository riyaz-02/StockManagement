import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';
import '../widgets/bill_ui.dart';
import '../widgets/live_refresh.dart';

String _s(dynamic v) => (v ?? '').toString();
double _n(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(_s(v)) ?? 0;
String _ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

const _catIcons = <String, IconData>{
  'Salary': Icons.badge_outlined,
  'Rent': Icons.home_work_outlined,
  'Electricity': Icons.bolt_outlined,
  'Tea / food': Icons.local_cafe_outlined,
  'Transport': Icons.local_shipping_outlined,
  'Repair / labour': Icons.build_outlined,
  'Packing / tags': Icons.sell_outlined,
  'Advertising': Icons.campaign_outlined,
  'Other': Icons.more_horiz,
};

/// The shop's running costs: pick a day, see what was spent, add a new one in three taps.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> with LiveRefresh<ExpensesScreen> {
  @override
  List<String> get liveModules => ['expenses'];

  @override
  void onLiveChange() => _load();

  final _api = ApiService();
  String _range = 'today'; // today | yesterday | month
  List<Map<String, dynamic>> _rows = [];
  double _total = 0;
  bool _loading = true;
  String? _error;

  (String, String) get _dates {
    final now = DateTime.now();
    switch (_range) {
      case 'yesterday':
        final y = _ymd(now.subtract(const Duration(days: 1)));
        return (y, y);
      case 'month':
        return (_ymd(DateTime(now.year, now.month, 1)), _ymd(now));
      default:
        return (_ymd(now), _ymd(now));
    }
  }

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
      final (from, to) = _dates;
      final r = await _api.expenses(from: from, to: to);
      final d = Map<String, dynamic>.from(r['data'] as Map);
      if (!mounted) return;
      setState(() {
        _rows = (d['rows'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _total = _n(d['total']);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
            _loading = false;
            _error = e.toString().replaceFirst('Exception: ', '');
          });
    }
  }

  Future<void> _add() async {
    final done = await showAddExpenseSheet(context);
    if (done == true) _load();
  }

  Future<void> _cancel(Map<String, dynamic> e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this expense?'),
        content: Text('${_s(e['category'])}  ${inr(_n(e['amount']))}\nIt will no longer count in the Day Book.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel expense'))],
      ),
    );
    if (ok != true) return;
    try {
      await _api.expenseCancel(_s(e['id']));
      _load();
    } catch (err) {
      if (mounted) showAppSnackBar(context, SnackBar(content: Text(err.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red.shade700));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = context.watch<AuthProvider>().can('expenses.create');
    final canDelete = context.watch<AuthProvider>().can('expenses.delete');
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(
        title: const Text('Expenses', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        backgroundColor: const Color(0xFFF4F5F8),
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
      ),
      floatingActionButton: canCreate ? FloatingActionButton.extended(backgroundColor: kBillAccent, foregroundColor: Colors.white, onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add expense')) : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: Row(children: [
            for (final c in const [('today', 'Today'), ('yesterday', 'Yesterday'), ('month', 'This month')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(c.$2),
                  selected: _range == c.$1,
                  selectedColor: kBillAccent.withOpacity(0.18),
                  onSelected: (_) {
                    setState(() => _range = c.$1);
                    _load();
                  },
                ),
              ),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [const Text('Total', style: TextStyle(fontSize: 11, color: Colors.black54)), Text(inr(_total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))]),
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
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                        children: _rows.isEmpty
                            ? [const Padding(padding: EdgeInsets.only(top: 90), child: Text('No expenses in this period.\nTap "Add expense" to write one down.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)))]
                            : [
                                for (final e in _rows)
                                  Card(
                                    elevation: 0,
                                    margin: const EdgeInsets.only(bottom: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    child: ListTile(
                                      onLongPress: canDelete ? () => _cancel(e) : null,
                                      leading: CircleAvatar(backgroundColor: kBillAccent.withOpacity(0.12), child: Icon(_catIcons[_s(e['category'])] ?? Icons.receipt_long, color: kBillAccent, size: 20)),
                                      title: Text(_s(e['category']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                      subtitle: Text('${DateFormat('dd MMM').format(DateTime.parse(_s(e['date'])))}  ·  ${_s(e['mode'])}${_s(e['note']).isEmpty ? '' : '  ·  ${_s(e['note'])}'}', style: const TextStyle(fontSize: 12)),
                                      trailing: Text(inr(_n(e['amount'])), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                                    ),
                                  ),
                                if (canDelete) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Long-press an expense to cancel it.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: Colors.black45))),
                              ],
                      ),
                    ),
        ),
      ]),
    );
  }
}

/// Bottom sheet to write down an expense: what for, how much, how it was paid. Returns true when one was saved.
Future<bool?> showAddExpenseSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => const _ExpenseSheet(),
  );
}

class _ExpenseSheet extends StatefulWidget {
  const _ExpenseSheet();
  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _cat = 'Tea / food';
  String _mode = 'Cash';
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final r = await ApiService().expenseCreate({'amount': _amount.text.trim(), 'category': _cat, 'mode': _mode, 'note': _note.text.trim()});
      if (!mounted) return;
      if (r['success'] == false) {
        setState(() {
          _busy = false;
          _err = _s(r['message']);
        });
        return;
      }
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() {
            _busy = false;
            _err = e.toString().replaceFirst('Exception: ', '');
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Add expense', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            decoration: billDec('Amount *', kBillAccent, prefixText: '₹ '),
          ),
          const SizedBox(height: 12),
          const Text('What for', style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 2, children: [
            for (final c in _catIcons.keys)
              ChoiceChip(
                avatar: Icon(_catIcons[c], size: 16),
                label: Text(c, style: const TextStyle(fontSize: 12.5)),
                selected: _cat == c,
                selectedColor: kBillAccent.withOpacity(0.18),
                onSelected: (_) => setState(() => _cat = c),
              ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _mode,
                isExpanded: true,
                decoration: billDec('Paid by', kBillAccent),
                items: [for (final m in const ['Cash', 'Online', 'Card', 'Cheque']) DropdownMenuItem(value: m, child: Text(m))],
                onChanged: (v) => setState(() => _mode = v ?? 'Cash'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _note, textCapitalization: TextCapitalization.sentences, decoration: billDec('Note (optional)', kBillAccent))),
          ]),
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: TextStyle(color: Colors.red.shade700, fontSize: 12.5, fontWeight: FontWeight.w600))),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: kBillAccent),
            onPressed: _busy || (double.tryParse(_amount.text) ?? 0) <= 0 ? null : _save,
            child: Text(_busy ? 'Saving...' : 'Save expense'),
          ),
        ]),
      ),
    );
  }
}
