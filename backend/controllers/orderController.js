'use strict';
const mongoose = require('mongoose');
const Order = require('../models/CustomerOrder');
const Calc = require('../services/billingCalc');
const { resolveBranch } = require('../utils/branches');

const MODES = ['Cash', 'Card', 'Online', 'Cheque'];
const str = (v) => String(v == null ? '' : v).trim();
const r2 = (n) => Math.round((Number(n) + Number.EPSILON) * 100) / 100;
const fail = (res, code, message) => res.status(code).json({ success: false, message });
const isId = (v) => /^[a-f0-9]{24}$/i.test(str(v));
const ymd = (v) => (/^\d{4}-\d{2}-\d{2}$/.test(str(v)) ? str(v) : '');
const who = (req) => req.user.name || '';

async function nextNumber(branchId) {
    let prefix = '';
    if (branchId && branchId !== 'main') {
        const b = await require('../models/Branch').findById(branchId).lean().catch(() => null);
        prefix = ((b && (b.invoicePrefix || b.code)) || 'BR').toUpperCase() + '-';
    }
    const r = await mongoose.connection.collection('app_counters').findOneAndUpdate({ _id: `ord:${branchId || 'main'}` }, { $inc: { seq: 1 } }, { upsert: true, returnDocument: 'after' });
    const seq = (r && (r.seq !== undefined ? r.seq : r.value && r.value.seq)) || 1;
    return `${prefix}ORD-${String(seq).padStart(4, '0')}`;
}

const view = (d) => {
    const today = Calc.todayIST();
    const active = ['new', 'making', 'ready'].includes(d.status);
    const days = Math.round((new Date(`${d.deliveryDate}T00:00:00Z`) - new Date(`${today}T00:00:00Z`)) / 86400000);
    return {
        id: String(d._id), number: d.number, date: d.date, customerId: d.customerId || '', customerName: d.customerName, customerMobile: d.customerMobile,
        description: d.description, metalType: d.metalType, purity: d.purity, approxWeight: d.approxWeight, estimatedPrice: d.estimatedPrice,
        deliveryDate: d.deliveryDate, daysLeft: active ? days : null, overdue: active && days < 0, karigar: d.karigar || '', note: d.note || '',
        advances: d.advances || [], advancePaid: d.advancePaid || 0, refunds: d.refunds || [], balanceEstimate: r2(Math.max(0, (d.estimatedPrice || 0) - (d.advancePaid || 0))),
        status: d.status, history: d.history || [], invoiceNumber: d.invoiceNumber || '', createdByName: d.createdByName || '', createdAt: d.createdAt,
    };
};

function advanceOf(b, req) {
    const amount = r2(b.advanceAmount !== undefined ? b.advanceAmount : b.amount);
    if (!(amount > 0)) return { none: true };
    if (amount > 10000000) return { error: 'That advance looks too large' };
    const mode = MODES.includes(b.advanceMode || b.mode) ? (b.advanceMode || b.mode) : 'Cash';
    return { amount, mode };
}

// Income Tax s.269ST: all cash from one person in a day must stay below Rs 2,00,000; the same care applies to an advance
const cashTooMuch = (amount, mode) => mode === 'Cash' && amount >= 200000;

