/**
 * billing-calc.test.js — unit tests for the invoice maths. No DB or network.
 *   node scripts/billing-calc.test.js
 *
 * Vector 1 is a REAL invoice from the live system (invoice 1401). The same
 * vectors run in flutter_app/test/billing_calc_test.dart so the phone's live
 * preview can never disagree with what the server saves.
 */
'use strict';
const assert = require('assert');
const { computeInvoice, amountInWords, invoiceStatus, todayIST, r2 } = require('../services/billingCalc');

let n = 0;
const t = (name, fn) => { fn(); n++; console.log('  ok   ' + name); };
const one = (o = {}) => ({ particulars: 'Ring', metalType: 'Gold', netWt: 1, rate: 1000, makingCharge: 0, ...o });

t('REAL invoice 1401 (the old website after-GST discount rule): 0.08 g @ 9190 + 64 making, +55 charges, -78 discount', () => {
    const r = computeInvoice({ items: [one({ netWt: 0.08, rate: 9190, makingCharge: 64 })], additionalCharges: 55, discount: 78, paidAmount: 800, discountMode: 'after_gst' });
    assert.ok(r.ok);
    const l = r.items[0];
    assert.deepStrictEqual([l.taxable_amount, l.cgst, l.sgst, l.total], [799.2, 11.99, 11.99, 823.18]);
    assert.strictEqual(r.totalAmount, 878.18);                 // items + additional charges
    assert.strictEqual(r.totalPayableAmount, 800);             // rounded to the rupee
    assert.strictEqual(r.roundOff, -0.18);                     // rounded - before
    assert.strictEqual(r.dueAdvance, 0);
    assert.deepStrictEqual([r.gstSummary.total_taxable_amount, r.gstSummary.total_cgst, r.gstSummary.total_sgst, r.gstSummary.total_gst], [799.2, 11.99, 11.99, 23.98]);
});

t('single gold line 10.5 g @ 6000 + 1500', () => {
    const r = computeInvoice({ items: [one({ netWt: 10.5, rate: 6000, makingCharge: 1500 })] });
    assert.deepStrictEqual([r.items[0].taxable_amount, r.items[0].cgst, r.items[0].total], [64500, 967.5, 66435]);
    assert.deepStrictEqual([r.totalAmount, r.totalPayableAmount, r.roundOff], [66435, 66435, 0]);
});

t('rounds to the nearest rupee, both directions', () => {
    let r = computeInvoice({ items: [one({ rate: 1000.55 })] });          // 1030.57 -> 1031, +0.43
    assert.deepStrictEqual([r.totalAmount, r.totalPayableAmount, r.roundOff], [1030.57, 1031, 0.43]);
    r = computeInvoice({ items: [one({ rate: 1000.1 })] });               // 1030.10 -> 1030, -0.1
    assert.strictEqual(r.totalPayableAmount, 1030);
    assert.strictEqual(r.roundOff, -0.1);
});

t('rate defaults from the metal rate; "Other" needs its own rate', () => {
    const r = computeInvoice({ goldRate: 6000, silverRate: 80, items: [one({ rate: '', netWt: 2 }), one({ metalType: 'Silver', rate: '', netWt: 100, makingCharge: 200 })] });
    assert.deepStrictEqual([r.items[0].rate, r.items[1].rate, r.items[1].taxable_amount], [6000, 80, 8200]);
    assert.match(computeInvoice({ goldRate: 6000, items: [one({ metalType: 'Other', rate: '' })] }).error, /rate/);
    assert.strictEqual(computeInvoice({ items: [one({ metalType: 'Other', rate: 50 })] }).items[0].metal_type, 'Other');
});

t('typed taxable override replaces weight x rate + making', () => {
    const r = computeInvoice({ items: [one({ netWt: 10, rate: 6000, makingCharge: 500, taxableOverride: 60000 })] });
    assert.deepStrictEqual([r.items[0].taxable_amount, r.items[0].cgst, r.items[0].total], [60000, 900, 61800]);
});

t('due (negative) / advance (positive) / exact', () => {
    const base = { items: [one()] };                                       // payable 1030
    let r = computeInvoice({ ...base, paidAmount: 500 });  assert.deepStrictEqual([r.dueAdvance, r.dueAmount, r.advanceAmount], [-530, 530, 0]);
    r = computeInvoice({ ...base, paidAmount: 1500 });     assert.deepStrictEqual([r.dueAdvance, r.dueAmount, r.advanceAmount], [470, 0, 470]);
    r = computeInvoice({ ...base, paidAmount: 1030 });     assert.deepStrictEqual([r.dueAdvance, r.dueAmount, r.advanceAmount], [0, 0, 0]);
});

