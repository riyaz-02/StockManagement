/**
 * gst-reports.test.js — unit tests for services/gstReports.js (periods, due dates, reminders, ITC, summaries).
 *   node scripts/gst-reports.test.js
 */
'use strict';
const assert = require('assert');
const G = require('../services/gstReports');
const { computeInvoice } = require('../services/billingCalc');

let n = 0;
const t = (name, fn) => { fn(); n++; console.log('  ok   ' + name); };

// ── periods ──
t('period keys: monthly, and financial-year quarters (Apr-Jun = Q1)', () => {
    assert.strictEqual(G.periodKey('monthly', '2026-08-15'), '2026-08');
    assert.strictEqual(G.periodKey('quarterly', '2026-04-01'), '2026-Q1');
    assert.strictEqual(G.periodKey('quarterly', '2026-06-30'), '2026-Q1');
    assert.strictEqual(G.periodKey('quarterly', '2026-08-15'), '2026-Q2');
    assert.strictEqual(G.periodKey('quarterly', '2026-12-31'), '2026-Q3');
    assert.strictEqual(G.periodKey('quarterly', '2027-01-01'), '2026-Q4');       // January belongs to Q4 of the FY that began the April before
    assert.strictEqual(G.periodKey('quarterly', '2027-03-31'), '2026-Q4');
});

t('period ranges', () => {
    assert.deepStrictEqual([G.periodRange('2026-Q4').from, G.periodRange('2026-Q4').to], ['2027-01-01', '2027-03-31']);
    assert.deepStrictEqual([G.periodRange('2028-02').from, G.periodRange('2028-02').to], ['2028-02-01', '2028-02-29']);   // leap year
    assert.strictEqual(G.periodRange('2026-13'), null);
    assert.strictEqual(G.periodRange('nonsense'), null);
    assert.strictEqual(G.nextPeriodKey('2026-12'), '2027-01');
    assert.strictEqual(G.nextPeriodKey('2026-Q4'), '2027-Q1');
    assert.deepStrictEqual(G.listPeriods('quarterly', '2026-04-01', '2027-03-31'), ['2026-Q1', '2026-Q2', '2026-Q3', '2026-Q4']);
});

// ── due dates ──
t('due dates: monthly (11th / 20th), QRMP quarterly (13th / 22nd or 24th), PMT-06 (25th), GSTR-9 (31 Dec)', () => {
    assert.strictEqual(G.dueDate('GSTR-1', '2026-08'), '2026-09-11');
    assert.strictEqual(G.dueDate('GSTR-3B', '2026-08'), '2026-09-20');
    assert.strictEqual(G.dueDate('GSTR-3B', '2026-12'), '2027-01-20');
    assert.strictEqual(G.dueDate('GSTR-1', '2026-Q2', { frequency: 'quarterly' }), '2026-10-13');
    assert.strictEqual(G.dueDate('GSTR-3B', '2026-Q2', { frequency: 'quarterly', stateCode: '19' }), '2026-10-24');   // West Bengal
    assert.strictEqual(G.dueDate('GSTR-3B', '2026-Q2', { frequency: 'quarterly', stateCode: '27' }), '2026-10-22');   // Maharashtra
    assert.strictEqual(G.dueDate('GSTR-3B', '2026-Q4', { frequency: 'quarterly', stateCode: '19' }), '2027-04-24');
    assert.strictEqual(G.dueDate('PMT-06', '2026-07'), '2026-08-25');
    assert.strictEqual(G.dueDate('GSTR-9', 'FY2026'), '2027-12-31');
    for (const s of ['22', '23', '24', '26', '27', '29', '30', '31', '32', '33', '34', '35', '36', '37']) assert.strictEqual(G.qrmpDay3b(s), 22, s);
    for (const s of ['01', '07', '09', '10', '19', '20', '21', '08', '38']) assert.strictEqual(G.qrmpDay3b(s), 24, s);
});

t('obligations: monthly has GSTR-1 + GSTR-3B each month; quarterly adds PMT-06 for the first two months of a quarter', () => {
    const m = G.obligations({ frequency: 'monthly' }, '2026-09-01', '2026-09-30');
    assert.deepStrictEqual(m.map((o) => [o.type, o.period, o.due]), [['GSTR-1', '2026-08', '2026-09-11'], ['GSTR-3B', '2026-08', '2026-09-20']]);
    const q = G.obligations({ frequency: 'quarterly', stateCode: '19' }, '2026-10-01', '2026-10-31');
    assert.deepStrictEqual(q.map((o) => [o.type, o.period, o.due]), [['GSTR-1', '2026-Q2', '2026-10-13'], ['GSTR-3B', '2026-Q2', '2026-10-24']]);
    const q2 = G.obligations({ frequency: 'quarterly' }, '2026-08-01', '2026-08-31');
    assert.deepStrictEqual(q2.map((o) => [o.type, o.period, o.due]), [['PMT-06', '2026-07', '2026-08-25']]);
    const yr = G.obligations({ frequency: 'monthly' }, '2027-12-01', '2027-12-31');
    assert.deepStrictEqual(yr.map((o) => [o.type, o.period]).filter((x) => x[0] === 'GSTR-9'), [['GSTR-9', 'FY2026']]);
});

