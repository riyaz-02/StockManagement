/**
 * gstFilings.js — the record of GST returns that were filed. ONE collection, the website's `gst_data`.
 *
 * `gst_data` holds one document per financial-year quarter, in the website's own shape:
 *     financial_year (the year the FY starts: 2025 = Apr 2025 - Mar 2026), quarter (1 = Apr-Jun ... 4 = Jan-Mar),
 *     gstr1_filed / gstr1_filed_date, gstr3b_filed / gstr3b_filed_date, taxable_supplies, gst_paid, itc_amount, remarks ...
 * Everything the app records beyond that sits in the SAME document, as `filings: [...]` (ignored by the PHP site): the
 * ARN, the amounts, PMT-06 and GSTR-9, monthly returns and the returns of another GSTIN. So there is exactly one list of
 * filed returns, whoever filed them and from where:
 *   - an old website record (flags only) shows up as a GSTR-1 / GSTR-3B filing for its quarter (`source: 'website'`);
 *   - a return filed in the app is stored in `filings` AND the website's flags for that quarter are kept in step, so the
 *     old site shows it as filed too. The flags are only ever set, never cleared, by the app.
 *
 * A filing as the app sees it: { _id, gstin ('' = the default registration), returnType, period ('2026-08' | '2026-Q2' | 'FY2025'),
 *   filedOn, arn, taxLiability, itcUsed, cashPaid, lateFee, interest, nil, note, createdBy(Name), updatedBy(Name), source }.
 *
 * Every function takes an optional `{ db }` (a raw MongoDB Db) so the sample-data script can use it without the server.
 */
'use strict';

const mongoose = require('mongoose');
const G = require('./gstReports');
const { getConnection } = require('../config/db');

const COLLECTION = 'gst_data';
const col = (o) => ((o && o.db) || getConnection().db).collection(COLLECTION);
const oid = (v) => (/^[0-9a-f]{24}$/i.test(String(v || '')) ? new mongoose.Types.ObjectId(String(v)) : undefined);
const r2 = (n) => Math.round((Number(n) + Number.EPSILON) * 100) / 100;
const num = (v) => (Number.isFinite(Number(v)) ? Number(v) : 0);
const FIELDS = ['returnType', 'period', 'filedOn', 'arn', 'taxLiability', 'itcUsed', 'cashPaid', 'lateFee', 'interest', 'nil', 'note'];

/** Which website document (FY start year + quarter) a return period lives in. */
function docKey(period) {
    let m = /^(\d{4})-Q([1-4])$/.exec(period);
    if (m) return { financial_year: Number(m[1]), quarter: Number(m[2]) };
    m = /^(\d{4})-(\d{2})$/.exec(period);
    if (m) {
        const y = Number(m[1]), mo = Number(m[2]);
        return { financial_year: mo >= 4 ? y : y - 1, quarter: Math.floor(((mo - 4 + 12) % 12) / 3) + 1 };
    }
    m = /^FY(\d{4})$/.exec(period);
    if (m) return { financial_year: Number(m[1]), quarter: 4 };
    return null;
}
const quarterPeriod = (d) => `${d.financial_year}-Q${d.quarter}`;

const clean = (e) => ({
    _id: String(e.id), gstin: e.gstin || '', returnType: e.returnType, period: e.period, filedOn: e.filedOn || '', arn: e.arn || '',
    taxLiability: num(e.taxLiability), itcUsed: num(e.itcUsed), cashPaid: num(e.cashPaid), lateFee: num(e.lateFee), interest: num(e.interest),
    nil: !!e.nil, note: e.note || '', createdBy: e.createdBy, createdByName: e.createdByName, updatedBy: e.updatedBy, updatedByName: e.updatedByName,
    createdAt: e.createdAt, updatedAt: e.updatedAt, source: 'app',
});

/** The filings of one document: the app's own, plus the website's flags for GSTR-1 / GSTR-3B that have no record of their own. */
function filingsOf(d) {
    const out = (d.filings || []).map(clean);
    const qp = quarterPeriod(d);
    for (const [type, flag, dateField] of [['GSTR-1', 'gstr1_filed', 'gstr1_filed_date'], ['GSTR-3B', 'gstr3b_filed', 'gstr3b_filed_date']]) {
        if (d[flag] !== true && d[flag] !== 'true') continue;
        const covered = out.some((f) => f.gstin === '' && f.returnType === type && (f.period === qp || (G.periodRange(f.period) || {}).kind === 'month'));
        if (covered) continue;
        const paid = type === 'GSTR-3B' ? num(d.gst_paid) : 0, itc = type === 'GSTR-3B' ? num(d.itc_amount) : 0;
        out.push({
            _id: `site:${d._id}:${type}`, gstin: '', returnType: type, period: qp, filedOn: String(d[dateField] || '').slice(0, 10), arn: '',
            taxLiability: paid, itcUsed: itc, cashPaid: type === 'GSTR-3B' ? r2(Math.max(0, paid - itc)) : 0,
            lateFee: 0, interest: 0, nil: false, note: type === 'GSTR-3B' ? String(d.remarks || '') : '',
            createdAt: d.created_at, updatedAt: d.updated_at, source: 'website',
        });
    }
    return out;
}

/**
 * list({ gstin, type, period, periods, db }): gstin '' = the default registration, 'XX..' = that GSTIN, undefined = every one.
 * Newest filing first.
 */
