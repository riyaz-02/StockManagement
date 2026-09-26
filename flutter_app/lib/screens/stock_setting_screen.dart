import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';
import '../widgets/bill_ui.dart';

const _accent = Color(0xFFD97706);

/// "Stock Setting": the rules that decide how stock, sales, purchases and old metal are valued.
/// Four tabs (Add Stock, Sell Stock, Purchase, Old Metal), each a card of dropdown rules. Everybody can read them
/// (the forms follow them); only people with the "Change Stock Setting rules" permission can save.
class StockSettingScreen extends StatefulWidget {
  const StockSettingScreen({super.key});

  @override
  State<StockSettingScreen> createState() => _StockSettingScreenState();
}

class _Opt {
  const _Opt(this.value, this.label);
  final dynamic value;
  final String label;
}

class _Rule {
  const _Rule(this.key, this.title, this.options, {this.hint = ''});
  final String key;
  final String title;
  final List<_Opt> options;
  final String hint;
}

const _bases = [_Opt('finalFine', 'By final fine wt'), _Opt('fine', 'By fine wt'), _Opt('net', 'By net wt'), _Opt('gross', 'By gross wt')];
const _yes = [_Opt(true, 'Yes'), _Opt(false, 'No')];
const _last3 = [_Opt('addStock', 'Add stock'), _Opt('lastEntry', 'Last entry'), _Opt('userWiseLastEntry', 'User-wise last entry')];

const _groups = <String, List<_Rule>>{
  'addStock': [
    _Rule('customerWastage', 'Customer wastage', [_Opt('fine', 'Fine wt'), _Opt('net', 'Net wt'), _Opt('gross', 'Gross wt')], hint: 'Weight the customer wastage % is taken on'),
    _Rule('valuation', 'Valuation', _bases, hint: 'Weight the metal value is worked out on'),
    _Rule('makingCharges', 'Making charges', _bases),
    _Rule('labourCharges', 'Labour charges', _bases),
    _Rule('metalRateByPurity', 'Metal rate by purity', _yes, hint: 'Use a separate rate for each purity'),
    _Rule('hallmarkGst', 'Hallmark GST', _yes, hint: 'Charge GST on the hallmarking fee'),
    _Rule('calculateItemRate', 'Calculate item rate', [_Opt('byPurity', 'By purity'), _Opt('default', 'Default')]),
  ],
  'sellStock': [
    _Rule('reverseCalculation', 'Reverse calculation (typed amount is more)', [_Opt('makingCharges', 'By making charges'), _Opt('custWastage', 'By customer wastage'), _Opt('metalRate', 'By metal rate')], hint: 'What changes when staff type a higher price'),
    _Rule('makingChargesType', 'Making charges', _last3, hint: 'Where the making charge is taken from'),
    _Rule('metalRateByPurity', 'Metal rate by purity', _yes),
    _Rule('byAddedMetalRate', 'Sell by the metal rate it was added at', _yes),
    _Rule('custWastage', 'Customer wastage', [..._last3, _Opt('blank', 'Blank')]),
    _Rule('hallmarkGst', 'Hallmark GST', _yes),
  ],
  'purchase': [
    _Rule('labourCharges', 'Labour charges', _bases),
    _Rule('wastage', 'Wastage', [_Opt('fine', 'By fine wt'), _Opt('net', 'By net wt'), _Opt('gross', 'By gross wt')]),
    _Rule('finalValuation', 'Final valuation', _bases),
    _Rule('hallmarkGst', 'Hallmark GST', _yes),
  ],
  'oldMetal': [
    _Rule('receivedValuation', 'Old metal / URD received valuation', _bases),
    _Rule('rawMetalPurchaseValuation', 'Raw metal purchase final valuation', _bases),
  ],
};

