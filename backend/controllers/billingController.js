/**
 * billingController.js — GST billing on the LIVE `invoices` collection.
 *
 * The business already runs on the LGPManagement website, which stores its
 * invoices in `invoices` (snake_case) and numbers them from
 * `shop_info.last_invoice_number`. This controller writes exactly that shape,
 * so an invoice made in the app appears on the website immediately, and the
 * two share one number sequence.
 *
 * Built for several branches and staff billing at the same moment (the website
 * cannot do this: it suggests a number, then saves it later):
 *   - the invoice number is taken with one ATOMIC increment of shop_info;
 *   - every create / payment carries a client `requestId`, claimed atomically
 *     first, so a double-tap or a retry over a bad connection can never bill
 *     twice;
 *   - a payment is ONE atomic update: the "still due" check, the new totals and
 *     the history entry move together, so two staff cannot over-collect.
 *
 * Writes are limited to: inserting a new invoice, recording a payment on an
 * invoice, and counting a print. There is NO delete, no cancel and no
 * amendment here (those stay on the website).
 */
'use strict';

const { getLgpAdminConnection } = require('../config/db');
const { hasPermission } = require('../middleware/auth');
const logger = require('../config/logger');
const { Branch, resolveBranch } = require('../utils/branches');
const V = require('../utils/directoryValidators');
const Calc = require('../services/billingCalc');
const { getSeller, TERMS, DECLARATION, HSN_CODES, TERMS_OF_DELIVERY } = require('../services/billingSeller');
const { toView, toRow, HIDDEN_STATUSES } = require('../services/billingView');
const { ensureCustomerProfile } = require('./directoryController');
const GstStates = require('../services/gstStates');

const db = () => getLgpAdminConnection().db;
const Invoices = () => db().collection('invoices');
const ShopInfo = () => db().collection('shop_info');
const Locks = () => db().collection('app_request_locks');
const Customers = () => require('../models/directory/LgpCustomer')(getLgpAdminConnection());
const Profiles = () => require('../models/directory/DirectoryCustomerProfile')(getLgpAdminConnection());
const { ObjectId } = require('mongodb');

const { str } = V;
const PAYMENT_MODES = ['Cash', 'Card', 'Online', 'Cheque'];   // same as the website
// Income Tax Act s.269ST: a shop may not receive Rs 2,00,000 OR MORE in cash from one person in a day (all invoices
// together), in one transaction, or for one event. Penalty (s.271DA) = the cash received; it falls on the shop.
const CASH_LIMIT = 200000;
const ADDRESS_LIMIT = 50000;      // CGST Rule 46(f)
const money = (n) => Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 });
const escapeRegex = (s) => String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const fail = (res, code, message, extra = {}) => res.status(code).json({ success: false, message, ...extra });
const me = (req) => ({ id: String(req.user._id), name: req.user.name || req.user.username || '' });
const isReqId = (v) => typeof v === 'string' && /^[A-Za-z0-9_-]{8,64}$/.test(v);
const oid = (v) => { try { return new ObjectId(String(v)); } catch (_) { return null; } };
const ymd = (v) => (/^\d{4}-\d{2}-\d{2}/.test(str(v)) ? str(v).slice(0, 10) : '');

// One-time, additive lock table (app-owned). _id = the client's request id.
let lockIndexReady = null;
const ensureLockIndex = () => (lockIndexReady ||= Locks().createIndex({ at: 1 }).catch(() => {}));

// The selling entity for a branch: its own GSTIN when it has one, else the firm's. The state of the
// supplier decides CGST+SGST (same state) or IGST (another state).
async function supplierFor(branch) {
    const seller = await getSeller();
    let gstin = seller.gstin;
    let stateCode = seller.stateCode || String(gstin || '').slice(0, 2) || '19';
    let branchState = null;
    if (branch && branch.branchId !== 'main') {
        let b = null;
        try { b = await Branch.findById(branch.branchId).lean(); } catch (_) { /* ignore */ }
        if (b) {
            if (b.gstin && /^\d{2}[A-Z0-9]{13}$/.test(b.gstin)) { gstin = b.gstin; stateCode = b.gstin.slice(0, 2); }
            branchState = GstStates.findByName(b.state);
        }
    }
    const own = GstStates.STATES.find((s) => s.code === stateCode) || GstStates.STATES.find((s) => s.code === '19');
    // customers are assumed to be local to the shop: default place = the branch's state, else the GSTIN's state
    return { seller: { ...seller, gstin, stateCode }, stateCode, defaultPlace: (branchState || own).place };
}

// ── invoice numbers ──────────────────────────────────────────────────────────
// Main branch continues the website's own sequence (shop_info shop_id "default",
// plain 4-digit numbers). Other branches get their own PREFIX-0001 series.
async function series(branchId) {
    if (branchId === 'main') return { shopId: 'default', prefix: '', start: parseInt(process.env.INVOICE_START_MAIN, 10) || 1300 };
    let b = null;
    try { b = await Branch.findById(branchId).lean(); } catch (_) { /* ignore */ }
    const initials = b && b.name ? b.name.replace(/[^A-Za-z]/g, '').slice(0, 3).toUpperCase() : 'BR';
    return { shopId: `branch:${branchId}`, prefix: ((b && (b.invoicePrefix || b.code)) || initials || 'BR').toUpperCase(), start: 1 };
}
const formatNumber = (s, n) => (s.prefix ? `${s.prefix}-${String(n).padStart(4, '0')}` : String(n).padStart(4, '0'));

async function allocateNumber(branchId) {
    const s = await series(branchId);
    // Make sure the counter document exists. (For "default" it already does on the live database.)
    if (!(await ShopInfo().findOne({ shop_id: s.shopId }, { projection: { _id: 1 } }))) {
        await ShopInfo().updateOne({ shop_id: s.shopId }, { $setOnInsert: { shop_id: s.shopId, last_invoice_number: s.start - 1, created_at: new Date() } }, { upsert: true });
    }
    // The website also writes last_invoice_number (after saving), and may move it back. So verify each
    // number is really unused before handing it out.
    for (let i = 0; i < 25; i++) {
        const doc = await ShopInfo().findOneAndUpdate(
            { shop_id: s.shopId }, { $inc: { last_invoice_number: 1 }, $set: { updated_at: new Date() } }, { returnDocument: 'after' });
        const number = formatNumber(s, doc.last_invoice_number);
        if (!(await Invoices().findOne({ invoice_number: number }, { projection: { _id: 1 } }))) return number;
    }
    throw new Error('Could not find a free invoice number');
}

