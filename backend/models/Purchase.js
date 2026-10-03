/**
 * Purchase.js — supplier purchases. ONE collection, `purchases`, shared with the PHP website.
 *
 * The WEBSITE's document is the stored shape, so the old site keeps working on every record and the app, the new website
 * and the old website all see the same list:
 *     invoice_date ('YYYY-MM-DD' string), invoice_number, metal_type ('Gold' / 'Silver'), biller, description,
 *     quantity (grams), rate, total_amount (the invoice total, GST included), created_/updated_ at / ist / by / by_name,
 *     attachment (the website's S3 file)
 * The app adds what only it records, as extra fields the website ignores:
 *     totalAmount (taxable value), billerGstin, remarks, transactionType, gstRate, cgst/sgst/igstAmount, totalGst,
 *     totalPayable, hsnCode, itc*, tds*, netPayable, effectiveCost, valuation, attachments, attachmentMeta, branchId, source
 * An old website purchase has none of these: its GST was never recorded, so the app shows it with the invoice total and no
 * GST / input credit (`gstRecorded: false`) instead of guessing. If the website later edits the total of a purchase the app
 * had split, the saved split no longer matches and is treated the same way.
 *
 * `toApp(doc)` turns a stored document into the JSON the app and the portal have always received (camelCase, lower-case
 * metal, a real Date), so nothing outside this file needs to know the storage names.
 * The website owns this collection: no automatic indexes or collection creation (autoIndex / autoCreate false), and no schema
 * defaults, so saving an old record never adds fields the user did not change.
 */

const mongoose = require('mongoose');

const IST_MS = 5.5 * 60 * 60 * 1000;
const r2 = (n) => Math.round((Number(n) + Number.EPSILON) * 100) / 100;
const num = (v) => (v === null || v === undefined || v === '' || Number.isNaN(Number(v)) ? 0 : Number(v));

/** 'YYYY-MM-DD' of the shop's (IST) calendar day for a Date, an ISO string or a plain date string. */
function ymdIST(v) {
    if (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v.trim())) return v.trim();
    const d = new Date(v);
    if (Number.isNaN(d.getTime())) return '';
    return new Date(d.getTime() + IST_MS).toISOString().slice(0, 10);
}
/** 'YYYY-MM-DD HH:mm:ss' in IST: how the website stamps created_ist / updated_ist. */
const istStamp = (d = new Date()) => new Date(d.getTime() + IST_MS).toISOString().replace('T', ' ').slice(0, 19);
/** The website writes metals as 'Gold' / 'Silver'. */
const websiteMetal = (m) => { const s = String(m || '').trim().toLowerCase(); return s ? s[0].toUpperCase() + s.slice(1) : ''; };
/** The day as a Date at 00:00 UTC (what the app always sent as invoiceDate). */
const dayAsDate = (ymd) => (/^\d{4}-\d{2}-\d{2}/.test(String(ymd)) ? new Date(`${String(ymd).slice(0, 10)}T00:00:00.000Z`) : null);

const purchaseSchema = new mongoose.Schema(
    {
        // ── the website's own fields ──
        invoice_date: { type: String },
        invoice_number: { type: String, trim: true },
        metal_type: { type: String },
        biller: { type: String, trim: true },
        description: { type: String },
        quantity: { type: Number },
        rate: { type: Number },
        total_amount: { type: Number },
        created_at: Date,
        created_ist: String,
        created_by: String,
        created_by_name: String,
        updated_at: Date,
        updated_ist: String,
        updated_by: String,
        updated_by_name: String,
        attachment: { type: Object },

        // ── what only the app records ──
        totalAmount: Number,            // taxable value (before GST)
        billerGstin: { type: String },
        remarks: { type: String },
        transactionType: String,
        gstRate: Number,
        cgstAmount: Number,
        sgstAmount: Number,
        igstAmount: Number,
        totalGst: Number,
        totalPayable: Number,           // = total_amount when the split is valid
        hsnCode: String,
        itcCgst: Number,
        itcSgst: Number,
        itcIgst: Number,
        totalItc: Number,
        effectiveCost: Number,
        tdsApplicable: Boolean,
        tdsRate: Number,
        tdsAmount: Number,
        netPayable: Number,
        valuation: { type: Object },
        attachments: { type: [String], default: undefined },
        attachmentMeta: { type: [Object], default: undefined },
        source: String,                 // 'app' for what the app created (missing = the website made it)
    },
    { collection: 'purchases', versionKey: false, timestamps: false, minimize: false, autoIndex: false, autoCreate: false }
);

