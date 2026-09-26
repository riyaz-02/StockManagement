/**
 * gstReportsController.js — the GST Summary page.
 *
 * READ-ONLY on the live data: it aggregates `invoices` (sales) and `purchases` (input tax credit) and never writes to
 * them. The only things it writes are the app's own bookkeeping: settings, filed-return records and reminder logs
 * (models/AppGst.js).
 */
'use strict';

const { getLgpAdminConnection, getShopmanageConnection } = require('../config/db');
const { hasPermission } = require('../middleware/auth');
const { getSeller } = require('../services/billingSeller');
const { reportScope, salesFilter, stockFilter, loadRegistrations } = require('../services/registrations');
const G = require('../services/gstReports');
const { GstSettings, GstFiling, GstDocument } = require('../models/AppGst');
const crypto = require('crypto');
const Notification = require('../models/Notification');

const invoices = () => getLgpAdminConnection().db.collection('invoices');
const Purchase = () => require('../models/Purchase')(getShopmanageConnection());
const fail = (res, code, message, extra = {}) => res.status(code).json({ success: false, message, ...extra });
const YMD = /^\d{4}-\d{2}-\d{2}$/;
const str = (v) => (v == null ? '' : String(v).trim());
const me = (req) => ({ id: String(req.user._id), name: req.user.name || req.user.username || '' });
const todayIST = () => G.istYmd(new Date());

// ── settings ─────────────────────────────────────────────────────────────────
const DEFAULTS = { frequency: 'monthly', trackFrom: '', openingItc: { igst: 0, cgst: 0, sgst: 0 }, countItcWithoutGstin: false, b2clThreshold: 100000, reminders: { enabled: true, daysBefore: [7, 3, 1, 0], overdue: true } };

// Settings are kept per registration (GSTIN): key 'main' for the firm's default GSTIN, 'gstin:<GSTIN>' for another one
const settingsKey = (reg) => (!reg || reg.isDefault ? 'main' : `gstin:${reg.gstin}`);
const filingKey = (reg) => (!reg || reg.isDefault ? '' : reg.gstin);
const filingFilter = (reg) => (!reg || reg.isDefault ? { gstin: { $in: ['', null] } } : { gstin: reg.gstin });

async function loadSettings(reg) {
    const key = settingsKey(reg);
    let doc = (await GstSettings.findOne({ key }).lean()) || {};
    if (!doc._id) {
        // first use: follow filings from LAST month on (older years are not this page's business unless the owner asks)
        const t0 = G.parse(todayIST());
        const pm = t0.m === 1 ? { y: t0.y - 1, m: 12 } : { y: t0.y, m: t0.m - 1 };
        await GstSettings.updateOne({ key }, { $setOnInsert: { key, remindersFrom: `${pm.y}-${String(pm.m).padStart(2, '0')}` } }, { upsert: true }).catch(() => {});
        doc = (await GstSettings.findOne({ key }).lean()) || {};
    }
    const seller = { ...(await getSeller()) };
    if (reg) { seller.gstin = reg.gstin; seller.stateCode = reg.stateCode; }
    const stateCode = String(seller.stateCode || String(seller.gstin || '').slice(0, 2) || '19');
    const t = todayIST();
    const fyFrom = `${G.fyStartYear(G.parse(t).y, G.parse(t).m)}-04`;
    const s = {
        ...DEFAULTS, ...doc,
        openingItc: { ...DEFAULTS.openingItc, ...(doc.openingItc || {}) },
        reminders: { ...DEFAULTS.reminders, ...(doc.reminders || {}) },
        stateCode,
    };
    s.trackFrom = /^\d{4}-\d{2}$/.test(s.trackFrom) ? s.trackFrom : fyFrom;
    s.remindersFrom = /^\d{4}-\d{2}$/.test(s.remindersFrom || '') ? s.remindersFrom : s.trackFrom;
    return { settings: s, seller, saved: !!doc._id };
}

