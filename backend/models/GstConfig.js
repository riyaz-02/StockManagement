/**
 * GstConfig.js — GST configuration for the jewellery firm (shopmanage DB)
 *
 * Stores the firm's GST/tax configuration:
 *   - GSTIN, PAN
 *   - Turnover bracket (determines HSN code)
 *   - GST rates (legally fixed at 3% for gold/silver jewelry)
 *   - TDS threshold and rate
 *
 * Only one active document is maintained (singleton config).
 */

const mongoose = require('mongoose');

const gstConfigSchema = new mongoose.Schema(
    {
        // Firm identification
        firmName: { type: String, trim: true },
        gstin: {
            type: String,
            trim: true,
            uppercase: true,
            // Format: 2-digit state code + PAN + 1 entity number + 'Z' + 1 check digit
            match: [
                /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$/,
                'Invalid GSTIN format',
            ],
        },
        pan: {
            type: String,
            trim: true,
            uppercase: true,
            match: [/^[A-Z]{5}[0-9]{4}[A-Z]{1}$/, 'Invalid PAN format'],
        },
        stateCode: { type: String, trim: true }, // 2-digit state code from GSTIN

        // Turnover bracket determines HSN digit count
        // 'below_1_5cr'  → 4-digit HSN (7113) — optional for small taxpayers
        // 'above_1_5cr'  → 8-digit HSN (71131100) — mandatory for larger taxpayers
        firmTurnoverCategory: {
            type: String,
            enum: ['below_1_5cr', 'above_1_5cr'],
            default: 'below_1_5cr',
        },
        hsnCode: {
            type: String,
            default: '7113',
        },

        // GST rates — legally fixed for Chapter 71 (gold/silver jewelry)
        // Admin can only view, not change these without a legal basis
        gstRate: { type: Number, default: 3.0 },
        cgstRate: { type: Number, default: 1.5 },
        sgstRate: { type: Number, default: 1.5 },
        igstRate: { type: Number, default: 3.0 },

        // TDS — Section 194Q (purchase from resident suppliers)
        tdsRate: { type: Number, default: 1.0 },
        // TDS applies only when transaction value STRICTLY EXCEEDS this threshold
        tdsThreshold: { type: Number, default: 200000 }, // ₹2,00,000

        // Default transaction type for the shop
        defaultTransactionType: {
            type: String,
            enum: ['intra-state', 'inter-state'],
            default: 'intra-state',
        },

        // Audit
        updatedBy: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User',
        },
        isActive: { type: Boolean, default: true },
    },
    {
        timestamps: true,
        collection: 'gst_configs',
    }
);

module.exports = (connection) => connection.model('GstConfig', gstConfigSchema);
