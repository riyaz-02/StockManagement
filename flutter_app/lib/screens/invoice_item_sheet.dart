import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';
import '../utils/billing_calc.dart';
import '../utils/stock_valuation.dart';
import '../widgets/bill_ui.dart';
import 'barcode_scanner_for_assignment.dart';

const _goldPurities = ['24K', '22K', '20K', '18K', '14K'];
const _silverPurities = ['999', '925', '800'];
const _extraKinds = ['Stone', 'Diamond', 'Pearl', 'Metal', 'Other'];
const _amber = Color(0xFFD97706);

String _s(dynamic v) => (v ?? '').toString();

/// 12.5 -> "12.5", 12 -> "12", 0 -> "" (blank fields stay blank).
String fmtNum(double v, {int dp = 3}) {
  if (v == 0) return '';
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(dp).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

String _metalOf(String v) {
  final s = v.toLowerCase();
  return s.startsWith('g') ? 'Gold' : (s.startsWith('s') ? 'Silver' : 'Other');
}

/// Scan a barcode (or type it) and turn the stock item into an invoice line.
/// Returns null when cancelled or when the item cannot be billed (a message is shown).
Future<BillItem?> scanStockItem(BuildContext context, {List<String> taken = const [], double goldRate = 0, double silverRate = 0}) async {
  final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const BarcodeScannerForAssignment()));
  if (code == null || code.trim().isEmpty || !context.mounted) return null;
  return lookupStockItem(context, code, taken: taken, goldRate: goldRate, silverRate: silverRate);
}

