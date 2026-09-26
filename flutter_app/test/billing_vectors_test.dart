// 400 random bills computed by the SERVER engine (backend/scripts/gen-billing-vectors.js).
// The phone's live preview must reproduce every number, or staff would see one figure and the
// invoice would carry another.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_stock_app/utils/billing_calc.dart';

double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

BillItem _item(Map<String, dynamic> j) => BillItem(
      particular: j['particulars'] as String,
      metal: j['metalType'] as String,
      netWt: _d(j['netWt']),
      rate: _d(j['rate']),
      making: _d(j['makingCharge']),
      taxableOverride: j['taxableOverride'] == null ? null : _d(j['taxableOverride']),
      certification: (j['certification'] as String?) ?? '',
      hallmarkCharge: _d(j['hallmarkCharge']),
      huid: (j['huid'] as String?) ?? '',
      extras: [for (final e in (j['extras'] as List? ?? [])) BillExtra(kind: e['kind'], name: e['name'], weight: _d(e['weight']), amount: _d(e['amount']))],
    );

void main() {
  final vectors = (json.decode(File('test/billing_vectors.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

  test('${vectors.length} server-computed bills are reproduced exactly (payable, tax, discount split, making, names)', () {
    var checked = 0, refused = 0;
    for (var n = 0; n < vectors.length; n++) {
      final v = vectors[n];
      final inp = v['input'] as Map<String, dynamic>;
      final exp = v['expect'] as Map<String, dynamic>;
      final t = BillingCalc.compute(
        items: [for (final i in (inp['items'] as List)) _item(Map<String, dynamic>.from(i))],
        goldRate: _d(inp['goldRate']),
        silverRate: _d(inp['silverRate']),
        additional: _d(inp['additionalCharges']),
        discount: _d(inp['discount']),
        interstate: inp['interstate'] == true,
      );
      final tag = 'vector $n';
      if (exp['ok'] != true) {
        expect(t.discountError, isNotNull, reason: '$tag: server refused, so must the phone');
        expect(t.maxDiscount, _d(exp['maxDiscount']), reason: '$tag: max discount');
        refused++;
        continue;
      }
      expect(t.discountError, isNull, reason: '$tag: ${t.discountError}');
      expect(t.payable, _d(exp['payable']), reason: '$tag: payable');
      expect(t.roundOff, _d(exp['roundOff']), reason: '$tag: round off');
      expect(t.totalAmount, _d(exp['totalAmount']), reason: '$tag: total amount');
      expect(t.discount, _d(exp['discountGiven']), reason: '$tag: discount given');
      expect(t.discountBeforeGst, _d(exp['discountBeforeGst']), reason: '$tag: discount before GST');
      expect(t.grossTaxable, _d(exp['grossTaxable']), reason: '$tag: gross taxable');
      expect(t.billBeforeDiscount, _d(exp['billBefore']), reason: '$tag: bill before discount');
      expect(t.maxDiscount, _d(exp['maxDiscount']), reason: '$tag: max discount');
      expect(t.metalValue, _d(exp['metalValue']), reason: '$tag: metal value');
      expect(t.additionalGst, _d(exp['additionalGst']), reason: '$tag: GST on extra charges');
      expect(t.taxableSum, _d(exp['taxable']), reason: '$tag: taxable sum');
      expect(BillingCalc.r2(t.cgstSum + t.sgstSum + t.igstSum), _d(exp['gst']), reason: '$tag: gst');
      final lines = (exp['lines'] as List).cast<Map<String, dynamic>>();
      expect(t.lines.length, lines.length);
      for (var i = 0; i < lines.length; i++) {
        final l = t.lines[i], e = lines[i];
        expect(l.taxable, _d(e['taxable']), reason: '$tag line $i: taxable');
        expect(l.cgst, _d(e['cgst']), reason: '$tag line $i: cgst');
        expect(l.sgst, _d(e['sgst']), reason: '$tag line $i: sgst');
        expect(l.igst, _d(e['igst']), reason: '$tag line $i: igst');
        expect(l.total, _d(e['total']), reason: '$tag line $i: total');
        expect(l.making, _d(e['making']), reason: '$tag line $i: making');
        expect(l.discount, _d(e['discount']), reason: '$tag line $i: discount share');
        expect(l.name, e['name'], reason: '$tag line $i: printed name');
      }
      checked++;
    }
    expect(checked, greaterThan(300));
    expect(refused, greaterThan(20));
  });
}
