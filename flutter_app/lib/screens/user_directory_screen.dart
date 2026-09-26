import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../utils/bilingual.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';
import 'directory_add_screens.dart';

/// The four kinds of people the directory manages. [path] is the API segment
/// under /api/directory.
enum DirectoryKind {
  customers('customers', 'Customers', 'Customer', Icons.people_alt_rounded,
      Color(0xFF2563EB)),
  staff('staff', 'Staff', 'Staff', Icons.badge_rounded, Color(0xFF7C3AED)),
  suppliers('suppliers', 'Suppliers', 'Supplier', Icons.local_shipping_rounded,
      Color(0xFF059669)),
  karigars('karigars', 'Karigars', 'Karigar', Icons.handyman_rounded,
      Color(0xFFD97706));

  const DirectoryKind(
      this.path, this.plural, this.singular, this.icon, this.color);
  final String path;
  final String plural;
  final String singular;
  final IconData icon;
  final Color color;

  String get viewPermission =>
      this == staff ? 'directory.viewStaff' : 'directory.view';
  String get createPermission =>
      this == staff ? 'directory.createStaff' : 'directory.create';
}

String _s(dynamic v) => (v ?? '').toString().trim();

String _joinNonEmpty(Iterable<dynamic> parts, [String sep = ' · ']) =>
    parts.map(_s).where((e) => e.isNotEmpty).join(sep);

/// Display data for one list row, derived from the raw API record.
class _RowData {
  _RowData(this.id, this.title, this.subtitle, this.phone,
      {this.badge, this.detailPath, this.inactive = false, this.source, this.nameBn = ''});
  final String id;
  final String title; // English / primary name
  final String nameBn; // Bengali name (customers)
  final String subtitle;
  final String phone;
  final String? badge;
  final String? detailPath;
  final bool inactive;
  final String? source; // staff tab only: login | profile | karigar

  /// Name as shown to the user: Bengali first with English in brackets when the
  /// app language is Bengali, and the reverse for English.
  String display(String lang) {
    final s = bilingualName(title, nameBn, lang);
    return s.isEmpty ? '(No name)' : s;
  }

  factory _RowData.from(DirectoryKind kind, Map<String, dynamic> r) {
    switch (kind) {
      case DirectoryKind.customers:
        final phone =
            _s(r['whatsapp_no']).isNotEmpty ? _s(r['whatsapp_no']) : _s(r['mobile_no']);
        return _RowData(_s(r['_id']), _s(r['customer_name']), _s(r['address']), phone,
            nameBn: _s(r['customer_name_bengali']), detailPath: 'customers/${r['_id']}');
      case DirectoryKind.staff:
        return _RowData(
            _s(r['id']),
            _s(r['name']),
            _s(r['email']),
            _s(r['mobile']),
            badge: _s(r['role']),
            source: _s(r['source']),
            inactive: r['active'] == false,
            detailPath: 'staff/${r['source']}/${r['id']}');
      case DirectoryKind.suppliers:
      case DirectoryKind.karigars:
        return _RowData(
            _s(r['_id']),
            _joinNonEmpty([r['firstName'], r['lastName']], ' '),
            _joinNonEmpty([r['firmName'], r['city']]),
            _s(r['mobile']),
            badge: _s(r['partyType']),
            detailPath: '${kind.path}/${r['_id']}');
    }
  }
}

