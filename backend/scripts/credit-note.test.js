// node scripts/credit-note.test.js
'use strict';
const assert = require('assert');
const CN = require('../services/creditNote');
let n = 0;
const t = (name, fn) => { fn(); n++; console.log('  ok  ', name); };
const inv = (o = {}) => ({ gst_type: 'CGST_SGST', invoice_date: '2026-08-10', items: [{ particulars: 'Gold Ring', hsn_code: '7113', metal_type: 'Gold', net_wt: 5, taxable_amount: 70000, cgst: 1050, sgst: 1050, item_id: 'a'.repeat(24) }, { particulars: 'Chain', taxable_amount: 30000 }], ...o });

t('return of a whole line: tax is 1.5% + 1.5% of the credited value', () => {
    const c = CN.compute(inv(), [{ index: 0 }]);
    assert.ok(c.ok);
    assert.strictEqual(c.taxable, 70000); assert.strictEqual(c.cgst, 1050); assert.strictEqual(c.sgst, 1050); assert.strictEqual(c.total, 72100);
    assert.strictEqual(c.lines[0].fullReturn, true);
});
t('inter-state invoice: IGST 3%', () => {
    const c = CN.compute(inv({ gst_type: 'IGST' }), [{ index: 1 }]);
    assert.strictEqual(c.igst, 900); assert.strictEqual(c.cgst, 0); assert.strictEqual(c.total, 30900);
});
t('partial amount (price adjustment): only that value and its tax; not a full return', () => {
    const c = CN.compute(inv(), [{ index: 0, taxable: 2000 }]);
    assert.strictEqual(c.taxable, 2000); assert.strictEqual(c.total, 2060); assert.strictEqual(c.lines[0].fullReturn, false);
});
t('several lines add up', () => {
    const c = CN.compute(inv(), [{ index: 0 }, { index: 1, taxable: 10000 }]);
    assert.strictEqual(c.taxable, 80000); assert.strictEqual(c.total, 82400);
});
t('earlier notes reduce what is left; cannot credit more than the line, nor a line twice', () => {
    assert.ok(!CN.compute(inv(), [{ index: 0, taxable: 70000.5 }]).ok);
    const c = CN.compute(inv(), [{ index: 0, taxable: 20000 }], { 0: 50000 });
    assert.ok(c.ok);
    assert.ok(!CN.compute(inv(), [{ index: 0, taxable: 20000.5 }], { 0: 50000 }).ok);
    assert.ok(!CN.compute(inv(), [{ index: 0 }], { 0: 70000 }).ok);
    assert.strictEqual(CN.compute(inv(), [{ index: 0 }], { 0: 50000 }).lines[0].fullReturn, false);   // part of it was credited before
});
t('bad input: unknown line, nothing chosen, zero / negative amount', () => {
    assert.ok(!CN.compute(inv(), [{ index: 9 }]).ok);
    assert.ok(!CN.compute(inv(), []).ok);
    assert.ok(!CN.compute(inv(), [{ index: 0, taxable: 0 }]).ok);
    assert.ok(!CN.compute(inv(), [{ index: 0, taxable: -5 }]).ok);
});
t('deadline: 30 November after the financial year of the invoice (April to March)', () => {
    assert.strictEqual(CN.deadline('2026-08-10'), '2027-11-30');
    assert.strictEqual(CN.deadline('2027-02-01'), '2027-11-30');     // Feb 2027 is FY 2026-27
    assert.strictEqual(CN.deadline('2026-03-31'), '2026-11-30');     // FY 2025-26
    assert.ok(CN.reducesTax('2026-08-10', '2027-11-30'));
    assert.ok(!CN.reducesTax('2026-08-10', '2027-12-01'));
});
t('rounding: paise are rounded per head so the total is the sum of its parts', () => {
    const c = CN.compute({ gst_type: 'CGST_SGST', items: [{ particulars: 'x', taxable_amount: 1234.57 }] }, [{ index: 0 }]);
    assert.strictEqual(c.cgst, 18.52); assert.strictEqual(c.sgst, 18.52); assert.strictEqual(c.total, Math.round((1234.57 + 18.52 * 2) * 100) / 100);
});
console.log(`\n${n} passed`);
