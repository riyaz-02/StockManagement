import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';
import '../services/live_service.dart';

String _s(dynamic v) => (v ?? '').toString();
double _n(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(_s(v)) ?? 0;
String _rs(double v) => v <= 0 ? '—' : '₹${NumberFormat('#,##,##0.##', 'en_IN').format(v)}';

/// Today's gold / silver rate at the top of Home. Set it once in the morning; every new bill and form starts from it.
/// The colour tells the story: green = set today, orange = an old rate, red = never set.
class RateStrip extends StatefulWidget {
  /// compact: just the two rates and one status icon (no sentences), for the Home screen.
  const RateStrip({super.key, this.compact = false});
  final bool compact;
  @override
  State<RateStrip> createState() => _RateStripState();
}

class _RateStripState extends State<RateStrip> {
  StreamSubscription<LiveEvent>? _live;

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  final _api = ApiService();
  Map<String, dynamic> _r = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    // the rate changed on the website or on another phone: show it at once
    _live = LiveService.instance.events.where((e) => e.type == 'rate.changed' || e.type == 'reset').listen((_) {
      if (mounted) _load();
    });
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
    final bn = context.read<LanguageProvider>().currentLanguage == 'bn';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(bn ? 'আজকের দর' : "Today's rate"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: gold, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: bn ? 'সোনা ₹ / গ্রাম' : 'Gold ₹ / gram', border: const OutlineInputBorder(), prefixText: '₹ ')),
          const SizedBox(height: 10),
          TextField(controller: silver, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: bn ? 'রূপা ₹ / গ্রাম' : 'Silver ₹ / gram', border: const OutlineInputBorder(), prefixText: '₹ ')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(bn ? 'বাতিল' : 'Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(bn ? 'সেভ' : 'Save'))],
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
    if (!_loaded) return SizedBox(height: widget.compact ? 58 : 74);
    final bn = context.watch<LanguageProvider>().currentLanguage == 'bn';
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
    if (widget.compact) {
      // Two rates and one status icon: green tick = set today, orange = an old rate, red = never set. No sentences.
      final icon = never ? Icons.error_rounded : (today ? Icons.check_circle_rounded : Icons.warning_amber_rounded);
      return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: canEdit ? _edit : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: tone.withOpacity(0.45), width: 1.3)),
          child: Row(children: [
            Expanded(child: _cell(bn ? 'সোনা' : 'Gold', _rs(gold), const Color(0xFFB8860B))),
            Container(width: 1, height: 30, color: Colors.grey.shade300),
            Expanded(child: _cell(bn ? 'রূপা' : 'Silver', _rs(silver), const Color(0xFF64748B))),
            Icon(icon, color: tone, size: 24),
            if (canEdit) ...[const SizedBox(width: 6), Icon(Icons.edit_outlined, color: tone, size: 18)],
          ]),
        ),
      );
    }
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