Future<void> _launch(Uri uri) async {
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

class UserDirectoryScreen extends StatefulWidget {
  const UserDirectoryScreen({super.key});

  @override
  State<UserDirectoryScreen> createState() => _UserDirectoryScreenState();
}

class _UserDirectoryScreenState extends State<UserDirectoryScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final ValueNotifier<int> _refresh = ValueNotifier(0);
  late final List<DirectoryKind> _kinds;
  late final TabController _tabs;
  Timer? _debounce;
  String _query = '';
  Map<String, dynamic> _counts = {};

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    // Karigars are shown inside the Staff tab, so they get no tab of their own.
    _kinds = DirectoryKind.values
        .where((k) => k != DirectoryKind.karigars && auth.can(k.viewPermission))
        .toList();
    _tabs = TabController(length: _kinds.isEmpty ? 1 : _kinds.length, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {}); // update the FAB label
      });
    _loadCounts();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _refresh.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    try {
      final res = await _api.getDirectorySummary();
      if (mounted && res['success'] == true) {
        setState(() => _counts = Map<String, dynamic>.from(res['data']));
      }
    } catch (_) {}
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  Future<void> _add(DirectoryKind kind) async {
    // Staff tab: ask whether this is a staff member or a karigar.
    if (kind == DirectoryKind.staff) {
      final auth = context.read<AuthProvider>();
      final canStaff = auth.can('directory.createStaff');
      final canKarigar = auth.can('directory.create');
      DirectoryKind? pick =
          canStaff && !canKarigar ? DirectoryKind.staff : (!canStaff && canKarigar ? DirectoryKind.karigars : null);
      pick ??= await showModalBottomSheet<DirectoryKind>(
        context: context,
        constraints: const BoxConstraints(maxWidth: 480),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(DirectoryKind.staff.icon, color: DirectoryKind.staff.color),
              title: const Text('Add Staff'),
              subtitle: const Text('Employee with personal & job details'),
              onTap: () => Navigator.pop(ctx, DirectoryKind.staff),
            ),
            ListTile(
              leading: Icon(DirectoryKind.karigars.icon, color: DirectoryKind.karigars.color),
              title: const Text('Add Karigar'),
              subtitle: const Text('Artisan with business, bank & balance details'),
              onTap: () => Navigator.pop(ctx, DirectoryKind.karigars),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      );
      if (pick == null || !mounted) return;
      kind = pick;
    }
    final Widget screen;
    switch (kind) {
      case DirectoryKind.customers:
        screen = const AddCustomerScreen();
      case DirectoryKind.staff:
        screen = const AddStaffScreen();
      case DirectoryKind.suppliers:
      case DirectoryKind.karigars:
        screen = AddPartyScreen(kind: kind);
    }
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => screen));
    if (saved == true) {
      _refresh.value++;
      _loadCounts();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    const bg = Color(0xFFF7F7FA);

    if (_kinds.isEmpty) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(title: const Text('Users')),
        body: const Center(child: Text('You do not have access to the directory.')),
      );
    }

    final current = _kinds[_tabs.index];
    final canAdd = auth.can(current.createPermission);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: bg,
        foregroundColor: const Color(0xFF1A1A1A),
        toolbarHeight: 46,
        centerTitle: false,
        titleSpacing: 0,
        title: const Text('Users',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(92),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(fontSize: 13.5),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search name, phone, address…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: current.color,
                indicatorColor: current.color,
                unselectedLabelColor: Colors.black54,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                tabs: [
                  for (final k in _kinds)
                    Tab(
                      height: 40,
                      iconMargin: const EdgeInsets.only(bottom: 1),
                      icon: Icon(k.icon, size: 17),
                      text: _counts[k.path] == null
                          ? k.plural
                          : '${k.plural} (${_counts[k.path]})',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton(
              tooltip: current == DirectoryKind.staff
                  ? 'Add staff or karigar'
                  : 'Add ${current.singular.toLowerCase()}',
              backgroundColor: current.color,
              foregroundColor: Colors.white,
              onPressed: () => _add(current),
              child: const Icon(Icons.person_add_alt_1),
            )
          : null,
      body: TabBarView(
        controller: _tabs,
        children: [
          for (final k in _kinds)
            _DirectoryList(
                key: PageStorageKey(k.path),
                kind: k,
                query: _query,
                refresh: _refresh),
        ],
      ),
    );
  }
}

// ── One tab: paginated list ──────────────────────────────────────────────────
class _DirectoryList extends StatefulWidget {
  const _DirectoryList(
      {super.key, required this.kind, required this.query, required this.refresh});
  final DirectoryKind kind;
  final String query;
  final ValueNotifier<int> refresh;

  @override
  State<_DirectoryList> createState() => _DirectoryListState();
}

