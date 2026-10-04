/// Live GST maths for the billing screens: a Dart port of
/// `backend/services/billingCalc.js` ("lgpmanagement-v1", the live website's
/// rules). It only drives the on-screen preview; the SERVER recomputes
/// everything from the raw inputs when the invoice is saved, and both are
/// tested against the same vectors (see test/billing_calc_test.dart).
///
///   line:    taxable = netWt x rate + making + stones/other metals (or a typed amount)
///            same state: CGST = SGST = 1.5%   |   another state: IGST 3%
///   discount (rule v2): taken off BEFORE GST, from the making charge (or the amount above
///            metal + stones + hallmark on a typed taxable line); never from the metal itself
///   extra charges: taxed like the goods (s.15(2)(c)), at 3% (or IGST 3%)
///   invoice: total_amount = sum(line totals) + additional + GST on it
///            payable = round(sum(line totals) + additional) to the RUPEE
///   payment: due = payable - paid | advance = paid - payable
///   TDS:     1% when payable is above Rs 2,00,000 (customer PAN required)
library;

/// A stone, diamond, pearl or another metal set into a piece.
class BillExtra {
  BillExtra({this.kind = 'Stone', this.name = '', this.weight = 0, this.amount = 0});
  String kind; // Stone | Diamond | Pearl | Metal | Other
  String name;
  double weight; // grams
  double amount; // value, added to the taxable amount

  BillExtra copy() => BillExtra(kind: kind, name: name, weight: weight, amount: amount);
  Map<String, dynamic> toJson() => {'kind': kind, 'name': name, 'weight': weight, 'amount': amount};
  bool get isEmpty => name.trim().isEmpty && weight == 0 && amount == 0;
}

class BillItem {
  BillItem({
    this.particular = '',
    this.metal = 'Gold',
    this.purity = '',
    this.grossWt = 0,
    this.netWt = 0,
    this.rate = 0,
    this.making = 0,
    this.hsn = '7113',
    this.taxableOverride,
    this.productCode = '',
    this.huid = '',
    this.certification = '',
    this.hallmarkCharge = 0,
    this.itemId = '',
    List<BillExtra>? extras,
  }) : extras = extras ?? [];

  String particular;
  String metal; // 'Gold' | 'Silver' | 'Other'
  String purity; // 22K, 18K, 92.5 ...
  double grossWt; // 0 = not entered
  double netWt;
  double rate; // 0 = use the metal rate
  double making;
  String hsn;
  double? taxableOverride; // typed taxable amount (negotiated price); null = calculate
  String productCode; // barcode of the stock item, if scanned
  String huid;
  String certification; // '' | 'hallmark' | 'huid'
  double hallmarkCharge; // the centre's fee, already taxed: passed on after GST (never taxed again); only used when certified
  String itemId; // stock item id, if scanned
  List<BillExtra> extras;

