import 'package:flutter/material.dart';
import '../services/api_service.dart';

String _s(dynamic v) => (v ?? '').toString();
int _i(dynamic v) => (v is num) ? v.toInt() : int.tryParse(_s(v)) ?? 0;

/// Box-by-box progress of a tally and the list of pieces still to find (with their box and slot), so staff know where to
/// walk next. After the tally is locked it shows what was recorded as not found. Reloads whenever [refreshKey] changes.
class TallyProgressCard extends StatefulWidget {
  const TallyProgressCard({super.key, required this.tallyId, required this.refreshKey, required this.locked});
  final String tallyId;
  final int refreshKey;
  final bool locked;
  @override
  State<TallyProgressCard> createState() => _TallyProgressCardState();
}

class _TallyProgressCardState extends State<TallyProgressCard> {
  Map<String, dynamic>? _d;
  bool _showMissing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TallyProgressCard old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey || old.locked != widget.locked) _load();
  }

  Future<void> _load() async {
    try {
      final r = await ApiService().tallySummary(widget.tallyId);
      if (mounted) setState(() => _d = Map<String, dynamic>.from(r['data'] as Map));
    } catch (_) {/* the rest of the screen still works */}
  }

  List<Map<String, dynamic>> _list(dynamic v) => (v as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return const SizedBox.shrink();
    final boxes = _list(d['boxes']);
    final missing = _list(d['missing']);
    final sold = _list(d['soldSince']);
    if (boxes.isEmpty && missing.isEmpty && sold.isEmpty) return const SizedBox.shrink();
    final frozen = d['frozen'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (boxes.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.fromLTRB(12, 12, 12, 4), child: Text('Box by box', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
          for (final b in boxes.take(30))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(children: [
                Expanded(flex: 4, child: Text(_s(b['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                Expanded(
                  flex: 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: _i(b['total']) == 0 ? 0 : _i(b['scanned']) / _i(b['total']), minHeight: 6, backgroundColor: Colors.grey[200], valueColor: AlwaysStoppedAnimation(_i(b['missing']) == 0 ? Colors.green : Colors.orange)),
                  ),
                ),
                SizedBox(width: 56, child: Text(_i(b['missing']) == 0 ? 'done ✓' : '${_i(b['scanned'])}/${_i(b['total'])}', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _i(b['missing']) == 0 ? Colors.green : Colors.black87))),
              ]),
            ),
          const SizedBox(height: 6),
        ],
        if (missing.isNotEmpty)
          InkWell(
            onTap: () => setState(() => _showMissing = !_showMissing),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(children: [
                Icon(Icons.search, size: 18, color: Colors.orange.shade800),
                const SizedBox(width: 6),
                Expanded(child: Text(frozen ? '${missing.length} pieces were not found' : 'Still to find: ${missing.length}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.orange.shade900))),
                Icon(_showMissing ? Icons.expand_less : Icons.expand_more, size: 20),
              ]),
            ),
          ),
        if (_showMissing)
          for (final m in missing.take(100))
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              title: Text(_s(m['name']).isEmpty ? _s(m['barcode']) : _s(m['name']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('${_s(m['barcode'])}  ·  ${_s(m['box'])}${m['slot'] == null ? '' : ', slot ${m['slot']}'}', style: const TextStyle(fontSize: 11.5)),
              trailing: Text('${_s(m['weight'])} g', style: const TextStyle(fontSize: 12)),
            ),
        if (sold.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Text('${sold.length} piece${sold.length == 1 ? ' was' : 's were'} sold while this tally ran: not counted as missing.', style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade700)),
          ),
      ]),
    );
  }
}
