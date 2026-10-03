/**
 * stockController.js — stock in the shop, bulk stock, daily movement and the reconciliation.
 *
 * STOCK IS WHAT IS IN THE SHOP: the barcoded pieces that are present (`items`, tracked by the barcode and the tally) plus
 * the explicit bulk entries (`bulk_weights`: dust, parts, sub-items, raw or in-process metal kept together without a
 * barcode). There is no hand-kept stock ledger any more (the old "stock in / stock out each day" entries): every number
 * here comes from the records the shop already keeps, in ONE collection each:
 *
 *   present stock   items (in shop) + bulk_weights (active)
 *   came in         purchases (raw material bought)  +  app_old_metal (old metal taken from customers, raw metal bought)
 *   went out        invoices (the weight of every non-cancelled bill line)  +  wastage_reports (approved)
 *
 * Reconciliation (the website's own formula, with the hand-kept ledger replaced by what is really present):
 *   adjustedPurchase(gold)   = purchasedGrams(gold)   * 1.10  (+10%)
 *   adjustedPurchase(silver) = purchasedGrams(silver)  * 1.20  (+20%)
 *   expectedDebit            = adjustedPurchase + old/raw metal received - present stock      (what has left the shop)
 *   discrepancy              = expectedDebit - sold - wastage
 *   ALERT if |discrepancy| > 1.0g
 */

'use strict';

const { getConnection } = require('../config/db');
const { getNowIST } = require('../utils/gstHelpers');
const Item = require('../models/Item');
const OldMetal = require('../models/OldMetal');
const PurchaseModel = require('../models/Purchase');
const { salesFilter } = require('../services/registrations');
const { current: branchContext } = require('../utils/branchScope');

let _BulkWeight, _Purchase;
function getBulkWeightModel() {
    if (!_BulkWeight) _BulkWeight = require('../models/BulkWeight')(getConnection());
    return _BulkWeight;
}
function getPurchaseModel() {
    if (!_Purchase) _Purchase = PurchaseModel(getConnection());
    return _Purchase;
}

// Purchase weight inflation multipliers (business rules from legacy system)
const METALS = ['gold', 'silver'];
const YMD = /^\d{4}-\d{2}-\d{2}$/;
const r3 = (n) => Math.round((Number(n) + Number.EPSILON) * 1000) / 1000;
const rx = (metal) => ({ $regex: `^${metal}$`, $options: 'i' });
const BULK_CATEGORIES = ['dust', 'parts', 'sub_items', 'raw', 'in_process', 'reserved', 'other'];

// Statuses that count as physically-in-shop.
// action_needed = quick-added items awaiting details completion; still on the rack.
const SummaryData = require('../services/stockSummaryData');
const IN_SHOP = [...SummaryData.IN_SHOP, ...SummaryData.WITH_OTHERS];   // everything the business owns: in the shop or out for repair / with an agent / with a customer

/** The invoices the caller may see (a branch user: only their branch; admin / owner: the whole firm). */
function invoiceScope() {
    const c = branchContext();
    return salesFilter(c && c.restrict ? c.restrict : null);
}
/** Wastage reports have no branch: only the whole-firm view includes them. */
const seesWholeFirm = () => { const c = branchContext(); return !(c && c.restrict); };

// the weight of invoice lines by metal (and optionally day): cancelled / void bills are not sales
async function invoiceLines(extraMatch, groupDay) {
    return getConnection().db.collection('invoices').aggregate([
        { $match: { $and: [invoiceScope(), { status: { $nin: ['cancelled', 'void', 'deleted'] } }, extraMatch || {}] } },
        { $unwind: '$items' },
        { $group: { _id: { metal: { $toLower: '$items.metal_type' }, ...(groupDay ? { day: '$invoice_date' } : {}) }, weight: { $sum: { $toDouble: { $ifNull: ['$items.net_wt', 0] } } } } },
    ]).toArray();
}