// POST / { requestId, customerId?, customerName, customerMobile, description, metalType, purity, approxWeight, estimatedPrice, deliveryDate, advanceAmount, advanceMode, karigar, note }
exports.create = async (req, res, next) => {
    try {
        const b = req.body || {};
        const requestId = str(b.requestId);
        if (requestId.length < 8) return fail(res, 400, 'Missing request id (please update the app)');
        const again = await Order.findOne({ requestId }).lean();
        if (again) return res.json({ success: true, duplicate: true, data: view(again) });
        const name = str(b.customerName).slice(0, 80);
        if (name.length < 2) return fail(res, 400, "Enter the customer's name");
        if (!str(b.customerMobile).replace(/\D/g, '').length && !isId(b.customerId)) return fail(res, 400, "Enter the customer's mobile number so you can call when it is ready");
        const description = str(b.description).slice(0, 300);
        if (description.length < 3) return fail(res, 400, 'Describe what is to be made');
        const today = Calc.todayIST();
        const delivery = ymd(b.deliveryDate);
        if (!delivery) return fail(res, 400, 'Choose the delivery date');
        if (delivery < today) return fail(res, 400, 'The delivery date cannot be in the past');
        const est = Math.max(0, r2(b.estimatedPrice));
        const adv = advanceOf(b, req);
        if (adv.error) return fail(res, 400, adv.error);
        if (!adv.none && cashTooMuch(adv.amount, adv.mode)) return fail(res, 400, 'Cash of ₹2,00,000 or more cannot be taken (Income Tax s.269ST). Take it by Online / Card / Cheque.');
        if (!adv.none && est > 0 && adv.amount > est) return fail(res, 400, 'The advance is more than the price told to the customer');
        const scope = req.branchScope ? req.branchScope.branchId : 'main';
        const branch = await resolveBranch(scope).catch(() => null);
        const number = await nextNumber(branch && branch.branchId ? branch.branchId : scope);
        const now = new Date();
        const doc = await Order.create({
            number, requestId, date: today, customerId: isId(b.customerId) ? str(b.customerId) : '', customerName: name, customerMobile: str(b.customerMobile).replace(/\D/g, '').slice(-10),
            description, metalType: str(b.metalType).toLowerCase() || 'gold', purity: str(b.purity).slice(0, 12), approxWeight: Math.max(0, Number(b.approxWeight) || 0), estimatedPrice: est,
            deliveryDate: delivery, karigar: str(b.karigar).slice(0, 60), note: str(b.note).slice(0, 300),
            advances: adv.none ? [] : [{ date: today, amount: adv.amount, mode: adv.mode, byName: who(req), at: now }], advancePaid: adv.none ? 0 : adv.amount,
            history: [{ status: 'new', at: now, byName: who(req) }], createdBy: String(req.user._id), createdByName: who(req),
        });
        res.status(201).json({ success: true, data: view(doc.toObject()) });
    } catch (e) { next(e); }
};

