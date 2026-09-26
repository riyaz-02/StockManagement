import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../utils/gst_periods.dart';
import '../widgets/bill_ui.dart';
import '../widgets/gst_widgets.dart';

final _dmy = DateFormat('dd MMM yyyy');

String daysText(int d) => d == 0 ? 'today' : d == 1 ? 'tomorrow' : d > 1 ? 'in $d days' : d == -1 ? '1 day ago' : '${-d} days ago';

Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _l(dynamic v) => v is List ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];
String _i2(dynamic v) => inr(gd(v));
String _wt(dynamic v) => gd(v).toStringAsFixed(3);

/// The period picker with the due date and filing status of one return.
class ReturnHeader extends StatelessWidget {
  const ReturnHeader({
    super.key,
    required this.type,
    required this.periods,
    required this.selected,
    required this.onPeriod,
    required this.due,
    required this.filing,
    required this.canFile,
    required this.onFile,
  });
  final String type; // GSTR-1 | GSTR-3B
  final List<GstPeriod> periods;
  final String selected;
  final ValueChanged<String> onPeriod;
  final String? due; // yyyy-mm-dd
  final Map<String, dynamic>? filing;
  final bool canFile;
  final VoidCallback onFile;

  @override
  Widget build(BuildContext context) {
    final dueDate = due == null ? null : DateTime.tryParse(due!);
    final today = DateTime.now();
    final left = dueDate == null ? 0 : DateTime(dueDate.year, dueDate.month, dueDate.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    final filed = filing != null;
    final color = filed ? kGstGreen : left < 0 ? kGstRed : left <= 3 ? kGstAmber : kGstIndigo;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.event_note_outlined, size: 20, color: kGstIndigo),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: periods.any((p) => p.key == selected) ? selected : null,
                isExpanded: true,
                hint: Text(selected),
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Colors.black87),
                items: [for (final p in periods) DropdownMenuItem(value: p.key, child: Text(p.label, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => v == null ? null : onPeriod(v),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StatusPill(type, kGstIndigo),
              if (filed)
                StatusPill('Filed ${_dmy.format(DateTime.parse(filing!['filedOn']))}${(filing!['arn'] ?? '').toString().isEmpty ? '' : ' · ${filing!['arn']}'}', kGstGreen)
              else if (dueDate != null)
                StatusPill('Due ${_dmy.format(dueDate)} · ${daysText(left)}', color),
            ]),
          ),
          if (canFile)
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: filed ? kGstSlate : kGstGreen),
              onPressed: onFile,
              icon: Icon(filed ? Icons.edit_outlined : Icons.check_circle_outline, size: 18),
              label: Text(filed ? 'Edit' : 'Mark filed', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ]),
      ]),
    );
  }
}

/// "Checks before you file": things in this period's own invoices that a GST officer or your CA would ask about.
Widget checksCard(Map<String, dynamic> data) {
  final checks = _l(data['checks']);
  final warns = checks.where((c) => c['severity'] == 'warn').length;
  final color = checks.isEmpty ? kGstGreen : (warns > 0 ? kGstAmber : kGstIndigo);
  return BillCard(
    title: 'Checks before you file',
    icon: checks.isEmpty ? Icons.verified_outlined : Icons.fact_check_outlined,
    color: color,
    trailing: StatusPill(checks.isEmpty ? 'All clear' : (warns > 0 ? '$warns to look at' : '${checks.length} notes'), color),
    child: checks.isEmpty
        ? const Text('Nothing to fix in this period: addresses, PAN, place of supply, cash limit and invoice numbering all look right.', style: TextStyle(fontSize: 12.5, color: Colors.black54))
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final c in checks)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(c['severity'] == 'warn' ? Icons.warning_amber_rounded : Icons.info_outline, size: 18, color: c['severity'] == 'warn' ? kGstAmber : kGstIndigo),
                    const SizedBox(width: 6),
                    Expanded(child: Text('${c['title']} (${c['count']})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                  ]),
                  Padding(padding: const EdgeInsets.only(left: 24, top: 2), child: Text('${c['detail']}', style: const TextStyle(fontSize: 11.5, color: Colors.black54))),
                  Padding(
                    padding: const EdgeInsets.only(left: 24, top: 4),
                    child: Wrap(spacing: 5, runSpacing: 4, children: [
                      for (final n in (c['invoices'] as List? ?? const [])) StatusPill('#$n', c['severity'] == 'warn' ? kGstAmber : kGstIndigo),
                      if (gd(c['more']) > 0) StatusPill('+${gd(c['more']).round()} more', kGstSlate),
                    ]),
                  ),
                ]),
              ),
          ]),
  );
}

