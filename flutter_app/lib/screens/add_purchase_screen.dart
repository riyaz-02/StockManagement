import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../providers/store_provider.dart';
import '../models/purchase_model.dart';
import '../models/store_models.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';

class AddPurchaseScreen extends StatefulWidget {
  /// Pass a [purchase] to open screen in edit mode.
  final Purchase? purchase;
  const AddPurchaseScreen({super.key, this.purchase});

  @override
  State<AddPurchaseScreen> createState() => _AddPurchaseScreenState();
}

class _AddPurchaseScreenState extends State<AddPurchaseScreen> {
  final _formKey         = GlobalKey<FormState>();
  final _invoiceNumCtrl  = TextEditingController();
  final _billerCtrl      = TextEditingController();
  final _billerGstinCtrl = TextEditingController();
  // Persistent date controller — updated whenever _invoiceDate changes
  late  TextEditingController _dateCtrl;
  final _quantityCtrl    = TextEditingController();
  final _rateCtrl        = TextEditingController();
  // Taxable amount (qty × rate). User can override.
  final _taxableCtrl     = TextEditingController();
  final _descCtrl        = TextEditingController();
  final _remarksCtrl     = TextEditingController();

  DateTime _invoiceDate   = DateTime.now();
  String _metalType       = 'gold';
  String _transactionType = 'intra-state';

  /// When user manually edits the taxable field.
  bool _taxableOverride = false;

  GstCalculation? _gst;
  bool _isCalcLoading = false;
  bool _isSaving      = false;
  bool _isDuplicate   = false;
  String? _dupMsg;

  final List<Map<String, dynamic>> _attachmentMeta = [];
  bool _isUploading = false;
  bool _showRemarks = false;

  // ── Suggestion data (loaded once on open) ─────────────────────────────────
  List<String> _supplierSuggestions  = [];
  List<String> _descSuggestions      = [];
  Map<String, String> _supplierGstins = {}; // supplier → GSTIN

  bool get _isEdit => widget.purchase != null;