// What a report covers. `gstin` picks the registration (default: the firm's own; 'all' = every registration the caller
// may see) and `branch` narrows to one branch. Staff without the every-branch permission only ever see their own branch
// (flagged `partial`). Returns null after answering the request with an error when the choice is not allowed.
async function scopeOf(req, res, { needRegistration = true } = {}) {
    const sc = await reportScope(req, { gstin: req.query.gstin || (req.body && req.body.gstin), branch: req.query.branch });
    if (sc.error) { fail(res, 403, sc.error); return null; }
    if (needRegistration && !sc.registration) { fail(res, 400, 'Choose one GSTIN: returns, credits and reminders are kept per registration'); return null; }
    return sc;
}

async function fetchSales(sc, from, to) {
    const docs = await invoices().find({ ...salesFilter(sc.branchIds), invoice_date: { $gte: from, $lte: to } }).limit(20000).toArray();
    return { docs, partial: sc.partial };
}

// Credit notes (sales returns / refunds) of the period whose tax can still be reduced (s.34(2)): they lower the output tax
// and are reported in GSTR-1 table 9B. Notes made after the deadline of their invoice's year do not reduce it.
async function fetchCreditNotes(sc, from, to) {
    const CreditNote = require('../models/CreditNote');
    const rows = await CreditNote.find({ ...stockFilter(sc.branchIds), date: { $gte: from, $lte: to }, status: 'active' }).lean();
    const sum = { count: 0, taxable: 0, cgst: 0, sgst: 0, igst: 0, total: 0 };
    const counted = rows.filter((n) => n.reducesTax !== false);
    for (const n of counted) { sum.count++; for (const k of ['taxable', 'cgst', 'sgst', 'igst', 'total']) sum[k] += n[k] || 0; }
    for (const k of ['taxable', 'cgst', 'sgst', 'igst', 'total']) sum[k] = G.r2(sum[k]);
    return { ...sum, all: rows, late: rows.length - counted.length };
}
const netOf = (lia, cn) => ({ igst: G.r2(lia.igst - cn.igst), cgst: G.r2(lia.cgst - cn.cgst), sgst: G.r2(lia.sgst - cn.sgst) });

async function fetchPurchases(sc, from, to) {
    const a = new Date(`${from}T00:00:00+05:30`), b = new Date(`${to}T23:59:59.999+05:30`);
    return Purchase().find({ ...stockFilter(sc.branchIds), isDeleted: { $ne: true }, invoiceDate: { $gte: a, $lte: b } }).lean();
}

const validRange = (from, to) => YMD.test(from) && YMD.test(to) && from <= to && G.daysBetween(from, to) <= 366 * 5;

// ── GET /settings ────────────────────────────────────────────────────────────
const regView = (r) => ({ gstin: r.gstin, name: r.name, stateCode: r.stateCode, isDefault: r.isDefault, branches: r.branches });

exports.getSettings = async (req, res, next) => {
    try {
        const sc = await scopeOf(req, res, { needRegistration: false });
        if (!sc) return;
        const { settings, seller } = await loadSettings(sc.registration || (sc.registrations.find((r) => r.isDefault) || sc.registrations[0]));
        res.json({ success: true, data: { settings, seller: { firmName: seller.firmName, gstin: seller.gstin }, registrations: sc.registrations.map(regView), qrmpDay3b: G.qrmpDay3b(settings.stateCode), today: todayIST() } });
    } catch (e) { next(e); }
};

