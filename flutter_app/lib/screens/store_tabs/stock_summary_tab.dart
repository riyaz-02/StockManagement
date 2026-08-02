import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/store_provider.dart';
import '../../utils/app_colors.dart';

class StockSummaryTab extends StatefulWidget {
  const StockSummaryTab({super.key});

  @override
  State<StockSummaryTab> createState() => _StockSummaryTabState();
}

class _StockSummaryTabState extends State<StockSummaryTab>
    with SingleTickerProviderStateMixin {
  String? _filterMetal;
  late TabController _localTab;

  // Available financial years from legacy data onwards
  late List<String> _fyOptions;
  late String _selectedFy;

  @override
  void initState() {
    super.initState();
    _localTab = TabController(length: 2, vsync: this);
    _fyOptions = _buildFyOptions();
    _selectedFy = _fyOptions.first; // default = current FY

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = Provider.of<StoreProvider>(context, listen: false);
      store.fetchItcSummary(fy: _selectedFy);
    });
  }

  @override
  void dispose() {
    _localTab.dispose();
    super.dispose();
  }

  /// Build list of FYs from 2020-21 to current+1
  List<String> _buildFyOptions() {
    final now = DateTime.now();
    final curFyStart = now.month >= 4 ? now.year : now.year - 1;
    final List<String> options = [];
    for (int y = curFyStart; y >= 2020; y--) {
      options.add('$y-${(y + 1).toString().substring(2)}');
    }
    return options;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StoreProvider>(
      builder: (context, store, _) {
        return Column(
          children: [
            // ── Tab bar: Ledger / ITC ─────────────────────────────────────
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _localTab,
                labelColor: AppColors.primary,
                unselectedLabelColor: Colors.grey[500],
                indicatorColor: AppColors.primary,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700),
                tabs: const [
                  Tab(text: 'Daily Ledger'),
                  Tab(text: 'GST / ITC Summary'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _localTab,
                children: [
                  _buildLedger(store),
                  _buildItc(store),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 1: Daily Ledger
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildLedger(StoreProvider store) {
    return Column(
      children: [
        _buildFilter(store),
        Expanded(
          child: store.isSummaryLoading
              ? const Center(child: CircularProgressIndicator())
              : store.dailySummary.isEmpty
                  ? _buildEmpty('No stock movement yet',
                      'Purchases and sales will appear here')
                  : RefreshIndicator(
                      onRefresh: () => store.fetchDailySummary(
                          metalType: _filterMetal),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 80),
                        children: _buildDayCards(store.dailySummary),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildFilter(StoreProvider store) {
    final metals = ['all', 'gold', 'silver', 'platinum'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: metals.map((m) {
            final sel = (_filterMetal == null && m == 'all') || _filterMetal == m;
            final color = m == 'all' ? AppColors.primary : _metalColor(m);
            return GestureDetector(
              onTap: () {
                setState(() => _filterMetal = m == 'all' ? null : m);
                store.fetchDailySummary(metalType: _filterMetal);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? color.withAlpha(18) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: sel ? color : Colors.grey.shade200,
                      width: sel ? 1.5 : 1),
                ),
                child: Text(
                  m == 'all' ? 'All' : m[0].toUpperCase() + m.substring(1),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      color: sel ? color : Colors.grey[600]),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  List<Widget> _buildDayCards(Map<String, dynamic> summary) {
    final sortedDates = summary.keys.toList()..sort((a, b) => b.compareTo(a));
    return sortedDates.map((date) => _dayCard(date,
        summary[date] as Map<String, dynamic>? ?? {})).toList();
  }

  Widget _dayCard(String date, Map<String, dynamic> dayData) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(5),
              blurRadius: 6, offset: const Offset(0, 1)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.blue.withAlpha(18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_formatDate(date),
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: Colors.blue)),
          ),
          const SizedBox(height: 12),
          ...dayData.entries.map((entry) {
            final metal = entry.key;
            final data  = entry.value as Map<String, dynamic>;
            final inW   = (data['in'] as num?)?.toDouble()  ?? 0;
            final outW  = (data['out'] as num?)?.toDouble() ?? 0;
            final net   = (data['net'] as num?)?.toDouble() ?? 0;
            final color = _metalColor(metal);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 6, height: 6,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(metal[0].toUpperCase() + metal.substring(1),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                          color: Colors.grey[600])),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  _ledgerCell('In (Credit)', inW, Colors.green),
                  const SizedBox(width: 8),
                  _ledgerCell('Out (Debit)', outW, Colors.red),
                  const SizedBox(width: 8),
                  _ledgerCell('Net', net,
                      net >= 0 ? Colors.green.shade700 : Colors.red),
                ]),
              ]),
            );
          }),
        ]),
      ),
    );
  }

  Widget _ledgerCell(String label, double value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: color.withAlpha(14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: [
            Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[500])),
            const SizedBox(height: 3),
            Text(
              '${value >= 0 ? '' : '-'}${value.abs().toStringAsFixed(3)} g',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color),
            ),
          ]),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 2: GST / ITC Summary (Quarterly)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildItc(StoreProvider store) {
    return Column(
      children: [
        // FY selector
        _fySelector(store),
        Expanded(
          child: store.isItcLoading
              ? const Center(child: CircularProgressIndicator())
              : store.itcError != null
                  ? _buildError(store.itcError!, store)
                  : store.itcSummary == null
                      ? _buildEmpty('No data', 'Tap refresh')
                      : _buildItcContent(store.itcSummary!),
        ),
      ],
    );
  }

  Widget _fySelector(StoreProvider store) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(children: [
        const Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey),
        const SizedBox(width: 6),
        const Text('Financial Year',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: Colors.grey)),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              value: _selectedFy,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A)),
              items: _fyOptions.map((fy) => DropdownMenuItem(
                value: fy, child: Text('FY $fy'),
              )).toList(),
              onChanged: (fy) {
                if (fy == null) return;
                setState(() => _selectedFy = fy);
                store.fetchItcSummary(fy: fy);
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => store.fetchItcSummary(fy: _selectedFy),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.refresh_rounded, size: 18, color: AppColors.primary),
          ),
        ),
      ]),
    );
  }

  Widget _buildItcContent(Map<String, dynamic> summary) {
    final quarters  = (summary['quarters'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final yearTot   = summary['yearTotals'] as Map<String, dynamic>? ?? {};
    final fy        = summary['fy'] as String? ?? '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 80),
      children: [
        // ── FY total banner ───────────────────────────────────────────────
        _fyBanner(fy, yearTot),
        const SizedBox(height: 12),

        // ── Quarter cards ─────────────────────────────────────────────────
        ...quarters.map((q) => _quarterCard(q)),

        // ── Filing note ───────────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withAlpha(8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withAlpha(25)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, size: 14, color: Colors.blue),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'These are estimated ITC figures based on purchase records. '
                'Actual ITC eligible for credit depends on supplier GSTR-1 '
                'filings visible in GSTR-2B. Verify before filing GSTR-3B.',
                style: TextStyle(fontSize: 10, color: Colors.blue, height: 1.5),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _fyBanner(String fy, Map<String, dynamic> t) {
    final itc    = (t['totalItc'] ?? 0).toDouble();
    final cgst   = (t['itcCgst']  ?? 0).toDouble();
    final sgst   = (t['itcSgst']  ?? 0).toDouble();
    final igst   = (t['itcIgst']  ?? 0).toDouble();
    final amount = (t['totalAmount'] ?? 0).toDouble();
    final wt     = (t['totalWeight']  ?? 0).toDouble();
    final inv    = (t['invoices']     ?? 0) as int;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withAlpha(230),
                   AppColors.primary.withAlpha(180)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.savings_outlined, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text('FY $fy — Full Year ITC',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: Colors.white70)),
          ]),
          const SizedBox(height: 10),
          Text('₹${_fmt(itc)}',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
                  color: Colors.white)),
          const Text('Total ITC Claimable',
              style: TextStyle(fontSize: 11, color: Colors.white70)),
          const Divider(color: Colors.white24, height: 20),
          Row(children: [
            _bnrCell('CGST Credit', '₹${_fmt(cgst)}'),
            _bnrCell('SGST Credit', '₹${_fmt(sgst)}'),
            if (igst > 0) _bnrCell('IGST Credit', '₹${_fmt(igst)}'),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _bnrCell('Invoices', '$inv'),
            _bnrCell('Metal Wt',  '${wt.toStringAsFixed(3)} g'),
            _bnrCell('Taxable',  '₹${_compact(amount)}'),
          ]),
        ],
      ),
    );
  }

  Widget _bnrCell(String label, String value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.white60)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: Colors.white)),
        ]),
      );

  Widget _quarterCard(Map<String, dynamic> q) {
    final label   = q['label']   as String? ?? '';
    final quarter = q['quarter'] as String? ?? '';
    final totals  = q['totals']  as Map<String, dynamic>? ?? {};
    final byMetal = q['byMetal'] as Map<String, dynamic>? ?? {};

    final itc  = (totals['totalItc'] ?? 0).toDouble();
    final cgst = (totals['itcCgst']  ?? 0).toDouble();
    final sgst = (totals['itcSgst']  ?? 0).toDouble();
    final igst = (totals['itcIgst']  ?? 0).toDouble();
    final invoices = (totals['invoices'] ?? 0) as int;
    final wt   = (totals['totalWeight'] ?? 0).toDouble();
    final empty = invoices == 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: empty ? Colors.grey.shade100 : Colors.green.withAlpha(30)),
        boxShadow: empty ? [] : [
          BoxShadow(color: Colors.black.withAlpha(4),
              blurRadius: 6, offset: const Offset(0, 1)),
        ],
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: empty ? Colors.grey[50] : Colors.green.withAlpha(8),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: empty
                    ? Colors.grey.withAlpha(18)
                    : Colors.green.withAlpha(22),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(quarter,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w900,
                        color: empty ? Colors.grey[400] : Colors.green.shade700)),
              ),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: empty ? Colors.grey[400] : const Color(0xFF1A1A1A))),
              if (!empty)
                Text('$invoices invoice${invoices > 1 ? 's' : ''} · '
                    '${wt.toStringAsFixed(3)} g',
                    style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            ]),
            const Spacer(),
            if (!empty)
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('₹${_fmt(itc)}',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900,
                        color: Colors.green.shade700)),
                const Text('ITC',
                    style: TextStyle(fontSize: 9, color: Colors.grey)),
              ])
            else
              Text('No data', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
          ]),
        ),

        if (!empty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(children: [
              // ITC split
              Row(children: [
                _itcSplitCell('CGST Credit', cgst, Colors.indigo),
                const SizedBox(width: 8),
                _itcSplitCell('SGST Credit', sgst, Colors.indigo),
                if (igst > 0) ...[
                  const SizedBox(width: 8),
                  _itcSplitCell('IGST Credit', igst, Colors.purple),
                ],
              ]),

              // Metal breakdown (if multiple metals)
              if (byMetal.length > 1) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),
                ...byMetal.entries.map((e) {
                  final m    = e.key;
                  final data = e.value as Map<String, dynamic>;
                  final mItc = (data['totalItc'] ?? 0).toDouble();
                  final mWt  = (data['totalWeight'] ?? 0).toDouble();
                  final mInv = (data['invoices'] ?? 0) as int;
                  final col  = _metalColor(m);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Container(width: 6, height: 6,
                          decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(m[0].toUpperCase() + m.substring(1),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      Text('$mInv inv · ${mWt.toStringAsFixed(3)} g',
                          style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                      const Spacer(),
                      Text('₹${_fmt(mItc)}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                              color: Colors.green.shade700)),
                    ]),
                  );
                }),
              ],
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _itcSplitCell(String label, double amount, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: color.withAlpha(10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[500])),
            const SizedBox(height: 3),
            Text('₹${_fmt(amount)}',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: color)),
          ]),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Shared helpers
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildEmpty(String title, String sub) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
                color: Colors.grey[100], shape: BoxShape.circle),
            child: Icon(Icons.bar_chart_rounded, size: 32, color: Colors.grey[400]),
          ),
          const SizedBox(height: 14),
          Text(title, style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: Colors.grey[700])),
          const SizedBox(height: 4),
          Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              textAlign: TextAlign.center),
        ]),
      );

  Widget _buildError(String err, StoreProvider store) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.cloud_off_outlined, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(err, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => store.fetchItcSummary(fy: _selectedFy),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ]),
        ),
      );

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      const m = ['Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${dt.day} ${m[dt.month - 1]} ${dt.year}';
    } catch (_) { return isoDate; }
  }

  Color _metalColor(String metal) {
    switch (metal.toLowerCase()) {
      case 'gold':     return const Color(0xFFF59E0B);
      case 'silver':   return const Color(0xFF6B7280);
      case 'platinum': return const Color(0xFF3B82F6);
      default:         return Colors.teal;
    }
  }

  String _fmt(double v) =>
      v.toStringAsFixed(2).replaceAllMapped(
          RegExp(r'(\d)(?=(\d{2})+(\d)(?!\d))'), (m) => '${m[1]},');

  String _compact(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000)   return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)     return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}
