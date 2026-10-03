/**
 * purchaseController.js — Supplier purchase entry management
 *
 * ONE collection, `purchases`, shared with the PHP website (website field names; see models/Purchase.js). `toApp()` gives the
 * app and the portal the same JSON as before. A delete removes the record for real (the website has no "deleted" flag) and
 * keeps a copy in `app_trash`.
 * Stock is what is present in the shop (items + bulk entries), so a purchase does not write a stock ledger entry: it is the
 * raw-material record the reconciliation compares the stock with (controllers/stockController.js).
 *
 * Aligned with legacy PHP save_purchase.php / get_purchases.php:
 *  - description field (separate from remarks)
 *  - sorting options: date_desc (default), date_asc, amount_desc, amount_asc
 *  - aggregate totals (gold_total, silver_total) matching active filters
 *  - 1000-document safety cap on list
 *  - duplicate invoice check excludes own ID on edit ($ne)
 *  - Cloudinary attachment meta (url + publicId)
 */

'use strict';

const { getConnection } = require('../config/db');
const { calculateGST } = require('../utils/gstHelpers');
const PurchaseModel = require('../models/Purchase');
const { toApp, ymdIST, istStamp, websiteMetal, dayAsDate, sumIfSplit, taxableExpr } = PurchaseModel;
const escapeRx = (t) => String(t).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// ── Lazy model getters ────────────────────────────────────────────────────────
let _Purchase, _GstConfig;

function getPurchaseModel() {
    if (!_Purchase) _Purchase = PurchaseModel(getConnection());
    return _Purchase;
}
function getGstConfigModel() {
    if (!_GstConfig) _GstConfig = require('../models/GstConfig')(getConnection());
    return _GstConfig;
}

// ── Helper: fetch active GST config ──────────────────────────────────────────
async function getActiveGstConfig() {
    const GstConfig = getGstConfigModel();
    const config = await GstConfig.findOne({ isActive: true }).lean();
    return config || {};
}

// ── Helper: build MongoDB sort object from sort param ─────────────────────────
function buildSort(sort) {
    switch (sort) {
        case 'date_asc':       return { invoice_date: 1, _id: 1 };
        case 'amount_desc':    return { total_amount: -1, _id: -1 };
        case 'amount_asc':     return { total_amount: 1, _id: 1 };
        case 'date_desc':
        default:               return { invoice_date: -1, _id: -1 };
    }
}

// ─── GET /api/purchases/suggestions ──────────────────────────────────────────
/**
 * Returns autocomplete suggestions from existing purchase records.
 * Used by the app form to suggest biller names, GSTINs, and descriptions.
 *
 * Response:
 *   { suppliers: [...], supplierGstins: { "NAME": "GSTIN" }, descriptions: [...] }
 */
exports.getPurchaseSuggestions = async (req, res) => {
    try {
        const Purchase = getPurchaseModel();

        const [suppliers, descriptions, gstinRows] = await Promise.all([
            Purchase.distinct('biller'),
            Purchase.distinct('description', { description: { $nin: ['', null] } }),
            Purchase.find(
                { billerGstin: { $nin: ['', null] } },
                { biller: 1, billerGstin: 1, _id: 0 }
            ).lean(),
        ]);

        // Map biller → most recently used GSTIN
        const supplierGstins = {};
        for (const row of gstinRows) {
            if (row.billerGstin) supplierGstins[row.biller] = row.billerGstin;
        }

        res.json({
            success: true,
            data: {
                suppliers:     suppliers.filter(Boolean).sort(),
                supplierGstins,
                descriptions:  descriptions.filter(Boolean).sort(),
            },
        });
    } catch (err) {
        console.error('[Purchase] getPurchaseSuggestions error:', err);
        res.status(500).json({ success: false, message: 'Error fetching suggestions', error: err.message });
    }
};

