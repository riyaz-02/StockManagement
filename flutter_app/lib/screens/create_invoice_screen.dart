import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';
import '../utils/bilingual.dart';
import '../utils/billing_calc.dart';
import '../utils/directory_validators.dart';
import '../widgets/bill_ui.dart';
import 'directory_add_screens.dart';
import 'invoice_item_sheet.dart';
import 'old_metal_screen.dart';

/// One idempotency key per invoice draft. If Save is tapped twice, or is
/// retried after a bad connection, the server returns the SAME invoice.
String _newRequestId() {
  final r = Random.secure();
  return 'inv-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-'
      '${List.generate(10, (_) => r.nextInt(36).toRadixString(36)).join()}';
}

String _s(dynamic v) => (v ?? '').toString();

const _blue = Color(0xFF2563EB);
const _amber = Color(0xFFD97706);
const _green = Color(0xFF16A34A);
const _indigo = Color(0xFF4F46E5);

/// One extra payment line when a bill is paid in more than one way (e.g. Cash + Online).
class _PayRow {
  _PayRow(this.mode, String amount) : amount = TextEditingController(text: amount);
  String mode;
  final TextEditingController amount;
}

/// Income Tax Act s.269ST: cash of Rs 2,00,000 OR MORE from one person in a day (all invoices together) is not allowed.
const double _kCashLimit = 200000;

/// CGST Rule 46(f): a bill of Rs 50,000 or more must carry the buyer's address.
const double _kAddressLimit = 50000;

/// Create a GST invoice in three steps: Customer -> Items -> Pay.
/// Most things are automatic: number, dates, rates, tax type (from the place
/// of supply), net weight, taxable amount and the amount received.
class CreateInvoiceScreen extends StatefulWidget {
  const CreateInvoiceScreen({super.key, this.initialItemCode, this.estimate, this.order});

  /// A made-to-order piece being delivered: its customer and description are filled in and its advance is credited on the bill.
  final Map<String, dynamic>? order;

  /// An estimate to make this invoice from: its customer, items, rates and discount are filled in (the price stays as quoted).
  final Map<String, dynamic>? estimate;

