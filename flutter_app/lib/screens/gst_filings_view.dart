import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../services/api_service.dart';
import '../widgets/bill_ui.dart';
import '../widgets/gst_widgets.dart';
import 'gst_returns_view.dart' show daysText;

final _dmy = DateFormat('dd MMM yyyy');
Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _l(dynamic v) => v is List ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];

Color statusColor(String s, int daysLeft) => switch (s) {
      'filed' => kGstGreen,
      'overdue' => kGstRed,
      'due-soon' => daysLeft <= 3 ? kGstAmber : kGstIndigo,
      _ => kGstSlate,
    };

/// Due dates (upcoming and overdue), filed history and the reminders that were sent.
class FilingsView extends StatelessWidget {
  const FilingsView({super.key, required this.cal, required this.canFile, required this.onMark, required this.onEdit, required this.onSettings});
  final Map<String, dynamic> cal;
  final bool canFile;
  final void Function(Map<String, dynamic> item) onMark;
  final void Function(Map<String, dynamic> item) onEdit;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final items = _l(cal['items']);
    final open = items.where((i) => i['status'] != 'filed' && i['status'] != 'untracked').toList()..sort((a, b) => '${a['due']}'.compareTo('${b['due']}'));
    final overdue = open.where((i) => i['status'] == 'overdue').toList();
    final coming = open.where((i) => i['status'] != 'overdue').take(8).toList();
    final filed = items.where((i) => i['status'] == 'filed').toList()..sort((a, b) => '${_m(b['filing'])['filedOn']}'.compareTo('${_m(a['filing'])['filedOn']}'));
    final untracked = items.where((i) => i['status'] == 'untracked').length;
    final reminders = _l(cal['recentReminders']);
    final quarterly = cal['frequency'] == 'quarterly';

    return ListView(padding: const EdgeInsets.fromLTRB(10, 10, 10, 30), children: [
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.black12)),
        child: Row(children: [
          const Icon(Icons.calendar_month_outlined, color: kGstIndigo),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(quarterly ? 'Quarterly filing (QRMP)' : 'Monthly filing', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              Text(
                  quarterly
                      ? 'GSTR-1 by the 13th, GSTR-3B by the ${cal['qrmpDay3b']}th after each quarter; tax paid every month (PMT-06) by the 25th'
                      : 'GSTR-1 by the 11th and GSTR-3B by the 20th of the next month',
                  style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
            ]),
          ),
          TextButton(onPressed: onSettings, child: const Text('Change')),
        ]),
      ),
      if (overdue.isNotEmpty) ...[
        _heading('Overdue', kGstRed, overdue.length),
        for (final i in overdue) _card(i),
      ],
      _heading('Coming up', kGstIndigo, coming.length),
      if (coming.isEmpty) const Padding(padding: EdgeInsets.all(10), child: Text('Nothing due soon', style: TextStyle(color: Colors.black45))),
      for (final i in coming) _card(i),
      if (untracked > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text('$untracked earlier due date${untracked == 1 ? ' is' : 's are'} not tracked. Change "Follow filings from" in the settings to include them.', style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
        ),
      _heading('Filed', kGstGreen, filed.length),
      if (filed.isEmpty) const Padding(padding: EdgeInsets.all(10), child: Text('Returns you mark as filed appear here', style: TextStyle(color: Colors.black45))),
      for (final i in filed) _filedCard(i),
      if (reminders.isNotEmpty) ...[
        _heading('Reminders sent', kGstSlate, reminders.length),
        for (final r in reminders)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
            child: Row(children: [
              const Icon(Icons.notifications_active_outlined, size: 18, color: kGstSlate),
              const SizedBox(width: 8),
              Expanded(child: Text('${r['title']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
              Text(r['at'] == null ? '' : _dmy.format(DateTime.parse('${r['at']}').toLocal()), style: const TextStyle(fontSize: 11, color: Colors.black45)),
            ]),
          ),
      ],
    ]);
  }

  Widget _heading(String t, Color c, int n) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
        child: Row(children: [
          Container(width: 4, height: 16, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(t, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: c)),
          const SizedBox(width: 6),
          StatusPill('$n', c),
        ]),
      );

  Widget _card(Map<String, dynamic> i) {
    final left = (i['daysLeft'] as num?)?.toInt() ?? 0;
    final c = statusColor('${i['status']}', left);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withOpacity(0.4)), boxShadow: [BoxShadow(color: c.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Row(children: [
        Container(
          width: 46,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Text(DateTime.parse('${i['due']}').day.toString(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)),
            Text(DateFormat('MMM').format(DateTime.parse('${i['due']}')), style: TextStyle(fontSize: 10.5, color: c)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${i['type']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            Text('${i['periodLabel']}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 3),
            StatusPill(left < 0 ? 'Overdue · ${daysText(left)}' : 'Due ${daysText(left)}', c),
          ]),
        ),
        if (canFile) FilledButton(style: FilledButton.styleFrom(backgroundColor: kGstGreen, minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 12)), onPressed: () => onMark(i), child: const Text('Mark filed')),
      ]),
    );
  }

  Widget _filedCard(Map<String, dynamic> i) {
    final f = _m(i['filing']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.black12)),
      child: Row(children: [
        const Icon(Icons.check_circle, color: kGstGreen),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${i['type']} · ${i['periodLabel']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
            Text('Filed ${_dmy.format(DateTime.parse('${f['filedOn']}'))}${(f['arn'] ?? '').toString().isEmpty ? '' : ' · ARN ${f['arn']}'}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            if (gd(f['taxLiability']) > 0 || gd(f['cashPaid']) > 0)
              Text('Tax ${inr0(gd(f['taxLiability']))} · ITC ${inr0(gd(f['itcUsed']))} · Cash ${inr0(gd(f['cashPaid']))}${gd(f['lateFee']) + gd(f['interest']) > 0 ? ' · Late fee & interest ${inr0(gd(f['lateFee']) + gd(f['interest']))}' : ''}',
                  style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
          ]),
        ),
        if (canFile) IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 19), onPressed: () => onEdit(i)),
      ]),
    );
  }
}