// ─── GET /api/purchases ───────────────────────────────────────────────────────
exports.getPurchases = async (req, res) => {
    try {
        const Purchase = getPurchaseModel();
        const {
            metalType, biller, startDate, endDate,
            page = 1, limit = 20, sort = 'date_desc',
        } = req.query;

        // Build filter
        const filter = {};
        if (metalType) filter.metal_type = { $regex: `^${escapeRx(metalType)}$`, $options: 'i' };
        if (biller) filter.biller = { $regex: biller, $options: 'i' };
        if (startDate || endDate) {
            // the website keeps the invoice date as 'YYYY-MM-DD' text, so a whole end day is included by comparing days
            filter.invoice_date = {};
            if (startDate) filter.invoice_date.$gte = ymdIST(startDate);
            if (endDate) filter.invoice_date.$lte = ymdIST(endDate);
        }

        const safePage  = Math.max(1, parseInt(page));
        const safeLimit = Math.min(parseInt(limit) || 20, 1000); // 1000-doc safety cap
        const skip      = (safePage - 1) * safeLimit;

        // Run list + count + aggregate totals in parallel
        const [rows, total, totals] = await Promise.all([
            Purchase.find(filter)
                .sort(buildSort(sort))
                .skip(skip)
                .limit(safeLimit)
                .lean(),
            Purchase.countDocuments(filter),
            // Aggregate totals MATCHING the current filter (like legacy PHP)
            Purchase.aggregate([
                { $match: filter },
                {
                    $group: {
                        _id: { $toLower: '$metal_type' },
                        totalWeight: { $sum: { $toDouble: '$quantity' } },
                        totalAmount: { $sum: taxableExpr },
                        count: { $sum: 1 },
                    },
                },
            ]),
        ]);
        const purchases = rows.map(toApp);

        // Shape aggregate output into a flat map: { gold: {...}, silver: {...} }
        const metalTotals = {};
        totals.forEach((t) => {
            metalTotals[t._id] = {
                totalWeight: parseFloat(t.totalWeight.toFixed(3)),
                totalAmount: parseFloat(t.totalAmount.toFixed(2)),
                count: t.count,
            };
        });

        res.json({
            success: true,
            data: {
                purchases,
                pagination: {
                    total,
                    page: safePage,
                    limit: safeLimit,
                    pages: Math.ceil(total / safeLimit),
                },
                // Aggregate totals for the header summary bar (matches PHP $aggregate)
                metalTotals,
            },
        });
    } catch (err) {
        console.error('[Purchase] getPurchases error:', err);
        res.status(500).json({ success: false, message: 'Error fetching purchases', error: err.message });
    }
};

// ─── GET /api/purchases/:id ───────────────────────────────────────────────────
exports.getPurchase = async (req, res) => {
    try {
        const Purchase = getPurchaseModel();
        const doc = await Purchase.findById(req.params.id).lean();
        if (!doc) {
            return res.status(404).json({ success: false, message: 'Purchase not found' });
        }
        res.json({ success: true, data: { purchase: toApp(doc) } });
    } catch (err) {
        console.error('[Purchase] getPurchase error:', err);
        res.status(500).json({ success: false, message: 'Error fetching purchase', error: err.message });
    }
};

// ─── POST /api/purchases ──────────────────────────────────────────────────────
// Price a purchase from its valuation input with the Stock Setting purchase rules. The goods carry the purchase GST (3%);
// the hallmark fee is its own charge with its own GST when the rule "hallmark GST" is on (split CGST+SGST or IGST).
async function priceValuation(valuationIn, txType) {
    const Rules = require('../services/stockRules');
    const stored = await require('../models/AppStockSettings').findOne({ key: 'main' }).lean();
    const inp = { gross: valuationIn.gross, less: valuationIn.less, net: valuationIn.net, purity: valuationIn.purity, wastage: valuationIn.wastage, rate: valuationIn.rate, labourRate: valuationIn.labourRate, pieces: valuationIn.pieces, certification: valuationIn.certification, interstate: txType === 'inter-state' };
    const out = require('../services/stockValuation').computePurchase(inp, Rules.resolve(stored));
    if (!(out.net > 0) || !(Number(inp.rate) > 0) || !(out.goodsTaxable > 0)) return { error: 'Enter the weight and the rate for the valuation' };
    const inter = txType === 'inter-state';
    const hall = { charge: out.hallmarkCharge, gst: out.hallmarkGst, cgst: inter ? 0 : Math.round(out.hallmarkGst * 50) / 100, sgst: inter ? 0 : Math.round(out.hallmarkGst * 50) / 100, igst: inter ? out.hallmarkGst : 0 };
    return { qty: out.net, rate: Number(inp.rate), totalAmount: out.goodsTaxable, valuation: { input: inp, result: out }, hall };
}

