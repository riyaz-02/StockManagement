/**
 * purchaseController.js — Supplier purchase entry management
 *
 * Uses shopmanage DB (separate connection from jewellery_stock).
 * On every new purchase, auto-creates a stock_entry credit record.
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

const { getShopmanageConnection } = require('../config/db');
const {
    calculateGST,
    getNowIST,
    normalizeToIST,
} = require('../utils/gstHelpers');

// ── Lazy model getters ────────────────────────────────────────────────────────
let _Purchase, _StockEntry, _GstConfig;

function getPurchaseModel() {
    if (!_Purchase) _Purchase = require('../models/Purchase')(getShopmanageConnection());
    return _Purchase;
}
function getStockEntryModel() {
    if (!_StockEntry) _StockEntry = require('../models/StockEntry')(getShopmanageConnection());
    return _StockEntry;
}
function getGstConfigModel() {
    if (!_GstConfig) _GstConfig = require('../models/GstConfig')(getShopmanageConnection());
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
        case 'date_asc':       return { invoiceDate: 1 };
        case 'amount_desc':    return { totalAmount: -1 };
        case 'amount_asc':     return { totalAmount: 1 };
        case 'date_desc':
        default:               return { invoiceDate: -1 };
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
            Purchase.distinct('biller',      { isDeleted: false }),
            Purchase.distinct('description', { isDeleted: false, description: { $ne: '' } }),
            Purchase.find(
                { isDeleted: false, billerGstin: { $nin: ['', null] } },
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
        const filter = { isDeleted: false };
        if (metalType) filter.metalType = metalType.toLowerCase();
        if (biller) filter.biller = { $regex: biller, $options: 'i' };
        if (startDate || endDate) {
            filter.invoiceDate = {};
            if (startDate) filter.invoiceDate.$gte = new Date(startDate);
            if (endDate) {
                // Include the full end day (legacy: $lte end of day)
                const end = new Date(endDate);
                end.setHours(23, 59, 59, 999);
                filter.invoiceDate.$lte = end;
            }
        }

        const safePage  = Math.max(1, parseInt(page));
        const safeLimit = Math.min(parseInt(limit) || 20, 1000); // 1000-doc safety cap
        const skip      = (safePage - 1) * safeLimit;

        // Run list + count + aggregate totals in parallel
        const [purchases, total, totals] = await Promise.all([
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
                        _id: '$metalType',
                        totalWeight: { $sum: '$quantity' },
                        totalAmount: { $sum: '$totalAmount' },
                        count: { $sum: 1 },
                    },
                },
            ]),
        ]);

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
        const purchase = await Purchase.findById(req.params.id).lean();
        if (!purchase || purchase.isDeleted) {
            return res.status(404).json({ success: false, message: 'Purchase not found' });
        }
        res.json({ success: true, data: { purchase } });
    } catch (err) {
        console.error('[Purchase] getPurchase error:', err);
        res.status(500).json({ success: false, message: 'Error fetching purchase', error: err.message });
    }
};

// ─── POST /api/purchases ──────────────────────────────────────────────────────
exports.createPurchase = async (req, res) => {
    try {
        const Purchase    = getPurchaseModel();
        const StockEntry  = getStockEntryModel();

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

        const qty     = parseFloat(quantity);
        const rateVal = parseFloat(rate);
        // Use provided totalAmount (taxable value per invoice); else compute from qty × rate
        const totalAmount = totalAmountRaw != null
            ? parseFloat(totalAmountRaw)
            : parseFloat((qty * rateVal).toFixed(2));

        // ── Duplicate invoice check (no self-exclusion needed for create) ──
        const existing = await Purchase.findOne({
            invoiceNumber: invoiceNumber.trim().toUpperCase(),
            isDeleted: false,
        });
        if (existing) {
            return res.status(409).json({
                success: false,
                message: `Invoice number "${invoiceNumber}" already exists. Duplicate entry prevented.`,
                duplicateId: existing._id,
            });
        }

        // ── GST calculation ────────────────────────────────────────────────
        const gstConfig = await getActiveGstConfig();
        const txType = transactionType || gstConfig.defaultTransactionType || 'intra-state';
        const gst = calculateGST(parseFloat(totalAmount), gstConfig, txType);

        // ── Normalize dates to IST ─────────────────────────────────────────
        const normalizedInvoiceDate = normalizeToIST(invoiceDate);
        const createdAtIST = getNowIST();

        // ── Derive attachment URLs array from meta (back-compat) ───────────
        const attachments = attachmentMeta.map((a) => a.url);

        // ── Create purchase document ───────────────────────────────────────
        const purchase = await Purchase.create({
            invoiceDate: normalizedInvoiceDate,
            invoiceNumber: invoiceNumber.trim().toUpperCase(),
            metalType: metalType.toLowerCase(),
            biller: biller.trim(),
            billerGstin: billerGstin.trim().toUpperCase(),
            quantity: qty,
            rate: rateVal,
            totalAmount,
            transactionType: gst.cgst ? 'intra-state' : 'inter-state',
            gstRate: gst.gstRate,
            cgstAmount: gst.cgst?.amount || 0,
            sgstAmount: gst.sgst?.amount || 0,
            igstAmount: gst.igst?.amount || 0,
            totalGst: gst.totalGst,
            totalPayable: gst.totalPayable,
            hsnCode: gst.hsnCode,
            // ITC — GST paid to supplier, claimable from credit ledger
            itcCgst: gst.itcCgst,
            itcSgst: gst.itcSgst,
            itcIgst: gst.itcIgst,
            totalItc: gst.totalItc,
            effectiveCost: gst.effectiveCost,
            // TDS (194Q)
            tdsApplicable: gst.tdsApplicable,
            tdsRate: gst.tdsRate,
            tdsAmount: gst.tdsAmount,
            netPayable: gst.netPayable,
            description: description.trim(),
            remarks: remarks.trim(),
            attachments,
            attachmentMeta,
            invoiceDateIST: normalizedInvoiceDate.toLocaleDateString('en-IN', { timeZone: 'Asia/Kolkata' }),
            createdAtIST,
            createdBy: req.user.id,
            createdByName: req.user.name || req.user.mobile || '',
            updatedBy: req.user.id,
            updatedByName: req.user.name || req.user.mobile || '',
        });


        // ── Auto-create credit stock ledger entry ──────────────────────────
        await StockEntry.create({
            entryDate: normalizedInvoiceDate,
            metalType: metalType.toLowerCase(),
            entryType: 'credit',
            weightGrams: qty,
            description: description.trim() ||
                `Purchase from ${biller} (Invoice: ${invoiceNumber})`,
            referenceId: purchase._id,
            referenceType: 'purchase',
            status: 'active',
            entryDateIST: normalizedInvoiceDate.toLocaleDateString('en-IN', { timeZone: 'Asia/Kolkata' }),
            createdBy: req.user.id,
        });

        res.status(201).json({
            success: true,
            message: 'Purchase entry created successfully',
            data: { purchase },
        });
    } catch (err) {
        if (err.code === 11000 && err.keyPattern?.invoiceNumber) {
            return res.status(409).json({
                success: false,
                message: 'Invoice number already exists. Duplicate entry prevented.',
            });
        }
        console.error('[Purchase] createPurchase error:', err);
        res.status(500).json({ success: false, message: 'Error creating purchase', error: err.message });
    }
};

// ─── PUT /api/purchases/:id ───────────────────────────────────────────────────
exports.updatePurchase = async (req, res) => {
    try {
        const Purchase = getPurchaseModel();
        const purchase = await Purchase.findById(req.params.id);
        if (!purchase || purchase.isDeleted) {
            return res.status(404).json({ success: false, message: 'Purchase not found' });
        }

        // ── Duplicate invoice check excluding own ID ($ne) — mirrors PHP logic ──
        if (req.body.invoiceNumber) {
            const dup = await Purchase.findOne({
                invoiceNumber: req.body.invoiceNumber.trim().toUpperCase(),
                isDeleted: false,
                _id: { $ne: purchase._id },
            });
            if (dup) {
                return res.status(409).json({
                    success: false,
                    message: `Invoice number "${req.body.invoiceNumber}" already exists on another entry.`,
                    duplicateId: dup._id,
                });
            }
            purchase.invoiceNumber = req.body.invoiceNumber.trim().toUpperCase();
        }

        // Fields the user is allowed to update
        const editable = ['biller', 'description', 'remarks', 'rate', 'attachments', 'attachmentMeta'];
        editable.forEach((field) => {
            if (req.body[field] !== undefined) purchase[field] = req.body[field];
        });

        // Sync flat URL array if attachmentMeta changed
        if (req.body.attachmentMeta) {
            purchase.attachments = req.body.attachmentMeta.map((a) => a.url);
        }

        purchase.updatedBy = req.user.id;
        await purchase.save();

        res.json({ success: true, message: 'Purchase updated', data: { purchase } });
    } catch (err) {
        console.error('[Purchase] updatePurchase error:', err);
        res.status(500).json({ success: false, message: 'Error updating purchase', error: err.message });
    }
};

// ─── DELETE /api/purchases/:id ────────────────────────────────────────────────
exports.deletePurchase = async (req, res) => {
    try {
        const Purchase   = getPurchaseModel();
        const StockEntry = getStockEntryModel();

        const purchase = await Purchase.findById(req.params.id);
        if (!purchase || purchase.isDeleted) {
            return res.status(404).json({ success: false, message: 'Purchase not found' });
        }

        // Soft-delete purchase
        purchase.isDeleted = true;
        purchase.deletedAt = new Date();
        purchase.updatedBy = req.user.id;
        await purchase.save();

        // Soft-delete associated stock ledger entry
        await StockEntry.updateMany(
            { referenceId: purchase._id, referenceType: 'purchase' },
            { status: 'deleted' }
        );

        res.json({ success: true, message: 'Purchase deleted and stock ledger reversed' });
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
                $match: {
                    isDeleted: false,
                    invoiceDate: { $gte: fyStart, $lte: fyEnd },
                },
            },
            {
                $addFields: {
                    // Map calendar month to Indian FY quarter number
                    month: { $month: '$invoiceDate' },
                    quarterNum: {
                        $switch: {
                            branches: [
                                { case: { $in: [{ $month: '$invoiceDate' }, [4, 5, 6]] },  then: 1 },
                                { case: { $in: [{ $month: '$invoiceDate' }, [7, 8, 9]] },  then: 2 },
                                { case: { $in: [{ $month: '$invoiceDate' }, [10, 11, 12]] }, then: 3 },
                                { case: { $in: [{ $month: '$invoiceDate' }, [1, 2, 3]] },  then: 4 },
                            ],
                            default: 0,
                        },
                    },
                },
            },
            {
                $group: {
                    _id: { quarter: '$quarterNum', metal: '$metalType' },
                    invoices:    { $sum: 1 },
                    totalAmount: { $sum: '$totalAmount' },
                    totalGst:    { $sum: '$totalGst' },
                    itcCgst:     { $sum: '$itcCgst' },
                    itcSgst:     { $sum: '$itcSgst' },
                    itcIgst:     { $sum: '$itcIgst' },
                    totalItc:    { $sum: '$totalItc' },
                    totalWeight: { $sum: '$quantity' },
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
