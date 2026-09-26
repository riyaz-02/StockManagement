// Same vectors as backend/scripts/billing-calc.test.js: the phone's live preview
// must give exactly the numbers the server saves.
import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_stock_app/utils/billing_calc.dart';

void main() {
  test('single gold line: 10.500 g @ 6000 + 1500 making', () {
    final t = BillingCalc.compute(items: [BillItem(particular: 'Ring', netWt: 10.5, rate: 6000, making: 1500)]);
    expect([t.lines[0].taxable, t.lines[0].cgst, t.lines[0].sgst, t.lines[0].total], [64500, 967.5, 967.5, 66435]);
    expect(t.totalAmount, 66435);
    expect(t.payable, 66435);
    expect(t.roundOff, 0);
    expect(t.totalTax, 1935);
    expect(t.tdsApplicable, false);
  });

  test('rate defaults from the metal rate when the line rate is blank; Other has none', () {
    final t = BillingCalc.compute(goldRate: 6000, silverRate: 80, items: [
      BillItem(particular: 'Chain', netWt: 2),
      BillItem(particular: 'Bowl', metal: 'Silver', netWt: 100, making: 200),
    ]);
    expect(t.lines[0].rate, 6000);
    expect(t.lines[1].rate, 80);
    expect(t.lines[1].taxable, 8200);
    expect(BillingCalc.validateItems([BillItem(particular: 'x', metal: 'Other', netWt: 1)]), contains('rate'));
  });

  test('bill of 880 (invoice 1401 with its Rs 55 extra charge now taxed): paying 850 takes 30 off the making charge, before GST', () {
    final it = () => [BillItem(particular: 'Chain', netWt: 0.08, rate: 9190, making: 64)];
    final full = BillingCalc.compute(items: it(), additional: 55);
    expect([full.lines[0].total, full.additionalGst, full.totalAmount, full.payable, full.roundOff], [823.18, 1.65, 879.83, 880, 0.17]);
    final t = BillingCalc.compute(items: it(), additional: 55, discount: 30, paid: 850);
    expect(t.payable, 850);
    expect(t.discount, 30);
    expect(t.due, 0);
    expect((t.discountBeforeGst - 28.96).abs() < 0.02, isTrue);
    expect((t.lines[0].making - 35.04).abs() < 0.02, isTrue);
    expect((t.taxableSum - 825.24).abs() < 0.02, isTrue); // goods 770.24 + extra charges 55
    expect(t.maxDiscount, 66);
    expect(BillingCalc.compute(items: it(), additional: 55, discount: 67).discountError, contains('too high'));
  });

  test('extra charges are taxed like the goods (s.15(2)(c)); IGST 3% when interstate', () {
    final it = () => [BillItem(particular: 'Ring', netWt: 10.5, rate: 6000, making: 1500)];
    final a = BillingCalc.compute(items: it(), additional: 500);
    expect([a.additionalGst, a.totalAmount, a.payable, a.taxableSum, a.totalTax], [15, 66950, 66950, 65000, 1950]);
    final b = BillingCalc.compute(items: it(), additional: 500, interstate: true);
    expect([b.additionalGst, b.igstSum, b.payable], [15, 1950, 66950]);
  });

  test('typed taxable amount (making 0) gets "+ Making Charge"; discount comes off it but never below the metal value', () {
    final it = () => [BillItem(particular: 'Gold Ring', netWt: 10, rate: 6000, taxableOverride: 64000)];
    final t = BillingCalc.compute(items: it());
    expect(t.lines[0].name, 'Gold Ring + Making Charge');
    expect(t.lines[0].making, 0);
    final d = BillingCalc.compute(items: it(), discount: 1030);
    expect(d.payable, 64890);
    expect((d.lines[0].taxable - 63000).abs() < 0.02, isTrue);
    final edge = BillingCalc.compute(items: it(), discount: t.maxDiscount);
    expect(edge.discountError, isNull);
    expect(edge.lines[0].taxable >= 60000 - 0.005, isTrue);
    expect(BillingCalc.compute(items: it(), discount: t.maxDiscount + 1).discountError, isNotNull);
    expect(BillingCalc.validateItems([BillItem(particular: 'x', netWt: 10, rate: 6000, taxableOverride: 50000)]), contains('below the metal value'));
  });

  test('typed taxable amount replaces weight x rate + making', () {
    final t = BillingCalc.compute(items: [BillItem(particular: 'x', netWt: 10, rate: 6000, making: 500, taxableOverride: 60000)]);
    expect([t.lines[0].taxable, t.lines[0].cgst, t.lines[0].total], [60000, 900, 61800]);
    expect(t.payable, 61800);
  });

  test('due and advance are signed against the rupee-rounded payable', () {
    final it = [BillItem(particular: 'x', netWt: 1, rate: 1000)];
    expect(BillingCalc.compute(items: it, paid: 30).due, 1000);
    expect(BillingCalc.compute(items: it, paid: 2000).advance, 970);
  });

  test('TDS 1% above Rs 2,00,000', () {
    final t = BillingCalc.compute(items: [BillItem(particular: 'x', netWt: 100, rate: 2000)]);
    expect(t.payable, 206000);
    expect(t.tdsApplicable, true);
    expect(t.tdsAmount, 2060);
  });

  test('validation messages match the server', () {
    expect(BillingCalc.validateItems([]), 'Add at least one item');
    expect(BillingCalc.validateItems([BillItem(particular: '', netWt: 1, rate: 1)]), contains('what is being sold'));
    expect(BillingCalc.validateItems([BillItem(particular: 'x', netWt: 0, rate: 1)]), contains('net weight'));
  });

  test('another state: IGST 3% instead of CGST+SGST, same total', () {
    final it = () => [BillItem(particular: 'Ring', netWt: 10.5, rate: 6000, making: 1500)];
    final a = BillingCalc.compute(items: it());
    final b = BillingCalc.compute(items: it(), interstate: true);
    expect([b.lines[0].taxable, b.lines[0].cgst, b.lines[0].sgst, b.lines[0].igst, b.lines[0].total], [64500, 0, 0, 1935, 66435]);
    expect(b.payable, a.payable);
    expect([b.igstSum, b.totalTax, b.interstate], [1935, 1935, true]);
  });

  test('stones / other metals add their value to the taxable amount', () {
    final t = BillingCalc.compute(items: [
      BillItem(particular: 'Ring', netWt: 10, rate: 6000, making: 500, grossWt: 10.4, extras: [BillExtra(name: 'Ruby', weight: 0.4, amount: 2000)])
    ]);
    expect(t.lines[0].taxable, 62500);
    expect(t.lines[0].autoTaxable, 62500);
  });

  test('a typed taxable amount wins, but the calculated one is still known', () {
    final t = BillingCalc.compute(interstate: true, items: [
      BillItem(particular: 'x', netWt: 10, rate: 6000, extras: [BillExtra(name: 'x', amount: 999)], taxableOverride: 50000)
    ]);
    expect([t.lines[0].taxable, t.lines[0].igst, t.lines[0].total, t.lines[0].autoTaxable], [50000, 1500, 51500, 60999]);
  });

  test('net weight cannot exceed gross weight', () {
    expect(BillingCalc.validateItems([BillItem(particular: 'x', netWt: 5, grossWt: 4, rate: 1)]), contains('gross'));
  });

  test('hallmarked: charge is pre-tax and the name gets (Hallmarked); same numbers as the server', () {
    final it = BillItem(particular: 'Earring', netWt: 2, rate: 1000, making: 100, certification: 'hallmark', hallmarkCharge: 45);
    final t = BillingCalc.compute(items: [it]);
    expect([t.lines[0].taxable, t.lines[0].cgst, t.lines[0].sgst, t.lines[0].total], [2145, 32.17, 32.17, 2209.35]);
    expect(it.displayName, 'Earring (Hallmarked)');
  });

  test('HUID: code in the name, must be 6 letters/digits', () {
    final it = BillItem(particular: 'Earring', netWt: 1, rate: 1000, certification: 'huid', huid: 'ab12cd', hallmarkCharge: 45);
    expect(it.displayName, 'Earring (HUID: AB12CD)');
    expect(BillingCalc.compute(items: [it]).lines[0].taxable, 1045);
    expect(BillingCalc.validateItems([it]), isNull);
    it.huid = 'AB1';
    expect(BillingCalc.validateItems([it]), contains('HUID'));
    final plain = BillItem(particular: 'Ring', netWt: 1, rate: 1000, hallmarkCharge: 99); // not certified: no charge
    expect(BillingCalc.compute(items: [plain]).lines[0].taxable, 1000);
    expect(plain.displayName, 'Ring');
  });
}