// The GST fields of a purchase: the goods at the purchase rate plus (if any) the hallmark fee and its GST (input credit too).
function gstFields(gst, hall) {
    const h = hall || { charge: 0, gst: 0, cgst: 0, sgst: 0, igst: 0 };
    const r2 = (n) => Math.round((n + Number.EPSILON) * 100) / 100;
    return {
        transactionType: gst.cgst ? 'intra-state' : 'inter-state',
        gstRate: gst.gstRate,
        cgstAmount: r2((gst.cgst?.amount || 0) + h.cgst),
        sgstAmount: r2((gst.sgst?.amount || 0) + h.sgst),
        igstAmount: r2((gst.igst?.amount || 0) + h.igst),
        totalGst: r2(gst.totalGst + h.gst),
        totalPayable: r2(gst.totalPayable + h.charge + h.gst),
        hsnCode: gst.hsnCode,
        itcCgst: r2(gst.itcCgst + h.cgst),
        itcSgst: r2(gst.itcSgst + h.sgst),
        itcIgst: r2(gst.itcIgst + h.igst),
        totalItc: r2(gst.totalItc + h.gst),
        effectiveCost: r2(gst.effectiveCost + h.charge),
        tdsApplicable: gst.tdsApplicable,
        tdsRate: gst.tdsRate,
        tdsAmount: gst.tdsAmount,
        netPayable: r2(gst.netPayable + h.charge + h.gst),
    };
}

// POST /api/purchases/calculate : what a purchase would come to (valuation + GST + ITC + TDS), nothing is saved.
// Body as for create: { quantity, rate, totalAmount? , transactionType?, valuation? }.
exports.calculate = async (req, res) => {
    try {
        const { quantity, rate, totalAmount: totalAmountRaw, transactionType, valuation: valuationIn } = req.body || {};
        let qty = parseFloat(quantity);
        let rateVal = parseFloat(rate);
        let totalAmount = totalAmountRaw != null && totalAmountRaw !== '' ? parseFloat(totalAmountRaw) : parseFloat((qty * rateVal).toFixed(2));
        const gstConfig = await getActiveGstConfig();
        const txType = transactionType || gstConfig.defaultTransactionType || 'intra-state';
        let valuation = null, hall = null;
        if (valuationIn && typeof valuationIn === 'object') {
            const v = await priceValuation(valuationIn, txType);
            if (v.error) return res.status(400).json({ success: false, message: v.error });
            qty = v.qty; rateVal = v.rate; totalAmount = v.totalAmount; valuation = v.valuation; hall = v.hall;
        }
        if (!(totalAmount > 0)) return res.status(400).json({ success: false, message: 'Enter the weight and the rate, or the taxable amount' });
        const gf = gstFields(calculateGST(totalAmount, gstConfig, txType), hall);
        res.json({ success: true, data: { quantity: qty, rate: rateVal, totalAmount, valuation: valuation && valuation.result, ...gf } });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Error calculating the purchase' });
    }
};

