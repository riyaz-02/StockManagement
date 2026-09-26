/**
 * AppGst.js — the app's own GST-return bookkeeping (collections in the APP's database; the live
 * `invoices` / `purchases` data is only ever read for reports).
 *
 *   app_gst_settings       one document: filing frequency, reminder lead times, opening ITC balance ...
 *   app_gst_filings        a record per return that was filed (date, ARN, amounts). Insert + edit, never deleted.
 *   app_gst_reminder_log   which reminders were already sent, so each is sent once
 */
'use strict';
const mongoose = require('mongoose');

const money = { type: Number, default: 0, min: 0 };

const settingsSchema = new mongoose.Schema(
    {
        key: { type: String, default: 'main', unique: true },
        // 'monthly' = GSTR-1 (11th) + GSTR-3B (20th) every month
        // 'quarterly' = QRMP: GSTR-1 (13th) + GSTR-3B (22nd/24th) every quarter, tax paid monthly (PMT-06, 25th)
        frequency: { type: String, enum: ['monthly', 'quarterly'], default: 'monthly' },
        // filings for periods that ended before this month ("2026-08") are not followed: no overdue alerts / reminders
        remindersFrom: { type: String, default: '' },
        // first period the app should roll ITC forward from ("2026-04"), with the credit balance at its start
        trackFrom: { type: String, default: '' },
        openingItc: { igst: money, cgst: money, sgst: money },
        // count purchases from suppliers without a GSTIN as claimable ITC (off: they are shown as "at risk")
        countItcWithoutGstin: { type: Boolean, default: false },
        // inter-state supplies to unregistered buyers above this value are listed invoice by invoice (GSTR-1 table 5)
        b2clThreshold: { type: Number, default: 100000, min: 0 },
        reminders: {
            enabled: { type: Boolean, default: true },
            daysBefore: { type: [Number], default: [7, 3, 1, 0] },
            overdue: { type: Boolean, default: true },
        },
        updatedBy: String,
        updatedByName: String,
    },
    { collection: 'app_gst_settings', timestamps: true, versionKey: false }
);

const filingSchema = new mongoose.Schema(
    {
        // the registration (GSTIN) the return belongs to; '' = the firm's default GSTIN (see services/registrations.js)
        gstin: { type: String, default: '', trim: true, uppercase: true },
        returnType: { type: String, enum: ['GSTR-1', 'GSTR-3B', 'PMT-06', 'GSTR-9'], required: true },
        period: { type: String, required: true },             // "2026-08", "2026-Q2", or "FY2026" for GSTR-9
        filedOn: { type: String, required: true },            // YYYY-MM-DD
        arn: { type: String, trim: true, default: '' },
        taxLiability: money,                                   // total tax on the return
        itcUsed: money,
        cashPaid: money,
        lateFee: money,
        interest: money,
        nil: { type: Boolean, default: false },
        note: { type: String, trim: true, default: '' },
        createdBy: String,
        createdByName: String,
        updatedBy: String,
        updatedByName: String,
    },
    { collection: 'app_gst_filings', timestamps: true, versionKey: false }
);
filingSchema.index({ gstin: 1, returnType: 1, period: 1 }, { unique: true });
// the first version of this collection was unique on (returnType, period) only: drop that index once
mongoose.connection.once('connected', () => { mongoose.connection.collection('app_gst_filings').dropIndex('returnType_1_period_1').catch(() => {}); });

const reminderLogSchema = new mongoose.Schema(
    { key: { type: String, required: true, unique: true }, sentAt: { type: Date, default: Date.now, expires: 60 * 60 * 24 * 500 } },
    { collection: 'app_gst_reminder_log', versionKey: false }
);

// one row per generated PDF record (the website keeps the same audit trail in `outputDoc`)
const documentSchema = new mongoose.Schema(
    {
        documentId: { type: String, required: true, unique: true },
        documentType: { type: String, default: 'GST_MONTHLY_RECORD' },
        documentName: String,
        year: Number,
        month: Number,
        totalInvoices: Number,
        validInvoices: Number,
        totalAmount: Number,
        totalGst: Number,
        taxableAmount: Number,
        partial: { type: Boolean, default: false },
        generatedBy: String,
        generatedByName: String,
        branchId: String,
        gstin: String,
        branchFilter: String,
    },
    { collection: 'app_gst_documents', timestamps: true, versionKey: false }
);

module.exports = {
    GstDocument: mongoose.models.AppGstDocument || mongoose.model('AppGstDocument', documentSchema),
    GstSettings: mongoose.models.AppGstSettings || mongoose.model('AppGstSettings', settingsSchema),
    GstFiling: mongoose.models.AppGstFiling || mongoose.model('AppGstFiling', filingSchema),
    GstReminderLog: mongoose.models.AppGstReminderLog || mongoose.model('AppGstReminderLog', reminderLogSchema),
};
