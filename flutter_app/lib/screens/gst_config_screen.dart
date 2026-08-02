import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/store_provider.dart';
import '../models/store_models.dart';
import '../utils/app_colors.dart';

/// Admin-only screen for configuring the firm's GST credentials and settings.
/// GST rates are legally fixed at 3% (Chapter 71) and shown read-only.
/// Only GSTIN, PAN, turnover category, and transaction type are editable.
class GstConfigScreen extends StatefulWidget {
  const GstConfigScreen({super.key});

  @override
  State<GstConfigScreen> createState() => _GstConfigScreenState();
}

class _GstConfigScreenState extends State<GstConfigScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firmNameCtrl = TextEditingController();
  final _gstinCtrl = TextEditingController();
  final _panCtrl = TextEditingController();

  String _turnoverCategory = 'below_1_5cr';
  String _defaultTransactionType = 'intra-state';

  // Validation states (null = not checked, true = valid, false = invalid)
  bool? _gstinValid;
  bool? _panValid;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _gstinError;
  String? _panError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firmNameCtrl.dispose();
    _gstinCtrl.dispose();
    _panCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final store = Provider.of<StoreProvider>(context, listen: false);
    await store.fetchGstConfig();
    final config = store.gstConfig;
    if (config != null && mounted) {
      _firmNameCtrl.text = config.firmName ?? '';
      _gstinCtrl.text = config.gstin ?? '';
      _panCtrl.text = config.pan ?? '';
      _turnoverCategory = config.firmTurnoverCategory;
      _defaultTransactionType = config.defaultTransactionType;
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // ── Live GSTIN validation ───────────────────────────────────────────────
  Future<void> _validateGstin(String value) async {
    if (value.trim().isEmpty) {
      setState(() { _gstinValid = null; _gstinError = null; });
      return;
    }
    final store = Provider.of<StoreProvider>(context, listen: false);
    final valid = await store.checkGstin(value.trim());
    if (mounted) {
      setState(() {
        _gstinValid = valid;
        _gstinError = (valid == true) ? null : 'Invalid GSTIN. Format: 22AAAAA0000A1Z5';
      });
    }
  }

  // ── Live PAN validation ─────────────────────────────────────────────────
  Future<void> _validatePan(String value) async {
    if (value.trim().isEmpty) {
      setState(() { _panValid = null; _panError = null; });
      return;
    }
    final store = Provider.of<StoreProvider>(context, listen: false);
    final valid = await store.checkPan(value.trim());
    if (mounted) {
      setState(() {
        _panValid = valid;
        _panError = (valid == true) ? null : 'Invalid PAN. Format: AAAAA0000A';
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_gstinValid == false || _panValid == false) {
      _showSnack('Fix validation errors before saving', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    final store = Provider.of<StoreProvider>(context, listen: false);

    final error = await store.updateGstConfig({
      if (_firmNameCtrl.text.trim().isNotEmpty) 'firmName': _firmNameCtrl.text.trim(),
      if (_gstinCtrl.text.trim().isNotEmpty) 'gstin': _gstinCtrl.text.trim().toUpperCase(),
      if (_panCtrl.text.trim().isNotEmpty) 'pan': _panCtrl.text.trim().toUpperCase(),
      'firmTurnoverCategory': _turnoverCategory,
      'defaultTransactionType': _defaultTransactionType,
    });

    if (mounted) {
      setState(() => _isSaving = false);
      if (error == null) {
        _showSnack('GST configuration saved successfully');
      } else {
        _showSnack(error, isError: true);
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('GST Configuration'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Consumer<StoreProvider>(
              builder: (context, store, _) => Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ── Legal Tax Rates (read-only) ─────────────────────
                    _buildReadOnlyCard(store.gstConfig),
                    const SizedBox(height: 20),

                    // ── Firm Details ───────────────────────────────────
                    _sectionHeader('🏢 Firm Details'),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _firmNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: _inputDec(
                          'Firm / Shop Name', Icons.store_outlined),
                    ),
                    const SizedBox(height: 12),

                    // GSTIN with live validator
                    TextFormField(
                      controller: _gstinCtrl,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 15,
                      decoration: _inputDec(
                        'GSTIN (Optional)',
                        Icons.verified_user_outlined,
                        suffixIcon: _validationIcon(_gstinValid),
                        errorText: _gstinError,
                        helperText: 'Format: 22AAAAA0000A1Z5',
                      ),
                      onChanged: (v) {
                        setState(() { _gstinValid = null; _gstinError = null; });
                        if (v.trim().length == 15) _validateGstin(v);
                      },
                    ),
                    const SizedBox(height: 12),

                    // PAN with live validator
                    TextFormField(
                      controller: _panCtrl,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 10,
                      decoration: _inputDec(
                        'PAN (Optional)',
                        Icons.credit_card_outlined,
                        suffixIcon: _validationIcon(_panValid),
                        errorText: _panError,
                        helperText: 'Format: AAAAA0000A',
                      ),
                      onChanged: (v) {
                        setState(() { _panValid = null; _panError = null; });
                        if (v.trim().length == 10) _validatePan(v);
                      },
                    ),
                    const SizedBox(height: 20),

                    // ── Turnover & HSN ─────────────────────────────────
                    _sectionHeader('📊 Turnover & HSN Code'),
                    const SizedBox(height: 8),
                    _hsnInfoBox(),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<String>(
                      value: _turnoverCategory,
                      decoration: _inputDec(
                          'Annual Turnover Category',
                          Icons.bar_chart_outlined),
                      items: const [
                        DropdownMenuItem(
                          value: 'below_1_5cr',
                          child: Text('≤ ₹1.5 Crore (HSN: 7113 — 4 digit)'),
                        ),
                        DropdownMenuItem(
                          value: 'above_1_5cr',
                          child: Text('> ₹1.5 Crore (HSN: 71131100 — 8 digit)'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _turnoverCategory = v!),
                    ),
                    const SizedBox(height: 12),

                    // Derived HSN display
                    _derivedHSNChip(),
                    const SizedBox(height: 20),

                    // ── Default Transaction Type ───────────────────────
                    _sectionHeader('🔄 Default Transaction Type'),
                    const SizedBox(height: 8),
                    _transactionTypeInfo(),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<String>(
                      value: _defaultTransactionType,
                      decoration: _inputDec(
                          'Transaction Type', Icons.swap_horiz_outlined),
                      items: const [
                        DropdownMenuItem(
                          value: 'intra-state',
                          child: Text('Intra-State → CGST 1.5% + SGST 1.5%'),
                        ),
                        DropdownMenuItem(
                          value: 'inter-state',
                          child: Text('Inter-State → IGST 3%'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _defaultTransactionType = v!),
                    ),
                    const SizedBox(height: 28),

                    // Save button
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.save_outlined),
                        label: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Save Configuration',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  // ── Read-only GST rates card ──────────────────────────────────────────
  Widget _buildReadOnlyCard(GstConfig? config) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.amber.withOpacity(0.08),
            Colors.orange.withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gavel_outlined,
                  color: Colors.amber, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Legally Fixed Tax Rates (Chapter 71)',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Read-only',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.green,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _rateTile('GST Rate', '3.0%', Colors.blue),
              const SizedBox(width: 8),
              _rateTile('CGST', '1.5%', Colors.indigo),
              const SizedBox(width: 8),
              _rateTile('SGST', '1.5%', Colors.purple),
              const SizedBox(width: 8),
              _rateTile('IGST', '3.0%', Colors.deepPurple),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _rateTile('TDS Rate', '1.0%', Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'TDS applies only when amount > ₹2,00,000\n(Section 194Q)',
                    style: TextStyle(fontSize: 10, color: Colors.orange),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rateTile(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _hsnInfoBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
      ),
      child: const Text(
        'HSN code is auto-selected based on your annual turnover:\n'
        '• ≤ ₹1.5 Cr: 4-digit HSN (7113) — optional for small taxpayers\n'
        '• > ₹1.5 Cr: 8-digit HSN (71131100) — mandatory per CBIC',
        style: TextStyle(fontSize: 11, color: Colors.blueGrey, height: 1.6),
      ),
    );
  }

  Widget _derivedHSNChip() {
    final hsn = _turnoverCategory == 'above_1_5cr' ? '71131100' : '7113';
    return Row(
      children: [
        const Text('Selected HSN Code:',
            style: TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withOpacity(0.4)),
          ),
          child: Text(
            hsn,
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                fontSize: 15,
                letterSpacing: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _transactionTypeInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.teal.withOpacity(0.2)),
      ),
      child: const Text(
        'Intra-State: Seller and buyer in the same state → CGST + SGST\n'
        'Inter-State: Seller and buyer in different states → IGST only\n'
        'This will be the default for new purchase entries (can be changed per-entry).',
        style: TextStyle(fontSize: 11, color: Colors.blueGrey, height: 1.6),
      ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 8),
            Text(text,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget? _validationIcon(bool? valid) {
    if (valid == null) return null;
    return Icon(
      valid ? Icons.check_circle_outline : Icons.cancel_outlined,
      color: valid ? Colors.green : Colors.red,
    );
  }

  InputDecoration _inputDec(
    String label,
    IconData icon, {
    Widget? suffixIcon,
    String? errorText,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      errorText: errorText,
      helperText: helperText,
      helperMaxLines: 2,
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: AppColors.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.5)),
    );
  }
}
