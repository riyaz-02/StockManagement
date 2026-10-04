'use strict';
const mongoose = require('mongoose');
const Estimate = require('../models/Estimate');
const Calc = require('../services/billingCalc');
const { resolveBranch } = require('../utils/branches');

const str = (v) => String(v == null ? '' : v).trim();
const fail = (res, code, message) => res.status(code).json({ success: false, message });
const isId = (v) => /^[a-f0-9]{24}$/i.test(str(v));
const ymd = (v) => (/^\d{4}-\d{2}-\d{2}$/.test(str(v)) ? str(v) : '');
const addDays = (d, n) => { const x = new Date(`${d}T00:00:00Z`); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };

async function nextNumber(branchId) {
    let prefix = '';
    if (branchId && branchId !== 'main') {
        const b = await require('../models/Branch').findById(branchId).lean().catch(() => null);
        prefix = ((b && (b.invoicePrefix || b.code)) || 'BR').toUpperCase() + '-';
    }
    const r = await mongoose.connection.collection('app_counters').findOneAndUpdate({ _id: `est:${branchId || 'main'}` }, { $inc: { seq: 1 } }, { upsert: true, returnDocument: 'after' });
    const seq = (r && (r.seq !== undefined ? r.seq : r.value && r.value.seq)) || 1;
    return `${prefix}EST-${String(seq).padStart(4, '0')}`;
}

const view = (d) => {
    const today = Calc.todayIST();
    return {
        id: String(d._id), number: d.number, date: d.date, validTill: d.validTill, customerId: d.customerId || '', customerName: d.customerName, customerMobile: d.customerMobile,
        goldRate: d.goldRate, silverRate: d.silverRate, items: d.items, inputItems: d.inputItems, additionalCharges: d.additionalCharges, discount: d.discount, totals: d.totals, note: d.note,
        status: d.status === 'open' && d.validTill < today ? 'expired' : d.status, convertedInvoice: d.convertedInvoice || '', createdByName: d.createdByName || '', createdAt: d.createdAt,
    };
};

// what's on the quote, without sending every item's full detail (used by the list only)
const summarizeItems = (items) => {
    const list = Array.isArray(items) ? items : [];
    const weight = {};
    for (const it of list) { const m = it.metalType || 'Other'; weight[m] = Math.round(((weight[m] || 0) + (Number(it.netWt) || 0)) * 1000) / 1000; }
    return { count: list.length, first: list[0] ? list[0].particulars : '', weight };
};

const viewList = (d) => {
    const v = view(d);
    v.itemsSummary = summarizeItems(d.items);
    delete v.items;
    delete v.inputItems;
    return v;
};