t('status: filed / overdue / due-soon / upcoming, matched against recorded filings', () => {
    const s = { frequency: 'monthly' };
    const filings = [{ returnType: 'GSTR-1', period: '2026-08', filedOn: '2026-09-09' }];
    const list = G.statusList(s, filings, '2026-09-14');
    const get = (type, period) => list.find((o) => o.type === type && o.period === period);
    assert.strictEqual(get('GSTR-1', '2026-08').status, 'filed');
    assert.strictEqual(get('GSTR-3B', '2026-08').status, 'due-soon');
    assert.strictEqual(get('GSTR-3B', '2026-08').daysLeft, 6);
    assert.strictEqual(get('GSTR-1', '2026-09').status, 'upcoming');
    assert.strictEqual(get('GSTR-3B', '2026-07').status, 'overdue');                    // due 20 Aug, not filed
    assert.strictEqual(G.statusList(s, [], '2026-09-21').find((o) => o.type === 'GSTR-3B' && o.period === '2026-08').status, 'overdue');
});

t('periods before "track filings from" are not followed (no false overdue), but a filing recorded for them still shows', () => {
    const s = { frequency: 'monthly', remindersFrom: '2026-08' };
    const list = G.statusList(s, [{ returnType: 'GSTR-1', period: '2026-06' }], '2026-09-14');
    const get = (type, period) => list.find((o) => o.type === type && o.period === period);
    assert.strictEqual(get('GSTR-3B', '2026-07').status, 'untracked');
    assert.strictEqual(get('GSTR-1', '2026-06').status, 'filed');
    assert.strictEqual(get('GSTR-3B', '2026-08').status, 'due-soon');
    const a = G.alerts(s, [], '2026-09-14');
    assert.ok(a.every((x) => x.period >= '2026-08'), 'no alert for untracked periods');
    assert.ok(G.pendingReminders({ ...s, reminders: { enabled: true, daysBefore: [7, 3, 1, 0], overdue: true } }, [], '2026-09-14', new Set()).every((r) => r.obligation.period >= '2026-08'));
});

t('alerts: overdue + anything within the reminder lead time; never a filed return', () => {
    const s = { frequency: 'monthly', reminders: { daysBefore: [7, 3, 1, 0] } };
    const a = G.alerts(s, [{ returnType: 'GSTR-1', period: '2026-08' }], '2026-09-14');
    assert.ok(a.every((x) => !(x.type === 'GSTR-1' && x.period === '2026-08')));
    const b3 = a.find((x) => x.type === 'GSTR-3B' && x.period === '2026-08');
    assert.ok(b3 && b3.severity === 'info' && b3.daysLeft === 6);
    assert.strictEqual(G.alerts(s, [], '2026-09-18').find((x) => x.type === 'GSTR-3B' && x.period === '2026-08').severity, 'urgent');
    assert.strictEqual(G.alerts(s, [], '2026-09-22').find((x) => x.type === 'GSTR-3B' && x.period === '2026-08').severity, 'overdue');
});

t('reminders: sent once per lead time; if the server slept through some, ONE message covers them; overdue daily', () => {
    const s = { frequency: 'monthly', reminders: { enabled: true, daysBefore: [7, 3, 1, 0], overdue: true } };
    const sent = new Set();
    const mark = (rs) => rs.forEach((r) => r.keys.forEach((k) => sent.add(k)));
    let r = G.pendingReminders(s, [], '2026-09-04', sent).filter((x) => x.obligation.type === 'GSTR-1');       // 7 days before the 11th
    assert.strictEqual(r.length, 1); assert.match(r[0].title, /due in 7 days/); mark(r);
    assert.strictEqual(G.pendingReminders(s, [], '2026-09-04', sent).filter((x) => x.obligation.type === 'GSTR-1').length, 0);   // not again
    assert.strictEqual(G.pendingReminders(s, [], '2026-09-06', sent).filter((x) => x.obligation.type === 'GSTR-1').length, 0);   // nothing new yet
    r = G.pendingReminders(s, [], '2026-09-08', sent).filter((x) => x.obligation.type === 'GSTR-1');                             // 3 days left
    assert.strictEqual(r.length, 1); assert.match(r[0].title, /due in 3 days/); mark(r);
    // the server slept: first seen with 1 day left -> a single message, covering the 1-day lead time
    const slept = G.pendingReminders(s, [], '2026-09-10', new Set()).filter((x) => x.obligation.type === 'GSTR-1');
    assert.strictEqual(slept.length, 1); assert.match(slept[0].title, /due tomorrow/); assert.strictEqual(slept[0].keys.length, 3);
    r = G.pendingReminders(s, [], '2026-09-11', sent).filter((x) => x.obligation.type === 'GSTR-1'); assert.match(r[0].title, /due TODAY/); mark(r);
    r = G.pendingReminders(s, [], '2026-09-12', sent).filter((x) => x.obligation.type === 'GSTR-1'); assert.match(r[0].title, /OVERDUE/); mark(r);
    assert.strictEqual(G.pendingReminders(s, [], '2026-09-12', sent).filter((x) => x.obligation.type === 'GSTR-1').length, 0);
    assert.strictEqual(G.pendingReminders(s, [], '2026-09-13', sent).filter((x) => x.obligation.type === 'GSTR-1').length, 1);    // overdue again next day
    // filed -> silence; disabled -> silence
    assert.strictEqual(G.pendingReminders(s, [{ returnType: 'GSTR-1', period: '2026-08' }], '2026-09-11', new Set()).filter((x) => x.obligation.type === 'GSTR-1').length, 0);
    assert.strictEqual(G.pendingReminders({ ...s, reminders: { enabled: false } }, [], '2026-09-11', new Set()).length, 0);
});

