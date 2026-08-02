/// Mirrors the actual MongoDB purchase document structure.
/// Fields intentionally match the legacy PHP schema field names.
class Purchase {
  // ── Core fields (match legacy DB document) ───────────────────────────────
  final String id;
  final DateTime invoiceDate;
  final String invoiceNumber;
  final String metalType;        // gold | silver | platinum | other
  final String biller;           // Supplier/biller firm name
  final String billerGstin;      // Supplier GSTIN (for ITC claim validity)
  final String description;      // e.g. "Fine Silver" — from legacy field
  final double quantity;         // Weight in grams
  final double rate;             // ₹ per gram
  final double totalAmount;      // Taxable value (as per supplier invoice)

  // ── B2B GST fields ───────────────────────────────────────────────────────
  final String transactionType;  // 'intra-state' | 'inter-state'
  final String hsnCode;
  final double gstRate;          // Total GST % (3.0 for precious metals)
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double totalGst;
  final double totalPayable;     // totalAmount + totalGst (paid to supplier)

  // ── ITC (Input Tax Credit) ────────────────────────────────────────────────
  // In B2B, buyer reclaims GST paid from the government credit ledger.
  final double itcCgst;          // Claim from CGST electronic credit ledger
  final double itcSgst;          // Claim from SGST electronic credit ledger
  final double itcIgst;          // Claim from IGST electronic credit ledger
  final double totalItc;         // Total ITC = itcCgst + itcSgst + itcIgst
  final double effectiveCost;    // Real cost = totalAmount (GST recovered via ITC)

  // ── TDS (194Q) ────────────────────────────────────────────────────────────
  final bool tdsApplicable;
  final double tdsRate;
  final double tdsAmount;
  final double netPayable;       // Cash outflow = totalPayable - tdsAmount

  // ── Attachments ───────────────────────────────────────────────────────────
  final List<String> attachments;
  final List<Map<String, dynamic>> attachmentMeta;

  // ── Other ─────────────────────────────────────────────────────────────────
  final String remarks;
  final String? invoiceDateIST;
  final String? createdAtIST;
  final String createdByName;
  final DateTime createdAt;

  const Purchase({
    required this.id,
    required this.invoiceDate,
    required this.invoiceNumber,
    required this.metalType,
    required this.biller,
    this.billerGstin = '',
    this.description = '',
    required this.quantity,
    required this.rate,
    required this.totalAmount,
    this.transactionType = 'intra-state',
    this.hsnCode = '7113',
    this.gstRate = 3.0,
    this.cgstAmount = 0,
    this.sgstAmount = 0,
    this.igstAmount = 0,
    this.totalGst = 0,
    this.totalPayable = 0,
    this.itcCgst = 0,
    this.itcSgst = 0,
    this.itcIgst = 0,
    this.totalItc = 0,
    this.effectiveCost = 0,
    this.tdsApplicable = false,
    this.tdsRate = 1.0,
    this.tdsAmount = 0,
    required this.netPayable,
    this.attachments = const [],
    this.attachmentMeta = const [],
    this.remarks = '',
    this.invoiceDateIST,
    this.createdAtIST,
    this.createdByName = '',
    required this.createdAt,
  });

  factory Purchase.fromJson(Map<String, dynamic> json) {
    final totalAmount = (json['totalAmount'] ?? json['total_amount'] ?? 0).toDouble();
    return Purchase(
      id: json['_id'] ?? json['id'] ?? '',
      invoiceDate: json['invoiceDate'] != null
          ? DateTime.parse(json['invoiceDate'])
          : DateTime.now(),
      invoiceNumber: json['invoiceNumber'] ?? json['invoice_number'] ?? '',
      metalType: (json['metalType'] ?? json['metal_type'] ?? '').toLowerCase(),
      biller: json['biller'] ?? '',
      billerGstin: json['billerGstin'] ?? '',
      description: json['description'] ?? '',
      quantity: (json['quantity'] ?? 0).toDouble(),
      rate: (json['rate'] ?? 0).toDouble(),
      totalAmount: totalAmount,
      transactionType: json['transactionType'] ?? 'intra-state',
      hsnCode: json['hsnCode'] ?? '7113',
      gstRate: (json['gstRate'] ?? 3.0).toDouble(),
      cgstAmount: (json['cgstAmount'] ?? 0).toDouble(),
      sgstAmount: (json['sgstAmount'] ?? 0).toDouble(),
      igstAmount: (json['igstAmount'] ?? 0).toDouble(),
      totalGst: (json['totalGst'] ?? 0).toDouble(),
      totalPayable: (json['totalPayable'] ?? 0).toDouble(),
      itcCgst: (json['itcCgst'] ?? 0).toDouble(),
      itcSgst: (json['itcSgst'] ?? 0).toDouble(),
      itcIgst: (json['itcIgst'] ?? 0).toDouble(),
      totalItc: (json['totalItc'] ?? 0).toDouble(),
      effectiveCost: (json['effectiveCost'] ?? totalAmount).toDouble(),
      tdsApplicable: json['tdsApplicable'] == true,
      tdsRate: (json['tdsRate'] ?? 1.0).toDouble(),
      tdsAmount: (json['tdsAmount'] ?? 0).toDouble(),
      netPayable: (json['netPayable'] ?? 0).toDouble(),
      attachments: List<String>.from(json['attachments'] ?? []),
      attachmentMeta: (json['attachmentMeta'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      remarks: json['remarks'] ?? '',
      invoiceDateIST: json['invoiceDateIST'] ?? json['invoice_date'],
      createdAtIST: json['createdAtIST'] ?? json['created_ist'],
      createdByName: json['createdByName'] ?? json['created_by_name'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'invoiceDate': invoiceDate.toIso8601String(),
        'invoiceNumber': invoiceNumber,
        'metalType': metalType,
        'biller': biller,
        'billerGstin': billerGstin,
        'description': description,
        'quantity': quantity,
        'rate': rate,
        'totalAmount': totalAmount,
        'transactionType': transactionType,
        'remarks': remarks,
        'attachmentMeta': attachmentMeta,
      };

  /// Formatted invoice date as DD/MM/YYYY
  String get invoiceDateFormatted {
    if (invoiceDateIST != null && invoiceDateIST!.contains('-')) {
      // Legacy format: "2021-03-23" → convert to DD/MM/YYYY
      final parts = invoiceDateIST!.split('-');
      if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
    }
    return '${invoiceDate.day.toString().padLeft(2, '0')}/'
        '${invoiceDate.month.toString().padLeft(2, '0')}/'
        '${invoiceDate.year}';
  }
}