async function list(o = {}) {
    const wanted = o.periods || (o.period ? [o.period] : null);
    let q = {};
    if (wanted) {
        const keys = [...new Set(wanted.map(docKey).filter(Boolean).map((k) => `${k.financial_year}-${k.quarter}`))];
        if (!keys.length) return [];
        q = { $or: keys.map((k) => { const [fy, qq] = k.split('-').map(Number); return { financial_year: fy, quarter: qq }; }) };
    }
    const docs = await col(o).find(q).limit(400).toArray();
    let rows = docs.flatMap(filingsOf);
    if (o.gstin !== undefined) rows = rows.filter((f) => (f.gstin || '') === (o.gstin || ''));
    if (o.type) rows = rows.filter((f) => f.returnType === o.type);
    if (wanted) rows = rows.filter((f) => wanted.includes(f.period));
    return rows.sort((a, b) => (b.filedOn || '').localeCompare(a.filedOn || ''));
}

async function findOne(o) { return (await list(o))[0] || null; }

/** One filing by id (an app record's id, or "site:<doc>:<type>" for a record the website made). */
async function get(id, o) {
    id = String(id || '');
    const site = /^site:([0-9a-f]{24}):(GSTR-1|GSTR-3B)$/i.exec(id);
    const d = site ? await col(o).findOne({ _id: new mongoose.Types.ObjectId(site[1]) }) : await col(o).findOne({ 'filings.id': id });
    return d ? filingsOf(d).find((f) => f._id === id) || null : null;
}

/** Keep the website's own flags for the quarter in step with what is recorded (only ever sets them). */
async function syncFlags(fy, q, o) {
    const d = await col(o).findOne({ financial_year: fy, quarter: q });
    if (!d) return;
    const mine = (d.filings || []).filter((f) => !f.gstin);
    const set = {};
    for (const [type, flag, dateField] of [['GSTR-1', 'gstr1_filed', 'gstr1_filed_date'], ['GSTR-3B', 'gstr3b_filed', 'gstr3b_filed_date']]) {
        const rows = mine.filter((f) => f.returnType === type && f.filedOn);
        const quarterly = rows.find((f) => f.period === `${fy}-Q${q}`);
        const monthly = rows.filter((f) => /^\d{4}-\d{2}$/.test(f.period));
        const done = quarterly ? quarterly.filedOn : (new Set(monthly.map((f) => f.period)).size >= 3 ? monthly.map((f) => f.filedOn).sort().pop() : '');
        if (!done) continue;
        set[flag] = true;
        set[dateField] = done;
        if (type === 'GSTR-3B') {
            const lia = rows.reduce((s, f) => s + num(f.taxLiability), 0), itc = rows.reduce((s, f) => s + num(f.itcUsed), 0);
            if (lia > 0) set.gst_paid = r2(lia);
            if (itc > 0) set.itc_amount = r2(itc);
        }
    }
    if (Object.keys(set).length) await col(o).updateOne({ _id: d._id }, { $set: { ...set, updated_at: new Date() } });
}

/** Record a filed return. Throws { code: 'DUPLICATE' } when that return for that period (and GSTIN) is already recorded. */
async function create(f, o = {}) {
    const k = docKey(f.period);
    if (!k) throw Object.assign(new Error('That period does not fit this return'), { code: 'BAD_PERIOD' });
    if (!o.__skipDup && await findOne({ gstin: f.gstin || '', type: f.returnType, period: f.period, db: o.db })) throw Object.assign(new Error('Already recorded'), { code: 'DUPLICATE' });
    const now = new Date();
    const entry = { id: new mongoose.Types.ObjectId().toString(), gstin: f.gstin || '', createdAt: now, updatedAt: now, createdBy: f.createdBy, createdByName: f.createdByName };
    for (const name of FIELDS) if (f[name] !== undefined) entry[name] = f[name];
    const by = oid(f.createdBy);
    await col(o).updateOne(
        { financial_year: k.financial_year, quarter: k.quarter },
        {
            $push: { filings: entry },
            $set: { updated_at: now, ...(by ? { updated_by: by } : {}) },
            $setOnInsert: { gstr1_filed: false, gstr3b_filed: false, created_at: now, ...(by ? { created_by: by } : {}), ...(o.extra || {}) },
        },
        { upsert: true }
    );
    await syncFlags(k.financial_year, k.quarter, o);
    return clean(entry);
}

/** Change a filing (the app's record; a record the website made becomes the app's own record with the changes). */
async function update(id, patch, o = {}) {
    const cur = await get(id, o);
    if (!cur) return null;
    const k = docKey(cur.period);
    const now = new Date();
    const changes = {};
    for (const name of FIELDS) if (name !== 'returnType' && name !== 'period' && patch[name] !== undefined) changes[name] = patch[name];
    if (cur.source === 'website') {
        return create({ ...cur, ...changes, createdBy: patch.updatedBy, createdByName: patch.updatedByName }, { ...o, __skipDup: true });
    }
    const $set = { updated_at: now };
    for (const [name, v] of Object.entries({ ...changes, updatedBy: patch.updatedBy, updatedByName: patch.updatedByName, updatedAt: now })) $set[`filings.$[e].${name}`] = v;
    await col(o).updateOne({ financial_year: k.financial_year, quarter: k.quarter }, { $set }, { arrayFilters: [{ 'e.id': cur._id }] });
    await syncFlags(k.financial_year, k.quarter, o);
    return get(id, o);
}

module.exports = { list, findOne, get, create, update, docKey, COLLECTION };
