import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';

String _msg(Object e) => e.toString().replaceAll('Exception: ', '');
String _s(dynamic v) => v == null ? '' : v.toString();

/// Settings > Branches & counters: every shop of the firm, with its billing counters and the people who work there.
/// Nothing is ever deleted (old bills point at branches and counters): a branch or a counter is switched off instead.
class BranchesScreen extends StatefulWidget {
  const BranchesScreen({super.key});

  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ApiService().getBranches();
      _branches = (r['data']?['branches'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _error = _msg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _open(Map<String, dynamic>? existing) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _BranchForm(existing: existing),
    );
    if (id == null || !mounted) return;
    await _load();
    if (existing == null && mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => BranchDetailScreen(branchId: id)));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(title: const Text('Branches & counters'), backgroundColor: Colors.white, foregroundColor: const Color(0xFF1A1A1A), elevation: 0),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _open(null), icon: const Icon(Icons.add), label: const Text('New branch'), backgroundColor: const Color(0xFFE94560), foregroundColor: Colors.white),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.red))))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text('Bills, stock and money made from now on are filed under the branch and counter of the person who made them. Nothing already saved is changed.', style: TextStyle(color: Colors.black54, fontSize: 13)),
                      ),
                      for (final b in _branches) _card(b),
                    ],
                  ),
                ),
    );
  }

  Widget _card(Map<String, dynamic> b) {
    final isMain = b['isMain'] == true;
    final off = b['isActive'] == false;
    final place = [_s(b['city']), _s(b['state'])].where((x) => x.isNotEmpty).join(', ');
    Widget chip(String t, Color c) => Container(
          margin: const EdgeInsets.only(right: 6, top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Text(t, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c)),
        );
    return Opacity(
      opacity: off ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 3))]),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => BranchDetailScreen(branchId: _s(b['id']))));
            _load();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFFFDE8EC), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.storefront_rounded, color: Color(0xFFE94560))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_s(b['name']) + (isMain ? '  (built in)' : off ? '  (off)' : ''), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  if (place.isNotEmpty) Text(place, style: const TextStyle(color: Colors.black54, fontSize: 12.5)),
                  Wrap(children: [
                    chip('${b['counterCount'] ?? 0} counter${(b['counterCount'] ?? 0) == 1 ? '' : 's'}', const Color(0xFF0D9488)),
                    chip('${b['staffCount'] ?? 0} staff', const Color(0xFF2563EB)),
                    if (_s(b['invoicePrefix']).isNotEmpty) chip('Bills ${b['invoicePrefix']}-', Colors.blueGrey),
                    if (_s(b['gstin']).isNotEmpty) chip('GSTIN', Colors.blueGrey),
                  ]),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.black38),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Add / change a branch (a bottom sheet). Pops the branch id when saved.
class _BranchForm extends StatefulWidget {
  const _BranchForm({this.existing});
  final Map<String, dynamic>? existing;

  @override
  State<_BranchForm> createState() => _BranchFormState();
}

class _BranchFormState extends State<_BranchForm> {
  late final Map<String, TextEditingController> _c;
  bool _active = true;
  bool _busy = false;
  String? _error;

  static const _fields = [
    ['name', 'Branch name'],
    ['invoicePrefix', 'Letters in front of its bill numbers (e.g. BGB)'],
    ['gstin', 'GSTIN (only if it has its own)'],
    ['code', 'Short code'],
    ['city', 'City'],
    ['state', 'State'],
    ['phone', 'Phone'],
    ['address', 'Address'],
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? const {};
    _c = {for (final f in _fields) f[0]: TextEditingController(text: _s(e[f[0]]))};
    _active = e['isActive'] != false;
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = {for (final f in _fields) f[0]: _c[f[0]]!.text.trim()};
    try {
      final api = ApiService();
      final editing = widget.existing != null;
      final r = editing ? await api.updateBranch(_s(widget.existing!['id']), {...body, 'isActive': _active}) : await api.createBranch(body);
      if (mounted) Navigator.pop(context, _s(r['data']?['id']));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _msg(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final lockedPrefix = editing && _s(widget.existing!['invoicePrefix']).isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(editing ? 'Change branch' : 'Open a new branch', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          for (final f in _fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _c[f[0]],
                textCapitalization: f[0] == 'invoicePrefix' || f[0] == 'gstin' ? TextCapitalization.characters : TextCapitalization.words,
                keyboardType: f[0] == 'phone' ? TextInputType.phone : TextInputType.text,
                decoration: InputDecoration(labelText: f[1], helperText: f[0] == 'invoicePrefix' && lockedPrefix ? 'Cannot be changed once a bill is made' : null, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), isDense: true),
              ),
            ),
          if (editing)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('This branch is open'),
              subtitle: const Text('Switch off to close it for new work (no staff may work there)'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE94560), padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(editing ? 'Save' : 'Open branch'),
          ),
        ]),
      ),
    );
  }
}

