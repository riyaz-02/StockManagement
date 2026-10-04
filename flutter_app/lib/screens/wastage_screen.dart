import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/stock_summary_models.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../providers/store_provider.dart';

const _categories = ['Manufacturing', 'Polishing', 'Stone Setting', 'Other'];

Color _statusColor(String s) => s == 'approved' ? Colors.green.shade700 : s == 'rejected' ? Colors.red.shade700 : Colors.orange.shade800;
String _statusLabel(String s, bool bn) => s == 'approved' ? (bn ? 'অনুমোদিত' : 'Approved') : s == 'rejected' ? (bn ? 'বাতিল' : 'Rejected') : (bn ? 'অপেক্ষায়' : 'Waiting');

/// Metal lost in making. Counts in the Summary only after someone other than the reporter approves it.
class WastageScreen extends StatefulWidget {
  const WastageScreen({super.key});

  @override
  State<WastageScreen> createState() => _WastageScreenState();
}

class _WastageScreenState extends State<WastageScreen> {
  String _status = '';
  bool _loading = true;
  List<WastageReport> _reports = [];
  Map<String, dynamic> _totals = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await context.read<StoreProvider>().fetchWastage(status: _status.isEmpty ? null : _status);
    if (!mounted) return;
    setState(() { _reports = r.reports; _totals = r.totals; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final bn = context.watch<LanguageProvider>().currentLanguage == 'bn';
    final auth = context.watch<AuthProvider>();
    final filters = [['', bn ? 'সব' : 'All'], ['pending', bn ? 'অপেক্ষায়' : 'Waiting'], ['approved', bn ? 'অনুমোদিত' : 'Approved'], ['rejected', bn ? 'বাতিল' : 'Rejected']];
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(title: Text(bn ? 'মেটাল ক্ষতির রিপোর্ট' : 'Wastage reports'), backgroundColor: Colors.white, foregroundColor: const Color(0xFF1A1A1A), elevation: 0),
      floatingActionButton: auth.can('wastage.report')
          ? FloatingActionButton.extended(
              onPressed: () async { if (await showWastageForm(context) == true) _load(); },
              icon: const Icon(Icons.add),
              label: Text(bn ? 'ক্ষতি জানান' : 'Report wastage'),
            )
          : null,
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final f in filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(f[1]), selected: _status == f[0], onSelected: (_) { setState(() => _status = f[0]); _load(); }),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _reports.isEmpty
                      ? ListView(children: [Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(bn ? 'কোনো রিপোর্ট নেই।' : 'No reports.', style: const TextStyle(color: Colors.grey))))])
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                          itemCount: _reports.length + 1,
                          itemBuilder: (_, i) {
                            if (i == 0) return _totalsLine(bn);
                            final w = _reports[i - 1];
                            final c = _statusColor(w.status);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 0,
                              child: ListTile(
                                onTap: () async { if (await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => WastageDetailScreen(report: w))) == true) _load(); },
                                leading: CircleAvatar(backgroundColor: (w.metal == 'gold' ? const Color(0xFFD4A017) : const Color(0xFF94A3B8)).withOpacity(0.2), child: Text(w.metal == 'gold' ? 'Au' : 'Ag', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                                title: Text('${w.amount.toStringAsFixed(3)} g · ${w.category}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text('${w.date} · ${w.reportedBy}${w.reason.isNotEmpty ? '\n${w.reason}' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                                isThreeLine: w.reason.isNotEmpty,
                                trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(10)), child: Text(_statusLabel(w.status, bn), style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 11))),
                              ),
                            );
                          },
                        ),
                ),
        ),
      ]),
    );
  }

  Widget _totalsLine(bool bn) {
    final a = _totals['approved'];
    final p = _totals['pending'];
    // The server sends {status: {gold: {grams, count}, silver: {grams, count}}}.
    double grams(dynamic m, String metal) {
      final v = m is Map ? m[metal] : null;
      final g = v is Map ? v['grams'] : v;
      return g is num ? g.toDouble() : 0;
    }
    String g(dynamic m) => '${grams(m, 'gold').toStringAsFixed(3)} g ${bn ? 'স্বর্ণ' : 'gold'} · ${grams(m, 'silver').toStringAsFixed(3)} g ${bn ? 'রূপা' : 'silver'}';
    if (a == null && p == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('${bn ? 'অনুমোদিত' : 'Approved'}: ${g(a)}\n${bn ? 'অপেক্ষায় (এখনো ধরা হয়নি)' : 'Waiting (not counted yet)'}: ${g(p)}', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
    );
  }
}

/// One report: details, Change (reporter, while waiting), Approve / Reject (not the reporter's own).
class WastageDetailScreen extends StatefulWidget {
  final WastageReport report;
  const WastageDetailScreen({super.key, required this.report});

