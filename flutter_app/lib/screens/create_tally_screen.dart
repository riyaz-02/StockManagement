import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/tally_provider.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_toast.dart';

String _s(dynamic v) => (v ?? '').toString();

/// Start a stock tally. Nothing to type: the app shows what it will count (from the stock itself) and one button starts it.
class CreateTallyScreen extends StatefulWidget {
  const CreateTallyScreen({super.key});

  @override
  State<CreateTallyScreen> createState() => _CreateTallyScreenState();
}

class _CreateTallyScreenState extends State<CreateTallyScreen> {
  final _name = TextEditingController();
  Map<String, dynamic>? _pv;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await ApiService().tallyPreview();
      if (mounted) setState(() => _pv = Map<String, dynamic>.from(r['data'] as Map));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    final provider = Provider.of<TallyProvider>(context, listen: false);
    final tally = await provider.createTally(description: _name.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (tally != null) {
      showAppSnackBar(context, const SnackBar(content: Text('Tally started'), backgroundColor: Colors.green));
      Navigator.pop(context);
    } else {
      showAppSnackBar(context, SnackBar(content: Text(provider.error ?? 'Could not start the tally'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pv = _pv;
    final running = pv?['running'] as Map?;
    final metals = (pv?['metals'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text('Start stock tally', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 8), FilledButton(onPressed: _load, child: const Text('Retry'))])))
          : pv == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(16), children: [
                  const Text('A tally checks that every piece the app has in stock is really in the shop. You scan each piece; anything you do not find is listed at the end.', style: TextStyle(fontSize: 13, color: Colors.black54)),
                  const SizedBox(height: 14),
                  if (running != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.shade200)),
                      child: Text('A tally is already running: "${_s(running['description'])}". Finish or lock it before starting a new one.', style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w600)),
                    ),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('This tally will count', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(child: _big('${pv['items']}', 'pieces')),
                        Expanded(child: _big('${pv['containers']}', 'boxes')),
                      ]),
                      const Divider(height: 22),
                      for (final m in metals)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            Expanded(child: Text(_s(m['metalType']).isEmpty ? '' : '${_s(m['metalType'])[0].toUpperCase()}${_s(m['metalType']).substring(1)}', style: const TextStyle(fontWeight: FontWeight.w700))),
                            Text('${m['items']} pieces  ·  ${m['weight']} g', style: const TextStyle(fontSize: 13)),
                          ]),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  TextField(controller: _name, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: 'Name (optional, e.g. Monthly tally)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _busy || running != null || (pv['items'] ?? 0) == 0 ? null : _start,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(_busy ? 'Starting...' : 'START TALLY', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    ),
                  ),
                ]),
    );
  }

  Widget _big(String v, String l) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(v, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)), Text(l, style: const TextStyle(fontSize: 12, color: Colors.black54))]);
}
