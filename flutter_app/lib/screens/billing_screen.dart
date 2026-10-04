import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../utils/bilingual.dart';
import '../widgets/bill_ui.dart';
import 'create_invoice_screen.dart';
import 'invoice_detail_screen.dart';
import '../widgets/live_refresh.dart';

String _s(dynamic v) => (v ?? '').toString();
double _n(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(_s(v)) ?? 0;

/// GST billing home: figures (swipeable cards), search, filter, invoice list.
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> with LiveRefresh<BillingScreen> {
  @override
  List<String> get liveModules => ['billing'];

  @override
  void onLiveChange() => _reset();

  final _api = ApiService();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _statsPage = PageController(viewportFraction: 0.86);
  Timer? _debounce;

  final List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic>? _stats;
  String _status = 'all';
  String _q = '';
  int _page = 1;
  bool _hasMore = true;
  bool _loading = false;
  int _total = 0;
  String? _error;
  int _statIdx = 0;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    initLive();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _load();
    });
    _reset();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    _statsPage.dispose();
    disposeLive();
    super.dispose();
  }

  Future<void> _reset() async {
    _gen++;
    _rows.clear();
    _page = 1;
    _hasMore = true;
    _loading = false;
    _error = null;
    if (mounted) setState(() {});
    _loadStats();
    await _load();
  }

  Future<void> _loadStats() async {
    try {
      final res = await _api.billingStats();
      if (mounted) setState(() => _stats = Map<String, dynamic>.from(res['data']));
    } catch (_) {}
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    final gen = _gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.billingList(q: _q, status: _status, page: _page);
      if (!mounted || gen != _gen) return;
      final data = List<Map<String, dynamic>>.from((res['data'] as List).map((e) => Map<String, dynamic>.from(e)));
      final pg = res['pagination'] ?? {};
      setState(() {
        _rows.addAll(data);
        _total = pg['total'] ?? _rows.length;
        _hasMore = pg['hasMore'] == true;
        _page++;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _newInvoice() async {
    final id = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const CreateInvoiceScreen()));
    if (id != null && mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id, justCreated: true)));
    }
    if (mounted) _reset();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = context.watch<AuthProvider>().can('billing.create');
    final lang = context.watch<LanguageProvider>().currentLanguage;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        toolbarHeight: 46,
        backgroundColor: const Color(0xFFF4F5F8),
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text('GST Billing', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              backgroundColor: kBillAccent,
              foregroundColor: Colors.white,
              onPressed: _newInvoice,
              icon: const Icon(Icons.add),
              label: const Text('New invoice', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: RefreshIndicator(
            onRefresh: _reset,
            child: ListView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 90),
              children: [
                _statsSlider(),
                const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 350), () {
                      _q = v.trim();
                      _reset();
                    });
                  },
                  style: const TextStyle(fontSize: 13.5),
                  decoration: billDec('Search invoice no., customer, mobile', kBillAccent, suffix: const Icon(Icons.search, size: 18)),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  for (final f in const [('all', 'All'), ('due', 'Due'), ('paid', 'Paid')])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                        selected: _status == f.$1,
                        selectedColor: kBillAccent.withOpacity(0.18),
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          _status = f.$1;
                          _reset();
                        },
                      ),
                    ),
                  const Spacer(),
                  Text('$_total invoice${_total == 1 ? '' : 's'}', style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
                ]),
                if (_rows.isEmpty && _loading)
                  const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                else if (_rows.isEmpty && _error != null)
                  Padding(padding: const EdgeInsets.all(24), child: Column(children: [Text(_error!, style: const TextStyle(color: Colors.red)), TextButton(onPressed: _reset, child: const Text('Retry'))]))
                else if (_rows.isEmpty)
                  const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No invoices yet.\nTap "New invoice" to create one.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54))))
                else
                  for (final r in _rows) _row(r, lang),
                if (_loading && _rows.isNotEmpty) const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── swipeable figure cards (same figures as the website's invoices page) ───
  Widget _statsSlider() {
    final s = _stats;
    Widget card(String title, String big, String sub, Color color, IconData icon) => Container(
          margin: const EdgeInsets.only(right: 8, top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color, color.withOpacity(0.78)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: color.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Row(children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: Colors.white.withOpacity(0.22), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: Colors.white, size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
                Text(big, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ]),
            ),
          ]),
        );

    final cards = s == null
        ? <Widget>[card('Loading…', '—', '', Colors.grey, Icons.hourglass_empty)]
        : [
            card('Total sales', inr(_n(s['sales'])), '${s['invoices']} invoices · received ${inr(_n(s['paid']))}', const Color(0xFF4F46E5), Icons.trending_up),
            card('Gold sales', inr(_n((s['gold'] as Map)['withGst'])), 'Without GST ${inr(_n((s['gold'] as Map)['withoutGst']))} · ${grams(_n((s['gold'] as Map)['weight']))} g', const Color(0xFFD97706), Icons.diamond_outlined),
            card('Silver sales', inr(_n((s['silver'] as Map)['withGst'])), 'Without GST ${inr(_n((s['silver'] as Map)['withoutGst']))} · ${grams(_n((s['silver'] as Map)['weight']))} g', const Color(0xFF64748B), Icons.diamond_outlined),
            card('Total due', inr(_n(s['due'])), 'to be collected', const Color(0xFFDC2626), Icons.pending_actions_outlined),
          ];

    return Column(children: [
      SizedBox(
        height: 96,
        child: PageView(controller: _statsPage, padEnds: false, onPageChanged: (i) => setState(() => _statIdx = i), children: cards),
      ),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < cards.length; i++)
          Container(margin: const EdgeInsets.symmetric(horizontal: 2), width: i == _statIdx ? 14 : 6, height: 6, decoration: BoxDecoration(color: i == _statIdx ? kBillAccent : Colors.black26, borderRadius: BorderRadius.circular(3))),
      ]),
    ]);
  }

  Widget _row(Map<String, dynamic> r, String lang) {
    final due = _n(r['dueAmount']);
    final adv = _n(r['advanceAmount']);
    final date = DateTime.tryParse(_s(r['invoiceDate']))?.toLocal();
    final name = bilingualName(_s(r['customerName']), _s(r['customerNameBn']), lang);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: _s(r['_id']))));
            _reset();
          },
          onLongPress: () async {
            await showInvoiceActions(context, r);
            _reset();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: Row(children: [
              // The whole bill number must show, however long (BGB-0094, MUM-0030, 2045 ...): the badge grows to fit it
              // (up to a limit) and a very long one shrinks instead of being cut.
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 46, maxWidth: 96),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                  decoration: BoxDecoration(color: kBillAccent.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.receipt_long, size: 16, color: kBillAccent),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(_s(r['invoiceNumber']), maxLines: 1, softWrap: false, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kBillAccent)),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
                    if (r['walkIn'] == true) ...[const SizedBox(width: 5), StatusPill('Walk-in', Colors.orange.shade800)],
                  ]),
                  Text('${date == null ? '' : DateFormat('dd MMM yyyy').format(date)}${_s(r['branchName']).isEmpty ? '' : ' · ${_s(r['branchName'])}'}${_s(r['counterName']).isEmpty ? '' : ' · ${_s(r['counterName'])}'}', style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(inr(_n(r['totalPayableAmount'])), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                if (_s(r['status']) == 'cancelled') StatusPill('Cancelled', Colors.grey.shade700) else if (due > 0) StatusPill('Due ${inr(due)}', Colors.red.shade700) else if (adv > 0) StatusPill('Advance ${inr(adv)}', const Color(0xFF16A34A)) else const StatusPill('Paid', Color(0xFF16A34A)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