async function peekNumber(branchId) {
    const s = await series(branchId);
    const info = await ShopInfo().findOne({ shop_id: s.shopId });
    return formatNumber(s, ((info && Number(info.last_invoice_number)) || s.start - 1) + 1);
}

// ── who can see what ─────────────────────────────────────────────────────────
const StockItem = () => require('../models/Item');
const StockBox = () => require('../models/Container');

// The pieces on a saved invoice leave stock: status "sold", their box slot is freed. Never fails the invoice.
async function markSold(items, invoiceNumber, who) {
    for (const it of items) {
        try {
            const r = await StockItem().updateOne({ _id: it._id, status: { $nin: ['sold', 'deleted'] } }, { $set: { status: 'sold', soldInvoice: invoiceNumber, soldAt: new Date(), soldBy: who.name || '' } });
            if (r.modifiedCount && it.containerId && it.slotNumber) {
                await StockBox().updateOne({ _id: it.containerId }, { $set: { 'slots.$[s].itemId': null, 'slots.$[s].reserved': false } }, { arrayFilters: [{ 's.itemId': it._id }] });
            }
        } catch (e) { logger.warn(`[billing] could not mark ${it._id} sold: ${e.message}`); }
    }
}

// Old invoices have no branch: they belong to the main branch.
const branchMatch = (id) => (id === 'main' ? { $or: [{ branch_id: 'main' }, { branch_id: { $exists: false } }] } : { branch_id: id });

// req.branchScope is set by `protect`: restrict = null (whole firm) or the branches this request may see; branchId = the
// branch new records are filed under (the caller's own, or the one an admin switched to with X-Branch).
const myBranch = (req) => (req.branchScope && req.branchScope.branchId) || req.user.branchId || 'main';
async function scope(req) {
    const and = [];
    const restrict = req.branchScope ? req.branchScope.restrict : [req.user.branchId || 'main'];
    if (!restrict) {
        if (str(req.query.branch)) and.push(branchMatch(str(req.query.branch)));
    } else {
        and.push({ $or: restrict.map(branchMatch) });
    }
    return and;
}
async function canSee(req, doc) {
    const restrict = req.branchScope ? req.branchScope.restrict : [req.user.branchId || 'main'];
    return !restrict || restrict.includes(str(doc.branch_id) || 'main');
}

// ── GET /api/billing/meta ────────────────────────────────────────────────────
exports.meta = async (req, res, next) => {
    try {
        const branch = await resolveBranch(myBranch(req));
        const sup = await supplierFor(branch);
        const todayRate = (await require('../models/AppRate').findOne({ key: 'main' }).lean()) || { gold: 0, silver: 0 };
        const last = await Invoices().find({ gold_rate: { $gt: 0 } }).sort({ _id: -1 }).limit(1).project({ gold_rate: 1, silver_rate: 1 }).toArray();
        res.json({
            success: true,
            data: {
                seller: sup.seller,
                supplyStateCode: sup.stateCode,
                defaultPlace: sup.defaultPlace,
                states: GstStates.STATES,
                branch,
                nextInvoiceNumber: await peekNumber(branch.branchId),
                goldRate: todayRate.gold > 0 ? todayRate.gold : (last[0] ? Number(last[0].gold_rate) || 0 : 0),        // today's rate (Home) first, else the last bill's
                silverRate: todayRate.silver > 0 ? todayRate.silver : (last[0] ? Number(last[0].silver_rate) || 0 : 0),
                paymentModes: PAYMENT_MODES,
                cashLimit: CASH_LIMIT,
                addressLimit: ADDRESS_LIMIT,
                hsnCodes: HSN_CODES,
                termsOfDelivery: TERMS_OF_DELIVERY,
                calcRule: Calc.RULE,
                tdsThreshold: Calc.TDS_THRESHOLD,
                terms: TERMS,
                declaration: DECLARATION,
                today: Calc.todayIST(),
            },
        });
    } catch (e) { next(e); }
};

// GET /api/billing/customer/:id — what this customer already owes, and recent bills
exports.customerSummary = async (req, res, next) => {
    try {
        const c = await Customers().findOne({ _id: req.params.id, is_deleted: { $ne: true } })
            .select('customer_name address whatsapp_no mobile_no mobile_no_3 mobile_no_4').lean();
        if (!c) return fail(res, 404, 'Customer not found');
        const p = await Profiles().findOne({ customerId: c._id }).select('customerCode contacts state').lean();
        const st = p && p.state ? GstStates.findByName(p.state) : null;
        // Old invoices carry no customer link, only the buyer's mobile: match on both.
        const phones = new Set([c.whatsapp_no, c.mobile_no, c.mobile_no_3, c.mobile_no_4, ...((p && p.contacts) || []).map((k) => k.number)].map((x) => V.normalizePhone(x)).filter(Boolean));
        const match = { $or: [{ customer_id: String(c._id) }, ...(phones.size ? [{ customer_mobile: { $in: [...phones] } }] : [])], status: { $nin: HIDDEN_STATUSES } };
        const [agg] = await Invoices().aggregate([
            { $match: match },
            { $group: { _id: null, invoices: { $sum: 1 },
                purchases: { $sum: { $convert: { input: '$total_payable_amount', to: 'double', onError: 0, onNull: 0 } } },
                due: { $sum: { $max: [0, { $subtract: [{ $convert: { input: '$total_payable_amount', to: 'double', onError: 0, onNull: 0 } }, { $convert: { input: '$paid_amount', to: 'double', onError: 0, onNull: 0 } }] }] } } } },
        ]).toArray();
        const recent = await Invoices().find(match).sort({ _id: -1 }).limit(5).toArray();
        res.json({ success: true, data: {
            id: String(c._id), code: p ? p.customerCode : null, place: st ? st.place : null, address: c.address || '',
            cashToday: await cashReceivedToday({ customerId: String(c._id), mobiles: [...phones] }, Calc.todayIST()),
            totalDue: Calc.r2(agg ? agg.due : 0), totalPurchases: Calc.r2(agg ? agg.purchases : 0), invoices: agg ? agg.invoices : 0,
            recent: recent.map((d) => { const v = toView(d); return { _id: v._id, invoiceNumber: v.invoiceNumber, invoiceDate: v.invoiceDate, totalPayableAmount: v.totalPayableAmount, dueAmount: v.dueAmount }; }),
        } });
    } catch (e) {
        if (e.name === 'CastError') return fail(res, 400, 'Invalid customer id');
        next(e);
    }
};