class _DirectoryListState extends State<_DirectoryList>
    with AutomaticKeepAliveClientMixin {
  final _api = ApiService();
  final _scroll = ScrollController();
  final List<_RowData> _rows = [];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = false;
  int _total = 0;
  String? _error;
  String _filter = 'all'; // staff tab: all | staff | karigar
  int _generation = 0; // discards responses from superseded queries

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        _load();
      }
    });
    widget.refresh.addListener(_reset);
    _load();
  }

  @override
  void didUpdateWidget(covariant _DirectoryList old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _reset();
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_reset);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    _generation++;
    _rows.clear();
    _page = 1;
    _hasMore = true;
    _loading = false;
    _error = null;
    if (mounted) setState(() {});
    await _load();
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    final gen = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.getDirectoryList(widget.kind.path,
          q: widget.query, page: _page);
      if (!mounted || gen != _generation) return;
      final data = List<Map<String, dynamic>>.from(
          (res['data'] as List).map((e) => Map<String, dynamic>.from(e)));
      final pg = res['pagination'] ?? {};
      setState(() {
        _rows.addAll(data.map((r) => _RowData.from(widget.kind, r)));
        _total = pg['total'] ?? _rows.length;
        _hasMore = pg['hasMore'] == true;
        _page++;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final kind = widget.kind;
    final isStaff = kind == DirectoryKind.staff;

    // Staff tab holds staff logins, HR profiles and karigars: filter client-side.
    final rows = !isStaff || _filter == 'all'
        ? _rows
        : _rows.where((r) => (_filter == 'karigar') == (r.source == 'karigar')).toList();

    Widget body;
    if (_rows.isEmpty && _loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_rows.isEmpty && _error != null) {
      body = _Message(
          icon: Icons.cloud_off,
          text: _error!,
          action: TextButton(onPressed: _reset, child: const Text('Retry')));
    } else if (rows.isEmpty) {
      body = _Message(
        icon: kind.icon,
        text: widget.query.isEmpty && _filter == 'all'
            ? 'No ${kind.plural.toLowerCase()} yet.\nTap the add button to create one.'
            : 'Nothing matches your search or filter.',
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _reset,
        child: LayoutBuilder(builder: (context, c) {
          // Phones: one column. Tablets: two/three columns of compact cards.
          final cols = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 640 ? 2 : 1);
          Widget item(int i) => _RowCard(kind: kind, data: rows[i], onChanged: _reset);
          const pad = EdgeInsets.fromLTRB(12, 4, 12, 84);
          if (cols == 1) {
            return ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: pad,
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 5),
              itemBuilder: (_, i) => item(i),
            );
          }
          return GridView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: pad,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisExtent: 62,
              crossAxisSpacing: 8,
              mainAxisSpacing: 6,
            ),
            itemCount: rows.length,
            itemBuilder: (_, i) => item(i),
          );
        }),
      );
    }

    return Column(children: [
      if (isStaff)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: Row(children: [
            for (final f in const [('all', 'All'), ('staff', 'Staff'), ('karigar', 'Karigar')])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                  selected: _filter == f.$1,
                  selectedColor: kind.color.withOpacity(0.15),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (_) => setState(() => _filter = f.$1),
                ),
              ),
          ]),
        ),
      Expanded(child: body),
      if (_loading && _rows.isNotEmpty)
        const Padding(
          padding: EdgeInsets.all(6),
          child: SizedBox(
              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        )
      else if (_error != null && _rows.isNotEmpty)
        TextButton(onPressed: _load, child: Text('$_error - tap to retry'))
      else if (_rows.isNotEmpty)
        // Left-aligned so the floating add button never covers it.
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${rows.length} of $_total ${kind.plural.toLowerCase()}',
                style: const TextStyle(color: Colors.black45, fontSize: 11)),
          ),
        ),
      const SizedBox(height: 2),
    ]);
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Colors.black26),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, height: 1.4)),
            if (action != null) action!,
          ]),
        ),
      );
}

class _RowCard extends StatelessWidget {
  const _RowCard({required this.kind, required this.data, required this.onChanged});
  final DirectoryKind kind;
  final _RowData data;
  final VoidCallback onChanged; // called after this record was edited

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>().currentLanguage;
    final title = data.display(lang);
    final initial = title.isEmpty ? '?' : title.characters.first.toUpperCase();
    // Karigars sit inside the Staff tab: give them their own accent colour.
    final accent = data.source == 'karigar' ? DirectoryKind.karigars.color : kind.color;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final result = await _showDetail(context, kind, data);
          if (result != null && context.mounted) {
            final saved = await _openEdit(context, kind, data, result.record);
            if (saved == true) onChanged();
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: accent.withOpacity(0.12),
                foregroundColor: accent,
                child: Text(initial,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13.5)),
                      ),
                      if (data.badge != null && data.badge!.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        _Chip(data.badge!, accent),
                      ],
                      if (data.inactive) ...[
                        const SizedBox(width: 5),
                        const _Chip('Inactive', Colors.red),
                      ],
                    ]),
                    Text(
                      _joinNonEmpty([data.phone, data.subtitle != data.phone ? data.subtitle : '']),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black54, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              if (data.phone.isNotEmpty)
                IconButton(
                  tooltip: 'Call',
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  icon: Icon(Icons.call, color: accent),
                  onPressed: () => _launch(Uri(scheme: 'tel', path: data.phone)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 10.5, fontWeight: FontWeight.w600)),
      );
}

