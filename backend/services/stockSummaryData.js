/**
 * stockSummaryData.js — reads the shop's records (one collection per operation) and builds the metal balance, its data
 * checks, insights, daily snapshots and the recent-movement feed. The calculations themselves are in stockSummary.js.
 *
 *   purchases        raw material bought (the website's list)          items          pieces, by status
 *   app_old_metal    old metal taken in, raw metal bought               bulk_weights   bulk stock
 *   invoices         bill lines (cancelled / void are not sales)        app_credit_notes   returned pieces put back
 *   wastage_reports  the website's wastage (approved counts)            tallysessions  last stock tally
 *   daily_snapshots  the website's daily snapshots (history)
 */
'use strict';

const { getConnection } = require('../config/db');
const Item = require('../models/Item');
const OldMetal = require('../models/OldMetal');
const CreditNote = require('../models/CreditNote');
const TallySession = require('../models/TallySession');
const PurchaseModel = require('../models/Purchase');
const { salesFilter } = require('./registrations');
const { current: branchContext } = require('../utils/branchScope');
const S = require('./stockSummary');

const IN_SHOP = ['active', 'action_needed', 'booked', 'no_sell'];
const WITH_OTHERS = ['in_repair', 'UNDER_REPAIR', 'repair', 'WITH_CUSTOMER', 'WITH_AGENT', 'temporarily_removed'];
const GONE = ['sold', 'deleted'];
const NOT_SALES = ['cancelled', 'void', 'deleted'];

const db = () => getConnection().db;
const dbl = (f) => ({ $convert: { input: f, to: 'double', onError: 0, onNull: 0 } });
const lower = (f) => ({ $toLower: { $ifNull: [f, ''] } });
const blank = () => ({
    purchased: 0, oldMetal: 0, rawMetal: 0, inShop: 0, withOthers: 0, bulk: 0, sold: 0, returned: 0, wastage: 0,
    _ctx: {
        removedPieces: 0, removedG: 0, actionNeededPieces: 0, actionNeededG: 0, zeroWeightPieces: 0, linesNoWeight: 0, purchasesBad: 0,
        cancelledPendingPieces: 0, cancelledPendingG: 0, soldNoBillPieces: 0, pendingWastageCount: 0, pendingWastageG: 0, bulkEntries: 0, unknownStatusPieces: 0,
        inShopPieces: 0, withOthersPieces: 0,
    },
});

/** Whole-firm view (admin / owner / all-branches) or a branch only: wastage and the website's own records have no branch. */
const restrict = () => { const c = branchContext(); return c && c.restrict ? c.restrict : null; };
const wholeFirm = () => !restrict();

async function loadSettings() {
    const stored = await require('../models/AppStockSettings').findOne({ key: 'main' }).lean();
    return S.resolveSettings(stored);
}