// ─── GET /api/stock/dashboard ────────────────────────────────────────────────
exports.getDashboard = async (req, res) => {
    try {
        const BulkWeight = getBulkWeightModel();

        const barcodedAgg = await Item.aggregate([
            { $match: { isDeleted: { $ne: true }, status: { $in: IN_SHOP } } },
            { $group: { _id: { $toLower: '$metalType' }, weightGrams: { $sum: '$netWeight' }, count: { $sum: 1 } } },
        ]);
        const barcodedStock = {};
        barcodedAgg.forEach(({ _id, weightGrams, count }) => {
            if (_id) barcodedStock[_id] = { weightGrams: r3(weightGrams), count };
        });

        const bulkWeights = await BulkWeight.find({ isActive: true }).lean();

        const totalStock = {};
        Object.entries(barcodedStock).forEach(([metal, data]) => { totalStock[metal] = r3(data.weightGrams); });
        const bulkByCategory = {};
        bulkWeights.forEach(({ metalType, weightGrams, category }) => {
            if (!metalType) return;
            const metal = metalType.toLowerCase();
            totalStock[metal] = r3((totalStock[metal] || 0) + weightGrams);
            const cat = BULK_CATEGORIES.includes(category) ? category : 'other';
            bulkByCategory[cat] = bulkByCategory[cat] || {};
            bulkByCategory[cat][metal] = r3((bulkByCategory[cat][metal] || 0) + weightGrams);
        });

        res.json({ success: true, data: { barcodedStock, bulkWeights, bulkByCategory, totalStock, asOf: getNowIST() } });
    } catch (err) {
        console.error('[Stock] getDashboard error:', err);
        res.status(500).json({ success: false, message: 'Error fetching stock dashboard', error: err.message });
    }
};

// ─── GET /api/stock/bulk-weights ─────────────────────────────────────────────
exports.getBulkWeights = async (req, res) => {
    try {
        const BulkWeight = getBulkWeightModel();
        const { metalType, isActive, category } = req.query;

        const filter = {};
        if (metalType) filter.metalType = metalType.toLowerCase();
        if (category && BULK_CATEGORIES.includes(category)) filter.category = category;
        if (isActive !== undefined) filter.isActive = isActive === 'true';

        const entries = await BulkWeight.find(filter).sort({ updatedAt: -1 }).lean();
        res.json({ success: true, data: { bulkWeights: entries, categories: BULK_CATEGORIES } });
    } catch (err) {
        console.error('[Stock] getBulkWeights error:', err);
        res.status(500).json({ success: false, message: 'Error fetching bulk weights', error: err.message });
    }
};

// ─── POST /api/stock/bulk-weights ────────────────────────────────────────────
// An explicit addition of metal kept in bulk, without a barcode: dust, parts, sub-items, raw or in-process metal.
exports.addBulkWeight = async (req, res) => {
    try {
        const BulkWeight = getBulkWeightModel();
        const { metalType, weightGrams, description, category, purity, pieces } = req.body;

        if (!metalType || weightGrams == null || !description) {
            return res.status(400).json({ success: false, message: 'metalType, weightGrams, and description are required' });
        }
        if (!(parseFloat(weightGrams) > 0)) return res.status(400).json({ success: false, message: 'Enter a weight above zero' });
        if (category && !BULK_CATEGORIES.includes(category)) return res.status(400).json({ success: false, message: `category must be one of: ${BULK_CATEGORIES.join(', ')}` });

        const entry = await BulkWeight.create({
            metalType: metalType.toLowerCase(),
            weightGrams: parseFloat(weightGrams),
            description: description.trim(),
            category: category || 'other',
            purity: purity ? String(purity).trim().slice(0, 20) : undefined,
            pieces: pieces != null && pieces !== '' ? Math.max(0, parseInt(pieces, 10) || 0) : undefined,
            date: new Date(),
            createdBy: req.user.id,
            updatedBy: req.user.id,
        });
        require('../services/audit').record(req, 'bulk_stock', entry._id, `${entry.category} · ${entry.description}`, 'added', [{ field: 'weight', to: `${entry.metalType} ${entry.weightGrams}g` }]);
        res.status(201).json({ success: true, message: 'Bulk weight entry added', data: { entry } });
    } catch (err) {
        console.error('[Stock] addBulkWeight error:', err);
        res.status(500).json({ success: false, message: 'Error adding bulk weight', error: err.message });
    }
};