/// Sections of the GSTR-1 view: totals, B2CS, B2CL, HSN summary, documents issued.
List<Widget> gstr1Sections(Map<String, dynamic> data, {required void Function(String type) onExport}) {
  final g = _m(data['gstr1']);
  final t = _m(g['totals']);
  final threshold = gd(g['b2clThreshold']);
  final b2cs = _l(g['b2cs']), b2cl = _l(g['b2cl']), hsn = _l(g['hsn']), docs = _l(g['docs']);
  double sum(List<Map<String, dynamic>> rows, String k) => rows.fold<double>(0, (a, r) => a + gd(r[k]));

  Widget exportBtn(String label, String type) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: kGstIndigo),
        onPressed: () => onExport(type),
        icon: const Icon(Icons.ios_share, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      );

  final cn = Map<String, dynamic>.from(data['creditNotes'] is Map ? data['creditNotes'] as Map : {});
  return [
    checksCard(data),
    if ((cn['list'] as List? ?? const []).isNotEmpty)
      BillCard(
        title: 'Credit notes (table 9B)',
        icon: Icons.assignment_return_outlined,
        color: kGstRed,
        trailing: StatusPill('${cn['count'] ?? 0} reduce tax', kGstRed),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          KV('Taxable value', _i2(cn['taxable'])),
          KV('CGST', _i2(cn['cgst'])),
          KV('SGST', _i2(cn['sgst'])),
          KV('IGST', _i2(cn['igst'])),
          const Divider(height: 12),
          for (final n in (cn['list'] as List))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(child: Text('${n['number']}  ·  bill ${n['invoiceNumber']}${n['reducesTax'] == false ? '  (after deadline: tax not reduced)' : ''}', style: TextStyle(fontSize: 11.5, color: n['reducesTax'] == false ? Colors.deepOrange : Colors.black87))),
                Text(_i2(n['total']), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
              ]),
            ),
          const Padding(padding: EdgeInsets.only(top: 6), child: Text('The tax on these notes is already taken off your GSTR-3B liability below.', style: TextStyle(fontSize: 11, color: Colors.black54))),
        ]),
      ),
    BillCard(
      title: 'Outward supplies',
      icon: Icons.summarize_outlined,
      color: kGstIndigo,
      child: Column(children: [
        KV('Invoices', '${t['invoices'] ?? 0}'),
        KV('Taxable value', _i2(t['taxable'])),
        KV('CGST', _i2(t['cgst'])),
        KV('SGST', _i2(t['sgst'])),
        KV('IGST', _i2(t['igst'])),
        const Divider(height: 12),
        KV('Invoice value', _i2(t['invoiceValue']), bold: true),
        const SizedBox(height: 6),
        Align(alignment: Alignment.centerLeft, child: Wrap(spacing: 8, runSpacing: 4, children: [exportBtn('HSN', 'hsn'), exportBtn('B2CS', 'b2cs'), exportBtn('B2CL', 'b2cl'), exportBtn('All invoices', 'register')])),
      ]),
    ),
    BillCard(
      title: 'B2C small (state-wise)',
      icon: Icons.groups_2_outlined,
      color: kGstTeal,
      trailing: const StatusPill('Table 7', kGstTeal),
      child: GstTable(
        color: kGstTeal,
        empty: 'No B2C sales in this period',
        cols: [
          const GstCol('Place of supply', 'place', numeric: false),
          const GstCol('Rate', 'rate', width: 60, fmt: _rate),
          const GstCol('Taxable', 'taxable', width: 110, fmt: _i2),
          const GstCol('IGST', 'igst', width: 100, fmt: _i2),
          const GstCol('CGST', 'cgst', width: 100, fmt: _i2),
          const GstCol('SGST', 'sgst', width: 100, fmt: _i2),
        ],
        rows: b2cs,
        sortKey: 'taxable',
        footer: b2cs.isEmpty ? null : {'place': 'Total', 'rate': '', 'taxable': sum(b2cs, 'taxable'), 'igst': sum(b2cs, 'igst'), 'cgst': sum(b2cs, 'cgst'), 'sgst': sum(b2cs, 'sgst')},
      ),
    ),
    BillCard(
      title: 'B2C large (invoice-wise)',
      icon: Icons.receipt_long_outlined,
      color: kGstPurple,
      trailing: StatusPill('Table 5 · above ${inr0(threshold)}', kGstPurple),
      child: GstTable(
        color: kGstPurple,
        empty: 'No inter-state invoice above ${inr0(threshold)}',
        cols: [
          const GstCol('Invoice', 'number', numeric: false),
          const GstCol('Date', 'date', numeric: false, width: 100),
          const GstCol('Place', 'place', numeric: false, width: 130),
          const GstCol('Value', 'value', width: 110, fmt: _i2),
          const GstCol('Taxable', 'taxable', width: 110, fmt: _i2),
          const GstCol('IGST', 'igst', width: 100, fmt: _i2),
        ],
        rows: b2cl,
        sortKey: 'date',
        asc: true,
      ),
    ),
    BillCard(
      title: 'HSN summary',
      icon: Icons.tag,
      color: kGstAmber,
      trailing: const StatusPill('Table 12', kGstAmber),
      child: GstTable(
        color: kGstAmber,
        empty: 'No sales in this period',
        cols: [
          const GstCol('HSN', 'hsn', numeric: false),
          const GstCol('UQC', 'uqc', numeric: false, width: 56),
          const GstCol('Quantity (g)', 'qty', width: 110, fmt: _wt),
          const GstCol('Total value', 'value', width: 110, fmt: _i2),
          const GstCol('Taxable', 'taxable', width: 110, fmt: _i2),
          const GstCol('IGST', 'igst', width: 96, fmt: _i2),
          const GstCol('CGST', 'cgst', width: 96, fmt: _i2),
          const GstCol('SGST', 'sgst', width: 96, fmt: _i2),
        ],
        rows: hsn,
        sortKey: 'hsn',
        asc: true,
        footer: hsn.isEmpty ? null : {'hsn': 'Total', 'uqc': '', 'qty': sum(hsn, 'qty'), 'value': sum(hsn, 'value'), 'taxable': sum(hsn, 'taxable'), 'igst': sum(hsn, 'igst'), 'cgst': sum(hsn, 'cgst'), 'sgst': sum(hsn, 'sgst')},
      ),
    ),
    BillCard(
      title: 'Documents issued',
      icon: Icons.description_outlined,
      color: kGstSlate,
      trailing: const StatusPill('Table 13', kGstSlate),
      child: GstTable(
        color: kGstSlate,
        empty: 'No invoices in this period',
        cols: [
          const GstCol('Series', 'series', numeric: false),
          const GstCol('From', 'from', numeric: false, width: 110),
          const GstCol('To', 'to', numeric: false, width: 110),
          const GstCol('Total', 'total', width: 70, fmt: _int),
          const GstCol('Cancelled', 'cancelled', width: 90, fmt: _int),
          const GstCol('Net issued', 'net', width: 90, fmt: _int),
        ],
        rows: docs.map((d) => {...d, 'series': d['series'] == 'MAIN' ? 'Main branch' : d['series']}).toList(),
        sortKey: 'series',
        asc: true,
      ),
    ),
  ];
}