exports.createPurchase = async (req, res) => {
    try {
        const Purchase    = getPurchaseModel();

        const {
            invoiceDate, invoiceNumber, metalType, biller,
            quantity, rate,
            // total_amount: use provided value (invoice taxable value as per bill);
            // if absent, auto-compute from qty × rate
            totalAmount: totalAmountRaw,
            transactionType,
            billerGstin = '',
            description = '',
            remarks = '',
            attachmentMeta = [],
            valuation: valuationIn,
        } = req.body;

        // ── Mandatory field validation ─────────────────────────────────────
        const missing = [];
        if (!invoiceDate)     missing.push('invoiceDate');
        if (!invoiceNumber)   missing.push('invoiceNumber');
        if (!metalType)       missing.push('metalType');
        if (!biller)          missing.push('biller');
        if (quantity == null) missing.push('quantity');
        if (rate == null)     missing.push('rate');
        if (missing.length > 0) {
            return res.status(400).json({
                success: false,
                message: `Missing required fields: ${missing.join(', ')}`,
            });
        }

        let qty     = parseFloat(quantity);
        let rateVal = parseFloat(rate);
        // Use provided totalAmount (taxable value per invoice); else compute from qty × rate
        let totalAmount = totalAmountRaw != null
            ? parseFloat(totalAmountRaw)
            : parseFloat((qty * rateVal).toFixed(2));

        // Purchase valuation (Stock Setting > Purchase rules): the server works the amount out itself from the weights
        const gstConfig = await getActiveGstConfig();
        const txType = transactionType || gstConfig.defaultTransactionType || 'intra-state';
        let valuation = null, hall = null;
        if (valuationIn && typeof valuationIn === 'object') {
            const v = await priceValuation(valuationIn, txType);
            if (v.error) return res.status(400).json({ success: false, message: v.error });
            qty = v.qty; rateVal = v.rate; totalAmount = v.totalAmount; valuation = v.valuation; hall = v.hall;
        }

        // ── Duplicate invoice check (no self-exclusion needed for create) ──
        const existing = await Purchase.findOne({ invoice_number: invoiceNumber.trim().toUpperCase() }).lean();
        if (existing) {
            return res.status(409).json({
                success: false,
                message: `Invoice number "${invoiceNumber}" already exists. Duplicate entry prevented.`,
                duplicateId: existing._id,
            });
        }

        // ── GST calculation ────────────────────────────────────────────────
        const gst = calculateGST(parseFloat(totalAmount), gstConfig, txType);
        const gf = gstFields(gst, hall);

        // ── The shop's calendar day, in the website's 'YYYY-MM-DD' form ────
        const invoiceYmd = ymdIST(invoiceDate);
        if (!invoiceYmd) return res.status(400).json({ success: false, message: 'The invoice date is not a valid date' });
        const normalizedInvoiceDate = dayAsDate(invoiceYmd);
        const now = new Date();
        const byId = String(req.user.id);
        const byName = req.user.name || req.user.mobile || '';

        // ── Derive attachment URLs array from meta (back-compat) ───────────
        const attachments = attachmentMeta.map((a) => a.url);

        // ── Create purchase document ───────────────────────────────────────
        const created = await Purchase.create({
            // the website's own fields (what the old site reads and shows)
            invoice_date: invoiceYmd,
            invoice_number: invoiceNumber.trim().toUpperCase(),
            metal_type: websiteMetal(metalType),
            biller: biller.trim(),
            description: description.trim(),
            quantity: qty,
            rate: rateVal,
            total_amount: gf.totalPayable,      // the invoice total, GST included: what the website calls total_amount
            created_at: now, created_ist: istStamp(now), created_by: byId, created_by_name: byName,
            updated_at: now, updated_ist: istStamp(now), updated_by: byId, updated_by_name: byName,
            // what only the app records
            totalAmount,                        // taxable value
            billerGstin: billerGstin.trim().toUpperCase(),
            remarks: remarks.trim(),
            valuation,
            ...gf,      // GST, ITC (input credit), TDS 194Q and net payable, incl. the hallmark fee when there is one
            attachments,
            attachmentMeta,
            source: 'app',
        });
        const purchase = toApp(created);


        require('../services/audit').record(req, 'purchase', purchase._id, `${purchase.invoiceNumber} · ${purchase.biller}`, 'created', [{ field: 'metal', to: `${purchase.metalType} ${purchase.quantity}g` }, { field: 'payable', to: String(purchase.totalPayable) }]);
        res.status(201).json({
            success: true,
            message: 'Purchase entry created successfully',
            data: { purchase },
        });
    } catch (err) {
        console.error('[Purchase] createPurchase error:', err);
        res.status(500).json({ success: false, message: 'Error creating purchase', error: err.message });
    }
};