// ── Detail bottom sheet ──────────────────────────────────────────────────────
/// Returned by the detail sheet when the user taps "Edit".
class _SheetResult {
  _SheetResult(this.record);
  final Map<String, dynamic> record;
}

/// Which audit-log entity a row belongs to; null = not editable from the app
/// (legacy web-admin login accounts).
String? _entityOf(DirectoryKind kind, _RowData row) {
  switch (kind) {
    case DirectoryKind.customers:
      return 'customer';
    case DirectoryKind.suppliers:
      return 'supplier';
    case DirectoryKind.karigars:
      return 'karigar';
    case DirectoryKind.staff:
      return row.source == 'karigar' ? 'karigar' : (row.source == 'profile' ? 'staff' : null);
  }
}

bool _canEdit(AuthProvider a, DirectoryKind kind, _RowData row) {
  final e = _entityOf(kind, row);
  if (e == null) return false;
  return e == 'staff' ? a.can('directory.editStaff') : a.can('directory.edit');
}

/// Opens the edit form for [record]; resolves to true when it was saved.
Future<bool?> _openEdit(BuildContext context, DirectoryKind kind, _RowData row,
    Map<String, dynamic> record) {
  final Widget screen;
  switch (_entityOf(kind, row)) {
    case 'customer':
      screen = AddCustomerScreen(existing: record);
    case 'supplier':
      screen = AddPartyScreen(kind: DirectoryKind.suppliers, existing: record);
    case 'karigar':
      screen = AddPartyScreen(kind: DirectoryKind.karigars, existing: record);
    case 'staff':
      screen = AddStaffScreen(existing: record);
    default:
      return Future.value(false);
  }
  return Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => screen));
}

Future<_SheetResult?> _showDetail(BuildContext context, DirectoryKind kind, _RowData row) {
  return showModalBottomSheet<_SheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    constraints: const BoxConstraints(maxWidth: 560), // centred card on tablets
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => _DetailSheet(kind: kind, row: row),
  );
}

class _DetailSheet extends StatefulWidget {
  const _DetailSheet({required this.kind, required this.row});
  final DirectoryKind kind;
  final _RowData row;

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  late final Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService()
        .getDirectoryRecord(widget.row.detailPath!)
        .then((r) => Map<String, dynamic>.from(r['data']));
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final row = widget.row;
    final lang = context.watch<LanguageProvider>().currentLanguage;
    final auth = context.read<AuthProvider>();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 10),
          Text(row.display(lang),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          if (row.badge != null && row.badge!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: _Chip(row.badge!, kind.color)),
            ),
          const SizedBox(height: 12),
          if (row.phone.isNotEmpty)
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: kind.color,
                      visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Call'),
                  onPressed: () => _launch(Uri(scheme: 'tel', path: row.phone)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.chat, size: 18),
                  label: const Text('WhatsApp'),
                  onPressed: () {
                    final d = row.phone.replaceAll(RegExp(r'\D'), '');
                    _launch(Uri.parse(
                        'https://wa.me/${d.length == 10 ? '91$d' : d}'));
                  },
                ),
              ),
            ]),
          const SizedBox(height: 8),
          FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                      snap.error.toString().replaceFirst('Exception: ', ''),
                      style: const TextStyle(color: Colors.red)),
                );
              }
              final sections = _sections(kind, snap.data!);
              final canEdit = _canEdit(auth, kind, row);
              final entity = _entityOf(kind, row);
              final canHistory = entity != null && auth.can('directory.edit');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (canEdit || canHistory)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(children: [
                        if (canEdit)
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: kind.color,
                                  side: BorderSide(color: kind.color)),
                              icon: const Icon(Icons.edit_outlined, size: 17),
                              label: const Text('Edit details'),
                              onPressed: () => Navigator.pop(context, _SheetResult(snap.data!)),
                            ),
                          ),
                        if (canEdit && canHistory) const SizedBox(width: 10),
                        if (canHistory)
                          TextButton.icon(
                            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                            icon: const Icon(Icons.history, size: 17),
                            label: const Text('History'),
                            onPressed: () => _showHistory(context, entity, _idOf(snap.data!)),
                          ),
                      ]),
                    ),
                  for (final sec in sections)
                    if (sec.value.any((e) => e.value.isNotEmpty)) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 3),
                        child: Text(sec.key.toUpperCase(),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: kind.color)),
                      ),
                      for (final e in sec.value)
                        if (e.value.isNotEmpty) _InfoLine(e.key, e.value),
                    ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

