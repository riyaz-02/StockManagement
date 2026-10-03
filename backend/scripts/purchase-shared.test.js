'use strict';
/**
 * One `purchases` collection for the app, the new website and the old PHP website (models/Purchase.js).
 * node scripts/purchase-shared.test.js      (needs the local database; uses and drops a throw-away database)
 */
const assert = require('assert');
const mongoose = require('mongoose');

const DB = `purchase_shared_test_${process.pid}`;
process.env.MONGODB_URI = `mongodb://127.0.0.1:27018/${DB}`;
process.env.JWT_SECRET = 'test';
const ok = (m) => console.log(`ok - ${m}`);

const call = (fn, req) => new Promise((resolve, reject) => {
    const res = { statusCode: 200, status(c) { this.statusCode = c; return this; }, json(b) { resolve({ code: this.statusCode, body: b }); } };
    Promise.resolve(fn({ query: {}, params: {}, body: {}, user: { id: '64b000000000000000000001', name: 'Tester', mobile: '9000000000' }, ...req }, res)).catch(reject);
});

(async () => {
    await mongoose.connect(process.env.MONGODB_URI);
    const raw = mongoose.connection.db.collection('purchases');
    const ctrl = require('../controllers/purchaseController');
    const P = require('../models/Purchase');

    // what the PHP site writes (save_purchase.php): website names, 'Gold', text date, no GST at all
    const site = (o) => ({ invoice_date: '2026-03-18', invoice_number: 'AST/25-26/945', metal_type: 'Gold', biller: 'A S TOUNCH CENTRE', description: 'GOLD BAR (99.50%)', quantity: 22.52, rate: 15951.3, total_amount: 370000, created_at: new Date('2026-06-07T14:41:05Z'), created_ist: '2026-06-07 20:11:05', created_by: 'u1', created_by_name: 'Sk Riyaz', updated_at: new Date('2026-06-07T14:41:05Z'), updated_ist: '2026-06-07 20:11:05', updated_by: 'u1', updated_by_name: 'Sk Riyaz', ...o });
    const a = (await raw.insertOne(site())).insertedId;
    await raw.insertOne(site({ invoice_date: '2025-11-02', invoice_number: 'JC/118', metal_type: 'Silver', biller: 'JALAN COMPANY', quantity: 1200, rate: 90, total_amount: 111240 }));
    const before = JSON.stringify(await raw.findOne({ _id: a }));

    // ── the app lists the website's purchases ──
    let r = await call(ctrl.getPurchases, { query: { limit: '50' } });
    assert.strictEqual(r.code, 200);
    assert.strictEqual(r.body.data.pagination.total, 2);
    const first = r.body.data.purchases[0];
    assert(first.invoiceNumber === 'AST/25-26/945' && first.metalType === 'gold' && first.quantity === 22.52 && first.totalPayable === 370000 && first.gstRecorded === false && first.totalItc === 0);
    assert.strictEqual(new Date(first.invoiceDate).toISOString(), '2026-03-18T00:00:00.000Z');
    assert.deepStrictEqual(Object.keys(r.body.data.metalTotals).sort(), ['gold', 'silver']);
    assert.strictEqual(r.body.data.metalTotals.silver.totalWeight, 1200);
    ok('the app lists the website\'s purchases: names, lower-case metal, real date, no GST or input credit invented');

    r = await call(ctrl.getPurchases, { query: { metalType: 'Silver', startDate: '2025-11-01', endDate: '2025-11-30' } });
    assert.strictEqual(r.body.data.pagination.total, 1);
    r = await call(ctrl.getPurchases, { query: { metalType: 'gold', startDate: '2026-03-18', endDate: '2026-03-18' } });
    assert.strictEqual(r.body.data.pagination.total, 1, 'a one-day range includes that whole day');
    ok('filters by metal (any capitals) and by day work on the website\'s text dates');

    // ── the app creates one; the website's fields are what the old site would write ──
    r = await call(ctrl.createPurchase, { body: { invoiceDate: '2026-04-10', invoiceNumber: 'smk-001', metalType: 'gold', biller: 'Test Supplier', billerGstin: '19abcde1234f1z5', quantity: 10, rate: 7000, transactionType: 'intra-state' } });
    assert.strictEqual(r.code, 201, JSON.stringify(r.body));
    const made = r.body.data.purchase;
    const stored = await raw.findOne({ _id: new mongoose.Types.ObjectId(String(made._id)) });
    assert(stored.invoice_number === 'SMK-001' && stored.invoice_date === '2026-04-10' && stored.metal_type === 'Gold' && stored.biller === 'Test Supplier' && stored.quantity === 10 && stored.rate === 7000, 'website fields');
    assert.strictEqual(stored.total_amount, 72100, 'the website\'s total_amount is the invoice total with GST (70,000 + 3%)');
    assert(typeof stored.created_ist === 'string' && /^\d{4}-\d{2}-\d{2} \d\d:\d\d:\d\d$/.test(stored.created_ist) && stored.created_by === '64b000000000000000000001' && stored.created_by_name === 'Tester', 'created_* stamps in the website\'s form');
    assert(stored.totalAmount === 70000 && stored.totalItc === 2100 && stored.billerGstin === '19ABCDE1234F1Z5' && stored.source === 'app', 'the app\'s extras sit beside them');
    assert(made.gstRecorded === true && made.totalAmount === 70000 && made.totalPayable === 72100 && made.totalItc === 2100 && made.metalType === 'gold');
    ok('a purchase made in the app is stored exactly as the website stores one, plus the app\'s GST extras');

    r = await call(ctrl.createPurchase, { body: { invoiceDate: '2026-04-11', invoiceNumber: 'ast/25-26/945', metalType: 'gold', biller: 'X', quantity: 1, rate: 1 } });
    assert.strictEqual(r.code, 409);
    ok('the website\'s own invoice numbers are protected from duplicates');

    // ── ITC and reports count only what has a recorded split ──
    r = await call(ctrl.getItcSummary, { query: { fy: '2026-27' } });
    assert.strictEqual(r.body.data.yearTotals.totalItc, 2100);
    assert.strictEqual(r.body.data.yearTotals.invoices, 1);
    r = await call(ctrl.getItcSummary, { query: { fy: '2025-26' } });
    assert.strictEqual(r.body.data.yearTotals.invoices, 2);
    assert.strictEqual(r.body.data.yearTotals.totalItc, 0, 'old website purchases carry no input credit');
    ok('the ITC summary counts input credit only where the GST split was recorded');

    // ── editing in the app changes only the fields it owns; the website's other fields stay as they were ──
    r = await call(ctrl.updatePurchase, { params: { id: String(a) }, body: { biller: 'A.S. TOUNCH CENTRE', rate: 16000 } });
    assert.strictEqual(r.code, 200);
    const after = await raw.findOne({ _id: a });
    assert(after.biller === 'A.S. TOUNCH CENTRE' && after.rate === 16000 && after.invoice_number === 'AST/25-26/945' && after.total_amount === 370000 && after.metal_type === 'Gold' && after.invoice_date === '2026-03-18' && after.created_by_name === 'Sk Riyaz');
    assert(after.updated_by_name === 'Tester' && after.updated_ist !== '2026-06-07 20:11:05', 'updated_* stamped the website\'s way');
    assert(JSON.stringify(Object.keys(after).filter((k) => !Object.keys(JSON.parse(before)).includes(k)).sort()) === '[]', 'no stray fields were added to the website\'s record');
    ok('an edit in the app touches only what changed and stamps updated_* like the website does');

    // ── delete: the website has no deleted flag, so it is removed for real and a copy is kept ──
    r = await call(ctrl.deletePurchase, { params: { id: String(a) } });
    assert.strictEqual(r.code, 200);
    assert.strictEqual(await raw.countDocuments({ _id: a }), 0);
    const kept = await mongoose.connection.db.collection('app_trash').findOne({ collection: 'purchases', docId: a });
    assert(kept && kept.doc.invoice_number === 'AST/25-26/945' && kept.byName === 'Tester');
    r = await call(ctrl.getPurchases, { query: {} });
    assert.strictEqual(r.body.data.pagination.total, 2);
    ok('a delete removes the record from the one shared list and keeps a full copy in app_trash');

    // ── a split the website invalidated is not trusted ──
    const sid = new mongoose.Types.ObjectId(String(made._id));
    await raw.updateOne({ _id: sid }, { $set: { total_amount: 80000 } });   // the website edited the total
    const edited = P.toApp(await raw.findOne({ _id: sid }));
    assert(edited.gstRecorded === false && edited.totalItc === 0 && edited.totalPayable === 80000);
    r = await call(ctrl.getItcSummary, { query: { fy: '2026-27' } });
    assert.strictEqual(r.body.data.yearTotals.totalItc, 0);
    ok('if the website changes the total of a purchase, the app\'s old GST split is no longer trusted');

    console.log('\nall shared-purchase checks passed');
})().catch((e) => { console.error('FAILED:', e && e.stack || e); process.exitCode = 1; }).finally(async () => {
    try { await mongoose.connection.db.dropDatabase(); } catch (e) { /* nothing to drop */ }
    await mongoose.disconnect();
});
