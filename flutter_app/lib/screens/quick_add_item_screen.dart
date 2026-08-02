import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:provider/provider.dart';

import '../models/item_model.dart';
import '../providers/item_provider.dart';
import '../providers/container_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import 'barcode_scanner_for_assignment.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
class _T {
  // Neutrals
  static const bg        = Color(0xFFF8F9FB);
  static const card      = Color(0xFFFFFFFF);
  static const border    = Color(0xFFE8EAF0);
  static const text1     = Color(0xFF111827);
  static const text2     = Color(0xFF4B5563);
  static const text3     = Color(0xFF9CA3AF);

  // Accents (used sparingly)
  static const accent    = Color(0xFF4F46E5); // indigo — required fields, save button
  static const accentBg  = Color(0xFFEEF2FF);
  static const success   = Color(0xFF10B981);
  static const warn      = Color(0xFFF59E0B);
  static const danger    = Color(0xFFEF4444);

  // Metal dots
  static const goldDot   = Color(0xFFD97706); // amber-600
  static const silverDot = Color(0xFF6B7280); // gray-500
  static const platDot   = Color(0xFF3B82F6); // blue-500
}

class QuickAddItemScreen extends StatefulWidget {
  final Item? item;
  final String? barcode;
  final String? initialContainerId;
  final int? initialSlotNumber;

  const QuickAddItemScreen({
    super.key,
    this.item,
    this.barcode,
    this.initialContainerId,
    this.initialSlotNumber,
  });

  bool get isEditMode => item != null;
  bool get isQuickMode => item == null && barcode != null;

  @override
  State<QuickAddItemScreen> createState() => _QuickAddItemScreenState();
}

class _QuickAddItemScreenState extends State<QuickAddItemScreen> {
  final _nameCtrl   = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _huidCtrl   = TextEditingController();
  final _piecesCtrl = TextEditingController(text: '1');
  final _descCtrl   = TextEditingController();

  late String _barcode;
  bool _barcodeFromScan = false;

  String? _metalType;
  String? _purity;
  String? _itemType;
  String  _weightCategory = 'Light';
  String  _weightAccuracy = 'exact';
  String  _status         = 'active';

  bool _isHallmarked = false;
  bool _isHUID       = false;

  String? _selectedContainerId;
  int?    _selectedSlotNumber;
  List<Map<String, dynamic>> _containers = [];

  final List<String> _existingImages = [];
  List<String> _newImageUrls         = [];
  bool _isUploadingImages            = false;
  int? _deletingIdx;
  bool _deletingExisting             = false;

  bool _isSaving         = false;
  bool _isLoading        = true;
  bool _moreExpanded     = false;

  final _picker     = ImagePicker();
  final _apiService = ApiService();

  static const _fallbackMetals    = ['gold', 'silver', 'mixed', 'gold-coated', 'platinum'];
  static const _fallbackItemTypes = ['ring', 'necklace', 'earring', 'bracelet', 'pendant', 'chain', 'bangle', 'other'];
  static const _fallbackPurities  = ['916-22k', '750-18k', '20kt', 'jewellery-silver', 'hallmark-silver'];
  static const _weightCategories  = ['Light', 'Medium', 'Heavy'];
  static const _statuses          = ['active', 'booked', 'in_repair', 'sold', 'action_needed'];

  List<String> _metals   = [];
  List<String> _itemTypes = [];
  List<String> _purities  = [];

  // ─── Metal colors (subtle dot only) ────────────────────────────────────────
  static Color _metalDot(String v) {
    switch (v.toLowerCase()) {
      case 'gold':        return _T.goldDot;
      case 'silver':      return _T.silverDot;
      case 'platinum':    return _T.platDot;
      case 'gold-coated': return const Color(0xFFB45309);
      case 'mixed':       return const Color(0xFF8B5CF6);
      default:            return _T.accent;
    }
  }

