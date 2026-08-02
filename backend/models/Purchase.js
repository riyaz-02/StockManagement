/**
 * Purchase.js — Supplier purchase entries (shopmanage DB)
 *
 * Tracks every purchase made from a supplier/biller.
 * Linked to stock_entries via referenceId for ledger tracking.
 */

const mongoose = require('mongoose');

const purchaseSchema = new mongoose.Schema(
    {
        invoiceDate: {
            type: Date,
            required: [true, 'Invoice date is required'],
        },
        invoiceNumber: {
            type: String,
            required: [true, 'Invoice number is required'],
            trim: true,
            unique: true,
            index: true,
        },
        metalType: {
            type: String,
            required: [true, 'Metal type is required'],
            enum: ['gold', 'silver', 'platinum', 'other'],
            lowercase: true,
        },
        biller: {
            type: String,
            required: [true, 'Biller/Supplier name is required'],
            trim: true,
        },
        // Weight in grams
        quantity: {
            type: Number,
            required: [true, 'Quantity (grams) is required'],
            min: [0.001, 'Quantity must be greater than 0'],
        },
        // Rate per gram in INR
        rate: {
            type: Number,
            required: [true, 'Rate per gram is required'],
            min: [0, 'Rate cannot be negative'],
        },
        // Gross amount before taxes (quantity * rate)
        totalAmount: {
            type: Number,
            required: [true, 'Total amount is required'],
        },
        // GST fields (B2B purchase — supplier charges GST, buyer claims ITC)
        gstRate: { type: Number, default: 3.0 },
        cgstAmount: { type: Number, default: 0 },
        sgstAmount: { type: Number, default: 0 },
        igstAmount: { type: Number, default: 0 },
        totalGst: { type: Number, default: 0 },
        transactionType: {
            type: String,
            enum: ['intra-state', 'inter-state'],
            default: 'intra-state',
        },
        hsnCode: { type: String, default: '7113' },
        // Supplier GSTIN (required for valid ITC claim in B2B)
        billerGstin: { type: String, trim: true, default: '' },
        // ITC (Input Tax Credit) — the GST paid to supplier that the firm can reclaim
        // In B2B: ITC = GST paid (CGST → CGST ledger, SGST → SGST ledger, IGST → IGST ledger)
        itcCgst: { type: Number, default: 0 }, // Claimable from CGST electronic credit ledger
        itcSgst: { type: Number, default: 0 }, // Claimable from SGST electronic credit ledger
        itcIgst: { type: Number, default: 0 }, // Claimable from IGST electronic credit ledger
        totalItc: { type: Number, default: 0 }, // Total ITC = itcCgst + itcSgst + itcIgst
        effectiveCost: { type: Number, default: 0 }, // total_amount (after ITC offset, real inventory cost)
        // Total payable to supplier (totalAmount + totalGst)
        totalPayable: { type: Number, default: 0 },
        // TDS fields (Section 194Q) — applicable when buyer's turnover > ₹10Cr
        tdsApplicable: { type: Boolean, default: false },
        tdsRate: { type: Number, default: 1.0 },
        tdsAmount: { type: Number, default: 0 },
        // Net cash outflow = totalPayable - tdsAmount
        netPayable: { type: Number, default: 0 },
        // Invoice/receipt file attachments (Cloudinary URLs — kept for back-compat)
        attachments: [{ type: String }],
        // Rich attachment objects with publicId for deletion
        attachmentMeta: [
            {
                url: { type: String, required: true },
                publicId: { type: String },
                originalName: { type: String },
                format: { type: String },
            },
        ],
        // Description (from legacy: separate from remarks, shown in stock ledger)
        description: { type: String, trim: true, default: '' },
        // Notes
        remarks: { type: String, trim: true, default: '' },
        // Audit trail (mirrors legacy created_by_name / updated_by_name)
        createdBy: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User',
            required: true,
        },
        createdByName: { type: String, trim: true, default: '' },
        updatedBy: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User',
        },
        updatedByName: { type: String, trim: true, default: '' },
        // IST timestamps (stored as formatted strings for display)
        invoiceDateIST: { type: String },
        createdAtIST: { type: String },
        // Soft delete
        isDeleted: { type: Boolean, default: false },
        deletedAt: { type: Date, default: null },
    },
    {
        timestamps: true,
        collection: 'purchases',
    }
);

// Indexes
purchaseSchema.index({ invoiceDate: -1 });
purchaseSchema.index({ metalType: 1, invoiceDate: -1 });
purchaseSchema.index({ biller: 1 });
purchaseSchema.index({ isDeleted: 1 });
purchaseSchema.index({ createdAt: -1 });

// Virtual: formatted invoice date in IST
purchaseSchema.virtual('invoiceDateFormatted').get(function () {
    return this.invoiceDate
        ? this.invoiceDate.toLocaleDateString('en-IN', { timeZone: 'Asia/Kolkata' })
        : null;
});

module.exports = (connection) => connection.model('Purchase', purchaseSchema);
