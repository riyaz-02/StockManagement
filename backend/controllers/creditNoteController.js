'use strict';
const mongoose = require('mongoose');
const CreditNote = require('../models/CreditNote');
const CN = require('../services/creditNote');
const { getConnection } = require('../config/db');
const { getSeller } = require('../services/billingSeller');
const { restorePiece } = require('../services/cancelReconcile');
const { resolveBranch } = require('../utils/branches');
const Calc = require('../services/billingCalc');

const invoices = () => getConnection().db.collection('invoices');
const fail = (res, code, message) => res.status(code).json({ success: false, message });
const str = (v) => (v == null ? '' : String(v).trim());
const oid = (v) => /^[0-9a-f]{24}$/i.test(str(v));
const HIDDEN = ['cancelled', 'void', 'deleted'];
const REFUND_MODES = ['Cash', 'Card', 'Online', 'Cheque'];

// can the caller see this invoice? (branch scope set by `protect`)
function canSee(req, inv) {
    const restrict = req.branchScope ? req.branchScope.restrict : null;
    return !restrict || restrict.includes(str(inv.branch_id) || 'main');
}

async function loadInvoice(req, res, id) {
    if (!oid(id)) { fail(res, 400, 'Choose an invoice'); return null; }
    const { ObjectId } = require('mongodb');
    const inv = await invoices().findOne({ _id: new ObjectId(id) });
    if (!inv) { fail(res, 404, 'Invoice not found'); return null; }
    if (!canSee(req, inv)) { fail(res, 403, 'This invoice belongs to another branch'); return null; }
    if (HIDDEN.includes(str(inv.status).toLowerCase())) { fail(res, 400, 'This invoice is cancelled: no credit note is needed'); return null; }
    return inv;
}

// what earlier (active) notes already credited on each line of the invoice
async function priorOf(invoiceNumber) {
    const prior = {};
    const notes = await CreditNote.find({ invoiceNumber: String(invoiceNumber), status: 'active' }).lean();
    for (const n of notes) for (const l of n.lines || []) prior[l.index] = Calc.r2((prior[l.index] || 0) + (l.taxable || 0));
    return { prior, notes };
}

// The most that can be paid back on a note: never more than the note itself, and never more than the customer actually paid
// for the invoice minus what earlier notes already refunded (a bill with a round-off is paid a few paise below taxable + tax).
function maxRefund(inv, notes, total) {
    const refunded = notes.reduce((a, n) => a + (Number(n.refundAmount) || 0), 0);
    const cap = Math.max(0, (Number(inv.paid_amount) || 0) - refunded);
    return Calc.r2(Math.min(total, cap));
}

// atomic serial per branch: app_counters { _id: 'cn:<branch>' }
async function nextNumber(branchId) {
    const branch = branchId && branchId !== 'main' ? await resolveBranch(branchId).catch(() => null) : null;
    let prefix = '';
    if (branch) {
        const b = await require('../models/Branch').findById(branchId).lean().catch(() => null);
        prefix = ((b && (b.invoicePrefix || b.code)) || String(branch.branchName).replace(/[^A-Za-z]/g, '').slice(0, 3) || 'BR').toUpperCase() + '-';
    }
    const r = await mongoose.connection.collection('app_counters').findOneAndUpdate({ _id: `cn:${branchId || 'main'}` }, { $inc: { seq: 1 } }, { upsert: true, returnDocument: 'after' });
    const seq = (r && (r.seq !== undefined ? r.seq : r.value && r.value.seq)) || 1;
    return `${prefix}CN-${String(seq).padStart(4, '0')}`;
}

const asked = (b) => (Array.isArray(b.lines) ? b.lines : []).map((l) => ({ index: l.index, taxable: l.taxable }));

// POST /preview { invoiceId, lines:[{index, taxable?}] }
exports.preview = async (req, res, next) => {
    try {
        const inv = await loadInvoice(req, res, req.body && req.body.invoiceId);
        if (!inv) return;
        const { prior, notes } = await priorOf(inv.invoice_number);
        const c = CN.compute(inv, asked(req.body), prior);
        if (!c.ok) return fail(res, 400, c.error);
        const today = Calc.todayIST();
        res.json({ success: true, data: { ...c, maxRefund: maxRefund(inv, notes, c.total), deadline: CN.deadline(str(inv.invoice_date)), reducesTax: CN.reducesTax(str(inv.invoice_date), today) } });
    } catch (e) { next(e); }
};