// ─── PUT /api/purchases/:id ───────────────────────────────────────────────────
exports.updatePurchase = async (req, res) => {
    try {
        const Purchase = getPurchaseModel();
        const doc = await Purchase.findById(req.params.id);
        if (!doc) {
            return res.status(404).json({ success: false, message: 'Purchase not found' });
        }
        const purchase = toApp(doc);   // the API's names; changes are written to the stored (website) fields below

        // ── Duplicate invoice check excluding own ID ($ne) — mirrors PHP logic ──
        if (req.body.invoiceNumber) {
            const dup = await Purchase.findOne({
                invoice_number: req.body.invoiceNumber.trim().toUpperCase(),
                _id: { $ne: doc._id },
            }).lean();
            if (dup) {
                return res.status(409).json({
                    success: false,
                    message: `Invoice number "${req.body.invoiceNumber}" already exists on another entry.`,
                    duplicateId: dup._id,
                });
            }
            doc.invoice_number = req.body.invoiceNumber.trim().toUpperCase();
        }

        // Fields the user is allowed to update
        const before = { biller: purchase.biller, rate: purchase.rate, totalAmount: purchase.totalAmount, quantity: purchase.quantity };
        const editable = ['biller', 'description', 'remarks', 'rate', 'attachments', 'attachmentMeta'];
        editable.forEach((field) => {
            if (req.body[field] !== undefined) doc[field] = req.body[field];   // same name on both sides
        });

        // Sync flat URL array if attachmentMeta changed
        if (req.body.attachmentMeta) {
            doc.attachments = req.body.attachmentMeta.map((a) => a.url);
        }

        // Change of the valuation: weights / purity / wastage / labour / rate. Amount, GST and input credit are
        // worked out again. Refused once the GSTR-3B of that period is filed (it would change a filed return).
        if (req.body.valuation && typeof req.body.valuation === 'object') {
            const GstSvc = require('../services/gstReports');
            const ymd = doc.invoice_date;
            const keys = [GstSvc.periodKey('monthly', ymd), GstSvc.periodKey('quarterly', ymd)];
            const filed = await require('../services/gstFilings').findOne({ type: 'GSTR-3B', periods: keys });
            if (filed) return res.status(409).json({ success: false, message: `The GSTR-3B for ${filed.period} is already filed. Record a correction in the next return instead of changing this purchase.` });
            const gstConfig = await getActiveGstConfig();
            const v = await priceValuation(req.body.valuation, purchase.transactionType || 'intra-state');
            if (v.error) return res.status(400).json({ success: false, message: v.error });
            const gst = calculateGST(v.totalAmount, gstConfig, purchase.transactionType || 'intra-state');
            const gf2 = gstFields(gst, v.hall);
            Object.assign(doc, { quantity: v.qty, rate: v.rate, totalAmount: v.totalAmount, valuation: v.valuation }, gf2, { total_amount: gf2.totalPayable });
        }

        const nowU = new Date();
        doc.updated_at = nowU;
        doc.updated_ist = istStamp(nowU);
        doc.updated_by = String(req.user.id);
        doc.updated_by_name = req.user.name || req.user.mobile || '';
        await doc.save();
        const after = toApp(doc);

        const changed = ['biller', 'rate', 'totalAmount', 'quantity']
            .filter((k) => String(before[k] ?? '') !== String(after[k] ?? ''))
            .map((k) => ({ field: k, from: before[k], to: after[k] }));
        if (changed.length) require('../services/audit').record(req, 'purchase', after._id, `${after.invoiceNumber} · ${after.biller}`, 'updated', changed);

        res.json({ success: true, message: 'Purchase updated', data: { purchase: after } });
    } catch (err) {
        console.error('[Purchase] updatePurchase error:', err);
        res.status(500).json({ success: false, message: 'Error updating purchase', error: err.message });
    }
};

// ─── DELETE /api/purchases/:id ────────────────────────────────────────────────
exports.deletePurchase = async (req, res) => {
    try {
        const Purchase   = getPurchaseModel();

        const doc = await Purchase.findById(req.params.id);
        if (!doc) {
            return res.status(404).json({ success: false, message: 'Purchase not found' });
        }
        const purchase = toApp(doc);

        // The website lists every purchase it finds and has no "deleted" flag, so the record is removed for real
        // (one list for the app and the website); a full copy is kept in app_trash.
        await require('../services/trash').keep(req, 'purchases', doc, `${purchase.invoiceNumber} · ${purchase.biller}`);
        await Purchase.deleteOne({ _id: doc._id });

        require('../services/audit').record(req, 'purchase', purchase._id, `${purchase.invoiceNumber} · ${purchase.biller}`, 'removed', [{ field: 'copy', to: 'kept in app_trash' }]);
        res.json({ success: true, message: 'Purchase deleted' });
    } catch (err) {
        console.error('[Purchase] deletePurchase error:', err);
        res.status(500).json({ success: false, message: 'Error deleting purchase', error: err.message });
    }
};