purchaseSchema.plugin(require('../utils/branchScope').branchPlugin);

/** A stored purchase as the API has always shown it. */
function toApp(d) {
    if (!d) return d;
    const o = typeof d.toObject === 'function' ? d.toObject() : d;
    const total = num(o.total_amount);
    const split = o.totalPayable != null && Math.abs(num(o.totalPayable) - total) <= 1;
    const ymd = String(o.invoice_date || '').slice(0, 10);
    const [yy, mm, dd] = ymd.split('-');
    const base = {
        _id: o._id,
        invoiceDate: dayAsDate(ymd),
        invoiceDateIST: yy ? `${dd}/${mm}/${yy}` : '',
        invoiceNumber: o.invoice_number || '',
        metalType: String(o.metal_type || '').toLowerCase(),
        biller: o.biller || '',
        billerGstin: o.billerGstin || '',
        quantity: num(o.quantity),
        rate: num(o.rate),
        description: o.description || '',
        remarks: o.remarks || '',
        attachments: o.attachments || [],
        attachmentMeta: o.attachmentMeta || [],
        websiteAttachment: o.attachment || null,
        valuation: o.valuation || null,
        branchId: o.branchId,
        isDeleted: false,
        source: o.source || 'website',
        createdAt: o.created_at, createdAtIST: o.created_ist || '', createdBy: o.created_by, createdByName: o.created_by_name,
        updatedAt: o.updated_at || o.created_at, updatedBy: o.updated_by, updatedByName: o.updated_by_name,
        gstRecorded: split,
    };
    if (split) {
        return {
            ...base,
            totalAmount: num(o.totalAmount), transactionType: o.transactionType, gstRate: num(o.gstRate),
            cgstAmount: num(o.cgstAmount), sgstAmount: num(o.sgstAmount), igstAmount: num(o.igstAmount), totalGst: num(o.totalGst),
            totalPayable: num(o.totalPayable), hsnCode: o.hsnCode,
            itcCgst: num(o.itcCgst), itcSgst: num(o.itcSgst), itcIgst: num(o.itcIgst), totalItc: num(o.totalItc),
            effectiveCost: num(o.effectiveCost), tdsApplicable: !!o.tdsApplicable, tdsRate: num(o.tdsRate), tdsAmount: num(o.tdsAmount),
            netPayable: num(o.netPayable),
        };
    }
    return {
        ...base,
        totalAmount: total, transactionType: '', gstRate: 0, cgstAmount: 0, sgstAmount: 0, igstAmount: 0, totalGst: 0,
        totalPayable: total, hsnCode: '', itcCgst: 0, itcSgst: 0, itcIgst: 0, totalItc: 0,
        effectiveCost: total, tdsApplicable: false, tdsRate: 0, tdsAmount: 0, netPayable: total,
    };
}

/** Mongo expressions for the same facts when summing in an aggregation (the GST split counts only while it is valid). */
const SPLIT_OK = { $and: [{ $ne: [{ $type: '$totalPayable' }, 'missing'] }, { $lte: [{ $abs: { $subtract: [{ $ifNull: ['$totalPayable', 0] }, { $ifNull: ['$total_amount', 0] }] } }, 1] }] };
const sumIfSplit = (field) => ({ $cond: [SPLIT_OK, { $ifNull: [`$${field}`, 0] }, 0] });
/** taxable value: the split's when valid, else the invoice total (no GST was recorded) */
const taxableExpr = { $cond: [SPLIT_OK, { $ifNull: ['$totalAmount', 0] }, { $ifNull: ['$total_amount', 0] }] };

module.exports = (connection) => connection.models.Purchase || connection.model('Purchase', purchaseSchema);
module.exports.toApp = toApp;
module.exports.ymdIST = ymdIST;
module.exports.istStamp = istStamp;
module.exports.websiteMetal = websiteMetal;
module.exports.dayAsDate = dayAsDate;
module.exports.r2 = r2;
module.exports.sumIfSplit = sumIfSplit;
module.exports.taxableExpr = taxableExpr;