// ── ITC ──
t('ITC: IGST credit pays IGST, then CGST, then SGST', () => {
    const u = G.utilise({ igst: 100, cgst: 200, sgst: 300 }, { igst: 450, cgst: 0, sgst: 0 });
    assert.deepStrictEqual(u.used.igst, { igst: 100, cgst: 200, sgst: 150 });
    assert.deepStrictEqual(u.cash, { igst: 0, cgst: 0, sgst: 150 });
    assert.deepStrictEqual(u.remaining, { igst: 0, cgst: 0, sgst: 0 });
});

t('ITC: CGST credit can pay CGST then IGST, but NEVER SGST (and SGST credit never CGST)', () => {
    const u = G.utilise({ igst: 50, cgst: 100, sgst: 100 }, { igst: 0, cgst: 400, sgst: 0 });
    assert.deepStrictEqual(u.used.cgst, { cgst: 100, igst: 50 });
    assert.deepStrictEqual(u.cash, { igst: 0, cgst: 0, sgst: 100 });          // SGST liability stays: CGST credit cannot pay it
    assert.deepStrictEqual(u.remaining, { igst: 0, cgst: 250, sgst: 0 });
    const v = G.utilise({ igst: 0, cgst: 100, sgst: 0 }, { igst: 0, cgst: 0, sgst: 500 });
    assert.deepStrictEqual(v.cash, { igst: 0, cgst: 100, sgst: 0 });
    assert.deepStrictEqual(v.remaining, { igst: 0, cgst: 0, sgst: 500 });
});

t('ITC: PROPERTY - 3000 random cases conserve money and never break the ordering rules', () => {
    let seed = 7;
    const rnd = () => { seed = (seed * 1664525 + 1013904223) % 4294967296; return seed / 4294967296; };
    const amt = () => (rnd() < 0.25 ? 0 : Math.round(rnd() * 100000) / 100);
    for (let i = 0; i < 3000; i++) {
        const L = { igst: amt(), cgst: amt(), sgst: amt() }, C = { igst: amt(), cgst: amt(), sgst: amt() };
        const u = G.utilise(L, C);
        const usedI = u.used.igst.igst + u.used.igst.cgst + u.used.igst.sgst, usedC = u.used.cgst.cgst + u.used.cgst.igst, usedS = u.used.sgst.sgst + u.used.sgst.igst;
        assert.ok(Math.abs(usedI + u.remaining.igst - C.igst) < 0.011 && Math.abs(usedC + u.remaining.cgst - C.cgst) < 0.011 && Math.abs(usedS + u.remaining.sgst - C.sgst) < 0.011, `case ${i}: credit conserved`);
        assert.ok(Math.abs(u.used.igst.igst + u.used.cgst.igst + u.used.sgst.igst + u.cash.igst - L.igst) < 0.011, `case ${i}: IGST liability`);
        assert.ok(Math.abs(u.used.igst.cgst + u.used.cgst.cgst + u.cash.cgst - L.cgst) < 0.011, `case ${i}: CGST liability (only IGST + CGST credit)`);
        assert.ok(Math.abs(u.used.igst.sgst + u.used.sgst.sgst + u.cash.sgst - L.sgst) < 0.011, `case ${i}: SGST liability (only IGST + SGST credit)`);
        for (const v of [...Object.values(u.cash), ...Object.values(u.remaining)]) assert.ok(v >= -0.0001, `case ${i}: never negative`);
        if (u.cash.sgst > 0.005) assert.ok(u.remaining.sgst < 0.006 && u.remaining.igst < 0.006, `case ${i}: SGST cash only when SGST/IGST credit is used up`);
        if (u.cash.cgst > 0.005) assert.ok(u.remaining.cgst < 0.006 && u.remaining.igst < 0.006, `case ${i}: CGST cash only when CGST/IGST credit is used up`);
        if (u.cash.igst > 0.005) assert.ok(u.remaining.igst < 0.006 && u.remaining.cgst < 0.006 && u.remaining.sgst < 0.006, `case ${i}: IGST cash only when all credit is used up`);
    }
});

t('ITC ledger: unused credit carries forward; the next period uses it first', () => {
    const z = { igst: 0, cgst: 0, sgst: 0 };
    const led = G.itcLedger([
        { key: '2026-04', liability: { igst: 0, cgst: 100, sgst: 100 }, itc: { igst: 0, cgst: 300, sgst: 300 } },
        { key: '2026-05', liability: { igst: 0, cgst: 500, sgst: 500 }, itc: z },
        { key: '2026-06', liability: { igst: 0, cgst: 50, sgst: 50 }, itc: { igst: 0, cgst: 10, sgst: 10 } },
    ], { igst: 0, cgst: 50, sgst: 0 });
    assert.deepStrictEqual(led[0].opening, { igst: 0, cgst: 50, sgst: 0 });
    assert.deepStrictEqual(led[0].closing, { igst: 0, cgst: 250, sgst: 200 });     // 350 - 100 ; 300 - 100
    assert.deepStrictEqual(led[1].cash, { igst: 0, cgst: 250, sgst: 300 });        // 500 - 250 ; 500 - 200
    assert.deepStrictEqual(led[1].closing, z);
    assert.deepStrictEqual(led[2].cash, { igst: 0, cgst: 40, sgst: 40 });
});