/// One branch: its details, its counters and the people who work there.
class BranchDetailScreen extends StatefulWidget {
  const BranchDetailScreen({super.key, required this.branchId});
  final String branchId;

  @override
  State<BranchDetailScreen> createState() => _BranchDetailScreenState();
}

class _BranchDetailScreenState extends State<BranchDetailScreen> {
  Map<String, dynamic> _b = {};
  List<Map<String, dynamic>> _others = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _list(dynamic v) => (v as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  List<Map<String, dynamic>> get _counters => _list(_b['counters']);
  List<Map<String, dynamic>> get _liveCounters => _counters.where((c) => c['isActive'] != false).toList();

  Future<void> _load() async {
    try {
      final r = await ApiService().getBranch(widget.branchId);
      _b = Map<String, dynamic>.from(r['data'] as Map);
      try {
        final u = await ApiService().getUsers();
        _others = _list(u['data']?['users']).where((x) {
          final home = _s(x['branchId']).isEmpty ? 'main' : _s(x['branchId']);
          return x['isActive'] != false && home != widget.branchId;
        }).toList();
      } catch (_) {
        _others = [];
      }
      _error = null;
    } catch (e) {
      _error = _msg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _toast(String text, {bool bad = false}) {
    showAppSnackBar(context, SnackBar(content: Text(text), backgroundColor: bad ? Colors.red : Colors.green));
  }

  Future<void> _editBranch() async {
    final done = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _BranchForm(existing: _b),
    );
    if (done != null) _load();
  }

  Future<void> _counterDialog([Map<String, dynamic>? c]) async {
    final name = TextEditingController(text: _s(c?['name']));
    final code = TextEditingController(text: _s(c?['code']));
    final note = TextEditingController(text: _s(c?['note']));
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(c == null ? 'Add a counter' : 'Change counter'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, autofocus: true, maxLength: 40, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Counter name (e.g. Counter 1, Gold desk)')),
            TextField(controller: code, maxLength: 10, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Short code (optional)')),
            TextField(controller: note, maxLength: 120, decoration: const InputDecoration(labelText: 'Note (optional)')),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  final body = {'name': name.text.trim(), 'code': code.text.trim(), 'note': note.text.trim()};
                  if (c == null) {
                    await ApiService().createCounter(widget.branchId, body);
                  } else {
                    await ApiService().updateCounter(widget.branchId, _s(c['id']), body);
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  set(() => error = _msg(e));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    code.dispose();
    note.dispose();
    if (saved == true) _load();
  }

  Future<void> _toggleCounter(Map<String, dynamic> c, bool on) async {
    try {
      await ApiService().updateCounter(widget.branchId, _s(c['id']), {'isActive': on});
      _load();
    } catch (e) {
      _toast(_msg(e), bad: true);
    }
  }

  Future<void> _setCounterOf(String userId, String counterId) async {
    try {
      await ApiService().assignStaff(widget.branchId, userId, counterId);
      _load();
    } catch (e) {
      _toast(_msg(e), bad: true);
    }
  }

  Future<void> _movePerson() async {
    String? uid;
    String counter = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Move a person here'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: uid,
              decoration: const InputDecoration(labelText: 'Person'),
              items: [for (final u in _others) DropdownMenuItem(value: _s(u['_id'] ?? u['id']), child: Text('${_s(u['name'])} (${_s(u['branchName']).isEmpty ? 'Main branch' : _s(u['branchName'])})', overflow: TextOverflow.ellipsis))],
              onChanged: (v) => set(() => uid = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: counter,
              decoration: const InputDecoration(labelText: 'Counter'),
              items: [const DropdownMenuItem(value: '', child: Text('No counter')), for (final c in _liveCounters) DropdownMenuItem(value: _s(c['id']), child: Text(_s(c['name'])))],
              onChanged: (v) => set(() => counter = v ?? ''),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: uid == null ? null : () => Navigator.pop(ctx, true), child: const Text('Move here')),
          ],
        ),
      ),
    );
    if (ok == true && uid != null) await _setCounterOf(uid!, counter);
  }

  Widget _section(String title, List<Widget> children, {Widget? action}) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 3))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))), if (action != null) action]),
          const SizedBox(height: 6),
          ...children,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final isMain = _b['isMain'] == true;
    final staff = _list(_b['staff']);
    final live = _liveCounters;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(
        title: Text(_s(_b['name']).isEmpty ? 'Branch' : _s(_b['name'])),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        actions: [if (!_loading && _error == null && !isMain) IconButton(tooltip: 'Change details', icon: const Icon(Icons.edit_outlined), onPressed: _editBranch)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.red))))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    _section('Details', [
                      if (isMain) const Text('The built-in branch: all earlier records belong to it. It cannot be changed or switched off, but it can have counters.', style: TextStyle(color: Colors.black54)),
                      if (!isMain) ...[
                        _kv('Status', _b['isActive'] == false ? 'Off' : 'Open'),
                        _kv('Bill numbers', _s(_b['invoicePrefix']).isEmpty ? 'Starts with the branch name' : '${_b['invoicePrefix']}-0001, ${_b['invoicePrefix']}-0002 ...'),
                        _kv('GSTIN', _s(_b['gstin']).isEmpty ? 'The firm\'s GSTIN is used' : _s(_b['gstin'])),
                        _kv('City / state', [_s(_b['city']), _s(_b['state'])].where((x) => x.isNotEmpty).join(', ')),
                        _kv('Phone', _s(_b['phone'])),
                        _kv('Address', _s(_b['address'])),
                      ],
                    ]),
                    _section(
                      'Billing counters',
                      [
                        if (_counters.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No counters yet. Without one, bills are saved with no counter.', style: TextStyle(color: Colors.black54))),
                        for (final c in _counters)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(_s(c['name']) + (_s(c['code']).isEmpty ? '' : '  (${c['code']})'), style: TextStyle(fontWeight: FontWeight.w600, color: c['isActive'] == false ? Colors.black45 : Colors.black87)),
                            subtitle: _s(c['note']).isEmpty ? null : Text(_s(c['note'])),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _counterDialog(c)),
                              Switch(value: c['isActive'] != false, onChanged: (v) => _toggleCounter(c, v)),
                            ]),
                          ),
                        const Padding(padding: EdgeInsets.only(top: 6), child: Text('A counter is a till or desk. Each person can be given one; everything they bill, receive or estimate is saved with it.', style: TextStyle(color: Colors.black54, fontSize: 12))),
                      ],
                      action: TextButton.icon(onPressed: () => _counterDialog(), icon: const Icon(Icons.add, size: 18), label: const Text('Add')),
                    ),
                    _section(
                      'Staff at this branch',
                      [
                        if (staff.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nobody works here yet.', style: TextStyle(color: Colors.black54))),
                        for (final p in staff)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(_s(p['name']) + (p['isActive'] == false ? '  (login off)' : ''), style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${_s(p['role'])}${_s(p['mobile']).isEmpty ? '' : ' · ${p['mobile']}'}'),
                            trailing: PopupMenuButton<String>(
                              tooltip: 'Counter',
                              onSelected: (v) => _setCounterOf(_s(p['id']), v),
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: '', child: Text('No counter')),
                                for (final c in live) PopupMenuItem(value: _s(c['id']), child: Text(_s(c['name']))),
                              ],
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Text(_s(p['counterName']).isEmpty ? 'No counter' : _s(p['counterName']), style: const TextStyle(fontSize: 12.5)),
                                  const Icon(Icons.arrow_drop_down, size: 18),
                                ]),
                              ),
                            ),
                          ),
                      ],
                      action: _others.isNotEmpty && _b['isActive'] != false ? TextButton.icon(onPressed: _movePerson, icon: const Icon(Icons.person_add_alt_1_outlined, size: 18), label: const Text('Move here')) : null,
                    ),
                  ]),
                ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text(v.isEmpty ? '-' : v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}
