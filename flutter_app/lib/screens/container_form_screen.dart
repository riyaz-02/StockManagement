import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:provider/provider.dart';

import '../models/container_model.dart' as cm;
import '../providers/container_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';
import '../widgets/bill_ui.dart';

class _T {
  static const bg = Color(0xFFF8F9FB);
  static const card = Color(0xFFFFFFFF);
  static const border = Color(0xFFE8EAF0);
  static const text1 = Color(0xFF111827);
  static const text2 = Color(0xFF4B5563);
  static const text3 = Color(0xFF9CA3AF);
  static const accent = Color(0xFF4F46E5);
  static const accentBg = Color(0xFFEEF2FF);
  static const success = Color(0xFF10B981);
  static const warn = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
}

/// Add or edit a box / drawer / tray as three short steps, like a new invoice:
///   1  Box     photo, name, type, how many slots
///   2  Holds   which items, metals, purities and weights it is for (the server uses this to pick a box for new items)
///   3  Code    layout, barcode label, summary, Save
/// One screen for both: pass `container` to edit. Saves the same fields the old two screens did.
class ContainerFormScreen extends StatefulWidget {
  const ContainerFormScreen({super.key, this.container});
  final cm.ItemContainer? container;

  bool get isEdit => container != null;

  @override
  State<ContainerFormScreen> createState() => _ContainerFormScreenState();
}

class _ContainerFormScreenState extends State<ContainerFormScreen> {
  final _nameCtrl = TextEditingController();
  final _capCtrl = TextEditingController(text: '20');
  final _picker = ImagePicker();
  final _api = ApiService();

  int _step = 2; // one page: every section is shown
  String _type = '';
  String _weightCat = '';
  String _layout = '';
  List<String> _metals = [];
  List<String> _purities = ['all'];
  List<String> _itemTypes = [];

  String? _imageUrl; // saved (existing or new) Cloudinary url
  bool _uploading = false;
  bool _deletingImage = false;

  String _barcode = '';
  bool _saving = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final c = widget.container;
    if (c != null) {
      _nameCtrl.text = c.name;
      _capCtrl.text = '${c.capacity}';
      _type = c.type;
      _weightCat = c.weightCategory;
      _layout = c.layoutType;
      _metals = List.of(c.metalType);
      _purities = c.purity.isEmpty ? ['all'] : List.of(c.purity);
      _itemTypes = List.of(c.allowedItemTypes);
      _barcode = c.qrCode ?? '';
      _imageUrl = c.image;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = Provider.of<SettingsProvider>(context, listen: false);
      await Future.wait([s.fetchContainerSettings(), s.fetchItemSettings()]);
      if (!mounted) return;
      setState(() {
        if (_type.isEmpty && s.containerTypes.isNotEmpty) _type = s.containerTypes.first;
        if (_weightCat.isEmpty && s.weightCategories.isNotEmpty) _weightCat = s.weightCategories.first;
        if (_layout.isEmpty && s.layoutTypes.isNotEmpty) _layout = s.layoutTypes.first;
        if (_metals.isEmpty && s.metalTypes.isNotEmpty) _metals = [s.metalTypes.first];
        _ready = true;
      });
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _capCtrl.dispose();
    super.dispose();
  }

  int get _cap => int.tryParse(_capCtrl.text.trim()) ?? 0;

  String? get _blocker {
    if (_step == 0) {
      if (_nameCtrl.text.trim().isEmpty) return 'Enter the box name';
      if (_cap < 1) return 'At least 1 slot';
      if (widget.isEdit && _cap < widget.container!.slots.where((s) => s.itemId != null).length) {
        return 'ভিতরে ${widget.container!.slots.where((s) => s.itemId != null).length}টি আইটেম আছে, এর কম স্লট হবে না';
      }
    }
    if (_step == 1 && _itemTypes.isEmpty) return 'Choose at least one item type';
    return null;
  }

  /// First thing missing on the page (the old per-step checks, all at once).
  void _afterTypes() {
    if (!widget.isEdit && _itemTypes.isNotEmpty) _makeBarcode();
  }

