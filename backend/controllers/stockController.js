/**
 * stockController.js — Stock weight dashboard, bulk weight management,
 *                      daily summary, and reconciliation
 *
 * Barcoded stock is read from jewellery_stock (primary mongoose connection).
 * Bulk weights, stock entries, purchases are from shopmanage DB.
 *
 * Reconciliation formula (from legacy system):
 *   adjustedPurchase(gold)   = purchasedGrams(gold)   * 1.10  (+10%)
 *   adjustedPurchase(silver) = purchasedGrams(silver)  * 1.20  (+20%)
 *   expectedDebit            = adjustedPurchase - ledgerTotal
 *   discrepancy              = expectedDebit - totalSold - wastage
 *   ALERT if |discrepancy| > 1.0g
 */

'use strict';

const mongoose = require('mongoose');
const { getShopmanageConnection } = require('../config/db');
const { getNowIST, normalizeToIST } = require('../utils/gstHelpers');

// Primary DB model (existing)
const Item = require('../models/Item');

// Lazy shopmanage model getters
let _BulkWeight, _StockEntry, _Purchase;
function getBulkWeightModel() {
    if (!_BulkWeight) _BulkWeight = require('../models/BulkWeight')(getShopmanageConnection());
    return _BulkWeight;
}
function getStockEntryModel() {
    if (!_StockEntry) _StockEntry = require('../models/StockEntry')(getShopmanageConnection());
    return _StockEntry;
}
function getPurchaseModel() {
    if (!_Purchase) _Purchase = require('../models/Purchase')(getShopmanageConnection());
    return _Purchase;
}

// Purchase weight inflation multipliers (business rules from legacy system)
const PURCHASE_MULTIPLIERS = { gold: 1.10, silver: 1.20 };
const DEFAULT_MULTIPLIER = 1.0;

// ─── GET /api/stock/dashboard ────────────────────────────────────────────────
exports.getDashboard = async (req, res) => {
    try {
        const BulkWeight = getBulkWeightModel();

        // 1. Barcoded stock from jewellery_stock DB
        // Statuses that count as physically-in-shop.
        // action_needed = quick-added items awaiting details completion; still on the rack.
        const inShopStatuses = ['active', 'action_needed', 'booked', 'in_repair', 'UNDER_REPAIR', 'no_sell'];

        const barcodedAgg = await Item.aggregate([
            {
                $match: {
                    isDeleted: { $ne: true },
                    status: { $in: inShopStatuses },
                },
            },
            {
                $group: {
                    _id: { $toLower: '$metalType' },
                    weightGrams: { $sum: '$netWeight' },
                    count: { $sum: 1 },
                },
            },
        ]);

        // Convert to object keyed by metalType (lowercase)
        const barcodedStock = {};
        barcodedAgg.forEach(({ _id, weightGrams, count }) => {
            if (_id) {
                barcodedStock[_id] = {
                    weightGrams: parseFloat(weightGrams.toFixed(3)),
                    count,
                };
            }
        });

        // 2. Bulk weight entries from shopmanage DB
        const bulkWeights = await BulkWeight.find({ isActive: true }).lean();

        // 3. Compute totals per metal
        const totalStock = {};

        // Start with barcoded
        Object.entries(barcodedStock).forEach(([metal, data]) => {
            totalStock[metal] = parseFloat(data.weightGrams.toFixed(3));
        });

        // Add bulk weights
        bulkWeights.forEach(({ metalType, weightGrams }) => {
            if (!metalType) return;
            const metal = metalType.toLowerCase();
            totalStock[metal] = parseFloat(((totalStock[metal] || 0) + weightGrams).toFixed(3));
        });

        res.json({
            success: true,
            data: {
                barcodedStock,
                bulkWeights,
                totalStock,
                asOf: getNowIST(),
            },
        });
    } catch (err) {
        console.error('[Stock] getDashboard error:', err);
        res.status(500).json({ success: false, message: 'Error fetching stock dashboard', error: err.message });
    }
};

