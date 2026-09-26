import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';

String _s(dynamic v) => (v ?? '').toString();
double _n(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(_s(v)) ?? 0;
String _rs(double v) => v <= 0 ? '—' : '₹${NumberFormat('#,##,##0.##', 'en_IN').format(v)}';

/// Today's gold / silver rate at the top of Home. Set it once in the morning; every new bill and form starts from it.
/// The colour tells the story: green = set today, orange = an old rate, red = never set.
class RateStrip extends StatefulWidget {
  const RateStrip({super.key});
  @override
  State<RateStrip> createState() => _RateStripState();
}

class _RateStripState extends State<RateStrip> {
  final _api = ApiService();
  Map<String, dynamic> _r = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.rates();
      if (mounted) setState(() {
            _r = Map<String, dynamic>.from(r['data'] as Map? ?? {});
            _loaded = true;
          });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _edit() async {
    final gold = TextEditingController(text: _n(_r['gold']) > 0 ? _n(_r['gold']).toString().replaceFirst(RegExp(r'\.0$'), '') : '');
    final silver = TextEditingController(text: _n(_r['silver']) > 0 ? _n(_r['silver']).toString().replaceFirst(RegExp(r'\.0$'), '') : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Today's rate"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Rupees per gram. New bills, old metal and stock forms start from these.', style: TextStyle(fontSize: 12.5, color: Colors.black54)),
          const SizedBox(height: 12),
          TextField(controller: gold, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Gold ₹ / gram', border: OutlineInputBorder(), prefixText: '₹ ')),
          const SizedBox(height: 10),
          TextField(controller: silver, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Silver ₹ / gram', border: OutlineInputBorder(), prefixText: '₹ ')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))],
      ),
    );
    if (ok != true) return;
    try {
      final r = await _api.ratesSave({'gold': gold.text.trim(), 'silver': silver.text.trim()});
      if (!mounted) return;
      if (r['success'] == false) {
        showAppSnackBar(context, SnackBar(content: Text(_s(r['message'])), backgroundColor: Colors.red.shade700));
        return;
      }
      setState(() => _r = Map<String, dynamic>.from(r['data'] as Map? ?? {}));
      showAppSnackBar(context, SnackBar(content: const Text('Rate saved'), backgroundColor: Colors.green.shade700));
    } catch (e) {
      if (mounted) showAppSnackBar(context, SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red.shade700));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox(height: 74);
    final canEdit = context.watch<AuthProvider>().can('rates.edit');
    final gold = _n(_r['gold']), silver = _n(_r['silver']);
    final at = DateTime.tryParse(_s(_r['updatedAt']))?.toLocal();
    final today = _r['updatedToday'] == true;
    final never = gold <= 0 && silver <= 0;
    final Color tone = never ? Colors.red.shade700 : (today ? const Color(0xFF15803D) : const Color(0xFFB45309));
    final note = never
        ? "Set today's rate"
        : today
            ? 'Set today ${DateFormat('hh:mm a').format(at!)}${_s(_r['updatedByName']).isEmpty ? '' : ' by ${_s(_r['updatedByName'])}'}'
            : 'Old rate from ${at == null ? '' : DateFormat('dd MMM').format(at)}: update it';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: canEdit ? _edit : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(color: tone.withOpacity(0.07), borderRadius: BorderRadius.circular(16), border: Border.all(color: tone.withOpacity(0.35))),
        child: Row(children: [
          Expanded(child: _cell('Gold / gram', _rs(gold), const Color(0xFFB8860B))),
          Container(width: 1, height: 34, color: tone.withOpacity(0.25)),
          Expanded(child: _cell('Silver / gram', _rs(silver), const Color(0xFF64748B))),
          Expanded(
            flex: 2,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(note, textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: tone)),
              if (canEdit) Padding(padding: const EdgeInsets.only(top: 2), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.edit_outlined, size: 14, color: tone), const SizedBox(width: 3), Text('Change', style: TextStyle(fontSize: 11.5, color: tone))])),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _cell(String label, String value, Color c) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)),
        ]),
      );
}