  /// Rebuilds a line from what [toJson] sent (used to make an invoice from an estimate).
  factory BillItem.fromJson(Map<String, dynamic> j) {
    double d(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
    return BillItem(
      particular: '${j['particulars'] ?? ''}',
      metal: '${j['metalType'] ?? 'Gold'}',
      purity: '${j['purity'] ?? ''}',
      grossWt: d(j['grossWt']),
      netWt: d(j['netWt']),
      rate: d(j['rate']),
      making: d(j['makingCharge']),
      hsn: '${j['hsnCode'] ?? '7113'}',
      taxableOverride: j['taxableOverride'] == null ? null : d(j['taxableOverride']),
      productCode: '${j['productCode'] ?? ''}',
      huid: '${j['huid'] ?? ''}',
      certification: '${j['certification'] ?? ''}',
      hallmarkCharge: d(j['hallmarkCharge']),
      itemId: '${j['itemId'] ?? ''}',
      extras: [for (final e in (j['extras'] as List? ?? const [])) BillExtra(kind: '${(e as Map)['kind'] ?? 'Stone'}', name: '${e['name'] ?? ''}', weight: d(e['weight']), amount: d(e['amount']))],
    );
  }

  double get extrasWeight => BillingCalc.r3(extras.fold<double>(0, (a, e) => a + e.weight));
  double get extrasAmount => BillingCalc.r2(extras.fold<double>(0, (a, e) => a + e.amount));

  /// Everything added to the taxable amount besides weight x rate + making: the stones. (The hallmark fee already carries
  /// its GST, so it is NOT taxable: it is added after the tax, rule v3.)
  double get preTaxExtras => extrasAmount;

  /// How the item is printed on the invoice: "Ring", "Ring (Hallmarked)" or "Ring (HUID: AB12CD)".
  String get displayName {
    final n = particular.trim();
    final h = huid.trim().toUpperCase();
    if (certification == 'huid' && h.isNotEmpty) return '$n (HUID: $h)';
    if (certification.isNotEmpty) return '$n (Hallmarked)';
    return n;
  }

  static final RegExp huidPattern = RegExp(r'^[A-Z0-9]{6}$');

  BillItem copy() => BillItem(
        particular: particular,
        metal: metal,
        purity: purity,
        grossWt: grossWt,
        netWt: netWt,
        rate: rate,
        making: making,
        hsn: hsn,
        taxableOverride: taxableOverride,
        productCode: productCode,
        huid: huid,
        certification: certification,
        hallmarkCharge: hallmarkCharge,
        itemId: itemId,
        extras: extras.map((e) => e.copy()).toList(),
      );

  /// What the server expects for one line.
  Map<String, dynamic> toJson() => {
        'particulars': particular.trim(),
        'hsnCode': hsn,
        'metalType': metal,
        if (purity.isNotEmpty) 'purity': purity,
        if (grossWt > 0) 'grossWt': grossWt,
        'netWt': netWt,
        'rate': rate,
        'makingCharge': making,
        if (taxableOverride != null) 'taxableOverride': taxableOverride,
        if (productCode.isNotEmpty) 'productCode': productCode,
        if (certification.isNotEmpty) 'certification': certification,
        if (certification.isNotEmpty && hallmarkCharge > 0) 'hallmarkCharge': hallmarkCharge,
        if (certification == 'huid' && huid.isNotEmpty) 'huid': huid.trim().toUpperCase(),
        if (itemId.isNotEmpty) 'itemId': itemId,
        if (extras.any((e) => !e.isEmpty)) 'extras': extras.where((e) => !e.isEmpty).map((e) => e.toJson()).toList(),
      };
}

class BillLine {
  BillLine({
    required this.rate,
    required this.taxable,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.total,
    required this.autoTaxable,
    required this.making,
    required this.discount,
    required this.name,
    required this.hiddenMaking,
    required this.metalValue,
    this.hallmark = 0,
  });
  final double rate, taxable, cgst, sgst, igst, total;
  final double hallmark; // hallmark / HUID fee inside `total` but outside `taxable` (no GST on it)
  final double autoTaxable; // the CALCULATED taxable amount (weight x rate + making + stones), ignoring any typed amount (the hallmark fee is not part of it)
  final double making; // making charge left after the discount (0 for a typed taxable amount)
  final double discount; // part of the discount taken off this line (before GST)
  final String name; // as printed on the invoice, e.g. "Ring (HUID: AB12CD) + Making Charge"
  final bool hiddenMaking; // typed taxable amount that contains a making charge
  final double metalValue; // net weight x rate: the floor no discount may touch
}

class BillTotals {
  BillTotals({
    required this.lines,
    required this.totalAmount,
    required this.additional,
    required this.discount,
    required this.payable,
    required this.roundOff,
    required this.paid,
    required this.due,
    required this.advance,
    required this.taxableSum,
    required this.cgstSum,
    required this.sgstSum,
    required this.igstSum,
    required this.tdsApplicable,
    required this.tdsAmount,
    required this.interstate,
    required this.grossTaxable,
    required this.discountBeforeGst,
    required this.billBeforeDiscount,
    required this.maxDiscount,
    required this.metalValue,
    required this.additionalGst,
    this.hallmarkTotal = 0,
    this.discountError,
  });
  final List<BillLine> lines;
  final double totalAmount, additional, payable, roundOff, paid, due, advance;

