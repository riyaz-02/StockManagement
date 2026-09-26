/**
 * Estimate.js - a price quotation given to a customer before any bill (collection app_estimates).
 * It is NOT a tax invoice: no GST number, no stock leaves, no money is taken. The figures are worked out by the same engine as
 * a bill, so turning the estimate into an invoice gives the same price (at the same rates). Branch-scoped.
 */
const mongoose = require('mongoose');

const schema = new mongoose.Schema(
    {
        number: { type: String, required: true, unique: true },            // EST-0001 (branch prefix for other branches)
        requestId: { type: String, index: true, sparse: true, unique: true },
        date: { type: String, required: true, index: true },               // YYYY-MM-DD (India)
        validTill: { type: String, required: true },
        customerId: { type: String, default: '' },
        customerName: { type: String, trim: true, default: '' },
        customerMobile: { type: String, trim: true, default: '' },
        goldRate: Number,
        silverRate: Number,
        inputItems: { type: [mongoose.Schema.Types.Mixed], default: [] },  // the lines as the app sent them (to make the invoice from)
        items: { type: [mongoose.Schema.Types.Mixed], default: [] },       // the lines as worked out (description, weights, amounts)
        additionalCharges: { type: Number, default: 0 },
        discount: { type: Number, default: 0 },
        totals: { type: mongoose.Schema.Types.Mixed, default: {} },        // { taxable, cgst, sgst, igst, total, payable, roundOff }
        note: { type: String, default: '' },
        status: { type: String, enum: ['open', 'converted', 'cancelled'], default: 'open', index: true },
        convertedInvoice: { type: String, default: '' },
        createdBy: String,
        createdByName: String,
    },
    { collection: 'app_estimates', timestamps: true }
);
schema.plugin(require('../utils/branchScope').branchPlugin);
module.exports = mongoose.models.AppEstimate || mongoose.model('AppEstimate', schema);