/** Read every source and return the per-metal inputs and the counts for the data checks. */
async function gather() {
    const inputs = { gold: blank(), silver: blank() };
    const other = { linesOtherMetal: 0 };
    const at = (m) => inputs[m];
    const BulkWeight = require('../models/BulkWeight')(getConnection());
    const Purchase = PurchaseModel(getConnection());
    const scope = salesFilter(restrict());

    // pieces by status
    // a piece flagged isDeleted is removed whatever its status says
    const itemRows = await Item.aggregate([{ $group: { _id: { s: { $cond: [{ $eq: ['$isDeleted', true] }, 'deleted', '$status'] }, m: lower('$metalType') }, w: { $sum: dbl('$netWeight') }, n: { $sum: 1 }, zero: { $sum: { $cond: [{ $lte: [dbl('$netWeight'), 0] }, 1, 0] } } } }]);
    for (const r of itemRows) {
        const m = r._id.m, st = r._id.s;
        if (!inputs[m]) continue;                       // a metal other than gold / silver is not part of this check
        const x = at(m), c = x._ctx;
        if (IN_SHOP.includes(st)) { x.inShop += r.w; c.inShopPieces += r.n; c.zeroWeightPieces += r.zero; if (st === 'action_needed') { c.actionNeededPieces += r.n; c.actionNeededG += r.w; } }
        else if (WITH_OTHERS.includes(st)) { x.withOthers += r.w; c.withOthersPieces += r.n; c.zeroWeightPieces += r.zero; }
        else if (st === 'deleted') { c.removedPieces += r.n; c.removedG += r.w; }
        else if (st === 'sold') { /* its weight is in the bills */ }
    }
    // pieces with a status this check does not know are counted once, firm-wide (reported with gold's findings)
    const unknown = itemRows.filter((r) => ![...IN_SHOP, ...WITH_OTHERS, ...GONE].includes(r._id.s)).reduce((a, r) => a + r.n, 0);
    inputs.gold._ctx.unknownStatusPieces = unknown;

    // bulk stock
    for (const r of await BulkWeight.aggregate([{ $match: { isActive: true } }, { $group: { _id: lower('$metalType'), w: { $sum: dbl('$weightGrams') }, n: { $sum: 1 } } }])) {
        if (inputs[r._id]) { inputs[r._id].bulk += r.w; inputs[r._id]._ctx.bulkEntries += r.n; }
    }

    // raw material bought
    for (const r of await Purchase.aggregate([{ $group: { _id: lower('$metal_type'), w: { $sum: dbl('$quantity') }, bad: { $sum: { $cond: [{ $lte: [dbl('$quantity'), 0] }, 1, 0] } } } }])) {
        if (inputs[r._id]) { inputs[r._id].purchased += r.w; inputs[r._id]._ctx.purchasesBad += r.bad; }
    }

    // old metal taken in / raw metal bought
    for (const r of await OldMetal.aggregate([{ $match: { status: 'active' } }, { $group: { _id: { m: '$metalType', k: '$kind' }, w: { $sum: '$net' } } }])) {
        if (inputs[r._id.m]) inputs[r._id.m][r._id.k === 'raw' ? 'rawMetal' : 'oldMetal'] += r.w;
    }

    // sold: every bill line that is not cancelled / void
    for (const r of await db().collection('invoices').aggregate([
        { $match: { $and: [scope, { status: { $nin: NOT_SALES } }] } },
        { $unwind: '$items' },
        { $group: { _id: lower('$items.metal_type'), w: { $sum: dbl('$items.net_wt') }, n: { $sum: 1 }, noW: { $sum: { $cond: [{ $lte: [dbl('$items.net_wt'), 0] }, 1, 0] } } } },
    ]).toArray()) {
        if (inputs[r._id]) { inputs[r._id].sold += r.w; inputs[r._id]._ctx.linesNoWeight += r.noW; } else other.linesOtherMetal += r.n;
    }

    // returned pieces that went back into stock
    for (const r of await CreditNote.aggregate([{ $match: { status: 'active' } }, { $unwind: '$lines' }, { $match: { 'lines.restocked': true } }, { $group: { _id: lower('$lines.metal'), w: { $sum: dbl('$lines.netWt') } } }])) {
        if (inputs[r._id]) inputs[r._id].returned += r.w;
    }

    // wastage (the website's reports; whole firm only)
    if (wholeFirm()) {
        for (const r of await db().collection('wastage_reports').aggregate([{ $group: { _id: { s: '$status', m: lower('$metal_type') }, w: { $sum: dbl('$wastage_amount') }, n: { $sum: 1 } } }]).toArray()) {
            const x = inputs[r._id.m];
            if (!x) continue;
            if (r._id.s === 'approved') x.wastage += r.w;
            else if (r._id.s === 'pending') { x._ctx.pendingWastageCount += r.n; x._ctx.pendingWastageG += r.w; }
        }
    }

    // cancelled bills whose pieces were never put back, and sold pieces with no bill
    const cancelled = (await db().collection('invoices').find({ $and: [scope, { status: 'cancelled' }] }, { projection: { invoice_number: 1 } }).limit(5000).toArray()).map((d) => String(d.invoice_number));
    if (cancelled.length) {
        for (const r of await Item.aggregate([{ $match: { status: 'sold', soldInvoice: { $in: cancelled } } }, { $group: { _id: lower('$metalType'), n: { $sum: 1 }, w: { $sum: dbl('$netWeight') } } }])) {
            if (inputs[r._id]) { inputs[r._id]._ctx.cancelledPendingPieces += r.n; inputs[r._id]._ctx.cancelledPendingG += r.w; }
        }
    }
    const soldItems = await Item.find({ status: 'sold' }, { soldInvoice: 1, metalType: 1 }).limit(5000).lean();
    if (soldItems.length) {
        const nums = [...new Set(soldItems.map((i) => String(i.soldInvoice || '')).filter(Boolean))];
        const have = new Set((await db().collection('invoices').find({ invoice_number: { $in: nums } }, { projection: { invoice_number: 1 } }).toArray()).map((d) => String(d.invoice_number)));
        for (const i of soldItems) {
            const m = String(i.metalType || '').toLowerCase();
            if (inputs[m] && (!i.soldInvoice || !have.has(String(i.soldInvoice)))) inputs[m]._ctx.soldNoBillPieces += 1;
        }
    }

    const dup = await db().collection('invoices').aggregate([{ $match: scope }, { $group: { _id: '$invoice_number', n: { $sum: 1 } } }, { $match: { n: { $gt: 1 }, _id: { $nin: [null, ''] } } }, { $count: 'n' }]).toArray();

    // last completed stock tally
    // how old the last COUNT is: the day the stock was counted (the tally's date), not the day it was locked
    const tally = await TallySession.findOne({ lockedAt: { $ne: null } }).sort({ date: -1 }).select('date').lean();
    const tallyDaysAgo = tally && tally.date ? Math.max(0, Math.floor((Date.now() - new Date(tally.date).getTime()) / 86400000)) : null;
    const running = await TallySession.findOne({ status: 'active' }).sort({ date: -1 }).select('scannedItemsCount expectedItems').lean();
    const tallyRunning = running ? { checked: Number(running.scannedItemsCount) || 0, total: Array.isArray(running.expectedItems) ? running.expectedItems.length : Number(running.expectedItems) || 0 } : null;

    return { inputs, other, duplicateBills: dup[0] ? dup[0].n : 0, tallyDaysAgo, tallyRunning, wholeFirm: wholeFirm() };
}