  /// What the customer actually saves (bill before discount - payable).
  final double discount;
  final double taxableSum, cgstSum, sgstSum, igstSum, tdsAmount;
  final bool tdsApplicable, interstate;

  /// Goods value before the discount (pre-tax), and the part of the discount taken off it.
  final double grossTaxable, discountBeforeGst;

  /// What the customer would pay with no discount.
  final double billBeforeDiscount;

  /// The most that can be taken off what the customer pays without touching metal, stones or hallmark.
  final double maxDiscount;
  final double metalValue;

  /// GST charged on the extra charges (they are taxed like the goods).
  final double additionalGst;

  /// Hallmark / HUID fees passed on: inside the total, outside the taxable value (no GST on them).
  final double hallmarkTotal;

  /// Set when the requested discount could not be applied (too high / no making charge).
  final String? discountError;
  double get totalTax => BillingCalc.r2(cgstSum + sgstSum + igstSum);

  /// The lowest price the customer can be charged.
  double get lowestPayable => billBeforeDiscount - maxDiscount;
}

class _Base {
  _Base(this.it, this.rate, this.making, this.overridden, this.taxable0, this.metalRaw, this.floorRaw, this.headroom, this.auto, this.hall);
  final BillItem it;
  final double rate, making, taxable0, metalRaw, floorRaw, auto, hall; // auto = what it would be with no typed amount
  final bool overridden;
  final int headroom; // paise that can be discounted on this line
}

class BillingCalc {
  BillingCalc._();

  static const double _eps = 2.220446049250313e-16;
  static double r2(num n) => ((n + _eps) * 100).round() / 100;
  static double r3(num n) => ((n + _eps) * 1000).round() / 1000;