  @override
  void initState() {
    super.initState();
    _dateCtrl = TextEditingController(text: _fmtDate(_invoiceDate));
    // Pre-fill fields in edit mode
    if (_isEdit) {
      final p = widget.purchase!;
      _invoiceDate = p.invoiceDate;
      _dateCtrl.text = _fmtDate(p.invoiceDate);
      _invoiceNumCtrl.text  = p.invoiceNumber;
      _billerCtrl.text      = p.biller;
      _billerGstinCtrl.text = p.billerGstin;
      _quantityCtrl.text    = p.quantity.toStringAsFixed(3);
      _rateCtrl.text        = p.rate.toStringAsFixed(2);
      _taxableCtrl.text     = p.totalAmount.toStringAsFixed(2);
      _descCtrl.text        = p.description;
      _remarksCtrl.text     = p.remarks;
      _metalType           = p.metalType;
      _transactionType     = p.transactionType;
      _taxableOverride     = true; // don't auto-overwrite on init
      // Keep existing attachments
      _attachmentMeta.addAll(p.attachmentMeta);
    }
    _loadSuggestions();
    // Trigger GST calc if taxable already set
    if (_taxableCtrl.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recalcGst());
    }
  }

  Future<void> _loadSuggestions() async {
    try {
      final api  = ApiService();
      final resp = await api.getPurchaseSuggestions();
      if (resp['success'] == true && mounted) {
        final data = resp['data'] as Map<String, dynamic>;
        setState(() {
          _supplierSuggestions = List<String>.from(data['suppliers'] ?? []);
          _descSuggestions     = List<String>.from(data['descriptions'] ?? []);
          _supplierGstins      = Map<String, String>.from(
              (data['supplierGstins'] as Map? ?? {}).map(
                  (k, v) => MapEntry(k.toString(), v.toString())));
        });
      }
    } catch (_) {/* suggestions are best-effort */}
  }

  @override
  void dispose() {
    for (final c in [
      _invoiceNumCtrl, _billerCtrl, _billerGstinCtrl,
      _dateCtrl, _quantityCtrl, _rateCtrl, _taxableCtrl,
      _descCtrl, _remarksCtrl,
    ]) { c.dispose(); }
    super.dispose();
  }

  // ── Amount / GST compute ─────────────────────────────────────────────────────
  void _onQtyRateChanged() {
    if (!_taxableOverride) {
      final q = double.tryParse(_quantityCtrl.text) ?? 0;
      final r = double.tryParse(_rateCtrl.text)     ?? 0;
      if (q > 0 && r > 0) {
        // Keep taxable to 2dp (monetary), weight displayed elsewhere as 3dp
        _taxableCtrl.text = (q * r).toStringAsFixed(2);
      }
    }
    _debounceGst();
  }

  void _onTaxableChanged() {
    _taxableOverride = true;
    _debounceGst();
  }

  void _resetTaxable() {
    final q = double.tryParse(_quantityCtrl.text) ?? 0;
    final r = double.tryParse(_rateCtrl.text)     ?? 0;
    if (q > 0 && r > 0) {
      setState(() {
        _taxableOverride = false;
        _taxableCtrl.text = (q * r).toStringAsFixed(2);
      });
      _debounceGst();
    }
  }

  void _debounceGst() {
    setState(() {}); // update computed display immediately
    _recalcGst();
  }

  Future<void> _recalcGst() async {
    final taxable = double.tryParse(_taxableCtrl.text) ?? 0;
    if (taxable <= 0) { setState(() => _gst = null); return; }
    setState(() => _isCalcLoading = true);
    final store = Provider.of<StoreProvider>(context, listen: false);
    final calc  = await store.calculateGst(
        baseAmount: taxable, transactionType: _transactionType);
    if (mounted) setState(() { _gst = calc; _isCalcLoading = false; });
  }

  // ── Invoice total (rounded) ───────────────────────────────────────────────
  double get _invoiceTotal {
    final taxable = double.tryParse(_taxableCtrl.text) ?? 0;
    if (_gst != null) return (_gst!.totalPayable).roundToDouble();
    // Estimated before GST loads (3%)
    return (taxable * 1.03).roundToDouble();
  }

  // ── File upload ───────────────────────────────────────────────────────────
  Future<void> _upload({required bool camera}) async {
    String? path; String mime = 'image/jpeg', name = 'photo.jpg';
    if (camera) {
      final img = await ImagePicker()
          .pickImage(source: ImageSource.camera, imageQuality: 85);
      if (img == null) return;
      path = img.path; name = img.name;
    } else {
      final res = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg','jpeg','png','webp','pdf']);
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      path = f.path; name = f.name;
      final ext = f.extension?.toLowerCase() ?? '';
      mime = ext == 'pdf' ? 'application/pdf' : 'image/$ext';
    }
    if (path == null) return;
    setState(() => _isUploading = true);
    if (!mounted) return;
    final store = Provider.of<StoreProvider>(context, listen: false);
    final meta  = await store.uploadPurchaseBill(
        filePath: path, mimeType: mime, originalName: name);
    if (mounted) {
      setState(() { _isUploading = false; if (meta != null) _attachmentMeta.add(meta); });
      _snack(meta != null ? 'Bill uploaded ✓' : 'Upload failed', isError: meta == null);
    }
  }

  Future<void> _removeAttachment(int i) async {
    final pid = _attachmentMeta[i]['publicId'] as String?;
    setState(() => _attachmentMeta.removeAt(i));
    if (pid != null && pid.isNotEmpty && mounted) {
      final store = Provider.of<StoreProvider>(context, listen: false);
      await store.deletePurchaseBillAttachment(pid);
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final qty     = double.tryParse(_quantityCtrl.text) ?? 0;
    final rate    = double.tryParse(_rateCtrl.text)     ?? 0;
    final taxable = double.tryParse(_taxableCtrl.text)  ?? 0;
    if (qty <= 0 || rate <= 0 || taxable <= 0) {
      _snack('Please fill weight, rate and verify amount');
      return;
    }
    setState(() { _isSaving = true; _isDuplicate = false; _dupMsg = null; });
    final store = Provider.of<StoreProvider>(context, listen: false);
    final payload = {
      'invoiceDate':     _invoiceDate.toIso8601String(),
      'invoiceNumber':   _invoiceNumCtrl.text.trim().toUpperCase(),
      'metalType':       _metalType,
      'biller':          _billerCtrl.text.trim(),
      'billerGstin':     _billerGstinCtrl.text.trim().toUpperCase(),
      'quantity':        qty,
      'rate':            rate,
      'totalAmount':     taxable,
      'transactionType': _transactionType,
      'description':     _descCtrl.text.trim(),
      'remarks':         _remarksCtrl.text.trim(),
      'attachmentMeta':  _attachmentMeta,
    };
    final err = _isEdit
        ? await store.updatePurchase(widget.purchase!.id, payload)
        : await store.createPurchase(payload);
    if (mounted) {
      setState(() => _isSaving = false);
      if (err == null) {
        _snack(_isEdit ? 'Updated ✓' : 'Purchase saved ✓', isError: false);
        Navigator.pop(context, true);
      } else {
        final dup = err.toLowerCase().contains('duplicate') ||
            err.toLowerCase().contains('already exists');
        setState(() { _isDuplicate = dup; _dupMsg = dup ? err : null; });
        _snack(err);
      }
    }
  }

  void _snack(String msg, {bool isError = true}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ));

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: Text(_isEdit ? 'Edit Purchase' : 'New Purchase',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
            child: _isSaving
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(_isEdit ? 'Update' : 'Save'),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 40),
          children: [

            // ── 1. Invoice Info ─────────────────────────────────────────────
            _card('INVOICE', [
              // Date — full width so it never truncates
              GestureDetector(
                onTap: _pickDate,
                child: AbsorbPointer(
                  child: TextFormField(
                    controller: _dateCtrl,
                    decoration: _dec('Invoice Date', Icons.calendar_today_outlined,
                        suffix: const Icon(Icons.arrow_drop_down,
                            size: 20, color: Colors.grey)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _invoiceNumCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: _dec('Invoice No. *', Icons.tag_outlined,
                    errorText: _dupMsg),
                onChanged: (_) {
                  if (_isDuplicate) setState(
                      () { _isDuplicate = false; _dupMsg = null; });
                },
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              // Supplier — Autocomplete
              _autocompleteField(
                label: 'Supplier *',
                icon: Icons.business_outlined,
                controller: _billerCtrl,
                suggestions: _supplierSuggestions,
                onSelected: (v) {
                  _billerCtrl.text = v;
                  final gstin = _supplierGstins[v];
                  if (gstin != null && gstin.isNotEmpty) {
                    setState(() => _billerGstinCtrl.text = gstin);
                  }
                },
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              // GSTIN
              TextFormField(
                controller: _billerGstinCtrl,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(15),
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]')),
                ],
                decoration: _dec('Supplier GSTIN', Icons.verified_outlined),
              ),
            ]),
            const SizedBox(height: 10),

            // ── 2. Metal & Amount ───────────────────────────────────────────
            _card('METAL & AMOUNT', [
              _metalSelector(),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _quantityCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _dec('Grams *', Icons.scale_outlined,
                        suffix: const Text('  g ',
                            style: TextStyle(fontWeight: FontWeight.w600,
                                color: Colors.grey))),
                    onChanged: (_) => _onQtyRateChanged(),
                    validator: (v) {
                      final d = double.tryParse(v ?? '');
                      return (d == null || d <= 0) ? 'Required' : null;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _rateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _dec('Rate/g *', Icons.currency_rupee_outlined),
                    onChanged: (_) => _onQtyRateChanged(),
                    validator: (v) {
                      final d = double.tryParse(v ?? '');
                      return (d == null || d <= 0) ? 'Required' : null;
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              // Taxable amount (editable)
              TextFormField(
                controller: _taxableCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _dec(
                  'Taxable Amt (₹) *',
                  Icons.currency_rupee_outlined,
                  suffix: _taxableOverride
                      ? GestureDetector(
                          onTap: _resetTaxable,
                          child: const Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: Icon(Icons.refresh_rounded,
                                size: 17, color: Colors.orange),
                          ),
                        )
                      : const Padding(
                          padding: EdgeInsets.only(right: 10),
                          child: Icon(Icons.auto_awesome,
                              size: 15, color: Colors.green),
                        ),
                ),
                onChanged: (_) => _onTaxableChanged(),
                validator: (v) {
                  final d = double.tryParse(v ?? '');
                  return (d == null || d <= 0) ? 'Required' : null;
                },
              ),

              // ── Invoice Total row (read-only computed) ────────────────────
              if ((double.tryParse(_taxableCtrl.text) ?? 0) > 0) ...[
                const SizedBox(height: 8),
                _invoiceTotalRow(),
              ],
            ]),
            const SizedBox(height: 10),

            // ── 3. Transaction Type ─────────────────────────────────────────
            _card('TRANSACTION TYPE', [_transactionSelector()]),
            const SizedBox(height: 10),

            // ── 4. GST Breakdown ────────────────────────────────────────────
            if (_isCalcLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  SizedBox(width: 15, height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Calculating…',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
              )
            else if (_gst != null) ...[
              _gstCard(_gst!),
              const SizedBox(height: 10),
            ],

            // ── 5. Description ──────────────────────────────────────────────
            _card('ITEM', [
              _autocompleteField(
                label: 'Description *',
                icon: Icons.category_outlined,
                controller: _descCtrl,
                suggestions: _descSuggestions,
                onSelected: (v) => setState(() => _descCtrl.text = v),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Required' : null,
              ),
            ]),
            const SizedBox(height: 10),

            // ── 6. Attachments ──────────────────────────────────────────────
            _card('BILL ATTACHMENTS', [
              for (int i = 0; i < _attachmentMeta.length; i++)
                _attachTile(i, _attachmentMeta[i]),
              if (_attachmentMeta.isNotEmpty) const SizedBox(height: 8),
              _isUploading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        SizedBox(width: 15, height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text('Uploading…',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ]),
                    )
                  : Row(children: [
                      Expanded(
                          child: _uploadBtn(Icons.camera_alt_outlined,
                              'Camera', () => _upload(camera: true))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _uploadBtn(Icons.attach_file_rounded,
                              'File / PDF', () => _upload(camera: false))),
                    ]),
            ]),
            const SizedBox(height: 10),

            // ── 7. Remarks (collapsible) ────────────────────────────────────
            GestureDetector(
              onTap: () => setState(() => _showRemarks = !_showRemarks),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: Colors.white,
                    borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  const Icon(Icons.note_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  const Text('Remarks / Notes',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Icon(_showRemarks ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: AppColors.primary),
                ]),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: _showRemarks
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14)),
                        child: TextFormField(
                            controller: _remarksCtrl,
                            maxLines: 3,
                            decoration:
                                _dec('Notes', Icons.note_outlined)),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 20),

            // ── Save Button ─────────────────────────────────────────────────
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _isSaving
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Row(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        const Icon(Icons.save_alt_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _gst != null
                              ? '${_isEdit ? 'Update' : 'Save'}  ·  Invoice ₹${_fmtN(_invoiceTotal)}'
                              : _isEdit ? 'Update Purchase' : 'Save Purchase',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Invoice Total (taxable + GST, rounded) — stacked to avoid overflow ──
  Widget _invoiceTotalRow() {
    final taxable = double.tryParse(_taxableCtrl.text) ?? 0;
    final gstAmt  = _gst?.totalGst ?? (taxable * 0.03);
    final total   = (taxable + gstAmt).roundToDouble();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withAlpha(30)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Taxable + GST',
                style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            const SizedBox(height: 1),
            Text('₹${_fmtN(taxable)} + ₹${_fmtN(gstAmt)}',
                style: TextStyle(fontSize: 11, color: Colors.grey[700])),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('Invoice Total',
              style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          const SizedBox(height: 1),
          Text('₹${_fmtN(total)}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                  color: AppColors.primary)),
        ]),
      ]),
    );
  }

  // ── GST Card (compact, no verbose text) ────────────────────────────────────
  Widget _gstCard(GstCalculation g) {
    final isIntra = (g.cgstAmount ?? 0) > 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.indigo.withAlpha(30)),
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
          decoration: BoxDecoration(
            color: Colors.indigo.withAlpha(8),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(children: [
            const Icon(Icons.receipt_long_outlined, size: 15, color: Colors.indigo),
            const SizedBox(width: 6),
            const Text('GST & ITC',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: Colors.indigo)),
            const Spacer(),
            _tag('HSN ${g.hsnCode}', Colors.indigo),
            const SizedBox(width: 5),
            _tag('${g.gstRate.toStringAsFixed(0)}%', Colors.blue),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(13),
          child: Column(children: [
            // Tax rows
            _r2('Taxable', '₹${_fmtN(g.baseAmount)}', Colors.grey[800]!),
            const SizedBox(height: 4),
            if (isIntra) ...[
              _r2('CGST ${g.cgstRate?.toStringAsFixed(1)}%',
                  '+₹${_fmtN(g.cgstAmount ?? 0)}', Colors.indigo),
              const SizedBox(height: 2),
              _r2('SGST ${g.sgstRate?.toStringAsFixed(1)}%',
                  '+₹${_fmtN(g.sgstAmount ?? 0)}', Colors.indigo),
            ] else
              _r2('IGST ${g.igstRate?.toStringAsFixed(1)}%',
                  '+₹${_fmtN(g.igstAmount ?? 0)}', Colors.purple),
            const Divider(height: 14),

            // Invoice Total
            Row(children: [
              const Text('Invoice Total',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(
                '₹${_fmtN(g.totalPayable.roundToDouble())}',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w900,
                    color: AppColors.primary),
              ),
            ]),
            if (g.tdsApplicable) ...[
              const SizedBox(height: 4),
              _r2('TDS ${g.tdsRate.toStringAsFixed(0)}% (194Q)',
                  '−₹${_fmtN(g.tdsAmount)}', Colors.orange),
              _r2('Net Payable', '₹${_fmtN(g.netPayable)}', Colors.grey[900]!, bold: true),
            ],
            const Divider(height: 14),

            // ITC row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(children: [
                const Icon(Icons.savings_outlined, size: 14, color: Colors.green),
                const SizedBox(width: 7),
                Text('ITC to Claim',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700],
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('₹${_fmtN(g.totalItc)}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                        color: Colors.green.shade700)),
              ]),
            ),
            const SizedBox(height: 5),
            // Effective cost line
            Row(children: [
              const SizedBox(width: 2),
              Icon(Icons.check_circle_outline, size: 12,
                  color: Colors.green.shade600),
              const SizedBox(width: 5),
              Text('Effective inventory cost: ₹${_fmtN(g.effectiveCost)}',
                  style: TextStyle(fontSize: 10, color: Colors.green.shade700)),
            ]),
          ]),
        ),
      ]),
    );
  }

  // ── Autocomplete field ────────────────────────────────────────────────────
  Widget _autocompleteField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required List<String> suggestions,
    required ValueChanged<String> onSelected,
    FormFieldValidator<String>? validator,
  }) {
    return Autocomplete<String>(
      optionsBuilder: (TextEditingValue tv) {
        if (tv.text.isEmpty) return suggestions.take(8);
        final q = tv.text.toLowerCase();
        return suggestions.where((s) => s.toLowerCase().contains(q)).take(8);
      },
      displayStringForOption: (s) => s,
      onSelected: onSelected,
      fieldViewBuilder: (ctx, fieldCtrl, focusNode, onSubmitted) {
        // Keep our controller in sync with Autocomplete's internal controller
        fieldCtrl.text = controller.text;
        fieldCtrl.addListener(() => controller.text = fieldCtrl.text);
        return TextFormField(
          controller: fieldCtrl,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          decoration: _dec(label, icon),
          validator: validator,
          onFieldSubmitted: (_) => onSubmitted(),
        );
      },
      optionsViewBuilder: (ctx, onSel, opts) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 360),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: opts.length,
                itemBuilder: (_, i) {
                  final opt = opts.elementAt(i);
                  return InkWell(
                    onTap: () => onSel(opt),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Text(opt,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Metal selector ────────────────────────────────────────────────────────
  Widget _metalSelector() {
    final opts = [
      _MO('gold',     const Color(0xFFF59E0B), Icons.diamond_outlined),
      _MO('silver',   const Color(0xFF6B7280), Icons.circle_outlined),
      _MO('platinum', const Color(0xFF3B82F6), Icons.hexagon_outlined),
      _MO('other',    Colors.teal,             Icons.category_outlined),
    ];
    return Row(
      children: opts.map((m) {
        final sel = _metalType == m.key;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _metalType = m.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: sel ? m.color.withAlpha(20) : const Color(0xFFF3F4F8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: sel ? m.color : Colors.grey.shade200,
                    width: sel ? 1.5 : 1),
              ),
              child: Column(children: [
                Icon(m.icon, size: 17,
                    color: sel ? m.color : Colors.grey[400]),
                const SizedBox(height: 3),
                Text(m.key[0].toUpperCase() + m.key.substring(1),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        color: sel ? m.color : Colors.grey[500])),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Transaction type ──────────────────────────────────────────────────────
  Widget _transactionSelector() => Row(children: [
        _txn('intra-state', 'Intra-State', 'CGST + SGST', Colors.indigo),
        const SizedBox(width: 10),
        _txn('inter-state', 'Inter-State', 'IGST only',   Colors.purple),
      ]);

  Widget _txn(String key, String title, String sub, Color color) {
    final sel = _transactionType == key;
    return Expanded(
      child: GestureDetector(
        onTap: () { setState(() => _transactionType = key); _recalcGst(); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: sel ? color.withAlpha(14) : const Color(0xFFF3F4F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: sel ? color : Colors.grey.shade200,
                width: sel ? 1.5 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 14, color: sel ? color : Colors.grey[400]),
              const SizedBox(width: 5),
              Flexible(child: Text(title,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                      color: sel ? color : Colors.grey[700]))),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: Text(sub, style: TextStyle(
                  fontSize: 10,
                  color: sel ? color.withAlpha(180) : Colors.grey[500])),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Attachment tile ───────────────────────────────────────────────────────
  Widget _attachTile(int i, Map<String, dynamic> meta) {
    final isPdf = (meta['format'] as String? ?? '') == 'pdf';
    final name  = meta['originalName'] as String? ?? 'Attachment';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: isPdf ? Colors.red.withAlpha(18) : Colors.blue.withAlpha(18),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
              size: 15, color: isPdf ? Colors.red : Colors.blue),
        ),
        const SizedBox(width: 9),
        Expanded(child: Text(name,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis)),
        GestureDetector(
          onTap: () => _removeAttachment(i),
          child: Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.close, size: 13, color: Colors.red),
          ),
        ),
      ]),
    );
  }

  Widget _uploadBtn(IconData icon, String label, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primary.withAlpha(50)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 15, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w600, color: AppColors.primary)),
          ]),
        ),
      );

  // ── Shared helpers ────────────────────────────────────────────────────────
  Widget _card(String heading, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 0),
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(4),
              blurRadius: 5, offset: const Offset(0, 1))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(heading, style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: Colors.grey[400], letterSpacing: 1.0)),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _r2(String label, String value, Color valueColor, {bool bold = false}) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        Text(value, style: TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: valueColor)),
      ]);

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: c.withAlpha(18),
            borderRadius: BorderRadius.circular(5)),
        child: Text(t, style: TextStyle(fontSize: 9,
            fontWeight: FontWeight.w800, color: c, letterSpacing: 0.3)),
      );

  InputDecoration _dec(String label, IconData icon,
      {Widget? suffix, String? errorText}) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 17),
        suffixIcon: suffix,
        errorText: errorText,
        filled: true,
        fillColor: const Color(0xFFF3F4F8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.red, width: 1.5)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.red, width: 1.5)),
      );

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context, initialDate: _invoiceDate,
        firstDate: DateTime(2000), lastDate: DateTime.now());
    if (d != null) {
      setState(() {
        _invoiceDate  = d;
        _dateCtrl.text = _fmtDate(d); // keep persistent controller in sync
      });
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  // Money amounts — always 2dp with Indian comma grouping
  String _fmtN(double v) => v
      .toStringAsFixed(2)
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{2})+(\d)(?!\d))'), (m) => '${m[1]},');
}


class _MO {
  final String key; final Color color; final IconData icon;
  const _MO(this.key, this.color, this.icon);
}