  /// Barcode of a stock piece to put on the bill straight away (the "Sell" button on a stock item).
  final String? initialItemCode;

  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> {
  static const _steps = [('Customer', Icons.person_outline), ('Items', Icons.diamond_outlined), ('Pay', Icons.payments_outlined)];
  static const _stepColors = [_blue, _amber, _green];
  static const _modes = [('Cash', Icons.payments_outlined), ('Card', Icons.credit_card), ('Online', Icons.smartphone), ('Cheque', Icons.receipt_outlined)];

  final _api = ApiService();
  final _pages = PageController();
  int _step = 0;
  bool _saving = false;
  bool _loading = true;
  String? _loadError;
  final String _requestId = _newRequestId();
  Map<String, dynamic> _meta = {};

  // ── customer ──
  bool _existing = true;
  Map<String, dynamic>? _customer;
  Map<String, dynamic>? _summary;
  final _search = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  Timer? _searchTimer;
  int _searchSeq = 0;
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _address = TextEditingController();
  List<Map<String, dynamic>> _mobileMatches = [];
  Timer? _mobileTimer;
  bool? _addChoice; // asked once: add this walk-in buyer to the customer list?

  // ── place of supply / extras ──
  String _place = '19-West Bengal';
  bool _placeTouched = false; // a hand-picked state stops following the customer
  final _pan = TextEditingController();
  final _reference = TextEditingController();
  String _terms = 'Customer Pickup';
  bool _reverse = false;
  DateTime _date = DateTime.now();
  DateTime? _delivery = DateTime.now();

  // ── items ──
  final _gold = TextEditingController();
  final _silver = TextEditingController();
  final List<BillItem> _items = [];

  // ── payment ──
  final _additional = TextEditingController();
  final _discount = TextEditingController();
  final _paid = TextEditingController();
  final _final = TextEditingController(); // what the customer will pay (payable); typing here sets the discount
  final _finalFocus = FocusNode();
  final _note = TextEditingController();
  String _mode = 'Cash';
  bool _paidTouched = false;
  final List<_PayRow> _extraPays = []; // more ways of paying the same bill
  double _cashToday = 0; // cash already received today from this customer (all invoices)

  @override
  void initState() {
    super.initState();
    _finalFocus.addListener(() {
      if (!_finalFocus.hasFocus && mounted) setState(_syncFinal);
    });
    _loadMeta();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _mobileTimer?.cancel();
    for (final c in [_pages, _search, _name, _mobile, _address, _pan, _reference, _gold, _silver, _additional, _discount, _paid, _final, _note]) {
      c.dispose();
    }
    _finalFocus.dispose();
    for (final r in _extraPays) {
      r.amount.dispose();
    }
    super.dispose();
  }

  /// Which billing counter this bill (and the payments on it) is filed under: one of the counters of this branch.
  Future<void> _pickCounter() async {
    final counters = ((_meta['counters'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (counters.isEmpty) return;
    final cur = _s((_meta['counter'] as Map?)?['counterId']);
    final pick = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 4), child: Align(alignment: Alignment.centerLeft, child: Text('Bill at which counter?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)))),
          for (final c in counters)
            ListTile(
              leading: Icon(_s(c['id']) == cur ? Icons.radio_button_checked : Icons.radio_button_off, color: const Color(0xFFE94560)),
              title: Text(_s(c['name'])),
              subtitle: _s(c['code']).isEmpty ? null : Text(_s(c['code'])),
              onTap: () => Navigator.pop(ctx, c),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (pick == null || !mounted) return;
    await Provider.of<AuthProvider>(context, listen: false).setActiveCounter(_s(pick['id']), _s(pick['name']));
    if (!mounted) return;
    setState(() => _meta = {..._meta, 'counter': {'counterId': _s(pick['id']), 'counterName': _s(pick['name']), 'counterCode': _s(pick['code'])}});
  }

  Future<void> _loadMeta() async {
    try {
      final res = await _api.billingMeta();
      final d = Map<String, dynamic>.from(res['data']);
      if (!mounted) return;
      setState(() {
        _meta = d;
        if ((d['goldRate'] ?? 0) > 0) _gold.text = _trim(d['goldRate']);
        if ((d['silverRate'] ?? 0) > 0) _silver.text = _trim(d['silverRate']);
        final tt = (d['termsOfDelivery'] as List?)?.map((e) => e.toString()).toList() ?? [];
        if (tt.isNotEmpty && !tt.contains(_terms)) _terms = tt.first;
        if (_s(d['defaultPlace']).isNotEmpty) _place = _s(d['defaultPlace']);
        _loading = false;
      });
      if ((widget.initialItemCode ?? '').isNotEmpty) _addInitialPiece();
      _applyEstimate();
      _applyOrder();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _applyEstimate() {
    final e = widget.estimate;
    if (e == null) return;
    setState(() {
      _existing = false;
      _name.text = _s(e['customerName']);
      _mobile.text = _s(e['customerMobile']);
      if (_d2(e['goldRate']) > 0) _gold.text = _trim(_d2(e['goldRate']));
      if (_d2(e['silverRate']) > 0) _silver.text = _trim(_d2(e['silverRate']));
      _items
        ..clear()
        ..addAll([for (final j in (e['inputItems'] as List? ?? const [])) BillItem.fromJson(Map<String, dynamic>.from(j as Map))]);
      if (_d2(e['discount']) > 0) _discount.text = _trim(_d2(e['discount']));
      _note.text = 'From estimate ${_s(e['number'])}';
      _syncPaid();
    });
  }

  double get _orderAdvance => widget.order == null ? 0 : (widget.order!['advancePaid'] is num ? (widget.order!['advancePaid'] as num).toDouble() : 0);

  void _applyOrder() {
    final o = widget.order;
    if (o == null) return;
    setState(() {
      _existing = false;
      _name.text = _s(o['customerName']);
      _mobile.text = _s(o['customerMobile']);
      final metal = _s(o['metalType']).toLowerCase() == 'silver' ? 'Silver' : 'Gold';
      _items
        ..clear()
        ..add(BillItem(particular: _s(o['description']).split('\n').first, metal: metal, purity: _s(o['purity'])));
      _note.text = 'Order ${_s(o['number'])}';
      _syncPaid();
    });
    _toast('Tap the item and enter the final weight and making charge of the finished piece.', error: false);
  }

  double _d2(dynamic v) => v is num ? v.toDouble() : double.tryParse(_s(v)) ?? 0;

  String _trim(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  double _d(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;
  String get _lang => context.read<LanguageProvider>().currentLanguage;
  bool get _walkIn => !_existing || _customer == null;

  String get _placeCode => _place.split('-').first;
  String get _placeName => _place.contains('-') ? _place.substring(_place.indexOf('-') + 1) : _place;
  bool get _interstate => _placeCode != _s(_meta['supplyStateCode'] ?? '19');
  List<String> get _hsnCodes {
    final l = ((_meta['hsnCodes'] as List?) ?? const ['7113']).map((h) => (h is Map ? h['code'] : h).toString()).toList();
    return l.isEmpty ? ['7113'] : l;
  }

  BillTotals _totals() => BillingCalc.compute(
        items: _items,
        goldRate: _d(_gold),
        silverRate: _d(_silver),
        additional: _d(_additional),
        discount: _d(_discount),
        paid: _paidTotal(),
        interstate: _interstate,
      );

  // ── old metal received from this customer, adjusted against the bill ──
  List<Map<String, dynamic>> _omAvail = [];
  final Set<String> _omSel = {};

  double get _omTotal => _omAvail.where((e) => _omSel.contains('${e['_id']}')).fold<double>(0, (a, e) => a + ((e['amount'] as num?)?.toDouble() ?? 0));

  Future<void> _loadOldMetal({bool keep = true}) async {
    try {
      final r = await _api.oldMetalAvailable(customerId: _walkIn ? '' : _s(_customer?['id']), mobile: _walkIn ? DV.normalizePhone(_mobile.text) : '', name: _walkIn ? _name.text.trim() : _s(_customer?['name']));
      if (!mounted) return;
      final list = (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() {
        _omAvail = list;
        _omSel.removeWhere((id) => !list.any((e) => '${e['_id']}' == id));
      });
    } catch (_) {/* the card just stays empty */}
  }

  Future<void> _receiveOldMetal() async {
    final entry = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => OldMetalFormScreen(kind: 'old', presetName: _walkIn ? _name.text.trim() : _s(_customer?['name']), presetMobile: _walkIn ? DV.normalizePhone(_mobile.text) : '', presetCustomerId: _walkIn ? '' : _s(_customer?['id']), returnEntry: true)),
    );
    if (entry == null || !mounted) return;
    await _loadOldMetal();
    if (!mounted) return;
    setState(() {
      _omSel.add('${entry['_id']}');
      _paidTouched = false;
      _syncPaid();
    });
  }

  double get _extraPaid => _extraPays.fold<double>(0, (a, r) => a + (double.tryParse(r.amount.text.trim()) ?? 0));
  double _paidTotal() => _d(_paid) + _extraPaid + _omTotal + _orderAdvance;

  /// Cash typed across all payment lines.
  double _cashNow() =>
      (_mode == 'Cash' ? _d(_paid) : 0.0) + _extraPays.where((r) => r.mode == 'Cash').fold<double>(0, (a, r) => a + (double.tryParse(r.amount.text.trim()) ?? 0));

  /// The most cash (whole rupees) that can still be taken today from this customer.
  int get _cashRoom => (_kCashLimit - 0.01 - _cashToday).floor().clamp(0, 1 << 30);

  void _toast(String m, {bool error = true}) => showAppSnackBar(
      context,
      SnackBar(content: Text(m, style: const TextStyle(fontSize: 13)), backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700, duration: const Duration(seconds: 3)));

  // Paid follows the payable amount until the user types their own figure.
  void _syncFinal() {
    if (_finalFocus.hasFocus) return;
    final t = _totals();
    _final.text = t.payable == 0 ? '' : t.payable.toStringAsFixed(0);
  }

  // The bill with no discount: the base for "final amount" and "round to", and the lowest price allowed.
  BillTotals _t0() =>
      BillingCalc.compute(items: _items, goldRate: _d(_gold), silverRate: _d(_silver), additional: _d(_additional), discount: 0, interstate: _interstate);

  void _onFinalChanged(String v) {
    final f = double.tryParse(v.trim());
    final t0 = _t0();
    setState(() {
      var d = f == null ? 0.0 : t0.billBeforeDiscount - f;
      if (d > t0.maxDiscount) d = t0.maxDiscount; // never below metal + stones + hallmark
      _discount.text = d > 0 ? d.toStringAsFixed(0) : '';
      _syncPaid();
    });
  }

  void _roundTo(int m) {
    final t0 = _t0();
    final before = t0.billBeforeDiscount;
    final lowest = before - t0.maxDiscount;
    var target = (before / m).floorToDouble() * m;
    if (target < lowest) target = (lowest / m).ceilToDouble() * m; // the nearest round figure the price allows
    if (target <= 0 || target >= before) {
      _toast(t0.maxDiscount > 0 ? 'Cannot round further: lowest price is ${inr(lowest)}' : 'No discount possible on this bill', error: false);
      return;
    }
    setState(() {
      _discount.text = (before - target).toStringAsFixed(0);
      _syncPaid();
    });
  }

  void _syncPaid() {
    _syncFinal();
    if (_paidTouched) return;
    final t = _totals();
    final v = t.payable - _extraPaid - _omTotal - _orderAdvance;
    // with old metal adjusted the cash is the exact remainder (paise), otherwise whole rupees as before
    _paid.text = t.payable == 0 || v <= 0 ? '' : (_omTotal + _orderAdvance > 0 ? v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '') : v.toStringAsFixed(0));
  }

  // ─────────────────────────────── customer ────────────────────────────────
  void _onSearch(String v) {
    _searchTimer?.cancel();
    final q = v.trim();
    if (q.length < 2 && DV.digits(q).length < 4) {
      setState(() => _results = []);
      return;
    }
    _searchTimer = Timer(const Duration(milliseconds: 350), () async {
      final seq = ++_searchSeq;
      try {
        final res = await _api.lookupCustomers(q);
        if (!mounted || seq != _searchSeq) return;
        setState(() => _results = List<Map<String, dynamic>>.from((res['data'] as List).map((e) => Map<String, dynamic>.from(e))));
      } catch (_) {}
    });
  }

  Future<void> _pickCustomer(Map<String, dynamic> c) async {
    setState(() {
      _customer = c;
      _results = [];
      _search.clear();
      _summary = null;
      _paidTouched = false;
      _cashToday = 0;
    });
    try {
      final res = await _api.billingCustomerSummary(_s(c['id']));
      if (!mounted) return;
      final sm = Map<String, dynamic>.from(res['data']);
      setState(() {
        _summary = sm;
        _cashToday = ((sm['cashToday'] ?? 0) as num).toDouble();
        if (_address.text.trim().isEmpty && _s(sm['address']).isNotEmpty) _address.text = _s(sm['address']); // saved address, editable on the Pay step
        // the customer's own state decides the tax type, unless staff picked a state by hand
        if (!_placeTouched && _s(sm['place']).isNotEmpty) _place = _s(sm['place']);
      });
    } catch (_) {/* a convenience; the server checks again on save */}
  }

  void _onMobileChanged(String v) {
    _addChoice = null;
    _mobileTimer?.cancel();
    final d = DV.normalizePhone(v);
    if (d.length < 10) {
      if (_mobileMatches.isNotEmpty) setState(() => _mobileMatches = []);
      return;
    }
    _mobileTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final res = await _api.lookupCustomers(d);
        if (!mounted) return;
        setState(() => _mobileMatches = List<Map<String, dynamic>>.from((res['data'] as List).map((e) => Map<String, dynamic>.from(e))).where((m) => m['exact'] == true).toList());
      } catch (_) {}
    });
  }

  /// Step 1 -> 2. A buyer who is not in the customer list: ask once whether to
  /// add them (YES creates the customer, NO keeps a walk-in bill).
  Future<bool> _finishCustomerStep() async {
    if (_existing) {
      if (_customer == null) {
        _toast('Choose a customer');
        return false;
      }
      return true;
    }
    final name = _name.text.trim();
    if (name.length < 2) {
      _toast('Enter the buyer\'s name');
      return false;
    }
    final mobileErr = DV.mobile(_mobile.text, required: false);
    if (mobileErr != null) {
      _toast(mobileErr);
      return false;
    }
    final mobile = DV.normalizePhone(_mobile.text);

    if (_mobileMatches.isNotEmpty) {
      final m = _mobileMatches.first;
      final use = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Already a customer', style: TextStyle(fontSize: 16)),
          content: Text('${bilingualName(_s(m['name']), _s(m['nameBn']), _lang)} (${_s(m['code'])}) uses this number.\nBill them instead?', style: const TextStyle(fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, use them')),
          ],
        ),
      );
      if (use == true) {
        setState(() => _existing = true);
        await _pickCustomer(m);
        return true;
      }
      _addChoice = false;
    }

    final canAdd = context.read<AuthProvider>().can('directory.create');
    if (_addChoice == null && mobile.isNotEmpty && canAdd) {
      final add = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Add to customer list?', style: TextStyle(fontSize: 16)),
          content: Text('$name is not in your customer list. Add them to keep their bills and dues?', style: const TextStyle(fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No, walk-in')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, add')),
          ],
        ),
      );
      if (add == null) return false;
      _addChoice = add;
      if (add) return _createCustomerNow(name, mobile);
    }
    return true;
  }