// ─── GET /api/stock/bulk-weights ─────────────────────────────────────────────
exports.getBulkWeights = async (req, res) => {
    try {
        const BulkWeight = getBulkWeightModel();
        const { metalType, isActive } = req.query;

        const filter = {};
        if (metalType) filter.metalType = metalType.toLowerCase();
        if (isActive !== undefined) filter.isActive = isActive === 'true';

        const entries = await BulkWeight.find(filter).sort({ updatedAt: -1 }).lean();
        res.json({ success: true, data: { bulkWeights: entries } });
    } catch (err) {
        console.error('[Stock] getBulkWeights error:', err);
        res.status(500).json({ success: false, message: 'Error fetching bulk weights', error: err.message });
    }
};

// ─── POST /api/stock/bulk-weights ────────────────────────────────────────────
exports.addBulkWeight = async (req, res) => {
    try {
        const BulkWeight = getBulkWeightModel();
        const { metalType, weightGrams, description } = req.body;

        if (!metalType || weightGrams == null || !description) {
            return res.status(400).json({
                success: false,
                message: 'metalType, weightGrams, and description are required',
            });
        }

        const entry = await BulkWeight.create({
            metalType: metalType.toLowerCase(),
            weightGrams: parseFloat(weightGrams),
            description: description.trim(),
            date: new Date(),
            createdBy: req.user.id,
            updatedBy: req.user.id,
        });

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

        const { weightGrams, description, isActive } = req.body;
        if (weightGrams != null) entry.weightGrams = parseFloat(weightGrams);
        if (description != null) entry.description = description.trim();
        if (isActive != null) entry.isActive = isActive;
        entry.updatedBy = req.user.id;
        entry.date = new Date();

        await entry.save();
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
        // Soft-disable instead of hard delete
        entry.isActive = false;
        entry.updatedBy = req.user.id;
        await entry.save();
        res.json({ success: true, message: 'Bulk weight entry removed' });
    } catch (err) {
        console.error('[Stock] deleteBulkWeight error:', err);
        res.status(500).json({ success: false, message: 'Error deleting bulk weight', error: err.message });
    }
};

// ─── GET /api/stock/daily-summary ────────────────────────────────────────────
exports.getDailySummary = async (req, res) => {
    try {
        const StockEntry = getStockEntryModel();
        const { startDate, endDate, metalType } = req.query;

        const match = { status: { $ne: 'deleted' } };
        if (metalType) match.metalType = metalType.toLowerCase();
        if (startDate || endDate) {
            match.entryDate = {};
            if (startDate) match.entryDate.$gte = normalizeToIST(startDate);
            if (endDate) match.entryDate.$lte = normalizeToIST(endDate + 'T23:59:59');
        }

        const agg = await StockEntry.aggregate([
            { $match: match },
            {
                $group: {
                    _id: {
                        date: {
                            $dateToString: { format: '%Y-%m-%d', date: '$entryDate', timezone: 'Asia/Kolkata' },
                        },
                        metalType: '$metalType',
                        entryType: '$entryType',
                    },
                    totalWeight: { $sum: '$weightGrams' },
                    count: { $sum: 1 },
                },
            },
            { $sort: { '_id.date': -1, '_id.metalType': 1 } },
        ]);

        // Group into { date -> { metal -> { in, out, net } } }
        const summary = {};
        agg.forEach(({ _id, totalWeight }) => {
            const { date, metalType, entryType } = _id;
            if (!summary[date]) summary[date] = {};
            if (!summary[date][metalType]) summary[date][metalType] = { in: 0, out: 0, net: 0 };

            if (entryType === 'credit') {
                summary[date][metalType].in += totalWeight;
                summary[date][metalType].net += totalWeight;
            } else {
                summary[date][metalType].out += totalWeight;
                summary[date][metalType].net -= totalWeight;
            }
        });

        // Round all values
        Object.values(summary).forEach((dayData) => {
            Object.values(dayData).forEach((metalData) => {
                metalData.in = parseFloat(metalData.in.toFixed(3));
                metalData.out = parseFloat(metalData.out.toFixed(3));
                metalData.net = parseFloat(metalData.net.toFixed(3));
            });
        });

        res.json({ success: true, data: { summary } });
    } catch (err) {
        console.error('[Stock] getDailySummary error:', err);
        res.status(500).json({ success: false, message: 'Error fetching daily summary', error: err.message });
    }
};