// ── summaries ──
const doc = (number, date, items, extra = {}, opts = {}) => {
    const calc = computeInvoice({ items, goldRate: 9000, silverRate: 100, interstate: !!opts.interstate, additionalCharges: opts.additional || 0, discount: opts.discount || 0, paidAmount: opts.paid == null ? 0 : opts.paid, discountMode: opts.legacy ? 'after_gst' : undefined });
    assert.ok(calc.ok, calc.error);
    return {
        _id: 'id' + number, invoice_number: number, invoice_date: date, customer_name: extra.name || 'Cust ' + number, customer_mobile: '9000000000', place_of_supply: opts.interstate ? '27-Maharashtra' : '19-West Bengal',
        items: calc.items, additional_charges: calc.additionalCharges, additional_charges_gst: calc.additionalGst, total_amount: calc.totalAmount, discount: calc.discount, round_off: calc.roundOff,
        total_payable_amount: calc.totalPayableAmount, paid_amount: calc.paidAmount, gst_summary: calc.gstSummary, status: extra.status || 'delivered',
        discount_mode: opts.legacy ? undefined : 'before_gst', discount_given: calc.discountGiven, gst_type: calc.gstType, branch_id: extra.branch || 'main', branch_name: 'Main branch',
        tds_applicable: calc.tdsApplicable, tds_amount: calc.tdsAmount, tds_rate: calc.tdsRate,
        payment_history: calc.paidAmount > 0 ? [{ amount: calc.paidAmount, payment_mode: extra.mode || 'Cash', payment_date: date, payment_time: '10:00:00', created_at: new Date(date + 'T05:00:00Z') }] : [],
    };
};
const gold = (o = {}) => ({ particulars: 'Gold Ring', metalType: 'Gold', netWt: 10, rate: 9000, makingCharge: 2000, purity: '22K', ...o });
const silver = (o = {}) => ({ particulars: 'Silver Chain', metalType: 'Silver', netWt: 100, rate: 100, makingCharge: 500, ...o });

const docs = () => [
    doc('1001', '2026-08-03', [gold(), silver()], {}, { additional: 500, paid: 100000 }),                                  // intra, 2 metals, taxed extra charges
    doc('1002', '2026-08-10', [gold({ particulars: 'Gold Ring (Hallmarked)', certification: 'hallmark', hallmarkCharge: 45 })], {}, { interstate: true, discount: 500 }),   // inter, discount before GST
    doc('1003', '2026-08-12', [gold({ netWt: 20 })], {}, { interstate: true }),                                               // inter and large (> 1 lakh)
    doc('1004', '2026-08-20', [silver()], { status: 'cancelled' }),                                                           // cancelled: excluded from figures
    doc('1005', '2026-08-25', [gold({ particulars: 'Gold Chain', netWt: 5 })], {}, { legacy: true, additional: 100, discount: 50 }),   // old website rule
    doc('1006', '2026-09-02', [gold()], {}, {}),                                                                              // next month
    doc('BR2-0001', '2026-08-15', [silver()], { branch: 'b2' }, {}),                                                          // another branch's series
];

t('summary: totals reconcile (taxable, GST by head, invoice value); cancelled invoices are excluded but counted', () => {
    const s = G.summarise(docs(), { from: '2026-08-01', to: '2026-08-31' });
    assert.strictEqual(s.totals.invoices, 5);
    assert.strictEqual(s.notes.cancelled, 1);
    const sum = (k) => G.r2(s.rows.reduce((a, r) => a + r[k], 0));
    assert.strictEqual(s.totals.taxable, sum('taxable'));
    assert.strictEqual(s.totals.tax, sum('tax'));
    assert.strictEqual(s.totals.invoiceValue, sum('value'));
    assert.ok(Math.abs(s.totals.tax - G.r2(s.totals.cgst + s.totals.sgst + s.totals.igst)) < 0.006);
    assert.ok(Math.abs(s.totals.tax - s.totals.taxable * 0.03) < 0.06 + 0.02 * 5 - 0.06, `GST is 3% of taxable (${s.totals.tax} vs ${s.totals.taxable * 0.03})`);
    assert.strictEqual(s.totals.inter, 2);
    assert.strictEqual(s.totals.intra, 3);
});

t('summary: metal-wise weight/making/taxable; the metal table + extra-charges row reconcile to the invoice totals', () => {
    const s = G.summarise(docs(), { from: '2026-08-01', to: '2026-08-31' });
    const goldRow = s.byMetal.find((m) => m.metal === 'Gold'), silverRow = s.byMetal.find((m) => m.metal === 'Silver'), extra = s.byMetal.find((m) => m.metal === 'Extra charges');
    assert.strictEqual(goldRow.weight, 10 + 10 + 20 + 5);
    assert.strictEqual(silverRow.weight, 100 + 100);
    assert.ok(extra && extra.taxable === 500, 'taxed extra charges (500) shown as their own row');
    const tax = G.r2(s.byMetal.reduce((a, m) => a + m.taxable, 0));
    // the old-rule invoice's 100 of extra charges is untaxed, so it is in no row and no total
    assert.ok(Math.abs(tax - s.totals.taxable) <= 0.03, `metal rows ${tax} vs totals ${s.totals.taxable}`);
    assert.strictEqual(s.notes.untaxedExtraCharges, 1);
    assert.strictEqual(s.notes.untaxedExtraAmount, 100);
    assert.strictEqual(s.notes.discountAfterGst, 1);
    assert.ok(goldRow.avgRate > 8900 && goldRow.avgRate < 9100);
    assert.ok(goldRow.making > 0);
});

