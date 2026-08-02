class BulkWeight {
  final String id;
  final String metalType;
  final double weightGrams;
  final String description;
  final DateTime date;
  final bool isActive;
  final DateTime updatedAt;

  const BulkWeight({
    required this.id,
    required this.metalType,
    required this.weightGrams,
    required this.description,
    required this.date,
    this.isActive = true,
    required this.updatedAt,
  });

  factory BulkWeight.fromJson(Map<String, dynamic> json) {
    return BulkWeight(
      id: json['_id'] ?? json['id'] ?? '',
      metalType: json['metalType'] ?? '',
      weightGrams: (json['weightGrams'] ?? 0).toDouble(),
      description: json['description'] ?? '',
      date: json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
      isActive: json['isActive'] != false,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : DateTime.now(),
    );
  }
}

// ─── GST Config Model ────────────────────────────────────────────────────────
class GstConfig {
  final String? id;
  final String? firmName;
  final String? gstin;
  final String? pan;
  final String? stateCode;
  final String firmTurnoverCategory;
  final String hsnCode;
  final double gstRate;
  final double cgstRate;
  final double sgstRate;
  final double igstRate;
  final double tdsRate;
  final double tdsThreshold;
  final String defaultTransactionType;

  const GstConfig({
    this.id,
    this.firmName,
    this.gstin,
    this.pan,
    this.stateCode,
    this.firmTurnoverCategory = 'below_1_5cr',
    this.hsnCode = '7113',
    this.gstRate = 3.0,
    this.cgstRate = 1.5,
    this.sgstRate = 1.5,
    this.igstRate = 3.0,
    this.tdsRate = 1.0,
    this.tdsThreshold = 200000,
    this.defaultTransactionType = 'intra-state',
  });

  factory GstConfig.fromJson(Map<String, dynamic> json) {
    return GstConfig(
      id: json['_id'] ?? json['id'],
      firmName: json['firmName'],
      gstin: json['gstin'],
      pan: json['pan'],
      stateCode: json['stateCode'],
      firmTurnoverCategory: json['firmTurnoverCategory'] ?? 'below_1_5cr',
      hsnCode: json['hsnCode'] ?? '7113',
      gstRate: (json['gstRate'] ?? 3.0).toDouble(),
      cgstRate: (json['cgstRate'] ?? 1.5).toDouble(),
      sgstRate: (json['sgstRate'] ?? 1.5).toDouble(),
      igstRate: (json['igstRate'] ?? 3.0).toDouble(),
      tdsRate: (json['tdsRate'] ?? 1.0).toDouble(),
      tdsThreshold: (json['tdsThreshold'] ?? 200000).toDouble(),
      defaultTransactionType: json['defaultTransactionType'] ?? 'intra-state',
    );
  }

  Map<String, dynamic> toJson() => {
        if (firmName != null) 'firmName': firmName,
        if (gstin != null) 'gstin': gstin,
        if (pan != null) 'pan': pan,
        'firmTurnoverCategory': firmTurnoverCategory,
        'defaultTransactionType': defaultTransactionType,
      };
}

// ─── GST Calculation Result ──────────────────────────────────────────────────
class GstCalculation {
  final double baseAmount;
  final double gstRate;
  final double? cgstRate;
  final double? cgstAmount;
  final double? sgstRate;
  final double? sgstAmount;
  final double? igstRate;
  final double? igstAmount;
  final double totalGst;
  final double totalWithGst;
  final double totalPayable;  // = totalWithGst (base + GST)
  // ITC fields — what the buyer can claim back from GST credit ledger
  final double itcCgst;
  final double itcSgst;
  final double itcIgst;
  final double totalItc;       // Total ITC claimable
  final double effectiveCost;  // Real inventory cost = baseAmount (after ITC)
  // TDS
  final bool tdsApplicable;
  final double tdsRate;
  final double tdsAmount;
  final double netPayable;     // Cash outflow after TDS deduction
  final String hsnCode;
  final String formattedNetPayable;
  final String netPayableInWords;

  const GstCalculation({
    required this.baseAmount,
    required this.gstRate,
    this.cgstRate,
    this.cgstAmount,
    this.sgstRate,
    this.sgstAmount,
    this.igstRate,
    this.igstAmount,
    required this.totalGst,
    required this.totalWithGst,
    this.totalPayable = 0,
    this.itcCgst = 0,
    this.itcSgst = 0,
    this.itcIgst = 0,
    this.totalItc = 0,
    this.effectiveCost = 0,
    required this.tdsApplicable,
    required this.tdsRate,
    required this.tdsAmount,
    required this.netPayable,
    required this.hsnCode,
    required this.formattedNetPayable,
    required this.netPayableInWords,
  });

  factory GstCalculation.fromJson(Map<String, dynamic> json) {
    final cgst = json['cgst'] as Map<String, dynamic>?;
    final sgst = json['sgst'] as Map<String, dynamic>?;
    final igst = json['igst'] as Map<String, dynamic>?;
    final base = (json['baseAmount'] ?? 0).toDouble();
    final totalGst = (json['totalGst'] ?? 0).toDouble();

    return GstCalculation(
      baseAmount: base,
      gstRate: (json['gstRate'] ?? 3.0).toDouble(),
      cgstRate: cgst != null ? (cgst['rate'] ?? 0).toDouble() : null,
      cgstAmount: cgst != null ? (cgst['amount'] ?? 0).toDouble() : null,
      sgstRate: sgst != null ? (sgst['rate'] ?? 0).toDouble() : null,
      sgstAmount: sgst != null ? (sgst['amount'] ?? 0).toDouble() : null,
      igstRate: igst != null ? (igst['rate'] ?? 0).toDouble() : null,
      igstAmount: igst != null ? (igst['amount'] ?? 0).toDouble() : null,
      totalGst: totalGst,
      totalWithGst: (json['totalWithGst'] ?? base + totalGst).toDouble(),
      totalPayable: (json['totalPayable'] ?? json['totalWithGst'] ?? 0).toDouble(),
      itcCgst: (json['itcCgst'] ?? 0).toDouble(),
      itcSgst: (json['itcSgst'] ?? 0).toDouble(),
      itcIgst: (json['itcIgst'] ?? 0).toDouble(),
      totalItc: (json['totalItc'] ?? 0).toDouble(),
      effectiveCost: (json['effectiveCost'] ?? base).toDouble(),
      tdsApplicable: json['tdsApplicable'] == true,
      tdsRate: (json['tdsRate'] ?? 1.0).toDouble(),
      tdsAmount: (json['tdsAmount'] ?? 0).toDouble(),
      netPayable: (json['netPayable'] ?? 0).toDouble(),
      hsnCode: json['hsnCode'] ?? '7113',
      formattedNetPayable: json['formattedNetPayable'] ?? '',
      netPayableInWords: json['netPayableInWords'] ?? '',
    );
  }
}