t('TDS 1% only above Rs 2,00,000 of payable', () => {
    let r = computeInvoice({ items: [one({ netWt: 100, rate: 1900 })] });      // 190000 + 3% = 195700
    assert.deepStrictEqual([r.tdsApplicable, r.tdsAmount], [false, 0]);
    r = computeInvoice({ items: [one({ netWt: 100, rate: 2000 })] });          // 206000
    assert.deepStrictEqual([r.tdsApplicable, r.tdsRate, r.tdsAmount], [true, 1, 2060]);
});

t('weight kept to 3 decimals, money to 2', () => {
    const l = computeInvoice({ items: [one({ netWt: 1.23456, rate: 100.456, makingCharge: 0.999 })] }).items[0];
    assert.deepStrictEqual([l.net_wt, l.rate, l.making_charge], [1.235, 100.46, 1]);
});

t('rejects bad input with a readable message', () => {
    assert.match(computeInvoice({ items: [] }).error, /at least one item/);
    assert.match(computeInvoice({ items: [one({ particulars: '' })] }).error, /Item 1: enter what/);
    assert.match(computeInvoice({ items: [one({ netWt: 0 })] }).error, /weight/);
    assert.match(computeInvoice({ items: [one({ rate: 0 })] }).error, /rate/);
    assert.match(computeInvoice({ discount: 99999, items: [one()], discountMode: 'after_gst' }).error, /Discount/);
});

t('status follows the website: delivered / pending / active', () => {
    assert.strictEqual(invoiceStatus(800, 800, '2026-09-19', '2026-09-19'), 'delivered');
    assert.strictEqual(invoiceStatus(800, 800, '2026-09-25', '2026-09-19'), 'pending');   // not delivered yet
    assert.strictEqual(invoiceStatus(800, 300, '2026-09-19', '2026-09-19'), 'active');    // delivered, unpaid
    assert.strictEqual(invoiceStatus(800, 300, '2026-09-25', '2026-09-19'), 'pending');
    assert.match(todayIST(), /^\d{4}-\d{2}-\d{2}$/);
});

t('another state: IGST 3% instead of CGST+SGST, same line total', () => {
    const a = computeInvoice({ items: [one({ netWt: 10.5, rate: 6000, makingCharge: 1500 })] });
    const b = computeInvoice({ items: [one({ netWt: 10.5, rate: 6000, makingCharge: 1500 })], interstate: true });
    const l = b.items[0];
    assert.deepStrictEqual([l.taxable_amount, l.cgst, l.sgst, l.igst, l.total], [64500, 0, 0, 1935, 66435]);
    assert.strictEqual(b.totalPayableAmount, a.totalPayableAmount);
    assert.deepStrictEqual([b.gstSummary.total_igst, b.gstSummary.total_gst, b.gstSummary.igst_rate, b.gstSummary.cgst_rate], [1935, 1935, 3, 0]);
    assert.strictEqual(b.gstType, 'IGST');
    assert.strictEqual(a.gstType, 'CGST_SGST');
    assert.strictEqual(a.items[0].igst, undefined);
});

t('stones / other metals add their value to the taxable amount', () => {
    const r = computeInvoice({ items: [one({ netWt: 10, rate: 6000, makingCharge: 500, grossWt: 10.4, purity: '22K', productCode: 'LG-101',
        extras: [{ kind: 'Stone', name: 'Ruby', weight: 0.4, amount: 2000 }] })] });
    const l = r.items[0];
    assert.strictEqual(l.taxable_amount, 62500);                 // 60000 + 500 + 2000
    assert.strictEqual(l.stone_charge, 2000);
    assert.deepStrictEqual([l.purity, l.gross_wt, l.product_code], ['22K', 10.4, 'LG-101']);
    assert.deepStrictEqual(l.extras, [{ kind: 'Stone', name: 'Ruby', weight: 0.4, amount: 2000 }]);
});

t('net weight cannot exceed gross weight; empty extras are dropped', () => {
    assert.match(computeInvoice({ items: [one({ netWt: 5, grossWt: 4 })] }).error, /gross/);
    const r = computeInvoice({ items: [one({ extras: [{ kind: 'Stone', name: '', weight: 0, amount: 0 }] })] });
    assert.strictEqual(r.items[0].extras, undefined);
});