t('summary: making charge includes the making hidden inside a typed taxable amount', () => {
    const s = G.summarise([doc('2001', '2026-08-05', [gold({ netWt: 10, rate: 9000, makingCharge: 0, taxableOverride: 93000 })])], { from: '2026-08-01', to: '2026-08-31' });
    assert.strictEqual(s.totals.making, 3000);
    assert.strictEqual(s.byItem[0].item, 'Gold Ring');                              // "+ Making Charge" is stripped for item-wise grouping
});

t('summary: item-wise groups names without the (Hallmarked)/(HUID) suffix; purity-wise; payments by mode', () => {
    const d = docs();
    d[0].payment_history.push({ amount: 5000, payment_mode: 'Online', payment_date: '2026-08-04', created_at: new Date('2026-08-04T05:00:00Z') });
    const s = G.summarise(d, { from: '2026-08-01', to: '2026-08-31' });
    const ring = s.byItem.find((i) => i.item === 'Gold Ring');
    assert.strictEqual(ring.pieces, 3);                                               // 1001, 1002 (Hallmarked), 1003
    assert.ok(s.byPurity.find((p) => p.metal === 'Gold' && p.purity === '22K'));
    assert.ok(s.byPurity.find((p) => p.metal === 'Silver' && p.purity === 'Not recorded'));
    assert.strictEqual(s.payments.find((p) => p.mode === 'Online').amount, 5000);
    assert.ok(s.payments.find((p) => p.mode === 'Cash').amount >= 100000);
});

t('GSTR-1 tables: B2CS by place, B2CL (inter-state invoices above the threshold), HSN totals, document series', () => {
    const s = G.summarise(docs(), { from: '2026-08-01', to: '2026-08-31', b2clThreshold: 100000 });
    assert.strictEqual(s.gstr1.b2cl.length, 1);
    assert.strictEqual(s.gstr1.b2cl[0].number, '1003');
    const wb = s.gstr1.b2cs.find((x) => x.place === '19-West Bengal'), mh = s.gstr1.b2cs.find((x) => x.place === '27-Maharashtra');
    assert.ok(wb && wb.cgst > 0 && wb.igst === 0);
    assert.ok(mh && mh.igst > 0 && mh.cgst === 0);                                    // 1002 is small, so it is in B2CS; 1003 is in B2CL
    // B2CS + B2CL together are all the taxable value
    const tot = G.r2(s.gstr1.b2cs.reduce((a, x) => a + x.taxable, 0) + s.gstr1.b2cl.reduce((a, x) => a + x.taxable, 0));
    assert.ok(Math.abs(tot - s.totals.taxable) <= 0.03, `${tot} vs ${s.totals.taxable}`);
    const igstAll = G.r2(s.gstr1.b2cs.reduce((a, x) => a + x.igst, 0) + s.gstr1.b2cl.reduce((a, x) => a + x.igst, 0));
    assert.ok(Math.abs(igstAll - s.totals.igst) <= 0.03);
    // HSN table reconciles to the totals (extra charges are filed under the first line's HSN)
    const h = s.gstr1.hsn;
    assert.ok(Math.abs(h.reduce((a, x) => a + x.taxable, 0) - s.totals.taxable) <= 0.03);
    assert.ok(Math.abs(h.reduce((a, x) => a + x.cgst + x.sgst + x.igst, 0) - (s.totals.tax - 0)) <= 0.06);
    assert.strictEqual(h[0].uqc, 'GMS');
    // documents: the main series 1001..1005 (1004 cancelled), and the BR2 series
    const main = s.gstr1.docs.find((d) => d.series === 'MAIN'), br = s.gstr1.docs.find((d) => d.series === 'BR2');
    assert.deepStrictEqual([main.from, main.to, main.total, main.cancelled, main.net], ['1001', '1005', 5, 1, 4]);
    assert.deepStrictEqual([br.from, br.to, br.total], ['BR2-0001', 'BR2-0001', 1]);
});

t('summary filters: metal (line-level), tax type, amount range, branch, search; each narrows the figures', () => {
    const base = { from: '2026-08-01', to: '2026-08-31' };
    const all = G.summarise(docs(), base);
    const s = G.summarise(docs(), { ...base, metal: 'silver' });
    assert.ok(s.lineBased);
    assert.strictEqual(s.byMetal.length, 1);
    assert.strictEqual(s.totals.weight, 200);
    assert.ok(s.totals.taxable < all.totals.taxable);
    assert.strictEqual(G.summarise(docs(), { ...base, taxType: 'inter' }).totals.invoices, 2);
    assert.strictEqual(G.summarise(docs(), { ...base, taxType: 'intra' }).totals.invoices, 3);
    assert.strictEqual(G.summarise(docs(), { ...base, min: 150000 }).totals.invoices, 1);
    assert.strictEqual(G.summarise(docs(), { ...base, branch: 'b2' }).totals.invoices, 1);
    assert.strictEqual(G.summarise(docs(), { ...base, q: 'cust 1003' }).totals.invoices, 1);
    assert.strictEqual(G.summarise(docs(), { ...base, q: 'nobody' }).totals.invoices, 0);
});

