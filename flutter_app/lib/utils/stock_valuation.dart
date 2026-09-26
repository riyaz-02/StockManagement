/// Price of a piece of stock from its weights and the Stock Setting rules. Mirror of backend/services/stockValuation.js;
/// both are tested against test/valuation_vectors.json. See the server file for the definitions.
library;

double _num(dynamic v) {
  if (v is num) return v.isFinite ? v.toDouble() : 0;
  return double.tryParse('${v ?? ''}'.trim()) ?? 0;
}

double _r2(double n) => (n * 100).roundToDouble() / 100;
double _r3(double n) => (n * 1000).roundToDouble() / 1000;

double purityPercent(String? text) {
  final t = (text ?? '').toLowerCase().replaceAll(RegExp(r'\s'), '');
  if (t.isEmpty) return 0;
  final k = RegExp(r'(\d{1,2})kt?\b').firstMatch(t) ?? RegExp(r'-(\d{1,2})k').firstMatch(t);
  if (k != null) {
    final kt = double.parse(k.group(1)!);
    return kt == 22 ? 91.6 : (kt == 24 ? 99.9 : _r2(kt / 24 * 100));
  }
  final n = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(t);
  if (n == null) return 0;
  final v = double.parse(n.group(1)!);
  return v > 100 ? _r2(v / 10) : v;
}

class StockPrice {
  StockPrice(this.m);
  final Map<String, double> m;
  double get net => m['net']!;
  double get purityPct => m['purityPct']!;
  double get fine => m['fine']!;
  double get finalFine => m['finalFine']!;
  double get custWastageWt => m['custWastageWt']!;
  double get valuationWt => m['valuationWt']!;
  double get metalValuation => m['metalValuation']!;
  double get labourTotal => m['labourTotal']!;
  double get makingTotal => m['makingTotal']!;
  double get stoneValuation => m['stoneValuation']!;
  double get hallmarkCharge => m['hallmarkCharge']!;
  double get taxable => m['taxable']!;
  double get goodsGst => m['goodsGst']!;
  double get hallmarkGst => m['hallmarkGst']!;
  double get totalGst => m['totalGst']!;
  double get finalPrice => m['finalPrice']!;
  double get makingForBilling => m['makingForBilling']!;
}

/// [i] keys: gross, less, net, purity, purityPct, wastage, custWastage, rate, labourRate, makingRate, stoneValue, pieces,
/// certification ('none' | 'hallmarked' | 'huid'), interstate. [rules] is the settings map from /api/stock-settings.
StockPrice computeStock(Map<String, dynamic> i, Map<String, dynamic> rules) {
  final add = Map<String, dynamic>.from((rules['addStock'] as Map?) ?? const {});
  final hm = Map<String, dynamic>.from((rules['hallmark'] as Map?) ?? const {'charge': 45, 'type': 'perPiece', 'cgst': 9, 'sgst': 9, 'igst': 18});
  double pos(dynamic v) => _num(v) < 0 ? 0 : _num(v);
  final gross = pos(i['gross']);
  final less = pos(i['less']);
  final hasNet = i['net'] != null && '${i['net']}'.trim().isNotEmpty;
  final net = hasNet ? pos(i['net']) : (gross - less < 0 ? 0.0 : gross - less);
  final hasP = i['purityPct'] != null && '${i['purityPct']}'.trim().isNotEmpty;
  final p = hasP ? _num(i['purityPct']) : purityPercent(i['purity'] as String?);
  final w = pos(i['wastage']);
  final fine = net * (p / 100);
  final finalFine = net * ((p + w) / 100);
  final basis = <String, double>{'finalFine': finalFine, 'fine': fine, 'net': net, 'gross': gross > 0 ? gross : net};
  double pick(String b) => basis[b] ?? net;

  final custWastageWt = pick('${add['customerWastage'] ?? 'fine'}') * (pos(i['custWastage']) / 100);
  final valuationWt = pick('${add['valuation'] ?? 'finalFine'}') + custWastageWt;
  final metal = valuationWt * pos(i['rate']);
  final labour = pick('${add['labourCharges'] ?? 'net'}') * pos(i['labourRate']);
  final making = pick('${add['makingCharges'] ?? 'net'}') * pos(i['makingRate']);
  final stones = pos(i['stoneValue']);

  final pcs = _num(i['pieces']).floor();
  final pieces = pcs < 1 ? 1 : pcs;
  final certified = i['certification'] == 'hallmarked' || i['certification'] == 'huid';
  final hallmark = certified ? ('${hm['type']}' == 'perGram' ? net * _num(hm['charge']) : pieces * _num(hm['charge'])) : 0.0;

  final taxable = metal + labour + making + stones;
  final goodsGst = taxable * 0.03;
  final hmRate = i['interstate'] == true ? _num(hm['igst']) : _num(hm['cgst']) + _num(hm['sgst']);
  final hallmarkGst = (add['hallmarkGst'] != false && hallmark > 0) ? hallmark * (hmRate / 100) : 0.0;
  final totalTaxable = taxable + hallmark;
  final totalGst = goodsGst + hallmarkGst;
  return StockPrice({
    'net': _r3(net),
    'purityPct': _r2(p),
    'fine': _r3(fine),
    'finalFine': _r3(finalFine),
    'custWastageWt': _r3(custWastageWt),
    'valuationWt': _r3(valuationWt),
    'metalValuation': _r2(metal),
    'labourTotal': _r2(labour),
    'makingTotal': _r2(making),
    'stoneValuation': _r2(stones),
    'hallmarkCharge': _r2(hallmark),
    'taxable': _r2(totalTaxable),
    'goodsGst': _r2(goodsGst),
    'hallmarkGst': _r2(hallmarkGst),
    'totalGst': _r2(totalGst),
    'finalPrice': _r2(totalTaxable + totalGst),
    'makingForBilling': _r2(labour + making),
  });
}

