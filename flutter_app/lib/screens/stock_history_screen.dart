import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/stock_summary_models.dart';
import '../providers/language_provider.dart';
import '../providers/store_provider.dart';

/// The saved daily snapshots over time: stock, what came in and went out, and the difference.
/// Daily / weekly / monthly are rolled up on the server (balances = the last snapshot of the period; in/out add up).
class StockHistoryScreen extends StatefulWidget {
  const StockHistoryScreen({super.key});

  @override
  State<StockHistoryScreen> createState() => _StockHistoryScreenState();
}

class _StockHistoryScreenState extends State<StockHistoryScreen> {
  String _view = 'daily';
  int _days = 30; // 0 = all

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() {
    final to = DateTime.now();
    return context.read<StoreProvider>().fetchHistory(
          view: _view,
          from: _days == 0 ? null : _ymd(to.subtract(Duration(days: _days))),
          to: _ymd(to),
        );
  }

  Color _sev(String s) => s == 'high' ? Colors.red.shade700 : s == 'moderate' ? Colors.orange.shade800 : Colors.green.shade700;

  @override
  Widget build(BuildContext context) {
    final bn = context.watch<LanguageProvider>().currentLanguage == 'bn';
    final store = context.watch<StoreProvider>();
    final h = store.history;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(title: Text(bn ? 'স্টকের ইতিহাস' : 'Stock history'), backgroundColor: Colors.white, foregroundColor: const Color(0xFF1A1A1A), elevation: 0),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'daily', label: Text(bn ? 'দৈনিক' : 'Daily')),
              ButtonSegment(value: 'weekly', label: Text(bn ? 'সাপ্তাহিক' : 'Weekly')),
              ButtonSegment(value: 'monthly', label: Text(bn ? 'মাসিক' : 'Monthly')),
            ],
            selected: {_view},
            onSelectionChanged: (s) { setState(() => _view = s.first); _load(); },
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
            for (final d in [[30, bn ? '৩০ দিন' : 'Last 30 days'], [90, bn ? '৯০ দিন' : 'Last 90 days'], [365, bn ? '১ বছর' : 'Last year'], [0, bn ? 'সব' : 'All']])
              Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text('${d[1]}'), selected: _days == d[0], onSelected: (_) { setState(() => _days = d[0] as int); _load(); })),
          ]),
        ),
        Expanded(
          child: store.isHistoryLoading && h == null
              ? const Center(child: CircularProgressIndicator())
              : h == null || h.rows.isEmpty
                  ? Center(child: Padding(padding: const EdgeInsets.all(30), child: Text(bn ? 'এই সময়ে কোনো স্ন্যাপশট নেই। সামারি খুললে বা "আজকের স্ন্যাপশট" চাপলে একটি সেভ হয়।' : 'No snapshots in this period. One is saved when the Summary is opened or when you press "Save today\'s snapshot".', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey))))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
                        itemCount: h.rows.length + 1,
                        itemBuilder: (_, i) {
                          if (i == 0) {
                            final note = !h.enough
                                ? (bn ? 'প্রবণতা বোঝার মতো যথেষ্ট স্ন্যাপশট নেই।' : 'Not enough snapshots yet to see a trend.')
                                : !h.comparable
                                    ? (bn ? 'হিসাবের পদ্ধতি বদলেছে (চিহ্নিত সারি): তার আগের ও পরের সংখ্যা সরাসরি তুলনীয় নয়।' : 'The way of counting changed (marked row): numbers before and after are not directly comparable.')
                                    : '';
                            return note.isEmpty ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(note, style: TextStyle(fontSize: 12, color: Colors.grey[700])));
                          }
                          return _row(h.rows[i - 1], bn);
                        },
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _row(HistoryRow r, bool bn) {
    Widget metal(String name, HistoryMetal m) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600)),
            Text('${m.stock.toStringAsFixed(3)} g', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            if (m.inG != null && m.outG != null) Text('+${m.inG!.toStringAsFixed(3)}  −${m.outG!.toStringAsFixed(3)}', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            Text('${bn ? 'গড়মিল' : 'Diff'} ${m.variance.toStringAsFixed(3)} g (${m.variancePct.abs().toStringAsFixed(2)}%)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _sev(m.severity))),
          ]),
        );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(r.label, style: const TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            if (r.methodChange) Text(bn ? 'পদ্ধতি বদল' : 'method changed', style: TextStyle(fontSize: 11, color: Colors.orange.shade800, fontWeight: FontWeight.w700)),
            if (r.snapshots > 1) Padding(padding: const EdgeInsets.only(left: 8), child: Text('${r.snapshots} ${bn ? 'স্ন্যাপশট' : 'snapshots'}', style: TextStyle(fontSize: 11, color: Colors.grey[600]))),
          ]),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [metal(bn ? 'স্বর্ণ' : 'Gold', r.gold), const SizedBox(width: 8), metal(bn ? 'রূপা' : 'Silver', r.silver)]),
        ]),
      ),
    );
  }
}