  @override
  State<WastageDetailScreen> createState() => _WastageDetailScreenState();
}

class _WastageDetailScreenState extends State<WastageDetailScreen> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    final bn = context.read<LanguageProvider>().currentLanguage == 'bn';
    final w = widget.report;
    final ctl = TextEditingController();
    final reversing = !approve && w.status == 'approved';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? (bn ? 'অনুমোদন করবেন?' : 'Approve this wastage?') : reversing ? (bn ? 'অনুমোদন ফেরত নেবেন?' : 'Reverse the approval?') : (bn ? 'বাতিল করবেন?' : 'Reject this wastage?')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${w.amount.toStringAsFixed(3)} g ${w.metal} · ${w.category}'),
          if (approve) Text(bn ? 'অনুমোদনের পর এটি হিসাবে ধরা হবে।' : 'Once approved it counts in the Summary.', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 10),
          TextField(controller: ctl, maxLines: 2, decoration: InputDecoration(border: const OutlineInputBorder(), labelText: approve ? (bn ? 'মন্তব্য (ঐচ্ছিক)' : 'Comment (optional)') : (bn ? 'কারণ লিখুন (আবশ্যক)' : 'Why (required)'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(bn ? 'ফিরে যান' : 'Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(approve ? (bn ? 'অনুমোদন' : 'Approve') : (bn ? 'বাতিল করুন' : 'Reject'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final err = await context.read<StoreProvider>().decideWastage(w.id, approve: approve, comment: ctl.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bn = context.watch<LanguageProvider>().currentLanguage == 'bn';
    final auth = context.watch<AuthProvider>();
    final w = widget.report;
    final mine = auth.user?.id == w.reportedById;
    final boss = ['admin', 'owner'].contains((auth.user?.role ?? '').toLowerCase());
    final canChange = w.status == 'pending' && auth.can('wastage.report') && (mine || boss);
    final canApprove = auth.can('wastage.approve') && ((w.status == 'pending' && (!mine || boss)) );
    final canReverse = auth.can('wastage.approve') && w.status == 'approved' && boss;
    final c = _statusColor(w.status);
    Widget row(String k, String v) => v.isEmpty ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 110, child: Text(k, style: TextStyle(color: Colors.grey[600], fontSize: 13))), Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)))]));
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(title: Text(bn ? 'ক্ষতির রিপোর্ট' : 'Wastage report'), backgroundColor: Colors.white, foregroundColor: const Color(0xFF1A1A1A), elevation: 0),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(12)), child: Text(
          w.status == 'approved' ? (bn ? 'অনুমোদিত: এটি হিসাবে ধরা হচ্ছে।' : 'Approved: this counts in the Summary.') : w.status == 'rejected' ? (bn ? 'বাতিল: এটি হিসাবে ধরা হয় না।' : 'Rejected: this does not count.') : (bn ? 'অনুমোদনের অপেক্ষায়: এখনো হিসাবে ধরা হয়নি।' : 'Waiting for approval: not counted yet.'),
          style: TextStyle(color: c, fontWeight: FontWeight.w700),
        )),
        const SizedBox(height: 12),
        row(bn ? 'ধাতু' : 'Metal', w.metal == 'gold' ? (bn ? 'স্বর্ণ' : 'Gold') : (bn ? 'রূপা' : 'Silver')),
        row(bn ? 'ওজন' : 'Weight', '${w.amount.toStringAsFixed(3)} g'),
        row(bn ? 'তারিখ' : 'Date', w.date),
        row(bn ? 'ধরন' : 'Category', w.category),
        row(bn ? 'কারণ' : 'Reason', w.reason),
        row(bn ? 'মন্তব্য' : 'Remarks', w.remarks),
        row(bn ? 'জানিয়েছেন' : 'Reported by', w.reportedBy),
        row(bn ? 'সিদ্ধান্ত নিয়েছেন' : 'Decided by', w.approvedBy),
        row(bn ? 'সিদ্ধান্তের মন্তব্য' : 'Decision note', w.comment),
        row(bn ? 'সংযুক্তি' : 'Attachment', w.attachmentName),
        const SizedBox(height: 18),
        if (_busy) const Center(child: CircularProgressIndicator()) else Wrap(spacing: 10, runSpacing: 10, children: [
          if (canChange) OutlinedButton.icon(onPressed: () async { if (await showWastageForm(context, existing: w) == true && mounted) Navigator.pop(context, true); }, icon: const Icon(Icons.edit_outlined, size: 18), label: Text(bn ? 'পরিবর্তন' : 'Change')),
          if (canApprove) ElevatedButton.icon(onPressed: () => _decide(true), icon: const Icon(Icons.check, size: 18), label: Text(bn ? 'অনুমোদন' : 'Approve')),
          if (canApprove) OutlinedButton.icon(onPressed: () => _decide(false), icon: const Icon(Icons.close, size: 18), label: Text(bn ? 'বাতিল' : 'Reject')),
          if (canReverse) OutlinedButton.icon(onPressed: () => _decide(false), icon: const Icon(Icons.undo, size: 18), label: Text(bn ? 'অনুমোদন ফেরত' : 'Reverse approval')),
        ]),
        if (w.status == 'pending' && mine && !boss) Padding(padding: const EdgeInsets.only(top: 12), child: Text(bn ? 'আপনার নিজের রিপোর্ট আপনি অনুমোদন করতে পারবেন না; অন্য কাউকে করতে হবে।' : 'You cannot approve your own report; someone else must.', style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
      ]),
    );
  }
}