/// Price of a PURCHASE with the Purchase rules (mirror of computePurchase in backend/services/stockValuation.js).
Map<String, double> computePurchase(Map<String, dynamic> i, Map<String, dynamic> rules) {
  final pr = Map<String, dynamic>.from((rules['purchase'] as Map?) ?? const {});
  final hm = Map<String, dynamic>.from((rules['hallmark'] as Map?) ?? const {'charge': 45, 'type': 'perPiece', 'cgst': 9, 'sgst': 9, 'igst': 18});
  double pos(dynamic v) => _num(v) < 0 ? 0 : _num(v);
  final gross = pos(i['gross']);
  final less = pos(i['less']);
  final hasNet = i['net'] != null && '${i['net']}'.trim().isNotEmpty;
  final net = hasNet ? pos(i['net']) : (gross - less < 0 ? 0.0 : gross - less);
  final hasP = i['purityPct'] != null && '${i['purityPct']}'.trim().isNotEmpty;
  final p = hasP ? _num(i['purityPct']) : purityPercent(i['purity'] as String?);
  final fine = net * (p / 100);
  final grossW = gross > 0 ? gross : net;
  final wb = <String, double>{'fine': fine, 'net': net, 'gross': grossW}['${pr['wastage'] ?? 'net'}'] ?? net;
  final wastageWt = wb * (pos(i['wastage']) / 100);
  final finalFine = fine + wastageWt;
  final basis = <String, double>{'finalFine': finalFine, 'fine': fine, 'net': net, 'gross': grossW};
  double pick(String b) => basis[b] ?? net;
  final valuationWt = pick('${pr['finalValuation'] ?? 'net'}');
  final metal = valuationWt * pos(i['rate']);
  final labour = pick('${pr['labourCharges'] ?? 'fine'}') * pos(i['labourRate']);
  final pcs = _num(i['pieces']).floor();
  final pieces = pcs < 1 ? 1 : pcs;
  final certified = i['certification'] == 'hallmarked' || i['certification'] == 'huid';
  final hallmark = certified ? ('${hm['type']}' == 'perGram' ? net * _num(hm['charge']) : pieces * _num(hm['charge'])) : 0.0;
  return {
    'net': _r3(net),
    'purityPct': _r2(p),
    'fine': _r3(fine),
    'wastageWt': _r3(wastageWt),
    'finalFine': _r3(finalFine),
    'valuationWt': _r3(valuationWt),
    'metalValuation': _r2(metal),
    'labourTotal': _r2(labour),
    'hallmarkCharge': _r2(hallmark),
    'taxable': _r2(metal + labour + hallmark),
    'goodsTaxable': _r2(metal + labour),
    'hallmarkGst': _r2((pr['hallmarkGst'] != false && hallmark > 0) ? hallmark * ((i['interstate'] == true ? _num(hm['igst']) : _num(hm['cgst']) + _num(hm['sgst'])) / 100) : 0.0),
  };
}

/// Old metal / raw metal valuation (mirror of computeOldMetal in backend/services/stockValuation.js).
Map<String, dynamic> computeOldMetal(Map<String, dynamic> i, Map<String, dynamic> rules) {
  final om = Map<String, dynamic>.from((rules['oldMetal'] as Map?) ?? const {});
  double pos(dynamic v) => _num(v) < 0 ? 0 : _num(v);
  final gross = pos(i['gross']);
  final less = pos(i['less']);
  final hasNet = i['net'] != null && '${i['net']}'.trim().isNotEmpty;
  final net = hasNet ? pos(i['net']) : (gross - less < 0 ? 0.0 : gross - less);
  final hasP = i['purityPct'] != null && '${i['purityPct']}'.trim().isNotEmpty;
  final p = hasP ? _num(i['purityPct']) : purityPercent(i['purity'] as String?);
  final d = pos(i['deduction']);
  final fine = net * (p / 100);
  final finalFine = net * ((p - d) < 0 ? 0 : (p - d)) / 100;
  final grossW = gross > 0 ? gross : net;
  final basis = <String, double>{'finalFine': finalFine, 'fine': fine, 'net': net, 'gross': grossW};
  final b = i['kind'] == 'raw' ? '${om['rawMetalPurchaseValuation'] ?? 'net'}' : '${om['receivedValuation'] ?? 'fine'}';
  final wt = basis[b] ?? net;
  return {'net': _r3(net), 'purityPct': _r2(p), 'fine': _r3(fine), 'finalFine': _r3(finalFine), 'valuationWt': _r3(wt), 'basis': basis.containsKey(b) ? b : 'net', 'amount': _r2(wt * pos(i['rate']))};
}