t('trend grouping: day / week / month / quarter', () => {
    const d = docs();
    assert.deepStrictEqual(G.summarise(d, { from: '2026-08-01', to: '2026-09-30', group: 'month' }).trend.map((x) => [x.key, x.invoices]), [['2026-08', 5], ['2026-09', 1]]);
    assert.deepStrictEqual(G.summarise(d, { from: '2026-04-01', to: '2027-03-31', group: 'quarter' }).trend.map((x) => x.key), ['2026-Q2']);
    assert.strictEqual(G.summarise(d, { from: '2026-08-01', to: '2026-08-31', group: 'day' }).trend.length, 5);
    const wk = G.summarise(d, { from: '2026-08-01', to: '2026-08-31', group: 'week' }).trend;
    assert.ok(wk.every((x) => new Date(x.key + 'T00:00:00Z').getUTCDay() === 1), 'weeks start on Monday');
});

t('register: sorted and paged by any column', () => {
    const rows = G.summarise(docs(), { from: '2026-08-01', to: '2026-09-30' }).rows;
    const byValueDesc = G.registerPage(rows, { sort: 'value', dir: 'desc' });
    assert.ok(byValueDesc.rows.every((r, i, a) => i === 0 || a[i - 1].value >= r.value));
    assert.strictEqual(byValueDesc.total, 7 - 1);
    const byNumAsc = G.registerPage(rows, { sort: 'invoiceNumber', dir: 'asc' });
    assert.strictEqual(byNumAsc.rows[0].invoiceNumber, '1001');
    assert.strictEqual(G.registerPage(rows, { limit: 2, page: 2 }).rows.length, 2);
    assert.strictEqual(G.registerPage(rows, { sort: 'evil; drop' }).rows.length, 6);      // unknown sort keys fall back safely
});

t('legacy website invoices (no purity, no discount_mode, untaxed extras, string numbers) are summarised without error', () => {
    const legacy = { invoice_number: '1401', invoice_date: '2025-06-10', customer_name: 'A', place_of_supply: '19-West Bengal', items: [{ particulars: 'Gold Chain', hsn_code: '7113', metal_type: 'Gold', net_wt: '0.08', rate: '9190', making_charge: '64', taxable_amount: '799.2', cgst: '11.99', sgst: '11.99', total: '823.18' }], additional_charges: '55', discount: '78', total_payable_amount: '800', paid_amount: '800', gst_summary: { total_taxable_amount: '799.2', total_cgst: '11.99', total_sgst: '11.99', total_gst: '23.98' }, status: 'delivered' };
    const block = { invoice_number: '1-100', invoice_date: '2025-06-13', customer_name: 'Block', items: [{ particulars: 'Mixed', metal_type: 'Gold', net_wt: 42.74, rate: 0, making_charge: 0, taxable_amount: 0, cgst: 0, sgst: 0, total: 0 }], total_payable_amount: 0, gst_summary: {}, status: 'delivered' };
    const s = G.summarise([legacy, block], { from: '2025-06-01', to: '2025-06-30' });
    assert.strictEqual(s.totals.invoices, 2);
    assert.strictEqual(s.totals.taxable, 799.2);
    assert.strictEqual(s.totals.tax, 23.98);
    assert.strictEqual(s.byMetal[0].weight, G.r3(0.08 + 42.74));
    assert.strictEqual(s.notes.untaxedExtraCharges, 1);
});

t('checks before filing: finds a missing address (50,000+), missing PAN (2 lakh+), a gap in the numbering, cash 2 lakh+ in a day, untaxed extras', () => {
    const d = [
        { ...doc('2001', '2026-08-03', [gold()], {}, { paid: 0 }), customer_address: '' },                                   // 66,435 with no address
        { ...doc('2002', '2026-08-04', [gold()], {}, { paid: 0 }), customer_address: '12 Road, Howrah' },
        { ...doc('2004', '2026-08-05', [gold({ netWt: 100, rate: 2000, makingCharge: 0 })], {}, { paid: 0 }), customer_address: '1 Road, Howrah', customer_pan: '' },   // 2,06,000, no PAN
        { ...doc('2005', '2026-08-06', [gold()], {}, { legacy: true, additional: 100 }), customer_address: '5 Lane, Howrah' },     // old rule: extra charges untaxed
    ];
    // 2003 is missing from the series; and a buyer paid 2 lakh+ in cash in one day over two invoices
    d[1].customer_mobile = '9811111111'; d[2].customer_mobile = '9811111111';
    d[1].payment_history = [{ amount: 100000, payment_mode: 'Cash', payment_date: '2026-08-05', payment_time: '10:00:00', created_at: new Date('2026-08-05T05:00:00Z') }];
    d[2].payment_history = [{ amount: 110000, payment_mode: 'Cash', payment_date: '2026-08-05', payment_time: '15:00:00', created_at: new Date('2026-08-05T09:00:00Z') }];
    const c = G.complianceChecks(d, '2026-08-01', '2026-08-31');
    const by = Object.fromEntries(c.map((x) => [x.id, x]));
    assert.deepStrictEqual(by.address.invoices, ['2001']);
    assert.deepStrictEqual(by.pan.invoices, ['2004']);
    assert.deepStrictEqual(by.gaps.invoices, ['2003']);
    assert.deepStrictEqual(by.cash.invoices.sort(), ['2002', '2004']);
    assert.deepStrictEqual(by.untaxed.invoices, ['2005']);
    assert.strictEqual(by.address.severity, 'warn');
    assert.strictEqual(c[0].severity, 'warn');                                          // warnings first
    assert.ok(!by.pos && !by.hsn);
});