// POST / { requestId, customerId?, customerName, customerMobile, items, goldRate, silverRate, additionalCharges, discount, validDays, note }
exports.create = async (req, res, next) => {
    try {
        const b = req.body || {};
        const requestId = str(b.requestId);
        if (requestId.length < 8) return fail(res, 400, 'Missing request id (please update the app)');
        const again = await Estimate.findOne({ requestId }).lean();
        if (again) return res.json({ success: true, duplicate: true, data: view(again) });
        const name = str(b.customerName).slice(0, 80);
        if (name.length < 2) return fail(res, 400, "Enter the customer's name");
        if (!Array.isArray(b.items) || !b.items.length || b.items.length > 50) return fail(res, 400, 'Add at least one item');
        // the same engine as a bill, intra-state, nothing paid; the tax shown is what a bill would carry
        const calc = Calc.computeInvoice({ items: b.items, goldRate: b.goldRate, silverRate: b.silverRate, interstate: false, additionalCharges: b.additionalCharges, discount: b.discount, paidAmount: 0 });
        if (!calc.ok) return fail(res, 400, calc.error);
        const today = Calc.todayIST();
        const days = Math.min(90, Math.max(1, Math.floor(Number(b.validDays) || 7)));
        const scope = req.branchScope ? req.branchScope.branchId : 'main';
        const branch = await resolveBranch(scope).catch(() => null);
        const number = await nextNumber(branch && branch.branchId ? branch.branchId : scope);
        const doc = await Estimate.create({
            number, requestId, date: today, validTill: addDays(today, days),
            customerId: isId(b.customerId) ? str(b.customerId) : '', customerName: name, customerMobile: str(b.customerMobile).replace(/\D/g, '').slice(-10),
            goldRate: calc.goldRate, silverRate: calc.silverRate,
            inputItems: JSON.parse(JSON.stringify(b.items)), items: calc.items,
            additionalCharges: calc.additionalCharges, discount: calc.discountGiven,
            totals: { hallmark: calc.hallmarkTotal, taxable: calc.gstSummary.total_taxable_amount, cgst: calc.gstSummary.total_cgst || 0, sgst: calc.gstSummary.total_sgst || 0, igst: calc.gstSummary.total_igst || 0, gst: calc.gstSummary.total_gst, total: calc.totalAmount, payable: calc.totalPayableAmount, roundOff: calc.roundOff, discount: calc.discountGiven },
            note: str(b.note).slice(0, 300), createdBy: String(req.user._id), createdByName: req.user.name || '',
        });
        require('../services/events').changed('estimates', doc.branchId, { id: req.user._id, name: req.user.name });
        require('../services/audit').record(req, 'estimate', doc._id, `${number} · ${name}`, 'created', [{ field: 'total', to: String(calc.totalPayableAmount) }]);
        res.status(201).json({ success: true, data: view(doc.toObject()) });
    } catch (e) { next(e); }
};

// GET /?q=&status=open|converted|cancelled|expired
exports.list = async (req, res, next) => {
    try {
        const f = {};
        const today = Calc.todayIST();
        const st = str(req.query.status);
        if (st === 'expired') { f.status = 'open'; f.validTill = { $lt: today }; }
        else if (st === 'open') { f.status = 'open'; f.validTill = { $gte: today }; }
        else if (['converted', 'cancelled'].includes(st)) f.status = st;
        const q = str(req.query.q);
        if (q.length >= 2) { const rx = new RegExp(q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'); f.$or = [{ customerName: rx }, { customerMobile: rx }, { number: rx }]; }
        const rows = await Estimate.find(f).sort({ createdAt: -1 }).limit(200).select('-inputItems').lean();
        res.json({ success: true, data: rows.map(viewList) });
    } catch (e) { next(e); }
};

exports.get = async (req, res, next) => {
    try {
        const d = isId(req.params.id) ? await Estimate.findById(req.params.id).lean() : null;
        if (!d) return fail(res, 404, 'Estimate not found');
        res.json({ success: true, data: view(d) });
    } catch (e) { next(e); }
};

// POST /:id/converted { invoiceNumber } : the app made an invoice from this estimate
exports.converted = async (req, res, next) => {
    try {
        const d = isId(req.params.id) ? await Estimate.findOneAndUpdate({ _id: req.params.id, status: 'open' }, { $set: { status: 'converted', convertedInvoice: str(req.body && req.body.invoiceNumber) } }, { new: true }).lean() : null;
        if (!d) return fail(res, 404, 'Estimate not found or already used');
        require('../services/audit').record(req, 'estimate', d._id, `${d.number} · ${d.customerName}`, 'billed', [{ field: 'invoice', to: d.convertedInvoice }]);
        res.json({ success: true, data: view(d) });
    } catch (e) { next(e); }
};

exports.cancel = async (req, res, next) => {
    try {
        const d = isId(req.params.id) ? await Estimate.findOneAndUpdate({ _id: req.params.id, status: 'open' }, { $set: { status: 'cancelled' } }, { new: true }).lean() : null;
        if (!d) return fail(res, 404, 'Estimate not found or already used');
        require('../services/audit').record(req, 'estimate', d._id, `${d.number} · ${d.customerName}`, 'cancelled', []);
        res.json({ success: true });
    } catch (e) { next(e); }
};
