import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';
import '../utils/gst_periods.dart';
import '../utils/gst_record_pdf.dart';
import '../widgets/bill_ui.dart';
import '../widgets/gst_widgets.dart';
import 'gst_filings_view.dart';
import 'gst_returns_view.dart';
import 'gst_settings_screen.dart';
import 'invoice_detail_screen.dart';

enum _Preset { thisMonth, lastMonth, thisQuarter, lastQuarter, thisFy, lastFy, custom }

const _presetLabels = {
  _Preset.thisMonth: 'This month',
  _Preset.lastMonth: 'Last month',
  _Preset.thisQuarter: 'This quarter',
  _Preset.lastQuarter: 'Last quarter',
  _Preset.thisFy: 'This FY',
  _Preset.lastFy: 'Last FY',
  _Preset.custom: 'Custom',
};

final _dmy = DateFormat('dd MMM yyyy');
final _dm = DateFormat('dd MMM');
Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _l(dynamic v) => v is List ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];
String _s(dynamic v) => (v ?? '').toString();

/// GST Summary: sales, tax collected, metal-wise figures, GSTR-1 / GSTR-3B tables, ITC, due dates and filings,
/// with filters, sorting and a period selector that follows the monthly / quarterly filing setting.
class GstSummaryScreen extends StatefulWidget {
  const GstSummaryScreen({super.key});

  @override
  State<GstSummaryScreen> createState() => _GstSummaryScreenState();
}