// Cash already received today from this person, across every invoice (by customer id or any of their mobiles).
async function cashReceivedToday({ customerId, mobiles }, today) {
    const or = [];
    if (customerId) or.push({ customer_id: String(customerId) });
    const phones = [...new Set((mobiles || []).map((x) => V.normalizePhone(x)).filter(Boolean))];
    if (phones.length) or.push({ customer_mobile: { $in: phones } });
    if (!or.length) return 0;                                   // an anonymous walk-in cannot be tracked
    const [row] = await Invoices().aggregate([
        { $match: { $or: or, status: { $nin: HIDDEN_STATUSES }, 'payment_history.payment_date': today } },
        { $unwind: '$payment_history' },
        { $match: { 'payment_history.payment_mode': 'Cash', 'payment_history.payment_date': today } },
        { $group: { _id: null, total: { $sum: { $convert: { input: '$payment_history.amount', to: 'double', onError: 0, onNull: 0 } } } } },
    ]).toArray();
    return Calc.r2(row ? row.total : 0);
}
// the most cash (whole rupees) that can still be taken today from this person
const cashRoom = (already) => Math.max(0, Math.floor(CASH_LIMIT - 0.01 - already));
const cashLimitMessage = (already, tryingToTake) => {
    const room = cashRoom(already);
    return `Cash limit (Income Tax Act s.269ST): ₹${money(CASH_LIMIT)} or more in cash from one customer in a day is not allowed. `
        + (already > 0 ? `₹${money(already)} was already received in cash today. ` : '')
        + (room > 0 ? `You can take at most ₹${money(room)} in cash (you tried ₹${money(tryingToTake)}); take the rest by Card, Online or Cheque.` : 'Take this payment by Card, Online or Cheque.');
};

// Turn the request into a clean list of payments. Old clients send paymentMode + paidAmount; new ones send payments[].
function readPayments(b) {
    const raw = Array.isArray(b.payments) ? b.payments : [{ mode: b.paymentMode, amount: b.paidAmount, reference: b.paymentReference }];
    if (raw.length > 6) return { error: 'At most 6 payment lines' };
    const list = [];
    for (const r of raw) {
        const amount = Calc.r2(Math.max(0, Number(r && r.amount) || 0));
        if (!(amount > 0)) continue;
        const mode = Array.isArray(b.payments) ? (r && r.mode) : (PAYMENT_MODES.includes(r && r.mode) ? r.mode : 'Cash');
        if (!PAYMENT_MODES.includes(mode)) return { error: `Payment mode must be one of ${PAYMENT_MODES.join(', ')}` };
        list.push({ mode, amount, reference: str(r.reference) });
    }
    return { list, total: Calc.r2(list.reduce((a, x) => a + x.amount, 0)) };
}

// GET /api/billing/cash-today?customerId=&mobile= — how much cash can still be taken today from this person
exports.cashToday = async (req, res, next) => {
    try {
        const mobiles = [];
        let customerId = str(req.query.customerId);
        if (customerId) {
            const c = oid(customerId) ? await Customers().findOne({ _id: customerId, is_deleted: { $ne: true } }).select('whatsapp_no mobile_no mobile_no_3 mobile_no_4').lean() : null;
            if (!c) return fail(res, 404, 'Customer not found');
            const p = await Profiles().findOne({ customerId: c._id }).select('contacts').lean();
            mobiles.push(c.whatsapp_no, c.mobile_no, c.mobile_no_3, c.mobile_no_4, ...((p && p.contacts) || []).map((k) => k.number));
        }
        if (str(req.query.mobile)) mobiles.push(req.query.mobile);
        const already = await cashReceivedToday({ customerId, mobiles }, Calc.todayIST());
        res.json({ success: true, data: { limit: CASH_LIMIT, alreadyToday: already, room: cashRoom(already) } });
    } catch (e) { next(e); }
};

// ── POST /api/billing/invoices ───────────────────────────────────────────────
const OldMetalModel = () => require('../models/OldMetal');
const OrderModel = () => require('../models/CustomerOrder');

