import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../viewmodels/invoice_view_model.dart';
import '../providers/store_provider.dart';
import '../utils/app_colors.dart';
import '../utils/app_toast.dart';

// ── Per-item text controllers (stored at State level — never recreated) ────────
class _ItemFields {
  final TextEditingController particulars = TextEditingController();
  final TextEditingController netWeight = TextEditingController();
  final TextEditingController makingCharge = TextEditingController();

  void dispose() {
    particulars.dispose();
    netWeight.dispose();
    makingCharge.dispose();
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// GST Sales Invoice
/// Designed for NON-TECHNICAL shop staff.
/// Simple, step-by-step, large tap targets.
/// ─────────────────────────────────────────────────────────────────────────────
class InvoiceScreen extends StatefulWidget {
  const InvoiceScreen({super.key});

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  late final InvoiceViewModel _vm;
  bool _isSaving = false;

  // ── Stable controllers (never recreated) ─────────────────────────────────
  final _custNameCtrl = TextEditingController();
  final _custMobileCtrl = TextEditingController();
  final _custAddressCtrl = TextEditingController();
  final _custPanCtrl = TextEditingController();
  final _goldRateCtrl = TextEditingController();
  final _silverRateCtrl = TextEditingController();
  final _addlCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _paidCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // ── Per-item controllers — grown/shrunk with items list ──────────────────
  final List<_ItemFields> _itemFields = [_ItemFields()];

  @override
  void initState() {
    super.initState();
    _vm = InvoiceViewModel();
    _fetchNextNumber();
  }

  Future<void> _fetchNextNumber() async {
    final store = Provider.of<StoreProvider>(context, listen: false);
    final num = await store.getNextInvoiceNumber();
    if (mounted && num != null) setState(() => _vm.invoiceNumber = num);
  }

  @override
  void dispose() {
    _custNameCtrl.dispose();
    _custMobileCtrl.dispose();
    _custAddressCtrl.dispose();
    _custPanCtrl.dispose();
    _goldRateCtrl.dispose();
    _silverRateCtrl.dispose();
    _addlCtrl.dispose();
    _discountCtrl.dispose();
    _paidCtrl.dispose();
    _notesCtrl.dispose();
    for (final f in _itemFields) f.dispose();
    _vm.dispose();
    super.dispose();
  }

  // ── Add / Remove item ────────────────────────────────────────────────────

  void _addItem() {
    _itemFields.add(_ItemFields());
    _vm.addItem();
    setState(() {});
  }

  void _removeItem(int i) {
    if (_itemFields.length <= 1) return;
    _itemFields[i].dispose();
    _itemFields.removeAt(i);
    _vm.removeItem(i);
    setState(() {});
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_vm.customerName.trim().isEmpty) {
      _snack('Please enter customer name', error: true);
      return;
    }
    if (_vm.tdsApplicable && _vm.customerPan.isEmpty) {
      _snack('Customer PAN is required (bill > ₹2,00,000)', error: true);
      return;
    }
    setState(() => _isSaving = true);
    final err = await Provider.of<StoreProvider>(context, listen: false)
        .createInvoice(_vm.toApiPayload());
    if (mounted) {
      setState(() => _isSaving = false);
      if (err == null) {
        _snack('Invoice saved ✓');
        Navigator.pop(context, true);
      } else {
        _snack(err, error: true);
      }
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _rupee(double v) {
    final s = v.toStringAsFixed(2);
    // Indian comma format: 1,23,456.78
    final parts = s.split('.');
    final whole = parts[0];
    final decimal = parts[1];
    if (whole.length <= 3) return '₹$whole.$decimal';
    final last3 = whole.substring(whole.length - 3);
    final rest = whole.substring(0, whole.length - 3);
    final fmt = rest.replaceAllMapped(
        RegExp(r'(\d)(?=(\d{2})+(?!\d))'), (m) => '${m[1]},');
    return '₹$fmt,$last3.$decimal';
  }

  String _fmt(double v, {int dp = 2}) => v.toStringAsFixed(dp);

  void _snack(String msg, {bool error = false}) {
    showAppSnackBar(
        context,
        SnackBar(
          content:
              Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
          backgroundColor: error ? Colors.red[700] : Colors.green[700],
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        ));
  }

  // ── Tap → select all for numeric fields ─────────────────────────────────
  void _sel(TextEditingController c) {
    c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
  }

  // ── Standard text field ───────────────────────────────────────────────────
  Widget _field(
    String label,
    TextEditingController ctrl, {
    TextInputType kb = TextInputType.text,
    int maxLines = 1,
    int? maxLen,
    String? hint,
    Widget? prefix,
    bool caps = false,
    bool numbersOnly = false,
    ValueChanged<String>? onChange,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: kb,
      maxLines: maxLines,
      maxLength: maxLen,
      textCapitalization:
          caps ? TextCapitalization.words : TextCapitalization.none,
      inputFormatters: numbersOnly
          ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))]
          : null,
      onTap: numbersOnly ? () => _sel(ctrl) : null,
      onChanged: onChange,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefix,
        filled: true,
        fillColor: Colors.grey[50],
        counterText: '',
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E3EA))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E3EA))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primary, width: 1.8)),
        labelStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
      ),
    );
  }

  // ── Section heading ───────────────────────────────────────────────────────
  Widget _section(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(18),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A1A))),
      ]),
    );
  }

  // ── White card ───────────────────────────────────────────────────────────
  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(5),
                blurRadius: 10,
                offset: const Offset(0, 2))
          ],
        ),
        child: child,
      );

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<InvoiceViewModel>.value(
      value: _vm,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F2F8),
        appBar: _buildAppBar(),
        body: Consumer<InvoiceViewModel>(
          builder: (_, vm, __) => ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
            children: [
              _sellerBanner(),
              _step1Customer(vm),
              _step2Rates(vm),
              _step3Items(vm),
              _step4Totals(vm),
              _step5Payment(vm),
            ],
          ),
        ),
        bottomNavigationBar:
            Consumer<InvoiceViewModel>(builder: (_, vm, __) => _bottomBar(vm)),
      ),
    );
  }

  // ── App bar ───────────────────────────────────────────────────────────────
  AppBar _buildAppBar() => AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        centerTitle: false,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('New GST Invoice',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          Text(
            _vm.invoiceNumber.isEmpty
                ? 'Generating number…'
                : _vm.invoiceNumber,
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 16),
              label: const Text('SAVE',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      );

  // ── Seller banner ─────────────────────────────────────────────────────────
  Widget _sellerBanner() {
    final cfg = Provider.of<StoreProvider>(context, listen: false).gstConfig;
    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withAlpha(20),
              borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.store_rounded,
              color: Color(0xFFF59E0B), size: 26),
        ),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(cfg?.firmName ?? 'Laltu Guinea Palace',
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          Text('GSTIN: ${cfg?.gstin ?? '19AKFPN3465R1ZB'}  •  West Bengal',
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ])),
        // Date chip
        GestureDetector(
          onTap: () => _pickDate(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withAlpha(40))),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('Invoice Date',
                      style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                  Text(DateFormat('dd MMM yyyy').format(_vm.invoiceDate),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                ]),
          ),
        ),
      ]),
    );
  }

  Future<void> _pickDate({bool delivery = false}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: delivery ? (_vm.deliveryDate ?? now) : _vm.invoiceDate,
      firstDate: DateTime(2020),
      lastDate: delivery ? DateTime(2030) : now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (delivery)
        _vm.deliveryDate = picked;
      else
        _vm.invoiceDate = picked;
    });
    _vm.recalcTotals();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 1 — Customer
  // ─────────────────────────────────────────────────────────────────────────
  Widget _step1Customer(InvoiceViewModel vm) {
    return _card(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Customer Details', Icons.person_outline_rounded),

        _field(
          'Customer Name *',
          _custNameCtrl,
          hint: 'e.g. Ramesh Kumar',
          caps: true,
          onChange: (v) => vm.customerName = v,
        ),
        const SizedBox(height: 10),

        Row(children: [
          Expanded(
              child: _field(
            'Mobile Number',
            _custMobileCtrl,
            kb: TextInputType.phone,
            maxLen: 10,
            hint: '10-digit',
            prefix: const Icon(Icons.phone_outlined, size: 18),
            onChange: (v) => vm.customerMobile = v,
          )),
          const SizedBox(width: 10),
          Expanded(
              child: _field(
            'Address',
            _custAddressCtrl,
            hint: 'City / Area',
            onChange: (v) => vm.customerAddress = v,
          )),
        ]),

        // TDS warning — only shows when bill > ₹2L
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: vm.tdsCardVisible
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withAlpha(15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.withAlpha(60)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.orange, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                            child: Text(
                          'Bill exceeds ₹2,00,000 — TDS (1%) applies.\n'
                          'Customer PAN number is required.',
                          style:
                              TextStyle(fontSize: 12, color: Colors.deepOrange),
                        )),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    _field(
                      'Customer PAN Number *',
                      _custPanCtrl,
                      maxLen: 10,
                      hint: 'e.g. ABCDE1234F',
                      onChange: (v) => vm.customerPan = v.toUpperCase(),
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.info_outline,
                          size: 13, color: Colors.orange),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(
                        'TDS: ${_rupee(vm.tdsAmount)}  •  '
                        'Net payable after TDS: ${_rupee(vm.netPayableAfterTds)}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange),
                      )),
                    ]),
                  ]),
                )
              : const SizedBox.shrink(),
        ),
      ],
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 2 — Rates (Gold / Silver)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _step2Rates(InvoiceViewModel vm) {
    return _card(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section("Today's Rates  (₹ per gram)", Icons.show_chart_rounded),
        Row(children: [
          Expanded(
              child: _rateBox(
            emoji: '🥇',
            label: 'Gold Rate',
            ctrl: _goldRateCtrl,
            color: const Color(0xFFF59E0B),
            onChanged: (v) => vm.setGoldRate(double.tryParse(v) ?? 0),
          )),
          const SizedBox(width: 12),
          Expanded(
              child: _rateBox(
            emoji: '🥈',
            label: 'Silver Rate',
            ctrl: _silverRateCtrl,
            color: Colors.blueGrey,
            onChanged: (v) => vm.setSilverRate(double.tryParse(v) ?? 0),
          )),
        ]),
        const SizedBox(height: 12),
        // ── Place of Supply → auto-determines transaction type ─────────────
        DropdownButtonFormField<String>(
          value: vm.placeOfSupply,
          decoration: InputDecoration(
            labelText: 'Place of Supply (Customer State)',
            prefixIcon: const Icon(Icons.location_on_outlined, size: 18),
            filled: true,
            fillColor: Colors.grey[50],
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E3EA))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E3EA))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          items: [
            'West Bengal',
            'Delhi',
            'Maharashtra',
            'Uttar Pradesh',
            'Rajasthan',
            'Gujarat',
            'Karnataka',
            'Tamil Nadu',
            'Madhya Pradesh',
            'Bihar',
            'Other State',
          ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: (v) => vm.setPlaceOfSupply(v!),
        ),
        const SizedBox(height: 10),
        // Auto-determined GST type badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: vm.transactionType == 'intra-state'
                ? Colors.indigo.withAlpha(10)
                : Colors.deepPurple.withAlpha(10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: vm.transactionType == 'intra-state'
                  ? Colors.indigo.withAlpha(50)
                  : Colors.deepPurple.withAlpha(50),
            ),
          ),
          child: Row(children: [
            Icon(
              vm.transactionType == 'intra-state'
                  ? Icons.home_work_outlined
                  : Icons.flight_takeoff_outlined,
              size: 18,
              color: vm.transactionType == 'intra-state'
                  ? Colors.indigo
                  : Colors.deepPurple,
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                    vm.transactionType == 'intra-state'
                        ? 'Same State Transaction'
                        : 'Other State Transaction',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: vm.transactionType == 'intra-state'
                          ? Colors.indigo
                          : Colors.deepPurple,
                    ),
                  ),
                  Text(
                    vm.transactionType == 'intra-state'
                        ? 'CGST 1.5% + SGST 1.5% will apply'
                        : 'IGST 3% will apply',
                    style: TextStyle(
                      fontSize: 11,
                      color: vm.transactionType == 'intra-state'
                          ? Colors.indigo[300]
                          : Colors.deepPurple[300],
                    ),
                  ),
                ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: vm.transactionType == 'intra-state'
                    ? Colors.indigo
                    : Colors.deepPurple,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                vm.transactionType == 'intra-state' ? 'CGST+SGST' : 'IGST',
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white),
              ),
            ),
          ]),
        ),
      ],
    ));
  }

  Widget _rateBox({
    required String emoji,
    required String label,
    required TextEditingController ctrl,
    required Color color,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ]),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
          ],
          onTap: () => _sel(ctrl),
          onChanged: onChanged,
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w800, color: color),
          decoration: const InputDecoration(
            hintText: '0.00',
            prefixText: '₹ ',
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 3 — Items
  // ─────────────────────────────────────────────────────────────────────────
  Widget _step3Items(InvoiceViewModel vm) {
    return _card(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Items Sold', Icons.diamond_outlined),
        ...List.generate(vm.items.length, (i) => _itemCard(vm, i)),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _addItem,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Add Another Item'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withAlpha(80)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    ));
  }

  Widget _itemCard(InvoiceViewModel vm, int i) {
    final item = vm.items[i];
    final f = _itemFields[i];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E3EA)),
      ),
      child: Column(children: [
        // ── Item header ────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primary.withAlpha(10),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle),
              child: Text('${i + 1}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
            const SizedBox(width: 10),
            const Text('Item Details',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const Spacer(),
            if (vm.items.length > 1)
              GestureDetector(
                onTap: () => _removeItem(i),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(children: [
                    Icon(Icons.delete_outline, color: Colors.red, size: 14),
                    SizedBox(width: 4),
                    Text('Remove',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.red,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            // ── Metal type selector ─────────────────────────────────────────
            Row(children: [
              const Text('Metal Type:',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(width: 10),
              _metalChip(vm, i, 'gold', '🥇 Gold'),
              const SizedBox(width: 8),
              _metalChip(vm, i, 'silver', '🥈 Silver'),
              const SizedBox(width: 8),
              _metalChip(vm, i, 'other', 'Other'),
            ]),
            const SizedBox(height: 12),

            // ── Particulars ─────────────────────────────────────────────────
            TextFormField(
              controller: f.particulars,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Description / Particulars',
                hintText: 'e.g. Gold Bangle, Chain, Ring…',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE0E3EA))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE0E3EA))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: AppColors.primary, width: 1.5)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onChanged: (v) => vm.setParticulars(i, v),
            ),
            const SizedBox(height: 10),

            // ── Weight + Making charge ──────────────────────────────────────
            Row(children: [
              Expanded(
                  child: _numericInput(
                label: 'Weight (grams)',
                hint: '0.000',
                ctrl: f.netWeight,
                suffix: 'g',
                onChange: (v) {
                  final d = double.tryParse(v) ?? 0;
                  item.taxableOverridden = false;
                  vm.setNetWeight(i, d);
                },
              )),
              const SizedBox(width: 10),
              Expanded(
                  child: _numericInput(
                label: 'Making Charge',
                hint: '0.00',
                ctrl: f.makingCharge,
                suffix: '₹',
                onChange: (v) => vm.setMakingCharge(i, double.tryParse(v) ?? 0),
              )),
            ]),
            const SizedBox(height: 10),

            // ── Taxable value display ───────────────────────────────────────
            _taxableDisplay(vm, i, item),
          ]),
        ),
      ]),
    );
  }

  Widget _numericInput({
    required String label,
    required String hint,
    required TextEditingController ctrl,
    required String suffix,
    required ValueChanged<String> onChange,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
      onTap: () => _sel(ctrl),
      onChanged: onChange,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffix,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE0E3EA))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE0E3EA))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
      ),
    );
  }

  Widget _metalChip(InvoiceViewModel vm, int i, String type, String label) {
    final sel = vm.items[i].metalType == type;
    return GestureDetector(
      onTap: () {
        vm.setMetalType(i, type);
        setState(() {});
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: sel ? AppColors.primary : Colors.grey.shade300,
              width: sel ? 0 : 1),
          boxShadow: sel
              ? [
                  BoxShadow(
                      color: AppColors.primary.withAlpha(30), blurRadius: 6)
                ]
              : null,
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: sel ? Colors.white : Colors.grey[600])),
      ),
    );
  }

  Widget _taxableDisplay(InvoiceViewModel vm, int i, InvoiceItem item) {
    return GestureDetector(
      onDoubleTap: () => _taxableOverrideDialog(vm, i, item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: item.taxableOverridden
              ? Colors.amber.withAlpha(15)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                item.taxableOverridden ? Colors.amber : const Color(0xFFE0E3EA),
            width: item.taxableOverridden ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Taxable Amount (Weight × Rate + Making)',
                style: TextStyle(fontSize: 9, color: Colors.grey[500])),
            const SizedBox(height: 2),
            Text(_rupee(item.taxableAmount),
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
          const Spacer(),
          Column(children: [
            if (item.taxableOverridden)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Overridden',
                    style: TextStyle(
                        fontSize: 9,
                        color: Colors.amber,
                        fontWeight: FontWeight.w700)),
              )
            else
              Text('Double-tap\nto change',
                  style: TextStyle(fontSize: 9, color: Colors.grey[400]),
                  textAlign: TextAlign.center),
          ]),
        ]),
      ),
    );
  }

  void _taxableOverrideDialog(InvoiceViewModel vm, int i, InvoiceItem item) {
    final ctrl = TextEditingController(
        text: item.taxableAmount > 0 ? _fmt(item.taxableAmount) : '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Change Taxable Amount',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Enter exact taxable amount as per bill.\n'
              'GST will be recalculated on this value.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Amount ₹',
              prefixText: '₹ ',
              border: OutlineInputBorder(),
            ),
            onTap: () => ctrl.selection =
                TextSelection(baseOffset: 0, extentOffset: ctrl.text.length),
          ),
        ]),
        actions: [
          if (item.taxableOverridden)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                vm.clearTaxableOverride(i);
                setState(() {});
              },
              child: const Text('Reset to Auto',
                  style: TextStyle(color: Colors.grey)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text) ?? 0;
              Navigator.pop(context);
              vm.overrideTaxable(i, v);
              setState(() {});
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 4 — Totals
  // ─────────────────────────────────────────────────────────────────────────
  Widget _step4Totals(InvoiceViewModel vm) {
    final isInter = vm.transactionType == 'inter-state';
    return _card(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Bill Summary', Icons.receipt_long_outlined),

        // Gross taxable
        _summaryRow('Total Item Value', _rupee(vm.grossTaxable)),
        if (vm.additionalCharges > 0)
          _summaryRow('+ Additional Charges', _rupee(vm.additionalCharges),
              color: Colors.teal),

        const SizedBox(height: 10),
        // Additional charges input
        _numericInput(
          label: 'Additional Charges (if any)',
          hint: '0.00',
          ctrl: _addlCtrl,
          suffix: '₹',
          onChange: (v) => vm.setAdditionalCharges(double.tryParse(v) ?? 0),
        ),
        const SizedBox(height: 10),

        // Discount input — clearly labelled
        TextFormField(
          controller: _discountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
          ],
          onTap: () => _sel(_discountCtrl),
          onChanged: (v) {
            vm.setDiscount(double.tryParse(v) ?? 0);
            if (!vm.totalPayableOverridden)
              _paidCtrl.text = _fmt(vm.totalPayable);
          },
          decoration: InputDecoration(
            labelText: 'Discount on Making Charge',
            hintText: 'Reduces taxable amount (before GST)',
            suffixText: '₹',
            prefixIcon: const Icon(Icons.remove_circle_outline,
                color: Colors.redAccent, size: 18),
            filled: true,
            fillColor: Colors.red.withAlpha(5),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE0E3EA))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.red.withAlpha(60))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: Colors.redAccent, width: 1.5)),
          ),
        ),
        if (vm.discount > 0) ...[
          const SizedBox(height: 4),
          _summaryRow('− Discount', _rupee(vm.discount), color: Colors.red),
        ],

        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 8),

        // Net taxable box
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.indigo.withAlpha(8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.indigo.withAlpha(40)),
          ),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Taxable Value (GST is on this)',
                  style: TextStyle(fontSize: 10, color: Colors.indigo[600])),
              const SizedBox(height: 2),
              Text(_rupee(vm.netTaxable),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.indigo[800])),
            ]),
            const Spacer(),
            Text('Gross − Discount',
                style: TextStyle(fontSize: 9, color: Colors.indigo[300])),
          ]),
        ),
        const SizedBox(height: 10),

        // GST lines
        if (isInter)
          _summaryRow('IGST @3%', _rupee(vm.totalIgst),
              color: Colors.deepPurple)
        else ...[
          _summaryRow('CGST @1.5%', _rupee(vm.totalCgst), color: Colors.indigo),
          _summaryRow('SGST @1.5%', _rupee(vm.totalSgst), color: Colors.purple),
        ],

        // Round-off helper
        if (vm.roundOff.abs() > 0.001) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              vm.applyRoundOff();
              _discountCtrl.text = _fmt(vm.discount);
              _paidCtrl.text = _fmt(vm.totalPayable);
              setState(() {});
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.teal.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.teal.withAlpha(50)),
              ),
              child: Row(children: [
                const Icon(Icons.touch_app_outlined,
                    color: Colors.teal, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('Tap to make round figure',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.teal)),
                      Text(
                          'Round-off: ${vm.roundOff >= 0 ? '+' : ''}${_fmt(vm.roundOff)}',
                          style:
                              TextStyle(fontSize: 10, color: Colors.teal[300])),
                    ])),
                Text('→ ${_rupee(vm.totalPayable.roundToDouble())}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.teal)),
              ]),
            ),
          ),
        ],

        const SizedBox(height: 12),
        const Divider(),

        // Grand total
        GestureDetector(
          onDoubleTap: () => _totalOverrideDialog(vm),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                AppColors.primary.withAlpha(20),
                AppColors.primary.withAlpha(8),
              ]),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: vm.totalPayableOverridden
                    ? Colors.amber
                    : AppColors.primary.withAlpha(50),
                width: vm.totalPayableOverridden ? 2 : 1,
              ),
            ),
            child: Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('TOTAL PAYABLE',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: Colors.grey)),
                    Text(vm.totalInWords,
                        style: const TextStyle(
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey)),
                    if (vm.totalPayableOverridden)
                      const Text('⚠ Manually overridden',
                          style: TextStyle(fontSize: 9, color: Colors.amber)),
                  ])),
              Text(_rupee(vm.totalPayable),
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary)),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        Center(
            child: Text('Double-tap to manually change total',
                style: TextStyle(fontSize: 10, color: Colors.grey[400]))),
      ],
    ));
  }

  Widget _summaryRow(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: color ?? Colors.grey[600])),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color ?? const Color(0xFF1A1A1A))),
        ]),
      );

  void _totalOverrideDialog(InvoiceViewModel vm) {
    final ctrl = TextEditingController(text: _fmt(vm.totalPayable));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Change Total Payable',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('After this, auto-calculation is paused.',
              style: TextStyle(fontSize: 12, color: Colors.orange)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Total Payable ₹',
              prefixText: '₹ ',
              border: OutlineInputBorder(),
            ),
            onTap: () => ctrl.selection =
                TextSelection(baseOffset: 0, extentOffset: ctrl.text.length),
          ),
        ]),
        actions: [
          if (vm.totalPayableOverridden)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                vm.clearTotalOverride();
                _paidCtrl.text = _fmt(vm.totalPayable);
                setState(() {});
              },
              child: const Text('Reset Auto',
                  style: TextStyle(color: Colors.grey)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text) ?? 0;
              Navigator.pop(context);
              vm.overrideTotalPayable(v);
              _paidCtrl.text = _fmt(v);
              setState(() {});
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 5 — Payment
  // ─────────────────────────────────────────────────────────────────────────
  Widget _step5Payment(InvoiceViewModel vm) {
    final due = vm.dueAmount;
    final isDue = due < -0.01;
    final isAdvance = due > 0.01;
    final badgeColor = isDue
        ? Colors.red
        : isAdvance
            ? Colors.green
            : Colors.teal;
    final badgeLabel = isDue
        ? 'Amount Due from Customer'
        : isAdvance
            ? 'Advance Paid'
            : 'Fully Settled ✓';

    return _card(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Payment', Icons.payments_outlined),

        // Amount paid
        _numericInput(
          label: 'Amount Received from Customer',
          hint: _fmt(vm.totalPayable),
          ctrl: _paidCtrl,
          suffix: '₹',
          onChange: (v) {
            vm.setPaidAmount(double.tryParse(v) ?? 0);
            setState(() {});
          },
        ),
        const SizedBox(height: 12),

        // Due / Advance badge
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: badgeColor.withAlpha(12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: badgeColor.withAlpha(60)),
          ),
          child: Row(children: [
            Icon(
                isDue
                    ? Icons.warning_amber_rounded
                    : isAdvance
                        ? Icons.check_circle_outline
                        : Icons.check_circle_outline,
                color: badgeColor,
                size: 22),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(badgeLabel,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: badgeColor)),
              if (due.abs() > 0.01)
                Text(_rupee(due.abs()),
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: badgeColor)),
            ]),
          ]),
        ),
        const SizedBox(height: 14),

        // Payment mode
        const Text('How did the customer pay?',
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PaymentMode.values.map((m) {
              final sel = vm.paymentMode == m;
              return GestureDetector(
                onTap: () {
                  vm.setPaymentMode(m);
                  setState(() {});
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: sel ? AppColors.primary : Colors.grey.shade300),
                    boxShadow: sel
                        ? [
                            BoxShadow(
                                color: AppColors.primary.withAlpha(30),
                                blurRadius: 6)
                          ]
                        : null,
                  ),
                  child: Text(_pmLabel(m),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: sel ? Colors.white : Colors.grey[600])),
                ),
              );
            }).toList()),
        const SizedBox(height: 14),

        // Notes
        TextFormField(
          controller: _notesCtrl,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (v) => vm.notes = v,
          decoration: InputDecoration(
            labelText: 'Remarks / Notes (Optional)',
            hintText: 'Any special note about this bill…',
            filled: true,
            fillColor: Colors.grey[50],
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE0E3EA))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE0E3EA))),
          ),
        ),
      ],
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Bottom status bar
  // ─────────────────────────────────────────────────────────────────────────
  Widget _bottomBar(InvoiceViewModel vm) {
    final s = vm.status;
    final sl = s == InvoiceStatus.pending
        ? 'Pending'
        : s == InvoiceStatus.active
            ? 'Active'
            : 'Delivered';
    final sc = s == InvoiceStatus.pending
        ? Colors.amber
        : s == InvoiceStatus.active
            ? Colors.blue
            : Colors.green;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 10,
              offset: const Offset(0, -2))
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(children: [
          // Status pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: sc.withAlpha(15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sc.withAlpha(60)),
            ),
            child: Text(sl,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: sc, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Text(_rupee(vm.totalPayable),
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const Spacer(),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 28),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save Invoice',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ),
          ),
        ]),
      ),
    );
  }

  String _pmLabel(PaymentMode m) {
    switch (m) {
      case PaymentMode.cash:
        return '💵 Cash';
      case PaymentMode.card:
        return '💳 Card';
      case PaymentMode.online:
        return '📱 Online';
      case PaymentMode.cheque:
        return '📄 Cheque';
    }
  }
}
