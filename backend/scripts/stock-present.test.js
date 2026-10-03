'use strict';
/**
 * Stock = what is in the shop (barcoded items present + explicit bulk entries); the reconciliation and the daily summary
 * come from the records the shop keeps (purchases, old metal, invoices, wastage). No hand-kept stock ledger.
 * node scripts/stock-present.test.js      (needs the local database; uses and drops a throw-away database)
 */
const assert = require('assert');
const mongoose = require('mongoose');

const DB = `stock_present_test_${process.pid}`;
process.env.MONGODB_URI = `mongodb://127.0.0.1:27018/${DB}`;
process.env.JWT_SECRET = 'test';
const ok = (m) => console.log(`ok - ${m}`);
const call = (fn, req) => new Promise((resolve, reject) => {
    const res = { statusCode: 200, status(c) { this.statusCode = c; return this; }, json(b) { resolve({ code: this.statusCode, body: b }); } };
    Promise.resolve(fn({ query: {}, params: {}, body: {}, user: { id: '64b000000000000000000001', name: 'Tester' }, ...req }, res)).catch(reject);
});

(async () => {
    await mongoose.connect(process.env.MONGODB_URI);
    const db = mongoose.connection.db;
    const ctrl = require('../controllers/stockController');
    const now = new Date();
    const day = '2026-09-10';

    // present pieces: 60 g gold in the shop (two pieces), a sold piece and a removed piece do not count
    await db.collection('items').insertMany([
        { name: 'Ring', metalType: 'gold', netWeight: 25, status: 'active', isDeleted: false },
        { name: 'Chain', metalType: 'Gold', netWeight: 35, status: 'booked', isDeleted: false },
        { name: 'Sold bangle', metalType: 'gold', netWeight: 20, status: 'sold', isDeleted: false },
        { name: 'Removed', metalType: 'gold', netWeight: 40, status: 'active', isDeleted: true },
    ]);
    // raw material bought (the website's own shape)
    await db.collection('purchases').insertMany([
        { invoice_date: day, invoice_number: 'P1', metal_type: 'Gold', biller: 'X', quantity: 60, rate: 1, total_amount: 60 },
        { invoice_date: '2026-09-02', invoice_number: 'P2', metal_type: 'Gold', biller: 'X', quantity: 40, rate: 1, total_amount: 40 },
    ]);
    // old metal taken from a customer and raw metal bought; a cancelled entry does not count
    await db.collection('app_old_metal').insertMany([
        { kind: 'old', status: 'active', metalType: 'gold', net: 10, date: new Date(`${day}T06:00:00Z`) },
        { kind: 'raw', status: 'active', metalType: 'gold', net: 5, date: new Date(`${day}T07:00:00Z`) },
        { kind: 'old', status: 'cancelled', metalType: 'gold', net: 99, date: now },
    ]);
    // bills: 12 g of gold sold in two lines of a delivered bill; a cancelled bill does not count
    await db.collection('invoices').insertMany([
        { invoice_number: '1', invoice_date: day, status: 'delivered', items: [{ metal_type: 'Gold', net_wt: 7 }, { metal_type: 'Gold', net_wt: '5' }, { metal_type: 'Silver', net_wt: 100 }] },
        { invoice_number: '2', invoice_date: day, status: 'cancelled', items: [{ metal_type: 'Gold', net_wt: 99 }] },
    ]);
    // wastage the website recorded: only the approved one counts
    await db.collection('wastage_reports').insertMany([
        { wastage_date: day, metal_type: 'Gold', wastage_amount: '1.500', status: 'approved' },
        { wastage_date: day, metal_type: 'Gold', wastage_amount: '7.000', status: 'pending' },
    ]);

    // ── bulk entries are explicit and have a kind ──
    let r = await call(ctrl.addBulkWeight, { body: { metalType: 'gold', weightGrams: 10, description: 'Bench dust', category: 'dust' } });
    assert.strictEqual(r.code, 201);
    r = await call(ctrl.addBulkWeight, { body: { metalType: 'gold', weightGrams: 20, description: 'Loose parts', category: 'parts', purity: '22K', pieces: 140 } });
    assert.strictEqual(r.code, 201);
    assert(r.body.data.entry.purity === '22K' && r.body.data.entry.pieces === 140);
    const gone = (await call(ctrl.addBulkWeight, { body: { metalType: 'gold', weightGrams: 5, description: 'Old note' } })).body.data.entry;
    r = await call(ctrl.deleteBulkWeight, { params: { id: String(gone._id) } });
    assert.strictEqual(r.code, 200);
    assert.strictEqual((await call(ctrl.addBulkWeight, { body: { metalType: 'gold', weightGrams: 5, description: 'x', category: 'nonsense' } })).code, 400);
    assert.strictEqual((await call(ctrl.addBulkWeight, { body: { metalType: 'gold', weightGrams: 0, description: 'x' } })).code, 400);
    ok('bulk metal is added explicitly with a kind (dust, parts ...), purity and pieces; bad input is refused; a removed entry stays out');

    // ── dashboard: stock in the shop = present pieces + active bulk ──
    r = await call(ctrl.getDashboard, {});
    const d = r.body.data;
    assert.strictEqual(d.barcodedStock.gold.weightGrams, 60);
    assert.strictEqual(d.totalStock.gold, 90);
    assert.deepStrictEqual(d.bulkByCategory, { dust: { gold: 10 }, parts: { gold: 20 } });
    ok('stock in the shop = the pieces present (sold and removed ones excluded) + the active bulk entries, by kind');

    // ── reconciliation: came in vs present, sold and wasted ──
    r = await call(ctrl.getReconciliation, {});
    const g = r.body.data.reconciliation.gold;
    assert.strictEqual(g.totalPurchased, 100);
    assert.strictEqual(g.adjustedPurchase, 110);
    assert.strictEqual(g.oldMetalReceived, 10);
    assert.strictEqual(g.rawMetalBought, 5);
    assert.strictEqual(g.presentStock, 90);
    assert.strictEqual(g.barcodedStock, 60);
    assert.strictEqual(g.bulkStock, 30);
    assert.strictEqual(g.totalSold, 12, 'a cancelled bill is not a sale; text weights count');
    assert.strictEqual(g.totalWastage, 1.5, 'only approved wastage');
    assert.strictEqual(g.expectedDebit, 35);          // 110 + 10 + 5 - 90
    assert.strictEqual(g.discrepancy, 21.5);          // 35 - 12 - 1.5
    assert.strictEqual(g.hasAlert, true);
    assert.strictEqual(g.ledgerTotal, 90, 'older phones that still say "Net Ledger" show what is present');
    ok('the reconciliation compares what came in (purchases x1.10, old and raw metal) with what is present, sold and wasted');

    // entering the missing bulk metal closes the gap
    await call(ctrl.addBulkWeight, { body: { metalType: 'gold', weightGrams: 21.5, description: 'In-process work', category: 'in_process' } });
    r = await call(ctrl.getReconciliation, {});
    assert.strictEqual(r.body.data.reconciliation.gold.discrepancy, 0);
    assert.strictEqual(r.body.data.reconciliation.gold.hasAlert, false);
    assert.strictEqual(r.body.data.reconciliation.silver.totalSold, 100);
    ok('adding the missing bulk metal as Bulk stock brings the discrepancy to zero');

    // ── daily summary from the real records ──
    r = await call(ctrl.getDailySummary, { query: { startDate: '2026-09-01', endDate: '2026-09-30', metalType: 'gold' } });
    const s = r.body.data.summary;
    assert.deepStrictEqual(s['2026-09-10'].gold, { in: 75, out: 13.5, net: 61.5 });   // 60 + 10 + 5 in; 12 sold + 1.5 wastage out
    assert.deepStrictEqual(s['2026-09-02'].gold, { in: 40, out: 0, net: 40 });
    assert.deepStrictEqual(Object.keys(s), ['2026-09-10', '2026-09-02'], 'newest day first');
    ok('the daily summary = purchases + old/raw metal in, bills + approved wastage out, per day');

    console.log('\nall present-stock checks passed');
})().catch((e) => { console.error('FAILED:', e && e.stack || e); process.exitCode = 1; }).finally(async () => {
    try { await mongoose.connection.db.dropDatabase(); } catch (e) { /* nothing to drop */ }
    await mongoose.disconnect();
});