exports.createInvoice = async (req, res, next) => {
    let claimed = false;
    let claimedOm = false;
    let claimedOrder = false;
    const b = req.body || {};
    try {
        if (!isReqId(b.requestId)) return fail(res, 400, 'Missing request id (please update the app)');
        await ensureLockIndex();

        // ── claim the request id (atomic): only one request may create this invoice ──
        try {
            await Locks().insertOne({ _id: b.requestId, status: 'pending', at: new Date(), by: String(req.user._id) });
            claimed = true;
        } catch (e) {
            if (e.code !== 11000) throw e;
            // Already claimed: either done (return that invoice), in flight (wait a moment), or failed (take it over).
            for (let i = 0; i < 20; i++) {
                const done = await Invoices().findOne({ request_id: b.requestId });
                if (done) return res.json({ success: true, duplicate: true, data: toView(done) });
                const lock = await Locks().findOne({ _id: b.requestId });
                if (lock && lock.status === 'failed') {
                    const took = await Locks().findOneAndUpdate({ _id: b.requestId, status: 'failed' }, { $set: { status: 'pending', at: new Date() } });
                    if (took) { claimed = true; break; }
                }
                await new Promise((r) => setTimeout(r, 250));
            }
            if (!claimed) return fail(res, 409, 'This invoice is still being saved. Please wait a moment and check the list before trying again.');
        }

        // ── customer ──
        let cust;
        let cashWho = { customerId: '', mobiles: [] };
        if (str(b.customerId)) {
            const c = oid(b.customerId) ? await Customers().findOne({ _id: b.customerId, is_deleted: { $ne: true } }).lean() : null;
            if (!c) return await release(b, res, 404, 'Customer not found');
            const p = await ensureCustomerProfile(c._id, me(req));
            cashWho = { customerId: String(c._id), mobiles: [c.whatsapp_no, c.mobile_no, c.mobile_no_3, c.mobile_no_4, ...((p && p.contacts) || []).map((k) => k.number)] };
            cust = {
                customer_id: String(c._id), customer_code: p.customerCode, walk_in: false,
                customer_name: c.customer_name || c.customer_name_bengali || '',
                customer_address: str(b.customerAddress) || c.address || '',
                customer_mobile: c.whatsapp_no || c.mobile_no || '',
            };
        } else {
            const name = str(b.customerName);
            if (name.length < 2) return await release(b, res, 400, 'Choose a customer, or enter the buyer\'s name');
            const mobile = V.normalizePhone(b.customerMobile);
            if (mobile && !V.isPhone10(mobile)) return await release(b, res, 400, 'Mobile number must be 10 digits');
            cust = { customer_id: '', walk_in: true, customer_name: name, customer_address: str(b.customerAddress), customer_mobile: mobile };
            cashWho = { customerId: '', mobiles: [mobile] };
        }
        cust.customer_pan = str(b.customerPan).toUpperCase();
        if (cust.customer_pan && !V.isPAN(cust.customer_pan)) return await release(b, res, 400, 'Customer PAN must look like ABCDE1234F');

        // ── place of supply decides the tax type: same state = CGST+SGST, another state = IGST ──
        const branch = await resolveBranch(myBranch(req));
        const sup = await supplierFor(branch);
        const place = GstStates.normalizePlace(b.placeOfSupply, sup.defaultPlace);
        const placeInfo = GstStates.parsePlace(place);
        const interstate = placeInfo.code !== sup.stateCode;

        // ── maths: the server recomputes everything ──
        const pays = readPayments(b);
        if (pays.error) return await release(b, res, 400, pays.error);
        const calc = Calc.computeInvoice({
            items: b.items, goldRate: b.goldRate, silverRate: b.silverRate, interstate,
            additionalCharges: b.additionalCharges, discount: b.discount, paidAmount: pays.total,
        });
        if (!calc.ok) return await release(b, res, 400, calc.error);
        // Selling a stock piece: it must still be in stock (a piece can only be sold once)
        const stockIds = [...new Set(calc.items.map((l) => l.item_id).filter((x) => /^[0-9a-f]{24}$/i.test(String(x || ''))))];
        const stock = stockIds.length ? await StockItem().find({ _id: { $in: stockIds } }).lean() : [];
        for (const it of stock) {
            if (['sold', 'deleted'].includes(it.status)) return await release(b, res, 400, `${it.name || 'This piece'} (${it.barcode}) is already ${it.status === 'sold' ? 'sold' : 'removed from stock'}`);
        }
        // CGST Rule 46(f): for an unregistered buyer, a bill of Rs 50,000 or more must carry the buyer's name and ADDRESS
        // (and the place of supply, which the invoice always has). This app does not record a buyer GSTIN, so it applies to every buyer.
        if (calc.totalPayableAmount >= ADDRESS_LIMIT && String(cust.customer_address || '').trim().length < 5) {
            return await release(b, res, 400, `Enter the buyer's address: it is required on a bill of ₹${money(ADDRESS_LIMIT)} or more (GST Rule 46)`);
        }
        if (calc.tdsApplicable && !cust.customer_pan) {
            return await release(b, res, 400, `Customer PAN is required above ₹${Calc.TDS_THRESHOLD.toLocaleString('en-IN')} (TDS)`);
        }
        // ── old metal received from this customer, adjusted against the bill (value counts as payment in kind) ──
        const omIds = [...new Set((Array.isArray(b.oldMetalIds) ? b.oldMetalIds : []).map(String).filter((x) => /^[0-9a-f]{24}$/i.test(x)))].slice(0, 10);
        let omDocs = [];
        if (omIds.length) {
            omDocs = await OldMetalModel().find({ _id: { $in: omIds }, status: 'active', kind: 'old', usedOnInvoice: { $in: ['', null] } }).lean();
            if (omDocs.length !== omIds.length) return await release(b, res, 400, 'Some of the old metal entries are already used, cancelled or not found');
        }
        const omTotal = Calc.r2(omDocs.reduce((a, x) => a + (x.amount || 0), 0));
        // ── a made-to-order piece is being delivered: the advance taken on it counts as already paid ──
        let orderDoc = null;
        if (str(b.orderId)) {
            orderDoc = /^[0-9a-f]{24}$/i.test(str(b.orderId)) ? await OrderModel().findOne({ _id: str(b.orderId), status: { $in: ['new', 'making', 'ready'] }, invoiceClaim: { $in: ['', null] } }).lean() : null;
            if (!orderDoc) return await release(b, res, 400, 'This order is already billed, cancelled or not found');
        }
        const advTotal = orderDoc ? Calc.r2(orderDoc.advancePaid || 0) : 0;
        if (omTotal > 0 || advTotal > 0) {
            // re-run the maths with the old metal and the order advance counted as paid, so due / advance are right
            const withOm = Calc.computeInvoice({ items: b.items, goldRate: b.goldRate, silverRate: b.silverRate, interstate, additionalCharges: b.additionalCharges, discount: b.discount, paidAmount: pays.total + omTotal + advTotal });
            if (!withOm.ok) return await release(b, res, 400, withOm.error);
            Object.assign(calc, withOm);
        }
        // ── cash limit: s.269ST counts every cash rupee from this person today, across invoices ──
        const cashNow = Calc.r2(pays.list.filter((x) => x.mode === 'Cash').reduce((a, x) => a + x.amount, 0));
        if (cashNow > 0) {
            const already = await cashReceivedToday(cashWho, Calc.todayIST());
            if (already + cashNow >= CASH_LIMIT) return await release(b, res, 400, cashLimitMessage(already, cashNow), { cashRoom: cashRoom(already) });
        }
        if (cust.walk_in && calc.dueAmount > 0) {
            return await release(b, res, 400, 'A walk-in bill must be paid in full. Add the customer to the list to keep a due balance.');
        }

        // ── state / place of supply, exactly as the website derives them ──
        const invoiceDate = ymd(b.invoiceDate) || Calc.todayIST();
        const deliveryDate = ymd(b.deliveryDate) || invoiceDate;

        // claim the old metal for this request first: one entry can only ever be adjusted once
        if (omDocs.length) {
            const claim = await OldMetalModel().updateMany({ _id: { $in: omDocs.map((x) => x._id) }, usedOnInvoice: { $in: ['', null] } }, { $set: { usedOnInvoice: `req:${b.requestId}` } });
            if (claim.modifiedCount !== omDocs.length) {
                await OldMetalModel().updateMany({ usedOnInvoice: `req:${b.requestId}` }, { $set: { usedOnInvoice: '' } });
                return await release(b, res, 400, 'Some of the old metal entries were just used on another bill');
            }
            claimedOm = true;
        }
        // claim the order for this request: it can only ever be billed once
        if (orderDoc) {
            const claim = await OrderModel().updateOne({ _id: orderDoc._id, status: { $in: ['new', 'making', 'ready'] }, invoiceClaim: { $in: ['', null] } }, { $set: { invoiceClaim: `req:${b.requestId}` } });
            if (!claim.modifiedCount) {
                if (claimedOm) await OldMetalModel().updateMany({ usedOnInvoice: `req:${b.requestId}` }, { $set: { usedOnInvoice: '' } }).catch(() => {});
                claimedOm = false;
                return await release(b, res, 400, 'This order was just billed on another invoice');
            }
            claimedOrder = true;
        }
        const number = await allocateNumber(branch.branchId);
        const who = me(req);
        const now = new Date();
        const words = Calc.amountInWords(calc.totalPayableAmount);
        const status = Calc.invoiceStatus(calc.totalPayableAmount, calc.paidAmount, deliveryDate, Calc.todayIST());

        const doc = {
            invoice_number: number,
            invoice_date: invoiceDate,
            customer_name: cust.customer_name,
            customer_address: cust.customer_address,
            customer_mobile: cust.customer_mobile,
            customer_id: cust.customer_id,
            customer_pan: cust.customer_pan,
            customer_state: placeInfo.name,
            customer_state_code: placeInfo.code,
            place_of_supply: place,
            reverse_charge: b.reverseCharge === 'Yes' ? 'Yes' : 'No',
            terms_of_delivery: TERMS_OF_DELIVERY.includes(b.termsOfDelivery) ? b.termsOfDelivery : 'Customer Pickup',
            reference: str(b.reference),
            lgp_wallet: 0,
            delivery_date: deliveryDate,
            gold_rate: calc.goldRate,
            silver_rate: calc.silverRate,
            items: calc.items,
            additional_charges: calc.additionalCharges,
            additional_charges_gst: calc.additionalGst,          // extra charges are taxed like the goods (s.15(2)(c))
            total_amount: calc.totalAmount,
            discount: calc.discount,
            round_off: calc.roundOff,
            note: str(b.note),
            total_payable_amount: calc.totalPayableAmount,
            amount_in_words: words.combined,
            paid_amount: calc.paidAmount,
            payment_mode: (pays.list.slice().sort((x, y) => y.amount - x.amount)[0] || { mode: omTotal > 0 ? 'Old Metal' : 'Cash' }).mode,   // the main mode (largest money part; 'Old Metal' only when nothing else was paid: the website's edit form and filters only know the money modes)
            due_advance: calc.dueAdvance,
            tds_applicable: calc.tdsApplicable,
            tds_rate: calc.tdsRate,
            tds_amount: calc.tdsAmount,
            gst_summary: calc.gstSummary,
            created_at: now,
            status,
            print_status: 0,
            pay_no: pays.list.length + (omTotal > 0 ? 1 : 0) + (advTotal > 0 ? 1 : 0),
            payment_history: [...pays.list, ...(omTotal > 0 ? [{ amount: omTotal, mode: 'Old Metal', reference: `Old metal adjusted (${omDocs.length} entr${omDocs.length === 1 ? 'y' : 'ies'})`, oldMetal: true }] : []), ...(advTotal > 0 ? [{ amount: advTotal, mode: 'Order Advance', reference: `Advance taken on order ${orderDoc.number}` }] : [])].map((x, i) => ({
                amount: x.amount, payment_mode: x.mode,
                transaction_reference: x.reference || `Initial payment with invoice #${number}`,
                description: 'Payment at the time of invoice creation',
                payment_date: Calc.todayIST(now), payment_time: new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Kolkata', hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' }).format(now),
                created_at: now, created_by: null, files: [],
                request_id: `${b.requestId}:${i}`, created_by_name: who.name, created_by_app_id: who.id, source: 'app',
            })),
            ...(orderDoc ? { order_number: orderDoc.number, order_advance: advTotal } : {}),
            ...(omDocs.length ? { old_metal: omDocs.map((x) => ({ id: String(x._id), metal: x.metalType, purity: x.purity, net: x.net, fine: x.fine, rate: x.rate, amount: x.amount, customer: x.customerName })), old_metal_amount: omTotal } : {}),
            // additive fields (the website ignores what it does not know)
            ...(cust.customer_code ? { customer_code: cust.customer_code } : {}),
            walk_in: cust.walk_in,
            branch_id: branch.branchId, branch_name: branch.branchName,
            created_by_name: who.name, created_by_app_id: who.id,
            request_id: b.requestId, calc_rule: calc.rule, source: 'app',
            gst_type: calc.gstType, supply_state_code: sup.stateCode, seller_gstin: sup.seller.gstin,
            // discount is taken off BEFORE GST (lines above are already net of it); the website's own `discount` stays 0
            discount_mode: calc.discountMode, discount_given: calc.discountGiven, discount_before_gst: calc.discountBeforeGst,
            gross_taxable: calc.grossTaxable, bill_before_discount: calc.billBeforeDiscount, metal_value: calc.metalValue,
        };

        const inserted = await Invoices().insertOne(doc);
        await markSold(stock, number, who);
        if (omDocs.length) await OldMetalModel().updateMany({ _id: { $in: omDocs.map((x) => x._id) } }, { $set: { usedOnInvoice: number } }).catch(() => {});
        if (orderDoc) await OrderModel().updateOne({ _id: orderDoc._id }, { $set: { status: 'delivered', invoiceNumber: number, invoiceClaim: number }, $push: { history: { status: 'delivered', at: new Date(), byName: who.name || '' } } }).catch(() => {});
        await Locks().updateOne({ _id: b.requestId }, { $set: { status: 'done', invoice_id: String(inserted.insertedId), number } }).catch(() => {});
        claimed = false;
        res.status(201).json({ success: true, data: toView({ ...doc, _id: inserted.insertedId }) });
    } catch (e) {
        if (claimedOm) await OldMetalModel().updateMany({ usedOnInvoice: `req:${b.requestId}` }, { $set: { usedOnInvoice: '' } }).catch(() => {});
        if (claimedOrder) await OrderModel().updateOne({ invoiceClaim: `req:${b.requestId}` }, { $set: { invoiceClaim: '' } }).catch(() => {});
        if (claimed) await Locks().updateOne({ _id: b.requestId }, { $set: { status: 'failed', error: String(e.message).slice(0, 200) } }).catch(() => {});
        next(e);
    }
};

