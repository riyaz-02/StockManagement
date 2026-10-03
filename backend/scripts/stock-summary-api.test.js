'use strict';
/**
 * The Summary on a hand-built shop (throw-away local database): balance, data checks, snapshots, history, wastage rules.
 * node scripts/stock-summary-api.test.js
 */
const assert = require('assert');
const mongoose = require('mongoose');

const DB = `stock_summary_test_${process.pid}`;
process.env.MONGODB_URI = `mongodb://127.0.0.1:27018/${DB}`;
process.env.JWT_SECRET = 'test';
const ok = (m) => console.log(`ok - ${m}`);
const call = (fn, req) => new Promise((resolve, reject) => {
    const res = { statusCode: 200, headers: {}, status(c) { this.statusCode = c; return this; }, json(b) { resolve({ code: this.statusCode, body: b }); }, send(b) { resolve({ code: this.statusCode, body: b, headers: this.headers }); }, setHeader(k, v) { this.headers[k] = v; } };
    Promise.resolve(fn({ query: {}, params: {}, body: {}, user: { _id: '64b000000000000000000001', id: '64b000000000000000000001', name: 'Admin', role: 'admin' }, ...req }, res)).catch(reject);
});
const staffA = { _id: '64b0000000000000000000a1', id: '64b0000000000000000000a1', name: 'Reporter A', role: 'staff' };
const staffB = { _id: '64b0000000000000000000b2', id: '64b0000000000000000000b2', name: 'Checker B', role: 'staff' };
const boss = { _id: '64b0000000000000000000c3', id: '64b0000000000000000000c3', name: 'Owner', role: 'owner' };

