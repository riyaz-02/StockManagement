'use strict';
/**
 * Branches, their billing counters, and who works where.
 *
 *   GET    /api/branches                          every branch you may see, each with its counters and staff count   (directory.view)
 *   GET    /api/branches/counters/current         the live counters of the branch you work on + the one in force    (any signed-in person)
 *   GET    /api/branches/:id                      one branch with its counters and its staff                        (directory.manageBranches)
 *   POST   /api/branches                          open a branch                                                     (directory.manageBranches)
 *   PATCH  /api/branches/:id                      change it / switch it off                                         (directory.manageBranches)
 *   GET    /api/branches/:id/counters             its counters                                                      (directory.view)
 *   POST   /api/branches/:id/counters             add a counter                                                     (directory.manageBranches)
 *   PATCH  /api/branches/:id/counters/:cid        rename / switch off                                               (directory.manageBranches)
 *   PATCH  /api/branches/:id/staff/:userId        put a person at this branch (and at one of its counters)          (users.manage)
 *
 * "main" is the built-in branch of all earlier data: it always exists, cannot be edited or switched off, but can have counters.
 * Nothing is ever deleted: old records point at branches and counters, so they are switched off instead.
 */
const { Branch, MAIN_BRANCH, resolveBranch } = require('../utils/branches');
const BranchCounter = require('../models/BranchCounter');
const User = require('../models/User');
const Counters = require('../utils/counters');
const audit = require('../services/audit');
const { getConnection } = require('../config/db');

const str = (v) => (v == null ? '' : String(v).trim());
const fail = (res, code, message) => res.status(code).json({ success: false, message });
const esc = (t) => String(t).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const isId = (v) => /^[a-f0-9]{24}$/i.test(str(v));
const flag = (v) => v === true || v === 'true' || v === 1 || v === '1' || v === 'on';
const PREFIX = /^[A-Z0-9]{1,6}$/;

const branchView = (b, counters = [], staffCount = 0) => ({
    id: String(b._id), name: b.name, code: b.code || '', invoicePrefix: b.invoicePrefix || '', city: b.city || '', state: b.state || '',
    phone: b.phone || '', address: b.address || '', gstin: b.gstin || '', isActive: b.isActive !== false, isMain: String(b._id) === 'main',
    staffCount, counterCount: counters.filter((c) => c.isActive).length, counters,
    createdByName: b.createdByName || '', createdAt: b.createdAt || null, updatedByName: b.updatedByName || '', updatedAt: b.updatedAt || null,
});
const counterView = (c) => ({
    id: String(c._id), branchId: c.branchId || 'main', name: c.name, code: c.code || '', note: c.note || '', isActive: c.isActive !== false,
    createdByName: c.createdByName || '', createdAt: c.createdAt || null, updatedByName: c.updatedByName || '', updatedAt: c.updatedAt || null,
});

/** The branches the caller may see: everything, or just their own when they cannot see the whole firm. */
const mayBranch = (req, id) => { const r = req.branchScope && req.branchScope.restrict; return !r || r.includes(String(id || 'main')); };

async function staffCounts() {
    const rows = await User.aggregate([{ $match: { isActive: { $ne: false } } }, { $group: { _id: { $ifNull: ['$branchId', 'main'] }, n: { $sum: 1 } } }]);
    return new Map(rows.map((r) => [String(r._id || 'main'), r.n]));
}

async function countersByBranch(extra = {}) {
    const rows = await BranchCounter.find(extra).sort({ name: 1 }).lean();
    const map = new Map();
    for (const c of rows) { const k = String(c.branchId || 'main'); if (!map.has(k)) map.set(k, []); map.get(k).push(counterView(c)); }
    return map;
}

async function branchOr404(req, res) {
    const id = str(req.params.id);
    if (id === 'main') return { _id: 'main', name: MAIN_BRANCH.name, code: MAIN_BRANCH.code, isActive: true };
    let b = null;
    if (isId(id)) b = await Branch.findById(id).lean();
    if (!b) { fail(res, 404, 'Branch not found'); return null; }
    return b;
}

// ── branches ───────────────────────────────────────────────────────────────────────────────────────

exports.list = async (req, res, next) => {
    try {
        const [rows, counters, staff] = await Promise.all([Branch.find({}).sort({ name: 1 }).lean(), countersByBranch(), staffCounts()]);
        const all = [{ ...MAIN_BRANCH, isActive: true }, ...rows].filter((b) => mayBranch(req, b._id));
        res.json({ success: true, data: { branches: all.map((b) => branchView(b, counters.get(String(b._id)) || [], staff.get(String(b._id)) || 0)) } });
    } catch (e) { next(e); }
};