  // ─── Bengali ────────────────────────────────────────────────────────────────
  static String _metalBn(String v) {
    switch (v.toLowerCase()) {
      case 'gold':        return 'সোনা';
      case 'silver':      return 'রুপা';
      case 'mixed':       return 'মিশ্র';
      case 'gold-coated': return 'গোল্ড কোটেড';
      case 'platinum':    return 'প্লাটিনাম';
      default:            return _fmt(v);
    }
  }

  static String _itemBn(String v) {
    switch (v.toLowerCase()) {
      case 'ring':     return 'আংটি';
      case 'necklace': return 'হার';
      case 'earring':  return 'কানের দুল';
      case 'bracelet': return 'ব্রেসলেট';
      case 'pendant':  return 'পেন্ডেন্ট';
      case 'chain':    return 'চেইন';
      case 'bangle':   return 'বালা';
      case 'other':    return 'অন্যান্য';
      default:         return _fmt(v);
    }
  }

  static String _weightCatBn(String v) {
    switch (v.toLowerCase()) {
      case 'light':  return 'হালকা';
      case 'medium': return 'মাঝারি';
      case 'heavy':  return 'ভারী';
      default:       return v;
    }
  }

  static String _statusBn(String v) {
    switch (v.toLowerCase()) {
      case 'active':        return 'সক্রিয়';
      case 'booked':        return 'বুক করা';
      case 'in_repair':     return 'মেরামতে';
      case 'sold':          return 'বিক্রিত';
      case 'action_needed': return 'পর্যালোচনা দরকার';
      default:              return v;
    }
  }