(async () => {
    await mongoose.connect(process.env.MONGODB_URI);
    const db = mongoose.connection.db;
    const ctrl = require('../controllers/stockController');
    const wctrl = require('../controllers/wastageController');
    const Data = require('../services/stockSummaryData');
    const { ymdIST } = require('../models/Purchase');
    const today = ymdIST(new Date());
    const daysAgo = (n) => new Date(Date.now() - n * 86400000);

    // ── the shop ──
    await db.collection('purchases').insertOne({ invoice_date: '2026-09-01', invoice_number: 'P1', metal_type: 'Gold', biller: 'X', quantity: 100, rate: 1, total_amount: 100 });
    await db.collection('items').insertMany([
        { name: 'ring', metalType: 'gold', netWeight: 60, status: 'active' },
        { name: 'in repair', metalType: 'gold', netWeight: 5, status: 'in_repair' },
        { name: 'with agent', metalType: 'Gold', netWeight: 3, status: 'WITH_AGENT' },
        { name: 'removed', metalType: 'gold', netWeight: 20, status: 'deleted' },
        { name: 'flagged', metalType: 'gold', netWeight: 7, status: 'active', isDeleted: true },
        { name: 'sold ok', metalType: 'gold', netWeight: 10, status: 'sold', soldInvoice: '1' },
        { name: 'sold, bill cancelled', metalType: 'gold', netWeight: 4, status: 'sold', soldInvoice: '2' },
        { name: 'sold, no bill', metalType: 'gold', netWeight: 6, status: 'sold', soldInvoice: '' },
        { name: 'weird', metalType: 'gold', netWeight: 1, status: 'mystery' },
    ].map((x, i) => ({ barcode: `T${i}`, ...x })));
    await db.collection('bulk_weights').insertMany([
        { metalType: 'gold', weightGrams: 7, description: 'dust', category: 'dust', isActive: true, date: new Date(), createdBy: new mongoose.Types.ObjectId() },
        { metalType: 'gold', weightGrams: 3, description: 'parts', category: 'parts', isActive: true, date: new Date(), createdBy: new mongoose.Types.ObjectId() },
        { metalType: 'gold', weightGrams: 5, description: 'old', category: 'other', isActive: false, date: new Date(), createdBy: new mongoose.Types.ObjectId() },
    ]);
    await db.collection('app_old_metal').insertMany([
        { kind: 'old', status: 'active', metalType: 'gold', net: 8, date: new Date() },
        { kind: 'raw', status: 'active', metalType: 'gold', net: 2, date: new Date() },
        { kind: 'old', status: 'cancelled', metalType: 'gold', net: 50, date: new Date() },
    ]);
    await db.collection('invoices').insertMany([
        { invoice_number: '1', invoice_date: '2026-09-02', status: 'delivered', customer_name: 'A', items: [{ metal_type: 'Gold', net_wt: 10 }, { metal_type: 'Gold', net_wt: 0 }, { metal_type: 'Platinum', net_wt: 3 }] },
        { invoice_number: '2', invoice_date: '2026-09-03', status: 'cancelled', items: [{ metal_type: 'Gold', net_wt: 4 }] },
        { invoice_number: '3', invoice_date: '2026-09-04', status: 'delivered', items: [{ metal_type: 'Gold', net_wt: '1' }] },
        { invoice_number: '3', invoice_date: '2026-09-05', status: 'delivered', items: [{ metal_type: 'Gold', net_wt: 1 }] },
    ]);
    await db.collection('app_credit_notes').insertOne({ number: 'CN-1', date: '2026-09-06', status: 'active', lines: [{ metal: 'Gold', netWt: 1.5, restocked: true }, { metal: 'Gold', netWt: 9, restocked: false }] });
    await db.collection('wastage_reports').insertMany([
        { wastage_date: '2026-09-03', metal_type: 'Gold', wastage_amount: '2.000', category: 'Manufacturing', status: 'approved' },
        { wastage_date: '2026-09-04', metal_type: 'Gold', wastage_amount: '0.500', category: 'Polishing', status: 'pending' },
        { wastage_date: '2026-09-05', metal_type: 'Gold', wastage_amount: '9.000', category: 'Other', status: 'rejected' },
    ]);
    await db.collection('tallysessions').insertOne({ status: 'force_locked', lockedAt: daysAgo(50), date: daysAgo(51) });

    // ── the balance ──
    let r = await call(ctrl.getSummary, {});
    assert.strictEqual(r.code, 200, JSON.stringify(r.body).slice(0, 200));
    const d = r.body.data;
    const g = d.metals.gold;
    assert.strictEqual(g.receipts.adjustedPurchase, 110);
    assert.strictEqual(g.receipts.total, 120);                     // 110 + 8 old + 2 raw
    assert.strictEqual(g.stock.inShop, 60, 'a flagged-removed piece and a deleted one are not stock');
    assert.strictEqual(g.stock.withOthers, 8, 'a piece in repair and one with an agent still belong to the business');
    assert.strictEqual(g.stock.bulk, 10, 'only the active bulk entries');
    assert.strictEqual(g.out.soldGross, 12, 'a cancelled bill is not a sale; text weights count; platinum is not in this check');
    assert.strictEqual(g.out.returned, 1.5, 'only the returned piece that went back into stock');
    assert.strictEqual(g.out.sold, 10.5);
    assert.strictEqual(g.out.wastage, 2, 'only approved wastage counts');
    assert.strictEqual(g.variance, 29.5);                          // 120 - (78 + 12.5)
    assert.strictEqual(g.severity, 'high');
    assert.strictEqual(g.direction, 'short');
    assert.strictEqual(g.pieces.removed, 2);
    ok('the balance on a hand-built shop: pieces out count as stock, cancelled bills and unapproved wastage do not count, returns reduce sales');

    // ── data checks ──
    const ids = d.checks.map((c) => c.id);
    for (const id of ['cancelled_not_restored', 'bill_lines_no_weight', 'bill_lines_other_metal', 'duplicate_bill_numbers', 'pieces_removed', 'sold_without_bill', 'wastage_pending', 'tally_old', 'pieces_unknown_status']) assert(ids.includes(id), `missing check ${id}: ${ids.join(',')}`);
    assert(!ids.includes('no_bulk_stock'));
    const cp = d.checks.find((c) => c.id === 'cancelled_not_restored');
    assert(cp.level === 'error' && cp.count === 1 && cp.grams === 4);
    assert.strictEqual(d.checks.find((c) => c.id === 'pieces_removed').grams, 27);
    assert.strictEqual(d.checks.find((c) => c.id === 'wastage_pending').grams, 0.5);
    assert.strictEqual(d.confidence.level, 'fix');
    assert(d.insights.gold.analysis.some((a) => /27\.000/.test(a.en)) && d.insights.gold.recommendations.length >= 4);
    assert.strictEqual(d.metals.silver.variance, 0);
    ok('data checks find the cancelled-bill piece, no-weight lines, other metals, duplicate bill numbers, removed pieces, a sold piece with no bill, pending wastage and an old tally');
    assert(d.movements.length >= 3 && d.movements.every((m) => m.at && m.direction && m.metal));
    const mv = (await call(ctrl.getSummaryMovements, { query: { limit: '30' } })).body.data.movements;
    assert(mv.some((m) => m.type === 'purchase') && mv.some((m) => m.type === 'sale' && m.grams > 0) && mv.some((m) => m.type === 'wastage') && mv.some((m) => m.type === 'old_metal') && mv.some((m) => m.type === 'bulk'));
    assert(!mv.some((m) => m.title === 'Bill 2'), 'a cancelled bill is not a movement');
    ok('the movement feed lists purchases, bills and wastage');

    // ── the old reconciliation answer is the same engine ──
    r = await call(ctrl.getReconciliation, {});
    const old = r.body.data.reconciliation.gold;
    assert(old.discrepancy === 29.5 && old.presentStock === 78 && old.totalSold === 10.5 && old.hasAlert === true && old.ledgerTotal === 78);
    ok('the shorter /reconciliation answer comes from the same engine (one formula)');

    // ── snapshots ──
    const snaps = db.collection('daily_snapshots');
    assert.strictEqual(await snaps.countDocuments({ date: today }), 1, 'opening the summary took today\'s snapshot');
    let s = await snaps.findOne({ date: today });
    assert(s.basis === 'items' && s.source === 'auto' && s.gold.final_result === 29.5 && s.gold.calculated_purchase === 110 && s.gold.stock_total === 78 && s.gold.total_sold === 10.5 && s.gold.wastage_total === 2 && s.gold.severity === 'high');
    assert(s.created_at instanceof Date && typeof s.created_by_name === 'string');
    assert.strictEqual(Math.round((s.gold.expected_stock_debit - s.gold.total_sold - s.gold.wastage_total - s.gold.final_result) * 1000) + 0, 0, "the old website's identity still holds in what the app saves");
    ok('the snapshot is built by the server in the website\'s field names (+ the app\'s extras) and the old identity holds');
    r = await call(ctrl.saveSummarySnapshot, {});
    assert(r.code === 200 && r.body.data.type === 'update');
    assert.strictEqual(await snaps.countDocuments({ date: today }), 1, 'saving again the same day updates it');
    ok('saving again the same day updates the one snapshot (never a second)');
    await snaps.deleteOne({ date: today });
    await snaps.insertOne({ date: today, gold: { calculated_purchase: 1, stock_total: 1, total_sold: 0, final_result: 0 }, silver: {}, created_at: new Date(), created_by: 'u', created_by_name: 'Old site' });
    let st = await Data.saveSnapshot({ source: 'auto' });
    assert.strictEqual(st.saved, false);
    assert.strictEqual((await snaps.findOne({ date: today })).gold.calculated_purchase, 1, 'the old website\'s own snapshot is not replaced by an automatic one');
    st = await Data.saveSnapshot({ source: 'app', by: 'u1', byName: 'Admin' });
    assert.strictEqual(st.type, 'update');
    assert.strictEqual((await snaps.findOne({ date: today })).basis, 'items');
    ok('an automatic snapshot never overwrites one the old website made; a person pressing Save may');

    // ── history ──
    await snaps.insertMany([
        { date: '2026-08-30', gold: { purchase_total: 90, calculated_purchase: 99, stock_total: 70, expected_stock_debit: 29, total_sold: 20, final_result: 6 }, silver: {}, created_at: new Date() },
        { date: '2026-08-31', gold: { purchase_total: 95, calculated_purchase: 104.5, stock_total: 72, expected_stock_debit: 32.5, total_sold: 22, final_result: 7.5 }, silver: {}, created_at: new Date() },
    ]);
    r = await call(ctrl.getSummaryHistory, { query: { view: 'daily' } });
    const rows = r.body.data.rows;
    assert.strictEqual(rows[0].date, today);
    assert.strictEqual(rows[2].gold.in, null, 'the first snapshot has nothing before it');
    assert.strictEqual(rows[1].gold.in, 5.5);                        // 104.5 - 99
    assert.strictEqual(rows[1].gold.out, 2, 'out = change of (sold + wastage): sold 20 -> 22, the old site\'s derived wastage (3) unchanged');
    assert.strictEqual(rows[0].methodChange, true, 'the day the method changed is marked');
    assert.strictEqual(r.body.data.trend.comparable, false);
    r = await call(ctrl.getSummaryHistory, { query: { view: 'monthly' } });
    assert(r.body.data.rows.length >= 1 && r.body.data.rows.length <= 2);
    r = await call(ctrl.getSummaryHistory, { query: { format: 'csv' } });
    assert(r.headers['Content-Type'].startsWith('text/csv') && /^Period,Date,Metal/.test(r.body) && r.body.split('\n').length === 1 + rows.length * 2);
    ok('history: in / out are the change between snapshots, the change of method is marked, monthly rolls up, CSV export');

    // ── wastage: the rules ──
    const mkw = (u, b) => call(wctrl.create, { user: u, body: b });
    const good = { date: '2026-09-10', metal: 'gold', amount: 0.25, category: 'polishing', reason: 'filing' };
    assert.strictEqual((await mkw(staffA, { ...good, amount: 0 })).code, 400);
    assert.strictEqual((await mkw(staffA, { ...good, date: '2099-01-01' })).code, 400);
    assert.strictEqual((await mkw(staffA, { ...good, metal: 'platinum' })).code, 400);
    assert.strictEqual((await mkw(staffA, { ...good, category: 'nonsense' })).code, 400);
    assert.strictEqual((await mkw(staffA, { ...good, amount: 999999 })).code, 400);
    r = await mkw(staffA, good);
    assert.strictEqual(r.code, 201);
    const w1 = r.body.data.report;
    assert(w1.status === 'pending' && w1.metal === 'gold' && w1.category === 'Polishing');
    const raw = await db.collection('wastage_reports').findOne({ _id: new mongoose.Types.ObjectId(w1._id) });
    assert(raw.metal_type === 'Gold' && raw.wastage_amount === '0.250' && raw.wastage_date === '2026-09-10' && raw.reported_by === staffA.id && raw.status === 'pending' && /^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$/.test(raw.created_ist), 'stored the website\'s way');
    ok('a wastage report is validated and stored the way the website stores it, always pending first');
    let before = (await call(ctrl.getSummary, {})).body.data.metals.gold.out.wastage;
    assert.strictEqual(before, 2, 'pending wastage does not count');
    assert.strictEqual((await call(wctrl.approve, { user: staffA, params: { id: w1._id }, body: {} })).code, 403, 'the reporter cannot approve their own report');
    assert.strictEqual((await call(wctrl.update, { user: staffB, params: { id: w1._id }, body: { amount: 1 } })).code, 403, 'only the reporter can change it');
    r = await call(wctrl.update, { user: staffA, params: { id: w1._id }, body: { amount: 0.3 } });
    assert(r.code === 200 && r.body.data.report.amount === 0.3);
    r = await call(wctrl.approve, { user: staffB, params: { id: w1._id }, body: { comment: 'seen' } });
    assert(r.code === 200 && r.body.data.report.status === 'approved' && r.body.data.report.approvedBy.id === staffB.id);
    assert.strictEqual((await call(wctrl.approve, { user: staffB, params: { id: w1._id }, body: {} })).code, 409, 'a second approval is refused');
    assert.strictEqual((await call(wctrl.update, { user: staffA, params: { id: w1._id }, body: { amount: 5 } })).code, 409, 'an approved report is final');
    assert.strictEqual((await call(wctrl.reject, { user: staffB, params: { id: w1._id }, body: { comment: 'no' } })).code, 403, 'only admin / owner can reverse an approved one');
    const after = (await call(ctrl.getSummary, {})).body.data.metals.gold;
    assert.strictEqual(after.out.wastage, 2.3, 'approval makes it count (2 + 0.3)');
    assert.strictEqual(after.variance, 29.2);
    r = await call(wctrl.reject, { user: boss, params: { id: w1._id }, body: {} });
    assert.strictEqual(r.code, 400, 'a rejection needs a reason');
    r = await call(wctrl.reject, { user: boss, params: { id: w1._id }, body: { comment: 'entered twice' } });
    assert(r.code === 200 && r.body.data.report.status === 'rejected');
    assert.strictEqual((await call(ctrl.getSummary, {})).body.data.metals.gold.out.wastage, 2, 'a reversed approval stops counting');
    const mine = (await mkw(boss, good)).body.data.report;
    assert.strictEqual((await call(wctrl.approve, { user: boss, params: { id: mine._id }, body: {} })).code, 200, 'admin / owner may approve their own report');
    const listed = await call(wctrl.list, { query: { status: 'approved' } });
    assert(listed.body.data.reports.length >= 2 && listed.body.data.totals.approved.gold.grams > 0);
    ok('wastage rules: no self-approval, only the reporter edits, one approval only, approved is final, a boss can reverse with a reason, only approved counts');

    console.log('\nall stock-summary API checks passed');
})().catch((e) => { console.error('FAILED:', e && e.stack || e); process.exitCode = 1; }).finally(async () => {
    try { await mongoose.connection.db.dropDatabase(); } catch (e) { /* nothing to drop */ }
    await mongoose.disconnect();
});
