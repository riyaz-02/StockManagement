/**
 * wastage.js — metal wastage reports. ONE collection, the website's `wastage_reports`, in its own shape:
 *     wastage_date 'YYYY-MM-DD', metal_type 'Gold' | 'Silver', wastage_amount (text, grams), category, reason, remarks,
 *     reported_by (user id), approved_by (user id), notes, status pending | approved | rejected,
 *     created_at / created_ist / created_by, updated_at / updated_ist / updated_by, approved_at, attachment
 * The app adds admin_comments, rejected_by / rejected_at, reported_by_name / approved_by_name beside them (the PHP site ignores them).
 *
 * Rules (what makes it safe):
 *  - a report is always created pending; only an approval counts in the metal balance;
 *  - the person who reported it cannot approve it (admin / owner can: they are the final authority);
 *  - approve / reject act only on a pending report and only once (a double tap or two people at once cannot do it twice);
 *  - an approved report is final; only admin / owner can reverse it (reject with a comment), and that is audited.
 */
'use strict';

const { ObjectId } = require('mongodb');
const { getConnection } = require('../config/db');
const { ymdIST, istStamp } = require('../models/Purchase');

const col = () => getConnection().db.collection('wastage_reports');
const CATEGORIES = ['Manufacturing', 'Polishing', 'Stone Setting', 'Other'];
const METALS = { gold: 'Gold', silver: 'Silver' };
const MAX_GRAMS = 100000;
const oid = (v) => (/^[0-9a-f]{24}$/i.test(String(v || '')) ? new ObjectId(String(v)) : null);
const str = (v, n = 500) => (v == null ? '' : String(v).trim().slice(0, n));
const isBoss = (user) => ['admin', 'owner'].includes(String((user && user.role) || '').toLowerCase());
const fail = (status, message) => Object.assign(new Error(message), { status });

async function names(ids) {
    const list = [...new Set(ids.filter((x) => oid(x)))];
    if (!list.length) return {};
    const rows = await getConnection().db.collection('users').find({ _id: { $in: list.map((x) => new ObjectId(x)) } }, { projection: { full_name: 1, username: 1 } }).toArray();
    return Object.fromEntries(rows.map((u) => [String(u._id), u.full_name || u.username || '']));
}

function toApp(d, who = {}) {
    const att = d.attachment && typeof d.attachment === 'object' ? d.attachment : null;
    return {
        _id: String(d._id),
        date: String(d.wastage_date || '').slice(0, 10),
        metal: String(d.metal_type || '').toLowerCase(),
        amount: Number(d.wastage_amount) || 0,
        category: d.category || '',
        reason: d.reason || '',
        remarks: d.remarks || '',
        notes: d.notes || '',
        status: d.status || 'pending',
        reportedBy: { id: d.reported_by ? String(d.reported_by) : '', name: d.reported_by_name || who[String(d.reported_by)] || '' },
        approvedBy: d.approved_by ? { id: String(d.approved_by), name: d.approved_by_name || who[String(d.approved_by)] || '' } : null,
        approvedAt: d.approved_at || null,
        rejectedAt: d.rejected_at || null,
        comment: d.admin_comments || '',
        attachment: att ? { name: att.original_name || att.filename || '', onWebsite: !!att.path } : null,
        createdAt: d.created_at || null,
        updatedAt: d.updated_at || null,
    };
}

async function present(rows) {
    const who = await names(rows.flatMap((d) => [d.reported_by, d.approved_by]).map(String));
    return rows.map((d) => toApp(d, who));
}

function readFields(b, partial = false) {
    const out = {};
    if (!partial || b.date !== undefined) {
        const date = str(b.date, 10);
        if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw fail(400, 'Enter the date of the wastage');
        if (date > ymdIST(new Date())) throw fail(400, 'The wastage date cannot be in the future');
        out.wastage_date = date;
    }
    if (!partial || b.metal !== undefined) {
        const m = METALS[str(b.metal, 12).toLowerCase()];
        if (!m) throw fail(400, 'Choose gold or silver');
        out.metal_type = m;
    }
    if (!partial || b.amount !== undefined) {
        const a = Number(b.amount);
        if (!Number.isFinite(a) || a <= 0) throw fail(400, 'Enter a wastage weight above zero');
        if (a > MAX_GRAMS) throw fail(400, 'That weight is too large to be right: check it');
        out.wastage_amount = a.toFixed(3);                       // the website keeps it as text with 3 decimals
    }
    if (!partial || b.category !== undefined) {
        const c = CATEGORIES.find((x) => x.toLowerCase() === str(b.category, 30).toLowerCase());
        if (!c) throw fail(400, `Category must be one of: ${CATEGORIES.join(', ')}`);
        out.category = c;
    }
    if (b.reason !== undefined) out.reason = str(b.reason);
    if (b.remarks !== undefined) out.remarks = str(b.remarks);
    if (b.notes !== undefined) out.notes = str(b.notes);
    return out;
}