  /// Mirrors `computeInvoice` in backend/services/billingCalc.js (rule v3: discount BEFORE GST; the hallmark fee is added after tax).
  static BillTotals compute({
    required List<BillItem> items,
    double goldRate = 0,
    double silverRate = 0,
    double additional = 0,
    double discount = 0,
    double paid = 0,
    bool interstate = false,
  }) {
    final gold = r2(goldRate);
    final silver = r2(silverRate);
    final add = r2(additional < 0 ? 0 : additional);
    final asked = r2(discount < 0 ? 0 : discount);
    // Extra charges (courier, packing...) are part of the value of supply (GST Act s.15(2)(c)): taxed like the goods.
    final addCg = interstate ? 0.0 : add * 0.015;
    final addSg = interstate ? 0.0 : add * 0.015;
    final addIg = interstate ? add * 0.03 : 0.0;
    final addTotal = r2(add + addCg + addSg + addIg);

    final base = <_Base>[];
    for (final it in items) {
      final wt = r3(it.netWt);
      final fallback = it.metal == 'Silver' ? silver : it.metal == 'Gold' ? gold : 0.0;
      final rate = r2(it.rate != 0 ? it.rate : fallback);
      final making = r2(it.making < 0 ? 0 : it.making);
      final extras = r2(it.extras.fold<double>(0, (a, e) => a + (e.amount < 0 ? 0 : r2(e.amount))));
      final hall = it.certification.isEmpty ? 0.0 : r2(it.hallmarkCharge < 0 ? 0 : it.hallmarkCharge);
      final preTax = extras;   // stones only: the hallmark fee is outside the taxable value
      final metalRaw = wt * rate;
      final ov = it.taxableOverride;
      final taxable0 = ov != null ? r2(ov) : metalRaw + making + preTax;
      // no making charge (and no typed taxable): discount comes off the total but never below the metal value
      final noMaking = ov == null && !(making > 0);
      final floorRaw = noMaking ? metalRaw : metalRaw + preTax;
      final headroom = (taxable0 * 100).round() - (floorRaw * 100).round();
      base.add(_Base(it, rate, making, ov != null, taxable0, metalRaw, floorRaw, headroom < 0 ? 0 : headroom, metalRaw + making + preTax, hall));
    }

    BillLine buildLine(_Base b, int dPaise) {
      final taxableRaw = b.taxable0 - dPaise / 100;
      final cg = interstate ? 0.0 : taxableRaw * 0.015;
      final sg = interstate ? 0.0 : taxableRaw * 0.015;
      final ig = interstate ? taxableRaw * 0.03 : 0.0;
      final total = r2(taxableRaw + cg + sg + ig + b.hall);   // hallmark fee: after tax, no GST on it
      final making = b.overridden ? 0.0 : r2(b.making - dPaise / 100 < 0 ? 0 : b.making - dPaise / 100);
      final hidden = b.overridden && (taxableRaw * 100).round() > (b.floorRaw * 100).round();
      return BillLine(
        rate: b.rate,
        taxable: r2(taxableRaw),
        cgst: r2(cg),
        sgst: r2(sg),
        igst: r2(ig),
        total: total,
        autoTaxable: r2(b.auto),
        making: making,
        discount: dPaise / 100,
        name: b.it.displayName + (hidden ? ' + Making Charge' : ''),
        hiddenMaking: hidden,
        metalValue: r2(b.metalRaw),
        hallmark: b.hall,
      );
    }

    final sumHp = base.fold<int>(0, (a, b) => a + b.headroom);

    List<int> allocate(int dtPaise) {
      final alloc = List<int>.filled(base.length, 0);
      if (dtPaise <= 0 || sumHp <= 0) return alloc;
      final frac = <List<num>>[];
      var given = 0;
      for (var i = 0; i < base.length; i++) {
        final share = dtPaise * base[i].headroom / sumHp;
        final f = share.floor() < base[i].headroom ? share.floor() : base[i].headroom;
        alloc[i] = f;
        given += f;
        frac.add([share - f, i]);
      }
      var rem = dtPaise - given;
      frac.sort((x, y) => (y[0] as double).compareTo(x[0] as double));
      while (rem > 0) {
        var moved = false;
        for (final f in frac) {
          if (rem <= 0) break;
          final i = f[1] as int;
          if (alloc[i] < base[i].headroom) {
            alloc[i]++;
            rem--;
            moved = true;
          }
        }
        if (!moved) break;
      }
      return alloc;
    }

    List<BillLine> linesFor(List<int> alloc) => [for (var i = 0; i < base.length; i++) buildLine(base[i], alloc[i])];
    double sumTotals(List<BillLine> ls) => ls.fold<double>(0, (a, l) => a + l.total);

    // the bill before any discount
    final lines0 = linesFor(List<int>.filled(base.length, 0));
    final before0 = sumTotals(lines0) + addTotal;
    final bill0 = before0.roundToDouble();
    final ro0 = bill0 - before0;
    final metalValue = r2(base.fold<double>(0, (a, b) => a + b.metalRaw));
    final maxDiscount = ((sumHp / 100) * 1.03 + ro0 - 0.02).floor().clamp(0, 1 << 30).toDouble();

    var lines = lines0;
    var discountBeforeGst = 0.0;
    String? error;
    if (asked > 0 && items.isNotEmpty) {
      if (asked > maxDiscount) {
        error = maxDiscount > 0 ? 'Discount is too high: at most ₹${maxDiscount.toStringAsFixed(0)} can be given' : 'No discount is possible: no making charge above the metal value';
      } else {
        final target = (bill0 - asked).round();
        final start = (((asked - ro0) / 1.03) * 100).round();
        List<BillLine>? best;
        var bestP = 0;
        for (var k = 0; k <= 12 && best == null; k++) {
          for (final sgn in (k == 0 ? [0] : [1, -1])) {
            var p = start + sgn * k;
            if (p < 0) p = 0;
            if (p > sumHp) p = sumHp;
            final cand = linesFor(allocate(p));
            if ((sumTotals(cand) + addTotal).round() == target) {
              best = cand;
              bestP = p;
              break;
            }
          }
        }
        if (best == null) {
          error = 'Could not fit that discount exactly';
        } else {
          lines = best;
          discountBeforeGst = bestP / 100;
        }
      }
    }

    final itemsTotal = sumTotals(lines);
    final totalAmount = r2(itemsTotal + addTotal);
    final before = itemsTotal + addTotal;
    final payable = before.roundToDouble();
    final roundOff = r2(payable - before);
    final paidR = r2(paid < 0 ? 0 : paid);
    final tds = payable > 200000;
    return BillTotals(
      lines: lines,
      totalAmount: totalAmount,
      additional: add,
      discount: r2(bill0 - payable),
      payable: payable,
      roundOff: roundOff,
      paid: paidR,
      due: paidR < payable ? r2(payable - paidR) : 0,
      advance: paidR > payable ? r2(paidR - payable) : 0,
      taxableSum: r2(lines.fold<double>(0, (a, l) => a + l.taxable) + add),
      cgstSum: r2(lines.fold<double>(0, (a, l) => a + l.cgst) + r2(addCg)),
      sgstSum: r2(lines.fold<double>(0, (a, l) => a + l.sgst) + r2(addSg)),
      igstSum: r2(lines.fold<double>(0, (a, l) => a + l.igst) + r2(addIg)),
      additionalGst: r2(addCg + addSg + addIg),
      hallmarkTotal: r2(base.fold<double>(0, (a, b) => a + b.hall)),
      tdsApplicable: tds,
      tdsAmount: tds ? r2(payable / 100) : 0,
      interstate: interstate,
      grossTaxable: r2(base.fold<double>(0, (a, b) => a + b.taxable0)),
      discountBeforeGst: discountBeforeGst,
      billBeforeDiscount: bill0,
      maxDiscount: maxDiscount,
      metalValue: metalValue,
      discountError: error,
    );
  }

