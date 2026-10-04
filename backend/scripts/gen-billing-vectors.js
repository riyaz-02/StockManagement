/**
 * gen-billing-vectors.js — writes flutter_app/test/billing_vectors.json: random bills computed by the
 * server engine. The Dart test (test/billing_vectors_test.dart) must reproduce every number, so the
 * phone's live preview can never disagree with what the server saves.
 *   node scripts/gen-billing-vectors.js
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { computeInvoice } = require('../services/billingCalc');

let seed = 424242;
const rnd = () => { seed = (seed * 1664525 + 1013904223) % 4294967296; return seed / 4294967296; };
const pick = (a, b) => a + rnd() * (b - a);
const out = [];
while (out.length < 400) {
    const interstate = rnd() < 0.3;
    const items = Array.from({ length: 1 + Math.floor(rnd() * 4) }, (_, i) => {
        const metalType = rnd() < 0.75 ? 'Gold' : rnd() < 0.7 ? 'Silver' : 'Other';
        const netWt = Math.round(pick(0.2, 60) * 1000) / 1000;
        const rate = Math.round(pick(60, 12000) * 100) / 100;
        const it = { particulars: `Item ${i}`, metalType, netWt, rate: metalType === 'Other' ? rate : (rnd() < 0.2 ? rate : 0), makingCharge: rnd() < 0.3 ? 0 : Math.round(pick(0, 6000) * 100) / 100 };
        if (rnd() < 0.25) it.extras = [{ kind: 'Stone', name: 'Ruby', weight: 0.2, amount: Math.round(pick(50, 4000)) }];
        if (rnd() < 0.2) { it.certification = rnd() < 0.5 ? 'hallmark' : 'huid'; it.hallmarkCharge = Math.round(pick(20, 120)); if (it.certification === 'huid') it.huid = 'AB12CD'; }
        return it;
    });
    const goldRate = Math.round(pick(6000, 11000) * 100) / 100, silverRate = Math.round(pick(70, 130) * 100) / 100;
    // typed taxable amounts are built after the rates are known so they are never below the metal value
    items.forEach((it) => {
        if (rnd() < 0.3) {
            const r = it.rate || (it.metalType === 'Gold' ? goldRate : it.metalType === 'Silver' ? silverRate : 0);
            it.taxableOverride = Math.round((it.netWt * r + pick(0, 5000) + (it.extras ? it.extras[0].amount : 0)) * 100) / 100;
        }
    });
    const additionalCharges = rnd() < 0.3 ? Math.round(pick(0, 500)) : 0;
    const base = { items, goldRate, silverRate, interstate, additionalCharges };
    const full = computeInvoice(base);
    if (!full.ok) continue;
    const r1 = rnd();
    const discount = full.maxDiscount <= 0 ? (r1 < 0.3 ? 50 : 0) : r1 < 0.15 ? full.maxDiscount : r1 < 0.25 ? full.maxDiscount + 1 : Math.floor(rnd() * (full.maxDiscount + 1));
    const r = computeInvoice({ ...base, discount });
    out.push({
        input: { ...base, discount },
        expect: r.ok
            ? { ok: true, payable: r.totalPayableAmount, roundOff: r.roundOff, totalAmount: r.totalAmount, discountGiven: r.discountGiven, discountBeforeGst: r.discountBeforeGst,
                grossTaxable: r.grossTaxable, billBefore: r.billBeforeDiscount, maxDiscount: r.maxDiscount, metalValue: r.metalValue, additionalGst: r.additionalGst, taxable: r.gstSummary.total_taxable_amount,
                gst: r.gstSummary.total_gst,
                lines: r.items.map((l) => ({ name: l.particulars, taxable: l.taxable_amount, cgst: l.cgst, sgst: l.sgst, igst: l.igst || 0, total: l.total, making: l.making_charge, discount: l.discount || 0 })) }
            : { ok: false, maxDiscount: r.maxDiscount },
    });
}
const file = path.join(__dirname, '..', '..', 'flutter_app', 'test', 'billing_vectors.json');
fs.writeFileSync(file, JSON.stringify(out));
console.log(`wrote ${out.length} vectors (${out.filter((v) => v.expect.ok && v.input.discount > 0).length} with a discount, ${out.filter((v) => !v.expect.ok).length} refused) -> ${file}`);