// ─── GET /api/purchases/preview-gst ──────────────────────────────────────────
exports.previewGst = async (req, res) => {
    try {
        const { totalAmount, transactionType } = req.query;
        if (!totalAmount) {
            return res.status(400).json({ success: false, message: 'totalAmount is required' });
        }
        const gstConfig = await getActiveGstConfig();
        const gst = calculateGST(parseFloat(totalAmount), gstConfig, transactionType || 'intra-state');
        res.json({ success: true, data: gst });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Error calculating GST', error: err.message });
    }
};

// ─── GET /api/purchases/itc-summary ──────────────────────────────────────────
/**
 * Returns per-quarter ITC summary for a given Indian financial year.
 *
 * Indian FY quarters (prefix: Apr 1 → Mar 31):
 *   Q1: Apr – Jun   (months 4,5,6)
 *   Q2: Jul – Sep   (months 7,8,9)
 *   Q3: Oct – Dec   (months 10,11,12)
 *   Q4: Jan – Mar   (months 1,2,3 of next calendar year)
 *
 * Query params:
 *   fy  — financial year string, e.g. "2025-26" (default: current FY)
 *
 * Response shape:
 *   data: {
 *     fy: "2025-26",
 *     quarters: [
 *       { quarter: "Q1", label: "Apr–Jun 2025", from, to,
 *         byMetal: { gold: { invoices, totalAmount, totalGst, totalItc, totalWeight }, ... },
 *         totals: { invoices, totalAmount, totalGst, totalItc, itcCgst, itcSgst, itcIgst, totalWeight } },
 *       ...
 *     ],
 *     yearTotals: { invoices, totalAmount, totalGst, totalItc, itcCgst, itcSgst, itcIgst, totalWeight }
 *   }
 */