// Reject a request that could not be processed: free its claim so the user can fix it and retry with the same id.
async function release(b, res, code, message, extra = {}) {
    await Locks().updateOne({ _id: b.requestId }, { $set: { status: 'failed', error: message } }).catch(() => {});
    return fail(res, code, message, extra);
}

// ── POST /api/billing/invoices/:id/payments ──────────────────────────────────
// GET /api/billing/last-making?name=&metal=&userWise=1 : the making charge PER GRAM of the last sale of the same kind of
// piece (same name and metal), for the Stock Setting rule "last entry" (userWise: only sales made by this user).
const escapeRe = (t) => String(t).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
exports.lastMaking = async (req, res, next) => {
    try {
        const name = str(req.query.name).replace(/\s*\((hallmarked|huid)[^)]*\)\s*/ig, '').replace(/\s*\+\s*making charge\s*$/i, '').slice(0, 60);
        if (name.length < 2) return res.json({ success: true, data: null });
        const and = await scope(req);
        const starts = new RegExp('^' + escapeRe(name), 'i');
        const match = { status: { $nin: HIDDEN_STATUSES }, items: { $elemMatch: { $or: [{ item_name: starts }, { particulars: starts }], net_wt: { $gt: 0 }, making_charge: { $gt: 0 } } } };
        if (req.query.userWise === '1') match.created_by_app_id = String(req.user._id);
        if (and.length) match.$and = and;
        const rows = await Invoices().find(match).sort({ _id: -1 }).limit(1).project({ items: 1, invoice_number: 1, invoice_date: 1 }).toArray();
        const metal = str(req.query.metal).toLowerCase();
        const ln = rows.length ? (rows[0].items || []).find((l) => Number(l.net_wt) > 0 && Number(l.making_charge) > 0 && starts.test(str(l.item_name || l.particulars)) && (!metal || str(l.metal_type).toLowerCase().startsWith(metal.slice(0, 3)))) : null;
        if (!ln) return res.json({ success: true, data: null });
        res.json({ success: true, data: { perGram: Calc.r2(Number(ln.making_charge) / Number(ln.net_wt)), invoiceNumber: str(rows[0].invoice_number), date: str(rows[0].invoice_date) } });
    } catch (e) { next(e); }
};