/// The report / change form. Resolves true when saved. The server checks everything again.
Future<bool?> showWastageForm(BuildContext context, {WastageReport? existing}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom), child: _WastageForm(existing: existing)),
  );
}

class _WastageForm extends StatefulWidget {
  final WastageReport? existing;
  const _WastageForm({this.existing});

  @override
  State<_WastageForm> createState() => _WastageFormState();
}

class _WastageFormState extends State<_WastageForm> {
  late String _metal;
  late String _category;
  late DateTime _date;
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  final _remarks = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final w = widget.existing;
    _metal = w?.metal.isNotEmpty == true ? w!.metal : 'gold';
    _category = w != null && _categories.contains(w.category) ? w.category : _categories.first;
    _date = w != null ? (DateTime.tryParse(w.date) ?? DateTime.now()) : DateTime.now();
    if (w != null) { _amount.text = w.amount.toString(); _reason.text = w.reason; _remarks.text = w.remarks; }
  }

  String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final bn = context.read<LanguageProvider>().currentLanguage == 'bn';
    final a = double.tryParse(_amount.text.trim());
    if (a == null || a <= 0) { setState(() => _error = bn ? 'শূন্যের বেশি ওজন লিখুন' : 'Enter a weight above zero'); return; }
    setState(() { _busy = true; _error = null; });
    final err = await context.read<StoreProvider>().reportWastage({
      'date': _ymd(_date), 'metal': _metal, 'amount': a, 'category': _category, 'reason': _reason.text.trim(), 'remarks': _remarks.text.trim(),
    }, editId: widget.existing?.id);
    if (!mounted) return;
    if (err != null) { setState(() { _busy = false; _error = err; }); return; }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final bn = context.watch<LanguageProvider>().currentLanguage == 'bn';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.existing == null ? (bn ? 'মেটাল ক্ষতি জানান' : 'Report wastage') : (bn ? 'রিপোর্ট পরিবর্তন' : 'Change the report'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(bn ? 'অনুমোদন না হওয়া পর্যন্ত এটি হিসাবে ধরা হবে না।' : 'It counts only after someone else approves it.', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 14),
        SegmentedButton<String>(
          segments: [ButtonSegment(value: 'gold', label: Text(bn ? 'স্বর্ণ' : 'Gold')), ButtonSegment(value: 'silver', label: Text(bn ? 'রূপা' : 'Silver'))],
          selected: {_metal},
          onSelectionChanged: (s) => setState(() => _metal = s.first),
        ),
        const SizedBox(height: 12),
        TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(fontSize: 18), decoration: InputDecoration(border: const OutlineInputBorder(), labelText: bn ? 'ওজন (গ্রাম)' : 'Weight (grams)', suffixText: 'g')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _category,
          decoration: InputDecoration(border: const OutlineInputBorder(), labelText: bn ? 'ধরন' : 'Category'),
          items: [for (final c in _categories) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
            if (d != null) setState(() => _date = d);
          },
          child: InputDecorator(decoration: InputDecoration(border: const OutlineInputBorder(), labelText: bn ? 'তারিখ' : 'Date', suffixIcon: const Icon(Icons.calendar_today, size: 18)), child: Text(_ymd(_date))),
        ),
        const SizedBox(height: 12),
        TextField(controller: _reason, decoration: InputDecoration(border: const OutlineInputBorder(), labelText: bn ? 'কারণ' : 'Reason')),
        const SizedBox(height: 12),
        TextField(controller: _remarks, maxLines: 2, decoration: InputDecoration(border: const OutlineInputBorder(), labelText: bn ? 'মন্তব্য (ঐচ্ছিক)' : 'Remarks (optional)')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600))),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(bn ? 'ফিরে যান' : 'Cancel'))),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton(onPressed: _busy ? null : _save, child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(bn ? 'সেভ' : 'Save'))),
        ]),
      ]),
    );
  }
}