// ─── PUT /api/stock/bulk-weights/:id ─────────────────────────────────────────
exports.updateBulkWeight = async (req, res) => {
    try {
        const BulkWeight = getBulkWeightModel();
        const entry = await BulkWeight.findById(req.params.id);
        if (!entry) {
            return res.status(404).json({ success: false, message: 'Bulk weight entry not found' });
        }

        const { weightGrams, description, isActive, category, purity, pieces } = req.body;
        if (category != null && !BULK_CATEGORIES.includes(category)) return res.status(400).json({ success: false, message: `category must be one of: ${BULK_CATEGORIES.join(', ')}` });
        const before = entry.weightGrams;
        if (weightGrams != null) entry.weightGrams = parseFloat(weightGrams);
        if (description != null) entry.description = description.trim();
        if (isActive != null) entry.isActive = isActive;
        if (category != null) entry.category = category;
        if (purity != null) entry.purity = String(purity).trim().slice(0, 20);
        if (pieces != null) entry.pieces = pieces === '' ? undefined : Math.max(0, parseInt(pieces, 10) || 0);
        entry.updatedBy = req.user.id;
        entry.date = new Date();

        await entry.save();
        if (weightGrams != null && before !== entry.weightGrams) require('../services/audit').record(req, 'bulk_stock', entry._id, `${entry.category || 'other'} · ${entry.description}`, 'changed', [{ field: 'weight', from: before, to: entry.weightGrams }]);
        res.json({ success: true, message: 'Bulk weight updated', data: { entry } });
    } catch (err) {
        console.error('[Stock] updateBulkWeight error:', err);
        res.status(500).json({ success: false, message: 'Error updating bulk weight', error: err.message });
    }
};

// ─── DELETE /api/stock/bulk-weights/:id ──────────────────────────────────────
exports.deleteBulkWeight = async (req, res) => {
    try {
        const BulkWeight = getBulkWeightModel();
        const entry = await BulkWeight.findById(req.params.id);
        if (!entry) {
            return res.status(404).json({ success: false, message: 'Bulk weight entry not found' });
        }
        // Soft-disable instead of hard delete (this collection belongs to the app alone)
        entry.isActive = false;
        entry.updatedBy = req.user.id;
        await entry.save();
        require('../services/audit').record(req, 'bulk_stock', entry._id, `${entry.category || 'other'} · ${entry.description}`, 'removed', []);
        res.json({ success: true, message: 'Bulk weight entry removed' });
    } catch (err) {
        console.error('[Stock] deleteBulkWeight error:', err);
        res.status(500).json({ success: false, message: 'Error deleting bulk weight', error: err.message });
    }
};