String _rate(dynamic v) => v == null || v == '' ? '' : '${gd(v).toStringAsFixed(0)}%';
String _int(dynamic v) => '${gd(v).round()}';

/// Sections of the GSTR-3B view: outward supplies, inter-state, ITC, tax payment, ITC ledger.
List<Widget> gstr3bSections(Map<String, dynamic> data) {
  final b = _m(data['gstr3b']);
  final out = _m(b['outward']);
  final itc = _m(b['itc']);
  final claim = _m(itc['claim']), risk = _m(itc['atRisk']);
  final led = _m(b['ledger']);
  final used = _m(led['used']);
  final cash = _m(led['cash']);
  final liab = _m(b['liability']);
  final inter = _l(b['interstateToUnregistered']);
  double t(Map<String, dynamic> m) => gd(m['igst']) + gd(m['cgst']) + gd(m['sgst']);
  final taxTotal = t(liab); // net of credit notes, same figure the payment table uses
  final riskTotal = t(risk);

  double u(String from, String to) => gd(_m(used[from])[to]);
  final payRows = <Map<String, dynamic>>[
    {'head': 'IGST', 'payable': gd(liab['igst']), 'viaI': u('igst', 'igst'), 'viaC': u('cgst', 'igst'), 'viaS': u('sgst', 'igst'), 'cash': gd(cash['igst'])},
    {'head': 'CGST', 'payable': gd(liab['cgst']), 'viaI': u('igst', 'cgst'), 'viaC': u('cgst', 'cgst'), 'viaS': 0.0, 'cash': gd(cash['cgst'])},
    {'head': 'SGST', 'payable': gd(liab['sgst']), 'viaI': u('igst', 'sgst'), 'viaC': 0.0, 'viaS': u('sgst', 'sgst'), 'cash': gd(cash['sgst'])},
  ];
  double ps(String k) => payRows.fold<double>(0, (a, r) => a + gd(r[k]));

  final open = _m(led['opening']), added = _m(led['added']), avail = _m(led['available']), close = _m(led['closing']);
  final usedI = u('igst', 'igst') + u('igst', 'cgst') + u('igst', 'sgst');
  final usedC = u('cgst', 'cgst') + u('cgst', 'igst');
  final usedS = u('sgst', 'sgst') + u('sgst', 'igst');
  final ledRows = <Map<String, dynamic>>[
    {'head': 'IGST', 'open': gd(open['igst']), 'added': gd(added['igst']), 'avail': gd(avail['igst']), 'used': usedI, 'close': gd(close['igst'])},
    {'head': 'CGST', 'open': gd(open['cgst']), 'added': gd(added['cgst']), 'avail': gd(avail['cgst']), 'used': usedC, 'close': gd(close['cgst'])},
    {'head': 'SGST', 'open': gd(open['sgst']), 'added': gd(added['sgst']), 'avail': gd(avail['sgst']), 'used': usedS, 'close': gd(close['sgst'])},
  ];
  double ls(String k) => ledRows.fold<double>(0, (a, r) => a + gd(r[k]));
  final cashTotal = gd(cash['igst']) + gd(cash['cgst']) + gd(cash['sgst']);

  return [
    checksCard(data),
    // the answer first: what to pay
    Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Cash to pay for this return', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 2),
            Text(inr(cashTotal), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('Tax ${inr(taxTotal)}${gd(_m(data['creditNotes'])['count']) > 0 ? ' (after credit notes)' : ''} − ITC used ${inr(ls('used'))}', style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('ITC carried forward', style: TextStyle(color: Colors.white70, fontSize: 11.5)),
          Text(inr(ls('close')), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
      ]),
    ),
    BillCard(
      title: '3.1(a) Outward taxable supplies',
      icon: Icons.north_east,
      color: kGstIndigo,
      child: Column(children: [
        KV('Taxable value', _i2(out['taxable'])),
        KV('Integrated tax (IGST)', _i2(out['igst'])),
        KV('Central tax (CGST)', _i2(out['cgst'])),
        KV('State / UT tax (SGST)', _i2(out['sgst'])),
        const Divider(height: 12),
        KV('Total tax', inr(taxTotal), bold: true),
      ]),
    ),
    if (inter.isNotEmpty)
      BillCard(
        title: '3.2 Inter-state to unregistered',
        icon: Icons.public,
        color: kGstPurple,
        child: GstTable(
          color: kGstPurple,
          cols: const [GstCol('Place of supply', 'place', numeric: false), GstCol('Taxable', 'taxable', width: 120, fmt: _i2), GstCol('IGST', 'igst', width: 110, fmt: _i2)],
          rows: inter,
          sortKey: 'taxable',
        ),
      ),
    BillCard(
      title: '4. Input tax credit (from purchases)',
      icon: Icons.south_west,
      color: kGstGreen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        KV('IGST', _i2(claim['igst'])),
        KV('CGST', _i2(claim['cgst'])),
        KV('SGST', _i2(claim['sgst'])),
        const Divider(height: 12),
        KV('ITC claimable this period', inr(t(claim)), bold: true, color: kGstGreen),
        Text('${itc['purchases'] ?? 0} purchase bill${(itc['purchases'] ?? 0) == 1 ? '' : 's'} with a supplier GSTIN', style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
        const Padding(padding: EdgeInsets.only(top: 4), child: Text('Claim only what also shows in your GSTR-2B (the auto-drafted statement on the GST portal). Purchases not in GSTR-2B are not yet claimable.', style: TextStyle(fontSize: 11, color: Colors.black45))),
        if (riskTotal > 0) ...[
          const SizedBox(height: 8),
          GstNotice('${inr(riskTotal)} of GST paid to ${itc['riskPurchases']} supplier${(itc['riskPurchases'] ?? 0) == 1 ? '' : 's'} without a GSTIN is NOT counted. ITC can be claimed only with a valid supplier GSTIN on the bill.', icon: Icons.warning_amber_rounded),
        ],
      ]),
    ),
    BillCard(
      title: '6.1 Payment of tax',
      icon: Icons.account_balance_outlined,
      color: kGstAmber,
      child: GstTable(
        color: kGstAmber,
        cols: const [
          GstCol('Head', 'head', numeric: false),
          GstCol('Tax payable', 'payable', width: 110, fmt: _i2),
          GstCol('IGST credit', 'viaI', width: 106, fmt: _i2),
          GstCol('CGST credit', 'viaC', width: 106, fmt: _i2),
          GstCol('SGST credit', 'viaS', width: 106, fmt: _i2),
          GstCol('Paid in cash', 'cash', width: 110, fmt: _i2, bold: true),
        ],
        rows: payRows,
        sortKey: null,
        footer: {'head': 'Total', 'payable': ps('payable'), 'viaI': ps('viaI'), 'viaC': ps('viaC'), 'viaS': ps('viaS'), 'cash': ps('cash')},
      ),
    ),
    BillCard(
      title: 'ITC ledger for this period',
      icon: Icons.account_balance_wallet_outlined,
      color: kGstTeal,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GstTable(
          color: kGstTeal,
          cols: const [
            GstCol('Head', 'head', numeric: false),
            GstCol('Opening', 'open', width: 104, fmt: _i2),
            GstCol('Added', 'added', width: 104, fmt: _i2),
            GstCol('Available', 'avail', width: 104, fmt: _i2),
            GstCol('Used', 'used', width: 104, fmt: _i2),
            GstCol('Closing', 'close', width: 104, fmt: _i2, bold: true),
          ],
          rows: ledRows,
          sortKey: null,
          footer: {'head': 'Total', 'open': ls('open'), 'added': ls('added'), 'avail': ls('avail'), 'used': ls('used'), 'close': ls('close')},
        ),
        const SizedBox(height: 6),
        const Text('Credit is used in the order the law requires: IGST credit first (IGST, then CGST, then SGST); CGST credit only against CGST or IGST; SGST credit only against SGST or IGST.',
            style: TextStyle(fontSize: 11, color: Colors.black45)),
      ]),
    ),
  ];
}