t('a typed taxable amount still wins over weight, making and stones (when it is not below the metal value)', () => {
    const r = computeInvoice({ items: [one({ netWt: 10, rate: 6000, extras: [{ name: 'x', amount: 999 }], taxableOverride: 62000 })], interstate: true });
    assert.deepStrictEqual([r.items[0].taxable_amount, r.items[0].igst, r.items[0].total], [62000, 1860, 63860]);
});

t('a typed taxable amount below the metal value is refused', () => {
    const r = computeInvoice({ items: [one({ netWt: 10, rate: 6000, taxableOverride: 50000 })] });
    assert.match(r.error, /below the metal value \(₹60000\.00\)/);
    // the old website rule allowed it
    assert.ok(computeInvoice({ items: [one({ netWt: 10, rate: 6000, taxableOverride: 50000 })], discountMode: 'after_gst' }).ok);
});

t('hallmarked: charge is pre-tax, name gets "(Hallmarked)"', () => {
    const r = computeInvoice({ items: [one({ particulars: 'Earring', netWt: 2, rate: 1000, makingCharge: 100, certification: 'hallmark', hallmarkCharge: 45 })] });
    const l = r.items[0];
    assert.strictEqual(l.particulars, 'Earring (Hallmarked)');
    assert.strictEqual(l.item_name, 'Earring');
    assert.strictEqual(l.taxable_amount, 2145);                         // 2000 + 100 + 45, before GST
    assert.deepStrictEqual([l.cgst, l.sgst, l.total], [32.17, 32.17, 2209.35]);
    assert.strictEqual(l.hallmark_charge, 45);
    assert.strictEqual(l.certification, 'hallmark');
});

t('HUID: code goes into the name, charge is pre-tax, code must be 6 letters/digits', () => {
    const r = computeInvoice({ items: [one({ particulars: 'Earring', certification: 'huid', huid: 'ab12cd', hallmarkCharge: 45 })] });
    assert.strictEqual(r.items[0].particulars, 'Earring (HUID: AB12CD)');
    assert.strictEqual(r.items[0].huid, 'AB12CD');
    assert.strictEqual(r.items[0].taxable_amount, 1045);
    assert.match(computeInvoice({ items: [one({ certification: 'huid', huid: 'AB1' })] }).error, /HUID must be 6/);
    assert.match(computeInvoice({ items: [one({ certification: 'huid' })] }).error, /HUID must be 6/);
    // a HUID with no certification given still counts as HUID
    assert.strictEqual(computeInvoice({ items: [one({ particulars: 'Ring', huid: 'ZZ99ZZ' })] }).items[0].particulars, 'Ring (HUID: ZZ99ZZ)');
    // no certification: the name is left alone and no charge is taken
    const plain = computeInvoice({ items: [one({ particulars: 'Ring', hallmarkCharge: 99 })] }).items[0];
    assert.deepStrictEqual([plain.particulars, plain.taxable_amount, plain.certification], ['Ring', 1000, undefined]);
});


// ─────────────────────────── discount BEFORE GST (rule v2) ───────────────────────────
const bill = (extra = {}, item = {}) => computeInvoice({ items: [one({ particulars: 'Gold Ring', netWt: 2, rate: 10000, makingCharge: 3636.5, ...item })], ...extra });

t('bill 24346, customer wants to pay 24200: payable is exactly 24200, taken off the making charge, GST follows', () => {
    const full = bill();
    assert.strictEqual(full.billBeforeDiscount, 24346);
    const r = bill({ discount: 146 });
    assert.ok(r.ok, r.error);
    assert.strictEqual(r.totalPayableAmount, 24200);
    assert.strictEqual(r.discountGiven, 146);
    const l = r.items[0];
    assert.ok(Math.abs(r.discountBeforeGst - 146 / 1.03) < 0.5, `pre-tax discount ${r.discountBeforeGst}`);   // the bill's own 0.405 round-off is folded in
    assert.strictEqual(l.taxable_amount, r2(23636.5 - r.discountBeforeGst));                  // taxable came down
    assert.strictEqual(l.making_charge, r2(3636.5 - r.discountBeforeGst));                    // ...by cutting the making charge
    assert.ok(l.taxable_amount > 20000, 'metal value is untouched');
    assert.ok(Math.abs(l.cgst - l.taxable_amount * 0.015) <= 0.006 && Math.abs(l.sgst - l.taxable_amount * 0.015) <= 0.006);
    assert.strictEqual(r.grossTaxable, 23636.5);
    assert.strictEqual(r.discount, 0);                          // the website's own discount field stays 0 (lines are already net)
    assert.strictEqual(r.discountMode, 'before_gst');
    assert.ok(Math.abs(r.gstSummary.total_taxable_amount + r.discountBeforeGst - 23636.5) <= 0.011);
});

