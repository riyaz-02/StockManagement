/**
 * AppGst.js — the app's own GST-return bookkeeping (collections in the APP's database; the live
 * `invoices` / `purchases` data is only ever read for reports).
 *
 *   app_gst_settings       one document: filing frequency, reminder lead times, opening ITC balance ...
 * (Filed returns are in the website's own `gst_data`, one document per quarter: see services/gstFilings.js.)
 *   app_gst_reminder_log   which reminders were already sent, so each is sent once
 * (The generated monthly records go to the website's own `outputDoc`; see gstReportsController.)
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

const reminderLogSchema = new mongoose.Schema(
    { key: { type: String, required: true, unique: true }, sentAt: { type: Date, default: Date.now, expires: 60 * 60 * 24 * 500 } },
    { collection: 'app_gst_reminder_log', versionKey: false }
);

// one row per generated PDF record (the website keeps the same audit trail in `outputDoc`)
module.exports = {
    GstSettings: mongoose.models.AppGstSettings || mongoose.model('AppGstSettings', settingsSchema),
    GstReminderLog: mongoose.models.AppGstReminderLog || mongoose.model('AppGstReminderLog', reminderLogSchema),
};