  /// The full customer form (numbers, Bengali, duplicates ...), then bill the customer that was just saved.
  Future<void> _addCustomerForm() async {
    final typed = _search.text.trim();
    final isNumber = RegExp(r'^[\d\s+()-]+$').hasMatch(typed);
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddCustomerScreen(prefillName: isNumber ? '' : typed, prefillNumber: isNumber ? typed : '')),
    );
    final d = AddCustomerScreen.lastCreated;
    if (saved != true || d == null || !mounted) return;
    final profile = d['profile'] is Map ? Map<String, dynamic>.from(d['profile'] as Map) : <String, dynamic>{};
    final contacts = (profile['contacts'] as List?) ?? const [];
    await _pickCustomer({
      'id': _s(d['_id']),
      'name': _s(d['customer_name']),
      'nameBn': _s(d['customer_name_bengali']),
      'code': profile['customerCode'],
      'phones': [for (final c in contacts) _s((c as Map)['number'])],
    });
    _search.clear();
    _results = [];
  }

  Future<bool> _createCustomerNow(String name, String mobile) async {
    try {
      final res = await _api.createDirectoryRecord('customers', {
        'name': name,
        'contacts': [
          {'number': mobile, 'label': 'whatsapp'}
        ],
        'address': _address.text.trim(),
        if (_placeName.isNotEmpty && _placeTouched) 'state': _placeName,
      });
      if (res['success'] == true) {
        final d = Map<String, dynamic>.from(res['data']);
        final profile = d['profile'] is Map ? Map<String, dynamic>.from(d['profile']) : <String, dynamic>{};
        setState(() => _existing = true);
        await _pickCustomer({'id': _s(d['_id']), 'name': name, 'nameBn': '', 'code': profile['customerCode'], 'phones': [mobile]});
        _toast('$name added', error: false);
        return true;
      }
      _toast(_s(res['message']).isEmpty ? 'Could not add the customer' : _s(res['message']));
      _addChoice = false;
      return true; // continue as a walk-in rather than lose the bill
    } catch (e) {
      _toast('Could not add the customer. Continuing as walk-in.');
      _addChoice = false;
      return true;
    }
  }

  // ─────────────────────────────── place of supply ─────────────────────────
  Future<void> _pickPlace() async {
    final states = ((_meta['states'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e)).toList();
    if (states.isEmpty) return;
    final home = _s(_meta['defaultPlace']);
    states.sort((a, b) {
      if (_s(a['place']) == home) return -1;
      if (_s(b['place']) == home) return 1;
      return _s(a['name']).compareTo(_s(b['name']));
    });
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => _StatePicker(states: states, current: _place, supplyCode: _s(_meta['supplyStateCode'] ?? '19')),
    );
    if (picked != null && mounted) {
      setState(() {
        _place = picked;
        _placeTouched = true;
        _syncPaid();
      });
    }
  }

  // ─────────────────────────────── items ───────────────────────────────────
  Future<void> _openItem({int? index, BillItem? seed}) async {
    var current = index != null ? _items[index] : seed;
    while (true) {
      final r = await showItemSheet(
        context,
        item: current,
        goldRate: _d(_gold),
        silverRate: _d(_silver),
        interstate: _interstate,
        hsnCodes: _hsnCodes,
        takenCodes: [for (final i in _items) if (i.productCode.isNotEmpty) i.productCode],
      );
      if (r == null || !mounted) return;
      setState(() {
        if (index != null) {
          _items[index] = r.item;
        } else {
          _items.add(r.item);
        }
        _syncPaid();
      });
      if (!r.addNext || index != null) return;
      current = null;
    }
  }

  Future<void> _addInitialPiece() async {
    final piece = await lookupStockItem(context, widget.initialItemCode!, goldRate: _d(_gold), silverRate: _d(_silver));
    if (piece == null || !mounted) return;
    await _openItem(seed: piece); // staff confirms the price
  }

  Future<void> _scanItem() async {
    final scanned = await scanStockItem(context, taken: [for (final i in _items) if (i.productCode.isNotEmpty) i.productCode], goldRate: _d(_gold), silverRate: _d(_silver));
    if (scanned == null || !mounted) return;
    await _openItem(seed: scanned); // staff adds the making charge and confirms
  }

  void _removeItem(int i) {
    final removed = _items[i];
    setState(() {
      _items.removeAt(i);
      _syncPaid();
    });
    showAppSnackBar(
      context,
      SnackBar(
        content: Text('${removed.displayName} removed', style: const TextStyle(fontSize: 13)),
        action: SnackBarAction(
            label: 'Undo',
            onPressed: () => setState(() {
                  _items.insert(min(i, _items.length), removed);
                  _syncPaid();
                })),
      ),
    );
  }

  // ─────────────────────────────── navigation ───────────────────────────────
  String? _validatePay() {
    final t = _totals();
    if (_walkIn && (t.due > 0 || t.advance > 0)) return 'Walk-in bills must be paid in full';
    if (t.discountError != null) return t.discountError;
    if (t.payable >= _kAddressLimit && _address.text.trim().length < 5) return "Enter the buyer's address (needed on a bill of ₹50,000 or more)";
    if (_cashNow() > _cashRoom + 0.001) {
      return _cashRoom > 0
          ? 'Cash limit (s.269ST): at most ${inr(_cashRoom)} can be taken in cash from this customer today. Use Split payment.'
          : 'Cash limit (s.269ST): no more cash can be taken from this customer today. Pay by Card, Online or Cheque.';
    }
    for (final r in _extraPays) {
      if ((double.tryParse(r.amount.text.trim()) ?? 0) < 0) return 'Payment amount cannot be negative';
    }
    if (t.tdsApplicable && !RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(_pan.text.trim().toUpperCase())) return 'Enter the customer PAN (bill is above ₹2,00,000)';
    return null;
  }

  Future<void> _next() async {
    FocusScope.of(context).unfocus();
    if (_step == 0) {
      if (!await _finishCustomerStep()) return;
    } else if (_step == 1) {
      final err = BillingCalc.validateItems(_items, goldRate: _d(_gold), silverRate: _d(_silver));
      if (err != null) {
        _toast(err);
        return;
      }
    } else {
      final err = _validatePay();
      if (err != null) {
        _toast(err);
        return;
      }
      await _save();
      return;
    }
    setState(() => _step++);
    if (_step == 2) {
      setState(_syncPaid);
      _loadCash();
      _loadOldMetal().then((_) {
        if (mounted) setState(_syncPaid);
      });
    }
    _pages.animateToPage(_step, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
  }

  void _goTo(int i) {
    if (i >= _step) return; // going forward always passes the checks in _next()
    FocusScope.of(context).unfocus();
    setState(() => _step = i);
    _pages.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
  }

  bool get _dirty => _customer != null || _name.text.isNotEmpty || _items.isNotEmpty;

  Future<bool> _confirmLeave() async {
    if (!_dirty || _saving) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this invoice?', style: TextStyle(fontSize: 16)),
        content: const Text('Nothing has been saved yet.', style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return leave == true;
  }

  // ─────────────────────────────── save ───────────────────────────────────
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final t = _totals();
      final body = <String, dynamic>{
        'requestId': _requestId,
        if (_s((_meta['counter'] as Map?)?['counterId']).isNotEmpty) 'counterId': _s((_meta['counter'] as Map?)?['counterId']),
        if (!_walkIn) 'customerId': _s(_customer!['id']) else ...{'customerName': _name.text.trim(), 'customerMobile': DV.normalizePhone(_mobile.text)},
        'customerAddress': _address.text.trim(),
        if (_pan.text.trim().isNotEmpty) 'customerPan': _pan.text.trim().toUpperCase(),
        'placeOfSupply': _place,
        'reverseCharge': _reverse ? 'Yes' : 'No',
        'termsOfDelivery': _terms,
        if (_reference.text.trim().isNotEmpty) 'reference': _reference.text.trim(),
        'invoiceDate': DateFormat('yyyy-MM-dd').format(_date),
        if (_delivery != null) 'deliveryDate': DateFormat('yyyy-MM-dd').format(_delivery!),
        'goldRate': _d(_gold),
        'silverRate': _d(_silver),
        'items': _items.map((i) => i.toJson()).toList(),
        'additionalCharges': t.additional,
        'discount': t.discount,
        'paidAmount': t.paid,
        'paymentMode': _mode,
        'payments': [
          if (_d(_paid) > 0) {'mode': _mode, 'amount': _d(_paid)},
          for (final r in _extraPays)
            if ((double.tryParse(r.amount.text.trim()) ?? 0) > 0) {'mode': r.mode, 'amount': double.parse(r.amount.text.trim())},
        ],
        'note': _note.text.trim(),
        'description': _note.text.trim(),
        if (_omSel.isNotEmpty) 'oldMetalIds': _omSel.toList(),
        if (widget.order != null) 'orderId': _s(widget.order!['id']),
      };
      final res = await _api.billingCreate(body);
      if (!mounted) return;
      if (res['success'] == true) {
        if (res['warning'] != null) _toast(_s(res['warning']), error: false);
        if (widget.estimate != null) {
          try {
            await _api.estimateConverted(_s(widget.estimate!['id']), _s((res['data'] as Map)['invoiceNumber']));
          } catch (_) {/* the invoice is saved; the estimate can be closed by hand */}
        }
        Navigator.pop(context, _s((res['data'] as Map)['_id'])); // the list opens the saved invoice
        return;
      }
      _toast(_s(res['message']).isEmpty ? 'Could not save the invoice' : _s(res['message']));
    } catch (e) {
      // Same request id on the retry: the server will not bill twice.
      if (mounted) _toast('Connection problem. Tap Save again: no duplicate bill will be made.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─────────────────────────────── build ──────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final color = _stepColors[_step];
    return WillPopScope(
      onWillPop: _confirmLeave,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F5F8),
        appBar: AppBar(
          elevation: 0,
          centerTitle: false,
          titleSpacing: 0,
          toolbarHeight: 46,
          backgroundColor: const Color(0xFFF4F5F8),
          foregroundColor: const Color(0xFF1A1A1A),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('New GST Invoice', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            if (_meta['nextInvoiceNumber'] != null)
              InkWell(
                onTap: (_meta['counters'] as List?)?.isNotEmpty == true ? _pickCounter : null,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('No. ${_meta['nextInvoiceNumber']} · ${_s((_meta['branch'] as Map?)?['branchName'])}', style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w500)),
                  if ((_meta['counters'] as List?)?.isNotEmpty == true) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(color: const Color(0xFFFDE8EC), borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.point_of_sale_rounded, size: 11, color: Color(0xFFE94560)),
                        const SizedBox(width: 3),
                        Text(_s((_meta['counter'] as Map?)?['counterName']).isEmpty ? 'Pick counter' : _s((_meta['counter'] as Map?)?['counterName']), style: const TextStyle(fontSize: 11, color: Color(0xFFE94560), fontWeight: FontWeight.w700)),
                        const Icon(Icons.arrow_drop_down, size: 14, color: Color(0xFFE94560)),
                      ]),
                    ),
                  ],
                ]),
              ),
          ]),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_loadError!, style: const TextStyle(color: Colors.red))))
                : Column(children: [
                    _stepper(),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: PageView(controller: _pages, physics: const NeverScrollableScrollPhysics(), children: [_customerStep(), _itemsStep(), _payStep()]),
                        ),
                      ),
                    ),
                    _bottomBar(color),
                  ]),
      ),
    );
  }

  Widget _stepper() => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: Row(children: [
          for (var i = 0; i < _steps.length; i++) ...[
            if (i > 0) Expanded(child: Container(height: 2, color: i <= _step ? _stepColors[i] : Colors.black12)),
            InkWell(
              onTap: () => _goTo(i),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: i <= _step ? _stepColors[i] : Colors.black12,
                    child: i < _step ? const Icon(Icons.check, size: 16, color: Colors.white) : Icon(_steps[i].$2, size: 16, color: i <= _step ? Colors.white : Colors.black45),
                  ),
                  const SizedBox(height: 2),
                  Text(_steps[i].$1, style: TextStyle(fontSize: 10.5, fontWeight: i == _step ? FontWeight.w800 : FontWeight.w500, color: i == _step ? _stepColors[i] : Colors.black45)),
                ]),
              ),
            ),
          ],
        ]),
      );

  Widget _bottomBar(Color color) {
    final t = _totals();
    final last = _step == 2;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.black12))),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Row(children: [
              if (_step > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 46), padding: EdgeInsets.zero, foregroundColor: color, side: BorderSide(color: color), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: _saving ? null : () => _goTo(_step - 1),
                    child: const Icon(Icons.arrow_back, size: 18),
                  ),
                ),
              if (_step >= 1)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text('${_items.length} item${_items.length == 1 ? '' : 's'}', style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
                      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(inr(t.payable), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                    ]),
                  ),
                ),
              _step == 0 ? Expanded(child: _navButton(color, last)) : SizedBox(width: last ? 148 : 112, child: _navButton(color, last)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _navButton(Color color, bool last) => FilledButton.icon(
        style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(46), padding: const EdgeInsets.symmetric(horizontal: 8), backgroundColor: color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        onPressed: _saving ? null : _next,
        icon: _saving
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(last ? Icons.check_circle_outline : Icons.arrow_forward, size: 19),
        label: Text(_saving ? 'Saving…' : (last ? 'Save invoice' : 'Next'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      );

  // ─────────────────────────────── step 1: customer ────────────────────────
  Widget _customerStep() {
    return ListView(padding: const EdgeInsets.fromLTRB(10, 10, 10, 16), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
      BillCard(
        title: 'Buyer',
        icon: Icons.person_search_outlined,
        color: _blue,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SegmentedButton<bool>(
            style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, label: Text('Customer'), icon: Icon(Icons.people_alt_outlined, size: 17)),
              ButtonSegment(value: false, label: Text('New buyer'), icon: Icon(Icons.person_add_alt_outlined, size: 17)),
            ],
            selected: {_existing},
            onSelectionChanged: (s) => setState(() {
              _existing = s.first;
              _paidTouched = false;
              if (!_existing) _summary = null;
            }),
          ),
          const SizedBox(height: 12),
          if (_existing) ..._existingCustomerUi() else ..._newCustomerUi(),
        ]),
      ),
      _moreOptions(),
    ]);
  }

  // Looks like every other field; the tax type is only a small hint underneath.
  Widget _placeField() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _pickPlace,
          child: InputDecorator(
            decoration: billDec('Place of supply', _blue, suffix: const Icon(Icons.expand_more, size: 20)),
            child: Text('$_placeName ($_placeCode)', style: const TextStyle(fontSize: 13.5)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 3),
          child: Text(_interstate ? 'Other state: IGST 3%' : 'Same state: CGST + SGST', style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ),
      ]);

  Widget _moreOptions() => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.black12)),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: const Icon(Icons.tune, size: 20, color: Colors.black54),
            title: const Text('More', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            initiallyExpanded: true,
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              const SizedBox(height: 10), // room for the floating labels
              _placeField(),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _dateBox('Invoice date', _date, (d) => setState(() => _date = d!), required: true, notFuture: true)),
                const SizedBox(width: 8),
                Expanded(child: _dateBox('Delivery', _delivery, (d) => setState(() => _delivery = d))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _terms,
                    isExpanded: true,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                    decoration: billDec('Delivery terms', _blue),
                    items: [for (final t in ((_meta['termsOfDelivery'] as List?) ?? ['Customer Pickup'])) DropdownMenuItem(value: t.toString(), child: Text(t.toString(), overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => setState(() => _terms = v ?? _terms),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _reference, style: const TextStyle(fontSize: 13.5), decoration: billDec('Reference', _blue))),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _pan,
                textCapitalization: TextCapitalization.characters,
                maxLength: 10,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 13.5),
                decoration: billDec('Customer PAN', _blue),
              ),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Reverse charge', style: TextStyle(fontSize: 13)), value: _reverse, onChanged: (v) => setState(() => _reverse = v)),
            ],
          ),
        ),
      );

  List<Widget> _existingCustomerUi() {
    if (_customer != null) {
      final m = _customer!;
      final due = ((_summary?['totalDue'] ?? 0) as num).toDouble();
      return [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: _blue.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: _blue.withOpacity(0.3))),
          child: Row(children: [
            CircleAvatar(radius: 17, backgroundColor: _blue.withOpacity(0.15), foregroundColor: _blue, child: const Icon(Icons.person, size: 19)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(bilingualName(_s(m['name']), _s(m['nameBn']), _lang), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                Text([_s(m['code']), ((m['phones'] as List?) ?? []).isNotEmpty ? _s((m['phones'] as List).first) : ''].where((e) => e.isNotEmpty).join('  ·  '), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                if (due > 0) Padding(padding: const EdgeInsets.only(top: 3), child: StatusPill('Owes ${inr(due)}', Colors.red.shade700)),
              ]),
            ),
            IconButton(
                tooltip: 'Change',
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => setState(() {
                      _customer = null;
                      _summary = null;
                    })),
          ]),
        ),
      ];
    }
    return [
      TextField(
        controller: _search,
        onChanged: _onSearch,
        style: const TextStyle(fontSize: 14),
        decoration: billDec('Name, mobile or ID', _blue, suffix: const Icon(Icons.search, size: 19)),
      ),
      for (final m in _results)
        InkWell(
          onTap: () => _pickCustomer(m),
          child: Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black12)),
            child: Row(children: [
              const Icon(Icons.person_outline, size: 19, color: _blue),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(bilingualName(_s(m['name']), _s(m['nameBn']), _lang), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  Text([_s(m['code']), ((m['phones'] as List?) ?? []).isNotEmpty ? _s((m['phones'] as List).first) : ''].where((e) => e.isNotEmpty).join('  ·  '), style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                ]),
              ),
            ]),
          ),
        ),
      if (context.read<AuthProvider>().can('directory.create'))
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: TextButton.icon(onPressed: _addCustomerForm, icon: const Icon(Icons.person_add_alt_1_outlined, size: 18), label: const Text('New customer')),
        ),
      if (_results.isEmpty && _search.text.trim().length >= 2)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: TextButton.icon(onPressed: () => setState(() => _existing = false), icon: const Icon(Icons.person_outline, size: 18), label: const Text('Not found: bill a new buyer (walk-in)')),
        ),
    ];
  }

  List<Widget> _newCustomerUi() => [
        TextField(controller: _name, textCapitalization: TextCapitalization.words, onChanged: (_) => _addChoice = null, style: const TextStyle(fontSize: 14), decoration: billDec('Name *', _blue)),
        const SizedBox(height: 8),
        TextField(
          controller: _mobile,
          keyboardType: TextInputType.phone,
          inputFormatters: [PhoneInputFormatter()],
          onChanged: _onMobileChanged,
          style: const TextStyle(fontSize: 14),
          decoration: billDec('Mobile', _blue),
        ),
        if (_mobileMatches.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.red.withOpacity(0.07), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade300)),
            child: Row(children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: Colors.red.shade700),
              const SizedBox(width: 8),
              Expanded(child: Text('Already: ${bilingualName(_s(_mobileMatches.first['name']), _s(_mobileMatches.first['nameBn']), _lang)}', style: const TextStyle(fontSize: 12.5))),
              TextButton(
                  onPressed: () async {
                    final m = _mobileMatches.first;
                    setState(() => _existing = true);
                    await _pickCustomer(m);
                  },
                  child: const Text('Use')),
            ]),
          ),
        const SizedBox(height: 8),
        TextField(controller: _address, style: const TextStyle(fontSize: 14), decoration: billDec('Address', _blue)),
      ];

  // notFuture: the invoice date can be today or an earlier day (the server refuses a future bill date)
  Widget _dateBox(String label, DateTime? v, ValueChanged<DateTime?> onPick, {bool required = false, bool notFuture = false}) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final now = DateTime.now();
          final last = notFuture ? DateTime(now.year, now.month, now.day) : DateTime(2100);
          final d = await showDatePicker(context: context, initialDate: (v != null && v.isAfter(last)) ? last : (v ?? now), firstDate: DateTime(2020), lastDate: last);
          if (d != null) onPick(d);
        },
        child: InputDecorator(
          decoration: billDec(label, _blue, suffix: const Icon(Icons.calendar_today, size: 15)),
          child: Text(v == null ? (required ? 'Select' : '—') : DateFormat('dd MMM yyyy').format(v), style: TextStyle(fontSize: 13.5, color: v == null ? Colors.black45 : Colors.black87)),
        ),
      );

  // ─────────────────────────────── step 2: items ───────────────────────────
  Widget _itemsStep() {
    final t = _totals();
    return Column(children: [
      // metal rates (filled from the last invoice)
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: Row(children: [
          Expanded(child: _rateField(_gold, 'Gold ₹/g', const Color(0xFFD4A017))),
          const SizedBox(width: 8),
          Expanded(child: _rateField(_silver, 'Silver ₹/g', const Color(0xFF64748B))),
        ]),
      ),
      Expanded(
        child: _items.isEmpty
            ? _emptyItems()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                itemCount: _items.length,
                itemBuilder: (_, i) => _itemTile(i, t),
              ),
      ),
      // add / scan: a floating capsule, deliberately unlike the Back / Next bar underneath
      Container(
        margin: const EdgeInsets.fromLTRB(14, 4, 14, 10),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: _amber.withOpacity(0.35)),
          boxShadow: [BoxShadow(color: _amber.withOpacity(0.22), blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: Row(children: [
          Expanded(
            child: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44), foregroundColor: const Color(0xFF9A5B00), backgroundColor: _amber.withOpacity(0.12), shape: const StadiumBorder()),
              onPressed: _scanItem,
              icon: const Icon(Icons.qr_code_scanner, size: 20),
              label: const Text('Scan', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44), backgroundColor: const Color(0xFF1F2937), shape: const StadiumBorder()),
              onPressed: () => _openItem(),
              icon: const Icon(Icons.add_circle_outline, size: 21),
              label: const Text('Add item', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _rateField(TextEditingController c, String label, Color color) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        onChanged: (_) => setState(_syncPaid),
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        decoration: billDec(label, color, prefixText: '₹ '),
      );

  Widget _emptyItems() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.diamond_outlined, size: 54, color: _amber.withOpacity(0.45)),
            const SizedBox(height: 10),
            const Text('No items yet', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black54)),
            const SizedBox(height: 2),
            const Text('Scan a tag or add by hand', style: TextStyle(fontSize: 12.5, color: Colors.black45)),
          ]),
        ),
      );

  Widget _itemTile(int i, BillTotals t) {
    final it = _items[i];
    final line = t.lines[i];
    final metalColor = it.metal == 'Gold' ? const Color(0xFFD4A017) : (it.metal == 'Silver' ? const Color(0xFF94A3B8) : const Color(0xFF7C3AED));
    Widget tag(String text, {Color? c, IconData? icon}) => Container(
          margin: const EdgeInsets.only(right: 5, top: 3),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(color: (c ?? Colors.black54).withOpacity(0.10), borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 11, color: c ?? Colors.black54), const SizedBox(width: 3)],
            Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: c ?? Colors.black54)),
          ]),
        );
    final stones = it.extras.where((e) => !e.isEmpty).toList();
    return Dismissible(
      key: ObjectKey(it),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.only(right: 18),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(color: Colors.red.shade400, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _removeItem(i),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12), boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))]),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openItem(index: i),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 5, decoration: BoxDecoration(color: metalColor, borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)))),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(line.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('${grams(it.netWt)} g${it.grossWt > 0 && it.grossWt != it.netWt ? ' (gross ${grams(it.grossWt)})' : ''} × ${inr(line.rate)}${it.making > 0 ? ' + ${inr(it.making)}' : ''}',
                            style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                        Wrap(children: [
                          if (it.purity.isNotEmpty) tag(it.purity, c: const Color(0xFFB45309)),
                          if (it.productCode.isNotEmpty) tag(it.productCode, icon: Icons.qr_code_2),
                          if (it.certification.isNotEmpty && it.hallmarkCharge > 0) tag('Hallmark ${inr(it.hallmarkCharge)} · no GST', c: const Color(0xFF0F766E), icon: Icons.verified_outlined),
                          for (final e in stones) tag('${e.name.isEmpty ? e.kind : e.name}${e.amount > 0 ? ' ${inr(e.amount)}' : ''}', c: const Color(0xFF7C3AED), icon: Icons.auto_awesome),
                          if (it.taxableOverride != null) tag('edited', c: Colors.red.shade700, icon: Icons.edit_outlined),
                        ]),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(inr(line.total), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                      Text('tax ${inr(line.cgst + line.sgst + line.igst)}', style: const TextStyle(fontSize: 10.5, color: Colors.black45)),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────── step 3: pay ─────────────────────────────
  Widget _oldMetalCard(BillTotals t) {
    const amber = Color(0xFFD97706);
    if (!context.read<AuthProvider>().can('oldMetal.create') && _omAvail.isEmpty) return const SizedBox.shrink();
    return BillCard(
      title: 'Old metal from the customer',
      icon: Icons.recycling_rounded,
      color: amber,
      trailing: _omSel.isEmpty ? null : StatusPill('- ${inr(_omTotal)}', amber),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_omAvail.isEmpty) const Text('No unused old metal for this customer.', style: TextStyle(fontSize: 12, color: Colors.black54)),
        for (final e in _omAvail)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _omSel.contains('${e['_id']}'),
            onChanged: (v) => setState(() {
              v == true ? _omSel.add('${e['_id']}') : _omSel.remove('${e['_id']}');
              _paidTouched = false;
              _syncPaid();
            }),
            title: Text('${e['metalType']} ${e['purity']}  ·  net ${e['net']} g  ·  fine ${e['fine']} g', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            subtitle: Text('${inr((e['amount'] as num).toDouble())}  ·  ${'${e['date']}'.split('T').first}', style: const TextStyle(fontSize: 11.5)),
          ),
        if (context.read<AuthProvider>().can('oldMetal.create'))
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _receiveOldMetal, icon: const Icon(Icons.add_circle_outline, size: 18), label: const Text('Receive old metal now'))),
        if (_omSel.isNotEmpty) const Text('Its value counts as payment in kind. GST is charged on the full bill.', style: TextStyle(fontSize: 11, color: Colors.black45)),
      ]),
    );
  }

  Widget _payStep() {
    final t = _totals();
    final name = _walkIn ? _name.text.trim() : bilingualName(_s(_customer?['name']), _s(_customer?['nameBn']), _lang);
    return ListView(padding: const EdgeInsets.fromLTRB(10, 10, 10, 16), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
      BillCard(
        title: name.isEmpty ? 'Bill' : name,
        icon: Icons.receipt_long_outlined,
        color: _indigo,
        trailing: StatusPill(_interstate ? 'IGST 3%' : 'CGST + SGST', _interstate ? _indigo : _green),
        child: Column(children: [
          for (var i = 0; i < _items.length && i < t.lines.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(children: [
                Expanded(child: Text(t.lines[i].name + (_items[i].purity.isEmpty ? '' : ' · ${_items[i].purity}'), style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                Text(inr(t.lines[i].total), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ]),
            ),
          const Divider(height: 14),
          MoneyRow('Total amount', inr(t.grossTaxable)),
          if (t.additional > 0) MoneyRow('Extra charges (taxed)', '+ ${inr(t.additional)}'),
          if (t.discountBeforeGst > 0) MoneyRow('Discount', '− ${inr(t.discountBeforeGst)}', color: Colors.red.shade700),
          MoneyRow('Taxable amount', inr(t.taxableSum)),
          if (t.interstate) MoneyRow('IGST 3%', inr(t.igstSum)) else ...[MoneyRow('CGST 1.5%', inr(t.cgstSum)), MoneyRow('SGST 1.5%', inr(t.sgstSum))],
          if (t.hallmarkTotal > 0) MoneyRow('Hallmark / HUID fee (no GST)', '+ ${inr(t.hallmarkTotal)}'),
          const SizedBox(height: 4),
          _discountBlock(t),
          if (t.roundOff != 0) MoneyRow('Round off', (t.roundOff >= 0 ? '' : '−') + inr(t.roundOff.abs())),
          const Divider(height: 14),
          MoneyRow('Payable', inr(t.payable), big: true),
        ]),
      ),
      if (t.payable >= _kAddressLimit)
        BillCard(
          title: 'Buyer address',
          icon: Icons.home_outlined,
          color: _blue,
          trailing: const StatusPill('Required · ₹50,000+', _blue),
          child: TextField(
            controller: _address,
            textCapitalization: TextCapitalization.words,
            minLines: 1,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 13.5),
            decoration: billDec('Address *', _blue, hint: 'House, street, town, PIN'),
          ),
        ),
      if (t.tdsApplicable)
        BillCard(
          title: 'TDS 1% · ${inr(t.tdsAmount)}',
          icon: Icons.warning_amber_rounded,
          color: Colors.orange.shade800,
          child: TextField(
            controller: _pan,
            textCapitalization: TextCapitalization.characters,
            maxLength: 10,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            decoration: billDec('Customer PAN *', Colors.orange.shade800, hint: 'ABCDE1234F'),
          ),
        ),
      if (widget.order != null)
        BillCard(
          title: 'Advance already taken',
          icon: Icons.savings_outlined,
          color: const Color(0xFF0E7490),
          trailing: StatusPill('- ${inr(_orderAdvance)}', const Color(0xFF0E7490)),
          child: Text('Order ${_s(widget.order!['number'])}: this is taken off the bill. Only the balance is paid now.', style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
        ),
      _oldMetalCard(t),
      BillCard(
        title: 'Payment',
        icon: Icons.payments_outlined,
        color: _green,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _modeChips(_mode, (m) => setState(() => _mode = m)),
          const SizedBox(height: 10),
          TextField(
            controller: _paid,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            onChanged: (_) => setState(() => _paidTouched = true),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            decoration: billDec(_extraPays.isEmpty ? 'Received now' : 'Payment 1', _green, prefixText: '₹ '),
          ),
          for (var i = 0; i < _extraPays.length; i++) ...[
            const SizedBox(height: 12),
            _modeChips(_extraPays[i].mode, (m) => setState(() => _extraPays[i].mode = m)),
            const SizedBox(height: 8),
            TextField(
              controller: _extraPays[i].amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              onChanged: (_) => setState(() => _paidTouched = true),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              decoration: billDec('Payment ${i + 2}', _green, prefixText: '₹ ').copyWith(
                suffixIcon: IconButton(
                    tooltip: 'Remove',
                    icon: Icon(Icons.close, size: 20, color: Colors.red.shade400),
                    onPressed: () => setState(() {
                          _extraPays.removeAt(i).amount.dispose();
                          _paidTouched = false;
                          _syncPaid();
                        })),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 0, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final q in const [('Full', 1.0), ('Half', 0.5), ('None', 0.0)])
              ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(q.$1, style: const TextStyle(fontSize: 12)),
                onPressed: () => setState(() {
                  for (final r in _extraPays) {
                    r.amount.dispose();
                  }
                  _extraPays.clear();
                  _paidTouched = q.$2 != 1.0;
                  final v = (t.payable * q.$2).roundToDouble();
                  _paid.text = v == 0 ? '' : v.toStringAsFixed(0);
                }),
              ),
            ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.call_split, size: 15),
              label: const Text('Split payment', style: TextStyle(fontSize: 12)),
              onPressed: _extraPays.length >= 4
                  ? null
                  : () => setState(() {
                        final rest = t.payable - _paidTotal();
                        _extraPays.add(_PayRow(_mode == 'Cash' ? 'Online' : 'Cash', rest > 0 ? rest.toStringAsFixed(0) : ''));
                        _paidTouched = true;
                      }),
            ),
          ]),
          ..._cashLimitNotice(t),
          const SizedBox(height: 8),
          if (t.due > 0)
            _banner(Icons.schedule, 'Due ${inr(t.due)}', _walkIn ? 'Walk-in must pay in full' : 'Added to the customer\'s balance', Colors.red.shade700)
          else if (t.advance > 0)
            _banner(Icons.add_circle_outline, 'Advance ${inr(t.advance)}', 'Kept on this invoice', _green)
          else
            _banner(Icons.check_circle_outline, 'Paid in full', '', _green),
          const SizedBox(height: 10),
          TextField(controller: _note, style: const TextStyle(fontSize: 13.5), decoration: billDec('Note (optional)', const Color(0xFF64748B))),
        ]),
      ),
    ]);
  }

  Widget _modeChips(String selected, ValueChanged<String> onPick) => Wrap(spacing: 6, runSpacing: 2, children: [
        for (final m in _modes)
          ChoiceChip(
            avatar: Icon(m.$2, size: 16),
            label: Text(m.$1, style: const TextStyle(fontSize: 12.5)),
            selected: selected == m.$1,
            selectedColor: _green.withOpacity(0.18),
            visualDensity: VisualDensity.compact,
            onSelected: (_) => onPick(m.$1),
          ),
      ]);

  Future<void> _loadCash() async {
    try {
      final id = _walkIn ? '' : _s(_customer?['id']);
      final mobile = _walkIn ? DV.normalizePhone(_mobile.text) : '';
      if (id.isEmpty && mobile.length != 10) {
        if (mounted) setState(() => _cashToday = 0);
        return;
      }
      final r = await _api.billingCashToday(customerId: id, mobile: mobile);
      if (mounted) setState(() => _cashToday = ((r['data']['alreadyToday'] ?? 0) as num).toDouble());
    } catch (_) {/* the server checks the limit again on save */}
  }

  // Cash up to the limit, the rest by Online.
  void _autoSplit() {
    final payable = _totals().payable;
    final room = _cashRoom.toDouble();
    setState(() {
      for (final r in _extraPays) {
        r.amount.dispose();
      }
      _extraPays.clear();
      _paidTouched = true;
      if (room <= 0) {
        _mode = 'Online';
        _paid.text = payable.toStringAsFixed(0);
      } else {
        _mode = 'Cash';
        _paid.text = (payable < room ? payable : room).toStringAsFixed(0);
        if (payable > room) _extraPays.add(_PayRow('Online', (payable - room).toStringAsFixed(0)));
      }
    });
  }

  // Income Tax Act s.269ST: the shop may not receive Rs 2,00,000 or more in cash from one person in a day.
  List<Widget> _cashLimitNotice(BillTotals t) {
    final cash = _cashNow();
    final over = cash > _cashRoom + 0.001;
    if (over) {
      return [
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.red.withOpacity(0.07), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade300)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.block, size: 18, color: Colors.red.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    _cashRoom > 0 ? 'Cash limit: at most ${inr(_cashRoom)} in cash today' : 'No more cash can be taken from this customer today',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.red.shade700)),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 2),
              child: Text(
                  'Income Tax Act s.269ST: ₹2,00,000 or more in cash from one person in a day is not allowed${_cashToday > 0 ? ' (${inr(_cashToday)} already taken today)' : ''}.',
                  style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
            ),
            const SizedBox(height: 6),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 38), backgroundColor: Colors.red.shade700, visualDensity: VisualDensity.compact),
              onPressed: _autoSplit,
              icon: const Icon(Icons.call_split, size: 18),
              label: Text(_cashRoom > 0 ? 'Split: Cash ${inr(_cashRoom)} + Online rest' : 'Take it by Online'),
            ),
          ]),
        ),
      ];
    }
    if (_cashToday > 0) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 2),
          child: Text('Cash already taken today from this customer: ${inr(_cashToday)} · ${inr(_cashRoom)} left', style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
        ),
      ];
    }
    return const [];
  }

  // The customer-facing discount: what they save. It is taken off the price BEFORE GST, out of the making
  // charge (or the amount above metal + stones + hallmark on a typed taxable line), never out of the metal.
  // Staff can type the discount, or the amount the customer wants to pay, or tap a round figure.
  Widget _discountBlock(BillTotals t) {
    final t0 = _t0();
    final before = t0.billBeforeDiscount;
    final pct = before > 0 ? t.discount / before * 100 : 0.0;
    final gstPart = t.discount - t.discountBeforeGst;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _money(_additional, 'Extra charges', () => setState(_syncPaid))),
        const SizedBox(width: 8),
        Expanded(child: _money(_discount, 'Discount', () => setState(_syncPaid))),
      ]),
      const SizedBox(height: 8),
      TextField(
        controller: _final,
        focusNode: _finalFocus,
        keyboardType: const TextInputType.numberWithOptions(decimal: false),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: _onFinalChanged,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        decoration: billDec('Final amount to pay', _green, prefixText: '₹ '),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 0, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Round to', style: TextStyle(fontSize: 12, color: Colors.black54)),
        for (final m in const [10, 100, 500, 1000])
          ActionChip(visualDensity: VisualDensity.compact, label: Text('₹$m', style: const TextStyle(fontSize: 12)), onPressed: () => _roundTo(m)),
        if (t.discount > 0 || _discount.text.isNotEmpty)
          ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.close, size: 14),
              label: const Text('Clear', style: TextStyle(fontSize: 12)),
              onPressed: () => setState(() {
                    _discount.clear();
                    _syncPaid();
                  })),
      ]),
      if (t.discountError != null)
        Padding(padding: const EdgeInsets.only(top: 4, left: 2), child: Text(t.discountError!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.red.shade700)))
      else if (t.discount > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 2),
          child: Text('Customer saves ${inr(t.discount)} (${pct.toStringAsFixed(pct < 1 ? 2 : 1)}%): ${inr(t.discountBeforeGst)} off the price + ${inr(gstPart)} GST',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: pct > 10 ? Colors.red.shade700 : Colors.black54)),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 2, left: 2),
        child: Text(t0.maxDiscount > 0 ? 'Lowest price allowed ${inr(t0.lowestPayable)} (metal, stones and hallmark are never discounted)' : 'No discount possible: no making charge on these items',
            style: const TextStyle(fontSize: 11, color: Colors.black45)),
      ),
    ]);
  }

  Widget _money(TextEditingController c, String label, VoidCallback onChange) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        onChanged: (_) => onChange(),
        style: const TextStyle(fontSize: 13.5),
        decoration: billDec(label, const Color(0xFF9333EA), prefixText: '₹ '),
      );

  Widget _banner(IconData icon, String title, String sub, Color color) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.4))),
        child: Row(children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color)),
          if (sub.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(child: Text(sub, style: const TextStyle(fontSize: 11.5, color: Colors.black54), overflow: TextOverflow.ellipsis)),
          ],
        ]),
      );
}