t('typed taxable amount with making 0: name gets "+ Making Charge", making column stays 0, discount comes off the taxable amount', () => {
    const at = { items: [one({ particulars: 'Gold Ring', netWt: 10, rate: 6000, taxableOverride: 64000 })] };
    const r = computeInvoice(at);
    assert.strictEqual(r.items[0].particulars, 'Gold Ring + Making Charge');
    assert.strictEqual(r.items[0].making_charge, 0);
    assert.strictEqual(r.items[0].item_name, 'Gold Ring');
    const d = computeInvoice({ ...at, discount: 1030 });
    assert.ok(d.ok, d.error);
    assert.strictEqual(d.totalPayableAmount, 65920 - 1030);
    assert.ok(Math.abs(d.items[0].taxable_amount - 63000) <= 0.02, `${d.items[0].taxable_amount}`);
    assert.strictEqual(d.items[0].particulars, 'Gold Ring + Making Charge');      // some hidden making still remains
});

t('the discount can never go into the metal: refused above the maximum; at the maximum payable is still >= metal + GST', () => {
    const at = { items: [one({ particulars: 'Ring', netWt: 10, rate: 6000, taxableOverride: 64000 })] };
    const full = computeInvoice(at);
    const max = full.maxDiscount;
    assert.ok(max > 4000 && max < 4200, `max ${max}`);
    const over = computeInvoice({ ...at, discount: max + 1 });
    assert.ok(!over.ok && /too high/.test(over.error) && over.maxDiscount === max, over.error);
    const edge = computeInvoice({ ...at, discount: max });
    assert.ok(edge.ok, edge.error);
    assert.ok(edge.items[0].taxable_amount >= 60000 - 0.005, `taxable ${edge.items[0].taxable_amount}`);
    assert.ok(edge.totalPayableAmount >= 60000 * 1.03 - 0.5);
    assert.ok(edge.totalPayableAmount >= edge.metalValue);
    // once the hidden making is used up, the "+ Making Charge" wording goes too
    assert.strictEqual(edge.items[0].particulars.endsWith('+ Making Charge'), edge.items[0].taxable_amount > 60000);
});

t('no making charge and no typed amount: nothing to discount, said clearly', () => {
    const r = computeInvoice({ items: [one({ netWt: 5, rate: 6000 })], discount: 100 });
    assert.ok(!r.ok);
    assert.match(r.error, /No discount is possible/);
    assert.strictEqual(computeInvoice({ items: [one({ netWt: 5, rate: 6000 })] }).maxDiscount, 0);
});

t('stones and hallmark are protected like the metal', () => {
    const it = () => one({ netWt: 2, rate: 10000, makingCharge: 500, certification: 'hallmark', hallmarkCharge: 45, extras: [{ name: 'Ruby', amount: 2000 }] });
    const r = computeInvoice({ items: [it()] });
    assert.strictEqual(r.grossTaxable, 22545);
    assert.ok(r.maxDiscount <= 515 && r.maxDiscount >= 505, `max ${r.maxDiscount}`);           // only the 500 making charge
    const d = computeInvoice({ items: [it()], discount: r.maxDiscount });
    assert.ok(d.ok, d.error);
    assert.ok(d.items[0].taxable_amount >= 22045 - 0.005);
    assert.strictEqual(d.items[0].hallmark_charge, 45);
    assert.strictEqual(d.items[0].stone_charge, 2000);
});

t('no making charge: the discount comes off the total, but never below the metal value', () => {
    const it = () => one({ netWt: 2, rate: 10000, makingCharge: 0, extras: [{ name: 'Ruby', amount: 2000 }] });
    const r = computeInvoice({ items: [it()] });
    assert.strictEqual(r.grossTaxable, 22000);
    assert.ok(r.maxDiscount >= 2000 && r.maxDiscount <= 2100, `max ${r.maxDiscount}`);       // down to the metal value (20,000) + GST
    const d = computeInvoice({ items: [it()], discount: r.maxDiscount });
    assert.ok(d.ok, d.error);
    assert.ok(d.items[0].taxable_amount >= 20000 - 0.005);
    const over = computeInvoice({ items: [it()], discount: r.maxDiscount + 200 });
    assert.ok(!over.ok);
});