/** The whole Summary answer: per metal the balance, the data checks, the confidence and the insights. */
async function summary() {
    const settings = await loadSettings();
    const g = await gather();
    const metals = {};
    const ctx = { branchOnly: !g.wholeFirm, tallyDaysAgo: g.tallyDaysAgo, tallyRunning: g.tallyRunning, duplicateBills: g.duplicateBills, linesOtherMetal: g.other.linesOtherMetal };
    for (const m of S.METALS) {
        const { _ctx, ...nums } = g.inputs[m];
        const calc = S.calcMetal(m, nums, settings);
        metals[m] = { ...calc, pieces: { inShop: _ctx.inShopPieces, withOthers: _ctx.withOthersPieces, removed: _ctx.removedPieces, removedG: Math.round(_ctx.removedG * 1000) / 1000 }, bulkEntries: _ctx.bulkEntries };
        ctx[m] = { ..._ctx, returnsExceedSales: calc.returnsExceedSales };
    }
    const checks = S.buildChecks(ctx);
    const insights = {};
    for (const m of S.METALS) insights[m] = S.buildInsights(m, metals[m], ctx[m], settings);
    return {
        asOf: new Date().toISOString(),
        scope: { wholeFirm: g.wholeFirm },
        settings,
        metals,
        checks,
        confidence: S.confidenceOf(checks),
        insights,
        tally: { daysAgo: g.tallyDaysAgo, running: g.tallyRunning },
    };
}

// ── snapshots ───────────────────────────────────────────────────────────────────────────────────────────────

const ymdIST = (d = new Date()) => PurchaseModel.ymdIST(d);
const snaps = () => db().collection('daily_snapshots');

/** The snapshot of a day as the app and the old website both understand it. */
function snapshotDoc(sum, date, by, source) {
    const doc = {
        date,
        gold: S.snapshotMetal(sum.metals.gold),
        silver: S.snapshotMetal(sum.metals.silver),
        basis: 'items',
        confidence: sum.confidence.level,
        source,
    };
    return { doc, by };
}

/**
 * Save the snapshot of today (one per day). Only the whole-firm view can be saved. A snapshot the old website made today is
 * never replaced by the automatic one (a person pressing Save may replace it). Returns { saved, date, type }.
 */
async function saveSnapshot({ by = '', byName = 'System', source = 'app' } = {}) {
    if (!wholeFirm()) { const e = new Error('Only the whole-firm view can be saved as a snapshot (switch to All branches).'); e.status = 400; throw e; }
    const date = ymdIST();
    const existing = await snaps().findOne({ date });
    if (existing && !existing.basis && source === 'auto') return { saved: false, date, type: 'kept-website-snapshot' };
    const { doc } = snapshotDoc(await summary(), date, by, source);
    const now = new Date();
    if (existing) {
        await snaps().updateOne({ _id: existing._id }, { $set: { gold: doc.gold, silver: doc.silver, basis: doc.basis, confidence: doc.confidence, source, updated_at: now, updated_by: String(by), updated_by_name: byName } });
        return { saved: true, date, type: 'update' };
    }
    await snaps().insertOne({ ...doc, created_at: now, created_by: String(by), created_by_name: byName });
    return { saved: true, date, type: 'insert' };
}

/** Today's snapshot if nobody saved one yet (called when the Summary is opened and by the nightly job). */
async function ensureToday() {
    if (!wholeFirm()) return { saved: false, reason: 'branch' };
    const date = ymdIST();
    if (await snaps().findOne({ date }, { projection: { _id: 1 } })) return { saved: false, date, type: 'exists' };
    try { return await saveSnapshot({ source: 'auto' }); } catch (e) { return { saved: false, error: e.message }; }
}