/// The stock piece behind a barcode as an invoice line. The making charge is pre-filled from what was recorded when the
/// piece was added, plus the effect of the Stock Setting rules on the metal (for example valuing on final fine weight,
/// or customer wastage), so the bill comes to the stock price.
Future<BillItem?> lookupStockItem(BuildContext context, String code, {List<String> taken = const [], double goldRate = 0, double silverRate = 0}) async {
  void toast(String m, {bool error = true}) => showAppSnackBar(
      context, SnackBar(content: Text(m, style: const TextStyle(fontSize: 13)), backgroundColor: error ? Colors.red.shade700 : Colors.orange.shade800));
  if (taken.contains(code.trim())) {
    toast('Already on this bill');
    return null;
  }
  try {
    final res = await ApiService().getItemByBarcode(code.trim());
    final it = Map<String, dynamic>.from((res['data'] ?? {})['item'] ?? {});
    if (it.isEmpty) {
      toast('Item not found');
      return null;
    }
    final status = _s(it['status']);
    if (status == 'sold' || status == 'deleted') {
      toast('This item is already ${status == 'sold' ? 'sold' : 'removed'}');
      return null;
    }
    if (status != 'active' && status != 'booked') toast('Note: item status is "$status"', error: false);
    final metal = _metalOf(_s(it['metalType']));
    var purity = _s(it['purity']).trim().toUpperCase();
    if (metal == 'Gold' && RegExp(r'^\d{2}$').hasMatch(purity)) purity = '${purity}K';
    final huidNo = (_s(it['huidNumber']).isNotEmpty ? _s(it['huidNumber']) : _s(it['huid'])).trim().toUpperCase();
    final certType = _s(it['certificationType']);
    final cert = huidNo.isNotEmpty || certType == 'huid' ? 'huid' : (certType == 'hallmarked' ? 'hallmark' : '');
    // the rules that decide the sell price (Stock Setting); if they cannot be read the stored making charge is used as is
    var making = (it['makingCharge'] is num) ? (it['makingCharge'] as num).toDouble() : 0.0;
    try {
      final rules = Map<String, dynamic>.from(((await ApiService().stockSettings())['data'] as Map)['settings'] as Map);
      final rate = metal == 'Gold' ? goldRate : (metal == 'Silver' ? silverRate : 0.0);
      final net = (it['netWeight'] is num) ? (it['netWeight'] as num).toDouble() : 0.0;
      final sell = Map<String, dynamic>.from((rules['sellStock'] as Map?) ?? const {});
      // Stock Setting > Sell stock > Making charges: "last entry" takes the making charge per gram of the last sale of the
      // same kind of piece (user-wise: only sales made by this user); otherwise the one recorded on the stock piece
      final mct = _s(sell['makingChargesType']);
      if ((mct == 'lastEntry' || mct == 'userWiseLastEntry') && net > 0) {
        try {
          final lm = (await ApiService().billingLastMaking(name: _s(it['name']), metal: metal, userWise: mct == 'userWiseLastEntry'))['data'];
          if (lm is Map && (lm['perGram'] as num? ?? 0) > 0) making = ((lm['perGram'] as num).toDouble() * net * 100).roundToDouble() / 100;
        } catch (_) {/* keep the recorded making charge */}
      }
      if (rate > 0 && net > 0) {
        final price = computeStock({
          'net': net,
          'gross': it['grossWeight'],
          'purity': purity,
          'wastage': it['wastage'],
          'custWastage': sell['custWastage'] == 'blank' ? 0 : it['custWastage'],
          'rate': rate,
        }, rules);
        // the bill charges net x rate for the metal; whatever the rules add on top of that goes into the making charge
        making = (making + (price.metalValuation - net * rate)).clamp(0, double.infinity).toDouble();
        making = (making * 100).roundToDouble() / 100;
      }
    } catch (_) {/* keep the stored making charge */}
    return BillItem(
      particular: _s(it['name']),
      metal: metal,
      purity: purity,
      netWt: (it['netWeight'] is num) ? (it['netWeight'] as num).toDouble() : 0,
      productCode: _s(it['barcode']).isEmpty ? code.trim() : _s(it['barcode']),
      huid: huidNo,
      certification: cert,
      itemId: _s(it['_id']),
      // what was recorded when the piece was added to stock saves typing at the counter
      grossWt: (it['grossWeight'] is num) ? (it['grossWeight'] as num).toDouble() : 0,
      making: making,
      extras: [
        if (it['stoneValue'] is num && (it['stoneValue'] as num) > 0)
          BillExtra(kind: 'Stone', name: _s(it['stoneNote']), weight: (it['lessWeight'] is num) ? (it['lessWeight'] as num).toDouble() : 0, amount: (it['stoneValue'] as num).toDouble()),
      ],
    );
  } catch (e) {
    final m = e.toString().replaceFirst('Exception: ', '');
    toast(m.toLowerCase().contains('not found') ? 'Item not found' : 'Could not look up the item ($m)');
    return null;
  }
}

class ItemSheetResult {
  ItemSheetResult(this.item, this.addNext);
  final BillItem item;
  final bool addNext;
}

Future<ItemSheetResult?> showItemSheet(
  BuildContext context, {
  BillItem? item,
  required double goldRate,
  required double silverRate,
  required bool interstate,
  required List<String> hsnCodes,
  List<String> takenCodes = const [],
}) {
  return showModalBottomSheet<ItemSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => _ItemSheet(item: item, goldRate: goldRate, silverRate: silverRate, interstate: interstate, hsnCodes: hsnCodes, takenCodes: takenCodes),
  );
}

class _ExtraCtl {
  _ExtraCtl(BillExtra e)
      : kind = e.kind,
        name = TextEditingController(text: e.name),
        weight = TextEditingController(text: fmtNum(e.weight)),
        amount = TextEditingController(text: fmtNum(e.amount, dp: 2));
  String kind;
  final TextEditingController name, weight, amount;
  double _d(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;
  BillExtra toExtra() => BillExtra(kind: kind, name: name.text, weight: _d(weight), amount: _d(amount));
  void dispose() {
    name.dispose();
    weight.dispose();
    amount.dispose();
  }
}

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({required this.item, required this.goldRate, required this.silverRate, required this.interstate, required this.hsnCodes, required this.takenCodes});
  final BillItem? item;
  final double goldRate, silverRate;
  final bool interstate;
  final List<String> hsnCodes, takenCodes;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  final _name = TextEditingController();
  final _gross = TextEditingController();
  final _net = TextEditingController();
  final _rate = TextEditingController();
  final _making = TextEditingController();
  final _taxable = TextEditingController();
  final _huidCtl = TextEditingController();
  final _hall = TextEditingController();
  final _taxableFocus = FocusNode();
  final List<_ExtraCtl> _extras = [];

