import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';
import '../utils/gst_periods.dart';
import '../widgets/bill_ui.dart';
import '../widgets/gst_widgets.dart';

/// GST filing settings: how often the returns are filed, reminders, and the ITC starting balance.
/// Anyone with GST access can read them; only those allowed to edit can save.
class GstSettingsScreen extends StatefulWidget {
  const GstSettingsScreen({super.key, required this.canEdit});
  final bool canEdit;

  @override
  State<GstSettingsScreen> createState() => _GstSettingsScreenState();
}

class _GstSettingsScreenState extends State<GstSettingsScreen> {
  final _api = ApiService();
  bool _loading = true, _saving = false;
  String? _error;

  String _frequency = 'monthly';
  int _qrmpDay = 24;
  String _firm = '', _gstin = '';
  String _followFrom = '';
  String _itcFrom = '';
  bool _remindOn = true, _overdue = true, _countNoGstin = false;
  final Set<int> _days = {7, 3, 1, 0};
  final _igst = TextEditingController();
  final _cgst = TextEditingController();
  final _sgst = TextEditingController();
  final _b2cl = TextEditingController();

  static const _dayChoices = [15, 10, 7, 5, 3, 2, 1, 0];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_igst, _cgst, _sgst, _b2cl]) {
      c.dispose();
    }
    super.dispose();
  }

  String _num(dynamic v) {
    final d = gd(v);
    return d == 0 ? '' : (d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2));
  }

  Future<void> _load() async {
    try {
      final res = await _api.gstSettings();
      final d = Map<String, dynamic>.from(res['data']);
      final s = Map<String, dynamic>.from(d['settings']);
      if (!mounted) return;
      setState(() {
        _frequency = '${s['frequency']}';
        _qrmpDay = (d['qrmpDay3b'] as num?)?.toInt() ?? 24;
        _firm = '${d['seller']?['firmName'] ?? ''}';
        _gstin = '${d['seller']?['gstin'] ?? ''}';
        _followFrom = '${s['remindersFrom']}';
        _itcFrom = '${s['trackFrom']}';
        final r = Map<String, dynamic>.from(s['reminders'] ?? {});
        _remindOn = r['enabled'] != false;
        _overdue = r['overdue'] != false;
        _days
          ..clear()
          ..addAll(((r['daysBefore'] as List?) ?? const [7, 3, 1, 0]).map((e) => (e as num).toInt()));
        _countNoGstin = s['countItcWithoutGstin'] == true;
        final o = Map<String, dynamic>.from(s['openingItc'] ?? {});
        _igst.text = _num(o['igst']);
        _cgst.text = _num(o['cgst']);
        _sgst.text = _num(o['sgst']);
        _b2cl.text = _num(s['b2clThreshold']);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  double _d(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    if (_days.isEmpty && _remindOn) {
      showAppSnackBar(context, SnackBar(content: const Text('Pick at least one reminder day'), backgroundColor: Colors.red.shade700));
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await _api.gstUpdateSettings({
        'frequency': _frequency,
        'remindersFrom': _followFrom,
        'trackFrom': _itcFrom,
        'openingItc': {'igst': _d(_igst), 'cgst': _d(_cgst), 'sgst': _d(_sgst)},
        'countItcWithoutGstin': _countNoGstin,
        'b2clThreshold': _d(_b2cl) == 0 ? 100000 : _d(_b2cl),
        'reminders': {'enabled': _remindOn, 'overdue': _overdue, 'daysBefore': _days.toList()..sort((a, b) => b.compareTo(a))},
      });
      if (!mounted) return;
      if (res['success'] == true) {
        Navigator.pop(context, true);
      } else {
        showAppSnackBar(context, SnackBar(content: Text('${res['message'] ?? 'Could not save'}'), backgroundColor: Colors.red.shade700));
      }
    } catch (e) {
      if (mounted) showAppSnackBar(context, SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red.shade700));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // months for the pickers: from 24 months ago to next month
  List<String> get _months {
    final t = DateTime.now();
    return [for (var i = -24; i <= 1; i++) () { final d = DateTime(t.year, t.month + i, 1); return '${d.year}-${d.month.toString().padLeft(2, '0')}'; }()].reversed.toList();
  }

  String _monthLabel(String k) => periodOf(k)?.label ?? k;

  Widget _monthPicker(String label, String value, ValueChanged<String> onChanged) {
    final months = _months;
    return DropdownButtonFormField<String>(
      value: months.contains(value) ? value : null,
      isExpanded: true,
      decoration: billDec(label, kGstIndigo),
      style: const TextStyle(fontSize: 13.5, color: Colors.black87),
      items: [for (final m in months) DropdownMenuItem(value: m, child: Text(_monthLabel(m)))],
      onChanged: widget.canEdit ? (v) => v == null ? null : setState(() => onChanged(v)) : null,
    );
  }

  Widget _money(TextEditingController c, String label) => TextField(
        controller: c,
        enabled: widget.canEdit,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        style: const TextStyle(fontSize: 13.5),
        decoration: billDec(label, kGstGreen, prefixText: '₹ '),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        toolbarHeight: 48,
        backgroundColor: const Color(0xFFF4F5F8),
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text('GST filing settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          if (widget.canEdit && !_loading && _error == null)
            TextButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.red))))
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ListView(padding: const EdgeInsets.fromLTRB(10, 6, 10, 30), children: [
                      if (!widget.canEdit) const GstNotice('You can view these settings but not change them.', icon: Icons.lock_outline),
                      BillCard(
                        title: 'How often do you file?',
                        icon: Icons.event_repeat,
                        color: kGstIndigo,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('$_firm${_gstin.isEmpty ? '' : '  ·  $_gstin'}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          const SizedBox(height: 8),
                          SegmentedButton<String>(
                            showSelectedIcon: false,
                            style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                            segments: const [
                              ButtonSegment(value: 'monthly', label: Text('Monthly'), icon: Icon(Icons.calendar_view_month, size: 17)),
                              ButtonSegment(value: 'quarterly', label: Text('Quarterly'), icon: Icon(Icons.calendar_view_week, size: 17)),
                            ],
                            selected: {_frequency},
                            onSelectionChanged: widget.canEdit ? (s) => setState(() => _frequency = s.first) : null,
                          ),
                          const SizedBox(height: 8),
                          if (_frequency == 'monthly') ...[
                            _rule('GSTR-1', 'by the 11th of the next month'),
                            _rule('GSTR-3B', 'by the 20th of the next month'),
                            const Text('All figures are shown month by month.', style: TextStyle(fontSize: 11.5, color: Colors.black45)),
                          ] else ...[
                            _rule('GSTR-1', 'by the 13th after the quarter'),
                            _rule('GSTR-3B', 'by the $_qrmpDay${_qrmpDay == 22 ? 'nd' : 'th'} after the quarter (your state)'),
                            _rule('Tax payment', 'monthly by the 25th (PMT-06) for the first two months'),
                            const Text('All figures are shown quarter by quarter (Apr–Jun, Jul–Sep, Oct–Dec, Jan–Mar). Quarterly filing (QRMP) is open to taxpayers with turnover up to ₹5 crore.', style: TextStyle(fontSize: 11.5, color: Colors.black45)),
                          ],
                        ]),
                      ),
                      BillCard(
                        title: 'Reminders',
                        icon: Icons.notifications_active_outlined,
                        color: kGstAmber,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Remind me before due dates', style: TextStyle(fontSize: 13.5)), value: _remindOn, onChanged: widget.canEdit ? (v) => setState(() => _remindOn = v) : null),
                          if (_remindOn) ...[
                            const Text('Send a reminder', style: TextStyle(fontSize: 12, color: Colors.black54)),
                            const SizedBox(height: 4),
                            Wrap(spacing: 6, runSpacing: 2, children: [
                              for (final d in _dayChoices)
                                FilterChip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(d == 0 ? 'On the day' : '$d day${d == 1 ? '' : 's'} before', style: const TextStyle(fontSize: 12)),
                                  selected: _days.contains(d),
                                  selectedColor: kGstAmber.withOpacity(0.2),
                                  onSelected: widget.canEdit ? (on) => setState(() => on ? _days.add(d) : _days.remove(d)) : null,
                                ),
                            ]),
                            SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Keep reminding when overdue', style: TextStyle(fontSize: 13.5)), subtitle: const Text('Once a day for 10 days', style: TextStyle(fontSize: 11.5)), value: _overdue, onChanged: widget.canEdit ? (v) => setState(() => _overdue = v) : null),
                            const Text('Reminders go to the admins as push notifications and show as alerts on the GST Summary page. A reminder stops as soon as you mark the return as filed.', style: TextStyle(fontSize: 11.5, color: Colors.black45)),
                          ],
                          const SizedBox(height: 10),
                          _monthPicker('Follow filings from', _followFrom, (v) => _followFrom = v),
                          const Padding(padding: EdgeInsets.only(top: 3, left: 2), child: Text('Returns for earlier periods are not tracked, so old months do not show as overdue.', style: TextStyle(fontSize: 11.5, color: Colors.black45))),
                        ]),
                      ),
                      BillCard(
                        title: 'Input tax credit (ITC)',
                        icon: Icons.account_balance_wallet_outlined,
                        color: kGstGreen,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _monthPicker('Track ITC from', _itcFrom, (v) => _itcFrom = v),
                          const SizedBox(height: 10),
                          const Text('Credit balance at the start of that month (from your last GSTR-3B / credit ledger)', style: TextStyle(fontSize: 12, color: Colors.black54)),
                          const SizedBox(height: 6),
                          Row(children: [Expanded(child: _money(_igst, 'IGST')), const SizedBox(width: 8), Expanded(child: _money(_cgst, 'CGST')), const SizedBox(width: 8), Expanded(child: _money(_sgst, 'SGST'))]),
                          SwitchListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Count purchases without a supplier GSTIN', style: TextStyle(fontSize: 13.5)),
                            subtitle: const Text('Off is safer: ITC needs the supplier\'s GSTIN on the bill', style: TextStyle(fontSize: 11.5)),
                            value: _countNoGstin,
                            onChanged: widget.canEdit ? (v) => setState(() => _countNoGstin = v) : null,
                          ),
                        ]),
                      ),
                      BillCard(
                        title: 'Return tables',
                        icon: Icons.table_chart_outlined,
                        color: kGstTeal,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _money(_b2cl, 'List inter-state sales above (invoice-wise)'),
                          const Padding(padding: EdgeInsets.only(top: 3, left: 2), child: Text('Inter-state sales to customers without a GSTIN above this value go in GSTR-1 table 5 (B2C large). The limit is ₹1,00,000 since 1 Aug 2024.', style: TextStyle(fontSize: 11.5, color: Colors.black45))),
                        ]),
                      ),
                    ]),
                  ),
                ),
    );
  }

  Widget _rule(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 82, padding: const EdgeInsets.symmetric(vertical: 1), child: Text(a, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: kGstIndigo))),
          Expanded(child: Text(b, style: const TextStyle(fontSize: 12.5))),
        ]),
      );
}
