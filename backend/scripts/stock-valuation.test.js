// node scripts/stock-valuation.test.js
'use strict';
const assert = require('assert');
const V = require('../services/stockValuation');
const Rules = require('../services/stockRules');
let n = 0;
const t = (name, fn) => { fn(); n++; console.log('  ok  ', name); };
const R = () => Rules.defaults();

t('purity text: karat, thousandths and silver grades', () => {
    assert.strictEqual(V.purityPercent('22K'), 91.6);
    assert.strictEqual(V.purityPercent('916'), 91.6);
    assert.strictEqual(V.purityPercent('18K'), 75);
    assert.strictEqual(V.purityPercent('750'), 75);
    assert.strictEqual(V.purityPercent('24K'), 99.9);
    assert.strictEqual(V.purityPercent('925'), 92.5);
    assert.strictEqual(V.purityPercent('silver925'), 92.5);
    assert.strictEqual(V.purityPercent('916-22k'), 91.6);
    assert.strictEqual(V.purityPercent(''), 0);
});

t('net = gross - less; fine and final fine follow purity and wastage', () => {
    const x = V.computeStock({ gross: 10.5, less: 0.5, purity: '22K', wastage: 8.4, rate: 0 }, R());
    assert.strictEqual(x.net, 10);
    assert.strictEqual(x.fine, 9.16);
    assert.strictEqual(x.finalFine, 10);          // 10 x (91.6 + 8.4)%
});

t('default rules: metal valuation is on the FINAL fine weight (rule "valuation")', () => {
    const x = V.computeStock({ net: 10, purity: '22K', wastage: 8.4, rate: 7000 }, R());
    assert.strictEqual(x.metalValuation, 70000);
});

t('valuation basis changes with the rule: fine / net / gross', () => {
    const base = { gross: 11, less: 1, purity: '22K', wastage: 0, rate: 1000 };
    for (const [b, wt] of [['fine', 9.16], ['net', 10], ['gross', 11], ['finalFine', 9.16]]) {
        const r = R(); r.addStock.valuation = b;
        assert.strictEqual(V.computeStock(base, r).metalValuation, wt * 1000, b);
    }
});

t('labour and making each use their own basis', () => {
    const r = R(); r.addStock.labourCharges = 'gross'; r.addStock.makingCharges = 'net';
    const x = V.computeStock({ gross: 12, less: 2, purity: '22K', rate: 0, labourRate: 100, makingRate: 50 }, r);
    assert.strictEqual(x.labourTotal, 1200);
    assert.strictEqual(x.makingTotal, 500);
    assert.strictEqual(x.makingForBilling, 1700);
});

t('customer wastage adds weight on the chosen basis and is valued with the metal', () => {
    const r = R(); r.addStock.customerWastage = 'net'; r.addStock.valuation = 'net';
    const x = V.computeStock({ net: 10, purity: '22K', custWastage: 2, rate: 1000 }, r);
    assert.strictEqual(x.custWastageWt, 0.2);
    assert.strictEqual(x.valuationWt, 10.2);
    assert.strictEqual(x.metalValuation, 10200);
});

t('GST: 3% on metal + labour + making + stones; hallmark fee has its own 18% when the rule is on', () => {
    const x = V.computeStock({ net: 10, purity: '22K', rate: 1000, makingRate: 100, stoneValue: 1000, certification: 'huid', pieces: 1 }, R());
    // metal 10 x 916/1000... default valuation finalFine = 9.16 -> 9,160 ; making 1,000 ; stones 1,000 -> 11,160
    assert.strictEqual(x.metalValuation, 9160);
    assert.strictEqual(x.goodsGst, 334.8);
    assert.strictEqual(x.hallmarkCharge, 45);
    assert.strictEqual(x.hallmarkGst, 8.1);
    assert.strictEqual(x.taxable, 11205);
    assert.strictEqual(x.finalPrice, r2(11205 + 334.8 + 8.1));
    const off = R(); off.addStock.hallmarkGst = false;
    assert.strictEqual(V.computeStock({ net: 10, purity: '22K', certification: 'huid' }, off).hallmarkGst, 0);
    assert.strictEqual(V.computeStock({ net: 10, purity: '22K', certification: 'huid', interstate: true }, R()).hallmarkGst, 8.1);
    assert.strictEqual(V.computeStock({ net: 10, purity: '22K', certification: 'none' }, R()).hallmarkCharge, 0);
});