  /// The first thing wrong with the items, in plain words (null = fine).
  /// Mirrors the server's checks so mistakes are caught before Save.
  static String? validateItems(List<BillItem> items, {double goldRate = 0, double silverRate = 0}) {
    if (items.isEmpty) return 'Add at least one item';
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final n = i + 1;
      if (it.particular.trim().isEmpty) return 'Item $n: enter what is being sold';
      if (!(r3(it.netWt) > 0)) return 'Item $n: net weight must be more than 0';
      if (it.grossWt > 0 && it.netWt > it.grossWt + 0.0005) return 'Item $n: net weight cannot be more than gross weight';
      final rate = it.rate != 0 ? it.rate : (it.metal == 'Silver' ? silverRate : it.metal == 'Gold' ? goldRate : 0.0);
      if (!(r2(rate) > 0)) return 'Item $n: enter the ${it.metal.toLowerCase()} rate';
      if (it.certification == 'huid' && !BillItem.huidPattern.hasMatch(it.huid.trim().toUpperCase())) return 'Item $n: HUID must be 6 letters or digits';
      if (it.taxableOverride != null && !(it.taxableOverride! > 0)) return 'Item $n: taxable amount must be more than 0';
      if (it.taxableOverride != null && (it.taxableOverride! * 100).round() < ((r3(it.netWt) * r2(rate)) * 100).round()) {
        return 'Item $n: taxable amount cannot be below the metal value (₹${(r3(it.netWt) * r2(rate)).toStringAsFixed(2)})';
      }
    }
    return null;
  }
}