// ─── GET /api/stock/reconciliation ──────────────────────────────────────────
exports.getReconciliation = async (req, res) => {
    try {
        const StockEntry = getStockEntryModel();
        const Purchase = getPurchaseModel();

        const metals = ['gold', 'silver'];
        const ALERT_THRESHOLD = 1.0; // grams

        const result = {};

        for (const metal of metals) {
            // 1. Total purchased weight from purchases collection
            const purchaseAgg = await Purchase.aggregate([
                { $match: { metalType: metal, isDeleted: false } },
                { $group: { _id: null, totalPurchased: { $sum: '$quantity' } } },
            ]);
            const totalPurchased = purchaseAgg[0]?.totalPurchased || 0;

            // 2. Apply inflation multiplier (business rule from legacy system)
            const multiplier = PURCHASE_MULTIPLIERS[metal] || DEFAULT_MULTIPLIER;
            const adjustedPurchase = parseFloat((totalPurchased * multiplier).toFixed(3));

            // 3. Stock ledger total (credits - debits from stock_entries)
            const ledgerAgg = await StockEntry.aggregate([
                { $match: { metalType: metal, status: { $ne: 'deleted' } } },
                {
                    $group: {
                        _id: '$entryType',
                        total: { $sum: '$weightGrams' },
                    },
                },
            ]);
            const creditTotal = ledgerAgg.find((e) => e._id === 'credit')?.total || 0;
            const debitTotal = ledgerAgg.find((e) => e._id === 'debit')?.total || 0;
            const ledgerTotal = parseFloat((creditTotal - debitTotal).toFixed(3));

            // 4. Sold weight — from jewellery_stock items (status=sold, metalType)
            const soldAgg = await Item.aggregate([
                {
                    $match: {
                        status: 'sold',
                        metalType: { $regex: new RegExp(metal, 'i') },
                        isDeleted: { $ne: true },
                    },
                },
                { $group: { _id: null, totalSold: { $sum: '$netWeight' } } },
            ]);
            const totalSold = soldAgg[0]?.totalSold || 0;

            // 5. Wastage entries from stock_entries
            const wastageAgg = await StockEntry.aggregate([
                { $match: { metalType: metal, referenceType: 'wastage', status: { $ne: 'deleted' } } },
                { $group: { _id: null, totalWastage: { $sum: '$weightGrams' } } },
            ]);
            const totalWastage = wastageAgg[0]?.totalWastage || 0;

            // 6. Discrepancy calculation
            const expectedDebit = parseFloat((adjustedPurchase - ledgerTotal).toFixed(3));
            const discrepancy = parseFloat((expectedDebit - totalSold - totalWastage).toFixed(3));
            const hasAlert = Math.abs(discrepancy) > ALERT_THRESHOLD;

            result[metal] = {
                totalPurchased: parseFloat(totalPurchased.toFixed(3)),
                adjustedPurchase,
                multiplierUsed: multiplier,
                ledgerCredit: parseFloat(creditTotal.toFixed(3)),
                ledgerDebit: parseFloat(debitTotal.toFixed(3)),
                ledgerTotal,
                totalSold: parseFloat(totalSold.toFixed(3)),
                totalWastage: parseFloat(totalWastage.toFixed(3)),
                expectedDebit,
                discrepancy,
                hasAlert,
                alertMessage: hasAlert
                    ? `⚠️ Discrepancy of ${Math.abs(discrepancy).toFixed(3)}g detected in ${metal} stock. Investigate immediately.`
                    : null,
            };
        }

        const anyAlert = Object.values(result).some((m) => m.hasAlert);

        res.json({
            success: true,
            data: {
                reconciliation: result,
                anyAlert,
                alertThresholdGrams: ALERT_THRESHOLD,
                generatedAt: getNowIST(),
            },
        });
    } catch (err) {
        console.error('[Stock] getReconciliation error:', err);
        res.status(500).json({ success: false, message: 'Error running reconciliation', error: err.message });
    }
};