// ── PUT /settings ────────────────────────────────────────────────────────────
exports.updateSettings = async (req, res, next) => {
    try {
        const sc = await scopeOf(req, res);
        if (!sc) return;
        const reg = sc.registration;
        const b = req.body || {};
        const set = {};
        if (b.frequency !== undefined) {
            if (!['monthly', 'quarterly'].includes(b.frequency)) return fail(res, 400, 'Frequency must be monthly or quarterly');
            set.frequency = b.frequency;
        }
        if (b.trackFrom !== undefined) {
            if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(str(b.trackFrom))) return fail(res, 400, 'Track ITC from: use a month like 2026-04');
            set.trackFrom = str(b.trackFrom);
        }
        if (b.remindersFrom !== undefined) {
            if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(str(b.remindersFrom))) return fail(res, 400, 'Follow filings from: use a month like 2026-08');
            set.remindersFrom = str(b.remindersFrom);
        }
        if (b.openingItc !== undefined) {
            for (const k of ['igst', 'cgst', 'sgst']) {
                const v = Number(b.openingItc && b.openingItc[k]);
                if (!(v >= 0) || v > 1e9) return fail(res, 400, `Opening ${k.toUpperCase()} credit must be 0 or more`);
                set[`openingItc.${k}`] = G.r2(v);
            }
        }
        if (b.countItcWithoutGstin !== undefined) set.countItcWithoutGstin = b.countItcWithoutGstin === true;
        if (b.b2clThreshold !== undefined) {
            const v = Number(b.b2clThreshold);
            if (!(v >= 0) || v > 1e9) return fail(res, 400, 'Large-invoice limit must be 0 or more');
            set.b2clThreshold = v;
        }
        if (b.reminders !== undefined) {
            const r = b.reminders || {};
            if (r.enabled !== undefined) set['reminders.enabled'] = r.enabled === true;
            if (r.overdue !== undefined) set['reminders.overdue'] = r.overdue === true;
            if (r.daysBefore !== undefined) {
                const list = [...new Set((Array.isArray(r.daysBefore) ? r.daysBefore : []).map(Number))];
                if (list.length < 1 || list.length > 6 || list.some((d) => !Number.isInteger(d) || d < 0 || d > 30)) return fail(res, 400, 'Remind me 0 to 30 days before (up to 6 reminders)');
                set['reminders.daysBefore'] = list.sort((x, y) => y - x);
            }
        }
        if (!Object.keys(set).length) return fail(res, 400, 'Nothing to change');
        const w = me(req);
        const key = settingsKey(reg);
        await GstSettings.updateOne({ key }, { $set: { ...set, updatedBy: w.id, updatedByName: w.name }, $setOnInsert: { key } }, { upsert: true });
        const { settings } = await loadSettings(reg);
        res.json({ success: true, data: { settings } });
    } catch (e) { next(e); }
};

// ── shared filter parsing ────────────────────────────────────────────────────
function opts(req, settings) {
    const q = req.query;
    return {
        from: str(q.from), to: str(q.to), group: str(q.group) || 'month', metal: str(q.metal), taxType: ['intra', 'inter'].includes(str(q.taxType)) ? str(q.taxType) : '',
        min: q.min, max: q.max, q: str(q.q).slice(0, 60), branch: str(q.branch), b2clThreshold: settings.b2clThreshold,
    };
}