// POST /api/billing/reconcile : run the cancelled-invoice reconcile now (also runs hourly)
exports.reconcile = async (req, res, next) => {
    try { res.json({ success: true, data: await require('../services/cancelReconcile').reconcileCancelled() }); } catch (e) { next(e); }
};

exports.addPayment = async (req, res, next) => {
    try {
        const b = req.body || {};
        if (!isReqId(b.requestId)) return fail(res, 400, 'Missing request id (please update the app)');
        const amount = Calc.r2(b.amount);
        if (!(amount > 0)) return fail(res, 400, 'Enter an amount more than 0');
        const mode = PAYMENT_MODES.includes(b.mode) ? b.mode : 'Cash';
        const id = oid(req.params.id);
        if (!id) return fail(res, 400, 'Invalid invoice id');

        const inv = await Invoices().findOne({ _id: id });
        if (!inv) return fail(res, 404, 'Invoice not found');
        if (!(await canSee(req, inv))) return fail(res, 403, 'This invoice belongs to another branch');
        if ((inv.payment_history || []).some((p) => p.request_id === b.requestId)) return res.json({ success: true, duplicate: true, data: toView(inv) });
        if (HIDDEN_STATUSES.includes(str(inv.status))) return fail(res, 409, `This invoice is ${inv.status}`);

        const view = toView(inv);
        if (amount > view.dueAmount + 0.001) return fail(res, 409, `Only ₹${view.dueAmount.toFixed(2)} is due on this invoice`);

        const who = me(req);
        const now = new Date();
        const today = Calc.todayIST(now);
        if (mode === 'Cash') {
            // s.269ST: cash from this person today (this and every other invoice) must stay below Rs 2,00,000
            const already = await cashReceivedToday({ customerId: str(inv.customer_id), mobiles: [inv.customer_mobile] }, today);
            if (already + amount >= CASH_LIMIT) return fail(res, 400, cashLimitMessage(already, amount), { cashRoom: cashRoom(already) });
        }
        const time = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Kolkata', hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' }).format(now);
        const entry = {
            amount, payment_mode: mode, transaction_reference: str(b.reference), description: str(b.description) || 'Payment update',
            payment_date: today, payment_time: time, created_at: now, created_by: null, files: [],
            request_id: b.requestId, created_by_name: who.name, created_by_app_id: who.id, source: 'app',
        };
        const num = (f) => ({ $convert: { input: f, to: 'double', onError: 0, onNull: 0 } });

        // ONE atomic update: the still-due check, the new totals and the history entry move together.
        const updated = await Invoices().findOneAndUpdate(
            {
                _id: id, status: { $nin: HIDDEN_STATUSES },
                'payment_history.request_id': { $ne: b.requestId },
                $expr: { $gte: [{ $round: [{ $subtract: [num('$total_payable_amount'), num('$paid_amount')] }, 2] }, amount] },
            },
            [{ $set: {
                paid_amount: { $round: [{ $add: [num('$paid_amount'), amount] }, 2] },
                pay_no: { $add: [{ $convert: { input: '$pay_no', to: 'int', onError: 0, onNull: 0 } }, 1] },
                last_payment_date: today, last_payment_time: time, updated_at: now,
                payment_history: { $concatArrays: [{ $ifNull: ['$payment_history', []] }, [entry]] },
            } }, { $set: {
                due_advance: { $round: [{ $subtract: [num('$paid_amount'), num('$total_payable_amount')] }, 2] },
                // fully paid and already delivered -> delivered (never touches cancelled / void / revised ...)
                status: { $cond: [{ $and: [{ $in: ['$status', ['pending', 'active']] }, { $lte: [{ $abs: { $subtract: [num('$total_payable_amount'), num('$paid_amount')] } }, 0.01] },
                    { $lte: [{ $ifNull: ['$delivery_date', '9999-12-31'] }, today] }] }, 'delivered', '$status'] },
            } }],
            { returnDocument: 'after' });

        if (!updated) {
            const now2 = await Invoices().findOne({ _id: id });
            if (now2 && (now2.payment_history || []).some((p) => p.request_id === b.requestId)) return res.json({ success: true, duplicate: true, data: toView(now2) });
            return fail(res, 409, now2 ? `Only ₹${toView(now2).dueAmount.toFixed(2)} is due on this invoice (someone else may have just received a payment)` : 'Invoice not found');
        }
        res.json({ success: true, data: toView(updated) });
    } catch (e) { next(e); }
};