// GET /invoice/:id : the returnable state of an invoice (per line: taxable, already credited, left) + the notes made so far
exports.forInvoice = async (req, res, next) => {
    try {
        const { ObjectId } = require('mongodb');
        if (!oid(req.params.id)) return fail(res, 400, 'Choose an invoice');
        const inv = await invoices().findOne({ _id: new ObjectId(req.params.id) });
        if (!inv) return fail(res, 404, 'Invoice not found');
        if (!canSee(req, inv)) return fail(res, 403, 'This invoice belongs to another branch');
        const { prior, notes } = await priorOf(inv.invoice_number);
        const lines = (inv.items || []).map((l, i) => ({ index: i, particulars: str(l.particulars || l.particular), metal: str(l.metal_type), netWt: Number(l.net_wt) || 0, itemId: str(l.item_id), taxable: Calc.r2(Number(l.taxable_amount) || 0), credited: Calc.r2(prior[i] || 0), left: Calc.r2((Number(l.taxable_amount) || 0) - (prior[i] || 0)) }));
        res.json({ success: true, data: { invoiceNumber: str(inv.invoice_number), invoiceDate: str(inv.invoice_date), gstType: str(inv.gst_type), cancelled: HIDDEN.includes(str(inv.status).toLowerCase()), deadline: CN.deadline(str(inv.invoice_date)), lines, notes } });
    } catch (e) { next(e); }
};

// POST / { requestId, invoiceId, lines, reason, note, refundMode, refundAmount, restock }
exports.create = async (req, res, next) => {
    try {
        const b = req.body || {};
        const requestId = str(b.requestId);
        if (requestId.length < 8) return fail(res, 400, 'Missing request id (please update the app)');
        const again = await CreditNote.findOne({ requestId }).lean();
        if (again) return res.status(200).json({ success: true, data: { note: again }, duplicate: true });
        const inv = await loadInvoice(req, res, b.invoiceId);
        if (!inv) return;
        const { prior, notes: priorNotes } = await priorOf(inv.invoice_number);
        const c = CN.compute(inv, asked(b), prior);
        if (!c.ok) return fail(res, 400, c.error);
        const reason = CN.REASONS.includes(b.reason) ? b.reason : 'sales_return';
        const refundAmount = Calc.r2(Math.max(0, Number(b.refundAmount) || 0));
        if (refundAmount > c.total + 0.005) return fail(res, 400, `The refund cannot be more than the credit note (${c.total.toFixed(2)})`);
        const cap = maxRefund(inv, priorNotes, c.total);
        if (refundAmount > cap + 0.005) return fail(res, 400, `The refund cannot be more than what the customer paid (${cap.toFixed(2)})`);
        const refundMode = refundAmount > 0 ? str(b.refundMode) : '';
        if (refundAmount > 0 && !REFUND_MODES.includes(refundMode)) return fail(res, 400, 'Choose how the refund is paid');
        const today = Calc.todayIST();
        const seller = await getSeller();
        const branchId = str(inv.branch_id) || 'main';
        const number = await nextNumber(branchId);
        const who = { id: String(req.user._id), name: req.user.name || '' };

        // pieces come back into stock when the whole line is returned
        const restock = b.restock !== false;
        for (const l of c.lines) {
            l.restocked = false;
            if (restock && reason !== 'price_adjustment' && l.fullReturn && /^[0-9a-f]{24}$/i.test(l.itemId)) {
                l.restocked = await restorePiece(str(inv.invoice_number), l.itemId).catch(() => false);
            }
        }
        const note = await CreditNote.create({
            number, requestId, date: today, invoiceId: String(inv._id), invoiceNumber: str(inv.invoice_number), invoiceDate: str(inv.invoice_date),
            customerName: str(inv.customer_name), customerMobile: str(inv.customer_mobile), customerAddress: str(inv.customer_address), customerState: str(inv.customer_state), customerStateCode: str(inv.customer_state_code),
            sellerGstin: str(inv.seller_gstin) || seller.gstin, gstType: c.gstType, lines: c.lines, taxable: c.taxable, cgst: c.cgst, sgst: c.sgst, igst: c.igst, total: c.total,
            reason, note: str(b.note).slice(0, 300), refundMode, refundAmount, reducesTax: CN.reducesTax(str(inv.invoice_date), today), branchId,
            createdBy: who.id, createdByName: who.name,
        });
        require('../services/events').changed('billing', branchId, { id: who.id, name: who.name });
        require('../services/audit').record(req, 'credit_note', note._id, `${number} · ${str(inv.customer_name) || 'Walk-in'} (bill ${str(inv.invoice_number)})`, 'return / refund issued', [{ field: 'reason', to: reason }, { field: 'credit total', to: String(c.total) }, { field: 'refund', to: String(refundAmount) }]);
        res.status(201).json({ success: true, data: { note } });
    } catch (e) { next(e); }
};

exports.list = async (req, res, next) => {
    try {
        const f = {};
        if (str(req.query.invoice)) f.invoiceNumber = str(req.query.invoice);
        if (/^\d{4}-\d{2}-\d{2}$/.test(str(req.query.from)) && /^\d{4}-\d{2}-\d{2}$/.test(str(req.query.to))) f.date = { $gte: str(req.query.from), $lte: str(req.query.to) };
        const rows = await CreditNote.find(f).sort({ date: -1, createdAt: -1 }).limit(300).lean();
        res.json({ success: true, data: rows });
    } catch (e) { next(e); }
};

exports.get = async (req, res, next) => {
    try {
        const n = oid(req.params.id) ? await CreditNote.findById(req.params.id).lean() : null;
        if (!n) return fail(res, 404, 'Credit note not found');
        res.json({ success: true, data: n });
    } catch (e) { next(e); }
};