  String? _allIssue() {
    for (final st in [0, 1]) {
      final keep = _step;
      _step = st;
      final b = _blocker;
      _step = keep;
      if (b != null) return b;
    }
    return null;
  }

  void _next() {
    final b = _blocker;
    if (b != null) return _snack(b, _T.warn);
    FocusScope.of(context).unfocus();
    if (_step == 1 && _barcode.isEmpty) _makeBarcode();
    setState(() => _step++);
  }

  void _goTo(int s) {
    if (s > _step) {
      for (var i = _step; i < s; i++) {
        final keep = _step;
        _step = i;
        final b = _blocker;
        _step = keep;
        if (b != null) return _snack(b, _T.warn);
      }
      if (s == 2 && _barcode.isEmpty) _makeBarcode();
    }
    setState(() => _step = s);
  }

  void _snack(String m, Color bg) => showAppSnackBar(context, SnackBar(content: Text(m, style: const TextStyle(fontWeight: FontWeight.w600)), backgroundColor: bg, behavior: SnackBarBehavior.floating));

  Future<void> _makeBarcode() async {
    if (_itemTypes.isEmpty) return;
    final prefix = _itemTypes.length == 1 ? _itemTypes.first.toUpperCase().substring(0, 1) : 'M';
    final serial = await Provider.of<ContainerProvider>(context, listen: false).getNextSerial(prefix);
    if (mounted) setState(() => _barcode = '$prefix$serial');
  }

