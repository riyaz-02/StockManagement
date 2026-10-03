import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../widgets/bill_ui.dart';
import 'invoice_detail_screen.dart';
import '../widgets/live_refresh.dart';

String _s(dynamic v) => (v ?? '').toString();
double _n(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(_s(v)) ?? 0;

/// Who still owes the shop money, biggest first. Tap a customer to see the bills; open a bill to receive a payment.
class PendingDuesScreen extends StatefulWidget {
  const PendingDuesScreen({super.key});
  @override
  State<PendingDuesScreen> createState() => _PendingDuesScreenState();
}

class _PendingDuesScreenState extends State<PendingDuesScreen> with LiveRefresh<PendingDuesScreen> {
  @override
  List<String> get liveModules => ['billing'];

  @override
  void onLiveChange() => _load();

  final _api = ApiService();
  final _q = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _rows = [];
  double _total = 0;
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
    _debounce?.cancel();
    _q.dispose();
    disposeLive();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.billingDues(q: _q.text.trim());
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

  String _age(String ymd) {
    final d = DateTime.tryParse(ymd);
    if (d == null) return '';
    final days = DateTime.now().difference(d).inDays;
    return days <= 0 ? 'today' : (days == 1 ? '1 day ago' : '$days days ago');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(
        title: const Text('Pending dues', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        backgroundColor: const Color(0xFFF4F5F8),
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: TextField(
            controller: _q,
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), _load);
            },
            decoration: billDec('Search name, mobile or bill no.', kBillAccent, suffix: const Icon(Icons.search)),
          ),
        ),
        if (!_loading && _error == null)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade100)),
            child: Row(children: [
              Expanded(child: Text('${_rows.length} customer${_rows.length == 1 ? '' : 's'} owe you', style: const TextStyle(fontWeight: FontWeight.w700))),
              Text(inr(_total), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.red.shade800)),
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
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        children: _rows.isEmpty
                            ? [const Padding(padding: EdgeInsets.only(top: 90), child: Text('Nobody owes you anything.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 15)))]
                            : [for (final r in _rows) _customer(r)],
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _customer(Map<String, dynamic> r) {
    final invs = (r['invoices'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final mobile = _s(r['mobile']);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text(_s(r['name']).isEmpty ? 'Walk-in' : _s(r['name']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          subtitle: Text('${r['count']} bill${r['count'] == 1 ? '' : 's'}  ·  since ${_age(_s(r['oldest']))}${mobile.isEmpty ? '' : '  ·  $mobile'}', style: const TextStyle(fontSize: 12)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (mobile.length >= 10) IconButton(tooltip: 'Call', icon: const Icon(Icons.call, color: Color(0xFF15803D)), onPressed: () => launchUrl(Uri.parse('tel:$mobile'))),
            Text(inr(_n(r['due'])), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.red.shade800)),
          ]),
          children: [
            for (final i in invs)
              ListTile(
                dense: true,
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: _s(i['id']), initialAction: null)));
                  _load();
                },
                title: Text('Bill ${_s(i['number'])}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                subtitle: Text(_s(i['date']).length >= 10 ? DateFormat('dd MMM yyyy').format(DateTime.parse(_s(i['date']))) : _s(i['date']), style: const TextStyle(fontSize: 11.5)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(inr(_n(i['due'])), style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(width: 4), TextButton(onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: _s(i['id']), initialAction: 'pay')));
                  _load();
                }, child: const Text('Receive'))]),
              ),
          ],
        ),
      ),
    );
  }
}