/** Has today's snapshot been taken, and which was the last one. */
async function snapshotStatus() {
    const today = ymdIST();
    const last = await snaps().find({}).sort({ date: -1 }).limit(1).next();
    const t = await snaps().findOne({ date: today }, { projection: { date: 1, basis: 1, source: 1, created_by_name: 1, updated_by_name: 1, created_at: 1, updated_at: 1 } });
    return {
        today, savedToday: !!t,
        todayInfo: t ? { source: t.source || 'website', basis: t.basis || 'ledger', by: t.updated_by_name || t.created_by_name || '', at: t.updated_at || t.created_at || null } : null,
        last: last ? { date: last.date, basis: last.basis || 'ledger' } : null,
    };
}

async function history({ from, to, view = 'daily' } = {}) {
    const f = {};
    if (from || to) { f.date = {}; if (from) f.date.$gte = String(from); if (to) f.date.$lte = String(to); }
    const rows = await snaps().find(f).sort({ date: 1 }).limit(2000).toArray();
    const settings = await loadSettings();
    const out = S.rollup(rows, ['weekly', 'monthly'].includes(view) ? view : 'daily', settings);
    return { rows: out, trend: S.trend(out), count: rows.length, bounds: rows.length ? { first: rows[0].date, last: rows[rows.length - 1].date } : null };
}

// ── recent movements: what came in and went out, newest first ───────────────────────────────────────────────

async function movements(limit = 8) {
    const lim = Math.min(Math.max(parseInt(limit, 10) || 8, 1), 100);
    const Purchase = PurchaseModel(getConnection());
    const BulkWeight = require('../models/BulkWeight')(getConnection());
    const scope = salesFilter(restrict());
    const keep = (m) => S.METALS.includes(m);
    const out = [];
    for (const p of await Purchase.find({}).sort({ invoice_date: -1, _id: -1 }).limit(lim).lean()) {
        const m = String(p.metal_type || '').toLowerCase();
        if (keep(m)) out.push({ at: String(p.invoice_date || '').slice(0, 10), type: 'purchase', direction: 'in', metal: m, grams: Number(p.quantity) || 0, title: `Purchase ${p.invoice_number || ''}`.trim(), note: p.biller || '' });
    }
    for (const o of await OldMetal.find({ status: 'active' }).sort({ date: -1 }).limit(lim).lean()) {
        if (keep(o.metalType)) out.push({ at: ymdIST(o.date), type: o.kind === 'raw' ? 'raw_metal' : 'old_metal', direction: 'in', metal: o.metalType, grams: o.net, title: o.kind === 'raw' ? 'Raw metal bought' : 'Old metal taken in', note: o.customerName || '' });
    }
    for (const b of await db().collection('invoices').find({ $and: [scope, { status: { $nin: NOT_SALES } }] }).sort({ invoice_date: -1, _id: -1 }).limit(lim).project({ invoice_number: 1, invoice_date: 1, customer_name: 1, items: 1 }).toArray()) {
        const by = {};
        for (const it of b.items || []) { const m = String(it.metal_type || '').toLowerCase(); if (keep(m)) by[m] = (by[m] || 0) + (Number(it.net_wt) || 0); }
        for (const [m, w] of Object.entries(by)) if (w > 0) out.push({ at: String(b.invoice_date || '').slice(0, 10), type: 'sale', direction: 'out', metal: m, grams: Math.round(w * 1000) / 1000, title: `Bill ${b.invoice_number}`, note: b.customer_name || '' });
    }
    if (wholeFirm()) {
        for (const w of await db().collection('wastage_reports').find({ status: 'approved' }).sort({ wastage_date: -1 }).limit(lim).toArray()) {
            const m = String(w.metal_type || '').toLowerCase();
            if (keep(m)) out.push({ at: String(w.wastage_date || '').slice(0, 10), type: 'wastage', direction: 'out', metal: m, grams: Number(w.wastage_amount) || 0, title: `Wastage: ${w.category || ''}`.trim(), note: w.reason || '' });
        }
    }
    for (const b of await BulkWeight.find({ isActive: true }).sort({ date: -1 }).limit(lim).lean()) {
        if (keep(b.metalType)) out.push({ at: ymdIST(b.date), type: 'bulk', direction: 'stock', metal: b.metalType, grams: b.weightGrams, title: `Bulk stock: ${b.description || ''}`, note: b.category || '' });
    }
    return out.sort((a, b) => (a.at < b.at ? 1 : a.at > b.at ? -1 : 0)).slice(0, lim).map((m) => ({ ...m, grams: Math.round(m.grams * 1000) / 1000 }));
}

module.exports = { summary, gather, saveSnapshot, ensureToday, snapshotStatus, history, movements, loadSettings, IN_SHOP, WITH_OTHERS };
