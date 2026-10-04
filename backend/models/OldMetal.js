/**
 * OldMetal.js - old metal / URD received from customers, and raw metal bought (collection app_old_metal).
 * Branch-scoped like every stock model. Each saved entry also adds its net weight to the stock ledger (credit).
 */
const mongoose = require('mongoose');

const schema = new mongoose.Schema(
    {
        kind: { type: String, enum: ['old', 'raw'], default: 'old', index: true },
        date: { type: Date, default: Date.now, index: true },
        customerId: { type: String, default: '' },        // the directory customer, when one was picked
        customerName: { type: String, trim: true, default: '' },
        customerMobile: { type: String, trim: true, default: '' },
        metalType: { type: String, enum: ['gold', 'silver', 'platinum', 'other'], lowercase: true, required: true },
        purity: { type: String, trim: true, default: '' },
        gross: { type: Number, default: 0 },
        less: { type: Number, default: 0 },
        net: { type: Number, required: true, min: 0 },
        deduction: { type: Number, default: 0 },          // % taken off the purity (melting / testing loss)
        rate: { type: Number, default: 0 },
        fine: Number,
        finalFine: Number,
        valuationWt: Number,
        basis: String,
        amount: { type: Number, default: 0 },             // what the metal is worth / is paid
        note: { type: String, trim: true, default: '' },
        status: { type: String, enum: ['active', 'cancelled'], default: 'active', index: true },
        usedOnInvoice: { type: String, default: '' },     // invoice number it was adjusted against
        createdBy: String,
        createdByName: String,
    },
    { collection: 'app_old_metal', timestamps: true }
);
schema.plugin(require('../utils/branchScope').branchPlugin, { counter: true }); // bills / money at a counter carry it
module.exports = mongoose.models.AppOldMetal || mongoose.model('AppOldMetal', schema);
