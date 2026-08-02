'use strict';

const mongoose = require('mongoose');

/**
 * Invoice.js — GST Sales Invoice for Laltu Guinea Palace
 * Stored in the shopmanage DB (secondary connection).
 *
 * Correct GST math (Section 15 CGST Act):
 *   netTaxable = Σ taxableAmount + additionalCharges − discount
 *   GST        = netTaxable × 3%  (CGST 1.5% + SGST 1.5%, or IGST 3%)
 *   payable    = round(netTaxable + GST)   [round-off always ±₹0.50]
 *
 * Discount reduces the TAXABLE BASE — never the post-GST amount.
 */

const invoiceItemSchema = new mongoose.Schema({
    particulars:       { type: String, default: '' },
    hsnCode:           { type: String, default: '7113' },
    metalType:         { type: String, enum: ['gold', 'silver', 'other'], default: 'gold' },
    netWeight:         { type: Number, default: 0 },      // grams, 3dp
    makingCharge:      { type: Number, default: 0 },      // ₹
    taxableAmount:     { type: Number, default: 0 },      // (wt × rate) + making OR manual override
    taxableOverridden: { type: Boolean, default: false }, // double-tap override flag
    cgstRate:          { type: Number, default: 1.5 },
    sgstRate:          { type: Number, default: 1.5 },
    igstRate:          { type: Number, default: 0 },
    cgstAmount:        { type: Number, default: 0 },
    sgstAmount:        { type: Number, default: 0 },
    igstAmount:        { type: Number, default: 0 },
    rowTotal:          { type: Number, default: 0 },
}, { _id: false });

/**
 * Factory function: returns a Mongoose model bound to `conn`.
 */