  // ─── photo (Cloudinary, unchanged) ───────────────────────────────────────────
  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.camera_alt_outlined, color: _T.accent), title: const Text('Camera'), onTap: () => Navigator.pop(c, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined, color: _T.accent), title: const Text('Gallery'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    final img = await _picker.pickImage(source: source, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
    if (img == null) return;
    setState(() => _uploading = true);
    try {
      final r = await _api.uploadImage(img, folder: 'containers');
      if (r['success'] == true) {
        final old = _imageUrl;
        setState(() => _imageUrl = r['data']['url'] as String);
        if (old != null && old != widget.container?.image) _api.deleteImage(old).catchError((_) => false);
      } else {
        throw Exception('upload');
      }
    } catch (_) {
      if (mounted) _snack('Photo upload failed', _T.danger);
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _removeImage() async {
    final url = _imageUrl;
    if (url == null || _deletingImage) return;
    setState(() => _deletingImage = true);
    try {
      // an unsaved new photo is removed from Cloudinary now; the saved one is replaced when the box is saved
      if (url != widget.container?.image) await _api.deleteImage(url);
    } catch (_) {}
    if (mounted) setState(() {
      _imageUrl = null;
      _deletingImage = false;
    });
  }

  // ─── save / delete ───────────────────────────────────────────────────────────
  Future<void> _save() async {
    final issue = _allIssue();
    if (issue != null) return _snack(issue, _T.warn);
    if (_barcode.isEmpty) await _makeBarcode();
    setState(() => _saving = true);
    final p = Provider.of<ContainerProvider>(context, listen: false);
    final data = {
      'name': _nameCtrl.text.trim(),
      'type': _type,
      'capacity': _cap,
      'allowedItemTypes': _itemTypes,
      'weightCategory': _weightCat,
      'metalType': _metals,
      'purity': _purities,
      'layoutType': _layout,
      'qrCode': _barcode,
      if (_imageUrl != null) 'image': _imageUrl,
    };
    final ok = widget.isEdit ? await p.updateContainer(widget.container!.id, data) : await p.createContainer(data);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      _snack(widget.isEdit ? 'Box updated' : 'Box created', _T.success);
      Navigator.pop(context, true);
    } else {
      _snack(p.error ?? 'Could not save', _T.danger);
    }
  }

  Future<void> _delete() async {
    final used = widget.container!.slots.where((s) => s.itemId != null).length;
    final yes = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('বাক্স মুছবেন?'),
            content: Text(used > 0 ? 'এতে $usedটি আইটেম আছে। আগে সেগুলো সরিয়ে নিন।' : 'এটি পূর্বাবস্থায় ফেরানো যাবে না।'),
            actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('বাতিল')), TextButton(style: TextButton.styleFrom(foregroundColor: _T.danger), onPressed: () => Navigator.pop(c, true), child: const Text('মুছুন'))],
          ),
        ) ??
        false;
    if (!yes || !mounted) return;
    final p = Provider.of<ContainerProvider>(context, listen: false);
    if (await p.deleteContainer(widget.container!.id)) {
      if (!mounted) return;
      _snack('বাক্স মুছে ফেলা হয়েছে', _T.success);
      Navigator.pop(context, true);
      if (Navigator.canPop(context)) Navigator.pop(context); // the detail screen it was opened from
    } else {
      _snack(p.error ?? 'মুছতে ব্যর্থ', _T.danger);
    }
  }

  // ─── build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final s = Provider.of<SettingsProvider>(context);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (did, _) {
        if (!did && _step > 0) setState(() => _step--);
      },
      child: Scaffold(
        backgroundColor: _T.bg,
        body: SafeArea(
          child: !_ready
              ? const Center(child: CircularProgressIndicator(color: _T.accent))
              : Column(children: [
                  _header(),
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: Column(children: [_stepBox(s), _stepHolds(s), _stepCode(s)]))),
                    ),
                  ),
                  _bar(),
                ]),
        ),
      ),
    );
  }

  Widget _header() => Container(
        color: _T.card,
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18), color: _T.text1, onPressed: () => Navigator.pop(context)),
          Expanded(child: Text(widget.isEdit ? 'Edit box' : 'New box', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _T.text1))),
          if (widget.isEdit) IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 20, color: _T.danger), onPressed: _delete),
        ]),
      );

  Widget _stepper() {
    const labels = ['Box', 'Holds', 'Code'];
    const icons = [Icons.inventory_2_outlined, Icons.diamond_outlined, Icons.qr_code_2_rounded];
    return Container(
      color: _T.card,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Row(children: [
        for (var i = 0; i < 3; i++) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => _goTo(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(color: _step == i ? _T.accent : (i < _step ? _T.accentBg : _T.bg), borderRadius: BorderRadius.circular(12), border: Border.all(color: _step == i ? _T.accent : _T.border)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(i < _step ? Icons.check_circle_rounded : icons[i], size: 16, color: _step == i ? Colors.white : (i < _step ? _T.accent : _T.text3)),
                  const SizedBox(width: 5),
                  Flexible(child: Text(labels[i], overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _step == i ? Colors.white : (i < _step ? _T.accent : _T.text2)))),
                ]),
              ),
            ),
          ),
          if (i < 2) const SizedBox(width: 6),
        ],
      ]),
    );
  }

  // 1 ── the box
  Widget _stepBox(SettingsProvider s) {
    final used = widget.isEdit ? widget.container!.slots.where((x) => x.itemId != null).length : 0;
    return Column(children: [
      _card('Photo', Icons.camera_alt_outlined, _photo()),
      _card(
        'Box',
        Icons.inventory_2_outlined,
        Column(children: [
          _tf(_nameCtrl, 'Name *', onChanged: (_) => setState(() {})),
          const SizedBox(height: 10),
          _two(
            _dd('Type', _type, s.containerTypes, (v) => setState(() => _type = v ?? _type)),
            Row(children: [
              _sq(Icons.remove, () => setState(() => _capCtrl.text = '${(_cap - 1).clamp(1, 9999)}')),
              Expanded(child: _tf(_capCtrl, 'Slots *', number: true, onChanged: (_) => setState(() {}))),
              _sq(Icons.add, () => setState(() => _capCtrl.text = '${_cap + 1}')),
            ]),
          ),
          if (widget.isEdit) Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(top: 5), child: Text('$used slot${used == 1 ? '' : 's'} in use', style: const TextStyle(fontSize: 11, color: _T.text3)))),
        ]),
      ),
    ]);
  }

  Widget _photo() {
    if (_uploading || _deletingImage) return const SizedBox(height: 64, child: Center(child: CircularProgressIndicator(color: _T.accent)));
    if (_imageUrl == null) {
      return OutlinedButton.icon(
        onPressed: _pickImage,
        icon: const Icon(Icons.add_a_photo_outlined, size: 18),
        label: const Text('Add photo'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      );
    }
    return Row(children: [
      ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(_imageUrl!, width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 64, height: 64, color: _T.border, child: const Icon(Icons.broken_image)))),
      const SizedBox(width: 10),
      TextButton.icon(onPressed: _pickImage, icon: const Icon(Icons.swap_horiz, size: 18), label: const Text('Change')),
      TextButton.icon(onPressed: _removeImage, icon: const Icon(Icons.delete_outline, size: 18, color: _T.danger), label: const Text('Remove', style: TextStyle(color: _T.danger))),
    ]);
  }

  // 2 ── what it holds
  Widget _stepHolds(SettingsProvider s) {
    final purityAll = ['all', ...s.purityOptions];
    return Column(children: [
      _card(
        'What it holds',
        Icons.diamond_outlined,
        Column(children: [
          _multi('Item types *', _itemTypes, s.itemTypes, (v) => setState(() {
                _itemTypes = v;
                if (!widget.isEdit) _barcode = '';
                _afterTypes();
              }), label: _cap1),
          const SizedBox(height: 10),
          _two(
            _multi('Metals', _metals, s.metalTypes, (v) => setState(() => _metals = v.isEmpty ? _metals : v), label: _cap1),
            _multi('Purity', _purities, purityAll, (v) => setState(() {
                  _purities = v.isEmpty || v.contains('all') && !(_purities.contains('all')) ? ['all'] : (v.length > 1 ? v.where((e) => e != 'all').toList() : v);
                }), label: (t) => t == 'all' ? 'All' : t.toUpperCase()),
          ),
          const SizedBox(height: 10),
          _two(_dd('Weight class', _weightCat, s.weightCategories, (v) => setState(() => _weightCat = v ?? _weightCat), label: _cap1), _dd('Layout', _layout, s.layoutTypes, (v) => setState(() => _layout = v ?? _layout), label: _cap1)),
        ]),
      ),
    ]);
  }

  // 3 ── code, summary
  Widget _stepCode(SettingsProvider s) {
    final rows = <(String, String)>[
      ('Name', _nameCtrl.text.trim()),
      ('Type / slots', '${_cap1(_type)} · $_cap slots'),
      ('Items', _itemTypes.map(_cap1).join(', ')),
      ('Metals', _metals.map(_cap1).join(', ')),
      ('Purity', _purities.map((e) => e == 'all' ? 'All' : e.toUpperCase()).join(', ')),
      ('Weight class', _cap1(_weightCat)),
    ];
    return Column(children: [
      _card(
        'Barcode label',
        Icons.qr_code_2_rounded,
        Column(children: [
          Row(children: [
            Expanded(child: Text(_barcode.isEmpty ? '—' : _barcode, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, fontFamily: 'monospace'))),
            OutlinedButton.icon(onPressed: _makeBarcode, icon: const Icon(Icons.refresh, size: 16), label: const Text('New'), style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
          ]),
          if (_barcode.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: SizedBox(height: 46, child: BarcodeWidget(barcode: Barcode.code128(), data: _barcode, drawText: false))),
        ]),
      ),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _T.accentBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: _T.accent.withValues(alpha: 0.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Summary', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _T.accent)),
          const SizedBox(height: 6),
          for (final r in rows) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 92, child: Text(r.$1, style: const TextStyle(fontSize: 12, color: _T.text2))), Expanded(child: Text(r.$2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)))])),
        ]),
      ),
    ]);
  }

  Widget _bar() {
    final last = _step == 2;
    final b = _allIssue();
    return Container(
      padding: EdgeInsets.fromLTRB(14, 8, 14, MediaQuery.of(context).padding.bottom + 10),
      decoration: const BoxDecoration(color: _T.card, boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, -2))]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (b != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(b, style: const TextStyle(fontSize: 12, color: _T.warn, fontWeight: FontWeight.w600))),
        Row(children: [
          if (false) ...[
            Expanded(flex: 2, child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), side: const BorderSide(color: _T.border)), onPressed: () => setState(() => _step--), child: const Text('Back', style: TextStyle(fontWeight: FontWeight.w700, color: _T.text2)))),
            const SizedBox(width: 10),
          ],
          Expanded(
            flex: 4,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: last ? _T.success : _T.accent, minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: last ? (_saving ? null : _save) : _next,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(last ? (widget.isEdit ? 'Update' : 'Save') : 'Next', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)), const SizedBox(width: 6), Icon(last ? Icons.check_rounded : Icons.arrow_forward_rounded, size: 19)]),
            ),
          ),
        ]),
      ]),
    );
  }

  // ─── bits ────────────────────────────────────────────────────────────────────
  static String _cap1(String v) => v.isEmpty ? v : v.replaceAll('-', ' ').replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1)).join(' ');

  Widget _card(String label, IconData icon, Widget child, {bool required = false}) => BillCard(title: label, icon: icon, color: _T.accent, child: child);

  Widget _two(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 8), Expanded(child: b)]);

  Widget _dd(String title, String? value, List<String> options, ValueChanged<String?> onChanged, {String Function(String)? label}) {
    final show = label ?? _cap1;
    final list = [...options];
    if (value != null && value.isNotEmpty && !list.contains(value)) list.insert(0, value);
    return DropdownButtonFormField<String>(
      value: (value == null || value.isEmpty) ? null : value,
      isExpanded: true,
      style: const TextStyle(fontSize: 13, color: Colors.black87),
      decoration: billDec(title, _T.accent),
      items: [for (final o in list) DropdownMenuItem(value: o, child: Text(show(o), overflow: TextOverflow.ellipsis))],
      onChanged: onChanged,
    );
  }

  Widget _tf(TextEditingController c, String label, {bool number = false, ValueChanged<String>? onChanged}) => TextFormField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        inputFormatters: [if (number) FilteringTextInputFormatter.digitsOnly],
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13.5),
        decoration: billDec(label, _T.accent),
      );

  /// A floating-label field that opens a checklist (for choices where several can apply).
  Widget _multi(String title, List<String> selected, List<String> options, ValueChanged<List<String>> onChanged, {required String Function(String) label}) {
    final text = selected.isEmpty ? '' : selected.map(label).join(', ');
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final picked = List<String>.of(selected);
        final ok = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setS) => SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 4), child: Align(alignment: Alignment.centerLeft, child: Text(title.replaceAll(' *', ''), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)))),
                  Flexible(
                    child: ListView(shrinkWrap: true, children: [
                      for (final o in options)
                        CheckboxListTile(dense: true, value: picked.contains(o), title: Text(label(o)), onChanged: (v) => setS(() => v == true ? picked.add(o) : picked.remove(o))),
                    ]),
                  ),
                  Padding(padding: const EdgeInsets.all(12), child: FilledButton(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Done'))),
                ]),
              ),
            ),
          ),
        );
        if (ok == true) onChanged(picked);
      },
      child: InputDecorator(
        decoration: billDec(title, _T.accent, suffix: const Icon(Icons.arrow_drop_down)),
        isEmpty: text.isEmpty,
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  Widget _sq(IconData i, VoidCallback t) => InkWell(onTap: t, borderRadius: BorderRadius.circular(8), child: Container(width: 34, height: 40, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: _T.accentBg, borderRadius: BorderRadius.circular(8)), child: Icon(i, size: 18, color: _T.accent)));

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _T.text3, fontSize: 13),
        filled: true,
        fillColor: _T.bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _T.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _T.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _T.accent, width: 1.8)),
      );
}