// ── POST /api/billing/invoices/:id/print — count a print (ORIGINAL first, then DUPLICATE) ──
exports.markPrinted = async (req, res, next) => {
    try {
        const id = oid(req.params.id);
        if (!id) return fail(res, 400, 'Invalid invoice id');
        const inv = await Invoices().findOne({ _id: id }, { projection: { branch_id: 1 } });
        if (!inv) return fail(res, 404, 'Invoice not found');
        if (!(await canSee(req, inv))) return fail(res, 403, 'This invoice belongs to another branch');
        // Same rule as the website: the first print is ORIGINAL, every later one is DUPLICATE.
        const before = await Invoices().findOneAndUpdate({ _id: id }, [{ $set: { print_status: { $add: [{ $convert: { input: '$print_status', to: 'int', onError: 0, onNull: 0 } }, 1] }, last_printed: new Date() } }], { returnDocument: 'before' });
        const prev = before ? Number(before.print_status) || 0 : 0;
        res.json({ success: true, data: { printStatus: prev + 1, printType: prev > 0 ? 'DUPLICATE' : 'ORIGINAL' } });
    } catch (e) { next(e); }
};

// ── reading ──────────────────────────────────────────────────────────────────
// GET /api/billing/invoices?q=&status=all|due|paid&from=&to=&page=&limit=
exports.listInvoices = async (req, res, next) => {
    try {
        const page = Math.max(1, parseInt(req.query.page, 10) || 1);
        const limit = Math.min(50, Math.max(1, parseInt(req.query.limit, 10) || 20));
        const and = await scope(req);
        const q = str(req.query.q);
        if (q) {
            const rx = new RegExp(escapeRegex(q), 'i');
            and.push({ $or: [{ customer_name: rx }, { customer_mobile: rx }, { invoice_number: rx }, { customer_id: rx }, { customer_code: rx }] });
        }
        const num = (f) => ({ $convert: { input: f, to: 'double', onError: 0, onNull: 0 } });
        if (req.query.status === 'due') and.push({ status: { $nin: HIDDEN_STATUSES } }, { $expr: { $gt: [{ $subtract: [num('$total_payable_amount'), num('$paid_amount')] }, 0.005] } });
        if (req.query.status === 'paid') and.push({ status: { $nin: HIDDEN_STATUSES } }, { $expr: { $lte: [{ $subtract: [num('$total_payable_amount'), num('$paid_amount')] }, 0.005] } });
        if (req.query.from) and.push({ invoice_date: { $gte: ymd(req.query.from) } });
        if (req.query.to) and.push({ invoice_date: { $lte: ymd(req.query.to) } });
        const filter = and.length ? { $and: and } : {};
        const [rows, total] = await Promise.all([
            Invoices().find(filter).sort({ _id: -1 }).skip((page - 1) * limit).limit(limit).toArray(),
            Invoices().countDocuments(filter),
        ]);
        res.json({ success: true, data: rows.map(toRow), pagination: { page, limit, total, hasMore: page * limit < total } });
    } catch (e) { next(e); }
};

// GET /api/billing/invoices/:id
exports.getInvoice = async (req, res, next) => {
    try {
        const id = oid(req.params.id);
        if (!id) return fail(res, 400, 'Invalid invoice id');
        const inv = await Invoices().findOne({ _id: id });
        if (!inv) return fail(res, 404, 'Invoice not found');
        if (!(await canSee(req, inv))) return fail(res, 403, 'This invoice belongs to another branch');
        res.json({ success: true, data: toView(inv), seller: await getSeller(), terms: TERMS, declaration: DECLARATION });
    } catch (e) { next(e); }
};

// GET /api/billing/stats?from=&to=  — same figures as the website's summary
exports.stats = async (req, res, next) => {
    try {
        const and = await scope(req);
        and.push({ status: { $nin: HIDDEN_STATUSES } });
        if (req.query.from) and.push({ invoice_date: { $gte: ymd(req.query.from) } });
        if (req.query.to) and.push({ invoice_date: { $lte: ymd(req.query.to) } });
        const d = (f) => ({ $convert: { input: f, to: 'double', onError: 0, onNull: 0 } });
        const [out] = await Invoices().aggregate([{ $match: { $and: and } }, { $facet: {
            totals: [{ $group: { _id: null, invoices: { $sum: 1 }, sales: { $sum: d('$total_payable_amount') }, paid: { $sum: d('$paid_amount') },
                due: { $sum: { $max: [0, { $subtract: [d('$total_payable_amount'), d('$paid_amount')] }] } } } }],
            metals: [{ $unwind: '$items' }, { $group: { _id: { $toLower: { $ifNull: ['$items.metal_type', ''] } }, withGst: { $sum: d('$items.total') }, withoutGst: { $sum: d('$items.taxable_amount') }, weight: { $sum: d('$items.net_wt') } } }],
        } }]).toArray();
        const t = out.totals[0] || { invoices: 0, sales: 0, paid: 0, due: 0 };
        const m = (k) => out.metals.find((x) => x._id === k) || { withGst: 0, withoutGst: 0, weight: 0 };
        const r = Calc.r2;
        res.json({ success: true, data: {
            invoices: t.invoices, sales: r(t.sales), paid: r(t.paid), due: r(t.due),
            gold: { withGst: r(m('gold').withGst), withoutGst: r(m('gold').withoutGst), weight: Calc.r3(m('gold').weight) },
            silver: { withGst: r(m('silver').withGst), withoutGst: r(m('silver').withoutGst), weight: Calc.r3(m('silver').weight) },
        } });
    } catch (e) { next(e); }
};

// GET /api/billing/dues?q=  - who still owes the shop money: customer-wise, biggest first
exports.dues = async (req, res, next) => {
    try {
        const and = await scope(req);
        and.push({ status: { $nin: HIDDEN_STATUSES } });
        const d = (f) => ({ $convert: { input: f, to: 'double', onError: 0, onNull: 0 } });
        const q = str(req.query.q);
        if (q.length >= 2) {
            const rx = new RegExp(escapeRegex(q), 'i');
            and.push({ $or: [{ customer_name: rx }, { customer_mobile: rx }, { invoice_number: rx }] });
        }
        const rows = await Invoices().aggregate([
            { $match: { $and: and } },
            { $addFields: { due: { $round: [{ $subtract: [d('$total_payable_amount'), d('$paid_amount')] }, 2] } } },
            { $match: { due: { $gt: 0.5 } } },
            { $sort: { invoice_date: 1, _id: 1 } },
            { $group: {
                _id: { $cond: [{ $gt: [{ $strLenCP: { $ifNull: ['$customer_mobile', ''] } }, 5] }, '$customer_mobile', { $toLower: { $ifNull: ['$customer_name', ''] } }] },
                name: { $last: '$customer_name' }, mobile: { $last: '$customer_mobile' }, customerId: { $last: '$customer_id' },
                due: { $sum: '$due' }, count: { $sum: 1 }, oldest: { $first: '$invoice_date' }, latest: { $last: '$invoice_date' },
                invoices: { $push: { id: { $toString: '$_id' }, number: '$invoice_number', date: '$invoice_date', due: '$due', total: d('$total_payable_amount') } },
            } },
            { $sort: { due: -1 } },
            { $limit: 200 },
        ]).toArray();
        const list = rows.map((r) => ({ name: str(r.name), mobile: str(r.mobile), customerId: str(r.customerId), due: Calc.r2(r.due), count: r.count, oldest: str(r.oldest), latest: str(r.latest), invoices: (r.invoices || []).slice(-20).reverse() }));
        res.json({ success: true, data: { total: Calc.r2(list.reduce((a, x) => a + x.due, 0)), customers: list.length, rows: list } });
    } catch (e) { next(e); }
};

