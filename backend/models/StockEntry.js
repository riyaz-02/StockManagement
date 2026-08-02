/**
 * StockEntry.js — Daily stock ledger entries (shopmanage DB)
 *
 * Every business transaction that moves weight (credit or debit) is recorded here.
 * The running net (credits - debits) forms the ledger total for reconciliation.
 *
 * References:
 *   referenceType 'purchase'    → from purchases collection
 *   referenceType 'sale'        → item sold (from jewellery_stock items)
 *   referenceType 'adjustment'  → manual admin correction
 *   referenceType 'wastage'     → wastage logged manually
 */

const mongoose = require('mongoose');

const stockEntrySchema = new mongoose.Schema(
    {
        entryDate: {
            type: Date,
            required: [true, 'Entry date is required'],
            index: true,
        },
        metalType: {
            type: String,
            required: [true, 'Metal type is required'],
            enum: ['gold', 'silver', 'platinum', 'other'],
            lowercase: true,
        },
        entryType: {
            type: String,
            required: [true, 'Entry type is required'],
            enum: ['credit', 'debit'],
        },
        // Weight in grams
        weightGrams: {
            type: Number,
            required: [true, 'Weight is required'],
            min: [0, 'Weight cannot be negative'],
        },
        description: {
            type: String,
            trim: true,
            default: '',
        },
        // Link to original document
        referenceId: {
            type: mongoose.Schema.Types.ObjectId,
            default: null,
        },
        referenceType: {
            type: String,
            enum: ['purchase', 'sale', 'adjustment', 'wastage', 'bulk_weight'],
            required: true,
        },
        // Soft delete — deleted entries are excluded from calculations
        status: {
            type: String,
            enum: ['active', 'deleted'],
            default: 'active',
            index: true,
        },
        createdBy: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User',
            required: true,
        },
        entryDateIST: { type: String },
    },
    {
        timestamps: true,
        collection: 'stock_entries',
    }
);

// Compound indexes for aggregation pipelines
stockEntrySchema.index({ metalType: 1, entryDate: -1 });
stockEntrySchema.index({ metalType: 1, entryType: 1, status: 1 });
stockEntrySchema.index({ referenceId: 1, referenceType: 1 });
stockEntrySchema.index({ status: 1, entryDate: -1 });

module.exports = (connection) => connection.model('StockEntry', stockEntrySchema);