exports.get = async (req, res, next) => {
    try {
        const b = await branchOr404(req, res);
        if (!b) return;
        const id = String(b._id);
        const [counters, staff] = await Promise.all([
            BranchCounter.find({ branchId: id }).sort({ name: 1 }).lean(),
            User.find(id === 'main' ? { $or: [{ branchId: 'main' }, { branchId: { $exists: false } }, { branchId: null }, { branchId: '' }] } : { branchId: id }).select('full_name mobile role is_active counterId counterName').sort({ name: 1 }).lean(),
        ]);
        const people = staff.map((u) => ({ id: String(u._id), name: u.full_name || '', mobile: u.mobile || '', role: u.role || '', isActive: u.is_active !== false, counterId: u.counterId || '', counterName: u.counterName || '' }));
        res.json({ success: true, data: { ...branchView(b, counters.map(counterView), people.filter((p) => p.isActive).length), staff: people } });
    } catch (e) { next(e); }
};

function branchFields(b) {
    const gstin = str(b.gstin).toUpperCase();
    return { code: str(b.code), invoicePrefix: str(b.invoicePrefix).toUpperCase(), city: str(b.city), state: str(b.state), phone: str(b.phone), address: str(b.address), gstin };
}
function checkFields(f) {
    if (f.gstin && !/^\d{2}[A-Z0-9]{13}$/.test(f.gstin)) return 'GSTIN must be 15 characters, like 19ABCDE1234F1Z5';
    if (f.invoicePrefix && !PREFIX.test(f.invoicePrefix)) return 'The bill-number letters must be 1 to 6 letters or digits (for example BR2)';
    return '';
}
async function prefixTaken(prefix, exceptId) {
    if (!prefix) return false;
    return !!(await Branch.findOne({ invoicePrefix: prefix, ...(exceptId ? { _id: { $ne: exceptId } } : {}) }).lean());
}

exports.create = async (req, res, next) => {
    try {
        const b = req.body || {};
        const name = str(b.name);
        if (!name) return fail(res, 400, 'Branch name is required');
        if (name.toLowerCase() === MAIN_BRANCH.name.toLowerCase() || (await Branch.findOne({ name: new RegExp(`^${esc(name)}$`, 'i') }).lean())) return fail(res, 409, 'A branch with this name already exists');
        const f = branchFields(b);
        const bad = checkFields(f);
        if (bad) return fail(res, 400, bad);
        if (await prefixTaken(f.invoicePrefix)) return fail(res, 409, 'Another branch already uses those bill-number letters');
        const doc = await Branch.create({ name, ...f, isActive: true });
        await audit.record(req, 'branch', doc._id, name, 'created', [{ field: 'prefix', to: f.invoicePrefix }, { field: 'gstin', to: f.gstin }]);
        res.status(201).json({ success: true, data: branchView(doc.toObject(), [], 0) });
    } catch (e) { next(e); }
};

exports.update = async (req, res, next) => {
    try {
        const id = str(req.params.id);
        if (id === 'main') return fail(res, 400, 'The main branch is built in and cannot be changed');
        const cur = isId(id) ? await Branch.findById(id).lean() : null;
        if (!cur) return fail(res, 404, 'Branch not found');
        const b = req.body || {};
        const set = {};
        if (b.name !== undefined) {
            const name = str(b.name);
            if (!name) return fail(res, 400, 'Branch name is required');
            if (name.toLowerCase() === MAIN_BRANCH.name.toLowerCase() || (await Branch.findOne({ name: new RegExp(`^${esc(name)}$`, 'i'), _id: { $ne: id } }).lean())) return fail(res, 409, 'A branch with this name already exists');
            set.name = name;
        }
        const f = branchFields({ ...cur, ...b });
        for (const k of ['code', 'city', 'state', 'phone', 'address', 'gstin']) if (b[k] !== undefined) set[k] = f[k];
        if (b.invoicePrefix !== undefined && f.invoicePrefix !== (cur.invoicePrefix || '')) {
            const inv = await getConnection().db.collection('invoices').countDocuments({ branch_id: id });
            if (inv > 0) return fail(res, 409, `Bills have already been made at this branch with the letters "${cur.invoicePrefix || ''}": they cannot be changed now`);
            if (await prefixTaken(f.invoicePrefix, id)) return fail(res, 409, 'Another branch already uses those bill-number letters');
            set.invoicePrefix = f.invoicePrefix;
        }
        const bad = checkFields({ ...f, ...(set.gstin !== undefined ? { gstin: set.gstin } : { gstin: str(cur.gstin) }) });
        if (bad) return fail(res, 400, bad);
        if (b.isActive !== undefined) {
            const on = flag(b.isActive);
            if (!on) {
                const people = await User.countDocuments({ branchId: id, isActive: { $ne: false } });
                if (people > 0) return fail(res, 409, `${people} active staff still work at this branch: move them to another branch first`);
            }
            set.isActive = on;
        }
        if (!Object.keys(set).length) return res.json({ success: true, data: branchView(cur, [], 0) });
        const doc = await Branch.findByIdAndUpdate(id, { $set: { ...set, updatedByName: (req.user && req.user.name) || '', updatedBy: String(req.user._id) } }, { new: true }).lean();
        await audit.record(req, 'branch', id, doc.name, 'updated', Object.keys(set).map((k) => ({ field: k, from: cur[k], to: set[k] })));
        res.json({ success: true, data: branchView(doc, [], 0) });
    } catch (e) { next(e); }
};

// ── counters ───────────────────────────────────────────────────────────────────────────────────────