  String _metal = 'Gold';
  String _purity = '';
  String _hsn = '7113';
  String _code = '';
  String _cert = ''; // '' | 'hallmark' | 'huid'
  String _itemId = '';
  bool _netTouched = false;
  bool _rateTouched = false;
  bool _override = false;
  String? _error;

  bool get _isNew => widget.item == null;
  double _d(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;
  double _metalRate(String m) => m == 'Gold' ? widget.goldRate : (m == 'Silver' ? widget.silverRate : 0);

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    if (it != null) _load(it, keepOverride: true);
    if (_rate.text.isEmpty && !_rateTouched) _rate.text = fmtNum(_metalRate(_metal), dp: 2);
    if (!widget.hsnCodes.contains(_hsn) && widget.hsnCodes.isNotEmpty) _hsn = widget.hsnCodes.first;
    _syncTaxable();
  }

  void _load(BillItem it, {bool keepOverride = false}) {
    _name.text = it.particular;
    _metal = it.metal;
    _purity = it.purity;
    _gross.text = fmtNum(it.grossWt);
    _net.text = fmtNum(it.netWt);
    _netTouched = it.netWt > 0;
    _rate.text = fmtNum(it.rate != 0 ? it.rate : _metalRate(it.metal), dp: 2);
    _rateTouched = it.rate != 0;
    _making.text = fmtNum(it.making, dp: 2);
    _hsn = it.hsn;
    _code = it.productCode;
    _huidCtl.text = it.huid;
    _cert = it.certification;
    _hall.text = fmtNum(it.hallmarkCharge, dp: 2);
    _itemId = it.itemId;
    for (final e in _extras) {
      e.dispose();
    }
    _extras
      ..clear()
      ..addAll(it.extras.map(_ExtraCtl.new));
    if (keepOverride && it.taxableOverride != null) {
      _override = true;
      _taxable.text = fmtNum(it.taxableOverride!, dp: 2);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _gross, _net, _rate, _making, _taxable, _huidCtl, _hall]) {
      c.dispose();
    }
    _taxableFocus.dispose();
    for (final e in _extras) {
      e.dispose();
    }
    super.dispose();
  }

  BillItem _build() => BillItem(
        particular: _name.text,
        metal: _metal,
        purity: _purity,
        grossWt: _d(_gross),
        netWt: _d(_net),
        rate: _rateTouched ? _d(_rate) : 0,
        making: _d(_making),
        hsn: _hsn,
        taxableOverride: _override && _taxable.text.trim().isNotEmpty ? _d(_taxable) : null,
        productCode: _code,
        huid: _huidCtl.text,
        certification: _cert,
        hallmarkCharge: _d(_hall),
        itemId: _itemId,
        extras: _extras.map((e) => e.toExtra()).where((e) => !e.isEmpty).toList(),
      );

  BillTotals get _calc => BillingCalc.compute(items: [_build()], goldRate: widget.goldRate, silverRate: widget.silverRate, interstate: widget.interstate);

  /// Keeps the (read-only) taxable field showing the calculated amount.
  void _syncTaxable() {
    if (_override) return;
    final v = _calc.lines.first.autoTaxable;
    _taxable.text = v == 0 ? '' : v.toStringAsFixed(2);
  }

  // net = gross - stones/other metals, until the net weight is typed by hand
  void _autoNet() {
    final g = _d(_gross);
    if (g > 0 && !_netTouched) {
      final n = g - BillingCalc.r3(_extras.fold<double>(0, (a, e) => a + e._d(e.weight)));
      _net.text = fmtNum(n < 0 ? 0 : BillingCalc.r3(n));
    }
  }

  void _changed({bool weights = false}) {
    if (weights) _autoNet();
    setState(() {
      _error = null;
      _syncTaxable();
    });
  }

  void _setMetal(String m) {
    setState(() {
      _metal = m;
      if (!(m == 'Gold' ? _goldPurities : m == 'Silver' ? _silverPurities : <String>[]).contains(_purity)) _purity = '';
      if (!_rateTouched) _rate.text = fmtNum(_metalRate(m), dp: 2);
      _error = null;
      _syncTaxable();
    });
  }

  void _enableOverride() {
    if (_override) return;
    setState(() {
      _override = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _taxableFocus.requestFocus());
  }

  void _resetOverride() {
    setState(() {
      _override = false;
      _syncTaxable();
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _scan() async {
    final scanned = await scanStockItem(context, taken: widget.takenCodes.where((c) => c != _code).toList());
    if (scanned == null || !mounted) return;
    setState(() {
      _load(scanned);
      _override = false;
      _error = null;
      _syncTaxable();
    });
  }

  ItemSheetResult? _finish(bool addNext) {
    final b = _build();
    if (b.metal != 'Other' && b.purity.isEmpty) {
      setState(() => _error = 'Choose the purity');
      return null;
    }
    if (_override && _taxable.text.trim().isEmpty) {
      setState(() => _error = 'Enter the taxable amount');
      return null;
    }
    final err = BillingCalc.validateItems([b], goldRate: widget.goldRate, silverRate: widget.silverRate);
    if (err != null) {
      setState(() => _error = err.replaceFirst(RegExp(r'^Item 1: '), ''));
      return null;
    }
    return ItemSheetResult(b, addNext);
  }

  // ───────────────────────────── build ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = _calc;
    final line = t.lines.first;
    final shownName = line.name;
    final belowMetal = _override && _taxable.text.trim().isNotEmpty && (_d(_taxable) * 100).round() < (line.metalValue * 100).round();
    final purities = _metal == 'Gold' ? _goldPurities : (_metal == 'Silver' ? _silverPurities : <String>[]);
    final chips = [...purities, if (_purity.isNotEmpty && !purities.contains(_purity) && _metal != 'Other') _purity];
    final hasStone = _extras.isNotEmpty;
    final gross = _d(_gross), net = _d(_net), stoneWt = BillingCalc.r3(_extras.fold<double>(0, (a, e) => a + e._d(e.weight)));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 6, 4),
          child: Row(children: [
            const Icon(Icons.diamond_outlined, color: _amber, size: 20),
            const SizedBox(width: 8),
            Text(_isNew ? 'Add item' : 'Edit item', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const Spacer(),
            IconButton(tooltip: 'Scan from stock', icon: const Icon(Icons.qr_code_scanner, color: _amber), onPressed: _scan),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => _changed(),
                style: const TextStyle(fontSize: 14),
                decoration: billDec('Item name *', _amber, hint: 'e.g. Gold Ring').copyWith(
                  suffixIcon: _code.isEmpty
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Chip(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            avatar: const Icon(Icons.qr_code_2, size: 14),
                            label: Text(_code, style: const TextStyle(fontSize: 11)),
                            onDeleted: () => setState(() {
                              _code = '';
                              _itemId = '';
                            }),
                          )),
                ),
              ),
              const SizedBox(height: 10),
              // metal + purity
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _metal,
                    isExpanded: true,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                    decoration: billDec('Metal', _amber),
                    items: [for (final m in const ['Gold', 'Silver', 'Other']) DropdownMenuItem(value: m, child: Text(m))],
                    onChanged: (v) {
                      if (v != null) _setMetal(v);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('purity-$_metal-$_purity'),
                    value: chips.contains(_purity) ? _purity : null,
                    isExpanded: true,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                    decoration: billDec('Purity', _amber),
                    items: [for (final p in chips) DropdownMenuItem(value: p, child: Text(p))],
                    onChanged: chips.isEmpty
                        ? null
                        : (v) => setState(() {
                              _purity = v ?? _purity;
                              _error = null;
                            }),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              // weights
              Row(children: [
                Expanded(child: _num(_gross, 'Gross wt (g)', onChanged: (_) => _changed(weights: true))),
                const SizedBox(width: 8),
                Expanded(
                  child: _num(_net, 'Net wt (g) *', onChanged: (_) {
                    _netTouched = true;
                    _changed();
                  }),
                ),
              ]),
              if (gross > 0 && (stoneWt > 0 || gross != net))
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 2),
                  child: Text('Gross ${grams(gross)} g − stones/other ${grams(stoneWt)} g = net ${grams(net)} g',
                      style: TextStyle(fontSize: 11, color: net > gross ? Colors.red.shade700 : Colors.black54)),
                ),
              const SizedBox(height: 10),
              // rate + making
              Row(children: [
                Expanded(
                  child: _num(_rate, 'Rate / g', prefix: '₹ ', onChanged: (_) {
                    _rateTouched = true;
                    _changed();
                  }),
                ),
                const SizedBox(width: 8),
                Expanded(child: Opacity(opacity: _override ? 0.45 : 1, child: IgnorePointer(ignoring: _override, child: _num(_making, _override ? 'Making (in taxable)' : 'Making charge', prefix: '₹ ', onChanged: (_) => _changed())))),
              ]),
              const SizedBox(height: 10),
              // HSN + hallmark / HUID
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: widget.hsnCodes.contains(_hsn) ? _hsn : null,
                    isExpanded: true,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                    decoration: billDec('HSN', _amber),
                    items: [for (final h in widget.hsnCodes) DropdownMenuItem(value: h, child: Text(h))],
                    onChanged: (v) => setState(() => _hsn = v ?? _hsn),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('cert-$_cert'),
                    value: _cert,
                    isExpanded: true,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                    decoration: billDec('Hallmark', const Color(0xFF0F766E)),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('None')),
                      DropdownMenuItem(value: 'hallmark', child: Text('Hallmarked')),
                      DropdownMenuItem(value: 'huid', child: Text('HUID')),
                    ],
                    onChanged: (v) => setState(() {
                      _cert = v ?? '';
                      _error = null;
                      _syncTaxable();
                    }),
                  ),
                ),
              ]),
              if (_cert.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(children: [
                  if (_cert == 'huid') ...[
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _huidCtl,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                          LengthLimitingTextInputFormatter(6),
                          TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toUpperCase())),
                        ],
                        onChanged: (_) => _changed(),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                        decoration: billDec('HUID code *', const Color(0xFF0F766E), hint: '6 characters'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(flex: 2, child: _num2(_hall, 'Hallmark charge', const Color(0xFF0F766E), (_) => _changed(), prefix: '₹ ')),
                ]),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 2),
                  child: Text('On the invoice: $shownName', style: const TextStyle(fontSize: 11.5, color: Color(0xFF0F766E), fontWeight: FontWeight.w600)),
                ),
              ],
              if (_cert.isEmpty && line.hiddenMaking)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 2),
                  child: Text('On the invoice: $shownName', style: const TextStyle(fontSize: 11.5, color: Color(0xFF0F766E), fontWeight: FontWeight.w600)),
                ),
              // stones / other metals
              const SizedBox(height: 8),
              if (!hasStone)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: const Color(0xFF7C3AED)),
                    onPressed: () => setState(() => _extras.add(_ExtraCtl(BillExtra()))),
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Stone / other metal'),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
                  decoration: BoxDecoration(color: const Color(0xFF7C3AED).withOpacity(0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.3))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7C3AED)),
                      const SizedBox(width: 6),
                      const Text('Stones / other metals', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF7C3AED))),
                      const Spacer(),
                      TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: const Color(0xFF7C3AED)),
                        onPressed: () => setState(() => _extras.add(_ExtraCtl(BillExtra()))),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add'),
                      ),
                    ]),
                    for (var i = 0; i < _extras.length; i++) _extraRow(i),
                  ]),
                ),
              // taxable
              const SizedBox(height: 12),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: _enableOverride,
                child: AbsorbPointer(
                  absorbing: !_override,
                  child: TextField(
                    controller: _taxable,
                    focusNode: _taxableFocus,
                    readOnly: !_override,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    onChanged: (_) => _changed(),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _override ? Colors.black87 : Colors.black54),
                    decoration: billDec('Taxable amount', _override ? Colors.red.shade700 : _amber, prefixText: '₹ ').copyWith(
                      fillColor: _override ? Colors.white : const Color(0xFFF6F1E7),
                      suffixIcon: _override
                          ? IconButton(tooltip: 'Back to calculated', icon: const Icon(Icons.restart_alt, size: 20), onPressed: _resetOverride)
                          : const Icon(Icons.edit_outlined, size: 17, color: Colors.black38),
                    ),
                  ),
                ),
              ),
              if (_override)
                Padding(
                  padding: const EdgeInsets.only(top: 3, left: 2),
                  child: Text(
                      belowMetal ? 'Cannot be below the metal value ${inr(line.metalValue)}' : 'Calculated ${inr(line.autoTaxable)} · metal ${inr(line.metalValue)}${shownName != _name.text.trim() && line.hiddenMaking ? ' · shows as "$shownName"' : ''}',
                      style: TextStyle(fontSize: 11, fontWeight: belowMetal ? FontWeight.w700 : FontWeight.w400, color: belowMetal ? Colors.red.shade700 : Colors.black54)),
                ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: _amber.withOpacity(0.07), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  if (widget.interstate)
                    _stat('IGST 3%', inr(line.igst))
                  else ...[
                    _stat('CGST 1.5%', inr(line.cgst)),
                    _stat('SGST 1.5%', inr(line.sgst)),
                  ],
                  _stat('Total', inr(line.total), bold: true, right: true),
                ]),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12.5, fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
        // actions
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(children: [
              if (_isNew)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46), foregroundColor: _amber, side: const BorderSide(color: _amber)),
                    onPressed: () {
                      final r = _finish(true);
                      if (r != null) Navigator.pop(context, r);
                    },
                    child: const Text('Add & next'),
                  ),
                ),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: _amber),
                  onPressed: () {
                    final r = _finish(false);
                    if (r != null) Navigator.pop(context, r);
                  },
                  icon: const Icon(Icons.check, size: 20),
                  label: Text(_isNew ? 'Add to bill' : 'Done', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _num(TextEditingController c, String label, {String? prefix, required ValueChanged<String> onChanged}) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14),
        decoration: billDec(label, _amber, prefixText: prefix),
      );

  Widget _stat(String label, String value, {bool bold = false, bool right = false}) => Expanded(
        child: Column(crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
          Text(value, style: TextStyle(fontSize: bold ? 15 : 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );

  Widget _extraRow(int i) {
    final e = _extras[i];
    const c = Color(0xFF7C3AED);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(children: [
        Row(children: [
          SizedBox(
            width: 104,
            child: DropdownButtonFormField<String>(
              value: e.kind,
              isExpanded: true,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              decoration: billDec('Type', c),
              items: [for (final k in _extraKinds) DropdownMenuItem(value: k, child: Text(k))],
              onChanged: (v) => setState(() => e.kind = v ?? e.kind),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: e.name, textCapitalization: TextCapitalization.words, onChanged: (_) => _changed(), style: const TextStyle(fontSize: 13.5), decoration: billDec('Name (Ruby, Silver...)', c))),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _num2(e.weight, 'Weight (g)', c, (_) => _changed(weights: true))),
          const SizedBox(width: 8),
          Expanded(child: _num2(e.amount, 'Value', c, (_) => _changed(), prefix: '₹ ')),
          IconButton(
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 20),
            onPressed: () {
              setState(() => _extras.removeAt(i).dispose());
              _changed(weights: true);
            },
          ),
        ]),
      ]),
    );
  }

  Widget _num2(TextEditingController c, String label, Color color, ValueChanged<String> onChanged, {String? prefix}) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13.5),
        decoration: billDec(label, color, prefixText: prefix),
      );
}
