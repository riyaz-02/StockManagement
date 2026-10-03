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
import '../utils/app_toast.dart';
import '../widgets/bill_ui.dart';
import '../utils/stock_valuation.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
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
  static const goldDot = Color(0xFFD97706);
  static const silverDot = Color(0xFF6B7280);
  static const platDot = Color(0xFF3B82F6);
}

/// Add / edit a stock item as three short steps (like a new invoice):
///   1  Item      photos, metal, purity, type, name
///   2  Weight    gross / less / net weight, pieces, certification, stones, making charge
///   3  Stock     the box and slot, status, barcode, notes  (then a summary and Save)
/// Same constructor and same saved fields as before, so every caller and every existing item keeps working; the
/// extra detail (gross weight, stones, making charge, supplier, size) is optional and is what billing picks up when
/// the item is scanned into an invoice.
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
  final _nameCtrl = TextEditingController();
  final _grossCtrl = TextEditingController();
  final _lessCtrl = TextEditingController();
  final _weightCtrl = TextEditingController(); // net
  final _huidCtrl = TextEditingController();
  final _piecesCtrl = TextEditingController(text: '1');
  final _descCtrl = TextEditingController();
  final _stoneValCtrl = TextEditingController();
  final _stoneNoteCtrl = TextEditingController();
  final _makingCtrl = TextEditingController();
  final _supplierCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController();
  final _wastageCtrl = TextEditingController();
  final _custWastageCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _labourCtrl = TextEditingController();
  final _makingRateCtrl = TextEditingController();
  Map<String, dynamic> _rules = {}; // Stock Setting rules from the server
  double _goldRate = 0, _silverRate = 0;

  int _step = 2; // one page: every section is shown, so the "last step" rules (Save, no Back) always apply
  late String _barcode;
  bool _barcodeFromScan = false;
  bool _nameAuto = true; // the name follows metal + type until the user types one
  bool _categoryTouched = false;

  String? _metalType;
  String? _purity;
  String? _itemType;
  String _weightCategory = 'Light';
  String _weightAccuracy = 'exact';
  String _status = 'active';
  String _cert = 'none'; // none | hallmarked | huid
  bool _certChosen = false; // staff must answer: hallmarked / HUID / not hallmarked (a new piece starts unanswered)

  String? _selectedContainerId;
  int? _selectedSlotNumber;
  List<Map<String, dynamic>> _containers = [];

  final List<String> _existingImages = [];
  final List<String> _newImageUrls = [];
  bool _isUploadingImages = false;
  int? _deletingIdx;
  bool _deletingExisting = false;

  bool _isSaving = false;
  bool _isLoading = true;
  bool _stonesOpen = false;

  final _picker = ImagePicker();
  final _apiService = ApiService();

  static const _fallbackMetals = ['gold', 'silver', 'mixed', 'gold-coated', 'platinum'];
  static const _fallbackItemTypes = ['ring', 'necklace', 'earring', 'bracelet', 'pendant', 'chain', 'bangle', 'other'];
  static const _fallbackPurities = ['916-22k', '750-18k', '20kt', 'jewellery-silver', 'hallmark-silver'];
  static const _weightCategories = ['Light', 'Medium', 'Heavy'];
  static const _accuracies = ['exact', 'approx', 'bulk'];
  static const _statuses = ['active', 'booked', 'in_repair', 'sold', 'action_needed'];

  List<String> _metals = [];
  List<String> _itemTypes = [];
  List<String> _purities = [];

  // ─── labels (Bengali first, as the staff read them) ─────────────────────────
  static Color _metalDot(String v) {
    switch (v.toLowerCase()) {
      case 'gold':
        return _T.goldDot;
      case 'silver':
        return _T.silverDot;
      case 'platinum':
        return _T.platDot;
      case 'gold-coated':
        return const Color(0xFFB45309);
      case 'mixed':
        return const Color(0xFF8B5CF6);
      default:
        return _T.accent;
    }
  }

  static String _metalBn(String v) => const {'gold': 'সোনা', 'silver': 'রুপা', 'mixed': 'মিশ্র', 'gold-coated': 'গোল্ড কোটেড', 'platinum': 'প্লাটিনাম'}[v.toLowerCase()] ?? _fmt(v);
  static String _itemBn(String v) =>
      const {'ring': 'আংটি', 'necklace': 'হার', 'earring': 'কানের দুল', 'bracelet': 'ব্রেসলেট', 'pendant': 'পেন্ডেন্ট', 'chain': 'চেইন', 'bangle': 'বালা', 'other': 'অন্যান্য'}[v.toLowerCase()] ?? _fmt(v);
  static String _weightCatBn(String v) => const {'light': 'হালকা', 'medium': 'মাঝারি', 'heavy': 'ভারী'}[v.toLowerCase()] ?? v;
  static String _accBn(String v) => const {'exact': 'সঠিক', 'approx': 'আনুমানিক', 'bulk': 'বাল্ক'}[v] ?? v;
  static String _statusBn(String v) => const {'active': 'সক্রিয়', 'booked': 'বুক করা', 'in_repair': 'মেরামতে', 'sold': 'বিক্রিত', 'action_needed': 'পর্যালোচনা দরকার'}[v.toLowerCase()] ?? v;

  // ─── init ────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    widget.isEditMode ? _initEdit() : _initCreate();
    Future.microtask(_load);
  }

  String _num(double? v, {int d = 3}) => v == null || v == 0 ? '' : v.toStringAsFixed(d).replaceFirst(RegExp(r'\.?0+$'), '');

  void _initEdit() {
    final it = widget.item!;
    _barcode = it.barcode;
    _barcodeFromScan = true;
    _nameCtrl.text = it.name;
    _nameAuto = false;
    _weightCtrl.text = _num(it.netWeight);
    _grossCtrl.text = _num(it.grossWeight);
    _lessCtrl.text = _num(it.lessWeight);
    _piecesCtrl.text = it.numberOfPieces.toString();
    _descCtrl.text = it.description;
    _stoneValCtrl.text = _num(it.stoneValue, d: 2);
    _stoneNoteCtrl.text = it.stoneNote;
    _makingCtrl.text = _num(it.makingCharge, d: 2);
    _supplierCtrl.text = it.supplier;
    _sizeCtrl.text = it.size;
    _wastageCtrl.text = _num(it.wastage, d: 2);
    _custWastageCtrl.text = _num(it.custWastage, d: 2);
    _labourCtrl.text = _num(it.labourRate, d: 2);
    _makingRateCtrl.text = _num(it.makingRate, d: 2);
    _stonesOpen = (it.stoneValue ?? 0) > 0 || it.stoneNote.isNotEmpty || (it.lessWeight ?? 0) > 0;
    _metalType = it.metalType.isNotEmpty ? it.metalType : null;
    _purity = it.purity.isNotEmpty ? it.purity : null;
    _itemType = it.itemType.isNotEmpty ? it.itemType : null;
    _weightCategory = it.weightCategory;
    _categoryTouched = true;
    _weightAccuracy = it.weightAccuracy;
    _status = it.status;
    _cert = it.certificationType == 'huid' ? 'huid' : (it.certificationType == 'hallmarked' ? 'hallmarked' : 'none');
    _certChosen = true;
    if (_cert == 'huid' && it.huidNumber != null) _huidCtrl.text = it.huidNumber!;
    _selectedContainerId = it.containerId;
    _selectedSlotNumber = it.slotNumber;
    _existingImages.addAll(it.images);
  }

  void _initCreate() {
    _barcode = widget.barcode ?? _genBarcode();
    _barcodeFromScan = widget.barcode != null;
    // Quick mode always starts as action_needed → bypasses the box requirement
    _status = widget.isQuickMode ? 'action_needed' : 'active';
    if (widget.initialContainerId != null) {
      _selectedContainerId = widget.initialContainerId;
      _selectedSlotNumber = widget.initialSlotNumber;
    }
  }

  Future<void> _load() async {
    final s = Provider.of<SettingsProvider>(context, listen: false);
    if (s.metalTypes.isEmpty || s.purityOptions.isEmpty) await s.fetchItemSettings();
    if (!mounted) return;
    final cp = Provider.of<ContainerProvider>(context, listen: false);
    if (cp.containers.isEmpty) await cp.fetchContainers();
    if (!mounted) return;
    try {
      final r = await _apiService.stockSettings();
      _rules = Map<String, dynamic>.from((r['data'] as Map)['settings'] as Map);
    } catch (_) {/* the defaults inside the engine apply */}
    try {
      final m = Map<String, dynamic>.from(((await _apiService.billingMeta())['data'] ?? {}) as Map);
      _goldRate = (m['goldRate'] as num?)?.toDouble() ?? 0;
      _silverRate = (m['silverRate'] as num?)?.toDouble() ?? 0;
    } catch (_) {/* no rate suggestion */}
    if (!mounted) return;

    setState(() {
      _metals = s.metalTypes.isNotEmpty ? s.metalTypes : _fallbackMetals;
      _itemTypes = s.itemTypes.isNotEmpty ? s.itemTypes : _fallbackItemTypes;
      _purities = s.purityOptions.isNotEmpty ? s.purityOptions : _fallbackPurities;
      _containers = cp.containers.where((c) => !c.isDeleted).map((c) {
        // the box the item is already in stays selectable even when full
        final mine = c.id == widget.item?.containerId;
        final ok = mine || (c.isActive && !c.isLocked && c.availableSlots > 0);
        final free = c.slots.where((sl) => sl.itemId == null && !sl.reserved).map((sl) => sl.slotNumber).toList();
        return {
          'id': c.id,
          'name': c.name,
          'code': c.qrCode ?? c.id.substring(0, 4),
          'available': c.availableSlots,
          'total': c.capacity,
          'free': free,
          'ok': ok,
          'status': c.isLocked ? 'লক' : (!c.isActive ? 'নিষ্ক্রিয়' : (!ok ? 'পূর্ণ' : 'সক্রিয়')),
        };
      }).toList()
        ..sort((a, b) => ((b['ok'] as bool) ? 1 : 0).compareTo((a['ok'] as bool) ? 1 : 0));
      _isLoading = false;
    });
    _autoName();
  }

  String _genBarcode() => (DateTime.now().millisecondsSinceEpoch % 90000 + 10000).toString();

  void _refreshBarcode() => setState(() => _barcode = _genBarcode());

  @override
  void dispose() {
    for (final c in [_nameCtrl, _grossCtrl, _lessCtrl, _weightCtrl, _huidCtrl, _piecesCtrl, _descCtrl, _stoneValCtrl, _stoneNoteCtrl, _makingCtrl, _supplierCtrl, _sizeCtrl, _wastageCtrl, _custWastageCtrl, _rateCtrl, _labourCtrl, _makingRateCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // ─── numbers ─────────────────────────────────────────────────────────────────
  /// The live price, worked out with the Stock Setting rules (same engine as the server).
  StockPrice get _price => computeStock({
        'net': _weightCtrl.text.trim(),
        'gross': _grossCtrl.text.trim(),
        'purity': _purity ?? '',
        'wastage': _wastageCtrl.text,
        'custWastage': _custWastageCtrl.text,
        'rate': _rateCtrl.text,
        'labourRate': _labourCtrl.text,
        'makingRate': _makingRateCtrl.text,
        'stoneValue': _stoneValCtrl.text,
        'pieces': _piecesCtrl.text,
        'certification': _cert,
      }, _rules);

  /// Suggest today's rate for the metal when the rate box is still empty.
  void _suggestRate() {
    if (_rateCtrl.text.trim().isNotEmpty) return;
    final m = (_metalType ?? '').toLowerCase();
    final r = m.contains('silver') ? _silverRate : (m.contains('gold') ? _goldRate : 0.0);
    if (r > 0) _rateCtrl.text = _num(r, d: 2);
  }

  double _d(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  double get _net => _d(_weightCtrl);

  bool get _certOk => _certChosen || widget.isQuickMode;
  bool get _step1Ok => _metalType != null && _purity != null && _certOk;
  bool get _step2Ok => _net > 0 && (_grossCtrl.text.isEmpty || _d(_grossCtrl) + 0.0005 >= _net) && (_cert != 'huid' || _huidCtrl.text.trim().length == 6 || widget.isQuickMode);
  bool get _canSave => _step1Ok && _step2Ok;

  /// Gross and less weight decide the net weight; typing the net directly still works.
  void _onGrossOrLess() {
    final g = _d(_grossCtrl), l = _d(_lessCtrl);
    if (g > 0) {
      final n = g - l;
      _weightCtrl.text = n > 0 ? _num(n) : '';
    }
    _autoCategory();
    setState(() {});
  }

  void _onNet() {
    final g = _d(_grossCtrl);
    if (g > 0 && _net > 0 && g >= _net) _lessCtrl.text = _num(g - _net);
    _autoCategory();
    setState(() {});
  }

  /// Same bands the server uses to pick a box: over 10 g heavy, over 5 g medium.
  void _autoCategory() {
    if (_categoryTouched || _net <= 0) return;
    _weightCategory = _net > 10 ? 'Heavy' : (_net > 5 ? 'Medium' : 'Light');
  }

  void _autoName() {
    if (!_nameAuto || widget.isEditMode) return;
    final parts = [if (_metalType != null) _metalBn(_metalType!), if (_itemType != null && _itemType != 'other') _itemBn(_itemType!)];
    _nameCtrl.text = parts.isEmpty ? '' : parts.join(' ');
    if (mounted) setState(() {});
  }

  // ─── camera / images (Cloudinary, unchanged) ─────────────────────────────────
  Future<void> _camera() async {
    // maxWidth/maxHeight bound the decoded size so a high-megapixel photo cannot spike memory while the camera app is in
    // the foreground (that spike is what makes Android kill this app in the background and "restart" it on return).
    final img = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 1600, maxHeight: 1600);
    if (img == null) return;
    setState(() => _isUploadingImages = true);
    try {
      final r = await _apiService.uploadImage(img);
      if (r['success'] == true) setState(() => _newImageUrls.add(r['data']['url'] as String));
    } catch (e) {
      if (mounted) _snack('আপলোড ব্যর্থ', _T.danger);
    }
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
        if (r['success'] == true) {
          ok++;
          setState(() => _newImageUrls.add(r['data']['url'] as String));
        }
      } catch (_) {}
    }
    setState(() => _isUploadingImages = false);
    if (mounted && ok > 0) _snack('$ok টি ছবি আপলোড হয়েছে', _T.success);
  }

  Future<void> _deleteImg(int idx, {bool existing = false}) async {
    if (_deletingIdx == idx && _deletingExisting == existing) return;
    setState(() {
      _deletingIdx = idx;
      _deletingExisting = existing;
    });
    final url = existing ? _existingImages[idx] : _newImageUrls[idx];
    try {
      if (await _apiService.deleteImage(url)) {
        setState(() {
          existing ? _existingImages.removeAt(idx) : _newImageUrls.removeAt(idx);
          _deletingIdx = null;
          _deletingExisting = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) _snack('ছবি মুছতে পারা যায়নি', _T.danger);
    setState(() {
      _deletingIdx = null;
      _deletingExisting = false;
    });
  }

  Future<void> _deleteItem() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('আইটেম মুছবেন?'),
            content: const Text('এটি পূর্বাবস্থায় ফেরানো যাবে না।'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
              TextButton(style: TextButton.styleFrom(foregroundColor: _T.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('মুছুন')),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    final p = Provider.of<ItemProvider>(context, listen: false);
    if (await p.deleteItem(widget.item!.id)) {
      Navigator.pop(context);
      _snack('মুছে ফেলা হয়েছে', _T.success);
    } else {
      _snack(p.error ?? 'মুছতে ব্যর্থ', _T.danger);
    }
  }

  // ─── save ────────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!_canSave) {
      _snack('Fill metal, purity and weight', _T.warn);
      return;
    }
    setState(() => _isSaving = true);
    final allImgs = [..._existingImages, ..._newImageUrls];
    final effectiveStatus = widget.isQuickMode ? 'action_needed' : _status;
    final name = _nameCtrl.text.trim().isEmpty ? 'Unnamed - $_barcode' : _nameCtrl.text.trim();
    double? opt(TextEditingController c) => c.text.trim().isEmpty ? null : double.tryParse(c.text.trim());

    final data = {
      'barcode': _barcode,
      'name': name,
      'itemType': _itemType ?? 'other',
      'metalType': _metalType!,
      'purity': _purity!,
      'netWeight': _net,
      'numberOfPieces': int.tryParse(_piecesCtrl.text) ?? 1,
      'weightAccuracy': _weightAccuracy,
      'weightCategory': _weightCategory,
      'certificationType': _cert,
      'huidNumber': _cert == 'huid' && _huidCtrl.text.trim().isNotEmpty ? _huidCtrl.text.trim() : null,
      'description': _descCtrl.text,
      'containerId': _selectedContainerId,
      'slotNumber': _selectedSlotNumber,
      'images': jsonEncode(allImgs),
      'status': effectiveStatus,
      // optional billing detail (null clears a value that was set before)
      'grossWeight': opt(_grossCtrl),
      'lessWeight': opt(_lessCtrl),
      'stoneValue': opt(_stoneValCtrl),
      'stoneNote': _stoneNoteCtrl.text.trim(),
      'makingCharge': _price.makingForBilling + _d(_makingCtrl) > 0 ? _price.makingForBilling + _d(_makingCtrl) : null,
      'wastage': opt(_wastageCtrl),
      'custWastage': opt(_custWastageCtrl),
      'labourRate': opt(_labourCtrl),
      'makingRate': opt(_makingRateCtrl),
      'supplier': _supplierCtrl.text.trim(),
      'size': _sizeCtrl.text.trim(),
    };

    final p = Provider.of<ItemProvider>(context, listen: false);
    final success = widget.isEditMode ? await p.updateItem(widget.item!.id, data, []) : await p.createItem(data, []);
    setState(() => _isSaving = false);
    if (!mounted) return;
    if (success) {
      _snack(widget.isEditMode ? 'Item updated' : 'Saved', _T.success);
      Navigator.pop(context, true);
    } else {
      _snack(p.error ?? 'Could not save', _T.danger);
    }
  }

  Future<void> _scanBarcode() async {
    if (kIsWeb) return;
    final v = await Navigator.push<String>(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => const BarcodeScannerForAssignment()));
    if (v == null || v.isEmpty) return;
    setState(() => _barcode = v);
  }

  void _snack(String msg, Color bg) => showAppSnackBar(
      context,
      SnackBar(
          content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
          backgroundColor: bg,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 12)));

  // ─── navigation ──────────────────────────────────────────────────────────────

  String? get _blocker {
    if (_step == 0 && !_step1Ok) return _metalType == null ? 'Choose the metal' : 'Choose the purity';
    if (_step == 1 && !_step2Ok) {
      if (_net <= 0) return 'Enter the net weight';
      if (_grossCtrl.text.isNotEmpty && _d(_grossCtrl) + 0.0005 < _net) return 'Net weight cannot be more than gross';
      return 'HUID must be 6 characters';
    }
    return null;
  }

  void _next() {
    final b = _blocker;
    if (b != null) {
      _snack(b, _T.warn);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _step = (_step + 1).clamp(0, 2));
  }

  void _goTo(int s) {
    if (s > _step) {
      if (!_step1Ok || (s == 2 && !_step2Ok)) {
        _snack(_step1Ok ? 'Enter the net weight' : 'Choose metal and purity', _T.warn);
        return;
      }
    }
    FocusScope.of(context).unfocus();
    setState(() => _step = s);
  }

  // ─── BUILD ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) setState(() => _step--);
      },
      child: Scaffold(
        backgroundColor: _T.bg,
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: _T.accent))
              : Column(children: [
                  _buildHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Column(children: [_stepItem(), _stepWeight(), _stepStock()]),
                        ),
                      ),
                    ),
                  ),
                  _buildBar(),
                ]),
        ),
      ),
    );
  }

  Widget _buildHeader() => Container(
        color: _T.card,
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18), color: _T.text1, onPressed: () => Navigator.pop(context)),
          Expanded(child: Text(widget.isEditMode ? 'Edit stock' : 'New stock', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _T.text1))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: _T.accentBg, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.qr_code, size: 13, color: _T.accent),
              const SizedBox(width: 4),
              Text(_barcode, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _T.accent)),
            ]),
          ),
          if (widget.isEditMode)
            IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 20, color: _T.danger), onPressed: _deleteItem, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 36, minHeight: 36)),
        ]),
      );

  Widget _buildStepper() {
    const labels = ['Item', 'Weight', 'Stock'];
    const icons = [Icons.diamond_outlined, Icons.scale_outlined, Icons.inventory_2_outlined];
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
                decoration: BoxDecoration(
                  color: _step == i ? _T.accent : (i < _step ? _T.accentBg : _T.bg),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _step == i ? _T.accent : _T.border),
                ),
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

  // ─── STEP 1: item ────────────────────────────────────────────────────────────
  Widget _stepItem() => Column(children: [
        _card('Photos', Icons.camera_alt_outlined, _buildImages()),
        _card(
          'Item',
          Icons.diamond_outlined,
          Column(children: [
            _two(
              _dd('Metal *', _metalType, _metals, (v) {
                setState(() {
                  _metalType = v;
                  if (_purity != null && !_puritiesForMetal().contains(_purity)) _purity = null;
                  _rateCtrl.clear();
                });
                _suggestRate();
                _autoName();
              }, label: (v) => '${_fmt(v)}  ·  ${_metalBn(v)}'),
              _dd('Purity *', _purity, _puritiesForMetal(), (v) => setState(() => _purity = v), label: (v) => v.toUpperCase()),
            ),
            const SizedBox(height: 10),
            _two(
              _dd('Type', _itemType, _itemTypes, (v) {
                setState(() => _itemType = v);
                _autoName();
              }, label: (v) => '${_fmt(v)}  ·  ${_itemBn(v)}'),
              _tf(_piecesCtrl, 'Pieces', number: true, digitsOnly: true),
            ),
            const SizedBox(height: 10),
            _tf(_nameCtrl, 'Name', onChanged: (_) => _nameAuto = false),
          ]),
        ),
        _certCard(),
      ]);

  /// Hallmark / HUID: its own amber card, and the form cannot be saved until staff have answered it.
  Widget _certCard() {
    const amber = Color(0xFFD97706);
    Widget opt(String value, String label, IconData icon) {
      final sel = _certChosen && _cert == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _cert = value;
            _certChosen = true;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: sel ? amber : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: sel ? amber : amber.withValues(alpha: 0.45), width: sel ? 1.6 : 1.2)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: sel ? Colors.white : amber),
              const SizedBox(width: 4),
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: sel ? Colors.white : const Color(0xFF92400E)))),
            ]),
          ),
        ),
      );
    }

    final unanswered = !_certChosen && !widget.isQuickMode;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: unanswered ? const Color(0xFFDC2626) : amber, width: unanswered ? 2 : 1.4),
        boxShadow: [BoxShadow(color: (unanswered ? const Color(0xFFDC2626) : amber).withValues(alpha: 0.18), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.verified_rounded, color: amber, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Hallmark / HUID', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF92400E)))),
          if (unanswered) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFDC2626), borderRadius: BorderRadius.circular(20)), child: const Text('CHOOSE ONE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white))),
        ]),
        const SizedBox(height: 8),
        Row(children: [opt('none', 'None', Icons.block_rounded), const SizedBox(width: 8), opt('hallmarked', 'Hallmarked', Icons.verified_outlined), const SizedBox(width: 8), opt('huid', 'HUID', Icons.fingerprint_rounded)]),
        if (_certChosen && _cert == 'huid') ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: _huidCtrl,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 2),
            onChanged: (_) => setState(() {}),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')), TextInputFormatter.withFunction((o, n) => TextEditingValue(text: n.text.toUpperCase(), selection: n.selection))],
            decoration: billDec('HUID number * (6 letters / digits)', amber),
          ),
        ],
      ]),
    );
  }

  /// Only the purities that make sense for the chosen metal (silver grades for silver ...); everything for "mixed".
  List<String> _puritiesForMetal() {
    final m = (_metalType ?? '').toLowerCase();
    if (m.isEmpty || m == 'mixed') return _purities;
    bool isSil(String p) => p.toLowerCase().contains('silver');
    bool isPla(String p) => p.toLowerCase().contains('platinum');
    final list = _purities.where((p) => m == 'silver' ? isSil(p) : m == 'platinum' ? isPla(p) : (!isSil(p) && !isPla(p))).toList();
    // keep a value that is already chosen (an old item) and never show an empty list
    if (_purity != null && !list.contains(_purity)) list.insert(0, _purity!);
    return list.isEmpty ? _purities : list;
  }

  // ─── STEP 2: weight, certification, stones, making ───────────────────────────
  Widget _stepWeight() {
    final g = _d(_grossCtrl), l = _d(_lessCtrl);
    return Column(children: [
      _card(
        'Weight (g)',
        Icons.scale_outlined,
        Column(children: [
          // Gross and Net sit side by side (the two fields almost every piece needs) so a quick add needs no jumping
          // between rows; Less and Accuracy — used less often — are the second row.
          _two(_tf(_grossCtrl, 'Gross', number: true, onChanged: (_) => _onGrossOrLess()), _tf(_weightCtrl, 'Net *', number: true, bold: true, onChanged: (_) => _onNet())),
          const SizedBox(height: 10),
          _two(_tf(_lessCtrl, 'Less (stone / other)', number: true, onChanged: (_) => _onGrossOrLess()), _dd('Accuracy', _weightAccuracy, _accuracies, (v) => setState(() => _weightAccuracy = v ?? 'exact'), label: (v) => _fmt(v))),
          if (g > 0 && l > 0) Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 5), child: Text('Net = gross ${_num(g)} − less ${_num(l)}', style: const TextStyle(fontSize: 11, color: _T.text3)))),
          const SizedBox(height: 10),
          _two(_dd('Weight class', _weightCategory, _weightCategories, (v) => setState(() {
                _weightCategory = v ?? 'Light';
                _categoryTouched = true;
              }), label: (v) => '$v  ·  ${_weightCatBn(v)}'), const SizedBox.shrink()),
        ]),
      ),
      _card(
        'Price',
        Icons.currency_rupee_rounded,
        Column(children: [
          _two(_tf(_rateCtrl, 'Rate ₹ / g', number: true, money: true), _tf(_wastageCtrl, 'Wastage %', number: true, money: true)),
          const SizedBox(height: 10),
          _two(_tf(_labourCtrl, 'Labour ₹ / g', number: true, money: true), _tf(_makingRateCtrl, 'Making ₹ / g', number: true, money: true)),
          const SizedBox(height: 10),
          _two(_tf(_makingCtrl, 'Fixed making ₹', number: true, money: true), _tf(_custWastageCtrl, 'Cust. wastage %', number: true, money: true)),
          const SizedBox(height: 10),
          _two(_tf(_stoneValCtrl, 'Stone value ₹', number: true, money: true), _tf(_stoneNoteCtrl, 'Stone details')),
          const SizedBox(height: 10),
          _two(_tf(_sizeCtrl, 'Size'), const SizedBox.shrink()),
          const SizedBox(height: 12),
          _priceBreakdown(),
        ]),
      ),
    ]);
  }

  Widget _priceBreakdown() {
    final p = _price;
    final basisName = {'finalFine': 'final fine', 'fine': 'fine', 'net': 'net', 'gross': 'gross'};
    final add = Map<String, dynamic>.from((_rules['addStock'] as Map?) ?? const {});
    String m(double v) => '₹${v.toStringAsFixed(2)}';
    final rows = <(String, String)>[
      ('Purity', '${p.purityPct.toStringAsFixed(2)} %'),
      ('Fine wt', '${p.fine.toStringAsFixed(3)} g'),
      ('Final fine wt', '${p.finalFine.toStringAsFixed(3)} g'),
      if (p.custWastageWt > 0) ('Cust. wastage wt', '${p.custWastageWt.toStringAsFixed(3)} g'),
      ('Metal valuation (${basisName[add['valuation'] ?? 'finalFine']} wt ${p.valuationWt.toStringAsFixed(3)} g)', m(p.metalValuation)),
      if (p.labourTotal > 0) ('Labour', m(p.labourTotal)),
      if (p.makingTotal > 0 || _d(_makingCtrl) > 0) ('Making', m(p.makingTotal + _d(_makingCtrl))),
      if (p.stoneValuation > 0) ('Stones', m(p.stoneValuation)),
      if (p.hallmarkCharge > 0) ('Hallmark', m(p.hallmarkCharge)),
      ('Taxable', m(p.taxable + _d(_makingCtrl))),
      ('GST', m(p.totalGst + _d(_makingCtrl) * 0.03)),
    ];
    final total = p.finalPrice + _d(_makingCtrl) * 1.03;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _T.accentBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _T.accent.withValues(alpha: 0.25))),
      child: Column(children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [Expanded(child: Text(r.$1, style: const TextStyle(fontSize: 12, color: _T.text2))), Text(r.$2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))]),
          ),
        const Divider(height: 14),
        Row(children: [const Expanded(child: Text('Final price', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _T.accent))), Text(m(total), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: _T.accent))]),
      ]),
    );
  }

  // ─── STEP 3: where it lives, status, barcode, summary ───────────────────────
  Widget _stepStock() => Column(children: [
        if (!widget.isQuickMode) _card('Location', Icons.inventory_2_outlined, _buildBoxPicker()),
        _card(
          'Details',
          Icons.tune_rounded,
          Column(children: [
            _two(
              (widget.isEditMode || !widget.isQuickMode) ? _dd('Status', _status, _statuses, (v) => setState(() => _status = v ?? _status), label: (v) => '${_fmt(v)}  ·  ${_statusBn(v)}') : const SizedBox.shrink(),
              _tf(_supplierCtrl, 'Supplier'),
            ),
            const SizedBox(height: 10),
            _tf(_descCtrl, 'Notes', lines: 2),
          ]),
        ),
        _card('Barcode', Icons.qr_code_rounded, _buildBarcodeRow()),
        _buildSummary(),
      ]);

  Widget _buildBoxPicker() {
    if (_containers.isEmpty) return const Text('No boxes found', style: TextStyle(fontSize: 13, color: _T.text3));
    final cur = _containers.where((c) => c['id'] == _selectedContainerId).toList();
    final box = cur.isEmpty ? null : cur.first;
    final free = box == null ? <int>[] : List<int>.from(box['free'] as List);
    if (box != null && _selectedSlotNumber != null && !free.contains(_selectedSlotNumber)) free.insert(0, _selectedSlotNumber!);
    return _two(
      DropdownButtonFormField<String>(
        value: box == null ? '' : _selectedContainerId,
        isExpanded: true,
        style: const TextStyle(fontSize: 13, color: Colors.black87),
        decoration: billDec('Box', _T.accent),
        items: [
          const DropdownMenuItem(value: '', child: Text('Auto (best box)')),
          for (final c in _containers)
            DropdownMenuItem(
              value: c['id'] as String,
              enabled: c['ok'] as bool,
              child: Text('${c['name']} (${c['code']}) · ${c['available']}/${c['total']} free${(c['ok'] as bool) ? '' : ' · ${c['status']}'}', overflow: TextOverflow.ellipsis, style: TextStyle(color: (c['ok'] as bool) ? Colors.black87 : Colors.black38)),
            ),
        ],
        onChanged: (v) => setState(() {
          _selectedContainerId = (v == null || v.isEmpty) ? null : v;
          _selectedSlotNumber = null;
        }),
      ),
      DropdownButtonFormField<int?>(
        value: box == null ? null : (free.contains(_selectedSlotNumber) ? _selectedSlotNumber : null),
        isExpanded: true,
        style: const TextStyle(fontSize: 13, color: Colors.black87),
        decoration: billDec('Slot', _T.accent),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('Auto')),
          for (final n in free.take(200)) DropdownMenuItem<int?>(value: n, child: Text('Slot $n')),
        ],
        onChanged: box == null ? null : (v) => setState(() => _selectedSlotNumber = v),
      ),
    );
  }

  Future<void> _pickBox() async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, sc) => Column(children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Align(alignment: Alignment.centerLeft, child: Text('বাক্স বেছে নিন', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)))),
          Expanded(
            child: ListView(controller: sc, children: [
              ListTile(leading: const Icon(Icons.auto_awesome, color: _T.accent), title: const Text('অটো (সেরা বাক্স)'), subtitle: const Text('ওজন ও ধরন অনুযায়ী সিস্টেম বেছে নেবে'), onTap: () => Navigator.pop(ctx, '')),
              for (final c in _containers)
                ListTile(
                  enabled: c['ok'] as bool,
                  leading: Icon((c['ok'] as bool) ? Icons.inventory_2_outlined : Icons.block, color: (c['ok'] as bool) ? _T.success : _T.text3),
                  title: Text('${c['name']} (${c['code']})', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${c['available']}/${c['total']} স্লট খালি · ${c['status']}'),
                  trailing: c['id'] == _selectedContainerId ? const Icon(Icons.check_circle, color: _T.accent) : null,
                  onTap: () => Navigator.pop(ctx, c['id'] as String),
                ),
            ]),
          ),
        ]),
      ),
    );
    if (pick == null) return;
    setState(() {
      _selectedContainerId = pick.isEmpty ? null : pick;
      _selectedSlotNumber = null;
    });
  }

  Widget _buildBarcodeRow() => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: _T.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: _T.border)),
        child: Row(children: [
          Expanded(
              flex: 2,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('BARCODE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _T.text3, letterSpacing: 0.8)),
                const SizedBox(height: 3),
                Text(_barcode, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'monospace', color: _T.text1)),
              ])),
          Expanded(flex: 3, child: SizedBox(height: 34, child: BarcodeWidget(barcode: Barcode.code128(), data: _barcode, drawText: false, color: _T.text1))),
          const SizedBox(width: 6),
          if (!kIsWeb) _iconBtn(Icons.qr_code_scanner, _T.accent, _scanBarcode),
          if (!_barcodeFromScan || !widget.isEditMode) _iconBtn(Icons.refresh_rounded, _T.text3, _refreshBarcode),
        ]),
      );

  Widget _buildSummary() {
    final box = _containers.where((c) => c['id'] == _selectedContainerId).toList();
    final rows = <(String, String)>[
      ('Name', _nameCtrl.text.trim().isEmpty ? 'Unnamed - $_barcode' : _nameCtrl.text.trim()),
      ('Metal / purity', '${_metalType == null ? '-' : _metalBn(_metalType!)} · ${(_purity ?? '-').toUpperCase()}'),
      ('Weight', 'Net ${_num(_net)} g${_d(_grossCtrl) > 0 ? ' (গ্রস ${_num(_d(_grossCtrl))})' : ''} · ${_piecesCtrl.text} pcs'),
      if (_cert != 'none') ('Certificate', _cert == 'huid' ? 'HUID ${_huidCtrl.text}' : 'হলমার্ক'),
      if (_d(_makingCtrl) > 0 || _d(_stoneValCtrl) > 0) ('Making / stones', '₹${_num(_d(_makingCtrl), d: 2).isEmpty ? '0' : _num(_d(_makingCtrl), d: 2)} / ₹${_num(_d(_stoneValCtrl), d: 2).isEmpty ? '0' : _num(_d(_stoneValCtrl), d: 2)}'),
      ('Box', box.isEmpty ? 'Auto' : '${box.first['name']}${_selectedSlotNumber == null ? '' : ' · স্লট $_selectedSlotNumber'}'),
      ('Photos', '${_existingImages.length + _newImageUrls.length}'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _T.accentBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: _T.accent.withValues(alpha: 0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Summary', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _T.accent)),
        const SizedBox(height: 8),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 108, child: Text(r.$1, style: const TextStyle(fontSize: 12, color: _T.text2))),
              Expanded(child: Text(r.$2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _T.text1))),
            ]),
          ),
      ]),
    );
  }

  // ─── images ──────────────────────────────────────────────────────────────────
  Widget _buildImages() {
    final all = [..._existingImages.asMap().entries.map((e) => (e.key, e.value, true)), ..._newImageUrls.asMap().entries.map((e) => (e.key, e.value, false))];
    return Column(children: [
      if (all.isNotEmpty) ...[
        SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: all.length + (_isUploadingImages ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                if (i == all.length) {
                  return Container(width: 64, height: 64, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: _T.accentBg), child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _T.accent))));
                }
                final (idx, url, isExist) = all[i];
                final del = _deletingIdx == idx && _deletingExisting == isExist;
                return Stack(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(url, width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 64, height: 64, color: _T.border, child: const Icon(Icons.broken_image)))),
                  if (del) Positioned.fill(child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.black45), child: const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))))),
                  Positioned(top: 3, right: 3, child: GestureDetector(onTap: del ? null : () => _deleteImg(idx, existing: isExist), child: Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: _T.danger, shape: BoxShape.circle), child: const Icon(Icons.close, size: 11, color: Colors.white)))),
                ]);
              },
            )),
        const SizedBox(height: 10),
      ],
      Row(children: [
        Expanded(child: _imgBtn(Icons.camera_alt_outlined, 'Camera', _isUploadingImages, _camera)),
        const SizedBox(width: 8),
        Expanded(child: _imgBtn(Icons.photo_library_outlined, 'Gallery', false, _gallery)),
      ]),
    ]);
  }

  Widget _imgBtn(IconData icon, String label, bool loading, VoidCallback onTap) => GestureDetector(
        onTap: loading ? null : onTap,
        child: Container(
          height: 38,
          decoration: BoxDecoration(color: _T.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: _T.border)),
          child: loading
              ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _T.accent)))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 17, color: _T.accent), const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _T.text2))]),
        ),
      );

  // ─── bottom bar ──────────────────────────────────────────────────────────────
  Widget _buildBar() {
    final last = _step == 2;
    final ready = last ? (_canSave && !_isSaving) : true;
    final blocker = !_step1Ok ? (_metalType == null ? 'Choose the metal' : (_purity == null ? 'Choose the purity' : 'Choose the hallmark status')) : (!_step2Ok ? (_net <= 0 ? 'Enter the net weight' : (_cert == 'huid' && _huidCtrl.text.trim().length != 6 ? 'Enter the 6-character HUID' : 'Net weight cannot be more than gross')) : null);
    return Container(
      padding: EdgeInsets.fromLTRB(14, 8, 14, MediaQuery.of(context).padding.bottom + 10),
      decoration: const BoxDecoration(color: _T.card, boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, -2))]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (blocker != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(blocker, style: const TextStyle(fontSize: 12, color: _T.warn, fontWeight: FontWeight.w600))),
        Row(children: [
          if (false) ...[
            Expanded(flex: 2, child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), side: const BorderSide(color: _T.border)), onPressed: () => setState(() => _step--), child: const Text('Back', style: TextStyle(fontWeight: FontWeight.w700, color: _T.text2)))),
            const SizedBox(width: 10),
          ],
          Expanded(
            flex: 4,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: last ? _T.success : _T.accent, minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: (last ? (ready ? _save : null) : _next),
              child: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(last ? (widget.isEditMode ? 'Update' : 'Save') : 'Next', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 6),
                      Icon(last ? Icons.check_rounded : Icons.arrow_forward_rounded, size: 19),
                    ]),
            ),
          ),
        ]),
      ]),
    );
  }

  // ─── small building blocks ───────────────────────────────────────────────────
  Widget _card(String label, IconData icon, Widget child, {bool required = false}) => BillCard(title: label, icon: icon, color: _T.accent, child: child);

  Widget _two(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 8), Expanded(child: b)]);

  /// Floating-label dropdown (same look as the billing screens).
  Widget _dd(String title, String? value, List<String> options, ValueChanged<String?> onChanged, {String Function(String)? label}) {
    final show = label ?? (String v) => v;
    final list = [...options];
    if (value != null && !list.contains(value)) list.insert(0, value);
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      style: const TextStyle(fontSize: 13, color: Colors.black87),
      decoration: billDec(title, _T.accent),
      items: [for (final o in list) DropdownMenuItem(value: o, child: Text(show(o), overflow: TextOverflow.ellipsis))],
      onChanged: onChanged,
    );
  }

  /// Floating-label text field.
  Widget _tf(TextEditingController c, String label, {bool number = false, bool money = false, bool digitsOnly = false, bool bold = false, int lines = 1, ValueChanged<String>? onChanged}) => TextFormField(
        controller: c,
        maxLines: lines,
        keyboardType: number ? TextInputType.numberWithOptions(decimal: !digitsOnly) : TextInputType.text,
        inputFormatters: [if (number) FilteringTextInputFormatter.allow(digitsOnly ? RegExp(r'^\d*') : (money ? RegExp(r'^\d*\.?\d{0,2}') : RegExp(r'^\d*\.?\d{0,3}')))],
        onChanged: onChanged ?? (_) => setState(() {}),
        style: TextStyle(fontSize: bold ? 15 : 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w500),
        decoration: billDec(label, _T.accent),
      );

  Widget _chip(String text, bool sel, {required VoidCallback onTap, Color? dot, bool dark = false, bool small = false, bool expand = false}) {
    final on = dark ? _T.text1 : _T.accent;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        alignment: expand ? Alignment.center : null,
        padding: EdgeInsets.symmetric(horizontal: small ? 12 : 14, vertical: small ? 9 : 10),
        decoration: BoxDecoration(color: sel ? on : _T.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: sel ? on : _T.border, width: sel ? 1.5 : 1.2)),
        child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          if (dot != null) ...[Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)), const SizedBox(width: 6)],
          Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: small ? 12.5 : 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w600, color: sel ? Colors.white : _T.text2))),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, {int lines = 1, ValueChanged<String>? onChanged}) => TextFormField(controller: c, maxLines: lines, onChanged: onChanged, decoration: _inputDec(hint));

  Widget _numField(TextEditingController c, String label, {bool big = false, String? suffix, bool money = false, ValueChanged<String>? onChanged}) => TextFormField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(money ? RegExp(r'^\d*\.?\d{0,2}') : RegExp(r'^\d*\.?\d{0,3}'))],
        onChanged: onChanged ?? (_) => setState(() {}),
        style: TextStyle(fontSize: big ? 22 : 16, fontWeight: FontWeight.w800, color: _T.text1),
        decoration: _inputDec('').copyWith(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 13, color: _T.text3, fontWeight: FontWeight.w600),
          suffixText: suffix,
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: big ? 16 : 14),
        ),
      );

  Widget _label(String label, IconData icon) => Row(children: [Icon(icon, size: 13, color: _T.text3), const SizedBox(width: 5), Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _T.text2))]);

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) => GestureDetector(onTap: onTap, child: Container(width: 34, height: 34, margin: const EdgeInsets.only(left: 2), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 18)));

  InputDecoration _inputDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _T.text3, fontSize: 13),
        filled: true,
        fillColor: _T.bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _T.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _T.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _T.accent, width: 1.8)),
      );

  static String _fmt(String v) => v.isEmpty ? v : v.replaceAll('-', ' ').replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1)).join(' ');
}