t('hallmark per gram uses the net weight; per piece uses the piece count', () => {
    const r = R(); r.hallmark.type = 'perGram'; r.hallmark.charge = 2;
    assert.strictEqual(V.computeStock({ net: 5, purity: '22K', certification: 'hallmarked', pieces: 3 }, r).hallmarkCharge, 10);
    const r2_ = R(); r2_.hallmark.type = 'perPiece';
    assert.strictEqual(V.computeStock({ net: 5, purity: '22K', certification: 'hallmarked', pieces: 3 }, r2_).hallmarkCharge, 135);
});

t('nothing entered gives zeros, never NaN; negative and text inputs are treated as 0', () => {
    const x = V.computeStock({ gross: 'abc', less: -3, rate: -5 }, R());
    for (const v of Object.values(x)) assert.ok(Number.isFinite(v), JSON.stringify(x));
    assert.strictEqual(x.finalPrice, 0);
});

t('purchase: wastage basis, final valuation basis and labour basis follow the Purchase rules', () => {
    const r = R();                                            // defaults: wastage by net, valuation net, labour by fine
    const x = V.computePurchase({ gross: 100, purity: '22K', wastage: 2, rate: 10000, labourRate: 50 }, r);
    assert.strictEqual(x.fine, 91.6);
    assert.strictEqual(x.wastageWt, 2);                       // 2% of NET 100
    assert.strictEqual(x.finalFine, 93.6);
    assert.strictEqual(x.metalValuation, 1000000);            // valued on net 100
    assert.strictEqual(x.labourTotal, 4580);                  // labour on fine 91.6
    assert.strictEqual(x.taxable, 1004580);
    r.purchase.finalValuation = 'finalFine'; r.purchase.wastage = 'fine'; r.purchase.labourCharges = 'gross';
    const y = V.computePurchase({ gross: 100, less: 10, purity: '22K', wastage: 2, rate: 10000, labourRate: 50 }, r);
    assert.strictEqual(y.net, 90);
    assert.strictEqual(y.fine, 82.44);
    assert.strictEqual(y.wastageWt, 1.649);                   // 2% of fine 82.44
    assert.strictEqual(y.valuationWt, 84.089);
    assert.strictEqual(y.labourTotal, 5000);                  // gross 100 x 50
});

t('purchase: hallmark fee is added; zero input gives zero, never NaN', () => {
    const x = V.computePurchase({ net: 10, purity: '22K', rate: 1000, certification: 'huid', pieces: 2 }, R());
    assert.strictEqual(x.hallmarkCharge, 90);
    const z = V.computePurchase({}, R());
    for (const v of Object.values(z)) assert.ok(Number.isFinite(v));
});

t('old metal: valued on the received-valuation basis (default fine wt); deduction comes off the purity', () => {
    const r = R();
    const x = V.computeOldMetal({ gross: 50, less: 2, purity: '22K', deduction: 3.6, rate: 10000 }, r);
    assert.strictEqual(x.net, 48);
    assert.strictEqual(x.fine, 43.968);
    assert.strictEqual(x.finalFine, 42.24);              // 48 x (91.6 - 3.6)%
    assert.strictEqual(x.basis, 'fine');
    assert.strictEqual(x.amount, 439680);
    r.oldMetal.receivedValuation = 'finalFine';
    assert.strictEqual(V.computeOldMetal({ net: 48, purity: '22K', deduction: 3.6, rate: 10000 }, r).amount, 422400);
});

t('raw metal purchase uses its own basis (default net wt); empty input gives zeros', () => {
    const x = V.computeOldMetal({ kind: 'raw', net: 10, purity: '24K', rate: 1000 }, R());
    assert.strictEqual(x.basis, 'net');
    assert.strictEqual(x.amount, 10000);
    for (const v of Object.values(V.computeOldMetal({}, R()))) assert.ok(v === 'fine' || Number.isFinite(v));
});

t('purchase hallmark GST: goods at 3%, the fee carries its own GST when the rule is on (CGST+SGST 18% total, IGST 18%)', () => {
    const inp = { net: 10, purity: '24K', rate: 1000, pieces: 2, certification: 'huid' };
    const a = V.computePurchase(inp, R());
    assert.strictEqual(a.hallmarkCharge, 90);
    assert.strictEqual(a.goodsTaxable, 10000);
    assert.strictEqual(a.hallmarkGst, 16.2);
    assert.strictEqual(V.computePurchase({ ...inp, interstate: true }, R()).hallmarkGst, 16.2);
    const off = R(); off.purchase.hallmarkGst = false;
    assert.strictEqual(V.computePurchase(inp, off).hallmarkGst, 0);
    assert.strictEqual(V.computePurchase({ ...inp, certification: 'none' }, R()).hallmarkGst, 0);
});

function r2(n_) { return Math.round((n_ + Number.EPSILON) * 100) / 100; }
console.log(`\n${n} passed`);