class _GstSummaryScreenState extends State<GstSummaryScreen> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late final TabController _tabs = TabController(length: 6, vsync: this)..addListener(_onTab);

  bool _booting = true;
  String? _error;
  bool _busy = false;

  // settings
  String _freq = 'monthly';

  // period + filters
  _Preset _preset = _Preset.thisMonth;
  DateTimeRange? _custom;
  String _metal = '';
  String _taxType = '';
  String _branch = '';
  final _minC = TextEditingController();
  final _maxC = TextEditingController();
  final _searchC = TextEditingController();
  String _search = '';
  String? _groupOverride;
  Timer? _debounce;
  List<Map<String, dynamic>> _branches = [];

  // data
  Map<String, dynamic>? _sum, _cal, _itc;
  int _metric = 0;

  // returns
  String _retPeriod = '';
  Map<String, dynamic>? _ret;
  bool _retLoading = false;
  String? _retError;
  String? _retLoadedFor;

  // register
  List<Map<String, dynamic>> _reg = [];
  int _regTotal = 0, _regPage = 1;
  Map<String, dynamic> _regTotals = {};
  String _regSort = 'date', _regDir = 'desc';
  bool _regLoading = false;

  bool get _canFile => context.read<AuthProvider>().can('gst.manageFilings');
  bool get _canEditSettings => context.read<AuthProvider>().can('gst.editSettings');
  bool get _allBranches => context.read<AuthProvider>().canSwitchBranch;

  // GST is filed per GSTIN (registration). A branch with its own GSTIN has its own returns, credit and due dates.
  List<Map<String, dynamic>> _regs = [];
  String _gstin = ApiService.activeGstin;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    ApiService.activeGstin = ''; // the other screens (and the next visit) start on the firm's default GSTIN
    _debounce?.cancel();
    _tabs.dispose();
    for (final c in [_minC, _maxC, _searchC]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onTab() {
    if (_tabs.indexIsChanging) return;
    if ((_tabs.index == 2 || _tabs.index == 3) && _retLoadedFor != _retPeriod) _loadReturns();
    if (_tabs.index == 5 && _reg.isEmpty && !_regLoading) _loadRegister(reset: true);
    setState(() {});
  }

  void _toast(String m, {bool error = true}) => showAppSnackBar(context, SnackBar(content: Text(m, style: const TextStyle(fontSize: 13)), backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700));

  // ─────────────────────────────── loading ───────────────────────────────
  Future<void> _boot() async {
    try {
      final st = await _api.gstSettings();
      final d = _m(st['data']);
      _regs = _l(d['registrations']);
      _freq = _s(_m(d['settings'])['frequency']);
      _preset = _freq == 'quarterly' ? _Preset.thisQuarter : _Preset.thisMonth;
      _retPeriod = previousPeriodKey(periodKeyFor(_freq, DateTime.now()));
      if (_allBranches && _branches.isEmpty) {
        try {
          final b = await _api.getDirectoryBranches();
          _branches = _l(b['data']);
        } catch (_) {/* the branch filter is optional */}
      }
      await _reloadAll(first: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _booting = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  /// Another GSTIN: its own filing frequency, so the period presets and the returns period are set up again.
  Future<void> _setGstin(String g) async {
    if (g == _gstin) return;
    setState(() {
      _gstin = g;
      _booting = true;
      _sum = _cal = _itc = _ret = null;
      _reg = [];
      _retLoadedFor = null;
    });
    ApiService.activeGstin = g;
    await _boot();
  }

  Widget _regBar() {
    if (_regs.length < 2) return const SizedBox.shrink();
    final def = _regs.firstWhere((r) => r['isDefault'] == true, orElse: () => _regs.first);
    final all = _gstin == 'ALL';
    final cur = all ? null : _regs.firstWhere((r) => _s(r['gstin']) == _gstin, orElse: () => def);
    final label = all ? 'All GSTINs added up' : _s(cur!['gstin']);
    final sub = all ? '' : _s(cur!['name']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: PopupMenuButton<String>(
        tooltip: 'Choose the GST registration',
        onSelected: _setGstin,
        itemBuilder: (_) => [
          for (final r in _regs)
            PopupMenuItem(
              value: r['isDefault'] == true ? '' : _s(r['gstin']),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_s(r['gstin']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                Text('${_s(r['name'])} · ${(r['branches'] as List? ?? const []).map((b) => (b as Map)['name']).join(', ')}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ]),
            ),
          if (_allBranches) const PopupMenuItem(value: 'ALL', child: Text('All GSTINs added up (sales only)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kGstIndigo.withOpacity(0.35))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.apartment_rounded, size: 17, color: kGstIndigo),
            const SizedBox(width: 6),
            Flexible(child: Text(sub.isEmpty ? label : '$label  ·  $sub', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
            const Icon(Icons.arrow_drop_down, size: 20),
          ]),
        ),
      ),
    );
  }

  Future<void> _reloadAll({bool first = false}) async {
    if (!mounted) return;
    setState(() => _busy = true);
    await Future.wait([_loadSummary(), _loadCal(), _loadItc()]);
    if (_tabs.index == 2 || _tabs.index == 3) await _loadReturns();
    if (_tabs.index == 5) await _loadRegister(reset: true);
    if (mounted) {
      setState(() {
        _busy = false;
        _booting = false;
      });
    }
  }

  /// Change of period or filters: summary and the register follow; returns / calendar do not depend on them.
  Future<void> _refilter() async {
    setState(() => _busy = true);
    _reg = [];
    await _loadSummary();
    if (_tabs.index == 5) await _loadRegister(reset: true);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _loadSummary() async {
    try {
      final r = await _api.gstSummary(_query());
      if (mounted) setState(() { _sum = _m(r['data']); _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _loadCal() async {
    try {
      final r = await _api.gstCalendar();
      if (mounted) setState(() => _cal = _m(r['data']));
    } catch (_) {/* the summary still works without the calendar */}
  }

  Future<void> _loadItc() async {
    try {
      final r = await _api.gstItc();
      if (mounted) setState(() => _itc = _m(r['data']));
    } catch (_) {}
  }

  Future<void> _loadReturns() async {
    if (_retPeriod.isEmpty) return;
    setState(() {
      _retLoading = true;
      _retError = null;
    });
    try {
      final r = await _api.gstReturns(_retPeriod);
      if (mounted) setState(() { _ret = _m(r['data']); _retLoadedFor = _retPeriod; });
    } catch (e) {
      if (mounted) setState(() => _retError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _retLoading = false);
    }
  }

  Future<void> _loadRegister({bool reset = false}) async {
    if (reset) {
      _regPage = 1;
      _reg = [];
    }
    setState(() => _regLoading = true);
    try {
      final r = await _api.gstRegister({..._query(), 'sort': _regSort, 'dir': _regDir, 'page': '$_regPage', 'limit': '30'});
      final d = _m(r['data']);
      if (mounted) {
        setState(() {
          _reg = [..._reg, ..._l(d['rows'])];
          _regTotal = (d['total'] as num?)?.toInt() ?? 0;
          _regTotals = _m(d['totals']);
        });
      }
    } catch (e) {
      if (mounted) _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _regLoading = false);
    }
  }

  // ─────────────────────────────── period + filters ───────────────────────────────
  DateTimeRange get _range {
    final t = DateTime.now();
    DateTimeRange r(DateTime a, DateTime b) => DateTimeRange(start: a, end: b);
    switch (_preset) {
      case _Preset.thisMonth:
        return r(DateTime(t.year, t.month, 1), DateTime(t.year, t.month + 1, 0));
      case _Preset.lastMonth:
        return r(DateTime(t.year, t.month - 1, 1), DateTime(t.year, t.month, 0));
      case _Preset.thisQuarter:
        final p = periodOf(periodKeyFor('quarterly', t))!;
        return r(p.from, p.to);
      case _Preset.lastQuarter:
        final p = periodOf(previousPeriodKey(periodKeyFor('quarterly', t)))!;
        return r(p.from, p.to);
      case _Preset.thisFy:
        final y = fyStartYear(t);
        return r(DateTime(y, 4, 1), DateTime(y + 1, 3, 31));
      case _Preset.lastFy:
        final y = fyStartYear(t) - 1;
        return r(DateTime(y, 4, 1), DateTime(y + 1, 3, 31));
      case _Preset.custom:
        return _custom ?? r(DateTime(t.year, t.month, 1), DateTime(t.year, t.month + 1, 0));
    }
  }

  String get _group {
    if (_groupOverride != null) return _groupOverride!;
    final days = _range.duration.inDays + 1;
    return days <= 35 ? 'day' : days <= 130 ? 'week' : days <= 800 ? 'month' : 'quarter';
  }

  Map<String, String> _query() => {
        'from': ymd(_range.start),
        'to': ymd(_range.end),
        'group': _group,
        if (_metal.isNotEmpty) 'metal': _metal,
        if (_taxType.isNotEmpty) 'taxType': _taxType,
        if (_branch.isNotEmpty) 'branch': _branch,
        if (_minC.text.trim().isNotEmpty) 'min': _minC.text.trim(),
        if (_maxC.text.trim().isNotEmpty) 'max': _maxC.text.trim(),
        if (_search.isNotEmpty) 'q': _search,
      };

  int get _filterCount => [_metal, _taxType, _branch, _minC.text.trim(), _maxC.text.trim(), _search].where((e) => e.isNotEmpty).length;

  Future<void> _pickPreset(_Preset p) async {
    if (p == _Preset.custom) {
      final picked = await showDateRangePicker(context: context, firstDate: DateTime(2017, 7), lastDate: DateTime.now().add(const Duration(days: 370)), initialDateRange: _range);
      if (picked == null) return;
      _custom = picked;
    }
    setState(() => _preset = p);
    _refilter();
  }

  Future<void> _openFilters() async {
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _FilterSheet(metal: _metal, taxType: _taxType, branch: _branch, min: _minC.text, max: _maxC.text, branches: _branches, group: _groupOverride),
    );
    if (res == null) return;
    // the sheet writes its choices back through this map
    final f = _FilterSheet.result;
    setState(() {
      _metal = f['metal'] ?? '';
      _taxType = f['taxType'] ?? '';
      _branch = f['branch'] ?? '';
      _minC.text = f['min'] ?? '';
      _maxC.text = f['max'] ?? '';
      _groupOverride = (f['group'] ?? '').isEmpty ? null : f['group'];
    });
    _refilter();
  }

  // ─────────────────────────────── actions ───────────────────────────────
  Future<void> _export(String type, {String? from, String? to}) async {
    try {
      final q = {..._query(), 'type': type, if (from != null) 'from': from, if (to != null) 'to': to};
      final r = await _api.gstExport(q);
      final d = _m(r['data']);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${d['filename']}');
      await file.writeAsString('﻿${d['csv']}', flush: true); // BOM so Excel reads the ₹ and Bengali names
      await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')], subject: _s(d['filename']));
    } catch (e) {
      if (mounted) _toast('Could not export: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  /// The monthly "GST Invoice Record" PDF, laid out like the website's: pick a month, then print / save / share it.
  Future<void> _monthlyRecord() async {
    final now = DateTime.now();
    final last = DateTime(now.year, now.month - 1, 1);
    final pick = await showDialog<(int, int)>(context: context, builder: (_) => _MonthYearDialog(initialYear: last.year, initialMonth: last.month));
    if (pick == null || !mounted) return;
    final (year, month) = pick;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(canPop: false, child: Center(child: Card(child: Padding(padding: EdgeInsets.all(22), child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 14), Text('Preparing the GST record…')]))))),
    );
    try {
      final res = await _api.gstMonthlyRecord(year, month);
      final data = _m(res['data']);
      final bytes = await buildMonthlyRecordPdf(data);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // the progress card
      final fileName = 'GST_Invoice_Record_${_s(_m(data['period'])['monthName'])}_$year.pdf';
      final how = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(leading: const Icon(Icons.picture_as_pdf_outlined, color: kGstIndigo), title: Text(fileName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)), subtitle: Text('${_s(_m(data['scope'])['label']).isEmpty ? 'GSTIN ${_s(_m(data['seller'])['gstin'])}' : _s(_m(data['scope'])['label'])} · ${(bytes.length / 1024).round()} KB')),
            ListTile(leading: const Icon(Icons.ios_share), title: const Text('Save / share the PDF file'), subtitle: const Text('Exact file: WhatsApp, Drive, email, or save to the phone'), onTap: () => Navigator.pop(context, 'share')),
            ListTile(leading: const Icon(Icons.print_outlined), title: const Text('Print or preview'), subtitle: const Text('In the print dialog choose Landscape'), onTap: () => Navigator.pop(context, 'print')),
          ]),
        ),
      );
      if (how == 'share') {
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      } else if (how == 'print') {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName, format: PdfPageFormat.a4.landscape);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _openSettings() async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => GstSettingsScreen(canEdit: _canEditSettings)));
    if (saved == true && mounted) {
      final st = await _api.gstSettings();
      _freq = _s(_m(_m(st['data'])['settings'])['frequency']);
      _preset = _freq == 'quarterly' ? _Preset.thisQuarter : _Preset.thisMonth;
      _retPeriod = previousPeriodKey(periodKeyFor(_freq, DateTime.now()));
      _retLoadedFor = null;
      _toast('Settings saved', error: false);
      await _reloadAll();
    }
  }

  Map<String, dynamic>? _filingOf(String type, String period) {
    for (final i in _l(_cal?['items'])) {
      if (i['type'] == type && i['period'] == period) return _m(i['filing']).isEmpty ? null : _m(i['filing']);
    }
    return null;
  }

  Future<void> _markFiled(String type, String period, String label, {Map<String, dynamic>? existing}) async {
    double tax = 0, itc = 0, cash = 0;
    if (type == 'GSTR-3B' && _ret != null && _ret!['period']?['key'] == period) {
      final led = _m(_m(_ret!['gstr3b'])['ledger']);
      final liab = _m(_m(_ret!['gstr3b'])['liability']);
      final cs = _m(led['cash']);
      tax = gd(liab['igst']) + gd(liab['cgst']) + gd(liab['sgst']);
      cash = gd(cs['igst']) + gd(cs['cgst']) + gd(cs['sgst']);
      itc = tax - cash;
    }
    final ok = await showFilingSheet(context, type: type, period: period, periodLabel: label, existing: existing, tax: tax, itc: itc, cash: cash);
    if (ok == true) {
      _toast('Saved', error: false);
      await _loadCal();
      _loadReturns();
    }
  }

  // ─────────────────────────────── build ───────────────────────────────
  @override
  Widget build(BuildContext context) {
    final alerts = _l(_cal?['alerts']);
    final range = _range;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        toolbarHeight: 48,
        backgroundColor: const Color(0xFFF4F5F8),
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text('GST Summary', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          Badge(isLabelVisible: _filterCount > 0, label: Text('$_filterCount'), offset: const Offset(-6, 6), child: IconButton(tooltip: 'Filters', icon: const Icon(Icons.filter_list_rounded), onPressed: _openFilters)),
          PopupMenuButton<String>(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.ios_share, size: 21),
            onSelected: (v) => v == 'record' ? _monthlyRecord() : _export(v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'record', child: Text('Monthly GST invoice record (PDF)')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'register', child: Text('Invoice register (CSV)')),
              PopupMenuItem(value: 'metal', child: Text('Metal-wise summary (CSV)')),
              PopupMenuItem(value: 'hsn', child: Text('HSN summary (CSV)')),
              PopupMenuItem(value: 'b2cs', child: Text('B2CS table (CSV)')),
              PopupMenuItem(value: 'b2cl', child: Text('B2CL table (CSV)')),
            ],
          ),
          Badge(isLabelVisible: alerts.isNotEmpty, label: Text('${alerts.length}'), backgroundColor: alerts.any((a) => a['severity'] == 'overdue') ? kGstRed : kGstAmber, offset: const Offset(-6, 6), child: IconButton(tooltip: 'Due dates', icon: const Icon(Icons.notifications_none_rounded), onPressed: () => _tabs.animateTo(4))),
          IconButton(tooltip: 'GST filing settings', icon: const Icon(Icons.settings_outlined), onPressed: _openSettings),
        ],
      ),
      body: _booting
          ? const Center(child: CircularProgressIndicator())
          : (_error != null && _sum == null)
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)), TextButton(onPressed: _boot, child: const Text('Retry'))])))
              : Column(children: [
                  _periodBar(range),
                  Container(
                    color: Colors.white,
                    child: TabBar(
                      controller: _tabs,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelColor: kGstIndigo,
                      unselectedLabelColor: Colors.black54,
                      indicatorColor: kGstIndigo,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      tabs: const [Tab(text: 'Overview'), Tab(text: 'Metals & items'), Tab(text: 'GSTR-1'), Tab(text: 'GSTR-3B & ITC'), Tab(text: 'Due dates'), Tab(text: 'Invoices')],
                    ),
                  ),
                  if (_busy) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: TabBarView(controller: _tabs, children: [_overview(), _metals(), _gstr1(), _gstr3b(), _due(), _invoices()]),
                  ),
                ]),
    );
  }

  Widget _periodBar(DateTimeRange range) {
    final prev = _sum == null ? null : _m(_sum!['previous']);
    return Container(
      color: const Color(0xFFF4F5F8),
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _regBar(),
        if (_gstin == 'ALL' && (_tabs.index == 2 || _tabs.index == 3 || _tabs.index == 4))
          const Padding(padding: EdgeInsets.only(bottom: 6), child: Text('Returns, credit and due dates belong to one GSTIN: showing the firm\'s main one. Pick a GSTIN above.', style: TextStyle(fontSize: 11.5, color: Colors.black54))),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final p in _Preset.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  avatar: p == _Preset.custom ? const Icon(Icons.date_range, size: 15) : null,
                  label: Text(_presetLabels[p]!, style: TextStyle(fontSize: 12.5, fontWeight: _preset == p ? FontWeight.w800 : FontWeight.w500)),
                  selected: _preset == p,
                  selectedColor: kGstIndigo.withOpacity(0.16),
                  onSelected: (_) => _pickPreset(p),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 2, top: 2),
          child: Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${_dmy.format(range.start)} – ${_dmy.format(range.end)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            if (prev != null && prev['from'] != null) Text('vs ${_dm.format(DateTime.parse('${prev['from']}'))} – ${_dm.format(DateTime.parse('${prev['to']}'))}', style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
            for (final f in [
              if (_metal.isNotEmpty) ('Metal: $_metal', () => setState(() => _metal = '')),
              if (_taxType.isNotEmpty) (_taxType == 'inter' ? 'Other state' : 'Same state', () => setState(() => _taxType = '')),
              if (_branch.isNotEmpty) ('Branch', () => setState(() => _branch = '')),
              if (_minC.text.trim().isNotEmpty || _maxC.text.trim().isNotEmpty) ('₹${_minC.text.trim().isEmpty ? '0' : _minC.text.trim()}–${_maxC.text.trim().isEmpty ? '∞' : _maxC.text.trim()}', () => setState(() { _minC.clear(); _maxC.clear(); })),
              if (_search.isNotEmpty) ('"$_search"', () => setState(() { _search = ''; _searchC.clear(); })),
            ])
              InputChip(visualDensity: VisualDensity.compact, label: Text(f.$1, style: const TextStyle(fontSize: 11.5)), onDeleted: () { f.$2(); _refilter(); }, padding: EdgeInsets.zero),
          ]),
        ),
      ]),
    );
  }

  Widget _page(List<Widget> children, {Future<void> Function()? onRefresh}) => RefreshIndicator(
        onRefresh: onRefresh ?? _reloadAll,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(10, 10, 10, 30), children: children)),
        ),
      );

  // Cards in equal-height rows (2, 3 or 4 across, by width).
  Widget _grid(List<Widget> cards) => LayoutBuilder(builder: (context, b) {
        final cols = b.maxWidth >= 900 ? 4 : (b.maxWidth >= 560 ? 3 : 2);
        const gap = 10.0;
        final rows = <Widget>[];
        for (var i = 0; i < cards.length; i += cols) {
          final chunk = cards.skip(i).take(cols).toList();
          rows.add(Padding(
            padding: EdgeInsets.only(bottom: i + cols < cards.length ? gap : 0),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var j = 0; j < cols; j++) ...[
                  if (j > 0) const SizedBox(width: gap),
                  Expanded(child: j < chunk.length ? chunk[j] : const SizedBox.shrink()),
                ],
              ]),
            ),
          ));
        }
        return Column(children: rows);
      });

  // ─────────────────────────────── overview ───────────────────────────────
  Widget _overview() {
    final s = _sum;
    if (s == null) return _page(const [Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))]);
    final t = _m(s['totals']);
    final prev = _m(s['previous']);
    final metals = _l(s['byMetal']);
    double mw(String n) => gd(metals.firstWhere((m) => m['metal'] == n, orElse: () => {})['weight']);
    final discountPct = (gd(t['invoiceValue']) + gd(t['discount'])) > 0 ? gd(t['discount']) / (gd(t['invoiceValue']) + gd(t['discount'])) * 100 : 0.0;
    final avg = gd(t['invoices']) > 0 ? gd(t['invoiceValue']) / gd(t['invoices']) : 0.0;
    final alerts = _l(_cal?['alerts']);
    final notes = _m(s['notes']);
    final next = _nextDue();
    final itc = _itc;

    final metrics = [('Sales', 'value'), ('Taxable', 'taxable'), ('GST', 'tax'), ('Weight (g)', 'weight')];
    final trend = _l(s['trend']);
    final metricKey = metrics[_metric].$2;

    return _page([
      if (s['partial'] == true) const GstNotice('Showing only your branch. Ask an admin for every-branch access to see the whole firm.', icon: Icons.store_outlined),
      for (final a in alerts.take(2))
        GstNotice(
          '${a['type']} for ${a['periodLabel']} ${(a['daysLeft'] as num) < 0 ? 'was due ${daysText(a['daysLeft'] as int)}' : 'is due ${daysText(a['daysLeft'] as int)}'}',
          color: a['severity'] == 'overdue' ? kGstRed : a['severity'] == 'urgent' ? kGstAmber : kGstIndigo,
          icon: Icons.event_busy_outlined,
          action: 'Open',
          onAction: () => _tabs.animateTo(4),
        ),
      if (alerts.length > 2) Padding(padding: const EdgeInsets.only(bottom: 8, left: 4), child: GestureDetector(onTap: () => _tabs.animateTo(4), child: Text('+ ${alerts.length - 2} more due dates', style: const TextStyle(fontSize: 12, color: kGstIndigo, fontWeight: FontWeight.w700)))),
      _grid([
        GstKpi(label: 'Sales value', value: inrShort(gd(t['invoiceValue'])), icon: Icons.receipt_long_outlined, color: kGstIndigo, delta: DeltaChip(gd(t['invoiceValue']), gd(prev['invoiceValue'])), sub: '${t['invoices']} invoice${t['invoices'] == 1 ? '' : 's'} · avg ${inrShort(avg)}'),
        GstKpi(label: 'Taxable value', value: inrShort(gd(t['taxable'])), icon: Icons.price_check, color: kGstTeal, delta: DeltaChip(gd(t['taxable']), gd(prev['taxable'])), sub: 'Metal ${inrShort(gd(t['metalValue']))} + making + other'),
        GstKpi(label: 'GST collected', value: inrShort(gd(t['tax'])), icon: Icons.account_balance_outlined, color: kGstGreen, delta: DeltaChip(gd(t['tax']), gd(prev['tax'])), sub: 'CGST ${inr0(gd(t['cgst']))} · SGST ${inr0(gd(t['sgst']))}${gd(t['igst']) > 0 ? ' · IGST ${inr0(gd(t['igst']))}' : ''}'),
        GstKpi(label: 'Making charges', value: inrShort(gd(t['making'])), icon: Icons.handyman_outlined, color: kGstAmber, delta: DeltaChip(gd(t['making']), gd(prev['making'])), sub: gd(t['taxable']) > 0 ? '${(gd(t['making']) / gd(t['taxable']) * 100).toStringAsFixed(1)}% of taxable value' : null),
        GstKpi(label: 'Metal sold', value: weightShort(gd(t['weight'])), icon: Icons.scale_outlined, color: kGstPurple, delta: DeltaChip(gd(t['weight']), gd(prev['weight'])), sub: 'Gold ${weightShort(mw('Gold'))} · Silver ${weightShort(mw('Silver'))}', onTap: () => _tabs.animateTo(1)),
        GstKpi(label: 'Discount given', value: inrShort(gd(t['discount'])), icon: Icons.local_offer_outlined, color: kGstRed, sub: gd(t['discount']) > 0 ? '${discountPct.toStringAsFixed(1)}% of sales' : 'None in this period'),
        GstKpi(label: 'ITC available', value: itc == null ? '…' : inrShort(gd(itc['availableNowTotal'])), icon: Icons.savings_outlined, color: kGstGreen, sub: itc == null ? null : 'Carried forward ${inrShort(gd(itc['carriedTotal']))}', onTap: () => _tabs.animateTo(3)),
        GstKpi(
          label: 'Next due',
          value: next == null ? '—' : '${next['type']}',
          icon: Icons.event_outlined,
          color: next == null ? kGstSlate : statusColor('${next['status']}', (next['daysLeft'] as num).toInt()),
          sub: next == null ? 'All caught up' : '${_dm.format(DateTime.parse('${next['due']}'))} · ${daysText((next['daysLeft'] as num).toInt())}',
          onTap: () => _tabs.animateTo(4),
        ),
      ]),
      const SizedBox(height: 10),
      BillCard(
        title: 'Trend',
        icon: Icons.bar_chart_rounded,
        color: kGstIndigo,
        trailing: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _groupOverride ?? 'auto',
            isDense: true,
            style: const TextStyle(fontSize: 12, color: kGstIndigo, fontWeight: FontWeight.w700),
            items: const [DropdownMenuItem(value: 'auto', child: Text('Auto')), DropdownMenuItem(value: 'day', child: Text('Daily')), DropdownMenuItem(value: 'week', child: Text('Weekly')), DropdownMenuItem(value: 'month', child: Text('Monthly')), DropdownMenuItem(value: 'quarter', child: Text('Quarterly'))],
            onChanged: (v) {
              setState(() => _groupOverride = v == 'auto' ? null : v);
              _refilter();
            },
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var i = 0; i < metrics.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(visualDensity: VisualDensity.compact, label: Text(metrics[i].$1, style: const TextStyle(fontSize: 12)), selected: _metric == i, selectedColor: kGstIndigo.withOpacity(0.16), onSelected: (_) => setState(() => _metric = i)),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          MiniBars(items: [for (final r in trend) (_s(r['label']), gd(r[metricKey]))], format: metricKey == 'weight' ? (v) => weightShort(v) : null),
        ]),
      ),
      LayoutBuilder(builder: (context, b) {
        final wide = b.maxWidth >= 720;
        final cards = [
          BillCard(
            title: 'GST by head',
            icon: Icons.pie_chart_outline,
            color: kGstGreen,
            child: SplitBar(parts: [('CGST', gd(t['cgst']), kGstIndigo), ('SGST', gd(t['sgst']), kGstTeal), ('IGST', gd(t['igst']), kGstAmber)]),
          ),
          BillCard(
            title: 'Money received',
            icon: Icons.payments_outlined,
            color: kGstAmber,
            child: SplitBar(parts: [for (final p in _l(s['payments'])) (_s(p['mode']), gd(p['amount']), _modeColor(_s(p['mode'])))]),
          ),
        ];
        return wide ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final c in cards) Expanded(child: Padding(padding: const EdgeInsets.only(right: 5, left: 5), child: c))]) : Column(children: cards);
      }),
      BillCard(
        title: 'Same state and other state',
        icon: Icons.compare_arrows,
        color: kGstPurple,
        child: SplitBar(parts: [('Same state (CGST+SGST)', gd(t['intra']), kGstTeal), ('Other state (IGST)', gd(t['inter']), kGstPurple)], format: (v) => '${v.round()} inv'),
      ),
      if (gd(notes['untaxedExtraCharges']) > 0)
        GstNotice(
            '${notes['untaxedExtraCharges']} older invoice${notes['untaxedExtraCharges'] == 1 ? '' : 's'} carry ${inr0(gd(notes['untaxedExtraAmount']))} of extra charges billed without GST (the old website rule). GST law treats such charges as part of the taxable value: ask your CA how to report them.',
            icon: Icons.rule_folder_outlined),
      if (gd(notes['discountAfterGst']) > 0)
        GstNotice('${notes['discountAfterGst']} older invoice${notes['discountAfterGst'] == 1 ? '' : 's'} took the discount off after GST (old website rule). New invoices take it off before GST.', color: kGstSlate, icon: Icons.info_outline),
      if (gd(notes['cancelled']) > 0) Padding(padding: const EdgeInsets.only(left: 4), child: Text('${notes['cancelled']} cancelled invoice${notes['cancelled'] == 1 ? '' : 's'} left out of these figures.', style: const TextStyle(fontSize: 11.5, color: Colors.black45))),
    ]);
  }

  Color _modeColor(String m) => switch (m) { 'Cash' => kGstAmber, 'Online' => kGstIndigo, 'Card' => kGstTeal, 'Cheque' => kGstPurple, _ => kGstSlate };

  Map<String, dynamic>? _nextDue() {
    final open = _l(_cal?['items']).where((i) => i['status'] != 'filed' && i['status'] != 'untracked').toList()..sort((a, b) => '${a['due']}'.compareTo('${b['due']}'));
    return open.isEmpty ? null : open.first;
  }

  // ─────────────────────────────── metals & items ───────────────────────────────
  Widget _metals() {
    final s = _sum;
    if (s == null) return _page(const [Center(child: CircularProgressIndicator())]);
    final metals = _l(s['byMetal']);
    double sum(String k) => metals.fold<double>(0, (a, r) => a + gd(r[k]));
    final purity = _l(s['byPurity']).map((p) => {...p, 'label': '${p['metal']} · ${p['purity']}'}).toList();
    final places = _l(s['byPlace']).map((p) => {...p, 'gst': gd(p['cgst']) + gd(p['sgst']) + gd(p['igst'])}).toList();
    return _page([
      BillCard(
        title: 'Metal-wise sales',
        icon: Icons.scale_outlined,
        color: kGstAmber,
        child: GstTable(
          color: kGstAmber,
          empty: 'No sales in this range',
          cols: const [
            GstCol('Metal', 'metal', numeric: false),
            GstCol('Weight (g)', 'weight', width: 104, fmt: _w3),
            GstCol('Metal value', 'metalValue', width: 112, fmt: _r0),
            GstCol('Making', 'making', width: 100, fmt: _r0),
            GstCol('Taxable', 'taxable', width: 108, fmt: _r0),
            GstCol('GST', 'tax', width: 90, fmt: _r0),
            GstCol('Pieces', 'pieces', width: 70, fmt: _r0n),
            GstCol('Avg ₹/g', 'avgRate', width: 90, fmt: _r0),
          ],
          rows: metals,
          sortKey: 'taxable',
          footer: metals.isEmpty ? null : {'metal': 'Total', 'weight': sum('weight'), 'metalValue': sum('metalValue'), 'making': sum('making'), 'taxable': sum('taxable'), 'tax': sum('tax'), 'pieces': sum('pieces'), 'avgRate': ''},
        ),
      ),
      BillCard(
        title: 'What was sold (item-wise)',
        icon: Icons.diamond_outlined,
        color: kGstIndigo,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _searchC,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 450), () {
                _search = v.trim();
                _refilter();
              });
            },
            style: const TextStyle(fontSize: 13.5),
            decoration: billDec('Search invoice, customer or mobile', kGstIndigo, suffix: const Icon(Icons.search, size: 19)),
          ),
          const SizedBox(height: 8),
          GstTable(
            color: kGstIndigo,
            empty: 'No items sold in this range',
            cols: const [
              GstCol('Item', 'item', numeric: false),
              GstCol('Metal', 'metal', numeric: false, width: 74),
              GstCol('Pieces', 'pieces', width: 70, fmt: _r0n),
              GstCol('Weight (g)', 'weight', width: 104, fmt: _w3),
              GstCol('Making', 'making', width: 98, fmt: _r0),
              GstCol('Taxable', 'taxable', width: 108, fmt: _r0),
              GstCol('GST', 'tax', width: 88, fmt: _r0),
            ],
            rows: _l(s['byItem']),
            sortKey: 'taxable',
          ),
        ]),
      ),
      BillCard(title: 'Purity-wise', icon: Icons.verified_outlined, color: kGstTeal, child: GstTable(color: kGstTeal, cols: const [GstCol('Metal · purity', 'label', numeric: false), GstCol('Pieces', 'pieces', width: 70, fmt: _r0n), GstCol('Weight (g)', 'weight', width: 104, fmt: _w3), GstCol('Taxable', 'taxable', width: 108, fmt: _r0)], rows: purity, sortKey: 'weight')),
      BillCard(
        title: 'State-wise sales',
        icon: Icons.map_outlined,
        color: kGstPurple,
        child: GstTable(
          color: kGstPurple,
          cols: const [GstCol('Place of supply', 'place', numeric: false), GstCol('Invoices', 'invoices', width: 76, fmt: _r0n), GstCol('Taxable', 'taxable', width: 108, fmt: _r0), GstCol('GST', 'gst', width: 92, fmt: _r0), GstCol('Value', 'value', width: 108, fmt: _r0)],
          rows: places,
          sortKey: 'taxable',
        ),
      ),
    ]);
  }

  // ─────────────────────────────── GSTR-1 / GSTR-3B ───────────────────────────────
  List<GstPeriod> get _periods => recentPeriods(_freq, DateTime.now(), count: 16);

  Widget _returnBody(String type, List<Widget> Function(Map<String, dynamic>) sections) {
    final key = _retPeriod;
    final r = (_retLoadedFor == key) ? _ret : null;
    final due = r == null ? null : _s(_m(r['due'])[type]);
    final p = periodOf(key);
    final header = ReturnHeader(
      type: type,
      periods: _periods,
      selected: key,
      onPeriod: (v) {
        setState(() {
          _retPeriod = v;
          _ret = null;
        });
        _loadReturns();
      },
      due: due == null || due.isEmpty ? null : due,
      filing: _filingOf(type, key),
      canFile: _canFile,
      onFile: () => _markFiled(type, key, p?.label ?? key, existing: _filingOf(type, key)),
    );
    return _page([
      header,
      if (_retLoading && r == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
      if (_retError != null) GstNotice(_retError!, color: kGstRed, icon: Icons.error_outline, action: 'Retry', onAction: _loadReturns),
      if (r != null) ...[
        if (r['partial'] == true) const GstNotice('Only your branch is included here. A GST return covers the whole firm: use an every-branch login to prepare it.', icon: Icons.store_outlined),
        ...sections(r),
      ],
    ], onRefresh: _loadReturns);
  }

  Widget _gstr1() => _returnBody('GSTR-1', (r) {
        final p = _m(r['period']);
        return gstr1Sections(r, onExport: (type) => _export(type, from: _s(p['from']), to: _s(p['to'])));
      });

  Widget _gstr3b() {
    final itc = _itc;
    return _returnBody('GSTR-3B', (r) => [
          ...gstr3bSections(r),
          if (itc != null)
            BillCard(
              title: 'ITC month by month',
              icon: Icons.timeline,
              color: kGstIndigo,
              child: GstTable(
                color: kGstIndigo,
                empty: 'No ITC tracked yet',
                cols: const [
                  GstCol('Period', 'label', numeric: false),
                  GstCol('Opening', 'open', width: 104, fmt: _r0),
                  GstCol('Added', 'added', width: 100, fmt: _r0),
                  GstCol('Used', 'used', width: 100, fmt: _r0),
                  GstCol('Cash paid', 'cash', width: 104, fmt: _r0),
                  GstCol('Closing', 'close', width: 104, fmt: _r0, bold: true),
                ],
                rows: _l(itc['rows']).map((row) {
                  double tot(dynamic m) => gd(_m(m)['igst']) + gd(_m(m)['cgst']) + gd(_m(m)['sgst']);
                  final used = _m(row['used']);
                  double usedSum = 0;
                  for (final h in ['igst', 'cgst', 'sgst']) {
                    for (final v in _m(used[h]).values) {
                      usedSum += gd(v);
                    }
                  }
                  return {'label': _s(row['label']), 'open': tot(row['opening']), 'added': tot(row['added']), 'used': usedSum, 'cash': tot(row['cash']), 'close': tot(row['closing'])};
                }).toList(),
              ),
            ),
        ]);
  }

  // ─────────────────────────────── due dates ───────────────────────────────
  Widget _due() {
    final cal = _cal;
    if (cal == null) return _page(const [Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))]);
    return RefreshIndicator(
      onRefresh: _loadCal,
      child: FilingsView(
        cal: cal,
        canFile: _canFile,
        onSettings: _openSettings,
        onMark: (i) => _markFiled('${i['type']}', '${i['period']}', '${i['periodLabel']}'),
        onEdit: (i) => _markFiled('${i['type']}', '${i['period']}', '${i['periodLabel']}', existing: _m(i['filing'])),
      ),
    );
  }

  // ─────────────────────────────── invoice register ───────────────────────────────
  Widget _invoices() {
    const sorts = [('date', 'Date'), ('invoiceNumber', 'Number'), ('value', 'Amount'), ('tax', 'GST'), ('weight', 'Weight'), ('making', 'Making'), ('due', 'Due')];
    final more = _reg.length < _regTotal;
    return RefreshIndicator(
      onRefresh: () => _loadRegister(reset: true),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(10, 10, 10, 30), children: [
            TextField(
              controller: _searchC,
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 450), () {
                  _search = v.trim();
                  _refilter();
                });
              },
              style: const TextStyle(fontSize: 13.5),
              decoration: billDec('Search invoice, customer or mobile', kGstIndigo, suffix: const Icon(Icons.search, size: 19)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: kGstIndigo, minimumSize: const Size.fromHeight(42), side: const BorderSide(color: kGstIndigo)),
              onPressed: _monthlyRecord,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
              label: const Text('Monthly GST invoice record (PDF)', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                const Padding(padding: EdgeInsets.only(right: 6), child: Text('Sort', style: TextStyle(fontSize: 12, color: Colors.black45))),
                for (final s in sorts)
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${s.$2}${_regSort == s.$1 ? (_regDir == 'asc' ? ' ↑' : ' ↓') : ''}', style: const TextStyle(fontSize: 12)),
                      selected: _regSort == s.$1,
                      selectedColor: kGstIndigo.withOpacity(0.16),
                      onSelected: (_) {
                        setState(() {
                          if (_regSort == s.$1) {
                            _regDir = _regDir == 'asc' ? 'desc' : 'asc';
                          } else {
                            _regSort = s.$1;
                            _regDir = s.$1 == 'invoiceNumber' ? 'asc' : 'desc';
                          }
                        });
                        _loadRegister(reset: true);
                      },
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            if (_regTotal > 0 || _regLoading)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: kGstIndigo.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                child: Wrap(spacing: 18, runSpacing: 4, children: [
                  Text('$_regTotal invoices', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                  Text('Value ${inr0(gd(_regTotals['invoiceValue']))}', style: const TextStyle(fontSize: 12.5)),
                  Text('Taxable ${inr0(gd(_regTotals['taxable']))}', style: const TextStyle(fontSize: 12.5)),
                  Text('GST ${inr0(gd(_regTotals['tax']))}', style: const TextStyle(fontSize: 12.5)),
                  Text(weightShort(gd(_regTotals['weight'])), style: const TextStyle(fontSize: 12.5)),
                ]),
              ),
            if (_reg.isEmpty && !_regLoading) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('No invoices match', style: TextStyle(color: Colors.black45)))),
            for (final r in _reg) _invoiceRow(r),
            if (_regLoading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            if (more && !_regLoading)
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    _regPage++;
                    _loadRegister();
                  },
                  icon: const Icon(Icons.expand_more),
                  label: Text('Load more (${_regTotal - _reg.length} left)'),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _invoiceRow(Map<String, dynamic> r) {
    final due = gd(r['due']);
    final inter = _s(r['taxType']) == 'IGST';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: _s(r['_id'])))),
      onLongPress: () => showInvoiceActions(context, Map<String, dynamic>.from(r)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('#${r['invoiceNumber']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Text(_s(r['date']).length == 10 ? _dmy.format(DateTime.parse(_s(r['date']))) : _s(r['date']), style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const Spacer(),
            Text(inr(gd(r['value'])), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ]),
          Text(_s(r['customerName']), style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 5),
          Wrap(spacing: 6, runSpacing: 4, children: [
            StatusPill('Taxable ${inr0(gd(r['taxable']))}', kGstTeal),
            StatusPill('GST ${inr0(gd(r['tax']))}', kGstGreen),
            StatusPill(inter ? 'IGST' : 'CGST+SGST', inter ? kGstPurple : kGstSlate),
            if (_s(r['metals']).isNotEmpty) StatusPill('${r['metals']} ${weightShort(gd(r['weight']))}', kGstAmber),
            if (due > 0) StatusPill('Due ${inr0(due)}', kGstRed),
            if (_s(r['status']) == 'cancelled') const StatusPill('Cancelled', kGstSlate),
          ]),
        ]),
      ),
    );
  }
}