// GET /api/billing/daybook?from=&to=  (default today) - money in and out by payment mode, with every line (see services/dayBook.js)
exports.dayBook = async (req, res, next) => {
    try {
        const DB = require('../services/dayBook');
        const today = Calc.todayIST();
        const from = ymd(req.query.from) || today, to = ymd(req.query.to) || from;
        const and = await scope(req);
        and.push({ status: { $nin: HIDDEN_STATUSES } });
        const d = (f) => ({ $convert: { input: f, to: 'double', onError: 0, onNull: 0 } });

        const pays = await Invoices().aggregate([
            { $match: { $and: [...and, { 'payment_history.payment_date': { $gte: from, $lte: to } }] } },
            { $unwind: '$payment_history' },
            { $match: { 'payment_history.payment_date': { $gte: from, $lte: to }, 'payment_history.payment_mode': { $nin: ['Old Metal', 'Order Advance'] } } },
            { $project: { number: '$invoice_number', name: '$customer_name', amount: d('$payment_history.amount'), mode: '$payment_history.payment_mode', date: '$payment_history.payment_date', time: '$payment_history.payment_time' } },
        ]).toArray();
        const receipts = pays.filter((p) => p.amount > 0).map((p) => ({ at: `${p.date} ${str(p.time)}`.trim(), title: str(p.name) || 'Walk-in', subtitle: `Invoice ${str(p.number)}`, mode: str(p.mode) || 'Cash', amount: p.amount }));

        const Orders = require('../models/CustomerOrder');
        const ords = await Orders.find({ $or: [{ 'advances.date': { $gte: from, $lte: to } }, { 'refunds.date': { $gte: from, $lte: to } }] }).lean();
        for (const o of ords) {
            for (const a of o.advances || []) if (a.date >= from && a.date <= to && a.amount > 0) receipts.push({ at: `${a.date} ${new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Kolkata', hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' }).format(new Date(a.at))}`, title: str(o.customerName) || 'Customer', subtitle: `Advance for order ${o.number}`, mode: a.mode || 'Cash', amount: a.amount });
        }
        const CreditNote = require('../models/CreditNote');
        const notes = await CreditNote.find({ date: { $gte: from, $lte: to }, status: 'active' }).lean();
        const Expense = require('../models/Expense');
        const exps = await Expense.find({ date: { $gte: from, $lte: to }, status: 'active' }).lean();
        const clock = (t) => (t ? new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Kolkata', hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' }).format(new Date(t)) : '');
        const outs = [
            ...notes.filter((n) => n.refundAmount > 0).map((n) => ({ at: `${n.date} ${clock(n.createdAt)}`.trim(), kind: 'refund', title: `Refund: ${str(n.customerName) || 'Walk-in'}`, subtitle: `${n.number} (invoice ${n.invoiceNumber})`, mode: n.refundMode || 'Cash', amount: n.refundAmount })),
            ...ords.flatMap((o) => (o.refunds || []).filter((r) => r.date >= from && r.date <= to && r.amount > 0).map((r) => ({ at: `${r.date} ${new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Kolkata', hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' }).format(new Date(r.at))}`, kind: 'refund', title: `Advance returned: ${str(o.customerName) || 'Customer'}`, subtitle: `Order ${o.number} cancelled`, mode: r.mode || 'Cash', amount: r.amount }))),
            ...exps.map((e) => ({ at: `${e.date} ${clock(e.createdAt)}`.trim(), kind: 'expense', title: e.category, subtitle: e.note || '', mode: e.mode, amount: e.amount })),
        ];
        const book = DB.build(receipts, outs);

        // what happened in the shop in the period (not all of it is money: a sale on credit, old metal taken, purchases)
        const [sales] = await Invoices().aggregate([
            { $match: { $and: [...and, { invoice_date: { $gte: from, $lte: to } }] } },
            { $group: { _id: null, count: { $sum: 1 }, amount: { $sum: d('$total_payable_amount') }, paid: { $sum: d('$paid_amount') } } },
        ]).toArray();
        const OldMetal = require('../models/OldMetal');
        const start = new Date(`${from}T00:00:00+05:30`), end = new Date(`${to}T23:59:59.999+05:30`);
        const om = await OldMetal.aggregate([{ $match: { status: 'active', date: { $gte: start, $lte: end } } }, { $group: { _id: '$kind', count: { $sum: 1 }, amount: { $sum: '$amount' }, net: { $sum: '$net' } } }]);
        const oldOf = (k) => { const x = om.find((y) => y._id === k) || { count: 0, amount: 0, net: 0 }; return { count: x.count, amount: DB.r2(x.amount), net: Calc.r3(x.net) }; };
        const Purchase = require('../models/Purchase')(require('../config/db').getShopmanageConnection());
        const [pu] = await Purchase.aggregate([{ $match: { isDeleted: false, invoiceDate: { $gte: start, $lte: end } } }, { $group: { _id: null, count: { $sum: 1 }, amount: { $sum: '$totalPayable' } } }]);
        res.json({ success: true, data: {
            from, to, ...book,
            summary: {
                sales: { count: sales ? sales.count : 0, amount: DB.r2(sales ? sales.amount : 0), received: DB.r2(sales ? sales.paid : 0) },
                refunds: { count: notes.length, amount: DB.r2(notes.reduce((a, n) => a + (n.total || 0), 0)) },
                expenses: { count: exps.length, amount: DB.r2(exps.reduce((a, e) => a + e.amount, 0)) },
                purchases: { count: pu ? pu.count : 0, amount: DB.r2(pu ? pu.amount : 0) },
                oldMetal: oldOf('old'), rawMetal: oldOf('raw'),
            },
        } });
    } catch (e) { next(e); }
};
