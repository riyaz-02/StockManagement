import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/stock_summary_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';
import '../../providers/store_provider.dart';
import '../stock_history_screen.dart';
import '../wastage_screen.dart';

/// The Summary: what came into the business against what is in the shop, was sold and was wasted, and the difference.
/// The server works every number out (the website shows the same); this only draws it, in English or Bengali.
class SummaryTab extends StatefulWidget {
  const SummaryTab({super.key});

  @override
  State<SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends State<SummaryTab> {
  List<Movement>? _moreMovements;
  bool _loadingMore = false;

  Color _sevColor(String s) => s == 'high' ? Colors.red.shade700 : s == 'moderate' ? Colors.orange.shade800 : Colors.green.shade700;
  String _sevLabel(String s, bool bn) => s == 'high' ? (bn ? 'বেশি' : 'High') : s == 'moderate' ? (bn ? 'সতর্ক' : 'Watch') : (bn ? 'স্বাভাবিক' : 'Normal');
  String _g(double v) => '${v.toStringAsFixed(3)} g';

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>().currentLanguage;
    final bn = lang == 'bn';
    final auth = context.watch<AuthProvider>();
    return Consumer<StoreProvider>(builder: (context, store, _) {
      final s = store.summary;
      if (s == null) {
        if (store.isReconcileLoading) return const Center(child: CircularProgressIndicator());
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.balance_outlined, size: 56, color: Colors.grey),
            const SizedBox(height: 10),
            Text(store.summaryError ?? (bn ? 'সামারি লোড হয়নি' : 'The summary is not loaded'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            ElevatedButton.icon(onPressed: store.fetchSummary, icon: const Icon(Icons.refresh), label: Text(bn ? 'আবার চেষ্টা' : 'Try again')),
          ]),
        );
      }
      final conf = {'reliable': Colors.green.shade700, 'check': Colors.orange.shade800, 'fix': Colors.red.shade700}[s.confidenceLevel]!;
      return RefreshIndicator(
        onRefresh: store.fetchSummary,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
          children: [
            // is the number to be trusted?
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: conf.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: conf.withOpacity(0.35))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(s.confidenceLevel == 'reliable' ? Icons.verified_outlined : Icons.report_gmailerrorred_outlined, color: conf, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${s.confidenceLevel == 'reliable' ? (bn ? 'নির্ভরযোগ্য' : 'Reliable') : s.confidenceLevel == 'check' ? (bn ? 'আগে দেখুন' : 'Check first') : (bn ? 'আগে ঠিক করুন' : 'Fix first')}: ${s.confidenceText.of(lang)}',
                    style: TextStyle(color: conf, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Text(
              '${bn ? 'হিসাব' : 'As of'} ${_fmtTime(s.asOf)} · ${s.savedToday ? (bn ? 'আজকের স্ন্যাপশট সেভ আছে' : "today's snapshot is saved") : (bn ? 'আজকের স্ন্যাপশট নেই' : 'no snapshot yet today')}'
              '${s.wholeFirm ? '' : (bn ? ' · শুধু আপনার শাখা' : ' · your branch only')}',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StockHistoryScreen())),
                  icon: const Icon(Icons.show_chart, size: 18),
                  label: Text(bn ? 'ইতিহাস' : 'History'),
                ),
              ),
              if (auth.can('stock.snapshot') && s.wholeFirm) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: store.isSummaryBusy ? null : () async {
                      final msg = await store.saveSnapshot();
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                    },
                    icon: store.isSummaryBusy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined, size: 18),
                    label: Text(bn ? 'আজকের স্ন্যাপশট' : "Save today's snapshot"),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 14),

            _metalCard(s.gold, s, bn),
            const SizedBox(height: 12),
            _metalCard(s.silver, s, bn),
            const SizedBox(height: 18),

            _heading(bn ? 'এর মানে কী · করণীয়' : 'What it means · what to do'),
            _insightCard(bn ? 'স্বর্ণ' : 'Gold', s.goldInsight, lang),
            _insightCard(bn ? 'রূপা' : 'Silver', s.silverInsight, lang),
            const SizedBox(height: 14),

            _heading(bn ? 'তথ্য যাচাই' : 'Data checks'),
            if (s.checks.isEmpty) Text(bn ? 'কোনো সমস্যা নেই।' : 'No problems found.', style: const TextStyle(color: Colors.grey)),
            for (final c in s.checks) _checkTile(c, lang),
            const SizedBox(height: 14),

            _heading(bn ? 'সাম্প্রতিক স্টক মুভমেন্ট' : 'Recent movements'),
            ..._movementTiles(_moreMovements ?? s.movements, bn),
            if (_moreMovements == null)
              TextButton(
                onPressed: _loadingMore ? null : () async {
                  setState(() => _loadingMore = true);
                  final m = await store.fetchMovements(limit: 30);
                  if (mounted) setState(() { _moreMovements = m; _loadingMore = false; });
                },
                child: Text(_loadingMore ? '...' : (bn ? 'আরও দেখুন' : 'Show more')),
              ),
            const SizedBox(height: 14),

            _heading(bn ? 'মেটাল ক্ষতির রিপোর্ট' : 'Wastage reports'),
            Text(
              bn ? 'কাজে হারানো ধাতু। অনুমোদন না হওয়া পর্যন্ত হিসাবে ধরা হয় না; যিনি রিপোর্ট করেন তিনি অনুমোদন করতে পারেন না।'
                 : 'Metal lost in making. It counts only once someone else approves it.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const WastageScreen()));
                    if (context.mounted) store.fetchSummary();
                  },
                  icon: const Icon(Icons.list_alt_outlined, size: 18),
                  label: Text(bn ? 'সব রিপোর্ট' : 'All reports'),
                ),
              ),
              if (auth.can('wastage.report')) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await showWastageForm(context);
                      if (context.mounted) store.fetchSummary();
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(bn ? 'ক্ষতি জানান' : 'Report wastage'),
                  ),
                ),
              ],
            ]),
          ],
        ),
      );
    });
  }

  String _fmtTime(DateTime? t) {
    if (t == null) return '';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(t.day)}/${p(t.month)} ${p(t.hour)}:${p(t.minute)}';
  }

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      );

  Widget _metalCard(MetalBalance m, StockSummary s, bool bn) {
    final gold = m.metal == 'gold';
    final accent = gold ? const Color(0xFFD4A017) : const Color(0xFF94A3B8);
    final sev = _sevColor(m.severity);
    Widget row(String en, String bnT, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(bn ? bnT : en, style: TextStyle(fontSize: 13, color: Colors.grey[800], fontWeight: bold ? FontWeight.w700 : FontWeight.w500))),
            const SizedBox(width: 10),
            Text(v, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ]),
        );
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border(top: BorderSide(color: accent, width: 4)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))]),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          title: Row(children: [
            Text(gold ? (bn ? 'স্বর্ণ' : 'Gold') : (bn ? 'রূপা' : 'Silver'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const Spacer(),
            Text(_g(m.stockTotal), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ]),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Text(bn ? 'গড়মিল ' : 'Difference ', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              Text(_g(m.variance), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: sev)),
              Text('  ${m.variancePct.abs().toStringAsFixed(2)}%', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(width: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: sev.withOpacity(0.12), borderRadius: BorderRadius.circular(10)), child: Text(_sevLabel(m.severity, bn), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: sev))),
            ]),
          ),
          children: [
            row('Metal bought (purchases)', 'ক্রয় করা ধাতু', _g(m.purchased)),
            row('+ Allowance for alloy and process (${m.allowancePct.toStringAsFixed(m.allowancePct % 1 == 0 ? 0 : 1)}%)', 'খাদ ও কাজের জন্য বাড়তি (${m.allowancePct.toStringAsFixed(m.allowancePct % 1 == 0 ? 0 : 1)}%)', _g(m.allowance)),
            if (m.oldMetal > 0 || m.rawMetal > 0) row('+ Old metal taken in and raw metal bought', 'পুরনো ও কাঁচা ধাতু প্রাপ্তি', _g(m.oldMetal + m.rawMetal)),
            row('Total metal received', 'মোট প্রাপ্ত ধাতু', _g(m.receiptsTotal), bold: true),
            const Divider(height: 14),
            row('In the shop (${m.piecesInShop} pieces)', 'দোকানে (${m.piecesInShop}টি পিস)', _g(m.inShop)),
            if (m.withOthers > 0) row('Out for repair / with agent or customer (${m.piecesWithOthers})', 'বাইরে — মেরামত / এজেন্ট / গ্রাহক (${m.piecesWithOthers})', _g(m.withOthers)),
            row('Bulk stock (${m.bulkEntries} entries)', 'বাল্ক স্টক (${m.bulkEntries}টি)', _g(m.bulk)),
            row('Stock now', 'বর্তমান স্টক', _g(m.stockTotal), bold: true),
            const Divider(height: 14),
            row('Expected to have left the shop', 'প্রত্যাশিত বেরিয়ে গেছে', _g(m.expectedOut)),
            row('Sold on GST bills${m.returned > 0 ? ' (after ${_g(m.returned)} returned)' : ''}', 'বিক্রি — জিএসটি বিল${m.returned > 0 ? ' (${_g(m.returned)} ফেরত বাদে)' : ''}', _g(m.sold)),
            row('Less: approved wastage', 'বিয়োগ: অনুমোদিত ক্ষতি', _g(m.wastage)),
            const Divider(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: sev.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Expanded(child: Text(bn ? 'গড়মিল / মিলানো বাকি' : 'Difference', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                Text('${_g(m.variance)}  ${m.variancePct.abs().toStringAsFixed(2)}%', style: TextStyle(fontWeight: FontWeight.w800, color: sev)),
              ]),
            ),
            const SizedBox(height: 6),
            Text(
              m.direction == 'balanced'
                  ? (bn ? 'রেকর্ড ও স্টক মিলেছে।' : 'The records and the stock agree.')
                  : m.direction == 'short'
                      ? (bn ? 'প্রাপ্ত ধাতুর এই অংশ স্টক, বিল বা অনুমোদিত ক্ষতিতে নেই (কারিগরের কাছে, লেখা হয়নি, বা হারিয়েছে)।' : 'Metal received that is not in the stock, the bills or the approved wastage (with workers, not entered, or missing).')
                      : (bn ? 'রেকর্ডের চেয়ে বেশি: কোনো ক্রয় লেখা হয়নি, বা কিছু দুবার লেখা হয়েছে।' : 'More than the records explain: a purchase may be missing, or something is entered twice.'),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _insightCard(String name, MetalInsight i, String lang) {
    final sev = _sevColor(i.severity);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(color: sev, width: 4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(i.headline.of(lang), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        const SizedBox(height: 6),
        for (final a in i.analysis) Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('• ${a.of(lang)}', style: const TextStyle(fontSize: 12.5))),
        if (i.recommendations.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(lang == 'bn' ? 'করণীয়' : 'What to do', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          for (final r in i.recommendations) Padding(padding: const EdgeInsets.only(top: 3), child: Text('→ ${r.of(lang)}', style: const TextStyle(fontSize: 12.5))),
        ],
      ]),
    );
  }

  Widget _checkTile(SummaryCheck c, String lang) {
    final color = c.level == 'error' ? Colors.red.shade700 : c.level == 'warn' ? Colors.orange.shade800 : Colors.blueGrey;
    final icon = c.level == 'info' ? Icons.info_outline : Icons.warning_amber_rounded;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(c.text.of(lang), style: const TextStyle(fontSize: 12.5))),
      ]),
    );
  }

  List<Widget> _movementTiles(List<Movement> list, bool bn) {
    if (list.isEmpty) return [Text(bn ? 'এখনও কোনো মুভমেন্ট নেই।' : 'No movements yet.', style: const TextStyle(color: Colors.grey))];
    const labels = {'purchase': ['Purchase', 'ক্রয়'], 'old_metal': ['Old metal in', 'পুরনো ধাতু'], 'raw_metal': ['Raw metal in', 'কাঁচা ধাতু'], 'sale': ['Sold', 'বিক্রি'], 'wastage': ['Wastage', 'ক্ষতি'], 'bulk': ['Bulk stock', 'বাল্ক স্টক']};
    return list.map((m) {
      final color = m.direction == 'in' ? Colors.green.shade700 : m.direction == 'out' ? Colors.red.shade700 : Colors.blueGrey;
      final label = (labels[m.type] ?? [m.type, m.type])[bn ? 1 : 0];
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          CircleAvatar(radius: 13, backgroundColor: color.withOpacity(0.12), child: Icon(m.direction == 'in' ? Icons.arrow_downward : m.direction == 'out' ? Icons.arrow_upward : Icons.circle, size: 13, color: color)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$label · ${m.metal == 'gold' ? (bn ? 'স্বর্ণ' : 'Gold') : (bn ? 'রূপা' : 'Silver')}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text('${m.at} · ${m.title}${m.note.isNotEmpty ? ' · ${m.note}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ]),
          ),
          Text('${m.direction == 'in' ? '+' : m.direction == 'out' ? '−' : ''}${_g(m.grams)}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: color)),
        ]),
      );
    }).toList();
  }
}