/** The live counters of the branch the caller works on, and which one is in force (for the billing screens). */
exports.currentCounters = async (req, res, next) => {
    try {
        const branchId = (req.branchScope && req.branchScope.branchId) || req.user.branchId || 'main';
        const rows = await BranchCounter.find({ branchId, isActive: { $ne: false } }).sort({ name: 1 }).lean();
        const sel = req.branchScope && req.branchScope.counter;
        res.json({ success: true, data: { branchId, counters: rows.map(counterView), selectedId: sel ? sel.counterId : '', assignedId: req.user.counterId || '' } });
    } catch (e) { next(e); }
};

exports.listCounters = async (req, res, next) => {
    try {
        const id = str(req.params.id);
        if (!mayBranch(req, id)) return fail(res, 403, 'That branch is not yours to see');
        const b = await branchOr404(req, res);
        if (!b) return;
        const rows = await BranchCounter.find({ branchId: String(b._id) }).sort({ name: 1 }).lean();
        res.json({ success: true, data: { counters: rows.map(counterView) } });
    } catch (e) { next(e); }
};

exports.createCounter = async (req, res, next) => {
    try {
        const b = await branchOr404(req, res);
        if (!b) return;
        if (b.isActive === false) return fail(res, 409, 'This branch is switched off');
        const branchId = String(b._id);
        const name = str((req.body || {}).name);
        if (!name) return fail(res, 400, 'Counter name is required');
        if (name.length > 40) return fail(res, 400, 'The counter name is too long (40 letters at most)');
        if (await BranchCounter.findOne({ branchId, name: new RegExp(`^${esc(name)}$`, 'i') }).lean()) return fail(res, 409, 'This branch already has a counter with this name');
        const code = str((req.body || {}).code).toUpperCase().slice(0, 10);
        const doc = await BranchCounter.create({ branchId, name, code, note: str((req.body || {}).note).slice(0, 120), isActive: true });
        Counters.bust();
        await audit.record(req, 'counter', doc._id, `${name} (${b.name})`, 'created', [{ field: 'branch', to: b.name }]);
        res.status(201).json({ success: true, data: counterView(doc.toObject()) });
    } catch (e) { next(e); }
};

exports.updateCounter = async (req, res, next) => {
    try {
        const b = await branchOr404(req, res);
        if (!b) return;
        const branchId = String(b._id);
        const cid = str(req.params.cid);
        const cur = isId(cid) ? await BranchCounter.findOne({ _id: cid, branchId }).lean() : null;
        if (!cur) return fail(res, 404, 'Counter not found');
        const body = req.body || {};
        const set = {};
        if (body.name !== undefined) {
            const name = str(body.name);
            if (!name || name.length > 40) return fail(res, 400, 'Counter name is required (40 letters at most)');
            if (await BranchCounter.findOne({ branchId, _id: { $ne: cid }, name: new RegExp(`^${esc(name)}$`, 'i') }).lean()) return fail(res, 409, 'This branch already has a counter with this name');
            set.name = name;
        }
        if (body.code !== undefined) set.code = str(body.code).toUpperCase().slice(0, 10);
        if (body.note !== undefined) set.note = str(body.note).slice(0, 120);
        if (body.isActive !== undefined) set.isActive = flag(body.isActive);
        if (!Object.keys(set).length) return res.json({ success: true, data: counterView(cur) });
        const doc = await BranchCounter.findByIdAndUpdate(cid, { $set: set }, { new: true }).lean();
        // the name is kept on people for quick display: keep it in step
        if (set.name) await User.updateMany({ counterId: cid }, { $set: { counterName: set.name } });
        Counters.bust(cid);
        await audit.record(req, 'counter', cid, `${doc.name} (${b.name})`, 'updated', Object.keys(set).map((k) => ({ field: k, from: cur[k], to: set[k] })));
        res.json({ success: true, data: counterView(doc) });
    } catch (e) { next(e); }
};

// ── who works where ────────────────────────────────────────────────────────────────────────────────

exports.assignStaff = async (req, res, next) => {
    try {
        const b = await branchOr404(req, res);
        if (!b) return;
        const branch = await resolveBranch(String(b._id));
        const uid = str(req.params.userId);
        const user = isId(uid) ? await User.findById(uid) : null;
        if (!user) return fail(res, 404, 'Person not found');
        const body = req.body || {};
        const counter = await Counters.resolveFor(branch.branchId, body.counterId);
        const before = { branch: user.branchName, counter: user.counterName || '' };
        user.branchId = branch.branchId;
        user.branchName = branch.branchName;
        user.counterId = counter.counterId;
        user.counterName = counter.counterName;
        await user.save();
        await audit.record(req, 'user', user._id, `${user.name} (${user.mobile || ''})`, 'updated', [
            { field: 'branch', from: before.branch, to: user.branchName }, { field: 'counter', from: before.counter, to: user.counterName || '' },
        ]);
        res.json({ success: true, data: { id: String(user._id), name: user.name, branchId: user.branchId, branchName: user.branchName, counterId: user.counterId || '', counterName: user.counterName || '' } });
    } catch (e) { if (e.statusCode) return fail(res, e.statusCode, e.message); next(e); }
};