exports.getItcSummary = async (req, res) => {
    try {
        const Purchase = getPurchaseModel();

        // ── Determine financial year ───────────────────────────────────────
        const now = new Date();
        const curMonth = now.getMonth() + 1; // 1-12
        const curYear  = now.getFullYear();
        const defaultFyStart = curMonth >= 4 ? curYear : curYear - 1;
        const defaultFy = `${defaultFyStart}-${String(defaultFyStart + 1).slice(-2)}`;

        const fyParam = (req.query.fy || defaultFy).trim(); // e.g. "2025-26"
        const fyMatch = fyParam.match(/^(\d{4})-(\d{2,4})$/);
        if (!fyMatch) {
            return res.status(400).json({
                success: false,
                message: 'Invalid fy format. Use "YYYY-YY" e.g. "2025-26"',
            });
        }

        const fyStartYear = parseInt(fyMatch[1]);
        const fyEndYear   = fyStartYear + 1;

        // Indian FY: Apr 1 fyStartYear → Mar 31 fyEndYear
        const fyStart = new Date(`${fyStartYear}-04-01`);
        const fyEnd   = new Date(`${fyEndYear}-03-31T23:59:59.999Z`);

        // ── Define 4 quarters ─────────────────────────────────────────────
        const quarters = [
            {
                q: 'Q1', label: `Apr–Jun ${fyStartYear}`,
                from: new Date(`${fyStartYear}-04-01`),
                to:   new Date(`${fyStartYear}-06-30T23:59:59.999Z`),
            },
            {
                q: 'Q2', label: `Jul–Sep ${fyStartYear}`,
                from: new Date(`${fyStartYear}-07-01`),
                to:   new Date(`${fyStartYear}-09-30T23:59:59.999Z`),
            },
            {
                q: 'Q3', label: `Oct–Dec ${fyStartYear}`,
                from: new Date(`${fyStartYear}-10-01`),
                to:   new Date(`${fyStartYear}-12-31T23:59:59.999Z`),
            },
            {
                q: 'Q4', label: `Jan–Mar ${fyEndYear}`,
                from: new Date(`${fyEndYear}-01-01`),
                to:   new Date(`${fyEndYear}-03-31T23:59:59.999Z`),
            },
        ];

        // ── Single aggregate for the full FY, group by (quarter, metal) ────
        const pipeline = [
            {
                // the website keeps the invoice date as 'YYYY-MM-DD' text: days compare as text
                $match: { invoice_date: { $gte: `${fyStartYear}-04-01`, $lte: `${fyEndYear}-03-31` } },
            },
            { $addFields: { month: { $toInt: { $substrBytes: ['$invoice_date', 5, 2] } } } },
            {
                $addFields: {
                    // Map calendar month to Indian FY quarter number
                    quarterNum: {
                        $switch: {
                            branches: [
                                { case: { $in: ['$month', [4, 5, 6]] },  then: 1 },
                                { case: { $in: ['$month', [7, 8, 9]] },  then: 2 },
                                { case: { $in: ['$month', [10, 11, 12]] }, then: 3 },
                                { case: { $in: ['$month', [1, 2, 3]] },  then: 4 },
                            ],
                            default: 0,
                        },
                    },
                },
            },
            {
                // GST / input credit only count where the app recorded the split (an old website purchase has none)
                $group: {
                    _id: { quarter: '$quarterNum', metal: { $toLower: '$metal_type' } },
                    invoices:    { $sum: 1 },
                    totalAmount: { $sum: taxableExpr },
                    totalGst:    { $sum: sumIfSplit('totalGst') },
                    itcCgst:     { $sum: sumIfSplit('itcCgst') },
                    itcSgst:     { $sum: sumIfSplit('itcSgst') },
                    itcIgst:     { $sum: sumIfSplit('itcIgst') },
                    totalItc:    { $sum: sumIfSplit('totalItc') },
                    totalWeight: { $sum: { $toDouble: '$quantity' } },
                },
            },
            { $sort: { '_id.quarter': 1, '_id.metal': 1 } },
        ];

        const rows = await Purchase.aggregate(pipeline);

        // ── Build response structure ───────────────────────────────────────
        const zero = () => ({
            invoices: 0, totalAmount: 0, totalGst: 0,
            itcCgst: 0, itcSgst: 0, itcIgst: 0,
            totalItc: 0, totalWeight: 0,
        });
        const add = (a, b) => {
            a.invoices    += b.invoices;
            a.totalAmount += b.totalAmount;
            a.totalGst    += b.totalGst;
            a.itcCgst     += b.itcCgst;
            a.itcSgst     += b.itcSgst;
            a.itcIgst     += b.itcIgst;
            a.totalItc    += b.totalItc;
            a.totalWeight += b.totalWeight;
        };
        const round2 = (n) => Math.round(n * 100) / 100;
        const round3 = (n) => Math.round(n * 1000) / 1000;
        const fmtRow = (r) => ({
            invoices:    r.invoices,
            totalAmount: round2(r.totalAmount),
            totalGst:    round2(r.totalGst),
            itcCgst:     round2(r.itcCgst),
            itcSgst:     round2(r.itcSgst),
            itcIgst:     round2(r.itcIgst),
            totalItc:    round2(r.totalItc),
            totalWeight: round3(r.totalWeight),
        });

        const yearTotals = zero();
        const quarterMap = {}; // { 1: { byMetal: {}, totals: {} }, ... }

        for (const row of rows) {
            const qn    = row._id.quarter;
            const metal = row._id.metal;
            if (!quarterMap[qn]) quarterMap[qn] = { byMetal: {}, totals: zero() };

            quarterMap[qn].byMetal[metal] = fmtRow(row);
            add(quarterMap[qn].totals, row);
            add(yearTotals, row);
        }

        const result = quarters.map((q, idx) => {
            const qn   = idx + 1;
            const data = quarterMap[qn] || { byMetal: {}, totals: zero() };
            return {
                quarter: q.q,
                label:   q.label,
                from:    q.from.toISOString().split('T')[0],
                to:      q.to.toISOString().split('T')[0],
                byMetal: data.byMetal,
                totals:  fmtRow(data.totals),
            };
        });

        res.json({
            success: true,
            data: {
                fy:          fyParam,
                quarters:    result,
                yearTotals:  fmtRow(yearTotals),
            },
        });
    } catch (err) {
        console.error('[Purchase] getItcSummary error:', err);
        res.status(500).json({ success: false, message: 'Error generating ITC summary', error: err.message });
    }
};
