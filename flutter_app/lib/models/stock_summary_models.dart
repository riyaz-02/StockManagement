/// Models for the Stock Summary (metal balance and difference), its history and the wastage reports.
/// The server works every number out (services/stockSummary.js); these only read its answer.

double _d(dynamic v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);
int _i(dynamic v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);
String _s(dynamic v) => v == null ? '' : '$v';

/// A text in English and Bengali; [of] picks by the app language ('bn' or 'en').
class LText {
  final String en;
  final String bn;
  const LText(this.en, this.bn);
  factory LText.from(dynamic j) {
    if (j is Map) return LText(_s(j['en']), _s(j['bn']));
    return LText(_s(j), _s(j));
  }
  String of(String lang) => lang == 'bn' && bn.isNotEmpty ? bn : en;
}

class MetalBalance {
  final String metal; // gold | silver
  final double purchased, allowancePct, allowance, adjustedPurchase, oldMetal, rawMetal, receiptsTotal;
  final double inShop, withOthers, bulk, stockTotal;
  final double soldGross, returned, sold, wastage;
  final double expectedOut, variance, variancePct;
  final String severity; // normal | moderate | high
  final String direction; // short | excess | balanced
  final int piecesInShop, piecesWithOthers, piecesRemoved, bulkEntries;

  const MetalBalance({
    required this.metal, this.purchased = 0, this.allowancePct = 0, this.allowance = 0, this.adjustedPurchase = 0,
    this.oldMetal = 0, this.rawMetal = 0, this.receiptsTotal = 0, this.inShop = 0, this.withOthers = 0, this.bulk = 0,
    this.stockTotal = 0, this.soldGross = 0, this.returned = 0, this.sold = 0, this.wastage = 0, this.expectedOut = 0,
    this.variance = 0, this.variancePct = 0, this.severity = 'normal', this.direction = 'balanced',
    this.piecesInShop = 0, this.piecesWithOthers = 0, this.piecesRemoved = 0, this.bulkEntries = 0,
  });

  factory MetalBalance.fromJson(String metal, Map<String, dynamic> j) {
    final r = Map<String, dynamic>.from(j['receipts'] as Map? ?? {});
    final s = Map<String, dynamic>.from(j['stock'] as Map? ?? {});
    final o = Map<String, dynamic>.from(j['out'] as Map? ?? {});
    final p = Map<String, dynamic>.from(j['pieces'] as Map? ?? {});
    return MetalBalance(
      metal: metal,
      purchased: _d(r['purchased']), allowancePct: _d(r['allowancePct']), allowance: _d(r['allowance']),
      adjustedPurchase: _d(r['adjustedPurchase']), oldMetal: _d(r['oldMetal']), rawMetal: _d(r['rawMetal']), receiptsTotal: _d(r['total']),
      inShop: _d(s['inShop']), withOthers: _d(s['withOthers']), bulk: _d(s['bulk']), stockTotal: _d(s['total']),
      soldGross: _d(o['soldGross']), returned: _d(o['returned']), sold: _d(o['sold']), wastage: _d(o['wastage']),
      expectedOut: _d(j['expectedOut']), variance: _d(j['variance']), variancePct: _d(j['variancePct']),
      severity: _s(j['severity']).isEmpty ? 'normal' : _s(j['severity']),
      direction: _s(j['direction']).isEmpty ? 'balanced' : _s(j['direction']),
      piecesInShop: _i(p['inShop']), piecesWithOthers: _i(p['withOthers']), piecesRemoved: _i(p['removed']), bulkEntries: _i(j['bulkEntries']),
    );
  }
}

class SummaryCheck {
  final String id, level; // error | warn | info
  final int count;
  final double? grams;
  final LText text;
  const SummaryCheck(this.id, this.level, this.count, this.grams, this.text);
  factory SummaryCheck.fromJson(Map<String, dynamic> j) =>
      SummaryCheck(_s(j['id']), _s(j['level']), _i(j['count']), j['grams'] == null ? null : _d(j['grams']), LText(_s(j['en']), _s(j['bn'])));
}

class MetalInsight {
  final String severity;
  final LText headline;
  final List<LText> analysis;
  final List<LText> recommendations;
  const MetalInsight(this.severity, this.headline, this.analysis, this.recommendations);
  factory MetalInsight.fromJson(Map<String, dynamic> j) => MetalInsight(
        _s(j['severity']), LText.from(j['headline']),
        (j['analysis'] as List? ?? []).map(LText.from).toList(),
        (j['recommendations'] as List? ?? []).map(LText.from).toList(),
      );
}

class Movement {
  final String at, type, direction, metal, title, note;
  final double grams;
  const Movement(this.at, this.type, this.direction, this.metal, this.grams, this.title, this.note);
  factory Movement.fromJson(Map<String, dynamic> j) =>
      Movement(_s(j['at']), _s(j['type']), _s(j['direction']), _s(j['metal']), _d(j['grams']), _s(j['title']), _s(j['note']));
}

class StockSummary {
  final DateTime? asOf;
  final bool wholeFirm;
  final MetalBalance gold, silver;
  final List<SummaryCheck> checks;
  final String confidenceLevel; // reliable | check | fix
  final LText confidenceText;
  final MetalInsight goldInsight, silverInsight;
  final List<Movement> movements;
  final bool savedToday;
  final String snapshotBy;
  final double okPct, highPct, minAlertGrams;