String _idOf(Map<String, dynamic> d) => _s(d['_id'] ?? d['id']);

// ── History ──────────────────────────────────────────────────────────────────
//
// One sheet, one tab per kind of history. To add a new kind (purchases,
// payments, notes ...) add ONE entry to [_historyTabsFor] with a builder that
// returns the tab's content. Nothing else needs to change.

class _HistoryTab {
  const _HistoryTab(this.label, this.icon, this.build, {this.comingSoon = false});
  final String label;
  final IconData icon;
  final Widget Function(String entity, String id) build;
  final bool comingSoon;
}

List<_HistoryTab> _historyTabsFor(String entity) => [
      // Live today: who edited what.
      _HistoryTab('Edits', Icons.edit_note_rounded, (e, id) => _EditsHistory(entity: e, id: id)),
      // Placeholders for what is planned. Swap `_ComingSoon` for a real widget
      // (fed by its own API) when the data exists.
      if (entity == 'customer')
        _HistoryTab('Purchases', Icons.shopping_bag_outlined,
            (e, id) => const _ComingSoon('Purchase history will appear here.'),
            comingSoon: true),
      if (entity == 'supplier')
        _HistoryTab('Purchases', Icons.local_shipping_outlined,
            (e, id) => const _ComingSoon('Purchases from this supplier will appear here.'),
            comingSoon: true),
    ];

void _showHistory(BuildContext context, String entity, String id) {
  final tabs = _historyTabsFor(entity);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.72,
      child: DefaultTabController(
        length: tabs.length,
        child: Column(children: [
          const SizedBox(height: 10),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.black12, borderRadius: BorderRadius.circular(2))),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text('History',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          ),
          if (tabs.length > 1)
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: [
                for (final t in tabs)
                  Tab(
                    height: 38,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(t.icon, size: 16),
                      const SizedBox(width: 5),
                      Text(t.label),
                      if (t.comingSoon)
                        const Padding(
                          padding: EdgeInsets.only(left: 5),
                          child: Icon(Icons.hourglass_empty_rounded, size: 12, color: Colors.black38),
                        ),
                    ]),
                  ),
              ],
            ),
          Expanded(
            child: TabBarView(
              children: [for (final t in tabs) t.build(entity, id)],
            ),
          ),
        ]),
      ),
    ),
  );
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.hourglass_empty_rounded, size: 40, color: Colors.black26),
            const SizedBox(height: 10),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, height: 1.4)),
            const SizedBox(height: 4),
            const Text('Coming soon',
                style: TextStyle(color: Colors.black38, fontSize: 12)),
          ]),
        ),
      );
}

/// "Who changed what": newest edit first, field by field.
class _EditsHistory extends StatefulWidget {
  const _EditsHistory({required this.entity, required this.id});
  final String entity;
  final String id;

  @override
  State<_EditsHistory> createState() => _EditsHistoryState();
}

class _EditsHistoryState extends State<_EditsHistory> with AutomaticKeepAliveClientMixin {
  late final Future<Map<String, dynamic>> _future =
      ApiService().getDirectoryHistory(widget.entity, widget.id);

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
              child: Text(snap.error.toString().replaceFirst('Exception: ', ''),
                  style: const TextStyle(color: Colors.red)));
        }
        final rows = List<Map<String, dynamic>>.from(
            (snap.data!['data'] as List).map((e) => Map<String, dynamic>.from(e)));
        if (rows.isEmpty) {
          return const _ComingSoon('No edits yet.').copyWithoutSoon();
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            for (final r in rows)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${_s(r['byName']).isEmpty ? 'Someone' : _s(r['byName'])}  ·  '
                    '${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(_s(r['at'])).toLocal())}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  for (final c in (r['changes'] as List))
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${c['field']}:  ${_s(c['from']).isEmpty ? '(empty)' : c['from']}  →  ${_s(c['to']).isEmpty ? '(empty)' : c['to']}',
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                ]),
              ),
          ],
        );
      },
    );
  }
}

