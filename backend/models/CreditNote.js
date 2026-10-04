/**
 * CreditNote.js - GST credit notes for sales returns / refunds / price adjustments (collection app_credit_notes).
 * The original invoice (website collection) is never changed; the note points at it. Branch-scoped through branchPlugin
 * (branchId is the branch of the ORIGINAL invoice).
 */
const mongoose = require('mongoose');

const lineSchema = new mongoose.Schema({
    index: Number, particulars: String, hsn: String, metal: String, netWt: Number, purity: String, productCode: String, itemId: String,
    lineTaxable: Number, taxable: Number, cgst: Number, sgst: Number, igst: Number, total: Number, fullReturn: Boolean, restocked: Boolean,
}, { _id: false });

const schema = new mongoose.Schema(
    {
        number: { type: String, required: true, unique: true },           // CN-0001 (main) / BGB-CN-0001 (branch)
        requestId: { type: String, index: true, sparse: true, unique: true },
        date: { type: String, required: true },                          // YYYY-MM-DD (India)
        invoiceId: String,
        invoiceNumber: { type: String, index: true },
        invoiceDate: String,
        customerName: String, customerMobile: String, customerAddress: String, customerState: String, customerStateCode: String,
        sellerGstin: String,
        gstType: { type: String, enum: ['CGST_SGST', 'IGST'] },
        lines: [lineSchema],
        taxable: Number, cgst: Number, sgst: Number, igst: Number, total: Number,
        reason: { type: String, enum: ['sales_return', 'price_adjustment', 'quality_issue', 'exchange', 'other'], default: 'sales_return' },
        note: { type: String, default: '' },
        refundMode: { type: String, default: '' },                       // Cash | Card | Online | Cheque | '' (kept as credit / adjusted)
        refundAmount: { type: Number, default: 0 },
        reducesTax: { type: Boolean, default: true },                     // false when made after the s.34(2) deadline
        status: { type: String, enum: ['active', 'cancelled'], default: 'active', index: true },
        createdBy: String, createdByName: String,
    },
    { collection: 'app_credit_notes', timestamps: true }
);
schema.plugin(require('../utils/branchScope').branchPlugin, { counter: true }); // bills / money at a counter carry it
module.exports = mongoose.models.AppCreditNote || mongoose.model('AppCreditNote', schema);