  // ─── Init ──────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _moreExpanded = widget.isEditMode;
    widget.isEditMode ? _initEdit() : _initCreate();
    Future.microtask(_load);
  }

  void _initEdit() {
    final it = widget.item!;
    _barcode          = it.barcode;
    _barcodeFromScan  = true;
    _nameCtrl.text    = it.name;
    _weightCtrl.text  = it.netWeight.toString();
    _piecesCtrl.text  = it.numberOfPieces.toString();
    _descCtrl.text    = it.description;
    _metalType        = it.metalType.isNotEmpty ? it.metalType : null;
    _purity           = it.purity.isNotEmpty   ? it.purity    : null;
    _itemType         = it.itemType.isNotEmpty  ? it.itemType  : null;
    _weightCategory   = it.weightCategory;
    _weightAccuracy   = it.weightAccuracy;
    _status           = it.status;
    _isHallmarked     = it.certificationType == 'hallmarked';
    _isHUID           = it.certificationType == 'huid';
    if (_isHUID && it.huidNumber != null) _huidCtrl.text = it.huidNumber!;
    _selectedContainerId = it.containerId;
    _selectedSlotNumber  = it.slotNumber;
    _existingImages.addAll(it.images);
  }

  void _initCreate() {
    _barcode = widget.barcode ?? _genBarcode();
    _barcodeFromScan = widget.barcode != null;
    _nameCtrl.text = 'Unnamed - $_barcode';
    // IMPORTANT: Quick mode always starts as action_needed
    // → bypasses backend container-required validation
    _status = widget.isQuickMode ? 'action_needed' : 'active';
    if (widget.initialContainerId != null) {
      _selectedContainerId = widget.initialContainerId;
      _selectedSlotNumber  = widget.initialSlotNumber;
    }
  }

  Future<void> _load() async {
    final s = Provider.of<SettingsProvider>(context, listen: false);
    if (s.metalTypes.isEmpty || s.purityOptions.isEmpty) await s.fetchItemSettings();
    if (!mounted) return;

    final cp = Provider.of<ContainerProvider>(context, listen: false);
    if (cp.containers.isEmpty) await cp.fetchContainers();
    if (!mounted) return;

    setState(() {
      _metals    = s.metalTypes.isNotEmpty    ? s.metalTypes    : _fallbackMetals;
      _itemTypes = s.itemTypes.isNotEmpty     ? s.itemTypes     : _fallbackItemTypes;
      _purities  = s.purityOptions.isNotEmpty ? s.purityOptions : _fallbackPurities;
      _containers = cp.containers.map((c) {
        final ok = c.isActive && !c.isLocked && c.availableSlots > 0;
        return {
          'id': c.id,
          'name': c.name,
          'code': c.qrCode ?? c.id.substring(0, 4),
          'available': c.availableSlots,
          'total': c.capacity,
          'ok': ok,
          'status': c.isLocked ? 'লক' : (!c.isActive ? 'নিষ্ক্রিয়' : (!ok ? 'পূর্ণ' : 'সক্রিয়')),
        };
      }).toList()..sort((a, b) {
        final sa = (a['ok'] as bool) ? 1 : 0;
        final sb = (b['ok'] as bool) ? 1 : 0;
        return sb.compareTo(sa);
      });
      _isLoading = false;
    });
  }

  String _genBarcode() => (DateTime.now().millisecondsSinceEpoch % 90000 + 10000).toString();

  void _refreshBarcode() {
    setState(() {
      _barcode = _genBarcode();
      if (_nameCtrl.text.startsWith('Unnamed - ')) _nameCtrl.text = 'Unnamed - $_barcode';
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _weightCtrl.dispose(); _huidCtrl.dispose();
    _piecesCtrl.dispose(); _descCtrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _metalType != null && _purity != null &&
      _weightCtrl.text.isNotEmpty && (double.tryParse(_weightCtrl.text) ?? 0) > 0;

  // ─── Camera / images ───────────────────────────────────────────────────────
  Future<void> _camera() async {
    final img = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (img == null) return;
    setState(() => _isUploadingImages = true);
    try {
      final r = await _apiService.uploadImage(img);
      if (r['success'] == true) setState(() => _newImageUrls.add(r['data']['url'] as String));
    } catch (e) { if (mounted) _snack('আপলোড ব্যর্থ', _T.danger); }
    if (mounted) setState(() => _isUploadingImages = false);
  }

  Future<void> _gallery() async {
    final imgs = await _picker.pickMultiImage();
    if (imgs.isEmpty) return;
    setState(() => _isUploadingImages = true);
    int ok = 0;
    for (final img in imgs) {
      try {
        final r = await _apiService.uploadImage(img);
        if (r['success'] == true) { ok++; setState(() => _newImageUrls.add(r['data']['url'] as String)); }
      } catch (_) {}
    }
    setState(() => _isUploadingImages = false);
    if (mounted && ok > 0) _snack('$ok টি ছবি আপলোড হয়েছে', _T.success);
  }

  Future<void> _deleteImg(int idx, {bool existing = false}) async {
    if (_deletingIdx == idx && _deletingExisting == existing) return;
    setState(() { _deletingIdx = idx; _deletingExisting = existing; });
    final url = existing ? _existingImages[idx] : _newImageUrls[idx];
    try {
      if (await _apiService.deleteImage(url)) {
        setState(() {
          if (existing) { _existingImages.removeAt(idx); } else { _newImageUrls.removeAt(idx); }
          _deletingIdx = null; _deletingExisting = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) _snack('ছবি মুছতে পারা যায়নি', _T.danger);
    setState(() { _deletingIdx = null; _deletingExisting = false; });
  }

  Future<void> _deleteItem() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('আইটেম মুছবেন?'),
        content: const Text('এটি পূর্বাবস্থায় ফেরানো যাবে না।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
          TextButton(style: TextButton.styleFrom(foregroundColor: _T.danger),
              onPressed: () => Navigator.pop(ctx, true), child: const Text('মুছুন')),
        ],
      ),
    ) ?? false;
    if (!ok || !mounted) return;
    final p = Provider.of<ItemProvider>(context, listen: false);
    if (await p.deleteItem(widget.item!.id)) {
      Navigator.pop(context); _snack('মুছে ফেলা হয়েছে', _T.success);
    } else {
      _snack(p.error ?? 'মুছতে ব্যর্থ', _T.danger);
    }
  }

  Future<void> _save() async {
    if (!_canSave) { _snack('ধাতু, বিশুদ্ধতা এবং ওজন পূরণ করুন', _T.warn); return; }
    setState(() => _isSaving = true);

    final cert = _isHUID ? 'huid' : _isHallmarked ? 'hallmarked' : 'none';
    final allImgs = [..._existingImages, ..._newImageUrls];

    // Quick mode → always action_needed so backend skips container requirement
    final effectiveStatus = widget.isQuickMode ? 'action_needed' : _status;

    final data = {
      'barcode':           _barcode,
      'name':              _nameCtrl.text.trim().isEmpty ? 'Unnamed - $_barcode' : _nameCtrl.text.trim(),
      'itemType':          _itemType ?? 'other',
      'metalType':         _metalType!,
      'purity':            _purity!,
      'netWeight':         double.parse(_weightCtrl.text),
      'numberOfPieces':    int.tryParse(_piecesCtrl.text) ?? 1,
      'weightAccuracy':    _weightAccuracy,
      'weightCategory':    _weightCategory,
      'certificationType': cert,
      'huidNumber':        _isHUID ? _huidCtrl.text : null,
      'description':       _descCtrl.text,
      'containerId':       _selectedContainerId,
      'slotNumber':        _selectedSlotNumber,
      'images':            jsonEncode(allImgs),
      'status':            effectiveStatus,
    };

    final p = Provider.of<ItemProvider>(context, listen: false);
    final success = widget.isEditMode
        ? await p.updateItem(widget.item!.id, data, [])
        : await p.createItem(data, []);

    setState(() => _isSaving = false);
    if (!mounted) return;

    if (success) {
      final msg = widget.isEditMode ? 'আইটেম আপডেট হয়েছে' : 'সফলভাবে সংরক্ষিত হয়েছে';
      _snack(msg, _T.success);
      Navigator.pop(context, true);
    } else {
      _snack(p.error ?? 'সংরক্ষণ ব্যর্থ', _T.danger);
    }
  }

  Future<void> _scanBarcode() async {
    if (kIsWeb) return;
    final v = await Navigator.push<String>(context,
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => const BarcodeScannerForAssignment()));
    if (v == null || v.isEmpty) return;
    setState(() {
      _barcode = v;
      if (_nameCtrl.text.startsWith('Unnamed - ')) _nameCtrl.text = 'Unnamed - $_barcode';
    });
  }

  void _snack(String msg, Color bg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: bg, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 12)));

  // ─── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _T.bg,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _T.accent))
            : Column(children: [
                _buildHeader(),
                Expanded(child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                  child: Column(children: [

                    // 1. Photos
                    _section(label: 'ছবি  (Photos)', icon: Icons.camera_alt_outlined,
                        child: _buildImages()),

                    // 2. Metal
                    _section(label: 'ধাতুর ধরন  (Metal)', icon: Icons.toll_outlined,
                        required: _metalType == null, child: _buildMetalChips()),

                    // 3. Purity
                    _section(label: 'বিশুদ্ধতা  (Purity)', icon: Icons.star_outline_rounded,
                        required: _purity == null, child: _buildPurityChips()),

                    // 4. Weight
                    _section(label: 'নিট ওজন  (Weight gm.)', icon: Icons.scale_outlined,
                        required: _weightCtrl.text.isEmpty, child: _buildWeightRow()),

                    // 5. Certification
                    _section(label: 'সার্টিফিকেশন  (Certification)', icon: Icons.verified_outlined,
                        child: _buildCert()),

                    // More info
                    _buildMore(),

                    const SizedBox(height: 6),
                  ]),
                )),
                _buildSaveBar(),
              ]),
      ),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      color: _T.card,
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            color: _T.text1, onPressed: () => Navigator.pop(context),
          ),
          Expanded(child: Text(
            widget.isEditMode ? 'আইটেম সম্পাদনা' : 'নতুন আইটেম',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _T.text1),
          )),
          // Barcode badge
          GestureDetector(
            onTap: _barcodeFromScan ? null : _refreshBarcode,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _T.accentBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.qr_code, size: 13, color: _T.accent),
                const SizedBox(width: 4),
                Text(_barcode, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _T.accent)),
              ]),
            ),
          ),
          if (widget.isEditMode) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: _T.danger),
              onPressed: _deleteItem, padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ]),
        const Divider(height: 1, color: _T.border),
      ]),
    );
  }

  // ─── Quick banner ──────────────────────────────────────────────────────────
  Widget _buildQuickBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _T.accentBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _T.accent.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline_rounded, size: 16, color: _T.accent),
        const SizedBox(width: 8),
        Expanded(child: Text(
          'দ্রুত যোগ করা আইটেম "পর্যালোচনা দরকার" তালিকায় যাবে। পরে বিস্তারিত আপডেট করুন।',
          style: const TextStyle(fontSize: 12, color: _T.accent, height: 1.4),
        )),
      ]),
    );
  }

  // ─── Section card ──────────────────────────────────────────────────────────
  Widget _section({
    required String label,
    required IconData icon,
    required Widget child,
    bool required = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _T.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: required ? _T.accent.withValues(alpha: 0.5) : _T.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 0),
          child: Row(children: [
            Icon(icon, size: 14, color: required ? _T.accent : _T.text3),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.2,
              color: required ? _T.accent : _T.text2,
            )),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Divider(height: 10, thickness: 0.8, color: _T.border),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
          child: child,
        ),
      ]),
    );
  }

  // ─── Metal chips ────────────────────────────────────────────────────────────
  Widget _buildMetalChips() {
    return Wrap(spacing: 8, runSpacing: 8, children: _metals.map((v) {
      final sel = _metalType == v;
      final dot = _metalDot(v);
      return GestureDetector(
        onTap: () => setState(() { _metalType = v; }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? _T.text1 : _T.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: sel ? _T.text1 : _T.border, width: sel ? 1.5 : 1.2),
            boxShadow: sel ? [const BoxShadow(color: Color(0x221A1A2E), blurRadius: 6, offset: Offset(0, 2))] : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(_metalBn(v), style: TextStyle(
              fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
              color: sel ? Colors.white : _T.text1,
            )),
          ]),
        ),
      );
    }).toList());
  }

  // ─── Purity chips ───────────────────────────────────────────────────────────
  Widget _buildPurityChips() {
    if (_purities.isEmpty) return Text('লোড হচ্ছে...', style: TextStyle(color: _T.text3, fontSize: 13));
    return Wrap(spacing: 8, runSpacing: 8, children: _purities.map((v) {
      final sel = _purity == v;
      return GestureDetector(
        onTap: () => setState(() => _purity = v),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? _T.accent : _T.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: sel ? _T.accent : _T.border, width: sel ? 1.5 : 1.2),
            boxShadow: sel ? [BoxShadow(color: _T.accent.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))] : null,
          ),
          child: Text(v.toUpperCase(), style: TextStyle(
            fontSize: 12.5, fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
            color: sel ? Colors.white : _T.text2, letterSpacing: 0.4,
          )),
        ),
      );
    }).toList());
  }

  // ─── Weight row ──────────────────────────────────────────────────────────────
  Widget _buildWeightRow() {
    final hasVal = (double.tryParse(_weightCtrl.text) ?? 0) > 0;
    return Row(children: [
      Expanded(child: TextFormField(
        controller: _weightCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}'))],
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _T.text1),
        decoration: InputDecoration(
          hintText: '0.000',
          hintStyle: const TextStyle(fontSize: 20, color: _T.border, fontWeight: FontWeight.w700),
          suffixText: 'g',
          suffixStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: hasVal ? _T.accent : _T.text3),
          filled: true, fillColor: _T.bg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _T.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _T.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _T.accent, width: 1.8)),
        ),
      )),
      const SizedBox(width: 10),
      AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 48, height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hasVal ? _T.accent : _T.border,
        ),
        child: Icon(Icons.scale_rounded, color: hasVal ? Colors.white : _T.text3, size: 20),
      ),
    ]);
  }

  // ─── Certification ─────────────────────────────────────────────────────────
  Widget _buildCert() {
    return Column(children: [
      _certRow('হলমার্ক', Icons.verified_outlined, _T.success, _isHallmarked,
          (v) => setState(() { _isHallmarked = v!; if (v) _isHUID = false; })),
      const SizedBox(height: 8),
      _certRow('HUID সার্টিফাইড', Icons.fingerprint_rounded, const Color(0xFF2196F3), _isHUID,
          (v) => setState(() { _isHUID = v!; if (v) _isHallmarked = false; })),
      if (_isHUID) ...[
        const SizedBox(height: 10),
        TextFormField(
          controller: _huidCtrl,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            TextInputFormatter.withFunction((o, n) => TextEditingValue(text: n.text.toUpperCase(), selection: n.selection)),
          ],
          decoration: _inputDec('HUID নম্বর'),
        ),
      ],
    ]);
  }

  Widget _certRow(String label, IconData icon, Color color, bool value, void Function(bool?) onChange) {
    return GestureDetector(
      onTap: () => onChange(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: value ? color.withValues(alpha: 0.07) : _T.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: value ? color.withValues(alpha: 0.5) : _T.border),
        ),
        child: Row(children: [
          Icon(icon, color: value ? color : _T.text3, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: TextStyle(fontSize: 13,
              fontWeight: value ? FontWeight.w700 : FontWeight.w400,
              color: value ? color : _T.text2))),
          AnimatedContainer(duration: const Duration(milliseconds: 140),
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: value ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: value ? color : _T.border, width: 1.5),
            ),
            child: value ? const Icon(Icons.check, size: 13, color: Colors.white) : null),
        ]),
      ),
    );
  }

  // ─── More Info ─────────────────────────────────────────────────────────────
  Widget _buildMore() {
    return Container(
      decoration: BoxDecoration(
        color: _T.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _T.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _moreExpanded,
          onExpansionChanged: (v) => setState(() => _moreExpanded = v),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
          leading: const Icon(Icons.tune_rounded, size: 16, color: _T.text3),
          title: const Text('আরও তথ্য',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _T.text2)),
          children: [
            const Divider(height: 1, color: _T.border),
            const SizedBox(height: 14),

            // Item Type
            _mLabel('গহনার ধরন', Icons.category_outlined),
            const SizedBox(height: 6),
            Wrap(spacing: 7, runSpacing: 7, children: _itemTypes.map((v) {
              final sel = _itemType == v;
              return GestureDetector(
                onTap: () => setState(() => _itemType = v),
                child: AnimatedContainer(duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel ? _T.text1 : _T.bg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: sel ? _T.text1 : _T.border),
                  ),
                  child: Text(_itemBn(v), style: TextStyle(fontSize: 12.5,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      color: sel ? Colors.white : _T.text2))),
              );
            }).toList()),
            const SizedBox(height: 14),

            // Weight Category
            _mLabel('ওজনের শ্রেণী', Icons.line_weight_rounded),
            const SizedBox(height: 6),
            Row(children: _weightCategories.map((v) {
              final sel = _weightCategory == v;
              return Expanded(child: Padding(padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => setState(() => _weightCategory = v),
                  child: AnimatedContainer(duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: sel ? _T.text1 : _T.bg,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: sel ? _T.text1 : _T.border),
                    ),
                    child: Text(_weightCatBn(v), textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5,
                            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                            color: sel ? Colors.white : _T.text2))),
                ),
              ));
            }).toList()),
            const SizedBox(height: 14),

            _mLabel('আইটেমের নাম', Icons.label_outline),
            const SizedBox(height: 6),
            TextFormField(controller: _nameCtrl, decoration: _inputDec('যেমন: সোনার আংটি')),
            const SizedBox(height: 12),

            _mLabel('টুকরোর সংখ্যা', Icons.tag_rounded),
            const SizedBox(height: 6),
            TextFormField(controller: _piecesCtrl, keyboardType: TextInputType.number, decoration: _inputDec('১')),
            const SizedBox(height: 12),

            // Container — not shown in quick mode (it's auto-skipped via action_needed status)
            if (!widget.isQuickMode) ...[
              _mLabel('বাক্স (ঐচ্ছিক)', Icons.inventory_2_outlined),
              const SizedBox(height: 6),
              _buildContainerField(),
              const SizedBox(height: 12),
            ],

            _mLabel('বিবরণ', Icons.notes_rounded),
            const SizedBox(height: 6),
            TextFormField(controller: _descCtrl, maxLines: 2, decoration: _inputDec('অতিরিক্ত নোট...')),
            const SizedBox(height: 12),

            // Status - only for edit / direct add
            if (widget.isEditMode || !widget.isQuickMode) ...[
              _mLabel('অবস্থা', Icons.flag_outlined),
              const SizedBox(height: 6),
              _buildStatusChips(),
              const SizedBox(height: 12),
            ],

            _mLabel('বারকোড', Icons.qr_code_rounded),
            const SizedBox(height: 6),
            _buildBarcodeRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildContainerField() {
    if (_containers.isEmpty) {
      return Text('কোনো বাক্স পাওয়া যায়নি', style: TextStyle(fontSize: 13, color: _T.text3));
    }
    return DropdownButtonFormField<String>(
      value: _selectedContainerId,
      hint: const Text('বাক্স বেছে নিন', style: TextStyle(fontSize: 13)),
      decoration: _inputDec(''),
      isExpanded: true,
      selectedItemBuilder: (ctx) => _containers.map<Widget>((c) =>
          Text('${c['name']} (${c['code']})', overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))).toList(),
      items: _containers.map((c) {
        final ok = c['ok'] as bool;
        return DropdownMenuItem(value: c['id'] as String, enabled: ok,
          child: Opacity(opacity: ok ? 1.0 : 0.45, child: Row(children: [
            Icon(ok ? Icons.check_circle_outline : Icons.block, size: 13,
                color: ok ? _T.success : _T.text3),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('${c['name']} (${c['code']})', overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text('${c['available']}/${c['total']} স্লট · ${c['status']}',
                  style: TextStyle(fontSize: 11, color: _T.text3)),
            ])),
          ])),
        );
      }).toList(),
      onChanged: (v) => setState(() => _selectedContainerId = v),
    );
  }

  Widget _buildStatusChips() {
    const colors = <String, Color>{
      'active': _T.success, 'booked': Color(0xFF1565C0),
      'in_repair': Color(0xFF7B1FA2), 'sold': _T.danger, 'action_needed': _T.warn,
    };
    return Wrap(spacing: 7, runSpacing: 7, children: _statuses.map((s) {
      final color = colors[s] ?? Colors.grey;
      final sel = _status == s;
      return GestureDetector(
        onTap: () => setState(() => _status = s),
        child: AnimatedContainer(duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: sel ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: sel ? color : _T.border),
          ),
          child: Text(_statusBn(s), style: TextStyle(fontSize: 12,
              fontWeight: FontWeight.w600,
              color: sel ? Colors.white : _T.text2))),
      );
    }).toList());
  }

  Widget _buildBarcodeRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: _T.bg, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _T.border)),
      child: Row(children: [
        Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('BARCODE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
              color: _T.text3, letterSpacing: 0.8)),
          const SizedBox(height: 3),
          Text(_barcode, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              fontFamily: 'monospace', color: _T.text1)),
        ])),
        Expanded(flex: 3, child: SizedBox(height: 34,
            child: BarcodeWidget(barcode: Barcode.code128(), data: _barcode,
                drawText: false, color: _T.text1))),
        const SizedBox(width: 6),
        if (!kIsWeb)
          _iconBtn(Icons.qr_code_scanner, _T.accent, _scanBarcode),
        if (!_barcodeFromScan || !widget.isEditMode)
          _iconBtn(Icons.refresh_rounded, _T.text3, _refreshBarcode),
      ]),
    );
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(width: 32, height: 32,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: color, size: 17)),
  );

  Widget _mLabel(String label, IconData icon) => Row(children: [
    Icon(icon, size: 13, color: _T.text3),
    const SizedBox(width: 5),
    Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _T.text2)),
  ]);

  // ─── Images ────────────────────────────────────────────────────────────────
  Widget _buildImages() {
    final existE = _existingImages.asMap().entries.map((e) => (e.key, e.value, true));
    final newE   = _newImageUrls.asMap().entries.map((e) => (e.key, e.value, false));
    final all = [...existE, ...newE];

    return Column(children: [
      if (all.isNotEmpty) ...[
        SizedBox(height: 80, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: all.length + (_isUploadingImages ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            if (i == all.length) return Container(width: 80, height: 80,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                    color: _T.accentBg, border: Border.all(color: _T.accent.withValues(alpha: 0.3))),
                child: const Center(child: SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _T.accent))));
            final (idx, url, isExist) = all[i];
            final del = _deletingIdx == idx && _deletingExisting == isExist;
            return Stack(children: [
              ClipRRect(borderRadius: BorderRadius.circular(10),
                  child: Image.network(url, width: 80, height: 80, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(width: 80, height: 80,
                          color: _T.border, child: const Icon(Icons.broken_image)))),
              if (del) Positioned.fill(child: Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.black45),
                  child: const Center(child: SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))))),
              Positioned(top: 3, right: 3, child: GestureDetector(
                onTap: del ? null : () => _deleteImg(idx, existing: isExist),
                child: Container(padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(color: _T.danger, shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 10, color: Colors.white)),
              )),
            ]);
          },
        )),
        const SizedBox(height: 10),
      ],
      Row(children: [
        Expanded(child: _imgBtn(Icons.camera_alt_outlined, 'ক্যামেরা', _isUploadingImages, _camera)),
        const SizedBox(width: 8),
        Expanded(child: _imgBtn(Icons.photo_library_outlined, 'গ্যালারি', false, _gallery)),
      ]),
    ]);
  }

  Widget _imgBtn(IconData icon, String label, bool loading, VoidCallback onTap) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(height: 44,
        decoration: BoxDecoration(color: _T.bg, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _T.border)),
        child: loading
            ? const Center(child: SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: _T.accent)))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 16, color: _T.accent),
                const SizedBox(width: 5),
                Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _T.text2)),
              ]),
      ),
    );
  }

  // ─── Save bar ──────────────────────────────────────────────────────────────
  Widget _buildSaveBar() {
    final ready = _canSave && !_isSaving;
    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, 14, MediaQuery.of(context).padding.bottom + 10),
      color: _T.card,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: double.infinity, height: 50,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: ready ? _T.accent : _T.border,
              borderRadius: BorderRadius.circular(12),
              boxShadow: ready ? [BoxShadow(color: _T.accent.withValues(alpha: 0.3),
                  blurRadius: 10, offset: const Offset(0, 3))] : [],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: ready ? _save : null,
                child: Center(child: _isSaving
                    ? const Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text('সংরক্ষণ হচ্ছে...', style: TextStyle(fontSize: 14,
                            fontWeight: FontWeight.w700, color: Colors.white)),
                      ])
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(widget.isEditMode ? Icons.update_rounded : Icons.check_rounded,
                            color: ready ? Colors.white : _T.text3, size: 18),
                        const SizedBox(width: 6),
                        Text(widget.isEditMode ? 'আপডেট করুন' : 'সংরক্ষণ করুন',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                                color: ready ? Colors.white : _T.text3)),
                      ])),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  InputDecoration _inputDec(String hint, {IconData? prefix}) => InputDecoration(
    hintText: hint,
    prefixIcon: prefix != null ? Icon(prefix, size: 17, color: _T.text3) : null,
    hintStyle: const TextStyle(color: _T.border, fontSize: 13),
    filled: true, fillColor: _T.bg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _T.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _T.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _T.accent, width: 1.8)),
  );

  static String _fmt(String v) => v.isEmpty ? v
      : v.replaceAll('-', ' ').replaceAll('_', ' ').split(' ')
          .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1)).join(' ');
}
