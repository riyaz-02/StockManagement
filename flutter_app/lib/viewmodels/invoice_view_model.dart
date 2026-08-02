import 'package:flutter/foundation.dart';

// ─────────────────────────────── Data classes ────────────────────────────────

enum InvoiceStatus { pending, active, delivered }

enum PaymentMode { cash, card, online, cheque }

class InvoiceItem {
  String particulars;
  String hsnCode;
  String metalType; // 'gold' | 'silver' | 'other'
  double netWeight;
  double makingCharge;
  double taxableAmount;   // = (netWt × rate) + makingCharge  [or override]
  bool taxableOverridden;
  // rowTotal = taxableAmount only (no GST per-row).
  // GST is applied at invoice level on NET taxable (after discount).
  double rowTotal;

  InvoiceItem({
    this.particulars      = '',
    this.hsnCode          = '7113',
    this.metalType        = 'gold',
    this.netWeight        = 0,
    this.makingCharge     = 0,
    this.taxableAmount    = 0,
    this.taxableOverridden = false,
    this.rowTotal         = 0,
  });

  Map<String, dynamic> toJson() => {
    'particulars':       particulars,
    'hsnCode':           hsnCode,
    'metalType':         metalType,
    'netWeight':         netWeight,
    'makingCharge':      makingCharge,
    'taxableAmount':     taxableAmount,
    'taxableOverridden': taxableOverridden,
  };
}

// ─────────────────────────────── ViewModel ───────────────────────────────────

/// All calculation logic for the GST Invoice screen.
///
/// ══════════════════════════════════════════════════════════════════
/// CORRECT GST MATH (Section 15 CGST Act):
///
///   Per-row taxable  = (netWeight × rate) + makingCharge
///   ─────────────────────────────────────────────────────
///   grossTaxable     = Σ taxableAmount  (all rows)
///   +additionalCharges (also taxable under GST)
///   −discount        ← reduces the TAXABLE BASE, not the post-GST total
///   ─────────────────────────────────────────────────────
///   netTaxable       = grossTaxable + additionalCharges − discount
///   CGST             = netTaxable × 1.5%
///   SGST             = netTaxable × 1.5%   [or IGST = 3% for inter-state]
///   payableBeforeRound = netTaxable + CGST + SGST
///   roundOff         = Math.round(payable) − payable  [always ±₹0.50]
///   totalPayable     = Math.round(payableBeforeRound)
///
/// WRONG (what we had before — DO NOT DO THIS):
///   payable = (taxable + GST) − discount   ← gives GST on discount amount
/// ══════════════════════════════════════════════════════════════════
///
/// ROUND-OFF RULE: always within ±₹0.50 (standard Math.round).
class InvoiceViewModel extends ChangeNotifier {
  // ── Invoice meta ──────────────────────────────────────────────────────────
  DateTime invoiceDate    = DateTime.now();
  DateTime? deliveryDate;
  String transactionType  = 'intra-state';
  bool reverseCharge      = false;
  String termsOfDelivery  = 'Customer Pickup';
  String placeOfSupply    = 'West Bengal';
  String invoiceNumber    = '';

  // ── Global rates ─────────────────────────────────────────────────────────
  double goldRate   = 0;
  double silverRate = 0;

  // ── Customer ─────────────────────────────────────────────────────────────
  String customerName    = '';
  String customerMobile  = '';
  String customerAddress = '';
  String customerPan     = '';

  // ── Items ─────────────────────────────────────────────────────────────────
  List<InvoiceItem> items = [InvoiceItem()];

  // ── Footer ────────────────────────────────────────────────────────────────
  double additionalCharges     = 0;
  double discount              = 0;
  bool   totalPayableOverridden = false;
  double _manualTotalPayable    = 0;

  // ── Payment ───────────────────────────────────────────────────────────────
  double      paidAmount  = 0;
  PaymentMode paymentMode = PaymentMode.cash;

  // ── Notes ─────────────────────────────────────────────────────────────────
  String notes = '';

  // ── Computed totals (read-only, all derived) ──────────────────────────────

  /// Sum of all item taxable amounts (before GST, before discount).
  double grossTaxable       = 0;

  /// grossTaxable + additionalCharges − discount  [GST base].
  double netTaxable         = 0;

  /// CGST on netTaxable (intra-state only).
  double totalCgst          = 0;

  /// SGST on netTaxable (intra-state only).
  double totalSgst          = 0;

  /// IGST on netTaxable (inter-state only).
  double totalIgst          = 0;

  /// netTaxable + totalCgst + totalSgst + totalIgst  (before rounding).
  double payableBeforeRound = 0;

  /// Math.round correction — always |roundOff| ≤ ₹0.50.
  double roundOff           = 0;

  /// Final invoice amount (= Math.round(payableBeforeRound), unless overridden).
  double totalPayable       = 0;

  bool   tdsApplicable      = false;
  double tdsAmount          = 0;
  double netPayableAfterTds = 0;

  /// paidAmount − totalPayable.  Negative → customer owes; positive → advance.
  double dueAmount          = 0;

  // ── Status ────────────────────────────────────────────────────────────────