// GET /?status=active|new|making|ready|delivered|cancelled|overdue&q=
exports.list = async (req, res, next) => {
    try {
        const f = {};
        const st = str(req.query.status);
        const today = Calc.todayIST();
        if (st === 'active') f.status = { $in: ['new', 'making', 'ready'] };
        else if (st === 'overdue') { f.status = { $in: ['new', 'making', 'ready'] }; f.deliveryDate = { $lt: today }; }
        else if (Order.STATUSES.includes(st)) f.status = st;
        const q = str(req.query.q);
        if (q.length >= 2) { const rx = new RegExp(q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'); f.$or = [{ customerName: rx }, { customerMobile: rx }, { number: rx }, { description: rx }]; }
        const rows = await Order.find(f).sort({ deliveryDate: 1, createdAt: -1 }).limit(300).lean();
        const all = rows.map(view);
        // counts for the tabs (whole shop, whatever the filter)
        const [act, over, ready] = await Promise.all([
            Order.countDocuments({ status: { $in: ['new', 'making', 'ready'] } }),
            Order.countDocuments({ status: { $in: ['new', 'making', 'ready'] }, deliveryDate: { $lt: today } }),
            Order.countDocuments({ status: 'ready' }),
        ]);
        res.json({ success: true, data: all, counts: { active: act, overdue: over, ready } });
    } catch (e) { next(e); }
};

exports.get = async (req, res, next) => {
    try {
        const d = isId(req.params.id) ? await Order.findById(req.params.id).lean() : null;
        if (!d) return fail(res, 404, 'Order not found');
        res.json({ success: true, data: view(d) });
    } catch (e) { next(e); }
};

// POST /:id/advance { amount, mode, requestId? } : more advance
exports.addAdvance = async (req, res, next) => {
    try {
        const adv = advanceOf(req.body || {}, req);
        if (adv.none) return fail(res, 400, 'Enter the amount');
        if (adv.error) return fail(res, 400, adv.error);
        if (cashTooMuch(adv.amount, adv.mode)) return fail(res, 400, 'Cash of ₹2,00,000 or more cannot be taken (Income Tax s.269ST). Take it by Online / Card / Cheque.');
        const d0 = isId(req.params.id) ? await Order.findById(req.params.id).lean() : null;
        if (!d0) return fail(res, 404, 'Order not found');
        if (!['new', 'making', 'ready'].includes(d0.status)) return fail(res, 400, 'This order is closed');
        if (d0.estimatedPrice > 0 && d0.advancePaid + adv.amount > d0.estimatedPrice + 0.005) return fail(res, 400, `The advance cannot be more than the price told (₹${d0.estimatedPrice}); already taken ₹${d0.advancePaid}`);
        const d = await Order.findOneAndUpdate({ _id: d0._id, status: { $in: ['new', 'making', 'ready'] } },
            { $push: { advances: { date: Calc.todayIST(), amount: adv.amount, mode: adv.mode, byName: who(req), at: new Date() } }, $inc: { advancePaid: adv.amount } }, { new: true }).lean();
        if (!d) return fail(res, 400, 'This order is closed');
        res.json({ success: true, data: view(d) });
    } catch (e) { next(e); }
};

// POST /:id/status { status: making|ready, karigar? } : moves the order forward
exports.setStatus = async (req, res, next) => {
    try {
        const b = req.body || {};
        const to = str(b.status);
        const from = { making: ['new', 'ready'], ready: ['new', 'making'] }[to];
        if (!from) return fail(res, 400, 'Choose making or ready');
        const set = { status: to };
        if (b.karigar !== undefined) set.karigar = str(b.karigar).slice(0, 60);
        const d = isId(req.params.id) ? await Order.findOneAndUpdate({ _id: req.params.id, status: { $in: from } }, { $set: set, $push: { history: { status: to, at: new Date(), byName: who(req) } } }, { new: true }).lean() : null;
        if (!d) return fail(res, 400, 'This order cannot move to that step');
        res.json({ success: true, data: view(d) });
    } catch (e) { next(e); }
};

// POST /:id/cancel { refundMode, refundAmount?, reason } : the advance is paid back (all of it, or the amount agreed)
exports.cancel = async (req, res, next) => {
    try {
        const b = req.body || {};
        const d0 = isId(req.params.id) ? await Order.findById(req.params.id).lean() : null;
        if (!d0) return fail(res, 404, 'Order not found');
        if (!['new', 'making', 'ready'].includes(d0.status)) return fail(res, 400, 'This order is closed');
        const refund = b.refundAmount === undefined || b.refundAmount === '' ? d0.advancePaid : r2(b.refundAmount);
        if (refund < 0 || refund > d0.advancePaid + 0.005) return fail(res, 400, `The refund cannot be more than the advance taken (₹${d0.advancePaid})`);
        const mode = MODES.includes(b.refundMode) ? b.refundMode : 'Cash';
        const reason = str(b.reason).slice(0, 200);
        if (d0.advancePaid > 0 && refund < d0.advancePaid && reason.length < 3) return fail(res, 400, 'Say why part of the advance is kept (for example work already done)');
        const set = { status: 'cancelled' };
        const push = { history: { status: 'cancelled', at: new Date(), byName: who(req) } };
        if (refund > 0) push.refunds = { date: Calc.todayIST(), amount: refund, mode, reason, byName: who(req), at: new Date() };
        const d = await Order.findOneAndUpdate({ _id: d0._id, status: { $in: ['new', 'making', 'ready'] } }, { $set: set, $push: push }, { new: true }).lean();
        if (!d) return fail(res, 400, 'This order is closed');
        res.json({ success: true, data: view(d) });
    } catch (e) { next(e); }
};