String _w3(dynamic v) => gd(v).toStringAsFixed(3);
String _r0(dynamic v) => v == '' || v == null ? '' : inr0(gd(v));
String _r0n(dynamic v) => gd(v).round().toString();

/// Filters bottom sheet. Choices are handed back through [result].
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.metal, required this.taxType, required this.branch, required this.min, required this.max, required this.branches, required this.group});
  final String metal, taxType, branch, min, max;
  final String? group;
  final List<Map<String, dynamic>> branches;
  static Map<String, String> result = {};

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _metal = widget.metal, _tax = widget.taxType, _branch = widget.branch, _group = widget.group ?? '';
  late final _min = TextEditingController(text: widget.min);
  late final _max = TextEditingController(text: widget.max);

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  Widget _chips(List<(String, String)> opts, String value, ValueChanged<String> on) => Wrap(spacing: 6, runSpacing: 2, children: [
        for (final o in opts) ChoiceChip(visualDensity: VisualDensity.compact, label: Text(o.$1, style: const TextStyle(fontSize: 12.5)), selected: value == o.$2, selectedColor: kGstIndigo.withOpacity(0.16), onSelected: (_) => setState(() => on(o.$2))),
      ]);

  Widget _head(String t) => Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(t, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.black54)));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.filter_list_rounded, color: kGstIndigo),
            const SizedBox(width: 8),
            const Expanded(child: Text('Filters', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            TextButton(
                onPressed: () => setState(() {
                      _metal = _tax = _branch = _group = '';
                      _min.clear();
                      _max.clear();
                    }),
                child: const Text('Reset')),
          ]),
          _head('Metal'),
          _chips(const [('All', ''), ('Gold', 'gold'), ('Silver', 'silver'), ('Other', 'other')], _metal, (v) => _metal = v),
          _head('Tax type'),
          _chips(const [('All', ''), ('Same state (CGST+SGST)', 'intra'), ('Other state (IGST)', 'inter')], _tax, (v) => _tax = v),
          if (widget.branches.isNotEmpty) ...[
            _head('Branch'),
            DropdownButtonFormField<String>(
              value: _branch,
              isExpanded: true,
              style: const TextStyle(fontSize: 13.5, color: Colors.black87),
              decoration: billDec('Branch', kGstIndigo),
              items: [
                const DropdownMenuItem(value: '', child: Text('All branches')),
                for (final b in widget.branches) DropdownMenuItem(value: '${b['_id'] ?? b['id'] ?? ''}', child: Text('${b['name'] ?? b['branchName'] ?? 'Branch'}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _branch = v ?? ''),
            ),
          ],
          _head('Invoice value'),
          Row(children: [
            Expanded(child: TextField(controller: _min, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], style: const TextStyle(fontSize: 13.5), decoration: billDec('At least', kGstIndigo, prefixText: '₹ '))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _max, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], style: const TextStyle(fontSize: 13.5), decoration: billDec('At most', kGstIndigo, prefixText: '₹ '))),
          ]),
          _head('Group the trend by'),
          _chips(const [('Auto', ''), ('Day', 'day'), ('Week', 'week'), ('Month', 'month'), ('Quarter', 'quarter')], _group, (v) => _group = v),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: kGstIndigo),
              onPressed: () {
                _FilterSheet.result = {'metal': _metal, 'taxType': _tax, 'branch': _branch, 'min': _min.text.trim(), 'max': _max.text.trim(), 'group': _group};
                Navigator.pop(context, true);
              },
              icon: const Icon(Icons.check, size: 20),
              label: const Text('Apply', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}