  InvoiceStatus get status {
    final today = DateTime.now();
    final del   = deliveryDate;
    if (del == null || del.isAfter(today)) return InvoiceStatus.pending;
    if (dueAmount.abs() < 0.01)            return InvoiceStatus.delivered;
    return InvoiceStatus.active;
  }

  bool get tdsCardVisible => tdsApplicable;

  // ── Add / Remove items ────────────────────────────────────────────────────

  void addItem() {
    items.add(InvoiceItem(
      hsnCode:   items.isNotEmpty ? items.last.hsnCode : '7113',
      metalType: items.isNotEmpty ? items.last.metalType : 'gold',
    ));
    notifyListeners();
  }

  void removeItem(int index) {
    if (items.length <= 1) return;
    items.removeAt(index);
    recalcAll();
  }

  // ── Item field setters ────────────────────────────────────────────────────

  void setParticulars(int i, String v)  { items[i].particulars  = v; notifyListeners(); }
  void setHsnCode(int i, String v)      { items[i].hsnCode      = v; notifyListeners(); }
  void setMetalType(int i, String v)    { items[i].metalType    = v; recalcItem(i); }
  void setNetWeight(int i, double v)    {
    items[i].netWeight          = v;
    items[i].taxableOverridden  = false;
    recalcItem(i);
  }
  void setMakingCharge(int i, double v) {
    items[i].makingCharge       = v;
    items[i].taxableOverridden  = false;
    recalcItem(i);
  }

  /// Double-tap override on the taxable field.
  void overrideTaxable(int i, double v) {
    items[i].taxableAmount     = v;
    items[i].taxableOverridden = true;
    recalcItem(i);
  }

  void clearTaxableOverride(int i) {
    items[i].taxableOverridden = false;
    recalcItem(i);
  }

  // ── Global rate setters ───────────────────────────────────────────────────

  void setGoldRate(double v) {
    goldRate = v;
    for (int i = 0; i < items.length; i++) {
      if (!items[i].taxableOverridden && items[i].metalType != 'silver') {
        recalcItem(i, notify: false);
      }
    }
    recalcTotals();
  }

  void setSilverRate(double v) {
    silverRate = v;
    for (int i = 0; i < items.length; i++) {
      if (!items[i].taxableOverridden && items[i].metalType == 'silver') {
        recalcItem(i, notify: false);
      }
    }
    recalcTotals();
  }

  // ── Footer setters ────────────────────────────────────────────────────────

  void setAdditionalCharges(double v) {
    additionalCharges = v;
    totalPayableOverridden = false;
    recalcTotals();
  }

  void setDiscount(double v) {
    discount = v;
    totalPayableOverridden = false;
    recalcTotals();
  }

  /// Updates place of supply and auto-determines transaction type:
  /// - West Bengal (seller's state) → intra-state (CGST + SGST)
  /// - Any other state              → inter-state  (IGST)
  void setPlaceOfSupply(String state) {
    placeOfSupply    = state;
    transactionType  = (state == 'West Bengal') ? 'intra-state' : 'inter-state';
    recalcAll();
  }

  void overrideTotalPayable(double v) {
    totalPayableOverridden = true;
    _manualTotalPayable    = v;
    totalPayable           = v;
    _afterTotalPayable();
    notifyListeners();
  }

  void clearTotalOverride() {
    totalPayableOverridden = false;
    recalcTotals();
  }

  void setPaidAmount(double v) {
    paidAmount = v;
    dueAmount  = _dp(v - totalPayable);
    notifyListeners();
  }

  void setPaymentMode(PaymentMode m) { paymentMode = m; notifyListeners(); }

  // ── Round-off helper ──────────────────────────────────────────────────────
  /// One-tap: adjusts discount so netTaxable shifts slightly and
  /// totalPayable lands on an exact rupee integer.
  /// The adjustment is always < ₹1, and since it changes the TAXABLE base,
  /// GST is also adjusted correctly (no compliance issue).
  void applyRoundOff() {
    if (roundOff.abs() < 0.001) return;
    // roundOff > 0 → we rounded up → payable is already integer, nothing to do
    // roundOff < 0 → we rounded down → payableBeforeRound had a fraction
    //
    // We adjust discount by subtracting roundOff from the taxable side.
    // equivalently: decrease discount by roundOff (negative roundOff → discount increases)
    // so netTaxable decreases, bringing payable exactly to the integer.
    discount = _dp(discount - roundOff);
    totalPayableOverridden = false;
    recalcTotals();
  }

  // ── Core calculation engine ───────────────────────────────────────────────

  /// Compute a single item's taxable value. NO per-row GST.
  /// GST is applied at the invoice level in recalcTotals().
  void recalcItem(int i, {bool notify = true}) {
    final item = items[i];
    final rate = item.metalType == 'silver' ? silverRate : goldRate;

    if (!item.taxableOverridden) {
      item.taxableAmount = _dp(item.netWeight * rate + item.makingCharge);
    }
    // rowTotal = just the taxable portion (informational; GST computed at footer)
    item.rowTotal = item.taxableAmount;

    recalcTotals(notify: notify);
  }