async function list({ status, metal, category, from, to, q, page = 1, limit = 20 } = {}) {
    const f = {};
    if (['pending', 'approved', 'rejected'].includes(status)) f.status = status;
    if (METALS[String(metal || '').toLowerCase()]) f.metal_type = METALS[String(metal).toLowerCase()];
    if (CATEGORIES.includes(category)) f.category = category;
    if (from || to) { f.wastage_date = {}; if (from) f.wastage_date.$gte = String(from); if (to) f.wastage_date.$lte = String(to); }
    if (str(q, 40)) { const rx = new RegExp(str(q, 40).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'); f.$or = [{ reason: rx }, { remarks: rx }, { notes: rx }, { category: rx }]; }
    const lim = Math.min(Math.max(parseInt(limit, 10) || 20, 1), 200);
    const pg = Math.max(1, parseInt(page, 10) || 1);
    const [rows, total, totals] = await Promise.all([
        col().find(f).sort({ wastage_date: -1, _id: -1 }).skip((pg - 1) * lim).limit(lim).toArray(),
        col().countDocuments(f),
        col().aggregate([{ $match: f }, { $group: { _id: { s: '$status', m: { $toLower: '$metal_type' } }, w: { $sum: { $convert: { input: '$wastage_amount', to: 'double', onError: 0, onNull: 0 } } }, n: { $sum: 1 } } }]).toArray(),
    ]);
    const sums = { approved: {}, pending: {}, rejected: {} };
    for (const t of totals) { if (sums[t._id.s]) sums[t._id.s][t._id.m] = { grams: Math.round(t.w * 1000) / 1000, count: t.n }; }
    return { reports: await present(rows), pagination: { total, page: pg, limit: lim, pages: Math.ceil(total / lim) }, totals: sums, categories: CATEGORIES };
}

async function get(id) {
    const _id = oid(id);
    const d = _id ? await col().findOne({ _id }) : null;
    return d ? (await present([d]))[0] : null;
}

async function create(b, user) {
    const f = readFields(b);
    const now = new Date();
    const uid = String(user._id || user.id);
    const doc = {
        ...f, reason: str(b.reason), remarks: str(b.remarks), notes: str(b.notes),
        reported_by: uid, reported_by_name: user.name || '', approved_by: null, status: 'pending',
        created_at: now, created_ist: istStamp(now), created_by: uid, updated_at: now, updated_ist: istStamp(now), updated_by: uid, source: 'app',
    };
    const r = await col().insertOne(doc);
    return get(r.insertedId);
}

async function update(id, b, user) {
    const _id = oid(id);
    const cur = _id ? await col().findOne({ _id }) : null;
    if (!cur) throw fail(404, 'Wastage report not found');
    if (cur.status !== 'pending') throw fail(409, 'Only a report that is still waiting for approval can be changed');
    if (String(cur.reported_by) !== String(user._id || user.id) && !isBoss(user)) throw fail(403, 'Only the person who reported it can change it');
    const f = readFields(b, true);
    if (!Object.keys(f).length) throw fail(400, 'Nothing to change');
    const now = new Date();
    const r = await col().updateOne({ _id, status: 'pending' }, { $set: { ...f, updated_at: now, updated_ist: istStamp(now), updated_by: String(user._id || user.id) } });
    if (!r.matchedCount) throw fail(409, 'This report was just approved or rejected');
    return get(id);
}

/** approve: pending -> approved (not by the reporter unless admin / owner). */
async function approve(id, comment, user) {
    const _id = oid(id);
    const cur = _id ? await col().findOne({ _id }) : null;
    if (!cur) throw fail(404, 'Wastage report not found');
    if (cur.status !== 'pending') throw fail(409, `This report is already ${cur.status}`);
    const uid = String(user._id || user.id);
    if (String(cur.reported_by) === uid && !isBoss(user)) throw fail(403, 'You cannot approve your own report: someone else must');
    const now = new Date();
    const r = await col().updateOne({ _id, status: 'pending' }, { $set: { status: 'approved', approved_by: uid, approved_by_name: user.name || '', approved_at: now, admin_comments: str(comment), updated_at: now, updated_ist: istStamp(now), updated_by: uid } });
    if (!r.matchedCount) throw fail(409, 'This report was just approved or rejected by someone else');
    return get(id);
}

/** reject: pending -> rejected (a comment is required). admin / owner can also reverse an approved one, which is final for everyone else. */
async function reject(id, comment, user) {
    const _id = oid(id);
    const cur = _id ? await col().findOne({ _id }) : null;
    if (!cur) throw fail(404, 'Wastage report not found');
    if (!str(comment)) throw fail(400, 'Write why it is rejected');
    const reversing = cur.status === 'approved';
    if (cur.status === 'rejected') throw fail(409, 'This report is already rejected');
    if (reversing && !isBoss(user)) throw fail(403, 'An approved report is final. Only the admin or owner can reverse it');
    const uid = String(user._id || user.id);
    const now = new Date();
    const r = await col().updateOne({ _id, status: cur.status }, { $set: { status: 'rejected', rejected_by: uid, rejected_by_name: user.name || '', rejected_at: now, admin_comments: str(comment), ...(reversing ? { reversed_approval: true } : {}), updated_at: now, updated_ist: istStamp(now), updated_by: uid } });
    if (!r.matchedCount) throw fail(409, 'This report was just changed by someone else');
    return get(id);
}

module.exports = { list, get, create, update, approve, reject, CATEGORIES, toApp };