t('checks before filing: a clean month has none; cancelled invoices and other months are ignored; numbers listed are capped', () => {
    const clean = [{ ...doc('3001', '2026-08-03', [gold()], {}, { paid: 0 }), customer_address: '1 Road, Howrah' }, { ...doc('3002', '2026-08-04', [gold()], {}, { paid: 0 }), customer_address: '2 Road, Howrah' }];
    assert.deepStrictEqual(G.complianceChecks(clean, '2026-08-01', '2026-08-31'), []);
    const cancelled = [{ ...doc('3001', '2026-08-03', [gold()], { status: 'cancelled' }, { paid: 0 }), customer_address: '' }];
    assert.strictEqual(G.complianceChecks(cancelled, '2026-08-01', '2026-08-31').length, 0);
    const other = [{ ...doc('3001', '2026-09-03', [gold()], {}, { paid: 0 }), customer_address: '' }];
    assert.strictEqual(G.complianceChecks(other, '2026-08-01', '2026-08-31').length, 0);
    const many = Array.from({ length: 30 }, (_, i) => ({ ...doc(String(4000 + i), '2026-08-03', [gold()], {}, { paid: 0 }), customer_address: '' }));
    const c = G.complianceChecks(many, '2026-08-01', '2026-08-31').find((x) => x.id === 'address');
    assert.strictEqual(c.count, 30); assert.strictEqual(c.invoices.length, 12); assert.strictEqual(c.more, 18);
});

t('monthly record: EVERY status of the month is listed, only valid ones count in the totals; sorted by date then number', () => {
    const d = docs();
    d.push(doc('1007', '2026-08-25', [gold()], { status: 'void' }));
    d.push(doc('1008', '2026-08-25', [gold()], { status: 'deleted' }));
    d.push(doc('1009', '2026-08-26', [gold({ netWt: 1 })], { status: 'revised' }));
    d.push(doc('1010', '2026-08-26', [gold()], { status: 'pending' }));
    const rec = G.monthlyRecord(d, 2026, 8);
    assert.deepStrictEqual(rec.invoices.map((i) => i.number), ['1001', '1002', '1003', 'BR2-0001', '1004', '1005', '1007', '1008', '1009', '1010']);
    assert.ok(rec.invoices.every((x, i, a) => i === 0 || a[i - 1].date <= x.date), 'oldest first');
    assert.strictEqual(rec.invoices.length, 10);                          // 1006 is September, left out
    assert.strictEqual(rec.tracking.total, 10);
    assert.strictEqual(rec.tracking.valid, 7);                            // 1001,1002,1003,1005(delivered),BR2,1009 revised,1010 pending
    assert.strictEqual(rec.tracking.cancelledVoidDeleted, 3);            // 1004 cancelled + void + deleted
    assert.strictEqual(rec.totals.count, 7);
    assert.deepStrictEqual(rec.invoices.filter((i) => !i.counted).map((i) => i.number).sort(), ['1004', '1007', '1008']);
    assert.strictEqual(rec.tracking.start, 1001);                         // the main series only: a branch number like BR2-0001 is not "invoice 1"
    assert.deepStrictEqual(rec.tracking.branchSeries, [{ name: 'BR2', from: 'BR2-0001', to: 'BR2-0001', count: 1 }]);
    assert.strictEqual(rec.tracking.end, 1010);
    assert.strictEqual(rec.period.monthName, 'August');
});

t('monthly record: totals equal the sum of the counted invoices (taxable, CGST/SGST/IGST, GST, payable, weights, making)', () => {
    const rec = G.monthlyRecord(docs(), 2026, 8);
    const c = rec.invoices.filter((i) => i.counted);
    const sum = (f) => G.r2(c.reduce((a, i) => a + f(i), 0));
    assert.strictEqual(rec.totals.taxable, sum((i) => i.taxable));
    assert.strictEqual(rec.totals.cgst, sum((i) => i.cgst));
    assert.strictEqual(rec.totals.sgst, sum((i) => i.sgst));
    assert.strictEqual(rec.totals.igst, sum((i) => i.igst));
    assert.strictEqual(rec.totals.gst, sum((i) => i.totalGst));
    assert.strictEqual(rec.totals.amount, sum((i) => i.totalPayable));
    assert.strictEqual(rec.totals.goldWeight, G.r3(c.reduce((a, i) => a + i.items.filter((l) => l.metal === 'Gold').reduce((x, l) => x + l.netWt, 0), 0)));
    assert.strictEqual(rec.totals.silverWeight, G.r3(c.reduce((a, i) => a + i.items.filter((l) => l.metal === 'Silver').reduce((x, l) => x + l.netWt, 0), 0)));
    assert.ok(rec.totals.igst > 0 && rec.totals.cgst > 0);
    assert.ok(Math.abs(rec.totals.gst - (rec.totals.cgst + rec.totals.sgst + rec.totals.igst)) < 0.02);
    assert.ok(rec.tracking.avgInvoice > 0 && rec.tracking.gstRate > 2.9 && rec.tracking.gstRate < 3.1, `rate ${rec.tracking.gstRate}`);
    // each counted invoice reconciles: items' amounts + tax + extra charges (+ GST on them) + round off = total payable
    for (const i of c) {
        const lines = i.items.reduce((a, l) => a + l.amount, 0);
        const afterGstDiscount = i.discountBeforeGst ? 0 : i.discount;          // old website rule: taken off the total, after GST
        assert.ok(Math.abs(lines + i.additionalCharges + i.totalGst + i.roundOff - afterGstDiscount - i.totalPayable) < 0.06, `invoice ${i.number}: ${lines}+${i.additionalCharges}+${i.totalGst}+${i.roundOff}-${afterGstDiscount} vs ${i.totalPayable}`);
    }
});