class _StockSettingScreenState extends State<StockSettingScreen> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late final TabController _tabs = TabController(length: 4, vsync: this);
  Map<String, dynamic> _saved = {}; // as stored on the server
  Map<String, dynamic> _draft = {}; // what is on screen
  final _charge = TextEditingController();
  final _cgst = TextEditingController();
  final _sgst = TextEditingController();
  final _igst = TextEditingController();
  bool _loading = true, _saving = false;
  String? _error;

  bool get _canEdit => context.read<AuthProvider>().can('settings.manageStockRules');

  Map<String, dynamic> _deep(Map<String, dynamic> m) => {for (final e in m.entries) e.key: e.value is Map ? Map<String, dynamic>.from(e.value as Map) : e.value};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [_charge, _cgst, _sgst, _igst]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await _api.stockSettings();
      final s = Map<String, dynamic>.from((r['data'] as Map)['settings'] as Map);
      _apply(s);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _apply(Map<String, dynamic> s) {
    _saved = _deep(s);
    _draft = _deep(s);
    final h = Map<String, dynamic>.from(_draft['hallmark'] as Map? ?? {});
    String n(dynamic v) => v == null ? '' : (v is num && v == v.roundToDouble() ? v.toInt().toString() : v.toString());
    _charge.text = n(h['charge']);
    _cgst.text = n(h['cgst']);
    _sgst.text = n(h['sgst']);
    _igst.text = n(h['igst']);
  }

  Map<String, dynamic> _changes() {
    final out = <String, dynamic>{};
    for (final g in _groups.keys) {
      final a = Map<String, dynamic>.from(_saved[g] as Map? ?? {}), b = Map<String, dynamic>.from(_draft[g] as Map? ?? {});
      final diff = {for (final e in b.entries) if (a[e.key] != e.value) e.key: e.value};
      if (diff.isNotEmpty) out[g] = diff;
    }
    final h = <String, dynamic>{};
    final sh = Map<String, dynamic>.from(_saved['hallmark'] as Map? ?? {}), dh = Map<String, dynamic>.from(_draft['hallmark'] as Map? ?? {});
    for (final k in ['charge', 'cgst', 'sgst', 'igst']) {
      final v = double.tryParse({'charge': _charge, 'cgst': _cgst, 'sgst': _sgst, 'igst': _igst}[k]!.text.trim());
      if (v != null && v != (sh[k] as num?)?.toDouble()) h[k] = v;
    }
    if (dh['type'] != sh['type']) h['type'] = dh['type'];
    if (h.isNotEmpty) out['hallmark'] = h;
    return out;
  }

  Future<void> _save() async {
    final ch = _changes();
    if (ch.isEmpty) return;
    setState(() => _saving = true);
    final r = await _api.stockSettingsSave(ch);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      setState(() => _apply(Map<String, dynamic>.from((r['data'] as Map)['settings'] as Map)));
      showAppSnackBar(context, const SnackBar(content: Text('Stock Setting saved'), backgroundColor: Colors.green));
    } else {
      showAppSnackBar(context, SnackBar(content: Text('${r['message'] ?? 'Could not save'}'), backgroundColor: Colors.red));
    }
  }

  Future<void> _reset() async {
    final yes = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Reset to defaults?'),
            content: const Text('Every rule on all four tabs goes back to its default.'),
            actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reset'))],
          ),
        ) ??
        false;
    if (!yes || !mounted) return;
    final r = await _api.stockSettingsReset();
    if (r['success'] == true && mounted) setState(() => _apply(Map<String, dynamic>.from((r['data'] as Map)['settings'] as Map)));
  }

  @override
  Widget build(BuildContext context) {
    final dirty = !_loading && _changes().isNotEmpty;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(
        title: const Text('Stock Setting', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [if (_canEdit) IconButton(tooltip: 'Reset to defaults', icon: const Icon(Icons.restart_alt_rounded), onPressed: _loading ? null : _reset)],
        bottom: TabBar(
          controller: _tabs,
          labelColor: _accent,
          indicatorColor: _accent,
          unselectedLabelColor: Colors.black54,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          tabs: const [Tab(text: 'Add Stock'), Tab(text: 'Sell Stock'), Tab(text: 'Purchase'), Tab(text: 'Old Metal')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.red))))
              : TabBarView(controller: _tabs, children: [_tab('addStock', 'Add stock', Icons.add_box_outlined, extra: _hallmarkCard()), _tab('sellStock', 'Sell stock', Icons.sell_outlined), _tab('purchase', 'Purchase', Icons.shopping_bag_outlined), _tab('oldMetal', 'Old metal', Icons.recycling_rounded)]),
      bottomNavigationBar: (!_canEdit || _loading)
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, -2))]),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _accent, minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: dirty && !_saving ? _save : null,
                  icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_rounded),
                  label: Text(dirty ? 'Save changes' : 'No changes', style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
    );
  }

  Widget _tab(String group, String title, IconData icon, {Widget? extra}) {
    final rules = _groups[group]!;
    final cur = Map<String, dynamic>.from(_draft[group] as Map? ?? {});
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        BillCard(
          title: title,
          icon: icon,
          color: _accent,
          child: Column(children: [
            for (var i = 0; i < rules.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _ruleField(group, rules[i], cur[rules[i].key]),
            ],
          ]),
        ),
        if (extra != null) extra,
        if (!_canEdit) const Padding(padding: EdgeInsets.all(8), child: Text('You can view these rules. Ask an admin to change them.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54))),
      ],
    );
  }

  Widget _ruleField(String group, _Rule r, dynamic value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownButtonFormField<dynamic>(
          value: r.options.any((o) => o.value == value) ? value : null,
          isExpanded: true,
          style: const TextStyle(fontSize: 13.5, color: Colors.black87),
          decoration: billDec(r.title, _accent),
          items: [for (final o in r.options) DropdownMenuItem<dynamic>(value: o.value, child: Text(o.label))],
          onChanged: _canEdit
              ? (v) => setState(() {
                    final m = Map<String, dynamic>.from(_draft[group] as Map? ?? {});
                    m[r.key] = v;
                    _draft[group] = m;
                  })
              : null,
        ),
        if (r.hint.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 4, top: 3), child: Text(r.hint, style: const TextStyle(fontSize: 11, color: Colors.black45))),
      ]);

  Widget _hallmarkCard() {
    final type = (_draft['hallmark'] as Map? ?? {})['type'] ?? 'perPiece';
    Widget num(TextEditingController c, String label) => TextFormField(
          controller: c,
          enabled: _canEdit,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 13.5),
          decoration: billDec(label, _accent),
        );
    return BillCard(
      title: 'Hallmarking charge & GST',
      icon: Icons.verified_outlined,
      color: _accent,
      child: Column(children: [
        Row(children: [
          Expanded(child: num(_charge, 'Charge ₹')),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: type as String,
              isExpanded: true,
              style: const TextStyle(fontSize: 13.5, color: Colors.black87),
              decoration: billDec('Charged', _accent),
              items: const [DropdownMenuItem(value: 'perPiece', child: Text('Per piece')), DropdownMenuItem(value: 'perGram', child: Text('Per gram'))],
              onChanged: _canEdit ? (v) => setState(() => (_draft['hallmark'] as Map)['type'] = v) : null,
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [Expanded(child: num(_cgst, 'CGST %')), const SizedBox(width: 8), Expanded(child: num(_sgst, 'SGST %')), const SizedBox(width: 8), Expanded(child: num(_igst, 'IGST %'))]),
      ]),
    );
  }
}