/// Month + year picker for the monthly record (no future months).
class _MonthYearDialog extends StatefulWidget {
  const _MonthYearDialog({required this.initialYear, required this.initialMonth});
  final int initialYear, initialMonth;

  @override
  State<_MonthYearDialog> createState() => _MonthYearDialogState();
}

class _MonthYearDialogState extends State<_MonthYearDialog> {
  static const _names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  late int _year = widget.initialYear, _month = widget.initialMonth;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final years = [for (var y = now.year; y >= 2020; y--) y];
    final future = _year > now.year || (_year == now.year && _month > now.month);
    return AlertDialog(
      title: const Row(children: [Icon(Icons.picture_as_pdf_outlined, color: kGstIndigo), SizedBox(width: 8), Expanded(child: Text('GST invoice record', style: TextStyle(fontSize: 17)))]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Every invoice of the month, with totals and the return-filing summary, in the same layout as the website.', style: TextStyle(fontSize: 12.5, color: Colors.black54)),
        const SizedBox(height: 14),
        DropdownButtonFormField<int>(
          value: _month,
          isExpanded: true,
          decoration: billDec('Month', kGstIndigo),
          items: [for (var i = 1; i <= 12; i++) DropdownMenuItem(value: i, child: Text(_names[i - 1]))],
          onChanged: (v) => setState(() => _month = v ?? _month),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          value: _year,
          isExpanded: true,
          decoration: billDec('Year', kGstIndigo),
          items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
          onChanged: (v) => setState(() => _year = v ?? _year),
        ),
        if (future) const Padding(padding: EdgeInsets.only(top: 8), child: Text('That month has not happened yet.', style: TextStyle(fontSize: 12, color: Colors.red))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(onPressed: future ? null : () => Navigator.pop(context, (_year, _month)), icon: const Icon(Icons.print_outlined, size: 18), label: const Text('Generate')),
      ],
    );
  }
}