// ─── GET /api/stock/daily-summary ────────────────────────────────────────────
// What came in and what went out each day, from the real records (no hand-kept ledger):
//   in  = purchases of the day + old / raw metal received that day
//   out = weight of the bills of the day + approved wastage of the day
// ?startDate=YYYY-MM-DD&endDate=YYYY-MM-DD&metalType=gold   (default: the last 31 days)
exports.getDailySummary = async (req, res) => {
    try {
        const { startDate, endDate, metalType } = req.query;
        const todayYmd = PurchaseModel.ymdIST(new Date());
        const to = YMD.test(String(endDate || '')) ? endDate : todayYmd;
        const from = YMD.test(String(startDate || '')) ? startDate : PurchaseModel.ymdIST(new Date(new Date(`${to}T00:00:00Z`).getTime() - 30 * 86400000));
        const only = metalType ? String(metalType).toLowerCase() : '';
        const day = { $gte: from, $lte: to };
        const summary = {};
        const add = (date, metal, kind, grams) => {
            if (!metal || (only && metal !== only) || !date) return;
            const m = ((summary[date] = summary[date] || {})[metal] = summary[date][metal] || { in: 0, out: 0, net: 0 });
            m[kind] += grams;
            m.net += kind === 'in' ? grams : -grams;
        };

        const purchases = await getPurchaseModel().aggregate([
            { $match: { invoice_date: day } },
            { $group: { _id: { d: '$invoice_date', m: { $toLower: '$metal_type' } }, w: { $sum: { $toDouble: '$quantity' } } } },
        ]);
        purchases.forEach((x) => add(x._id.d, x._id.m, 'in', x.w));

        const start = new Date(`${from}T00:00:00+05:30`), end = new Date(`${to}T23:59:59.999+05:30`);
        const old = await OldMetal.aggregate([
            { $match: { status: 'active', date: { $gte: start, $lte: end } } },
            { $group: { _id: { d: { $dateToString: { format: '%Y-%m-%d', date: '$date', timezone: 'Asia/Kolkata' } }, m: '$metalType' }, w: { $sum: '$net' } } },
        ]);
        old.forEach((x) => add(x._id.d, x._id.m, 'in', x.w));

        (await invoiceLines({ invoice_date: day }, true)).forEach((x) => add(x._id.day, x._id.metal, 'out', x.weight));

        if (seesWholeFirm()) {
            const waste = await getConnection().db.collection('wastage_reports').aggregate([
                { $match: { status: 'approved', wastage_date: day } },
                { $group: { _id: { d: '$wastage_date', m: { $toLower: '$metal_type' } }, w: { $sum: { $toDouble: '$wastage_amount' } } } },
            ]).toArray();
            waste.forEach((x) => add(x._id.d, x._id.m, 'out', x.w));
        }

        Object.values(summary).forEach((dayData) => Object.values(dayData).forEach((m) => { m.in = r3(m.in); m.out = r3(m.out); m.net = r3(m.net); }));
        const ordered = Object.fromEntries(Object.entries(summary).sort((a, b) => (a[0] < b[0] ? 1 : -1)));
        res.json({ success: true, data: { summary: ordered, from, to } });
    } catch (err) {
        console.error('[Stock] getDailySummary error:', err);
        res.status(500).json({ success: false, message: 'Error fetching daily summary', error: err.message });
    }
};

// ─── GET /api/stock/reconciliation ──────────────────────────────────────────
// The older, shorter shape of the Summary (the same engine: services/stockSummary.js), kept for phones that still read it.
exports.getReconciliation = async (req, res) => {
    try {
        const sum = await SummaryData.summary();
        const result = {};
        for (const metal of ['gold', 'silver']) {
            const m = sum.metals[metal];
            result[metal] = {
                totalPurchased: m.receipts.purchased,
                adjustedPurchase: m.receipts.adjustedPurchase,
                multiplierUsed: Math.round((1 + m.receipts.allowancePct / 100) * 1000) / 1000,
                oldMetalReceived: m.receipts.oldMetal,
                rawMetalBought: m.receipts.rawMetal,
                presentStock: m.stock.total,
                barcodedStock: m.stock.inShop,
                barcodedPieces: m.pieces.inShop,
                withOthersStock: m.stock.withOthers,
                bulkStock: m.stock.bulk,
                bulkEntries: m.bulkEntries,
                // kept for phones that still show "Net Ledger": it is now what is present
                ledgerCredit: m.stock.total,
                ledgerDebit: 0,
                ledgerTotal: m.stock.total,
                totalSold: m.out.sold,
                totalWastage: m.out.wastage,
                expectedDebit: m.expectedOut,
                discrepancy: m.variance,
                discrepancyPct: m.variancePct,
                severity: m.severity,
                hasAlert: m.severity !== 'normal',
                alertMessage: m.severity === 'normal' ? null : sum.insights[metal].headline.en,
            };
        }
        const anyAlert = Object.values(result).some((m) => m.hasAlert);
        res.json({ success: true, data: { reconciliation: result, anyAlert, alertThresholdGrams: sum.settings.minAlertGrams, wastageIncluded: sum.scope.wholeFirm, confidence: sum.confidence.level, generatedAt: getNowIST() } });
    } catch (err) {
        console.error('[Stock] getReconciliation error:', err);
        res.status(500).json({ success: false, message: 'Error running reconciliation', error: err.message });
    }
};