t('with a making charge only the making charge can be discounted (stones stay)', () => {
    const r = computeInvoice({ items: [one({ netWt: 2, rate: 10000, makingCharge: 300, extras: [{ name: 'Ruby', amount: 2000 }] })] });
    assert.ok(r.maxDiscount <= 310 && r.maxDiscount >= 300, `max ${r.maxDiscount}`);
});

t('two lines: the discount is shared in proportion to what can be discounted, and adds up exactly', () => {
    const r = computeInvoice({
        items: [
            one({ particulars: 'A', netWt: 1, rate: 10000, makingCharge: 1000 }),
            one({ particulars: 'B', netWt: 1, rate: 10000, makingCharge: 3000 }),
            one({ particulars: 'C', netWt: 1, rate: 10000 }),                                  // no making: takes none
        ],
        discount: 412,
    });
    assert.ok(r.ok, r.error);
    const [a, b, c] = r.items;
    assert.strictEqual(c.discount, undefined);
    assert.ok(Math.abs(b.discount - 3 * a.discount) < 0.02, `${a.discount} ${b.discount}`);
    assert.strictEqual(r2(a.discount + b.discount), r.discountBeforeGst);
    assert.strictEqual(r.totalPayableAmount, r.billBeforeDiscount - 412);
});

t('interstate (IGST) discount also lands the payable exactly', () => {
    const r = bill({ discount: 146, interstate: true });
    assert.ok(r.ok, r.error);
    assert.strictEqual(r.totalPayableAmount, 24200);
    assert.strictEqual(r.items[0].cgst, 0);
    assert.ok(Math.abs(r.items[0].igst - r.items[0].taxable_amount * 0.03) <= 0.006);
});

t('FUZZ: 3000 random bills with random discounts up to the maximum: payable exact, floors kept, GST correct', () => {
    let seed = 20260919;
    const rnd = () => { seed = (seed * 1664525 + 1013904223) % 4294967296; return seed / 4294967296; };
    const pick = (a, b) => a + rnd() * (b - a);
    let checked = 0, withDiscount = 0;
    for (let c = 0; c < 3000; c++) {
        const inter = rnd() < 0.3;
        const its = Array.from({ length: 1 + Math.floor(rnd() * 4) }, (_, i) => {
            const netWt = Math.round(pick(0.2, 60) * 1000) / 1000;
            const rate = Math.round(pick(60, 12000) * 100) / 100;
            const it = { particulars: `Item ${i}`, metalType: 'Gold', netWt, rate, makingCharge: rnd() < 0.3 ? 0 : Math.round(pick(0, 6000) * 100) / 100 };
            if (rnd() < 0.25) it.extras = [{ name: 'Stone', amount: Math.round(pick(50, 4000)) }];
            if (rnd() < 0.2) { it.certification = 'hallmark'; it.hallmarkCharge = Math.round(pick(20, 120)); }
            if (rnd() < 0.3) it.taxableOverride = Math.round((netWt * rate + pick(0, 5000) + (it.extras ? it.extras[0].amount : 0) + (it.hallmarkCharge || 0)) * 100) / 100;
            return it;
        });
        const additionalCharges = rnd() < 0.3 ? Math.round(pick(0, 500)) : 0;
        const full = computeInvoice({ items: its, interstate: inter, additionalCharges });
        if (!full.ok) continue;
        const max = full.maxDiscount;
        const dp = max <= 0 ? 0 : (rnd() < 0.15 ? max : Math.floor(rnd() * (max + 1)));
        const r = computeInvoice({ items: its, interstate: inter, additionalCharges, discount: dp });
        assert.ok(r.ok, `case ${c}: ${r.error} (discount ${dp}, max ${max})`);
        assert.strictEqual(r.totalPayableAmount, full.totalPayableAmount - dp, `case ${c}: payable`);
        assert.strictEqual(r.discountGiven, dp);
        let sumD = 0;
        r.items.forEach((l, i) => {
            const it = its[i];
            const noMaking = it.taxableOverride === undefined && !(it.makingCharge > 0);
            const floor = it.netWt * it.rate + (noMaking ? 0 : ((it.extras || []).reduce((a, e) => a + e.amount, 0)) + (it.certification ? (it.hallmarkCharge || 0) : 0));
            assert.ok(l.taxable_amount >= floor - 0.006, `case ${c}: line ${i} went below metal+stones+hallmark (${l.taxable_amount} < ${floor})`);
            assert.ok(l.making_charge >= 0);
            const tax = inter ? (l.igst || 0) : l.cgst + l.sgst;
            assert.ok(Math.abs(tax - l.taxable_amount * 0.03) <= 0.011, `case ${c}: tax`);
            assert.ok(Math.abs(l.total - (l.taxable_amount + tax)) <= 0.011, `case ${c}: line total`);
            sumD += l.discount || 0;
        });
        assert.ok(Math.abs(sumD - r.discountBeforeGst) <= 0.0051, `case ${c}: shares`);
        assert.ok(Math.abs(r.gstSummary.total_taxable_amount - (r.grossTaxable + additionalCharges - r.discountBeforeGst)) <= 0.03, `case ${c}: taxable sums`);
        assert.ok(Math.abs(r.gstSummary.total_gst - r.gstSummary.total_taxable_amount * 0.03) <= 0.012 * (r.items.length + 1), `case ${c}: total GST is 3% of the taxable value, extra charges included`);
        assert.ok(r.totalPayableAmount >= r.metalValue, `case ${c}: payable below metal value`);
        assert.ok(r.totalPayableAmount >= r.metalValue * 1.03 - 1, `case ${c}: payable below metal + GST`);
        if (dp > 0) withDiscount++;
        checked++;
    }
    assert.ok(checked > 2500 && withDiscount > 1200, `checked ${checked}, with discount ${withDiscount}`);
});