module.exports = (conn) => {
    if (conn.models && conn.models.Invoice) return conn.models.Invoice;

    const invoiceSchema = new mongoose.Schema({
        // ── Auto-generated invoice number ──────────────────────────────────
        invoiceNumber: { type: String, unique: true, index: true },

        // ── Seller snapshot (from GstConfig at time of creation) ───────────
        seller: {
            firmName:  { type: String, default: 'Laltu Guinea Palace' },
            gstin:     { type: String, default: '' },
            pan:       { type: String, default: '' },
            stateCode: { type: String, default: '19' },
            state:     { type: String, default: 'West Bengal' },
        },

        // ── Invoice metadata ────────────────────────────────────────────────
        invoiceDate:   { type: Date, required: true },
        deliveryDate:  { type: Date, default: null },
        transactionType: {
            type: String,
            enum: ['intra-state', 'inter-state'],
            default: 'intra-state',
        },
        reverseCharge:    { type: Boolean, default: false },
        termsOfDelivery:  { type: String, default: 'Customer Pickup' },
        placeOfSupply:    { type: String, default: 'West Bengal' },

        // ── Global rates for this invoice ───────────────────────────────────
        goldRate:   { type: Number, default: 0 }, // ₹ per gram
        silverRate: { type: Number, default: 0 },

        // ── Customer ────────────────────────────────────────────────────────
        customerName: { type: String, required: true, trim: true },
        customerMobile: { type: String, trim: true },
        customerAddress: { type: String, trim: true, default: '' },
        customerPan: { type: String, trim: true, default: '' }, // mandatory if TDS

        // ── Line items ──────────────────────────────────────────────────────
        items: { type: [invoiceItemSchema], default: [] },

        // ── Computed totals (all set by recomputeTotals()) ──────────────────
        // Σ item.taxableAmount  (before any GST, before discount)
        grossTaxable:       { type: Number, default: 0 },
        // grossTaxable + additionalCharges − discount  (the GST base)
        netTaxable:         { type: Number, default: 0 },
        // GST amounts computed on netTaxable
        totalCgst:          { type: Number, default: 0 },
        totalSgst:          { type: Number, default: 0 },
        totalIgst:          { type: Number, default: 0 },
        additionalCharges:  { type: Number, default: 0 },
        discount:           { type: Number, default: 0 },
        payableBeforeRound: { type: Number, default: 0 }, // netTaxable + GST
        roundOff:           { type: Number, default: 0 }, // Math.round correction, ±₹0.50
        totalPayable:       { type: Number, default: 0 }, // round(payableBeforeRound)
        totalPayableOverridden: { type: Boolean, default: false },

        // ── TDS (Section 194Q, applies if totalPayable > 200000) ───────────
        tdsApplicable: { type: Boolean, default: false },
        tdsRate:       { type: Number, default: 1.0 },
        tdsAmount:     { type: Number, default: 0 },
        netPayableAfterTds: { type: Number, default: 0 },

        // ── Payment ─────────────────────────────────────────────────────────
        paidAmount:  { type: Number, default: 0 },
        paymentMode: {
            type: String,
            enum: ['cash', 'card', 'online', 'cheque'],
            default: 'cash',
        },
        // dueAmount < 0 → customer owes us | > 0 → advance paid
        dueAmount: { type: Number, default: 0 },

        // ── Status (derived) ─────────────────────────────────────────────────
        // pending   = no delivery date or delivery in future
        // active    = delivered but not fully paid
        // delivered = delivered AND fully paid
        status: {
            type: String,
            enum: ['pending', 'active', 'delivered'],
            default: 'pending',
            index: true,
        },

        // ── Attachments & notes ─────────────────────────────────────────────
        attachments: [{ type: String }],  // Cloudinary URLs
        notes: { type: String, default: '' },

        // ── Soft delete ─────────────────────────────────────────────────────
        isDeleted: { type: Boolean, default: false, index: true },

        // ── Audit ────────────────────────────────────────────────────────────
        createdBy:        { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
        createdByName:    { type: String, default: '' },
        updatedBy:        { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
        updatedByName:    { type: String, default: '' },
        createdAtIST:     { type: String },
        updatedAtIST:     { type: String },
    }, {
        timestamps: true,
        collection: 'invoices',
    });

    // Compound indexes for common queries
    invoiceSchema.index({ invoiceDate: -1, isDeleted: 1 });
    invoiceSchema.index({ status: 1, isDeleted: 1 });
    invoiceSchema.index({ customerMobile: 1 });

    /**
     * Server-side total recompute — call before every save/update.
     *
     * CORRECT GST MATH (Section 15 CGST Act):
     *   netTaxable = Σ taxableAmount + additionalCharges − discount
     *   GST        = netTaxable × 3%  (CGST 1.5% + SGST 1.5%, or IGST 3%)
     *   payable    = netTaxable + GST → Math.round() → ±₹0.50 max round-off
     *
     * WRONG (do NOT do this):
     *   payable = (taxable + GST) − discount  ← taxes the discount amount
     *
     * Round-off: always |roundOff| ≤ ₹0.50  (standard Math.round).
     */
    invoiceSchema.methods.recomputeTotals = function () {
        const isInter = this.transactionType === 'inter-state';

        // ── Step 1: per-row taxable only (no per-row GST) ───────────────────
        let grossTaxable = 0;
        for (const item of this.items) {
            // rowTotal = taxable only (GST computed at invoice level)
            item.rowTotal = parseFloat((item.taxableAmount || 0).toFixed(2));
            // Zero out per-row GST fields (kept in schema for legacy compat)
            item.cgstAmount = 0;
            item.sgstAmount = 0;
            item.igstAmount = 0;
            grossTaxable += item.taxableAmount || 0;
        }
        this.grossTaxable = parseFloat(grossTaxable.toFixed(2));

        // ── Step 2: net taxable = gross + additional − discount ──────────────
        //    Discount reduces the GST base — no GST on the discounted amount.
        const net = grossTaxable + (this.additionalCharges || 0) - (this.discount || 0);
        this.netTaxable = parseFloat(Math.max(0, net).toFixed(2));

        // ── Step 3: GST on net taxable ───────────────────────────────────────
        let cgst = 0, sgst = 0, igst = 0;
        if (isInter) {
            igst = parseFloat((this.netTaxable * 0.03).toFixed(2));
        } else {
            cgst = parseFloat((this.netTaxable * 0.015).toFixed(2));
            sgst = parseFloat((this.netTaxable * 0.015).toFixed(2));
        }
        this.totalCgst = cgst;
        this.totalSgst = sgst;
        this.totalIgst = igst;
        const totalGst = cgst + sgst + igst;

        // ── Step 4: payable before round-off ─────────────────────────────────
        const rawPayable = parseFloat((this.netTaxable + totalGst).toFixed(2));
        this.payableBeforeRound = rawPayable;

        // ── Step 5: round-off (always ±₹0.50 max) ────────────────────────────
        const rounded = Math.round(rawPayable);
        this.roundOff = parseFloat((rounded - rawPayable).toFixed(2));

        if (!this.totalPayableOverridden) {
            this.totalPayable = rounded;
        }

        // ── Step 6: TDS (Section 194Q) ───────────────────────────────────────
        if (this.totalPayable > 200000) {
            this.tdsApplicable = true;
            this.tdsAmount     = parseFloat((this.totalPayable * 0.01).toFixed(2));
        } else {
            this.tdsApplicable = false;
            this.tdsAmount     = 0;
        }
        this.netPayableAfterTds = parseFloat((this.totalPayable - this.tdsAmount).toFixed(2));

        // ── Step 7: Due / Advance ─────────────────────────────────────────────
        this.dueAmount = parseFloat(((this.paidAmount || 0) - this.totalPayable).toFixed(2));

        // ── Step 8: Invoice status ────────────────────────────────────────────
        const today      = new Date(); today.setHours(23, 59, 59, 999);
        const delivered  = this.deliveryDate && new Date(this.deliveryDate) <= today;
        const fullPaid   = Math.abs(this.dueAmount) < 0.01;
        if (!delivered)        this.status = 'pending';
        else if (fullPaid)     this.status = 'delivered';
        else                   this.status = 'active';

        return this;
    };

    return conn.model('Invoice', invoiceSchema);
};
