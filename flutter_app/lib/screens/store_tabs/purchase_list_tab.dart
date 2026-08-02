import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../../providers/store_provider.dart';
import '../../models/purchase_model.dart';
import '../../utils/app_colors.dart';
import '../add_purchase_screen.dart';

class PurchaseListTab extends StatefulWidget {
  const PurchaseListTab({super.key});

  @override
  State<PurchaseListTab> createState() => _PurchaseListTabState();
}

class _PurchaseListTabState extends State<PurchaseListTab> {
  String? _filterMetal;
  String _sort = 'date_desc';

  static const _sortOptions = [
    _SO('date_desc',   'Date: Newest First',  Icons.arrow_downward),
    _SO('date_asc',    'Date: Oldest First',  Icons.arrow_upward),
    _SO('amount_desc', 'Amount: High → Low',  Icons.trending_down),
    _SO('amount_asc',  'Amount: Low → High',  Icons.trending_up),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<StoreProvider>(
      builder: (context, store, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FC),
          body: Column(
            children: [
              if (store.metalTotals.isNotEmpty) _totalsBar(store),
              _filterSortRow(store),
              Expanded(child: _body(store)),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () async {
              final ok = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const AddPurchaseScreen()),
              );
              if (ok == true && context.mounted) {
                store.fetchPurchases(metalType: _filterMetal, sort: _sort);
                store.fetchStockDashboard();
              }
            },
            backgroundColor: AppColors.primary,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('New Purchase',
                style: TextStyle(fontWeight: FontWeight.w600)),
            elevation: 3,
          ),
        );
      },
    );
  }

  // ── Totals header ─────────────────────────────────────────────────────────
  Widget _totalsBar(StoreProvider store) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: store.metalTotals.entries.map((e) {
          final wt  = (e.value['totalWeight'] as num?)?.toDouble() ?? 0.0;
          final amt = (e.value['totalAmount'] as num?)?.toDouble() ?? 0.0;
          final cnt = (e.value['count']       as num?)?.toInt()    ?? 0;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(
                  right: e.key != store.metalTotals.keys.last ? 8 : 0),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: _mc(e.key).withAlpha(15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _mc(e.key).withAlpha(40)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(width: 6, height: 6,
                        decoration: BoxDecoration(
                            color: _mc(e.key), shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Expanded(child: Text(
                      e.key[0].toUpperCase() + e.key.substring(1),
                      style: TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w700, color: _mc(e.key)),
                      overflow: TextOverflow.ellipsis,
                    )),
                    Text('$cnt', style: TextStyle(
                        fontSize: 9, color: Colors.grey[500])),
                  ]),
                  const SizedBox(height: 2),
                  Text('${wt.toStringAsFixed(3)} g',
                      style: TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w800, color: _mc(e.key))),
                  Text('₹${_rupee(amt)}',
                      style: TextStyle(fontSize: 9, color: Colors.grey[600])),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Filter + sort row ─────────────────────────────────────────────────────
  Widget _filterSortRow(StoreProvider store) {
    final metals = [null, 'gold', 'silver', 'platinum'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: metals.map((m) {
              final sel   = _filterMetal == m;
              final label = m == null ? 'All' : m[0].toUpperCase() + m.substring(1);
              final color = m == null ? AppColors.primary : _mc(m);
              return GestureDetector(
                onTap: () {
                  setState(() => _filterMetal = m);
                  store.fetchPurchases(metalType: m, sort: _sort);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: sel ? color.withAlpha(20) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: sel ? color : Colors.grey.shade200,
                        width: sel ? 1.5 : 1),
                  ),
                  child: Text(label, style: TextStyle(
                      fontSize: 12,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      color: sel ? color : Colors.grey[600])),
                ),
              );
            }).toList()),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _sortSheet(store),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(children: [
              const Icon(Icons.sort_rounded, size: 13, color: Colors.grey),
              const SizedBox(width: 4),
              Text(_sortLabel(_sort),
                  style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            ]),
          ),
        ),
      ]),
    );
  }

  void _sortSheet(StoreProvider store) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Sort By',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            for (final opt in _sortOptions)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  setState(() => _sort = opt.key);
                  store.fetchPurchases(metalType: _filterMetal, sort: opt.key);
                  Navigator.pop(context);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: _sort == opt.key
                        ? AppColors.primary.withAlpha(12) : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    Icon(opt.icon, size: 16,
                        color: _sort == opt.key
                            ? AppColors.primary : Colors.grey[500]),
                    const SizedBox(width: 10),
                    Text(opt.label, style: TextStyle(
                        fontWeight: _sort == opt.key
                            ? FontWeight.w700 : FontWeight.w500,
                        color: _sort == opt.key
                            ? AppColors.primary : Colors.grey[700])),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── List body ─────────────────────────────────────────────────────────────
  Widget _body(StoreProvider store) {
    if (store.isPurchasesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (store.purchasesError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.cloud_off_outlined, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(store.purchasesError ?? '', textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
                onPressed: store.fetchPurchases,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry')),
          ]),
        ),
      );
    }
    if (store.purchases.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 80, height: 80,
              decoration: BoxDecoration(
                  color: Colors.grey[100], shape: BoxShape.circle),
              child: Icon(Icons.receipt_long_outlined,
                  size: 36, color: Colors.grey[400])),
          const SizedBox(height: 16),
          Text('No purchases yet', style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16, color: Colors.grey[700])),
          const SizedBox(height: 6),
          Text(
            _filterMetal != null
                ? 'No ${_filterMetal![0].toUpperCase()}${_filterMetal!.substring(1)} purchases'
                : 'Tap + New Purchase to add the first entry',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: () =>
          store.fetchPurchases(metalType: _filterMetal, sort: _sort),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        itemCount: store.purchases.length,
        itemBuilder: (_, i) => _card(context, store.purchases[i], store),
      ),
    );
  }

  // ── Purchase card ─────────────────────────────────────────────────────────
  Widget _card(BuildContext ctx, Purchase p, StoreProvider store) {
    final color = _mc(p.metalType);
    return GestureDetector(
      // Tap → open view details directly
      onTap: () => _viewDetails(ctx, p, store),
      // Long press → action menu (view / edit / delete)
      onLongPress: () => _showActions(ctx, p, store),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(5),
              blurRadius: 6, offset: const Offset(0, 1))],
        ),
        child: Column(children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
            decoration: BoxDecoration(
              color: color.withAlpha(8),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                    color: color.withAlpha(20),
                    borderRadius: BorderRadius.circular(5)),
                child: Text(p.metalType.toUpperCase(),
                    style: TextStyle(fontSize: 9,
                        fontWeight: FontWeight.w800, color: color,
                        letterSpacing: 0.4)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(p.invoiceNumber,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                  overflow: TextOverflow.ellipsis)),
              if (p.attachmentMeta.isNotEmpty || p.attachments.isNotEmpty) ...[
                Icon(Icons.attach_file_rounded,
                    size: 13, color: Colors.grey[400]),
                const SizedBox(width: 4),
              ],
              Text(p.invoiceDateFormatted,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ]),
          ),

          // ── Body ──────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(children: [
              // Supplier / Weight / Rate
              Row(children: [
                _cell('Supplier', p.biller, Icons.business_outlined, flex: 2),
                const SizedBox(width: 6),
                _cell('Weight', '${p.quantity.toStringAsFixed(3)} g',
                    Icons.scale_outlined),
                const SizedBox(width: 6),
                _cell('Rate/g', '₹${_rupee(p.rate)}',
                    Icons.currency_rupee),
              ]),

              if (p.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.notes_outlined, size: 11, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Expanded(child: Text(p.description,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis)),
                ]),
              ],

              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // Financial row — full amounts, small font, no overflow
              Row(children: [
                // Taxable
                Expanded(child: _amtCol('Taxable',
                    '₹${_rupee(p.totalAmount)}', Colors.grey[800]!)),
                _chevron(),
                // GST
                Expanded(child: _amtCol(
                    'GST ${p.gstRate.toStringAsFixed(0)}%',
                    '+₹${_rupee(p.totalGst)}', Colors.indigo)),
                if (p.tdsApplicable) ...[
                  _chevron(),
                  Expanded(child: _amtCol(
                      'TDS ${p.tdsRate.toStringAsFixed(0)}%',
                      '−₹${_rupee(p.tdsAmount)}', Colors.orange)),
                ],
                const SizedBox(width: 8),
                // Net payable — larger, right-aligned
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Net Payable',
                      style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                  Text('₹${_rupee(p.netPayable)}',
                      style: TextStyle(fontSize: 14,
                          fontWeight: FontWeight.w800, color: color)),
                ]),
              ]),

              // ITC hint
              if (p.totalItc > 0) ...[
                const SizedBox(height: 5),
                Row(children: [
                  Icon(Icons.savings_outlined, size: 11,
                      color: Colors.green.shade600),
                  const SizedBox(width: 4),
                  Text('ITC claim: ₹${_rupee(p.totalItc)}',
                      style: TextStyle(fontSize: 10,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600)),
                ]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Long-press action sheet ───────────────────────────────────────────────
  void _showActions(BuildContext ctx, Purchase p, StoreProvider store) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          // Mini header
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: _mc(p.metalType).withAlpha(20),
                  borderRadius: BorderRadius.circular(7)),
              child: Text(p.metalType.toUpperCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                      color: _mc(p.metalType))),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(p.invoiceNumber,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis)),
            Text(p.invoiceDateFormatted,
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ]),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 10),
          _actionTile(
            icon: Icons.visibility_outlined, label: 'View Details',
            color: Colors.blue,
            onTap: () { Navigator.pop(ctx); _viewDetails(ctx, p, store); },
          ),
          _actionTile(
            icon: Icons.edit_outlined, label: 'Edit Purchase',
            color: Colors.orange,
            onTap: () async {
              Navigator.pop(ctx);
              final ok = await Navigator.push<bool>(ctx,
                  MaterialPageRoute(
                      builder: (_) => AddPurchaseScreen(purchase: p)));
              if (ok == true && ctx.mounted) {
                store.fetchPurchases(metalType: _filterMetal, sort: _sort);
                store.fetchStockDashboard();
              }
            },
          ),
          _actionTile(
            icon: Icons.delete_outline_rounded, label: 'Delete Purchase',
            color: Colors.red,
            onTap: () { Navigator.pop(ctx); _confirmDelete(ctx, p, store); },
          ),
        ]),
      ),
    );
  }

  Widget _actionTile({required IconData icon, required String label,
      required Color color, required VoidCallback onTap}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(children: [
            Container(width: 36, height: 36,
                decoration: BoxDecoration(
                    color: color.withAlpha(15),
                    borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 18, color: color)),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: color)),
          ]),
        ),
      );

  // ── View details bottom sheet (tap or from action menu) ───────────────────
  void _viewDetails(BuildContext ctx, Purchase p, StoreProvider store) {
    final color = _mc(p.metalType);
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.78,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2))),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: color.withAlpha(20),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(p.metalType.toUpperCase(),
                      style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w800, color: color)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('Invoice #${p.invoiceNumber}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700))),
                // Edit shortcut button
                GestureDetector(
                  onTap: () async {
                    Navigator.pop(ctx);
                    final ok = await Navigator.push<bool>(ctx,
                        MaterialPageRoute(
                            builder: (_) => AddPurchaseScreen(purchase: p)));
                    if (ok == true && ctx.mounted) {
                      store.fetchPurchases(
                          metalType: _filterMetal, sort: _sort);
                      store.fetchStockDashboard();
                    }
                  },
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                        color: Colors.orange.withAlpha(15),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.edit_outlined,
                        size: 16, color: Colors.orange),
                  ),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                children: [
                  _section('Supplier', [
                    _d2('Name',  p.biller),
                    _d2('Date',  p.invoiceDateFormatted),
                    if (p.billerGstin.isNotEmpty)
                      _d2('GSTIN', p.billerGstin),
                  ]),
                  _section('Metal & Quantity', [
                    _d2('Metal',  p.metalType[0].toUpperCase() + p.metalType.substring(1)),
                    _d2('Weight', '${p.quantity.toStringAsFixed(3)} g'),
                    _d2('Rate/g', '₹${_rupee(p.rate)}'),
                    if (p.description.isNotEmpty)
                      _d2('Description', p.description),
                  ]),
                  _section('Transaction', [
                    _d2('Type',     p.transactionType),
                    _d2('HSN Code', p.hsnCode),
                    _d2('GST Rate', '${p.gstRate.toStringAsFixed(0)}%'),
                  ]),
                  _section('Financial Summary', [
                    _d2('Taxable Value',  '₹${_rupee(p.totalAmount)}'),
                    if (p.cgstAmount > 0) ...[
                      _d2('CGST', '+₹${_rupee(p.cgstAmount)}'),
                      _d2('SGST', '+₹${_rupee(p.sgstAmount)}'),
                    ],
                    if (p.igstAmount > 0)
                      _d2('IGST', '+₹${_rupee(p.igstAmount)}'),
                    _d2('Total GST',     '₹${_rupee(p.totalGst)}'),
                    _d2('Invoice Total', '₹${_rupee(p.totalPayable)}',
                        bold: true),
                    if (p.tdsApplicable) ...[
                      _d2('TDS (194Q) ${p.tdsRate.toStringAsFixed(0)}%',
                          '−₹${_rupee(p.tdsAmount)}'),
                      _d2('Net Payable', '₹${_rupee(p.netPayable)}',
                          bold: true),
                    ],
                  ]),
                  if (p.totalItc > 0)
                    _section('ITC (Input Tax Credit)', [
                      if (p.itcCgst > 0)
                        _d2('CGST Credit', '₹${_rupee(p.itcCgst)}'),
                      if (p.itcSgst > 0)
                        _d2('SGST Credit', '₹${_rupee(p.itcSgst)}'),
                      if (p.itcIgst > 0)
                        _d2('IGST Credit', '₹${_rupee(p.itcIgst)}'),
                      _d2('Total ITC', '₹${_rupee(p.totalItc)}',
                          bold: true, color: Colors.green.shade700),
                      _d2('Effective Cost', '₹${_rupee(p.effectiveCost)}'),
                    ]),

                  // ── Attachments ──────────────────────────────────────────
                  if (p.attachmentMeta.isNotEmpty)
                    _section('Bill Attachments',
                        [_attachmentsView(p.attachmentMeta)]),

                  if (p.remarks.isNotEmpty)
                    _section('Notes', [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(p.remarks,
                            style: TextStyle(fontSize: 13,
                                color: Colors.grey[700], height: 1.5)),
                      ),
                    ]),
                  if (p.createdByName.isNotEmpty)
                    _section('Audit', [
                      _d2('Entered by', p.createdByName),
                      if (p.createdAtIST != null)
                        _d2('Created at', p.createdAtIST!),
                    ]),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Attachment viewer ─────────────────────────────────────────────────────
  Widget _attachmentsView(List<Map<String, dynamic>> metas) {
    return Column(
      children: metas.asMap().entries.map((entry) {
        final meta   = entry.value;
        final url    = meta['url'] as String? ?? '';
        final format = (meta['format'] as String? ?? '').toLowerCase();
        final name   = meta['originalName'] as String? ?? 'Attachment';
        final isPdf  = format == 'pdf';

        if (isPdf) {
          return GestureDetector(
            onTap: () async {
              final uri = Uri.tryParse(url);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withAlpha(40)),
              ),
              child: Row(children: [
                const Icon(Icons.picture_as_pdf_outlined,
                    color: Colors.red, size: 22),
                const SizedBox(width: 10),
                Expanded(child: Text(name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis)),
                Icon(Icons.open_in_new, size: 15, color: Colors.grey[400]),
              ]),
            ),
          );
        }

        // Image
        return GestureDetector(
          onTap: () => _fullScreenImage(url, name),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Column(children: [
                CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 200,
                  placeholder: (_, __) => Container(
                    height: 200,
                    color: Colors.grey[100],
                    child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    height: 100,
                    color: Colors.grey[100],
                    child: const Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: Colors.grey)),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 7),
                  color: Colors.grey[50],
                  child: Row(children: [
                    const Icon(Icons.image_outlined,
                        size: 12, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(child: Text(name,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[600]),
                        overflow: TextOverflow.ellipsis)),
                    Icon(Icons.fullscreen, size: 14,
                        color: Colors.grey[400]),
                  ]),
                ),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _fullScreenImage(String url, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(name, style: const TextStyle(fontSize: 14)),
            actions: [
              IconButton(
                icon: const Icon(Icons.open_in_new),
                onPressed: () async {
                  final uri = Uri.tryParse(url);
                  if (uri != null && await canLaunchUrl(uri)) {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ),
          body: InteractiveViewer(
            child: Center(
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (_, __) =>
                    const Center(child: CircularProgressIndicator()),
                errorWidget: (_, __, ___) =>
                    const Icon(Icons.broken_image, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, Purchase p, StoreProvider store) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.warning_amber_rounded,
            color: Colors.orange, size: 40),
        title: const Text('Delete Purchase?',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: const TextStyle(
                color: Colors.grey, fontSize: 13, height: 1.5),
            children: [
              const TextSpan(text: 'Invoice '),
              TextSpan(text: p.invoiceNumber,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A))),
              const TextSpan(
                  text: ' will be deleted and the stock entry reversed.'),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              final err = await store.deletePurchase(p.id);
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text(err ?? 'Purchase deleted'),
                  backgroundColor:
                      err != null ? Colors.red : Colors.green,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                ));
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── Detail view helpers ───────────────────────────────────────────────────
  Widget _section(String title, List<Widget> rows) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
              color: Colors.grey[400], letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: rows),
          ),
        ]),
      );

  Widget _d2(String label, String value,
      {bool bold = false, Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120,
              child: Text(label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
          Expanded(child: Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: color ?? const Color(0xFF1A1A1A)))),
        ]),
      );

  // ── Card sub-widgets ──────────────────────────────────────────────────────
  Widget _cell(String label, String value, IconData icon,
      {int flex = 1}) =>
      Expanded(
        flex: flex,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
              color: const Color(0xFFF8F9FC),
              borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 9, color: Colors.grey[400]),
              const SizedBox(width: 2),
              Expanded(child: Text(label,
                  style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                  overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      );

  Widget _amtCol(String label, String value, Color valueColor) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(fontSize: 9, color: Colors.grey[500])),
        Text(value,
            style: TextStyle(fontSize: 11,
                fontWeight: FontWeight.w600, color: valueColor),
            overflow: TextOverflow.ellipsis),
      ]);

  Widget _chevron() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Icon(Icons.chevron_right, size: 13, color: Colors.grey[300]),
      );

  // ── Number formatting ─────────────────────────────────────────────────────
  /// Full Indian number with commas, 2dp for amounts.
  String _rupee(double v) => v
      .toStringAsFixed(2)
      .replaceAllMapped(
          RegExp(r'(\d)(?=(\d{2})+(\d)(?!\d))'), (m) => '${m[1]},');

  String _sortLabel(String key) => _sortOptions
      .firstWhere((o) => o.key == key, orElse: () => _sortOptions.first)
      .label.split(':').first.trim();

  Color _mc(String metal) {
    switch (metal.toLowerCase()) {
      case 'gold':     return const Color(0xFFF59E0B);
      case 'silver':   return const Color(0xFF6B7280);
      case 'platinum': return const Color(0xFF3B82F6);
      default:         return Colors.teal;
    }
  }
}

class _SO {
  final String key; final String label; final IconData icon;
  const _SO(this.key, this.label, this.icon);
}
