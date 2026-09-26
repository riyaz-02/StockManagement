'use strict';
const OldMetal = require('../models/OldMetal');
const Rules = require('../services/stockRules');
const Doc = require('../models/AppStockSettings');
const { computeOldMetal } = require('../services/stockValuation');
const { getShopmanageConnection } = require('../config/db');

const fail = (res, code, message) => res.status(code).json({ success: false, message });
const str = (v) => (v == null ? '' : String(v).trim());
const StockEntry = () => require('../models/StockEntry')(getShopmanageConnection());

exports.list = async (req, res, next) => {
    try {
        const f = {};
        if (['old', 'raw'].includes(req.query.kind)) f.kind = req.query.kind;
        if (['active', 'cancelled'].includes(req.query.status)) f.status = req.query.status;
        if (req.query.used === 'yes') f.usedOnInvoice = { $nin: ['', null] };
        if (req.query.used === 'no') { f.usedOnInvoice = { $in: ['', null] }; f.status = 'active'; }
        if (str(req.query.q)) {
            const re = new RegExp(str(req.query.q).replace(/[.*+?^${}()|[\]\\]/g, '\\$&').slice(0, 40), 'i');
            f.$or = [{ customerName: re }, { customerMobile: re }, { note: re }];
        }
        const rows = await OldMetal.find(f).sort({ date: -1, createdAt: -1 }).limit(300).lean();
        const sum = { count: 0, net: 0, fine: 0, amount: 0 };
        for (const r of rows) if (r.status === 'active') { sum.count++; sum.net += r.net; sum.fine += r.fine || 0; sum.amount += r.amount; }
        for (const k of ['net', 'fine', 'amount']) sum[k] = Math.round(sum[k] * 1000) / 1000;
        res.json({ success: true, data: { rows, totals: sum } });
    } catch (e) { next(e); }
};

exports.create = async (req, res, next) => {
    try {
        const b = req.body || {};
        const kind = b.kind === 'raw' ? 'raw' : 'old';
        const metal = str(b.metalType).toLowerCase();
        if (!['gold', 'silver', 'platinum', 'other'].includes(metal)) return fail(res, 400, 'Choose the metal');
        if (kind === 'old' && str(b.customerName).length < 2) return fail(res, 400, 'Enter the customer name');
        const stored = await Doc.findOne({ key: 'main' }).lean();
        const v = computeOldMetal({ kind, gross: b.gross, less: b.less, net: b.net, purity: b.purity, deduction: b.deduction, rate: b.rate }, Rules.resolve(stored));
        if (!(v.net > 0)) return fail(res, 400, 'Enter the weight');
        if (!(Number(b.rate) > 0)) return fail(res, 400, 'Enter the rate');
        if (!str(b.purity)) return fail(res, 400, 'Choose the purity');
        const doc = await OldMetal.create({
            kind, date: b.date ? new Date(b.date) : new Date(), customerId: /^[0-9a-f]{24}$/i.test(str(b.customerId)) ? str(b.customerId) : '', customerName: str(b.customerName).slice(0, 80), customerMobile: str(b.customerMobile).slice(0, 15),
            metalType: metal, purity: str(b.purity), gross: Number(b.gross) || 0, less: Number(b.less) || 0, net: v.net, deduction: Number(b.deduction) || 0, rate: Number(b.rate),
            fine: v.fine, finalFine: v.finalFine, valuationWt: v.valuationWt, basis: v.basis, amount: v.amount, note: str(b.note).slice(0, 200),
            createdBy: String(req.user._id), createdByName: req.user.name || '',
        });
        // the metal comes into the shop: a credit in the stock ledger (never blocks the entry)
        await StockEntry().create({
            entryDate: doc.date, metalType: metal, entryType: 'credit', weightGrams: v.net, referenceId: doc._id, referenceType: 'adjustment',
            description: `${kind === 'old' ? 'Old metal from' : 'Raw metal'} ${doc.customerName || ''}`.trim(), status: 'active', createdBy: req.user._id,
        }).catch(() => {});
        res.status(201).json({ success: true, data: { entry: doc } });
    } catch (e) { next(e); }
};

// GET /available?customerId=&mobile=&name= : received old metal not yet adjusted, for this customer (by id, mobile or exact name)
exports.available = async (req, res, next) => {
    try {
        const or = [];
        if (/^[0-9a-f]{24}$/i.test(str(req.query.customerId))) or.push({ customerId: str(req.query.customerId) });
        const digits = str(req.query.mobile).replace(/\D/g, '').slice(-10);
        if (digits.length >= 10) or.push({ customerMobile: digits });
        if (str(req.query.name).length >= 2) or.push({ customerName: new RegExp('^' + str(req.query.name).replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '$', 'i') });
        const rows = or.length ? await OldMetal.find({ kind: 'old', status: 'active', usedOnInvoice: { $in: ['', null] }, $or: or }).sort({ date: -1 }).limit(30).lean() : [];
        res.json({ success: true, data: rows });
    } catch (e) { next(e); }
};

exports.cancel = async (req, res, next) => {
    try {
        const doc = await OldMetal.findById(req.params.id);
        if (!doc) return fail(res, 404, 'Entry not found');
        if (doc.status === 'cancelled') return fail(res, 400, 'Already cancelled');
        if (doc.usedOnInvoice) return fail(res, 400, `Already adjusted on invoice ${doc.usedOnInvoice}`);
        doc.status = 'cancelled';
        await doc.save();
        await StockEntry().updateMany({ referenceId: doc._id, referenceType: 'adjustment' }, { $set: { status: 'deleted' } }).catch(() => {});
        res.json({ success: true, data: { entry: doc } });
    } catch (e) { next(e); }
};

exports.calculate = async (req, res, next) => {
    try {
        const stored = await Doc.findOne({ key: 'main' }).lean();
        res.json({ success: true, data: computeOldMetal(req.body || {}, Rules.resolve(stored)) });
    } catch (e) { next(e); }
};