/// Bottom sheet: search and pick a state / union territory.
class _StatePicker extends StatefulWidget {
  const _StatePicker({required this.states, required this.current, required this.supplyCode});
  final List<Map<String, dynamic>> states;
  final String current;
  final String supplyCode;

  @override
  State<_StatePicker> createState() => _StatePickerState();
}

class _StatePickerState extends State<_StatePicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = widget.states.where((s) => _q.isEmpty || _s(s['name']).toLowerCase().contains(_q) || _s(s['code']).startsWith(_q)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
            child: Row(children: [
              const Icon(Icons.place_outlined, color: _blue),
              const SizedBox(width: 8),
              const Text('Place of supply', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              style: const TextStyle(fontSize: 14),
              decoration: billDec('Search state', _blue, suffix: const Icon(Icons.search, size: 19)),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final s = list[i];
                final sel = _s(s['place']) == widget.current;
                final same = _s(s['code']) == widget.supplyCode;
                return ListTile(
                  dense: true,
                  selected: sel,
                  selectedTileColor: _blue.withOpacity(0.08),
                  leading: SizedBox(width: 26, child: Text(_s(s['code']), style: const TextStyle(fontSize: 13, color: Colors.black45, fontWeight: FontWeight.w600))),
                  title: Text(_s(s['name']), style: TextStyle(fontSize: 14.5, fontWeight: sel ? FontWeight.w800 : FontWeight.w500)),
                  trailing: StatusPill(same ? 'CGST+SGST' : 'IGST', same ? _green : _indigo),
                  onTap: () => Navigator.pop(context, _s(s['place'])),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