  void recalcAll() {
    for (int i = 0; i < items.length; i++) {
      recalcItem(i, notify: false);
    }
    recalcTotals();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Grand total — correct GST flow
  // ══════════════════════════════════════════════════════════════════════════
  void recalcTotals({bool notify = true}) {
    // Step 1: gross taxable = Σ item taxable amounts (no GST yet)
    grossTaxable = _dp(items.fold(0.0, (s, it) => s + it.taxableAmount));

    // Step 2: net taxable = gross + additional − discount
    //         Discount reduces the TAXABLE BASE (correct GST treatment).
    final net = grossTaxable + additionalCharges - discount;
    netTaxable = _dp(net < 0 ? 0 : net);  // floor at 0

    // Step 3: compute GST on net taxable
    final isInter = transactionType == 'inter-state';
    if (isInter) {
      totalCgst = 0;
      totalSgst = 0;
      totalIgst = _dp(netTaxable * 0.03);
    } else {
      totalCgst = _dp(netTaxable * 0.015);
      totalSgst = _dp(netTaxable * 0.015);
      totalIgst = 0;
    }
    final totalGst = totalCgst + totalSgst + totalIgst;

    // Step 4: payable before round-off
    final rawPayable = netTaxable + totalGst;
    payableBeforeRound = _dp(rawPayable);

    // Step 5: round-off (Math.round → always ±₹0.50 max)
    final rounded = rawPayable.roundToDouble();
    roundOff = _dp(rounded - rawPayable);

    // Step 6: final payable
    if (!totalPayableOverridden) {
      totalPayable = rounded;
    } else {
      totalPayable = _manualTotalPayable;
    }

    _afterTotalPayable();
    if (notify) notifyListeners();
  }

  void _afterTotalPayable() {
    // TDS engine (Section 194Q)
    if (totalPayable > 200000) {
      tdsApplicable      = true;
      tdsAmount          = _dp(totalPayable * 0.01);
      netPayableAfterTds = _dp(totalPayable - tdsAmount);
    } else {
      tdsApplicable      = false;
      tdsAmount          = 0;
      netPayableAfterTds = totalPayable;
    }

    // Due / Advance
    dueAmount = _dp(paidAmount - totalPayable);
  }

  // ── Amount in words ───────────────────────────────────────────────────────

  String get totalInWords => _amountToWords(totalPayable.truncate());

  // ── Helper: 2 decimal places ──────────────────────────────────────────────

  static double _dp(double v) => double.parse(v.toStringAsFixed(2));

  // ── Amount in words (Indian system) ──────────────────────────────────────

  static const _ones = [
    '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
    'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
    'Seventeen', 'Eighteen', 'Nineteen',
  ];
  static const _tens = [
    '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty',
    'Sixty', 'Seventy', 'Eighty', 'Ninety',
  ];

  static String _twoDigits(int n) {
    if (n < 20) return _ones[n];
    return '${_tens[n ~/ 10]}${n % 10 > 0 ? ' ${_ones[n % 10]}' : ''}';
  }

  static String _threeDigits(int n) {
    if (n == 0) return '';
    if (n < 100) return _twoDigits(n);
    return '${_ones[n ~/ 100]} Hundred ${_twoDigits(n % 100)}'.trim();
  }

  static String _amountToWords(int n) {
    if (n == 0) return 'Zero Rupees Only';
    final crore = n ~/ 10000000;
    n %= 10000000;
    final lakh  = n ~/ 100000;
    n %= 100000;
    final thou  = n ~/ 1000;
    n %= 1000;
    final rest  = n;

    final buf = StringBuffer();
    if (crore > 0) buf.write('${_threeDigits(crore)} Crore ');
    if (lakh  > 0) buf.write('${_twoDigits(lakh)} Lakh ');
    if (thou  > 0) buf.write('${_twoDigits(thou)} Thousand ');
    if (rest  > 0) buf.write(_threeDigits(rest));

    return '${buf.toString().trim()} Rupees Only';
  }

  // ── API payload ───────────────────────────────────────────────────────────

  Map<String, dynamic> toApiPayload() => {
    'invoiceNumber':          invoiceNumber,
    'invoiceDate':            invoiceDate.toIso8601String(),
    if (deliveryDate != null)
      'deliveryDate':         deliveryDate!.toIso8601String(),
    'transactionType':        transactionType,
    'reverseCharge':          reverseCharge,
    'termsOfDelivery':        termsOfDelivery,
    'placeOfSupply':          placeOfSupply,
    'goldRate':               goldRate,
    'silverRate':             silverRate,
    'customerName':           customerName,
    'customerMobile':         customerMobile,
    'customerAddress':        customerAddress,
    'customerPan':            customerPan,
    'items':                  items.map((it) => it.toJson()).toList(),
    'additionalCharges':      additionalCharges,
    'discount':               discount,
    'totalPayableOverridden': totalPayableOverridden,
    if (totalPayableOverridden) 'totalPayable': totalPayable,
    'paidAmount':             paidAmount,
    'paymentMode':            paymentMode.name,
    'notes':                  notes,
  };
}