// ─── GET /api/stock/summary ─────────────────────────────────────────────────
// The Summary: per metal the balance and the difference, the data checks, the insights, the recent movements and the
// state of the daily snapshot. Opening it also takes today's snapshot if nobody has yet.
exports.getSummary = async (req, res) => {
    try {
        const data = await SummaryData.summary();
        if (data.scope.wholeFirm) await SummaryData.ensureToday();
        data.snapshot = await SummaryData.snapshotStatus();
        data.movements = await SummaryData.movements(8);
        res.json({ success: true, data });
    } catch (err) {
        console.error('[Stock] getSummary error:', err);
        res.status(500).json({ success: false, message: 'Error building the summary', error: err.message });
    }
};

// GET /api/stock/summary/movements?limit=  — what came in and went out recently
exports.getSummaryMovements = async (req, res) => {
    try {
        res.json({ success: true, data: { movements: await SummaryData.movements(req.query.limit) } });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Error fetching movements', error: err.message });
    }
};

// POST /api/stock/summary/snapshot  — save today's snapshot (built here, never from numbers the client sends)
exports.saveSummarySnapshot = async (req, res) => {
    try {
        const r = await SummaryData.saveSnapshot({ by: String(req.user._id), byName: req.user.name || '', source: 'app' });
        require('../services/audit').record(req, 'stock_snapshot', r.date, `Snapshot ${r.date}`, r.type === 'insert' ? 'saved' : 'updated', []);
        res.status(r.type === 'insert' ? 201 : 200).json({ success: true, message: r.type === 'insert' ? `Snapshot for ${r.date} saved` : `Snapshot for ${r.date} updated`, data: r });
    } catch (err) {
        res.status(err.status || 500).json({ success: false, message: err.status ? err.message : 'Error saving the snapshot' });
    }
};

// GET /api/stock/summary/history?from&to&view=daily|weekly|monthly[&format=csv]
exports.getSummaryHistory = async (req, res) => {
    try {
        const YMD = /^\d{4}-\d{2}-\d{2}$/;
        const from = YMD.test(String(req.query.from || '')) ? req.query.from : undefined;
        const to = YMD.test(String(req.query.to || '')) ? req.query.to : undefined;
        const h = await SummaryData.history({ from, to, view: req.query.view });
        if (String(req.query.format || '') === 'csv') {
            const q = (v) => (/[",\n]/.test(String(v)) ? `"${String(v).replace(/"/g, '""')}"` : String(v));
            const lines = [['Period', 'Date', 'Metal', 'Stock g', 'In g', 'Out g', 'Difference g', 'Difference %', 'Level'].join(',')];
            for (const r of h.rows) for (const m of ['gold', 'silver']) lines.push([r.label, r.date, m, r[m].stock, r[m].in ?? '', r[m].out ?? '', r[m].variance, r[m].variancePct, r[m].severity || ''].map(q).join(','));
            res.setHeader('Content-Type', 'text/csv; charset=utf-8');
            res.setHeader('Content-Disposition', 'attachment; filename="stock-history.csv"');
            return res.send(lines.join('\n'));
        }
        res.json({ success: true, data: h });
    } catch (err) {
        console.error('[Stock] getSummaryHistory error:', err);
        res.status(500).json({ success: false, message: 'Error fetching the history', error: err.message });
    }
};

exports.BULK_CATEGORIES = BULK_CATEGORIES;