t('monthly record: carries the audit detail (purity, gross/net, code, HUID, stones, hallmark, discount, payments, who/where/when) and honest average rates', () => {
    const rich = doc('4001', '2026-08-05', [gold({ grossWt: 10.35, productCode: 'LGP-RG-0342', certification: 'huid', huid: 'AB12CD', hallmarkCharge: 45, extras: [{ kind: 'Stone', name: 'Ruby', weight: 0.4, amount: 900 }] })], {}, { discount: 500, paid: 20000 });
    rich.created_by_name = 'Counter Staff'; rich.created_at = new Date('2026-08-05T05:30:00Z'); rich.branch_name = 'Bagbazar Showroom'; rich.gold_rate = 9000;
    rich.payment_history = [{ amount: 12000, payment_mode: 'Cash', payment_date: '2026-08-05', created_at: new Date('2026-08-05T05:30:00Z') }, { amount: 8000, payment_mode: 'Online', payment_date: '2026-08-05', transaction_reference: 'UPI123', created_at: new Date('2026-08-05T05:31:00Z') }];
    const inter = doc('4002', '2026-08-06', [gold({ netWt: 20 })], {}, { interstate: true });
    const r = G.monthlyRecord([rich, inter, doc('4003', '2026-08-07', [gold({ makingCharge: 0, taxableOverride: 95000 })], {}, {})], 2026, 8);
    const a = r.invoices[0], line = a.items[0];
    assert.strictEqual(line.purity, '22K'); assert.strictEqual(line.grossWt, 10.35); assert.strictEqual(line.netWt, 10);
    assert.strictEqual(line.code, 'LGP-RG-0342'); assert.strictEqual(line.huid, 'AB12CD'); assert.strictEqual(line.hallmark, 45); assert.strictEqual(line.stone, 900);
    assert.strictEqual(line.extras[0].name, 'Ruby'); assert.strictEqual(line.metalValue, 90000); assert.ok(line.discount > 0);
    assert.strictEqual(a.createdBy, 'Counter Staff'); assert.strictEqual(a.branch, 'Bagbazar Showroom'); assert.strictEqual(a.goldRate, 9000);
    assert.deepStrictEqual(a.payments.map((p) => [p.mode, p.amount]), [['Cash', 12000], ['Online', 8000]]);
    assert.strictEqual(a.payments[1].reference, 'UPI123');
    // making shown = the making column, or (typed taxable amount) what is left over: never 0 for a typed-taxable bill
    assert.ok(a.items[0].making < 2000 && a.items[0].making > 1500, 'making is net of the pre-GST discount: ' + a.items[0].making); assert.strictEqual(a.items[0].makingDerived, false);
    assert.strictEqual(r.invoices[2].items[0].making, 5000); assert.strictEqual(r.invoices[2].items[0].makingDerived, true);
    // CGST/SGST are 1.5% of the in-state sales and IGST 3% of the inter-state ones (not diluted by each other)
    assert.strictEqual(r.tracking.cgstRate, 1.5); assert.strictEqual(r.tracking.sgstRate, 1.5); assert.strictEqual(r.tracking.igstRate, 3);
    assert.deepStrictEqual(r.breakdown.metals.map((m) => [m.metal, m.purity, m.pieces]), [['Gold', '22K', 3]]);
    assert.deepStrictEqual(r.breakdown.payments.map((p) => p.mode), ['Cash', 'Online']);        // 12,000 cash / 8,000 online / the others paid nothing
    assert.strictEqual(r.breakdown.branches.length, 2);
});

t('monthly record: an empty month, a leap-year February and December are handled', () => {
    assert.strictEqual(G.monthlyRecord(docs(), 2026, 3).invoices.length, 0);
    assert.strictEqual(G.monthlyRecord([doc('9', '2028-02-29', [gold()])], 2028, 2).invoices.length, 1);
    assert.strictEqual(G.monthlyRecord([doc('9', '2026-12-31', [gold()])], 2026, 12).invoices.length, 1);
    assert.strictEqual(G.monthlyRecord([doc('9', '2026-12-31', [gold()])], 2026, 11).invoices.length, 0);
});

t('purchase ITC: within the period only, deleted ignored, suppliers without GSTIN kept apart (not claimable)', () => {
    const P = (date, cg, sg, ig, gstin = '19ABCDE1234F1Z5', extra = {}) => ({ invoiceDate: new Date(date + 'T05:00:00Z'), itcCgst: cg, itcSgst: sg, itcIgst: ig, billerGstin: gstin, totalAmount: 1000, ...extra });
    const r = G.purchaseItc([P('2026-08-05', 100, 100, 0), P('2026-08-31', 0, 0, 60), P('2026-09-01', 500, 500, 0), P('2026-08-10', 30, 30, 0, ''), P('2026-08-11', 9, 9, 0, '19ABCDE1234F1Z5', { isDeleted: true })], '2026-08-01', '2026-08-31');
    assert.deepStrictEqual(r.claim, { igst: 60, cgst: 100, sgst: 100 });
    assert.deepStrictEqual(r.atRisk, { igst: 0, cgst: 30, sgst: 30 });
    assert.strictEqual(r.count, 2); assert.strictEqual(r.riskCount, 1);
    assert.deepStrictEqual(G.purchaseItc([P('2026-08-10', 30, 30, 0, '')], '2026-08-01', '2026-08-31', { countWithoutGstin: true }).claim, { igst: 0, cgst: 30, sgst: 30 });
});

console.log(`\n${n} passed`);