/// Record (or edit) that a return was filed. Returns true when saved.
Future<bool?> showFilingSheet(
  BuildContext context, {
  required String type,
  required String period,
  required String periodLabel,
  Map<String, dynamic>? existing,
  double tax = 0,
  double itc = 0,
  double cash = 0,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => _FilingSheet(type: type, period: period, periodLabel: periodLabel, existing: existing, tax: tax, itc: itc, cash: cash),
  );
}

class _FilingSheet extends StatefulWidget {
  const _FilingSheet({required this.type, required this.period, required this.periodLabel, this.existing, required this.tax, required this.itc, required this.cash});
  final String type, period, periodLabel;
  final Map<String, dynamic>? existing;
  final double tax, itc, cash;

  @override
  State<_FilingSheet> createState() => _FilingSheetState();
}

class _FilingSheetState extends State<_FilingSheet> {
  final _api = ApiService();
  late DateTime _date;
  final _arn = TextEditingController();
  final _tax = TextEditingController();
  final _itc = TextEditingController();
  final _cash = TextEditingController();
  final _late = TextEditingController();
  final _interest = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  String _num(double v) => v == 0 ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2));

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e != null ? DateTime.parse('${e['filedOn']}') : DateTime.now();
    _arn.text = '${e?['arn'] ?? ''}';
    _tax.text = _num(e != null ? gd(e['taxLiability']) : widget.tax);
    _itc.text = _num(e != null ? gd(e['itcUsed']) : widget.itc);
    _cash.text = _num(e != null ? gd(e['cashPaid']) : widget.cash);
    _late.text = _num(gd(e?['lateFee']));
    _interest.text = _num(gd(e?['interest']));
    _note.text = '${e?['note'] ?? ''}';
  }

  @override
  void dispose() {
    for (final c in [_arn, _tax, _itc, _cash, _late, _interest, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  double _d(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final body = {
        'returnType': widget.type,
        'period': widget.period,
        'filedOn': DateFormat('yyyy-MM-dd').format(_date),
        'arn': _arn.text.trim(),
        'taxLiability': _d(_tax),
        'itcUsed': _d(_itc),
        'cashPaid': _d(_cash),
        'lateFee': _d(_late),
        'interest': _d(_interest),
        'note': _note.text.trim(),
      };
      final res = widget.existing == null ? await _api.gstCreateFiling(body) : await _api.gstUpdateFiling('${widget.existing!['_id']}', body);
      if (!mounted) return;
      if (res['success'] == true) {
        Navigator.pop(context, true);
      } else {
        setState(() => _error = '${res['message'] ?? 'Could not save'}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _money(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        style: const TextStyle(fontSize: 13.5),
        decoration: billDec(label, kGstGreen, prefixText: '₹ '),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.check_circle_outline, color: kGstGreen),
            const SizedBox(width: 8),
            Expanded(child: Text('${widget.type} · ${widget.periodLabel}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2017, 7), lastDate: DateTime.now());
                  if (d != null) setState(() => _date = d);
                },
                child: InputDecorator(decoration: billDec('Filed on', kGstGreen, suffix: const Icon(Icons.calendar_today, size: 15)), child: Text(_dmy.format(_date), style: const TextStyle(fontSize: 13.5))),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _arn, textCapitalization: TextCapitalization.characters, style: const TextStyle(fontSize: 13.5), decoration: billDec('ARN (optional)', kGstGreen))),
          ]),
          if (widget.type == 'GSTR-3B' || widget.type == 'PMT-06') ...[
            const SizedBox(height: 10),
            Row(children: [Expanded(child: _money(_tax, 'Tax on return')), const SizedBox(width: 8), Expanded(child: _money(_itc, 'Paid by ITC'))]),
            const SizedBox(height: 10),
            Row(children: [Expanded(child: _money(_cash, 'Paid in cash')), const SizedBox(width: 8), Expanded(child: _money(_late, 'Late fee'))]),
            const SizedBox(height: 10),
            _money(_interest, 'Interest'),
          ],
          const SizedBox(height: 10),
          TextField(controller: _note, style: const TextStyle(fontSize: 13.5), decoration: billDec('Note (optional)', kGstSlate)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12.5, fontWeight: FontWeight.w600))),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: kGstGreen),
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check, size: 20),
              label: Text(widget.existing == null ? 'Save as filed' : 'Save changes', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}