t('extra charges (courier, packing) are taxed like the goods: s.15(2)(c) - CGST+SGST', () => {
    const r = computeInvoice({ items: [one({ netWt: 10.5, rate: 6000, makingCharge: 1500 })], additionalCharges: 500 });
    assert.strictEqual(r.additionalGst, 15);
    assert.strictEqual(r.totalAmount, 66435 + 515);
    assert.strictEqual(r.totalPayableAmount, 66950);
    assert.deepStrictEqual([r.gstSummary.total_taxable_amount, r.gstSummary.total_cgst, r.gstSummary.total_sgst, r.gstSummary.total_gst], [65000, 975, 975, 1950]);
});

t('extra charges under IGST carry 3% IGST; the old website rule left them untaxed', () => {
    const r = computeInvoice({ items: [one({ netWt: 10.5, rate: 6000, makingCharge: 1500 })], additionalCharges: 500, interstate: true });
    assert.deepStrictEqual([r.additionalGst, r.gstSummary.total_igst, r.gstSummary.total_taxable_amount, r.totalPayableAmount], [15, 1950, 65000, 66950]);
    const old = computeInvoice({ items: [one({ netWt: 10.5, rate: 6000, makingCharge: 1500 })], additionalCharges: 500, discountMode: 'after_gst' });
    assert.deepStrictEqual([old.additionalGst, old.totalPayableAmount, old.gstSummary.total_taxable_amount], [0, 66935, 64500]);
});

t('a discount is never taken out of the extra charges, and the payable still lands exactly', () => {
    const r = computeInvoice({ items: [one({ netWt: 10.5, rate: 6000, makingCharge: 1500 })], additionalCharges: 500, discount: 400 });
    assert.ok(r.ok, r.error);
    assert.strictEqual(r.totalPayableAmount, 66950 - 400);
    assert.strictEqual(r.additionalTaxable, 500);
    assert.ok(Math.abs(r.gstSummary.total_taxable_amount - (65000 - r.discountBeforeGst)) <= 0.011);
});

t('amount in words: English + Bengali, Indian numbering', () => {
    assert.strictEqual(amountInWords(800).en, 'Eight Hundred Rupees Only');
    assert.strictEqual(amountInWords(12550).en, 'Twelve Thousand Five Hundred and Fifty Rupees Only');
    assert.strictEqual(amountInWords(12550).bn, 'বারো হাজার পাঁচ শত পঞ্চাশ টাকা মাত্র');
    assert.strictEqual(amountInWords(12345678).en, 'One Crore Twenty Three Lakh Forty Five Thousand Six Hundred and Seventy Eight Rupees Only');
    assert.match(amountInWords(66435).combined, /^Sixty Six Thousand Four Hundred and Thirty Five Rupees Only \(.+টাকা মাত্র\)$/);
});

console.log(`\n${n} passed`);
