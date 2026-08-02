/**
 * gstController.js — GST configuration and calculation endpoints
 */

'use strict';

const { getShopmanageConnection } = require('../config/db');
const {
    validateGSTIN,
    validatePAN,
    validateHSN,
    getHSNCode,
    calculateGST,
    formatIndianCurrency,
    amountToWordsIndian,
} = require('../utils/gstHelpers');

let _GstConfig;
function getGstConfigModel() {
    if (!_GstConfig) _GstConfig = require('../models/GstConfig')(getShopmanageConnection());
    return _GstConfig;
}

// ─── GET /api/gst/config ─────────────────────────────────────────────────────
exports.getConfig = async (req, res) => {
    try {
        const GstConfig = getGstConfigModel();
        let config = await GstConfig.findOne({ isActive: true }).lean();

        if (!config) {
            // Return defaults if no config exists yet
            config = {
                gstRate: 3.0,
                cgstRate: 1.5,
                sgstRate: 1.5,
                igstRate: 3.0,
                tdsRate: 1.0,
                tdsThreshold: 200000,
                hsnCode: '7113',
                firmTurnoverCategory: 'below_1_5cr',
                defaultTransactionType: 'intra-state',
            };
        }

        res.json({ success: true, data: { config } });
    } catch (err) {
        console.error('[GST] getConfig error:', err);
        res.status(500).json({ success: false, message: 'Error fetching GST config', error: err.message });
    }
};

// ─── PUT /api/gst/config ─────────────────────────────────────────────────────
exports.updateConfig = async (req, res) => {
    try {
        const GstConfig = getGstConfigModel();

        const {
            firmName,
            gstin,
            pan,
            firmTurnoverCategory,
            defaultTransactionType,
        } = req.body;

        // Validate GSTIN if provided
        if (gstin && !validateGSTIN(gstin)) {
            return res.status(400).json({
                success: false,
                message: 'Invalid GSTIN format. Expected format: 22AAAAA0000A1Z5',
            });
        }

        // Validate PAN if provided
        if (pan && !validatePAN(pan)) {
            return res.status(400).json({
                success: false,
                message: 'Invalid PAN format. Expected format: AAAAA0000A',
            });
        }

        // Auto-select HSN code based on turnover category
        const hsnCode = firmTurnoverCategory ? getHSNCode(firmTurnoverCategory) : undefined;

        // Extract state code from GSTIN (first 2 digits)
        const stateCode = gstin ? gstin.substring(0, 2) : undefined;

        const update = {};
        if (firmName !== undefined) update.firmName = firmName.trim();
        if (gstin !== undefined) update.gstin = gstin.toUpperCase().trim();
        if (pan !== undefined) update.pan = pan.toUpperCase().trim();
        if (firmTurnoverCategory !== undefined) update.firmTurnoverCategory = firmTurnoverCategory;
        if (hsnCode !== undefined) update.hsnCode = hsnCode;
        if (stateCode !== undefined) update.stateCode = stateCode;
        if (defaultTransactionType !== undefined) update.defaultTransactionType = defaultTransactionType;
        update.updatedBy = req.user.id;

        // GST rates are legally fixed — cannot be changed by admin
        // (they are set as defaults in the schema)

        const config = await GstConfig.findOneAndUpdate(
            { isActive: true },
            { $set: update },
            { new: true, upsert: true, setDefaultsOnInsert: true }
        );

        res.json({
            success: true,
            message: 'GST configuration updated',
            data: { config },
        });
    } catch (err) {
        console.error('[GST] updateConfig error:', err);
        res.status(500).json({ success: false, message: 'Error updating GST config', error: err.message });
    }
};

// ─── POST /api/gst/calculate ─────────────────────────────────────────────────
exports.calculate = async (req, res) => {
    try {
        const GstConfig = getGstConfigModel();
        const { baseAmount, transactionType } = req.body;

        if (baseAmount == null) {
            return res.status(400).json({ success: false, message: 'baseAmount is required' });
        }

        if (parseFloat(baseAmount) < 0) {
            return res.status(400).json({ success: false, message: 'baseAmount cannot be negative' });
        }

        const config = (await GstConfig.findOne({ isActive: true }).lean()) || {};
        const txType = transactionType || config.defaultTransactionType || 'intra-state';

        const result = calculateGST(parseFloat(baseAmount), config, txType);

        res.json({
            success: true,
            data: {
                ...result,
                formattedNetPayable: formatIndianCurrency(result.netPayable),
                netPayableInWords: amountToWordsIndian(result.netPayable),
                transactionType: txType,
            },
        });
    } catch (err) {
        console.error('[GST] calculate error:', err);
        res.status(500).json({ success: false, message: 'Error calculating GST', error: err.message });
    }
};

// ─── POST /api/gst/validate-gstin ────────────────────────────────────────────
exports.validateGSTIN = async (req, res) => {
    const { gstin } = req.body;
    if (!gstin) return res.status(400).json({ success: false, message: 'gstin is required' });

    const valid = validateGSTIN(gstin);
    res.json({
        success: true,
        data: {
            gstin: gstin.toUpperCase().trim(),
            valid,
            message: valid ? 'Valid GSTIN' : 'Invalid GSTIN format',
            stateCode: valid ? gstin.substring(0, 2) : null,
            panEmbedded: valid ? gstin.substring(2, 12) : null,
        },
    });
};

// ─── POST /api/gst/validate-pan ──────────────────────────────────────────────
exports.validatePAN = async (req, res) => {
    const { pan } = req.body;
    if (!pan) return res.status(400).json({ success: false, message: 'pan is required' });

    const valid = validatePAN(pan);
    res.json({
        success: true,
        data: {
            pan: pan.toUpperCase().trim(),
            valid,
            message: valid ? 'Valid PAN' : 'Invalid PAN format',
        },
    });
};

// ─── POST /api/gst/validate-hsn ──────────────────────────────────────────────
exports.validateHSN = async (req, res) => {
    const { hsn } = req.body;
    if (!hsn) return res.status(400).json({ success: false, message: 'hsn is required' });

    const valid = validateHSN(hsn);
    res.json({
        success: true,
        data: {
            hsn: hsn.trim(),
            valid,
            message: valid ? 'Valid HSN code for Chapter 71' : 'Invalid HSN code. Must be 4 or 8 digits starting with 71.',
        },
    });
};