  const StockSummary({
    required this.asOf, required this.wholeFirm, required this.gold, required this.silver, required this.checks,
    required this.confidenceLevel, required this.confidenceText, required this.goldInsight, required this.silverInsight,
    required this.movements, required this.savedToday, required this.snapshotBy, required this.okPct, required this.highPct, required this.minAlertGrams,
  });

  bool get anyAlert => gold.severity != 'normal' || silver.severity != 'normal';

  factory StockSummary.fromJson(Map<String, dynamic> j) {
    final metals = Map<String, dynamic>.from(j['metals'] as Map? ?? {});
    final ins = Map<String, dynamic>.from(j['insights'] as Map? ?? {});
    final conf = Map<String, dynamic>.from(j['confidence'] as Map? ?? {});
    final snap = Map<String, dynamic>.from(j['snapshot'] as Map? ?? {});
    final snapInfo = Map<String, dynamic>.from(snap['todayInfo'] as Map? ?? {});
    final set = Map<String, dynamic>.from(j['settings'] as Map? ?? {});
    MetalBalance mb(String m) => MetalBalance.fromJson(m, Map<String, dynamic>.from(metals[m] as Map? ?? {}));
    MetalInsight mi(String m) => MetalInsight.fromJson(Map<String, dynamic>.from(ins[m] as Map? ?? {}));
    return StockSummary(
      asOf: DateTime.tryParse(_s(j['asOf']))?.toLocal(),
      wholeFirm: (j['scope'] as Map?)?['wholeFirm'] != false,
      gold: mb('gold'), silver: mb('silver'),
      checks: (j['checks'] as List? ?? []).map((e) => SummaryCheck.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      confidenceLevel: _s(conf['level']).isEmpty ? 'reliable' : _s(conf['level']),
      confidenceText: LText(_s(conf['en']), _s(conf['bn'])),
      goldInsight: mi('gold'), silverInsight: mi('silver'),
      movements: (j['movements'] as List? ?? []).map((e) => Movement.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      savedToday: snap['savedToday'] == true, snapshotBy: _s(snapInfo['by']),
      okPct: _d(set['okPct']), highPct: _d(set['highPct']), minAlertGrams: _d(set['minAlertGrams']),
    );
  }
}

class HistoryMetal {
  final double stock, variance, variancePct;
  final double? inG, outG;
  final String severity;
  const HistoryMetal(this.stock, this.inG, this.outG, this.variance, this.variancePct, this.severity);
  factory HistoryMetal.fromJson(Map<String, dynamic> j) => HistoryMetal(
        _d(j['stock']), j['in'] == null ? null : _d(j['in']), j['out'] == null ? null : _d(j['out']), _d(j['variance']), _d(j['variancePct']), _s(j['severity']));
}

class HistoryRow {
  final String label, date, basis;
  final int snapshots;
  final bool methodChange;
  final HistoryMetal gold, silver;
  const HistoryRow(this.label, this.date, this.basis, this.snapshots, this.methodChange, this.gold, this.silver);
  factory HistoryRow.fromJson(Map<String, dynamic> j) => HistoryRow(
        _s(j['label']), _s(j['date']), _s(j['basis']), _i(j['snapshots']), j['methodChange'] == true,
        HistoryMetal.fromJson(Map<String, dynamic>.from(j['gold'] as Map? ?? {})),
        HistoryMetal.fromJson(Map<String, dynamic>.from(j['silver'] as Map? ?? {})),
      );
}

class StockHistory {
  final List<HistoryRow> rows; // newest first
  final bool enough, comparable;
  final Map<String, dynamic> trend;
  const StockHistory(this.rows, this.enough, this.comparable, this.trend);
  factory StockHistory.fromJson(Map<String, dynamic> j) {
    final t = Map<String, dynamic>.from(j['trend'] as Map? ?? {});
    return StockHistory(
      (j['rows'] as List? ?? []).map((e) => HistoryRow.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      t['enough'] == true, t['comparable'] == true, t,
    );
  }
}

class WastageReport {
  final String id, date, metal, category, reason, remarks, status, reportedBy, reportedById, approvedBy, comment, attachmentName;
  final double amount;
  final DateTime? createdAt, approvedAt;
  const WastageReport({
    required this.id, required this.date, required this.metal, required this.amount, required this.category, required this.reason,
    required this.remarks, required this.status, required this.reportedBy, required this.reportedById, required this.approvedBy,
    required this.comment, required this.attachmentName, required this.createdAt, required this.approvedAt,
  });
  factory WastageReport.fromJson(Map<String, dynamic> j) {
    final rb = Map<String, dynamic>.from(j['reportedBy'] as Map? ?? {});
    final ab = j['approvedBy'] is Map ? Map<String, dynamic>.from(j['approvedBy'] as Map) : <String, dynamic>{};
    final att = j['attachment'] is Map ? Map<String, dynamic>.from(j['attachment'] as Map) : <String, dynamic>{};
    return WastageReport(
      id: _s(j['_id']), date: _s(j['date']), metal: _s(j['metal']), amount: _d(j['amount']), category: _s(j['category']),
      reason: _s(j['reason']), remarks: _s(j['remarks']), status: _s(j['status']).isEmpty ? 'pending' : _s(j['status']),
      reportedBy: _s(rb['name']), reportedById: _s(rb['id']), approvedBy: _s(ab['name']), comment: _s(j['comment']),
      attachmentName: _s(att['name']), createdAt: DateTime.tryParse(_s(j['createdAt']))?.toLocal(), approvedAt: DateTime.tryParse(_s(j['approvedAt']))?.toLocal(),
    );
  }
}