extension on _ComingSoon {
  // "No edits yet" is an empty state, not a "coming soon" one.
  Widget copyWithoutSoon() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text, style: const TextStyle(color: Colors.black54)),
        ),
      );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 108,
                child: Text(label,
                    style: const TextStyle(color: Colors.black45, fontSize: 12))),
            Expanded(
              child: GestureDetector(
                onLongPress: () {
                  Clipboard.setData(ClipboardData(text: value));
                  showAppSnackBar(context, const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)));
                },
                child: Text(value, style: const TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
      );
}

String _date(dynamic v) {
  final d = DateTime.tryParse(_s(v));
  return d == null ? '' : DateFormat('dd MMM yyyy').format(d.toLocal());
}

String _bal(dynamic b, {bool weight = false}) {
  if (b is! Map) return '';
  final n = weight ? b['weight'] : b['amount'];
  if (n == null || n == 0) return '';
  final unit = weight ? ' ${_s(b['unit'])}' : '';
  return '$n$unit (${_s(b['type'])})';
}

/// Curated, grouped (label → value) entries per record kind. Empty values are
/// hidden by the caller.
List<MapEntry<String, List<MapEntry<String, String>>>> _sections(
    DirectoryKind kind, Map<String, dynamic> d) {
  final base = _sectionsBase(kind, d);
  final by = _s(d['updated_by_name'] ?? d['updatedByName']);
  if (by.isNotEmpty) {
    base.add(MapEntry('Last edited', [
      MapEntry('By', by),
      MapEntry('On', _date(d['updated_at'] ?? d['updatedAt'])),
    ]));
  }
  return base;
}