// ── GET /summary ─────────────────────────────────────────────────────────────
exports.summary = async (req, res, next) => {
    try {
        const sc = await scopeOf(req, res, { needRegistration: false });
        if (!sc) return;
        const { settings } = await loadSettings(sc.registration);
        const o = opts(req, settings);
        if (!validRange(o.from, o.to)) return fail(res, 400, 'Give a valid from and to date (YYYY-MM-DD), at most 5 years apart');
        const { docs, partial } = await fetchSales(sc, o.from, o.to);
        const s = G.summarise(docs, o);
        const { rows, ...rest } = s;
        // the previous period of the same length, for the "vs before" figures
        const days = G.daysBetween(o.from, o.to) + 1;
        const pTo = new Date(Date.UTC(G.parse(o.from).y, G.parse(o.from).m - 1, G.parse(o.from).d - 1)), pFrom = new Date(pTo.getTime() - (days - 1) * 86400000);
        const ymd = (d) => `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
        const prevDocs = (await fetchSales(sc, ymd(pFrom), ymd(pTo))).docs;
        const prev = G.summarise(prevDocs, { ...o, from: ymd(pFrom), to: ymd(pTo) }).totals;
        res.json({ success: true, data: { ...rest, count: rows.length, partial, previous: { from: ymd(pFrom), to: ymd(pTo), invoices: prev.invoices, taxable: prev.taxable, tax: prev.tax, invoiceValue: prev.invoiceValue, weight: prev.weight, making: prev.making } } });
    } catch (e) { next(e); }
};

// ── GET /register — the sortable, filterable invoice list ───────────────────
exports.register = async (req, res, next) => {
    try {
        const sc = await scopeOf(req, res, { needRegistration: false });
        if (!sc) return;
        const { settings } = await loadSettings(sc.registration);
        const o = opts(req, settings);
        if (!validRange(o.from, o.to)) return fail(res, 400, 'Give a valid from and to date (YYYY-MM-DD)');
        const { docs, partial } = await fetchSales(sc, o.from, o.to);
        const s = G.summarise(docs, o);
        const page = G.registerPage(s.rows, { sort: str(req.query.sort), dir: str(req.query.dir), page: req.query.page, limit: req.query.limit });
        res.json({ success: true, data: { ...page, partial, totals: { taxable: s.totals.taxable, tax: s.totals.tax, invoiceValue: s.totals.invoiceValue, weight: s.totals.weight, making: s.totals.making } } });
    } catch (e) { next(e); }
};

// ── ITC roll-forward up to (and including) a period ─────────────────────────
async function buildLedger(sc, settings, uptoKey) {
    const freq = settings.frequency;
    const trackStart = `${settings.trackFrom}-01`;
    const upto = G.periodRange(uptoKey);
    if (!upto) return { rows: [], periods: [] };
    const keys = G.listPeriods(freq, trackStart, upto.to).filter((k) => G.periodRange(k).to >= trackStart);
    const range = { from: G.periodRange(keys[0]).from, to: upto.to };
    if (range.from > range.to) return { rows: [], periods: [] };
    const [{ docs, partial }, purchases] = await Promise.all([fetchSales(sc, range.from, range.to), fetchPurchases(sc, range.from, range.to)]);
    const periods = await Promise.all(keys.map(async (k) => {
        const p = G.periodRange(k);
        const s = G.summarise(docs, { from: p.from, to: p.to });
        const itc = G.purchaseItc(purchases, p.from, p.to, { countWithoutGstin: settings.countItcWithoutGstin });
        const cn = await fetchCreditNotes(sc, p.from, p.to);
        return { key: k, label: p.label, from: p.from, to: p.to, liability: netOf(G.liabilityOf(s), cn), itc: itc.claim, itcInfo: itc, sales: s.totals, creditNotes: { count: cn.count, tax: G.r2(cn.cgst + cn.sgst + cn.igst) } };
    }));
    const rows = G.itcLedger(periods, settings.openingItc).map((r, i) => ({ ...r, label: periods[i].label, from: periods[i].from, to: periods[i].to, itcInfo: periods[i].itcInfo }));
    return { rows, periods, partial };
}

// ── GET /returns?period=2026-08 ─────────────────────────────────────────────
exports.returns = async (req, res, next) => {
    try {
        const sc = await scopeOf(req, res);
        if (!sc) return;
        const reg = sc.registration;
        const { settings } = await loadSettings(reg);
        const key = str(req.query.period);
        const p = G.periodRange(key);
        if (!p) return fail(res, 400, 'Period must look like 2026-08 or 2026-Q2');
        const { docs, partial } = await fetchSales(sc, p.from, p.to);
        const s = G.summarise(docs, { from: p.from, to: p.to, group: 'day', b2clThreshold: settings.b2clThreshold });
        const ledger = await buildLedger(sc, settings, key);
        const cnPeriod = await fetchCreditNotes(sc, p.from, p.to);
        const row = ledger.rows.find((r) => r.key === key) || null;
        const kind = p.kind === 'quarter' ? 'quarterly' : 'monthly';
        const ctx = { frequency: kind, stateCode: settings.stateCode };
        const months = p.months.map((m) => `${m.y}-${String(m.m).padStart(2, '0')}`);
        const filings = await GstFiling.find({ ...filingFilter(reg), period: { $in: [key, ...months] } }).lean();
        const ITC = row ? row.itcInfo : { claim: G.zeroT(), atRisk: G.zeroT(), count: 0, riskCount: 0, purchaseValue: 0 };
        res.json({
            success: true,
            data: {
                period: { key, kind: p.kind, label: p.label, from: p.from, to: p.to },
                registration: regView(reg), partial,
                due: { 'GSTR-1': G.dueDate('GSTR-1', key, ctx), 'GSTR-3B': G.dueDate('GSTR-3B', key, ctx) },
                gstr1: {
                    ...s.gstr1,
                    totals: { invoices: s.totals.invoices, taxable: s.totals.taxable, cgst: s.totals.cgst, sgst: s.totals.sgst, igst: s.totals.igst, invoiceValue: s.totals.invoiceValue },
                },
                gstr3b: {
                    outward: { taxable: s.totals.taxable, igst: s.totals.igst, cgst: s.totals.cgst, sgst: s.totals.sgst },
                    interstateToUnregistered: s.byPlace.filter((x) => x.inter).map((x) => ({ place: x.place, taxable: x.taxable, igst: x.igst })),
                    itc: { claim: ITC.claim, atRisk: ITC.atRisk, purchases: ITC.count, riskPurchases: ITC.riskCount, purchaseValue: ITC.purchaseValue },
                    liability: netOf(G.liabilityOf(s), cnPeriod),
                    liabilityBeforeCreditNotes: G.liabilityOf(s),
                    ledger: row,
                },
                creditNotes: { count: cnPeriod.count, late: cnPeriod.late, taxable: cnPeriod.taxable, cgst: cnPeriod.cgst, sgst: cnPeriod.sgst, igst: cnPeriod.igst, total: cnPeriod.total, list: cnPeriod.all.map((n) => ({ number: n.number, date: n.date, invoiceNumber: n.invoiceNumber, invoiceDate: n.invoiceDate, customer: n.customerName, taxable: n.taxable, cgst: n.cgst, sgst: n.sgst, igst: n.igst, total: n.total, reason: n.reason, reducesTax: n.reducesTax !== false })) },
                notes: s.notes,
                checks: G.complianceChecks(docs, p.from, p.to),
                filings,
            },
        });
    } catch (e) { next(e); }
};

// ── GET /itc — the roll-forward table + what is left now ────────────────────
exports.itc = async (req, res, next) => {
    try {
        const sc = await scopeOf(req, res);
        if (!sc) return;
        const { settings } = await loadSettings(sc.registration);
        const cur = G.periodKey(settings.frequency, todayIST());
        const ledger = await buildLedger(sc, settings, cur);
        const last = ledger.rows[ledger.rows.length - 1] || null;
        const prev = ledger.rows.length > 1 ? ledger.rows[ledger.rows.length - 2] : null;
        // remaining credit = what the last finished period carried forward + this period's purchases so far
        const carried = prev ? prev.closing : settings.openingItc;
        res.json({
            success: true,
            data: {
                frequency: settings.frequency, trackFrom: settings.trackFrom, opening: settings.openingItc, current: last,
                carriedForward: carried, carriedTotal: G.totalOf(carried),
                availableNow: last ? last.available : settings.openingItc, availableNowTotal: G.totalOf(last ? last.available : settings.openingItc),
                rows: ledger.rows, partial: !!ledger.partial,
            },
        });
    } catch (e) { next(e); }
};

// ── GET /calendar — due dates, status, alerts ───────────────────────────────
exports.calendar = async (req, res, next) => {
    try {
        const sc = await scopeOf(req, res);
        if (!sc) return;
        const { settings } = await loadSettings(sc.registration);
        const filings = await GstFiling.find(filingFilter(sc.registration)).lean();
        const today = todayIST();
        const list = G.statusList(settings, filings, today, { back: 240, ahead: 270 });
        const recent = await Notification.find({ source: 'gst-due' }).sort({ createdAt: -1 }).limit(10).lean();
        res.json({
            success: true,
            data: {
                today, frequency: settings.frequency, qrmpDay3b: G.qrmpDay3b(settings.stateCode),
                items: list,
                alerts: G.alerts(settings, filings, today),
                recentReminders: recent.map((n) => ({ title: n.title, body: n.body, at: n.createdAt })),
            },
        });
    } catch (e) { next(e); }
};

// ── filings ──────────────────────────────────────────────────────────────────
const periodOk = (type, period) => (type === 'GSTR-9' ? /^FY\d{4}$/.test(period) : type === 'PMT-06' ? /^\d{4}-(0[1-9]|1[0-2])$/.test(period) : !!G.periodRange(period));
const money = (v) => { const n = Number(v); return Number.isFinite(n) && n >= 0 && n < 1e10 ? G.r2(n) : null; };

function readFiling(b, res) {
    const type = str(b.returnType), period = str(b.period), filedOn = str(b.filedOn);
    if (!G.RETURN_TYPES.includes(type)) { fail(res, 400, 'Return type must be one of ' + G.RETURN_TYPES.join(', ')); return null; }
    if (!periodOk(type, period)) { fail(res, 400, 'That period does not fit this return'); return null; }
    if (!YMD.test(filedOn)) { fail(res, 400, 'Enter the date it was filed'); return null; }
    if (filedOn > todayIST()) { fail(res, 400, 'Filing date cannot be in the future'); return null; }
    const out = { returnType: type, period, filedOn, arn: str(b.arn).toUpperCase().slice(0, 30), nil: b.nil === true, note: str(b.note).slice(0, 300) };
    for (const k of ['taxLiability', 'itcUsed', 'cashPaid', 'lateFee', 'interest']) {
        const v = b[k] === undefined || b[k] === '' || b[k] === null ? 0 : money(b[k]);
        if (v === null) { fail(res, 400, `${k} must be an amount of 0 or more`); return null; }
        out[k] = v;
    }
    return out;
}

exports.listFilings = async (req, res, next) => {
    try {
        const sc = await scopeOf(req, res);
        if (!sc) return;
        const f = { ...filingFilter(sc.registration) };
        if (str(req.query.type)) f.returnType = str(req.query.type);
        if (str(req.query.period)) f.period = str(req.query.period);
        const rows = await GstFiling.find(f).sort({ filedOn: -1, createdAt: -1 }).limit(500).lean();
        res.json({ success: true, data: rows });
    } catch (e) { next(e); }
};

exports.createFiling = async (req, res, next) => {
    try {
        const sc = await scopeOf(req, res);
        if (!sc) return;
        const f = readFiling(req.body || {}, res);
        if (!f) return;
        const w = me(req);
        try {
            const doc = await GstFiling.create({ ...f, gstin: filingKey(sc.registration), createdBy: w.id, createdByName: w.name });
            res.status(201).json({ success: true, data: doc });
        } catch (e) {
            if (e.code === 11000) return fail(res, 409, `${f.returnType} for this period is already recorded. Edit it instead.`);
            throw e;
        }
    } catch (e) { next(e); }
};

exports.updateFiling = async (req, res, next) => {
    try {
        const cur = await GstFiling.findById(req.params.id).lean().catch(() => null);
        if (!cur) return fail(res, 404, 'Filing record not found');
        const sc = await reportScope(req, { gstin: cur.gstin || '' });
        if (sc.error) return fail(res, 403, sc.error);
        const f = readFiling({ ...cur, ...(req.body || {}), returnType: cur.returnType, period: cur.period }, res);
        if (!f) return;
        const w = me(req);
        const doc = await GstFiling.findByIdAndUpdate(req.params.id, { $set: { ...f, updatedBy: w.id, updatedByName: w.name } }, { new: true });
        res.json({ success: true, data: doc });
    } catch (e) { next(e); }
};

// ── GET /export?type=register|hsn|b2cs|summary&from&to  (CSV for the CA) ────
const csvCell = (v) => { const s = v == null ? '' : String(v); return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
const csv = (head, rows) => [head.map(csvCell).join(','), ...rows.map((r) => r.map(csvCell).join(','))].join('\n');

exports.exportCsv = async (req, res, next) => {
    try {
        const sc = await scopeOf(req, res, { needRegistration: false });
        if (!sc) return;
        const { settings } = await loadSettings(sc.registration);
        const o = opts(req, settings);
        if (!validRange(o.from, o.to)) return fail(res, 400, 'Give a valid from and to date');
        const { docs } = await fetchSales(sc, o.from, o.to);
        const s = G.summarise(docs, o);
        const type = str(req.query.type) || 'register';
        let name, body;
        if (type === 'hsn') {
            name = 'hsn-summary'; body = csv(['HSN', 'UQC', 'Total quantity (g)', 'Total value', 'Taxable value', 'IGST', 'CGST', 'SGST'], s.gstr1.hsn.map((h) => [h.hsn, h.uqc, h.qty, h.value, h.taxable, h.igst, h.cgst, h.sgst]));
        } else if (type === 'b2cs') {
            name = 'b2cs'; body = csv(['Place of supply', 'Rate %', 'Taxable value', 'IGST', 'CGST', 'SGST'], s.gstr1.b2cs.map((x) => [x.place, x.rate, x.taxable, x.igst, x.cgst, x.sgst]));
        } else if (type === 'b2cl') {
            name = 'b2cl'; body = csv(['Invoice no', 'Date', 'Place of supply', 'Invoice value', 'Taxable value', 'IGST'], s.gstr1.b2cl.map((x) => [x.number, x.date, x.place, x.value, x.taxable, x.igst]));
        } else if (type === 'metal') {
            name = 'metal-summary'; body = csv(['Metal', 'Pieces', 'Weight (g)', 'Metal value', 'Making charge', 'Taxable', 'GST', 'Total'], s.byMetal.map((m) => [m.metal, m.pieces, m.weight, m.metalValue, m.making, m.taxable, m.tax, m.total]));
        } else {
            name = 'invoice-register';
            const sorted = s.rows.slice().sort((x, y) => x.date.localeCompare(y.date) || String(x.invoiceNumber).localeCompare(String(y.invoiceNumber), undefined, { numeric: true }));
            body = csv(['Invoice no', 'Date', 'Customer', 'Mobile', 'Place of supply', 'Tax type', 'Metals', 'Weight (g)', 'Making', 'Taxable', 'CGST', 'SGST', 'IGST', 'Invoice value', 'Status'],
                sorted.map((r) => [r.invoiceNumber, r.date, r.customerName, r.customerMobile, r.place, r.taxType, r.metals, r.weight, r.making, r.taxable, r.cgst, r.sgst, r.igst, r.value, r.status]));
        }
        res.json({ success: true, data: { filename: `${name}_${o.from}_to_${o.to}.csv`, csv: body } });
    } catch (e) { next(e); }
};

// ── GET /monthly-record?year=&month= — the month's "GST Invoice Record" (data for the PDF) ─────────────
exports.monthlyRecord = async (req, res, next) => {
    try {
        const year = parseInt(req.query.year, 10), month = parseInt(req.query.month, 10);
        if (!(month >= 1 && month <= 12) || !(year >= 2017 && year <= 2100)) return fail(res, 400, 'Choose a valid month and year');
        const t = G.parse(todayIST());
        if (year > t.y || (year === t.y && month > t.m)) return fail(res, 400, 'Cannot generate a record for a future month');
        const sc = await scopeOf(req, res);
        if (!sc) return;
        const from = G.fmt(year, month, 1), to = G.fmt(year, month, new Date(Date.UTC(year, month, 0)).getUTCDate());
        const { docs, partial } = await fetchSales(sc, from, to);
        const rec = G.monthlyRecord(docs, year, month);
        const label = `${rec.period.monthName} ${year}`;
        if (!rec.invoices.length) return fail(res, 404, `No invoices found for ${label}`);

        const seller = { ...(await getSeller()) };
        if (sc.registration) seller.gstin = sc.registration.gstin;
        const scopeLabel = sc.registration ? (sc.registration.branches.length > 1 || !sc.registration.isDefault ? sc.registration.branches.map((b) => b.name).join(', ') : '') : 'All registrations';
        const now = new Date();
        const documentId = 'GST-' + crypto.createHash('md5').update(`${label}${now.toISOString()}${req.user._id}`).digest('hex').slice(0, 6).toUpperCase();
        const ist = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Kolkata', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false }).format(now).replace(/\//g, '-').replace(',', '');
        const w = me(req);
        await GstDocument.create({
            documentId, documentName: `GST_Invoice_Record_${rec.period.monthName}_${year}.pdf`, year, month, totalInvoices: rec.tracking.total, validInvoices: rec.tracking.valid,
            totalAmount: rec.totals.amount, totalGst: rec.totals.gst, taxableAmount: rec.totals.taxable, partial, generatedBy: w.id, generatedByName: w.name, branchId: (req.branchScope && req.branchScope.branchId) || 'main', gstin: seller.gstin, branchFilter: str(req.query.branch),
        }).catch(() => {});        // the audit row must never block the report
        res.json({
            success: true,
            data: {
                documentId, generatedAt: `${ist} IST`, partial,
                seller: { firmName: seller.firmName, gstin: seller.gstin, address: seller.address, phone: seller.phone },
                scope: { registration: sc.registration ? regView(sc.registration) : null, branch: str(req.query.branch), label: scopeLabel },
                ...rec,
            },
        });
    } catch (e) { next(e); }
};

exports._loadSettings = loadSettings;
exports._filingFilter = filingFilter;