List<MapEntry<String, List<MapEntry<String, String>>>> _sectionsBase(
    DirectoryKind kind, Map<String, dynamic> d) {
  MapEntry<String, String> e(String l, dynamic v) => MapEntry(l, _s(v));
  switch (kind) {
    case DirectoryKind.customers:
      final p = (d['profile'] ?? {}) as Map;
      final op = (p['opening'] ?? {}) as Map;
      return [
        MapEntry('Contact', [
          // Every number the customer has (app profile carries the full list)
          if ((p['contacts'] as List?)?.isNotEmpty ?? false)
            for (final k in (p['contacts'] as List))
              e(
                  _s(k['label']) == 'whatsapp'
                      ? 'WhatsApp'
                      : (_s(k['label']).isEmpty
                          ? 'Phone'
                          : _s(k['label'])[0].toUpperCase() + _s(k['label']).substring(1)),
                  k['number'])
          else ...[
            e('WhatsApp', d['whatsapp_no']),
            e('Mobile', d['mobile_no']),
            e('Mobile 3', d['mobile_no_3']),
            e('Mobile 4', d['mobile_no_4']),
          ],
          e('Email', d['email']),
          e('Address',
              _joinNonEmpty([d['address'], p['city'], p['state'], p['pincode']], ', ')),
        ]),
        MapEntry('Profile', [
          e('Customer ID', p['customerCode']),
          e('Branch', p['branchName']),
          e('Membership', p['membershipStatus']),
          e('Type', p['customerType']),
          e('S/O · D/O · W/O', p['fatherName']),
          e('Gender', p['gender']),
          e('Date of birth', _date(p['dob'])),
          e('Anniversary', _date(p['anniversary'])),
          e(
              'Referred by',
              (p['referredBy'] is Map)
                  ? (_joinNonEmpty([
                        (p['referredBy'] as Map)['name'],
                        (p['referredBy'] as Map)['mobile'],
                        (p['referredBy'] as Map)['code'],
                      ]).isNotEmpty
                      ? _joinNonEmpty([
                          (p['referredBy'] as Map)['name'],
                          (p['referredBy'] as Map)['mobile'],
                          (p['referredBy'] as Map)['code'],
                        ])
                      : _s((p['referredBy'] as Map)['text']))
                  : ''),
          e('Nickname', d['nickname']),
          e('Bengali name', d['customer_name_bengali']),
        ]),
        MapEntry('Business & tax', [
          e('Business', p['businessName']),
          e('GST no.', p['gstNo']),
          e('PAN', p['panNo']),
          e('Aadhaar', p['aadharNo']),
          e('Tax no.', p['taxNo']),
        ]),
        MapEntry('Opening balance', [
          e('As on', (_bal(op['cash']).isNotEmpty || _bal(op['gold'], weight: true).isNotEmpty || _bal(op['silver'], weight: true).isNotEmpty) ? _date(op['date']) : ''),
          e('Cash', _bal(op['cash'])),
          e('Gold', _bal(op['gold'], weight: true)),
          e('Silver', _bal(op['silver'], weight: true)),
        ]),
        MapEntry('Other', [
          e('Notes', p['notes']),
          e('Notifications', d['notification_type']),
          e('Serial no.', d['sl_no']),
          e('Added by', d['created_by_name']),
          e('Added on', _date(d['created_at'])),
        ]),
      ];
    case DirectoryKind.staff:
      if (d['source'] == 'karigar') return _sectionsBase(DirectoryKind.karigars, d);
      final emp = (d['employment'] ?? {}) as Map;
      final edu = (d['education'] ?? {}) as Map;
      final bank = (emp['bank'] ?? {}) as Map;
      final isLogin = d['source'] == 'login';
      return [
        MapEntry('Contact', [
          e('Branch', d['branchName']),
          e('Mobile', isLogin ? d['contact'] : d['mobile']),
          e('Phone', d['phone']),
          e('Email', d['email']),
          e('Emergency contact',
              _joinNonEmpty([d['emergencyContactName'], d['emergencyContactPhone']])),
          e('Address',
              _joinNonEmpty([d['address'], d['city'], d['state'], d['pincode']], ', ')),
        ]),
        MapEntry('Personal', [
          e('Date of birth', _date(d['dob'])),
          e('Marital status', d['maritalStatus']),
          e('PAN', d['panNo']),
          e('Aadhaar', d['aadharNo']),
        ]),
        MapEntry('Login account', [
          e('Username', d['username']),
          e('Role', d['role']),
          e('Status', d['status']),
          e('Last login', _date(d['last_login'])),
        ]),
        MapEntry('Education', [
          e('Degree', edu['degree']),
          e('Institution', edu['institution']),
          e('Passing year', edu['passingYear']),
          e('Certifications', edu['certifications']),
        ]),
        MapEntry('Employment', [
          e('Department', emp['department']),
          e('Designation', emp['designation']),
          e('Salary', emp['salary'] == 0 ? '' : emp['salary']),
          e('Start date', _date(emp['startDate'])),
          e('Previous company', emp['previousCompany']),
        ]),
        MapEntry('Bank', [
          e('Bank', bank['name']),
          e('Account name', bank['accountName']),
          e('Account no.', bank['accountNo']),
          e('IFSC', bank['ifsc']),
        ]),
      ];
    case DirectoryKind.suppliers:
    case DirectoryKind.karigars:
      final bank = (d['bank'] ?? {}) as Map;
      final nom = (d['nominee'] ?? {}) as Map;
      final op = (d['opening'] ?? {}) as Map;
      return [
        MapEntry('Contact', [
          e('Branch', d['branchName']),
          e('Mobile', d['mobile']),
          e('Phone', d['phone']),
          e('Email', d['email']),
          e('Address',
              _joinNonEmpty([d['address'], d['city'], d['state'], d['pincode']], ', ')),
          e('Reference', d['reference']),
        ]),
        MapEntry('Business', [
          e('Firm', d['firmName']),
          e('Business name', d['businessName']),
          e('GST no.', d['gstNo']),
          e('PAN', d['panNo']),
          e('Aadhaar', d['aadharNo']),
          e('Tax no.', d['taxNo']),
          e('Father name', d['fatherName']),
        ]),
        MapEntry('Bank', [
          e('Bank', bank['name']),
          e('Account name', bank['accountName']),
          e('Account no.', bank['accountNo']),
          e('IFSC', bank['ifsc']),
          e('Nominee', _joinNonEmpty([nom['name'], nom['relation']])),
        ]),
        MapEntry('Opening balance', [
          e('As on', (_bal(op['cash']).isNotEmpty || _bal(op['gold'], weight: true).isNotEmpty || _bal(op['silver'], weight: true).isNotEmpty) ? _date(op['date']) : ''),
          e('Cash', _bal(op['cash'])),
          e('Gold', _bal(op['gold'], weight: true)),
          e('Silver', _bal(op['silver'], weight: true)),
        ]),
      ];
  }
}
